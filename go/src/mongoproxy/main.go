package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"sync/atomic"
	"time"

	"github.com/Sirupsen/logrus"
)

var port int64 = 27017
var mongod_path string = "/home/vagrant/mongodb/bin/mongod"
var mongo_shel_path string = "/home/vagrant/mongodb/bin/mongo"
var db_base_path = "/home/vagrant/dbs"
var ip_address = "127.0.0.1"
var run_mongod = "./mongodb/bin/mongod --dbpath %s --fork --replSet %s --storageEngine=wiredTiger --logpath %s/mongod.log --port %d"

/*
rs.initiate()
rs.add("localhost.localdomain:27018")

r = rs.status(); for(var i = 0; i < r.members.length; i++) { print(r.members[i].name); print(r.members[i].stateStr);}
*/

type replSet struct {
	RS         string
	P          string
	Initialied bool
	Port       int64
}

var all_replSet map[string]*replSet = make(map[string]*replSet)

func getReplicaSet(rs string) *replSet {
	if _, ok := all_replSet[rs]; !ok {
		// create a new set
		all_replSet[rs] = &replSet{Initialied: false}
	}
	return all_replSet[rs]
}

func (r *replSet) Add(port int64) {
	if !r.Initialied {
		// initial set
		r.Port = port
		log.Println("Initiate RS set ", r.RS)
		runMongoCmd("rs.initiate();", r.Port)
		runMongoCmd("rs.addArb(\"localhost:localdomain:27017\")", r.Port)
		r.Initialied = true
	} else {
		log.Println("replSet ", r.RS, " already initiated, Add myself with port ", port)
		runMongoCmd(fmt.Sprintf("rs.add(\"localhost.localdomain:%d\");rs.status();", port), r.Port)
	}
}

func runMongoCmd(s string, port int64) string {
	cmd := exec.Command(mongo_shel_path,
		"--port", fmt.Sprint(port),
		"--eval", s,
	)

	out, err := cmd.CombinedOutput()
	// log.Printf("%s\n", out)
	if err != nil {
		log.Println("Failed to run mongo command ", s)
		log.Println(err)
	}

	return string(out)
}

type Mongo struct {
	ID   string
	RS   string
	Name string
	PID  string

	Port    int64
	DB_path string
}

var arbitor *Mongo = &Mongo{
	RS:      "rs1",
	Port:    27017,
	DB_path: "/home/vagrant/dbs/arb",
}

func (m *Mongo) RunOnly() error {
	// clean up folder
	err := os.RemoveAll(m.DB_path)
	if err != nil {
		log.Println("failed to remove db folder ", m.DB_path, err)
	}
	os.Mkdir(m.DB_path, os.ModePerm)

	cmd := exec.Command(mongod_path,
		"--fork",
		"--storageEngine", "wiredTiger",
		"--logpath", m.DB_path+"/mongod.log",
		"--dbpath", m.DB_path,
		"--replSet", m.RS,
		"--port", fmt.Sprintf("%d", m.Port),
	)

	log.Println("prepare to run mongod")
	err = cmd.Run()
	log.Println("done to run mongod")

	if err == nil {
		log.Println("Mongod ", m.ID, " running...")
		m.PID = getMongodPID(m.Port)
	} else {
		log.Println(cmd)
		log.Println(err)
	}

	return err
}

func getMongodPID(p int64) string {

	out, err := exec.Command(mongo_shel_path,
		"--port", fmt.Sprintf("%d", p),
		"--eval", "printjson(db.serverStatus().pid * 1);",
	).CombinedOutput()

	if err != nil {
		log.Println("failed to find PID")
		return ""
	}

	s := strings.Split(string(out), "\n")
	log.Println(s[len(s)-2])
	return s[len(s)-2]
}

func (m *Mongo) Run() error {
	// clean up folder
	err := os.Remove(m.DB_path)
	if err != nil {
		log.Println("error remove folder: ", err)
	}
	err = os.Mkdir(m.DB_path, os.ModePerm)
	if err != nil {
		log.Println("error creating folder: ", err)
	}

	cmd := exec.Command(mongod_path,
		"--fork",
		"--storageEngine", "wiredTiger",
		"--logpath", m.DB_path+"/mongod.log",
		"--dbpath", m.DB_path,
		"--replSet", m.RS,
		"--port", fmt.Sprintf("%d", m.Port),
	)

	log.Println("prepare to run mongod")
	err = cmd.Run()
	log.Println("done to run mongod")

	if err == nil {
		log.Println("Mongod ", m.ID, " running...")
		m.PID = getMongodPID(m.Port)
	} else {
		log.Println(cmd)
		log.Println(err)
	}

	// time.Sleep(15 * time.Second)
	rs := getReplicaSet(m.RS)
	rs.Add(m.Port)

	return err
}

var all_instance map[string]*Mongo = make(map[string]*Mongo)

func main() {

	// goproxy is executed as a short lived process to send a request to the
	// goproxy daemon process
	if len(os.Args) > 1 {
		// If there's an argument
		// It will be considered as a path for an HTTP GET request
		// That's a way to communicate with goproxy daemon
		if len(os.Args) == 2 {
			reqPath := "http://127.0.0.1:8000/" + os.Args[1]
			resp, err := http.Get(reqPath)
			if err != nil {
				logrus.Println("Error on request:", reqPath, "ERROR:", err.Error())
			} else {
				logrus.Println("Request sent", reqPath, "StatusCode:", resp.StatusCode)
			}
		}
		return
	}

	arbitor.RunOnly()
	// start a http server and listen on local port 8000
	go func() {
		http.HandleFunc("/containers", listContainers)
		http.HandleFunc("/newmongo", newMongo)
		http.HandleFunc("/killmongo", killMongo)
		http.HandleFunc("/exec", execCmd)
		http.ListenAndServe(":8000", nil)
	}()

	// testCreateAndThenDelete()
	go updateMongoClusterStatus()

	// wait for interruption
	<-make(chan int)
}

// execCmd handles http requests received for the path "/exec"
func execCmd(w http.ResponseWriter, r *http.Request) {

	io.WriteString(w, "OK")

	go func() {
		cmd := r.URL.Query().Get("cmd")
		cmd, _ = url.QueryUnescape(cmd)
		arr := strings.Split(cmd, " ")
		if len(arr) > 0 {

			if arr[0] == "docker" {
				arr[0] = "docker-" + "something here FIXME"
			}

			cmd := exec.Command(arr[0], arr[1:]...)
			// Stdout buffer
			// cmdOutput := &bytes.Buffer{}
			// Attach buffer to command
			// cmd.Stdout = cmdOutput
			// Execute command
			// printCommand(cmd)
			err := cmd.Run() // will wait for command to return
			if err != nil {
				logrus.Println("Error:", err.Error())
			}
		}
	}()
}

// listContainers handles and reply to http requests having the path "/containers"
func listContainers(w http.ResponseWriter, r *http.Request) {

	// answer right away to avoid dead locks in LUA
	io.WriteString(w, "OK")

	go func() {

		data := url.Values{
			"action":    {"containerInfos"},
			"id":        {"test_id"},
			"name":      {"name"},
			"imageRepo": {"imageRepo"},
			"imageTag":  {"imageTag"},
		}

		CuberiteServerRequest(data)

	}()
}

func createInstance(id string) {
	log.Println("create event")
	data := url.Values{
		"action":    {"createContainer"},
		"id":        {id},
		"name":      {"containerName"},
		"imageRepo": {"repo"},
		"imageTag":  {"tag"}}

	CuberiteServerRequest(data)
}

func testCreateAndThenDelete() {

	createInstance("1")
	createInstance("2")

	return

	log.Println("die event")

	// destroy
	destroyINstance("1")
	destroyINstance("2")
}

func destroyINstance(id string) {

	data := url.Values{
		"action":    {"destroyContainer"},
		"id":        {id},
		"name":      {"containerName"},
		"imageRepo": {"repo"},
		"imageTag":  {"tag"}}

	CuberiteServerRequest(data)
}

// CuberiteServerRequest send a POST request that will be handled
// by our Cuberite Docker plugin.
func CuberiteServerRequest(data url.Values) {

	// log.Println("Sending request to minecraft")

	client := &http.Client{}
	req, _ := http.NewRequest("POST", "http://127.0.0.1:8080/webadmin/Docker/Docker", strings.NewReader(data.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth("admin", "admin")
	client.Do(req)
}

func getURLParameter(r *http.Request, p string) string {
	s := r.URL.Query().Get(p)
	s, _ = url.QueryUnescape(s)

	return s
}

func killMongo(w http.ResponseWriter, r *http.Request) {
	// answer right away to avoid dead locks in LUA
	io.WriteString(w, "OK")

	go func() {
		// run mongod
		id := getURLParameter(r, "id")

		if val, ok := all_instance[id]; ok {
			log.Println("Kill mongo ", id, val.PID)
			exec.Command("kill", val.PID).Run()
			runMongoCmd("db.getSiblingDB('admin').shutdownServer()", val.Port)
			delete(all_instance, id)
		} else {
			log.Println("Error, try to delete non-exist mongo -> ", id)
		}
	}()
}

//
func newMongo(w http.ResponseWriter, r *http.Request) {
	// answer right away to avoid dead locks in LUA
	io.WriteString(w, "OK")

	go func() {
		// run mongod
		id := getURLParameter(r, "id")
		rs := getURLParameter(r, "rs")
		name := getURLParameter(r, "name")

		log.Println("Create mongo ", id)

		if _, ok := all_instance[id]; ok {
			// try to create instance with the same id, do nothing here
			log.Println("error, try to create the same instance again", id)
			return
		}

		m := Mongo{
			RS:      rs,
			ID:      id,
			DB_path: "/home/vagrant/dbs/dbs-" + rs + "-" + id,
			Port:    atomic.AddInt64(&port, 1),
			Name:    name,
		}

		err := m.Run()
		if err != nil {
			return
		}
		log.Println("Mongod ", id, " is running")
		all_instance[id] = &m

		// send details back to minecraft
		data := url.Values{
			"action":  {"createMongod"},
			"id":      {id},
			"name":    {name},
			"rs":      {rs},
			"running": {"true"},
		}

		CuberiteServerRequest(data)
	}()
}

func updateMongoClusterStatus() {
	var t = 0
	c := time.Tick(2 * time.Second)
	for now := range c {
		// fmt.Println(now)
		var cmd = "a = rs.status(); r = []; for(i = 0; i < a.members.length; i++) {t = a.members[i]; print('>> ' +t.name + ' ' + t.stateStr); }"
		_ = now

		if _, ok := all_replSet["rs1"]; ok {

			r := runMongoCmd(cmd, all_replSet["rs1"].Port)
			log.Printf("%s\n", r)
			s := strings.Split(r, "\n")

			for i := 0; i < len(s); i++ {
				log.Println(s[i])

				go func(x string) {
					var _isPrimary = "false"
					tt := strings.Fields(x)

					if len(tt) > 0 && tt[0] == ">>" {
						state := tt[2]
						port := strings.Split(tt[1], ":")[1]

						// looking for ID
						var id = "error"
						var vv *Mongo
						for _, val := range all_instance {
							if port == fmt.Sprintf("%d", val.Port) {
								id = val.ID
								vv = val
							}
						}

						if state == "PRIMARY" {
							_isPrimary = "true"
						} else {
							_isPrimary = "false"
						}

						if vv != nil {
							r = runMongoCmd("db.serverStatus().connections.current", vv.Port)
							s = strings.Split(r, "\n")
							data := url.Values{
								"action":     {"updateMongoStatus"},
								"id":         {id},
								"name":       {vv.Name},
								"rs":         {vv.RS},
								"connection": {s[len(s)-2]},
								"running":    {"true"},
								"now":        {fmt.Sprint(t)},
								"isPrimary":  {_isPrimary},
							}
							CuberiteServerRequest(data)
						} else {
							log.Println("error, vv is nil")
						}
					}
				}(s[i])
			}

			t = t + 1
		}
	}
}

func init() {
}

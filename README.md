# mongocraft

Build a MongoDB cluster from minecraft, inspired by Dockercraft. This is a Hackathon project

# How to 

You need install Cuberite minecraft server (http://cuberite.org/), then

<pre>
cd ./world
~/bin/Cuberite
</pre>

run proxy server to control mongodb cluster

<pre>
go get github.com/rzh/mongocraft/go/src/mongoproxy
mongoproxy
</pre>

This assume your mongodb binary installed under ```~/mongodb/bin```

The original README file is here https://github.com/rzh/mongocraft/blob/master/dockercraft-README.md



function MongoCommand(Split, Player)

	if table.getn(Split) > 0
	then
		LOG("Split[1]: " .. Split[1])

		if Split[1] == "/mongo"
		then
			if table.getn(Split) > 2
			then
                for i=1, table.getn(Containers)
                do
                    -- if container found with same ID, we update it
                    if Containers[i] ~= EmptyContainerSpace and Containers[i].id .. "" == Split[2]
                    then
                        LOG("Found mongo instance " .. Split[2])
                        -- setRS
                        if Split[3] == "setRS"
                        then
                            Containers[i]:setRS(Split[4])
                        end

                        -- setPrimary
                        if Split[3] == "setPrimary"
                        then
                            if Split[4] == "true" then
                                Containers[i]:updateMongoState(true)
                                LOG("setPrimary for instance " .. Split[2] .. " to true")
                            else
                                Containers[i]:updateMongoState(false)
                            end
                        end

                        -- display to reflect changes
                        --- Containers[i]:display(true)
                    end
				end
			end
		end
	end

	return true
end


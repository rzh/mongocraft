
--
--
-- NewContainer returns a Container object,
-- representation of a Docker container in
-- the Minecraft world
function NewPanel()
	c = {
			displayed = true, 
			x = 0, 
			z = 0, 
			name="",
			id="",
			init=Panel.init,
			-- setInfos=Panel.setInfos,
			display=Panel.display,
			-- addGround=Panel.addGround
		}
	return c
end

Panel = {displayed = true, x = 0, z = 0, name="Panel", id=""}

-- Container:init sets Container's position
function Panel:init(x,z)
	self.x = x
	self.z = z
	self.displayed = true	
end


-- Panel:display displays all Container's blocks
function Panel:display()

	metaPrimaryColor = E_META_WOOL_LIGHTBLUE
	metaSecondaryColor = E_META_WOOL_BLUE

	self.displayed = true
	
	for pz=self.z, self.z+2
	do
	    LOG("Setup control panel wall")
        setBlock(UpdateQueue,self.x,GROUND_LEVEL + 3,pz - 5,E_BLOCK_WOOL,metaPrimaryColor)
        setBlock(UpdateQueue,self.x,GROUND_LEVEL + 2,pz - 5,E_BLOCK_WOOL,metaPrimaryColor)
        setBlock(UpdateQueue,self.x,GROUND_LEVEL + 1,pz - 5,E_BLOCK_WOOL,metaPrimaryColor)

        setBlock(UpdateQueue,self.x+1,GROUND_LEVEL + 2,pz - 5,E_BLOCK_WOOL,metaPrimaryColor)
        setBlock(UpdateQueue,self.x+1,GROUND_LEVEL + 1,pz - 5,E_BLOCK_WOOL,metaPrimaryColor)

        setBlock(UpdateQueue,self.x+2,GROUND_LEVEL + 1,pz - 5,E_BLOCK_WOOL,metaPrimaryColor)
	end

	-- torch
	-- setBlock(UpdateQueue,self.x+1,GROUND_LEVEL+3,self.z,E_BLOCK_TORCH,E_META_TORCH_ZP)

	-- new instance button
	setBlock(UpdateQueue,self.x+1,GROUND_LEVEL + 3,self.z+1-5,E_BLOCK_WALLSIGN,E_META_CHEST_FACING_XP)
	updateSign(UpdateQueue,self.x+1,GROUND_LEVEL + 3,self.z+1-5,"","CREATE","  |","",2)

	setBlock(UpdateQueue,self.x,GROUND_LEVEL+4,self.z+1-5,E_BLOCK_STONE_BUTTON,E_BLOCK_BUTTON_YP)

end

function setupPanel()
    p = NewPanel()
    p:init(7, 3)
    p:display()
end


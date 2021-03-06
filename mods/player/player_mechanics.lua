local minetest,math,vector = minetest,math,vector

local movement_class        = {} -- controls all data of the movement
local player_movement_data  = {} -- used to calculate player movement
local player_state_channels = {} -- holds every player's channel
movement_pointer            = {} -- allows other mods to index local data
movement_class.get_group    = minetest.get_item_group
movement_class.input_data   = nil
-- creates volitile data for the game to use
movement_class.create_movement_variables = function(player)
	local name = player:get_player_name()
	if not player_movement_data[name] then
		player_movement_data[name] = {
			state        = 0    ,
			old_state    = 0    ,
			was_in_water = false,
			swimming     = false,
		}
	end
end

-- sets data for the game to use
movement_class.set_data = function(player,data)
	local name = player:get_player_name()
	if player_movement_data[name] then
		for index,i_data in pairs(data) do
			if player_movement_data[name][index] ~= nil then
				player_movement_data[name][index] = i_data
			end
		end
	else
		movement_class.create_movement_variables(player)
	end
end

-- retrieves data for the game to use
movement_class.get_data = function(player)
	local name = player:get_player_name()
	if player_movement_data[name] then
		return({
			state        = player_movement_data[name].state       ,
			old_state    = player_movement_data[name].old_state   ,
			was_in_water = player_movement_data[name].was_in_water,
			swimming     = player_movement_data[name].swimming    ,
		})
	end
end

-- removes movement data
movement_class.terminate = function(player)
	local name = player:get_player_name()
	if player_movement_data[name] then
		player_movement_data[name] = nil
	end
end

-- creates specific channels for players
minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	player_state_channels[name] = minetest.mod_channel_join(name..":player_movement_state")
	player:set_physics_override({
			jump   = 1.25,
			gravity= 1.25
	})

	movement_class.create_movement_variables(player)
end)

-- resets the player's state on death
minetest.register_on_respawnplayer(function(player)
	movement_class.set_data(player,{
		state        = 0    ,
		was_in_water = false,
	})
	movement_class.send_running_cancellation(player,false)
end)


-- delete data on player leaving
minetest.register_on_leaveplayer(function(player)
	movement_class.terminate(player)
end)

-- tells the client to stop sending running/bunnyhop data
movement_class.send_running_cancellation = function(player,sneaking)
	local name = player:get_player_name()
	player_state_channels[name]:send_all(
		minetest.serialize({
			stop_running=true,
			state=sneaking
		}
	))
end

-- intercept incoming data messages
minetest.register_on_modchannel_message(function(channel_name, sender, message)
	local channel_decyphered = channel_name:gsub(sender,"")
	if sender ~= "" and channel_decyphered == ":player_movement_state" then
		local new_state = tonumber(message)
		if type(new_state) == "number" then
			local player = minetest.get_player_by_name(sender)
			movement_class.set_data(player,{
				state = new_state
			})
		end
	end
end)

-- allows other mods to set data for the game to use
movement_pointer.set_data = function(player,data)
	local name = player:get_player_name()
	if player_movement_data[name] then
		for index,i_data in pairs(data) do
			if player_movement_data[name][index] ~= nil then
				player_movement_data[name][index] = i_data
			end
		end
	else
		movement_class.create_movement_variables(player)
	end
end

-- allows other mods to retrieve data for the game to use
movement_pointer.get_data = function(player,requested_data)
	local name = player:get_player_name()
	if player_movement_data[name] then
		local data_list = {}
		local count     = 0
		for index,i_data in pairs(requested_data) do
			if player_movement_data[name][i_data] ~= nil then
				data_list[i_data] = player_movement_data[name][i_data]
				count = count + 1
			end
		end
		if count > 0 then
			return(data_list)
		else
			return(nil)
		end
	end
	return(nil)
end


-- loops through player states/eating mechanics
minetest.register_globalstep(function(dtime)
	for _,player in ipairs(minetest.get_connected_players()) do
		local hunger = hunger_pointer.get_data(player,{"hunger"})
		if hunger then
			hunger   = hunger.hunger
		end
		local data   = movement_class.get_data(player)
		
		-- water movement data
		local env_data = environment_pointer.get_data(player,{"legs","head"})
		local in_water = {at_all=false,head=false,legs=false}		
		if env_data then
			in_water.legs = movement_class.get_group(env_data.legs,"water") > 0
			in_water.head = movement_class.get_group(env_data.head,"water") > 0
			if in_water.legs or in_water.head then
				in_water.at_all = true
				movement_class.set_data(player,{swimming=true})
			else
				movement_class.set_data(player,{swimming=false})
			end
		end
		
		if (in_water.at_all ~= data.was_in_water) or (data.state ~= data.old_state) or ((data.state == 1 or data.state == 2) and hunger and hunger <= 6) then
			if not in_water.at_all and data.was_in_water then
				player:set_physics_override({
					sneak   = true,
				})
				player_pointer.force_update(player)
				player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
				player_pointer.set_data(player,{
					collisionbox = {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
				})
			elseif in_water.at_all and not data.was_in_water then
				player:set_physics_override({
					sneak   = false,
				})

				player_pointer.force_update(player)
				player:set_eye_offset({x=0,y=-6,z=0},{x=0,y=-6,z=5.9})
				player_pointer.set_data(player,{
					collisionbox = {-0.3, 0.5, -0.3, 0.3, 1.2, 0.3},
				})
			end

			-- running/swimming fov modifier
			if hunger and hunger > 6 and (data.state == 1 or data.state == 2) then
				player:set_fov(1.25, true, 0.15)
				if data.state == 2 then
					player:set_physics_override({speed=1.75})
				elseif data.state == 1 then
					player:set_physics_override({speed=1.5})
				end
			elseif (not in_water.at_all and data.state ~= 1 and data.state ~= 2 and (data.old_state == 1 or data.old_state == 2)) or 
			(in_water.at_all and data.state ~= 1 and data.state ~= 2 and data.state ~= 3 and (data.old_state == 1 or data.old_state == 2 or data.old_state == 3))then

				player:set_fov(1, true,0.15)
				player:set_physics_override({speed=1})

				movement_class.send_running_cancellation(player,data.state==3) --preserve network data
				
			elseif (data.state == 1 or data.state == 2) and (hunger and hunger <= 6) then
				player:set_fov(1, true,0.15)
				player:set_physics_override({speed=1})				
				movement_class.send_running_cancellation(player,false) --preserve network data
			end

			--sneaking
			if data.state == 3 and in_water.at_all then
				movement_class.send_running_cancellation(player,false)
			elseif not in_water.at_all and data.state == 3 and data.old_state ~= 3 then
				player:set_eye_offset({x=0,y=-1,z=0},{x=0,y=-1,z=0})
			elseif not in_water.at_all and data.old_state == 3 and data.state ~= 3 then
				player:set_eye_offset({x=0,y=0,z=0},{x=0,y=0,z=0})
			end

			movement_class.set_data(player,{
				old_state    = data.state,
				was_in_water = in_water.at_all
			})
		
		-- water movement
		elseif in_water.at_all then
			if not data.was_in_water then
				player:set_physics_override({
					sneak   = false ,
				})
				player:set_velocity(vector.new(0,0,0))
			end

			movement_class.set_data(player,{
				old_state    = data.state,
				was_in_water = in_water.at_all
			})
		end
		
		--eating
		if player:get_player_control().RMB then

			local meta = player:get_meta()
			if meta:get_int("hunger") == 20 then
				return 
			end
			local item = player:get_wielded_item():get_name()
			local satiation = minetest.get_item_group(item, "satiation")
			local hunger = minetest.get_item_group(item, "hunger")
			
			if hunger > 0 and satiation > 0  then				
				local eating = meta:get_float("eating")
				local eating_timer = meta:get_float("eating_timer")
				
				eating = eating + dtime
				eating_timer = eating_timer + dtime
				
				local pos = player:get_pos()

				if sneaking then
					pos.y = pos.y + 1.425
				else
					pos.y = pos.y + 1.625
				end

				local dir = vector.multiply(player:get_look_dir(),0.3)
				local newpos = vector.add(pos,dir)

				local vel = player:get_player_velocity()

				local ps = minetest.add_particlespawner({
					amount = 6,
					time = 0.00001,
					minpos = {x=newpos.x-0.1, y=newpos.y-0.1, z=newpos.z-0.1},
					maxpos = {x=newpos.x+0.1, y=newpos.y-0.3, z=newpos.z+0.1},
					minvel = vector.new(vel.x-0.5,0.2,vel.z-0.5),
					maxvel = vector.new(vel.x+0.5,0.6,vel.z+0.5),
					minacc = {x=0, y=-9.81, z=1},
					maxacc = {x=0, y=-9.81, z=1},
					minexptime = 0.5,
					maxexptime = 1.5,
					minsize = 0,
					maxsize = 0,
					--attached = player,
					collisiondetection = true,
					collision_removal = true,
					vertical = false,
					node = {name= item.."node"},
					--texture = "eat_particles_1.png"
				})


				if eating_timer + dtime > 0.25 then
					minetest.sound_play("eat", {
						to_player = player:get_player_name(),
						gain = 1.0,  -- default
						pitch = math.random(60,100)/100,
					})
					eating_timer = 0
				end
				
				if eating + dtime >= 1 then
					local stack = player:get_wielded_item()
					stack:take_item(1)
					minetest.eat_food(player,item)
					eating = 0
					minetest.sound_play("eat_finish", {
						to_player = player:get_player_name(),
						gain = 0.2,  -- default
						pitch = math.random(60,85)/100,
					})
				end
				
				meta:set_float("eating_timer", eating_timer)
				meta:set_float("eating", eating)
			else
				local meta = player:get_meta()
				meta:set_float("eating", 0)
				meta:set_float("eating_timer", 0)
				
			end
		else
			local meta = player:get_meta()
			meta:set_float("eating", 0)
			meta:set_float("eating_timer", 0)
		end
	end
end)

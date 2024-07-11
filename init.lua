
ambience = {}

-- settings
local SOUNDVOLUME = 1.0
local MUSICVOLUME = 0.6
local MUSICINTERVAL = 60 * 20
local play_music = minetest.settings:get_bool("ambience_music") ~= false
local radius = 6
local playing = {}
local sound_sets = {} -- all the sounds and their settings
local sound_set_order = {} -- needed because pairs loops randomly through tables
local set_nodes = {} -- all the nodes needed for sets

-- translation
local S = minetest.get_translator("ambience")

-- add set to list
ambience.add_set = function(set_name, def)

	if not set_name or not def then
		return
	end

	sound_sets[set_name] = {
		frequency = def.frequency or 50,
		sounds = def.sounds,
		sound_check = def.sound_check,
		nodes = def.nodes
	}

	-- add set name to the sound_set_order table
	local can_add = true

	for i = 1, #sound_set_order do

		if sound_set_order[i] == set_name then
			can_add = false
		end
	end

	if can_add then
		table.insert(sound_set_order, set_name)
	end

	-- add any missing nodes to the set_nodes table
	if def.nodes then

		for i = 1, #def.nodes do

			can_add = def.nodes[i]

			for j = 1, #set_nodes do

				if def.nodes[i] == set_nodes[j] then
					can_add = false
				end
			end

			if can_add then
				table.insert(set_nodes, can_add)
			end
		end
	end
end


-- return set from list using name
ambience.get_set = function(set_name)
	return sound_sets[set_name]
end


-- remove set from list
ambience.del_set = function(set_name)

	sound_sets[set_name] = nil

	local can_del = false

	for i = 1, #sound_set_order do

		if sound_set_order[i] == set_name then
			can_del = i
		end
	end

	if can_del then
		table.remove(sound_set_order, can_del)
	end
end


-- setup table when player joins
minetest.register_on_joinplayer(function(player)

	if player then

		local name = player:get_player_name()
		local meta = player:get_meta()

		playing[name] = {
			mvol = tonumber(meta:get_string("ambience.mvol")) or MUSICVOLUME,
			svol = tonumber(meta:get_string("ambience.svol")) or SOUNDVOLUME,
			music = 0,
			music_handler = nil
		}
	end
end)

-- remove table when player leaves
minetest.register_on_leaveplayer(function(player)

	if player then
		playing[player:get_player_name()] = nil
	end
end)


-- plays music and selects sound set
local get_ambience = function(player, tod, name)

	-- if enabled and not already playing, play local/server music on interval check
	if play_music and playing[name] and playing[name].mvol > 0 then

		-- increase music interval
		playing[name].music = playing[name].music + 1

		-- play music on interval check
		if playing[name].music > MUSICINTERVAL and playing[name].music_handler == nil then

			playing[name].music_handler = minetest.sound_play("ambience_music", {
				to_player = name,
				gain = playing[name].mvol
			})

			playing[name].music = 0 -- reset interval
		end
--print("-- music timer", playing[name].music .. "/" .. MUSICINTERVAL)
	end

	-- get foot and head level nodes at player position
	local pos = player:get_pos() ; if not pos then return end
	local prop = player:get_properties()
	local eyeh = prop.eye_height or 1.47 -- eye level with fallback

	pos.y = pos.y + eyeh -- head level

	local nod_head = minetest.get_node(pos).name

	pos.y = (pos.y - eyeh) + 0.2 -- foot level

	local nod_feet = minetest.get_node(pos).name

	pos.y = pos.y - 0.2 -- reset pos

	-- get all set nodes around player
	local ps, cn = minetest.find_nodes_in_area(
		{x = pos.x - radius, y = pos.y - radius, z = pos.z - radius},
		{x = pos.x + radius, y = pos.y + radius, z = pos.z + radius}, set_nodes)

	-- loop through sets in order and choose first that meets conditions set
	for n = 1, #sound_set_order do

		local set = sound_sets[ sound_set_order[n] ]

		if set and set.sound_check then

			-- pass settings to function for condition check
			local set_name, gain = set.sound_check({
				player = player,
				pos = pos,
				tod = tod,
				totals = cn,
				positions = ps,
				head_node = nod_head,
				feet_node = nod_feet
			})

			-- if conditions met return set name and gain value
			if set_name then
				return set_name, gain
			end
		end
	end

	return nil, nil
end


local timer = 0
local random = math.random

-- players routine
minetest.register_globalstep(function(dtime)

	-- one second timer
	timer = timer + dtime
	if timer < 1 then return end
	timer = 0

	local player_name, number, chance, ambience, handler, ok
	local tod = minetest.get_timeofday()

	-- loop through players
	for _, player in pairs(minetest.get_connected_players()) do

		player_name = player:get_player_name()

		local set_name, MORE_GAIN = get_ambience(player, tod, player_name)

		ok = playing[player_name] -- everything starts off ok if player found

		-- are we playing something already?
		if ok and playing[player_name].handler then

			-- stop current sound if another set active or gain changed
			if playing[player_name].set ~= set_name
			or playing[player_name].gain ~= MORE_GAIN then

--print ("-- change stop", set_name, playing[player_name].handler)

				minetest.sound_stop(playing[player_name].handler)

				playing[player_name].set = nil
				playing[player_name].gain = nil
				playing[player_name].handler = nil
			else
				ok = false -- sound set still playing, skip new sound
			end
		end

		-- set random chance
		chance = random(1000)

		-- if chance is lower than set frequency then select set
		if ok and set_name and chance < sound_sets[set_name].frequency then

			number = random(#sound_sets[set_name].sounds) -- choose random sound from set
			ambience = sound_sets[set_name].sounds[number] -- grab sound information

			-- play sound
			handler = minetest.sound_play(ambience.name, {
				to_player = player_name,
				gain = ((ambience.gain or 0.3) + (MORE_GAIN or 0)) * playing[player_name].svol,
				pitch = ambience.pitch or 1.0
			}, ambience.ephemeral)

--print ("playing... " .. ambience.name .. " (" .. chance .. " < "
--		.. sound_sets[set_name].frequency .. ") @ ", MORE_GAIN, handler)

			-- only continue if sound playing returns handler
			if handler then

--print("-- current handler", handler)

				-- set what player is currently listening to
				playing[player_name].set = set_name
				playing[player_name].gain = MORE_GAIN
				playing[player_name].handler = handler

				-- set timer to stop sound
				minetest.after(ambience.length, function(handler, player_name)

--print("-- timed stop", set_name, handler)
					if handler then
						minetest.sound_stop(handler)
					end

					-- reset variables if handlers match
					if playing[player_name]
					and playing[player_name].handler == handler then

--print("-- timed reset", handler, player_name)

						playing[player_name].set = nil
						playing[player_name].gain = nil
						playing[player_name].handler = nil
					end
				end, handler, player_name)
			end
		end
	end
end)


-- sound volume command
minetest.register_chatcommand("svol", {
	params = S("<svol>"),
	description = S("set sound volume (0.1 to 1.0)"),
	privs = {},

	func = function(name, param)

		local svol = tonumber(param) or playing[name].svol

		if svol < 0.1 then svol = 0.1 end
		if svol > 1.0 then svol = 1.0 end

		local player = minetest.get_player_by_name(name)
		local meta = player:get_meta()

		meta:set_string("ambience.svol", svol)

		playing[name].svol = svol

		return true, S("Sound volume set to @1", svol)
	end
})


-- music volume command (0 stops music)
minetest.register_chatcommand("mvol", {
	params = S("<mvol>"),
	description = S("set music volume (0.1 to 1.0, 0 to stop music)"),
	privs = {},

	func = function(name, param)

		local mvol = tonumber(param) or playing[name].mvol

		-- stop music currently playing by setting volume to 0
		if mvol == 0 and playing[name].music_handler then

			minetest.sound_stop(playing[name].music_handler)

			playing[name].music_handler = nil

			minetest.chat_send_player(name, S("Music stopped!"))
		end

		if mvol < 0 then mvol = 0 end
		if mvol > 1.0 then mvol = 1.0 end

		local player = minetest.get_player_by_name(name)
		local meta = player:get_meta()

		meta:set_string("ambience.mvol", mvol)

		playing[name].mvol = mvol

		return true, S("Music volume set to @1", mvol)
	end
})


-- load default sound sets
dofile(minetest.get_modpath("ambience") .. "/soundsets.lua")


print("[MOD] Ambience Lite loaded")


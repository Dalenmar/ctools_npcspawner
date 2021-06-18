local t_requests = {}
local t_spawnednpcs = {}
local t_npcs = {}




local flags = FCVAR_ARCHIVE+FCVAR_LUA_SERVER+FCVAR_SERVER_CAN_EXECUTE
local desc = [[Chromium NPC Tool
	The amount of NPCs that will be spawned each server tick in process
	Minimum value - 1, maximum - 100
	If your server experiences crashes while using the tool, keep this value at 1]]
local cvar_min, cvar_max = 1, 100
local cvar_mnt = CreateConVar('ct_npc_amount','1',flags,desc,cvar_min,cvar_max)
local npc_per_tick = cvar_mnt:GetInt()
cvars.AddChangeCallback('ct_npc_amount',function()
	npc_per_tick = cvar_mnt:GetInt()
end)




util.AddNetworkString('ctnpces')

hook.Add('InitPostEntity','ctools_npc',function()
	local npctab = list.Get('NPC')
	for k,v in pairs(npctab) do
		t_npcs[v.Name] = v
	end
end)

net.Receive('ctnpces',function(len,ply)
	local af = #t_requests+1
	t_requests[af] = {}
	local reqt = t_requests[af]
	reqt.ply = ply
	reqt.npckey = #t_spawnednpcs+1
	t_spawnednpcs[reqt.npckey] = {}
	reqt.info = {}
	reqt.info[1] = net.ReadString()
	reqt.info[2] = net.ReadInt(9)
	reqt.info[3] = net.ReadUInt(32)
	reqt.info[4] = net.ReadBool()
	if !reqt.info[4] then
		reqt.info[5] = net.ReadString()
	end
	reqt.info[6] = net.ReadBool()
	if reqt.info[6] then
		reqt.info[7] = net.ReadString()
	end
	reqt.info[8] = net.ReadUInt(5)
	reqt.info[9] = net.ReadUInt(3)
	reqt.info[10] = net.ReadBool()
	reqt.info[11] = net.ReadBool()
	reqt.info[12] = net.ReadBool()
	reqt.info[13] = net.ReadBool()
	if reqt.info[13] then
		reqt.info[14] = net.ReadString()
	end
	reqt.info[15] = net.ReadBool()
	if reqt.info[15] then
		reqt.info[16] = net.ReadUInt(32)
	end
	reqt.info[17] = net.ReadBool()
	if reqt.info[17] then
		reqt.info[18] = net.ReadUInt(32)
	end
	reqt.info[19] = net.ReadUInt(16)
	reqt.info[20] = net.ReadFloat()
	reqt.info[21] = {}
	reqt.info[22] = {}
	for i = 1, reqt.info[19] do
		reqt.info[21][i] = net.ReadInt(16)
		reqt.info[22][i] = net.ReadInt(16)
	end

	undo.Create('NPC')
		undo.SetCustomUndoText('Undone NPC Area')
		undo.AddFunction(function(tab,args)
			for k,v in ipairs(t_spawnednpcs[reqt.npckey] or {}) do
				v:Remove()
			end
			t_requests[af] = nil
			t_spawnednpcs[reqt.npckey] = nil
		end)
		undo.SetPlayer(ply)
	undo.Finish('NPC Area')
end)


local req_key

hook.Add('Tick','ctools_npc',function()
	if !req_key or !t_requests[req_key] then
		req_key = next(t_requests)
	end
	local reqt = t_requests[req_key]
	if !reqt then return end

	for i = 1, npc_per_tick do
		if #reqt.info[21] == 0 then
			t_requests[req_key] = nil
			break
		end

		local NPCData = t_npcs[reqt.info[1]]
		if !NPCData or !NPCData.Class then continue end

		local npc = ents.Create(NPCData.Class)
		if !IsValid(npc) then continue end
		t_spawnednpcs[reqt.npckey][#(t_spawnednpcs[reqt.npckey])+1] = npc

		-- POSITION
		local posoff = NPCData.Offset or 32
		local pos = Vector(reqt.info[21][#(reqt.info[21])],reqt.info[22][#(reqt.info[22])],reqt.info[20]+posoff)
		if !util.IsInWorld(pos) then
			reqt.info[21][#(reqt.info[21])] = nil
			reqt.info[22][#(reqt.info[22])] = nil
			continue
		end
		npc:SetPos(pos)
		reqt.info[21][#(reqt.info[21])] = nil
		reqt.info[22][#(reqt.info[22])] = nil

		-- ANGLES
		local ang = Angle(0,reqt.info[2],0)
		if NPCData.Rotate then
			ang = ang + NPCData.Rotate
		end
		npc:SetAngles(ang)

		-- SPAWNFLAGS
		local sfs = reqt.info[3]
		if NPCData.SpawnFlags then
			sfs = bit.bor(sfs,NPCData.SpawnFlags)
		end
		if NPCData.TotalSpawnFlags then
			sfs = NPCData.TotalSpawnFlags
		end
		npc:SetKeyValue('spawnflags',sfs)
		npc.SpawnFlags = sfs

		-- KEYVALUES
		if NPCData.KeyValues then
			for k,v in pairs(NPCData.KeyValues) do
				npc:SetKeyValue(k,v)
			end
		end
		if reqt.info[13] then
			npc:SetKeyValue('SquadName',reqt.info[14])
			npc:Fire('setsquad',reqt.info[14],0)
		end

		-- MODEL
		if NPCData.Model then
			npc:SetModel(NPCData.Model)
		end
		if reqt.info[6] and util.IsValidModel(reqt.info[7]) then
			npc:SetModel(reqt.info[7])
		end

		-- MATERIAL
		if NPCData.Material then
			npc:SetMaterial(NPCData.Material)
		end

		-- SKIN
		if NPCData.Skin then
			npc:SetSkin(NPCData.Skin)
		end
		npc:SetSkin(reqt.info[8])

		-- WEAPON
		if !reqt.info[4] then
			if reqt.info[5] == '_def' then
				if istable(NPCData.Weapons) then
					local eqwep = NPCData.Weapons[math.random(#NPCData.Weapons)]
					npc:SetKeyValue('additionalequipment',eqwep)
				end
			elseif reqt.info[5] ~= '' then
				npc:SetKeyValue('additionalequipment',reqt.info[5])
			end
		end

		-- SPAWN
		npc:Spawn()
		npc:Activate()

		-- BODYGROUPS
		if NPCData.BodyGroups then
			for k,v in pairs(NPCData.BodyGroups) do
				npc:SetBodygroup(k,v)
			end
		end

		-- WEAPON PROFICIENCY
		local prof = reqt.info[9]
		if reqt.info[9] == 5 then
			prof = math.random(0,4)
		elseif reqt.info[9] == 6 then
			prof = math.random(2,4)
		elseif reqt.info[9] == 7 then
			prof = math.random(0,2)
		end
		npc:SetCurrentWeaponProficiency(prof)

		-- RELATIONSHIPS
		if reqt.info[10] then
			npc:AddEntityRelationship(reqt.ply,D_LI,99)
		end
		if reqt.info[11] then
			npc:AddRelationship('player D_LI 99')
		end

		-- MOVEMENT
		if reqt.info[12] then
			npc:CapabilitiesRemove(CAP_MOVE_GROUND)
			npc:CapabilitiesRemove(CAP_MOVE_FLY)
			npc:CapabilitiesRemove(CAP_MOVE_CLIMB)
			npc:CapabilitiesRemove(CAP_MOVE_SWIM)
		end
		
		-- HEALTH
		if reqt.info[15] then
			npc:SetMaxHealth(reqt.info[16])
		end
		if reqt.info[17] then
			npc:SetHealth(reqt.info[18])
		elseif NPCData.Health then
			npc:SetHealth( NPCData.Health )
		end

		-- DROP TO FLOOR
		if !NPCData.NoDrop and !NPCData.OnCeiling then --!NPCData.OnFloor
			npc:DropToFloor()
		end
	end
end)
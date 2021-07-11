local net = net
local undo = undo
local math = math
local ipairs = ipairs
local pairs = pairs
local CurTime = CurTime


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


local t_requests = {}
local t_spawnednpcs = {}
local t_npcs = {}
local req_key = 1
local postraceoff = Vector(0,0,512)

local t_ceilingnpcs = {
	['Barnacle'] = true,
	['Camera'] = true,
	['Ceiling Turret'] = true,
}


util.AddNetworkString('ctnpces')


local function RequestClear(id)
	t_requests[id] = nil
	local temp = {}
	for k,v in pairs(t_requests) do
		temp[#temp+1] = v
	end
	t_requests = temp
end

local function InitNPCList()
	local npctab = list.Get('NPC')
	for k,v in pairs(npctab) do
		if !t_npcs[v.Category] then
			t_npcs[v.Category] = {}
		end
		t_npcs[v.Category][v.Name] = v
	end
end

local function ReceiveData(len,ply)
	local cmplen = net.ReadUInt(32)
	local cmpdata = net.ReadData(cmplen)
	local data = util.JSONToTable(util.Decompress(cmpdata))
	if !data then return end

	for k,v in ipairs(data) do
		local af = #t_requests+1
		t_requests[af] = {}
		local reqt = t_requests[af]
		reqt.ply = ply
		reqt.npckey = #t_spawnednpcs+1
		t_spawnednpcs[reqt.npckey] = {}
		reqt.info = v
		local info = reqt.info

		-- POSITION GRID
		local areatab = {}
		for i = 1, info.by_x do
			for j = 1, info.by_y do
				areatab[#areatab+1] = {
					info.pos_start.x+i*info.abs*info.ssx,
					info.pos_start.y+j*info.abs*info.ssy,
					info.pos_start.x+(i-1)*info.abs*info.ssx,
					info.pos_start.y+(j-1)*info.abs*info.ssy,
				}
			end
		end
		t_requests[af].info.areatab = areatab

		-- SPAWN METHOD
		if info.sm_method == 3 then
			t_requests[af].info.ts = info.sm_timer < 1 and math.huge or CurTime()+info.sm_timer
		elseif info.sm_method == 2 then
			if info.sm_total == 0 then
				t_requests[af].info.sm_total = math.huge
			end
		end

		-- UNDO
		undo.Create('NPC')
			undo.SetCustomUndoText('Undone NPC Area')
			undo.AddFunction(function(tab,args)
				if info.sm_removal then
					for k,v in ipairs(t_spawnednpcs[reqt.npckey] or {}) do
						if !IsValid(v) then continue end
						v:Remove()
					end
				end
				RequestClear(af)
				t_spawnednpcs[reqt.npckey] = nil
			end)
			undo.SetPlayer(ply)
		undo.Finish('NPC Area')
	end
end

local function CalculatePos(req_id,pos_id)
	local info = t_requests[req_id].info
	local x = math.Round((info.areatab[pos_id][1]+info.areatab[pos_id][3])/2+math.random(-info.random,info.random))
	local y = math.Round((info.areatab[pos_id][2]+info.areatab[pos_id][4])/2+math.random(-info.random,info.random))
	local gridpos = Vector(x,y,info.maxz)
	local trinfo1 = {start = gridpos,endpos = gridpos+postraceoff}
	local tr1 = util.TraceLine(trinfo1)
	if tr1.StartSolid then
		t_requests[req_id].info.areatab[pos_id] = nil
		return
	end
	if t_ceilingnpcs[info.class] then
		if IsValid(tr1.HitEntity) and tr1.HitEntity:IsNPC() then return end
		if !tr1.Hit then
			t_requests[req_id].info.areatab[pos_id] = nil
			return
		end
		return tr1.HitPos
	end
	local trinfo2 = {start = tr1.HitPos,endpos = tr1.HitPos-postraceoff*2}
	local tr2 = util.TraceLine(trinfo2)
	if IsValid(tr2.HitEntity) and tr2.HitEntity:IsNPC() then return end
	return tr2.HitPos
end

local function SpawnNPC(req_id,pos_id)
	local reqt = t_requests[req_id]
	if !reqt then return end
	local info = reqt.info
	
	-- CATEGORY & CLASS CHECK
	local npccat = t_npcs[info.npccat]
	if !npccat then
		RequestClear(req_key)
		return
	end
	local NPCData = npccat[info.class]
	if !NPCData or !NPCData.Class then
		RequestClear(req_key)
		return
	end

	-- POSITION CHECK
	local pos = CalculatePos(req_id,pos_id)
	if !pos then return end

	-- CREATION
	local npc = ents.Create(NPCData.Class)
	if !IsValid(npc) then
		RequestClear(req_key)
		return
	end
	t_spawnednpcs[reqt.npckey][#(t_spawnednpcs[reqt.npckey])+1] = npc
	if info.sm_method == 1 then
		t_requests[req_id].info.areatab[pos_id] = nil
	else
		t_requests[req_id].info.areatab[pos_id].npc = npc
		t_requests[req_id].info.areatab[pos_id].delay = nil
	end

	-- POSITION & ANGLES
	local posoff = Vector(0,0,NPCData.Offset or 32)
	npc:SetPos(pos+posoff)
	npc:SetAngles(info.angle or Angle(0,0,0))

	-- SPAWNFLAGS
	local sfs = info.flags
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
	if info.squad then
		npc:SetKeyValue('SquadName',info.squad)
		npc:Fire('setsquad',info.squad)
	end
	--npc:SetKeyValue('startburrowed','1')
	--npc:Fire('unburrow')

	-- MODEL
	if NPCData.Model then
		npc:SetModel(NPCData.Model)
	end
	if info.model and util.IsValidModel(info.model) then
		npc:SetModel(info.model)
	end

	-- MATERIAL
	if NPCData.Material then
		npc:SetMaterial(NPCData.Material)
	end

	-- WEAPON
	if info.equip == '_def' then
		if istable(NPCData.Weapons) then
			local eqwep = NPCData.Weapons[math.random(#NPCData.Weapons)]
			npc:SetKeyValue('additionalequipment',eqwep)
		end
	elseif info.equip and info.equip ~= '' then
		npc:SetKeyValue('additionalequipment',info.equip)
	end

	-- SPAWN
	npc:Spawn()
	npc:Activate()

	-- SKIN
	if NPCData.Skin then
		npc:SetSkin(NPCData.Skin)
	end
	if info.skin == 1 then
		local randskin = math.random(1,npc:SkinCount())-1
		npc:SetSkin(randskin)
	elseif info.skin > 1 then
		npc:SetSkin(info.skin-1)
	end

	-- BODYGROUPS
	if NPCData.BodyGroups then
		for k,v in pairs(NPCData.BodyGroups) do
			npc:SetBodygroup(k,v)
		end
	end

	-- WEAPON PROFICIENCY
	local prof = info.prof
	if info.prof == 5 then
		prof = math.random(0,4)
	elseif info.prof == 6 then
		prof = math.random(2,4)
	elseif info.prof == 7 then
		prof = math.random(0,2)
	elseif info.prof == 8 then
		prof = nil
	end
	if prof and npc.SetCurrentWeaponProficiency then
		npc:SetCurrentWeaponProficiency(prof)
	end

	-- RELATIONSHIPS
	if info.ignoreply and npc.AddEntityRelationship then
		npc:AddEntityRelationship(reqt.ply,D_LI,99)
	end
	if info.ignoreplys and npc.AddRelationship then
		npc:AddRelationship('player D_LI 99')
	end

	-- MOVEMENT
	if info.immobile and npc.CapabilitiesRemove then
		npc:CapabilitiesRemove(CAP_MOVE_GROUND)
		npc:CapabilitiesRemove(CAP_MOVE_FLY)
		npc:CapabilitiesRemove(CAP_MOVE_CLIMB)
		npc:CapabilitiesRemove(CAP_MOVE_SWIM)
	end

	-- HEALTH
	if info.maxhp then
		npc:SetMaxHealth(info.maxhp)
	end
	if info.hp then
		npc:SetHealth(info.hp)
	elseif NPCData.Health then
		npc:SetHealth(NPCData.Health)
	end

	-- DROP TO FLOOR
	--[[
		if !NPCData.NoDrop and !NPCData.OnCeiling then --!NPCData.OnFloor
			npc:DropToFloor()
		end
	]]

	-- TOTAL COUNT
	if info.sm_method == 2 then
		t_requests[req_id].info.sm_total = info.sm_total - 1
	end
end

local function GetArea(req_id)
	local reqt = t_requests[req_id]
	local info = reqt.info
	local sm_def = info.sm_method == 1
	local delay = info.sm_respdelay
	local temp = {}
	for k,v in pairs(info.areatab) do
		if !sm_def and IsValid(v.npc) then continue end
		if delay and v.npc ~= nil then
			local ct = CurTime()
			if !v.delay then
				t_requests[req_id].info.areatab[k].delay = CurTime()+delay
				continue
			end
			if ct < v.delay then continue end
		end
		temp[#temp+1] = k
	end
	local t_key = info.sm_random and math.random(#temp) or #temp
	return temp[t_key]
end

local function SpawnThink()
	local req_cnt = #t_requests
	if req_cnt == 0 then return end
	--req_key = ((req_key+1)%req_cnt)+1
	req_key = math.random(req_cnt)
	local reqt = t_requests[req_key]
	if !reqt then return end
	local info = reqt.info
	local sm_def = info.sm_method == 1
	if !sm_def then
		if info.sm_method == 3 then
			if info.ts < CurTime() then
				RequestClear(req_key)
				return
			end
		end
		local cnt = 0
		for k,v in ipairs(t_spawnednpcs[reqt.npckey] or {}) do
			if !IsValid(v) then continue end
			cnt = cnt + 1
		end
		local alive_cnt = info.sm_alive == 0 and info.by_x*info.by_y or info.sm_alive
		if cnt >= alive_cnt then
			return
		end
		if info.sm_method == 2 and info.sm_total < 1 then
			RequestClear(req_key)
			return
		end
	end

	for i = 1, npc_per_tick do
		local posi = GetArea(req_key)
		if (!posi or posi == 0) then
			if sm_def then
				RequestClear(req_key)
			end
			continue
		end
		SpawnNPC(req_key,posi)
	end
end




net.Receive('ctnpces',ReceiveData)
hook.Add('InitPostEntity','ctools_npc',InitNPCList)
hook.Add('Tick','ctools_npc',SpawnThink)
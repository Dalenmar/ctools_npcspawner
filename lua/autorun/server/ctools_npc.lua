local net = net
local undo = undo
local math = math
local table = table
local ipairs = ipairs
local pairs = pairs
local CurTime = CurTime


local npc_per_tick, npc_max

local flags = {FCVAR_ARCHIVE,FCVAR_LUA_SERVER,FCVAR_SERVER_CAN_EXECUTE,FCVAR_NOTIFY,FCVAR_REPLICATED}
local desc = [[Chromium NPC Tool
	The amount of NPCs that will be spawned each server tick in process
	Minimum value - 1, maximum - 100
	If your server experiences crashes while using the tool, keep this value at 1]]
local cvar_mnt = CreateConVar('ct_npc_tick','1',flags,desc,1,100)
npc_per_tick = cvar_mnt:GetInt()
cvars.AddChangeCallback('ct_npc_tick',function()
	npc_per_tick = cvar_mnt:GetInt()
end)

local desc = [[Chromium NPC Tool
	The maximum amount of NPCs that can be spawned per area
	Minimum value - 1, maximum - 8192
	This convar guaranties that amount of spawned NPCs for each area may not exceed the value
	Doesn't work like clamp - just notifies client when creating an area]]
local cvar_max = CreateConVar('ct_npc_area','1024',flags,desc,1,8192)
npc_max = cvar_max:GetInt()
cvars.AddChangeCallback('ct_npc_area',function()
	npc_max = cvar_max:GetInt()
end)


local t_requests = {}
local t_spawnednpcs = {}
local t_npcs = {}
local req_key = 1
local postraceoff = Vector(0,0,512)
local think_npcs = 0
local req_exec = false
local ukey_incr = 0

local t_ceilingnpcs = {
	['Barnacle'] = true,
	['Camera'] = true,
	['Ceiling Turret'] = true,
}


util.AddNetworkString('ctnpces')




local function RequestGet(ukey)
	if !ukey then return end
	for k,v in ipairs(t_requests) do
		if v.ukey ~= ukey then continue end
		return k
	end
end
	
local function RequestClear(id_or_ukey)
	if !id_or_ukey then return end
	if isstring(id_or_ukey) then
		for k,v in ipairs(t_requests) do
			if v.ukey ~= id_or_ukey then continue end
			id_or_ukey = k
			break
		end
	end
	if !t_requests[id_or_ukey] then return end
	table.remove(t_requests,id_or_ukey)
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

	for k,vinfo in ipairs(data) do
		-- BASTARD CHECK
		local bastard = true
		while true do
			local npccat = t_npcs[vinfo.npccat]
			if !npccat then break end
			local npcdata = npccat[vinfo.class]
			if !npcdata or !npcdata.Class then break end
			if !isnumber(vinfo.sm_method) or vinfo.sm_method < 1 or vinfo.sm_method > 3 then break end
			if !isvector(vinfo.pos_start) then break end
			if !isnumber(vinfo.by_x) or !isnumber(vinfo.by_y) then break end
			if vinfo.by_x < 1 or vinfo.by_y < 1 then break end
			if vinfo.by_x*vinfo.by_y > npc_max then break end
			if !isnumber(vinfo.ssx) or !isnumber(vinfo.ssy) then break end
			if math.abs(vinfo.ssx) ~= 1 or math.abs(vinfo.ssy) ~= 1 then break end
			if !isnumber(vinfo.abs) or vinfo.abs < 24 then break end
			if !isnumber(vinfo.by_count) then break end
			if vinfo.by_count < 1 or vinfo.by_count > npc_max then break end
			bastard = false
			break
		end
		if bastard then continue end
		

		-- TABLE ASSIGN
		ukey_incr = ukey_incr + 1
		local ukey = 'ukey_'..tostring(ukey_incr)
		local af = #t_requests+1
		t_requests[af] = {}
		local reqt = t_requests[af]
		reqt.ukey = ukey
		reqt.ply = ply
		reqt.info = vinfo
		local info = reqt.info
		info.count = 0
		t_spawnednpcs[ukey] = {}

		-- POSITION GRID
		local areatab = {}
		for x = 1, info.by_x do
			for y = 1, info.by_y do
				areatab[#areatab+1] = {
					info.pos_start.x+x*info.abs*info.ssx,
					info.pos_start.y+y*info.abs*info.ssy,
					info.pos_start.x+(x-1)*info.abs*info.ssx,
					info.pos_start.y+(y-1)*info.abs*info.ssy,
				}
			end
		end
		info.areatab = areatab

		-- SPAWN METHOD
		if info.sm_method == 3 then
			info.ts = info.sm_timer < 1 and math.huge or CurTime()+info.sm_timer
		elseif info.sm_method == 2 then
			if info.sm_total == 0 then
				info.sm_total = math.huge
			end
		end

		-- UNDO
		local removal = info.sm_removal
		undo.Create('NPC')
			undo.SetCustomUndoText('Undone NPC Area'..(removal and ' with NPCs' or ''))
			undo.AddFunction(function(tab,args)
				if t_spawnednpcs[ukey] then
					for k,ent in ipairs(t_spawnednpcs[ukey]) do
						if !IsValid(ent) then continue end
						ent.ct_ukey = nil
						if !removal then continue end
						ent:Remove()
					end
					t_spawnednpcs[ukey] = nil
				end
				RequestClear(ukey)
			end)
			undo.SetPlayer(ply)
		undo.Finish('NPC Area')
	end
end

local function CalculatePos(req_id,pos_id)
	local info = t_requests[req_id].info
	local areatab = info.areatab
	local x = math.Round((areatab[pos_id][1]+areatab[pos_id][3])/2+math.random(-info.random,info.random))
	local y = math.Round((areatab[pos_id][2]+areatab[pos_id][4])/2+math.random(-info.random,info.random))
	local gridpos = Vector(x,y,info.maxz)
	local trinfo1 = {start = gridpos,endpos = gridpos+postraceoff}
	local tr1 = util.TraceLine(trinfo1)
	if tr1.StartSolid then
		table.remove(areatab,pos_id)
		return
	end
	if t_ceilingnpcs[info.class] then
		if IsValid(tr1.HitEntity) and tr1.HitEntity:IsNPC() then return end
		if !tr1.Hit then
			table.remove(areatab,pos_id)
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
	local npccat = t_npcs[info.npccat]
	local npcdata = npccat[info.class]

	-- POSITION CHECK
	local pos = CalculatePos(req_id,pos_id)
	if !pos then return end

	-- CREATION
	local npc = ents.Create(npcdata.Class)
	if !IsValid(npc) then
		t_spawnednpcs[reqt.ukey] = nil
		RequestClear(req_id)
		return
	end
	t_spawnednpcs[reqt.ukey][#t_spawnednpcs[reqt.ukey]+1] = npc
	if info.sm_method == 1 then
		table.remove(info.areatab,pos_id)
	else
		info.areatab[pos_id].npc = npc
		info.areatab[pos_id].delay = nil
	end

	-- POSITION & ANGLES
	local posoff = Vector(0,0,npcdata.Offset or 32)
	npc:SetPos(pos+posoff)
	npc:SetAngles(info.angle or Angle(0,0,0))

	-- SPAWNFLAGS
	local sfs = info.flags
	if npcdata.SpawnFlags then
		sfs = bit.bor(sfs,npcdata.SpawnFlags)
	end
	if npcdata.TotalSpawnFlags then
		sfs = npcdata.TotalSpawnFlags
	end
	npc:SetKeyValue('spawnflags',sfs)
	npc.SpawnFlags = sfs

	-- KEYVALUES
	if npcdata.KeyValues then
		for k,v in pairs(npcdata.KeyValues) do
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
	if npcdata.Model then
		npc:SetModel(npcdata.Model)
	end
	if info.model and util.IsValidModel(info.model) then
		npc:SetModel(info.model)
	end

	-- MATERIAL
	if npcdata.Material then
		npc:SetMaterial(npcdata.Material)
	end

	-- WEAPON
	if info.equip == '_def' then
		if istable(npcdata.Weapons) then
			local eqwep = npcdata.Weapons[math.random(#npcdata.Weapons)]
			npc:SetKeyValue('additionalequipment',eqwep)
		end
	elseif info.equip and info.equip ~= '' then
		npc:SetKeyValue('additionalequipment',info.equip)
	end

	-- SPAWN
	npc:Spawn()
	npc:Activate()

	-- SKIN
	if npcdata.Skin then
		npc:SetSkin(npcdata.Skin)
	end
	if info.skin == 1 then
		local randskin = math.random(1,npc:SkinCount())-1
		npc:SetSkin(randskin)
	elseif info.skin > 1 then
		npc:SetSkin(info.skin-1)
	end

	-- BODYGROUPS
	if npcdata.BodyGroups then
		for k,v in pairs(npcdata.BodyGroups) do
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
	elseif npcdata.Health then
		npc:SetHealth(npcdata.Health)
	end

	-- TOTAL COUNT
	if info.sm_method == 2 then
		info.sm_total = info.sm_total - 1
	end
	
	-- COUNT CHECK
	npc.fuck_me = true
	npc.ct_ukey = reqt.ukey
	info.count = info.count + 1

	-- RETURN
	return true
end

local function GetArea(req_id)
	local reqt = t_requests[req_id]
	local info = reqt.info
	local sm_def = info.sm_method == 1
	local delay = info.sm_respdelay
	local temp = {}
	for k,v in ipairs(info.areatab) do
		if !sm_def and IsValid(v.npc) then continue end
		if delay and v.npc ~= nil then
			local ct = CurTime()
			if !v.delay then
				info.areatab[k].delay = CurTime()+delay
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
	req_exec = false
	local reqt, info

	for i = 1, req_cnt do
		req_key = math.max(1,(req_key+1)%(req_cnt+1))
		reqt = t_requests[req_key]
		if !reqt then continue end
		info = reqt.info
		if info.full then continue end
		if info.sm_method == 1 then
			req_exec = true
			break
		end
		if info.count >= (info.sm_alive ~= 0 and info.sm_alive or info.by_count) then
			info.full = true
			continue
		end
		if info.sm_method == 2 and info.sm_total < 1 then
			info.full = true
			continue
		end
		req_exec = true
		break
	end

	if !req_exec then return end
	think_npcs = 0
	while think_npcs < npc_per_tick do
		if #info.areatab < 1 and info.count < 1 then
			if t_spawnednpcs[reqt.ukey] then
				t_spawnednpcs[reqt.ukey] = nil
			end
			RequestClear(req_key)
			return
		end
		local posi = GetArea(req_key)
		if (!posi or posi == 0) then
			if info.sm_method == 1 then
				info.full = true
				return
			end
			think_npcs = think_npcs + 1
			continue
		end
		if !SpawnNPC(req_key,posi) then return end
		think_npcs = think_npcs + 1
	end
end

local function RemovalCheck(ent)
	if !ent or !ent.ct_ukey then return end
	local req_id = RequestGet(ent.ct_ukey)
	local reqt = t_requests[req_id]
	if !reqt then return end
	local info = reqt.info
	info.count = info.count - 1
	if info.sm_method == 2 then
		info.full = nil
	end
	if info.sm_method == 3 and info.ts > CurTime() then
		info.full = nil
		return
	end
	if info.count > 0 then return end
	if info.sm_total and info.sm_total > 0 then return end
	if t_spawnednpcs[reqt.ukey] then
		t_spawnednpcs[reqt.ukey] = nil
	end
	RequestClear(ent.ct_ukey)
end

function ctnpcdebug(ply,cmd,args,strarg)
	if IsValid(ply) and ply ~= Entity(1) then return end
	print('---------------------------')
	print('\t'..'t_requests:')
	print('\t\t','K','UKEY','METHOD','ALIVE','TOTAL','TIMELEFT')
	for k,v in ipairs(t_requests) do
		local info = v.info
		local tleft = info.ts and (info.ts-CurTime()) or '-'
		print('\t\t',k,v.ukey,info.sm_method,info.count,info.sm_total,tleft)
	end
	print('\t'..'t_spawnednpcs:')
	print('\t\t\t','UKEY','#TAB','ALIVE')
	for k,v in pairs(t_spawnednpcs) do
		local alive = 0
		for k1,v1 in ipairs(v) do
			if !IsValid(v1) then continue end
			alive = alive + 1
		end
		print('\t\t\t',k,#v,alive)
	end
	print('---------------------------\n\n\n')
end




concommand.Add('ct_npc_debuginfo',ctnpcdebug,nil,nil,FCVAR_PROTECTED)
net.Receive('ctnpces',ReceiveData)
hook.Add('InitPostEntity','ctools_npc',InitNPCList)
hook.Add('EntityRemoved','ctools_npc',RemovalCheck)
hook.Add('Tick','ctools_npc',SpawnThink)
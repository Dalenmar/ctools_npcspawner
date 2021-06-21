TOOL.Category = 'Chromium Tools'
TOOL.Name = 'NPC Spawner'
TOOL.Command = nil
TOOL.ConfigName = ''




if SERVER then
	if game.SinglePlayer() then
		util.AddNetworkString('ctdamnprediction')

		local function SendNet(num)
			net.Start('ctdamnprediction')
				net.WriteUInt(num,3)
			net.Send(Entity(1))
		end

		function TOOL:LeftClick() SendNet(0) end
		function TOOL:RightClick() SendNet(1) end
		function TOOL:Reload() SendNet(2) end
		function TOOL:Deploy() SendNet(3) end
		function TOOL:Holster() SendNet(4) end
	end
	return
end

if game.SinglePlayer() then
	net.Receive('ctdamnprediction',function()
		local num = net.ReadUInt(3)
		local tooltab = LocalPlayer():GetTool('ctools_npc')
		if !tooltab then return end
		if num == 0 then
			tooltab:LeftClick()
		elseif num == 1 then
			tooltab:RightClick()
		elseif num == 2 then
			tooltab:Reload()
		elseif num == 3 then
			tooltab:Deploy()
		elseif num == 4 then
			tooltab:Holster()
		end
	end)
end

language.Add('tool.ctools_npc.name','Chromium NPC Spawner')
language.Add('tool.ctools_npc.desc','Simple and flexible NPC Spawner Tool')
language.Add('tool.ctools_npc.left','Create a new spawn area')
language.Add('tool.ctools_npc.right','Request execution of created spawn areas')
language.Add('tool.ctools_npc.reload','Remove last created spawn area or undo the current one')
language.Add('tool.ctools_npc.mscr','Scroll up/down to increase/decrease spread multiplier when creating an area')
language.Add('tool.ctools_npc.mscr2','Hold Shift key when scrolling to change randomness instead')

local font =  'Impact' --'Segoe UI'
for i = 8, 64, 8 do
	surface.CreateFont('CTOOLS_NPC_'..i,{font = font,size = i})
end

TOOL.Information = {
	{name='left'},
	{name='right'},
	{name='reload'},
	{name='mscr',icon='gui/info'},
	{name='mscr2',icon='gui/info'},
}

TOOL.Preset = 'Default'

local WeaponTable = {}

local wepprof = {}
wepprof[WEAPON_PROFICIENCY_POOR] = 'Poor'
wepprof[WEAPON_PROFICIENCY_AVERAGE] = 'Average'
wepprof[WEAPON_PROFICIENCY_GOOD] = 'Good'
wepprof[WEAPON_PROFICIENCY_VERY_GOOD] = 'Very good'
wepprof[WEAPON_PROFICIENCY_PERFECT] = 'Perfect'
wepprof[5] = 'Random'
wepprof[6] = 'Randomly good'
wepprof[7] = 'Randomly bad'

local npcflags = {}
npcflags[1] = 'Wait until seen'
npcflags[2] = 'Gag (no idle sounds until angry)'
npcflags[4] = 'Fall to ground (not teleport)'
npcflags[8] = 'Drop healthkit'
npcflags[16] = 'Don\'t acquire enemies or avoid obstacles'
npcflags[128] = 'Wait for script'
npcflags[256] = 'Long visibility and shoot'
npcflags[512] = 'Fade corpse'
npcflags[1024] = 'Think outside its potentially visible set'
npcflags[2048] = 'Template NPC'
npcflags[4096] = 'Alternate collision for this NPC (player avoidance)'
npcflags[8192] = 'Don\'t drop weapons'
npcflags[16384] = 'Ignore player push'

local npcflagsadd = {}
npcflagsadd['npc_citizen'] = {}
npcflagsadd['npc_citizen'][65536] = 'Follow player on spawn'
npcflagsadd['npc_citizen'][131072] = 'Medic'
npcflagsadd['npc_citizen'][262144] = 'Random head'
npcflagsadd['npc_citizen'][524288] = 'Ammo resupplier'
npcflagsadd['npc_citizen'][1048576] = 'Not commandable (cannot join players squad)'
npcflagsadd['npc_citizen'][4194304] = 'Random male head'
npcflagsadd['npc_citizen'][8388608] = 'Random female head'
npcflagsadd['npc_citizen'][16777216] = 'Use render bounds instead of human hull (for NPCs sitting in chairs, etc.)'
npcflagsadd['npc_citizen'][2097152] = 'Work outside the speech semaphore system'
npcflagsadd['npc_rollermine'] = {}
npcflagsadd['npc_rollermine'][65536] = 'Friendly'
npcflagsadd['npc_turret_floor'] = {}
npcflagsadd['npc_turret_floor'][512] = 'Friendly'

local str_nowep = 'No weapon'
local str_defwep = 'Default weapon'

TOOL.ClientConVar['class'] = 'Citizen'
TOOL.ClientConVar['spread'] = 20
TOOL.ClientConVar['random'] = 0
TOOL.ClientConVar['yaw'] = 0
TOOL.ClientConVar['equip'] = '_def'
TOOL.ClientConVar['model'] = ''
TOOL.ClientConVar['skin'] = 0
TOOL.ClientConVar['skinrandom'] = 0
TOOL.ClientConVar['wepprof'] = 2
TOOL.ClientConVar['ignoreply'] = 0
TOOL.ClientConVar['ignoreplys'] = 0
TOOL.ClientConVar['immobile'] = 0
TOOL.ClientConVar['squad'] = ''
TOOL.ClientConVar['maxhp'] = 0
TOOL.ClientConVar['hp'] = 0

for k,v in SortedPairs(npcflags) do
	TOOL.ClientConVar['SF_'..k] = 0
end
-- Force SF_NPC_ALWAYSTHINK and SF_NPC_FADE_CORPSE flags
TOOL.ClientConVar['SF_512'] = 1
TOOL.ClientConVar['SF_1024'] = 1

for k,v in pairs(npcflagsadd) do
	for k1,v1 in SortedPairs(v) do
		TOOL.ClientConVar['SFA_'..k..'_'..k1] = 0
	end
end

local ConVarsDefault = TOOL:BuildConVarList()
local MIN_SPREAD, MAX_SPREAD = 10, 1000
local MIN_RANDOM, MAX_RANDOM = 0, 100
local mat_wireframe = CreateMaterial('cmat_wireframe','Wireframe')
local mat_solid = CreateMaterial('sadasdas'..math.random(10000),'UnlitGeneric',
	{['$basetexture'] = 'color/white',['$translucent'] = 1,['$vertexalpha'] = 1,['$vertexcolor'] = 1})

local tex_cornerin = Material('gui/corner512')
local tex_cornerout = Material('gui/sniper_corner')

local mcol_black = Color(0,0,0,255)
local mcol_white = Color(255,255,255,255)
local mcol_prewhite = Color(200,200,200,255)
local mcol_bad = Color(255,64,64,64)
local mcol_good = Color(64,255,92,64)
local mcol_completed = Color(128,192,255,64)
local mcol_line = Color(255,255,255,128)

local soundtab = {
	success = 'buttons/button14.wav',
	fail = 'buttons/button11.wav',
	exec = 'buttons/combine_button1.wav',
	undo = 'buttons/button15.wav',
	click_random = 'buttons/lever7.wav',
	click_spread = 'buttons/lightswitch2.wav',
}

local npcboxtab = {
	['_def'] = 26+8,
	['Antlion'] = 32+16,
	['Antlion Worker'] = 32+16,
	['Antlion Guard'] = 80+16,
	['Antlion Guardian'] = 80+16,
	['Strider'] = 76+64,
	['Turret'] = 46+4,
	['City Scanner'] = 16+8,
	['Shield Scanner'] = 16+8,
	['Manhack'] = 16+8,
	['Hunter-Chopper'] = 76+64,
	['Combine Dropship'] = 80+64,
	['Combine Gunship'] = 80+64,
}

local lg_postraceoff = Vector(0,0,512)
local NPCBox = npcboxtab._def
local r_lines_writez = false
local r_renderoff = 2
local r_yawmult = 512
local r_rmkcol = Color(192,192,255,128)
local r_rmksize = 128

local t_areas = {}
local t_npcs, t_weps
local data_npc, data_weps
local oldarcnt, arnpccnt = 0, 0
local trbuff, scndbuff, angbuff
local lp = NULL
local arx, ary = 0, 0
local spamtime = CurTime()
local oldang
local mx_old = 0
local yawlerp = 0


local ipairs = ipairs
local pairs = pairs
local math = math
local cam = cam
local render = render
local surface = surface




hook.Add('InitPostEntity','ctools_npc',function()
	lp = LocalPlayer()
	t_npcs = {}
	local npctab = list.Get('NPC')
	for k,v in pairs(npctab) do
		t_npcs[v.Name] = v
	end
	t_weps = {}
	local weptab = list.Get('Weapon')
	for k,v in pairs(weptab) do
		if !v.Spawnable or !v.PrintName or v.PrintName == '' then continue end
		local name = language.GetPhrase(v.PrintName)
		local wtab = {class = v.ClassName,name = name,category = v.Category}
		t_weps[name] = wtab
	end
	local npcweptab = list.Get('NPCUsableWeapons')
	for k,v in pairs(npcweptab) do
		if !v.class or !v.title or v.title == '' then continue end
		local name = language.GetPhrase(v.title)
		if t_weps[name] then continue end
		local wtab = {class = v.class,name = name,category = 'NPC'}
		t_weps[name] = wtab
	end
end)

hook.Add('PlayerBindPress','ctools_npc', function(ply,bind)
	if !trbuff then return end
	local wep = ply:GetActiveWeapon()
	if !IsValid(wep) or wep:GetClass() ~= 'gmod_tool' then return end
	if ply:GetTool().Mode ~= 'ctools_npc' then return end
	if input.IsMouseDown(MOUSE_WHEEL_DOWN) and input.LookupKeyBinding(MOUSE_WHEEL_DOWN) == bind then return true end
	if input.IsMouseDown(MOUSE_WHEEL_UP) and input.LookupKeyBinding(MOUSE_WHEEL_UP) == bind then return true end
end)

local function IsInWorld(pos)
	return util.TraceLine({start = pos, endpos = pos, collisiongroup = COLLISION_GROUP_WORLD}).HitWorld
end

local function DrawArea(vec1,vec2,mat,col)
	local minx = vec1.x < vec2.x and vec1.x or vec2.x
	local maxx = vec1.x > vec2.x and vec1.x or vec2.x
	local miny = vec1.y < vec2.y and vec1.y or vec2.y
	local maxy = vec1.y > vec2.y and vec1.y or vec2.y
	local maxz = vec1.z > vec2.z and vec1.z or vec2.z
	local v1 = Vector(minx,miny,maxz+r_renderoff)
	local v2 = Vector(minx,maxy,maxz+r_renderoff)
	local v3 = Vector(maxx,maxy,maxz+r_renderoff)
	local v4 = Vector(maxx,miny,maxz+r_renderoff)
	render.SetMaterial(mat)
	render.DrawQuad(v1,v2,v3,v4,col)
	render.DrawQuad(v4,v3,v2,v1,col)
end

local function DrawAngle(pos,ang,sizelimit,ignorez)
	local size = r_rmksize
	if sizelimit and sizelimit < r_rmksize*2 then
		size = sizelimit/2
	end
	local lpunder = lp:GetShootPos().z < pos.z
	local ar = lpunder and 180 or 0
	local yadd = lpunder and -90 or 0
	ang = Angle(0,ang-135+yadd,ar)
	cam.Start3D2D(pos+Vector(0,0,r_renderoff),ang,1)
		if ignorez then cam.IgnoreZ(true) end
			render.PushFilterMag(TEXFILTER.ANISOTROPIC)
			render.PushFilterMin(TEXFILTER.ANISOTROPIC)
				surface.SetDrawColor(r_rmkcol.r,r_rmkcol.g,r_rmkcol.b,r_rmkcol.a)
				surface.SetMaterial(tex_cornerin)
				surface.DrawTexturedRectUV(-size,0-size,size,size,0,0,1,1)
				surface.DrawTexturedRectUV(0,-size,size,size,1,0,0,1)
				surface.DrawTexturedRectUV(-size,0,size,size,0,1,1,0)
				surface.DrawTexturedRectUV(0,0,size,size,1,1,0,0)
				surface.SetMaterial(tex_cornerout)
				surface.DrawTexturedRect(-size,-size,size,size)
			render.PopFilterMag()
			render.PopFilterMin()
		if ignorez then cam.IgnoreZ(false) end
	cam.End3D2D()
end

function TOOL:LeftClick(trace)
	if spamtime+0.1 > CurTime() then return false end
	trace = trace or lp:GetEyeTrace()
	spamtime = CurTime()
	if trbuff then
		local absolute = NPCBox*math.Clamp(self:GetClientNumber('spread',20),MIN_SPREAD,MAX_SPREAD)/10
		
		local maxz = trbuff.z > trace.HitPos.z and trbuff.z or trace.HitPos.z
		local maxz = angbuff and (trbuff.z > scndbuff.z and trbuff.z or scndbuff.z) or trbuff.z
		local area = ((angbuff and scndbuff or trace.HitPos)-trbuff)
		local by_x, by_y = math.floor(math.abs(area.x)/absolute), math.floor(math.abs(area.y)/absolute)
		if by_x < 1 or by_y < 1 then
			notification.AddLegacy('Not enough area!',NOTIFY_ERROR,2)
			surface.PlaySound(soundtab.fail)
			trbuff = nil
			angbuff = nil
			oldang = nil
			return false
		end
		if by_x*by_y > 16384 then
			notification.AddLegacy('Too many NPCs!',NOTIFY_ERROR,2)
			surface.PlaySound(soundtab.fail)
			trbuff = nil
			angbuff = nil
			oldang = nil
			return false
		end
		if !angbuff then
			angbuff = true
			scndbuff = lp:GetEyeTrace().HitPos
			surface.PlaySound(soundtab.success)
			return false
		end
		local areatab = {}
		for i = 1, by_x do
			for j = 1, by_y do
				local ssx = trbuff.x < scndbuff.x and 1 or -1
				local ssy = trbuff.y < scndbuff.y and 1 or -1
				areatab[#areatab+1] = {
					trbuff.x+i*absolute*ssx,
					trbuff.y+j*absolute*ssy,
					trbuff.x+(i-1)*absolute*ssx,
					trbuff.y+(j-1)*absolute*ssy
				}
			end
		end
		local flags = 0
		for k,v in SortedPairs(npcflags) do
			if self:GetClientNumber('SF_'..k,0) ~= 0 then
				flags = bit.bor(flags,k)
			end
		end
		local curclass = self:GetClientInfo('class')
		local data_npc = t_npcs[curclass]
		if npcflagsadd[data_npc.Class] then
			for k,v in SortedPairs(npcflagsadd[data_npc.Class]) do
				local nullflag = bit.bnot(k)
				flags = bit.band(flags,nullflag)
				if self:GetClientNumber('SFA_'..data_npc.Class..'_'..k,0) ~= 0 then
					flags = bit.bor(flags,k)
				end
			end
		end
		local spreadd = math.Clamp(self:GetClientNumber('spread',20),MIN_SPREAD,MAX_SPREAD)
		local randomm = math.Clamp(self:GetClientNumber('random',0),MIN_RANDOM,MAX_RANDOM)
		local quickmath = ((NPCBox*spreadd/10-NPCBox/2)/2*randomm/100)
		local ang = math.NormalizeAngle(angbuff.y)
		local equip = self:GetClientInfo('equip')
		local equipbool = !equip or equip == ''
		local equip_class
		if t_weps[equip] then
			equip_class = t_weps[equip].class
		end
		local skin = self:GetClientNumber('skin',0)
		if self:GetClientNumber('skinrandom',0) ~= 0 then
			skin = -1
		end
		t_areas[#t_areas+1] = {
			trbuff,
			scndbuff,
			areatab,
			maxz,
			spreadd,
			quickmath,
			curclass,
			ang,
			flags,
			equipbool,
			equip_class or equip,
			#self:GetClientInfo('model') > 4,
			self:GetClientInfo('model'),
			skin,
			self:GetClientNumber('wepprof',2),
			tobool(self:GetClientNumber('ignoreply',0)),
			tobool(self:GetClientNumber('ignoreplys',0)),
			tobool(self:GetClientNumber('immobile',0)),
			#self:GetClientInfo('squad') > 0,
			self:GetClientInfo('squad'),
			self:GetClientNumber('maxhp',100) ~= 0,
			self:GetClientNumber('maxhp',100),
			self:GetClientNumber('hp',100) ~= 0,
			self:GetClientNumber('hp',100),
		}
		trbuff = nil
		angbuff = nil
		oldang = nil
		surface.PlaySound(soundtab.success)
		return false
	end
	trbuff = trace.HitPos
	surface.PlaySound(soundtab.success)
	return false
end

function TOOL:RightClick(trace)
	if spamtime+0.1 > CurTime() then return false end
	trace = trace or lp:GetEyeTrace()
	spamtime = CurTime()
	if trbuff and angbuff then return false end
	if trbuff then
		trbuff = nil
		surface.PlaySound(soundtab.success)
		return false
	end
	if !t_areas[1] then return false end
	notification.AddLegacy('Executing...',NOTIFY_GENERIC,2)
	surface.PlaySound(soundtab.exec)
	for k,v in ipairs(t_areas) do
		net.Start('ctnpces')
		net.WriteString(v[7])
		net.WriteInt(v[8],9)
		net.WriteUInt(v[9],32)
		net.WriteBool(v[10])
		if !v[10] then
			net.WriteString(v[11])
		end
		net.WriteBool(v[12])
		if v[12] then
			net.WriteString(v[13])
		end
		net.WriteInt(v[14],6)
		net.WriteUInt(v[15],3)
		net.WriteBool(v[16])
		net.WriteBool(v[17])
		net.WriteBool(v[18])
		net.WriteBool(v[19])
		if v[19] then
			net.WriteString(v[20])
		end
		net.WriteBool(v[21])
		if v[21] then
			net.WriteUInt(v[22],32)
		end
		net.WriteBool(v[23])
		if v[23] then
			net.WriteUInt(v[24],32)
		end
		local temp = {}
		for mk,at in ipairs(v[3]) do
			local x = math.Round((at[1]+at[3])/2+math.random(-v[6],v[6]))
			local y = math.Round((at[2]+at[4])/2+math.random(-v[6],v[6]))
			local gridpos = Vector(x,y,v[4])
			local trinfo1 = {start = gridpos,endpos = gridpos+lg_postraceoff}
			local tr1 = util.TraceLine(trinfo1)
			local trinfo2 = {start = tr1.HitPos,endpos = tr1.HitPos-lg_postraceoff*2}
			local tr2 = util.TraceLine(trinfo2)
			temp[mk] = tr2.HitPos
		end
		local cmpdata = util.Compress(util.TableToJSON(temp))
		net.WriteUInt(#cmpdata,32)
		net.WriteData(cmpdata,#cmpdata)
		net.SendToServer()
	end
	trbuff = nil
	t_areas = {}
	return false
end

function TOOL:Reload()
	if spamtime+0.1 > CurTime() then return false end
	spamtime = CurTime()
	if trbuff then
		trbuff = nil
		angbuff = nil
		oldang = nil
		surface.PlaySound(soundtab.undo)
		notification.AddLegacy('Undone the current area!',NOTIFY_UNDO,2)
		return false
	end
	if t_areas[#t_areas] then
		t_areas[#t_areas] = nil
		surface.PlaySound(soundtab.undo)
		notification.AddLegacy('Undone last created area!',NOTIFY_UNDO,2)
		return false
	end
end

function TOOL:Deploy() end

function TOOL:Holster()
	trbuff = nil
	angbuff = nil
	oldang = nil
end

hook.Add('CreateMove','ctools_npc',function(cmd)
	if angbuff then
		if !oldang then
			oldang = cmd:GetViewAngles()
		end
		cmd:SetViewAngles(oldang)
		local mx = cmd:GetMouseX()
		mx_old = mx_old-mx/16
		angbuff = Angle(0,math.floor(mx_old/15)*15,0)
	end
	if !trbuff then return angbuff end
	local nullcmdnum = cmd:CommandNumber() == 0
	local scrollup = input.WasMousePressed(MOUSE_WHEEL_UP) and nullcmdnum
	local scrolldown = input.WasMousePressed(MOUSE_WHEEL_DOWN) and nullcmdnum
	local shiftdown = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
	if !scrollup and !scrolldown then return angbuff end
	local nmin, nmax
	local var, cvar
	local step = scrolldown and -2 or 2
	if shiftdown then
		var = GetConVar('ctools_npc_random')
		cvar = lp:GetTool():GetClientNumber('random',0)
		nmin, nmax = MIN_RANDOM, MAX_RANDOM
		if var:GetInt() > MIN_RANDOM and var:GetInt() < MAX_RANDOM then
			EmitSound(soundtab.click_random,Vector(0,0,0),-2,CHAN_AUTO,0.25,75,0,255,0)
		end
	else
		var = GetConVar('ctools_npc_spread')
		cvar = lp:GetTool():GetClientNumber('spread',20)
		nmin, nmax = MIN_SPREAD, MAX_SPREAD
		if var:GetInt() > MIN_SPREAD and var:GetInt() < MAX_SPREAD then
			EmitSound(soundtab.click_spread,Vector(0,0,0),-2,CHAN_AUTO,0.25,75,0,255,0)
		end
	end
	if !var then return angbuff end
	var:SetInt(math.Clamp(cvar+step,nmin,nmax))
end)

hook.Add('PostDrawTranslucentRenderables','ctools_npc',function(bDepth,bSkybox)
	if bSkybox then return end
	if !IsValid(lp) then return end
	if !IsValid(lp:GetActiveWeapon()) then return end
	if lp:GetActiveWeapon():GetClass() ~= 'gmod_tool' then return end
	if !lp:GetTool() or lp:GetTool():GetMode() ~= 'ctools_npc' then return end
	if trbuff then
		local curtr = lp:GetEyeTrace().HitPos
		local strbuff = angbuff and scndbuff or curtr
		local absolute = NPCBox*math.Clamp(lp:GetTool():GetClientNumber('spread',20),MIN_SPREAD,MAX_SPREAD)/10
		local maxz = (trbuff.z > strbuff.z and trbuff.z or strbuff.z)
		local area = (strbuff-trbuff)
		local by_x, by_y = math.floor(math.abs(area.x)/absolute), math.floor(math.abs(area.y)/absolute)
		local sx, sy = area.x < 0 and -1 or 1, area.y < 0 and -1 or 1
		arx, ary = by_x, by_y
		local actbad = (by_x < 1 or by_y < 1)
		local secondpos = Vector(trbuff.x+by_x*absolute*sx,trbuff.y+by_y*absolute*sy,maxz)
		DrawArea(trbuff,angbuff and secondpos or curtr,mat_solid,actbad and mcol_bad or mcol_good)
		if !actbad then
			for i = 1, by_x+1 do
				local v1 = Vector(trbuff.x+absolute*(i-1)*sx,trbuff.y,maxz+r_renderoff)
				local v2 = Vector(trbuff.x+absolute*(i-1)*sx,trbuff.y+by_y*absolute*sy,maxz+r_renderoff)
				render.DrawLine(v1,v2,mcol_line,r_lines_writez)
			end
			for i = 1, by_y+1 do
				local v1 = Vector(trbuff.x,trbuff.y+absolute*(i-1)*sy,maxz+r_renderoff)
				local v2 = Vector(trbuff.x+by_x*absolute*sx,trbuff.y+absolute*(i-1)*sy,maxz+r_renderoff)
				render.DrawLine(v1,v2,mcol_line,r_lines_writez)
			end
		end
		if angbuff then
			local orig = Vector(trbuff.x+absolute*sx*by_x/2,trbuff.y+absolute*sy*by_y/2,maxz)
			yawlerp = Lerp(0.25,yawlerp,angbuff.y)
			local angsizelimit = math.min(by_x*absolute,by_y*absolute)
			DrawAngle(orig,yawlerp,angsizelimit,true)
		end
	end
	for _,at in ipairs(t_areas) do
		local absolute = NPCBox*at[5]/10
		local area = at[2]-at[1]
		local maxz = at[4]
		local by_x, by_y = math.floor(math.abs(area.x)/absolute), math.floor(math.abs(area.y)/absolute)
		local sx, sy = area.x < 0 and -1 or 1, area.y < 0 and -1 or 1
		DrawArea(Vector(at[1].x,at[1].y,maxz),Vector(at[1].x+absolute*by_x*sx,at[1].y+absolute*by_y*sy,maxz),mat_solid,mcol_completed)
		for i = 1, by_x+1 do
			local v1 = Vector(at[1].x+absolute*(i-1)*sx,at[1].y,maxz+r_renderoff)
			local v2 = Vector(at[1].x+absolute*(i-1)*sx,at[1].y+by_y*absolute*sy,maxz+r_renderoff)
			render.DrawLine(v1,v2,mcol_line,r_lines_writez)
		end
		for i = 1, by_y+1 do
			local v1 = Vector(at[1].x,at[1].y+absolute*(i-1)*sy,maxz+r_renderoff)
			local v2 = Vector(at[1].x+by_x*absolute*sx,at[1].y+absolute*(i-1)*sy,maxz+r_renderoff)
			render.DrawLine(v1,v2,mcol_line,r_lines_writez)
		end
		local orig = Vector(at[1].x+absolute*sx*by_x/2,at[1].y+absolute*sy*by_y/2,maxz)
		local angsizelimit = math.min(by_x*absolute,by_y*absolute)
		DrawAngle(orig,at[8],angsizelimit)
	end
end)

function TOOL:DrawToolScreen(width,height)
	surface.SetDrawColor(mcol_black)
	surface.DrawRect(0,0,width,height)
	if oldarcnt ~= #t_areas then
		oldarcnt = #t_areas
		arnpccnt = 0
		for k,v in ipairs(t_areas) do
			arnpccnt = arnpccnt + #v[3]
		end
	end
	local width_h = width/2
	local width_q = width/4
	local width_o = width/8
	local height_h = height/2
	surface.SetDrawColor(mcol_white.r,mcol_white.g,mcol_white.b,mcol_white.a)
    surface.DrawRect(0,height-72,width,2)
    surface.DrawRect(width_q-1,height-72,2,72)
	surface.DrawRect(width_h-1,height-72,2,72)
	surface.DrawRect(width_h,height-36-1,width,2)
	local sprd = self:GetClientNumber('spread')
	local rnd = self:GetClientNumber('random')
	local sprd_font = sprd >= 1000 and 'CTOOLS_NPC_40' or (sprd >= 100 and 'CTOOLS_NPC_48' or 'CTOOLS_NPC_64')
	local rnd_font = rnd >= 100 and 'CTOOLS_NPC_48' or 'CTOOLS_NPC_64'
	draw.SimpleText(sprd,sprd_font,width_o,height-48,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText('SPREAD','CTOOLS_NPC_16',width_o,height-16,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(rnd,rnd_font,width_q+width_o,height-48,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText('RANDOM','CTOOLS_NPC_16',width_q+width_o,height-16,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(arnpccnt..' NPCs','CTOOLS_NPC_32',width-width_q,height-56,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(oldarcnt..' Areas','CTOOLS_NPC_32',width-width_q,height-20,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(self:GetClientInfo('class'),'CTOOLS_NPC_32',width_h,24,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	if trbuff then
		draw.SimpleText(arx*ary,'CTOOLS_NPC_64',width_h,height_h-56,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText('NPC to be spawned','CTOOLS_NPC_24',width_h,height_h-48+32,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText('X','CTOOLS_NPC_56',width_h,height_h+20,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText(arx,'CTOOLS_NPC_64',width_q,height_h+20,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText(ary,'CTOOLS_NPC_64',width-width_q,height_h+20,mcol_prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	end
end

function TOOL.BuildCPanel(panel)
	panel:ClearControls()

	local form_flagsadd = vgui.Create('DForm',panel)
	form_flagsadd:SetExpanded(true)
	form_flagsadd:SetName('Spawn Flags Additional')
	function form_flagsadd:ReloadFlags(class)
		for k,v in ipairs(form_flagsadd:GetChildren()) do
			for k1,v1 in ipairs(v:GetChildren()) do
				if !v1.ToBeUpdated then continue end
				v1:Remove()
			end
		end
		local data_npc = t_npcs[class]
		if !npcflagsadd[data_npc.Class] then return end
		for k,v in SortedPairs(npcflagsadd[data_npc.Class]) do
			local fstr = 'SFA_'..data_npc.Class..'_'..k
			local check_flag = form_flagsadd:CheckBox(v,'ctools_npc_'..fstr)
			check_flag.OnChange = function(self,bool)
				GetConVar('ctools_npc_'..fstr):SetInt(bool and 1 or 0)
			end
			check_flag.ToBeUpdated = true
		end
	end

	local presetpanel = panel:AddControl('ComboBox', {MenuButton = 1, Folder = 'ctools_npc', Options = { [ '#preset.default' ] = ConVarsDefault }, CVars = table.GetKeys(ConVarsDefault)})
	

	local slider_spread = panel:NumSlider('Spread multiplier','ctools_npc_spread',MIN_SPREAD,MAX_SPREAD,0)
	slider_spread:SetHeight(20)
	local slider_random = panel:NumSlider('Randomness','ctools_npc_random',MIN_RANDOM,MAX_RANDOM,0)
	slider_random:SetHeight(20)

	entry_srchnpc = panel:TextEntry('Search NPC:')
	local list_selectnpc = vgui.Create('DListView',panel)
	list_selectnpc:SetHeight(160)
	panel:AddItem(list_selectnpc)
	list_selectnpc:SetMultiSelect(false)
	list_selectnpc:AddColumn('NPC Class')
	list_selectnpc.UpdateData = function(self,class)
		list_selectnpc:Clear()
		local filter = string.lower(entry_srchnpc:GetValue())
		local NpcList = {}
		for k,v in pairs(t_npcs) do
			local match_name = string.match(string.lower(v.Name),filter)
			local match_class = string.match(string.lower(v.Class),filter)
			if filter == '' or match_name or match_class then
				NpcList[#NpcList+1] = v.Name
			end
		end
		local selectedLine
		local currentClass = class or GetConVar('ctools_npc_class'):GetString()
		for k,v in SortedPairsByValue(NpcList) do
			local currentLine = list_selectnpc:AddLine(v)
			if currentClass ~= v then continue end
			selectedLine = currentLine
		end
		list_selectnpc.OnRowSelected = function(clist,rowid,row)
			if !row or !row.GetColumnText or !row:GetColumnText(1) then return end
			local class = row:GetColumnText(1)
			GetConVar('ctools_npc_class'):SetString(class)
			data_npc = t_npcs[class]
			NPCBox = npcboxtab[class] or npcboxtab._def
			if IsValid(form_flagsadd) and form_flagsadd.ReloadFlags then
				form_flagsadd:ReloadFlags(class)
			end
		end
		if selectedLine then
			list_selectnpc:SelectItem(selectedLine)
			local dath = list_selectnpc:GetDataHeight()
			local id = selectedLine:GetID()
			list_selectnpc.VBar:AnimateTo((id-1)*dath,0.25)
		end
	end
	list_selectnpc:UpdateData()
	entry_srchnpc:SetUpdateOnType(true)
	entry_srchnpc.OnValueChange = function()
		list_selectnpc:UpdateData()
	end

	local entry_srchwep = panel:TextEntry('Search Weapon:')
	local list_selectwep = vgui.Create('DListView',panel)
	list_selectwep:SetHeight(160)
	panel:AddItem(list_selectwep)
	list_selectwep:SetMultiSelect(false)
	list_selectwep:AddColumn('Weapon Class')
	list_selectwep.UpdateData = function(self,wep)
		list_selectwep:Clear()
		local line_nowep = list_selectwep:AddLine(str_nowep)
		local line_defwep = list_selectwep:AddLine(str_defwep)
		local filter = string.lower(entry_srchwep:GetValue())
		local weptab = {}
		for k,v in pairs(t_weps) do
			local match_name = string.match(string.lower(v.name),filter)
			local match_class = string.match(string.lower(v.class),filter)
			if filter == '' or match_name or match_class then
				weptab[#weptab+1] = v.name
			end
		end
		local selectedLine
		local curwep = wep or GetConVar('ctools_npc_equip'):GetString()
		for k,v in SortedPairsByValue(weptab) do
			local currentLine = list_selectwep:AddLine(v)
			if curwep ~= v then continue end
			selectedLine = currentLine
		end
		list_selectwep.OnRowSelected = function(clist,rowid,row)
			if row and row.GetColumnText and row:GetColumnText(1) then
				local selwep = row:GetColumnText(1)
				local weptouse = selwep == str_nowep and '' or selwep
				weptouse = weptouse == str_defwep and '_def' or weptouse
				GetConVar('ctools_npc_equip'):SetString(weptouse)
			end
		end
		if curwep == '' then
			selectedLine = line_nowep
		elseif curwep == '_def' then
			selectedLine = line_defwep
		end
		if selectedLine then
			list_selectwep:SelectItem(selectedLine)
			local dath = list_selectwep:GetDataHeight()
			local id = selectedLine:GetID()
			list_selectwep.VBar:AnimateTo((id-1)*dath,0.25)
		end
	end
	list_selectwep:UpdateData()
	entry_srchwep:SetUpdateOnType(true)
	entry_srchwep.OnValueChange = function()
		list_selectwep:UpdateData()
	end

	function presetpanel:OnSelect(index,value,data)
		if !data then return end
		list_selectnpc:UpdateData(data.ctools_npc_class)
		list_selectwep:UpdateData(data.ctools_npc_equip)
	end

	local combo_prof = panel:ComboBox('Proficiency','ctools_npc_wepprof')
	combo_prof:SetSortItems(false)
	function combo_prof.UpdateData()
		combo_prof:Clear()
		local currentProficiency = GetConVar('ctools_npc_wepprof'):GetInt()
		for k,v in pairs(wepprof) do
			local showDefault = false
			if currentProficiency == k then
				showDefault = true
			end
			combo_prof:AddChoice(v,k,showDefault)
		end
	end
	combo_prof:UpdateData()

	local entry_mdl = panel:TextEntry('Custom Model:','ctools_npc_model')
	local check_randskin = panel:CheckBox('Set random model skin on spawn','ctools_npc_skinrandom')
	check_randskin:SetHeight(20)
	local slider_skin = panel:NumSlider('Model Skin','ctools_npc_skin',0,31,0)
	slider_skin:SetHeight(20)
	local slider_hpstart = panel:NumSlider('Start Health','ctools_npc_hp',0,1000,0)
	slider_hpstart:SetHeight(20)
	local slider_hpmax = panel:NumSlider('Max Health','ctools_npc_maxhp',0,1000,0)
	slider_hpmax:SetHeight(20)
	local check_ignoreply = panel:CheckBox('Ignore me','ctools_npc_ignoreply')
	check_ignoreply:SetHeight(20)
	local check_ignoreplys = panel:CheckBox('Ignore all players','ctools_npc_ignoreplys')
	local check_immobile = panel:CheckBox('NPC can\'t move','ctools_npc_immobile')

	local form_flags = vgui.Create('DForm',panel)
	panel:AddItem(form_flags)
	form_flags:SetExpanded(true)
	form_flags:SetName('Spawn Flags')
	for k,v in SortedPairs(npcflags) do
		local fstr = 'SF_'..k
		local check_flag = form_flags:CheckBox(v,'ctools_npc_'..fstr)
		check_flag.OnChange = function(self,bool)
			GetConVar('ctools_npc_'..fstr):SetInt(bool and 1 or 0)
		end
		check_flag.UpdateData = function(this)
			check_flag:SetChecked(tobool(GetConVar('ctools_npc_'..fstr):GetInt()))
		end
		check_flag:UpdateData()
	end

	panel:AddItem(form_flagsadd)

end

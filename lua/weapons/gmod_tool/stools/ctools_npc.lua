TOOL.Category = 'Chromium Tools'
TOOL.Name = 'NPC Spawner'
TOOL.Command = nil
TOOL.ConfigName = ''
TOOL.Preset = 'Default'
TOOL.Information = {
	{name='left'},
	{name='right'},
	{name='reload'},
	{name='mscr',icon='gui/info'},
	{name='mscr2',icon='gui/info'},
}



if game.SinglePlayer() then
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
	else
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
end

if SERVER then return end




local net = net
local CurTime = CurTime
local ipairs = ipairs
local pairs = pairs
local math = math
local string = string
local cam = cam
local render = render
local surface = surface
local draw = draw




local mat_wireframe = CreateMaterial('cmat_wireframe','Wireframe')
local mat_solid = CreateMaterial('cmat_solid','UnlitGeneric',{['$basetexture'] = 'color/white',['$translucent'] = 1,['$vertexalpha'] = 1,['$vertexcolor'] = 1})
local tex_cornerin = Material('gui/corner512')
local tex_cornerout = Material('gui/sniper_corner')

local NPC_LIMIT = 1024
local MIN_SPREAD, MAX_SPREAD = 10, 1000
local MIN_RANDOM, MAX_RANDOM = 0, 100
local npcbox = 26+8
local r_lines_writez = false
local r_renderoff = 2
local r_rmksize = 512

local t_areas = {}
local t_npcs, t_weps
local data_npc, data_weps
local oldarcnt, arnpccnt = 0, 0
local trbuff, scndbuff, angbuff
local lp = NULL
local arx, ary = 0, 0
local spamtime = CurTime()
local yawlerp = Angle(0,0,0)
local angcent
local absolute_lerp = 0
local npccat_temp = 'Humans + Resistance'
local norm_f = Vector(0,0,1)
local vec_up = Vector(0,0,1)

local t_str = {
	notif_area = 'Not enough area!',
	notif_limit = 'The area is too large! Unhealthy amount of NPCs for the server',
	notif_exec = 'Executing (sending %sB of data...)',
	notif_undoareacur = 'Undone the current area!',
	notif_undoarealast = 'Undone last created area!',
	nowep = 'No weapon',
	defwep = 'Default weapon',
}

local t_col = {
	black = Color(16,16,24,255),
	white = Color(255,255,255,255),
	prewhite = Color(200,200,200,255),
	area_bad = Color(255,64,64,64),
	area_good = Color(64,255,92,64),
	area_placed = Color(128,192,255,64),
	line = Color(255,255,255,128),
	ang_body = Color(255,255,255,80),
	ang_arrow = Color(255,255,255,128),
}

local t_sound = {
	success = 'buttons/button14.wav',
	fail = 'buttons/button11.wav',
	exec = 'buttons/combine_button1.wav',
	undo = 'buttons/button15.wav',
	click_random = 'buttons/lever7.wav',
	click_spread = 'buttons/lightswitch2.wav',
}

local t_npcbox = {
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

local t_spawnmethods = {
	{'Default','NPCs will be spawned across the area (no respawning)'},
	{'Amount (respawn)','NPCs will respawn till total amount of X is reached'},
	{'Timer (respawn)','NPCs will respawn while the timer is active'},
}

local t_wepprof = {
	{8,'Default'},
	{WEAPON_PROFICIENCY_POOR, 'Poor'},
	{WEAPON_PROFICIENCY_AVERAGE, 'Average'},
	{WEAPON_PROFICIENCY_GOOD, 'Good'},
	{WEAPON_PROFICIENCY_VERY_GOOD, 'Very good'},
	{WEAPON_PROFICIENCY_PERFECT, 'Perfect'},
	{5, 'Random'},
	{6, 'Random good'},
	{7, 'Random bad'},
}

local t_npcflags = {
	{512,	'Fade corpse on death'},
	{8192,	'Don\'t drop weapons on death'},
	{8,		'Drop healthkit on death'},
	{256,	'Increase visibility and shoot distance'},
	{16384,	'[PHYS] Ignore player push'},
	{4096,	'[PHYS] Alternate collision (don\'t avoid players)'},
	{1,		'[IDLE] Remain idle till seen'},
	{2,		'[IDLE] Make no idle sounds until angry'},
	{16,	'[IDLE] Don\'t acquire enemies or avoid obstacles'},
	{128,	'[DEV] Wait for script'},
	{4,		'[DEV] Fall to ground instead of teleporting'},
	{1024,	'[DEV] Think outside PVS'},
	{2048,	'[DEV] Template NPC'},
}

local t_npcflagsadd = {
	npc_citizen = {
		[65536] = 'Follow player on spawn',
		[131072] = 'Medic',
		[262144] = 'Random head',
		[524288] = 'Ammo resupplier',
		[1048576] = 'Not commandable (cannot join players squad)',
		[4194304] = 'Random male head',
		[8388608] = 'Random female head',
		[16777216] = 'Use render bounds instead of human hull (for NPCs sitting in chairs, etc.)',
		[2097152] = 'Work outside the speech semaphore system',
	},
	npc_rollermine = {
		[65536] = 'Friendly',
	},
	npc_turret_floor = {
		[512] = 'Friendly',
	},
}




TOOL.ClientConVar['npccat'] = 'Humans + Resistance'
TOOL.ClientConVar['class'] = 'Citizen'
TOOL.ClientConVar['spread'] = 20
TOOL.ClientConVar['random'] = 0
TOOL.ClientConVar['yaw'] = 0
TOOL.ClientConVar['equip'] = '_def'
TOOL.ClientConVar['model'] = ''
TOOL.ClientConVar['skin'] = 0
TOOL.ClientConVar['wepprof'] = 2
TOOL.ClientConVar['ignoreply'] = 0
TOOL.ClientConVar['ignoreplys'] = 0
TOOL.ClientConVar['immobile'] = 0
TOOL.ClientConVar['squad'] = ''
TOOL.ClientConVar['maxhp'] = 0
TOOL.ClientConVar['hp'] = 0
TOOL.ClientConVar['sm_method'] = 1
TOOL.ClientConVar['sm_removal'] = 1
TOOL.ClientConVar['sm_respdelay'] = 0
TOOL.ClientConVar['sm_alive'] = 0
TOOL.ClientConVar['sm_total'] = 0
TOOL.ClientConVar['sm_timer'] = 0
TOOL.ClientConVar['sm_random'] = 1

for k,v in ipairs(t_npcflags) do
	TOOL.ClientConVar['SF_'..v[1]] = 0
end
-- Force SF_NPC_ALWAYSTHINK and SF_NPC_FADE_CORPSE flags
TOOL.ClientConVar['SF_512'] = 1
TOOL.ClientConVar['SF_1024'] = 1

for k,v in pairs(t_npcflagsadd) do
	for k1,v1 in SortedPairs(v) do
		TOOL.ClientConVar['SFA_'..k..'_'..k1] = 0
	end
end

local ConVarsDefault = TOOL:BuildConVarList()

language.Add('tool.ctools_npc.name','Chromium NPC Spawner')
language.Add('tool.ctools_npc.desc','Simple and flexible NPC Spawner Tool')
language.Add('tool.ctools_npc.left','Create a new spawn area')
language.Add('tool.ctools_npc.right','Request execution of created spawn areas')
language.Add('tool.ctools_npc.reload','Remove last created spawn area or undo the current one')
language.Add('tool.ctools_npc.mscr','Scroll up/down to increase/decrease spread multiplier when creating an area')
language.Add('tool.ctools_npc.mscr2','Hold Shift key when scrolling to change randomness instead')

local font = 'Staatliches Regular'
local t_fonts = {
	num_1 = 40,
	num_2 = 56,
	num_3 = 72,
	num_4 = 80,
	str_csleft = 28,
	str_cxright = 32,
	str_cxnum = 28,
	str_cxx = 48,
	str_class = 32,
}

for id,size in pairs(t_fonts) do
	local f_str = 'ctools_npc_'..size
	surface.CreateFont(f_str,{font = font,size = size})
	t_fonts[id] = f_str
end




function TOOL:LeftClick(trace)
	if spamtime+0.1 > CurTime() then return false end
	local npccat = self:GetClientInfo('npccat') ~= 'All' and self:GetClientInfo('npccat') or npccat_temp
	local class = self:GetClientInfo('class')
	npcbox = t_npcbox[class] or t_npcbox._def
	trace = trace or lp:GetEyeTrace()
	spamtime = CurTime()
	if trbuff then
		local absolute = npcbox*math.Clamp(self:GetClientNumber('spread',20),MIN_SPREAD,MAX_SPREAD)/10
		local maxz = trbuff.z > trace.HitPos.z and trbuff.z or trace.HitPos.z
		local maxz = angbuff and (trbuff.z > scndbuff.z and trbuff.z or scndbuff.z) or trbuff.z
		local area = ((angbuff and scndbuff or trace.HitPos)-trbuff)
		local by_x = math.floor(math.abs(area.x)/absolute)
		local by_y = math.floor(math.abs(area.y)/absolute)
		if by_x < 1 or by_y < 1 then
			notification.AddLegacy(t_str.notif_area,NOTIFY_ERROR,2)
			surface.PlaySound(t_sound.fail)
			trbuff = nil
			angbuff = nil
			return false
		end
		local npc_cnt = by_x*by_y
		local sm_method = self:GetClientNumber('sm_method',1)
		local sm_total = self:GetClientNumber('sm_total',0)
		local sm_alive = self:GetClientNumber('sm_alive',0)
		local npc_total = sm_method == 2 and (sm_total ~= 0 and sm_total or npc_cnt) or npc_cnt
		local npc_alive = sm_method ~= 1 and (sm_alive ~= 0 and sm_alive or npc_cnt) or npc_cnt
		if !(npc_total < NPC_LIMIT or npc_alive < NPC_LIMIT or npc_cnt < NPC_LIMIT) then
			notification.AddLegacy(t_str.notif_limit,NOTIFY_ERROR,2)
			surface.PlaySound(t_sound.fail)
			trbuff = nil
			angbuff = nil
			return false
		end
		if !angbuff then
			angcent = nil
			angbuff = true
			scndbuff = lp:GetEyeTrace().HitPos
			surface.PlaySound(t_sound.success)
			return false
		end

		local flags = 0
		for k,v in ipairs(t_npcflags) do
			if self:GetClientNumber('SF_'..v[1],0) ~= 0 then
				flags = bit.bor(flags,v[1])
			end
		end
		local data_npc = t_npcs[npccat][class]
		if t_npcflagsadd[data_npc.Class] then
			for k,v in SortedPairs(t_npcflagsadd[data_npc.Class]) do
				local nullflag = bit.bnot(k)
				flags = bit.band(flags,nullflag)
				if self:GetClientNumber('SFA_'..data_npc.Class..'_'..k,0) ~= 0 then
					flags = bit.bor(flags,k)
				end
			end
		end

		local sm_method = self:GetClientNumber('sm_method',1)
		local random = math.Clamp(self:GetClientNumber('random',0),MIN_RANDOM,MAX_RANDOM)
		local rand_calc = ((absolute-npcbox/2)/2*random/100)
		local equip = self:GetClientInfo('equip')
		t_areas[#t_areas+1] = {
			pos_start = trbuff,
			pos_end = scndbuff,
			spread = math.Clamp(self:GetClientNumber('spread',20),MIN_SPREAD,MAX_SPREAD),
			random = rand_calc,
			npccat = npccat,
			class = class,
			angle = angbuff,
			flags = flags,
			equip = (equip and equip ~= '') and ((equip == '_def') and equip or (t_weps[equip] and t_weps[equip].class)) or nil,
			model = #self:GetClientInfo('model') > 4 and self:GetClientInfo('model') or nil,
			skin = self:GetClientNumber('skin',0),
			prof = self:GetClientNumber('wepprof',2),
			ignoreply = self:GetClientNumber('ignoreply',0) == 1 and true or nil,
			ignoreplys = self:GetClientNumber('ignoreplys',0) == 1 and true or nil,
			immobile = self:GetClientNumber('immobile',0) == 1 and true or nil,
			squad = (#self:GetClientInfo('squad') > 0 and self:GetClientInfo('squad') ~= '') and self:GetClientInfo('squad') or nil,
			hp = self:GetClientNumber('hp',100) ~= 0 and self:GetClientNumber('hp',100) or nil,
			maxhp = self:GetClientNumber('maxhp',100) ~= 0 and self:GetClientNumber('maxhp',100) or nil,
			npcbox = npcbox,
			sm_method = sm_method,
			sm_removal = self:GetClientNumber('sm_removal',1) == 1 and true or nil,
			sm_respdelay = self:GetClientNumber('sm_respdelay',0) ~= 0 and self:GetClientNumber('sm_respdelay',0) or nil,
			sm_alive = sm_method ~= 1 and self:GetClientNumber('sm_alive',0) or nil,
			sm_total = sm_method == 2 and self:GetClientNumber('sm_total',0) or nil,
			sm_timer = sm_method == 3 and self:GetClientNumber('sm_timer',0) or nil,
			sm_random = self:GetClientNumber('sm_random',1) ~= 0,
			maxz = maxz,
			abs = absolute,
			by_x = by_x,
			by_y = by_y,
			ssx = trbuff.x < scndbuff.x and 1 or -1,
			ssy = trbuff.y < scndbuff.y and 1 or -1,
			norm = norm_f:Dot(vec_up) > 0 and trace.HitNormal:Dot(vec_up) > 0
		}

		trbuff = nil
		angbuff = nil
		surface.PlaySound(t_sound.success)
		return false
	end
	trbuff = trace.HitPos
	norm_f = trace.HitNormal
	surface.PlaySound(t_sound.success)
	return false
end

function TOOL:RightClick(trace)
	if spamtime+0.1 > CurTime() then return false end
	trace = trace or lp:GetEyeTrace()
	spamtime = CurTime()
	if trbuff and angbuff then return false end
	if trbuff then
		trbuff = nil
		surface.PlaySound(t_sound.success)
		return false
	end
	if !t_areas[1] then return false end

	local bytes = 0
	local data = util.Compress(util.TableToJSON(t_areas))
	net.Start('ctnpces')
		net.WriteUInt(#data,32)
		net.WriteData(data,#data)
		bytes = net.BytesWritten()
	net.SendToServer()

	notification.AddLegacy(string.format(t_str.notif_exec,bytes),NOTIFY_GENERIC,2)
	surface.PlaySound(t_sound.exec)

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
		surface.PlaySound(t_sound.undo)
		notification.AddLegacy(t_str.notif_undoareacur,NOTIFY_UNDO,2)
		return false
	end
	if t_areas[#t_areas] then
		t_areas[#t_areas] = nil
		surface.PlaySound(t_sound.undo)
		notification.AddLegacy(t_str.notif_undoarealast,NOTIFY_UNDO,2)
		return false
	end
end

function TOOL:Deploy()
	
end

function TOOL:Holster()
	trbuff = nil
	angbuff = nil
end

function TOOL:DrawToolScreen(width,height)
	surface.SetDrawColor(t_col.black)
	surface.DrawRect(0,0,width,height)
	if oldarcnt ~= #t_areas then
		oldarcnt = #t_areas
		arnpccnt = 0
		for k,v in ipairs(t_areas) do
			arnpccnt = arnpccnt + v.by_x*v.by_y
		end
	end
	local width_h = width/2
	local width_q = width/4
	local width_o = width/8
	local height_h = height/2
	
	local btop = 72
	surface.SetDrawColor(t_col.white.r,t_col.white.g,t_col.white.b,t_col.white.a)
    surface.DrawRect(0,height-btop,width,2)
    surface.DrawRect(width_q-1,height-btop,2,btop)
	surface.DrawRect(width_h-1,height-btop,2,btop)
	surface.DrawRect(width_h,height-btop/2-1,width,2)
	local sprd = self:GetClientNumber('spread')
	local rnd = self:GetClientNumber('random')
	local sprd_font = sprd >= 1000 and t_fonts.num_1 or (sprd >= 100 and t_fonts.num_2 or t_fonts.num_3)
	local rnd_font = rnd >= 100 and t_fonts.num_2 or t_fonts.num_3
	draw.SimpleText(sprd,sprd_font,width_o,height-44,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText('SPREAD',t_fonts.str_csleft,width_o,height-12,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(rnd,rnd_font,width_q+width_o,height-44,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText('RANDOM',t_fonts.str_csleft,width_q+width_o,height-12,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(arnpccnt..' NPCs',t_fonts.str_cxright,width-width_q,height-54,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(oldarcnt..' Areas',t_fonts.str_cxright,width-width_q,height-18,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(self:GetClientInfo('class'),t_fonts.str_class,width_h,24,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	if trbuff then
		draw.SimpleText(arx*ary,t_fonts.num_4,width_h,height_h-52,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText('NPCs to be spawned',t_fonts.str_cxnum,width_h,height_h-12,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText('X',t_fonts.str_cxx,width_h,height-btop-32,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText(arx,t_fonts.num_4,width_q,height-btop-32,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText(ary,t_fonts.num_4,width-width_q,height-btop-32,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	end
end

function TOOL.BuildCPanel(panel)

	local form_flagsadd = vgui.Create('DForm')
	form_flagsadd:SetExpanded(true)
	form_flagsadd:SetName('Spawn Flags Additional')
	function form_flagsadd:ReloadFlags(npccat,class)
		for k,v in ipairs(form_flagsadd:GetChildren()) do
			for k1,v1 in ipairs(v:GetChildren()) do
				if !v1.ToBeUpdated then continue end
				v1:Remove()
			end
		end
		local data_npc = t_npcs[npccat][class]
		if !t_npcflagsadd[data_npc.Class] then return end
		local help_ms = form_flagsadd:ControlHelp('Additional flags, specific for '..data_npc.Class)
		help_ms.ToBeUpdated = true
		for k,v in SortedPairs(t_npcflagsadd[data_npc.Class]) do
			local fstr = 'SFA_'..data_npc.Class..'_'..k
			local check_flag = form_flagsadd:CheckBox(v,'ctools_npc_'..fstr)
			check_flag.OnChange = function(self,bool)
				GetConVar('ctools_npc_'..fstr):SetInt(bool and 1 or 0)
			end
			check_flag.ToBeUpdated = true
		end
	end


	local presetpanel = panel:AddControl('ComboBox', {MenuButton = 1, Folder = 'ctools_npc', Options = {['#preset.default'] = ConVarsDefault}, CVars = table.GetKeys(ConVarsDefault)})
	
	local slider_spread = panel:AddControl('slider', {label = 'Spread multiplier', command = 'ctools_npc_spread', min = MIN_SPREAD, max = MAX_SPREAD})
	slider_spread:SetHeight(20)
	local slider_random = panel:NumSlider('Randomness','ctools_npc_random',MIN_RANDOM,MAX_RANDOM,0)
	slider_random:SetHeight(20)


	local method_list = vgui.Create('DForm',panel)
	panel:AddItem(method_list)
	method_list:SetName('NPC Spawn Method')
	method_list.addpanels = {}

	function method_list:MakeAdditional(sm)
		for k,v in ipairs(method_list.addpanels) do
			v:Remove()
		end
		if sm == 1 then return end
		local check_removal = method_list:CheckBox('Remove spawned NPCs on removal','ctools_npc_sm_removal')
		check_removal:SetHeight(20)
		method_list.addpanels[#method_list.addpanels+1] = check_removal
		
		local slider_respdel = method_list:NumSlider('Respawn delay','ctools_npc_sm_respdelay',0,30,0)
		slider_respdel:SetHeight(20)
		method_list.addpanels[#method_list.addpanels+1] = slider_respdel

		local st_str = sm == 3 and 'Timer (in seconds)' or 'Total NPC amount'
		local st_cvar = sm == 3 and 'ctools_npc_sm_timer' or 'ctools_npc_sm_total'
		local st_maxval = sm == 3 and 60 or 100
		local slider_total = method_list:NumSlider(st_str,st_cvar,0,st_maxval,0)
		slider_total:SetHeight(20)
		local textarea = slider_total:GetTextArea()
		function textarea:OnValueChange(str)
			if str ~= '0' then return end
			textarea:SetText('Infinite')
		end
		method_list.addpanels[#method_list.addpanels+1] = slider_total

		local slider_alive = method_list:NumSlider('Maximum alive NPCs','ctools_npc_sm_alive',0,100,0)
		slider_alive:SetHeight(20)
		local textarea = slider_alive:GetTextArea()
		function textarea:OnValueChange(str)
			if str ~= '0' then return end
			textarea:SetText('Area size')
		end
		method_list.addpanels[#method_list.addpanels+1] = slider_alive
	end

	method_list.UpdateData = function(self,class)
		local help_method

		local method = method_list:ComboBox('Method','ctools_npc_sm_method')
		method:SetMinimumSize(nil,20)
		method:SetSortItems(false)
		
		local cursm = GetConVar('ctools_npc_sm_method'):GetInt()
		for k,v in ipairs(t_spawnmethods) do
			method:AddChoice(v[1],k,cursm == v[1])
		end
		function method:OnSelect(index,value,data)
			-- Why the fuck doesn't it work without SetInt???
			GetConVar('ctools_npc_sm_method'):SetInt(data)
			help_method:SetText(t_spawnmethods[data][2])
			method_list:MakeAdditional(data)
		end

		help_method = method_list:ControlHelp(t_spawnmethods[cursm or 1][2])

		local check_randomize = method_list:CheckBox('Randomize spawn','ctools_npc_sm_random')
		check_randomize:SetHeight(20)

		method_list:MakeAdditional(cursm)
	end

	method_list:UpdateData()
	method_list:InvalidateLayout(true)
	method_list:SetExpanded(true)
	method_list:SizeToChildren(false,true)
	panel:AddItem(method_list)




	local entry_srchnpc

	local list_selectnpc = vgui.Create('DListView',panel)
	list_selectnpc:SetHeight(17*10)
	list_selectnpc:SetMultiSelect(false)
	local column_name = list_selectnpc:AddColumn('Name')
	local column_class = list_selectnpc:AddColumn('Class')
	column_class:SetFixedWidth(100)
	list_selectnpc.UpdateData = function(self,npccat,class)
		npccat = npccat or GetConVar('ctools_npc_npccat'):GetString()
		local oldclass = GetConVar('ctools_npc_class'):GetString()
		list_selectnpc:Clear()
		local filter = string.lower(entry_srchnpc:GetValue())
		local NpcList = {}
		local classfound = false
		if npccat == 'All' then
			for cat,ct in pairs(t_npcs) do
				for k,v in pairs(ct) do
					local match_name = string.match(string.lower(v.Name),filter)
					local match_class = string.match(string.lower(v.Class),filter)
					if !classfound and v.Name == oldclass then
						classfound = true
					end
					if filter == '' or match_name or match_class then
						NpcList[#NpcList+1] = {v.Name,v.Class,v.Category}
					end
				end
			end
		else
			for k,v in pairs(t_npcs[npccat]) do
				local match_name = string.match(string.lower(v.Name),filter)
				local match_class = string.match(string.lower(v.Class),filter)
				if !classfound and v.Name == oldclass then
					classfound = true
				end
				if filter == '' or match_name or match_class then
					NpcList[#NpcList+1] = {v.Name,v.Class}
				end
			end
		end
		
		if !classfound then
			for k,v in SortedPairsByMemberValue(NpcList,1) do
				GetConVar('ctools_npc_class'):SetString(v[1])
				break
			end
		end
		
		local selectedLine
		class = class or GetConVar('ctools_npc_class'):GetString()
		for k,v in SortedPairsByMemberValue(NpcList,1) do
			local currentLine = list_selectnpc:AddLine(v[1],v[2])
			currentLine.npccat = v[3] or npccat
			if class ~= v[1] then continue end
			selectedLine = currentLine
		end
		list_selectnpc.OnRowSelected = function(clist,rowid,row)
			if !row or !row.GetColumnText or !row:GetColumnText(1) then return end
			local class = row:GetColumnText(1)
			npccat_temp = row.npccat
			GetConVar('ctools_npc_class'):SetString(class)
			data_npc = t_npcs[npccat_temp][class]
			npcbox = t_npcbox[class] or t_npcbox._def
			if IsValid(form_flagsadd) and form_flagsadd.ReloadFlags then
				form_flagsadd:ReloadFlags(npccat_temp,class)
			end
		end
		if selectedLine then
			list_selectnpc:SelectItem(selectedLine)
			local dath = list_selectnpc:GetDataHeight()
			local id = selectedLine:GetID()
			list_selectnpc.VBar:AnimateTo((id-1)*dath,0.25)
		end
	end
	


	local combo_npccat = panel:ComboBox('Category','ctools_npc_npccat')
	combo_npccat:SetMinimumSize(nil,20)
	combo_npccat:SetSortItems(false)
	function combo_npccat.UpdateData()
		combo_npccat:Clear()
		local curnpccat = GetConVar('ctools_npc_npccat'):GetString()
		combo_npccat:AddChoice('All','All',curnpccat == 'All')
		for cat,v in pairs(t_npcs) do
			combo_npccat:AddChoice(cat,cat,curnpccat == cat)
		end
	end
	function combo_npccat:OnSelect(index,value,data)
		GetConVar('ctools_npc_npccat'):SetString(data)
		entry_srchnpc:SetValue('')
		list_selectnpc:UpdateData(data)
	end

	entry_srchnpc = panel:TextEntry('NPC Filter')
	entry_srchnpc:SetPlaceholderText('Name or Class')
	entry_srchnpc:SetUpdateOnType(true)
	entry_srchnpc.OnValueChange = function()
		list_selectnpc:UpdateData()
	end

	panel:AddItem(list_selectnpc)

	combo_npccat:UpdateData()
	--list_selectnpc:UpdateData()

	local entry_srchwep = panel:TextEntry('Weapon Filter')
	entry_srchwep:SetPlaceholderText('Name or Class')
	
	local list_selectwep = vgui.Create('DListView',panel)
	list_selectwep:SetHeight(17*10)
	panel:AddItem(list_selectwep)
	list_selectwep:SetMultiSelect(false)
	list_selectwep:AddColumn('Name')
	local column_class = list_selectwep:AddColumn('Class')
	column_class:SetFixedWidth(100)
	list_selectwep.UpdateData = function(self,wep)
		list_selectwep:Clear()
		local line_nowep = list_selectwep:AddLine(t_str.nowep)
		local line_defwep = list_selectwep:AddLine(t_str.defwep)
		local filter = string.lower(entry_srchwep:GetValue())
		local weptab = {}
		for k,v in pairs(t_weps) do
			local match_name = string.match(string.lower(v.name),filter)
			local match_class = string.match(string.lower(v.class),filter)
			if filter == '' or match_name or match_class then
				weptab[#weptab+1] = {v.name,v.class}
			end
		end
		local selectedLine
		local curwep = wep or GetConVar('ctools_npc_equip'):GetString()
		for k,v in SortedPairsByMemberValue(weptab,1) do
			local currentLine = list_selectwep:AddLine(v[1],v[2])
			if curwep ~= v[1] then continue end
			selectedLine = currentLine
		end
		list_selectwep.OnRowSelected = function(clist,rowid,row)
			if row and row.GetColumnText and row:GetColumnText(1) then
				local selwep = row:GetColumnText(1)
				local weptouse = selwep == t_str.nowep and '' or selwep
				weptouse = weptouse == t_str.defwep and '_def' or weptouse
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
		list_selectnpc:UpdateData(data.ctools_npc_npccat,data.ctools_npc_class)
		list_selectwep:UpdateData(data.ctools_npc_equip)
	end

	local combo_prof = panel:ComboBox('Proficiency','ctools_npc_wepprof')
	combo_prof:SetMinimumSize(nil,20)
	combo_prof:SetSortItems(false)
	function combo_prof.UpdateData()
		combo_prof:Clear()
		local curprof = GetConVar('ctools_npc_wepprof'):GetInt()
		for k,v in ipairs(t_wepprof) do
			combo_prof:AddChoice(v[2],v[1],curprof == v[1])
		end
	end
	combo_prof:UpdateData()

	local entry_mdl = panel:TextEntry('Custom Model:','ctools_npc_model')
	entry_mdl:SetPlaceholderText('Example: "models/some_model.mdl"')
	local entry_squad = panel:TextEntry('Custom Squad:','ctools_npc_squad')
	entry_squad:SetPlaceholderText('Internal var for making NPC squads')
	local slider_skin = panel:NumSlider('Model Skin','ctools_npc_skin',0,8,0)
	slider_skin:SetHeight(20)
	local textarea = slider_skin:GetTextArea()
	function textarea:OnValueChange(str)
		if str == '0' then
			textarea:SetText('Default')
		elseif str == '1' then
			textarea:SetText('Random')
		end
	end
	local slider_hpstart = panel:NumSlider('Start Health','ctools_npc_hp',0,100,0)
	slider_hpstart:SetHeight(20)
	local textarea = slider_hpstart:GetTextArea()
	function textarea:OnValueChange(str)
		if str ~= '0' then return end
		textarea:SetText('Default')
	end
	local slider_hpmax = panel:NumSlider('Max Health','ctools_npc_maxhp',0,100,0)
	slider_hpmax:SetHeight(20)
	local textarea = slider_hpmax:GetTextArea()
	function textarea:OnValueChange(str)
		if str ~= '0' then return end
		textarea:SetText('Default')
	end
	local check_ignoreply = panel:CheckBox('Ignore me','ctools_npc_ignoreply')
	local check_ignoreplys = panel:CheckBox('Ignore all players','ctools_npc_ignoreplys')
	local check_immobile = panel:CheckBox('NPC can\'t move','ctools_npc_immobile')

	local form_flags = vgui.Create('DForm',panel)
	panel:AddItem(form_flags)
	form_flags:SetExpanded(false)
	form_flags:SetName('Spawn Flags')
	for k,v in ipairs(t_npcflags) do
		local fstr = 'SF_'..v[1]
		local check_flag = form_flags:CheckBox(v[2],'ctools_npc_'..fstr)
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




local function DrawArea(vec1,vec2,mat,col,norm)
	local minx = vec1.x < vec2.x and vec1.x or vec2.x
	local maxx = vec1.x > vec2.x and vec1.x or vec2.x
	local miny = vec1.y < vec2.y and vec1.y or vec2.y
	local maxy = vec1.y > vec2.y and vec1.y or vec2.y
	local maxz = vec1.z > vec2.z and vec1.z or vec2.z
	norm = norm and r_renderoff or -r_renderoff
	local v1 = Vector(minx,miny,maxz+norm)
	local v2 = Vector(minx,maxy,maxz+norm)
	local v3 = Vector(maxx,maxy,maxz+norm)
	local v4 = Vector(maxx,miny,maxz+norm)
	render.SetMaterial(mat)
	render.DrawQuad(v1,v2,v3,v4,col)
	render.DrawQuad(v4,v3,v2,v1,col)
end

local function DrawAngle(pos,ang,sizelimit,ignorez,norm)
	local size = r_rmksize
	if sizelimit and sizelimit < r_rmksize*2 then
		size = sizelimit/2
	end
	local lpunder = lp:GetShootPos().z < pos.z
	local ar = lpunder and 180 or 0
	local yadd = lpunder and -90 or 0
	cam.Start3D2D(pos+Vector(0,0,norm and r_renderoff or -r_renderoff),ang+Angle(0,-135+yadd,ar),1)
		if ignorez then cam.IgnoreZ(true) end
			render.PushFilterMag(TEXFILTER.ANISOTROPIC)
			render.PushFilterMin(TEXFILTER.ANISOTROPIC)
				surface.SetDrawColor(t_col.ang_body.r,t_col.ang_body.g,t_col.ang_body.b,t_col.ang_body.a)
				surface.SetMaterial(tex_cornerin)
				surface.DrawTexturedRectUV(-size,0-size,size,size,0,0,1,1)
				surface.DrawTexturedRectUV(0,-size,size,size,1,0,0,1)
				surface.DrawTexturedRectUV(-size,0,size,size,0,1,1,0)
				surface.DrawTexturedRectUV(0,0,size,size,1,1,0,0)
				surface.SetDrawColor(t_col.ang_arrow.r,t_col.ang_arrow.g,t_col.ang_arrow.b,t_col.ang_arrow.a)
				surface.SetMaterial(tex_cornerout)
				surface.DrawTexturedRect(-size,-size,size,size)
			render.PopFilterMag()
			render.PopFilterMin()
		if ignorez then cam.IgnoreZ(false) end
	cam.End3D2D()
end

local function ToolInit()
	lp = LocalPlayer()
	t_npcs = {}
	local npctab = list.Get('NPC')
	for k,v in pairs(npctab) do
		if !t_npcs[v.Category] then
			t_npcs[v.Category] = {}
		end
		t_npcs[v.Category][v.Name] = v
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
	local cvar_cat = GetConVar('ctools_npc_npccat')
	local cvar_class = GetConVar('ctools_npc_class')
	local cvar_equip = GetConVar('ctools_npc_equip')
	local cv_cat = cvar_cat:GetString()
	if !t_npcs[cv_cat] and cv_cat ~= 'All' then
		cvar_cat:SetString('Humans + Resistance')
		cvar_class:SetString('Citizen')
	end
	local cv_class = cvar_class:GetString()
	if cvar_cat:GetString() ~= 'All' then
		if !t_npcs[cvar_cat:GetString()][cv_class] then
			cvar_cat:SetString('Humans + Resistance')
			cvar_class:SetString('Citizen')
		end
	else
		local found = false
		for cat,ct in pairs(t_npcs) do
			if ct[cv_class] then
				found = true
				break
			end
		end
		if !found then
			cvar_class:SetString('Citizen')
		end
	end
	local cv_equip = cvar_equip:GetString()
	if !t_weps[cv_equip] and cv_equip ~= '' and cv_equip ~= '_def' then
		cvar_equip:SetString('_def')
	end
end

local function PreventBind(ply,bind)
	if !trbuff then return end
	local wep = ply:GetActiveWeapon()
	if !IsValid(wep) or wep:GetClass() ~= 'gmod_tool' then return end
	if ply:GetTool().Mode ~= 'ctools_npc' then return end
	if input.IsMouseDown(MOUSE_WHEEL_DOWN) and input.LookupKeyBinding(MOUSE_WHEEL_DOWN) == bind then return true end
	if input.IsMouseDown(MOUSE_WHEEL_UP) and input.LookupKeyBinding(MOUSE_WHEEL_UP) == bind then return true end
end

local function ControlMouseWheel(cmd)
	if !trbuff then return end
	local nullcmdnum = cmd:CommandNumber() == 0
	local scrollup = input.WasMousePressed(MOUSE_WHEEL_UP) and nullcmdnum
	local scrolldown = input.WasMousePressed(MOUSE_WHEEL_DOWN) and nullcmdnum
	local shiftdown = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
	if !scrollup and !scrolldown then return end
	local nmin, nmax
	local var, cvar
	local step = scrolldown and -2 or 2
	if shiftdown then
		var = GetConVar('ctools_npc_random')
		cvar = lp:GetTool():GetClientNumber('random',0)
		nmin, nmax = MIN_RANDOM, MAX_RANDOM
		if var:GetInt() > MIN_RANDOM and var:GetInt() < MAX_RANDOM then
			EmitSound(t_sound.click_random,Vector(0,0,0),-2,CHAN_AUTO,0.25,75,0,255,0)
		end
	else
		var = GetConVar('ctools_npc_spread')
		cvar = lp:GetTool():GetClientNumber('spread',20)
		nmin, nmax = MIN_SPREAD, MAX_SPREAD
		if var:GetInt() > MIN_SPREAD and var:GetInt() < MAX_SPREAD then
			EmitSound(t_sound.click_spread,Vector(0,0,0),-2,CHAN_AUTO,0.25,75,0,255,0)
		end
	end
	if !var then return end
	var:SetInt(math.Clamp(cvar+step,nmin,nmax))
end

local function DrawVisuals(bDepth,bSkybox)
	if bSkybox then return end
	if !IsValid(lp) then return end
	if !IsValid(lp:GetActiveWeapon()) then return end
	if lp:GetActiveWeapon():GetClass() ~= 'gmod_tool' then return end
	if !lp:GetTool() or lp:GetTool():GetMode() ~= 'ctools_npc' then return end
	if trbuff then
		local lptr = lp:GetEyeTrace()
		local curtr = lptr.HitPos
		local strbuff = angbuff and scndbuff or curtr
		local absolute = npcbox*math.Clamp(lp:GetTool():GetClientNumber('spread',20),MIN_SPREAD,MAX_SPREAD)/10
		local maxz = (trbuff.z > strbuff.z and trbuff.z or strbuff.z)
		local area = (strbuff-trbuff)
		local by_x = math.floor(math.abs(area.x)/absolute)
		local by_y = math.floor(math.abs(area.y)/absolute)
		local sx, sy = area.x < 0 and -1 or 1, area.y < 0 and -1 or 1
		arx, ary = by_x, by_y
		absolute_lerp = Lerp(0.2,absolute_lerp,absolute)
		local col_area = (by_x < 1 or by_y < 1) and t_col.area_bad or t_col.area_good
		local secondpos = Vector(trbuff.x+by_x*absolute*sx,trbuff.y+by_y*absolute*sy,maxz)
		local norm = norm_f:Dot(vec_up) > 0 and lptr.HitNormal:Dot(vec_up) > 0
		DrawArea(trbuff,angbuff and secondpos or curtr,mat_solid,col_area,norm)
		local lx, ly = math.max(by_x,1), math.max(by_y,1)
		local lineoff = norm and r_renderoff or -r_renderoff
		for i = 1, lx+1 do
			local v1 = Vector(trbuff.x+absolute_lerp*(i-1)*sx,trbuff.y,maxz+lineoff)
			local v2 = Vector(trbuff.x+absolute_lerp*(i-1)*sx,trbuff.y+ly*absolute_lerp*sy,maxz+lineoff)
			render.DrawLine(v1,v2,t_col.line,r_lines_writez)
		end
		for i = 1, ly+1 do
			local v1 = Vector(trbuff.x,trbuff.y+absolute_lerp*(i-1)*sy,maxz+lineoff)
			local v2 = Vector(trbuff.x+lx*absolute_lerp*sx,trbuff.y+absolute_lerp*(i-1)*sy,maxz+lineoff)
			render.DrawLine(v1,v2,t_col.line,r_lines_writez)
		end
		if angbuff then
			if !angcent then
				angcent = Vector(trbuff.x+absolute*sx*by_x/2,trbuff.y+absolute*sy*by_y/2,maxz)
			end
			local anghitpos = util.IntersectRayWithPlane(lptr.StartPos,lptr.Normal,angcent,vec_up)
			local ang = ((anghitpos or curtr)-angcent):Angle()
			angbuff = Angle(0,math.floor((ang.y+7.5)/15)*15,0)
			if angbuff ~= true then
				yawlerp = LerpAngle(0.25,yawlerp,angbuff)
				local angsizelimit = math.min(by_x*absolute,by_y*absolute)
				DrawAngle(angcent,yawlerp,angsizelimit,true,norm)
			end
		end
	end
	for _,at in ipairs(t_areas) do
		DrawArea(Vector(at.pos_start.x,at.pos_start.y,at.maxz),Vector(at.pos_start.x+at.abs*at.by_x*at.ssx,at.pos_start.y+at.abs*at.by_y*at.ssy,at.maxz),mat_solid,t_col.area_placed,at.norm)
		local lineoff = at.norm and r_renderoff or -r_renderoff
		for i = 1, at.by_x+1 do
			local v1 = Vector(at.pos_start.x+at.abs*(i-1)*at.ssx,at.pos_start.y,at.maxz+lineoff)
			local v2 = Vector(at.pos_start.x+at.abs*(i-1)*at.ssx,at.pos_start.y+at.by_y*at.abs*at.ssy,at.maxz+lineoff)
			render.DrawLine(v1,v2,t_col.line,r_lines_writez)
		end
		for i = 1, at.by_y+1 do
			local v1 = Vector(at.pos_start.x,at.pos_start.y+at.abs*(i-1)*at.ssy,at.maxz+lineoff)
			local v2 = Vector(at.pos_start.x+at.by_x*at.abs*at.ssx,at.pos_start.y+at.abs*(i-1)*at.ssy,at.maxz+lineoff)
			render.DrawLine(v1,v2,t_col.line,r_lines_writez)
		end
		local orig = Vector(at.pos_start.x+at.abs*at.ssx*at.by_x/2,at.pos_start.y+at.abs*at.ssy*at.by_y/2,at.maxz)
		local angsizelimit = math.min(at.by_x*at.abs,at.by_y*at.abs)
		DrawAngle(orig,at.angle,angsizelimit,nil,at.norm)
	end
end




hook.Add('InitPostEntity','ctools_npc',ToolInit)
hook.Add('PlayerBindPress','ctools_npc',PreventBind)
hook.Add('CreateMove','ctools_npc',ControlMouseWheel)
hook.Add('PostDrawTranslucentRenderables','ctools_npc',DrawVisuals)
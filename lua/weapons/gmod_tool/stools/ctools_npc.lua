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

local wepprof = {
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

local npcflags = {
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
TOOL.ClientConVar['sm_random'] = 1

for k,v in ipairs(npcflags) do
	TOOL.ClientConVar['SF_'..v[1]] = 0
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

local t_str = {
	notif_area = 'Not enough area!',
	notif_limit = 'Too many NPCs!',
	notif_exec = 'Executing (sending %sB of data...)',
	notif_undoareacur = 'Undone the current area!',
	notif_undoarealast = 'Undone last created area!',
	nowep = 'No weapon',
	defwep = 'Default weapon',
}

local t_col = {
	black = Color(0,0,0,255),
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

local spawnmethods = {
	'Default',
	'Amount (respawn)',
	'Timer (respawn)',
}

local sm_help = {
	'NPCs will be spawned across the area (no respawning)',
	'NPCs will respawn till total amount of X is reached',
	'NPCs will respawn while the timer is active',
}

local tex_cornerin = Material('gui/corner512')
local tex_cornerout = Material('gui/sniper_corner')

local npcbox = t_npcbox._def
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


local ipairs = ipairs
local pairs = pairs
local math = math
local cam = cam
local render = render
local surface = surface
local draw = draw




function TOOL:LeftClick(trace)
	if spamtime+0.1 > CurTime() then return false end
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
		if by_x*by_y > 16384 then
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
		for k,v in ipairs(npcflags) do
			if self:GetClientNumber('SF_'..v[1],0) ~= 0 then
				flags = bit.bor(flags,v[1])
			end
		end
		local data_npc = t_npcs[class]
		if npcflagsadd[data_npc.Class] then
			for k,v in SortedPairs(npcflagsadd[data_npc.Class]) do
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
			class = class,
			angle = angbuff,
			flags = flags,
			equip = (equip and equip ~= '') and (t_weps[equip] and t_weps[equip].class) or '_def',
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
			sm_total = sm_method ~= 1 and self:GetClientNumber('sm_total',0) or nil,
			sm_random = self:GetClientNumber('sm_random',1) ~= 0,
			maxz = maxz,
			abs = absolute,
			by_x = by_x,
			by_y = by_y,
			ssx = trbuff.x < scndbuff.x and 1 or -1,
			ssy = trbuff.y < scndbuff.y and 1 or -1,
		}

		trbuff = nil
		angbuff = nil
		surface.PlaySound(t_sound.success)
		return false
	end
	trbuff = trace.HitPos
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
	surface.SetDrawColor(t_col.white.r,t_col.white.g,t_col.white.b,t_col.white.a)
    surface.DrawRect(0,height-72,width,2)
    surface.DrawRect(width_q-1,height-72,2,72)
	surface.DrawRect(width_h-1,height-72,2,72)
	surface.DrawRect(width_h,height-36-1,width,2)
	local sprd = self:GetClientNumber('spread')
	local rnd = self:GetClientNumber('random')
	local sprd_font = sprd >= 1000 and 'CTOOLS_NPC_40' or (sprd >= 100 and 'CTOOLS_NPC_48' or 'CTOOLS_NPC_64')
	local rnd_font = rnd >= 100 and 'CTOOLS_NPC_48' or 'CTOOLS_NPC_64'
	draw.SimpleText(sprd,sprd_font,width_o,height-48,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText('SPREAD','CTOOLS_NPC_16',width_o,height-16,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(rnd,rnd_font,width_q+width_o,height-48,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText('RANDOM','CTOOLS_NPC_16',width_q+width_o,height-16,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(arnpccnt..' NPCs','CTOOLS_NPC_32',width-width_q,height-56,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(oldarcnt..' Areas','CTOOLS_NPC_32',width-width_q,height-20,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	draw.SimpleText(self:GetClientInfo('class'),'CTOOLS_NPC_32',width_h,24,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
	if trbuff then
		draw.SimpleText(arx*ary,'CTOOLS_NPC_64',width_h,height_h-56,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText('NPC to be spawned','CTOOLS_NPC_24',width_h,height_h-48+32,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText('X','CTOOLS_NPC_56',width_h,height_h+20,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText(arx,'CTOOLS_NPC_64',width_q,height_h+20,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
		draw.SimpleText(ary,'CTOOLS_NPC_64',width-width_q,height_h+20,t_col.prewhite,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
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
		local help_ms = form_flagsadd:ControlHelp('Additional flags, specific for '..data_npc.Class)
		help_ms.ToBeUpdated = true
		for k,v in SortedPairs(npcflagsadd[data_npc.Class]) do
			local fstr = 'SFA_'..data_npc.Class..'_'..k
			local check_flag = form_flagsadd:CheckBox(v,'ctools_npc_'..fstr)
			check_flag.OnChange = function(self,bool)
				GetConVar('ctools_npc_'..fstr):SetInt(bool and 1 or 0)
			end
			check_flag.ToBeUpdated = true
		end
	end

	local presetpanel = panel:AddControl('ComboBox', {MenuButton = 1, Folder = 'ctools_npc', Options = {['#preset.default'] = ConVarsDefault}, CVars = table.GetKeys(ConVarsDefault)})
	

	local slider_spread = panel:NumSlider('Spread multiplier','ctools_npc_spread',MIN_SPREAD,MAX_SPREAD,0)
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
		slider_respdel:SetHeight(cursm == 1 and 0 or 20)
		method_list.addpanels[#method_list.addpanels+1] = slider_respdel

		local st_str = sm == 3 and 'Timer (in seconds)' or 'Total NPC amount'
		local slider_total = method_list:NumSlider(st_str,'ctools_npc_sm_total',0,100,0)
		slider_total:SetHeight(cursm == 1 and 0 or 20)
		local textarea = slider_total:GetTextArea()
		function textarea:OnValueChange(str)
			if str ~= '0' then return end
			textarea:SetText('Infinite')
		end
		method_list.addpanels[#method_list.addpanels+1] = slider_total

		local slider_alive = method_list:NumSlider('Maximum alive NPCs','ctools_npc_sm_alive',0,100,0)
		slider_alive:SetHeight(cursm == 1 and 0 or 20)
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
		for k,v in ipairs(spawnmethods) do
			method:AddChoice(v,k,cursm == v)
		end
		function method:OnSelect(index,value,data)
			-- Why the fuck doesn't it work without SetInt???
			GetConVar('ctools_npc_sm_method'):SetInt(data)
			help_method:SetText(sm_help[data])
			method_list:MakeAdditional(data)
		end

		help_method = method_list:ControlHelp(sm_help[cursm or 1])

		local check_randomize = method_list:CheckBox('Randomize spawn','ctools_npc_sm_random')
		check_randomize:SetHeight(20)

		method_list:MakeAdditional(cursm)
	end

	method_list:UpdateData()
	method_list:InvalidateLayout(true)
	method_list:SetExpanded(true)
	method_list:SizeToChildren(false,true)
	panel:AddItem(method_list)

	entry_srchnpc = panel:TextEntry('NPC Filter')
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
			npcbox = t_npcbox[class] or t_npcbox._def
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

	local entry_srchwep = panel:TextEntry('Weapon Filter')
	local list_selectwep = vgui.Create('DListView',panel)
	list_selectwep:SetHeight(160)
	panel:AddItem(list_selectwep)
	list_selectwep:SetMultiSelect(false)
	list_selectwep:AddColumn('Weapon Class')
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
		list_selectnpc:UpdateData(data.ctools_npc_class)
		list_selectwep:UpdateData(data.ctools_npc_equip)
	end

	local combo_prof = panel:ComboBox('Proficiency','ctools_npc_wepprof')
	combo_prof:SetMinimumSize(nil,20)
	combo_prof:SetSortItems(false)
	function combo_prof.UpdateData()
		combo_prof:Clear()
		local curprof = GetConVar('ctools_npc_wepprof'):GetInt()
		for k,v in ipairs(wepprof) do
			combo_prof:AddChoice(v[2],v[1],curprof == v[1])
		end
	end
	combo_prof:UpdateData()

	local entry_mdl = panel:TextEntry('Custom Model:','ctools_npc_model')
	local entry_squad = panel:TextEntry('Custom Squad:','ctools_npc_squad')
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
	for k,v in ipairs(npcflags) do
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
	cam.Start3D2D(pos+Vector(0,0,r_renderoff),ang+Angle(0,-135+yadd,ar),1)
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

hook.Add('CreateMove','ctools_npc',function(cmd)
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
end)

hook.Add('PostDrawTranslucentRenderables','ctools_npc',function(bDepth,bSkybox)
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
		local by_x, by_y = math.floor(math.abs(area.x)/absolute), math.floor(math.abs(area.y)/absolute)
		local sx, sy = area.x < 0 and -1 or 1, area.y < 0 and -1 or 1
		arx, ary = by_x, by_y
		absolute_lerp = Lerp(0.2,absolute_lerp,absolute)
		local actbad = (by_x < 1 or by_y < 1)
		local secondpos = Vector(trbuff.x+by_x*absolute*sx,trbuff.y+by_y*absolute*sy,maxz)
		DrawArea(trbuff,angbuff and secondpos or curtr,mat_solid,actbad and t_col.area_bad or t_col.area_good)
		if !actbad then
			for i = 1, by_x+1 do
				local v1 = Vector(trbuff.x+absolute_lerp*(i-1)*sx,trbuff.y,maxz+r_renderoff)
				local v2 = Vector(trbuff.x+absolute_lerp*(i-1)*sx,trbuff.y+by_y*absolute_lerp*sy,maxz+r_renderoff)
				render.DrawLine(v1,v2,t_col.line,r_lines_writez)
			end
			for i = 1, by_y+1 do
				local v1 = Vector(trbuff.x,trbuff.y+absolute_lerp*(i-1)*sy,maxz+r_renderoff)
				local v2 = Vector(trbuff.x+by_x*absolute_lerp*sx,trbuff.y+absolute_lerp*(i-1)*sy,maxz+r_renderoff)
				render.DrawLine(v1,v2,t_col.line,r_lines_writez)
			end
		end
		if angbuff then
			if !angcent then
				angcent = Vector(trbuff.x+absolute*sx*by_x/2,trbuff.y+absolute*sy*by_y/2,maxz)
			end
			local anghitpos = util.IntersectRayWithPlane(lptr.StartPos,lptr.Normal,angcent,Vector(0,0,1))
			local ang = ((anghitpos or curtr)-angcent):Angle()
			angbuff = Angle(0,math.floor((ang.y+7.5)/15)*15,0)
			if angbuff ~= true then
				yawlerp = LerpAngle(0.25,yawlerp,angbuff)
				local angsizelimit = math.min(by_x*absolute,by_y*absolute)
				DrawAngle(angcent,yawlerp,angsizelimit,true)
			end
		end
	end
	for _,at in ipairs(t_areas) do
		DrawArea(Vector(at.pos_start.x,at.pos_start.y,at.maxz),Vector(at.pos_start.x+at.abs*at.by_x*at.ssx,at.pos_start.y+at.abs*at.by_y*at.ssy,at.maxz),mat_solid,t_col.area_placed)
		for i = 1, at.by_x+1 do
			local v1 = Vector(at.pos_start.x+at.abs*(i-1)*at.ssx,at.pos_start.y,at.maxz+r_renderoff)
			local v2 = Vector(at.pos_start.x+at.abs*(i-1)*at.ssx,at.pos_start.y+at.by_y*at.abs*at.ssy,at.maxz+r_renderoff)
			render.DrawLine(v1,v2,t_col.line,r_lines_writez)
		end
		for i = 1, at.by_y+1 do
			local v1 = Vector(at.pos_start.x,at.pos_start.y+at.abs*(i-1)*at.ssy,at.maxz+r_renderoff)
			local v2 = Vector(at.pos_start.x+at.by_x*at.abs*at.ssx,at.pos_start.y+at.abs*(i-1)*at.ssy,at.maxz+r_renderoff)
			render.DrawLine(v1,v2,t_col.line,r_lines_writez)
		end
		local orig = Vector(at.pos_start.x+at.abs*at.ssx*at.by_x/2,at.pos_start.y+at.abs*at.ssy*at.by_y/2,at.maxz)
		local angsizelimit = math.min(at.by_x*at.abs,at.by_y*at.abs)
		DrawAngle(orig,at.angle,angsizelimit)
	end
end)
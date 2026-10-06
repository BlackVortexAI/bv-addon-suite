local _,L=...
if not L.ready then return end
-- Settings page, simulation and /bv sct commands.
local ns=L.ns
local UI,D=ns.UI,ns.DesignSystem.Metrics

function L:Changed()
    if not self:Active() then return end
    self.Blizzard:Apply()
    self.Log:Update()
end

-- Simulation: a short fight against the target (or the anchors without one).
local Sim={}
L.Sim=Sim
-- {delay, unit, action, flag, amount, school, spell for the icon}
local SCRIPT={
    {0,"plate","WOUND","",1234,1,6603},{.25,"plate","WOUND","",987,1,6603},{.5,"plate","WOUND","CRITICAL",4321,4,133},
    {.6,"player","WOUND","",356,1},{.8,"plate","DODGE","",nil,nil},{1,"player","HEAL","",1520,2,2050},
    {1.2,"plate","WOUND","",18250,16,116},{1.4,"player","PARRY","",nil,nil},{1.5,"player","WOUND","BLOCK_REDUCED",210,1},
    {1.7,"plate","WOUND","CRITICAL",36500,32,589},{1.9,"player","HEAL","CRITICAL",2840,2,2050},{2.1,"plate","MISS","",nil,nil},
}
function Sim:Run()
    if not L:Active() then L:Print("Turn the module on first (/bv sct on).");return end
    self.serial=(self.serial or 0)+1
    local serial=self.serial
    for _,step in ipairs(SCRIPT) do
        C_Timer.NewTimer(step[1],function()
            if serial~=self.serial or not L:Active() then return end
            local player=step[2]=="player"
            local entry=L.Sources:Entry(player and "player" or "nameplate1",step[3],step[4],step[5],step[6],true)
            if not entry then return end
            -- Shown at the target's nameplate when there is one, else at the anchors.
            if not player then entry.unit=UnitExists and UnitExists("target") and "target" or nil end
            local c=L:Config()
            if step[7] and c.spellGuess and (entry.category~="heal" or c.iconHeals) then entry.spell=step[7] end
            L.Display:Show(entry)
        end)
    end
end
-- Messages: {delay, category, core text, kind}.
local MESSAGES={
    {.1,"notice","+Combat","combat start"},{.9,"buff","+Power Word: Fortitude","gain"},{1.3,"power","+250 Mana","power"},
    {1.6,"debuff","+Curse of Weakness","gain"},{2.2,"notice","Overpower!","proc"},{2.6,"buff","-Power Word: Fortitude","fade"},
    {2.9,"notice","Stormwind +25","reputation"},{3.2,"notice","-Combat","combat end"},
}
local runMessages=Sim.Run
function Sim:Run()
    runMessages(self)
    if not L:Active() then return end
    local serial=self.serial
    for _,step in ipairs(MESSAGES) do
        C_Timer.NewTimer(step[1],function()
            if serial==self.serial and L:Active() then L.Notices:Show(step[2],step[3],step[4]) end
        end)
    end
end
function Sim:Stop() self.serial=(self.serial or 0)+1 end

-- Settings page -----------------------------------------------------------------------
local NUMBERS={{value="short",label="Short (12.3k)"},{value="full",label="Full (12,345)"},{value="plain",label="Plain (12345)"}}
local OUTLINES={{value="OUTLINE",label="Outline"},{value="THICKOUTLINE",label="Thick outline"},{value="",label="None"}}
local PRESETS={{value="up",label="Scroll up"},{value="down",label="Scroll down"},{value="fountain",label="Fountain (arc)"},
    {value="rain",label="Rain (falls)"},{value="pop",label="Pop (crit style)"}}
local ANIMATIONS={}
for _,option in ipairs(PRESETS) do ANIMATIONS[#ANIMATIONS+1]=option end
for i=1,L.CUSTOM_COUNT do ANIMATIONS[#ANIMATIONS+1]={value="custom"..i,label="Custom "..i} end
local CUSTOMS={}
for i=1,L.CUSTOM_COUNT do CUSTOMS[i]={value=i,label="Custom "..i} end
local MIRRORS={{value="none",label="As designed"},{value="x",label="Mirrored sideways"},{value="y",label="Upside down"},{value="xy",label="Both"}}
local EASES={{value="NONE",label="Linear"},{value="IN",label="Ease in (slow start)"},{value="OUT",label="Ease out (slow end)"},{value="IN_OUT",label="Ease in and out"}}
local POSITIONS={{value="nameplate",label="At the nameplate"},{value="outgoing",label="Outgoing anchor"},
    {value="incoming",label="Incoming anchor"},{value="notice",label="Notification anchor"},{value="auto",label="Where it happened"}}
local PETS={{value="mine",label="As mine"},{value="dimmed",label="Dimmed"},{value="hidden",label="Hidden"}}
local SCOPES={{value="mine",label="Only mine"},{value="dimmed",label="Mine, others dimmed"},{value="all",label="All, full color"}}
local SCOPE_TEXT={world={"Open world","Outside instances."},pvp={"Battlegrounds & arenas","Against players."},
    dungeon={"Dungeons","Five-player dungeons and scenarios."},raid={"Raids","Raid instances."}}
local SCOPE_NOTE=" \"Only mine\": your hits. \"Mine, others dimmed\": also hits of others on enemies fighting you or your group (pet, group members, Thorns), in the color and opacity below. \"All, full color\": every number on enemies. Which hits are yours: with the Combat Log set up (below) the game's own report of your actions, otherwise every hit on an enemy that fights you counts as yours."
local AFFIX_NOTE=" Placeholders: {school} damage type, {spell} your spell (experimental guess, see the Experimental tab), {name} the unit that was hit. A field whose placeholder has no value is left out. The game does not name the attacker. At most 24 characters."
local ICONS={{value="left",label="Left of the number"},{value="right",label="Right of the number"},{value="off",label="Off"}}
local CATEGORY_TEXT={
    outgoing={"Outgoing damage","Damage enemies take. The event names no attacker, so in a group this includes the damage of others."},
    incoming={"Incoming damage","Damage you take."},
    heal={"Incoming heals","Heals you receive."},
    outheal={"Outgoing heals","Heals on others: at their nameplate (friendly nameplates must be shown) or your outgoing anchor. Whose heals: as set under \"Whose numbers\"."},
    miss={"Misses and avoidance","Miss, dodge, parry and similar: yours at the enemy, the enemy's at you."},
    buff={"Buffs on you","Buffs you gain (+Name) and lose (-Name), as the game reports them for its own combat text."},
    debuff={"Debuffs on you","Debuffs you gain (+Name) and lose (-Name)."},
    buffgiven={"Buffs you give","Your buffs on your friendly target, at its nameplate (or your outgoing anchor). Shown when the buff landed: out of combat Combat Text checks the target's buffs. In combat buffs cannot be read; there only spells already seen landing as a buff are shown. Off by default."},
    power={"Power gains","Mana, rage, energy and other power you gain from spells and effects, e.g. +250 Mana."},
    notice={"Notifications","Combat start and end, reputation, honor and procs such as Overpower!"},
}
local SWITCH_TEXT={
    gains={"Show gained","Shows the aura when you get it."},
    fades={"Show faded","Shows the aura when it ends."},
    combat={"Combat start and end","+Combat and -Combat when you enter and leave combat."},
    reputation={"Reputation","Faction name and the reputation you gained or lost."},
    honor={"Honor","Honor you gain."},
    procs={"Procs","Abilities that become usable, e.g. Overpower! or Revenge!"},
}
local page
local function build(parent)
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls,styleControls={},{}
    local function cfg() return L:Config() end
    local function set(key) return function(value) cfg()[key]=value;L:Changed() end end
    local function row(key,title,control,help,opts)
        opts=opts or {};opts.help=opts.help or help
        controls[key]=g:Row(title,control,opts)
        return controls[key]
    end
    g:Section("module","Module")
    page.enabled=g:Row("Enabled",UI:Switch(g,false,function(value)
        ns.Modules:SetEnabled(L.ID,value);ns.Layout:Refresh(true);if ns.Config then ns.Config:Refresh() end
    end),{help="Floating combat text for damage, heals and avoidance."})
    row("hideBlizzardSelf","Hide Blizzard text at you",UI:Switch(g,true,set("hideBlizzardSelf")),
        "Blizzard's damage and heals you take, shown at your character. Off while this module runs; the previous setting comes back when you turn this off.")
    row("hideBlizzard","Hide Blizzard numbers at enemies",UI:Switch(g,true,set("hideBlizzard")),
        "Blizzard's numbers over the enemies you hit. They show only your own damage, which addons cannot tell apart; keep them and turn \"Outgoing damage\" below off if you want exactly your own.")
    row("plates","Use nameplates",UI:Switch(g,true,set("plates")),
        "Texts set to \"At the nameplate\" follow the enemy's nameplate; without one they use the outgoing anchor.")
    row("numbers","Numbers",UI:Dropdown(g,190,NUMBERS,set("numbers")),"How amounts are written.")
    row("outline","Outline",UI:Dropdown(g,190,OUTLINES,set("outline")),"Outline of all combat texts.")
    g:Row("Position",UI:Button(g,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:combattext_outgoing") end),
        {help="Outgoing, incoming and notification anchors are movable elements. Texts start in the middle of the anchor."})
    if ns.Tutorial and ns.Tutorial.Open then
        g:Row("Guide",UI:Button(g,"Show guide",170,function() ns.Tutorial:Open(L.GUIDE_ID) end),
            {help="Step by step: what Combat Text needs (Combat Log, its filter) and what the main settings do. Shown once when the module is first turned on."})
    end
    g:Row("Simulation",UI:Button(g,"Test combat text",170,function() Sim:Run() end),
        {help="A short fake fight: hits, crits, heals, avoidance, auras, power and notifications. Uses your target's nameplate when there is one."})
    g:Section("scope","Whose numbers")
    local scopeControls={}
    for _,kind in ipairs(L.CONTENT_TYPES) do
        local text=SCOPE_TEXT[kind]
        scopeControls[kind]=g:Row(text[1],UI:Dropdown(g,190,SCOPES,function(value) cfg().whose[kind]=value end),{help=text[2]..SCOPE_NOTE})
    end
    row("pet","Your pet",UI:Dropdown(g,190,PETS,set("pet")),
        "Hits Combat Text knows as your pet's: a spell your pet just cast whose damage type matches the hit (e.g. the imp's Firebolt), with that spell's icon. As mine: like your hits. Dimmed: in the color and opacity of others. Hidden: not shown. Your pet's melee is not told apart yet.")
    row("foreignTint","Others in own color",UI:Switch(g,true,set("foreignTint")),
        "With \"Mine, others dimmed\": hits of others use the color below instead of their damage type color.")
    row("foreignColor","Color of others",UI:ColorInput(g,150,set("foreignColor")),"Used when \"Others in own color\" is on.",{width=150})
    row("foreignAlpha","Opacity of others",UI:InlineSlider(g,190,.1,1,.05,"x%.2f",set("foreignAlpha")),
        "With \"Mine, others dimmed\": hits of others are drawn with this opacity (1 = solid).")
    -- Combat Log signal (Log.lua): status and the two setup steps, checked live.
    g:Section("combatlog","Your hits from the Combat Log")
    local logRows={}
    page.logRows=logRows
    local function info(title,help)
        local label=UI:Label(g,"",13,"text",false)
        g:Row(title,label,{width=440,help=help})
        return label
    end
    logRows.state=info("Status","WoW Forever does not say who hit an enemy. The Combat Log tab still reports when you did something, so Combat Text can tell your hits from others' (\"Whose numbers\" above) and a damage-over-time tick from a fresh hit. Used only when both steps below are done; otherwise every hit on an enemy fighting you counts as yours.")
    logRows.opened=info("1. Open the Combat Log","The game reports your actions only after the Combat Log tab in your chat was shown once since login or /reload. Click that tab once (and back), or the Start button at the top of the screen.")
    logRows.filter=info("2. Combat Log filter","The filter selected on the Combat Log tab decides which actions are reported. It must take only yours: WoW's default \"My actions\" does. With \"Pet\" ticked too, your pet's hits count as yours. To check or change it: right-click the Combat Log tab, Settings, select the filter, Message Sources, \"Done By\": \"Me\", and \"Pet\" if you like, nothing else. Message types do not matter. Combat Text reads this filter and never changes it.")
    row("logSignal","Use the Combat Log",UI:Switch(g,true,set("logSignal")),
        "Off: every hit on an enemy fighting you counts as yours.")
    row("logButton","Start button",UI:Switch(g,true,set("logButton")),
        "Shows a button at the top of the screen until the Combat Log tab was opened. It opens the tab for a moment and switches back. A macro with /click BVCombatTextLogStart does the same.")
    function page:RefreshLog()
        local s=L.Log:Status()
        local G=L.Log
        local ok,bad="|cff40d060","|cffff6060"
        logRows.state:SetText((s.state=="active" or s.state=="waiting") and ok..G.STATE_TEXT[s.state].."|r" or s.state=="off" and G.STATE_TEXT.off or bad..G.STATE_TEXT[s.state].."|r")
        logRows.opened:SetText(s.opened and ok.."Done|r" or bad.."Not yet since login|r")
        local name=s.filterName and "\""..s.filterName.."\" " or ""
        logRows.filter:SetText((G.USABLE[s.filter] and ok or bad)..name..G.FILTER_TEXT[s.filter].."|r")
    end
    g:Section("icons","Spell guess (experimental)")
    row("spellGuess","Guess the spell",UI:Switch(g,false,set("spellGuess")),
        "The game does not say which spell hit. When on, the module guesses from your own casts: the channel you are casting, your last spell and your damage-over-time debuffs on the enemy. It learns each spell's damage type and tick rhythm from the hits (until then the damage type named in the spell's description counts); a spell is named only when exactly one fits the hit's damage type and timing, otherwise nothing. Physical hits while you auto attack count as auto attack. Used for icons and {spell}. Note: in combat WoW Forever protects aura data; only auras tracked in Blizzard's Cooldown Manager stay readable, so DoTs are recognised by their tick rhythm instead of the debuff.")
    row("icons","Icons",UI:Dropdown(g,190,ICONS,set("icons")),"Where the spell icon appears. Only with \"Guess the spell\" on.")
    g:Row("Learned spell data",UI:Button(g,"Forget",120,function() L.Attribution:Forget();L:Print("Learned damage types and tick rhythms cleared.") end),
        {help="The spell guess remembers each spell's damage type and tick rhythm. Clear it after something wrong was learned (e.g. a talent changed a spell's school)."})
    row("iconSize","Icon size",UI:InlineSlider(g,190,.5,2,.1,"x%.1f",set("iconSize")),"Icon edge relative to the font size.")
    row("iconHeals","Icons on heals",UI:Switch(g,true,set("iconHeals")),"Heals you receive within 4 seconds of your own cast get that spell's icon (also when someone else healed you).")
    g:Section("schools","Damage types")
    local schoolControls={}
    for _,bit in ipairs({1,2,4,8,16,32,64}) do
        schoolControls[bit]=g:Row(L.Format.SchoolName(bit),UI:ColorInput(g,150,function(value) cfg().schoolColors[bit]=value end),
            {help="Color of this damage type for \"School colors\" and the damage type text.",width=150})
    end
    -- Custom animation editor: one animation and one point at a time.
    g:Section("custom","Custom animations")
    local edit={index=1,point=1}
    page.edit=edit
    local ec={}
    page.customControls=ec
    local function keys() return cfg().customAnimations[edit.index].keys end
    local function changedKeys()
        local custom=cfg().customAnimations[edit.index]
        custom.keys=L.Animation.CleanKeys(custom.keys,custom.keys)
        edit.point=math.min(edit.point,#custom.keys)
        page:RefreshCustom()
    end
    local function field(key) return function(value) keys()[edit.point][key]=value;changedKeys() end end
    ec.index=g:Row("Edit",UI:Dropdown(g,190,CUSTOMS,function(value) edit.index=value;edit.point=1;page:RefreshCustom() end),
        {help="Choose the custom animation to edit. Use it in a category below with Animation \"Custom 1-3\"."})
    ec.preset=g:Row("Start from",UI:Dropdown(g,190,PRESETS,function(value)
        local jitter=value=="fountain" and .6 or 0
        cfg().customAnimations[edit.index].keys=L.Animation.CleanKeys(L.Animation.PRESETS[value](jitter),nil)
        edit.point=1;changedKeys()
    end),{help="Replaces the points of this custom animation with a copy of a preset to start from."})
    ec.count=g:Row("Points",UI:InlineSlider(g,190,2,L.Animation.MAX_POINTS,1,"%d",function(value)
        L.Animation.Resize(keys(),math.floor(value+.5));changedKeys()
    end),{help="Start point, end point and up to three points in between. Each part between two points can ease on its own."})
    ec.point=g:Row("Point",UI:Dropdown(g,190,{},function(value) edit.point=value;page:RefreshCustom() end),
        {help="The point whose values are shown below. Point 1 is the start, the last point the end."})
    ec.t=g:Row("Time",UI:InlineSlider(g,190,0,100,5,"%d %%",function(value)
        -- Stays between its neighbours; start and end are fixed.
        local list=keys();local i=edit.point
        local low,high=i>1 and list[i-1].t or 0,i<#list and list[i+1].t or 1
        list[i].t=math.max(low,math.min(high,value/100));changedKeys()
    end),
        {help="When the text reaches this point, as a share of the duration. The start is always 0 %, the end 100 %; points stay in order."})
    ec.x=g:Row("Sideways",UI:InlineSlider(g,190,-3,3,.05,"x%.2f",field("x")),
        {help="Horizontal position as a multiple of the category's distance; negative is left."})
    ec.y=g:Row("Up / down",UI:InlineSlider(g,190,-3,3,.05,"x%.2f",field("y")),
        {help="Vertical position as a multiple of the category's distance; negative is down."})
    ec.s=g:Row("Size",UI:InlineSlider(g,190,.1,3,.05,"x%.2f",field("s")),{help="Text size at this point (1 = font size)."})
    ec.a=g:Row("Opacity",UI:InlineSlider(g,190,0,1,.05,"%.2f",field("a")),{help="0 is invisible, 1 solid."})
    ec.ease=g:Row("Easing to here",UI:Dropdown(g,190,EASES,field("ease")),
        {help="How the movement from the previous point to this one runs. Not used for point 1."})
    g:Row("Preview",UI:Button(g,"Play",120,function() if L:Active() then L.Display:Preview(edit.index,false) else L:Print("Turn the module on first (/bv sct on).") end end),
        {help="Plays this custom animation at the outgoing anchor with the outgoing style (module must be on)."})
    g:Row("",UI:Button(g,"Play as crit",120,function() if L:Active() then L.Display:Preview(edit.index,true) end end),
        {help="The same with the crit pop and crit size."})
    function page:RefreshCustom()
        local list=keys()
        local options={}
        for i=1,#list do options[i]={value=i,label=i==1 and "1 (start)" or i==#list and i.." (end)" or tostring(i)} end
        ec.point.options=options
        ec.index:SetValue(edit.index);ec.count:SetValue(#list);ec.point:SetValue(edit.point)
        local k=list[edit.point]
        ec.t:SetValue(math.floor(k.t*100+.5))
        for _,key in ipairs({"x","y","s","a"}) do ec[key]:SetValue(k[key]) end
        ec.ease:SetValue(k.ease)
    end
    for _,name in ipairs(L.CATEGORY_ORDER) do
        local text=CATEGORY_TEXT[name]
        local function style() return cfg().categories[name] end
        local function sset(key) return function(value) style()[key]=value;L:Changed() end end
        local list={}
        styleControls[name]=list
        local function srow(key,title,control,help,opts)
            opts=opts or {};opts.help=help
            list[key]=g:Row(title,control,opts)
        end
        g:Section("cat_"..name,text[1])
        srow("enabled","Show",UI:Switch(g,true,sset("enabled")),text[2])
        srow("anchor","Position",UI:Dropdown(g,190,POSITIONS,sset("anchor")),"Nameplate, one of the two anchors, or where it happened (enemy nameplate or incoming anchor).")
        srow("animation","Animation",UI:Dropdown(g,190,ANIMATIONS,sset("animation")),"Movement of the text: a preset or one of your custom animations. Crits start with an extra pop.")
        srow("mirror","Direction",UI:Dropdown(g,190,MIRRORS,sset("mirror")),"Flips the animation, e.g. a scroll up becomes a scroll down, a fountain to the right goes left.")
        srow("size","Font size",UI:InlineSlider(g,190,8,64,1,"%d",sset("size")),"Size of normal hits.")
        srow("crit","Crit size",UI:InlineSlider(g,190,1,3,.1,"x%.1f",sset("crit")),"Crits are this much larger.")
        srow("color","Color",UI:ColorInput(g,150,sset("color")),"Text color.",{width=150})
        if name=="outgoing" then srow("school","School colors",UI:Switch(g,true,sset("school")),"Fire orange, frost blue and so on instead of the color above.") end
        local defaults=L.CATEGORY_DEFAULTS[name]
        for _,key in ipairs(L.CATEGORY_SWITCHES) do
            if defaults[key]~=nil then srow(key,SWITCH_TEXT[key][1],UI:Switch(g,true,sset(key)),SWITCH_TEXT[key][2]) end
        end
        if name=="outgoing" or name=="incoming" then
            srow("label","Damage type text",UI:Switch(g,false,sset("label")),"Adds the damage type after the number, e.g. \"1234 Fire\", in its color. Missing when the game hides the type.")
        end
        local function affix(key,title,help)
            local box=UI:GetStyle():Input(g,190,false,"",function(text) style()[key]=L.Format.CleanAffix(text,"");L:Changed() end)
            UI:TextFieldMenu(box);box:SetMaxLetters(L.Format.AFFIX_MAX)
            function box:SetValue(value) if not self:HasFocus() and self:GetText()~=value then self:SetText(value or "") end end
            srow(key,title,box,help..AFFIX_NOTE)
        end
        affix("prefix","Prefix","Text in front of every "..(name=="miss" and "message" or "number")..".")
        affix("suffix","Suffix","Text after every "..(name=="miss" and "message" or "number")..".")
        if name~="miss" then
            affix("critPrefix","Crit prefix","Extra text in front of crits only, outside the prefix.")
            affix("critSuffix","Crit suffix","Extra text after crits only, outside the suffix.")
        end
        srow("duration","Duration",UI:InlineSlider(g,190,.3,5,.1,"%.1f s",sset("duration")),"How long the text stays on screen.")
        srow("distance","Distance",UI:InlineSlider(g,190,0,300,5,"%d px",sset("distance")),"How far the text travels.")
    end
    -- Tabs in the settings window header: which sections each one shows.
    local TABS={
        {id="general",label="General",sections={"module","scope","combatlog","schools"}},
        {id="categories",label="Combat",sections={"cat_outgoing","cat_incoming","cat_heal","cat_outheal","cat_miss"}},
        {id="messages",label="Auras & messages",sections={"cat_buff","cat_debuff","cat_buffgiven","cat_power","cat_notice"}},
        {id="animations",label="Animations",sections={"custom"}},
        {id="experimental",label="Experimental",sections={"icons"}},
    }
    local definitions={}
    for i,tab in ipairs(TABS) do definitions[i]={id=tab.id,label=tab.label} end
    local function select(id)
        for _,tab in ipairs(TABS) do
            if tab.id==id then
                local set={}
                for _,section in ipairs(tab.sections) do set[section]=true end
                g:ShowSections(set)
            end
        end
        page.navigation.selected=id
        page:Arrange(page.width or 880)
        if ns.Config.window then ns.Config:Layout() end
    end
    page.navigation={definitions=definitions,selected="general",select=select}
    function page:Arrange(width)
        self.width=width
        UI:Place(g,self,0,0)
        local height=g:Arrange(width)+8
        D.Height(self,height);return height
    end
    function page:Refresh()
        local c=L:Config()
        self:RefreshCustom()
        self:RefreshLog()
        self.enabled:SetValue(ns.Settings:Module(L.ID).enabled==true)
        for key,control in pairs(controls) do if control.SetValue then control:SetValue(c[key]) end end
        for kind,control in pairs(scopeControls) do control:SetValue(c.whose[kind]) end
        for bit,control in pairs(schoolControls) do control:SetValue(c.schoolColors[bit]) end
        for name,list in pairs(styleControls) do
            for key,control in pairs(list) do if control.SetValue then control:SetValue(c.categories[name][key]) end end
        end
    end
    select("general");page:Refresh()
    return page
end
ns.Config:RegisterPage("combattext",{title="Combat Text",description="Floating damage, heal and avoidance numbers with animations.",
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})

L.commands.test=function(action) if action=="stop" then Sim:Stop() else Sim:Run() end end
-- Explicit: "hide" or "show" (both parts); without an argument only the state is printed.
L.commands.blizzard=function(action)
    local c=L:Config()
    if action=="hide" or action=="off" then c.hideBlizzard,c.hideBlizzardSelf=true,true
    elseif action=="show" or action=="on" then c.hideBlizzard,c.hideBlizzardSelf=false,false
    elseif action~="" then L:Print("/bv sct blizzard [hide|show]");return end
    if action~="" then L.Blizzard:Apply();ns.Config:Refresh() end
    L:Print("Blizzard text at you "..(c.hideBlizzardSelf and "hidden" or "shown")..", at enemies "..(c.hideBlizzard and "hidden" or "shown")
        ..(L:Active() and "" or " (module off: all shown)").." - /bv sct blizzard [hide|show]")
end
L.commands.debug=function(action)
    if action=="reset" then L.Sources.stats={};L.Sources.lastError=nil;L:DB().spellTrace=nil;L:DB().logTrace=nil;L:Print("Counters, spell and log traces reset.");return end
    if action=="spells" then
        -- Last decisions of the spell guess: id:fit:school:interval:base per candidate.
        local list=L:DB().spellTrace or {}
        if #list==0 then L:Print("No spell guess recorded yet (Experimental: Guess the spell).");return end
        for i=math.max(1,#list-14),#list do L:Print(list[i]) end
        L:Print(#list.." lines kept in the saved data (BVCombatTextDB.spellTrace).")
        return
    end
    L.Sources:Report()
end
if ns.ready and IsLoggedIn() then ns.Modules:Reconcile() end

local package,L=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.91 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.6.0","0.8.91",1) then return end
-- Combat text module. Everything specific to it lives in this package, never
-- in Core, so Core stays free for fixes.
L.ns=ns
L.ready=true
L.ID="combat_text"
ns.CombatText=L

-- Own saved data (BVCombatTextDB): Blizzard CVars we changed, learned spell data.
function L:DB()
    if type(BVCombatTextDB)~="table" then BVCombatTextDB={} end
    return BVCombatTextDB
end
function L:Print(text) ns:Print("|cffe6bd83Combat Text:|r "..tostring(text)) end
function L.Secret(v)
    if v==nil then return false end
    if issecretvalue then local ok,s=pcall(issecretvalue,v);if ok and s then return true end end
    if canaccessvalue then local ok,a=pcall(canaccessvalue,v);if ok and a==false then return true end end
    return false
end

-- Categories: where a number comes from and how it looks. Anchors: "outgoing",
-- "incoming" (movable in the Layout Editor) or "nameplate" (falls back to
-- outgoing without a plate). Animations: see UI/Animation.lua.
L.CATEGORY_ORDER={"outgoing","incoming","heal","miss"}
L.CATEGORY_DEFAULTS={
    outgoing={anchor="nameplate",animation="fountain",size=20,color="FFFFFFFF",school=true,label=false,prefix="",suffix="",duration=1.4,distance=70,crit=1.5},
    incoming={anchor="incoming",animation="down",size=18,color="FF5050FF",school=false,label=false,prefix="-",suffix="",duration=1.6,distance=90,crit=1.4},
    heal={anchor="incoming",animation="up",size=18,color="50FF70FF",school=false,prefix="+",suffix="",duration=1.6,distance=90,crit=1.4},
    miss={anchor="auto",animation="up",size=16,color="C8C8C8FF",school=false,prefix="",suffix="",duration=1.2,distance=50,crit=1},
}
L.DEFAULTS={enabled=false,hideBlizzard=true,hideBlizzardSelf=true,plates=true,numbers="short",font="inherit",outline="OUTLINE",
    -- Numbers on enemies not fighting you: own color (optional) and transparency.
    foreignTint=true,foreignColor="A0A0A0FF",foreignAlpha=.6,
    -- Spell icons (best guess from your own casts): "off", "left" or "right".
    icons="left",iconSize=1,iconHeals=true,
    -- Experimental: guess the spell of a hit (icons, {spell}). Off by default.
    spellGuess=false}
-- Whose numbers at enemies, per content type: "mine", "group" or "all".
L.CONTENT_TYPES={"world","pvp","dungeon","raid"}
L.SCOPE_DEFAULTS={world="mine",pvp="mine",dungeon="group",raid="mine"}
function L.ContentType()
    local ok,inside,kind=pcall(IsInInstance)
    if not ok or not inside then return "world" end
    if kind=="pvp" or kind=="arena" then return "pvp" end
    if kind=="raid" then return "raid" end
    if kind=="party" or kind=="scenario" then return "dungeon" end
    return "world"
end
local function num(v,default,low,high) if type(v)~="number" or v~=v then v=default end;return math.max(low,math.min(high,v)) end
local ANIMATIONS={up=true,down=true,fountain=true,rain=true,pop=true,custom1=true,custom2=true,custom3=true}
local MIRRORS={none=true,x=true,y=true,xy=true}
-- Three editable custom animations; the defaults start from presets.
L.CUSTOM_COUNT=3
L.CUSTOM_DEFAULTS={{preset="up",jitter=0},{preset="fountain",jitter=.6},{preset="pop",jitter=0}}
function L:Config()
    local cfg=ns.Settings:Module(self.ID)
    for key,value in pairs(self.DEFAULTS) do if cfg[key]==nil then cfg[key]=value end end
    cfg.hideBlizzard=cfg.hideBlizzard==true;cfg.hideBlizzardSelf=cfg.hideBlizzardSelf==true;cfg.plates=cfg.plates==true
    if cfg.numbers~="short" and cfg.numbers~="full" and cfg.numbers~="plain" then cfg.numbers="short" end
    if cfg.outline~="OUTLINE" and cfg.outline~="THICKOUTLINE" and cfg.outline~="" then cfg.outline="OUTLINE" end
    cfg.foreignTint=cfg.foreignTint==true;cfg.foreignAlpha=num(cfg.foreignAlpha,.6,.1,1)
    if type(cfg.foreignColor)~="string" or not cfg.foreignColor:match("^%x%x%x%x%x%x%x%x$") then cfg.foreignColor="A0A0A0FF" end
    if cfg.icons~="off" and cfg.icons~="left" and cfg.icons~="right" then cfg.icons="left" end
    cfg.iconSize=num(cfg.iconSize,1,.5,2);cfg.iconHeals=cfg.iconHeals==true;cfg.spellGuess=cfg.spellGuess==true
    if type(cfg.schoolColors)~="table" then cfg.schoolColors={} end
    for bit,hex in pairs(L.Format.SCHOOLS) do
        local v=cfg.schoolColors[bit]
        if type(v)~="string" or not v:match("^%x%x%x%x%x%x%x%x$") then cfg.schoolColors[bit]=hex.."FF" end
    end
    if type(cfg.customAnimations)~="table" then cfg.customAnimations={} end
    for i=1,L.CUSTOM_COUNT do
        local custom=cfg.customAnimations[i]
        if type(custom)~="table" then custom={};cfg.customAnimations[i]=custom end
        local d=L.CUSTOM_DEFAULTS[i]
        custom.keys=L.Animation.CleanKeys(custom.keys,L.Animation.PRESETS[d.preset](d.jitter))
    end
    if type(cfg.scope)~="table" then cfg.scope={} end
    for kind,default in pairs(self.SCOPE_DEFAULTS) do
        local v=cfg.scope[kind]
        if v~="mine" and v~="group" and v~="all" then cfg.scope[kind]=default end
    end
    if type(cfg.categories)~="table" then cfg.categories={} end
    for name,defaults in pairs(self.CATEGORY_DEFAULTS) do
        local c=cfg.categories[name]
        if type(c)~="table" then c={};cfg.categories[name]=c end
        for key,value in pairs(defaults) do if c[key]==nil then c[key]=value end end
        c.enabled=c.enabled~=false
        if not ANIMATIONS[c.animation] then c.animation=defaults.animation end
        if not MIRRORS[c.mirror] then c.mirror="none" end
        if c.anchor~="outgoing" and c.anchor~="incoming" and c.anchor~="nameplate" and c.anchor~="auto" then c.anchor=defaults.anchor end
        c.size=num(c.size,defaults.size,8,64);c.duration=num(c.duration,defaults.duration,.3,5)
        c.distance=num(c.distance,defaults.distance,0,300);c.crit=num(c.crit,defaults.crit,1,3)
        if type(c.color)~="string" or not c.color:match("^%x%x%x%x%x%x%x%x$") then c.color=defaults.color end
        -- Prefix/suffix (also only for crits) with {school} {spell} {name}.
        for _,key in ipairs({"prefix","suffix","critPrefix","critSuffix"}) do c[key]=L.Format.CleanAffix(c[key],defaults[key] or "") end
        c.school=c.school==true;c.label=c.label==true
    end
    return cfg
end
function L:Active() return self.context~=nil end

ns.Modules:Register({id=L.ID,OnEnable=function(context)
    L.context=context
    context:Defer(function() L.context=nil end)
    L:Config()
    L.Display:Enable(context)
    L.Blizzard:Enable(context)
    L.Attribution:Enable(context)
    L.Sources:Enable(context)
end})

L.commands={}
local HELP="/bv sct [on|off] | /bv sct test [stop] | /bv sct blizzard [hide|show] | /bv sct debug [spells|reset]"
ns.Commands:RegisterAction("sct",function(action)
    local command,rest=(action or ""):match("^(%S*)%s*(.-)$")
    if command=="" then ns.Config:OpenPage("combattext");return end
    if command=="on" or command=="off" then
        ns.Modules:SetEnabled(L.ID,command=="on");ns.Layout:Refresh(true)
        L:Print(ns.Modules.records[L.ID].state);ns.Config:Refresh();return
    end
    local handler=L.commands[command]
    if handler then handler(rest) else L:Print(HELP) end
end)

local package,G=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.96 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.1.6","0.8.96",1) then return end
-- Gather package (docs/map-gather-plan.md phase 3/4, own package by
-- Florian's choice): herbs, ore, fishing pools and treasure you gather are
-- recorded where you stood and shown on the world map and the minimap
-- (Core's pin layer). GatherMate2's database can be imported; with
-- GatherMate2 running, ours neither records nor draws by default, so the
-- two never double up (plan decision 3, "use ours anyway" takes it back).
-- Files fill G: Data (node database), Record, Pins, Import, Share, Route,
-- RouteGrid and RoutePlan (route editor), Trace (walked ways), Follow
-- (following a route), UI/Exchange,
-- UI/Editor, Options.
G.ns=ns
ns.Gather=G
G.ready=true
G.ID="gather"

-- Node kinds: GatherMate2's database name, our symbol and colour.
G.TYPES={
    {id="herb",label="Herbs",symbol="leaf",color={.35,.85,.4},gathermate="Herb Gathering",db="GatherMate2HerbDB"},
    {id="ore",label="Ore",symbol="pickaxe",color={.92,.6,.3},gathermate="Mining",db="GatherMate2MineDB"},
    {id="fish",label="Fishing pools",symbol="fish",color={.4,.7,1},gathermate="Fishing",db="GatherMate2FishDB"},
    {id="treasure",label="Treasure",symbol="gem",color={1,.82,.2},gathermate="Treasure",db="GatherMate2TreasureDB"},
}
G.TYPE={}
for _,t in ipairs(G.TYPES) do G.TYPE[t.id]=t end
-- Skill needed to gather a node (Herbalism, Mining; Classic values, Florian
-- 2026-10-09: shown in the route editor). English names, as nodes are named.
G.SKILL={
    ["Peacebloom"]=1,["Silverleaf"]=1,["Earthroot"]=15,["Mageroyal"]=50,["Briarthorn"]=70,["Stranglekelp"]=85,
    ["Bruiseweed"]=100,["Wild Steelbloom"]=115,["Grave Moss"]=120,["Kingsblood"]=125,["Liferoot"]=150,["Fadeleaf"]=160,
    ["Goldthorn"]=170,["Khadgar's Whisker"]=185,["Wintersbite"]=195,["Firebloom"]=205,["Purple Lotus"]=210,
    ["Arthas' Tears"]=220,["Sungrass"]=230,["Blindweed"]=235,["Ghost Mushroom"]=245,["Gromsblood"]=250,
    ["Golden Sansam"]=260,["Dreamfoil"]=270,["Mountain Silversage"]=280,["Plaguebloom"]=285,["Icecap"]=290,
    ["Black Lotus"]=300,["Bloodvine"]=300,
    ["Copper Vein"]=1,["Tin Vein"]=65,["Incendicite Mineral Vein"]=65,["Silver Vein"]=75,["Ooze Covered Silver Vein"]=75,
    ["Lesser Bloodstone Deposit"]=75,["Iron Deposit"]=125,["Ooze Covered Iron Deposit"]=125,["Indurium Mineral Vein"]=150,
    ["Gold Vein"]=155,["Ooze Covered Gold Vein"]=155,["Mithril Deposit"]=175,["Ooze Covered Mithril Deposit"]=175,
    ["Truesilver Deposit"]=230,["Ooze Covered Truesilver Deposit"]=230,["Dark Iron Deposit"]=230,["Small Thorium Vein"]=245,
    ["Ooze Covered Thorium Vein"]=245,["Rich Thorium Vein"]=275,["Ooze Covered Rich Thorium Vein"]=275,
    ["Hakkari Thorium Vein"]=275,["Small Obsidian Chunk"]=305,["Large Obsidian Chunk"]=305,
}
-- "Silverleaf (1)": a name with its skill, when known.
function G.WithSkill(name)
    local skill=type(name)=="string" and G.SKILL[name]
    return skill and (name.." ("..skill..")") or name
end

G.DEFAULTS={enabled=false,
    -- Where nodes show; which kinds; a name filter (comma separated, empty = all).
    world=true,minimap=true,minimapEdge=false,herb=true,ore=true,fish=true,treasure=true,filter="",
    -- Recording: merge distance in yards; with GatherMate2 running ours waits.
    record=true,merge=15,spawn=8,forceRecord=false,forceShow=false,routeUnderground=false,
    -- Route editor: loop, pass-by radius (yards), high-risk areas ("ignore",
    -- "avoid" where possible, "block" like no-go).
    loop=true,passRadius=45,risk="avoid",
    -- Route editor: terrain tiles (local Map Art data) over Blizzard's map.
    editorTerrain=true,editorNames=true,
    -- Route planning with the terrain data (slopes, water): use it, and how
    -- much water is avoided.
    routeTerrain=true,avoidWater=true,editorRelief=false,
    -- Enemy bases ("avoid" hard, "block" never, "ignore"); flight masters of
    -- your own faction only (and neutral ones).
    enemy="avoid",ownFlights=true,
    -- Cliffs down: "never", "safe" (short drops) or "always" (Slow Fall,
    -- Levitate); optional curves on the ways round.
    cliffs="safe",routeSmooth=false,
    -- Roads from the terrain data count as preferred ground.
    preferRoads=true,
    -- Walked ways: record them (heatmap) and prefer them in routes.
    recordWays=true,preferWalked=true,editorHeat=false,
    -- Following a route: colours (empty = the style's accent) and opacity of
    -- its lines and dots in percent.
    routeColor="",routeNextColor="5FD16B",routeLineAlpha=80,routeDotAlpha=100,
    -- Gather mode (the route shows only while it is on), its window, the
    -- route's lines.
    mode=false,modeWindow=false,routeLines=true,
    -- Tracker: price source ("auto", "tsm", "auctionator", "vendor"), all
    -- loot or only from gathering, its window.
    priceSource="auto",trackAllLoot=false,trackerWindow=false,
    -- HUD: size (percent of the screen height), opacity, turning with you.
    hudSize=80,hudAlpha=55,hudRotate=true,
    -- The minimap's shape after the HUD (turning it may reset the shape your
    -- interface package gave it; the client cannot tell which one it had).
    hudShape="keep",
    -- HUD turning (Florian 2026-10-09): "turn" with you, "north" up, or
    -- "keep" your minimap's setting; compass letters at its edge.
    hudTurn="turn",hudCompass=true,
    -- Known spawn points (the data package): shown, and used for routes.
    knownSpawns=true,routeKnown=true,
    -- Your own finds shown and used (a source like the others), and the
    -- other sources switched off by hand.
    ownFinds=true,sourceOff={},
    -- Route goal: "visit" every node or come "sight" of each (the minimap's
    -- Find Herbs dots show what lies within its view); the sight radius and
    -- a ring of it on the minimap.
    routeGoal="visit",sightRadius=150,sightCircle=false,
    -- Worth the way: yards of way a node may cost at most (0 = every node).
    worthLimit=0,
    -- Nodes you gathered show grey this many minutes (0: never); the tracker
    -- pauses after this many minutes without gathering (0: never).
    respawnMinutes=10,trackerIdle=5,
    -- When each kind shows (Visibility.lua): always, with the profession, with tracking on.
    herbWhen="always",oreWhen="always",fishWhen="always",treasureWhen="always",
    -- The circle's colour (empty: the style's accent) and its ring's opacity.
    sightColor="",sightAlpha=55,sightWidth=3,
    -- Following: only legs this close are looked at for joining (Florian 2026-10-09).
    followRange=300,
    -- Live sharing: send your new nodes ("off", "group", "guild", "both"),
    -- receive those of your group and guild.
    shareSend="off",shareReceive=true,
    -- Minimap scanner (Florian 2026-10-10): on, the list of herbs and ores
    -- with their sounds, the on-screen message, the default sound and its
    -- channel, minutes a node must be gone before it warns again.
    scanner=false,scanWatch={},scanStage=true,scanSound={source="soundkit",soundKit=8959},scanChannel="Master",scanRepeat=5,
    -- Windows opened and closed with the gather mode; the finds window.
    modeTracker=false,modeFinds=false,findsWindow=false,
    -- Pin colours per kind (hex RRGGBB); empty = the kind's own colour.
    herbColor="",oreColor="",fishColor="",treasureColor="",
    size=14,styleFamily="inherit"}
local function num(value,default,low,high)
    if type(value)~="number" or value~=value then value=default end
    return math.max(low,math.min(high,math.floor(value+.5)))
end
function G:Config()
    local cfg=ns.Settings:Module(self.ID)
    for key,value in pairs(self.DEFAULTS) do if cfg[key]==nil then cfg[key]=value end end
    for _,key in ipairs({"world","minimap","minimapEdge","herb","ore","fish","treasure","record","forceRecord","forceShow","shareReceive","routeUnderground","loop","editorTerrain","editorNames","routeTerrain","avoidWater","editorRelief","ownFlights","routeSmooth","preferRoads","recordWays","preferWalked","editorHeat","mode","modeWindow","routeLines","trackAllLoot","trackerWindow","hudRotate","knownSpawns","routeKnown","sightCircle","hudCompass","ownFinds","scanner","scanStage","modeTracker","modeFinds","findsWindow"}) do cfg[key]=cfg[key]==true end
    cfg.passRadius=num(cfg.passRadius,45,10,80)
    cfg.hudSize=num(cfg.hudSize,80,40,100);cfg.hudAlpha=num(cfg.hudAlpha,55,10,100)
    cfg.sightRadius=num(cfg.sightRadius,150,40,230);cfg.sightAlpha=num(cfg.sightAlpha,55,5,100);cfg.sightWidth=num(cfg.sightWidth,3,1,16)
    cfg.followRange=num(cfg.followRange,300,100,1500)
    cfg.worthLimit=num(cfg.worthLimit,0,0,600)
    cfg.respawnMinutes=num(cfg.respawnMinutes,10,0,60);cfg.trackerIdle=num(cfg.trackerIdle,5,0,30)
    if cfg.routeGoal~="sight" then cfg.routeGoal="visit" end
    cfg.routeLineAlpha=num(cfg.routeLineAlpha,80,10,100);cfg.routeDotAlpha=num(cfg.routeDotAlpha,100,10,100)
    for key,default in pairs({routeColor="",routeNextColor="5FD16B",sightColor=""}) do
        if type(cfg[key])~="string" or not (cfg[key]=="" or cfg[key]:match("^%x%x%x%x%x%x")) then cfg[key]=default end
    end
    if cfg.routeNextColor=="" then cfg.routeNextColor="5FD16B" end
    if not ({ignore=true,avoid=true,block=true})[cfg.risk] then cfg.risk="avoid" end
    if not ({ignore=true,avoid=true,block=true})[cfg.enemy] then cfg.enemy="avoid" end
    if not ({never=true,safe=true,always=true})[cfg.cliffs] then cfg.cliffs="safe" end
    if not ({auto=true,tsm=true,auctionator=true,vendor=true})[cfg.priceSource] then cfg.priceSource="auto" end
    if not ({keep=true,square=true,round=true})[cfg.hudShape] then cfg.hudShape="keep" end
    if type(cfg.sourceOff)~="table" then cfg.sourceOff={} end
    cfg.scanRepeat=num(cfg.scanRepeat,5,1,60)
    if not ns.Sound.channels[cfg.scanChannel] then cfg.scanChannel="Master" end
    local function sound(value)
        if type(value)~="table" then return nil end
        if value.source=="soundkit" and type(value.soundKit)=="number" and value.soundKit>0 then return {source="soundkit",soundKit=math.floor(value.soundKit)} end
        if value.source=="sharedmedia" and type(value.sound)=="string" and value.sound~="" then return {source="sharedmedia",sound=value.sound} end
    end
    cfg.scanSound=sound(cfg.scanSound) or {source="soundkit",soundKit=8959}
    -- In place: rows of the settings hold these entries and change their sound.
    if type(cfg.scanWatch)~="table" then cfg.scanWatch={} end
    local seen={}
    for i=#cfg.scanWatch,1,-1 do
        local entry=cfg.scanWatch[i]
        if type(entry)~="table" or type(entry.name)~="string" or entry.name=="" then table.remove(cfg.scanWatch,i)
        else
            if entry.sound~=false then entry.sound=sound(entry.sound) end
            seen[entry.name]=(seen[entry.name] or 0)+1
        end
    end
    for i=#cfg.scanWatch,1,-1 do
        local name=cfg.scanWatch[i].name
        if seen[name]>1 then seen[name]=seen[name]-1;table.remove(cfg.scanWatch,i) end
    end
    for _,t in ipairs(G.TYPES) do
        local key,ok=t.id.."When",false
        for _,value in ipairs(G.Visibility and G.Visibility.CHOICES[t.id] or {"always"}) do if cfg[key]==value then ok=true end end
        if not ok then cfg[key]="always" end
    end
    if not ({turn=true,north=true,keep=true})[cfg.hudTurn] then cfg.hudTurn=cfg.hudRotate==false and "keep" or "turn" end
    cfg.merge=num(cfg.merge,15,3,60);cfg.spawn=num(cfg.spawn,8,0,30);cfg.size=num(cfg.size,14,8,30)
    if type(cfg.filter)~="string" then cfg.filter="" end
    if not ({off=true,group=true,guild=true,both=true})[cfg.shareSend] then cfg.shareSend="off" end
    for _,t in ipairs(self.TYPES) do
        local key=t.id.."Color"
        if type(cfg[key])~="string" or not (cfg[key]=="" or cfg[key]:match("^%x%x%x%x%x%x")) then cfg[key]="" end
    end
    if cfg.styleFamily~="inherit" and not ns.Styles.families[cfg.styleFamily] then cfg.styleFamily="inherit" end
    return cfg
end
function G:Active() return self.context~=nil end
-- A kind's pin colour: the one set in the settings, else its own.
function G:Color(kind)
    local hex=self:Config()[kind.."Color"]
    if hex and hex~="" then local r,g,b=ns.UI:RGBA(hex:sub(1,6).."FF");return {r,g,b} end
    return self.TYPE[kind].color
end
function G.Hex(color) return string.format("%02X%02X%02X",color[1]*255,color[2]*255,color[3]*255) end
function G:Style() return ns.UI:GameStyle(self.ID) end
function G:Print(text) ns:Print(text,"Gather") end
function G.Call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
function G.Secret(value) return issecretvalue and issecretvalue(value) or false end

-- GatherMate2 running: it records and draws already (ours waits unless forced).
function G:GatherMate()
    local loaded=G.Call("C_AddOns.IsAddOnLoaded","GatherMate2")
    if loaded==nil then loaded=G.Call("IsAddOnLoaded","GatherMate2") end
    return loaded==true or loaded==1
end
function G:Recording() local c=self:Config();return self:Active() and c.record and (c.forceRecord or not self:GatherMate()) end
function G:Showing() local c=self:Config();return self:Active() and (c.forceShow or not self:GatherMate()) end

ns.Modules:Register({id=G.ID,OnEnable=function(context)
    G.context=context
    context:Defer(function() G.context=nil;G.Pins:Refresh() end)
    G:Config()
    G.Data:Init()
    G.Record:Enable(context)
    G.Pins:Enable(context)
    G.Share:Enable(context)
    G.Trace:Enable(context)
    G.Follow:Enable(context)
    G.Mode:Enable(context)
    G.Tracker:Enable(context)
    G.TrackerWindow:Enable(context)
    G.Expert:Apply()
    G.Hud:Enable(context)
    G.Visibility:Enable(context)
    G.Sight:Enable(context)
    G.Scanner:Enable(context)
    G.Finds:Enable(context)
end})

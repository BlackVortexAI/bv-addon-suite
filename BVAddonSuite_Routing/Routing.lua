local package,R=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.101 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.1.4","0.8.101",1) then return end
-- BV Routing (Florian 2026-10-10, docs/module-structure-routing.md): ways
-- you can really walk, round slopes, water, cliffs, enemy bases, painted
-- areas and walls, through cities and between their levels, by flight,
-- ship and zeppelin, instead of a straight line. Gather's route editor plans
-- with it; Map's way to a waypoint, Route Studio and Codex use it. No module
-- to switch on: it works for the packages that use it.
-- Files fill R: the terrain data (Terrain\Data_<map>.lua, from the client's
-- map files, about 9 MB, loaded at login like Gather's before; decoded tile
-- by tile when a way needs it), Grid (raster, terrain costs, walls, A*,
-- string pulling), Data\Transports (stops and round trips), Level (on which
-- level you are), Navigate (the travel plan and leading you along it),
-- Commands.
R.ns=ns
ns.Routing=R
R.ready=true
R.ID="routing"
-- What the shared store holds: areas, transitions, walls, levels (see Store).
R.STORE=1

-- How ways are found; shared by every package that asks for one.
R.DEFAULTS={
    -- Terrain data (slopes, water, heights): use it; swimming avoided.
    routeTerrain=true,avoidWater=true,
    -- Roads from the terrain data count as preferred ground.
    preferRoads=true,
    -- Painted high-risk areas and enemy bases: "ignore", "avoid" where
    -- possible, "block" like no-go.
    risk="avoid",enemy="avoid",
    -- Cliffs down: "never", "safe" (short drops) or "always" (Slow Fall, Levitate).
    cliffs="safe",
    -- The guide window while led (arrow, what comes next, time): "right" or
    -- "left" of the tour window when it is open, "free" where you drag it,
    -- "off" not shown; guideGround: with its background (Florian
    -- 2026-10-14: none by default, switched on in its menu; was guideBare).
    guide="right",guideGround=false,
    -- Flight masters on a continent whose flight map you have not opened
    -- yet (Florian 2026-10-15): "leave" them out (asked once, a hint in the
    -- guide) or count "all" of your side.
    flightsUnknown="leave",
    -- Colours of the way (Florian 2026-10-15: players set their own), as
    -- RRGGBB; empty: the built-in one.
    colorWalk="",colorFlight="",colorTransport="",colorTransition="",colorGoal="",
    -- The legs after the one you are on (Florian 2026-10-16: players set the
    -- dimming): the line's opacity at full dimming in percent (100: none)
    -- and over how many legs it gets there.
    aheadOpacity=30,aheadSteps=3}
-- Numbers kept in their range: {low, high}.
local RANGES={aheadOpacity={10,100},aheadSteps={1,6}}
local CHOICES={flightsUnknown={leave=true,all=true},risk={ignore=true,avoid=true,block=true},enemy={ignore=true,avoid=true,block=true},cliffs={never=true,safe=true,always=true},guide={left=true,right=true,free=true,off=true}}
function R:Config()
    local cfg=ns.Settings:Module(self.ID)
    -- These settings were Gather's until 2026-10-10: taken over once per profile.
    if cfg.moved~=1 then
        local gather=ns.Settings:Module("gather")
        for key in pairs(self.DEFAULTS) do
            if cfg[key]==nil and gather[key]~=nil then cfg[key]=gather[key] end
            gather[key]=nil
        end
        cfg.moved=1
    end
    for key,value in pairs(self.DEFAULTS) do if cfg[key]==nil then cfg[key]=value end end
    cfg.guideBare=nil
    for _,key in ipairs({"routeTerrain","avoidWater","preferRoads","guideGround"}) do cfg[key]=cfg[key]==true end
    for key,valid in pairs(CHOICES) do if not valid[cfg[key]] then cfg[key]=self.DEFAULTS[key] end end
    for key,range in pairs(RANGES) do
        local v=tonumber(cfg[key]) or self.DEFAULTS[key]
        cfg[key]=math.max(range[1],math.min(range[2],math.floor(v+.5)))
    end
    return cfg
end

-- The shared store, account-wide (BVRoutingDB):
--   areas[mapID]  painted strokes {x, y (map 0..1), r (yards), kind} or
--                 polygons {kind, poly = {x1, y1, ...}}
--   links         transitions {a = {mapID, x, y, level}, b = {...}, oneway,
--                 name, kind, seconds, path, condition}
--   walls[mapID]  {kind = "line" | "circle" | "arc", level, points =
--                 {x1, y1, ...} | x, y, r (yards), from, to (degrees)}
--   levels[mapID] {id, name, subzones = {...} (districts), waysOnly (only
--                 given ways walkable), open (unpainted walkable too,
--                 dearer)}; level nil or 0 is the ground
--   notes[mapID]  Route Studio's notes (what is left to do): {kind = "note",
--                 x, y, level, name}; the way finding does not read them
--   log[mapID]    Route Studio's change log: {at, by, action, kind, id, name, detail}
--   maps[mapID]   settings of a map: paintedOnly (its ground walkable only
--                 where painted), own (edited here: shipped data not read),
--                 mineOff / shippedOff (your own / the shipped data set off)
--   sets[id]      data sets (Florian 2026-10-11: a friend's import named,
--                 on or off, copied to your own): {id, name, map, key (who
--                 and which map it came from), by, at, off, own (a set of
--                 your own beside "Mine", 2026-10-13), export (goes into
--                 the export of the map)}. An element's set: element.set;
--                 none: your own of its map ("Mine")
--   source        what the way finding reads (Florian 2026-10-13): "studio"
--                 (nil; your Route Studio data, the shipped maps where you
--                 have none) or "shipped" (only the maps released with
--                 Routing, to try what players get)
--   ways[mapID]   given ways (Florian 2026-10-10): {points = {x1, y1, ...},
--                 level, oneway, name}; the search follows them exactly
-- Every element added from now on carries id (unique), by (who made it)
-- and at (when) for sharing and merging (Route Studio).
-- Fixed in place (callers and windows hold the tables; LEARNINGS 2026-10-10).
function R:Store()
    if type(BVRoutingDB)~="table" then BVRoutingDB={} end
    local db=BVRoutingDB
    for _,key in ipairs({"areas","links","walls","levels","ways","log","maps","notes","sets"}) do
        if type(db[key])~="table" then db[key]={} end
    end
    if type(db.seq)~="number" then db.seq=0 end
    db.version=R.STORE
    return db
end
-- A new id: unique per account (time, a counter, a random part), so
-- elements from two players never clash when merged.
function R:NewID()
    local db=self:Store()
    db.seq=db.seq+1
    return string.format("%x-%x-%x",time(),db.seq,math.random(0,0xFFFF))
end
function R:Author()
    local name=self.Call("UnitName","player")
    local realm=self.Call("GetRealmName")
    if type(name)~="string" or self.Secret(name) then return "?" end
    return name..((type(realm)=="string" and not self.Secret(realm)) and ("-"..realm) or "")
end
-- Gives an element its id, author and time when it has none.
function R:Stamp(element)
    if type(element)~="table" then return element end
    element.id=element.id or self:NewID()
    element.by=element.by or self:Author()
    element.at=element.at or time()
    return element
end

-- Painted strokes per map.
function R:Areas() return self:Store().areas end
function R:Strokes(mapID)
    local areas=self:Areas()
    if type(areas[mapID])~="table" then areas[mapID]={} end
    return areas[mapID]
end
-- Transitions.
function R:Links() return self:Store().links end
function R:AddLink(a,b,oneway,name,extra)
    local links=self:Links()
    local link={a=a,b=b,oneway=oneway or nil,name=name or ("Transition "..(#links+1))}
    for key,value in pairs(extra or {}) do link[key]=value end
    links[#links+1]=self:Stamp(link)
    R:SetsChanged()
    return link
end
function R:RemoveLink(index) table.remove(self:Links(),index);R:SetsChanged() end
-- Walls and levels per map.
function R:Walls(mapID)
    local walls=self:Store().walls
    if type(walls[mapID])~="table" then walls[mapID]={} end
    return walls[mapID]
end
function R:Ways(mapID)
    local ways=self:Store().ways
    if type(ways[mapID])~="table" then ways[mapID]={} end
    return ways[mapID]
end
function R:Notes(mapID)
    local notes=self:Store().notes
    if type(notes[mapID])~="table" then notes[mapID]={} end
    return notes[mapID]
end
-- A map's settings (maps[mapID]), made when asked for.
function R:MapSettings(mapID)
    local maps=self:Store().maps
    if type(maps[mapID])~="table" then maps[mapID]={} end
    return maps[mapID]
end
function R:Levels(mapID)
    local levels=self:Store().levels
    if type(levels[mapID])~="table" then levels[mapID]={} end
    return levels[mapID]
end
-- Shipped maps (Phase B, point 7; Florian 2026-10-11: "the maps as data in
-- Routing"): Data\Maps.lua (tools/build_routing_maps.py) brings painted
-- cities with Routing, SHIPPED[mapID] = {levels, areas, walls, ways, links,
-- settings}. The way finding reads them together with your own store
-- (R:Data): the same id counts once and yours wins. A map you edit in
-- Route Studio becomes yours (maps[mapID].own, the shipped copied in
-- first): from then on only your store counts there.
R.SHIPPED=R.SHIPPED or {}
R.KINDS={"areas","walls","ways","levels"}
function R:Own(mapID)
    local m=self:Store().maps[mapID]
    return type(m)=="table" and m.own==true
end
-- Yours and the shipped of one list, by id (cached while yours keeps its length).
local merged=setmetatable({},{__mode="k"})
local function merge(own,shipped)
    own=type(own)=="table" and own or {}
    local known=merged[shipped]
    if known and known.own==own and known.n==#own then return known.list end
    local seen,list={},{}
    for _,e in ipairs(own) do
        list[#list+1]=e
        if type(e)=="table" and e.id~=nil then seen[e.id]=true end
    end
    for _,e in ipairs(shipped) do
        if type(e)=="table" and not (e.id~=nil and seen[e.id]) then list[#list+1]=e;if e.id~=nil then seen[e.id]=true end end
    end
    merged[shipped]={own=own,n=#own,list=list}
    return list
end
-- What the way finding reads: the store, with the shipped maps that are
-- not yours laid in (the store itself while nothing is shipped).
-- Data sets switched off: their elements are kept, but not read. Is an
-- element's set off (mapID: the map it lies on, for your own set)?
R.offVersion=0
function R:SetOff(element,mapID)
    local db=self:Store()
    local id=type(element)=="table" and element.set
    if id~=nil then
        local set=db.sets[id]
        return type(set)=="table" and set.off==true
    end
    local m=db.maps[mapID]
    return type(m)=="table" and m.mineOff==true
end
function R:ShippedOff(mapID)
    local m=self:Store().maps[mapID]
    return type(m)=="table" and m.shippedOff==true
end
-- A set switched on or off (the cached lists are made anew).
function R:SetsChanged() R.offVersion=R.offVersion+1 end
local function anyOff(db)
    for _,set in pairs(db.sets) do if type(set)=="table" and set.off then return true end end
    for _,m in pairs(db.maps) do if type(m)=="table" and (m.mineOff or m.shippedOff) then return true end end
    return false
end
-- A list without the elements of sets switched off (cached while it keeps
-- its length and no set changes); the list itself when none is off.
local filtered=setmetatable({},{__mode="k"})
local function filter(self,list,mapID,linkList)
    if type(list)~="table" then return list end
    local known=filtered[list]
    if known and known.n==#list and known.v==R.offVersion then return known.list end
    local out,dropped={},false
    for _,e in ipairs(list) do
        local map=mapID
        if linkList and type(e)=="table" and type(e.a)=="table" then map=e.a.mapID end
        if self:SetOff(e,map) then dropped=true else out[#out+1]=e end
    end
    if not dropped then out=list end
    filtered[list]={n=#list,v=R.offVersion,list=out}
    return out
end
-- Where the way finding takes its maps from (Route Studio's switch).
function R:Source() local v=self:Store().source;return v=="shipped" and "shipped" or "studio" end
function R:SetSource(value)
    self:Store().source=value=="shipped" and "shipped" or nil
    R:SetsChanged()
end
-- Only the shipped maps (source "shipped"): your store not read at all.
local function shippedOnly()
    local view={}
    for _,kind in ipairs(R.KINDS) do
        local out={}
        for mapID,data in pairs(R.SHIPPED) do if type(data[kind])=="table" then out[mapID]=data[kind] end end
        view[kind]=out
    end
    local links,maps={},{}
    for mapID,data in pairs(R.SHIPPED) do
        if type(data.links)=="table" then links=merge(links,data.links) end
        if type(data.settings)=="table" then maps[mapID]=data.settings end
    end
    view.links,view.maps=links,maps
    return view
end
-- The view is built once and kept while its makings stay the same
-- (Florian/Codex 2026-10-14: built anew on every call it cost 1.2 s of a
-- way with all shipped capitals): the sets switched (offVersion), the
-- source, the length of every list, the maps' own/off marks. Elements
-- changed in place are the same tables in the view. R.dataVersion counts
-- the views built (caches of other parts key on it).
R.dataVersion=0
local view_,sig_
local function signature(db)
    -- (The store or the shipped data themselves replaced: another view.)
    local parts={R.offVersion,tostring(db.source),tostring(db),tostring(R.SHIPPED)}
    for _,kind in ipairs(R.KINDS) do
        for mapID,list in pairs(db[kind]) do if type(list)=="table" then parts[#parts+1]=kind..tostring(mapID)..":"..#list end end
    end
    parts[#parts+1]="links:"..#(db.links or {})
    for mapID,m in pairs(db.maps) do
        if type(m)=="table" then parts[#parts+1]=tostring(mapID)..(m.own and "o" or "")..(m.mineOff and "m" or "")..(m.shippedOff and "s" or "") end
    end
    return table.concat(parts,"|")
end
function R:Data()
    local db=self:Store()
    local sig=signature(db)
    if view_ and sig_==sig then return view_ end
    view_,sig_=self:BuildData(db),sig
    R.dataVersion=R.dataVersion+1
    return view_
end
function R:BuildData(db)
    if db.source=="shipped" then return shippedOnly() end
    local off=anyOff(db)
    if next(R.SHIPPED)==nil and not off then return db end
    local view={}
    for _,kind in ipairs(R.KINDS) do
        local out={}
        for mapID,list in pairs(db[kind]) do out[mapID]=off and filter(self,list,mapID) or list end
        for mapID,data in pairs(R.SHIPPED) do
            if type(data[kind])=="table" and not self:Own(mapID) and not self:ShippedOff(mapID) then out[mapID]=merge(out[mapID],data[kind]) end
        end
        view[kind]=out
    end
    local links=off and filter(self,db.links,nil,true) or db.links
    local maps={}
    for mapID,m in pairs(db.maps) do maps[mapID]=m end
    for mapID,data in pairs(R.SHIPPED) do
        if not self:Own(mapID) and not self:ShippedOff(mapID) then
            if type(data.links)=="table" then links=merge(links,data.links) end
            if type(data.settings)=="table" and type(maps[mapID])~="table" then maps[mapID]=data.settings end
        end
    end
    view.links,view.maps=links,maps
    return view
end
-- Read-only lists for one map (shipped included).
function R:ReadList(kind,mapID) local list=self:Data()[kind][mapID];return type(list)=="table" and list or {} end
function R:ReadLevels(mapID) return self:ReadList("levels",mapID) end
function R:ReadStrokes(mapID) return self:ReadList("areas",mapID) end
function R:ReadWays(mapID) return self:ReadList("ways",mapID) end
function R:ReadLinks() return self:Data().links end
-- A shipped map taken over for editing (Route Studio): what is shipped and
-- not yet in your store copied in (same ids), the map marked yours.
-- Returns how many elements were copied (nil: nothing shipped or yours).
local function copy(v)
    if type(v)~="table" then return v end
    local out={}
    for k,x in pairs(v) do out[k]=copy(x) end
    return out
end
function R:TakeOver(mapID)
    local data=R.SHIPPED[mapID]
    if type(data)~="table" or self:Own(mapID) then return nil end
    local db=self:Store()
    local n=0
    local function into(list,from)
        local seen={}
        for _,e in ipairs(list) do if type(e)=="table" and e.id~=nil then seen[e.id]=true end end
        for _,e in ipairs(type(from)=="table" and from or {}) do
            if type(e)=="table" and not (e.id~=nil and seen[e.id]) then list[#list+1]=copy(e);n=n+1 end
        end
    end
    into(self:Strokes(mapID),data.areas)
    into(self:Walls(mapID),data.walls)
    into(self:Ways(mapID),data.ways)
    into(self:Levels(mapID),data.levels)
    into(db.links,data.links)
    local m=self:MapSettings(mapID)
    for k,v in pairs(type(data.settings)=="table" and data.settings or {}) do if m[k]==nil then m[k]=copy(v) end end
    m.own=true
    return n
end
-- Areas and transitions another package kept until now join ours (Gather's
-- until 2026-10-10), kept as they were (no doubles: an adopted table is
-- marked).
function R:Adopt(areas,links)
    for zone,strokes in pairs(type(areas)=="table" and areas or {}) do
        if type(strokes)=="table" and type(zone)=="number" then
            local list=self:Strokes(zone)
            for _,stroke in ipairs(strokes) do list[#list+1]=stroke end
        end
    end
    local list=self:Links()
    for _,link in ipairs(type(links)=="table" and links or {}) do list[#list+1]=link end
end

-- Where you are: the best map for you and your place on it (nil in an
-- instance or where the client tells nothing).
function R:Position()
    local mapID=self.Call("C_Map.GetBestMapForUnit","player")
    if type(mapID)~="number" or self.Secret(mapID) then return nil end
    local position=self.Call("C_Map.GetPlayerMapPosition",mapID,"player")
    if type(position)~="table" and type(position)~="userdata" then return nil end
    local ok,x,y=pcall(position.GetXY,position)
    if not ok or type(x)~="number" or type(y)~="number" or self.Secret(x) or (x==0 and y==0) then return nil end
    return mapID,x,y
end
-- The continent a map lies on and a point of it there.
function R:OnContinent(mapID,x,y)
    local cont=ns.MapPins and ns.MapPins:Continent(mapID)
    if not cont then return nil end
    local cx,cy=self.Grid.Convert(mapID,cont,x,y)
    if not cx then return nil end
    return cont,cx,cy
end

-- The terrain data ships with Routing (Florian 2026-10-10: one package).
function R:Terrain() return type(rawget(_G,"BVTerrainData"))=="table" end

-- The log of the way (Florian 2026-10-14: the details in a window rather
-- than the chat): every message of Routing, said ones (Print) and quiet
-- ones (Note), with the time; LOGMAX lines kept, a new way marked.
R.LOGMAX=600
R.log={}
function R:Log(text,said)
    local line=string.format("%s %s%s",date("%H:%M:%S"),said and "" or "  ",tostring(text))
    local log=self.log
    log[#log+1]=line
    while #log>R.LOGMAX do table.remove(log,1) end
end
function R:Print(text) self:Log(text,true);ns:Print(text,"Routing") end
-- Into the log only (the details of a way).
function R:Note(text) self:Log(text,false) end
function R:LogText() return #self.log>0 and table.concat(self.log,"\n") or "Nothing logged yet." end
function R.Call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
function R.Secret(value) return issecretvalue and issecretvalue(value) or false end

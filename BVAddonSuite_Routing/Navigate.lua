local _,Routing=...
if not Routing.ready then return end
-- Leading you somewhere (Florian 2026-10-10; Gather's navigation prototype,
-- docs/handoffs/2026-10-10-encyclopedia-and-routing-prototype.md, made
-- Routing's own): /bv route <what> | way | <x> <y> | stop.
-- Two levels: a small travel graph (you, the goal, the flight masters you
-- know, zeppelin and ship stops, the Deeprun Tram, transitions between
-- levels) picks walking, flying, a transport or a transition by estimated
-- seconds; only the walking legs are searched on the grid (Routing.Grid,
-- 8 yards a cell; one grid per continent and level). The way shows as lines
-- on the map and the minimap (walk cyan, flight yellow, transport blue,
-- transition violet; legs on another level than yours fainter on the
-- minimap); you leave the way and it is searched again from where you are.
-- Flight masters come from the client; Map Data (optional) adds targets by
-- name; Map (optional) adds the flight times it learned.
local ns=Routing.ns
local N={}
Routing.Navigate=N
N.WALK=7          -- yards a second on foot
N.MOUNT=1.6       -- mounted from level 40 (Classic riding)
N.DETOUR=1.3      -- a walked way is about this much longer than the line
N.FLY=30          -- yards a second on a flight, the line times DETOUR
N.TAKEOFF=15      -- seconds at a flight master (talk, take off, land)
N.WAIT=.75        -- of a transport's round trip: half waiting, half riding
N.PASS=5          -- seconds through a transition without its own time
N.ARRIVE=15       -- yards to the goal that count as arrived
N.APART=1.5       -- yards between the goal and where its way ends to mark both
N.REACH=60        -- yards to a step's end that count as reached
N.OFF=40          -- yards off the walked way that start a new search
N.PORTAL=20       -- yards to where a teleport lands that count as through it
N.DOOR=15         -- yards to a transition's end that count as reached (cities:
                  -- doors and stairs lie close together)
N.SHAPEEND=4      -- yards left of a walked shape (stairs, a ramp round a tower) that
                  -- count as its end (Florian 2026-10-13: with DOOR, half a turn of
                  -- Orgrimmar's flight tower ramp, the guide went on a turn early)
N.LEAVE=20        -- a transition on one spot (a lift): this far from it again,
                  -- along the next leg, and it was taken
N.SPOT=8          -- ends closer than this: a transition on one spot (a lift, a
                  -- spiral stair); farther: you come out at its other end
                  -- (Florian 2026-10-11: 19.6 yards apart counted as one spot
                  -- under the old 20, and the last step into the Apothecarium hung)
N.UNSURE=8        -- yards: streets of two levels this close in distance to you
                  -- leave your level open (the plan starts on either)
N.OTHERSTART=900  -- seconds a start on another level than the one Routing
                  -- knows costs (only when no way leads on from that one)
N.STARTWEIGHT=3   -- unknown level: a level's street farther than the nearest
                  -- costs this many times its extra walk
N.LIMIT=200000    -- cells a search may look at
N.GROUNDLIMIT=100000 -- on the ground (Codex 2026-10-16: the 52 reference ways
                  -- need at most 18,191 there and stay the same; Crossroads
                  -- to Silithus on foot 37 -> 4.7 s offline before it gives up)
N.WEIGHT=1        -- the search heads for the goal (Grid.Search weight; measured
                  -- 2026-10-10 on Kalimdor: Ratchet -> Nartok 116,000 cells at 1,
                  -- 44,000 at 4, the way 2 % longer). 1 since 2026-10-16 (Florian:
                  -- roads ignored; Codex's matrix: at 4 a fifth of the ground on
                  -- roads, at 1 two thirds; 640/640 found, median 0.6 s, max 2.3 s
                  -- offline; 1.5 to 3 still miss roads in some cases)
N.BUDGET=14       -- ms a frame while searching (the grid's own 8 for routes)
N.ZTIE=2          -- yards: goal levels fitting about as well are told apart by the nearest street
N.REPLAN=10       -- plans tried with the walked lengths found (then the best searched through)
N.NEAR=3          -- precomputed walks' anchors a start or goal joins
N.JOINSECONDS=10  -- seconds a walk joining the precomputed walks may search
N.NEARJOINSECONDS=3 -- the same when only the short-way rule (Transit NEARNODE) joined the network
N.WIDESECONDS=30  -- seconds a walk may search when the network found no way
N.WIDETOTAL=45    -- seconds all such walks of one way may search together
N.SPUR=12         -- yards: a walk going back along the one before it this near is cut there
N.NEARZONE=200    -- yards an anchor in the start's or goal's own zone counts nearer
N.NEARCELL=250    -- yards a cell of the grid the nearest anchors are looked up in
N.LOCALWALK=400   -- yards a guessed walk between two nodes off the network may have (with the network in)
N.JOINEXACT=2     -- yards: a start or goal this near an anchor joins that anchor only
N.WAYEND=15       -- yards: a goal on a level this near the last point of its way ends there
N.NOWAY=1e7       -- yards a leg without a walkable way counts (never chosen
                  -- while any other way exists)
N.CONTINENTS={1414,1415}
-- Capitals: their streets come from walked ways and painted streets
-- (Grid.Cities). Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff,
-- Undercity.
N.CITIES={1453,1455,1457,1454,1456,1458}
-- Transitions magenta (Florian 2026-10-14: purple was hard to see on
-- Undercity's minimap; Route Studio keeps its own purple).
N.COLOR={walk={.3,.85,1},flight={1,.8,.2},transport={.45,.6,1},transition={1,.3,.8},goal={1,1,1}}
-- Your own colours (Florian 2026-10-15), set on Routing's settings page.
N.COLORKEY={walk="colorWalk",flight="colorFlight",transport="colorTransport",transition="colorTransition",goal="colorGoal"}
local hexColors={}
function N:Color(kind)
    local key=N.COLORKEY[kind] and kind or "walk"
    local hex=Routing:Config()[N.COLORKEY[key]]
    if type(hex)=="string" and hex:match("^%x%x%x%x%x%x") then
        hex=hex:sub(1,6):upper()
        local c=hexColors[hex]
        if not c then c={tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255};hexColors[hex]=c end
        return c
    end
    return N.COLOR[key]
end
function N.Hex(c) return string.format("%02X%02X%02X",math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5)) end
N.VERB={walk="Walk",lift="Take the lift",jump="Jump down",teleport="Use the teleport",transport="Ride"}

local function call(...) return Routing.Call(...) end
local function data() return rawget(_G,"BVMapData") end
local function rows(list,stride)
    local i=-stride
    return function()
        i=i+stride
        if list and i+stride<=#list then local r={};for j=1,stride do r[j]=list[i+j] end;return r end
    end
end
-- Faction masks: 1 Horde, 2 Alliance, 3 both.
local function shares(a,b) return (a%2==1 and b%2==1) or (math.floor(a/2)%2==1 and math.floor(b/2)%2==1) end
function N.Faction()
    local group=call("UnitFactionGroup","player")
    return group=="Horde" and 1 or group=="Alliance" and 2 or 3
end
-- Yards between two points of one continent map.
local sizes={}
function N.Yards(cont,x1,y1,x2,y2)
    local s=sizes[cont]
    if not s then
        local w,h=call("C_Map.GetMapWorldSize",cont)
        s={type(w)=="number" and w or 0,type(h)=="number" and h or 0};sizes[cont]=s
    end
    local dx,dy=(x2-x1)*s[1],(y2-y1)*s[2]
    return math.sqrt(dx*dx+dy*dy)
end
-- Where you are, on your continent map, and your level.
function N:Here()
    local mapID,x,y=Routing:Position()
    if not mapID then return nil end
    local cont,cx,cy=Routing:OnContinent(mapID,x,y)
    if not cont then return nil end
    return cont,cx,cy,Routing.Level:Current()
end
function N:Speed()
    local level=call("UnitLevel","player")
    return N.WALK*((type(level)=="number" and level>=40) and N.MOUNT or 1)
end

-- Flight masters, from the client (C_TaxiMap.GetTaxiNodesForMap: every
-- flight master of a continent with its faction); Map Data's list where the
-- client gives none. {cont, x, y, name, mask}.
function N:FlightMasters()
    if self.flights then return self.flights end
    local out={}
    local XY=ns.MapPins and ns.MapPins.XY
    for _,cont in ipairs(N.CONTINENTS) do
        local nodes=call("C_TaxiMap.GetTaxiNodesForMap",cont)
        for _,node in ipairs(type(nodes)=="table" and nodes or {}) do
            if type(node)=="table" and type(node.name)=="string" and not Routing.Secret(node.name) and node.position and XY then
                local ok,x,y=pcall(XY,node.position)
                -- Enum.FlightPathFaction: 0 neutral, 1 Horde, 2 Alliance.
                local mask=node.faction==1 and 1 or node.faction==2 and 2 or 3
                if ok and type(x)=="number" and type(y)=="number" then out[#out+1]={cont=cont,x=x,y=y,name=node.name,mask=mask} end
            end
        end
    end
    local d=data()
    -- Map Data's heights of the flight masters, by name (a tower's top).
    local heights={}
    local zi
    for i,f in ipairs(d and d.fields and d.fields.flights or {}) do if f=="z" then zi=i end end
    -- The client's nodes when it tells them, else Map Data's.
    local fromClient=#out>0
    if d and d.flights and d.fields then
        for _,cont in ipairs(N.CONTINENTS) do
            for r in rows(d.flights[cont],#d.fields.flights) do
                local name=d.strings[r[3]] or "?"
                if zi then heights[name]=r[zi] end
                if not fromClient then out[#out+1]={cont=cont,x=r[1],y=r[2],name=name,mask=r[4]} end
            end
        end
    end
    for _,f in ipairs(out) do f.z=heights[f.name] end
    if #out>0 then self.flights=out end
    return out
end
-- The level a flight master stands on (Florian 2026-10-11: Orgrimmar's on
-- its tower, "Fly Top"): by its height like any goal; nil on the ground.
-- Kept for a few seconds (Route Studio may change the levels).
N.FLIGHTLEVELS=5
function N:FlightLevel(f)
    local now=GetTime()
    if not self.flightLevels or now-(self.flightLevelsAt or 0)>N.FLIGHTLEVELS then self.flightLevels,self.flightLevelsAt={},now end
    local known=self.flightLevels[f]
    if known==nil then
        known=false
        if f.z then
            local level=self:GoalLevel({cont=f.cont,x=f.x,y=f.y,z=f.z,name=f.name})
            known=level or false
        end
        self.flightLevels[f]=known
    end
    return known or nil
end
-- A stop without its height (TRANSPORTS {cont, x, y, name}): the level of
-- the street it lies on, kept like flight masters' levels.
function N:StopLevel(stop)
    local now=GetTime()
    if not self.stopLevels or now-(self.stopLevelsAt or 0)>N.FLIGHTLEVELS then self.stopLevels,self.stopLevelsAt={},now end
    local known=self.stopLevels[stop]
    if known==nil then
        known=self:GoalLevel({cont=stop[1],x=stop[2],y=stop[3],name=stop[4]}) or false
        self.stopLevels[stop]=known
    end
    return known or nil
end
-- Flight masters you know, per character: remembered when a flight map
-- opens. Until then every one of your faction counts (said in the report).
function N:Known()
    local db=Routing:Store()
    db.flights=type(db.flights)=="table" and db.flights or {}
    local who=Routing:Author()
    db.flights[who]=type(db.flights[who])=="table" and db.flights[who] or {}
    return db.flights[who]
end
-- Per character and continent (Florian 2026-10-15: a flight map shows
-- only its own continent; the client tells no unknown flight points
-- elsewhere, C_TaxiMap's isUndiscovered is false for all): the continents
-- whose flight map you opened, and those you chose to go on without.
N.CONTNAME={[1414]="Kalimdor",[1415]="the Eastern Kingdoms"}
N.FLIGHTASK=1000   -- yards: a way at least this far (or to the other continent) may fly
local function perCharacter(key)
    local db=Routing:Store()
    db[key]=type(db[key])=="table" and db[key] or {}
    local who=Routing:Author()
    return db[key],who
end
function N:FlightConts()
    local all,who=perCharacter("flightConts")
    local t=all[who]
    if type(t)~="table" then
        -- Known before this was kept: the continents of the flight masters known.
        t={}
        local known=self:Known()
        for _,f in ipairs(self:FlightMasters()) do if known[f.name] then t[f.cont]=true end end
        all[who]=t
    end
    return t
end
function N:FlightSkips()
    local all,who=perCharacter("flightSkips")
    all[who]=type(all[who])=="table" and all[who] or {}
    return all[who]
end
-- Known: the flight map's current and reachable ones. Forever lists the
-- undiscovered flight points of the continent too, as DISTANT, and does not
-- draw them (Florian 2026-10-15: Booty Bay counted as known, the map showed
-- three points); so the map is the truth for its continent, earlier wrong
-- entries there go.
N.TAXIKNOWN={CURRENT=true,REACHABLE=true}
function N:TaxiOpened()
    local known=self:Known()
    local seen={}
    for i=1,(call("NumTaxiNodes") or 0) do
        local kind,name=call("TaxiNodeGetType",i),call("TaxiNodeName",i)
        if type(name)=="string" and not Routing.Secret(name) and N.TAXIKNOWN[kind] then seen[name]=true;known[name]=true end
    end
    local mapID,x,y=Routing:Position()
    local cont=mapID and Routing:OnContinent(mapID,x,y)
    if not cont then return end
    for _,f in ipairs(self:FlightMasters()) do
        if f.cont==cont and known[f.name] and not seen[f.name] then known[f.name]=nil end
    end
    local first=not self:FlightConts()[cont]
    self:FlightConts()[cont]=true
    self:FlightSkips()[cont]=nil
    -- Led without your flight points there: planned anew with them.
    if first and self.flightNote and self.goal and self.steps and not self.busy then
        Routing:Print(string.format("Your flight points on %s are known now: the way is planned anew.",N.CONTNAME[cont] or "this continent"))
        self:Restart()
    end
end
-- Continents of a way (where you are, where it goes) whose flight points
-- are not known, when flying may matter there; {} with "count all".
function N:FlightsMissing(goal)
    if Routing:Config().flightsUnknown=="all" or not Routing:Config().useFlights then return {} end
    local cont,px,py=self:Here()
    if not cont then return {} end
    if goal.cont==cont and N.Yards(cont,px,py,goal.x,goal.y)<N.FLIGHTASK then return {} end
    local known,out,seen=self:FlightConts(),{},{}
    for _,c in ipairs({cont,goal.cont}) do
        if c and N.CONTNAME[c] and not known[c] and not seen[c] then seen[c]=true;out[#out+1]=c end
    end
    return out
end
function N.ContNames(list)
    local names={}
    for _,c in ipairs(list) do names[#names+1]=N.CONTNAME[c] or tostring(c) end
    return table.concat(names," and ")
end
function N:FlightSeconds(a,b)
    local map=ns.Map
    local times=map and map.FlightTimes
    local store=times and times.Store and times:Store()
    local entry=store and times.Key and store[times.Key(a.name,b.name)]
    if type(entry)=="table" and type(entry.seconds)=="number" then return entry.seconds+N.TAKEOFF,true end
    return N.Yards(a.cont,a.x,a.y,b.x,b.y)*N.DETOUR/N.FLY+N.TAKEOFF,false
end

-- Targets by text (Map Data): instance entrances, flight masters, NPCs
-- (name or title; services of the other faction left out), "my trainer"
-- for your class. Without Map Data: only map pins and coordinates.
function N:Find(text)
    local d=data()
    if not (d and d.fields) then return nil,"Finding places by name needs BV Map Data. Without it: /bv route way (your map pin) or /bv route <x> <y>." end
    text=text:lower()
    local mine=N.Faction()
    local cont,px,py=self:Here()
    local _,_,classID=call("UnitClass","player")
    local classTrainer=text=="my trainer" or text=="class trainer" or text=="trainer"
    local best,bestScore
    -- The height of each kind of row (Map Data 2026-10-11 on; older data: none).
    local function zAt(list,name) for i,f in ipairs(list or {}) do if f==name then return i end end end
    local zNpc,zEntrance=zAt(d.fields.npc,"z"),zAt(d.fields.entrances,"z")
    local function consider(c,x,y,name,label,z)
        local score=(c==cont and px) and N.Yards(c,px,py,x,y) or 1e9
        if not bestScore or score<bestScore then best,bestScore={cont=c,x=x,y=y,name=name,label=label,z=z},score end
    end
    for _,c in ipairs(N.CONTINENTS) do
        for r in rows(d.entrances and d.entrances[c],#d.fields.entrances) do
            local name=d.strings[r[3]] or ""
            if not classTrainer and name:lower():find(text,1,true) then consider(c,r[1],r[2],name,"entrance",zEntrance and r[zEntrance]) end
        end
        for r in rows(d.flights and d.flights[c],#d.fields.flights) do
            local name=d.strings[r[3]] or ""
            if not classTrainer and shares(r[4],mine) and (name:lower():find(text,1,true) or (text=="flight" or text=="flight master")) then consider(c,r[1],r[2],name,"flight master") end
        end
        for r in rows(d.npc and d.npc[c],#d.fields.npc) do
            local name,sub=d.strings[r[3]] or "",d.strings[r[4]] or ""
            -- hostile: 1 to the Alliance, 2 to the Horde (not the faction mask).
            local hostile=shares(r[6],mine==1 and 2 or mine==2 and 1 or 3)
            local service=r[5]~=0
            local ok
            if classTrainer then ok=not hostile and r[8]~=0 and math.floor(r[8]/16)==0 and r[8]%16==classID
            else ok=(name:lower():find(text,1,true) or sub:lower():find(text,1,true)) and not (hostile and service) end
            if ok then consider(c,r[1],r[2],name,sub~="" and sub or "creature",zNpc and r[zNpc]) end
        end
    end
    if not best then return nil,"Nothing found for \""..text.."\"." end
    return best
end

-- The travel graph: you, the goal, known flight masters of your faction,
-- transport stops, transitions between levels. Dijkstra on estimated seconds.
-- A node: {cont, x, y, level (nil: the ground), kind, name}.
-- One empty list for "nothing" in the search's loops (a new {} for every node was garbage).
local EMPTY={}
local function key(n)
    -- A precomputed walk's node by its own key (Transit.lua), never by position.
    if n.tkey then return n.tkey end
    return string.format("%d:%.4f:%.4f:%s",n.cont,n.x,n.y,tostring(n.level or 0))
end
N.Key=key
-- A transition's walked shape (link.path: x1, y1, ... on its start's map)
-- as continent points {{x, y}, ...} from a to b; nil without one.
function N:LinkPath(link,cont)
    local p=type(link)=="table" and link.path
    if type(p)~="table" or #p<6 or type(link.a)~="table" then return nil end
    local out={}
    for i=1,#p-1,2 do
        local c,x,y=Routing:OnContinent(link.a.mapID,p[i],p[i+1])
        if c~=cont then return nil end
        out[#out+1]={x,y}
    end
    -- A lift's cabin way stays as measured (Codex 2026-10-16: the Great
    -- Lift's rounded cabin way cut the bottom edge).
    if link.kind=="lift" then return out end
    -- Drawn by clicks: its corners rounded (a ramp round a tower).
    return Routing.Grid.Round(out,function(ax,ay,bx,by) return N.Yards(cont,ax,ay,bx,by) end)
end
function N.Length(cont,points)
    local yards=0
    for i=2,#points do yards=yards+N.Yards(cont,points[i-1][1],points[i-1][2],points[i][1],points[i][2]) end
    return yards
end
-- An edge (Florian 2026-10-13: two large areas meeting edge to edge, a
-- level changed anywhere along it): link.edge = {x1, y1, ...} on its map,
-- link.edgeSide = 1 when level a lies to the left of it (drawn first to
-- last), -1 to the right. Planned as transitions across it every EDGESTEP
-- yards, EDGEOFF yards into either level: the plan takes the one that
-- makes the shortest way. Returns {{ax, ay, bx, by}, ...} on the map.
N.EDGESTEP=6
N.EDGEOFF=5
function N.EdgeCrossings(link)
    local p=link.edge
    if type(p)~="table" or #p<4 then return {} end
    local w,h=call("C_Map.GetMapWorldSize",link.a.mapID)
    if type(w)~="number" or w<=0 then w,h=1000,1000 end
    local side=link.edgeSide==-1 and -1 or 1
    local out={}
    local carry=N.EDGESTEP/2
    for i=1,#p-3,2 do
        local x1,y1,x2,y2=p[i],p[i+1],p[i+2],p[i+3]
        local dx,dy=(x2-x1)*w,(y2-y1)*h
        local len=math.sqrt(dx*dx+dy*dy)
        if len>0 then
            -- Left of the way drawn (in yards), to map units.
            local nx,ny=-dy/len,dx/len
            local ox,oy=nx*N.EDGEOFF/w*side,ny*N.EDGEOFF/h*side
            local at=carry
            while at<=len do
                local t=at/len
                local x,y=x1+(x2-x1)*t,y1+(y2-y1)*t
                out[#out+1]={x+ox,y+oy,x-ox,y-oy}
                at=at+N.EDGESTEP
            end
            carry=at-len
        end
    end
    -- A short edge: at least its middle.
    if #out==0 then
        local x,y=(p[1]+p[#p-1])/2,(p[2]+p[#p])/2
        local dx,dy=(p[#p-1]-p[1])*w,(p[#p]-p[2])*h
        local len=math.max(1e-9,math.sqrt(dx*dx+dy*dy))
        local ox,oy=-dy/len*N.EDGEOFF/w*side,dx/len*N.EDGEOFF/h*side
        out[1]={x+ox,y+oy,x-ox,y-oy}
    end
    return out
end
-- Transitions between levels (Route Studio): both ends on a continent.
-- Kept while the data stay the same (Routing.dataVersion; Florian/Codex
-- 2026-10-14: rebuilt on every plan round).
function N:Doors()
    Routing:Data()
    local cache=self.doorsCache
    if cache and cache.v==Routing.dataVersion then return cache.list end
    local out={}
    for _,link in ipairs(Routing:ReadLinks()) do
        if type(link)=="table" and type(link.a)=="table" and type(link.b)=="table" and (link.a.level or 0)~=(link.b.level or 0) and type(link.edge)=="table" then
            local name=link.name or "Edge"
            for _,c in ipairs(N.EdgeCrossings(link)) do
                local ca,ax,ay=Routing:OnContinent(link.a.mapID,c[1],c[2])
                local cb,bx,by=Routing:OnContinent(link.b.mapID,c[3],c[4])
                if ca and cb then
                    local a={cont=ca,x=ax,y=ay,level=link.a.level,kind="door",name=name,link=link,side="a"}
                    local b={cont=cb,x=bx,y=by,level=link.b.level,kind="door",name=name,link=link,side="b"}
                    out[#out+1]={a,b,link,edge=true}
                end
            end
        -- Between levels, or a lift also between two ground places (the Great
        -- Lift: wait for it and ride, Codex 2026-10-16).
        elseif type(link)=="table" and type(link.a)=="table" and type(link.b)=="table" and ((link.a.level or 0)~=(link.b.level or 0) or link.kind=="lift") then
            local ca,ax,ay=Routing:OnContinent(link.a.mapID,link.a.x,link.a.y)
            local cb,bx,by=Routing:OnContinent(link.b.mapID,link.b.x,link.b.y)
            if ca and cb then
                local name=link.name or "Transition"
                local a={cont=ca,x=ax,y=ay,level=link.a.level,kind="door",name=name,link=link,side="a"}
                local b={cont=cb,x=bx,y=by,level=link.b.level,kind="door",name=name,link=link,side="b"}
                out[#out+1]={a,b,link}
            end
        end
    end
    self.doorsCache={v=Routing.dataVersion,list=out}
    return out
end
-- Estimated seconds from a point to a goal ({cont, x, y, level}) by the
-- travel plan (walking, flights, transports, transitions); nil when there
-- is no way. No grid search: quick enough to compare many pairs.
function N:Estimate(from,to)
    local steps,seconds=self:Plan({cont=to.cont,x=to.x,y=to.y,level=to.level,name=to.name or "goal"},nil,from)
    if not steps then return nil end
    return seconds
end
-- The times to several places from one start, in one plan (Florian
-- 2026-10-14: Codex's "Navigate now" on a class trainer planned once for
-- each of its places and froze the game a moment): {seconds or false}, by
-- the places' order; each the time Estimate gives.
function N:EstimateMany(from,list)
    local goals={}
    for i,to in ipairs(list) do goals[i]={cont=to.cont,x=to.x,y=to.y,level=to.level,name=to.name or "goal"} end
    if #goals==0 then return {} end
    local times=self:Plan(goals[1],nil,from,goals)
    local out={}
    for i=1,#goals do out[i]=type(times)=="table" and times[i] or false end
    return out
end
-- known: [from key .. ">" .. to key] = walked yards found by a search.
-- from: a start other than where you are ({cont, x, y, level}; Codex's
-- tours estimate from one stop to the next); its level is taken as known.
-- A city as the goal (Florian 2026-10-14: Orgrimmar's middle lay on its
-- Cleft of Shadow; "we know all the cities' entrances, use them"): the
-- entrance quickest from you, on its ground side; a transition from the
-- ground onto one of the city's levels (one way only inward). A zone, or
-- a city without levels: its middle as before.
-- The six capitals (Grid's lists of both sides).
function N.IsCapital(mapID)
    local G=Routing.Grid
    for _,list in ipairs({G.HORDECAPITALS or {},G.ALLIANCECAPITALS or {}}) do
        for _,id in ipairs(list) do if id==mapID then return true end end
    end
    return false
end
function N:CityEntrance(goal)
    if goal.label~="Zone" or goal.entrance then return end
    local info=call("C_Map.GetMapInfoAtPosition",goal.cont,goal.x,goal.y)
    local mapID=type(info)=="table" and info.mapID
    if not mapID then return end
    -- Only the capitals (Codex 2026-10-20: Thousand Needles as a goal went to
    -- Freewind Post's lift, its levels lie on the zone's own map).
    if not N.IsCapital(mapID) then return end
    local ids,any={},false
    for _,level in ipairs(Routing:ReadLevels(mapID) or {}) do if type(level)=="table" and level.id~=nil then ids[level.id]=true;any=true end end
    if not any then return end
    local list,seen={},{}
    for _,door in ipairs(self:Doors()) do
        local a,b,link=door[1],door[2],door[3]
        local ground
        if (a.level or 0)==0 and ids[b.level] then ground=a
        elseif (b.level or 0)==0 and ids[a.level] and not link.oneway then ground=b end
        if ground and ground.cont==goal.cont then
            local k=key(ground)
            if not seen[k] then seen[k]=true;list[#list+1]={cont=ground.cont,x=ground.x,y=ground.y,name=ground.name} end
        end
    end
    if #list==0 then return end
    local cont,px,py,level=self:Here()
    if not cont then return end
    local times=self:EstimateMany({cont=cont,x=px,y=py,level=level},list)
    local best,bestT
    for i,t in ipairs(times) do if t and (not bestT or t<bestT) then best,bestT=list[i],t end end
    if not best then return end
    -- All of them goals; the plan's walked ways choose (N:Plan).
    goal.x,goal.y,goal.level,goal.ground,goal.entrance,goal.entrances=best.x,best.y,nil,true,true,list
    Routing:Note(string.format("%s: to whichever of its %d entrances the way reaches first (by the line: %s).",goal.name,#list,tostring(best.name)))
end
-- No way through the precomputed walks: wide (the network with guessed walks between),
-- or, when only the short-way rule (Transit NEARNODE) turned it on, on the ground as
-- before that rule (Codex 2026-10-20, Mountaineer Grugelm).
function N:LeaveNetwork()
    -- On the ground only when a join ran out of time (a way may exist, Grugelm); joins
    -- proved without a way keep the quick wide plan (Codex 2026-10-20: Johan Focht,
    -- 1.5 s with it, 65 s of searches on the ground).
    if self.nearOnly and self.nearLimit then
        self.noNear=true;self.nearOnly=nil
        Routing:Note("No way through the precomputed walks near you: planned on the ground.")
    else
        self.transitWide=true
        Routing:Note("No way through the precomputed walks: planned without them.")
    end
end
-- Gives the frame back when the slice is used up (Grid.Breathe), in a coroutine.
function N.Breathe() local G=Routing.Grid;if G and G.Breathe then G.Breathe() end end
-- A walk's key "a>b" split into its two node keys, kept (the network's 15000
-- keys were split again for every plan; Claude 2026-10-20).
N.splitKeys,N.splitCount={},0
function N.SplitKey(k)
    local t=N.splitKeys[k]
    if t==nil then
        local a,b=k:match("^(.-)>(.*)$")
        -- Searched walks add keys of their own: emptied before it grows without end.
        if N.splitCount>=60000 then N.splitKeys,N.splitCount={},0 end
        t=a and {a,b} or false;N.splitKeys[k]=t;N.splitCount=N.splitCount+1
    end
    if t then return t[1],t[2] end
end
-- many: several goals (EstimateMany), goal the first of them; the times
-- to each are returned ({seconds or false}), no steps.
function N:Plan(goal,known,from,many,groundDetour)
    local cont,px,py,level
    if from then cont,px,py,level=from.cont,from.x,from.y,from.level else cont,px,py,level=self:Here() end
    if not cont then return nil,"No position here (instance?)." end
    local mine=N.Faction()
    local speed=self:Speed()
    local goalNode={cont=goal.cont,x=goal.x,y=goal.y,level=goal.level,kind="goal",name=goal.name}
    local goalNodes,left
    if many then
        goalNodes={goalNode}
        for i=2,#many do local g=many[i];goalNodes[i]={cont=g.cont,x=g.x,y=g.y,level=g.level,kind="goal",name=g.name} end
        left=#goalNodes
    end
    local nodes={{cont=cont,x=px,y=py,level=level,kind="start",name="you"},goalNode}
    -- Your level open: a start on each level it may be, at a cost
    -- (startLevels: {{level (false: the ground), cost (seconds)}}).
    local starts={nodes[1]}
    if self.startLevels and not from then
        starts={}
        for i,st in ipairs(self.startLevels) do
            local node={cont=cont,x=px,y=py,level=st.level or nil,kind="start",name="you",cost=st.cost or 0}
            starts[i]=node
            if i==1 then nodes[1]=node else nodes[#nodes+1]=node end
        end
    end
    local flights,anyKnown=self:Known(),false
    for _ in pairs(flights) do anyKnown=true;break end
    -- Per continent: where its flight map was opened, the flight points you
    -- know; elsewhere none (or all, by the setting).
    local conts,countAll=self:FlightConts(),Routing:Config().flightsUnknown=="all"
    for _,f in ipairs(Routing:Config().useFlights and self:FlightMasters() or {}) do
        if shares(f.mask,mine) and ((conts[f.cont] and flights[f.name]) or (not conts[f.cont] and countAll)) then nodes[#nodes+1]={cont=f.cont,x=f.x,y=f.y,kind="flight",name=f.name,level=self:FlightLevel(f)} end
    end
    for _,t in ipairs(Routing.TRANSPORTS or {}) do
        if shares(t.faction,mine) then
            -- The tram's stations lie in its cities' streets (Florian
            -- 2026-10-15: never taken, its stops counted as the ground):
            -- the level of the street nearest them.
            local tram=t.kind=="tram"
            local a={cont=t.a[1],x=t.a[2],y=t.a[3],kind="dock",name=t.a[4],level=tram and self:StopLevel(t.a) or nil}
            local b={cont=t.b[1],x=t.b[2],y=t.b[3],kind="dock",name=t.b[4],level=tram and self:StopLevel(t.b) or nil}
            a.pairs={{b,t.seconds*N.WAIT,t}};b.pairs={{a,t.seconds*N.WAIT,t}}
            nodes[#nodes+1]=a;nodes[#nodes+1]=b
        end
    end
    for _,door in ipairs(self:Doors()) do
        local a,b,link=door[1],door[2],door[3]
        -- Its length is the door's own (kept with it).
        if not door.yards then
            -- (Once a data state, all of them: 342 ms at once in the game,
            -- Florian 2026-10-14; given back now and then.)
            if Routing.Grid.Pace and coroutine.running() then Routing.Grid.Pace(200) end
            local shape=not door.edge and N:LinkPath(link,a.cont)
            door.yards=(not door.edge and shape) and N.Length(a.cont,shape) or N.Yards(a.cont,a.x,a.y,b.x,b.y)
        end
        local seconds=door.edge and door.yards/speed
            or tonumber(link.seconds) or math.max(N.PASS,door.yards/speed)
        a.pairs={{b,seconds,link}}
        if not link.oneway then b.pairs={{a,seconds,link}} end
        a.doorLink,b.doorLink=link.id,link.id
        nodes[#nodes+1]=a;nodes[#nodes+1]=b
    end
    -- The same plan as walking every pair of nodes, found faster (Florian/
    -- Codex 2026-10-14: 180-400 ms a round, ten rounds a way): each node's
    -- key made once; walking only among the nodes of its continent and
    -- level (flight masters among all of their continent); the next node
    -- from a heap by its time, ties to the node first in the list as
    -- before; walked lengths looked up by key pairs. In a coroutine it
    -- gives the frame back now and then (Grid.Pace).
    if goalNodes then for i=2,#goalNodes do nodes[#nodes+1]=goalNodes[i] end end
    -- A city's entrances (CityEntrance): each a goal, the way ends at the
    -- first reached (Florian 2026-10-15: the entrance chosen by the line,
    -- Orgrimmar's west gate, held for every round; each search to it from
    -- outside ran to the limit).
    if not many and type(goal.entrances)=="table" then
        for _,e in ipairs(goal.entrances) do
            if not (e.x==goal.x and e.y==goal.y) then nodes[#nodes+1]={cont=e.cont,x=e.x,y=e.y,kind="goal",name=goal.name,anyGoal=true} end
        end
    end
    -- Precomputed walks between zones (Transit.lua, Florian 2026-10-16):
    -- their nodes on the ground of where you are and where you go.
    -- With them a long walk on the ground nobody measured is no edge
    -- (Codex 2026-10-17: the first plan still took the whole line
    -- Crossroads to Silithus and searched it to the limit): start and goal
    -- join the network near them, the network's stored walks carry the
    -- rest. Planned again without this when it finds no way (transitWide).
    local narrow
    self.narrowed=nil
    local long,why
    if not many and Routing.Transit then long,why=Routing.Transit:Long(cont,px,py,goal) end
    self.nearOnly=long and why=="near" or nil
    if long then
        local seen={}
        for _,c in ipairs({cont,goal.cont}) do
            if c and not seen[c] and Routing.Transit:Usable(c) then
                seen[c]=true
                local net=Routing.Transit:Net(c)
                for _,n in ipairs(net and net.nodes or {}) do nodes[#nodes+1]=n;narrow=not self.transitWide end
            end
        end
    end
    -- A ride the network knows (the Great Lift) only as the network's
    -- (Codex 2026-10-17: the same lift from your data beside it let a
    -- guessed walk start at its ends, round the proven ways).
    if narrow then
        local rides={}
        for _,n in ipairs(nodes) do
            for _,p in ipairs(n.tkey and n.pairs or EMPTY) do if p[3] and p[3].linkId then rides[p[3].linkId]=true end end
        end
        if next(rides) then
            local kept={}
            for _,n in ipairs(nodes) do if not (n.doorLink and rides[n.doorLink]) then kept[#kept+1]=n end end
            nodes=kept
        end
    end
    -- Nodes off the network join only their nearest anchors (Codex 2026-10-17:
    -- Darkshore's start went to a bridge into Felwood within the radius,
    -- 18 s and then 25 s searched, the inn beside it cost nothing): the
    -- NEAR nearest; its own zone only a hint (NEARZONE yards ahead), never
    -- before an anchor right beside it.
    local near,exact={},{}
    if narrow then
        self.narrowed=true
        near={}
        -- The network's nodes of a continent in square cells of CELL yards (built once per plan).
        local grids={}
        -- free: may give the frame back (not inside near[]'s lookup).
        local function grid(c,free)
            local g=grids[c]
            if g then return g end
            local w,h=N.Yards(c,0,0,1,0),N.Yards(c,0,0,0,1)
            local cell=N.NEARCELL
            g={cells={},cw=w>0 and cell/w or 1,ch=h>0 and cell/h or 1,cell=cell}
            g.max=math.ceil(math.max(1/g.cw,1/g.ch))+1
            for i,n in ipairs(nodes) do
                if free and i%2000==0 and Routing.Grid.Breathe then Routing.Grid.Breathe() end
                if n.tkey and n.cont==c then
                    local k=math.floor(n.x/g.cw)*4096+math.floor(n.y/g.ch)
                    local l=g.cells[k];if not l then l={};g.cells[k]=l end;l[#l+1]=n
                end
            end
            grids[c]=g
            return g
        end
        local ringBuf={}
        local function pick(e)
            local zones=N.Zones(e.cont,e.x,e.y,e.x,e.y)
            local zone=zones and zones[1]
            -- Only the NEAR best kept, not every node sorted (Claude 2026-10-20: thousands of
            -- network nodes sorted again for each node off the network).
            -- Nodes from a grid of CELL yards, ring by ring, until no farther ring can hold
            -- a better one (its nearest point beyond the NEAR-th score plus the zone bonus).
            local list={}
            local ground=(e.level or 0)==0
            local on
            local g=grid(e.cont)
            local cx,cy=math.floor(e.x/g.cw),math.floor(e.y/g.ch)
            local r=0
            while r<=g.max do
                if #list>=N.NEAR and (r-1)*g.cell-N.NEARZONE>list[#list][2] then break end
                -- The ring's cells only (its border), not the whole square again; into one
                -- list kept for the plan, empty cells skipped (Claude 2026-10-20: a new list
                -- per ring and an empty table per empty cell, over a hundred rings in empty
                -- country, were up to 180 MB of garbage a plan and stops of 600-700 ms).
                local ring,nr=ringBuf,0
                if r==0 then nr=1;ring[1]=cx*4096+cy
                else
                    for gx=cx-r,cx+r do ring[nr+1]=gx*4096+cy-r;ring[nr+2]=gx*4096+cy+r;nr=nr+2 end
                    for gy=cy-r+1,cy+r-1 do ring[nr+1]=(cx-r)*4096+gy;ring[nr+2]=(cx+r)*4096+gy;nr=nr+2 end
                end
                for k=1,nr do
                local cellList=g.cells[ring[k]]
                if cellList then for _,n in ipairs(cellList) do
                    local yards=N.Yards(e.cont,e.x,e.y,n.x,n.y)
                    local score=yards-((zone and n.zone==zone) and N.NEARZONE or 0)
                    -- Standing on an anchor (on the ground): that one only (Codex
                    -- 2026-10-17: from Calandrath's own anchor the plan went to a
                    -- junction beside it, a guessed walk instead of the proven ways).
                    if ground and yards<=N.JOINEXACT and (not on or yards<on[3]) then on={n,score,yards} end
                    if #list<N.NEAR or score<list[#list][2] then
                        if #list>=N.NEAR then list[#list]=nil end
                        local i=#list
                        while i>=1 and list[i][2]>score do list[i+1]=list[i];i=i-1 end
                        list[i+1]={n,score,yards}
                    end
                end end
                end
                r=r+1
            end
            local set={}
            if on then set[on[1]]=true;exact[e]=true
            else for i=1,math.min(N.NEAR,#list) do set[list[i][1]]=true end end
            near[e]=set
        end
        -- Every node off the network the same way, not only start and goal
        -- (Florian's Crossroads 2026-10-17: from the Great Lift's foot a
        -- guessed 1587 yd walk to Marshal's Refuge, up Un'Goro's cliffs,
        -- searched for minutes; the lift's own anchors lie beside it).
        setmetatable(near,{__index=function(t,e) pick(e);return rawget(t,e) end})
        -- The grids of the network's continents built here, given back now and then.
        for _,n in ipairs(nodes) do if n.tkey and not grids[n.cont] then grid(n.cont,true) end end
    end
    local level0=function(n) return tostring(n.level or 0) end
    local byCont,byLevel={},{}
    local Breathe=Routing.Grid.Breathe or function() end
    for i,n in ipairs(nodes) do
        if i%2000==0 then Breathe() end
        n.idx,n.k=i,key(n)
        if n.kind~="start" then
            local c=byCont[n.cont];if not c then c={};byCont[n.cont]=c end;c[#c+1]=n
            -- A network node's level key kept with it (the same in every plan).
            local lk=n.lkey or n.cont..":"..level0(n)
            if n.tkey then n.lkey=lk end
            local l=byLevel[lk];if not l then l={};byLevel[lk]=l end;l[#l+1]=n
        end
    end
    local walkedBy
    if known then
        walkedBy={}
        local i=0
        for k,v in pairs(known) do
            i=i+1;if i%1000==0 then N.Breathe() end
            local a,b=N.SplitKey(k)
            if a then local t=walkedBy[a];if not t then t={};walkedBy[a]=t end;t[b]=v end
        end
    end
    -- A measured complete ground walk tells this plan more about its
    -- detour than the fixed estimate. Otherwise each unused nearby gate
    -- makes two unmeasured walks look cheaper than that same known way.
    -- Only estimates change: every edge and real transport remains available.
    -- This is local to Plan, not a new cache or a reachability assertion.
    local groundFactor=N.DETOUR
    local groundFrom,groundTo
    if groundDetour and known and #starts==1 and not many and not goal.entrances
        and not starts[1].level and not goalNode.level and starts[1].cont==goalNode.cont then
        local yards=known[key(starts[1])..">"..key(goalNode)]
        local line=N.Yards(cont,px,py,goalNode.x,goalNode.y)
        if yards and yards<N.NOWAY and line>=Routing.Grid.COARSEMIN then
            groundFactor=math.max(groundFactor,yards/line)
            -- Measured long prefixes/suffixes refine estimates from/to their
            -- shared endpoint. These small maps die with this Plan call.
            groundFrom,groundTo={},{}
            local at={}
            for _,node in ipairs(nodes)do
                if node.cont==cont and not node.level then at[node.k]=node end
            end
            for ak,list in pairs(walkedBy or {})do
                local a=at[ak]
                if a then for bk,yards in pairs(list)do
                    local b=at[bk]
                    if b and yards<N.NOWAY then
                        local line=N.Yards(cont,a.x,a.y,b.x,b.y)
                        if line>=Routing.Grid.COARSEMIN then
                            local factor=yards/line
                            groundFrom[ak]=math.max(groundFrom[ak]or N.DETOUR,factor)
                            groundTo[bk]=math.max(groundTo[bk]or N.DETOUR,factor)
                        end
                    end
                end end
            end
        end
    end
    local dist,prev,via,what,done={},{},{},{},{}
    local reached
    -- The heap as two arrays, cost and node (Claude 2026-10-20: a table for each
    -- entry was most of 100+ MB of garbage a plan, collected in one 200-465 ms piece).
    local hc,hn,size={},{},0
    local function less(i,j) return hc[i]<hc[j] or (hc[i]==hc[j] and hn[i].idx<hn[j].idx) end
    local function swap(i,j) hc[i],hc[j]=hc[j],hc[i];hn[i],hn[j]=hn[j],hn[i] end
    local function push(cost,n)
        size=size+1;hc[size],hn[size]=cost,n
        local i=size
        while i>1 do
            local p=math.floor(i/2)
            if less(i,p) then swap(i,p);i=p else break end
        end
    end
    local function pop()
        local cost,node=hc[1],hn[1]
        hc[1],hn[1]=hc[size],hn[size];hc[size],hn[size]=nil,nil;size=size-1
        local i=1
        while true do
            local l,r,m=2*i,2*i+1,i
            if l<=size and less(l,m) then m=l end
            if r<=size and less(r,m) then m=r end
            if m==i then break end
            swap(i,m);i=m
        end
        return cost,node
    end
    local function try(v,cost,u,kind,by)
        if not dist[v] or cost<dist[v] then dist[v],prev[v],via[v],what[v]=cost,u,kind,by;push(cost,v) end
    end
    for _,node in ipairs(starts) do dist[node]=node.cost or 0 end
    for _,node in ipairs(nodes) do if dist[node] then push(dist[node],node) end end
    -- Per level list: its nodes by key, those off the network and those at a walked transition.
    local index={}
    local extraBuf,outBuf={},{}
    local function byIdx(a,b) return a.idx<b.idx end
    local function reach(list,u,walked)
        local ix=index[list]
        if not ix then
            ix={byKey={},rest={}}
            for _,n in ipairs(list) do
                ix.byKey[n.k]=n
                if not n.tkey or n.bound then ix.rest[#ix.rest+1]=n end
            end
            index[list]=ix
        end
        -- In the list's own order (ties resolved as before): the few walked ends sorted and
        -- merged into the rest, which is in that order already (Claude 2026-10-20: sorting
        -- all of them for every node was a fifth of the search).
        -- Into two lists kept for the whole plan (a new one for every node was garbage).
        local extra,ne=extraBuf,0
        for k in pairs(walked or EMPTY) do
            local n=ix.byKey[k]
            if n and n.tkey and not n.bound then ne=ne+1;extra[ne]=n end
        end
        for t=ne+1,#extra do extra[t]=nil end
        if ne==0 then return ix.rest end
        table.sort(extra,byIdx)
        local out,no,i,j,rest=outBuf,0,1,1,ix.rest
        while i<=#rest or j<=ne do
            local a,b=rest[i],extra[j]
            no=no+1
            if b and (not a or b.idx<a.idx) then out[no]=b;j=j+1 else out[no]=a;i=i+1 end
        end
        for t=no+1,#out do out[t]=nil end
        return out
    end
    local Grid=Routing.Grid
    while size>0 do
        local best,u=pop()
        if not done[u] and dist[u]==best then
            if goalNodes then
                -- Several goals: done when all are reached (walking on
                -- through one is never shorter, so no time changes by it).
                if u.kind=="goal" then left=left-1;if left<=0 then break end end
            elseif u==goalNode or u.anyGoal then reached=u;break end
            done[u]=true
            local list=u.kind=="flight" and byCont[u.cont] or byLevel[u.lkey or u.cont..":"..level0(u)] or EMPTY
            local walked=walkedBy and walkedBy[u.k]
            local level=(u.level or 0)
            local factor=level~=0 and 1 or (u.cont==cont and groundFactor or N.DETOUR)
            -- A node of the precomputed network reaches on its level only its stored walks, the
            -- other end of a walked transition and the nodes off the network (Claude 2026-10-20:
            -- every other network node is ruled out below anyway; looking at all of them made the
            -- search quadratic, 23 of 33 s of a way across both continents, pieces of 0.9 s).
            local cands=list
            if u.tkey and u.kind~="flight" then cands=reach(list,u,walked) end
            for j,b in ipairs(cands) do
                -- Each node off the network picks its anchors when first met (near[]):
                -- given back between them, never inside that lookup.
                if j%8==0 then Breathe() end
                if b~=u then
                    -- Walking only on one level.
                    if (b.level or 0)==level then
                        -- Not walked yet: the line times DETOUR; on a level (city
                        -- streets) the line alone, never more than the way (Florian
                        -- 2026-10-11: the nearer stairs looked worse on paper than the
                        -- way measured to the farther ones and were never tried).
                        local w=walked and walked[b.k]
                        -- Between two nodes of the precomputed network only its
                        -- stored walks (Codex 2026-10-16): no estimated shortcut
                        -- the network never found, but the two ends of a bridge
                        -- of your data (searched as usual); everything else stays.
                        if u.tkey and b.tkey and not w and not Routing.Transit:Bound(u,b) then w=false end
                        local estimate=factor
                        if level==0 and u.cont==cont and groundFrom then
                            estimate=math.max(estimate,groundFrom[u.k]or N.DETOUR,groundTo[b.k]or N.DETOUR)
                        end
                        local line=not w and N.Yards(u.cont,u.x,u.y,b.x,b.y)
                        if narrow and level==0 and line and line>=Routing.Transit.LONG then w=false end
                        -- Between two nodes off the network only short walks (Codex
                        -- 2026-10-17: from the Great Lift's top a row of guessed walks
                        -- via flight masters and docks went round the lift and the
                        -- network); the way between places is the network's.
                        if narrow and level==0 and line and not u.tkey and not b.tkey and line>N.LOCALWALK then w=false end
                        -- Standing on an anchor: from there only the network
                        -- (Codex 2026-10-17: Crossroads' flight master to its inn,
                        -- both on anchors, went the short guessed way over ground
                        -- that does not hold, not the proven 272 yd).
                        if narrow and level==0 and line and not u.tkey and not b.tkey then
                            if near[u] and exact[u] or near[b] and exact[b] then w=false end
                        end
                        if narrow and line and (u.tkey or b.tkey) and not (u.tkey and b.tkey) then
                            if not near[u.tkey and b or u][u.tkey and u or b] then w=false end
                        end
                        -- A place off the network walked through from the network
                        -- back onto it (Codex 2026-10-19: Thunder Bluff's gate 64
                        -- as a waypoint between two proven walks, both guessed
                        -- pieces unwalkable): its own transition only, never a
                        -- shortcut on the ground.
                        if narrow and b.tkey and not u.tkey and via[u]=="walk" and prev[u] and prev[u].tkey then w=false end
                        if w~=false then try(b,best+(w or line*estimate)/speed,u,"walk") end
                    end
                    if u.kind=="flight" and b.kind=="flight" then try(b,best+self:FlightSeconds(u,b),u,"flight") end
                end
            end
            for _,p in ipairs(u.pairs or EMPTY) do try(p[1],best+p[2],u,u.kind=="dock" and "transport" or "transition",p[3]) end
            Breathe()
        end
    end
    if goalNodes then
        local times={}
        for i,n in ipairs(goalNodes) do times[i]=dist[n] or false end
        return times
    end
    goalNode=reached or goalNode
    if not dist[goalNode] then
        return nil,"No way to "..goal.name.." (another continent without a transport for your faction, or another level without a transition?)."
    end
    local steps={}
    local n=goalNode
    while prev[n] do table.insert(steps,1,{from=prev[n],to=n,kind=via[n],by=what[n],cost=dist[n]-dist[prev[n]]});n=prev[n] end
    -- A transition walked in Route Studio (a ramp round a tower): its shape,
    -- in the direction taken.
    for _,step in ipairs(steps) do
        if step.kind=="transition" and type(step.by)=="table" and step.by.transitEdge then
            -- A stored walk between levels: the network's own shape.
            local net=Routing.Transit:Net(step.by.cont)
            step.path=net and Routing.Transit:Path(step.by.transitEdge,net)
        elseif step.kind=="transition" and type(step.by)=="table" then
            local shape=N:LinkPath(step.by,step.from.cont)
            if shape and step.from.side=="b" then
                local back={}
                for i=#shape,1,-1 do back[#back+1]=shape[i] end
                shape=back
            end
            step.path=shape
        end
    end
    -- Already there (on the start's level).
    if #steps==0 then steps[1]={from=nodes[1],to=goalNode,kind="walk"} end
    return steps,dist[goalNode],anyKnown
end

-- Zones a walk crosses (sampled along the line), for the grid's space.
function N.Zones(cont,x1,y1,x2,y2)
    local zones,seen={},{}
    local function add(x,y)
        local info=call("C_Map.GetMapInfoAtPosition",cont,x,y)
        local guard=0
        while type(info)=="table" and info.mapType and info.mapType>3 and info.parentMapID and guard<4 do
            info=call("C_Map.GetMapInfo",info.parentMapID);guard=guard+1
        end
        local id=type(info)=="table" and info.mapType==3 and info.mapID
        if id and not seen[id] then seen[id]=true;zones[#zones+1]=id end
    end
    local yards=N.Yards(cont,x1,y1,x2,y2)
    local n=math.max(1,math.ceil(yards/250))
    for i=0,n do add(x1+(x2-x1)*i/n,y1+(y2-y1)*i/n) end
    -- No zone under a short line (Florian 2026-10-20: "Gate 67 -> Gate 67 recorded road,
    -- 0 yd", the gate spot outside Orgrimmar has none in game): the zones round its ends.
    if #zones==0 and yards<200 then
        local w,h=N.Yards(cont,0,0,1,0),N.Yards(cont,0,0,0,1)
        if w>0 and h>0 then
            for _,r in ipairs({15,40,80}) do
                for k=0,7 do
                    local dx,dy=math.cos(k*math.pi/4)*r/w,math.sin(k*math.pi/4)*r/h
                    add(x1+dx,y1+dy);add(x2+dx,y2+dy)
                end
                if #zones>0 then break end
            end
        end
    end
    return zones
end
-- One walking leg on the grid of its continent and level (inside a
-- coroutine). Returns points {x, y} and a note.
-- Why a leg found no way (Florian 2026-10-11: "it finds no way on Town,
-- I do not see why"): start or goal off every street, or both on streets
-- that do not hang together (how many cells each reaches).
function N.WhyNoWay(s,x1,y1,x2,y2)
    local Grid=Routing.Grid
    local function on(x,y)
        local cx,cy=Grid.Cell(s,x,y)
        if not cx then return nil end
        local sx,sy=Grid.Snap(s,cx,cy)
        if not Grid.CellCost(s,sx,sy) then return nil end
        return sy*s.cols+sx
    end
    local a,b=on(x1,y1),on(x2,y2)
    if not a and not b then return "start and goal off the streets" end
    if not a then return "start off the streets" end
    if not b then return "goal off the streets" end
    -- Known apart (Grid.Apart, a search ran to the end): said without
    -- searching both sides again (Florian/Codex 2026-10-14: 4 s each time).
    local function count(part)
        if not part.count then local n=0;for _ in pairs(part.cells) do n=n+1 end;part.count=n end
        return part.count
    end
    for _,part in ipairs(s.apart or {}) do
        if part.reverse and part.goal==b and not part.cells[a] then
            return string.format("start and goal on streets that do not meet: %d cells lead to the goal (known)",count(part))
        elseif not part.reverse and part.cells[a] and not part.cells[b] then
            return string.format("start and goal on streets that do not meet: %d cells from the start (known)",count(part))
        end
    end
    -- First back from the goal: all that leads there, when it ends, is kept
    -- (Grid.KeepApart) and makes the next search to it fail at once.
    local back,_,okB,allB=Grid.Explore(s,b,a,nil,N.LIMIT,nil,true)
    if okB and allB and not back[a] then
        Grid.KeepApart(s,back,b,true)
        local n=0;for _ in pairs(back) do n=n+1 end
        return string.format("start and goal on streets that do not meet: %d cells lead to the goal",n)
    end
    local fromA=Grid.Explore(s,a,b,nil,N.LIMIT)
    local fromB=Grid.Explore(s,b,a,nil,N.LIMIT,nil,true)
    local na,nb=0,0
    for _ in pairs(fromA or {}) do na=na+1 end
    for _ in pairs(fromB or {}) do nb=nb+1 end
    return string.format("start and goal on streets that do not meet: %d cells from the start, %d to the goal",na,nb)
end
-- A leg's outcome (Codex/Florian 2026-10-16): "ok", "nopath" (proven: no
-- walkable way), "limit" (not found within the search's limit: it may
-- exist), "unknown" (the data cannot tell). Only "nopath" says "no way".
N.STATUSLABEL={nopath="NO WAY",limit="SEARCH LIMIT",unknown="UNKNOWN"}
N.STATUSWORD={nopath="no way",limit="search limit",unknown="unknown"}
-- Zones above your level on the way (Florian 2026-10-16): said once per way,
-- with their levels; with "avoid" the search already went round where it could.
N.ZONESAMPLE=6   -- every this many points of a walk asked for its zone
function N:ZoneWarning(steps)
    local mode=Routing:ZoneMode()
    if mode=="off" or not Routing.ZoneAt then return end
    local level=UnitLevel and UnitLevel("player") or 1
    local seen,list={},{}
    local function look(cont,x,y)
        local zone,name=Routing:ZoneAt(cont,x,y)
        local range=zone and Routing:ZoneAbove(zone,level)
        if range and not seen[zone] then seen[zone]=true;list[#list+1]=string.format("%s (%d-%d)",name or ("map "..zone),range[1],range[2]) end
    end
    for _,step in ipairs(steps or {}) do
        local cont=step.from and step.from.cont
        local path=step.path
        if cont and type(path)=="table" then
            for i=1,#path,N.ZONESAMPLE do look(cont,path[i][1],path[i][2]) end
            if #path>0 then look(cont,path[#path][1],path[#path][2]) end
        elseif step.to and step.to.cont then look(step.to.cont,step.to.x,step.to.y) end
    end
    if #list==0 then return nil end
    local text=string.format("Above your level on this way: %s.%s",table.concat(list,", "),mode=="avoid" and " Routing went round where it could." or "")
    Routing:Print(text)
    return text
end
-- project: the goal of the way (not a transition's end): on a blocked spot
-- the way ends on the nearest free one (Grid.Search).
function N:Walk(cont,level,x1,y1,x2,y2,project)
    local Grid=Routing.Grid
    local zones=N.Zones(cont,x1,y1,x2,y2)
    -- A known level is searched on its own city's map only (Florian/Codex
    -- 2026-10-15: Undercity's lifts and North Main Gate fell apart on
    -- "Ruins of Lordaeron 5": Tirisfal under the line made the space so big
    -- that the cells grew from 2 to 8 yards).
    local owner
    if level and Routing.Level then
        local _,map=Routing.Level:Find(level)
        if type(map)=="number" then owner=map;zones={map} end
    end
    if #zones==0 then return {{x1,y1},{x2,y2}},"UNKNOWN (no zone under the line): straight",false,"unknown" end
    -- One space per continent and level, kept while you navigate: every leg
    -- and every new search on the way reuses what earlier ones worked out
    -- about the ground (first native run 2026-10-10: each replanned leg
    -- started cold). It covers all zones of the continent; built anew only
    -- for a zone it lacks.
    self.spaces=self.spaces or {}
    local id=cont..":"..tostring(level or 0)
    local s=self.spaces[id]
    local covered=s~=nil
    if s then for _,zone in ipairs(zones) do if not s.has[zone] then covered=false end end end
    -- A level's space grown over other maps earlier is built anew.
    if s and owner and s.owner~=owner then covered=false end
    local warm=covered
    if not covered then
        local all={}
        -- The ground: all zones of the continent (legs through the open
        -- world reuse it). A level lies in its city's map: only the zones of
        -- the leg (Florian 2026-10-12: Undercity's levels searched as all of
        -- Eastern Kingdoms, 1274 x 2408 cells of 8 yards, the town apart).
        if not level then
            for _,info in ipairs(call("C_Map.GetMapChildrenInfo",cont,3,true) or {}) do
                if type(info)=="table" and info.mapType==3 then all[#all+1]=info.mapID end
            end
        end
        for _,zone in ipairs(zones) do all[#all+1]=zone end
        if s and not owner then for zone in pairs(s.has) do all[#all+1]=zone end end
        local has,list={},{}
        for _,zone in ipairs(all) do if not has[zone] then has[zone]=true;list[#list+1]=zone end end
        s=Grid.Space(list,level)
        if s.mapID~=cont then return {{x1,y1},{x2,y2}},"UNKNOWN (zones on another map): straight",false,"unknown" end
        s.has=has
        s.owner=owner
        if not level then Grid.Cities(s,N.CITIES) end
        Grid.Prepare(s)
        -- Cell costs kept while this space lives (Gather's routes do the same).
        s.costs={}
        self.spaces[id]=s
    end
    local limit=level and N.LIMIT or N.GROUNDLIMIT
    -- "blocked": the goal moved onto a free cell only when its own cell is
    -- not (a goal on a city's level, Codex 2026-10-17).
    if project=="blocked" then
        local cx,cy=Grid.Cell(s,x2,y2)
        project=not (cx and Grid.CellCost(s,cx,cy))
    end
    local path,why=Grid.Search(s,x1,y1,x2,y2,limit,N.WEIGHT,project,true)
    local status=path and "ok" or (why=="limit" or why=="nopath") and why or "unknown"
    local note=string.format("%d zone(s), %dx%d cells, %s, %s",#zones,s.cols,s.rows,
        level and ("level "..Routing.Level:Name(level)) or (s.terrain and "terrain" or "NO terrain"),warm and "warm" or "cold")
    -- At the limit: not searched again to say why (Florian 2026-10-14,
    -- Darnassus to Orgrimmar: three more searches of LIMIT cells each,
    -- minutes in the game).
    if not path then
        local reason=status=="limit" and ("not reached within the search's limit of "..limit.." cells; a way may exist") or N.WhyNoWay(s,x1,y1,x2,y2)
        return {{x1,y1},{x2,y2}},note..", "..N.STATUSLABEL[status].." ("..reason.."): straight",false,status
    end
    return path,note,true,"ok"
end
-- Two walks in a row where the second goes back along the first (Florian
-- 2026-10-17: a precomputed walk ends in Everlook's middle, the walk on
-- to the goal leads straight back out; in and out again): both cut where
-- they part. Followed from the joint while the second walk's points stay
-- within SPUR yards of the first walk's line, going back along it.
function N.Trim(cont,a,b)
    if #a<2 or #b<2 then return a,b end
    local sx,sy=N.Yards(cont,0,0,1,0),N.Yards(cont,0,0,0,1)
    local function near(p,k)
        -- p to the piece of a from point k-1 to k, in yards.
        local ax,ay=a[k-1][1]*sx,a[k-1][2]*sy
        local bx,by=a[k][1]*sx,a[k][2]*sy
        local px,py=p[1]*sx,p[2]*sy
        local dx,dy=bx-ax,by-ay
        local l=dx*dx+dy*dy
        local t=l>0 and math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/l)) or 0
        local qx,qy=ax+t*dx-px,ay+t*dy-py
        return math.sqrt(qx*qx+qy*qy)
    end
    local i,j=#a,1
    while j<#b do
        local p=b[j+1]
        local best,at=math.huge,nil
        for k=i,math.max(2,i-40),-1 do
            local d=near(p,k)
            if d<best then best,at=d,k end
        end
        if not at or best>N.SPUR then break end
        i,j=at,j+1
    end
    if j==1 then return a,b end
    -- a kept to the end of its piece nearer to where b goes on.
    local function yards(p,q) local dx,dy=(p[1]-q[1])*sx,(p[2]-q[2])*sy;return dx*dx+dy*dy end
    if yards(b[j],a[i-1])<yards(b[j],a[i]) then i=i-1 end
    local na,nb={},{}
    for k=1,math.max(1,i) do na[k]=a[k] end
    for k=j,#b do nb[#nb+1]=b[k] end
    return na,nb
end
local function length(cont,path)
    local yards=0
    for j=2,#path do yards=yards+N.Yards(cont,path[j-1][1],path[j-1][2],path[j][1],path[j][2]) end
    return yards
end
-- A leg searched (inside the coroutine), kept by its key.
-- The precomputed walks of the continents a way touches, as walks already
-- known (their points decoded when the way uses one).
function N:SeedTransit(legs,conts)
    local T=Routing.Transit
    if not T then return 0 end
    local n=0
    local roadCost=(tonumber(Routing:Config().roadPercent) or 60)/100
    for c in pairs(conts) do
        local net=T:Usable(c) and T:Net(c)
        -- Each walk's entry made once per network and road preference and shared by
        -- every way (Claude 2026-10-20: 15000 new tables twice a way, 24 MB of garbage
        -- whose collection stopped the game for 200-465 ms). Only its points are
        -- added later, the same for every way.
        local seed=net and net.seed
        if net and not (seed and seed.cost==roadCost) then
            seed={cost=roadCost,keys={},legs={}}
            for i,e in ipairs(net.edges or {}) do
                if i%500==0 then N.Breathe() end
                local k=e.legKey
                if not k then k=key(e.a)..">"..key(e.b);e.legKey=k end
                seed.keys[#seed.keys+1]=k
                seed.legs[#seed.legs+1]={yards=e.yards,rank=T.Rank(e,roadCost),ok=true,status="ok",note="precomputed",seconds=0,transit=e,net=net}
            end
            net.seed=seed
        end
        for i,k in ipairs(seed and seed.keys or {}) do
            if i%2000==0 then N.Breathe() end
            if not legs[k] then legs[k]=seed.legs[i];n=n+1 end
        end
    end
    return n
end
-- The yards of a way's walks searched on the terrain past the precomputed
-- ones, longer than a local walk (nil when none).
function N.Guessed(steps,legs)
    local yards=0
    for _,step in ipairs(steps or {}) do
        local found=step.kind=="walk" and legs[key(step.from)..">"..key(step.to)]
        if found and found.ok and not found.transit and (found.yards or 0)>N.LOCALWALK then yards=yards+found.yards end
    end
    return yards>0 and math.floor(yards+0.5) or nil
end
local function leg(legs,step)
    local k=key(step.from)..">"..key(step.to)
    local known=legs[k]
    if known and known.transit and not known.path then
        known.path=Routing.Transit:Path(known.transit,known.net) or {{step.from.x,step.from.y},{step.to.x,step.to.y}}
    end
    if not legs[k] then
        N.searched=(N.searched or 0)+1
        local t0=GetTime()
        -- Each walk said as it is searched (Florian 2026-10-17: a search ran
        -- for minutes and the log told nothing about which walk).
        Routing:Note(string.format("  searching walk %d: %s -> %s, %d yd in a line...",N.searched,tostring(step.from.name),tostring(step.to.name),
            N.Yards(step.from.cont,step.from.x,step.from.y,step.to.x,step.to.y)))
        -- Joining the precomputed walks: a few seconds, then it counts as
        -- failed and the plan takes another anchor (never one walk holding
        -- up the whole way).
        local function walk()
            local s,t=step.from,step.to
            -- A goal on a city's level: its own spot first (Codex 2026-10-17,
            -- Freewind Post: moved onto the nearest cell's middle, the last
            -- piece to it was a guess through the post); moved only when its
            -- own spot cannot be reached.
            local project=t.kind=="goal"
            if project and t.level then project="blocked" end
            return N:Walk(s.cont,s.level,s.x,s.y,t.x,t.y,project)
        end
        local path,note,ok,status,late
        -- Planned without the network after it found no way (a gap in it,
        -- Florian 2026-10-18: Winterspring behind Timbermaw searched for
        -- minutes): those walks get WIDESECONDS, then they count as failed.
        -- Joined only by the short-way rule: a join of at most NEARNODE yards gets NEARJOINSECONDS.
        local limit=N.narrowed and (N.nearOnly and N.NEARJOINSECONDS or N.JOINSECONDS) or (N.transitWide and N.WIDESECONDS) or nil
        -- All walks of that plan without the network together WIDETOTAL
        -- (Codex 2026-10-18: each ended after 30 s, the rounds tried the
        -- same gap from one anchor after another for minutes).
        local wide=not N.narrowed and N.transitWide
        if wide then limit=math.min(limit,N.WIDETOTAL-(N.wideUsed or 0)) end
        if wide and limit<=0 then
            late=true;N.gapNoted=true
            path,ok,status={{step.from.x,step.from.y},{step.to.x,step.to.y}},false,"limit"
            note="not searched: the time for ways outside the precomputed walks is used up"
        elseif limit and coroutine.running() then
            -- The walk in a coroutine of its own: each slice it gives back is
            -- passed on to the frame, and past its time it is left (its
            -- space dropped: a search left halfway may hold borrowed tables).
            local co=coroutine.create(walk)
            -- Where it stands is where the run stands (Grid.Where, the cost line).
            Routing.Grid.inner=co
            while true do
                local res={coroutine.resume(co)}
                if not res[1] then Routing.Grid.inner=nil end
                if not res[1] then error(res[2],0) end
                if coroutine.status(co)=="dead" then path,note,ok,status=res[2],res[3],res[4],res[5];break end
                if GetTime()-t0>limit then
                    late=true
                    if N.spaces then N.spaces[step.from.cont..":"..tostring(step.from.level or 0)]=nil end
                    path,ok,status={{step.from.x,step.from.y},{step.to.x,step.to.y}},false,"limit"
                    note=string.format("ended after %d s (%s): straight",limit,N.narrowed and "joining the precomputed walks" or "not in the precomputed walks")
                    if not N.narrowed then N.gapNoted=true end
                    break
                end
                coroutine.yield()
            end
            Routing.Grid.inner=nil
        else
            path,note,ok,status=walk()
        end
        if wide then N.wideUsed=(N.wideUsed or 0)+(GetTime()-t0) end
        legs[k]={path=path,yards=length(step.from.cont,path),note=note,seconds=GetTime()-t0,ok=ok,status=status or (ok and "ok" or "unknown")}
        Routing:Note(string.format("  walk %d: %s, %.1f s",N.searched,ok and "found" or late and "too long, another anchor" or tostring(status or "no way"),GetTime()-t0))
    end
    return legs[k],k
end
N.Leg=leg

-- A zone by its map ID or its name (the start of it, any case: "silverpine"),
-- among the zones with levels (ZoneLevels.lua: all of the continents').
function N:ZoneNamed(text)
    local id=tonumber(text)
    if id then return id end
    text=text:lower()
    local found
    for mapID in pairs(Routing.ZONE_LEVELS or {}) do
        local ok,info=pcall(C_Map.GetMapInfo,mapID)
        local name=ok and type(info)=="table" and type(info.name)=="string" and info.name:lower()
        if name==text then return mapID end
        if name and name:sub(1,#text)==text and (not found or mapID<found) then found=mapID end
    end
    return found
end
-- The goal from the command: "way" (your map pin), "<x> <y>" (your map),
-- "<zone> <x> <y>" (a zone by name or map ID, Florian 2026-10-16: whole
-- commands for test ways into another zone), else a name (Map Data).
function N:Goal(text)
    if text=="way" then
        local point=call("C_Map.GetUserWaypoint")
        if type(point)~="table" or not point.position then return nil,"Set a map pin first (Ctrl+click on the world map)." end
        local px,py=ns.MapPins.XY(point.position)
        local cont,cx,cy
        if px then cont,cx,cy=Routing:OnContinent(point.uiMapID,px,py) end
        if not cont then return nil,"That pin is on no continent map." end
        return {cont=cont,x=cx,y=cy,name="map pin",label="pin"}
    end
    local x,y=text:match("^(%d+%.?%d*)[%s,]+(%d+%.?%d*)$")
    if x then
        local mapID=Routing:Position()
        local cont,cx,cy
        if mapID then cont,cx,cy=Routing:OnContinent(mapID,tonumber(x)/100,tonumber(y)/100) end
        if not cont then return nil,"No position here." end
        return {cont=cont,x=cx,y=cy,name=x..", "..y,label="point"}
    end
    local zone,zx,zy=text:match("^(.-)%s+(%d+%.?%d*)[%s,]+(%d+%.?%d*)$")
    if zone and zone~="" then
        local mapID=self:ZoneNamed(zone)
        if not mapID then return nil,"No zone \""..zone.."\" (its name or map ID)." end
        local cont,cx,cy=Routing:OnContinent(mapID,tonumber(zx)/100,tonumber(zy)/100)
        if not cont then return nil,"That point is on no continent map." end
        local ok,info=pcall(C_Map.GetMapInfo,mapID)
        local name=(ok and type(info)=="table" and info.name or ("map "..mapID)).." "..zx..", "..zy
        return {cont=cont,x=cx,y=cy,name=name,label="point"}
    end
    return self:Find(text)
end
-- The level a goal lies on (Florian 2026-10-10: Map Data knows where
-- Chemist Cuely stands, not that it is down in the Apothecarium): on a map
-- with levels, the level whose painted street or given way passes nearest
-- to the goal, within GOALREACH yards; a street on the ground nearer still
-- keeps it on the ground. The goal then lies on that street (an NPC in a
-- room beside it: you are led to the street next to it). Returns the level
-- (nil: the ground) and the point on the street, if it moved.
N.GOALREACH=25
-- The levels whose street or given way passes within GOALREACH of a
-- point (cont, x, y), nearest first, the best point of each:
-- {{level (false: the ground), d (yards), map, x, y}}.
-- reach: how far a street may be (GOALREACH unless given). The result's
-- field map: a map with levels the point lies on (nil: none).
N.areaIndex={}
function N:Candidates(cont,x,y,reach)
    reach=reach or N.GOALREACH
    local Grid=Routing.Grid
    local db=Routing:Data()
    local best={}
    local onMap
    for mapID,levels in pairs(db.levels) do
        if type(levels)=="table" and #levels>0 and type(mapID)=="number" then
            local mx,my=Grid.Convert(cont,mapID,x,y)
            if mx and mx>=0 and mx<=1 and my>=0 and my<=1 then
                onMap=onMap or mapID
                local w,h=call("C_Map.GetMapWorldSize",mapID)
                if type(w)~="number" or w<=0 then w,h=1000,1000 end
                local function consider(level,px,py,d)
                    local k=level or false
                    local known=best[k]
                    if d<=reach and (not known or d<known.d) then best[k]={level=k,d=d,map=mapID,x=px,y=py} end
                end
                -- What lies last on a spot of a level (the order areas are
                -- painted in): a street point under later no-go is none
                -- (Florian/Codex 2026-10-14: Stormwind's Trade District,
                -- a goal set on a level masked there by no-go).
                local areas=type(db.areas[mapID])=="table" and db.areas[mapID] or {}
                -- Per level its streets and no-go in painting order, each
                -- with its box (asked only for a point that would be the
                -- best yet: Orgrimmar's 1860 areas made it slow otherwise).
                -- Kept per map while its areas stay the same list, count and
                -- sets (Florian 2026-10-14: built anew on every call it cost
                -- 13 ms in his Undercity of 8772 areas; asked every second).
                local cache=N.areaIndex[mapID]
                local fresh=cache and cache.list==areas and cache.n==#areas and cache.ver==Routing.offVersion
                local byLevel=fresh and cache.byLevel or nil
                local boxes=fresh and cache.boxes or nil
                local function index()
                    byLevel,boxes={},{}
                    N.areaIndex[mapID]={list=areas,n=#areas,ver=Routing.offVersion,byLevel=byLevel,boxes=boxes}
                    for _,a in ipairs(areas) do
                        if a.kind=="prefer" or a.kind=="nogo" then
                            local x0,y0,x1,y1
                            if type(a.poly)=="table" and #a.poly>=6 then
                                x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
                                for i=1,#a.poly-1,2 do
                                    local px,py=a.poly[i],a.poly[i+1]
                                    if px<x0 then x0=px end;if px>x1 then x1=px end;if py<y0 then y0=py end;if py>y1 then y1=py end
                                end
                            elseif type(a.x)=="number" then
                                local rx,ry=(a.r or 0)/w,(a.r or 0)/h
                                x0,y0,x1,y1=a.x-rx,a.y-ry,a.x+rx,a.y+ry
                            end
                            if x0 then
                                local k=a.level or false
                                byLevel[k]=byLevel[k] or {}
                                local list=byLevel[k]
                                list[#list+1]={a,x0,y0,x1,y1}
                                boxes[a]=list[#list]
                            end
                        end
                    end
                end
                -- What lies last there: "prefer", "nogo" or nil (unpainted).
                local function lastKind(level,px,py)
                    if not byLevel then index() end
                    local kind
                    for _,e in ipairs(byLevel[level or false] or {}) do
                        if px>=e[2] and px<=e[4] and py>=e[3] and py<=e[5] then
                            local a=e[1]
                            local inside
                            if type(a.poly)=="table" then inside=Grid.Inside(a.poly,px,py)
                            else local dx,dy=(px-a.x)*w,(py-a.y)*h;inside=dx*dx+dy*dy<=(a.r or 0)^2 end
                            if inside then kind=a.kind end
                        end
                    end
                    return kind
                end
                local function free(level,px,py) return lastKind(level,px,py)~="nogo" end
                local plain=consider
                -- A blocked point (a counter or pillar painted no-go under an
                -- NPC, Codex 2026-10-14: Stormwind's Master Wood) still counts
                -- with the nearest street of its level within SNAP yards,
                -- as far as the search would move it (Grid.SNAPYARDS); a
                -- level masked over a wide area does not.
                consider=function(level,px,py,d)
                    local known=best[level or false]
                    if not (d<=reach and (not known or d<known.d)) then return end
                    if free(level,px,py) then plain(level,px,py,d);return end
                    local snap=Grid.SNAPYARDS or 16
                    for r=2,snap,2 do
                        for k=0,15 do
                            local a=k*math.pi/8
                            local qx,qy=px+math.cos(a)*r/w,py+math.sin(a)*r/h
                            if lastKind(level,qx,qy)=="prefer" then
                                local dd=d+r
                                if dd<=reach and (not known or dd<known.d) then plain(level,qx,qy,dd) end
                                return
                            end
                        end
                    end
                end
                -- Areas whose box lies farther than reach are left out.
                if not byLevel then index() end
                local rx,ry=reach/w,reach/h
                for _,st in ipairs(areas) do
                    local bb=boxes[st]
                    if bb and (mx<bb[2]-rx or mx>bb[4]+rx or my<bb[3]-ry or my>bb[5]+ry) then
                    elseif st.kind=="prefer" and not st.poly and type(st.x)=="number" then
                        local dx,dy=(mx-st.x)*w,(my-st.y)*h
                        -- Inside the stroke: there; outside: its edge.
                        consider(st.level,st.x,st.y,math.max(0,math.sqrt(dx*dx+dy*dy)-(st.r or 0)))
                    elseif st.kind=="prefer" and type(st.poly)=="table" and #st.poly>=6 then
                        -- A filled area: inside it 0, else its nearest edge.
                        local q=st.poly
                        if Grid.Inside(q,mx,my) then consider(st.level,mx,my,0)
                        else
                            local n=#q/2
                            for k=1,n do
                                local ax,ay=q[2*k-1],q[2*k]
                                local bx,by=q[(k%n)*2+1],q[(k%n)*2+2]
                                local vx,vy=(bx-ax)*w,(by-ay)*h
                                local len=vx*vx+vy*vy
                                local t=len>0 and math.max(0,math.min(1,((mx-ax)*w*vx+(my-ay)*h*vy)/len)) or 0
                                local qx,qy=ax+(bx-ax)*t,ay+(by-ay)*t
                                local dx,dy=(mx-qx)*w,(my-qy)*h
                                consider(st.level,qx,qy,math.sqrt(dx*dx+dy*dy))
                            end
                        end
                    end
                end
                for _,way in ipairs(type(db.ways[mapID])=="table" and db.ways[mapID] or {}) do
                    local p=way.points
                    for k=1,#(p or {})-3,2 do
                        local ax,ay,ex,ey=p[k],p[k+1],p[k+2],p[k+3]
                        local vx,vy=(ex-ax)*w,(ey-ay)*h
                        local len=vx*vx+vy*vy
                        local t=len>0 and math.max(0,math.min(1,((mx-ax)*w*vx+(my-ay)*h*vy)/len)) or 0
                        local qx,qy=ax+(ex-ax)*t,ay+(ey-ay)*t
                        local dx,dy=(mx-qx)*w,(my-qy)*h
                        -- A given way is walkable under no-go too (Grid.BaseCost).
                        plain(way.level,qx,qy,math.sqrt(dx*dx+dy*dy))
                    end
                end
            end
        end
    end
    local out={}
    for _,c in pairs(best) do out[#out+1]=c end
    -- (Equally near: by the level's id, the same every time; Codex
    -- 2026-10-14: the order of a table walk decided between floors.)
    table.sort(out,function(a,b) if a.d~=b.d then return a.d<b.d end return tostring(a.level)<tostring(b.level) end)
    out.map=onMap
    return out
end
-- A goal looks farther for a level's street than a start (Florian
-- 2026-10-11: the warlock trainer's room in Undercity was not painted, the
-- goal fell to the ground above and the way led up and over the ruins):
-- a level's street within LEVELREACH; the ground only with a street of its
-- own within GOALREACH. Returns the level, the point on its street, and
-- the map with levels the goal lies on (for saying why it stays on the ground).
N.LEVELREACH=60
-- With the goal's height (Map Data): the ground's height there (terrain
-- data) tells whether it stands under the ground (then never the ground)
-- or on it (then the ground, unless a level of that height is near); the
-- levels' heights (Level:Height) pick the floor among the levels near.
N.UNDER=12        -- yards below the terrain: under the ground
N.ZFIT=10         -- yards between the goal's and a level's height that still fit
function N.GroundHeight(cont,x,y)
    local T=ns.MapTerrain
    local f=T and T:Frame(cont)
    if not (f and T.Height) then return nil end
    local ok,h=pcall(T.Height,T,f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
    return ok and type(h)=="number" and h or nil
end
function N:GoalLevel(goal)
    local cands=self:Candidates(goal.cont,goal.x,goal.y,N.LEVELREACH)
    local z=tonumber(goal.z)
    local ground=z and N.GroundHeight(goal.cont,goal.x,goal.y)
    local under=ground and z<ground-N.UNDER
    local onTop=ground and not under and math.abs(z-ground)<=N.ZFIT
    -- Levels whose height fits the goal's.
    local fitting
    if z then
        local bestDz
        local offs={}
        for _,cand in ipairs(cands) do
            if cand.level~=false then
                local off=Routing.Level:Off(cand.level,z,goal.cont,goal.x,goal.y)
                offs[cand]=off
                if off and off<=N.ZFIT and (not bestDz or off<bestDz) then fitting,bestDz=cand,off end
            end
        end
        -- Of levels about as fitting (ZTIE yards), the one whose street the
        -- goal is nearest (Claude's walk simulation 2026-10-13: Orgrimmar's
        -- Hall of the Brave, 0.3 yards off, lost to the valley's slope beside
        -- it, right at its height).
        if fitting then
            for _,cand in ipairs(cands) do
                local off=offs[cand]
                if off and off<=N.ZFIT and off<=bestDz+N.ZTIE and cand.d<fitting.d then fitting=cand end
            end
        end
    end
    local best=fitting
    if not best and onTop then return nil,nil,nil,nil end
    if not best then
        for _,cand in ipairs(cands) do
            if (cand.level~=false and (not z or not Routing.Level:Height(cand.level) or under))
                or (cand.level==false and not under and cand.d<=N.GOALREACH) then best=cand;break end
        end
    end
    -- Under the ground and still nothing: the nearest level at all.
    if not best and under then for _,cand in ipairs(cands) do if cand.level~=false then best=cand;break end end end
    -- Not mapped (Codex 2026-10-14, Stormwind: trainers in a cellar at 101
    -- and below at 30 no level has): its height known and against the
    -- ground and every level of known height near; led to the nearest
    -- street of a level, said so (not as reached on the ground or a floor
    -- above). (Fifth return: true.)
    local unmapped
    if z and ground and not onTop and not fitting and (not best or best.level==false or (under and Routing.Level:Height(best.level))) then
        for _,cand in ipairs(cands) do if cand.level~=false then best,unmapped=cand,true;break end end
    end
    if not best or best.level==false then return nil,nil,nil,cands.map end
    -- Within reach of the street: the goal stays where it is; else the street.
    local cx,cy
    if best.d>N.ARRIVE*.8 then cx,cy=Routing.Grid.Convert(best.map,goal.cont,best.x,best.y) end
    return best.level,cx,cy,nil,unmapped
end
-- goal: a table from Goal, or what other packages hand in ({cont, x, y,
-- level, name, label}).
-- again: planned anew by Navigate itself (a level corrected), not by you.
function N:Start(goal,again)
    -- A new goal starts in Routing's mode; the same one searched again keeps
    -- the mode switched in the guide.
    if goal~=self.lastGoal then self.modeOverride=nil end
    self.lastGoal=goal
    self:Learn()
    local findMs=self.findMs;self.findMs=nil
    if not again then self.corrections=0 end
    if self.busy then Routing:Print("Still calculating.");return false end
    -- A new way ends the old one at once (Codex 2026-10-14: a new start that
    -- failed left the old steps under the new goal's name); its spaces and
    -- legs are kept for the new one (Stop).
    -- Flight points not known on a continent of the way (Florian
    -- 2026-10-15): asked once, before anything is calculated; going on
    -- without them is kept for this character until a flight map there.
    if not again and not goal.flightsAsked then
        local skips,ask=self:FlightSkips(),{}
        for _,c in ipairs(self:FlightsMissing(goal)) do if not skips[c] then ask[#ask+1]=c end end
        if #ask>0 and Routing.Busy and Routing.Busy.Prompt then
            goal.flightsAsked=true
            Routing.Busy:Prompt(string.format("Your flight points on %s are not known yet. Talk to a flight master there and open the flight map once: the way then uses them. Go on without flights there for now?",N.ContNames(ask)),
                "Without flights","Cancel",
                function() for _,c in ipairs(ask) do skips[c]=true end;N:Start(goal) end,
                function() Routing:Print("Way not started: open a flight master's map once, then ask again.") end)
            return false
        end
    end
    if self.steps then self:Stop(true) end
    -- Said in the guide while led (no flights where they are not known).
    local missing=self:FlightsMissing(goal)
    self.flightNote=#missing>0 and string.format("No flights on %s: open a flight master's map there once.",N.ContNames(missing)) or nil
    -- A goal in an enemy base (Codex marks it): enemy bases not avoided on
    -- this way (Florian 2026-10-14); its spaces apart from the others (Stamp).
    self.enemyOff=goal.hostile and true or nil
    if self.enemyOff then Routing:Note(string.format("%s lies in an enemy base (%s): enemy bases not avoided on this way.",tostring(goal.name),tostring(goal.hostile))) end
    -- Everything from here in slices (Florian/Codex 2026-10-14: the goal's
    -- level, where you start and the first plan ran at once and froze the
    -- game): busy at once, the goal known; the outcome is said when the
    -- run ends.
    self.busy,self.goal=true,goal
    local Grid=Routing.Grid
    local budget=Grid.BUDGET;Grid.BUDGET=N.BUDGET;self.budget=budget
    local dropped={}
    local steps,seconds,startInfo,planMs,reused,replanned
    local began=GetTime()
    Grid.nextLabel="Finding the way"
    self.run=Grid.Run(function()
        self:CityEntrance(goal)
        -- Led to a street near a goal the map has no level for: asked anew.
        if goal.npcAt then goal.x,goal.y,goal.level,goal.unmapped,goal.npcAt=goal.npcAt.x,goal.npcAt.y,nil,nil,nil end
        if goal.level==nil and not goal.ground then
            local t0=debugprofilestop and debugprofilestop()
            local level,x,y,map,unmapped=self:GoalLevel(goal)
            self.goalMs=t0 and debugprofilestop()-t0
            if level and unmapped then
                -- Where it really stands kept (a new plan asks again: a map
                -- may have its room by then).
                goal.npcAt={x=goal.x,y=goal.y}
                goal.level=level
                if x then goal.x,goal.y=x,y end
                goal.unmapped=true
                Routing:Print(string.format("%s stands where the map has no level (height %d): led to the nearest street (\"%s\"), the last stretch is yours.",
                    goal.name,math.floor(tonumber(goal.z) or 0),Routing.Level:Name(level)))
            elseif level then
                goal.level=level
                if x then goal.x,goal.y=x,y end
                Routing:Print(string.format("%s is on the level \"%s\".",goal.name,Routing.Level:Name(level)))
            elseif map then
                local info=call("C_Map.GetMapInfo",map)
                Routing:Print(string.format("%s lies on %s but near no street of its levels (%d yd): taken as the ground. Paint its room in Route Studio.",
                    goal.name,type(info)=="table" and info.name or "a map with levels",N.LEVELREACH))
            end
        end
        -- Where you start: a level no transition or subzone told (you logged in
        -- down in Undercity, walked down without being led): the level whose
        -- street you stand on, the same way.
        -- Streets of several levels about as near (ways crossing on different
        -- levels in a city): not guessed; the plan starts on each of them and
        -- the way decides (Florian 2026-10-10). /bv route level <name> says it.
        -- Where you start (Florian 2026-10-11: in Undercity's middle the streets
        -- of four levels lie close; a wrong start drew a straight line): a start
        -- on every level whose street is near. A level Routing knows (a
        -- transition, a district, kept over a reload, /bv route level) costs
        -- nothing, the others OTHERSTART (they win only when no way leads on
        -- from it). Unknown: the nearest street's level costs nothing, the
        -- others their extra walk STARTWEIGHT times; levels as near as the
        -- nearest (UNSURE) are said to be open; off every street the ground too.
        local cont,px,py,here=self:Here()
        self.startLevels=nil
        -- Off the way the level kept is no longer sure (you went elsewhere,
        -- Florian 2026-10-12): found anew from the evidence, as at any start.
        local known=(here~=nil or self.levelSet) and not self.fromHere
        self.fromHere=nil
        local open,likely={},nil
        if cont then
            local cands=self:Candidates(cont,px,py)
            -- Your height (NPCs near): a level your height denies is not yours,
            -- as in the following (Locate). It denying every level near but not
            -- the ground: you stand on the ground (Florian 2026-10-12: planned
            -- anew above a cellar, the cellar's street under you was taken).
            if Routing.Height and #cands>0 then
                local H=Routing.Height
                local kept,ground={},false
                for _,cand in ipairs(cands) do
                    if H:FitsLevel(cand.level or nil,cont,px,py)~=false then kept[#kept+1]=cand end
                    if cand.level==false then ground=true end
                end
                if #kept==0 and not ground and H:FitsLevel(nil,cont,px,py)~=false then kept={{level=false,d=0}} end
                if #kept>0 and #kept<#cands or (#kept==1 and kept[1].level==false and not ground) then
                    cands=kept
                    if Routing.Probe and Routing.Probe.on then Routing.Probe:Note("start levels by your height: "..#kept.." fit") end
                end
            end
            -- Districts naming where you are (several levels): only those.
            local named=Routing.Level:CueLevels()
            if next(named) then
                local kept={}
                for _,cand in ipairs(cands) do if cand.level and named[cand.level] then kept[#kept+1]=cand end end
                if #kept>0 then cands=kept end
            end
            local speed=self:Speed()
            local starts={}
            if known then
                starts[1]={level=here or false,cost=0}
                for _,cand in ipairs(cands) do
                    if (cand.level or false)~=(here or false) then starts[#starts+1]={level=cand.level,cost=N.OTHERSTART+cand.d/speed} end
                end
            elseif #cands>0 then
                local best=cands[1].d
                likely=cands[1].level
                local ground=false
                for _,cand in ipairs(cands) do
                    starts[#starts+1]={level=cand.level,cost=(cand.d-best)/speed*N.STARTWEIGHT}
                    if cand.d-best<=N.UNSURE then open[#open+1]=cand.level end
                    if cand.level==false then ground=true end
                end
                if best>N.UNSURE and not ground then starts[#starts+1]={level=false,cost=0} end
            end
            if #starts==1 and not known then
                if starts[1].level~=false then
                    Routing.Level:Set(starts[1].level)
                    Routing:Print("You are on the level \""..Routing.Level:Name(starts[1].level).."\" (the street you stand on).")
                end
            elseif #starts>1 then self.startLevels=starts end
        end
        self.levelSet=nil
        local planBegan=debugprofilestop and debugprofilestop()
        local anyKnown
        -- The precomputed walks known from the first plan on (Codex
        -- 2026-10-17: seeded only after it, they never shaped it).
        self.transitWide=nil;self.noNear=nil;self.nearLimit=nil
        N.gapNoted=nil;N.wideUsed=0;N.guessedYards=nil
        local first
        do
            local conts,pre={},{}
            if cont and Routing.Transit and Routing.Transit:Long(cont,px,py,goal) then
                conts[cont]=true
                if goal.cont then conts[goal.cont]=true end
            end
            if self:SeedTransit(pre,conts)>0 then
                first={}
                local i=0
                for k,v in pairs(pre) do first[k]=v.rank or v.yards;i=i+1;if i%1000==0 then N.Breathe() end end
            end
        end
        steps,seconds,anyKnown=self:Plan(goal,first)
        if not steps and self.narrowed then
            N:LeaveNetwork()
            steps,seconds,anyKnown=self:Plan(goal,first)
        end
        planMs=planBegan and debugprofilestop()-planBegan
        if not steps then Routing:Print(seconds);return nil end
        -- Which start it was is known once the legs are searched (StartSaid).
        startInfo=self.startLevels and {known=known,here=here,open=open,likely=likely}

        -- The spaces of the last way kept (Florian 2026-10-14: painting the
        -- levels anew was half of every search): taken again while nothing
        -- that makes them changed (N:Stamp).
        local stamp=self:Stamp()
        -- (A way planned anew while led keeps its own.)
        local kept=(self.spaces and self.spacesStamp==stamp and self.spaces) or (self.kept and self.kept.stamp==stamp and GetTime()-self.kept.at<=N.KEEP and self.kept.spaces) or nil
        -- The walks searched before go with them (Florian 2026-10-14: planning
        -- anew after leaving the way searched every leg again).
        local keptLegs=kept and ((kept==self.spaces and self.legs) or (self.kept and self.kept.legs)) or nil
        self.kept=nil
        self.goal,self.steps,self.current,self.spaces,self.ahead,self.track=goal,nil,1,kept,nil,nil
        self.spacesStamp=stamp
        self.keptLegs=keptLegs
        Routing:Note("---- new way ----")
        -- Where it started, for the log and the export (Florian 2026-10-14).
        do
            local mapID,mx,my=Routing:Position()
            local cont,cx,cy,level=self:Here()
            self.startAt={mapID=mapID,mx=mx,my=my,cont=cont,x=cx,y=cy,level=level,subzone=call("GetSubZoneText"),at=time()}
        end
        Routing:Note("Finding the way to "..goal.name.."...")
        began=GetTime()
        local known,legs
        known,legs,replanned={},self.keptLegs or {},0
        self.legs,self.keptLegs=legs,nil
        do
            local here,hx,hy=self:Here()
            local conts={}
            if here and Routing.Transit and Routing.Transit:Long(here,hx,hy,goal) then
                conts[here]=true
                if goal.cont then conts[goal.cont]=true end
            end
            local seeded=self:SeedTransit(legs,conts)
            if seeded>0 then Routing:Note(string.format("Precomputed walks between zones: %d known.",seeded)) end
        end
        reused=0
        for k,v in pairs(legs) do
            known[k]=v.ok and (v.rank or v.yards) or N.NOWAY;reused=reused+1
            if reused%1000==0 then N.Breathe() end
        end
        N.searched=0
        -- Plan, search the walking legs not searched yet, plan again with the
        -- lengths found, until the best plan's legs are all known.
        dropped={}
        -- The best plan whose walks were all searched (its time is real):
        -- taken when the rounds run out on a plan still guessed (Claude's
        -- walk simulation 2026-10-12: on one large level the straight-line
        -- guesses kept finding new pairs of doors; the tenth plan, guessed
        -- at 0:42, walked 1100 yards).
        local sure,sureSeconds
        local function searched(list)
            for _,step in ipairs(list) do
                local found=step.kind=="walk" and legs[key(step.from)..">"..key(step.to)]
                -- Searched and found (Codex 2026-10-17: a failed walk counted).
                if step.kind=="walk" and not (found and found.ok) then return false end
            end
            return true
        end
        -- A plan's time with its walks as searched.
        local function measured(list)
            local t=list[1] and list[1].from.cost or 0
            for _,step in ipairs(list) do
                if step.kind=="walk" then t=t+legs[key(step.from)..">"..key(step.to)].yards/self:Speed() else t=t+(step.cost or 0) end
            end
            return t
        end
        for _=1,N.REPLAN do
            -- Outside the network and its time used up: no further rounds.
            if N.transitWide and (N.wideUsed or 0)>=N.WIDETOTAL then break end
            local open=false
            for _,step in ipairs(steps) do
                if step.kind=="walk" and not legs[key(step.from)..">"..key(step.to)] then
                    open=true
                    local found,k=leg(legs,step)
                    -- No walkable way (a level in parts, Florian 2026-10-11):
                    -- this leg is impossible; the plan goes another way.
                    known[k]=found.ok and found.yards or N.NOWAY
                    -- Said with the way (Florian 2026-10-11: the way went round,
                    -- the nearer stairs left out, and nobody could tell why).
                    if not found.ok then
                        dropped[#dropped+1]={status=found.status,text=string.format("walk to %s on %s: %s",step.to.name,Routing.Level:Name(step.from.level),found.note or "no way")}
                        -- A failed leg on the ground: plan again at once rather
                        -- than searching the legs after it (Codex 2026-10-16:
                        -- Winterspring to Feralas 27 -> 12 walks; on city
                        -- levels this made ways worse, so the ground only).
                        if not step.from.level and not step.to.level then
                            -- Only the short-way rule had the network on and its anchor
                            -- ran out of time: on the ground at once, not anchor after
                            -- anchor (Codex 2026-10-20, Grugelm: three times 10 s first).
                            if N.nearOnly and N.narrowed and found.status=="limit" then N.nearLimit=true;N:LeaveNetwork() end
                            break
                        end
                    end
                end
            end
            if not open then break end
            -- This plan searched through: kept before planning again (Codex
            -- 2026-10-17: Crossroads to Silithus found its whole way through
            -- the precomputed walks six times and lost it to new guesses).
            -- With those walks that is the way: the rounds end here.
            if searched(steps) then
                local t=measured(steps)
                if not sureSeconds or t<sureSeconds then sure,sureSeconds=steps,t end
                if N.narrowed then steps,seconds=sure,sureSeconds;break end
            end
            -- First measure one alternative normally. A short useful detour
            -- must get its chance before the complete walk calibrates guesses.
            local again,total=N:Plan(goal,known,nil,nil,_>=2)
            -- The narrow plan left with walks known to fail only (Codex
            -- 2026-10-17: the nearest anchors all ran to the limit): wide.
            local broken=false
            for _,step in ipairs(again or {}) do
                if step.kind=="walk" and known[key(step.from)..">"..key(step.to)]==N.NOWAY then broken=true end
            end
            if (not again or broken) and N.narrowed then
                N:LeaveNetwork()
                again,total=N:Plan(goal,known,nil,nil,_>=2)
            end
            if again and searched(again) and (not sureSeconds or total<sureSeconds) then sure,sureSeconds=again,total end
            if again then
                local changed=#again~=#steps
                for i=1,math.min(#again,#steps) do if key(again[i].to)~=key(steps[i].to) or again[i].kind~=steps[i].kind then changed=true end end
                if changed then replanned=replanned+1 end
                steps,seconds=again,total
            end
        end
        if sure and not searched(steps) then steps,seconds=sure,sureSeconds end
        -- The time said from the walks' real yards (stored walks are weighed
        -- cheaper on roads, not shorter).
        if searched(steps) then seconds=measured(steps) end
        -- Counted before walks in a row are joined (a joined walk counts as
        -- precomputed when one piece is).
        N.guessedYards=N.transitWide and N.Guessed(steps,legs) or nil
        -- Walks in a row (through a flight master you do not fly from, or to
        -- a transition's end not taken) are one walk. On one level and map
        -- searched as one way (Codex's repro 2026-10-14, Florian's canal in
        -- Undercity: a walk up to a platform where an unused transition
        -- ends, then the same way back down; the way in one piece was 31
        -- yards shorter); kept when that finds none or no shorter one, else
        -- the two joined.
        for i=#steps,2,-1 do
            if steps[i].kind=="walk" and steps[i-1].kind=="walk" then
                local a,b=steps[i-1],steps[i]
                local la,lb=leg(legs,a),leg(legs,b)
                local joined={from=a.from,to=b.to,kind="walk"}
                local k=key(a.from)..">"..key(b.to)
                local direct
                -- Not when a piece is precomputed (its whole way searched again
                -- would cost the minutes it saves).
                if a.from.cont==b.to.cont and (a.from.level or false)==(b.to.level or false) and la.ok and lb.ok and not (la.transit or lb.transit) then
                    direct=leg(legs,joined)
                    if not (direct.ok and direct.yards<la.yards+lb.yards) then direct=nil end
                    -- The time said: the yards saved at your speed (Codex 2026-10-14).
                    if direct and seconds then seconds=math.max(0,seconds-(la.yards+lb.yards-direct.yards)/N:Speed()) end
                end
                if not direct then
                    local path={}
                    local pa,pb=la.path,lb.path
                    local yards=la.yards+lb.yards
                    -- (Never a precomputed walk: its proven shape stays as it is,
                    -- Codex 2026-10-17; only two searched walks are trimmed.)
                    if la.ok and lb.ok and not (la.transit or lb.transit) then
                        pa,pb=N.Trim(a.from.cont,la.path,lb.path)
                        if pa~=la.path then
                            local cut=la.yards+lb.yards-length(a.from.cont,pa)-length(b.from.cont,pb)
                            if cut>0 then yards=yards-cut;if seconds then seconds=math.max(0,seconds-cut/N:Speed()) end end
                        end
                    end
                    for _,p in ipairs(pa) do path[#path+1]=p end
                    -- (Cut: the second walk goes on from where they part.)
                    for j=(pb==lb.path) and 2 or 1,#pb do path[#path+1]=pb[j] end
                    legs[k]={path=path,yards=yards,note=la.note,seconds=la.seconds+lb.seconds,ok=la.ok and lb.ok,transit=la.transit or lb.transit,
                        status=(la.ok and lb.ok) and "ok" or (not la.ok and la.status or lb.status)}
                end
                steps[i-1]=joined;table.remove(steps,i)
            end
        end
        for i,step in ipairs(steps) do
            if step.kind=="walk" then
                local found=leg(legs,step)
                step.path,step.yards,step.noway=found.path,found.yards,not found.ok or nil
                step.status=found.status
                -- A goal on a city's level beside its given ways: the way ends
                -- on the last point of a way (fixed), not on a cell's middle
                -- joined by a guess (Codex 2026-10-17, Freewind Post: the last
                -- piece to the cell went through the post). The NPC stays
                -- marked apart when it is further.
                if found.ok and step.to.kind=="goal" and step.to.level then
                    local path=found.path
                    local k=#path
                    if k>=2 and not path[k].fixed then
                        local f
                        for j=k-1,1,-1 do if path[j].fixed then f=j;break end end
                        if f and N.Yards(step.from.cont,path[f][1],path[f][2],step.to.x,step.to.y)<=N.WAYEND then
                            local cut={}
                            for j=1,f do cut[j]=path[j] end
                            step.path=cut
                            step.yards=length(step.from.cont,cut)
                        end
                    end
                end
                -- The goal itself on a blocked spot: you arrive where the way
                -- ends; the goal (the NPC) stays marked apart (Points).
                local last=found.ok and step.to.kind=="goal" and step.path[#step.path]
                if last and N.Yards(step.from.cont,last[1],last[2],step.to.x,step.to.y)>N.APART then
                    local to={}
                    for k,v in pairs(step.to) do to[k]=v end
                    to.npc={x=step.to.x,y=step.to.y}
                    to.x,to.y=last[1],last[2]
                    step.to=to
                end
                step.report=string.format("%d. walk %d yd to %s, %d points, search %.1f s; %s",i,found.yards,step.to.name,#found.path,found.seconds,found.note)
            elseif step.kind=="flight" then
                local secs,learned=N:FlightSeconds(step.from,step.to)
                step.report=string.format("%d. fly %s -> %s, %s%s",i,step.from.name,step.to.name,N.Clock(secs),learned and " (learned)" or " (estimate)")
            elseif step.kind=="transport" then
                step.report=string.format("%d. %s: %s -> %s, about %s",i,step.by.kind,step.from.name,step.to.name,N.Clock(step.by.seconds*N.WAIT))
            else
                step.report=string.format("%d. %s: %s (%s -> %s)",i,(N.VERB[step.by.kind] or "Pass"):lower(),step.from.name,
                    Routing.Level:Name(step.from.level),Routing.Level:Name(step.to.level))
            end
        end
        return true
    end,function(ok)
        local run=N.run
        N.busy,N.run,N.budget=nil,nil,nil
        -- What it cost, in the log (Florian 2026-10-14: ingame numbers).
        if run and run.cpu then
            Routing:Note(string.format("Cost: name %s ms, goal level %s ms, first plan %s ms; %d walk(s) searched, %d known before; %.0f ms of work in %d frame(s), longest piece %.0f ms%s, %.1f s in all; budget %s%s.",
                findMs and string.format("%.0f",findMs) or "-",N.goalMs and string.format("%.0f",N.goalMs) or "-",planMs and string.format("%.0f",planMs) or "-",
                N.searched or 0,reused or 0,run.cpu,run.frames,run.longest or 0,
                run.longestTo and string.format(" (from %s to %s, %+.0f KB)",tostring(run.longestFrom or "start"),run.longestTo,run.longestKB or 0) or "",GetTime()-began,
                tostring(Routing:Config().computeBudget),run.paused and string.format(", waited %d frame(s) in combat",run.paused) or ""))
            -- Spaces made for this way, by part (time from start to end, memory grown).
            -- Whether the preparation after login was done (it shares the frames while it runs).
            Routing:Note("    Prepared after login: "..(N.prepareState or (Routing:Config().prepareAtLogin and "not yet" or "off"))..".")
            local prep=Grid.PrepCostText and Grid.PrepCostText()
            if prep then Routing:Note("  Spaces prepared: "..prep..".") end
        end
        if Grid.prepCost then Grid.prepCost={} end
        N.goalMs=nil
        Grid.BUDGET=budget
        -- No way (said while planning): no goal left over.
        if not ok and N.goal==goal and not N.steps then N.goal=nil end
        if not ok or N.goal~=goal then return end
        N.steps,N.track=steps,nil
        -- A leg nothing walkable leads along (no other way either): said, drawn straight.
        if startInfo then N:StartSaid(startInfo,steps) end
        local blocked
        for _,step in ipairs(steps) do if step.noway then blocked=step end end
        if blocked then
            local on=Routing.Level:Name(blocked.from.level)
            -- Said as it is: proven, not decided, or unknown (Codex/Florian 2026-10-16).
            if blocked.status=="limit" then
                Routing:Print(string.format("The way on \"%s\" to %s was not found within the search's limit: that leg is drawn straight. A way may still exist; searching again nearer to it can find it, or plan with flights.",on,blocked.to.name))
            elseif blocked.status=="unknown" then
                Routing:Print(string.format("Routing cannot tell whether \"%s\" leads to %s (start or goal where no walkable ground is known): that leg is drawn straight.",on,blocked.to.name))
            else
                Routing:Print(string.format("No walkable way on \"%s\" to %s: that leg is drawn straight. Route Studio's Check map shows where \"%s\" falls apart.",on,blocked.to.name,on))
            end
        end
        -- The cost of starting on another level than Routing had you on is
        -- for choosing, not time (Florian 2026-10-11: "about 15:38").
        local start=steps[1] and steps[1].from
        if start and type(start.cost)=="number" then seconds=math.max(0,seconds-start.cost) end
        -- In the chat one line; the steps in the log (/bv route log).
        N.seconds=seconds
        Routing:Print(string.format("Way to %s (%s): about %s. Details: /bv route log.",goal.name,goal.label or "goal",blocked and "?" or N.Clock(seconds)))
        N:ZoneWarning(steps)
        if replanned>0 then Routing:Note(string.format("Planned again %d time(s) with the walked lengths.",replanned)) end
        for _,step in ipairs(steps) do Routing:Note(step.report) end
        -- Legs that had no way and were left out (another way taken).
        for _,d in ipairs(dropped or {}) do Routing:Note("Left out, "..(N.STATUSWORD[d.status] or "no way")..": "..d.text) end
        Routing:Note(string.format("All legs searched in %.1f s. /bv route stop ends it.",GetTime()-began))
        if N.gapNoted then Routing:Print("Part of this way is not in the precomputed walks yet (a gap such as the Timbermaw tunnel): it was searched only so long and may be straight there. Flights or a nearer goal help.") end
        -- Found, but past the precomputed walks (Codex 2026-10-18: Gadgetzan
        -- to Marshal's Refuge took a terrain walk down Un'Goro's cliffs that
        -- the full ground check fails): said, never passed off as proven.
        local guessed=not N.gapNoted and N.guessedYards
        if guessed then Routing:Print(string.format("%d yd of this way are not in the precomputed walks: found on the terrain only, they may lead down a cliff or through water.",guessed)) end
        local probe=Routing.Probe
        if probe and probe.on then probe:Plan(goal,steps) end
        N:Show()
        N:Watch(true)
    end)
    -- Long: asked whether to go on (Routing.Busy, Florian 2026-10-15).
    if self.run then self.run.askStop=function() Routing:Print("Stopped calculating the way to "..tostring(goal.name)..".");N:Stop(true) end end
    return true
end
-- The level the way starts on, said and taken as yours (several were open).
function N:StartSaid(info,steps)
    local from=steps[1] and steps[1].from.level
    local name=Routing.Level:Name(from)
    if info.known then
        if (from or false)~=(info.here or false) then
            Routing:Print(string.format("No way leads on from \"%s\" (where Routing had you): starting from \"%s\". /bv route level <name> sets it.",Routing.Level:Name(info.here),name))
        end
    elseif #info.open>1 then
        local names={}
        for _,level in ipairs(info.open) do names[#names+1]=Routing.Level:Name(level or nil) end
        Routing:Print("Not sure which level you are on ("..table.concat(names," or ").."); starting from \""..name.."\". /bv route level <name> sets it.")
    elseif (from or false)==(info.likely or false) then
        if from~=nil then Routing:Print("You are on the level \""..name.."\" (the street you stand on).") end
    else
        Routing:Print(string.format("Starting from \"%s\": no way leads on from \"%s\", the nearest street.",name,Routing.Level:Name(info.likely or nil)))
    end
    Routing.Level:Set(from)
end
function N.Clock(seconds)
    seconds=math.floor((seconds or 0)+.5)
    if seconds>=3600 then return string.format("%d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60) end
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end
-- The way searched anew from where you are now, to the same goal (Florian
-- 2026-10-14: the guide's button, when you came far off the way).
function N:Restart()
    if self.busy then Routing:Print("Still calculating.");return false end
    local goal=self.goal
    if not goal then return false end
    self:Stop(true)
    Routing:Print("Searching the way anew from where you are.")
    return self:Start(goal)
end
-- Safe or normal for this way (Florian 2026-10-16: a switch in the guide,
-- the setting only the default): the way searched again in the other mode.
function N:ToggleSafe()
    if self.busy then Routing:Print("Still calculating.");return false end
    if not self.goal then return false end
    self.modeOverride=Routing:RouteMode()=="safe" and "normal" or "safe"
    Routing:Print(self.modeOverride=="safe" and "This way: safe (keeps to roads, goes round zones above your level)." or "This way: normal.")
    return self:Restart()
end
-- The whole way as text for a bug report (Florian 2026-10-14): versions,
-- where it started and the goal, the settings that change ways, the maps
-- on it with their data sets, every step with its points (map 0..1, six
-- places), then the log. One line per item, tab separated "key=value":
-- readable, and read back by tools (BVROUTE1).
function N:ExportText()
    local out={"BVROUTE1"}
    local function add(...)
        local parts={...}
        for i=1,#parts do parts[i]=tostring(parts[i]) end
        out[#out+1]=table.concat(parts,"\t")
    end
    local query=C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local function version(name)
        if type(query)~="function" then return "?" end
        local ok,v=pcall(query,name,"Version")
        return ok and v or "?"
    end
    add("versions","core="..version("BVAddonSuite"),"routing="..version("BVAddonSuite_Routing"),"routestudio="..version("BVAddonSuite_RouteStudio"),
        "mapdata="..version("BVAddonSuite_MapData"),"gather="..version("BVAddonSuite_Gather"))
    add("date",date("%Y-%m-%d %H:%M:%S"))
    local function f6(v) return type(v)=="number" and string.format("%.6f",v) or "-" end
    local function lv(level) return tostring(level or "ground").."|"..Routing.Level:Name(level) end
    local s=self.startAt
    if s then
        add("start","map="..tostring(s.mapID),"x="..f6(s.mx),"y="..f6(s.my),"cont="..tostring(s.cont),"cx="..f6(s.x),"cy="..f6(s.y),
            "level="..lv(s.level),"subzone="..tostring(s.subzone or ""))
    end
    local g=self.goal
    if g then add("goal","name="..tostring(g.name),"label="..tostring(g.label or ""),"cont="..tostring(g.cont),"cx="..f6(g.x),"cy="..f6(g.y),"level="..lv(g.level)) end
    -- Zone levels (Florian 2026-10-16: no warning seen): the goal's zone, its range, your level.
    if g and g.cont and Routing.ZoneAt then
        local zone,zname=Routing:ZoneAt(g.cont,g.x,g.y)
        local range=zone and Routing.ZONE_LEVELS[zone]
        local okLevel,you=pcall(UnitLevel,"player")
        add("zones","goal="..tostring(zone),"name="..tostring(zname),"range="..(range and (range[1].."-"..range[2]) or "none"),"you="..tostring(okLevel and you),"mode="..tostring(Routing:ZoneMode()),"routeMode="..tostring(Routing:RouteMode()),"default="..tostring(Routing:Config().routeMode))
    end
    local cfg=Routing:Config()
    add("settings","routeTerrain="..tostring(cfg.routeTerrain),"avoidWater="..tostring(cfg.avoidWater),"preferRoads="..tostring(cfg.preferRoads),"useFlights="..tostring(cfg.useFlights),
        "risk="..tostring(cfg.risk),"enemy="..tostring(cfg.enemy),"cliffs="..tostring(cfg.cliffs),
        "roadPercent="..tostring(cfg.roadPercent),"walkedPercent="..tostring(cfg.walkedPercent))
    -- The maps on the way (start, goal, every step's ends): cell size,
    -- clearance, source, and their data sets.
    local maps,seen={},{}
    local function map(cont,x,y)
        if not (cont and x and y) then return end
        local info=call("C_Map.GetMapInfoAtPosition",cont,x,y)
        local id=type(info)=="table" and info.mapID
        if id and not seen[id] then seen[id]=true;maps[#maps+1]=id end
    end
    if s then map(s.cont,s.x,s.y) end
    if g then map(g.cont,g.x,g.y) end
    for _,step in ipairs(self.steps or {}) do map(step.from.cont,step.from.x,step.from.y);map(step.to.cont,step.to.x,step.to.y) end
    local data=Routing:Data()
    for _,id in ipairs(maps) do
        local m=(data.maps or {})[id]
        m=type(m)=="table" and m or {}
        add("map",id,"cell="..tostring(Routing.Grid.CellFor(id)),"clearance="..tostring(m.clearance or "default"),"mineOff="..tostring(m.mineOff==true),"source="..tostring(m.source or "mine"))
    end
    for id,set in pairs(Routing:Store().sets or {}) do
        if type(set)=="table" and seen[set.map] then
            add("set",id,"map="..tostring(set.map),"name="..tostring(set.name or ""),"off="..tostring(set.off==true),"by="..tostring(set.by or ""))
        end
    end
    for i,step in ipairs(self.steps or {}) do
        local by=type(step.by)=="table" and (tostring(step.by.kind or "")..":"..tostring(step.by.name or "")) or ""
        add("step",i,"kind="..step.kind,"from="..tostring(step.from.name),"to="..tostring(step.to.name),"cont="..tostring(step.from.cont),
            "fromLevel="..lv(step.from.level),"toLevel="..lv(step.to.level),"yards="..string.format("%.1f",step.yards or 0),"by="..by,i==self.current and "current" or "")
        if type(step.path)=="table" then
            local pts={}
            for _,p in ipairs(step.path) do pts[#pts+1]=f6(p[1])..","..f6(p[2]) end
            add("points",i,table.concat(pts,";"))
        end
    end
    if self.seconds then add("seconds",string.format("%.0f",self.seconds)) end
    out[#out+1]="log"
    for _,line in ipairs(Routing.log) do out[#out+1]=line end
    return table.concat(out,"\n")
end
-- What the spaces are made of: the data (its sets switched, counts per
-- map, the maps' settings, Route Studio's changes), the way settings, and
-- Gather's walked ways. Spaces are kept between ways while it is the same.
N.KEEP=300   -- seconds the spaces of an ended way are taken again (no timer: asked at the next way)
function N:Stamp()
    local cfg=Routing:Config()
    local db=Routing:Store()
    local data=Routing:Data()
    local roads=rawget(_G,"BVRoutingRoads")
    local parts={tostring(Routing.offVersion),tostring(db.source),tostring(cfg.routeTerrain),tostring(cfg.avoidWater),tostring(cfg.preferRoads),tostring(cfg.useFlights),
        tostring(cfg.roadPercent),tostring(cfg.walkedPercent),tostring(Routing:RouteMode()),tostring(Routing:ZoneMode()),Routing:ZoneMode()=="avoid" and tostring(UnitLevel and UnitLevel("player")) or "",
        tostring(type(roads)=="table" and roads.revision),tostring(type(rawget(_G,"BVRoutingTransit"))=="table" and rawget(_G,"BVRoutingTransit").revision),
        tostring(cfg.risk),tostring(cfg.enemy),tostring(self.enemyOff),tostring(cfg.cliffs),tostring(Routing.Grid.PreferWalked and Routing.Grid.PreferWalked())}
    for _,kind in ipairs(Routing.KINDS) do
        local ids={}
        for id,list in pairs(data[kind] or {}) do if type(list)=="table" then ids[#ids+1]=tostring(id)..":"..#list end end
        table.sort(ids)
        parts[#parts+1]=kind.."="..table.concat(ids,",")
    end
    parts[#parts+1]="links="..#(data.links or {})
    local maps={}
    for id,m in pairs(data.maps or {}) do
        if type(m)=="table" then maps[#maps+1]=string.format("%s:%s,%s,%s,%s",tostring(id),tostring(m.cell),tostring(m.clearance),tostring(m.paintedOnly),tostring(m.mineOff)) end
    end
    table.sort(maps)
    parts[#parts+1]=table.concat(maps,";")
    return table.concat(parts,"|")
end
function N:Stop(quiet)
    local had=self.steps or self.busy
    -- Its spaces kept a while for the next way (N:Stamp, N.KEEP).
    if self.spaces and self.spacesStamp and not self.busy then
        self.kept={stamp=self.spacesStamp,spaces=self.spaces,legs=self.legs,at=GetTime()}
    end
    if self.run then self.run:Cancel();self.run=nil end
    if self.budget then Routing.Grid.BUDGET=self.budget end
    self.steps,self.goal,self.current,self.spaces,self.busy,self.budget,self.left,self.flightNote=nil,nil,nil,nil,nil,nil,nil,nil
    self:Watch(false)
    self:Show()
    if had and not quiet then Routing:Print("Way ended.") end
end
function N:Status()
    if self.busy then return "Calculating the way to "..(self.goal and self.goal.name or "?").."." end
    if not self.steps then return "No way. /bv route <what> | way | <x> <y>." end
    local step=self.steps[self.current]
    return string.format("Way to %s: step %d of %d (%s), you are on %s.",self.goal.name,self.current,#self.steps,
        step and step.kind or "-",Routing.Level:Name(Routing.Level:Current()))
end

-- On the maps: every step's points in its colour, stops as rings, the goal
-- white; the leg you walk now starts with a line from you. Legs on another
-- level than yours are fainter on the minimap.
-- The legs after the one you are on, dimmed (Florian 2026-10-11: ways
-- over each other on several levels were unclear in one colour), step by
-- step (Florian 2026-10-14: the next one hardly, then more): FADESTEPS legs
-- on the full dimming of AHEADLINE and AHEADPIN.
N.DRAWSTEP=2
N.AHEADLINE=.3
N.AHEADPIN=.55
N.FADESTEPS=3
function N.Fade(n,full,steps)
    if n<=0 then return 1 end
    return 1-(1-full)*math.min(1,n/(steps or N.FADESTEPS))
end
-- The dimming as the settings say (Florian 2026-10-16): line and pin at full
-- dimming, legs to get there; pins keep their share of the line's dimming
-- (built in: line .3, pin .55).
N.PINSHARE=(1-N.AHEADPIN)/(1-N.AHEADLINE)
function N:Ahead()
    local c=Routing:Config()
    local line=c.aheadOpacity/100
    return line,1-(1-line)*N.PINSHARE,c.aheadSteps
end
-- The points of each leg kept while nothing about it changes (Claude 2026-10-20:
-- the minimap repaints ten times a second while you walk; new tables for every
-- point of a long way each time also missed Core's memo of where each point lies,
-- two client calls per point, and walking a way made the game slow).
function N:Points()
    local out={}
    if not self.steps then return out end
    -- Your level by the plan (the step you are on).
    local now=self.steps[self.current]
    local here=now and now.from.level
    local aheadLine,aheadPin,aheadSteps=self:Ahead()
    if self.pointSteps~=self.steps then self.pointSteps,self.pointCache=self.steps,{} end
    local cache=self.pointCache
    local cfg=Routing:Config()
    local colors=table.concat({tostring(cfg.colorWalk),tostring(cfg.colorFlight),tostring(cfg.colorTransport),tostring(cfg.colorTransition),tostring(cfg.colorGoal)},":")
    for i,step in ipairs(self.steps) do
        if i>=self.current then
            local ahead=(i==self.current and step.kind=="walk" and step.path) and (self.ahead or 1) or 1
            local id=string.format("%d:%d:%s:%s:%s:%s:%s:%s",i-self.current,ahead,tostring(step.path),tostring(here),tostring(aheadLine),tostring(aheadPin),tostring(aheadSteps),colors)
            local c=cache[i]
            if not (c and c.id==id) then c={id=id,list=self:StepPoints(i,step,here,aheadLine,aheadPin,aheadSteps,ahead)};cache[i]=c end
            for _,point in ipairs(c.list) do out[#out+1]=point end
        end
    end
    return out
end
-- One leg's points for the maps (N:Points).
function N:StepPoints(i,step,here,aheadLine,aheadPin,aheadSteps,ahead)
    local out={}
    local color=N:Color(step.kind)
    local from,to=step.from,step.to
    local dim=(from.level or 0)~=(here or 0) or nil
    local later=i>self.current
    local la,pa=N.Fade(i-self.current,aheadLine,aheadSteps),N.Fade(i-self.current,aheadPin,aheadSteps)
    -- The walk you are on: from the next point ahead of you, the line
    -- from you leading to it (Florian 2026-10-11: it led back to the
    -- leg's start behind you). self.ahead: Tick, the path point after
    -- the piece you are nearest to.
    local lead=i==self.current and step.kind=="walk"
    if ahead<=1 then
        out[#out+1]={mapID=from.cont,x=from.x,y=from.y,noPin=from.kind=="start" or nil,dot=true,size=10,hollow=true,color=color,alpha=pa,lineAlpha=la,dim=dim,
            lead=lead or nil,leadColor=color}
        lead=false
    end
    if step.path then
        -- Points DRAWSTEP yards apart at least (Florian 2026-10-14:
        -- the Slaughtered Lamb's spiral, 338 points on 62 yards, was
        -- not drawn at all: pieces of a fraction of a pixel); the
        -- way itself keeps every point.
        local lx,ly=step.path[math.max(1,ahead-1)][1],step.path[math.max(1,ahead-1)][2]
        for j=math.max(2,ahead),#step.path-1 do
            local px,py=step.path[j][1],step.path[j][2]
            if lead or N.Yards(from.cont,lx,ly,px,py)>=N.DRAWSTEP then
                out[#out+1]={mapID=from.cont,x=px,y=py,noPin=true,lineColor=color,lineAlpha=la,dim=dim,
                    lead=lead or nil,leadColor=color}
                lead=false
                lx,ly=px,py
            end
        end
    end
    -- A teleport: no line between its ends (none to walk).
    local jump=N.Teleport(step)
    out[#out+1]={mapID=to.cont,x=to.x,y=to.y,dot=true,size=to.kind=="goal" and 14 or 10,hollow=true,dim=(to.level or 0)~=(here or 0) or nil,
        color=to.kind=="goal" and N:Color("goal") or color,alpha=(later and to.kind~="goal") and pa or 1,lineColor=color,lineAlpha=jump and 0 or la,noLine=jump or nil,lead=lead or nil,leadColor=color}
    -- The goal where the way cannot reach it (its NPC on no-go): a
    -- small mark of its own, no line to it.
    if to.npc then
        out[#out+1]={mapID=to.cont,x=to.npc.x,y=to.npc.y,dot=true,size=9,color=N:Color("goal"),alpha=.8,lineAlpha=0,noLine=true,dim=(to.level or 0)~=(here or 0) or nil}
    end
    return out
end
function N:Show()
    if Routing.Guide then Routing.Guide:Update() end
    if not ns.MapPins then return end
    if not self.registered then
        self.registered=true
        ns.MapPins:Register("routing:way",{points=function() return N:Points() end,lines=true,arrows=true,minimap=true,
            tooltip=function() return N.goal and N.goal.name,{tag="Way",hint="/bv route stop ends it"} end})
    end
    ns.MapPins:Refresh()
end
-- What to do next, told when a step begins.
function N:Tell(step)
    if not step then return end
    -- The guide shows it; the chat stays quiet (the log keeps it).
    if step.kind=="walk" then Routing:Note("Walk to "..step.to.name..".")
    elseif step.kind=="flight" then Routing:Note("Take the flight to "..step.to.name..".")
    elseif step.kind=="transport" then Routing:Note("Take the "..step.by.kind.." to "..step.to.name..".")
    else Routing:Note(self:Say(step)..".") end
end
-- A step in a few words, for the guide (Florian 2026-10-12: what comes next,
-- walking or the transition by its name and kind). yards: what is left of it.
-- Transitions by their kind, for the guide: a heading, what you do, what it
-- is called when Route Studio named it itself ("Walk 21", "Lift 2").
N.PASSAGE={walk={head="Passage",verb="Go through",thing="the passage",icon="door-open"},
    lift={head="Lift",verb="Take the lift",thing="the lift",icon="arrow-up-down"},
    jump={head="Drop",verb="Jump down",thing="the drop",icon="arrow-down-to-line"},
    teleport={head="Teleport",verb="Use the teleport",thing="the teleport",icon="sparkles"},
    transport={head="Ride",verb="Ride",thing="the ride",icon="ship"}}
local function own(name)
    return type(name)=="string" and not name:match("^%a+ %d+$") and name or nil
end
-- What a step's end is called: a transition by its own name or its kind.
function N:Called(node,after)
    if node.kind=="door" then
        local link=after and type(after.by)=="table" and after.by or node.link
        local p=N.PASSAGE[link and link.kind or "walk"] or N.PASSAGE.walk
        return own(node.name) or p.thing
    end
    return node.name or "?"
end
-- A step in parts: {head, icon, verb, target, name}.
function N:Parts(step)
    local to=step.to
    if step.kind=="walk" then
        local i
        for k,s in ipairs(self.steps or {}) do if s==step then i=k end end
        local after=i and self.steps[i+1]
        return {head="Walk",icon="footprints",verb="Walk",target="to "..self:Called(to,after)}
    elseif step.kind=="flight" then return {head="Flight",icon="plane",verb="Fly",target="to "..to.name}
    elseif step.kind=="transport" then
        local kind=tostring(step.by.kind or "ride")
        return {head=kind:sub(1,1):upper()..kind:sub(2),icon="ship",verb="Take the "..kind,target="to "..to.name}
    end
    local kind=type(step.by)=="table" and step.by.kind or "walk"
    local p=N.PASSAGE[kind] or N.PASSAGE.walk
    -- Up or down (by the levels' heights), and where to by its district.
    local L=Routing.Level
    local dir=L:Way(step.from.level,to.level,step.from.cont,step.from.x,step.from.y)
    local verb=p.verb
    if kind=="walk" then verb=dir and ("Go "..dir) or "Go through"
    elseif kind=="lift" and dir then verb=p.verb.." "..dir end
    -- Both in one district (Florian 2026-10-14: "down to The Slaughtered
    -- Lamb" into its cellar): the level's own name.
    local where=L:Shown(to.level)
    if to.level~=nil and where==L:Shown(step.from.level) then
        local level=L:Find(to.level)
        where=type(level)=="table" and level.name or where
    end
    return {head=p.head,icon=p.icon,verb=verb,target="to "..where,name=own(step.from.name)}
end
-- short: without a transition's own name (the guide's "Then").
function N:Say(step,yards,short)
    if not step then return "" end
    local parts=self:Parts(step)
    if step.kind=="walk" and yards then return string.format("Walk %d yd %s",math.floor(yards+.5),parts.target) end
    -- The name of its own after what it is: "Take the lift (Bat Lift) up".
    local verb=parts.verb
    if parts.name and not short then
        local head,rest=verb:match("^(.-) (up)$")
        if not head then head,rest=verb:match("^(.-) (down)$") end
        verb=head and (head.." ("..parts.name..") "..rest) or (verb.." ("..parts.name..")")
    end
    return verb.." "..parts.target
end
-- Seconds a step takes by the plan's own estimate.
function N:StepSeconds(step)
    if step.kind=="walk" then
        local yards=step.yards or N.Yards(step.from.cont,step.from.x,step.from.y,step.to.x,step.to.y)*N.DETOUR
        return yards/self:Speed()
    elseif step.kind=="flight" then return (self:FlightSeconds(step.from,step.to))
    elseif step.kind=="transport" then return (tonumber(step.by.seconds) or 0)*N.WAIT end
    local link=type(step.by)=="table" and step.by or {}
    local yards=step.path and N.Length(step.from.cont,step.path) or N.Yards(step.from.cont,step.from.x,step.from.y,step.to.x,step.to.y)
    return tonumber(link.seconds) or math.max(N.PASS,yards/self:Speed())
end
-- Seconds left to the goal: of the step you are on what is left of its way
-- (Tick keeps it), then the steps after it.
function N:SecondsLeft()
    if not self.steps then return nil end
    local i=self.current or 1
    local step=self.steps[i]
    if not step then return 0 end
    local now=self:StepSeconds(step)
    if self.left and (step.kind=="walk" or step.kind=="transition") then
        now=step.kind=="walk" and self.left/self:Speed() or math.min(now,math.max(N.PASS,self.left/self:Speed()))
    end
    local total=now
    for k=i+1,#self.steps do total=total+self:StepSeconds(self.steps[k]) end
    return total
end
-- Once a second, along the plan (Florian 2026-10-10: guessing your level
-- each second let the steps hang in cities, where ways of different
-- levels cross): you are on the step you are on, the steps go one by one.
-- A walk ends at its end (a door or stairs at DOOR yards, a flight master
-- or a dock at REACH, the goal at ARRIVE); a transition when you come out
-- at its other end (Taken); after a flight or a ride (nobody can follow
-- you on them) the step whose end you are near. Off the walked way a new
-- search from where you are, on the step's level.
-- Where you are against the way: TICK seconds (Florian 2026-10-14: once a
-- second, the arrow and the drawn way lagged behind you and turned back);
-- off the way for OFFLOOKS looks in a row (two seconds as before) before a
-- new plan.
N.TICK=.25
N.OFFLOOKS=8
function N:Watch(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(N.TICK,function() N:Tick() end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
local function segment(cont,px,py,ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    local len=dx*dx+dy*dy
    local t=len>0 and math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/len)) or 0
    return N.Yards(cont,px,py,ax+dx*t,ay+dy*t)
end
local function nearest(cont,px,py,path)
    local near=math.huge
    for j=2,#(path or {}) do near=math.min(near,segment(cont,px,py,path[j-1][1],path[j-1][2],path[j][1],path[j][2])) end
    return near
end
N.Nearest=nearest
-- The probe (/bv route probe) hears what happens.
local function note(text)
    Routing:Note(text)
    local probe=Routing.Probe;if probe and probe.on then probe:Note(text) end
end
-- Where you are along the whole way (Florian 2026-10-11: "we keep adding a
-- rule for every case instead of solving the logic"). One estimate instead
-- of rules per kind of step:
--  - The track: every walk and transition of the plan as one line of
--    pieces, each knowing its step and how far along the way it lies.
--    Flights and rides are marks on it (nobody can follow you on them).
--  - Each second the piece nearest to you, only forward and only within
--    WINDOW yards along the way after where you were. A piece of a level
--    your height denies is not you.
--  - A gate at every change of level: the pieces after a transition count
--    only with evidence that you went through it (Crossed). Where levels
--    lie over each other the map position alone never decides.
--  - A step is done when you are on a later one, or at a walk's end with
--    little of its way left. No piece within OFF yards: off the way.
N.WINDOW=60
N.TIE=2
N.LEAP=20         -- yards the tracker may take you ahead at once among pieces about as near
N.AGAIN=10        -- seconds at least between plans anew when off the way
-- Yards left of a transition that count as its end: a walked shape to near
-- its end, else DOOR.
local function endOf(step)
    return type(step)=="table" and type(step.path)=="table" and #step.path>=3 and N.SHAPEEND or N.DOOR
end
N.EndOf=endOf
-- A teleport (Codex 2026-10-14, Darnassus' portals): no way between its
-- ends to walk; tracked as a ride, through it where it lands.
function N.Teleport(step)
    return type(step)=="table" and step.kind=="transition" and type(step.by)=="table" and step.by.kind=="teleport"
end
function N:BuildTrack()
    local pieces,along={},0
    for i,step in ipairs(self.steps or {}) do
        local pts=step.path
        if (step.kind=="walk" or step.kind=="transition") and not N.Teleport(step) then
            if type(pts)~="table" or #pts<2 then pts={{step.from.x,step.from.y},{step.to.x,step.to.y}} end
            if step.from.cont==step.to.cont then
                for j=2,#pts do
                    local ax,ay,bx,by=pts[j-1][1],pts[j-1][2],pts[j][1],pts[j][2]
                    local len=N.Yards(step.from.cont,ax,ay,bx,by)
                    pieces[#pieces+1]={step=i,j=j,kind=step.kind,cont=step.from.cont,ax=ax,ay=ay,bx=bx,by=by,a0=along,len=len}
                    along=along+len
                end
            end
        else
            pieces[#pieces+1]={step=i,ride=true,a0=along,len=0}
        end
    end
    self.track,self.trackOf,self.trackAlong,self.farthest=pieces,self.steps,nil,nil
    return pieces
end
-- Yards from you to a piece, and how far along it (0..1).
local function onPiece(g,cont,px,py)
    local ax,ay,bx,by=g.ax,g.ay,g.bx,g.by
    local w,h=1,1
    local dx,dy=bx-ax,by-ay
    local len=dx*dx+dy*dy
    local t=len>0 and math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/len)) or 0
    return N.Yards(cont,px,py,ax+dx*t,ay+dy*t),t
end
-- Did you go through a transition (from, to)? Evidence, not the map
-- position alone: your height (it must not deny the level it leads to; it
-- fitting there and not where it starts says so), the district naming
-- that level; on stairs and ramps reaching their end; at a lift (one spot)
-- having stood there its time, or walked off it along the next leg.
-- atEnd: you have come along its walked shape to its last SHAPEEND yards (EndOf).
function N:Crossed(i,cont,px,py,atEnd,nearEnd)
    local step=self.steps[i]
    local from,to=step.from,step.to
    if to.cont~=cont then return false end
    local H=Routing.Height
    -- (false kept: "a and false or nil" was nil, Codex 2026-10-14.)
    local toFits,fromFits
    if H and to.level~=nil then toFits=H:FitsLevel(to.level,cont,px,py) end
    if H and from.level~=nil then fromFits=H:FitsLevel(from.level,cont,px,py) end
    if toFits==false then return false end
    -- A walked shape (stairs, a ramp round a tower, however near its ends
    -- lie on the map): through it when you came along it to its end.
    if type(step.path)=="table" and #step.path>=3 then
        if atEnd then return true,"along its walked shape to its end" end
        -- Off it near its end onto the next leg (Claude's walk simulation
        -- 2026-10-13, Florian's flight tower: off the ramp onto the top a few
        -- yards before the end drawn, the guide waited there for good).
        local after=self.steps[i+1]
        if nearEnd and after and after.path and nearest(cont,px,py,after.path)+N.TIE<nearest(cont,px,py,step.path) then
            return true,"off its walked shape near its end onto the next leg"
        end
        return false
    end
    if toFits==true and fromFits~=true then return true,"your height fits its level" end
    local dTo=N.Yards(cont,px,py,to.x,to.y)
    local apart=N.Yards(cont,from.x,from.y,to.x,to.y)
    local cue=Routing.Level:Cue()
    if cue~=nil and cue==to.level and (apart<N.SPOT or dTo<=N.DOOR) then return true,"the district names its level" end
    -- Your height fitting where it starts says you are still there only when
    -- it does not fit where it leads too (Florian 2026-10-12: Town -62 and
    -- Mage Down -61, both fit; the lift to Mage Down was never through).
    if fromFits==true and toFits~=true then return false end
    if apart>=N.SPOT then
        if dTo<=N.DOOR and dTo<N.Yards(cont,px,py,from.x,from.y) then return true,string.format("out at its other end (%.0f yd)",dTo) end
        return false
    end
    -- One spot: when you were there first; then off it again along the next leg.
    local after,before=self.steps[i+1],self.steps[i-1]
    -- Past a door to where the next leg ends (Claude's walk simulation
    -- 2026-10-12: Orgrimmar's banker stands 10 yards inside its door, never
    -- LEAVE yards from it). Not at a lift: its other end may lie over you.
    local lift=type(step.by)=="table" and step.by.kind=="lift"
    if not lift and after and after.kind=="walk" and after.to and dTo>=N.SPOT and N.Yards(cont,px,py,after.to.x,after.to.y)<N.SPOT then
        return true,"past it at the end of the next leg"
    end
    if dTo<=N.DOOR then self.door=self.door or GetTime();return false end
    if dTo<N.LEAVE then return false end
    local onNext=after and after.path and nearest(cont,px,py,after.path) or math.huge
    local onLast=before and before.path and nearest(cont,px,py,before.path) or math.huge
    if onNext<=N.OFF/2 and onNext<onLast then return true,string.format("left it along the next leg (%.0f yd from it)",onNext) end
    local wait=(step.by and tonumber(step.by.seconds)) or N.PASS
    if self.door and GetTime()-self.door>=wait and onNext<=N.OFF then return true,"waited there and walked off" end
    return false
end
-- The piece of the track you are on: {piece, step, yards from it, left (of
-- its step's way), why}; nil when none is within OFF (off the way).
function N:Locate(cont,px,py)
    -- The track belongs to its plan: a new plan, a new track.
    local track=(self.track and self.trackOf==self.steps) and self.track or self:BuildTrack()
    local was=self.trackAlong or 0
    local first
    for k,g in ipairs(track) do if g.step==self.current then first=k;break end end
    if not first then return nil end
    local found,passed={},{}
    local base=was
    for k=first,#track do
        local g=track[k]
        if g.ride then break end
        -- Into the step after a transition: only through its gate.
        local prev=track[k-1]
        if prev and prev.step~=g.step and prev.kind=="transition" and k>first then
            -- Its end reached along the way so far (walked shapes count by it).
            -- (How far you came, not where you are now: off a ramp's top
            -- you are nearer to a lower turn than to its end.)
            local far=math.max(was,self.farthest or 0)
            local atEnd=far>=prev.a0+prev.len-endOf(self.steps[prev.step])
            local ok,reason=self:Crossed(prev.step,cont,px,py,atEnd,far>=prev.a0+prev.len-N.DOOR)
            if not ok then break end
            passed[g.step]=reason
            -- Through it: the window counts from here (a long transition).
            base=g.a0
        end
        -- Beyond the window (on one level): not you, but the gates further
        -- on are still asked; one through by evidence counts from there.
        if g.cont==cont and g.a0+g.len>=was-N.WINDOW and g.a0-base<=N.WINDOW then
            local level=self.steps[g.step].from.level
            local H=Routing.Height
            local denied=g.kind=="walk" and level~=nil and H and H:FitsLevel(level,cont,px,py)==false
            if not denied then
                local d,t=onPiece(g,cont,px,py)
                found[#found+1]={g,d,t}
            end
        end
    end
    -- The nearest piece; of pieces about as near (TIE yards: a lift's spot
    -- and the leg starting there), the one furthest along.
    local minD
    for _,f in ipairs(found) do if not minD or f[2]<minD then minD=f[2] end end
    if not minD or minD>N.OFF then return nil end
    -- Not further than LEAP yards ahead of where you were (Claude's walk
    -- simulation 2026-10-12: at the foot of Orgrimmar's flight tower ramp,
    -- a spiral, its top lies over its foot; the tracker took the top at
    -- once). A step beyond a gate passed by evidence (your height, the
    -- lift taken) is not a leap. Only when no piece that near is about as
    -- near: the nearest.
    local best,bestD,bestT
    for _,f in ipairs(found) do
        if f[2]<=minD+N.TIE and (passed[f[1].step] or f[1].a0+f[1].len*f[3]<=was+N.LEAP) then best,bestD,bestT=f[1],f[2],f[3] end
    end
    if not best then
        for _,f in ipairs(found) do if f[2]==minD then best,bestD,bestT=f[1],f[2],f[3] end end
    end
    local pos=best.a0+best.len*bestT
    self.trackAlong=math.max(pos,was-N.WINDOW)
    -- The farthest along you came on this step (Claude's walk simulation
    -- 2026-10-13: 5 yards before the end of Florian's flight tower ramp, then
    -- onto the top, and the tracker had you 19 yards before it again).
    if best.step==self.current then self.farthest=math.max(self.farthest or 0,pos) end
    -- What is left of that step's way.
    local stepEnd=pos
    for k=1,#track do local g=track[k];if g.step==best.step then stepEnd=math.max(stepEnd,g.a0+g.len) end end
    return {piece=best,step=best.step,d=bestD,left=stepEnd-pos,why=passed[best.step]}
end
-- The point the guide's arrow points to on a walk (Florian 2026-10-14: on
-- a winding way of many short pieces each point was reached late and the
-- arrow swung back and forth): LOOK yards along the way ahead of the
-- farthest you came on this step, so it never turns back; the step's end
-- when less is left. nil before you are placed on the way.
N.LOOK=15
function N:Carrot()
    local track=self.track
    if not (track and self.trackOf==self.steps and self.farthest) then return nil end
    local target=self.farthest+N.LOOK
    local last
    for _,g in ipairs(track) do
        if g.step==self.current and not g.ride then
            last=g
            if g.a0+g.len>=target then
                local t=g.len>0 and math.max(0,math.min(1,(target-g.a0)/g.len)) or 1
                return g.cont,g.ax+(g.bx-g.ax)*t,g.ay+(g.by-g.ay)*t
            end
        end
    end
    if last then return last.cont,last.bx,last.by end
end
-- On to step i (the one now begun); your level is where the last one ended.
function N:Advance(i,reason)
    note(string.format("on to step %d: %s",i,reason or "?"))
    local done=self.steps[i-1]
    if done then Routing.Level:Set(done.to.level) end
    self.current,self.off,self.door,self.ahead,self.left,self.farthest=i,0,nil,nil,nil,nil
    if i>#self.steps then
        local goal=self.goal
        -- Only the nearest street of a goal the map has no level for: not
        -- arrived, no tour's next stop (Codex 2026-10-14).
        if goal.unmapped then
            Routing:Print(string.format("This is as near as the map leads to %s: it stands where the map has no level. The last stretch is yours.",goal.name))
            self:Stop(true)
            return
        end
        Routing:Print("You have arrived: "..goal.name..".")
        self:Stop(true)
        -- Who asked to be told (Codex: on to the tour's next stop).
        local arrive=self.onArrive
        if arrive then pcall(arrive,goal) end
        return
    end
    self:Tell(self.steps[i])
    self:Show()
end
function N:Tick()
    if not self.steps or self.busy then return end
    local cont,px,py=self:Here()
    if not cont then return end
    local i=self.current
    local step=self.steps[i]
    if not step then return end
    local function near(p,r) return p.cont==cont and N.Yards(cont,px,py,p.x,p.y)<=r end
    -- Through a teleport: where it lands, your height not against its level;
    -- on it, or still on the way to it (between two looks you may already
    -- have gone through).
    local tp=N.Teleport(step) and i or (N.Teleport(self.steps[i+1]) and i+1)
    if tp then
        local to=self.steps[tp].to
        local H=Routing.Height
        -- (Landing on the ground too: your height not against the ground,
        -- Codex 2026-10-14.)
        if near(to,N.PORTAL) and not (H and H:FitsLevel(to.level,cont,px,py)==false) then
            return self:Advance(tp+1,"through the teleport")
        end
        if tp==i then return end
    end
    -- After a flight or a ride: the step whose end you are near (got off early or late).
    -- Not while still on the flight; and that end's level must fit your height (Florian
    -- 2026-10-19: landed on Orgrimmar's tower, the gate's bottom right below counted as
    -- near, steps 3-8 were skipped and the way planned anew twice).
    if step.kind=="flight" or step.kind=="transport" then
        if step.kind=="flight" and UnitOnTaxi and UnitOnTaxi("player") then return end
        local H=Routing.Height
        -- Landed where the ride ends: on with the next step (before any later end that only
        -- lies near on the map, a level below).
        if near(step.to,step.to.kind=="goal" and N.ARRIVE or N.REACH) then return self:Advance(i+1,"at the end of the ride") end
        for j=#self.steps,i+1,-1 do
            local t=self.steps[j].to
            if near(t,t.kind=="goal" and N.ARRIVE or N.REACH) and not (H and t.level and H:FitsLevel(t.level,cont,px,py)==false) then
                return self:Advance(j+1,"near the end of step "..j.." after the ride")
            end
        end
        return
    end
    -- Walks and transitions: where you are along the whole way (Locate).
    local at=self:Locate(cont,px,py)
    if at then
        self.off=0
        self.left=at.step==i and at.left or nil
        if at.step>i then return self:Advance(at.step,at.why and ("through the transition: "..at.why) or "on a later leg of the way") end
        -- On a transition, at its end (a lift: on its spot) and through its gate.
        if step.kind=="transition" and at.left<=N.DOOR then
            local ok,why=self:Crossed(i,cont,px,py,at.left<=endOf(step),true)
            if ok then return self:Advance(i+1,"transition taken: "..why) end
        end
        if step.kind=="walk" then
            local to=step.to
            -- A flight master stands on a spot (Florian 2026-10-15: on
            -- Stormwind's flight tower the way to him vanished 60 yards
            -- before); docks keep REACH (their stops lie roughly).
            local reach=(to.kind=="goal" or to.kind=="flight") and N.ARRIVE or to.kind=="door" and N.DOOR or N.REACH
            -- At the walk's end, little of its way left.
            if near(to,reach) and at.left<=reach+N.DOOR then return self:Advance(i+1,string.format("within %d yd of the walk's end",reach)) end
            -- Only forward (Florian 2026-10-14: on a winding way of short
            -- pieces the nearest piece changed back and forth).
            if at.piece.j>(self.ahead or 0) then self.ahead=at.piece.j;self:Show() end
        end
        return
    end
    -- Off the way (no piece of the track near, Florian 2026-10-12: another
    -- way taken through Undercity; only the leg was searched again, back to
    -- its end at the bank, the rest of the old plan kept): the whole way
    -- planned anew from where you are, at most every AGAIN seconds. Your
    -- level is found as at any start (the street you stand on, your height).
    self.off=(self.off or 0)+1
    if self.off<N.OFFLOOKS or GetTime()<(self.again or 0) then return end
    self.off,self.again=0,GetTime()+N.AGAIN
    local goal=self.goal
    note("off the way: planning the whole way anew from here")
    Routing:Print("Off the way: planning anew from where you are.")
    self:Stop(true)
    self.fromHere=true
    self:Start(goal,true)
end

-- Flight masters you know: learned at every flight map. Through Blizzard's
-- flight map itself (no event kept open for the whole session; Core's
-- checks count open subscriptions); where the client has none, from the
-- first way you ask for on.
function N:Learn()
    if self.learning then return end
    self.learning=true
    local frame=rawget(_G,"TaxiFrame")
    if type(frame)=="table" and frame.HookScript then
        frame:HookScript("OnShow",function() N:TaxiOpened() end)
    else
        ns.Events:Subscribe(N,"TAXIMAP_OPENED",function() N:TaxiOpened() end)
    end
end
if type(rawget(_G,"TaxiFrame"))=="table" then N:Learn() end

-- After login (prepareAtLogin, Florian 2026-10-20): the precomputed network of both
-- continents with its shared walks and your map data made in the background, quietly
-- and in slices, PREPAREDELAY seconds after login. Once a session.
N.PREPAREDELAY=5
function N:Prepare()
    if self.prepared or not Routing:Config().prepareAtLogin then return end
    self.prepared=true;self.prepareState="running"
    local T=Routing.Transit
    if not (T and Routing.Grid and Routing.Grid.Run) then return end
    local conts={}
    for _,c in ipairs({1414,1415}) do if T:Usable(c) then conts[c]=true end end
    Routing.Grid.Run(function()
        local began=GetTime()
        local n=N:SeedTransit({},conts)
        Routing:Data()
        N.preparedIn=GetTime()-began
        return n
    end,function(n) N.preparedWalks=n;N.prepareState=string.format("done in %.1f s",N.preparedIn or 0) end,false)
end
-- After login, as Core itself: the subscription goes when it fired (Core's checks count
-- open subscriptions and timers); a one-shot timer where the client has one.
local function prepareLater()
    local after=C_Timer and C_Timer.After
    if after then after(N.PREPAREDELAY,function() N:Prepare() end) end
end
if IsLoggedIn and IsLoggedIn() then prepareLater()
elseif ns.Events then
    local stop
    stop=ns.Events:Subscribe(N,"PLAYER_LOGIN",function()
        if stop then stop();stop=nil end
        prepareLater()
    end)
end

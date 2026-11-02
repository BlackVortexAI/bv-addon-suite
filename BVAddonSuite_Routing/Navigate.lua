local _,Routing=...
if not Routing.ready then return end
-- Leading you somewhere (Florian 2026-10-10; Gather's navigation prototype,
-- docs/handoffs/2026-10-10-encyclopedia-and-routing-prototype.md, made
-- Routing's own): /bv route <what> | way | <x> <y> | stop.
-- Two levels: a small travel graph (you, the goal, the flight masters you
-- know, zeppelin and ship stops, the Deeprun Tram, transitions between
-- levels) picks walking, flying, a transport or a transition by estimated
-- seconds; only the walking legs are measured, on the navmesh (Routing.Hpa).
-- The way shows as lines
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
N.LIFTEND=5       -- yards to a lift's other station, apart on the map, that count as ridden up (Claude 2026-10-25)
N.UNSURE=8        -- yards: streets of two levels this close in distance to you
                  -- leave your level open (the plan starts on either)
N.OTHERSTART=900  -- seconds a start on another level than the one Routing
                  -- knows costs (only when no way leads on from that one)
N.STARTWEIGHT=3   -- unknown level: a level's street farther than the nearest
                  -- costs this many times its extra walk
N.BUDGET=14       -- ms a frame while searching (the grid's own 8 for routes)
N.ZTIE=2          -- yards: goal levels fitting about as well are told apart by the nearest street
N.REPLAN=10       -- plans tried with the walked lengths found (then the best searched through)
N.VIAROUND=4      -- from this round on no walk through a place where nothing is taken
N.HPAREPLAN=1.25  -- the navmesh planner plans again when its way measured takes this much longer than reckoned,
N.HPAREPLANS=0    -- at most this many times (off, Claude 2026-10-26: measured warm +38-130 % in navtest, e.g. Dun Morogh
                  -- to Helbrek 277 -> 641 ms, the way the same; it only changed Taurajo -> Freewind, open with Florian)
N.SPUR=12         -- yards: a walk going back along the one before it this near is cut there
N.WAYEND=15       -- yards: a goal on a level this near the last point of its way ends there
N.SNAPYARDS=16    -- yards a blocked goal looks round for the nearest street of its level (as the grid's search moved it)
N.NOWAY=1e7       -- yards a leg without a walkable way counts (never chosen
                  -- while any other way exists)
N.CONTINENTS={1414,1415,2665}
-- Capitals: Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity (the navmesh build's ground,
-- tools/hpa, paints their streets from walked ways and painted streets).
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
local function mapSize(cont)
    local s=sizes[cont]
    if not s then
        local w,h=call("C_Map.GetMapWorldSize",cont)
        s={type(w)=="number" and w or 0,type(h)=="number" and h or 0};sizes[cont]=s
    end
    return s
end
function N.Yards(cont,x1,y1,x2,y2)
    local s=mapSize(cont)
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
    if link.kind=="lift" or link.recorded then return out end
    -- Drawn by clicks: its corners rounded (a ramp round a tower).
    return Routing.Geo.Round(out,function(ax,ay,bx,by) return N.Yards(cont,ax,ay,bx,by) end)
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
    -- (Its own spacing: a town's edge every 24 yards, Road Studio; its level and the
    -- ground meet anywhere along it, and 20 towns at 6 yards were 4000 doors.)
    local step=math.max(N.EDGESTEP,tonumber(link.edgeStep) or N.EDGESTEP)
    local out={}
    local carry=step/2
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
                at=at+step
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
-- A town level kept from before still yours at a start: not when your height
-- denies it (Florian 2026-10-20: kept "The Crossroads" from the ways before,
-- up the tower ramp the first way went from the town's ground through the air;
-- planned anew 2 s later from the ramp). Other levels as before.
-- Nor once you are out of its bounds (Florian 2026-10-20: out of the town the
-- level stayed and the way started "off the streets", drawn straight).
function N.KeptFits(here,cont,px,py)
    if here==nil or not Routing.Level then return true end
    local lv,mapID=Routing.Level:Find(here)
    local b=type(lv)=="table" and lv.bounds
    if type(b)=="table" then
        local mx,my=Routing.Geo.Convert(cont,mapID,px,py)
        if type(mx)=="number" and type(my)=="number" and (mx<b[1] or mx>b[3] or my<b[2] or my>b[4]) then return false end
    end
    -- A remembered navmesh level is local, even when it has no rectangular
    -- bounds. After a teleport an empty subzone cue used to retain a distant
    -- shop floor and project its height onto a bridge beside the player.
    -- Use the same labelled footprint/reach as ordinary start candidates.
    local near,labels=N.LevelsNear(cont,px,py,N.GOALREACH)
    if labels and labels.ok and type(labels.refs)=="table" then
        local ref
        for i,v in ipairs(labels.refs) do if v[1]==mapID and v[2]==here then ref=i;break end end
        if ref then
            local found=false
            for _,v in ipairs(near) do if v[1]==ref then found=true;break end end
            if not found then return false end
        end
    end
    if not Routing.Height then return true end
    return Routing.Height:FitsLevel(here,cont,px,py)~=false
end
-- Unsure on which of a town's level ways you stand (a ramp round a tower lies
-- over its own foot on the map; up on the tower the NPCs in sight stand high
-- and low, your height tells nothing): the way starts on the highest of them.
-- A leap only goes down (Florian 2026-10-20): led from above while you are
-- lower, you are taken onto your piece as you walk; led from below while you
-- are up, the way went straight down through the air ("Go down to The
-- Crossroads" next to Darsok). starts {{level, cost}}, open {level ids}.
function N.TopTownStart(starts,open)
    local top,topMid
    for _,id in ipairs(open) do
        local mid=id and N.IsTownLevel(id) and N.LevelMid(id)
        if mid and (not topMid or mid>topMid) then top,topMid=id,mid end
    end
    if not top then return starts,open end
    local lower=function(id) local mid=id and N.IsTownLevel(id) and N.LevelMid(id);return mid and mid<topMid end
    local s2,o2={},{}
    for _,st in ipairs(starts) do if not lower(st.level) then s2[#s2+1]=st end end
    for _,id in ipairs(open) do if not lower(id) then o2[#o2+1]=id end end
    return s2,o2
end
-- The town (its ground level's id) a door belongs to: its network doors and the doors
-- along its edge; nil for every other door.
function N.DoorTown(door)
    local a,b,link=door[1],door[2],door[3]
    if type(link)~="table" then return nil end
    if link.town then return (a.level or b.level) end
    if door.edge then
        for _,id in ipairs({link.a and link.a.level,link.b and link.b.level}) do
            local lv=id and Routing.Level and Routing.Level:Find(id)
            if type(lv)=="table" and lv.townGround then return id end
        end
    end
    return nil
end
-- The towns ({[ground level id]=true}) whose bounds (and TOWNNEAR yards round them)
-- hold the start or a goal.
N.TOWNNEAR=60
function N.TownsAt(start,goals)
    local out={}
    for mapID,levels in pairs(Routing:Data().levels or {}) do
        for _,lv in ipairs(type(levels)=="table" and levels or {}) do
            local b=type(lv)=="table" and lv.townGround and lv.bounds
            if b then
                local w,h=call("C_Map.GetMapWorldSize",mapID)
                local mx,my=(type(w)=="number" and w>0) and N.TOWNNEAR/w or .01,(type(h)=="number" and h>0) and N.TOWNNEAR/h or .01
                for _,p in ipairs({start,unpack(goals or {})}) do
                    local x,y
                    if p and p.cont then x,y=Routing.Geo.Convert(p.cont,mapID,p.x,p.y) end
                    if x and y and x>=b[1]-mx and x<=b[3]+mx and y>=b[2]-my and y<=b[4]+my then out[lv.id]=true;break end
                end
            end
        end
    end
    return out
end
-- Whether a continent has a town's ground level (Road Studio) on it.
function N.HasTowns(cont)
    for mapID,levels in pairs(Routing:Data().levels or {}) do
        for _,lv in ipairs(type(levels)=="table" and levels or {}) do
            local b=type(lv)=="table" and lv.townGround and lv.bounds
            if b and Routing:OnContinent(mapID,(b[1]+b[3])/2,(b[2]+b[4])/2)==cont then return true end
        end
    end
    return false
end
function N:Doors()
    Routing:Data()
    local cache=self.doorsCache
    local v=Routing.dataVersion
    if cache and cache.v==v then return cache.list end
    local out={}
    for _,link in ipairs(Routing:ReadLinks()) do
        if type(link)=="table" and type(link.a)=="table" and type(link.b)=="table" and (link.a.level or 0)~=(link.b.level or 0) and type(link.edge)=="table" then
            local name=link.name or "Edge"
            local tlv=Routing.Level and Routing.Level:Find(link.a.level)
            local zb=type(tlv)=="table" and tlv.townGround and type(tlv.zband)=="table" and tlv.zband
            for _,c in ipairs(N.EdgeCrossings(link)) do
                -- (A town's edge: some 200 crossings; given back now and then, Florian 2026-10-20: 74-112 ms at once after a reload.)
                N.Breathe()
                local ca,ax,ay=Routing:OnContinent(link.a.mapID,c[1],c[2])
                local cb,bx,by=Routing:OnContinent(link.b.mapID,c[3],c[4])
                -- (Not where the town's edge runs outside its height band: Freewind's canyon.)
                local h=zb and ca and N.GroundHeight(ca,ax,ay)
                if ca and cb and not (h and (h<zb[1] or h>zb[2])) then
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
    self.doorsCache={v=v,list=out}
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
-- The six capitals (Geo's lists of both sides).
function N.IsCapital(mapID)
    local G=Routing.Geo
    for _,list in ipairs({G.HORDECAPITALS,G.ALLIANCECAPITALS}) do
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
-- Gives the frame back when the slice is used up (Scheduler.Breathe), in a coroutine.
function N.Breathe() Routing.Scheduler.Breathe() end
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
function N:Plan(goal,known,from,many)
    local schedules,planAt
    if Routing.Timetable then schedules,planAt=Routing.Timetable:Snapshot() end
    local cont,px,py,level
    if from then cont,px,py,level=from.cont,from.x,from.y,from.level else cont,px,py,level=self:Here() end
    if not cont then return nil,"No position here (instance?)." end
    -- Yield throughout preparation, including warm doors whose lengths are cached.
    local function preparePace(i) if i%64==0 then N.Breathe() end end
    N.Breathe()
    local mine=N.Faction()
    local speed=self:Speed()
    local goalNode={cont=goal.cont,x=goal.x,y=goal.y,level=goal.level,kind="goal",name=goal.name}
    local goalNodes,left
    if many then
        goalNodes={goalNode}
        for i=2,#many do local g=many[i];goalNodes[i]={cont=g.cont,x=g.x,y=g.y,level=g.level,kind="goal",name=g.name} end
        left=#goalNodes
    end
    -- (your height from the way you followed here, N:HeightOnWay: while you still stand there, for this plan's rounds)
    local hz=not from and self.hereZ
    if hz and not (hz.cont==cont and N.Yards(cont,hz.x,hz.y,px,py)<=2 and GetTime()-(hz.t or 0)<=N.HEREZTIME) then hz=nil end
    hz=hz and hz.z
    -- A measured player height is also an explicit start height. An old
    -- labelled floor must not override it (the Sanctum interior lies below
    -- the labelled Mage Quarter). Hypothetical EstimateMany starts keep
    -- their own level; wide or missing measurements remain unknown.
    if not from and hz==nil and Routing.Height and Routing.Hpa then
        local m=Routing.Height:Now()
        local span,lo,hi=Routing.Height.Span(m and m.set)
        if span and span<=Routing.Hpa.ZSPAN then hz=(lo+hi)/2 end
    end
    local nodes={{cont=cont,x=px,y=py,level=level,kind="start",name="you",z=hz},goalNode}
    -- Your level open: a start on each level it may be, at a cost
    -- (startLevels: {{level (false: the ground), cost (seconds)}}).
    local starts={nodes[1]}
    if self.startLevels and not from then
        starts={}
        for i,st in ipairs(self.startLevels) do
            local node={cont=cont,x=px,y=py,level=st.level or nil,kind="start",name="you",cost=st.cost or 0,z=hz}
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
        N.Breathe()
        if shares(f.mask,mine) and ((conts[f.cont] and flights[f.name]) or (not conts[f.cont] and countAll)) then nodes[#nodes+1]={cont=f.cont,x=f.x,y=f.y,kind="flight",name=f.name,level=self:FlightLevel(f)} end
    end
    N.Breathe()
    for _,t in ipairs(Routing.TRANSPORTS or {}) do
        N.Breathe()
        if shares(t.faction,mine) then
            -- The tram's stations lie in its cities' streets (Florian
            -- 2026-10-15: never taken, its stops counted as the ground):
            -- the level of the street nearest them.
            local tram=t.kind=="tram"
            -- The ship's model origin waits over water. Walk to its verified
            -- dry boarding surface instead, keeping the deck's own height.
            local function dock(stop,boarding)
                return {cont=stop[1],x=boarding and boarding[1] or stop[2],y=boarding and boarding[2] or stop[3],
                    z=boarding and boarding[3] or nil,kind="dock",name=stop[4],level=tram and self:StopLevel(stop) or nil}
            end
            local a=dock(t.a,t.boardingA)
            local b=dock(t.b,t.boardingB)
            a.transportSide="a";b.transportSide="b"
            a.pairs={{b,t.seconds*N.WAIT,t}};b.pairs={{a,t.seconds*N.WAIT,t}}
            nodes[#nodes+1]=a;nodes[#nodes+1]=b
        end
    end
    -- A town's doors (its edge, its network nodes) only for a way that starts or ends in
    -- it (Claude 2026-10-20: with 20 towns every far way tried shortcuts through towns
    -- off its line, 2.8 times the search time, two ways no longer found).
    local inTown=N.TownsAt(nodes[1],goalNodes or {goalNode})
    N.Breathe()
    for i,door in ipairs(self:Doors()) do
      preparePace(i)
      local a,b,link=door[1],door[2],door[3]
      local town=N.DoorTown(door)
      if (not town or inTown[town]) and not (N.hpaPlan and (N.HpaFlat(door) or N.HpaLift(door))) then
        -- Its length is the door's own (kept with it).
        if not door.yards then
            -- (Once a data state, all of them: 342 ms at once in the game,
            -- Florian 2026-10-14; given back now and then.)
            if coroutine.running() then Routing.Scheduler.Pace(200) end
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
    end
    -- The same plan as walking every pair of nodes, found faster (Florian/
    -- Codex 2026-10-14: 180-400 ms a round, ten rounds a way): each node's
    -- key made once; walking only among the nodes of its continent and
    -- level (flight masters among all of their continent); the next node
    -- from a heap by its time, ties to the node first in the list as
    -- before; walked lengths looked up by key pairs. In a coroutine it
    -- gives the frame back now and then (Scheduler.Pace).
    N.Breathe()
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
    -- With the navmesh planner a town's or city's level is walked on the same graph as the ground (Claude
    -- 2026-10-25, Florian in Thunder Bluff: the plan went to the gate at the cliff, then back along a painted level
    -- on the same plain): those levels count as the ground for walking, their transitions stay a way among others;
    -- where a level really lies apart (the mesa, a lift's top) its walks find no way and the lift is taken.
    local merged={}
    local function walkLevel(n)
        local lv=n.level
        if not lv then return 0 end
        if not N.hpaPlan then return lv end
        local m=merged[lv]
        if m==nil then m=Routing.Hpa.TownLevel(lv) and Routing.Hpa:Has(n.cont) or false;merged[lv]=m end
        return m and 0 or lv
    end
    local level0=function(n) return tostring(walkLevel(n)) end
    local byCont,byLevel={},{}
    local Breathe=Routing.Scheduler.Breathe
    for i,n in ipairs(nodes) do
        if i%500==0 then Breathe() end
        n.idx,n.k=i,key(n)
        if n.kind~="start" then
            local c=byCont[n.cont];if not c then c={};byCont[n.cont]=c end;c[#c+1]=n
            local lk=n.cont..":"..level0(n)
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
    -- With the navmesh planner (Claude 2026-10-25, Jordan Stilwell to Menethil's inn): a guessed walk on the ground
    -- never brings you to a place sooner than the walk measured from your start to it, when the way there went on the
    -- ground only (walks and transitions between ground places). Without this, guessed walks from a door end beside
    -- the start (87 yd) to the town's crossings (the line, 1145 yd, against 7000 yd measured round the mountains) won
    -- every round, and the measured way through the gate never came up. hpaFloor[node]: the start it was reached from.
    local hpaFloor=N.hpaPlan and walkedBy and {} or nil
    local function try(v,cost,u,kind,by)
        if not dist[v] or cost<dist[v] then
            dist[v],prev[v],via[v],what[v]=cost,u,kind,by;push(cost,v)
            if hpaFloor then hpaFloor[v]=(not v.level and v.cont==u.cont and (kind=="walk" or kind=="transition") and hpaFloor[u]) or nil end
        end
    end
    for _,node in ipairs(starts) do
        dist[node]=node.cost or 0
        if hpaFloor and not node.level then hpaFloor[node]=node end
    end
    for _,node in ipairs(nodes) do if dist[node] then push(dist[node],node) end end
    while size>0 do
        local best,u=pop()
        if not done[u] and dist[u]==best then
            if goalNodes then
                -- Several goals: done when all are reached (walking on
                -- through one is never shorter, so no time changes by it).
                if u.kind=="goal" then left=left-1;if left<=0 then break end end
            elseif u==goalNode or u.anyGoal then reached=u;break end
            done[u]=true
            local list=u.kind=="flight" and byCont[u.cont] or byLevel[u.cont..":"..level0(u)] or EMPTY
            local walked=walkedBy and walkedBy[u.k]
            local level=walkLevel(u)
            local factor=level~=0 and 1 or N.DETOUR
            for j,b in ipairs(list) do
                if j%8==0 then Breathe() end
                if b~=u then
                    -- Walking only on one level.
                    if walkLevel(b)==level then
                        -- Not walked yet: the line times DETOUR; on a level (city
                        -- streets) the line alone, never more than the way (Florian
                        -- 2026-10-11: the nearer stairs looked worse on paper than the
                        -- way measured to the farther ones and were never tried).
                        local w=walked and walked[b.k]
                        local estimate=factor
                        local line=not w and N.Yards(u.cont,u.x,u.y,b.x,b.y)
                        -- Walked through a place where nothing is taken (a door end, a city waypoint) while the walk
                        -- from where it came to b is already measured: never shorter than that walk, only a way
                        -- round its measured length (Claude 2026-10-24, Ironforge navmesh: 21 walks, ten rounds
                        -- through one door end after another on the same street, 4.4 s to Harick). Only from round
                        -- VIAROUND on: a long walk searched in two pieces can come out shorter than in one, and the
                        -- first rounds keep that chance (measured: 24 cases 39 % less work, one way 12 of 655 yd longer).
                        if (N.viaRound or 0)>=N.VIAROUND and w==nil and (level~=0 or u.kind=="door") and via[u]=="walk" and prev[u] and walkedBy then
                            local pw=walkedBy[prev[u].k]
                            local direct=pw and pw[b.k]
                            if direct and direct<N.NOWAY then w=false end
                        end
                        if w~=false then
                            local t=best+(w or line*estimate)/speed
                            local s0=w==nil and level==0 and hpaFloor and hpaFloor[u]
                            local sb=s0 and walkedBy[s0.k] and walkedBy[s0.k][b.k]
                            if sb and sb<N.NOWAY then t=math.max(t,(s0.cost or 0)+sb/speed) end
                            -- (No way on the ground from the start: none through a place reached on the ground either.)
                            if not (sb and sb>=N.NOWAY) then try(b,t,u,"walk") end
                        end
                    end
                    if u.kind=="flight" and b.kind=="flight" then try(b,best+self:FlightSeconds(u,b),u,"flight") end
                end
            end
            for _,p in ipairs(u.pairs or EMPTY) do
                local cost=p[2]
                if u.kind=="dock" and Routing.Timetable then
                    cost=Routing.Timetable:Quote(p[3],u.transportSide,planAt+best,schedules).seconds
                end
                try(p[1],best+cost,u,u.kind=="dock" and "transport" or "transition",p[3])
            end
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
    if Routing.Timetable then
        for _,step in ipairs(steps) do
            if step.kind=="transport" then step.schedule=Routing.Timetable:Quote(step.by,step.from.transportSide,planAt+dist[step.from],schedules) end
        end
    end
    -- A transition walked in Route Studio (a ramp round a tower): its shape,
    -- in the direction taken.
    for _,step in ipairs(steps) do
        if step.kind=="transition" and type(step.by)=="table" then
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

-- A leg's outcome (Codex/Florian 2026-10-16): "ok", "nopath" (proven: no
-- walkable way), "limit" (not found within the search's limit: it may
-- exist), "unknown" (the data cannot tell). Only "nopath" says "no way".
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
-- doors: {from = the door's height where the leg starts at a door's ground end, to = at its end}.
function N:Walk(cont,level,x1,y1,x2,y2,doors)
    -- The navmesh planner (Hpa.lua; Claude 2026-10-25): a walk on the ground of a
    -- continent it has data for is measured on its abstract graph only, no space, no terrain asked; the walks of
    -- the final way are refined once (N:Start).
    local Hpa=Routing.Hpa
    -- A town's levels too (Claude 2026-10-25, Florian: towns over the navmesh; Hpa.TownLevel).
    if Hpa and N.hpaPlan and (not level or Hpa.TownLevel(level)) and Hpa:Active(cont) then return Hpa:Walk(cont,x1,y1,x2,y2,doors,level) end
    -- (no navmesh data there, or a level without heights: no walk - the grid that searched it is gone, Florian 2026-10-26)
    return {{x1,y1},{x2,y2}},"no navmesh data here",false,"nodata"
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
-- With the navmesh planner (Claude 2026-10-25): the heights of a walk's ends, each its own: a door's floor, a
-- town's or city's level at that point (Hpa.LevelZ); the goal's is the NPC's (Hpa.Z), nil here.
function N.HpaEnds(s,t)
    local Hpa=Routing.Hpa
    local function z(n)
        if n.kind=="goal" then return nil end
        if (n.kind=="start" or n.kind=="dock") and type(n.z)=="number" then return n.z end
        if n.kind=="door" and type(n.link)=="table" and tonumber(n.link.doorZ) then return tonumber(n.link.doorZ) end
        if n.level and Hpa.TownLevel(n.level) then return Hpa.LevelZ(n.level,n.cont,n.x,n.y) end
    end
    return {from=z(s),to=z(t)}
end
-- A transition the navmesh planner leaves out (Claude 2026-10-25, Florian: "transitions in the middle of nowhere,
-- like stairs", a town's edge, a painted level's gate on the same plain): both its ends on the ground or on a
-- level walked on the navmesh, of one continent, not a lift or teleport, and the graph walks from one end to the
-- other nearby (a town's edge always). Then it is no step of the way: the walks before and after are one, the level
-- changes by itself. Bridges the navmesh lacks (Thunder Bluff's) and lifts stay.
function N.HpaFlat(door)
    -- (kept with the door: the door list itself is kept per data state, N:Doors)
    local v=door.hpaFlat
    if v==nil then
        local final
        v,final=N.HpaFlatOf(door)
        -- (only a final answer: one that needed another continent's data current is asked again there)
        if v or final or Routing.Hpa.cont==(door[1] and door[1].cont) or door.edge then door.hpaFlat=v end
    end
    return v
end
-- A lift the navmesh planner's graph rides itself (Claude 2026-10-26, Florian: lifts are the quick, usual way; one
-- search weighs them against the walk round): a data lift in the continent's navmesh data (Hpa.LiftIds) is no door
-- of the plan; the walk across it is split at the lift afterwards (N.SplitLifts).
function N.HpaLift(door)
    local Hpa=Routing.Hpa
    local a,link=door[1],door[3]
    if not (Hpa and Hpa.LiftIds and type(link)=="table" and link.kind=="lift" and a and type(link.id)=="string") then return false end
    if not Hpa:Has(a.cont) then return false end
    return Hpa.LiftIds(a.cont)[link.id]==true
end
function N.HpaFlatOf(door)
    local Hpa=Routing.Hpa
    local a,b,link=door[1],door[2],door[3]
    if not (a and b and a.cont==b.cont) then return false end
    for _,e in ipairs({a,b}) do
        if e.level and not Hpa.TownLevel(e.level) then return false end
    end
    if not Hpa:Has(a.cont) then return false end
    if door.edge then return true end
    if type(link)~="table" or link.kind=="lift" or link.kind=="teleport" or link.kind=="transport" then return false end
    local za=a.level and Hpa.LevelZ(a.level,a.cont,a.x,a.y) or tonumber(link.doorZ)
    local zb=b.level and Hpa.LevelZ(b.level,b.cont,b.x,b.y) or tonumber(link.doorZ)
    -- (precomputed for the shipped transitions, tools/hpa/flat.py: a final answer on any continent)
    local known=Hpa.JoinedKnown and Hpa.JoinedKnown(a.cont,Hpa.JoinedKey(a.cont,a.x,a.y,za,b.x,b.y,zb))
    if known~=nil then return known,true end
    -- (checked on the continent in use only: making another's data current for one door costs a whole switch)
    if Hpa.cont~=a.cont then return false end
    return Hpa:Joined(a.cont,a.x,a.y,za,b.x,b.y,zb)
end
-- A walk the navmesh planner's graph led across a lift (its path's points marked lift: the jump ridden to there from
-- the point before) is split there: walk to the lift's station, take the lift (a transition step: its wait, its
-- arrival at the other end, Navigate's guidance as for any lift), walk on (Claude 2026-10-26). A data lift is its
-- link (its levels and seconds); a ride from Florian's recordings a link of its own, named after the lift beside it.
N.navLifts={}
function N.LiftLink(cont,lift)
    if type(lift)~="table" then return nil end
    local data=Routing:Data()
    if lift.id and lift.id~="" then
        local byId=N.navLifts.byId
        if not byId or N.navLifts.data~=data then
            byId={}
            for _,link in ipairs(data.links or {}) do if type(link)=="table" and link.id then byId[link.id]=link end end
            N.navLifts={data=data,byId=byId,made={}}
        end
        if byId[lift.id] then return byId[lift.id] end
    end
    local made=N.navLifts.made or {}
    N.navLifts.made=made
    local k=cont..":"..tostring(lift.name)..":"..tostring(lift.a and lift.a[1])
    if not made[k] then
        -- (a teleport the build baked as a lift, Stormwind's Wizard's Sanctum: its kind kept - "Use the teleport", tracked as
        -- a ride; Claude 2026-10-27)
        made[k]={kind=lift.kind=="teleport" and "teleport" or "lift",name=lift.name or "Lift",seconds=(lift.seconds and lift.seconds>0) and lift.seconds or Routing.Hpa.LIFTSECONDS,
            id="navmesh-lift-"..k,recorded=lift.recorded or nil,navmesh=true}
    end
    return made[k]
end
-- A walk that comes back to within LOOP yards of a point it passed (out to a node beyond the goal and back to its NPC,
-- a cell's middle beside a precomputed walk's end) goes on from there: the excursion between is cut (Claude 2026-10-26:
-- Florian's walks in Brill and the walk simulation in Gadgetzan; the tracker never saw you walk such a spur and either
-- stayed before it or leapt past the goal). Only within LOOPBACK yards along, the new piece at most LOOP yards long, and
-- only a spur that comes back the way it went (every point of its way back within SPURWIDTH yards of its way out): a
-- ramp winding up over its own foot or a round loop is no spur and stays. Returns whether it cut.
N.LOOP=3
N.LOOPZXY=1.5     -- yards across: points this close lie over each other (a spiral's turns), N.CutLoops
N.LOOPZ=3         -- yards: a way back to a point passed this much higher or lower is a climb, no spur
N.LOOPBACK=80
N.SPURWIDTH=3
local function toSegment(cont,p,a,b)
    local dx,dy=b[1]-a[1],b[2]-a[2]
    local len=dx*dx+dy*dy
    local t=len>0 and math.max(0,math.min(1,((p[1]-a[1])*dx+(p[2]-a[2])*dy)/len)) or 0
    return N.Yards(cont,p[1],p[2],a[1]+dx*t,a[2]+dy*t)
end
local function spur(cont,path,along,k,i)
    local half=(along[k]+along[i])/2
    local m=k
    while m<i and along[m+1]<=half do m=m+1 end
    for q=m+1,i-1 do
        local near=false
        for s=k,m do
            if toSegment(cont,path[q],path[s],path[math.min(s+1,m+1)])<=N.SPURWIDTH then near=true;break end
        end
        if not near then return false end
    end
    return true
end
function N.CutLoops(cont,path)
    local cut=false
    local along={0}
    local i=2
    while i<=#path do
        along[i]=along[i-1]+N.Yards(cont,path[i-1][1],path[i-1][2],path[i][1],path[i][2])
        local back
        for k=i-2,1,-1 do
            if along[i]-along[k]>N.LOOPBACK then break end
            -- A funnel corner is required by the polygon corridor. A thin
            -- obstacle can look like a spur in 2D; do not delete its way round.
            if path[k+1].corner then break end
            -- (never across a climb on the spot drawn on the polygons, Hpa's points marked stack: a spiral ramp's upper
            -- turn lies over its lower one and looked like the way back; Claude 2026-10-28, Orgrimmar, Doras)
            -- (unless both ends of the cut lie at one height - your start and an NPC beside you, the way drawn down a
            -- stair and back: Brooke Stonebraid in Stormwind, 0 yd away, 34 yd; the ends' heights from Hpa:Refine)
            local zk0,zi0=path[k].z or path[k].endz,path[i].z or path[i].endz
            if (path[k].stack or path[i].stack) and not (zk0 and zi0 and math.abs(zk0-zi0)<=N.LOOPZ) then break end
            -- (nor where the way comes back over itself on another height, the points' z where Hpa knows it: a ramp
            -- winding up round a tower, the Wizard's Sanctum's, came back to the same cells' middles one turn up and
            -- was cut to a line through the tower; Claude 2026-10-28, Florian)
            -- (only right over each other, LOOPZXY yd: a spur on a steep slope comes back past neighbouring cells'
            -- middles some yards higher or lower, and was kept - gather ways 0.3-0.6 % longer; Claude 2026-10-28)
            local zk,zi=path[k].z,path[i].z
            if zk and zi and math.abs(zk-zi)>N.LOOPZ and N.Yards(cont,path[k][1],path[k][2],path[i][1],path[i][2])<=N.LOOPZXY then
            elseif N.Yards(cont,path[k][1],path[k][2],path[i][1],path[i][2])<=N.LOOP and along[i]-along[k]>2*N.LOOP and spur(cont,path,along,k,i) then back=k end
        end
        if back then
            for _=back+1,i-1 do table.remove(path,back+1) end
            i=back+1
            along[i]=along[back]+N.Yards(cont,path[back][1],path[back][2],path[i][1],path[i][2])
            for k=i+1,#along do along[k]=nil end
            cut=true
        end
        i=i+1
    end
    return cut
end
N.LIFTCELL=6
function N.SplitLifts(steps)
    local Hpa=Routing.Hpa
    if not (Hpa and Hpa.JumpLiftOf) then return steps end
    local out={}
    for _,step in ipairs(steps) do
        local path=step.kind=="walk" and type(step.path)=="table" and step.path
        local cut
        if path then for k=2,#path do if type(path[k])=="table" and path[k].lift then cut=true;break end end end
        if not cut then
            out[#out+1]=step
        else
            local cont=step.from.cont
            local from,piece=step.from,{path[1]}
            local function walkTo(to)
                if #piece>=2 then
                    local w={from=from,to=to,kind="walk",path=piece,yards=length(cont,piece),navmesh=step.navmesh,status=step.status,note=step.note}
                    out[#out+1]=w
                end
            end
            for k=2,#path do
                local p=path[k]
                local lift=type(p)=="table" and p.lift and Hpa.JumpLiftOf(p.lift)
                if lift then
                    local link=N.LiftLink(cont,lift)
                    local a,b=path[k-1],p
                    -- The stations where the lift's data has them (a data lift: its link's ends; a ride: where the
                    -- recording got on and off), the walks drawn to and from them; the nearer one is where you get on.
                    -- (At the graph's cell middles the stations of Undercity's lift lay 4 yd closer together, under
                    -- N.SPOT: the tracker took it for a lift on one spot and lost you below; walk simulation, Brill.)
                    local sa,sb=lift.a,lift.b
                    -- (the jump's way: from the lift's a to its b, or back - its road byte, tools/hpa/hierarchy.py; older
                    -- data without it: the nearer station)
                    local _,_,back=Hpa.JumpRank(p.lift)
                    local flip
                    if back~=nil then flip=back>=.5
                    else
                        flip=type(sa)=="table" and type(sb)=="table" and
                            N.Yards(cont,a[1],a[2],sa[1],sa[2])+N.Yards(cont,b[1],b[2],sb[1],sb[2])>N.Yards(cont,a[1],a[2],sb[1],sb[2])+N.Yards(cont,b[1],b[2],sa[1],sa[2])
                    end
                    -- (up or down by the floors' heights; Florian 2026-10-26: "Ground -> Ground" told nothing)
                    local za,zb=tonumber(lift.za),tonumber(lift.zb)
                    if flip then za,zb=zb,za end
                    local dir=(za and zb and math.abs(zb-za)>=2) and (zb>za and "up" or "down") or nil
                    if flip then sa,sb=sb,sa end
                    local ax,ay=(type(sa)=="table" and sa[1] or a[1]),(type(sa)=="table" and sa[2] or a[2])
                    local bx,by=(type(sb)=="table" and sb[1] or b[1]),(type(sb)=="table" and sb[2] or b[2])
                    -- (a data lift's levels with its ends: its link's a is the data's a)
                    local la,lb
                    if type(link.a)=="table" and type(link.b)=="table" and not link.navmesh then
                        if flip then la,lb=link.b,link.a else la,lb=link.a,link.b end
                        -- (the link's levels by where its ends lie: the one nearer where you get on is where you get on
                        -- - a lift from a recorded ride may run the other way round from the data's link; Florian
                        -- 2026-10-27, Freewind north: "take the lift up (Freewind Post paths -> Ground)")
                        local ca,xa,ya=Routing:OnContinent(link.a.mapID,link.a.x,link.a.y)
                        local cb,xb,yb=Routing:OnContinent(link.b.mapID,link.b.x,link.b.y)
                        if ca==cont and cb==cont then
                            if N.Yards(cont,ax,ay,xa,ya)+N.Yards(cont,bx,by,xb,yb)<=N.Yards(cont,ax,ay,xb,yb)+N.Yards(cont,bx,by,xa,ya) then
                                la,lb=link.a,link.b
                            else
                                la,lb=link.b,link.a
                            end
                        end
                    end
                    local na={cont=cont,x=ax,y=ay,level=la and la.level or nil,kind="door",name=link.name or "Lift",link=link,side=flip and "b" or "a"}
                    local nb={cont=cont,x=bx,y=by,level=lb and lb.level or nil,kind="door",name=link.name or "Lift",link=link,side=flip and "a" or "b"}
                    -- (the floors' heights where known: the cabin's foot and exit lie on one spot)
                    na.z,nb.z=za,zb
                    -- (the lift's ends on the graph are its cells' middles: within LIFTCELL yards of its station the station
                    -- itself, exact; the middle beside it made the walk go out and back - Undercity's Lift 2, Claude 2026-10-26)
                    if #piece>=2 and N.Yards(cont,piece[#piece][1],piece[#piece][2],ax,ay)<=N.LIFTCELL then piece[#piece]=nil end
                    if N.Yards(cont,piece[#piece][1],piece[#piece][2],ax,ay)>.1 then piece[#piece+1]={ax,ay} end
                    walkTo(na)
                    -- (a recorded ride: its way drawn on the maps, from where you got on to where you got off; Florian
                    -- 2026-10-27, Freewind and the Great Lift; drawing only - the tracker and the guide take the step as
                    -- a lift)
                    local shape
                    if type(lift.pts)=="table" and #lift.pts>=6 then
                        shape={}
                        for q=1,#lift.pts-1,2 do shape[#shape+1]={lift.pts[q],lift.pts[q+1]} end
                        if flip then local r={};for q=#shape,1,-1 do r[#r+1]=shape[q] end;shape=r end
                    end
                    out[#out+1]={from=na,to=nb,kind="transition",by=link,cost=Hpa.LiftSeconds(p.lift)*N.WAIT,dir=dir,shape=shape}
                    from,piece=nb,{{bx,by}}
                    if N.Yards(cont,bx,by,b[1],b[2])>N.LIFTCELL then piece[#piece+1]={b[1],b[2]} end
                else
                    piece[#piece+1]=p
                end
            end
            walkTo(step.to)
            -- (the way's goal end kept with the last piece: an NPC marked apart)
            if out[#out] and out[#out].kind=="walk" then out[#out].to=step.to end
        end
    end
    -- the reports numbered again
    for i,step in ipairs(out) do
        if step.kind=="walk" and not step.report then
            step.report=string.format("%d. walk %d yd to %s, %d points; %s",i,step.yards or 0,step.to.name,#step.path,tostring(step.note or "navmesh"))
        elseif step.kind=="transition" and not step.report then
            step.report=string.format("%d. %s%s: %s (%s -> %s)",i,(N.VERB[step.by.kind] or "Pass"):lower(),step.dir and " "..step.dir or "",step.from.name,
                Routing.Level:Name(step.from.level),Routing.Level:Name(step.to.level))
        elseif step.report then
            step.report=step.report:gsub("^%d+%.",i..".",1)
        end
    end
    return out
end
-- The yards a walk's lifts stand for (their wait and ride at your speed, Hpa.LiftYards), beside the yards walked.
function N.LiftYards(path)
    local Hpa=Routing.Hpa
    local extra=0
    if Hpa and Hpa.LiftYards and type(path)=="table" then
        for _,p in ipairs(path) do if type(p)=="table" and p.lift then extra=extra+Hpa.LiftYards(p.lift) end end
    end
    return extra
end
local function leg(legs,step)
    local k=key(step.from)..">"..key(step.to)
    if not legs[k] then
        N.searched=(N.searched or 0)+1
        local t0=GetTime()
        -- Each walk said as it is searched (Florian 2026-10-17: a search ran
        -- for minutes and the log told nothing about which walk).
        Routing:Note(string.format("  searching walk %d: %s -> %s, %d yd in a line...",N.searched,tostring(step.from.name),tostring(step.to.name),
            N.Yards(step.from.cont,step.from.x,step.from.y,step.to.x,step.to.y)))
        local function walk()
            local s,t=step.from,step.to
            -- The heights of its ends: a door's floor, a town's level (N.HpaEnds).
            local doors
            if not s.level or Routing.Hpa.TownLevel(s.level) then doors=N.HpaEnds(s,t) end
            return N:Walk(s.cont,s.level,s.x,s.y,t.x,t.y,doors)
        end
        local path,note,ok,status=walk()
        legs[k]={path=path,yards=length(step.from.cont,path)+N.LiftYards(path),note=note,seconds=GetTime()-t0,ok=ok,status=status or (ok and "ok" or "unknown")}
        Routing:Note(string.format("  walk %d: %s, %.1f s",N.searched,ok and "found" or tostring(status or "no way"),GetTime()-t0))
    end
    return legs[k],k
end
N.Leg=leg
-- With the navmesh planner, a walk on the ground to a crossing of a town's edge: the walks to all crossings of that
-- edge measured at once (Hpa:WalkMany, one search) and kept as searched (Claude 2026-10-25, Florian: from before
-- Menethil's gate, and from Jordan Stilwell, the way to the inn went round to a harbour crossing; the plan measured
-- the crossings one at a time, nearest by the line first, and the gate was never measured). Returns how many walks
-- it added.
local function edgeWalks(legs,known,step)
    local Hpa=Routing.Hpa
    local s,t=step.from,step.to
    if not (Hpa and N.hpaPlan) or s.level or t.level or t.kind~="door" or type(t.link)~="table" or type(t.link.edge)~="table" then return 0 end
    if not Hpa:Active(s.cont) or legs[key(s)..">"..key(t)] then return 0 end
    local ends,keys={},{}
    for _,door in ipairs(N:Doors({[s.cont]=true})) do
        if door.edge and door[3]==t.link then
            for k=1,2 do
                local e=door[k]
                if e and not e.level and e.cont==s.cont then
                    local kk=key(s)..">"..key(e)
                    if not legs[kk] then
                        ends[#ends+1]={e.x,e.y,type(e.link)=="table" and tonumber(e.link.doorZ) or nil}
                        keys[#keys+1]=kk
                    end
                end
            end
        end
    end
    if #ends<2 then return 0 end
    local t0=GetTime()
    local z1=s.kind=="door" and type(s.link)=="table" and tonumber(s.link.doorZ) or Hpa.Z(s.x,s.y)
    local paths,none=Hpa:WalkMany(s.cont,s.x,s.y,z1,ends)
    local added,nowhere=0,0
    for i,yards in pairs(paths) do
        N.Breathe()
        -- (only its length is kept: the walk taken is refined anew at the end, Hpa:Refine; 44 paths of cells
        -- were 6 MB kept with the legs, Claude 2026-10-25 /bv route memory)
        legs[keys[i]]={path={{s.x,s.y},{ends[i][1],ends[i][2]}},yards=yards,note=Hpa.ABSTRACT,seconds=0,ok=true,status="ok"}
        known[keys[i]]=legs[keys[i]].yards
        added=added+1
    end
    -- (No way for sure: known as none, never guessed again.)
    for i in pairs(none) do
        legs[keys[i]]={path={{s.x,s.y},{ends[i][1],ends[i][2]}},yards=0,note="navmesh: no way on the ground",seconds=0,ok=false,status="nopath"}
        known[keys[i]]=N.NOWAY
        nowhere=nowhere+1
    end
    Routing:Note(string.format("  walks to the %d crossings of %s measured at once: %d found, %d without a way, %.1f s",#ends,tostring(t.name),added,nowhere,GetTime()-t0))
    return added+nowhere
end
N.EdgeWalks=edgeWalks

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
-- The shipped maps' painted streets, on the navmesh (Claude 2026-10-27, Phase 4 of the grid's removal; Florian: the
-- levels found on the navmesh, the painted polygons out of Maps.lua): the cells labelled with their levels
-- (Data/NavLevels_<cont>.lua, tools/hpa/levels.py) within reach of a continent point, each with its distance (yards to
-- the cell), the nearest point of the cell and the height of the layer that carries it:
-- {{ref (into the data's refs: {mapID, level id or false}), d, x, y, z}}. Only for the Nav data it was made for.
N.LEVELREC=8
function N.LevelsNear(cont,x,y,reach)
    local all,nav=rawget(_G,"BVRoutingNavLevels"),rawget(_G,"BVRoutingNav")
    local L,d=type(all)=="table" and all[cont],type(nav)=="table" and nav[cont]
    if not (type(L)=="table" and type(d)=="table" and type(L.rec)=="string" and L.version==2 and Routing.Hpa) then return {},L end
    if L.bound~=d then L.bound,L.ok=d,Routing.Hpa.NavStamp(d)==L.navStamp end
    if not L.ok then return {},L end
    local floor,byte=math.floor,string.byte
    local rec,size,g,cell,cols=L.rec,N.LEVELREC,d.geo,d.cell,d.cols
    local n=#rec/size
    local function cellAt(i) local a,b,c=byte(rec,i*size+1,i*size+3);return a+b*256+c*65536 end
    local px,py=(x-g.minX)*g.width,(y-g.minY)*g.height
    local cx,cy=floor(px/cell),floor(py/cell)
    local r=math.ceil(reach/cell)+1
    local out={}
    for yy=cy-r,cy+r do
        local lo,hi=yy*cols+cx-r,yy*cols+cx+r
        -- the first record of the row's run: by halving
        local a,b=0,n
        while a<b do local m=floor((a+b)/2);if cellAt(m)<lo then a=m+1 else b=m end end
        local i=a
        while i<n do
            local c=cellAt(i)
            if c>hi then break end
            local ccx,ccy=c%cols,floor(c/cols)
            local o=i*size
            local r1,r2,z1,z2,quarters=byte(rec,o+4,o+8)
            -- The quarters of the cell the street covers (half a cell each): the nearest, no nearer than its square nor
            -- than its middle less half a quarter, and within reach only with its middle (a street at the far edge of
            -- reach is not taken from a quarter that only reaches into it).
            local best,bx,by
            for q=0,3 do
                if floor(quarters/2^q)%2==1 then
                    local h=cell/2
                    local x0,y0=ccx*cell+(q%2)*h,ccy*cell+floor(q/2)*h
                    -- (the point a hair inside the quarter: on its edge it lay in the next cell, the cell's own layer
                    -- not found there - Clavicus Knavingham's goal in Stormwind, Claude 2026-10-27)
                    local qx=math.max(x0+.05,math.min(x0+h-.05,px))
                    local qy=math.max(y0+.05,math.min(y0+h-.05,py))
                    local centre=math.sqrt((x0+h/2-px)^2+(y0+h/2-py)^2)
                    local dist=math.max(math.sqrt((qx-px)^2+(qy-py)^2),centre-h/2)
                    if not best or dist<best then best,bx,by=dist,qx,qy end
                end
            end
            if best and best<=reach then
                local z=z1+z2*256;if z>=32768 then z=z-65536 end
                out[#out+1]={r1+r2*256,best,g.minX+bx/g.width,g.minY+by/g.height,z/2}
            end
            i=i+1
        end
    end
    return out,L
end
function N:Candidates(cont,x,y,reach)
    reach=reach or N.GOALREACH
    local Geo=Routing.Geo
    local db=Routing:Data()
    local best={}
    local onMap
    local near,labels=N.LevelsNear(cont,x,y,reach)
    for mapID,levels in pairs(db.levels) do
        if type(levels)=="table" and #levels>0 and type(mapID)=="number" then
            local mx,my=Geo.Convert(cont,mapID,x,y)
            if mx and mx>=0 and mx<=1 and my>=0 and my<=1 then
                onMap=onMap or mapID
                local w,h=call("C_Map.GetMapWorldSize",mapID)
                if type(w)~="number" or w<=0 then w,h=1000,1000 end
                -- (z: the height of the navmesh layer a labelled cell's level lies on, N.LevelsNear)
                local function consider(level,px,py,d,z)
                    local k=level or false
                    local known=best[k]
                    -- (A better point of a level kept in its entry: no table per point.)
                    if d<=reach and known and d<known.d then known.d,known.map,known.x,known.y,known.z=d,mapID,px,py,z
                    elseif d<=reach and not known then best[k]={level=k,d=d,map=mapID,x=px,y=py,z=z} end
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
                            if type(a.poly)=="table" then inside=Geo.Inside(a.poly,px,py)
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
                -- as far as the search moved it (N.SNAPYARDS); a
                -- level masked over a wide area does not.
                consider=function(level,px,py,d)
                    local known=best[level or false]
                    if not (d<=reach and (not known or d<known.d)) then return end
                    if free(level,px,py) then plain(level,px,py,d);return end
                    local snap=N.SNAPYARDS
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
                -- A town's ground level (open, its bounds, Road Studio): the whole town, also
                -- where nothing is painted (Florian 2026-10-20, Crossroads: its houses' walls).
                for _,lv in ipairs(levels) do
                    local b=type(lv)=="table" and lv.open==true and lv.townGround and lv.bounds
                    if b and mx>=b[1] and mx<=b[3] and my>=b[2] and my<=b[4] then
                        -- (Not below or above its height band: Freewind Post's canyon is not the town.)
                        local zb,h=type(lv.zband)=="table" and lv.zband,nil
                        if zb then h=N.GroundHeight(cont,x,y) end
                        if not (h and (h<zb[1] or h>zb[2])) then plain(lv.id,mx,my,0) end
                    end
                end
                -- The shipped painted streets: the navmesh's labelled cells (N.LevelsNear).
                for _,e in ipairs(near) do
                    local ref=labels.refs[e[1]]
                    if ref and ref[1]==mapID then
                        local qx,qy=Geo.Convert(cont,mapID,e[3],e[4])
                        if qx then plain(ref[2],qx,qy,e[2],e[5]) end
                    end
                end
                -- Areas whose box lies farther than reach are left out (your own painting, and a town's of Data/Towns).
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
                        if Geo.Inside(q,mx,my) then consider(st.level,mx,my,0)
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
N.TOWNFIT=2       -- the same for a town level (Road Studio bounds): its heights are walked
N.TOWNDOOR=1      -- seconds between a town's ground level and the ground at a network node in it
N.TOWNGROUNDSTART=5 -- seconds a start on the ground under a town's level costs more than on the level
-- The ground height at a continent point (Claude 2026-10-27, Phase 3 of the grid's removal: the terrain data left the
-- addon): the heights of its ADT tile baked in (Data/NavGround_<cont>.lua, tools/hpa/ground.py: the terrain data's own
-- grids, unchanged), bilinear between the cell middles as before; nil where there are none (no fallback). The world
-- position from Core's frame of the continent (X north, Y west).
N.GROUNDKEEP=64   -- tiles' heights kept decoded
N.groundTiles,N.groundOrder={},{}
function N.GroundTile(d,instance,col,row)
    local key=instance*10000+col*100+row
    local grid=N.groundTiles[key]
    if grid~=nil then return grid end
    local text=d.heights and d.heights[col*100+row]
    if type(text)~="string" then return false end
    local delta=d.deltaValues
    if not delta then
        delta={}
        for i=1,#d.delta do delta[d.delta:sub(i,i)]=i-32 end
        d.deltaValues=delta
    end
    local colon=text:find(":",1,true)
    local value=tonumber(text:sub(1,colon-1)) or 0
    grid={value}
    local i=colon+1
    while i<=#text do
        local char=text:sub(i,i)
        if char=="!" then
            local stop=text:find(";",i+1,true)
            value=value+(tonumber(text:sub(i+1,stop-1)) or 0);i=stop+1
        else value=value+(delta[char] or 0);i=i+1 end
        grid[#grid+1]=value
    end
    N.groundTiles[key]=grid
    local order=N.groundOrder
    order[#order+1]=key
    if #order>N.GROUNDKEEP then N.groundTiles[table.remove(order,1)]=nil end
    return grid
end
function N.GroundHeight(cont,x,y)
    local T=ns.MapTerrain
    local f=T and T:Frame(cont)
    local all=rawget(_G,"BVRoutingNavGround")
    local d=f and type(all)=="table" and all[f.instance]
    if type(d)~="table" then return nil end
    local X,Y=f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx
    local n=d.heightCells or 32
    local fc,fr=32-Y/T.ADT,32-X/T.ADT
    local col,row=math.floor(fc),math.floor(fr)
    local grid=N.GroundTile(d,f.instance,col,row)
    if not grid then return nil end
    local gx=math.max(0,math.min(n-1,(fc-col)*n-.5))
    local gy=math.max(0,math.min(n-1,(fr-row)*n-.5))
    local x0,y0=math.floor(gx),math.floor(gy)
    local x1,y1=math.min(n-1,x0+1),math.min(n-1,y0+1)
    local tx,ty=gx-x0,gy-y0
    local function at(cx,cy) return grid[cy*n+cx+1] or 0 end
    return (at(x0,y0)*(1-tx)+at(x1,y0)*tx)*(1-ty)+(at(x0,y1)*(1-tx)+at(x1,y1)*tx)*ty
end
-- A town's NPCs know their level (Florian 2026-10-21: "this NPC needs this way, follow it, do not
-- guess"): Data/Towns.lua (export_levels.py) lists per continent every Map Data NPC in a town
-- with the level it stands on: {[cont]={levels={ids},rows={x,y,z,li,px,py,...}}}, li 0 the
-- ground, -1 a level no way leads to yet (guessed as before), else levels[li] (a level way of
-- the town's network or the town's ground; a list: the levels whose ways pass it there, parts
-- of one winding way or two ways crossing, the nearest street of them taken), px,py the point
-- on its way nearest. Goals carry no
-- NPC id (Codex hands over Map Data's spawn, cont/x/y/z/name): an NPC is known by its spawn,
-- NPCAT yards and NPCZ in height (Codex's goal lies on it exactly).
N.NPCAT=1
N.NPCZ=3
N.NPCSTART=5      -- yards: a start this near known NPCs (all of one level) starts on their level
N.npcIndex={}
function N.TownNPCs(cont,x,y,reach)
    local data=Routing.TOWNNPCS and Routing.TOWNNPCS[cont]
    if type(data)~="table" or type(data.rows)~="table" then return {} end
    local B=.002
    local idx=N.npcIndex[cont]
    if not idx or idx.rows~=data.rows then
        idx={rows=data.rows,cells={}}
        local r=data.rows
        for i=1,#r-5,6 do
            local k=math.floor(r[i]/B)..":"..math.floor(r[i+1]/B)
            idx.cells[k]=idx.cells[k] or {};table.insert(idx.cells[k],i)
        end
        N.npcIndex[cont]=idx
    end
    local out={}
    local cx,cy=math.floor(x/B),math.floor(y/B)
    local r=data.rows
    for dx=-1,1 do
        for dy=-1,1 do
            for _,i in ipairs(idx.cells[(cx+dx)..":"..(cy+dy)] or {}) do
                local d=N.Yards(cont,x,y,r[i],r[i+1])
                if d<=reach then
                    local li=r[i+3]
                    local level=nil
                    if li==0 then level=false elseif li>0 then level=data.levels[li] end
                    out[#out+1]={d=d,x=r[i],y=r[i+1],z=r[i+2],level=level,none=li<0,px=r[i+4],py=r[i+5]}
                end
            end
        end
    end
    table.sort(out,function(a,b) return a.d<b.d end)
    return out
end
-- Its levels that exist ({ids}; a stale list: none).
local function existing(level)
    local out={}
    for _,id in ipairs(type(level)=="table" and level or {level}) do
        if Routing.Level and Routing.Level:Find(id) then out[#out+1]=id end
    end
    return out
end
-- The known NPC a goal is (nil: a free point, or one without a level known): {level (false:
-- the ground, or the id), levels (the ids), px, py}; its levels must exist (a stale list guesses
-- as before).
-- Only with the goal's height: a map click has none (Map's Path.lua: cont/x/y only) and never
-- chooses a floor (Florian 2026-10-21), also right on an NPC's spot; Codex hands Map Data's z.
function N.TownNPC(goal)
    if not (goal and goal.cont and goal.x and goal.y) then return nil end
    local z=tonumber(goal.z)
    if not z then return nil end
    for _,row in ipairs(N.TownNPCs(goal.cont,goal.x,goal.y,N.NPCAT)) do
        if math.abs(row.z-z)<=N.NPCZ then
            if row.none then return nil end
            if row.level==false then return row end
            local ids=existing(row.level)
            if #ids==0 then return nil end
            row.levels,row.level=ids,ids[1]
            return row
        end
    end
    return nil
end
-- Where you start beside known NPCs (Florian 2026-10-21: from the NPC in the cellar up to the one
-- upstairs, the way stays in the house): all NPCs within NPCSTART of one level (and your height,
-- if known, not against it) -> that level (false: the ground); otherwise nil. In the game Routing
-- has your position, not your height; standing at an NPC you talked to is the common case
-- (a tour from stop to stop).
-- (Several levels at their spot: the list {ids}, the start tries those.) Right on a spawn (NPCAT,
-- the offline planner starts a case there) that NPC's; NPCs of other floors within NPCSTART (one
-- over another in a house): those your height denies (Height, NPCs in range) left out.
function N.StartNPC(cont,x,y)
    local rows=N.TownNPCs(cont,x,y,N.NPCSTART)
    local function of(row)
        if row.none then return nil end
        -- On the ground: found as its goal is (Codex 2026-10-21: start and goal alike), a walked way there or the ground.
        if row.level==false then return N:GoalLevel({cont=cont,x=row.x,y=row.y,z=row.z}) or false end
        local ids=existing(row.level)
        if #ids==0 then return nil end
        return #ids==1 and ids[1] or ids
    end
    -- First the ones your height denies left out (Codex 2026-10-21: two NPCs on one spot, one
    -- floor over the other), then: right on a spawn the nearest (equally near: by level, the same
    -- every time), else all of one level.
    local H=Routing.Height
    local kept={}
    for _,row in ipairs(rows) do
        local this=of(row)
        if this==nil then return nil end
        local denied=H and type(this)~="table" and H:FitsLevel(this or nil,cont,x,y)==false
        if not denied then kept[#kept+1]={d=row.d,level=this,key=type(this)=="table" and table.concat(this,"|") or tostring(this)} end
    end
    if #kept==0 then return nil end
    table.sort(kept,function(a,b) if a.d~=b.d then return a.d<b.d end return a.key<b.key end)
    if kept[1].d<=N.NPCAT then
        -- (every one as near: any of another level and it is not chosen; Codex 2026-10-21: A, A, B)
        for i=2,#kept do if kept[i].d<=kept[1].d+1e-6 and kept[i].key~=kept[1].key then return nil end end
        return kept[1].level
    end
    for _,k in ipairs(kept) do if k.key~=kept[1].key then return nil end end
    return kept[1].level
end
-- A level a goal takes only by a walked height right at it (Codex's SpanAt rule, 2026-10-21,
-- 3,078 replays: bounds, a level of ways, its heights listed, not a town's ground; Freewind's
-- plateau of ways has no bounds and keeps its whole span).
function N.LocalOnly(id)
    if id==nil or id==false or not Routing.Level then return false end
    local lv=Routing.Level:Find(id)
    return type(lv)=="table" and lv.bounds~=nil and lv.waysOnly==true and type(lv.heights)=="table" and #lv.heights>=4 and not lv.townGround
end
-- How far a height z is from a town level way's walked heights right at (cont, x, y): its
-- samples within TOWNSAMPLE yards (export_levels: one each 2 yards of the way); nil: none there
-- (then it does not fit: no whole span, Codex's SpanAt rule).
N.TOWNSAMPLE=14  -- (Level.SAMPLE; Codex 2026-10-21: 4 yards lost Brill's Rupert Boch)
N.L3GroundExit={["town-1443-shadowprey-village-upper-layer-tower"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true},["town-1443-shadowprey-village-upper-layer-tower-2"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true},["town-1451-cenarion-hold-upper-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true},["town-1451-cenarion-hold-ramp-tower-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true},["town-1420-brill-basement-building"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true,[97]=true,[101]=true,[105]=true,[109]=true,[113]=true,[117]=true,[121]=true},["town-1420-brill-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true},["town-1424-southshore-keller"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true,[97]=true,[101]=true,[105]=true,[109]=true,[113]=true,[117]=true,[121]=true,[125]=true,[129]=true,[133]=true,[137]=true,[141]=true,[145]=true},["town-1424-southshore-building-first-layer-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true,[97]=true,[101]=true,[105]=true,[109]=true},["town-1440-astranaar-platform-over-the-lake"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true},["town-1444-feathermoon-stronghold-platform"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true,[97]=true,[101]=true,[105]=true,[109]=true,[113]=true,[117]=true,[121]=true,[125]=true,[129]=true,[133]=true,[137]=true,[141]=true,[145]=true,[149]=true,[153]=true,[157]=true,[161]=true},["town-1413-crossroads-tower-ramp-1"]={[1]=true,[5]=true,[9]=true,[13]=true},["town-1425-revantusk-village-tower-top-layer"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true},["town-1425-revantusk-village-top-of-the-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true,[97]=true},["town-1425-first-layer-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true},["town-1425-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true},["town-1425-basement-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true},["town-1429-goldshire-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true},["town-1433-lakeshire-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true},["town-1433-lakeshire-first-layer-building-1-2"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true},["town-1437-menethil-harbor-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true},["town-1437-menethil-harbor-first-layer-building-1-2"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true},["town-1437-menethil-harbor-first-layer-castle-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true,[93]=true,[97]=true,[101]=true,[105]=true,[109]=true,[113]=true,[117]=true,[121]=true,[125]=true,[129]=true,[133]=true,[137]=true,[141]=true,[145]=true,[149]=true,[153]=true,[157]=true,[161]=true,[165]=true,[169]=true,[173]=true,[177]=true,[181]=true},["town-1438-dolanaar-inn-upper-layer"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true},["town-1431-darkshire-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true},["town-1435-stonard-first-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true},["town-1435-stonard-first-layer-building-1-2"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true},["town-1439-auberdine-platform-over-the-lake"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true,[85]=true,[89]=true},["town-1439-auberdine-upper-layer-building-1"]={[1]=true,[5]=true,[9]=true,[13]=true,[17]=true,[21]=true,[25]=true,[29]=true,[33]=true,[37]=true,[41]=true,[45]=true,[49]=true,[53]=true,[57]=true,[61]=true,[65]=true,[69]=true,[73]=true,[77]=true,[81]=true}}
-- Isolated L3 proposal. A local sample is a floor, not the union of nearby stair heights.
N.TOWNFIT=3
function N.TownLocalOff(id,z,cont,x,y)
    local lv,mapID=Routing.Level:Find(id)
    local list=type(lv)=="table" and lv.heights
    if type(list)~="table" or #list<4 or not mapID or type(z)~="number" then return nil end
    local mx,my=Routing.Geo.Convert(cont,mapID,x,y)
    if type(mx)~="number" then return nil end
    local w,h=call("C_Map.GetMapWorldSize",mapID)
    if type(w)~="number" or w<=0 then return nil end
    local nearest=N.TOWNSAMPLE
    local found=false
    for i=1,#list-3,4 do
        local dx,dy=(list[i]-mx)*w,(list[i+1]-my)*h
        local d=math.sqrt(dx*dx+dy*dy)
        if d<=nearest then nearest=d;found=true end
    end
    if not found then return nil end
    local exits=N.L3GroundExit and N.L3GroundExit[id]
    local ground=exits and N.GroundHeight(cont,x,y)
    local best
    for i=1,#list-3,4 do
        local dx,dy=(list[i]-mx)*w,(list[i+1]-my)*h
        local d=math.sqrt(dx*dx+dy*dy)
        -- One yard tolerates sampling phase; never fills the vertical gap between floors.
        if d<=nearest+1 and d<=N.TOWNSAMPLE then
            local lo,hi=list[i+2],list[i+3]
            local exit=exits and exits[i] and ground and math.abs(z-ground)<=3
            if not exit and type(lo)=="number" and type(hi)=="number" then
                local off=z<lo and lo-z or z>hi and z-hi or 0
                if not best or off<best then best=off end
            end
        end
    end
    return best
end

-- The towns with a list of their NPCs (Data/Towns.lua TOWNNPCS[cont].towns: {x0,y0,x1,y1,...}, the
-- town's box and LEVELREACH round it, continent 0..1): there the stricter goal rules below hold;
-- everywhere else the goal's level is found as shipped (GoalLevelProduct), so towns go out one
-- by one (Codex/Florian 2026-10-21: Wildhammer without its list lost five NPCs).
function N.StrictAt(cont,x,y)
    local data=Routing.TOWNNPCS and Routing.TOWNNPCS[cont]
    local t=type(data)=="table" and data.towns
    if type(t)~="table" then return false end
    for i=1,#t-3,4 do
        if x>=t[i] and x<=t[i+2] and y>=t[i+1] and y<=t[i+3] then return true end
    end
    return false
end
-- As shipped (Navigate.lua b9039c99, frozen by Codex 2026-10-21), for goals outside towns with an NPC list.
-- Of two levels about as fitting: the one whose street the goal is nearer; within LABELTIE yards of each other (the
-- navmesh's labelled cells, 8 yards) the one whose navmesh layer there lies nearer the goal's height (Claude
-- 2026-10-27, Phase 4: Undercity's Algernon on two levels painted over each other, the cell holds both).
N.LABELTIE=4
function N.Nearer(a,b,z)
    if z and a.z and b.z and math.abs(a.d-b.d)<=N.LABELTIE then return math.abs(a.z-z)<math.abs(b.z-z) end
    return a.d<b.d
end
function N:GoalLevelProduct(goal)
    -- Keep the shipped fit outside strict towns; local recorded-floor tolerance is separate.
    local townFit=2
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
                -- A town's level (its own bounds, heights as walked in Road Studio) fits only
                -- TOWNFIT yards off (Florian 2026-10-20: Devrak on the ground at the foot of the
                -- Crossroads tower ramp, 6 yards below it, was led onto the ramp).
                local lv=Routing.Level:Find(cand.level)
                if off and type(lv)=="table" and lv.bounds and off>townFit then off=nil end
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
                if off and off<=N.ZFIT and off<=bestDz+N.ZTIE and N.Nearer(cand,fitting,z) then fitting=cand end
            end
            -- A town's ground is near every point of the town (0 yards): a level way of the
            -- town (Road Studio, walked) that fits as well wins (Florian 2026-10-20: Innkeeper
            -- Sikewa on the town's ground, not on the walked way up to her).
            local flv=Routing.Level:Find(fitting.level)
            if type(flv)=="table" and flv.townGround then
                local way
                for _,cand in ipairs(cands) do
                    local off=offs[cand]
                    if off and off<=N.ZFIT and off<=bestDz+N.ZTIE and N.IsTownLevel(cand.level) and cand.d<=N.ARRIVE and (not way or cand.d<way.d) then way=cand end
                end
                if way then fitting=way end
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
    if best.d>N.ARRIVE*.8 then cx,cy=Routing.Geo.Convert(best.map,goal.cont,best.x,best.y) end
    return best.level,cx,cy,nil,unmapped
end

function N:GoalLevel(goal)
    -- A separately qualified entrance floor does not rewrite MapData's trigger height.
    -- Only the exact entrance identity is bound; map pins and unrelated floors stay untouched.
    if goal.label=="entrance" then
        for _,list in pairs(Routing:Data().levels or {}) do
            for _,lv in ipairs(list) do
                local b=lv.entranceBinding;local q=b and b.requested
                if q and goal.cont==q.cont and goal.name==q.name and goal.z==q.z
                    and math.abs(goal.x-q.x)<1e-9 and math.abs(goal.y-q.y)<1e-9 then
                    goal.requested={cont=goal.cont,x=goal.x,y=goal.y,z=goal.z,label=goal.label,name=goal.name}
                    goal.arrival={cont=b.arrival.cont,x=b.arrival.x,y=b.arrival.y,z=b.arrival.z,level=lv.id,evidence=b.evidence}
                    return lv.id,b.arrival.x,b.arrival.y
                end
            end
        end
    end
    -- A known NPC: its level, not guessed.
    local npc=N.TownNPC(goal)
    -- On the ground (the list: 0): found as a point of its town with the strict rules below (a level way only
    -- by a walked height right there, Stonard's Innkeeper Karakul on the inn's walked way at its ground floor).
    if npc and npc.level==false then npc=nil end
    if npc and N.LocalOnly(npc.level) then
        local off=N.TownLocalOff(npc.level,tonumber(goal.z),goal.cont,goal.x,goal.y)
        if not off or off>N.TOWNFIT then npc=nil end
    end
    if npc then
        local level=npc.level
        if #npc.levels>1 then
            -- Of its levels the one whose street fits its height best, then the nearest (as below).
            local z=tonumber(goal.z)
            local inSet,best,bestOff={},nil,nil
            for _,id in ipairs(npc.levels) do inSet[id]=true end
            for _,cand in ipairs(self:Candidates(goal.cont,goal.x,goal.y,N.LEVELREACH)) do
                if cand.level and inSet[cand.level] then
                    local off=z and (N.LocalOnly(cand.level) and N.TownLocalOff(cand.level,z,goal.cont,goal.x,goal.y)
                        or not N.LocalOnly(cand.level) and Routing.Level:Off(cand.level,z,goal.cont,goal.x,goal.y)) or 99
                    if off and (not best or off<bestOff-N.ZTIE or (off<=bestOff+N.ZTIE and cand.d<best.d)) then best,bestOff=cand,math.min(off,bestOff or off) end
                end
            end
            if best then level=best.level end
        end
        local cx,cy
        if npc.px and N.Yards(goal.cont,goal.x,goal.y,npc.px,npc.py)>N.ARRIVE*.8 then cx,cy=npc.px,npc.py end
        return level,cx,cy,nil,nil
    end
    if not (goal.cont and goal.x and goal.y and N.StrictAt(goal.cont,goal.x,goal.y)) then return self:GoalLevelProduct(goal) end
    local cands=self:Candidates(goal.cont,goal.x,goal.y,N.LEVELREACH)
    -- Level ways from the geometry (origin ai) only for the NPCs they lead to (the list): their foot lies at the
    -- ground's height and took the NPCs beside it (Darkshire's Barkeep Hann, Dolanaar's Laurna, 2026-10-21).
    do
        local kept={map=cands.map}
        for _,c in ipairs(cands) do
            local lv=c.level and Routing.Level:Find(c.level)
            if not (type(lv)=="table" and lv.origin=="ai") then kept[#kept+1]=c end
        end
        cands=kept
    end
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
                local off
                -- A town's level way (its own bounds, heights as walked in Road Studio): only by a
                -- walked height right at the goal (TOWNSAMPLE), TOWNFIT yards off at most (Florian
                -- 2026-10-20: Devrak at the foot of the Crossroads tower ramp was led onto it;
                -- 2026-10-21: no level from afar, its whole span caught the ground's NPCs).
                if N.LocalOnly(cand.level) then off=N.TownLocalOff(cand.level,z,goal.cont,goal.x,goal.y)
                else off=Routing.Level:Off(cand.level,z,goal.cont,goal.x,goal.y) end
                local lv=Routing.Level:Find(cand.level)
                if off and type(lv)=="table" and lv.bounds and off>N.TOWNFIT then off=nil end
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
                if off and off<=N.ZFIT and off<=bestDz+N.ZTIE and N.Nearer(cand,fitting,z) then fitting=cand end
            end
            -- A town's ground is near every point of the town (0 yards): a level way of the
            -- town (Road Studio, walked) that fits as well wins (Florian 2026-10-20: Innkeeper
            -- Sikewa on the town's ground, not on the walked way up to her). Both fit locally:
            -- the way only by a walked height near (N.TownLocalOff); Codex 2026-10-21: catching
            -- came from the fallbacks only, this rule is needed (Auberdine's platform).
            local flv=Routing.Level:Find(fitting.level)
            if type(flv)=="table" and flv.townGround then
                local way
                for _,cand in ipairs(cands) do
                    local off=offs[cand]
                    if off and off<=N.ZFIT and off<=bestDz+N.ZTIE and N.IsTownLevel(cand.level) and cand.d<=N.ARRIVE and (not way or cand.d<way.d) then way=cand end
                end
                if way then fitting=way end
            end
        end
    end
    local best=fitting
    if not best and onTop then return nil,nil,nil,nil end
    -- A town's level way (Road Studio bounds) takes a goal only as fitting above (a height walked
    -- right there) or as a known NPC's (TownNPC); never by the following fallbacks (Florian
    -- 2026-10-21: a map click has no height, it cannot choose a floor: the ground or the town's
    -- ground; Codex 2026-10-21: without a sample there a goal under or over the ground was moved
    -- 30 yards onto it and not said). The shipped levels (cities, Freewind's plateau: no bounds)
    -- keep them: a goal in Undercity has no height either and lies on its levels.
    local free={}
    for _,cand in ipairs(cands) do if not N.LocalOnly(cand.level) then free[#free+1]=cand end end
    free.map=cands.map
    cands=free
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
    -- Under the ground and no level it may take (Codex 2026-10-21, Wildhammer without its NPC
    -- list: Nioma 90 yards down was led as on the ground): not mapped, said so; led to the ground
    -- above it (no level), not arrived there. (Not over the ground: piers, docks and platforms of
    -- objects stand over the terrain data, Booty Bay over the sea floor; 87 goals the ground led
    -- to would be said as not mapped.)
    if z and ground and not fitting and under and (not best or best.level==false) then
        return nil,nil,nil,nil,true
    end
    if not best or best.level==false then return nil,nil,nil,cands.map end
    -- Within reach of the street: the goal stays where it is; else the street.
    local cx,cy
    if best.d>N.ARRIVE*.8 then cx,cy=Routing.Geo.Convert(best.map,goal.cont,best.x,best.y) end
    return best.level,cx,cy,nil,unmapped
end
-- goal: a table from Goal, or what other packages hand in ({cont, x, y,
-- level, name, label}).
-- again: planned anew by Navigate itself (a level corrected), not by you.
function N:Start(goal,again)
    -- A new goal starts in Routing's mode; the same one searched again keeps
    -- the mode switched in the guide.
    if goal~=self.lastGoal then self.modeOverride=nil;self.enemyAllowed=nil;self.enemyPlan=nil;self.enemyPending=nil;self.quiet=nil end
    self.lastGoal=goal
    self:Learn()
    local findMs=self.findMs;self.findMs=nil
    if not again then self.corrections=0 end
    if self.busy then Routing:Print("Still calculating.");return false end
    -- A new way ends the old one at once (Codex 2026-10-14: a new start that
    -- failed left the old steps under the new goal's name).
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
    if self.steps then self:HeightOnWay();self:Stop(true) end
    -- Said in the guide while led (no flights where they are not known).
    local missing=self:FlightsMissing(goal)
    self.flightNote=#missing>0 and string.format("No flights on %s: open a flight master's map there once.",N.ContNames(missing)) or nil
    -- A goal in an enemy base (Codex marks it, goal.hostile): asked when the way is planned (N:EnemyGate).
    -- Everything from here in slices (Florian/Codex 2026-10-14: the goal's
    -- level, where you start and the first plan ran at once and froze the
    -- game): busy at once, the goal known; the outcome is said when the
    -- run ends.
    self.busy,self.goal=true,goal
    -- (a plan run again for the enemy question says in the log only what the first one said already)
    local function say(text) if N.quiet then Routing:Note(text) else Routing:Print(text) end end
    local Sch=Routing.Scheduler
    local budget=Sch.BUDGET;Sch.BUDGET=N.BUDGET;self.budget=budget
    local dropped={}
    local steps,seconds,startInfo,planMs,reused,replanned
    local began=GetTime()
    Sch.nextLabel="Finding the way"
    self.run=Sch.Run(function()
        -- A target may have appeared since the last periodic measurement.
        -- Refresh once for this plan, before any start-level decision.
        if Routing.Height then Routing.Height:Fresh() end
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
                say(string.format("%s stands where the map has no level (height %d): led to the nearest street (\"%s\"), the last stretch is yours.",
                    goal.name,math.floor(tonumber(goal.z) or 0),Routing.Level:Name(level)))
            elseif unmapped then
                goal.npcAt={x=goal.x,y=goal.y}
                goal.unmapped=true
                say(string.format("%s stands where the map has no level (height %d, the ground at %d): led to the ground there, the last stretch is yours.",
                    goal.name,math.floor(tonumber(goal.z) or 0),math.floor(N.GroundHeight(goal.cont,goal.x,goal.y) or 0)))
            elseif level then
                goal.level=level
                if x then goal.x,goal.y=x,y end
                say(string.format("%s is on the level \"%s\".",goal.name,Routing.Level:Name(level)))
            elseif map then
                local info=call("C_Map.GetMapInfo",map)
                say(string.format("%s lies on %s but near no street of its levels (%d yd): taken as the ground.",
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
        if known and not N.KeptFits(here,cont,px,py) then known=false end
        -- Beside known NPCs (Florian 2026-10-21, NPC to NPC in one house): their level, also over a level
        -- kept from before (Codex 2026-10-21: Agnar's cellar kept, the way started on the ground above).
        local npcSet,npcKnown
        if cont then
            local npcLevel=N.StartNPC(cont,px,py)
            if type(npcLevel)=="table" then
                -- Several levels at its spot: the kept one if it is among them, else the one whose street
                -- passes nearest (as for a goal).
                npcSet={}
                for _,id in ipairs(npcLevel) do npcSet[id]=true end
                local best
                if known and here and npcSet[here] then best={level=here} end
                if not best then
                    for _,cand in ipairs(self:Candidates(cont,px,py)) do if cand.level and npcSet[cand.level] and (not best or cand.d<best.d) then best=cand end end
                end
                if best then
                    here,known,npcKnown=best.level,true,true
                    Routing:Note("start on the level of the NPC beside you: "..Routing.Level:Name(best.level))
                end
            elseif npcLevel~=nil then
                -- (On the ground there and the town's ground kept: kept, the town's ground lies on the ground.)
                local klv=known and here and npcLevel==false and Routing.Level:Find(here)
                if not (type(klv)=="table" and klv.townGround) then here=npcLevel or nil end
                known,npcKnown=true,true
                Routing:Note("start on the level of the NPCs beside you: "..tostring(npcLevel and Routing.Level:Name(npcLevel) or "the ground"))
            end
        end
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
            -- Beside an NPC standing where several levels' ways pass: only those (the way decides).
            if npcSet then
                local kept={}
                for _,cand in ipairs(cands) do if cand.level and npcSet[cand.level] then kept[#kept+1]=cand end end
                if #kept>0 then cands=kept end
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
                -- (Known from the NPC you stand at: only there, Codex 2026-10-21: Agnar in the cellar to Fraggar
                -- started on the ground above, 13.3 s, not through the house.)
                for _,cand in ipairs(npcKnown and {} or cands) do
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
                starts,open=N.TopTownStart(starts,open)
            end
            -- In a town (its ground level): the ground under it too, a little dearer (Claude
            -- 2026-10-20, Gadgetzan to Ahn'Qiraj: from the town's level a far way had to leave
            -- by its edge first and was no longer found; for a way in the town its level wins).
            local townStart,groundStart=false,false
            for _,st in ipairs(starts) do
                local lv=st.level and Routing.Level:Find(st.level)
                if type(lv)=="table" and lv.townGround then townStart=true end
                if st.level==false then groundStart=true end
            end
            if townStart and not groundStart and not npcKnown then starts[#starts+1]={level=false,cost=N.TOWNGROUNDSTART} end
            -- A bounded town level rejected at this position must not leak back
            -- through Plan -> Here when no painted level is nearby. Bind the
            -- ground explicitly; retain ordinary ambiguity inside the bounds.
            if #starts==0 and not N.KeptFits(here,cont,px,py) then
                starts[1]={level=false,cost=0}
            end
            if #starts==1 and not known then
                self.startLevels=starts
                if starts[1].level~=false then
                    Routing.Level:Set(starts[1].level)
                    say("You are on the level \""..Routing.Level:Name(starts[1].level).."\" (the street you stand on).")
                end
            elseif #starts>1 or npcKnown then self.startLevels=starts end  -- (from an NPC: its level, not the one kept)
        end
        self.levelSet=nil
        local planBegan=debugprofilestop and debugprofilestop()
        local anyKnown
        -- The navmesh planner on where you are or where you go (Hpa.lua): its graph holds the precomputed walks
        -- and measures every walk on the ground exactly.
        local Hpa=Routing.Hpa
        N.hpaPlan=Hpa and (Hpa:Active(cont) or (goal.cont and Hpa:Active(goal.cont))) or nil
        -- Ways only on the navmesh (Florian 2026-10-26: no grid to fall back on, no straight line): where it has no
        -- data for where you stand, no way, said.
        if not N.hpaPlan then
            local why=Hpa and cont and Hpa:Missing(cont) or "no navmesh data"
            Routing:Print(string.format("No way: Routing finds ways only on its navmesh, and here it has none (%s).",tostring(why)))
            return nil
        end
        N.hpaReplanned=nil
        Hpa:Begin()
        steps,seconds,anyKnown=self:Plan(goal)
        planMs=planBegan and debugprofilestop()-planBegan
        if not steps then Routing:Print(seconds);return nil end
        -- Which start it was is known once the legs are searched (StartSaid).
        startInfo=self.startLevels and {known=known,here=here,open=open,likely=likely}

        self.goal,self.steps,self.current,self.ahead,self.track=goal,nil,1,nil,nil
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
        known,legs,replanned={},{},0
        self.legs=legs
        reused=0
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
        N.viaRound=0
        for _=1,N.REPLAN do
            local open=false
            -- Walks to a town's other crossings measured with this round's (navmesh planner): planned again.
            local fresh=0
            for _,step in ipairs(steps) do
                if step.kind=="walk" and not legs[key(step.from)..">"..key(step.to)] then
                    open=true
                    fresh=fresh+edgeWalks(legs,known,step)
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
                local hasTown,otherLevel=false,false
                for _,step in ipairs(steps) do
                    for _,node in ipairs({step.from,step.to}) do
                        if node.level then
                            local lv=Routing.Level:Find(node.level)
                            if lv and lv.townGround then hasTown=true else otherLevel=true end
                        end
                    end
                end
                -- With the navmesh planner every walk on the ground is measured on its abstract graph, a town's
                -- crossings all at once (edgeWalks): the first way searched through is taken, unless this round
                -- measured crossings the plan has not weighed yet (Claude 2026-10-25, Menethil's gate).
                -- (Not when the walks measured came out much longer than the plan reckoned, Claude 2026-10-26: Camp
                -- Taurajo to Freewind, the walk round by the line beat the Great Lift on paper and was 5.7 km measured;
                -- planned again with its real length.)
                local grew=seconds and t>seconds*N.HPAREPLAN and (N.hpaReplanned or 0)<N.HPAREPLANS
                if grew then N.hpaReplanned=(N.hpaReplanned or 0)+1 end
                if (fresh==0 and not grew) or (hasTown and not otherLevel) then steps,seconds=sure,sureSeconds;break end
            end
            -- First measure one alternative normally. A short useful detour
            -- must get its chance before the complete walk calibrates guesses.
            N.viaRound=_
            local again,total=N:Plan(goal,known)
            if again and searched(again) and (not sureSeconds or total<sureSeconds) then sure,sureSeconds=again,total end
            if again then
                local changed=#again~=#steps
                for i=1,math.min(#again,#steps) do if key(again[i].to)~=key(steps[i].to) or again[i].kind~=steps[i].kind then changed=true end end
                if changed then replanned=replanned+1 end
                steps,seconds=again,total
            end
        end
        N.viaRound=nil
        if sure and not searched(steps) then steps,seconds=sure,sureSeconds end
        -- The time said from the walks' real yards (stored walks are weighed
        -- cheaper on roads, not shorter).
        if searched(steps) then seconds=measured(steps) end
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
                if a.from.cont==b.to.cont and (a.from.level or false)==(b.to.level or false) and la.ok and lb.ok then
                    direct=leg(legs,joined)
                    if not (direct.ok and direct.yards<la.yards+lb.yards) then direct=nil end
                    -- The time said: the yards saved at your speed (Codex 2026-10-14).
                    if direct and seconds then seconds=math.max(0,seconds-(la.yards+lb.yards-direct.yards)/N:Speed()) end
                end
                if not direct then
                    local path={}
                    local pa,pb=la.path,lb.path
                    local yards=la.yards+lb.yards
                    if la.ok and lb.ok then
                        pa,pb=N.Trim(a.from.cont,la.path,lb.path)
                        if pa~=la.path then
                            local cut=la.yards+lb.yards-length(a.from.cont,pa)-length(b.from.cont,pb)
                            if cut>0 then yards=yards-cut;if seconds then seconds=math.max(0,seconds-cut/N:Speed()) end end
                        end
                    end
                    for _,p in ipairs(pa) do path[#path+1]=p end
                    -- (Cut: the second walk goes on from where they part.)
                    for j=(pb==lb.path) and 2 or 1,#pb do path[#path+1]=pb[j] end
                    legs[k]={path=path,yards=yards,note=la.note,seconds=la.seconds+lb.seconds,ok=la.ok and lb.ok,
                        status=(la.ok and lb.ok) and "ok" or (not la.ok and la.status or lb.status)}
                end
                steps[i-1]=joined;table.remove(steps,i)
            end
        end
        for i,step in ipairs(steps) do
            if step.kind=="walk" then
                local found=leg(legs,step)
                -- The navmesh planner's walks on the ground: refined once, now that the way is chosen (Hpa.lua),
                -- on the cells and pulled tight.
                local Hpa=Routing.Hpa
                if Hpa and N.hpaPlan and found.ok and found.note==Hpa.ABSTRACT then
                    local s,t=step.from,step.to
                    local doors
                    if not s.level and (s.kind=="door" or t.kind=="door") then
                        doors={from=s.kind=="door" and type(s.link)=="table" and tonumber(s.link.doorZ) or nil,
                            to=t.kind=="door" and type(t.link)=="table" and tonumber(t.link.doorZ) or nil}
                    end
                    doors=N.HpaEnds(s,t)
                    local path,why=Hpa:Refine(s.cont,s.x,s.y,t.x,t.y,doors,s.level)
                    if not path then
                        Routing:Print("No way to "..goal.name..": "..(why=="start floor is disconnected"
                            and "no walkable connection from your current position. Move onto a connected path and try again."
                            or why=="target floor is disconnected"
                            and "no walkable connection to the target floor." or "the walking path could not be refined."))
                        return nil
                    end
                    found.path,found.yards,found.note=path,length(s.cont,path),"navmesh (refined)"
                    -- (done only by the way left, as on a town's level; Claude 2026-10-25,
                    -- Florian in Ironforge: one walk now from Mekkatorque to Harick, and at the foot of the outer
                    -- stair, Harick a few yards away on the map one floor up, the way said "arrived")
                    step.navmesh=true
                end
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
                step.note=found.note
            elseif step.kind=="flight" then
                local secs,learned=N:FlightSeconds(step.from,step.to)
                step.report=string.format("%d. fly %s -> %s, %s%s",i,step.from.name,step.to.name,N.Clock(secs),learned and " (learned)" or " (estimate)")
            elseif step.kind=="transport" then
                local q=step.schedule
                step.report=string.format("%d. %s: %s -> %s, %s (%s)",i,step.by.kind,step.from.name,step.to.name,
                    N.Clock(q and q.seconds or step.by.seconds*N.WAIT),q and q.source or "estimate")
            else
                step.report=string.format("%d. %s: %s (%s -> %s)",i,(N.VERB[step.by.kind] or "Pass"):lower(),step.from.name,
                    Routing.Level:Name(step.from.level),Routing.Level:Name(step.to.level))
            end
        end
        steps=N.SplitLifts(steps)
        for _,step in ipairs(steps) do
            if step.kind=="walk" and type(step.path)=="table" and N.CutLoops(step.from.cont,step.path) then
                step.yards=length(step.from.cont,step.path)
            end
        end
        -- Refinement, endpoint trimming and lift splitting change the actual
        -- journey. Chat/export and the guide must estimate these final steps,
        -- not the earlier abstract walks (Norman -> Sylvanas: 46 s vs 66 s).
        -- Finish removes the start-selection penalty; it is never travel time.
        seconds=steps[1] and steps[1].from.cost or 0
        for _,step in ipairs(steps) do seconds=seconds+N:StepSeconds(step) end
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
            -- Where the rest of the time went (Claude 2026-10-27): the longest stretch without a frame (a loading
            -- screen), and waiting while another plan built the continent's navmesh state.
            local wait=Routing.Hpa and Routing.Hpa.stats and Routing.Hpa.stats.waitMs
            Routing:Note(string.format("    Longest time without a frame %.0f ms; waited for the navmesh to be built %.0f ms.",run.longestGap or 0,wait or 0))
            -- Whether the navmesh's preparation after login was done (it shares the frames while it runs).
            local prep=Routing.Hpa.prepared
            Routing:Note("    Prepared after login: "..(prep and string.format("continent %s in %.0f ms",tostring(prep.cont),prep.ms or 0)
                or (Routing:Config().prepareAtLogin and "not yet" or "off"))..".")
            -- What the navmesh planner's walks cost.
            if N.hpaPlan then Routing:Note("  "..Routing.Hpa:Report()) end
        end
        N.hpaPlan=nil
        N.goalMs=nil
        Sch.BUDGET=budget
        -- No way (said while planning): no goal left over.
        if not ok and N.goal==goal and not N.steps then N.goal=nil end
        if not ok or N.goal~=goal then N.quiet,N.enemyPlan=nil,nil;return end
        -- A leg nothing walkable leads along (no other way either): no way, said; never a straight line (Florian
        -- 2026-10-26).
        local blocked
        for _,step in ipairs(steps) do if step.noway then blocked=step end end
        local info={startInfo=startInfo,replanned=replanned,dropped=dropped,began=began}
        if N:EnemyGate(goal,steps,seconds,blocked,info) then return end
        N:Finish(goal,steps,seconds,blocked,info)
    end)
    -- Long: asked whether to go on (Routing.Busy, Florian 2026-10-15).
    if self.run then self.run.askStop=function() Routing:Print("Stopped calculating the way to "..tostring(goal.name)..".");N:Stop(true) end end
    return true
end
-- The way found, taken: drawn, said, followed (or no way, said: a leg nothing walkable leads along).
function N:Finish(goal,steps,seconds,blocked,info)
    info=info or {}
    N.steps,N.track=steps,nil
    -- A leg nothing walkable leads along (no other way either): no way, said; never a straight line (Florian
    -- 2026-10-26).
    if blocked then
        local on=Routing.Level:Name(blocked.from.level)
        Routing:Print(string.format("No way: on \"%s\" the navmesh leads nowhere to %s (%s). Nothing is drawn.",on,blocked.to.name,tostring(blocked.status or "no way")))
        N.steps,N.track,N.goal=nil,nil,nil
        N:Show()
        return
    end
    if info.startInfo then N:StartSaid(info.startInfo,steps) end
    -- The cost of starting on another level than Routing had you on is
    -- for choosing, not time (Florian 2026-10-11: "about 15:38").
    local start=steps[1] and steps[1].from
    -- The search may choose another start layer than Here reported before
    -- refinement. Export the actual plan's start, as the log and steps do.
    if start and self.startAt then self.startAt.level=start.level end
    if start and type(start.cost)=="number" then seconds=math.max(0,seconds-start.cost) end
    -- In the chat one line; the steps in the log (/bv route log).
    N.seconds=seconds
    Routing:Print(string.format("Way to %s (%s): about %s. Details: /bv route log.",goal.name,goal.label or "goal",blocked and "?" or N.Clock(seconds)))
    N:ZoneWarning(steps)
    if (info.replanned or 0)>0 then Routing:Note(string.format("Planned again %d time(s) with the walked lengths.",info.replanned)) end
    for _,step in ipairs(steps) do Routing:Note(step.report) end
    -- Legs that had no way and were left out (another way taken).
    for _,d in ipairs(info.dropped or {}) do Routing:Note("Left out, "..(N.STATUSWORD[d.status] or "no way")..": "..d.text) end
    Routing:Note(string.format("All legs searched in %.1f s. /bv route stop ends it.",GetTime()-(info.began or GetTime())))
    local probe=Routing.Probe
    if probe and probe.on then probe:Plan(goal,steps) end
    N:Show()
    N:Watch(true)
end
-- Enemy bases (Florian 2026-10-27): a way that leads only through or into an enemy base is asked for (Busy:Prompt):
-- yes, led for this way (enemy ground costed as "Avoid enemies", the setting unchanged); no, no way, said. A way
-- that goes round is never asked for: as the setting says. Found by planning again, quietly: a way through
-- (with "Avoid enemies") is planned once more without enemy ground (strict) - none, then asked; no way at all
-- (with "Never cross") is planned once more with enemy ground at "Avoid" (probe) - one through it, then asked.
-- Returns true when it took the way over (asked, or planning again).
function N:EnemyMode()
    local set=Routing:Config().enemy or "avoid"
    if not self.busy or set=="ignore" then return set end
    if self.enemyPlan=="strict" then return "block" end
    if self.enemyPlan=="probe" or self.enemyAllowed then return "avoid" end
    return set
end
-- The enemy base a way leads through or into (its name: the goal's own, else the zone there), or nil.
N.ENEMYSTEP=4   -- yards between the points of a walk looked at
N.ENEMYRUN=3    -- points in a row inside enemy ground that count (not its edge: a way round it may touch that)
function N:EnemyOnWay(goal,steps)
    local Hpa=Routing.Hpa
    if not Hpa then return nil end
    local function name(cont,x,y)
        local info=call("C_Map.GetMapInfoAtPosition",cont,x,y)
        return type(info)=="table" and info.name or "enemy ground"
    end
    if goal.cont and goal.x and Hpa:Active(goal.cont) and Hpa.EnemyAt(goal.x,goal.y) then
        return goal.hostile or name(goal.cont,goal.x,goal.y)
    end
    for _,step in ipairs(steps or {}) do
        local cont,path=step.from and step.from.cont,step.path
        if step.kind=="walk" and type(path)=="table" and cont and Hpa:Active(cont) then
            local run=0
            for i=2,#path do
                local a,b=path[i-1],path[i]
                local k=math.max(1,math.ceil(N.Yards(cont,a[1],a[2],b[1],b[2])/N.ENEMYSTEP))
                for j=(i==2) and 0 or 1,k do
                    local x,y=a[1]+(b[1]-a[1])*j/k,a[2]+(b[2]-a[2])*j/k
                    if Hpa.EnemyAt(x,y,true) then
                        run=run+1
                        if run>=N.ENEMYRUN then return goal.hostile or name(cont,x,y) end
                    else run=0 end
                end
            end
        end
    end
    return nil
end
function N:EnemyAgain(goal,plan)
    self.enemyPlan,self.quiet=plan,true
    Routing:Note(plan=="strict" and "The way leads through enemy ground: planned again without it, to see whether a way round exists."
        or "No way: planned again with enemy ground allowed, to see whether a way leads through it.")
    if not self:Start(goal,true) then self.enemyPlan,self.quiet,self.enemyPending=nil,nil,nil;return false end
    return true
end
function N:EnemyAsk(goal,p)
    Routing:Note(string.format("Only through or into an enemy base (%s): asked.",p.name))
    Routing.Busy:Prompt(string.format("The way to %s leads through an enemy base (%s). Lead you there anyway?",tostring(goal.name),p.name),"Yes","No",
        function()
            if N.goal~=goal or N.steps or N.busy then return end
            N.enemyAllowed=true
            Routing:Note(string.format("Enemy ground allowed for this way after you confirmed (%s); the setting is unchanged.",p.name))
            N:Finish(goal,p.steps,p.seconds,nil,p.info)
        end,
        function()
            if N.goal~=goal or N.steps or N.busy then return end
            Routing:Note(string.format("Enemy ground not allowed (you chose No, %s): no way.",p.name))
            Routing:Print(string.format("No way to %s: it leads only through an enemy base (%s), and you chose not to go there. Nothing is drawn.",tostring(goal.name),p.name))
            N.goal=nil
            N:Show()
        end)
    return true
end
function N:EnemyGate(goal,steps,seconds,blocked,info)
    local plan=self.enemyPlan
    self.enemyPlan,self.quiet=nil,nil
    local set=Routing:Config().enemy or "avoid"
    if set=="ignore" or self.enemyAllowed or not (Routing.Busy and Routing.Busy.Prompt) then return false end
    local p=self.enemyPending
    self.enemyPending=nil
    if plan==nil then
        local name=not blocked and self:EnemyOnWay(goal,steps)
        if name then
            self.enemyPending={steps=steps,seconds=seconds,name=name,info=info}
            return self:EnemyAgain(goal,"strict")
        end
        if blocked and set=="block" then
            self.enemyPending={steps=steps,seconds=seconds,blocked=blocked,info=info}
            return self:EnemyAgain(goal,"probe")
        end
        return false
    end
    if not p then return false end
    if plan=="strict" then
        -- A way round exists: the setting's own choice (the way through, "Avoid enemies") stands, not asked.
        if not blocked then
            Routing:Note(string.format("A way round the enemy base (%s) exists: the way through it stands, as \"Avoid enemies\" weighs it.",p.name))
            self:Finish(goal,p.steps,p.seconds,nil,p.info)
            return true
        end
        return self:EnemyAsk(goal,p)
    end
    -- probe: a way through enemy ground, asked; none: the first answer (no way)
    local name=not blocked and self:EnemyOnWay(goal,steps)
    if name then return self:EnemyAsk(goal,{steps=steps,seconds=seconds,name=name,info=info}) end
    self:Finish(goal,p.steps,p.seconds,p.blocked,p.info)
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
-- Height for replanning comes from the tracked walk, not the nearest vertex
-- anywhere in the plan (an upper turn can be closer on the map). Only a
-- nearby projection with both endpoint heights is evidence for N.HpaEnds.
N.HEREZYD=6
function N:HeightOnWay()
    self.hereZ=nil
    local cont,px,py=self:Here()
    if not (cont and self.steps) then return end
    local a=self:AnchorSample(cont,px,py)
    local g=a and a.piece
    if a and a.relation=="projected" and a.d<=N.HEREZYD and g.kind=="walk"
        and self.steps[g.step].navmesh and type(g.az)=="number" and type(g.bz)=="number" then
        self.hereZ={cont=cont,x=px,y=py,z=g.az+(g.bz-g.az)*a.t,t=GetTime()}
    end
end
N.HEREZTIME=30
-- The way searched anew from where you are now, to the same goal (Florian
-- 2026-10-14: the guide's button, when you came far off the way).
function N:Restart()
    if self.busy then Routing:Print("Still calculating.");return false end
    local goal=self.goal
    if not goal then return false end
    self:HeightOnWay()
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
    add("versions","core="..version("BVAddonSuite"),"routing="..version("BVAddonSuite_Routing"),
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
        add("map",id,"clearance="..tostring(m.clearance or "default"),"mineOff="..tostring(m.mineOff==true),"source="..tostring(m.source or "mine"))
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
function N:Stop(quiet)
    local had=self.steps or self.busy
    if self.run then self.run:Cancel();self.run=nil end
    if self.budget then Routing.Scheduler.BUDGET=self.budget end
    self.steps,self.goal,self.current,self.busy,self.budget,self.left,self.flightNote=nil,nil,nil,nil,nil,nil,nil
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
-- Distance along the remaining way, independent of its point/step density.
N.DRAWSTEP=2
N.AHEADLINE=.3
N.AHEADPIN=.55
N.FADESTART=20
N.FADEDIST=100
N.FADEPIECE=5
function N.Fade(yards,full,distance)
    if yards<=N.FADESTART then return 1 end
    return 1-(1-full)*math.min(1,(yards-N.FADESTART)/math.max(1,(distance or N.FADEDIST)-N.FADESTART))
end
-- The dimming as the settings say (Florian 2026-10-16): line and pin at full
-- dimming, route yards to get there; pins keep their share of the line's dimming
-- (built in: line .3, pin .55).
N.PINSHARE=(1-N.AHEADPIN)/(1-N.AHEADLINE)
-- Display-only options live here, outside the baked navigation data contract.
-- The legacy aheadSteps value remains readable by old clients but is unused.
function N:DisplayConfig()
    local c=Routing:Config()
    local distance=tonumber(c.aheadDistance)
    if not distance or distance~=distance then distance=N.FADEDIST end
    c.aheadDistance=math.max(40,math.min(300,math.floor(distance+.5)))
    return c
end
function N:Ahead()
    local c=self:DisplayConfig()
    local line=c.aheadOpacity/100
    return line,1-(1-line)*N.PINSHARE,c.aheadDistance
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
    local aheadLine,aheadPin,aheadDistance=self:Ahead()
    if self.pointSteps~=self.steps then self.pointSteps,self.pointCache=self.steps,{} end
    local cache=self.pointCache
    local cfg=Routing:Config()
    local colors=table.concat({tostring(cfg.colorWalk),tostring(cfg.colorFlight),tostring(cfg.colorTransport),tostring(cfg.colorTransition),tostring(cfg.colorGoal)},":")
    local drawAhead=0
    for i,step in ipairs(self.steps) do
        if i>=self.current then
            local ahead=(i==self.current and step.kind=="walk" and step.path) and (self.ahead or 1) or 1
            local id=table.concat({drawAhead,ahead,tostring(step.path),tostring(here),aheadDistance,colors},":")
            local c=cache[i]
            if not (c and c.id==id) then
                local list,span,origin=self:StepPoints(i,step,here,aheadLine,aheadPin,aheadDistance,ahead,drawAhead)
                c={id=id,list=list,spans=span,origin=origin};cache[i]=c
            end
            for _,point in ipairs(c.list) do out[#out+1]=point end
            drawAhead=drawAhead+(c.spans or 0)
        end
    end
    local cont,px,py=self:Here()
    local base=cache[self.current] and cache[self.current].origin or 0
    local anchor=self:Anchor(cont,px,py)
    if anchor and self.track then
        for _,g in ipairs(self.track) do if g.step==self.current then base=math.max(0,anchor-g.a0);break end end
    end
    return self:DistancePoints(out,base,aheadLine,aheadPin,aheadDistance,cont,px,py)
end
-- Split only the moving fade window, at most ~60 extra points even on a
-- continent-long route. Cached geometry and pooled samples keep repaint
-- allocation bounded; none of these points is fed to navigation/tracking.
function N:DistancePoints(points,base,line,pin,distance,cont,px,py)
    local out,previous={},nil
    self.fadePool=self.fadePool or {}
    local pool,used=self.fadePool,0
    local function sample(source)
        used=used+1
        local p=pool[used] or {};pool[used]=p
        for k in pairs(p) do p[k]=nil end
        if source then for k,v in pairs(source) do p[k]=v end end
        return p
    end
    for _,q in ipairs(points) do
        local lead=q.lead
        if lead and cont==q.mapID and px then previous={mapID=cont,x=px,y=py,distance=base} end
        local split=false
        if line<1 and not q.noLine and q.distance and previous and previous.mapID==q.mapID
            and previous.distance and q.distance>previous.distance+1e-6 then
            local cut=base+N.FADESTART
            if cut<=previous.distance then cut=cut+(math.floor((previous.distance-cut)/N.FADEPIECE)+1)*N.FADEPIECE end
            while cut<q.distance-1e-6 and cut<=base+distance do
                local t=(cut-previous.distance)/(q.distance-previous.distance)
                local x,y=previous.x+(q.x-previous.x)*t,previous.y+(q.y-previous.y)*t
                -- Do not turn a dense stair into subpixel pieces again.
                local last=out[#out] or previous
                if N.Yards(q.mapID,last.x,last.y,x,y)>=N.DRAWSTEP and N.Yards(q.mapID,x,y,q.x,q.y)>=N.DRAWSTEP then
                    local p=sample()
                    p.mapID,p.x,p.y=q.mapID,x,y
                    p.distance,p.noPin,p.dim=cut,true,q.dim
                    p.lineColor,p.lineAlpha=q.lineColor or q.color,N.Fade(cut-base,line,distance)
                    p.lead,p.leadColor=lead,q.leadColor;lead=nil
                    out[#out+1]=p;split=true
                end
                cut=cut+N.FADEPIECE
            end
        end
        local p=(split and q.lead) and sample(q) or q
        p.lead=lead
        if not p.noLine then p.lineAlpha=N.Fade((p.distance or base)-base,line,distance) end
        if p.fadePin then p.alpha=N.Fade((p.distance or base)-base,pin,distance) end
        out[#out+1]=p;previous=q
    end
    return out
end
-- The inner points of a drawn line with its corners as short curves (a quadratic curve through the corner's two
-- neighbours' directions, at most ROUNDDEV yards inside the corner, never past half a side). seq: the line's points
-- {x, y}, its first and last kept as they are; returns the points between them.
N.ROUNDDEV=2
function N.RoundCorners(cont,seq)
    local out={}
    for i=2,#seq-1 do
        local A,P,B=seq[i-1],seq[i],seq[i+1]
        local la=N.Yards(cont,P[1],P[2],A[1],A[2])
        local lb=N.Yards(cont,P[1],P[2],B[1],B[2])
        local done=false
        if la>=.5 and lb>=.5 then
            local ux,uy=(A[1]-P[1])/la,(A[2]-P[2])/la
            local vx,vy=(B[1]-P[1])/lb,(B[2]-P[2])/lb
            local s=N.Yards(cont,P[1],P[2],P[1]+ux+vx,P[2]+uy+vy)
            if s>=.05 then
                local r=math.min(la/2,lb/2,4*N.ROUNDDEV/s)
                local x1,y1,x2,y2=P[1]+ux*r,P[2]+uy*r,P[1]+vx*r,P[2]+vy*r
                for _,f in ipairs({0,.25,.5,.75,1}) do
                    local g=1-f
                    out[#out+1]={g*g*x1+2*f*g*P[1]+f*f*x2,g*g*y1+2*f*g*P[2]+f*f*y2,
                        distance=P.distance and (P.distance-r+2*r*f) or nil}
                end
                done=true
            end
        end
        if not done then out[#out+1]=P end
    end
    return out
end
-- One leg's points for the maps (N:Points).
function N:StepPoints(i,step,here,aheadLine,aheadPin,aheadDistance,ahead,drawAhead)
    local out={}
    local color=N:Color(step.kind)
    local from,to=step.from,step.to
    local dim=(from.level or 0)~=(here or 0) or nil
    local later=i>self.current
    drawAhead=drawAhead or 0
    local la,pa=1,1
    local span,origin=0,0
    -- The walk you are on: from the next point ahead of you, the line
    -- from you leading to it (Florian 2026-10-11: it led back to the
    -- leg's start behind you). self.ahead: Tick, the path point after
    -- the piece you are nearest to.
    local lead=i==self.current and step.kind=="walk"
    if ahead<=1 then
        out[#out+1]={mapID=from.cont,x=from.x,y=from.y,noPin=from.kind=="start" or nil,dot=true,size=10,hollow=true,color=color,alpha=pa,lineAlpha=la,dim=dim,
            lead=lead or nil,leadColor=color,distance=drawAhead,fadePin=later or nil}
        lead=false
    end
    local drawn=step.path or step.shape
    if drawn then
        -- Points DRAWSTEP yards apart at least (Florian 2026-10-14:
        -- the Slaughtered Lamb's spiral, 338 points on 62 yards, was
        -- not drawn at all: pieces of a fraction of a pixel); the
        -- way itself keeps every point.
        local lx,ly=drawn[math.max(1,ahead-1)][1],drawn[math.max(1,ahead-1)][2]
        for j=2,math.max(1,ahead-1) do span=span+N.Yards(from.cont,drawn[j-1][1],drawn[j-1][2],drawn[j][1],drawn[j][2]) end
        origin=span
        local first={lx,ly,distance=drawAhead+span}
        local pts,leadAt={},nil
        for j=math.max(2,ahead),#drawn-1 do
            local px,py=drawn[j][1],drawn[j][2]
            span=span+N.Yards(from.cont,drawn[j-1][1],drawn[j-1][2],px,py)
            if lead or N.Yards(from.cont,lx,ly,px,py)>=N.DRAWSTEP then
                pts[#pts+1]={px,py,distance=drawAhead+span}
                if lead then leadAt=#pts end
                lead=false
                lx,ly=px,py
            end
        end
        if #drawn>=2 then span=span+N.Yards(from.cont,drawn[#drawn-1][1],drawn[#drawn-1][2],drawn[#drawn][1],drawn[#drawn][2]) end
        -- A walk's corners drawn round (only drawn: the way, the tracker and the guide keep its points; Florian
        -- 2026-10-27, Undercity's ring corner to corner: "korrekt, nur nicht schoen"). Not the one leading from you.
        if step.kind=="walk" and #pts>=1 then
            local seq={leadAt and pts[1] or first}
            for k=(leadAt and 2 or 1),#pts do seq[#seq+1]=pts[k] end
            seq[#seq+1]={to.x,to.y,distance=drawAhead+span}
            local round=N.RoundCorners(from.cont,seq)
            if leadAt then table.insert(round,1,pts[1]) end
            pts=round
        end
        for k,q in ipairs(pts) do
            out[#out+1]={mapID=from.cont,x=q[1],y=q[2],noPin=true,lineColor=color,
                lineAlpha=la,dim=dim,distance=q.distance,
                lead=(k==leadAt) or nil,leadColor=color}
        end
    elseif from.cont==to.cont then
        span=N.Yards(from.cont,from.x,from.y,to.x,to.y)
    end
    -- A teleport: no line between its ends (none to walk).
    local jump=N.Teleport(step)
    if jump or from.cont~=to.cont then span=math.max(span,aheadDistance or N.FADEDIST) end
    out[#out+1]={mapID=to.cont,x=to.x,y=to.y,dot=true,size=to.kind=="goal" and 14 or 10,hollow=true,dim=(to.level or 0)~=(here or 0) or nil,
        color=to.kind=="goal" and N:Color("goal") or color,alpha=1,lineColor=color,lineAlpha=jump and 0 or la,noLine=jump or nil,lead=lead or nil,leadColor=color,
        distance=drawAhead+span,fadePin=(later and to.kind~="goal") or nil}
    -- The goal where the way cannot reach it (its NPC on no-go): a
    -- small mark of its own, no line to it.
    if to.npc then
        out[#out+1]={mapID=to.cont,x=to.npc.x,y=to.npc.y,dot=true,size=9,color=N:Color("goal"),alpha=.8,lineAlpha=0,noLine=true,dim=(to.level or 0)~=(here or 0) or nil}
    end
    return out,span,origin
end
function N:Show()
    if Routing.Guide then Routing.Guide:Update() end
    if not ns.MapPins then return end
    if not self.registered then
        self.registered=true
        ns.MapPins:Register("routing:way",{points=function() return N:Points() end,lines=true,arrows=true,continuousArrows=true,minimap=true,
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
    local dir=step.dir or L:Way(step.from.level,to.level,step.from.cont,step.from.x,step.from.y)
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
function N:StepSeconds(step,at)
    if step.kind=="walk" then
        local yards=step.yards or N.Yards(step.from.cont,step.from.x,step.from.y,step.to.x,step.to.y)*N.DETOUR
        return yards/self:Speed()
    elseif step.kind=="flight" then return (self:FlightSeconds(step.from,step.to))
    elseif step.kind=="transport" then
        if Routing.Timetable then return Routing.Timetable:StepQuote(step,at or Routing.Timetable:Now()).seconds end
        return (tonumber(step.by.seconds) or 0)*N.WAIT
    end
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
    local at=Routing.Timetable and Routing.Timetable:Now()
    for k=i+1,#self.steps do total=total+self:StepSeconds(self.steps[k],at and at+total) end
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
    local s=mapSize(cont)
    local dx,dy=(bx-ax)*s[1],(by-ay)*s[2]
    local len=dx*dx+dy*dy
    local t=len>0 and math.max(0,math.min(1,((px-ax)*s[1]*dx+(py-ay)*s[2]*dy)/len)) or 0
    return N.Yards(cont,px,py,ax+(bx-ax)*t,ay+(by-ay)*t),t
end
local function nearest(cont,px,py,path)
    local near=math.huge
    for j=2,#(path or {}) do
        local d=segment(cont,px,py,path[j-1][1],path[j-1][2],path[j][1],path[j][2])
        near=math.min(near,d)
    end
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
N.TOWNSTEP=6      -- the same onto a town's level, where a leap ahead goes only down
N.SHAPELEAP=15    -- yards ahead along a transition's walked shape the tracker may take you at once
N.TOWNDOWN=3      -- yards a town level lies below yours to be leapt onto
N.SOFTNEAR=6      -- yards to the goal (or the way's end) and of the way left within which soft interact on it is arrival
N.MOVESLACK=8     -- yards beyond your own movement the tracker may take you ahead on a navmesh walk
N.ENDNEAR=6       -- yards from a navmesh walk's end (the goal's reach) before it counts as done
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
                    pieces[#pieces+1]={step=i,j=j,kind=step.kind,cont=step.from.cont,ax=ax,ay=ay,bx=bx,by=by,
                        az=pts[j-1].z or pts[j-1].endz,bz=pts[j].z or pts[j].endz,a0=along,len=len,corner=pts[j].corner}
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
    return segment(cont,px,py,g.ax,g.ay,g.bx,g.by)
end
-- A navmesh walk can cross several floors without changing steps. Compare
-- height at the projected point, not the level at the whole walk's start.
-- Polygon tails may lack heights: unknown, not an invented start-floor test.
local function fitsPiece(self,g,cont,px,py,t)
    local H=Routing.Height
    if not H or g.kind~="walk" then return nil end
    local step=self.steps[g.step]
    if step.navmesh then
        if type(g.az)~="number" or type(g.bz)~="number" then return nil end
        return H.Fits(H:Now().set,g.az+(g.bz-g.az)*t)
    end
    if step.from.level~=nil then return H:FitsLevel(step.from.level,cont,px,py) end
end
-- Did you go through a transition (from, to)? Evidence, not the map
-- position alone: your height (it must not deny the level it leads to; it
-- fitting there and not where it starts says so), the district naming
-- that level; on stairs and ramps reaching their end; at a lift (one spot)
-- having stood there its time, or walked off it along the next leg.
-- atEnd: you have come along its walked shape to its last SHAPEEND yards (EndOf).
-- A town's level (Road Studio: its own bounds and cells): its heights walked, a ramp round
-- a tower may lie over its own foot on the map.
-- The middle of a level's heights (lo, hi), or nil (the ground: nil).
function N.LevelMid(id)
    if id==nil or not Routing.Level then return nil end
    local lo,hi=Routing.Level:Span(id)
    if type(lo)=="number" and type(hi)=="number" then return (lo+hi)/2 end
    return nil
end
-- (Its level ways only: a town's ground is a wide open level where you walk
-- anywhere and a leap ahead along the way is as anywhere, Florian 2026-10-20:
-- the guide no longer leapt ahead and sent you back.)
function N.IsTownLevel(id)
    if id==nil or not Routing.Level then return false end
    local lv=Routing.Level:Find(id)
    return type(lv)=="table" and lv.bounds~=nil and not lv.townGround
end
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
    -- Onto a town's level (Road Studio bounds, a ramp round a tower): only by your height
    -- or when you came along the way to it; nothing that lies near on the map counts
    -- (Florian 2026-10-20: at the Crossroads tower's foot, Darsok right above, the guide
    -- took the ramp as climbed and said "arrived").
    if N.IsTownLevel(to.level) then
        if toFits==true then return true,"your height fits its level" end
        if atEnd then return true,"along the way to it" end
        return false
    end
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
        -- A lift whose stations lie apart on the map (Thunder Bluff's, 26-28 yd): out at its top only right there, LIFTEND
        -- yards (Claude 2026-10-25, walk simulation to Atepa: DOOR yards counted it as ridden half way along at its
        -- foot, and the walk above it lay further than you had moved: "off the way").
        local reach=(type(step.by)=="table" and step.by.kind=="lift") and N.LIFTEND or N.DOOR
        if dTo<=reach and dTo<N.Yards(cont,px,py,from.x,from.y) then return true,string.format("out at its other end (%.0f yd)",dTo) end
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
-- Is your soft interact target the goal (an NPC by its name; Map Data has no creature IDs)? Never with secret values.
-- Is your soft interact target within the client's interact distance (CheckInteractDistance index N.SOFTCHECK, as
-- /bv route reach says it: "interact range")? true, false, or nil where it cannot be asked (no call, an error, a
-- protected or secret answer).
N.SOFTCHECK=3
function N.SoftInRange()
    local f=rawget(_G,"CheckInteractDistance")
    if type(f)~="function" then return nil end
    local ok,v=pcall(f,"softinteract",N.SOFTCHECK)
    if not ok or Routing.Secret(v) then return nil end
    if v==true then return true end
    if v==false then return false end
    return nil
end
function N.SoftOnGoal(goal)
    if not (goal and type(goal.name)=="string" and type(goal.z)=="number") then return false end
    local f=rawget(_G,"UnitName")
    if type(f)~="function" then return false end
    local ok,name=pcall(f,"softinteract")
    if not ok or type(name)~="string" or Routing.Secret(name) then return false end
    return name==goal.name
end
function N:Locate(cont,px,py)
    -- The track belongs to its plan: a new plan, a new track.
    local track=(self.track and self.trackOf==self.steps) and self.track or self:BuildTrack()
    local was=self.trackAlong or 0
    local first
    for k,g in ipairs(track) do if g.step==self.current then first=k;break end end
    if not first then return nil end
    local found,passed,startOf={},{},{}
    local base=was
    for k=first,#track do
        local g=track[k]
        if g.ride then break end
        startOf[g.step]=startOf[g.step] or g.a0
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
            local d,t=onPiece(g,cont,px,py)
            if fitsPiece(self,g,cont,px,py,t)~=false then
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
    -- Onto a town's level a leap ahead goes only down, never up (Florian 2026-10-20: "a jump
    -- cannot go up, only down"; at the Crossroads tower's foot the end of the ramp's first turn
    -- lies over the foot and was taken from the ground): ahead by TOWNSTEP yards as you walk,
    -- further only onto a level lower than the one you are on.
    local hereMid=N.LevelMid(self.steps[self.current] and self.steps[self.current].from.level)
    -- On a navmesh walk ahead only as far as you moved since the last look, plus MOVESLACK (Claude 2026-10-25,
    -- Florian in Ironforge: at the foot of Harick's outer stair the line's end, a floor up, lies near on the map; the
    -- tracker leapt onto it and the way ended 27 yd before him).
    local moved
    local last=self.trackXY
    if last and last[1]==cont then moved=N.Yards(cont,last[2],last[3],px,py) end
    self.trackXY={cont,px,py}
    -- Outdoors (Florian 2026-10-26, Taurajo -> Freewind at GM speed: the next point stayed behind you): on no level, or on
    -- a town's open ground, on the walk you are on, you are where the way passes you - the piece nearest you however far
    -- along. Strict only where floors lie over each other: on a level, along a transition or a lift.
    local lvNow=Routing.Level and Routing.Level:Current()
    local lvRec=lvNow and Routing.Level:Find(lvNow)
    local outdoors=lvNow==nil or (type(lvRec)=="table" and lvRec.townGround==true)
    self.outdoors=outdoors
    local walkRun=self:WalkRun(outdoors)
    local function townOk(f)
        local st=self.steps[f[1].step]
        if outdoors and walkRun[f[1].step] and st.kind=="walk" then return true end
        local level=st.from.level
        -- (beyond a gate passed by evidence, a lift ridden: from that step's start)
        if st.navmesh and moved then
            local from=passed[f[1].step] and math.max(was,startOf[f[1].step] or was) or was
            return f[1].a0+f[1].len*f[3]<=from+moved+N.MOVESLACK
        end
        -- Along a transition's walked shape only as you walk it, never leapt onto (Claude's walk
        -- simulation 2026-10-24, Ironforge navmesh stairs: the top of the stair to Nissa lies 4-5 yd
        -- over the street before it; the tracker leapt onto it and the way said "arrived" 34 yd early).
        if st.kind=="transition" and type(st.path)=="table" and #st.path>=3 then
            return f[1].a0+f[1].len*f[3]<=was+N.SHAPELEAP
        end
        if not N.IsTownLevel(level) then return nil end
        local along,mid=f[1].a0+f[1].len*f[3],N.LevelMid(level)
        -- (From where you are or from the start of the step you are on: entering it is no leap.)
        return along<=math.max(was,startOf[self.current] or was)+N.TOWNSTEP or (hereMid~=nil and mid~=nil and mid<hereMid-N.TOWNDOWN)
    end
    local bestGap
    for _,f in ipairs(found) do
        local town=townOk(f)
        local ok
        if town~=nil then ok=town else ok=passed[f[1].step] or f[1].a0+f[1].len*f[3]<=was+N.LEAP end
        if f[2]<=minD+N.TIE and ok then
            -- (outdoors, of pieces about as near the one nearest where you were along the way: where the way passes the
            -- same spot again - into a house and out beside its door - not its later pass; walk simulation, Gadgetzan)
            local gap=outdoors and f[1].step==self.current and math.abs(f[1].a0+f[1].len*f[3]-was) or nil
            if not (gap and bestGap and gap>=bestGap) then best,bestD,bestT,bestGap=f[1],f[2],f[3],gap end
        end
    end
    if not best then
        -- The nearest piece, but never a leap up a town's level.
        local nd
        for _,f in ipairs(found) do if townOk(f)~=false and (not nd or f[2]<nd) then nd=f[2] end end
        for _,f in ipairs(found) do if townOk(f)~=false and f[2]==nd then best,bestD,bestT=f[1],f[2],f[3] end end
        if not best then return nil end
    end
    -- A movement-gated projection can stay at an old corner after a player
    -- cuts across a bend. Do not call that distant fallback "on the way"
    -- forever: it would reset OFFLOOKS while preventing all later progress.
    -- Keep the floor gate intact and let sustained disagreement use the
    -- normal replan from the player's position. A nearby lower-floor piece
    -- remains valid even if an upper turn is slightly closer on the map.
    if self.steps[best.step].navmesh and bestD>math.max(N.MOVESLACK,minD+N.TIE) then
        return nil,"progressMismatch"
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
-- Where you are on the step you walk (yards along the track): your projection onto its pieces, never behind the farthest
-- you came (walking back the way ahead stays ahead). Outdoors (no level or a town's open ground, as N:Locate last found
-- you) up to WINDOW yards past the farthest; on a level only within MOVESLACK past it, where
-- floors lie over each other. The guide's arrow and the tracker share it (Claude 2026-10-26: the arrow's point leapt
-- each quarter second with the tracker's farthest, and zigzagged with the way's dense points).
-- The steps you may be on as you walk: outdoors the one you are on and the walks right after it (no transition, lift
-- or ride between: a walk's end there is only a point on the way - Claude 2026-10-27, Florian at GM speed: the compass
-- turned back at such a point until the tracker's next look moved the step on); on a level only the one you are on.
-- (step index -> true)
function N:WalkRun(outdoors)
    local run={[self.current]=true}
    local steps=self.steps or {}
    if outdoors and steps[self.current] and steps[self.current].kind=="walk" then
        local i=self.current+1
        while steps[i] and steps[i].kind=="walk" and steps[i].from.cont==steps[self.current].from.cont do run[i]=true;i=i+1 end
    end
    return run
end
function N:AnchorSample(cont,px,py)
    local track=self.track
    if not (track and self.trackOf==self.steps and self.farthest) then return nil end
    local far=self.farthest
    -- (outdoors or not as the tracker last found you)
    local reach=self.outdoors and N.WINDOW or N.MOVESLACK
    local run=self:WalkRun(self.outdoors)
    local best,bestD,bestG,bestT
    if cont and px then
        for _,g in ipairs(track) do
            if run[g.step] and not g.ride and g.cont==cont and g.a0+g.len>=far and g.a0<=far+reach then
                local d,t=onPiece(g,cont,px,py)
                local at=g.a0+g.len*t
                -- A small correction behind the last tracker sample is
                -- still a projection onto this piece, not a missing course.
                -- Use the tracker's existing tie tolerance; never rewind
                -- the guidance anchor or change recorded progress. The
                -- piece must still reach far, and all height gates apply.
                if at>=far-N.TIE and at<=far+reach and fitsPiece(self,g,cont,px,py,t)~=false
                    and (not bestD or d<bestD) then best,bestD,bestG,bestT=math.max(far,at),d,g,t end
            end
        end
    end
    if best then return {along=best,piece=bestG,t=bestT,d=bestD,relation="projected"} end
    return {along=far,relation="progressFallback"}
end
-- (the yards along alone, for the tracker's callers)
function N:Anchor(cont,px,py)
    local a=self:AnchorSample(cont,px,py)
    return a and a.along
end
-- The point the guide's arrow points to on a walk (Florian 2026-10-14: on a winding way of many short pieces each point
-- was reached late and the arrow swung back and forth): LOOK yards along the way ahead of where you are on it
-- (N:Anchor), as the middle of the way's points from LOOK-SPREAD to LOOK+SPREAD yards ahead (Claude 2026-10-26, Florian
-- at Bloodhoof: the dense navmesh points zigzag a yard or two either side; one point 15 yd ahead swung the arrow by as
-- much, and stood a little to one side). The step's end when less is left. nil before you are placed on the way.
N.LOOK=15
N.SPREAD=5
-- From base yards along the step you are on: cont, x, y, and "stepEnd" (less is left) or "carrot" (the middle).
function N:CarrotFrom(base)
    local track=self.track
    if not (track and self.trackOf==self.steps and base) then return nil end
    -- (outdoors on into the walks right after the one you are on, N:WalkRun)
    local run=self:WalkRun(self.outdoors)
    local pieces,stop={},nil
    for _,g in ipairs(track) do
        if run[g.step] and not g.ride then pieces[#pieces+1]=g;stop=g.a0+g.len end
    end
    if #pieces==0 then return nil end
    local last=pieces[#pieces]
    -- An averaged target beyond a polygon corner points through its wall or
    -- off its stair. Preserve required corridor turns; unmarked noisy samples
    -- on open paths retain the existing smoothed lookahead.
    for _,g in ipairs(pieces) do
        local turn=g.a0+g.len
        if g.corner and turn>base+1e-6 and turn<=base+N.LOOK+N.SPREAD then
            return g.cont,g.bx,g.by,"carrot"
        end
    end
    local function at(a)
        for _,g in ipairs(pieces) do
            if g.a0+g.len>=a then
                local t=g.len>0 and math.max(0,math.min(1,(a-g.a0)/g.len)) or 1
                return g.ax+(g.bx-g.ax)*t,g.ay+(g.by-g.ay)*t
            end
        end
        return last.bx,last.by
    end
    if base+N.LOOK>=stop then return last.cont,last.bx,last.by,"stepEnd" end
    local sx,sy,n=0,0,0
    for a=base+N.LOOK-N.SPREAD,math.min(stop,base+N.LOOK+N.SPREAD),1 do
        local x,y=at(a);sx,sy,n=sx+x,sy+y,n+1
    end
    return last.cont,sx/n,sy/n,"carrot"
end
function N:Carrot()
    if not (self.track and self.trackOf==self.steps and self.farthest) then return nil end
    local mapID,mx,my=Routing:Position()
    local cont,px,py
    if mapID then cont,px,py=Routing:OnContinent(mapID,mx,my) end
    local cc,x,y=self:CarrotFrom(self:Anchor(cont,px,py))
    return cc,x,y
end
-- One sample of where the guide leads, for the guide's compass (Codex's contract v1, 2026-10-26:
-- artifacts/ui-routing-compass-concept-2026-10-26/snapshot-contract-v1.md): your position read once, the anchor on the
-- way (N:AnchorSample) once; the course along the way's piece there, the point ahead (N:CarrotFrom) from that same
-- anchor, the side you stand off the way. Nothing of the tracker's progress changes. Bearings in world radians as
-- G:Vector: north 0, west pi/2, south pi, east 3pi/2.
function N:GuideSnapshot()
    local steps=self.steps
    local step=steps and steps[self.current]
    local snap={version=1,route=steps,stepIndex=self.current,routeRelation="unknown"}
    local function no(reason) return {valid=false,reason=reason} end
    if not step then
        snap.phase=self.busy and "searching" or "stopped"
        snap.course,snap.target,snap.offset=no(snap.phase),no(snap.phase),no(snap.phase)
        return snap
    end
    if step.kind=="walk" then snap.phase="walk"
    elseif step.kind=="transition" then
        snap.phase="transition"
        snap.transitionKind=type(step.by)=="table" and step.by.kind or nil
        if snap.transitionKind=="lift" then snap.liftPhase="unknown" end
    else snap.phase=step.kind end
    if snap.phase=="flight" or snap.phase=="transport" then
        snap.course,snap.target,snap.offset=no("notWalking"),no("notWalking"),no("notWalking")
        return snap
    end
    local cont=step.from.cont
    local mapID,mx,my=Routing:Position()
    local here,px,py
    if mapID then here,px,py=Routing:OnContinent(mapID,mx,my) end
    local width,height=Routing.Call("C_Map.GetMapWorldSize",cont)
    local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge and not (Routing.Secret and Routing.Secret(v)) end
    if not (here and finite(px) and finite(py)) then
        snap.course,snap.target,snap.offset=no("noPosition"),no("noPosition"),no("noPosition")
        return snap
    end
    if here~=cont or not (finite(width) and finite(height) and width>0 and height>0) then
        snap.course,snap.target,snap.offset=no("mapMismatch"),no("mapMismatch"),no("mapMismatch")
        return snap
    end
    local function bearing(e,s) return math.atan2(-e,-s)%(2*math.pi) end
    -- The anchor, once (on a walk or along a transition's walked shape).
    local walked=step.kind=="walk" or (step.kind=="transition" and not N.Teleport(step) and type(step.path)=="table" and #step.path>=3)
    local a=walked and self:AnchorSample(here,px,py) or nil
    if a then snap.anchorAlongYards,snap.routeRelation=a.along,a.relation end
    -- The course: the piece at the anchor, forward (at its end the next piece of the step, at the step's end the last).
    if a and a.relation=="projected" then
        local g=a.piece
        local run=self:WalkRun(self.outdoors)
        local function long(q) return q and not q.ride and run[q.step] and N.Yards(cont,q.ax,q.ay,q.bx,q.by)>.01 end
        if not long(g) or a.t>=1 then
            local found,lastOk
            for _,q in ipairs(self.track) do
                if long(q) then
                    lastOk=q
                    if not found and q.a0>=g.a0+g.len-1e-9 and q~=g then found=q end
                end
            end
            g=found or (long(g) and g) or lastOk
        end
        if g then
            local e,s=(g.bx-g.ax)*width,(g.by-g.ay)*height
            snap.course={valid=true,bearingWorldRad=bearing(e,s),mode="tangent"}
            -- Off the way, routewise (positive: right of the way's direction): only where you project onto the inside
            -- of the piece the anchor used.
            if a.piece==g and a.t>0 and a.t<1 then
                local l=math.sqrt(e*e+s*s)
                local tE,tS=e/l,s/l
                local qx,qy=g.ax+(g.bx-g.ax)*a.t,g.ay+(g.by-g.ay)*a.t
                local rE,rS=(px-qx)*width,(py-qy)*height
                snap.offset={valid=true,signedYards=-tS*rE+tE*rS}
            else snap.offset=no("clamped") end
        else snap.course,snap.offset=no("degenerate"),no("degenerate") end
    else
        local why=a and "progressFallback" or "noAnchor"
        snap.course,snap.offset=no(why),no(why)
    end
    -- The point ahead from the same anchor; else the guide's former points (the way's next point, the step's end, a
    -- teleport's entry).
    local tc,tx,ty,source
    if a then tc,tx,ty,source=self:CarrotFrom(a.along) end
    if not tc then
        if N.Teleport(step) then tc,tx,ty,source=step.from.cont,step.from.x,step.from.y,"teleportEntry"
        elseif step.kind=="walk" and type(step.path)=="table" and #step.path>=2 then
            local j=math.min(#step.path,math.max(2,self.ahead or 2))
            tc,tx,ty,source=cont,step.path[j][1],step.path[j][2],"pathPoint"
        else tc,tx,ty,source=step.to.cont,step.to.x,step.to.y,"stepEnd" end
    end
    if tc~=cont or not (finite(tx) and finite(ty)) then snap.target=no("mapMismatch")
    else
        local e,s=(tx-px)*width,(ty-py)*height
        local d=math.sqrt(e*e+s*s)
        if d<1e-6 then snap.target={valid=false,reason="coincident",distanceYards=0,source=source}
        else snap.target={valid=true,bearingWorldRad=bearing(e,s),distanceYards=d,source=source} end
    end
    return snap
end
-- On to step i (the one now begun); your level is where the last one ended.
function N:Advance(i,reason)
    note(string.format("on to step %d: %s",i,reason or "?"))
    local done=self.steps[i-1]
    if done then Routing.Level:Set(done.to.level) end
    self.current,self.off,self.door,self.ahead,self.left,self.farthest=i,0,nil,nil,nil,nil
    -- (the next look counts from where you are: a lift on one spot is through only once you walk off it, already some
    -- yards along the next leg - MOVESLACK would hold you back there; Claude 2026-10-26)
    self.trackXY=nil
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
    local at,locateWhy=self:Locate(cont,px,py)
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
            -- Onto a transition's walked shape (navmesh stairs): at its start, not DOOR yards before it;
            -- its top may lie over the way to it (Claude's walk simulation 2026-10-24, Nissa).
            local nxt=self.steps[i+1]
            if nxt and nxt.kind=="transition" and type(nxt.path)=="table" and #nxt.path>=3 then reach=N.SHAPEEND end
            -- At the walk's end, little of its way left. On a town's level (a ramp round a
            -- tower, its end beside its start on the map) only by the way left (Florian
            -- 2026-10-20, Crossroads tower: at the foot the guide said "arrived").
            -- The goal you can talk to (soft interact on it, Florian 2026-10-25: at Harick's counter it named him, at
            -- the stair's foot a guard): there.
            -- Not by that alone (Florian 2026-10-26, Goldshire to Allison: with SoftTargetInteractRange 60 the client named
            -- her 42 yd before, outside the inn, "interact range false"; in front of her true. Arrived means you can
            -- talk to her, a controller talks by the soft target): the client's interact distance on it
            -- (N.SoftInRange) decides, false is no arrival at all; where it cannot be asked, the goal or the way's
            -- end SOFTNEAR yd from you and at most SOFTNEAR yd of the way left.
            if to.kind=="goal" and N.SoftOnGoal(self.goal) then
                local inRange=N.SoftInRange()
                if inRange==true then return self:Advance(i+1,"the goal is your interact target, within reach") end
                if inRange==false then
                    if at.piece.j>(self.ahead or 0) then self.ahead=at.piece.j;self:Show() end
                    return
                end
                if inRange==nil and at.left<=N.SOFTNEAR then
                    local e=type(step.path)=="table" and step.path[#step.path]
                    local g=self.goal
                    local dg=(g and g.x and N.Yards(cont,px,py,g.x,g.y)) or math.huge
                    local de=e and N.Yards(cont,px,py,e[1],e[2]) or math.huge
                    if math.min(dg,de)<=N.SOFTNEAR then return self:Advance(i+1,"the goal is your interact target") end
                end
            end
            if N.IsTownLevel(step.from.level) or step.navmesh then
                -- (on a navmesh walk also near its end on the map: the goal's reach point)
                local e=type(step.path)=="table" and step.path[#step.path]
                local endOk=not step.navmesh or not e or N.Yards(cont,px,py,e[1],e[2])<=N.ENDNEAR
                if at.left<=N.TOWNSTEP and endOk then return self:Advance(i+1,string.format("%d yd of the walk's way left",math.floor(at.left))) end
            elseif near(to,reach) and at.left<=reach+N.DOOR then return self:Advance(i+1,string.format("within %d yd of the walk's end",reach)) end
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
    if locateWhy=="progressMismatch" then
        note("progress mismatch: planning the whole way anew from here")
        Routing:Print("Rejoining the way from where you are.")
    else
        note("off the way: planning the whole way anew from here")
        Routing:Print("Off the way: planning anew from where you are.")
    end
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

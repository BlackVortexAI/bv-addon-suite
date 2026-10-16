local _,N=...
if not N.ready then return end
-- Quest navigation (Florian 2026-10-15): where a quest's objectives and its
-- turn-in are, from QuestieDB when it is installed (read only, nothing of it
-- is shipped), and BV Routing leads you there. Spawn points close together
-- become one spot; the spots of an objective form a round from the nearest
-- one, and asking again leads to the next spot (spot by spot), since the
-- creatures of one place are often killed or taken already.
local ns=N.ns
local QB={cache={},walks={}}
N.Questie=QB
QB.SPOT=60        -- yards: spawn points this close form one spot
QB.MAXSPOTS=40    -- spots of one objective at most (the nearest ones)
QB.MAXSOURCES=8   -- creatures or objects that drop an item, at most (those with a place)
QB.MAXLOOK=64     -- sources looked at, at most: the first ones of a long list may have no place

local function lib() return rawget(_G,"LibQuestieDB") end
local function routing() local R=ns.Routing;return R and R.ready and R.Navigate and R or nil end
local function zoneDB()
    local loader=rawget(_G,"QuestieLoader")
    if type(loader)~="table" or type(loader.ImportModule)~="function" then return nil end
    local ok,zone=pcall(loader.ImportModule,loader,"ZoneDB")
    if ok and type(zone)=="table" and type(zone.GetUiMapIdByAreaId)=="function" then return zone end
    return nil
end
-- Quest navigation works with QuestieDB (contract 4), Questie's zone table and BV Routing.
function QB:Available()
    local L=lib()
    if type(L)~="table" or type(L.RequireContract)~="function" then return false end
    local ok,fits=pcall(L.RequireContract,4)
    return ok and fits==true and zoneDB()~=nil and routing()~=nil
end
-- What is missing, said plainly.
function QB:Missing()
    local L=lib()
    if type(L)~="table" then return "Install Questie (with its QuestieDB): Quest Navigation reads where objectives are from it." end
    local ok,fits=pcall(L.RequireContract,4)
    if not (ok and fits==true) then return "This QuestieDB is too old or too new for Quest Navigation; update Questie or BV Addon Suite." end
    if not zoneDB() then return "Questie's zone table is missing: is Questie itself turned on?" end
    if not routing() then return "BV Routing is needed to lead you there." end
    return nil
end
local function get(entity,id,key)
    if not entity then return nil end
    local ok,value=pcall(entity.Get,id,key)
    return ok and value or nil
end
local function lower(text) return type(text)=="string" and text:lower() or "" end

-- A place on its continent from a map and percent coordinates.
local function place(zone,R,areaID,x,y)
    local okM,map=pcall(zone.GetUiMapIdByAreaId,zone,areaID)
    if not (okM and type(map)=="number" and map>0) then return nil end
    local okC,cont,cx,cy=pcall(R.OnContinent,R,map,x/100,y/100)
    if okC and cont then return {cont=cont,x=cx,y=cy} end
end
-- The entrances of the dungeon an area lies in (Questie's zone table), as
-- {cont,x,y,name}; nil outside dungeons.
local function entrances(zone,R,areaID)
    if type(zone.GetDungeonLocation)~="function" then return nil end
    local ok,locations=pcall(zone.GetDungeonLocation,zone,areaID)
    if not (ok and type(locations)=="table") then return nil end
    local okN,dungeon=false,nil
    if type(zone.GetLocalizedDungeonName)=="function" then okN,dungeon=pcall(zone.GetLocalizedDungeonName,zone,areaID) end
    local name="Entrance"..((okN and type(dungeon)=="string") and (": "..dungeon) or "")
    local out={}
    for _,l in ipairs(locations) do
        if type(l)=="table" and type(l[1])=="number" and type(l[2])=="number" and type(l[3])=="number" then
            local p=place(zone,R,l[1],l[2],l[3])
            if p then p.name=name;out[#out+1]=p end
        end
    end
    return out
end
-- Points of an NPC or object on their continent: {cont,x,y}, and the
-- entrances of the dungeons it is found in (Florian 2026-10-15: dungeon
-- objectives lead to the dungeon's entrance); cached by kind and id.
function QB:Points(kind,id)
    local key=kind..":"..tostring(id)
    local cached=self.cache[key]
    if cached then return cached.points,cached.doors end
    local L,zone,R=lib(),zoneDB(),routing()
    local out,doors,seen={},{},{}
    local entity=L and (kind=="npc" and L.Npc or L.Object)
    local list=entity and get(entity,id,"spawns")
    if type(list)=="table" and zone and R then
        for areaID,points in pairs(list) do
            local before=#out
            local okM,map=pcall(zone.GetUiMapIdByAreaId,zone,areaID)
            if okM and type(map)=="number" and map>0 and type(points)=="table" then
                for _,p in ipairs(points) do
                    if type(p)=="table" and type(p[1])=="number" and type(p[2])=="number" and p[1]>=0 and p[2]>=0 then
                        local okC,cont,cx,cy=pcall(R.OnContinent,R,map,p[1]/100,p[2]/100)
                        if okC and cont then out[#out+1]={cont=cont,x=cx,y=cy} end
                    end
                end
            end
            -- Inside a dungeon (its own map, no place on a continent): its entrance.
            if #out==before and not seen[areaID] then
                seen[areaID]=true
                for _,door in ipairs(entrances(zone,R,areaID) or {}) do doors[#doors+1]=door end
            end
        end
    end
    self.cache[key]={points=out,doors=doors}
    return out,doors
end
local function add(into,points,name)
    for _,p in ipairs(points) do into[#into+1]={cont=p.cont,x=p.x,y=p.y,name=p.name or name} end
end
-- An objective's or the turn-in's places: NPCs, objects, the droppers of an
-- item. Only sources with a place count towards MAXSOURCES (the first ones of
-- a long list may lie in dungeons only); dungeon entrances go to doors.
local function sources(self,into,doors,ids,kind,entity)
    local used,looked=0,0
    for _,id in ipairs(type(ids)=="table" and ids or {}) do
        local source=type(id)=="table" and id[1] or id
        if type(source)=="number" then
            looked=looked+1
            if looked>QB.MAXLOOK or used>=QB.MAXSOURCES then break end
            local points,entry=self:Points(kind,source)
            if #points>0 then used=used+1;add(into,points,get(entity,source,"name")) end
            if doors then add(doors,entry) end
        end
    end
end
local function npcs(self,into,ids,doors) sources(self,into,doors,ids,"npc",lib().Npc) end
local function objects(self,into,ids,doors) sources(self,into,doors,ids,"object",lib().Object) end
local function item(self,into,itemID,doors)
    local L=lib()
    npcs(self,into,get(L.Item,itemID,"npcDrops"),doors)
    objects(self,into,get(L.Item,itemID,"objectDrops"),doors)
    if #into==0 then npcs(self,into,get(L.Item,itemID,"vendors"),doors) end
end
-- Where nothing lies in the open world: the dungeon's entrance (one place per entrance).
local function orDoors(places,doors)
    if #places>0 or #doors==0 then return places end
    local out,seen={},{}
    for _,d in ipairs(doors) do
        local key=d.cont..":"..math.floor(d.x*1000+.5)..":"..math.floor(d.y*1000+.5)
        if not seen[key] then seen[key]=true;out[#out+1]=d end
    end
    return out
end

-- Which QuestieDB entry an objective of the log is: by its name in the
-- objective's text, else by its place among the objectives of its kind.
local SLOT={monster=1,object=2,item=3}
local function match(L,o,entries,entity,seen)
    local text=lower(o.text)
    for n,entry in ipairs(entries) do
        local id=type(entry)=="table" and entry[1] or entry
        local name=lower(get(entity,id,"name"))
        if name~="" and text:find(name,1,true) then return id,n end
    end
    for n,entry in ipairs(entries) do
        if not seen[n] then return type(entry)=="table" and entry[1] or entry,n end
    end
end

-- Targets of a quest: turn-in and one per objective of the log, each
-- {label, places={{cont,x,y,name}}}; nil without QuestieDB or for a quest it does not know.
function QB:Targets(q)
    if not (q and self:Available()) then return nil end
    local L=lib()
    local okE,known=pcall(L.Quest.Exists,q.id)
    if not (okE and known) then return nil end
    local out={objectives={}}
    local finished=get(L.Quest,q.id,"finishedBy")
    if type(finished)=="table" then
        local places,doors={},{}
        npcs(self,places,finished[1],doors);objects(self,places,finished[2],doors)
        local who=places[1] and places[1].name
        if not who then
            local first=type(finished[1])=="table" and finished[1][1]
            who=type(first)=="number" and get(L.Npc,first,"name") or nil
        end
        places=orDoors(places,doors)
        if places[1] then out.turnin={label="Turn in"..(who and (": "..who) or ""),places=places} end
    end
    local o=get(L.Quest,q.id,"objectives") or {}
    local seen={{},{},{}}
    for index,objective in ipairs(q.objectives or {}) do
        if not objective.finished then
            local places,doors={},{}
            local slot=SLOT[objective.type]
            if slot==1 and type(o[1])=="table" then
                local id,n=match(L,objective,o[1],L.Npc,seen[1])
                if id then seen[1][n]=true;npcs(self,places,{id},doors) end
            elseif slot==2 and type(o[2])=="table" then
                local id,n=match(L,objective,o[2],L.Object,seen[2])
                if id then seen[2][n]=true;objects(self,places,{id},doors) end
            elseif slot==3 and type(o[3])=="table" then
                local id,n=match(L,objective,o[3],L.Item,seen[3])
                if id then seen[3][n]=true;item(self,places,id,doors) end
            end
            -- Kill credit (several creatures count for one), then the place to reach.
            if #places==0 and type(o[5])=="table" and type(o[5][1])=="table" then npcs(self,places,o[5][1],doors) end
            if #places==0 and objective.type=="event" then
                local trigger=get(L.Quest,q.id,"triggerEnd")
                local zone,R=zoneDB(),routing()
                for areaID,points in pairs(type(trigger)=="table" and type(trigger[2])=="table" and trigger[2] or {}) do
                    local before=#places
                    local okM,map=pcall(zone.GetUiMapIdByAreaId,zone,areaID)
                    for _,p in ipairs(okM and type(map)=="number" and type(points)=="table" and points or {}) do
                        local okC,cont,cx,cy=pcall(R.OnContinent,R,map,p[1]/100,p[2]/100)
                        if okC and cont then places[#places+1]={cont=cont,x=cx,y=cy,name=trigger[1]} end
                    end
                    if #places==before then add(doors,entrances(zone,R,areaID) or {}) end
                end
            end
            places=orDoors(places,doors)
            if #places>0 then out.objectives[index]={label=objective.text,places=places} end
        end
    end
    return out
end

-- Spots: places within SPOT yards of each other become one (their middle).
function QB:Spots(places)
    local R=routing()
    local spots={}
    for _,p in ipairs(places) do
        local joined
        for _,s in ipairs(spots) do
            if s.cont==p.cont and R.Navigate.Yards(p.cont,s.x,s.y,p.x,p.y)<=self.SPOT then joined=s;break end
        end
        if joined then
            joined.count=joined.count+1
            joined.x=joined.x+(p.x-joined.x)/joined.count;joined.y=joined.y+(p.y-joined.y)/joined.count
        else spots[#spots+1]={cont=p.cont,x=p.x,y=p.y,count=1,name=p.name} end
    end
    return spots
end
-- A round through the spots from the nearest one: nearest neighbour, then
-- 2-opt, by the straight line (the way itself is Routing's).
function QB:Round(spots,cont,x,y)
    local R=routing()
    local function far(a,b) if a.cont~=b.cont then return math.huge end;return R.Navigate.Yards(a.cont,a.x,a.y,b.x,b.y) end
    local here={cont=cont,x=x,y=y}
    local left={}
    for _,s in ipairs(spots) do left[#left+1]=s end
    table.sort(left,function(a,b) return far(here,a)<far(here,b) end)
    while #left>self.MAXSPOTS do table.remove(left) end
    local order,at={},here
    while #left>0 do
        local best,bestD=1,math.huge
        for i,s in ipairs(left) do local d=far(at,s);if d<bestD then best,bestD=i,d end end
        at=table.remove(left,best);order[#order+1]=at
    end
    -- 2-opt on the round (back to the first spot).
    local n=#order
    local improved=n>3
    local guard=0
    while improved and guard<20 do
        improved=false;guard=guard+1
        for i=1,n-2 do
            for j=i+2,n do
                local a,b,c,d=order[i],order[i+1],order[j],order[j%n+1]
                if d~=a and far(a,c)+far(b,d)<far(a,b)+far(c,d)-1 then
                    local lo,hi=i+1,j
                    while lo<hi do order[lo],order[hi]=order[hi],order[lo];lo,hi=lo+1,hi-1 end
                    improved=true
                end
            end
        end
    end
    return order
end

-- Leads to a target: the nearest spot first; asked again for the same
-- target, the next spot of the round (Florian 2026-10-15).
function QB:Lead(q,key,target)
    local R=routing()
    if not (R and target) then return false end
    local walkKey=q.id..":"..key
    local walk=self.walks[walkKey]
    -- The same walk: Routing still leads it, or you arrived at its spot
    -- (arriving ends Routing's way; clicking again then is the next spot).
    local active=self.active and self.active.walkKey==walkKey
    local leading=R.Navigate.goal and R.Navigate.goal.questWalk==walkKey
    if walk and walk.active and (leading or (active and self.active.arrived and not R.Navigate.goal)) then
        walk.index=self:NextIndex(walk,1)
    else
        local mapID,x,y=R:Position()
        local cont,cx,cy
        if mapID then cont,cx,cy=R:OnContinent(mapID,x,y) end
        local spots=self:Spots(target.places)
        walk={spots=cont and self:Round(spots,cont,cx,cy) or spots,index=1,active=true}
        self.walks[walkKey]=walk
    end
    walk.label=target.label
    if not self:Go(walk,walkKey) then return false end
    if N.Guide then N.Guide:Started(q,key,walkKey) end
    return true,walk.index,#walk.spots
end
-- The next spot of the round in a direction, past the ones you have
-- already been at (Florian 2026-10-16: the way led back to a spot passed
-- on the way); all visited: the round starts over.
function QB:NextIndex(walk,delta)
    local n=#walk.spots
    walk.visited=walk.visited or {}
    for step=1,n do
        local i=(walk.index-1+delta*step)%n+1
        if not walk.visited[i] then return i end
    end
    walk.visited={}
    return (walk.index-1+delta)%n+1
end
-- Routing leads to the walk's spot at walk.index (also for the spot bar
-- and the spots on the map: any spot of the round).
function QB:Go(walk,walkKey)
    local R=routing()
    local spot=R and walk and walk.spots[walk.index]
    if not spot then return false end
    local name=spot.name or walk.label
    local label=#walk.spots>1 and string.format("%s (spot %d of %d)",walk.label,walk.index,#walk.spots) or walk.label
    R.Navigate:Start({cont=spot.cont,x=spot.x,y=spot.y,name=name,label=label,questWalk=walkKey})
    return true
end
-- The spot a target's walk is at (for the tooltip): index, count.
function QB:Walk(q,key)
    local walk=self.walks[q.id..":"..key]
    if walk then return walk.index,#walk.spots end
end

-- What Quest's details ask (Quest.navigation).
function N:Targets(q) return QB:Targets(q) end
function N:Lead(q,key,target) return QB:Lead(q,key,target) end
function N:Walk(q,key) return QB:Walk(q,key) end
function N:Available() return QB:Available() end
-- Whether QuestieDB knows a quest (cheap: for the tracker's buttons).
function N:Knows(questID)
    local L=lib()
    if type(L)~="table" or not L.Quest then return false end
    local ok,known=pcall(L.Quest.Exists,questID)
    return ok and known==true
end

local _,G=...
if not G.ready then return end
-- Following a route (Florian 2026-10-08): its own layer instead of the Map
-- package's waypoints, so a route with many points stays readable and
-- leaves your waypoints alone. Stops are small dots, the ways round have
-- none; lines with arrows show the way, the leg you walk now in the next
-- target's colour, from you to the next stop. Dynamic: you join at the
-- nearest leg instead of walking to the first point; reaching a point moves
-- on; walking off to another leg on purpose (far from the current one, close
-- to the other, twice in a row) makes that leg the active one, so parts can
-- be skipped (an open PvP fight, a camp taken). Kept across /reload.
local ns=G.ns
local F={}
G.Follow=F
F.ARRIVE=20     -- yards to a point that count as reached
F.OFF=50        -- yards away from the current leg that count as leaving it
F.NEAR=30       -- (kept for the setting's lower end)
F.ON=10         -- yards to the current leg that count as walking on it
F.CLOSER=15     -- yards another leg must be closer than the current one
F.TICK=1
-- Pieces that drop down a cliff (jump here): their own colour.
F.DROP={1,.45,.15}
-- Legs without a way round (only the straight line is known): red.
F.GAP={.95,.2,.25}

function F:State()
    local db=G.Data.db or G.Data:Init()
    return db.follow
end
function F:Active() local s=self:State();return s~=nil and type(s.points)=="table" and #s.points>1 end
-- Starts following a route ({points, loop}); joins at the leg nearest to you.
function F:Start(name,route)
    if not (route and type(route.points)=="table" and #route.points>1) then return false end
    local points={}
    for i,point in ipairs(route.points) do points[i]={mapID=point.mapID,x=point.x,y=point.y,stop=point.stop,count=point.count,drop=point.drop,gap=point.gap} end
    G.Data.db.follow={name=name or "Route",points=points,loop=route.loop and true or false,next=2}
    -- Following means gathering: the mode comes on.
    G:Config().mode=true
    self:Join(true)
    self:Watch(true)
    self:Refresh()
    G:Print(string.format("Following %s: %d points%s. /bv gather stop ends it.",G.Data.db.follow.name,#points,route.loop and ", loop" or ""))
    return true
end
function F:Stop()
    if not self:State() then return false end
    G.Data.db.follow=nil
    self:Watch(false);self:Refresh()
    G:Print("Route ended.")
    return true
end
-- Legs: from point i-1 to point i (and, in a loop, from the last to the first).
function F:LegCount()
    local s=self:State()
    return s.loop and #s.points or #s.points-1
end
function F:Leg(n)
    local s=self:State()
    local to=n+1
    if to>#s.points then to=1 end
    return s.points[n],s.points[to],to
end
-- Your position and a point on your map in yards (nil when not on one map).
local function yards(mapID,width,height,point)
    local x,y=ns.MapPins:OnMap(point,mapID,true)
    if not x then return nil end
    return x*width,y*height
end
function F:Where()
    local mapID,x,y=G.Record:Position()
    if not mapID then return nil end
    local width,height=G.Call("C_Map.GetMapWorldSize",mapID)
    if type(width)~="number" or width<=0 then return nil end
    return mapID,width,height,x*width,y*height
end
-- Distance from (px,py) to the segment a-b, all in yards.
local function segment(px,py,ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    local len=dx*dx+dy*dy
    local t=len>0 and math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/len)) or 0
    local qx,qy=ax+dx*t,ay+dy*t
    return math.sqrt((px-qx)^2+(py-qy)^2)
end
function F:LegDistance(n,mapID,width,height,px,py)
    local a,b=self:Leg(n)
    local ax,ay=yards(mapID,width,height,a)
    local bx,by=yards(mapID,width,height,b)
    if not (ax and bx) then return math.huge end
    return segment(px,py,ax,ay,bx,by)
end
-- The legs in yards on one map, worked out once per route and map: the
-- check every second is then plain arithmetic (Florian 2026-10-09: frame
-- drops with long routes).
function F:Legs(mapID,width,height)
    local s=self:State()
    local cache=self.legs
    if cache and cache.points==s.points and cache.map==mapID and cache.loop==s.loop then return cache end
    cache={points=s.points,map=mapID,loop=s.loop}
    for n=1,self:LegCount() do
        local a,b=self:Leg(n)
        local ax,ay=yards(mapID,width,height,a)
        local bx,by=yards(mapID,width,height,b)
        if ax and bx then cache[n]={ax,ay,bx,by,math.min(ax,bx),math.max(ax,bx),math.min(ay,by),math.max(ay,by)} else cache[n]=false end
    end
    self.legs=cache
    return cache
end
-- The nearest leg within the joining range (a leg whose box lies farther
-- away is skipped without measuring).
function F:Nearest(mapID,width,height,px,py,range)
    local legs=self:Legs(mapID,width,height)
    local best,bestDistance
    for n,leg in ipairs(legs) do
        if leg and px>=leg[5]-range and px<=leg[6]+range and py>=leg[7]-range and py<=leg[8]+range then
            local d=segment(px,py,leg[1],leg[2],leg[3],leg[4])
            if d<=range and (not bestDistance or d<bestDistance) then best,bestDistance=n,d end
        end
    end
    return best,bestDistance
end
-- Joins the nearest leg: its end becomes the next target. force: always
-- (on start, at any distance); else only when far from the current leg and
-- near another, and only legs within the joining range count.
function F:Join(force)
    local s=self:State()
    local mapID,width,height,px,py=self:Where()
    if not mapID then return false end
    local current=s.next-1;if current<1 then current=s.loop and #s.points or 1 end
    local legs=self:Legs(mapID,width,height)
    local onCurrent=math.huge
    if not force then
        -- Right on the current leg: nothing to look for.
        local leg=legs[current]
        if leg then onCurrent=segment(px,py,leg[1],leg[2],leg[3],leg[4]) end
        if onCurrent<=F.ON then self.pending=nil;return false end
    end
    local best,bestDistance=self:Nearest(mapID,width,height,px,py,force and math.huge or math.max(F.NEAR,G:Config().followRange))
    if not best then return false end
    local _,_,to=self:Leg(best)
    if force then s.next=to;self.pending=nil;return true end
    if to==s.next then self.pending=nil;return false end
    -- Another leg within the joining range and clearly closer than the
    -- current one: you walk that one now (Florian 2026-10-09: a leg 60 yards
    -- away while the current one was 150 away did not count before).
    if bestDistance+F.CLOSER<onCurrent then
        -- Twice in a row: a deliberate change, not a step aside.
        if self.pending==to then s.next=to;self.pending=nil;self:Refresh();return true end
        self.pending=to
    else self.pending=nil end
    return false
end
-- Reached the next point: on to the one after it (a loop starts over).
function F:Check()
    local s=self:State()
    if not (self:Active() and G:Config().mode) then return self:Watch(false) end
    local mapID,width,height,px,py=self:Where()
    if not mapID then return end
    local tx,ty=yards(mapID,width,height,s.points[s.next])
    if tx and math.sqrt((px-tx)^2+(py-ty)^2)<=F.ARRIVE then
        if s.next>=#s.points then
            if not s.loop then G:Print(s.name.." done.");return self:Stop() end
            s.next=1
        else s.next=s.next+1 end
        self.pending=nil
        self:Refresh()
        return
    end
    self:Join(false)
end
function F:Watch(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(F.TICK,function() F:Check() end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end

-- The layer: small dots for stops, nothing for ways round, the next target
-- larger in its colour with the line from you to it.
local function rgb(hex) local r,g,b=ns.UI:RGBA(hex:sub(1,6).."FF");return {r,g,b} end
function F:Points()
    -- Only while the gather mode is on (Florian 2026-10-09).
    if not (G:Active() and self:Active() and G:Config().mode) then return {} end
    local s=self:State()
    local c=G:Config()
    -- Kept until the route, its next point or the look changes: the same
    -- tables let the map remember where they lie on other maps.
    local key=table.concat({tostring(s.points),s.next,tostring(s.loop),c.routeColor,c.routeNextColor,c.routeLineAlpha,c.routeDotAlpha,tostring(c.routeLines),
        G.Hex({G:Style():Color("accent")})},":")
    if self.cached and self.cachedKey==key then return self.cached end
    self.cached,self.cachedKey=self:Build(s,c),key
    return self.cached
end
function F:Build(s,c)
    local route=c.routeColor~="" and rgb(c.routeColor) or {G:Style():Color("accent")}
    local nextColor=rgb(c.routeNextColor)
    local lineAlpha,dotAlpha=c.routeLineAlpha/100,c.routeDotAlpha/100
    if not c.routeLines then lineAlpha=0 end
    local out={}
    for i,point in ipairs(s.points) do
        local isNext=i==s.next
        out[#out+1]={mapID=point.mapID,x=point.x,y=point.y,index=i,dot=true,noPin=not point.stop and not isNext or nil,
            -- The next point as a ring, not to be taken for a tracking dot.
            size=isNext and 14 or 7,hollow=isNext or nil,color=isNext and nextColor or route,alpha=dotAlpha,
            lineColor=(point.gap and F.GAP) or (point.drop and F.DROP) or (isNext and nextColor or route),lineAlpha=lineAlpha,
            lead=isNext or nil,leadColor=nextColor}
    end
    if s.loop then
        local first=s.points[1]
        out[#out+1]={mapID=first.mapID,x=first.x,y=first.y,index=1,noPin=true,lineColor=(first.gap and F.GAP) or (first.drop and F.DROP) or (s.next==1 and nextColor or route),lineAlpha=lineAlpha}
    end
    return out
end
function F:Register()
    if self.registered or not ns.MapPins then return end
    self.registered=true
    ns.MapPins:Register("gather:follow",{points=function() return F:Points() end,lines=true,arrows=true,minimap=true,
        tooltip=function(point)
            local s=F:State()
            if not s then return nil end
            local p=s.points[point.index]
            return s.name,{tag=point.index==s.next and "Next" or ("#"..point.index),
                rows={{"Nodes",tostring(p and p.count or 0)}},hint="/bv gather stop ends the route"}
        end})
end
function F:Refresh() if ns.MapPins then ns.MapPins:Refresh() end end
function F:Enable(context)
    self:Register()
    if self:Active() and G:Config().mode then self:Watch(true) end
    context:Defer(function() F:Watch(false);F:Refresh() end)
    self:Refresh()
end

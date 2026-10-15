local _,C=...
if not C.ready then return end
-- A tour (Florian 2026-10-11: "a warlock trainer, then the zeppelin, then
-- the auction house"): stops in your order. A stop of several places (every
-- warlock trainer) takes the one that makes the whole way shortest, not the
-- nearest: CHOICES nearest places a stop, dynamic programming over the
-- stops, costs in estimated seconds (Routing's travel plan, else the line).
-- "Best order" also tries every order (up to ORDERED stops). Navigate leads
-- with Routing stop after stop; arriving at one starts the next.
local T={stops={}}
C.Tour=T
T.CHOICES=12
T.ORDERED=6
T.DETOUR=1.3       -- a walked way is about this much longer than the line
T.WALK=7           -- yards a second without Routing
T.FAR=36000        -- seconds for a place no way is known to

-- The tour kept for the session and over a reload (entry keys, chosen places).
function T:Store()
    if type(BVCodexDB)~="table" then BVCodexDB={} end
    local db=BVCodexDB
    if type(db.tour)~="table" then db.tour={stops={}} end
    return db.tour
end
function T:Load()
    local saved=self:Store()
    self.stops={}
    for _,s in ipairs(saved.stops or {}) do
        local e=C:Entry(s.key)
        if e then self.stops[#self.stops+1]={entry=e,fixed=s.fixed and e.places[s.fixed] or nil,off=(s.off=="done" or s.off=="manual") and s.off or nil} end
    end
    self.best=saved.best==true
    self:Changed()
end
-- Loaded on first use (Map Data's places are there by then).
function T:Ensure()
    if self.loaded then return end
    self.loaded=true
    self:Load()
end
function T:Save()
    local saved=self:Store()
    saved.stops={}
    for _,s in ipairs(self.stops) do
        local fixed
        if s.fixed then for i,p in ipairs(s.entry.places) do if p==s.fixed then fixed=i end end end
        saved.stops[#saved.stops+1]={key=s.entry.key,fixed=fixed,off=s.off}
    end
    saved.best=self.best or nil
end
function T:Changed()
    self.plan,self.costs=nil,nil
    self:Save()
    if self.Window then self.Window:Refresh() end
    self:ShowMap()
end
-- The tour on the world map and the minimap (while its window is open or
-- it leads): the stops as numbered points joined by a line.
function T:MapPoints()
    local shown=(self.Window and self.Window.window and self.Window.window:IsShown()) or self.running
    if not shown then return {} end
    local plan=self.running and self.running.plan or self:Plan()
    if not plan then return {} end
    local UI=C.ns.UI
    local r,g,b=UI:GameStyle(nil):Color("accent")
    -- Florian 2026-10-11: arrows show the direction; only the leg you walk
    -- now is bright, the legs behind and ahead dimmed (lines that cross
    -- stay readable). Before the start a line leads from you to the first
    -- stop; while led, Routing draws the way to the current stop itself.
    local at=self.running and self.running.at or 1
    local out={}
    for i,p in ipairs(plan.places) do
        local point={mapID=p.cont,x=p.x,y=p.y,dot=true,size=i==at and 18 or 15,color={r,g,b},label=tostring(i),
            lineColor={r,g,b},stop=i,name=p.name}
        if i<at then point.alpha,point.lineAlpha=.35,.15
        elseif i==at then
            point.alpha,point.lineAlpha=1,.15
            if not self.running then point.lead,point.leadColor,point.leadAlpha=true,{r,g,b},1 end
        else point.alpha,point.lineAlpha=.75,i==at+1 and .4 or .25 end
        out[#out+1]=point
    end
    return out
end
function T:ShowMap()
    local pins=C.ns.MapPins
    if not pins then return end
    if not self.registered then
        self.registered=true
        pins:Register("codex:tour",{points=function() return T:MapPoints() end,lines=true,arrows=true,
            tooltip=function(point) return point and point.name,{tag="Tour, stop "..tostring(point and point.stop),hint="/bv tour"} end})
    end
    pins:Refresh()
end
-- A stop: an entry (all its places count), or one place of it.
function T:Add(entry,place)
    if type(entry)~="table" then return false end
    self:Ensure()
    self.stops[#self.stops+1]={entry=entry,fixed=(#entry.places==1 or place) and (place or entry.places[1]) or nil}
    self:Changed()
    return true
end
function T:Remove(i)
    if not self.stops[i] then return false end
    table.remove(self.stops,i)
    self:Changed()
    return true
end
function T:Move(i,by)
    local j=i+by
    if not (self.stops[i] and self.stops[j]) then return false end
    self.stops[i],self.stops[j]=self.stops[j],self.stops[i]
    self:Changed()
    return true
end
-- A stop off (Florian 2026-10-12: reached ones stayed in the tour): "done"
-- when you arrived there, "manual" when switched off by hand; kept in the
-- list, left out of the plan and the leading; switched on again by hand.
function T:Active()
    local out={}
    for _,stop in ipairs(self.stops) do if not stop.off then out[#out+1]=stop end end
    return out
end
function T:SetOff(i,off)
    local stop=self.stops[i]
    if not stop then return false end
    stop.off=off and (off==true and "manual" or off) or nil
    self:Changed()
    return true
end
function T:Toggle(i)
    local stop=self.stops[i]
    if not stop then return false end
    return self:SetOff(i,not stop.off)
end
function T:Clear()
    self.stops={}
    self:Changed()
end
function T:SetBest(on)
    self.best=on and true or nil
    self:Changed()
end

-- Estimated seconds between two points ({cont, x, y, level}): walking on
-- one continent; farther than FLYCHECK yards, or across the sea, Routing's
-- travel plan too (flights, ships, zeppelins), the quicker. Kept for one
-- plan (many stops ask for the same pairs).
T.FLYCHECK=1500
local function costKey(a,b) return string.format("%d:%.4f:%.4f>%d:%.4f:%.4f",a.cont,a.x,a.y,b.cont,b.x,b.y) end
-- The planned times from a to each of list, in one plan (Florian
-- 2026-10-14: one plan for each of a class trainer's places froze the game
-- a moment): kept as Cost would keep them.
function T:Prefill(a,list)
    local R=C.Routing()
    if not (R and R.Navigate.EstimateMany) then return end
    self.costs=self.costs or {}
    local want,keys={},{}
    for _,b in ipairs(list) do
        local key=costKey(a,b)
        if self.costs[key]==nil and not keys[key] and (a.cont~=b.cont or C.Yards(a.cont,a.x,a.y,b.x,b.y)>T.FLYCHECK) then
            keys[key]=true;want[#want+1]=b
        end
    end
    if #want<2 then return end
    local times=R.Navigate:EstimateMany(a,want)
    local speed=R.Navigate:Speed()
    for i,b in ipairs(want) do
        local seconds=times[i] or nil
        local cost
        if a.cont==b.cont then
            cost=C.Yards(a.cont,a.x,a.y,b.x,b.y)*T.DETOUR/speed
            if seconds and seconds<cost then cost=seconds end
        else cost=seconds or T.FAR end
        self.costs[costKey(a,b)]=cost
    end
end
function T:Cost(a,b)
    local R=C.Routing()
    local key=costKey(a,b)
    self.costs=self.costs or {}
    local known=self.costs[key]
    if known then return known end
    local cost=T.FAR
    if a.cont==b.cont then
        local speed=R and R.Navigate:Speed() or T.WALK
        local yards=C.Yards(a.cont,a.x,a.y,b.x,b.y)
        cost=yards*T.DETOUR/speed
        if R and yards>T.FLYCHECK then
            local seconds=R.Navigate:Estimate(a,b)
            if seconds and seconds<cost then cost=seconds end
        end
    elseif R then
        cost=R.Navigate:Estimate(a,b) or T.FAR
    end
    self.costs[key]=cost
    return cost
end
-- The places a stop may take: its own, or the CHOICES nearest to you
-- (those on your continent first).
local function choices(stop,here)
    if stop.fixed then return {stop.fixed} end
    local list={}
    for _,p in ipairs(stop.entry.places) do
        local d=(here and p.cont==here.cont) and C.Yards(p.cont,here.x,here.y,p.x,p.y) or 1e9
        list[#list+1]={p,d}
    end
    table.sort(list,function(a,b) return a[2]<b[2] end)
    local out={}
    for i=1,math.min(#list,T.CHOICES) do out[i]=list[i][1] end
    return out
end
-- The best places for stops in this order from here: {places}, seconds,
-- legs (seconds of each).
local function solve(self,order,here)
    local layers={}
    for i,stop in ipairs(order) do layers[i]=choices(stop,here) end
    local cost,back={},{}
    -- From each place of a layer to all of the next: one plan each.
    for i,layer in ipairs(layers) do
        if i==1 then self:Prefill(here,layer) else for _,q in ipairs(layers[i-1]) do self:Prefill(q,layer) end end
    end
    for i,layer in ipairs(layers) do
        cost[i],back[i]={},{}
        for j,p in ipairs(layer) do
            local best,from
            if i==1 then best=self:Cost(here,p)
            else
                for k,q in ipairs(layers[i-1]) do
                    local c=cost[i-1][k]+self:Cost(q,p)
                    if not best or c<best then best,from=c,k end
                end
            end
            cost[i][j],back[i][j]=best,from
        end
    end
    local n=#layers
    if n==0 then return {},0,{} end
    local best,at
    for j,c in ipairs(cost[n]) do if not best or c<best then best,at=c,j end end
    local places={}
    for i=n,1,-1 do places[i]=layers[i][at];at=back[i][at] end
    local legs,prev={},here
    for i,p in ipairs(places) do legs[i]=self:Cost(prev,p);prev=p end
    return places,best,legs
end
-- Every order of n stops (Heap's algorithm).
local function orders(list,f)
    local a={}
    for i,v in ipairs(list) do a[i]=v end
    local n=#a
    local c={}
    for i=1,n do c[i]=1 end
    f(a)
    local i=1
    while i<=n do
        if c[i]<i then
            if i%2==1 then a[1],a[i]=a[i],a[1] else a[c[i]],a[i]=a[i],a[c[i]] end
            f(a)
            c[i]=c[i]+1
            i=1
        else
            c[i]=1
            i=i+1
        end
    end
end
-- The plan: {order = stops, places, legs, seconds}; nil without a position.
-- Yards you may walk off before the places are chosen anew (Florian
-- 2026-10-11: at the zeppelin tower the plan made far away still chose
-- another zeppelin master than the one 18 yd off). Not while led.
T.MOVED=30
function T:Moved()
    local plan=self.plan
    if not plan or self.running then return false end
    local cont,x,y=C:Here()
    if not cont then return false end
    local h=plan.here
    return h.cont~=cont or C.Yards(cont,h.x,h.y,x,y)>T.MOVED
end
function T:Plan()
    if self.plan and not self:Moved() then return self.plan end
    local cont,x,y,level=C:Here()
    if not cont then return nil end
    local here={cont=cont,x=x,y=y,level=level}
    self.costs={}
    local best
    local function try(order)
        local places,seconds,legs=solve(self,order,here)
        if not best or seconds<best.seconds then
            local copy={}
            for i,s in ipairs(order) do copy[i]=s end
            best={order=copy,places=places,legs=legs,seconds=seconds}
        end
    end
    local active=self:Active()
    if #active==0 then self.plan=nil;return nil end
    if self.best and #active<=T.ORDERED then orders(active,try) else try(active) end
    if best then best.here=here end
    self.plan=best
    return best
end

-- One place now (Shift+Enter in the search): of its places the one with
-- the least estimated time from here; the tour stays as it is.
function T:GoNow(entry)
    local R=C.Routing()
    if not R then C:Print("Leading needs BV Routing: install or enable it.");return false end
    local cont,x,y,level=C:Here()
    if not cont then C:Print("No position here.");return false end
    local here={cont=cont,x=x,y=y,level=level}
    local best,bestCost
    local list=choices({entry=entry},here)
    self:Prefill(here,list)
    for _,p in ipairs(list) do
        local cost=self:Cost(here,p)
        if not bestCost or cost<bestCost then best,bestCost=p,cost end
    end
    if not best then return false end
    if self.running then self:Stop() end
    R.Navigate:Start({cont=best.cont,x=best.x,y=best.y,z=best.z,name=best.name,label=best.label~="" and best.label or entry.name,hostile=C:Hostile(best.cont,best.x,best.y)})
    return true
end
-- Navigate now (the search, Florian 2026-10-12): the tour cleared, only
-- these in it, and led there at once.
function T:Only(entries)
    self:Ensure()
    if self.running then self:Stop() end
    self.stops={}
    for _,e in ipairs(entries) do self.stops[#self.stops+1]={entry=e} end
    self:Changed()
    return self:Navigate()
end
-- Leading: Routing to each stop's place in turn.
function T:Navigate()
    self:Ensure()
    local R=C.Routing()
    if not R then C:Print("Leading needs BV Routing: install or enable it.");return false end
    if #self.stops==0 then C:Print("The tour has no stops yet: search with /bv codex and add some.");return false end
    if #self:Active()==0 then C:Print("Every stop is done or off: switch one on in the tour window.");return false end
    local plan=self:Plan()
    if not plan then C:Print("No position here.");return false end
    self.running={plan=plan,at=1}
    if self.best then
        -- The order found becomes the tour's (the stops off after it).
        local order={}
        for _,stop in ipairs(plan.order) do order[#order+1]=stop end
        for _,stop in ipairs(self.stops) do if stop.off then order[#order+1]=stop end end
        self.stops=order
        self:Save()
    end
    return self:Go()
end
function T:Go()
    local run=self.running
    local R=C.Routing()
    if not (run and R) then return false end
    local p=run.plan.places[run.at]
    local stop=run.plan.order[run.at]
    if not p then self:Finish();return false end
    C:Print(string.format("Stop %d of %d: %s (%s).",run.at,#run.plan.places,p.name,stop.entry.name))
    R.Navigate.onArrive=function(goal) if T.running==run and goal and goal.name==p.name then T:Next() end end
    run.goal=p
    R.Navigate:Start({cont=p.cont,x=p.x,y=p.y,z=p.z,name=p.name,label=p.label~="" and p.label or stop.entry.name,hostile=C:Hostile(p.cont,p.x,p.y)})
    if self.Window then self.Window:Refresh() end
    self:ShowMap()
    return true
end
function T:Next()
    local run=self.running
    if not run then return end
    -- Arrived: that stop is done (still in the list, switched on by hand).
    local stop=run.plan.order[run.at]
    if stop then stop.off="done";self:Save() end
    run.at=run.at+1
    if run.at>#run.plan.places then self:Finish();return end
    -- After the arrival message, on to the next stop.
    C_Timer.NewTimer(.5,function() if T.running==run then T:Go() end end)
end
function T:Finish()
    local R=C.Routing()
    if R and R.Navigate.onArrive then R.Navigate.onArrive=nil end
    if self.running then C:Print("Tour done.") end
    -- The stops done are left out of the next plan.
    self.running,self.plan=nil,nil
    if self.Window then self.Window:Refresh() end
    self:ShowMap()
end
function T:Stop()
    local R=C.Routing()
    if self.running and R then R.Navigate.onArrive=nil;R.Navigate:Stop(true) end
    self.running=nil
    if self.Window then self.Window:Refresh() end
    self:ShowMap()
end
-- Seconds as m:ss or h:mm:ss.
-- Florian 2026-10-11: "1:23" read as hours; the units said.
function T.Clock(seconds)
    seconds=math.floor((seconds or 0)+.5)
    if seconds>=3600 then return string.format("%d h %02d min",math.floor(seconds/3600),math.floor(seconds/60)%60) end
    if seconds>=60 then return string.format("%d min %02d s",math.floor(seconds/60),seconds%60) end
    return seconds.." s"
end

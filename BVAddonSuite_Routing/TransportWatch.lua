local _,R=...
if not R.ready then return end
local T=R.Timetable
-- Passive sampling only: never interact, move, target or send addon messages.
-- A ride requires idle time at a dock, sustained world movement at zero player
-- speed, then an idle stop at the opposite endpoint. Walking/teleports alone
-- cannot establish a timetable. No navmesh/level query on this background path.
-- Deck positions are not the boarding waypoint. Keep all plausible origins;
-- only the opposite physical endpoint may identify the actual connection.
function T:DockCandidates(cont,x,y)
    local out={}
    for _,route in ipairs(R.TRANSPORTS or {}) do
        if route.kind~="tram" then for _,side in ipairs({"a","b"}) do
            local p=route[side]
            if p[1]==cont then
                local d=R.Navigate.Yards(cont,x,y,p[2],p[3])
                if d<=100 then out[#out+1]={route=route,side=side,distance=d} end
            end
        end end
    end
    return out
end
function T:WatchState(state)
    if self.watchState~=state then
        self.watchState=state
        self.watchLog=self.watchLog or {}
        local log=self.watchLog;log[#log+1]=state
        if #log>16 then table.remove(log,1) end
    end
end
function T:Observe(cont,x,y,speed,blocked,now)
    if blocked==true then
        self.sample=nil;self.armed=nil;self.ride=nil;self:WatchState("Not a ship/zeppelin: taxi or vehicle");return
    end
    if blocked=="pause" or not self.Number(speed) or not cont or not (self.Number(x) and self.Number(y)) then
        self.sample=nil;self.armed=nil;self:WatchState("Position unavailable; retaining an existing ride");return
    end
    local prev=self.sample
    self.sample={cont=cont,x=x,y=y,at=now}
    if not prev or now-prev.at>8 or now<=prev.at then self.armed=nil;return end
    local distance=cont==prev.cont and R.Navigate.Yards(cont,x,y,prev.x,prev.y) or nil
    local idle=speed<.1 and distance and distance<.5
    local moving=speed<.1 and distance and distance>=.5 and distance/(now-prev.at)<80
    if self.ride then
        local ride=self.ride
        if now-ride.departure>ride.timeout then self.ride=nil;self:WatchState("Ride expired without a matching destination");return end
        local match,ambiguous
        if idle then for _,candidate in ipairs(ride.candidates) do
            local stop=candidate.route[candidate.side=="a" and "b" or "a"]
            if stop[1]==cont and R.Navigate.Yards(cont,x,y,stop[2],stop[3])<=100 then
                if match then ambiguous=true else match=candidate end
            end
        end end
        if match and not ambiguous then
            ride.stopped=ride.stopped or now
            if now-ride.stopped>=3 then
                -- Publish only after the opposite endpoint corroborates the ride.
                -- Motion on a nearby lift or another vehicle must not change a phase.
                local duration=ride.stopped-ride.departure
                if duration>=20 and duration<=match.route.seconds*.9 then
                    self:Departure(match.route,match.side,ride.departure)
                    self:Arrival(match.route,match.side,ride.departure,ride.stopped)
                    self:WatchState("Recorded: "..match.route[match.side][4].." > "..match.route[match.side=="a" and "b" or "a"][4])
                end
                self.ride=nil;self.armed=nil
            end
        else ride.stopped=nil end
        return
    end
    local nearby=self:DockCandidates(cont,x,y)
    if idle and #nearby>0 then
        if not self.armed then self.armed={candidates=nearby,idle=now} end
        self.armed.ready=now-self.armed.idle>=3
        self.armed.moves=nil;self.armed.departure=nil
        self:WatchState(self.armed.ready and "Ready at dock; waiting for carried movement" or "At dock; waiting for an idle player")
    elseif moving and self.armed and self.armed.ready then
        local arm=self.armed
        arm.moves=(arm.moves or 0)+1;arm.departure=arm.departure or prev.at
        if arm.moves>=3 then
            local timeout=0
            for _,p in ipairs(arm.candidates) do timeout=math.max(timeout,p.route.seconds*1.5) end
            local p=#arm.candidates==1 and arm.candidates[1] or nil
            self.ride={route=p and p.route,side=p and p.side,candidates=arm.candidates,departure=arm.departure,timeout=timeout}
            self.armed=nil
            self:WatchState("Carried movement detected; waiting for the destination")
        end
    else self.armed=nil;self:WatchState("Waiting for an idle player at a dock") end
end
-- DockWatch v1 is optional. Match BOTH physical endpoints and the period,
-- not localized names or an assumed route order (Forever has changed ports).
local function endpoint(ep,stop)
    local p=type(ep)=="table" and ep.position
    if not p or not (T.Number(p.x) and T.Number(p.y)) then return false end
    local c,x,y
    -- Same world-rectangle axis order as tools/build_routing_transports.py.
    if p.instanceId==0 then c=1415;x=(16000-p.y)/35199.900390625;y=(7466.6000976562-p.x)/23466.6000976562
    elseif p.instanceId==1 then c=1414;x=(17066.599609375-p.y)/36799.810546875;y=(12799.900390625-p.x)/24533.200195313 end
    return c==stop[1] and R.Navigate.Yards(c,x,y,stop[2],stop[3])<50
end
function T:ReadDockWatch(api)
    if not (type(api)=="table" and type(api.GetAPIVersion)=="function" and api.GetAPIVersion()==1
        and api.IsReady() and type(api.GetRoutes)=="function") then return {} end
    local now,foreignNow=self:Now(),api.Now()
    if not self.Number(foreignNow) then return {} end
    local out={}
    for _,other in ipairs(api.GetRoutes() or {}) do
        local ends=other.endpoints
        if other.stable and type(ends)=="table" and #ends==2 then
            for _,route in ipairs(R.TRANSPORTS or {}) do
                if route.kind==other.vehicle and route.kind~="tram" then
                    local a,b
                    if endpoint(ends[1],route.a) and endpoint(ends[2],route.b) then a,b=ends[1].id,ends[2].id
                    elseif endpoint(ends[2],route.a) and endpoint(ends[1],route.b) then a,b=ends[2].id,ends[1].id end
                    if a and b then for _,dir in ipairs(other.directions or {}) do
                        local side=(dir.from==a and dir.to==b and "a") or (dir.from==b and dir.to==a and "b")
                        if side and dir.departs==true and dir.lanes==1 and self.Number(dir.period) and math.abs(dir.period-route.seconds)<10
                            and self.Number(dir.trip) and dir.trip>10 and dir.trip<dir.period then
                            local d=api.GetNextDeparture(dir.id)
                            if d and d.state=="scheduled" and self.Number(d.departsAt) and self.Number(d.confirmedAt)
                                and foreignNow-d.confirmedAt>=-5 and foreignNow-d.confirmedAt<=self.TTL then
                                out[self:Key(route,side)]={departure=now+d.departsAt-foreignNow,period=dir.period,trip=dir.trip,
                                    observedAt=now+d.confirmedAt-foreignNow,periodConfirmed=true,approximate=d.approximate==true,
                                    source="DockWatch",dwell=dir.wait}
                            end
                        end
                    end end
                end
            end
        end
    end
    return out
end
function T:Tick()
    local now=self:Now()
    if self.Sync then self.Sync:Tick(now) end
    if not self.externalAt or now-self.externalAt>=5 then
        self.externalAt=now
        local ok,result=pcall(self.ReadDockWatch,self,rawget(_G,"DockWatchAPI"))
        self.external=ok and result or {}
    end
    local wx,wy,_,instance=R.Call("UnitPosition","player")
    local cont,x,y=self:WorldPosition(wx,wy,instance)
    local blocked=false
    for _,call in ipairs({"IsFalling","IsSwimming","UnitOnTaxi","UnitInVehicle","IsFlying"}) do
        local value=R.Call(call,"player")
        if R.Secret(value) then blocked="pause"
        elseif value then
            if call=="IsFalling" or call=="IsSwimming" then blocked="pause" else blocked=true;break end
        end
    end
    self:Observe(cont,x,y,R.Call("GetUnitSpeed","player"),blocked,now)
    if not cont then cont,x,y=self:Position() end -- map fallback is display-only, never movement evidence
    if R.Arrivals then R.Arrivals:Tick(cont,x,y,now) end
end
R.ns.Events:Subscribe(T,"PLAYER_ENTERING_WORLD",function(_,login,reload)
    T:EnterSession(login,reload)
    if not T.ticker then T.ticker=C_Timer.NewTicker(1,function() T:Tick() end) end
end)

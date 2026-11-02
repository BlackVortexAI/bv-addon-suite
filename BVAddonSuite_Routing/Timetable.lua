local _,R=...
if not R.ready then return end
-- One clock and one directional schedule for planning, the guide and the board.
-- A period without a phase is NOT a timetable. No baked-in historical epochs.
local T={models={},external={},peers={},session={},BUFFER=5,TTL=1800}
R.Timetable=T
-- UI preference belongs to this service, not the baked geometry contract.
R.DEFAULTS.transportAutoShow=true
local function number(v) return type(v)=="number" and not R.Secret(v) and v==v and math.abs(v)<1e12 end
T.Number=number
function T:Now()
    if not self.clock then self.clock=(R.Call("GetServerTime") or time())-GetTime() end
    return self.clock+GetTime()
end
function T:Key(route,side)
    if not (route and route.a and route.b and (side=="a" or side=="b")) then return nil end
    return string.format("%s:%d:%.5f:%.5f:%d:%.5f:%.5f:%s",route.kind,route.a[1],route.a[2],route.a[3],route.b[1],route.b[2],route.b[3],side)
end
function T:Store()
    local db=R:Store()
    if type(db.timetables)~="table" or db.timetables.schema~=1 then db.timetables={schema=1,scopes={}} end
    local scope=table.concat({tostring(R.Call("GetCVar","portal") or "?"),tostring(R.Call("GetRealmName") or "?"),tostring(R.Call("GetBuildInfo") or "?")},":")
    local scopes=db.timetables.scopes
    if not scopes[scope] then scopes[scope]={} end
    return scopes[scope]
end
local function owner()
    local guid=R.Call("UnitGUID","player")
    return type(guid)=="string" and not R.Secret(guid) and guid or nil
end
-- Observations are local, never promoted from another addon's data. A new
-- login invalidates phases; a pure UI reload may retain fresh completed ones.
function T:Departure(route,side,at)
    if not number(at) then return end
    local key=self:Key(route,side);if not key then return end
    local records=self:Store();local old=records[key]
    local period=route.seconds
    local confirmed=false
    if old and self.models[key] and number(old.departure) then
        local delta=at-old.departure
        -- Only consecutive cycles: missing several laps is not independent evidence.
        if delta>period*.85 and delta<period*1.15 then period=delta;confirmed=true end
    end
    local m={departure=at,observedAt=at,period=period,periodConfirmed=confirmed,
        trip=old and old.trip or nil,dwell=old and old.dwell or nil,session=self.session,source="BV observation"}
    records[key]={departure=at,observedAt=at,period=period,trip=m.trip,dwell=m.dwell,
        owner=owner(),periodConfirmed=confirmed,reloadEligible=false}
    self.models[key]=m
    local arrived=self.arrivals and self.arrivals[key]
    if arrived and at-arrived>=5 and at-arrived<period*.5 then m.dwell=at-arrived;records[key].dwell=m.dwell end
    return m
end
function T:Arrival(route,fromSide,departure,at)
    local trip=at-departure
    if not number(trip) or trip<20 or trip>route.seconds*.9 then return false end
    local key=self:Key(route,fromSide);local m=key and self.models[key]
    if not m or m.departure~=departure then return false end
    m.trip=trip;m.observedAt=at
    local rec=self:Store()[key];rec.trip=trip;rec.observedAt=at;rec.reloadEligible=true
    self.arrivals=self.arrivals or {}
    self.arrivals[self:Key(route,fromSide=="a" and "b" or "a")]=at
    return true
end
function T:Model(route,side,now)
    local key=self:Key(route,side);if not key then return nil end
    local own,other=self.models[key],self.external[key]
    local function usable(m)
        return m and number(m.departure) and number(m.period) and m.period>=30 and m.period<=1800
            and number(m.trip) and m.trip>=10 and m.trip<m.period and number(m.observedAt)
            and now-m.observedAt>=-5 and now-m.observedAt<=self.TTL
    end
    if usable(own) and own.session==self.session then return own end
    local peer=self.peers[key]
    if usable(peer) and (not usable(other) or peer.observedAt>other.observedAt) then return peer end
    if usable(other) then return other end
end
function T:Quote(route,side,at,models,buffer)
    local now=self:Now()
    local m=models and models[self:Key(route,side)] or (not models and self:Model(route,side,now))
    if not m then return {state="unknown",seconds=(tonumber(route and route.seconds) or 0)*.75,approximate=true,source="average wait + ride"} end
    local ready=at+(buffer or self.BUFFER)
    local departure=m.departure+math.max(0,math.ceil((ready-m.departure)/m.period))*m.period
    return {state="scheduled",departure=departure,arrival=departure+m.trip,seconds=departure-at+m.trip,
        wait=departure-at,trip=m.trip,period=m.period,dwell=m.dwell,source=m.source,
        approximate=not m.periodConfirmed or m.approximate==true}
end
function T:Snapshot()
    -- Frozen for an entire graph search, even when it yields across frames.
    local models={};local now=self:Now()
    for _,r in ipairs(R.TRANSPORTS or {}) do for _,side in ipairs({"a","b"}) do
        local m=self:Model(r,side,now)
        if m then local copy={};for k,v in pairs(m) do copy[k]=v end;models[self:Key(r,side)]=copy end
    end end
    return models,now
end
function T:Incoming(route,side,now)
    local m=self:Model(route,side=="a" and "b" or "a",now)
    if not m then return nil end
    local first=m.departure+m.trip
    local previous=first+math.floor((now-first)/m.period)*m.period
    local departing=self:Model(route,side,now)
    if departing then
        local leaves=departing.departure+math.ceil((now-departing.departure)/departing.period)*departing.period
        if previous<=now and leaves>=now and leaves-previous<m.period*.45 then
            return now,not m.periodConfirmed or m.approximate==true,true
        end
    end
    local at=first+math.max(0,math.ceil((now-first)/m.period))*m.period
    return at,not m.periodConfirmed or m.approximate==true
end
function T:Nearest(cont,x,y,radius,accept)
    if not (cont and number(x) and number(y)) then return nil end
    local best,dist
    for _,r in ipairs(R.TRANSPORTS or {}) do
        if r.kind~="tram" and (not accept or accept(r)) then for _,side in ipairs({"a","b"}) do
            local p=r[side];local boarding=side=="a" and r.boardingA or r.boardingB
            if p[1]==cont then
                local d=R.Navigate.Yards(cont,x,y,boarding and boarding[1] or p[2],boarding and boarding[2] or p[3])
                if d<=radius and (not dist or d<dist) then best={route=r,side=side,key=self:Key(r,side)};dist=d end
            end
        end end
    end
    return best,dist
end
-- A schematic direction from fresh phases, never a live vehicle position.
-- Incomplete or conflicting directional observations must stay neutral.
function T:Journey(route,now)
    local active
    for _,side in ipairs({"a","b"}) do
        local m=self:Model(route,side,now)
        if m then
            local departure=m.departure+math.floor((now-m.departure)/m.period)*m.period
            if now<departure+m.trip then
                if active then return {state="unknown"} end
                active={state="underway",side=side}
            end
        end
    end
    if active then return active end
    local dock
    for _,side in ipairs({"a","b"}) do
        local _,_,docked=self:Incoming(route,side,now)
        if docked then
            if dock then return {state="unknown"} end
            dock={state="docked",side=side}
        end
    end
    return dock or {state="unknown"}
end
function T:Position()
    local map,x,y=R:Position()
    if map then return R:OnContinent(map,x,y) end
end
function T:WorldPosition(x,y,instance)
    if not (number(x) and number(y) and number(instance)) then return end
    if instance==0 then return 1415,(16000-y)/35199.900390625,(7466.6000976562-x)/23466.6000976562 end
    if instance==1 then return 1414,(17066.599609375-y)/36799.810546875,(12799.900390625-x)/24533.200195313 end
end
function T:ResetSession()
    self.session={};self.models={};self.external={};self.peers={};self.ride=nil;self.sample=nil;self.armed=nil;self.arrivals=nil
    self.watchState=nil;self.watchLog=nil
end
function T:EnterSession(login,reload)
    if not (login or reload) then return end -- map/loading transition in the same ride
    self:ResetSession()
    local records=self:Store()
    if login then
        for _,record in pairs(records) do
            if type(record)=="table" then record.reloadEligible=false end
        end
        return
    end
    local now,player=self:Now(),owner()
    for _,route in ipairs(R.TRANSPORTS or {}) do for _,side in ipairs({"a","b"}) do
        local key=self:Key(route,side);local record=records[key]
        -- Legacy records have no eligibility flag: only a completed arrival
        -- (observedAt = departure + trip) can qualify, never a pending departure.
        if type(record)=="table" and record.reloadEligible~=false
            and (not record.owner or record.owner==player)
            and number(record.departure) and number(record.observedAt) and number(record.trip)
            and math.abs(record.observedAt-record.departure-record.trip)<1
            and number(record.period) and math.abs(record.period-route.seconds)<=route.seconds*.15 then
            local m={departure=record.departure,observedAt=record.observedAt,period=record.period,
                trip=record.trip,dwell=number(record.dwell) and record.dwell or nil,
                periodConfirmed=record.periodConfirmed==true,session=self.session,source="BV observation"}
            self.models[key]=m
            if not self:Model(route,side,now) then self.models[key]=nil
            else
                self.arrivals=self.arrivals or {}
                self.arrivals[self:Key(route,side=="a" and "b" or "a")]=m.observedAt
            end
        end
    end end
end
function T:StepQuote(step,at)
    local ride=self.ride
    if ride and ride.route==step.by and ride.side==step.from.transportSide then
        local model=self:Model(ride.route,ride.side,self:Now())
        if model then return {state="riding",arrival=ride.departure+model.trip,seconds=math.max(0,ride.departure+model.trip-at),approximate=true,source=model.source} end
    end
    return self:Quote(step.by,step.from.transportSide,at)
end
function T:GuideText(step)
    local q=self:StepQuote(step,self:Now());local clock=R.Navigate.Clock
    if q.state=="riding" then return "Arrival in "..clock(q.seconds).." (estimate)" end
    q=self:Quote(step.by,step.from.transportSide,self:Now(),nil,0)
    if q.state=="scheduled" then
        return string.format("Departs in %s; ride %s%s",clock(q.wait),clock(q.trip),q.approximate and " (estimate)" or "")
    end
    return "Wait here and ride along. Departure time not known yet."
end

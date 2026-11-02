local _,R=...
if not R.ready then return end
local T=R.Timetable
local S={prefix="BVTransit1",queue={},sent=0,received=0,rejected=0}
T.Sync=S
R.DEFAULTS.transportSharing=true
local function text(v) return type(v)=="string" and not R.Secret(v) and #v>0 and not v:find("[%c]") end
local function hash(value)
    local n=0
    for i=1,#value do n=(n*31+value:byte(i))%2147483647 end
    return tostring(n)
end
function S:Scope()
    local version,build=R.Call("GetBuildInfo")
    local portal,realm,faction=R.Call("GetCVar","portal"),R.Call("GetRealmName"),R.Call("UnitFactionGroup","player")
    if not (text(portal) and text(realm) and text(version) and text(build) and (faction=="Horde" or faction=="Alliance")) then return end
    -- The channel already separates realm/faction. Also separate patch and test/live
    -- realms explicitly; endpoint keys + period validate the route calibration.
    return hash(table.concat({portal,realm,version,build,faction},":"))
end
function S:Queue(message,medium,key)
    if #message>250 then return end
    for _,item in ipairs(self.queue) do
        if item.medium==medium and item.key==key then item.message=message;return end
    end
    if #self.queue<64 then self.queue[#self.queue+1]={message=message,medium=medium,key=key} end
end
function S:Broadcast(message,key)
    if self.channelID then self:Queue(message,"CHANNEL",key) end
    if self.group then self:Queue(message,self.group,key) end
end
function S:Offer(force)
    local now=T:Now();local origin=R.Call("UnitGUID","player")
    if not text(origin) or #origin>64 then return end
    for _,route in ipairs(R.TRANSPORTS or {}) do if route.kind~="tram" then
        for _,side in ipairs({"a","b"}) do
            local key=T:Key(route,side);local m=T.models[key]
            -- Only completed, fresh local observations are published. Peer/DockWatch
            -- samples are never rebroadcast or counted as independent confirmations.
            if m and m.session==T.session and T:Model(route,side,now)==m
                and math.abs(m.observedAt-m.departure-m.trip)<1 then
                local message=table.concat({"1",self.scope,"D",key,string.format("%.3f",m.departure),
                    string.format("%.3f",m.observedAt),string.format("%.3f",m.period),string.format("%.3f",m.trip),
                    string.format("%.3f",m.dwell or 0),m.periodConfirmed and "1" or "0",origin},"\t")
                if force or self.offered[key]~=message then
                    self:Broadcast(message,key);self.offered[key]=message
                end
            end
        end
    end end
end
function S:Receive(prefix,message,medium,sender)
    if R:Config().transportSharing==false or prefix~=self.prefix or not self.scope
        or not (medium=="CHANNEL" or medium=="PARTY" or medium=="RAID") then return end
    if type(message)~="string" or R.Secret(message) then return end
    if #message>250 or message:find("[%z\1-\8\10-\31\127]") then return end
    local fields={};for v in (message.."\t"):gmatch("([^\t]*)\t") do fields[#fields+1]=v end
    if fields[1]~="1" or fields[2]~=self.scope then return end
    local now=T:Now()
    if fields[3]=="Q" and #fields==3 then
        local name=R.Call("UnitName","player")
        if text(sender) and text(name) and (sender==name or sender:sub(1,#name+1)==name.."-") then return end
        -- One bounded response burst, even if many clients query at once.
        if not self.replyAt then
            self.replyAt=math.max(now+2+tonumber(hash(tostring(R.Call("UnitGUID","player") or "")))%5,
                (self.repliedAt or 0)+30)
        end
        return
    end
    if fields[3]~="D" or #fields~=11 then return end
    local key,origin=fields[4],fields[11];local ref=self.routes[key]
    if not ref or not text(origin) or #origin>64 or origin==R.Call("UnitGUID","player") then return end
    local departure,observed,period,trip,dwell=tonumber(fields[5]),tonumber(fields[6]),tonumber(fields[7]),tonumber(fields[8]),tonumber(fields[9])
    if not (T.Number(departure) and T.Number(observed) and T.Number(period) and T.Number(trip) and T.Number(dwell)
        and period>=30 and period<=1800 and math.abs(period-ref.seconds)<=ref.seconds*.15
        and trip>=20 and trip<period*.9 and dwell>=0 and dwell<period*.5
        and math.abs(observed-departure-trip)<1 and now-observed>=-5 and now-observed<=T.TTL
        and (fields[10]=="0" or fields[10]=="1")) then self.rejected=self.rejected+1;return end
    local old=T.peers[key]
    if old and old.observedAt>=observed then return end
    T.peers[key]={departure=departure,observedAt=observed,period=period,trip=trip,dwell=dwell>0 and dwell or nil,
        periodConfirmed=fields[10]=="1",source="BV shared observation",origin=origin}
    self.received=self.received+1;self.lastReceived=now
end
function S:Tick(now)
    if R:Config().transportSharing==false then
        if self.channel then R.Call("LeaveChannelByName",self.channel) end
        self.channel=nil;self.scope=nil;self.queue={};T.peers={};return
    end
    local scope=self:Scope();if not scope then return end
    if self.scope~=scope or self.session~=T.session then
        if self.channel and self.scope~=scope then R.Call("LeaveChannelByName",self.channel) end
        self.scope=scope;self.channel="BVTransit"..scope;self.session=T.session
        self.queue={};self.offered={};self.routes={};self.channelID=nil;self.group=nil
        self.queryAt=nil;self.joinAt=now+5;self.replyAt=nil;self.repliedAt=nil;self.registered=nil
        for _,route in ipairs(R.TRANSPORTS or {}) do if route.kind~="tram" then
            self.routes[T:Key(route,"a")]=route;self.routes[T:Key(route,"b")]=route
        end end
    end
    if not self.registered then
        local result=R.Call("C_ChatInfo.RegisterAddonMessagePrefix",self.prefix)
        local enum=Enum and Enum.RegisterAddonMessagePrefixResult
        self.registered=result==true or result==(enum and enum.Success or 0)
        if not self.registered then self.state="Addon messages unavailable";return end
    end
    local id=R.Call("GetChannelName",self.channel)
    id=T.Number(id) and id>0 and id or nil
    if not id and now>=self.joinAt then R.Call("JoinTemporaryChannel",self.channel);self.joinAt=now+30 end
    if id and self.channelID~=id then
        self.queryAt=nil
        local remove=ChatFrame_RemoveChannel or (ChatFrameUtil and ChatFrameUtil.RemoveChannel)
        if remove then for i=1,(NUM_CHAT_WINDOWS or 10) do
            local frame=_G["ChatFrame"..i];if frame then pcall(remove,frame,self.channel) end
        end end
    end
    self.channelID=id
    local group=R.Call("IsInRaid") and "RAID" or (R.Call("IsInGroup") and "PARTY" or nil)
    if group~=self.group then self.group=group;self.queryAt=nil end
    self.state=id and "Shared channel ready" or (group and "Group only; channel pending" or "Waiting for shared channel")
    if id or group then
        if not self.queryAt or now-self.queryAt>=120 then
            self:Broadcast("1\t"..scope.."\tQ","query");self.queryAt=now;self:Offer(true)
        end
        local reply=self.replyAt and now>=self.replyAt
        self:Offer(reply)
        if reply then self.replyAt=nil;self.repliedAt=now end
    end
    if now<(self.sendAt or 0) then return end
    local item=self.queue[1];if not item then return end
    if item.medium=="CHANNEL" and not id then return end
    if item.medium~="CHANNEL" and item.medium~=group then table.remove(self.queue,1);return end
    local result=R.Call("C_ChatInfo.SendAddonMessage",self.prefix,item.message,item.medium,item.medium=="CHANNEL" and id or nil)
    local enum=Enum and Enum.SendAddonMessageResult
    self.sendAt=now+1
    if result==true or result==(enum and enum.Success or 0) then
        table.remove(self.queue,1);self.sent=self.sent+1;self.lastError=nil
    else self.lastError="Send pending/failed";self.sendAt=now+5 end
end
function S:Status()
    return string.format("Sharing: %s\nSent: %d; received observations: %d; rejected: %d\nQueued: %d%s",
        R:Config().transportSharing==false and "off" or (self.state or "starting"),self.sent,self.received,self.rejected,#self.queue,
        self.lastError and ("\n"..self.lastError) or "")
end
R.ns.Events:Subscribe(T,"CHAT_MSG_ADDON",function(_,...) S:Receive(...) end)

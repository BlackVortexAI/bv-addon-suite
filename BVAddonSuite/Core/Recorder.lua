-- Data-only session journal. Sampling, timers, UI and transport belong to callers.
local _,ns=...
local R={};ns.Recorder=R
local HARD={maxSessions=3,maxRecords=50000,maxSessionRecords=20000,maxBytes=8*1024*1024}
local RESERVE=16384
local function finite(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
local function integer(v,lo,hi) return finite(v) and v==math.floor(v) and v>=lo and v<=hi end
-- Validate all bytes, then cut only at a codepoint boundary.
local function utf8(s,limit)
    local i,n,last=1,#s,0
    while i<=n do
        local b=s:byte(i);local len= b<128 and 1 or b>=194 and b<=223 and 2 or b>=224 and b<=239 and 3 or b>=240 and b<=244 and 4
        if not len or i+len-1>n then return nil end
        for j=i+1,i+len-1 do local c=s:byte(j);if c<128 or c>191 then return nil end end
        local second=s:byte(i+1)
        if len==3 and (b==224 and second<160 or b==237 and second>=160) or len==4 and (b==240 and second<144 or b==244 and second>=144) then return nil end
        if i+len-1<=limit then last=i+len-1 end
        i=i+len
    end
    return s:sub(1,last),last<n
end
function R.New(api,options)
    api,options=api or _G,options or {}
    local self={};local store,storeError,active,lastTime
    local function protected(v)
        local detector=api.issecretvalue or issecretvalue
        if detector then local ok,result=pcall(detector,v);if not ok or type(result)~="boolean" or result then return true end end
        -- The table value may be ordinary while indexing its contents is forbidden.
        -- Check access before any metatable, rawget, iteration or handle classifier.
        if type(v)=="table" then
            local access=api.canaccesstable or canaccesstable
            if access then local ok,result=pcall(access,v);if not ok or type(result)~="boolean" or not result then return true end end
            local tableSecret=api.issecrettable or issecrettable
            if tableSecret then local ok,result=pcall(tableSecret,v);if not ok or type(result)~="boolean" or result then return true end end
        end
        if ns.GraphValues and ns.GraphValues.IsSecret then local ok,result=pcall(ns.GraphValues.IsSecret,v);if not ok or result then return true end end
        return false
    end
    if protected(options) or type(options)~="table" or getmetatable(options) then options={} end
    local limits={}
    for key,max in pairs(HARD) do local v=options[key];limits[key]=not protected(v) and integer(v,1,max) and v or max end
    local keyOption=options.storeKey
    local storeKey=not protected(keyOption) and type(keyOption)=="string" and #keyOption<=80 and keyOption:match("^[%a_][%w_]*$") and keyOption or "BVRecordingDB"
    local function clock(v) return not protected(v) and finite(v) and v>=0 and v<=1e15 end
    local function text(v,max)
        if protected(v) or type(v)~="string" or #v>max then return false end
        return utf8(v,max)~=nil
    end
    local function clean(value,maxNodes,maxBytes,maxString,maxDepth)
        local seen,nodes,bytes={},0,0
        local function walk(v,depth,isKey)
            nodes=nodes+1;if nodes>maxNodes or depth>(maxDepth or 12) then return nil,"limit" end
            if protected(v) then return nil,"protected" end
            local kind=type(v);local size,out
            if kind=="nil" then size=4
            elseif kind=="boolean" then if isKey then return nil,"invalid" end;out=v;size=5
            elseif kind=="number" then
                if not finite(v) or isKey and not integer(v,1,50000) then return nil,"invalid" end
                out=v;size=32
            elseif kind=="string" then
                if #v>(isKey and 80 or maxString) or not utf8(v,#v) or isKey and (v=="" or v:find("[%z\1-\31\127]")) then return nil,"invalid" end
                out=v;size=2+#v*6
            elseif kind=="table" and not isKey then
                if getmetatable(v)~=nil then return nil,"opaque" end
                if seen[v] then return nil,"cycle" end
                seen[v]=true;out={};size=2
                for key,item in next,v do
                    local copiedKey,why=walk(key,depth+1,true);if why then return nil,why end
                    local copied;copied,why=walk(item,depth+1,false);if why then return nil,why end
                    out[copiedKey]=copied;size=size+2
                end
                seen[v]=nil
            else return nil,"opaque" end
            bytes=bytes+size;if bytes>maxBytes then return nil,"limit" end
            return out
        end
        local out,why=walk(value,0,false);return out,why,bytes
    end
    local function copy(value) return clean(value,4096,limits.maxBytes,160) end
    local function array(value,max)
        if type(value)~="table" then return false end
        local n=0;for k in next,value do if not integer(k,1,max) then return false end;n=n+1 end
        for i=1,n do if rawget(value,i)==nil then return false end end
        return true,n
    end
    local function plainSummary(s)
        if not s then return {active=false,status=storeError and "unavailable" or "empty",reason=storeError} end
        return {active=s==active,id=s.id,label=s.label,status=s.status,started=s.started,finished=s.finished,duration=s.duration,reason=s.reason,
            dropped=clean(s.dropped,4096,RESERVE,160),totals=clean(s.totals,4096,RESERVE,160)}
    end
    local function keysOnly(value,allowed)
        if type(value)~="table" then return false end
        for key in pairs(value) do if not allowed[key] then return false end end
        return true
    end
    local function load()
        local raw=api[storeKey]
        if protected(raw) then storeError="invalid store";return end
        if raw==nil then store={schema=1,nextID=1,sessions={}};api[storeKey]=store;return end
        if protected(raw) or type(raw)~="table" or getmetatable(raw) then storeError="invalid store";return end
        local schema=rawget(raw,"schema")
        if protected(schema) or schema~=1 then storeError="unsupported schema";return end
        local candidate,why=clean(raw,600000,limits.maxBytes,160,20)
        if why then storeError="invalid store";return end
        if not keysOnly(candidate,{schema=true,nextID=true,sessions=true}) then storeError="invalid store";return end
        local ok,n=array(candidate.sessions,limits.maxSessions)
        if not ok or not integer(candidate.nextID,1,1e12) then storeError="invalid store";return end
        local total,previousID=0,0
        for i=1,n do
            local s=candidate.sessions[i]
            if not keysOnly(s,{id=true,label=true,status=true,metadata=true,started=true,finished=true,duration=true,events=true,dropped=true,totals=true,reason=true}) or not integer(s.id,1,candidate.nextID-1) or s.id<=previousID or not text(s.label,48) or not clock(s.started)
                or not ({running=true,stopped=true,interrupted=true})[s.status] then storeError="invalid session";return end
            previousID=s.id
            local eventOK,count=array(s.events,limits.maxSessionRecords)
            if not eventOK or type(s.dropped)~="table" or not integer(s.dropped.count,0,1e12) or type(s.dropped.reasons)~="table" or type(s.totals)~="table" then storeError="invalid session";return end
            if not keysOnly(s.dropped,{count=true,reasons=true}) or not keysOnly(s.totals,{events=true,bytes=true}) or s.reason~=nil and not text(s.reason,48) then storeError="invalid session";return end
            local reasons,dropped=0,0;for key,value in pairs(s.dropped.reasons) do reasons=reasons+1;if not text(key,48) or not integer(value,0,1e12) then storeError="invalid gap";return end;dropped=dropped+value end
            if s.dropped.count~=math.min(1e12,dropped) or reasons>17 then storeError="invalid gap";return end
            local _,metadataError=copy(s.metadata);if metadataError then storeError="invalid metadata";return end
            local elapsed,bytes=0,0
            for j=1,count do
                local event=s.events[j]
                if not keysOnly(event,{seq=true,t=true,kind=true,data=true}) or event.seq~=j or not clock(event.t) or event.t<elapsed or not text(event.kind,48) or event.kind=="" or event.data==nil then storeError="invalid event";return end
                local _,eventError,eventBytes=copy(event.data);if eventError then storeError="invalid event";return end
                elapsed=event.t;bytes=bytes+eventBytes+512
            end
            if s.status~="running" and (not clock(s.finished) or s.finished<s.started or not clock(s.duration) or s.duration~=s.finished-s.started or s.duration<elapsed) then storeError="invalid chronology";return end
            if s.status=="running" then s.status="interrupted";s.reason="reload";s.finished=s.started+elapsed;s.duration=elapsed end
            if not integer(s.totals.events,0,limits.maxSessionRecords) or s.totals.events~=count or not integer(s.totals.bytes,0,limits.maxBytes) or s.totals.bytes~=bytes then storeError="invalid totals";return end
            s.totals={events=count,bytes=bytes};total=total+count
        end
        if total>limits.maxRecords then storeError="record limit";return end
        -- Replace only after every structural and chronological check succeeded.
        local accounted=256
        for _,s in ipairs(candidate.sessions) do local _,_,metadataBytes=copy(s.metadata);accounted=accounted+RESERVE+metadataBytes+s.totals.bytes end
        if accounted>limits.maxBytes then storeError="storage limit";return end
        store=candidate;api[storeKey]=store
    end
    load()
    local function usage()
        local records,bytes=0,256
        for _,s in ipairs(store.sessions) do
            local _,_,metadataBytes=copy(s.metadata)
            records=records+#s.events;bytes=bytes+RESERVE+(metadataBytes or 0)+s.totals.bytes
        end
        return records,bytes
    end
    function self:Observe(value)
        if protected(value) then return {status="protected",type="unknown"} end
        local kind=type(value)
        if kind=="nil" then return {status="unavailable",type="nil"} end
        if kind=="number" then return finite(value) and {status="readable",type=kind,value=value} or {status="invalid",type=kind} end
        if kind=="boolean" then return {status="readable",type=kind,value=value} end
        if kind=="string" then
            local clipped,truncated=utf8(value,160)
            if not clipped then return {status="invalid",type=kind} end
            return {status="readable",type=kind,value=clipped,truncated=truncated or nil}
        end
        return {status="opaque",type=kind}
    end
    function self:Now()
        local fn=api.GetTimePreciseSec or api.GetTime
        if type(fn)~="function" then return nil end
        local ok,value=pcall(fn);if ok and clock(value) then return value end
    end
    function self:Store() return store,storeError end
    function self:Start(label,metadata)
        if not store then return nil,storeError end
        if active then return nil,"already active" end
        if not text(label,48) then return nil,"invalid label" end
        local now=self:Now();if not now then return nil,"invalid clock" end
        local frozen,why=copy(metadata);if why then return nil,"invalid metadata" end
        if store.nextID>=1e12 then return nil,"id limit" end
        if #store.sessions>=limits.maxSessions then return nil,"session limit" end
        local records,bytes=usage();local _,_,metadataBytes=copy(metadata)
        if records>=limits.maxRecords or bytes+RESERVE+metadataBytes>limits.maxBytes then return nil,"storage limit" end
        active={id=store.nextID,label=label,status="running",metadata=frozen,started=now,events={},dropped={count=0,reasons={}},totals={events=0,bytes=0}}
        store.nextID=store.nextID+1;store.sessions[#store.sessions+1]=active;lastTime=now
        return self:Get(active.id)
    end
    local function finish(reason,now)
        local s=active;if not s then return nil end
        s.status="stopped";s.reason=text(reason,48) and reason or "stopped";s.finished=now;s.duration=now-s.started
        active,lastTime=nil,nil;return s
    end
    local function timestamp(observedAt)
        local now=observedAt
        if protected(now) then finish("invalid clock",lastTime);return nil,"invalid clock" end
        if now==nil then now=self:Now() end
        if not clock(now) then finish("invalid clock",lastTime);return nil,"invalid clock" end
        if now<lastTime then finish("backward clock",lastTime);return nil,"backward clock" end
        return now
    end
    function self:Gap(reason,count)
        if not active then return false,"inactive" end
        local now,why=timestamp();if not now then return false,why end
        lastTime=now
        reason=text(reason,48) and reason or "unspecified"
        count=not protected(count) and integer(count,1,1e12) and count or 1
        local reasons=active.dropped.reasons;local n=0;for _ in pairs(reasons)do n=n+1 end
        if not reasons[reason] and n>=16 then reason="other" end
        reasons[reason]=math.min(1e12,(reasons[reason] or 0)+count);active.dropped.count=math.min(1e12,active.dropped.count+count)
        local records,bytes=usage();local data={reason=reason,count=count};local _,_,size=copy(data);size=size+512
        if #active.events<limits.maxSessionRecords and records<limits.maxRecords and bytes+size<=limits.maxBytes then
            local seq=#active.events+1;active.events[seq]={seq=seq,t=lastTime-active.started,kind="gap",data=data}
            active.totals.events=seq;active.totals.bytes=active.totals.bytes+size
        end
        return true
    end
    function self:Append(kind,data,observedAt)
        if not active then return false,"inactive" end
        local now,why=timestamp(observedAt);if not now then return false,why end
        if not text(kind,48) or kind=="" then self:Gap("invalid kind");return false,"invalid kind" end
        if data==nil then data=self:Observe(nil) end
        local frozen,size;frozen,why,size=copy(data)
        if why then self:Gap("invalid data");return false,"invalid data" end
        size=size+512
        local records,bytes=usage()
        if #active.events>=limits.maxSessionRecords or records>=limits.maxRecords or bytes+size>limits.maxBytes then self:Gap("storage limit");return false,"storage limit" end
        local seq=#active.events+1;active.events[seq]={seq=seq,t=now-active.started,kind=kind,data=frozen}
        active.totals.events=seq;active.totals.bytes=active.totals.bytes+size;lastTime=now
        return true
    end
    function self:Stop(reason)
        if not active then return nil,"inactive" end
        local now,why=timestamp();if not now then return self:Get(),why end
        local s=finish(reason,now);return self:Get(s.id)
    end
    function self:Status() return plainSummary(active or store and store.sessions[#store.sessions]) end
    function self:Get(id)
        if not store then return nil,storeError end
        if protected(id) or id~=nil and not integer(id,1,1e12) then return nil,"invalid id" end
        for i=#store.sessions,1,-1 do local s=store.sessions[i];if id==nil or s.id==id then return clean(s,600000,limits.maxBytes,160,20) end end
        return nil,"not found"
    end
    function self:Clear()
        if active then return false,"active" end
        if not store then return false,storeError end
        store={schema=1,nextID=store.nextID,sessions={}};api[storeKey]=store;return true
    end
    return self
end

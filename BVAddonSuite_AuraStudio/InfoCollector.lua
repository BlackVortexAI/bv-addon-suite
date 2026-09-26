-- Session-only observation cache. Existing adapters publish; no polling or prediction.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local C={};C.__index=C;A.InfoCollector=C
local MAX_ENTRIES,MAX_FIELDS,MAX_HISTORY=128,32,256
function C.New(api)
    api=api or _G
    -- Recorder's storage remains private to this classifier, never SavedVariables.
    local isolated={issecretvalue=api.issecretvalue,canaccesstable=api.canaccesstable,issecrettable=api.issecrettable,GetTime=api.GetTime}
    return setmetatable({api=api,observer=ns.Recorder.New(isolated),entries={},order={},ring={},sequence=0},C)
end
function C:Field(value) return self.observer:Observe(value) end
function C:Key(value)
    local f=self:Field(value)
    return f.status=="readable" and f.type=="string" and not f.truncated and #f.value<=80
        and f.value:match("^[%w_:%-%.]+$") and f.value or nil
end
function C:Now()
    local ok,value=pcall(self.api.GetTime or GetTime)
    local field=ok and self:Field(value)
    if field and field.status=="readable" and field.type=="number" and field.value>=0 then return field.value end
end
local function clone(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value) do out[key]=clone(item) end;return out
end
function C:Publish(source,scope,values,quality)
    source,scope=self:Key(source),self:Key(scope)
    if not source or not scope then return false,"invalid scope" end
    local top=self:Field(values)
    if top.status=="protected" or type(values)~="table" or getmetatable(values) then return false,"unreadable fields" end
    local fields,count,readable,protected={},0,0,0
    for key,value in pairs(values) do
        count=count+1;if count>MAX_FIELDS then return false,"field limit" end
        local name=self:Key(key);if not name then return false,"invalid field" end
        local field=self:Field(value);fields[name]=field
        if field.status=="readable" then readable=readable+1 elseif field.status=="protected" then protected=protected+1 end
    end
    local q=self:Key(quality)
    if not ({observed=true,unknown=true,protected=true,unavailable=true})[q or ""] then q=nil end
    q=q or (protected>0 and (readable>0 and "mixed" or "protected") or readable>0 and "observed" or "unknown")
    if protected>0 and q=="observed" then q=readable>0 and "mixed" or "protected" end
    local key=source.."/"..scope
    if not self.entries[key] then
        if #self.order>=MAX_ENTRIES then self.entries[table.remove(self.order,1)]=nil end
        self.order[#self.order+1]=key
    end
    local now=self:Now()
    local row={source=source,scope=scope,observedAt=now,quality=now and q or "unknown",fields=fields}
    self.entries[key]=row
    if self.recording then
        self.sequence=self.sequence+1
        self.ring[(self.sequence-1)%MAX_HISTORY+1]={sequence=self.sequence,source=source,scope=scope,observedAt=row.observedAt,quality=q}
    end
    return true
end
function C:Read(source,scope,maxAge)
    source,scope=self:Key(source),self:Key(scope)
    local row=source and scope and self.entries[source.."/"..scope]
    if not row then return {quality="unknown",fields={}} end
    local out=clone(row);local now=self:Now()
    if not now or not out.observedAt or now<out.observedAt then out.observedQuality=out.quality;out.quality="unknown";return out end
    out.age=now-out.observedAt
    local f=self:Field(maxAge)
    local ageLimit=f.status=="readable" and f.type=="number" and f.value>=0 and f.value or 5
    if out.age>ageLimit then out.observedQuality=out.quality;out.quality="stale" end
    return out
end
-- Adapter result contract: {values={scalar fields},fields={field=status},status=...}.
-- Select a deterministic bounded projection, preserving status-only unavailable fields.
function C:PublishObservation(source,scope,observation)
    local function plain(value)
        return self:Field(value).status~="protected" and type(value)=="table" and getmetatable(value)==nil
    end
    if not plain(observation) then return false,"unreadable observation" end
    local values=plain(observation.values) and observation.values or {}
    local statuses=plain(observation.fields) and observation.fields or {}
    local names,seen={},{};local scanned,truncated=0,false
    for _,map in ipairs({values,statuses}) do
        for key in pairs(map) do
            scanned=scanned+1
            if scanned>256 then truncated=true;break end
            local name=self:Key(key)
            if name and not seen[name] then seen[name]=true;names[#names+1]=name end
        end
        if scanned>256 then break end
    end
    -- Oversized untrusted maps have no deterministic full key set; omit instead of
    -- choosing a random pairs() prefix and expose truncation explicitly.
    if scanned>256 then names={} else table.sort(names) end
    local projection={}
    for i=1,math.min(MAX_FIELDS,#names) do local name=names[i];projection[name]=values[name] end
    truncated=truncated or #names>MAX_FIELDS
    local ok,why=self:Publish(source,scope,projection)
    if not ok then return ok,why end
    local row=self.entries[source.."/"..scope]
    local status=self:Field(observation.status)
    if status.status=="readable" and status.type=="string" then row.sourceStatus=status.value end
    row.truncated=truncated or nil
    for i=1,math.min(MAX_FIELDS,#names) do
        local name=names[i];local field=row.fields[name] or self:Field(nil);row.fields[name]=field
        local s=self:Field(statuses[name])
        if s.status=="readable" and s.type=="string" then
            field.sourceStatus=s.value
            if s.value=="protected" then field.status="protected";field.type="unknown";field.value=nil end
        end
    end
    local readable,hidden=0,0
    for _,field in pairs(row.fields) do
        if field.status=="readable" then readable=readable+1 elseif field.status=="protected" then hidden=hidden+1 end
    end
    row.quality=not row.observedAt and "unknown" or row.sourceStatus=="protected" and "protected"
        or hidden>0 and (readable>0 and "mixed" or "protected") or readable>0 and "observed" or "unknown"
    if self.recording then self.ring[(self.sequence-1)%MAX_HISTORY+1].quality=row.quality end
    return true
end
function C:Summary()
    local out={count=#self.order,historyCount=math.min(self.sequence,MAX_HISTORY),recording=self.recording==true,sources={}}
    for _,key in ipairs(self.order) do
        local row=self.entries[key];local summary=out.sources[row.source] or {count=0}
        summary.count=summary.count+1
        if not summary.time or row.observedAt and row.observedAt>=summary.time then
            summary.lastStatus=row.sourceStatus or row.quality;summary.time=row.observedAt
        end
        out.sources[row.source]=summary
    end
    return out
end
function C:SetRecording(enabled) local f=self:Field(enabled);self.recording=f.status=="readable" and f.type=="boolean" and f.value==true end
function C:History()
    local out={}
    for seq=math.max(1,self.sequence-MAX_HISTORY+1),self.sequence do out[#out+1]=clone(self.ring[(seq-1)%MAX_HISTORY+1]) end
    return out
end
function C:Clear() self.entries={};self.order={};self.ring={};self.sequence=0 end
A.infoCollector=C.New()

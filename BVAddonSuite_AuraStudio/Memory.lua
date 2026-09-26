-- Volatile graph-context memory. No saved state, native access or shared instances.
local _,A=...
if A.blocked then return end
local G=A.G
local M={limit=64,keyBytes=64,valueBytes=1024};A.Memory=M
local types={boolean=true,integer=true,float=true,string=true,timestamp=true}
local function readable(value)local ok,secret=pcall(G.IsSecret,value);return ok and not secret end
function M.Type(kind) return readable(kind) and type(kind)=="string" and types[kind]==true end
function M.Key(key)
    return readable(key) and type(key)=="string" and #key>0 and #key<=M.keyBytes and not key:find("[%c]")
end
function M.Value(kind,value)
    if not readable(value) or not M.Type(kind) then return false end
    if kind=="string" then return type(value)=="string" and #value<=M.valueBytes end
    return G.Accepts(kind,value)
end
function M.Execute(run,operation,kind,key,value,timestamp)
    if run.stopped then return {done=false,success=false,status="inactive"} end
    local store=run.memory
    if operation=="clear" then
        local count=store and store.count or 0;run.memory=nil
        return {done=true,removed=count,status="cleared"}
    end
    if not M.Key(key) then return {done=false,success=false,status="invalid_key"} end
    local entry=store and store.entries[key]
    if operation=="get" then
        if not M.Type(kind) then return {done=false,status="invalid_type"} end
        if not entry then return {done=true,found=false,status="missing"} end
        if entry.kind~=kind then return {done=true,found=true,status="type_mismatch"} end
        return {done=true,found=true,value=entry.value,status="found"}
    elseif operation=="delete" then
        if entry then store.entries[key]=nil;store.count=store.count-1 end
        return {done=true,removed=entry~=nil,status=entry and "deleted" or "missing"}
    elseif operation=="set" then
        if not M.Value(kind,value) then return {done=false,success=false,status="invalid_value"} end
        if timestamp~=nil and not G.Accepts("timestamp",timestamp) then return {done=false,success=false,status="invalid_timestamp"} end
        if not entry and store and store.count>=M.limit then return {done=false,success=false,status="full"} end
        if not store then store={entries={},count=0};run.memory=store end
        if not entry then store.count=store.count+1 end
        store.sequence=(store.sequence or 0)+1
        store.entries[key]={kind=kind,value=value,timestamp=timestamp,sequence=entry and entry.sequence or store.sequence}
        return {done=true,success=true,status="stored"}
    end
    return {done=false,success=false,status="unsupported"}
end
function M.Release(run)
    if not run then return end
    run.memory=nil
    if run.baseRun then run.baseRun.memory=nil end
    for _,child in pairs(run.children or {}) do child.memory=nil end
end

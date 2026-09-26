-- Typed execution-local collections. All edits return independent snapshots.
local _,A=...
if A.blocked then return end
local G=A.G
local F={types={boolean=true,integer=true,float=true,string=true,timestamp=true},limit=64};A.FlowValues=F
function F.Valid(v,kind)
    if type(v)~="table" or getmetatable(v) or v.valueType~=kind or type(v.entries)~="table" or #v.entries>F.limit then return false end
    local seen={}
    for _,e in ipairs(v.entries) do
        if type(e)~="table" or not A.Memory.Key(e.key) or seen[e.key] or not G.Accepts(kind,e.value)
            or e.timestamp~=nil and not G.Accepts("timestamp",e.timestamp) then return false end
        seen[e.key]=true
    end
    return true
end
local accepts=G.Accepts
function G.Accepts(kind,value)
    if kind=="timestamp" then return G.Number(value) and value>=0 end
    if type(kind)=="string" and kind:sub(1,6)=="array:" then
        return not BVAddonSuiteCore.GraphValues.Contains(value) and F.types[kind:sub(7)]==true and F.Valid(value,kind:sub(7))
    end
    return accepts(kind,value)
end
local runtimeAccepts=G.RuntimeAccepts
function G.RuntimeAccepts(kind,value)
    if kind=="any" and not G.IsSecret(value) and type(value)=="table" and F.types[value.valueType] then return G.Accepts("array:"..value.valueType,value) end
    return runtimeAccepts(kind,value)
end
local compatible=G.Compatible
function G.Compatible(from,to)
    if from=="nil" and (to=="timestamp" or to:sub(1,6)=="array:") then return true end
    if to=="any" and (from=="timestamp" or from:sub(1,6)=="array:") then return true end
    return compatible(from,to)
end
function F.Sort(array,sort,descending)
    local out=G.Copy(array)
    if sort=="insertion" then return out end
    local indexed={};for i,e in ipairs(out.entries) do indexed[e]=i end
    table.sort(out.entries,function(a,b)
        local x,y=a[sort],b[sort]
        if x==nil and y==nil then return indexed[a]<indexed[b] end
        if x==nil or y==nil then return x~=nil and y==nil end
        if type(x)=="boolean" then x=x and 1 or 0;y=y and 1 or 0 end
        if x==y then return indexed[a]<indexed[b] end
        if descending then return x>y end
        return x<y
    end)
    return out
end
function F.Snapshot(run,kind,keys,sort,descending)
    local selected={};for key in (keys or ""):gmatch("[^,]+") do selected[key:match("^%s*(.-)%s*$")]=true end
    local out={valueType=kind,entries={}}
    for key,e in pairs(run.memory and run.memory.entries or {}) do
        if e.kind==kind and (not next(selected) or selected[key]) then
            out.entries[#out.entries+1]={key=key,value=e.value,timestamp=e.timestamp,sequence=e.sequence or 0}
        end
    end
    table.sort(out.entries,function(a,b) return a.sequence==b.sequence and a.key<b.key or a.sequence<b.sequence end)
    return F.Sort(out,sort,descending)
end
function F.Array(c,array,key,value,timestamp,index)
    local out=G.Copy(array or {valueType=c.valueType,entries={}})
    local position
    for i,e in ipairs(out.entries) do if c.by=="index" and i==index or c.by~="index" and e.key==key then position=i;break end end
    local found=position~=nil;local entry=position and out.entries[position]
    local op=c.operation
    if op=="set" or op=="add" then
        if not A.Memory.Key(key) or not G.Accepts(c.valueType,value) then return nil,"invalid value" end
        if op=="add" and found then return nil,"key already exists" end
        if not found and #out.entries>=F.limit then return nil,"array full" end
        out.entries[position or #out.entries+1]={key=key,value=value,timestamp=timestamp}
    elseif op=="remove" and found then table.remove(out.entries,position)
    elseif op=="clear" then out.entries={}
    elseif op=="sort" then out=F.Sort(out,c.sort,c.descending) end
    return {array=out,count=#out.entries,found=found,value=entry and entry.value,key=entry and entry.key,timestamp=entry and entry.timestamp},"ready"
end

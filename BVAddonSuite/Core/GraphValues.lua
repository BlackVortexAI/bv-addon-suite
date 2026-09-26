-- Runtime-only opaque scalar transport. Persistent copies never retain secrets.
local _,ns=...
local V={}; ns.GraphValues=V
local payloads=setmetatable({},{__mode="k"})
local scalar={float=true,integer=true,boolean=true,string=true,event=true}
local objects={data=true,duration=true,calculator=true,unitref=true,click=true}
local function nativeSecret(value) return issecretvalue and issecretvalue(value) or false end
local function payload(value)
    if nativeSecret(value) then return end
    return type(value)=="table" and payloads[value] or nil
end
function V.IsSecret(value) return nativeSecret(value) or payload(value)~=nil end
-- Presentation metadata only; never exposes the referenced native object.
function V.OpaqueKind(value)
    local ok,held=pcall(payload,value)
    return ok and held and held.object and held.kind or nil
end
-- Use only for internal status metadata, never arbitrary user/client text.
function V.StatusLabel(status)
    if nativeSecret(status) or type(status)~="string" then return "unavailable" end
    return (status:gsub("%f[%a][Pp]rotected%f[%A]","Secret"))
end
function V.Capture(value,kind,detector)
    local held=payload(value)
    if held then assert(held.kind==kind,"Secret value type mismatch"); return value end
    if not (detector or nativeSecret)(value) then return value end
    assert(scalar[kind],"Unsupported secret value type")
    local token=setmetatable({},{__metatable="protected runtime scalar",__tostring=function() return "<secret>" end})
    payloads[token]={value=value,kind=kind}
    return token
end
function V.Accepts(kind,value)
    local held=payload(value)
    return held~=nil and (kind=="any" or held.kind==kind or (held.kind=="integer" and kind=="float"))
end
-- Adapter-owned objects are runtime references, never serializable graph data.
-- Only a schema-aware projection or native renderer may unwrap these handles.
function V.CaptureObject(value,kind)
    assert(objects[kind],"Unsupported runtime object type")
    local token=setmetatable({},{__metatable="opaque runtime object",__tostring=function() return "<opaque>" end})
    payloads[token]={value=value,kind=kind,object=true}
    return token
end
function V.Object(value,kind)
    local held=payload(value)
    if held and held.object and held.kind==kind then return held.value end
end
-- Only the native renderer uses this; no public scalar inspection is provided.
function V.Native(value)
    local held=payload(value)
    if held then return held.value end
    assert(not nativeSecret(value),"Unwrapped secret value")
    return value
end
-- A display-only conversion boundary. Secret arguments are passed to the
-- client's native formatter, never inspected or converted through tostring.
-- The result remains opaque even if a client/mock returns an ordinary string.
function V.FormatDisplay(template,values,count)
    if V.IsSecret(template) or type(template)~="string" or #template>1024
        or V.IsSecret(values) or type(values)~="table" or getmetatable(values)
        or type(count)~="number" or count~=math.floor(count) or count<1 or count>16 then return nil,"invalid format" end
    local parts,arguments={},{}
    local cursor,slots,hidden=1,0,false
    while true do
        local first,last,token=template:find("{([^{}]+)}",cursor)
        if not first then parts[#parts+1]={literal=template:sub(cursor)};break end
        parts[#parts+1]={literal=template:sub(cursor,first-1)}
        local index=token:match("^(%d+)$") or token:match("^value(%d+)$")
        if index and (not tonumber(index) or tonumber(index)<1 or tonumber(index)>16 or tostring(tonumber(index))~=index) then index=nil end
        if index then
            index=tonumber(index)
            if index<1 or index>count then return nil,"input unavailable" end
            slots=slots+1;if slots>64 then return nil,"format limit" end
            local value=values[index]
            local held=payload(value)
            if held then
                if held.object or not ({integer=true,float=true,string=true})[held.kind] then return nil,"protected" end
                hidden=true;parts[#parts+1]={value=value,hidden=true}
            elseif V.IsSecret(value) then return nil,"protected"
            elseif value==nil then return nil,"input unavailable"
            elseif type(value)=="number" then
                if value~=value or math.abs(value)==math.huge then return nil,"invalid value" end
                parts[#parts+1]={literal=tostring(value)}
            elseif type(value)=="string" or type(value)=="boolean" then
                parts[#parts+1]={literal=tostring(value)}
            else return nil,"invalid value" end
        else parts[#parts+1]={literal=template:sub(first,last)} end
        cursor=last+1
    end
    local text={};local size,secretCount=0,0
    for _,part in ipairs(parts) do
        if part.hidden then
            secretCount=secretCount+1
        else
            local literal=part.literal
            -- Plain text reaches a sink which escapes markup. For opaque text
            -- that operation is impossible there, so escape the readable parts now.
            if hidden then literal=literal:gsub("|","||"):gsub("%%","%%%%") end
            part.formatted=literal
            -- Percent escaping adds syntax, not rendered characters.
            size=size+#(hidden and part.literal:gsub("|","||") or part.literal)
            if size>1024 then return nil,"text_too_long" end
        end
    end
    -- Lua 5.1 supports only two precision digits. Reserve a bounded share of
    -- the remaining display budget for each opaque argument (at most 99 bytes).
    local precision=secretCount>0 and math.min(99,math.floor((1024-size)/secretCount)) or 0
    for _,part in ipairs(parts) do
        if part.hidden then
            text[#text+1]="%."..precision.."s"
            arguments[#arguments+1]=payload(part.value).value
        else text[#text+1]=part.formatted end
    end
    local format=table.concat(text)
    if not hidden then return format,"formatted" end
    local ok,result=pcall(string.format,format,unpack(arguments))
    if not ok then return nil,"protected" end
    if not nativeSecret(result) and type(result)~="string" then return nil,"protected" end
    return V.Capture(result,"string",function() return true end),"protected display"
end
local function copy(value,mode,seen)
    if V.IsSecret(value) then
        if mode=="trace" then return nil end
        assert(mode=="runtime" and payload(value),"Secret or opaque values cannot enter graph storage")
        return value
    end
    if type(value)~="table" then return value end
    seen=seen or {}; assert(not seen[value],"Cyclic graph storage"); seen[value]=true
    local out={}
    for key,item in pairs(value) do
        if V.IsSecret(key) then assert(mode=="trace","Secret or opaque table key")
        else out[key]=copy(item,mode,seen) end
    end
    seen[value]=nil; return out
end
function V.Copy(value) return copy(value,"storage") end
function V.RuntimeCopy(value) return copy(value,"runtime") end
function V.TraceCopy(value) return copy(value,"trace") end
function V.Contains(value,seen)
    if V.IsSecret(value) then return true end
    if type(value)~="table" then return false end
    seen=seen or {}; if seen[value] then return false end; seen[value]=true
    for key,item in pairs(value) do if V.IsSecret(key) or V.Contains(item,seen) then return true end end
    return false
end
function V.PlainExcept(value,allowed)
    if V.IsSecret(value) or type(value)~="table" or getmetatable(value) then return false end
    local function plain(item,seen,exceptions)
        if V.IsSecret(item) then return false end
        if type(item)~="table" then return true end
        if getmetatable(item) or seen[item] then return false end
        seen[item]=true
        for key,child in pairs(item) do
            if V.IsSecret(key) then return false end
            local rule=exceptions and exceptions[key]
            if not (type(rule)=="string" and V.Accepts(rule,child))
                and not plain(child,seen,type(rule)=="table" and rule or nil) then return false end
        end
        seen[item]=nil; return true
    end
    for key,item in pairs(value) do
        if V.IsSecret(key) then return false end
        local rule=allowed[key]
        if not (rule and V.Accepts(rule==true and "float" or type(rule)=="string" and rule or "",item))
            and not plain(item,{},type(rule)=="table" and rule or nil) then return false end
    end
    return true
end
function V.Error(value)
    return not V.IsSecret(value) and type(value)=="string" and value or "Operation failed (secret or opaque error)"
end
-- Typed click payloads are opaque runtime snapshots, never graph or trace data.
function V.ClickSchema(schema)
    if schema==nil then return true end
    if not V.PlainExcept(schema,{}) or #schema>8 then return false end
    local seen={}
    for k in pairs(schema) do if type(k)~="number" or k<1 or k>#schema or k~=math.floor(k) then return false end end
    for _,field in ipairs(schema) do
        if type(field)~="table" or type(field.id)~="string" or #field.id>16 or not field.id:match("^value[1-9]%d*$") or seen[field.id]
            or type(field.label)~="string" or #field.label<1 or #field.label>48 or field.label:find("[%c|]")
            or not ({string=true,float=true,integer=true,boolean=true})[field.type] then return false end
        for key in pairs(field) do if key~="id" and key~="label" and key~="type" then return false end end
        seen[field.id]=true
    end
    return true
end
function V.ClickSignature(schema)
    assert(V.ClickSchema(schema),"Invalid click payload schema")
    local out={}
    for _,field in ipairs(schema or {}) do out[#out+1]=field.id..":"..field.type..":"..#field.label..":"..field.label end
    return table.concat(out,";")
end
function V.ClickCapture(schema,values)
    local signature=V.ClickSignature(schema)
    if signature=="" then return end
    local out={}
    for _,field in ipairs(schema) do
        local value=values[field.id]
        assert(value==nil or ns.GraphModel.RuntimeAccepts(field.type,value),"Invalid click payload value")
        out[field.id]=V.RuntimeCopy(value)
    end
    return V.CaptureObject({signature=signature,values=out},"click")
end
function V.ClickRead(handle,schema)
    local signature=V.ClickSignature(schema)
    if signature=="" and handle==nil then return {} end
    local data=V.Object(handle,"click")
    if not data or data.signature~=signature then return end
    return V.RuntimeCopy(data.values)
end

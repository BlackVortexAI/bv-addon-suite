-- Session-only bounded inspection. Never unwrap opaque values or serialize a run.
local _,ns=...
local D={};ns.GraphDebug=D
local V=ns.GraphValues
local function protected(value)
    local ok,secret=pcall(V.IsSecret,value)
    return not ok or secret,not ok
end
local function clean(text,limit)
    return text:sub(1,limit):gsub("|","||"):gsub("[%c]"," ")..(#text>limit and "..." or "")
end
function D.Format(value,signal,observed,expanded)
    if not observed then return "No observation" end
    local opaque=V.OpaqueKind(value)
    if opaque then return "Opaque object / "..opaque end
    local secret,unknown=protected(value)
    if unknown then return "Opaque object / unavailable" end
    if signal=="protected" or secret then return "Secret value" end
    if value==nil then return signal=="nil" and "nil / Nil" or "No value / "..(signal or "unavailable") end
    local remaining=expanded and 20 or 5
    local seen={}
    local function describe(item,depth)
        local opaque=V.OpaqueKind(item)
        if opaque then return "<opaque "..opaque..">" end
        local secret,unknown=protected(item)
        if unknown then return "<opaque object>" end
        if secret then return "<secret>" end
        local kind=type(item)
        if kind=="string" then return '"'..clean(item,expanded and 120 or 64)..'"' end
        if kind=="boolean" then return item and "true" or "false" end
        if kind=="number" then return tostring(item) end
        if kind=="nil" then return "nil" end
        if kind~="table" then return "<"..kind..">" end
        if getmetatable(item) then return "<opaque table>" end
        if seen[item] then return "<cycle>" end
        if depth> (expanded and 2 or 0) or remaining<=0 then return "{...}" end
        seen[item]=true
        local out={};local key,child=next(item)
        while (protected(key) or key~=nil) and remaining>0 do
            if protected(key) then out[#out+1]="<secret or opaque key>";key=nil;break end
            remaining=remaining-1
            out[#out+1]=describe(key,depth+1).."="..describe(child,depth+1)
            key,child=next(item,key)
        end
        if protected(key) or key~=nil then out[#out+1]="..." end
        seen[item]=nil
        return "{"..table.concat(out,", ").."}"
    end
    return describe(value,0):sub(1,1536).." / "..type(value)
end
function D.Contexts(run)
    local options={{value="",label="Select context..."}}
    if run and run.instanceRuntime and not run.stopped then
        for index=1,40 do
            local token="nameplate"..index;local child=run.children[token];local b=run.bindings[token]
            if child and b and not child.stopped and child.instanceGeneration==b.generation and rawequal(child.instance,b.reference) then
                options[#options+1]={value=token,label=token.." / generation "..b.generation}
            end
        end
    end
    return options
end
function D.Select(run,token)
    local b=run and run.bindings and run.bindings[token]
    if b then return {token=token,generation=b.generation,reference=b.reference,run=run} end
end
function D.Observe(run,id,selection)
    local context="Graph";local source=run
    if not run or run.stopped then return {context=context,observed=false} end
    if run.instanceRuntime then
        if run.repeated[id] then
            if not selection then return {context="Select a nameplate context",observed=false} end
            context=selection.token.." / generation "..selection.generation
            local b=run.bindings[selection.token];source=run.children[selection.token]
            if selection.run~=run or not b or not source or source.stopped or b.generation~=selection.generation
                or not rawequal(b.reference,selection.reference) or source.instanceGeneration~=selection.generation
                or not rawequal(source.instance,selection.reference) then
                return {context=context.." / expired - select again",observed=false}
            end
        else source=run.baseRun;context="Shared context" end
    end
    local trace=source and source.trace[id]
    return {context=context,observed=trace~=nil,value=source and source.values[id] and source.values[id].value,
        signal=source and source.signals[id] and source.signals[id].value,at=trace and trace.at}
end

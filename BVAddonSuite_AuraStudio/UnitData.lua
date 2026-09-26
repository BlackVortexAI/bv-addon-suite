-- Shared bounded API engine for graph observations and explicit diagnostic probes.
local _,A=...
if A.blocked then return end
local G,C=A.G,A.UnitDataCatalog
local D={};A.UnitData=D
local unpack=unpack
local function pack(...) return {n=select("#",...),...} end
local handles=setmetatable({},{__mode="k"})
local function bounded(v,default,max)
    return G.Number(v) and math.max(1,math.min(max,math.floor(v))) or default
end
function D.New(api)
    api=api or _G
    local self={}
    local function tableRestricted(value)
        if type(value)~="table" then return false end
        local accessCheck=api.canaccesstable or canaccesstable
        if accessCheck then local ok,result=pcall(accessCheck,value);if not ok or type(result)~="boolean" or not result then return true end end
        local tableCheck=api.issecrettable or issecrettable
        if tableCheck then local ok,result=pcall(tableCheck,value);if not ok or type(result)~="boolean" or result then return true end end
        return false
    end
    local function secret(value)
        local ok,result=pcall(api.issecretvalue or issecretvalue or function()return false end,value)
        if not ok or type(result)~="boolean" or result or tableRestricted(value) then return true end
        local knownOK,known=pcall(G.IsSecret,value)
        return knownOK and known==true
    end
    local function scalar(value,kind,nonnegative)
        if secret(value) then
            -- Restricted table contents are not a scalar payload to cast or expose.
            if tableRestricted(value) then return nil,"protected" end
            local ok,held=pcall(G.Capture,value,kind,api.issecretvalue)
            return ok and held or nil,"protected"
        end
        local primitive=type(value)
        if primitive~="boolean" and primitive~="number" and primitive~="string" then return nil,"unavailable" end
        if not G.Accepts(kind,value) then return nil,"unavailable" end
        if nonnegative and value<0 then return nil,"unavailable" end
        return value,"readable"
    end
    local function access(value,key)
        if secret(value) then return nil,"protected" end
        if value==nil then return nil,"unavailable" end
        local ok,result=pcall(function()return value[key]end)
        if not ok then return nil,"error" end
        return result
    end
    local function lookup(path)
        local value=api
        for key in path:gmatch("[^.]+") do local why;value,why=access(value,key);if why then return nil,why end end
        if secret(value) then return nil,"protected" end
        return type(value)=="function" and value or nil,"unsupported"
    end
    local function execute(fn,context,...)
        if not fn then return nil,"unsupported" end
        if context.calls>=context.limit then context.truncated=true;return nil,"truncated" end
        context.calls=context.calls+1
        local result=pack(pcall(fn,...))
        if not result[1] then return nil,"error" end
        local values={n=result.n-1};for i=2,result.n do values[i-1]=result[i] end
        return values
    end
    local function call(path,context,...)
        local parts={path};local cacheable=true
        for i=1,select("#",...) do
            local value=select(i,...)
            if secret(value) then cacheable=false;break end
            local kind=type(value)
            if kind~="nil" and kind~="string" and kind~="number" and kind~="boolean" then cacheable=false;break end
            parts[#parts+1]=kind..":"..tostring(value)
        end
        local key=cacheable and table.concat(parts,"|")
        context.cache=context.cache or {}
        if key and context.cache[key] then local saved=context.cache[key];return unpack(saved,1,saved.n) end
        local fn,why=lookup(path);if not fn then return nil,why end
        local result=pack(execute(fn,context,...));if key then context.cache[key]=result end
        return unpack(result,1,result.n)
    end
    local function method(object,name,context,...)
        local fn,why=access(object,name)
        if why then return nil,why end
        if secret(fn) or type(fn)~="function" then return nil,"unsupported" end
        return execute(fn,context,object,...)
    end
    local function describe(value,kind,status)
        local out={status=status,type=kind}
        if status=="readable" and not secret(value) then
            if type(value)=="string" then
                local cut=math.min(160,#value)
                if cut<#value then while cut>0 and value:byte(cut+1)>=128 and value:byte(cut+1)<192 do cut=cut-1 end end
                out.value=value:sub(1,cut)
            elseif type(value)=="number" or type(value)=="boolean" then out.value=value end
        end
        return out
    end
    local project
    project=function(raw,schema,context,diagnostic,prefix)
        if secret(raw) then return nil,"protected" end
        if raw==nil then return nil,"unavailable" end
        if type(raw)~="table" and type(raw)~="userdata" then return nil,"unavailable" end
        local data={schema=schema,values={},fields={},records={}}
        local listSchema=({auras="aura",numbers="numbers",controls="control",tooltipLines="tooltipLine"})[schema]
        if listSchema then
            for index=1,context.recordLimit do
                local child,why=access(raw,index)
                if why then data.fields[index]=why;diagnostic[prefix.."["..index.."]"]={status=why,type="data"};break end
                if not secret(child) and child==nil then break end
                if schema=="numbers" then
                    local value,status=scalar(child,"float")
                    data.records[index]={schema="numbers",values={value=value},fields={value=status}}
                    diagnostic[prefix.."["..index.."].value"]=describe(value,"float",status)
                else
                    local rec,status=project(child,listSchema,context,diagnostic,prefix.."["..index.."]")
                    data.records[index]=rec;data.fields[index]=status;diagnostic[prefix.."["..index.."]"]={status=status,type="data"}
                end
            end
        else
            for key,kind in pairs(C.schemas[schema] or {}) do
                local rawValue,why=access(raw,key)
                local value,status
                if why then status=why
                elseif kind=="data" then
                    local nested=C.nestedSchemas[schema] and C.nestedSchemas[schema][key]
                    if nested then
                        local child;child,status=project(rawValue,nested,context,diagnostic,prefix.."."..key)
                        if child then value=G.CaptureObject(child,"data");handles[value]={schema=nested,source=self} end
                    else status=secret(rawValue) and "protected" or "opaque" end
                else value,status=scalar(rawValue,kind) end
                data.values[key]=value;data.fields[key]=status
                diagnostic[prefix.."."..key]=describe(value,kind,status)
            end
            if schema=="tooltip" then
                local projected=data.values.lines and G.Object(data.values.lines,"data")
                data.records=projected and projected.records or {}
            end
        end
        return data,"opaque"
    end
    local function captureObject(raw,field,context,diagnostic)
        if field.type=="duration" or field.type=="calculator" then
            if not secret(raw) and raw==nil then return nil,"unavailable" end
            if not secret(raw) and type(raw)~="table" and type(raw)~="userdata" then return nil,"unavailable" end
            local held=G.CaptureObject(raw,field.type)
            handles[held]={schema=field.type,source=self}
            local methodCache={}
            for key,definition in pairs(context.probe and C.methods[field.type] or {}) do
                local name=type(definition)=="table" and definition.name or definition
                local index=type(definition)=="table" and definition.index or 1
                local cached=methodCache[name];if not cached then cached=pack(method(raw,name,context));methodCache[name]=cached end
                local result,why=unpack(cached,1,cached.n)
                local value,status
                if result then
                    local candidate=result[index]
                    if type(definition)=="table" and definition.path then candidate,why=access(candidate,definition.path) end
                    if why then status=why else value,status=scalar(candidate,C.schemas[field.type][key]) end
                else status=why end
                diagnostic[field.key.."."..key]=describe(value,C.schemas[field.type][key],status)
            end
            return held,secret(raw) and "protected" or "opaque"
        end
        local projected,status
        if field.schema=="geometry" then
            if secret(raw) then return nil,"protected" end
            if raw==nil then return nil,"unavailable" end
            projected={schema="geometry",values={},fields={},records={}}
            for _,spec in ipairs({{"GetCenter",{"x","y"}},{"GetRect",{"left","bottom","width","height"}},{"GetEffectiveScale",{"scale"}},{"IsForbidden",{"forbidden"}}}) do
                local result,why=method(raw,spec[1],context)
                for index,key in ipairs(spec[2]) do
                    local value,state
                    if result then value,state=scalar(result[index],C.schemas.geometry[key]) else state=why end
                    projected.values[key]=value;projected.fields[key]=state
                    diagnostic[field.key.."."..key]=describe(value,C.schemas.geometry[key],state)
                end
            end
            status="opaque"
        else projected,status=project(raw,field.schema,context,diagnostic,field.key) end
        if not projected then return nil,status end
        local held=G.CaptureObject(projected,"data");handles[held]={schema=field.schema,source=self}
        return held,status
    end
    local function run(unit,requested,options,probe)
        options=options or {}
        assert(not secret(unit) and type(unit)=="string","Invalid unit selector")
        local context={calls=0,probe=probe,limit=bounded(options.callLimit or options.maxCalls,200,512),recordLimit=bounded(options.recordLimit,16,40)}
        local result={values={},fields={},entries={},summary={attempted=0,unsupported=0,errors=0,protected=0,truncated=false},unit=unit}
        local start=bounded(options.startEntry,1,#C.entries);local finish=math.min(#C.entries,start+bounded(options.maxEntries,#C.entries,#C.entries)-1)
        local cache={}
        local absent=false;local existence
        if not probe and options.liveExistence and unit~="player" then
            local values,why=call("UnitExists",context,unit)
            existence={values=values,why=why}
            absent=values and not secret(values[1]) and values[1]==false
        end
        local function auxiliary(key,fn)
            if not cache[key] then cache[key]=pack(fn()) end
            return unpack(cache[key],1,cache[key].n)
        end
        local function argument(arg)
            if type(arg)~="string" or arg:sub(1,1)~="$" then return arg end
            if arg=="$unit" then return unit elseif arg=="$player" then return "player" elseif arg=="$nil" then return nil end
            local enum=arg:match("^%$power:(.+)$") or arg:match("^%$damage:(.+)$") or arg:match("^%$swing:(.+)$")
            if enum then
                local category=arg:find("$power:",1,true) and "PowerType" or arg:find("$swing:",1,true) and "SwingType" or "Damageclass"
                local e=api.Enum and api.Enum[category];local value,why=access(e,enum)
                if why or secret(value) or not G.Number(value) then return nil,"unsupported" end
                return value
            end
            local option=arg:match("^%$option:(.+)$")
            if option then
                local value=options[option] or C.queryDefaults[option]
                if option=="spellID" and (not G.Number(value) or value<1) or option=="spellName" and (secret(value) or type(value)~="string" or value=="") then return nil,"unconfigured" end
                return value
            end
            if arg=="$bestMap" then
                local values,why=auxiliary(arg,function()return call("C_Map.GetBestMapForUnit",context,unit)end)
                if not values then return nil,why end
                if secret(values[1]) then return nil,"protected" end
                return values[1]
            end
            if arg=="$neutralColorCurve" then
                -- Deliberately neutral: this observes the native color/access path,
                -- without guessing a mapping between undocumented dispel IDs and types.
                local values,why=auxiliary(arg,function()
                    local created,state=call("C_CurveUtil.CreateColorCurve",context)
                    if not created then return nil,state end
                    local curve=created[1];if secret(curve) then return nil,"protected" end
                    local color;color,state=call("CreateColor",context,1,1,1,1)
                    if not color then return nil,state end
                    local added;added,state=method(curve,"AddPoint",context,0,color[1])
                    if not added then return nil,state end
                    return {n=1,curve}
                end)
                return values and values[1],why
            end
            if arg=="$calculator" then
                local values,why=auxiliary(arg,function()return call("CreateUnitHealPredictionCalculator",context)end)
                return values and values[1],why
            end
            if arg=="$auraID" then
                local values,why=auxiliary(arg,function()return call("C_UnitAuras.GetAuraDataByIndex",context,unit,options.auraIndex or 1,"HELPFUL")end)
                if not values then return nil,why end
                return access(values[1],"auraInstanceID")
            end
            if arg=="$auraSlot" then
                local values,why=auxiliary(arg,function()return call("C_UnitAuras.GetAuraSlots",context,unit,"HELPFUL",options.auraIndex or 1)end)
                return values and values[(options.auraIndex or 1)+1],why
            end
            return nil,"unsupported"
        end
        for index=start,finish do
            local entry=C.entries[index];local wanted=probe
            if options.entries then wanted=options.entries[entry.id]==true or options.entries[entry.api]==true end
            if not wanted then for _,field in ipairs(entry.outputs) do if requested and requested[field.key] then wanted=true;break end end end
            if wanted then
                local row={id=entry.id,api=entry.api,family=entry.family,status="ready",fields={}}
                local args={n=#entry.args};local why
                if absent and entry.api~="UnitExists" then why="absent" end
                if entry.playerOnly and unit~="player" or entry.targetOnly and unit~="target" or entry.nameplateOnly and not unit:match("^nameplate%d+$") then why="unsupported" end
                for i,arg in ipairs(entry.args) do if not why then args[i],why=argument(arg) end end
                local values
                if not why then
                    local apiName=entry.api
                    if entry.api=="UnitAffectingCombat" and unit=="player" then apiName="InCombatLockdown";args={n=0} end
                    if entry.api=="UnitExists" and existence then values,why=existence.values,existence.why
                    elseif entry.api=="UnitExists" and unit=="player" and not probe then values={n=1,true}
                    else values,why=call(apiName,context,unpack(args,1,args.n)) end
                    if entry.api=="UnitHealthPercent" and why=="unsupported" then
                        local health=call("UnitHealth",context,unit,false);local maximum=call("UnitHealthMax",context,unit)
                        if health and maximum then
                            local hv,hs=scalar(health[1],"float",true);local mv,ms=scalar(maximum[1],"float",true)
                            if hs=="readable" and ms=="readable" and mv>0 then values={n=1,hv/mv*100};why=nil
                            else why=G.SignalMerge(hs,ms);if why=="readable" then why="unavailable" end end
                        end
                    end
                    result.summary.attempted=result.summary.attempted+1
                    if entry.calculator and values then values={n=1,args[3]} end
                end
                row.status=why or "ready"
                for _,field in ipairs(entry.outputs) do
                    local value,status
                    if values then
                        local raw=values[field.index]
                        if field.variadic then raw={};for i=field.index,math.min(values.n,field.index+context.recordLimit-1) do raw[i-field.index+1]=values[i] end end
                        if field.type=="data" or field.type=="duration" or field.type=="calculator" then value,status=captureObject(raw,field,context,row.fields)
                        else value,status=scalar(raw,field.type,field.nonnegative) end
                    else status=why or "unavailable" end
                    row.fields[field.key]=describe(value,field.type,status)
                    if status=="protected" then result.summary.protected=result.summary.protected+1 end
                    if not probe then result.values[field.key]=value;result.fields[field.key]=status end
                end
                if why=="unsupported" then result.summary.unsupported=result.summary.unsupported+1 elseif why=="error" then result.summary.errors=result.summary.errors+1 end
                for key,description in pairs(row.fields) do
                    if description.status=="protected" and not C.fields[key] then result.summary.protected=result.summary.protected+1 end
                end
                result.entries[#result.entries+1]=row
            end
        end
        result.nextEntry=finish<#C.entries and finish+1 or nil;result.done=finish>=#C.entries
        result.summary.calls=context.calls;result.summary.truncated=context.truncated==true
        result.status=result.fields.exists=="readable" and (result.values.exists and "present" or "absent") or result.fields.exists or "observed"
        if probe then result.values=nil;result.fields=nil end
        return result
    end
    function self:Capture(unit,requested,options) return run(unit,requested,options,false) end
    function self:Probe(unit,options) return run(unit,nil,options,true) end
    function self:Project(handle,schema,key,index)
        local info=handles[handle]
        if not info or (info.schema~=schema and not (info.schema=="tooltip" and schema=="tooltipLines")) or not C.schemas[schema] or not C.schemas[schema][key] then return nil,"unavailable" end
        local kind=(schema=="duration" or schema=="calculator") and schema or "data"
        local raw=G.Object(handle,kind)
        if kind=="data" then
            local record=raw
            if schema=="auras" or schema=="numbers" or schema=="controls" or schema=="tooltipLines" then record=raw.records[index] end
            if schema=="tooltip" and C.schemas.tooltipLine[key] then record=raw.records[index] end
            return record and record.values[key],record and record.fields[key] or "unavailable"
        end
        local definition=C.methods[schema][key];local name=type(definition)=="table" and definition.name or definition
        local result,why=method(raw,name,{calls=0,limit=1});if not result then return nil,why end
        local candidate=result[type(definition)=="table" and definition.index or 1]
        if type(definition)=="table" and definition.path then candidate,why=access(candidate,definition.path);if why then return nil,why end end
        return scalar(candidate,C.schemas[schema][key])
    end
    return self
end
function D.Project(handle,schema,key,index)
    local info=handles[handle];if not info then return nil,"unavailable" end
    return info.source:Project(handle,schema,key,index)
end

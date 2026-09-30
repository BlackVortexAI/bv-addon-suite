local _, A=...
if A.blocked then return end
local G=A.G
local M=BVAddonSuiteCore.DisplayModel
local P=BVAddonSuiteCore.Performance
local R={}; A.Runtime=R
local ops={ ["<"]=function(a,b)return a<b end,["<="]=function(a,b)return a<=b end,[">"]=function(a,b)return a>b end,[">="]=function(a,b)return a>=b end,["=="]=function(a,b)return a==b end,["~="]=function(a,b)return a~=b end }
local function seconds(value,minimum)
    if value<minimum or value>86400 then error("Seconds must be "..minimum.."..86400") end
    return value
end
local function evaluateAnimation(n,def,state,resolve,now)
    local media,active=resolve("media"),resolve("active")
    if not media or active==nil then state.time=nil;return nil,"unavailable" end
    if not active then state.time=nil;return {media=G.RuntimeCopy(media)},"inactive" end
    local strength,speed,duration,looping,reset=resolve("strength"),resolve("speed"),resolve("duration"),resolve("looping"),resolve("reset")
    if strength==nil or speed==nil or duration==nil or looping==nil or reset==nil then state.time=nil;return nil,"unavailable" end
    if strength<0 or strength>100 or speed<.05 or speed>2.5 then error("Animation strength 0..100; speed 0.05..2.5") end
    seconds(duration,0)
    local t=state.time
    if not t or reset or t.strength~=strength or t.speed~=speed or t.duration~=duration or t.looping~=looping then
        t={startedAt=now,strength=strength,speed=speed,duration=duration,looping=looping};state.time=t
    end
    local elapsed=math.max(0,now-t.startedAt)
    local span=duration>0 and duration or (looping and math.huge or 1/speed)
    if not looping then span=math.min(span,1/speed) end
    t.clock=elapsed<span and strength>0
    if not t.clock then return {media=G.RuntimeCopy(media)},"finished" end
    local phase=(elapsed*speed)%1;local wave=math.sin(phase*math.pi*2)
    local config={mode="visual",pivot=n.config.pivot}
    local result
    if def.animation=="shake" then
        local x,y=strength*wave,strength*.25*math.sin(phase*math.pi*4)
        if n.config.axis=="HORIZONTAL" then y=0 elseif n.config.axis=="VERTICAL" then x=0;y=strength*wave end
        result=M.Modify(media,"offset",{x=x,y=y},config)
    elseif def.animation=="float" then result=M.Modify(media,"offset",{x=0,y=strength*wave},config)
    elseif def.animation=="pulse" then result=M.Modify(media,"scale",{factor=1+strength/100*wave},config)
    elseif def.animation=="spin" then result=M.Modify(media,"rotate",{angle=phase*360*strength/100},config)
    elseif def.animation=="bounce" then result=M.Modify(media,"offset",{x=0,y=strength*math.abs(wave)},config)
    else result=M.Modify(media,"opacity",{alpha=media.alpha*(1-strength/100*(.5-.5*math.cos(phase*math.pi*2)))},config) end
    return {media=result},"animating"
end
-- One stateful implementation for the clock-driven nodes. It consumes only
-- checked graph values; history is run-local and never stored in a graph.
local function evaluateTime(run,id,n,state,resolve,context,now,dirty)
    local active=resolve("active")
    if active==nil then state.time=nil; return nil,"unavailable" end
    local t=state.time or {}; state.time=t; t.clock=false
    if n.type=="remaining_estimate" then
        if not active then state.time=nil; return {estimated=false},"inactive" end
        local value=resolve("value")
        if value~=nil then
            seconds(value,0)
            local edge=run.plan.incoming[id].value
            -- A control update must not re-date a stale source observation.
            if t.baseline==nil or not edge or dirty[edge.from] then
                t.baseline=value; t.observedAt=edge and run.trace[edge.from] and run.trace[edge.from].at or now
            end
            return {value=value,estimated=false},"observed"
        end
        if t.baseline==nil then return {estimated=false},"no baseline",{value=context.inputs.value} end
        local remaining=math.max(0,t.baseline-math.max(0,now-t.observedAt))
        t.clock=remaining>0
        return {value=remaining,estimated=true},"estimated"
    end
    -- Inactive nodes ignore optional Reset; an unavailable Reset must not keep
    -- old state alive. A missing required operand always clears the countdown.
    if not active then
        state.time=nil
        if n.type=="interval" then return {event=false},"inactive" end
        local start=resolve("start"); if start==nil then return nil,"unavailable" end
        return {value=seconds(start,0),running=false,finished=false},"inactive"
    end
    local reset=resolve("reset")
    if reset==nil then state.time=nil; return nil,"unavailable" end
    if n.type=="timer" then
        local start,target=resolve("start"),resolve("target")
        if start==nil or target==nil then state.time=nil; return nil,"unavailable" end
        seconds(start,0); seconds(target,0)
        if not t.startedAt or reset or t.start~=start or t.target~=target then
            t.startedAt=now; t.start=start; t.target=target; t.done=false
        end
        local span=math.abs(target-start); local elapsed=math.max(0,now-t.startedAt)
        local done=elapsed>=span; local finished=done and not t.done
        t.done=done; t.clock=not done
        return {value=done and target or start+(target>=start and 1 or -1)*elapsed,running=not done,finished=finished},done and "finished" or "running"
    end
    local interval,immediate=resolve("seconds"),resolve("immediate")
    if interval==nil or immediate==nil then state.time=nil; return nil,"unavailable" end
    seconds(interval,.1)
    local fire=false
    if not t.deadline or reset or t.interval~=interval or t.immediate~=immediate then
        t.interval=interval; t.immediate=immediate; t.deadline=now+interval; fire=immediate
    elseif now>=t.deadline then
        fire=true
        -- Preserve cadence while skipping missed deadlines (no catch-up burst).
        t.deadline=t.deadline+(math.floor((now-t.deadline)/interval)+1)*interval
    end
    t.clock=true
    return {event=fire},fire and "triggered" or "waiting"
end
local function formatValues(config,resolve)
    local template=resolve("template");if template==nil then return nil,"unavailable" end
    local values,observed={},{}
    local function read(index)
        if index<1 or index>config.count then return nil end
        if not observed[index] then values[index]=resolve("value"..index);observed[index]=true end
        local value=values[index]
        if G.IsSecret(value) then return nil end
        if type(value)=="string" or type(value)=="boolean" or G.Number(value) then return value end
    end
    if config.hideZero or config.hideOne then
        local first=read(1);if first==nil then return nil,"unavailable" end
        if type(first)=="number" and (config.hideZero and first==0 or config.hideOne and first==1) then return {text="",visible=false},"suppressed" end
    end
    local failed,size=nil,#template
    local function number(value)return string.format("%."..config.decimals.."f",value)end
    local text=template:gsub("{([^{}]+)}",function(token)
        if failed then return "" end
        local replacement
        if token=="percent" then
            local current,maximum=read(1),read(2)
            if not G.Number(current) or not G.Number(maximum) or maximum<=0 or not G.Number(100*(current/maximum)) then failed="unavailable";return "" end
            replacement=number(100*(current/maximum))
        else
            local mode,index=token:match("^(value)(%d+)$")
            if not mode then mode,index=token:match("^(time)(%d+)$") end
            if not mode and token:match("^%d+$") then mode,index="value",token end
            if mode and (not tonumber(index) or tonumber(index)<1 or tonumber(index)>16 or tostring(tonumber(index))~=index) then mode=nil end
            if not mode then return nil end
            local value=read(tonumber(index))
            if value==nil then failed="unavailable";return "" end
            if mode=="time" then
                if not G.Number(value) or value<0 or value>86400 then failed="unavailable";return "" end
                local seconds=math.floor(value+.5);replacement=string.format("%d:%02d",math.floor(seconds/60),seconds%60)
            else replacement=type(value)=="number" and number(value) or tostring(value) end
        end
        size=size-#token-2+#replacement
        if size>1024 then failed="text_too_long";return "" end
        return replacement
    end)
    if failed then return nil,failed end
    return {text=text,visible=true},"formatted"
end
local function parseValue(value,target)
    if G.IsSecret(value) then return nil end
    local t=type(value)
    if t~="boolean" and t~="string" and not G.Number(value) then return nil end
    if target=="string" then local text=tostring(value);if #text<=1024 then return text end;return nil end
    if target=="boolean" then
        if t=="boolean" then return value end
        if t=="string" then value=value:match("^%s*(.-)%s*$"):lower() end
        if value==1 or value=="1" or value=="true" then return true end
        if value==0 or value=="0" or value=="false" then return false end
        return nil
    end
    if t=="boolean" then value=value and 1 or 0
    elseif t=="string" then
        local text=value:match("^%s*(.-)%s*$")
        local mantissa,exponent=text:match("^(.-)[eE]([+-]?%d+)$")
        if not mantissa then mantissa=text end
        if not (mantissa:match("^[+-]?%d+%.?%d*$") or mantissa:match("^[+-]?%.%d+$")) then return nil end
        value=tonumber(text)
    end
    if not G.Number(value) or target=="integer" and value~=math.floor(value) then return nil end
    return value
end
local function roundValue(value,config)
    local scale=10^config.decimals
    local scaled=value*scale
    if not G.Number(scaled) or math.abs(scaled)>4503599627370495 then return nil end
    local rounded
    if config.operation=="floor" then rounded=math.floor(scaled)
    elseif config.operation=="ceil" then rounded=math.ceil(scaled)
    elseif scaled<0 then rounded=math.ceil(scaled-.5)
    else rounded=math.floor(scaled+.5) end
    -- Normalize negative zero so the numerical/text outputs agree visibly.
    local result=rounded==0 and 0 or rounded/scale
    return result,string.format("%."..config.decimals.."f",result)
end
local function stringFormatter(config,resolve)
    local template=resolve("template");if template==nil then return nil,"unavailable" end
    local values,seen={},{}
    for token in template:gmatch("{([^{}]+)}") do
        local index=token:match("^value(%d+)$") or token:match("^(%d+)$")
        local number=index and tonumber(index)
        if number and number>=1 and number<=config.count and tostring(number)==index and not seen[number] then
            values[number]=resolve("value"..number,true);seen[number]=true
        end
    end
    local text,status=BVAddonSuiteCore.GraphValues.FormatDisplay(template,values,config.count)
    if text==nil then return nil,status or "unavailable" end
    return {text=text},status or "formatted"
end
-- Static spell artwork is independent of native aura presence/texture secrecy.
-- Reuse the existing metadata cache/picker reference; never query native APIs.
local function validIconID(value)return G.Number(value) and value>0 and value==math.floor(value) end
local function auraIcon(run,n,values,fields)
    local icon=run.objectIcons and run.objectIcons[n.config.spellID]
    if not validIconID(icon) then icon=n.config.spellIcon end
    values.icon=validIconID(icon) and M.New("icon",{texture=tostring(icon),cropBorder=n.config.cropBorder}) or nil
    fields.icon=values.icon and "readable" or "unavailable"
end
-- Explicit graph-level fallback; never mutate or infer the native observation.
local function presentEstimate(values,fields,status,observation,now)
    local value=values.present
    local signal=G.SignalStatus(value,fields.present or status)
    if signal=="protected" then
        local memory=observation and observation.targetEstimate
        if memory and type(memory.present)=="boolean" then
            values.presentEstimate=memory.present
            if memory.memoryOnly and G.Number(memory.deadline) and memory.deadline<=now then values.presentEstimate=false end
        else values.presentEstimate=observation and observation.cdmPresence==true or false end
        fields.presentEstimate="readable"
    elseif not G.IsSecret(value) and type(value)=="boolean" then
        values.presentEstimate=value;fields.presentEstimate="readable"
    else
        values.presentEstimate=nil;fields.presentEstimate=signal
    end
end
local function nonnegative(value)return G.Number(value) and value>=0 end
local function auraTimingEstimate(run,id,n,state,values,fields,observation,token,sample,now)
    local durationSignal=G.SignalStatus(values.duration,fields.duration or observation and observation.status)
    local remainingSignal=G.SignalStatus(values.remaining,fields.remaining or observation and observation.status)
    values.durationEstimate=nil;values.remainingEstimate=nil
    fields.durationEstimate=durationSignal;fields.remainingEstimate=remainingSignal
    local unit=token and sample.units and sample.units[token]
    local absent=not G.IsSecret(values.present) and values.present==false
    local stopped=not G.IsSecret(values.presentEstimate) and values.presentEstimate==false
    if not observation or absent or unit and unit.status=="absent" then
        state.auraEstimate=nil;fields.durationEstimate="unavailable";fields.remainingEstimate="unavailable"
        if stopped then fields.remainingEstimate="nil" end
        return
    end
    local reference=run.instance or token and sample.unitRefs and sample.unitRefs[token]
    local binding=reference and G.Object(reference,"unitref")
    local generation
    if binding then generation=binding.generation end
    if not nonnegative(generation) and token and sample.unitGenerations then generation=sample.unitGenerations[token] end
    if not nonnegative(generation) then generation=nil end
    local instance=observation.auraInstanceID
    if not G.Number(instance) or instance<=0 or instance~=math.floor(instance) then instance=nil end
    local s=state.auraEstimate
    if not s or s.unit~=token or s.spellID~=n.config.spellID or s.filter~=n.config.filter
        or generation and s.generation and generation~=s.generation
        or instance and s.instance and instance~=s.instance then
        s={unit=token,spellID=n.config.spellID,filter=n.config.filter};state.auraEstimate=s
    end
    if generation then s.generation=generation end
    if instance then s.instance=instance end
    s.clock=false
    local permanent=not G.IsSecret(values.hasExpiration) and values.hasExpiration==false
    if permanent then s.duration=nil end
    if nonnegative(values.duration) then
        s.duration=values.duration;values.durationEstimate=values.duration;fields.durationEstimate="readable"
    elseif durationSignal=="protected" then
        values.durationEstimate=s.duration;fields.durationEstimate=s.duration~=nil and "readable" or "unavailable"
    else
        s.duration=nil
    end
    if permanent or stopped then
        if permanent then s.duration=nil end
        s.remaining=nil;s.remainingAt=nil;s.deadline=nil;s.remainingStamp=nil;s.remainingSerial=nil
        if stopped then fields.remainingEstimate="nil"
        else fields.remainingEstimate="permanent" end
        return
    end
    local expiration=observation.expirationTime
    if not nonnegative(expiration) or expiration==0 then expiration=nil end
    local remainingValue=values.remaining
    -- An accessible absolute expiration is itself a timing observation;
    -- calculating this estimate never modifies the native Remaining output.
    if not nonnegative(remainingValue) and expiration then remainingValue=math.max(0,expiration-now) end
    if nonnegative(remainingValue) then
        local stamp=observation.observedAt;if not nonnegative(stamp) then stamp=nil end
        local serial=observation.captureSerial;if not nonnegative(serial) then serial=nil end
        -- A cached sample can arrive again on control/unit/clock updates. Only
        -- a new capture may date a relative remaining-time baseline anew.
        if s.remaining==nil or stamp and stamp~=s.remainingStamp or serial and serial~=s.remainingSerial then
            s.remaining=remainingValue;s.remainingAt=stamp or now;s.remainingStamp=stamp;s.remainingSerial=serial
            s.deadline=expiration
        elseif expiration then s.deadline=expiration end
        values.remainingEstimate=remainingValue;fields.remainingEstimate="readable"
        s.clock=run.estimateClockRoots[id] and expiration~=nil and remainingValue>0 or false
    elseif remainingSignal=="protected" then
        if s.remaining~=nil then
            local remaining=s.deadline and math.max(0,s.deadline-now) or math.max(0,s.remaining-math.max(0,now-s.remainingAt))
            values.remainingEstimate=remaining;fields.remainingEstimate="readable"
            s.clock=run.estimateClockRoots[id] and remaining>0 or false
        else fields.remainingEstimate="unavailable" end
    else
        s.remaining=nil;s.remainingAt=nil;s.deadline=nil;s.remainingStamp=nil;s.remainingSerial=nil
    end
    -- An exhausted estimate has no remaining value; native numeric zero stays
    -- available on the native output. Retain the expired deadline for cached
    -- samples so replay cannot restart an already finished countdown.
    if values.remainingEstimate==0 then
        values.remainingEstimate=nil;fields.remainingEstimate="nil";s.clock=false
    end
end
local function targetMemoryTiming(run,id,state,values,fields,observation,now)
    local memory=observation and observation.targetEstimate
    if not memory or values.present==false then return end
    if G.Number(memory.duration) and not G.Number(values.duration) then
        values.durationEstimate=memory.duration;fields.durationEstimate="readable"
    end
    if values.presentEstimate~=true then
        values.remainingEstimate=nil;fields.remainingEstimate=values.presentEstimate==false and "nil" or "unavailable"
        if state.auraEstimate then state.auraEstimate.clock=false end
        return
    end
    if G.Number(memory.deadline) and not G.Number(values.remaining) then
        local remaining=memory.deadline-now
        values.remainingEstimate=remaining>0 and remaining or nil
        fields.remainingEstimate=remaining>0 and "readable" or "nil"
        state.auraEstimate=state.auraEstimate or {}
        state.auraEstimate.clock=run.estimateClockRoots[id] and remaining>0 or false
    end
end
function R.New(plan,emit,diagnose,display)
    local roots,timeRoots,estimateRoots,rangeRoots={},{},{},{}; local messageDriven=false
    local sectionMute,sectionBypass=A.Sections.Effects(plan.graph)
    for _,e in ipairs(plan.graph.edges) do
        if plan.active[e.to] and (plan.graph.nodes[e.from].type=="aura" or plan.definitions[e.from].auraSource) and e.output=="remaining" then roots[e.from]=true end
        if plan.active[e.to] and (plan.graph.nodes[e.from].type=="aura" or plan.definitions[e.from].auraSource) and (e.output=="remainingEstimate" or e.output=="presentEstimate" and plan.graph.nodes[e.from].config.unit=="target") then estimateRoots[e.from]=true end
    end
    for id in pairs(plan.active) do
        if plan.definitions[id].clock then timeRoots[id]=true end
        if plan.definitions[id].rangeSource then rangeRoots[id]=true end
        if plan.definitions[id].messageSource then messageDriven=true end
    end
    return {plan=plan,emit=emit,diagnose=diagnose,display=display,state={},trace={},values={},signals={},auras={},clockRoots=roots,timeRoots=timeRoots,estimateClockRoots=estimateRoots,rangeRoots=rangeRoots,sectionMute=sectionMute,sectionBypass=sectionBypass,messageDriven=messageDriven,stopped=false,revision=0}
end
local function evaluate(run,id,sample,now,dirty,context)
    local n=run.plan.graph.nodes[id]; local def=run.plan.definitions[id]; local args={}
    local state=run.state[id] or {}; run.state[id]=state
    if state.paused or (state.retryAt and now<state.retryAt) then state.auraEstimate=nil;return nil,"faulted" end
    local override=run.test and run.nodeOverrides and run.nodeOverrides[id]
    if override then
        local pulse=context.reason=="node_test:"..id and sample.nodeTest and sample.nodeTest.id==id and sample.nodeTest
        local values=G.Copy(pulse and pulse.values or override.values)
        for key,p in pairs(def.outputs) do if p.type=="event" then values[key]=pulse and pulse.fire and values[key]==true or false end end
        return values,override.mode=="freeze" and "Frozen" or "Test Mode"
    end
    local ports=G.Ports(def)
    local function resolve(key,transport)
        local p=ports[key]
        local e=run.plan.incoming[id][key]; local value
        if e then local source=run.values[e.from]; value=source and source[e.output]
        else
            value=n.values[key]; if value==nil then value=p.default end
            if value==nil and p.type=="event" and p.required==false then value=false end
        end
        local signal=G.SignalStatus(value,e and run.signals[e.from] and run.signals[e.from][e.output] or nil)
        context.inputs[key]=signal
        if G.IsSecret(value) then
            -- A declaration permits transport, never evaluating the payload.
            local allowed=transport or (def.secretInputs and def.secretInputs[key])
            if allowed and G.RuntimeAccepts(p.type,value) then
                if p.type=="event" and e and not dirty[e.from] then value=false end
                args[key]=value; return value
            end
            context.missing=G.SignalMerge(context.missing,"protected"); return nil
        end
        if value==nil then context.missing=G.SignalMerge(context.missing,signal) end
        if value==nil then return nil end
        if p.type=="event" then
            if type(value)~="boolean" then error("Invalid event: "..key) end
            if e and not dirty[e.from] then value=false end
        elseif not G.RuntimeAccepts(p.type,value) then error("Invalid input: "..key) end
        args[key]=value
        return value
    end
    -- A muted section silences every member, sources included; its Bypass
    -- applies to members that have a bypass mapping. Node settings stay as is.
    if run.sectionMute and run.sectionMute[id] then
        if def.soundSink then BVAddonSuiteCore.Sound:Stop(run,id) end
        if def.clock then state.time=nil end;if def.lastUnprotectedValue then state.lastReadable=nil end;state.auraEstimate=nil
        return nil,"muted by section"
    end
    local sectionBypass=run.sectionBypass and run.sectionBypass[id] and def.bypass
    if sectionBypass then
        if def.animation then state.time=nil end
        local out={}
        for key,input in pairs(def.bypass) do
            if resolve(input,true)==nil then return nil,"unavailable" end
            out[key]=args[input]
        end
        return out,"bypassed by section"
    end
    -- Controls are evaluated before payload. Bypass needs only its mapped input,
    -- not operands belonging exclusively to the skipped operation.
    if ports.mute then
        if def.soundSink then local mute=resolve("mute");if mute==nil or mute then BVAddonSuiteCore.Sound:Stop(run,id) end end
        if resolve("mute")==nil then if def.clock then state.time=nil end;if def.lastUnprotectedValue then state.lastReadable=nil end;state.auraEstimate=nil; return nil,"unavailable" end
        if args.mute then if def.clock then state.time=nil end;if def.lastUnprotectedValue then state.lastReadable=nil end;state.auraEstimate=nil; return nil,"muted" end
    end
    if ports.bypass then
        if resolve("bypass")==nil then return nil,"unavailable" end
        if args.bypass then
            if def.animation then state.time=nil end
            local out={}
            for key,input in pairs(def.bypass) do
                if resolve(input,true)==nil then return nil,"unavailable" end
                out[key]=args[input]
            end
            return out,"bypass"
        end
    end
    if def.flowOperation then return A.FlowValues.Evaluate(run,id,n,def,state,resolve,context,now) end
    if def.formatValues then return formatValues(n.config,resolve) end
    if def.stringFormatter then return stringFormatter(n.config,resolve) end
    if def.roundValue then
        local value=resolve("value")
        if value==nil then return {success=false},"unavailable" end
        local number,text=roundValue(value,n.config)
        return {value=number,text=text,success=number~=nil},number~=nil and "rounded" or "out_of_range"
    end
    if def.timeFormat then
        local value=resolve("value")
        if value==nil then return {success=false},"unavailable" end
        if value<0 or value>86400 then return {success=false},"out_of_range" end
        local total=math.floor(value+.5)
        return {text=string.format("%d:%02d",math.floor(total/60),total%60),success=true},"formatted"
    end
    if def.lastUnprotectedValue then
        local reset=resolve("reset")
        if reset==nil then state.lastReadable=nil;return {cached=false},"unavailable",{value=context.inputs.reset} end
        if reset then state.lastReadable=nil;return {cached=false},"reset" end
        local value=resolve("value")
        if context.inputs.value=="protected" then
            local cached=state.lastReadable
            if cached then return {value=cached.value,cached=true},"cached" end
            return {cached=false},"no baseline",{value="unavailable"}
        end
        if value==nil then state.lastReadable=nil;return {cached=false},"unavailable",{value=context.inputs.value} end
        if type(value)~="boolean" and type(value)~="string" and not G.Number(value) then
            state.lastReadable=nil;return {cached=false},"scalar_required"
        end
        state.lastReadable={value=value}
        return {value=value,cached=false},"observed"
    end
    if def.parseValue then
        local value=resolve("value")
        if value==nil then return {success=false},"unavailable",{value=context.inputs.value} end
        local converted=parseValue(value,n.config.targetType)
        return {value=converted,success=converted~=nil},converted~=nil and "converted" or "invalid_value"
    end
    if def.mathOperation then
        local a,b=resolve("value"),resolve("factor")
        if a==nil or b==nil then return {success=false},"unavailable" end
        local op=def.mathOperation;local result
        if (op=="divide" or op=="modulo") and b==0 then return {success=false},"division_by_zero" end
        if op=="percent" and b<=0 then return {success=false},"invalid_maximum" end
        if op=="add" then result=a+b elseif op=="subtract" then result=a-b elseif op=="multiply" then result=a*b
        elseif op=="divide" then result=a/b elseif op=="percent" then result=100*(a/b) else result=a%b end
        if not G.Number(result) then return {success=false},"nonfinite_result" end
        return {value=result,success=true},"calculated"
    end
    if def.booleanOperation then
        local op=def.booleanOperation
        if op=="not" then local value=resolve("in1");if value==nil then return nil,"unavailable" end;return {result=not value} end
        local parity=op=="xor" or op=="xnor"
        local disjunction=op=="or" or op=="nor"
        local inverted=op=="nand" or op=="nor" or op=="xnor"
        local unknown,count=false,0
        for i=1,def.count do
            local value=resolve("in"..i)
            if value==nil then unknown=true elseif value then count=count+1 end
            if not parity and value==disjunction then return {result=(inverted and not disjunction or not inverted and disjunction)} end
        end
        if unknown then return nil,"unavailable" end
        local value=parity and count%2==1 or not parity and not disjunction
        if inverted then value=not value end
        return {result=value}
    end
    if def.memoryOperation then
        local idle={done=false,status="idle"};if def.memoryOperation=="set" then idle.success=false end
        local trigger=resolve("event")
        if trigger==nil then idle.status="unavailable";return idle,idle.status end
        if not trigger or context.reason=="initial" then return idle,"idle" end
        if run.plan.incoming[id].instance then
            local instance=resolve("instance",true)
            if not G.Object(instance,"unitref") or instance~=run.instance then idle.status="unavailable";return idle,idle.status end
        end
        local key,value
        if def.memoryOperation~="clear" then
            key=resolve("key");if key==nil then idle.status="unavailable";return idle,idle.status end
        end
        if def.memoryOperation=="set" then
            value=resolve("value");if value==nil then idle.status="unavailable";return idle,idle.status end
        end
        local result=A.Memory.Execute(run,def.memoryOperation,n.config.valueType,key,value,def.memoryOperation=="set" and resolve("timestamp") or nil)
        return result,result.status
    end
    if n.type=="media_interaction" then
        if resolve("media")==nil or resolve("enabled")==nil then return nil,"unavailable" end
        for _,field in ipairs(n.config.payload or {}) do resolve(field.id,true) end
        return {media=M.Modify(args.media,n.type,args,n.config)}
    end
    if def.animation then return evaluateAnimation(n,def,state,resolve,now) end
    if def.clock then return evaluateTime(run,id,n,state,resolve,context,now,dirty) end
    -- Inspection must run before ordinary payloads reject missing values.
    -- The edge itself is required by the compiler, not a readable observation.
    if def.debugPreview then
        local value=resolve("value",true)
        local edge=run.plan.incoming[id].value
        local source=edge and run.plan.definitions[edge.from].outputs[edge.output]
        if source and source.type=="event" and not dirty[edge.from] then value=false end
        return {value=value},"inspected",{value=context.inputs.value}
    end
    if n.type=="is_nil" then
        local value=resolve("value",true)
        if G.IsSecret(value) then return nil,"protected" end
        return {result=value==nil}
    end
    if n.type=="secret" then
        local value=resolve("value",true); local signal=context.inputs.value
        local hidden=G.SignalSecret(signal)
        return {value=G.RuntimeCopy(value),isSecret=hidden,available=value~=nil and not G.IsSecret(value)},"inspected",
            {value=signal,isSecret=hidden==nil and "unavailable" or "readable",available="readable"}
    end
    if n.type=="constant_nil" then return {},"nil" end
    if n.type=="message_receive" then
        local active=resolve("active"); if active==nil then return nil,"unavailable" end
        local p=sample.message
        if n.config.permission==false then return {event=false},"disabled on node"end
        if not active then return {event=false},"inactive" end
        if (context.reason=="message" or (run.test and context.reason=="test")) and p and p.topic==n.config.topic
            and p.kind==n.config.payloadType and p.channel==n.config.channel then
            if run.messageAccept and not run.messageAccept(n.config,p)then return {event=false},"sender not allowed on node"end
            if n.config.sender~="" and p.sender~=n.config.sender:lower() then return {event=false},"sender filtered" end
            return {event=true,value=p.value,sender=p.sender},"received"
        end
        return {event=false},"waiting"
    end
    if n.type=="media_event" then
        local active=resolve("active");if active==nil then return nil,"unavailable" end
        if not active then return {event=false},"inactive" end
        local p=sample.interaction
        if p and p.instance and run.instance and p.instance~=run.instance then return {event=false},"other instance" end
        if (context.reason=="interaction" or (run.test and context.reason=="test")) and p and p.key==n.config.key then
            local values=BVAddonSuiteCore.GraphValues.ClickRead(p.payload,n.config.payload)
            if not values then return {event=false},"payload mismatch" end
            values.event=true;values.button=p.button;values.shift=p.shift;values.control=p.control;values.alt=p.alt
            return values,"clicked"
        end
        return {event=false},"waiting"
    end
    if def.nativeEvent then
        if n.type=="chat_receive" and n.config.permission==false then return {event=false},"disabled on node"end
        local active=resolve("active");if active==nil then return nil,"unavailable" end
        if not active then return {event=false},"inactive" end
        local p=sample.sourceEvent
        if (context.reason=="source_event" or (run.test and context.reason=="test")) and p and p.kind==n.type then
            if (n.type=="encounter_event" or n.type=="ready_check_event") and n.config.phase~="either" and p.values[n.config.phase]~=true then return {event=false},"filtered" end
            if n.type=="chat_receive" and not (p.matches and p.matches[id]) then return {event=false},"filtered" end
            if n.type=="bossmod_event" then
                local c=n.config;local v=p.values
                if (c.provider~="any" and v.provider~=c.provider) or (c.eventType~="any" and v.eventType~=c.eventType) then return {event=false},"filtered" end
                if c.spellID~=0 then if v.spellId==nil then return {event=false},"filtered" end;if v.spellId~=c.spellID then return {event=false},"filtered" end end
                if c.text~="" and not (v.text and A.TextOps.Fold(v.text):find(A.TextOps.Fold(c.text),1,true)) then return {event=false},"filtered" end
            end
            local key,filter
            if n.type=="player_cast" and n.config.spellID~=0 then key="spellID";filter=n.config.spellID end
            if n.type=="player_swing" and n.config.hand~="ALL" then key="hand";filter=n.config.hand end
            if key then
                if p.values[key]==nil then return nil,"unavailable",{event=p.fields[key]} end
                if p.values[key]~=filter then return {event=false},"filtered" end
            end
            return G.Copy(p.values),"received",G.Copy(p.fields)
        end
        return {event=false},"waiting"
    end
    if def.frameSource then
        local observation=sample.sources and sample.sources["frame_state:"..n.config.reference]
        local status=observation and observation.state or "pending"
        local binding=observation and observation.binding
        local knownBinding=not G.IsSecret(binding) and (binding==nil or G.Number(binding) and binding>0 and binding==math.floor(binding))
        if not knownBinding then binding=nil;state.frameVisible=nil;state.frameBinding=nil end
        if n.config.reference=="" then status="invalid" end
        if G.IsSecret(status) or type(status)~="string" or not ({pending=true,missing=true,restricted=true,hidden=true,ready=true,invalid=true})[status] then status="restricted" end
        local out={shown=false,hidden=false,state=status}
        if status=="ready" or status=="hidden" then
            local visible=status=="ready";out.found=true;out.visible=visible
            if knownBinding and state.frameBinding==binding and state.frameVisible~=nil and state.frameVisible~=visible and (context.reason=="frame_state" or run.test and context.reason=="test") then
                out.shown=visible;out.hidden=not visible
            end
            if knownBinding then state.frameVisible=visible else state.frameVisible=nil end;state.frameBinding=binding
        else
            state.frameVisible=nil;state.frameBinding=nil
            if status=="missing" then out.found=false end
        end
        return out,status,{found=status=="restricted" and "protected" or nil,visible=status=="restricted" and "protected" or nil}
    end
    if def.dataSource then
        local observation=sample.sources and sample.sources[A.DataSource.Key(n.type,n.config)]
        return G.RuntimeCopy(observation and observation.values or {}),"observed",G.Copy(observation and observation.fields or {})
    end
    if def.soundSink then
        local play,stop=resolve("event"),resolve("stop")
        local sound=BVAddonSuiteCore.Sound
        if run.test then return {played=false,status="test: use Preview sound"},"test suppressed" end
        if stop then sound:Stop(run,id);return {played=false,status="stopped"},"stopped" end
        if play==nil or stop==nil then sound:Stop(run,id);return {played=false,status="unavailable"},"unavailable" end
        if context.reason=="initial" or context.reason=="test" or not play then return {played=false,status="armed"},"armed" end
        local played,status=sound:Play(run,id,n.config)
        return {played=played,status=status},status
    end
    if def.clickAction then
        local values={};for _,f in ipairs(n.config.payload or {}) do values[f.id]=resolve(f.id,true) end
        return {action={kind="click",key=n.config.key,payload=BVAddonSuiteCore.GraphValues.ClickCapture(n.config.payload,values)}},"configured click event"
    end
    if def.actionSource then
        local action
        if def.makeAction then action=def.makeAction(n.config) else action={kind="spell",spellID=n.config.spellID,unit=n.config.target} end
        return {action=action},action and "configured action" or "select an action"
    end
    if def.actionDisplay then
        local bindings={};local count=0
        for _,key in ipairs(BVAddonSuiteCore.Actions.bindingOrder) do
            local input=key=="left" and "action" or "action_"..key
            if ports[input] then local action=resolve(input,true)
                if G.Action(action) and action.kind~="bindings" then bindings[key]=action;count=count+1 end
            end
        end
        if count==0 then return {visible=false},"action unavailable" end
        local action=count==1 and bindings.left or {kind="bindings",bindings=bindings}
        local media=resolve("media",true)
        if ports.highlight and media and resolve("highlight")==true then media=M.Modify(media,"glow",{strength=.5,color="FFD100",size=3,speed=1},{iconStyle="auto",textStyle="soft"}) end
        return {visible=true,media=media,stack={action=action,hoverMedia=resolve("hoverMedia",true),pressedMedia=resolve("pressedMedia",true)}},"prepared click action"
    end
    if def.secureAction then
        return {visible=true,stack={highlight=resolve("highlight")}},"click to cast / self"
    end
    if def.actionStack then
        local reference=resolve("instance",true) or run.instance
        local binding=reference and G.Object(reference,"unitref")
        if reference and (not binding or run.instance and reference~=run.instance) then return nil,"unavailable" end
        if binding then
            local target=n.config.target
            local match=target=="party" and binding.unit:match("^party[1-4]$") or target=="raid" and binding.unit:match("^raid%d+$") or binding.unit==target
            if not match then return nil,"instance / action target mismatch" end
        end
        local media={};for _,element in ipairs(n.config.elements) do media[element.id]=resolve(element.id,true) end
        local spellID=n.config.spellID;local visible=true
        if def.actionMode=="ooc" then
            local override=resolve("spell",true)
            if override~=nil then
                if not G.Number(override) or override<1 or override>2147483647 or override~=math.floor(override) then return {visible=false},"invalid action spell" end
                spellID=override
            elseif G.Binding(run.plan.graph,n.id,"spell") then return {visible=false},"action spell unavailable" end
            visible=resolve("visible")==true
        end
        return {visible=visible,stack={instance=reference,media=media,highlight=resolve("highlight"),spellID=spellID}},"prepared click action"
    end
    if def.displayStack then
        local reference=resolve("instance",true)
        local binding=G.Object(reference,"unitref")
        if not binding or (run.instance and reference~=run.instance) then return nil,"unavailable" end
        local visible=resolve("visible")
        local sort=resolve("sort",true)
        local media={}
        for _,element in ipairs(n.config.elements or {}) do media[element.id]=resolve(element.id,true) end
        return {visible=visible~=false and visible~=nil,stack={instance=reference,sortValue=sort,media=media}},"stack"
    end
    if def.collectionSource then
        local token=A.UnitSource.Token(n.type,n.config,run.instance)
        if not token then state.auraEstimate=nil;return nil,"unavailable" end
        local matches=run.test or A.UnitSource.MatchesRelation(_G,token,n.config.relation)
        if not matches then state.auraEstimate=nil;return nil,"filtered" end
    end
    -- Connected Slot input chooses the roster token for this evaluation.
    local function sourceToken()
        if not A.UnitSource.DynamicSlot(run.plan,id) then return A.UnitSource.Token(n.type,n.config,run.instance) end
        local token=A.UnitSource.SlotToken(n.config,resolve("slot"))
        state.slotToken=token;return token
    end
    if def.auraSource then
        local token=sourceToken()
        local observation=token and run.auras and run.auras[A.AuraSource.Key(n.config.spellID,n.config.filter,token)]
        local values=G.RuntimeCopy(observation and observation.values or {})
        local fields=G.Copy(observation and observation.fields or {})
        presentEstimate(values,fields,observation and observation.status or "unavailable",observation,now)
        auraIcon(run,n,values,fields)
        if G.Number(observation and observation.expirationTime) then values.remaining=math.max(0,observation.expirationTime-now) end
        local unitObservation=token and sample.units and sample.units[token]
        if def.outputs.instance and not (unitObservation and unitObservation.status=="absent") then values.instance=def.collectionSource and run.instance or sample.unitRefs and sample.unitRefs[token] end
        -- Target's source owns its GUID history. Never resurrect an older
        -- per-node baseline after source combat/session reset or unknown GUID.
        if token=="target" and observation and observation.targetEstimateManaged then state.auraEstimate=nil end
        auraTimingEstimate(run,id,n,state,values,fields,observation,token,sample,now)
        if token=="target" then targetMemoryTiming(run,id,state,values,fields,observation,now) end
        return values,observation and observation.status or "unavailable",fields
    end
    if def.unitSource then
        local token=sourceToken()
        if not token then return nil,"unavailable" end
        local key=A.UnitSource.Key(token,n.config)
        local observation=sample.unitQueries and sample.unitQueries[key] or (key==token and (n.type=="player" and sample.player or sample.units and sample.units[token]))
        observation=observation or {}; local values,fields={},{}
        for key in pairs(def.outputs) do
            values[key]=observation.values and observation.values[key]
            fields[key]=observation.fields and observation.fields[key]
        end
        if def.outputs.instance and observation.status~="absent" and not (observation.values and not G.IsSecret(observation.values.exists) and observation.values.exists==false) then
            values.instance=def.collectionSource and run.instance or sample.unitRefs and sample.unitRefs[token]
        end
        if def.sourceFamily=="cast" then
            local event=sample.sourceEvent
            local matched=context.reason=="source_event" and event and event.kind=="unit_cast" and event.unit==token
            if def.outputs.castSucceeded then values.castSucceeded=matched==true;fields.castSucceeded="readable" end
            if def.outputs.succeededSpellID and matched then values.succeededSpellID=event.spellID;fields.succeededSpellID=G.SignalStatus(event.spellID) end
        end
        return G.RuntimeCopy(values),A.UnitSource.SlotStatus(n.config,token) or "observed",G.Copy(fields)
    end
    -- Resolve only the operands needed for a decision. nil is an unavailable
    -- signal, not Boolean false; unused choices cannot invalidate a selection.
    if def.logic then
        if def.logic=="and" or def.logic=="or" then
            local decisive=def.logic=="or"; local unavailable=false
            for i=1,def.count do
                local value=resolve("in"..i)
                if value==decisive then return {result=decisive} end
                if value==nil then unavailable=true end
            end
            if unavailable then return nil,"unavailable" end
            return {result=not decisive}
        elseif def.logic=="not" then
            local value=resolve("value"); if value==nil then return nil,"unavailable" end
            return {result=not value}
        end
        local condition=resolve("condition"); if condition==nil then return nil,"unavailable" end
        local selected=condition and "yes" or "no"
        local value=resolve(def.logic=="select" and selected or "value",true)
        if value==nil then return nil,"unavailable" end
        if def.logic=="select" then return {value=G.RuntimeCopy(value)},condition and "true selected" or "false selected" end
        local out=def.payloadType=="event" and {yes=false,no=false} or {}
        out[selected]=G.RuntimeCopy(value); return out,condition and "true branch" or "false branch",{yes="inactive",no="inactive"}
    end
    for _,key in ipairs({"font","style"}) do
        if ports[key] and run.plan.incoming[id][key] and resolve(key)==nil then return nil,"unavailable" end
    end
    local function styled(media)
        media=M.ApplyStyle(M.ApplyFont(media,args.font),args.style)
        if n.type=="media_bar" then
            for _,key in ipairs({"color","background","borderColor","borderWidth"})do
                if run.plan.incoming[id][key] then media[key]=key=="borderWidth" and args[key] or M.GlowColor(args[key]) end
            end
            assert(M.Valid(media),"Invalid wired bar style")
        end
        return media
    end
    if n.type=="media_bar" and n.config.source=="player_health" then
        for _,key in ipairs({"color","background","borderColor","borderWidth"})do if resolve(key)==nil then return nil,"unavailable" end end
        -- Test sessions use their injected readable sample, never live native APIs.
        if run.test then
            if not G.Number(sample.current) or not G.Number(sample.maximum) or sample.maximum<=0 then return nil,"unavailable" end
            local c=G.Copy(n.config); c.source="values"
            local values=G.Copy(args);values.value=sample.current;values.maximum=sample.maximum
            return {media=styled(M.New("bar",c,values))}
        end
        return {media=styled(M.New("bar",n.config,args))}
    end
    if n.type=="unit_record" then
        local record=resolve("record");if not record then return nil,"unavailable" end
        local value,status=A.UnitData.Project(record,n.config.schema,n.config.field,n.config.index)
        return {value=value,available=status=="readable",status=status},"projected",{value=status}
    end
    if n.type=="media_icon" then
        -- Icon ID output (e.g. for the Toast Note icon input): the connected
        -- texture as is, else the chosen icon when it is a numeric file ID.
        if run.plan.incoming[id].texture then
            local texture=resolve("texture");if texture==nil then return nil,"unavailable" end
            return {media=styled(M.New("icon",n.config,texture)),textureID=texture}
        end
        local ref=BVAddonSuiteCore.IconCatalog:Reference(n.config.texture)
        return {media=styled(M.New("icon",n.config)),textureID=type(ref)=="number" and ref or tonumber(ref)}
    end
    local missing=false
    for key,p in pairs(ports) do
        local unusedDefinition=(p.type=="font" or p.type=="style" or p.type=="symbol" or n.type=="display" and key=="realTime") and not run.plan.incoming[id][key]
        if not unusedDefinition and args[key]==nil and resolve(key)==nil then missing=true end
    end
    if missing then return nil,"unavailable" end
    if n.type=="media_font" then return {font=M.NewFont(n.config)}
    elseif n.type=="media_style" then return {style=M.NewStyle(n.config)}
    elseif n.type=="media_icon" then return {media=styled(M.New("icon",n.config))}
    elseif n.type=="media_graphic" then return {media=styled(M.New("graphic",n.config))}
    elseif n.type=="media_bar" then return {media=styled(M.New("bar",n.config,args))}
    elseif n.type=="bar_duration" or n.type=="icon_duration" then return {media=M.Modify(args.media,n.type,args,n.config)}
    elseif n.type=="icon_cooldown" then
        if run.test then return {media=G.RuntimeCopy(args.media)},"native preview unavailable" end
        return {media=M.Modify(args.media,n.type,args,n.config)}
    elseif n.type=="media_overlay" or n.type=="media_crop" or n.type=="icon_appearance" or n.type=="media_sprite" or n.type=="display_lifecycle" or n.type=="color_overlay" then return {media=M.Modify(args.media,n.type,args,n.config)}
    elseif n.type=="media_interaction" then return {media=M.Modify(args.media,n.type,args,n.config)}
    elseif n.type=="media_button" then return {media=M.AttachSymbol(styled(M.NewButton(n.config,args.text)),args.symbol,n.config)}
    elseif n.type=="media_text" then return {media=M.AttachSymbol(styled(M.New("text",n.config,args.text)),args.symbol,n.config)}
    elseif n.type=="display" then
        local media=args.media
        if run.plan.incoming[id].realTime then
            if resolve("realTime")==nil then return {visible=false},"timer unavailable" end
            if not media or (media.kind~="icon" and media.kind~="bar") then return {visible=false},"timer needs icon or bar" end
            media=M.Modify(media,media.kind=="icon" and "icon_duration" or "bar_duration",{duration=args.realTime},{})
        end
        return {visible=args.visible,media=media},args.visible and "shown" or "hidden"
    elseif ({opacity=true,tint=true,glow=true,scale=true,size=true,offset=true,rotate=true,text_outline=true,text_shadow=true,icon_border=true})[n.type] then return {media=M.Modify(args.media,n.type,args,n.config)}
    elseif n.type=="circle" or n.type=="rotate_offset" then
        local x,y=M.Rotate(n.type=="circle" and args.radius or args.x,n.type=="circle" and 0 or args.y,args.angle)
        return {x=x,y=y}
    elseif n.type=="aura" then
        local observation=run.auras[A.AuraSource.Key(n.config.spellID,n.config.filter)]
        local values=G.RuntimeCopy(observation and observation.values or {}); local fields=G.Copy(observation and observation.fields or {})
        presentEstimate(values,fields,observation and observation.status or "no aura observation",observation,now)
        auraIcon(run,n,values,fields)
        if observation and not G.IsSecret(values.present) and values.present and G.Number(observation.expirationTime) and observation.expirationTime>0 then
            values.remaining=math.max(0,observation.expirationTime-now); fields.remaining="readable"
        end
        auraTimingEstimate(run,id,n,state,values,fields,observation,"player",sample,now)
        return next(values) and values or nil,observation and observation.status or "no aura observation",fields
    elseif n.type=="hp" then
        local values,fields={},{}
        for _,key in ipairs({"current","maximum"}) do
            if G.IsSecret(sample[key]) then values[key]=G.Capture(sample[key],"float")
            elseif G.Number(sample[key]) and sample[key]>=0 then values[key]=sample[key] end
            fields[key]=G.SignalStatus(values[key],sample.hpFields and sample.hpFields[key])
        end
        if G.Number(values.current) and G.Number(values.maximum) and values.maximum>0 then
            values.percent=100*values.current/values.maximum; fields.percent="readable"
        else fields.percent=G.SignalMerge(fields.current,fields.maximum); if fields.percent=="readable" then fields.percent="unavailable" end end
        return values,"observed",fields
    elseif n.type=="context" then
        if G.IsSecret(sample.combat) then return {combat=G.Capture(sample.combat,"boolean")},"observed",{combat="protected"} end
        if type(sample.combat)~="boolean" then return nil,"unavailable" end
        return {combat=sample.combat}
    elseif n.type=="number" or n.type=="boolean" then return {value=n.config.value}
    elseif n.type=="multiply" then return {value=args.value*args.factor}
    elseif n.type=="compare" then return {result=ops[n.config.operator](args.value,args.threshold)}
    elseif n.type=="format" then
        return {text=(args.template:gsub("{value}",function() return string.format("%.2f",args.value) end))}
    elseif n.type=="gate" then
        if args.seconds<0 or args.seconds>86400 then error("Seconds must be 0..86400") end
        local fire=false
        if n.config.mode=="activation" then
            if args.condition then if not state.latched then fire=true; state.latched=true end else state.latched=false end
        elseif args.condition and now>=(state.deadline or -math.huge) then fire=true; state.deadline=now+args.seconds end
        return {event=fire},fire and "triggered" or "blocked"
    elseif n.type=="icon" then return {visible=args.visible},args.visible and "shown" or "hidden"
    elseif n.type=="chat" then
        -- Only a new event observation can cause a side effect, not a text/control update.
        local event=run.plan.incoming[id].event
        if args.event and dirty[event.from] then run.emit(args.text,id,n.config.prefix~=false) end
        return {},args.event and dirty[event.from] and "emitted" or "idle"
    elseif n.type=="chat_send" or n.type=="chat_direct" then
        local event=run.plan.incoming[id].event
        local direct=n.type=="chat_direct"
        local function result(ok,status)return {[direct and "submitted"or"requested"]=ok==true,status=status},status end
        if run.test then return result(false,"test_suppressed") end
        if n.config.permission==false or direct and n.config.permission~=true then return result(false,"disabled_on_node")end
        if context.reason=="initial" or context.reason=="test" or not args.event or not event or not dirty[event.from] then return result(false,"idle") end
        if run.messageDriven then return result(false,"forwarding_blocked") end
        local send=direct and run.sendChat or run.requestChat
        if not send then return result(false,"unsupported") end
        local sent,status=send(id,args.text,n.config)
        return result(sent,status)
    elseif n.type=="message_send" then
        local event=run.plan.incoming[id].event
        local function result(submitted,status,available) return {submitted=submitted,status=status,available=available},status end
        if run.test then return result(false,"test: message suppressed",false) end
        if n.config.permission==false then return result(false,"disabled on node",false)end
        if run.messageDriven then return result(false,"forwarding blocked",false) end
        if not run.send then return result(false,"message service unavailable",false) end
        local allowed,status=true,"ready"
        if run.messageStatus then allowed,status=run.messageStatus(n.config) end
        if not args.event or not dirty[event.from] then return result(false,status,allowed) end
        if not allowed then return result(false,status,false) end
        local sent,sendStatus=run.send(n.config,args.value)
        return result(sent==true,sendStatus,allowed)
    end
end
function R.NeedsClock(run)
    if not run or run.stopped then return false end
    if run.rangeRoots and next(run.rangeRoots) then return true end
    for id in pairs(run.timeRoots) do
        local s=run.state[id]; if s and s.time and s.time.clock then return true end
    end
    for id in pairs(run.estimateClockRoots) do
        local s=run.state[id];if s and s.auraEstimate and s.auraEstimate.clock then return true end
    end
    for id in pairs(run.clockRoots) do
        local n=run.plan.graph.nodes[id];local token=run.plan.definitions[id].auraSource and (A.UnitSource.DynamicSlot(run.plan,id) and run.state[id] and run.state[id].slotToken or A.UnitSource.Token(n.type,n.config,run.instance))
        local o=run.auras[A.AuraSource.Key(n.config.spellID,n.config.filter,token)]
        if o and o.values and not G.IsSecret(o.values.present) and o.values.present and G.Number(o.expirationTime) and o.expirationTime>0
            and not (run.values[id] and run.values[id].remaining==0) then return true end
    end
    return false
end
function R.Begin(run,sample,now,reason)
    if run.stopped then return end
    local started=P.active and P:Begin()
    run.revision=run.revision+1
    if reason=="initial" or reason=="aura" or reason=="test" or reason=="unit" then
        if reason=="initial" or reason=="test" or reason=="aura" then run.auras={} end
        for key,value in pairs(sample.auras or {}) do run.auras[key]=G.RuntimeCopy(value) end
    end
    local dirty={}
    for _,id in ipairs(run.plan.order) do
        local n=run.plan.graph.nodes[id]
        if reason=="initial" or reason=="test" or (n.type=="aura" and (reason=="aura" or reason=="metadata"))
            or ((n.type=="hp" or (n.type=="media_bar" and n.config.source=="player_health")) and reason=="hp")
            or (n.type=="icon_cooldown" and reason=="cooldown") or (n.type=="context" and reason=="context") then dirty[id]=true end
        if run.plan.definitions[id].dataSource and A.DataSource.reasons[n.type]==reason then dirty[id]=true end
        if reason=="dialog:"..id or reason=="node_test:"..id then dirty[id]=true end
        if reason=="frame_state" and run.plan.definitions[id].frameSource and sample.sources and sample.sources["frame_state:"..n.config.reference] then dirty[id]=true end
        if n.type=="player" and ({hp=true,power=true,player_state=true,context=true})[reason] then dirty[id]=true end
        if reason=="unit" and run.plan.definitions[id].unitSource then
            for _,token in ipairs(A.UnitSource.PlanTokens(run.plan,id,n,run.instance)) do
                local key=A.UnitSource.Key(token,n.config)
                if sample.unitQueries and sample.unitQueries[key] or not sample.unitQueries and sample.units and sample.units[token] then dirty[id]=true end
            end
        end
        if run.plan.definitions[id].auraSource and (reason=="aura" or reason=="unit" or reason=="clock" or reason=="metadata") then dirty[id]=true end
        if reason=="message" and n.type=="message_receive" then
            local p=sample.message
            if p and p.topic==n.config.topic and p.kind==n.config.payloadType and p.channel==n.config.channel then dirty[id]=true end
        end
        if reason=="message_reset" and n.type=="message_receive" and n.config.channel~="LOCAL" then dirty[id]=true end
        if reason=="interaction" and n.type=="media_event" and sample.interaction and sample.interaction.key==n.config.key then dirty[id]=true end
        if reason=="source_event" and run.plan.definitions[id].nativeEvent and sample.sourceEvent and sample.sourceEvent.kind==n.type then dirty[id]=true end
        if reason=="source_event" and run.plan.definitions[id].sourceFamily=="cast" then dirty[id]=true end
        if reason=="message_policy" and n.type=="message_send" then dirty[id]=true end
        if reason=="macros" and n.type=="macro_exists" and not run.plan.incoming[id].event then dirty[id]=true end
        if reason=="clock" and run.clockRoots[id] then dirty[id]=true end
        if reason=="clock" and run.rangeRoots and run.rangeRoots[id] then dirty[id]=true end
        if reason=="bossmod" and run.plan.definitions[id].bossmodTimer then dirty[id]=true end
        if reason=="clock" and run.estimateClockRoots[id] then
            local s=run.state[id];if s and s.auraEstimate and s.auraEstimate.clock then dirty[id]=true end
        end
        if reason=="clock" and run.timeRoots[id] then
            local s=run.state[id]; if s and s.time and s.time.clock then dirty[id]=true end
        end
        for _,e in pairs(run.plan.incoming[id]) do
            local auraClock=reason=="clock" and (run.clockRoots[e.from] or run.estimateClockRoots[e.from])
            local timedOutput=e.output=="remaining" and run.clockRoots[e.from]
                or (e.output=="remainingEstimate" or e.output=="presentEstimate" and run.plan.graph.nodes[e.from].config.unit=="target") and run.estimateClockRoots[e.from]
            if dirty[e.from] and not (auraClock and not timedOutput)
                and not (reason=="metadata" and (run.plan.graph.nodes[e.from].type=="aura" or run.plan.definitions[e.from].auraSource) and e.output~="icon") then dirty[id]=true end
        end
    end
    local job={run=run,sample=sample,now=now,reason=reason,dirty=dirty,index=1}
    if P.active then P:Finish("node_begin_ms",started) end
    return job
end
function R.Step(job)
    local run=job.run; if run.stopped then return true end
    local id=run.plan.order[job.index]; if not id then return true end
    job.index=job.index+1
    if job.dirty[id] then
        local evaluateStarted=P.active and P:Begin()
        local context={inputs={},reason=job.reason}
        local ok,value,status,fields=pcall(evaluate,run,id,job.sample,job.now,job.dirty,context)
        if P.active then P:Finish("node_evaluate_ms",evaluateStarted) end
        local publishStarted=P.active and P:Begin()
        if status=="unavailable" and context.missing then status=context.missing end
        if ok then
            if value then
                -- Bypass forwards only its mapped outputs; the others stay empty.
                local def=run.plan.definitions[id]
                local bypassing=(status=="bypass" or status=="bypassed by section") and def.bypass
                for key,p in pairs(def.outputs) do
                    local v=value[key]
                    if not (not G.IsSecret(v) and (p.optional or (bypassing and not def.bypass[key]) or run.test and run.nodeOverrides and run.nodeOverrides[id]) and v==nil)
                        and not (p.type=="event" and not G.IsSecret(v) and type(v)=="boolean" or G.RuntimeAccepts(p.type,v)) then ok=false; value="Invalid output: "..key; break end
                end
            end
        end
        -- Stateful displays must clear on false, Mute, missing input and faults.
        -- Unlike chat, this consumes a Boolean state, never a one-shot event.
        if A.catalog[run.plan.graph.nodes[id].type].display and run.display then
            local shown=ok and value and value.visible==true or false
            local displayed,why=pcall(run.display,id,shown,ok and value and value.media or nil,ok and value and value.stack or nil,run.instance)
            if not displayed then
                pcall(run.display,id,false); ok=false; value=why
            end
        end
        if not ok then
            local s=run.state[id] or {}; run.state[id]=s; s.failures=(s.failures or 0)+1
            s.time=nil
            s.auraEstimate=nil
            s.retryAt=job.now+math.min(30,2^(s.failures-1)); s.paused=s.failures>=5
            local message=not G.IsSecret(value) and type(value)=="string" and value or "Node operation failed (secret or opaque error)"
            run.diagnose(id,message); value=nil; status="faulted"
        elseif value then local s=run.state[id]; if s then s.failures=0; s.retryAt=nil end end
        if P.active then P:Finish("node_publish_ms",publishStarted) end
        local traceStarted=P.active and P:Begin()
        run.values[id]=value
        local signals={}
        for key in pairs(run.plan.definitions[id].outputs) do
            signals[key]=G.SignalStatus(value and value[key],not ok and "faulted" or fields and fields[key] or status)
        end
        run.signals[id]=signals
        run.trace[id]={status=status or (value and "ready" or "unavailable"),values=G.TraceCopy(value),fields=G.TraceCopy(fields),signals=G.Copy(signals),inputs=context.inputs,at=job.now,revision=run.revision}
        if P.active then P:Finish("node_trace_ms",traceStarted) end
    end
    return job.index>#run.plan.order
end
R.NewOne=R.New;R.BeginOne=R.Begin;R.StepOne=R.Step;R.NeedsClockOne=R.NeedsClock
function R.Run(run,sample,now,reason)
    local job=R.Begin(run,sample,now,reason or "test"); if job then while not R.Step(job) do end end
end

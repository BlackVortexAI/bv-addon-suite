local _,A=...
if A.blocked then return end
local G,F=A.G,A.FlowValues
function F.Evaluate(run,id,n,def,state,resolve,context,now)
    if def.flowOperation=="lua" then return A.LuaNode.Evaluate(run,id,n,def,state,resolve,context,now)
    elseif def.flowOperation=="macro_exists" then
        local result={found=false,missing=false,failed=false,status=state.macroStatus or "waiting for check",
            exists=state.macroExists,index=state.macroIndex}
        if run.test or context.reason=="test" then result.status="test suppressed";return result,result.status end
        local automatic=not run.plan.incoming[id].event
        if automatic then
            if context.reason~="initial" and context.reason~="macros" and run.values[id]~=nil then return result,result.status end
        elseif context.reason=="initial" or not resolve("event") then return result,result.status end
        local checked,status=BVAddonSuiteCore.Actions.CheckMacro(n.config.name,n.config.scope)
        result.exists=checked and checked.exists;result.index=checked and checked.index;result.status=status
        local changed=state.macroStatus~=status or state.macroExists~=result.exists or state.macroIndex~=result.index
        -- Startup establishes state only. Native updates pulse on changes;
        -- explicitly wired checks pulse for every fresh request.
        if context.reason~="initial" and (not automatic or changed) then
            result.found=status=="found";result.missing=status=="missing";result.failed=not result.found and not result.missing
        end
        state.macroExists=result.exists;state.macroIndex=result.index;state.macroStatus=status
        return result,status
    elseif def.flowOperation=="macro_write" then
        local actions=BVAddonSuiteCore.Actions;local c=n.config
        if not state.macroArmed then
            local snapshot,why=actions.FindMacro(c.name,c.scope,true)
            state.macroSnapshot=snapshot and G.Copy(snapshot) or nil;state.macroInitialError=why;state.macroArmed=true
        end
        local trigger=resolve("event");local enabled=resolve("enabled")
        local function result(ok,status,attempt,index) return {saved=attempt and ok or false,failed=attempt and not ok or false,success=ok,status=status,index=index},status end
        if run.test or context.reason=="test" then return result(false,"test suppressed",false) end
        if context.reason=="initial" or not trigger then return result(false,"armed",false) end
        if not enabled or c.permission~=true then return result(false,"macro writes disabled",true) end
        if InCombatLockdown() then return result(false,"Save macros outside combat",true) end
        if state.macroInitialError=="Ambiguous macro name in this scope" then return result(false,state.macroInitialError,true) end
        if c.operation=="update" and not state.macroSnapshot then return result(false,"Macro missing; update requires an existing macro",true) end
        if c.operation=="create" and state.macroSnapshot then return result(false,"Name already exists in this scope",true) end
        local body=resolve("body")
        if body==nil then return result(false,"Macro text unavailable",true) end
        local saved,why=actions.SaveMacro(state.macroSnapshot,c.name,c.scope,body)
        if not saved then return result(false,why,true) end
        state.macroSnapshot=G.Copy(saved);state.macroInitialError=nil
        return result(true,"saved",true,saved.index)
    elseif def.flowOperation=="timestamp" then
        local value=resolve("trigger");local edge=value==true and state.timestampHigh~=true
        state.timestampHigh=value==true
        if edge then state.timestampValue=GetServerTime and GetServerTime() or time() end
        return {value=state.timestampValue,event=edge},"ready"
    elseif def.flowOperation=="debounce" then
        local event,seconds=resolve("event"),resolve("seconds")
        if not G.Number(seconds) or seconds<0 or seconds>86400 then return nil,"invalid interval" end
        local passed=false
        if event and context.reason~="initial" then passed=not state.lastEvent or now-state.lastEvent>=seconds;state.lastEvent=now end
        return {event=passed},passed and "passed" or "waiting"
    elseif def.flowOperation=="array" then
        local c=n.config;local op=n.type=="memory_output" and "snapshot" or c.operation
        if op=="snapshot" then
            local event=resolve("event")
            if event and context.reason~="initial" then
                state.arrayValue=F.Snapshot(run,c.valueType,resolve("keys"),c.sort,c.descending)
                return {array=state.arrayValue,count=#state.arrayValue.entries,done=true},"read"
            end
            return {array=state.arrayValue,count=state.arrayValue and #state.arrayValue.entries or 0,done=false},"idle"
        elseif op=="initialize" then
            local array={valueType=c.valueType,entries={}};local seen={}
            for i=1,c.count do
                local key,value=resolve("key"..i),resolve("value"..i)
                if not A.Memory.Key(key) or seen[key] or not G.Accepts(c.valueType,value) then return nil,"invalid or duplicate entry" end
                seen[key]=true;array.entries[i]={key=key,value=value}
            end
            return {array=array,count=#array.entries},"ready"
        end
        local array=resolve("array");if not array then return nil,"unavailable" end
        local function optional(key) if G.Ports(def)[key] then return resolve(key) end end
        local config=G.Copy(c);if op=="set" or op=="add" then config.by="key" end
        return F.Array(config,array,optional("key"),optional("value"),optional("timestamp"),optional("index"))
    elseif def.flowOperation=="dialog" then
        if state.dialogResult then
            local result=state.dialogResult;state.dialogResult=nil
            result.done=true;return result,"completed"
        end
        local event=resolve("event")
        if event and context.reason~="initial" and not state.dialogPending then
            local payload=resolve("payload");if payload==nil then return {done=false},"unavailable" end
            local title,message=resolve("title"),resolve("message")
            local text=n.type=="input_dialog" and resolve("text") or nil
            if title==nil or message==nil then return {done=false},"unavailable" end
            state.dialogPending=true
            A.Dialogs.Open(run,id,n.config,title,message,text,payload,function(confirmed,value)
                state.dialogPending=nil
                if run.stopped then return end
                state.dialogResult={confirmed=confirmed,payload=G.Copy(payload),text=value}
                if run.dialogResume then run.dialogResume(id) end
            end)
        end
        return {done=false},state.dialogPending and "waiting for response" or "idle"
    elseif def.flowOperation=="capture_target" then
        -- A fresh value on Capture triggers one read; events only when fired.
        local value=resolve("capture")
        local fresh
        if run.plan.incoming[id].capture then
            local src=run.plan.definitions[run.plan.incoming[id].capture.from]
            local outType=src and src.outputs[run.plan.incoming[id].capture.output] and src.outputs[run.plan.incoming[id].capture.output].type
            if outType=="event" then fresh=value==true
            else fresh=value~=nil and (context.reason=="initial" or not BVAddonSuiteCore.DisplayModel.Equal(state.captureInput,value)) end
        end
        if value~=nil and not G.IsSecret(value) then state.captureInput=G.RuntimeCopy(value) elseif G.IsSecret(value) then state.captureInput=nil end
        if context.reason=="initial" and not state.captured then fresh=false end
        local out=state.captured or {}
        if not fresh or run.test and context.reason=="test" then
            local copy=G.RuntimeCopy(out);copy.captured=false;return copy,state.captured and "held" or "waiting"
        end
        local c=n.config
        local token=c.unit=="target" and "target" or c.unit=="focus" and "focus" or c.unit=="mouseover" and "mouseover"
            or (c.unit=="party_member" and "party"..c.slot.."target") or ("raid"..c.slot.."target")
        local function read(fn)
            if type(fn)~="function" then return nil end
            local ok,v=pcall(fn,token);if not ok then return nil end
            if G.IsSecret(v) or (issecretvalue and issecretvalue(v)) then return G.Capture(v,"string"),true end
            return v
        end
        local exists=read(UnitExists);if exists~=true and exists~=false then exists=nil end
        local name,nameSecret=read(UnitName);if not nameSecret and (type(name)~="string" or name=="") then name=nil end
        local guid,guidSecret=read(UnitGUID);if not guidSecret and (type(guid)~="string" or guid=="") then guid=nil end
        local prev=state.previousCapture
        local changed
        if prev then
            local a,b
            if not guidSecret and not prev.guidSecret and (guid or prev.guid) then a,b=guid or "",prev.guid or ""
            elseif not nameSecret and not prev.nameSecret and (name or prev.name) then a,b=name or "",prev.name or ""
            elseif exists==false and prev.exists==false then a,b="",""
            end
            if a~=nil then changed=a~=b end
        end
        state.previousCapture={guid=not guidSecret and guid or nil,name=not nameSecret and name or nil,guidSecret=guidSecret,nameSecret=nameSecret,exists=exists}
        out={captured=true,exists=exists,name=name,guid=guid,changed=changed}
        state.captured={exists=exists,name=name,guid=guid,changed=changed}
        return out,"captured"
    elseif def.flowOperation=="symbol" then
        local DM=BVAddonSuiteCore.DisplayModel
        local color=DM.GlowColor(resolve("color") or "FFFFFF")
        if not color or not BVAddonSuiteCore.Symbols:Valid(n.config.symbol) then return nil,"unavailable" end
        local sym={kind="symbol",name=n.config.symbol,color=color}
        return {symbol=sym,media=DM.SymbolMedia(sym)},"ready"
    elseif def.flowOperation=="relay" then
        local value=resolve("value")
        if value==nil then return nil,"unavailable" end
        return {value=value},"ready"
    elseif def.flowOperation=="bossmod_timer" then
        local bar=A.BossMods:Find(n.config)
        if not bar then return {active=false},A.BossMods:Status()=="no boss mod loaded" and "no boss mod loaded" or "no match" end
        local t=GetTime();local remaining=bar.paused and bar.remaining or math.max(0,bar.expiration-t)
        return {active=true,remaining=remaining,duration=bar.duration,expiration=not bar.paused and bar.expiration or nil,startTime=bar.start,paused=bar.paused==true,
            text=bar.text,spellId=bar.spellId,count=bar.count,provider=bar.provider},bar.paused and "paused" or "running"
    elseif def.flowOperation=="unit_range" then
        local token=A.UnitSource.Token("unit",n.config)
        if not token then return nil,"unavailable" end
        local now=GetTime()
        -- The shared 10 Hz clock drives this node; measure at most every interval.
        if context.reason=="clock" and state.range and state.rangeToken==token and now-state.rangeAt<A.RangeCheck.interval then
            return state.rangeOut,state.range.status
        end
        local r=A.RangeCheck.Measure(token,n.config.spellID)
        state.range=r;state.rangeAt=now;state.rangeToken=token
        state.rangeOut={min=r.min,max=r.max,inSpell=r.inSpell,status=r.status}
        return state.rangeOut,r.status
    elseif def.flowOperation=="regex" then
        local c,text=n.config,resolve("text")
        if text==nil then return nil,"unavailable" end
        local X=A.Regex
        if c.operation=="test" then
            local matched,why=X.Test(c.pattern,text,c.ignoreCase)
            if matched==nil then return nil,why end
            return {matched=matched},matched and "matched" or "no match"
        elseif c.operation=="match" then
            local m,why=X.Match(c.pattern,text,c.ignoreCase)
            if not m then return nil,why end
            local out={matched=m.matched,match=m.text}
            for i=1,5 do out["group"..i]=m.groups[i] end
            return out,m.matched and "matched" or "no match"
        end
        local result,count=X.Replace(c.pattern,text,c.replacement,c.replaceAll,c.ignoreCase)
        if result==nil then return nil,count end
        return {result=result,count=count},count.." replaced"
    elseif def.flowOperation=="text_compare" then
        local a,b=resolve("value"),resolve("other")
        local result=A.TextOps.Compare(a,b,n.config.operation,n.config.ignoreCase)
        if result==nil then return nil,"unavailable" end
        return {result=result},result and "true" or "false"
    elseif def.flowOperation=="toast" then
        -- Closed notes resume the run once each; several closures drain in order.
        state.toastClosed=state.toastClosed or {}
        local closed=table.remove(state.toastClosed,1)
        if closed~=nil and #state.toastClosed>0 and run.dialogResume then run.dialogResume(id) end
        local result={closed=closed~=nil,dismissed=closed==true}
        -- One note per fresh Show event; text/setting updates never re-show.
        if context.reason=="initial" or not resolve("event") then return result,closed~=nil and "closed" or "idle" end
        local c=n.config;local icon=resolve("icon")
        if icon==nil and c.icon~="" then icon=BVAddonSuiteCore.IconCatalog:Reference(c.icon) end
        local symbol=resolve("symbol")
        if symbol~=nil and not BVAddonSuiteCore.DisplayModel.Symbol(symbol) then symbol=nil end
        local shown,status=A.Toasts.Show(run,c,resolve("text"),icon,function(dismissed)
            if run.stopped then return end
            state.toastClosed[#state.toastClosed+1]=dismissed==true
            if run.dialogResume then run.dialogResume(id) end
        end,symbol)
        -- Sound follows Play Sound: one playback per note, silent in Test Mode.
        if shown and c.source~="none" and not run.test and context.reason~="test" then BVAddonSuiteCore.Sound:Play(run,id,c) end
        return result,status
    end
end

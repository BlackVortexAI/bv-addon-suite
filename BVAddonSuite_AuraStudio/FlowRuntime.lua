local _,A=...
if A.blocked then return end
local G,F=A.G,A.FlowValues
function F.Evaluate(run,id,n,def,state,resolve,context,now)
    if def.flowOperation=="macro_exists" then
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
    end
end

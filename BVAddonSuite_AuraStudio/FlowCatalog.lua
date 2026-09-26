local _,A=...
if A.blocked then return end
local G=A.G
local function default(kind) if kind=="boolean" then return false elseif kind=="string" then return "" else return 0 end end
local types={"boolean","integer","float","string","timestamp"}
local function port(kind,label,default,order) return {type=kind,label=label,default=default,order=order,optional=true,required=false} end
local function add(id,d) A.catalog[id]=d;A.order[#A.order+1]=id end
add("timestamp",{label="Timestamp",flowOperation="timestamp",inputs={trigger=port("boolean","Trigger",false,1)},outputs={value=port("timestamp","Timestamp",nil,1),event=port("event","Captured",nil,2)},defaults={},fields={},help="Capture epoch seconds once on false-to-true. Hold the timestamp until the next rising edge. False rearms; no continuous clock."})
add("debounce",{label="Debounce",flowOperation="debounce",inputs={event={type="event",label="Trigger",wire=true,required=true},seconds=port("float","Quiet interval (s)",1,2)},outputs={event=port("event","Passed",nil,1)},defaults={},fields={},help="Pass the first fresh event immediately. Suppress further events until the quiet interval since the last event has elapsed. No trailing replay."})
add("macro_exists",{label="Macro Exists",flowOperation="macro_exists",sink=true,
    inputs={event={type="event",label="Check",wire=true,required=false,optional=true,order=1}},
    outputs={exists=port("boolean","Exists",nil,1),found=port("event","Found",nil,2),missing=port("event","Missing",nil,3),
        failed=port("event","Failed",nil,4),status=port("string","Status",nil,5),index=port("integer","Macro index",nil,6)},
    defaults={name="BV Macro",scope="account"},
    fields={{key="name",label="Macro name",type="string"},{key="scope",label="Scope",choices={"account","character"}}},
    validate=function(c)
        if type(c.name)~="string" or #c.name==0 or #c.name>128 or c.name:find("[%c|]") or not ({account=true,character=true})[c.scope] then return false,"Invalid macro target" end
        return true
    end,
    help="Check is optional. Unconnected: read on activation and refresh when WoW reports macro changes, without polling. Connected: read only on fresh Check events. Exists, Status and Macro index retain the last result. Automatic startup establishes state without event pulses; later result changes emit Found, Missing or Failed. Explicit checks emit a result event each time. Connect Exists to a condition, or Missing to Write Macro's Write input with the same name/scope and Create mode. Read failures never mean Missing; duplicate names report Exists=true and Failed without an index. Test never queries. This node never writes or executes macros; the writer still checks conflicts and combat restrictions."})
add("macro_write",{label="Write Macro",flowOperation="macro_write",sink=true,
    inputs={event={type="event",label="Write",wire=true,required=true,order=1},body=port("string","Macro text","",2),enabled=port("boolean","Enabled",true,3)},
    outputs={saved=port("event","Saved",nil,1),failed=port("event","Failed",nil,2),success=port("boolean","Success",nil,3),status=port("string","Status",nil,4),index=port("integer","Macro index",nil,5)},
    defaults={name="BV Target",scope="character",operation="update",permission=false},
    fields={{key="name",label="Macro name",type="string"},{key="scope",label="Scope",choices={"account","character"}},
        {key="operation",label="Write mode",choices={"update","create","upsert"}},{key="permission",label="Allow macro writes",type="boolean"}},
    validate=function(c)
        if type(c.name)~="string" or #c.name==0 or #c.name>128 or c.name:find("[%c|]") or not ({account=true,character=true})[c.scope]
            or not ({update=true,create=true,upsert=true})[c.operation] or type(c.permission)~="boolean" then return false,"Invalid macro target or permission" end
        return true
    end,
    help="A fresh Write event saves Macro text to the configured name and scope outside combat. Enable Allow macro writes explicitly; imports reset it. Update requires an existing macro, Create rejects an existing name, Upsert allows either. The armed snapshot rejects external changes until the graph is reapplied. Saved fires only after native readback matches. Failed reports rejection; there is no retry or combat queue. Test/initial evaluation never writes, and this node never executes the macro. Connect Input Dialog Completed to Write and Confirmed to Enabled to avoid saving on Cancel."})
local base={label="Array",flowOperation="array",inputs={},outputs={},defaults={valueType="string",operation="extract",by="key",sort="insertion",descending=false,count=3},
    help="Execution-local typed string-key collection, up to 64 entries. Edits return an independent array. Set replaces a key, Add rejects duplicate keys. Index starts at 1. Missing timestamps sort last; ties retain order. Arrays cannot be stored in Memory."}
base.resolve=function(c)
    if not A.FlowValues.types[c.valueType] or not ({initialize=true,extract=true,set=true,add=true,remove=true,clear=true,count=true,contains=true,sort=true,snapshot=true})[c.operation]
        or not ({key=true,index=true})[c.by] or not ({insertion=true,key=true,value=true,timestamp=true})[c.sort]
        or type(c.descending)~="boolean" or not G.Number(c.count) or c.count<1 or c.count>64 or c.count%1~=0 then return nil,"Invalid array configuration" end
    local d=G.Copy(base);d.resolve=nil
    d.fields={{key="operation",label="Operation",choices={"initialize","extract","set","add","remove","clear","count","contains","sort"}},{key="valueType",label="Value type",choices=types}}
    local kind="array:"..c.valueType
    d.outputs={array=port(kind,"Array",nil,1),count=port("integer","Count",nil,2)}
    d.inputs={}
    if c.operation=="initialize" then
        d.fields[#d.fields+1]={key="count",label="Entries (1..64)",type="integer"}
        for i=1,c.count do
            d.inputs["key"..i]=port("string","Key "..i,"key"..i,i*2)
            d.inputs["value"..i]=port(c.valueType,"Value "..i,default(c.valueType),i*2+1)
        end
    elseif c.operation=="snapshot" then
        d.label="Memory Output";d.sink=true;d.fields={d.fields[2]}
        d.inputs.event={type="event",label="Read",wire=true,required=true,order=1}
        d.inputs.keys=port("string","Keys (comma separated; empty = all)","",2)
        d.outputs.done=port("event","Done",nil,3)
    else
        d.inputs.array={type=kind,label="Array",wire=true,required=true,order=1}
        if ({extract=true,remove=true,contains=true})[c.operation] then
            d.fields[#d.fields+1]={key="by",label="Find by",choices={"key","index"}}
            d.inputs[c.by]=port(c.by=="key" and "string" or "integer",c.by=="key" and "Key" or "Index",c.by=="key" and "key1" or 1,2)
            d.outputs.found=port("boolean","Found",nil,3)
            if c.operation=="extract" then
                d.outputs.value=port(c.valueType,"Value",nil,4);d.outputs.key=port("string","Key",nil,5);d.outputs.timestamp=port("timestamp","Timestamp",nil,6)
            end
        elseif c.operation=="set" or c.operation=="add" then
            d.inputs.key=port("string","Key","key1",2);d.inputs.value=port(c.valueType,"Value",default(c.valueType),3)
            d.inputs.timestamp=port("timestamp","Timestamp",nil,4)
        end
    end
    if c.operation=="sort" or c.operation=="snapshot" then
        d.fields[#d.fields+1]={key="sort",label="Sort by",choices={"insertion","key","value","timestamp"}}
        d.fields[#d.fields+1]={key="descending",label="Descending",type="boolean"}
    end
    return d
end
add("array",base)
local snapshot=G.Copy(base);snapshot.label="Memory Output";snapshot.sink=true;snapshot.defaults.operation="snapshot"
snapshot.resolve=function(c) local copy=G.Copy(c);copy.operation="snapshot";return base.resolve(copy) end
add("memory_output",snapshot)
for _,kind in ipairs({"confirm_dialog","input_dialog"}) do
    local d={label=kind=="confirm_dialog" and "Confirm Dialog" or "Input Dialog",flowOperation="dialog",layoutOwner=true,sink=true,inputs={},outputs={},defaults={valueType="string",allowCombat=false,anchor="",position="center"},
        fields={{key="valueType",label="Payload type",choices=types},{key="allowCombat",label="Allow in combat",type="boolean"},{key="position",label="Position",choices={"center","layout"},choiceLabels={center="Screen Center",layout="Layout Editor"}}},
        help="Screen Center ignores layout positioning. Layout Editor owns free positioning and anchor links; dialog height follows its content. One dialog on a fresh Trigger. Capture Payload until OK or Cancel. Completed resumes the branch exactly once; Confirmed is false on cancellation. No combat queue. Input never takes keyboard focus automatically in combat. Closing the graph cancels pending UI. Protected follow-up actions retain their own restrictions."}
    d.resolve=function(c)
        if not A.FlowValues.types[c.valueType] or type(c.allowCombat)~="boolean" or type(c.anchor)~="string" or #c.anchor>128 or (c.position~=nil and c.position~="center" and c.position~="layout") then return nil,"Invalid dialog configuration" end
        local out=G.Copy(d);out.resolve=nil
        out.inputs={event={type="event",label="Trigger",wire=true,required=true,order=1},title=port("string","Title","AuraStudio",2),message=port("string","Message","Confirm?",3),payload=port(c.valueType,"Payload",default(c.valueType),4)}
        out.outputs={done=port("event","Completed",nil,1),confirmed=port("boolean","Confirmed",nil,2),payload=port(c.valueType,"Payload",nil,3)}
        if kind=="input_dialog" then out.inputs.text=port("string","Initial text","",5);out.outputs.text=port("string","Text",nil,4) end
        return out
    end
    add(kind,d)
end

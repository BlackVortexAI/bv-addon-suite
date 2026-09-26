local package, A = ...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireRelease then
    A.blocked=true
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BVAddonSuite Core 0.8.51. Update all BV packages together; saved data is preserved.") end
    return
end
if not ns:RequireRelease(package,"0.8.51") then A.blocked=true; return end
A.G=ns.GraphModel
local function port(label,t,default,wire,order) return {label=label,type=t,default=default,wire=wire,required=true,order=order} end
local function logicDefinition(base,config)
    local d=A.G.Copy(base); d.resolve=nil; d.inputs={}; d.outputs={}
    if base.logic=="and" or base.logic=="or" then
        local count=config.count; if count==nil then count=2 end
        if not A.G.Number(count) or count~=math.floor(count) or count<2 or count>16 then return nil,"Input count must be an integer from 2 to 16" end
        d.count=count
        for i=1,count do d.inputs["in"..i]=port("Input "..i,"boolean",base.logic=="and",false,i) end
        d.outputs.result=port("Result","boolean"); d.bypass={result="in1"}
    else
        local t=config.payloadType; if t==nil then t=base.defaults.payloadType end
        if not ({boolean=true,integer=true,float=true,string=true,media=true,event=base.logic=="branch"})[t] then return nil,"Unsupported logic value type" end
        d.payloadType=t
        d.inputs.condition=port("Condition","boolean",false,false,1)
        local fallback
        if t=="boolean" then fallback=false elseif t=="float" or t=="integer" then fallback=0 elseif t=="string" then fallback="" end
        local wire=t=="media" or t=="event"
        if base.logic=="select" then
            d.inputs.yes=port("If true",t,fallback,wire,2); d.inputs.no=port("If false",t,fallback,wire,3)
            d.outputs.value=port("Value",t)
        else
            d.inputs.value=port("Value",t,fallback,wire,2)
            d.outputs.yes=port("Condition True",t,nil,nil,1); d.outputs.yes.optional=true
            d.outputs.no=port("Condition False",t,nil,nil,2); d.outputs.no.optional=true
        end
    end
    return d
end
A.catalog={
    debug_value={label="Debug / Inspect value",sink=true,debugPreview=true,transparentInput="value",secretInputs={value=true},
        inputs={value=port("Value","any",nil,true,1)},outputs={value={label="Value",type="any",optional=true}},defaults={},
        help="Inspect a value directly on the graph. The output preserves the connected source type and value. Select a specific nameplate context; recycled slots require reselection. Secret values stay opaque. The bounded preview updates only while the editor is visible and is never saved or logged."},
    timer={label="Timer",clock=true,inputs={start=port("Start (s)","float",10,false,1),target=port("Target (s)","float",0,false,2),active=port("Active","boolean",true,false,3),reset=port("Reset","event",nil,true,4)},
        outputs={value=port("Time (s)","float",nil,nil,1),running=port("Running","boolean",nil,nil,2),finished=port("Finished","event",nil,nil,3)},defaults={},
        help="Counts from Start to Target at one second per second, up or down. Shared 10 Hz updates use elapsed time, not tick counts. Active=false resets to Start. Reset is an event; changing Start or Target restarts. Finished fires once, including equal endpoints. Mute or unavailable controls clear the timer. Start/Target: 0..86400 seconds."},
    remaining_estimate={label="Remaining estimate",clock=true,inputs={value=port("Remaining (s)","float",nil,true,1),active=port("Active","boolean",nil,true,2)},
        outputs={value=port("Time (s)","float",nil,nil,1),estimated=port("Estimated","boolean",nil,nil,2)},defaults={},
        help="Explicit estimate, NOT recovered secret data. Readable seconds pass through and synchronize the baseline. While Active=true and Remaining is nil, count down from the last readable sample timestamp. Without a baseline, output stays nil. False/unknown Active or Mute clears history. Hidden refreshes cannot be detected; zero does not prove the aura ended. Use Estimated to identify the fallback. Remaining: 0..86400 seconds."},
    interval={label="Interval trigger",clock=true,inputs={seconds=port("Interval (s)","float",300,false,1),active=port("Active","boolean",true,false,2),reset=port("Reset","event",nil,true,3),immediate=port("Fire immediately","boolean",false,false,4)},
        outputs={event=port("Trigger","event",nil,nil,1)},defaults={},
        help="Autonomous repeating trigger while Active=true. First pulse after the interval, optionally immediately on start/reset. Active=false, Mute or unavailable controls clear the schedule. Changing interval/immediate restarts. Missed intervals are skipped, never replayed in a burst. Shared 10 Hz clock; interval: 0.1..86400 seconds."},
    secret={label="Secret",inputs={},outputs={},secretInputs={value=true},defaults={payloadType="float"},
        fields={{key="payloadType",label="Value type",choices={"boolean","integer","float","string","media","event"}}},
        help="Inspect a value without reading secret contents. Value passes readable data or an opaque secret payload unchanged. Is Secret is true for secret fields; Is Available means readable/accessibility and remains false for secret data. Secret numbers and text may feed String Formatter and compatible native display inputs without becoming readable. No ordinary math, comparisons, tracing or storage of secret contents. Mute suppresses this node too."},
    constant_nil={label="Nil",source=true,inputs={},outputs={value=port("Nil","nil")},defaults={},
        help="Explicitly outputs no value. Connect to a value input, including an If / Else choice. A connected Nil never uses the input's local default. It does not emit an event."},
    is_nil={label="Is Nil",inputs={value=port("Value","any",nil,true,1)},outputs={result=port("Is Nil","boolean")},defaults={},
        help="True when the connected output is missing, including explicit Nil, missing observations, Mute or faults. False for readable 0, false and empty text. A transported secret scalar cannot be tested for Nil: the result stays secret. Use Secret to inspect accessibility. Requires a connection; Mute suppresses this node."},
    boolean={label="Boolean",source=true,inputs={},outputs={value=port("Value","boolean")},defaults={value=false},fields={{key="value",label="Value",type="boolean"}}},
    logic_not={label="NOT / Invert",logic="not",inputs={value=port("Value","boolean",false,false,1)},outputs={result=port("Result","boolean")},bypass={result="value"},defaults={},
        help="Invert a Boolean: true becomes false, false becomes true. Unavailable stays unavailable. Bypass passes the original value."},
    aura={label="Player aura",source=true,inputs={},outputs={present=port("Present","boolean",nil,nil,1),stacks=port("Stacks","integer",nil,nil,2),duration=port("Duration (s)","float",nil,nil,3)},defaults={spellID=0,filter="HELPFUL"},fields={{key="spellID",label="Aura / Spell ID",type="integer",picker="aura"},{key="filter",label="Aura type",choices={"HELPFUL","HARMFUL"}}}},
    hp={label="Player HP",source=true,inputs={},outputs={current=port("HP","float",nil,nil,1),maximum=port("Maximum","float",nil,nil,2),percent=port("Percent","float",nil,nil,3)},defaults={}},
    number={label="Number",source=true,inputs={},outputs={value=port("Value","float")},defaults={value=1},fields={{key="value",label="Value",type="float"}}},
    multiply={label="Multiply",inputs={value=port("Value","float",nil,true,1),factor=port("Factor","float",3,false,2)},outputs={value=port("Result","float")},bypass={value="value"},defaults={}},
    compare={label="Compare",inputs={value=port("Value","float",nil,true,1),threshold=port("Threshold","float",50,false,2)},outputs={result=port("Condition","boolean")},defaults={operator="<"},fields={{key="operator",label="Operator",choices={"<","<=",">",">=","==","~="}}}},
    context={label="In combat?",source=true,inputs={},outputs={combat=port("In combat","boolean")},defaults={}},
    gate={label="Emission control",inputs={condition=port("Condition","boolean",nil,true,1),seconds=port("Seconds","float",10,false,2)},outputs={event=port("Trigger","event")},defaults={mode="activation"},fields={{key="mode",label="Mode",choices={"activation","timed"}}}},
    format={label="Format text",inputs={value=port("Value","float",nil,true,1),template=port("Template","string","HP: {value}%",false,2)},outputs={text=port("Text","string")},defaults={}},
    chat={label="System message",sink=true,inputs={event=port("Trigger","event",nil,true,1),text=port("Message","string","AuraStudio",false,2)},outputs={},defaults={prefix=true},
        fields={{key="prefix",label="BV prefix",type="boolean",optional=true,default=true}},help="Local output in your chat frame only. BV prefix is optional; legacy graphs keep it enabled. Test output always retains its Test marker. Never sends a message to another player."},
    icon={label="Display icon",sink=true,display=true,inputs={visible=port("Visible","boolean",nil,true,1)},outputs={},
        defaults={texture="134400"},fields={{key="texture",label="Icon",type="string",picker="icon"}}},
}
do
    local all={}
    for i,entry in ipairs({{"health","Health","float"},{"healthMax","Max health","float"},{"healthPercent","Health (%)","float"},
        {"power","Primary power","float"},{"powerMax","Max primary power","float"},{"powerType","Power type","integer"},{"powerToken","Power token","string"},
        {"mounted","Mounted","boolean"},{"resting","Resting","boolean"},{"moving","Moving","boolean"},{"combat","In combat","boolean"},
        {"mana","Mana","float"},{"manaMax","Max mana","float"},{"rage","Rage","float"},{"rageMax","Max rage","float"},
        {"energy","Energy","float"},{"energyMax","Max energy","float"},{"focus","Focus","float"},{"focusMax","Max focus","float"},
        {"comboPoints","Combo points","float"},{"comboPointsMax","Max combo points","float"},{"runicPower","Runic power","float"},{"runicPowerMax","Max runic power","float"}}) do
        all[entry[1]]=port(entry[2],entry[3],nil,nil,i);all[entry[1]].optional=true;all[entry[1]].maySecret=true
    end
    local fieldKeys={};for key in pairs(A.UnitDataCatalog.fields) do fieldKeys[#fieldKeys+1]=key end;table.sort(fieldKeys)
    for _,key in ipairs(fieldKeys) do if not all[key] then
        local field=A.UnitDataCatalog.fields[key];all[key]=port(field.label,field.type,nil,nil,100+#fieldKeys)
        all[key].order=100+_;all[key].optional=true;all[key].maySecret=true
    end end
    for i,field in ipairs({{"classIcon","Class icon","media"},{"classColor","Class color (hex)","string"},
        {"classRed","Class red (0..1)","float"},{"classGreen","Class green (0..1)","float"},{"classBlue","Class blue (0..1)","float"},{"roleIcon","Role icon","media"}}) do
        all[field[1]]=port(field[2],field[3],nil,nil,40+i);all[field[1]].optional=true
    end
    all.groupRolesAssigned.label="Assigned role"
    for i,field in ipairs({{"moneyCopper","Money (copper)","integer"},{"xpCurrent","XP","integer"},{"xpMaximum","XP maximum","integer"},{"xpRested","Rested XP","integer"},{"xpLevel","Level","integer"},{"xpDisabled","XP disabled","boolean"},{"xpCapped","At level cap","boolean"}}) do
        all[field[1]]=port(field[2],field[3],nil,nil,60+i);all[field[1]].optional=true;all[field[1]].maySecret=true;all[field[1]].playerOnly=true
    end
    for _,entry in ipairs(A.UnitDataCatalog.entries) do if entry.playerOnly then for _,field in ipairs(entry.outputs) do if all[field.key] then all[field.key].playerOnly=true end end end end
    local base={label="Player",source=true,inputs={},outputs={},selectableOutputs=all,outputSelectionKey="outputs",
        defaults={outputs={health=true,healthMax=true,power=true,powerMax=true}},fields={},
        help="One player source with selectable outputs. Named resources may be used simultaneously; Primary power follows the current resource. Only connected fields are sampled, once per event across graphs. Health percent uses the native percentage API; an unavailable API may use readable health/max only. Missing client enums/APIs remain unsupported. Secret fields travel as opaque runtime handles for compatible native display inputs. String Formatter supports secret numbers/text for display only; their contents cannot be compared, traced or saved. Existing HP and Player state graphs remain compatible."}
    base.resolve=function(config)
        local selected=config.outputs
        if type(selected)~="table" then return nil,"Select player outputs" end
        for key,value in pairs(selected) do if not all[key] or value~=true then return nil,"Unknown player output selection" end end
        local d=A.G.Copy(base);d.resolve=nil;d.outputs={}
        for key in pairs(selected) do d.outputs[key]=A.G.Copy(all[key]) end
        return d
    end
    A.catalog.player=base
end
A.catalog.player.unitSource=true
for _,entry in ipairs({{"target","Target"},{"focus","Focus"},{"target_target","Target of Target"},
    {"focus_target","Target of Focus"},{"party_member","Party Member",4},{"raid_member","Raid Member",40},{"pet","Pet"},{"nameplate","Nameplate Slot",40}}) do
    local all=A.G.Copy(A.catalog.player.selectableOutputs)
    all.mounted=nil;all.resting=nil;all.moving=nil
    all.exists=port("Exists","boolean",nil,nil,0);all.exists.optional=true;all.exists.maySecret=true
    local base={label=entry[2],source=true,unitSource=true,unitKind=entry[1],slotMax=entry[3],inputs={},outputs={},selectableOutputs=all,outputSelectionKey="outputs",
        defaults={outputs={exists=true,health=true,healthMax=true,power=true,powerMax=true}},fields={},
        help="Event-driven unit binding. Exists=false clears all other values; inaccessible existence stays unknown/secret. Health and power are classified per field. Named resource outputs depend on client enum/API support. Target/focus/roster changes discard old queued observations and displays. Party/Raid slot identifies the current roster slot, never a permanent person. No name/GUID cache or player-only mounted/resting/moving queries. Nameplate slots are temporary visible bindings; recycling does not preserve mob identity."}
    if entry[3] then base.defaults.slot=1;base.fields={{key="slot",label=entry[1]=="nameplate" and "Plate slot" or "Roster slot",type="integer"}} end
    base.resolve=function(config)
        if type(config.outputs)~="table" then return nil,"Select unit outputs" end
        if base.slotMax and (not A.G.Number(config.slot) or config.slot~=math.floor(config.slot) or config.slot<1 or config.slot>base.slotMax) then return nil,(base.unitKind=="nameplate" and "Plate slot" or "Roster slot").." must be 1.."..base.slotMax end
        local d=A.G.Copy(base);d.resolve=nil;d.outputs={}
        for key,value in pairs(config.outputs) do
            if not all[key] or value~=true then return nil,"Unknown unit output selection" end
            d.outputs[key]=A.G.Copy(all[key])
        end
        if base.slotMax then d.label=base.label.." "..config.slot end
        return d
    end
    A.catalog[entry[1]]=base
end
for _,kind in ipairs({"player","target","focus","target_target","focus_target","party_member","raid_member","pet","nameplate"}) do
    local base=A.catalog[kind];local resolve=base.resolve
    for _,entry in ipairs({{"spellID","Query spell ID",0},{"auraIndex","Aura index",1},{"controlIndex","Control index",1},{"statIndex","Stat index",1},{"interactionIndex","Interact index",1},{"damageClass","Damage class ID",0}}) do
        base.defaults[entry[1]]=entry[3]
        base.fields[#base.fields+1]={key=entry[1],label=entry[2],type="integer",optional=true,default=entry[3],advanced=true}
    end
    base.defaults.spellName="";base.fields[#base.fields+1]={key="spellName",label="Query spell name",type="string",optional=true,default="",advanced=true}
    base.resolve=function(config)
        for key,default in pairs(A.UnitDataCatalog.queryDefaults) do
            local value=config[key];if value==nil then value=default end
            if key=="spellName" then
                if type(value)~="string" or #value>160 then return nil,"Query spell name must be at most 160 bytes" end
            else
            local max=key=="spellID" and 100000000 or key=="damageClass" and 7 or key=="statIndex" and 5 or key=="interactionIndex" and 4 or 40
            if not A.G.Number(value) or value~=math.floor(value) or value<((key=="spellID" or key=="damageClass") and 0 or 1) or value>max then return nil,"Invalid unit query "..key end
            end
        end
        return resolve(config)
    end
end
do
    local base=A.catalog.secret
    base.resolve=function(config)
        local t=config.payloadType; if t==nil then t="float" end
        if not ({boolean=true,integer=true,float=true,string=true,media=true,event=true})[t] then return nil,"Unsupported Secret value type" end
        local d=A.G.Copy(base); d.resolve=nil
        d.inputs={value=port("Value",t,nil,true,1)}
        d.outputs={value=port("Value",t,nil,nil,1),isSecret=port("Is Secret","boolean",nil,nil,2),available=port("Is Available","boolean",nil,nil,3)}
        d.outputs.value.optional=true; d.outputs.isSecret.optional=true
        return d
    end
end
for _,kind in ipairs({"and","or","select","branch"}) do
    local d={label=({["and"]="AND",["or"]="OR",select="If / Else",branch="Branch"})[kind],logic=kind,inputs={},outputs={},fields={}}
    if kind=="and" or kind=="or" then
        d.defaults={count=2}; d.fields={{key="count",label="Input count",type="integer",optional=true,default=2}}
        d.help="2..16 Boolean inputs. Add/remove the last input in details. AND: false decides; OR: true decides. Otherwise an unavailable input leaves the result unavailable. Bypass passes Input 1. Connected inputs must be disconnected before removal."
    else
        d.defaults={payloadType=kind=="branch" and "event" or "float"}
        local choices={"boolean","integer","float","string","media"}; if kind=="branch" then choices[#choices+1]="event" end
        d.fields={{key="payloadType",label="Value type",choices=choices,optional=true,default=d.defaults.payloadType}}
        d.help=kind=="select" and "Select If true or If false using Condition. Only the chosen value is read; unavailable Condition does not choose either. Media inputs require wires. Upstream nodes still run; this selects values, not execution of whole subgraphs."
            or "Route Value to the True or False output. The other state output is unavailable, so displays clear. Events are routed only on a new upstream event, never replayed by changing Condition. This does not prevent upstream execution."
    end
    local base=d; d.resolve=function(config) return logicDefinition(base,config) end
    A.catalog["logic_"..kind]=d
end
local pivots={"CENTER","TOPLEFT","TOP","TOPRIGHT","LEFT","RIGHT","BOTTOMLEFT","BOTTOM","BOTTOMRIGHT"}
local function mediaPort() return port("Media","media",nil,true,1) end
local function definitionPort(label,kind,order)
    local p=port(label,kind,nil,true,order);p.required=false;p.optional=true;return p
end
for _,operation in ipairs({"set","get","delete","clear"}) do
    local typed=operation=="set" or operation=="get"
    local base={label="Memory "..operation,sink=true,memoryOperation=operation,secretInputs={instance=true},
        inputs={},outputs={},defaults=typed and {valueType="string"} or {},fields=typed and {
            {key="valueType",label="Value type",choices={"boolean","integer","float","string","timestamp"}}} or {},
        help="Temporary memory in this graph runtime only. Each nameplate instance has its own map. Connect fresh Trigger pulses; chain Done to the next Trigger for explicit ordering. Up to 64 keys (1..64 bytes), readable scalar values only; text up to 1024 bytes. No secrets, tables or persistence. Apply, disable, Test end and profile changes clear memory. Get is a triggered snapshot, not a live subscription. Found distinguishes missing from false, zero and empty text. A different stored type reports type_mismatch without conversion."}
    base.resolve=function(config)
        if typed and not ({boolean=true,integer=true,float=true,string=true,timestamp=true})[config.valueType] then return nil,"Choose a scalar memory value type" end
        local d=A.G.Copy(base);d.resolve=nil
        d.inputs={event=port("Trigger","event",nil,true,1)}
        d.inputs.instance=port("Instance (optional)","unitref",nil,true,9);d.inputs.instance.required=false
        if operation~="clear" then d.inputs.key=port("Key","string","value",false,2) end
        d.outputs={done=port("Done","event",nil,nil,1),status=port("Status","string",nil,nil,4)}
        if operation=="set" then
            local value=0;if config.valueType=="boolean" then value=false elseif config.valueType=="string" then value="" end
            d.inputs.value=port("Value",config.valueType,value,false,3)
            d.inputs.timestamp=port("Timestamp","timestamp",nil,true,4);d.inputs.timestamp.required=false
            d.outputs.success=port("Stored","boolean",nil,nil,2)
        elseif operation=="get" then
            d.outputs.value=port("Value",config.valueType,nil,nil,2);d.outputs.value.optional=true
            d.outputs.found=port("Found","boolean",nil,nil,3);d.outputs.found.optional=true
        elseif operation=="delete" then d.outputs.removed=port("Removed","boolean",nil,nil,2);d.outputs.removed.optional=true
        else d.outputs.removed=port("Removed count","integer",nil,nil,2);d.outputs.removed.optional=true end
        return d
    end
    A.catalog["memory_"..operation]=base
end
A.catalog.media_font={label="Font definition",source=true,inputs={},outputs={font=port("Font","font",nil,nil,1)},
    defaults={family="ysabeau",size=20,outline="NONE"},fields={
        {key="family",label="Font",type="string",options="fonts"},{key="size",label="Font size",type="float"},
        {key="outline",label="Outline",choices={"NONE","OUTLINE","THICKOUTLINE"}}},
    help="Reusable readable font definition for Text media and Media text overlay. The wired definition replaces the local family, size and outline. SharedMedia references identify registered fonts, not arbitrary filesystem fonts; recipients need the same resource. Missing resources preserve the selection and render an explicitly reported fallback."}
A.catalog.frame_state={label="Frame state",source=true,frameSource=true,inputs={},
    outputs={found=port("Found","boolean",nil,nil,1),visible=port("Visible","boolean",nil,nil,2),shown=port("Shown","event",nil,nil,3),hidden=port("Hidden","event",nil,nil,4),state=port("State","string",nil,nil,5)},
    defaults={reference=""},fields={{key="reference",label="Frame",type="string",options="frameLibrary"}},
    help="Observe a frame selected from the shared Frame Library. The portable path is retained even while its addon is not loaded. Ready/hidden frames have Found=true and readable Visible; missing has Found=false; pending, restricted and invalid never invent Boolean values. Shown/Hidden pulse only between observed readable visible and hidden states, never on initial observation or across unavailable states. Read-only, shared bounded observation; no native actions, foreign hooks or separate timer. An empty selection is unconfigured."}
A.catalog.frame_state.outputs.found.optional=true;A.catalog.frame_state.outputs.visible.optional=true
A.catalog.format_values={label="Format text",formatValues=true,inputs={},outputs={text=port("Text","string",nil,nil,1),visible=port("Visible","boolean",nil,nil,2)},
    defaults={count=2,decimals=0,hideZero=false,hideOne=false},fields={
        {key="count",label="Value inputs (1..16)",type="integer"},{key="decimals",label="Decimal places (0..6)",type="integer"},
        {key="hideZero",label="Hide if Value 1 is zero",type="boolean"},{key="hideOne",label="Hide if Value 1 is one",type="boolean"}},
    help="Combine 1..16 readable scalar values using {1} through {16}, or {value1} through {value16}. {percent} computes 100 * Value 1 / Value 2 with positive maximum; {time1} through {time16} format nonnegative seconds as m:ss (up to one day). Only referenced inputs are required. Decimal places apply to numbers and percent. Optional zero/one suppression checks numeric Value 1 and returns empty text plus Visible=false. Unknown tokens remain literal. Missing, secret or nonscalar referenced values leave text unavailable. Output is bounded to 1024 bytes; no Lua or user patterns execute."}
A.catalog.format_values.resolve=function(config)
    if not A.G.Number(config.count) or config.count~=math.floor(config.count) or config.count<1 or config.count>16 then return nil,"Value input count must be 1..16" end
    if not A.G.Number(config.decimals) or config.decimals~=math.floor(config.decimals) or config.decimals<0 or config.decimals>6 then return nil,"Decimal places must be 0..6" end
    local d=A.G.Copy(A.catalog.format_values);d.resolve=nil
    d.inputs={template=port("Template","string","{value1} / {value2}",false,1)}
    for i=1,config.count do d.inputs["value"..i]=port("Value "..i,"any","",false,1+i);d.inputs["value"..i].required=false end
    return d
end
-- Existing format_values nodes keep their calculation and suppression contract.
-- New graphs use composition-only formatting and explicit utility nodes.
A.catalog.string_formatter={label="String Formatter",stringFormatter=true,category="math",inputs={},outputs={text=port("Text","string",nil,nil,1)},
    defaults={count=2},minCount=1,maxCount=16,fields={{key="count",label="Value inputs (1..16)",type="integer"}},
    help="Combine text with {1} through {16}, or {value1} through {value16}. Only referenced inputs are needed; unknown tokens remain literal. Readable strings, numbers and booleans are supported. Secret numeric/text values may continue through the native display-only text path when the client supports it; the result stays secret and cannot be used as readable text. Use Round for decimal places, Math for percent, Time Format for seconds and logic for conditions. No calculations or visibility output."}
A.catalog.string_formatter.resolve=function(config)
    if not A.G.Number(config.count) or config.count~=math.floor(config.count) or config.count<1 or config.count>16 then return nil,"Value input count must be 1..16" end
    local d=A.G.Copy(A.catalog.string_formatter);d.resolve=nil
    d.inputs={template=port("Template","string","{1} / {2}",false,1)}
    for i=1,config.count do d.inputs["value"..i]=port("Value "..i,"any","",false,1+i);d.inputs["value"..i].required=false end
    return d
end
A.catalog.round={label="Round",roundValue=true,category="math",inputs={value=port("Value","float",0,false,1)},
    outputs={value=port("Number","float",nil,nil,1),text=port("Text","string",nil,nil,2),success=port("Successful","boolean",nil,nil,3)},
    defaults={operation="round",decimals=0},fields={{key="operation",label="Operation",choices={"round","floor","ceil"}},{key="decimals",label="Decimal places (0..6)",type="integer"}},
    help="Round a readable number to 0..6 decimal places. Round resolves halfway values away from zero; Floor goes toward negative infinity and Ceil toward positive infinity. Number is the rounded numeric value; Text preserves exactly the requested decimal places, including trailing zeros. Both outputs represent the same rounded result. Secret values are not calculated. Scaled magnitudes above 4503599627370495 are rejected to avoid unreliable integer rounding."}
A.catalog.round.outputs.value.optional=true;A.catalog.round.outputs.text.optional=true
A.catalog.round.resolve=function(config)
    if not ({round=true,floor=true,ceil=true})[config.operation] then return nil,"Choose Round, Floor or Ceil" end
    if not A.G.Number(config.decimals) or config.decimals~=math.floor(config.decimals) or config.decimals<0 or config.decimals>6 then return nil,"Decimal places must be 0..6" end
    local d=A.G.Copy(A.catalog.round);d.resolve=nil;return d
end
A.catalog.time_format={label="Time Format",timeFormat=true,category="time",inputs={value=port("Seconds","float",0,false,1)},
    outputs={text=port("Text","string",nil,nil,1),success=port("Successful","boolean",nil,nil,2)},defaults={},
    help="Format readable seconds from 0 through 86400 as m:ss. Fractions round to the nearest second; 59.5 becomes 1:00. Invalid or secret values produce no text. This node formats a supplied observation; it does not estimate remaining time."}
A.catalog.time_format.outputs.text.optional=true
A.catalog.last_unprotected_value={label="Last Non-Secret Value",lastUnprotectedValue=true,transparentInput="value",category="memory",
    inputs={value=port("Value","any",nil,true,1),reset=port("Reset","boolean",false,false,2)},
    outputs={value=port("Value","any",nil,nil,1),cached=port("Using cached value","boolean",nil,nil,2)},defaults={},
    help="Remember the last readable scalar (number, boolean or text) in this node runtime. Readable false, zero and empty text replace the stored value. Only a Secret input reuses it and sets Using cached value=true; without a previous value the output remains unavailable. Missing/nil input clears the cache. Reset=true takes priority over input; unavailable Reset and Mute also clear it. Apply, disable, Test end and profile changes discard runtime state. Cached values are old observations, never recovered secret data."}
A.catalog.last_unprotected_value.outputs.value.optional=true
A.catalog.media_style={label="Style definition",source=true,inputs={},outputs={style=port("Style","style",nil,nil,1)},
    defaults={color="FFFFFFFF",background="00000000",borderColor="00000000",borderWidth=0,alpha=1},fields={
        {key="color",label="Fill / text color",type="string",picker="color"},{key="background",label="Background",type="string",picker="color"},
        {key="borderColor",label="Border color",type="string",picker="color"},{key="borderWidth",label="Border width",type="float"},
        {key="alpha",label="Opacity",type="float"}},
    help="Reusable readable style for icons, graphics, text and bars. A wired style replaces local fill/text color, background, border and opacity; later media modifiers still apply. Fill alpha affects content; opacity affects the entire element. Transparent background/border are preserved. No font, texture, geometry or input behavior is changed."}
A.catalog.media_icon={label="Icon media",source=true,secretInputs={texture=true},inputs={texture=port("Texture ID","integer",134400,false,1)},outputs={media=mediaPort()},defaults={texture="134400"},fields={{key="texture",label="Icon",type="string",picker="icon"}}}
A.catalog.media_bar={label="Bar media",source=true,secretInputs={value=true,maximum=true},inputs={value=port("Value","float",65,false,1),maximum=port("Maximum","float",100,false,2)},outputs={media=mediaPort()},
    defaults={source="values",direction="RIGHT",texture="flat",background="16131CCC",borderColor="000000FF",borderWidth=1},fields={
        {key="direction",label="Fill direction",choices={"RIGHT","LEFT","UP","DOWN"}},
        {key="texture",label="Texture",type="string",options="statusbars"}},
    help="Fixed layout frame with four fill directions. Connect Unit values to Value/Maximum. Secret numbers pass only to native StatusBar setters. Background, border color and border width accept graph inputs or local values. Style replaces local styling; individually wired style inputs override Style, and later media modifiers still apply. Existing player-health bars migrate to a Unit source when graph capacity permits; full graphs retain their health binding. Rotation is unsupported for bars."}
A.catalog.media_bar.inputs.background=port("Background color","string","16131CCC",false,4)
A.catalog.media_bar.inputs.borderColor=port("Border color","string","000000FF",false,5)
A.catalog.media_bar.inputs.borderWidth=port("Border width","float",1,false,6)
A.catalog.media_bar.inputs.background.picker="color"
A.catalog.media_bar.inputs.borderColor.picker="color"
A.catalog.media_bar.resolve=function(config)
    local d=A.G.Copy(A.catalog.media_bar);d.resolve=nil
    for _,key in ipairs({"background","borderColor","borderWidth"})do
        if config[key]~=nil then d.inputs[key].default=config[key] end
    end
    return d
end
A.catalog.icon_cooldown={label="Icon cooldown",inputs={media=mediaPort()},outputs={media=mediaPort()},bypass={media="media"},
    defaults={spellID=1,showNumbers=true},fields={{key="spellID",label="Spell ID",type="integer"},{key="showNumbers",label="Native countdown",type="boolean"}},
    help="Native spell cooldown overlay on icon media. Duration objects stay inside the renderer adapter. Availability and countdown appearance require target-client support; unavailable bindings clear the overlay. Isolated Test does not query live cooldowns."}
A.catalog.media_overlay={label="Media text overlay",inputs={media=mediaPort(),text=port("Text","string","",false,2),color=port("Color (hex)","string","FFFFFFFF",false,3),x=port("Offset X","float",0,false,4),y=port("Offset Y","float",0,false,5)},
    outputs={media=mediaPort()},bypass={media="media"},defaults={font="ysabeau",fontSize=16,point="BOTTOMRIGHT",outline="OUTLINE"},fields={
        {key="font",label="Font",type="string",options="fonts",advanced=true},
        {key="fontSize",label="Font size",type="float"},{key="point",label="Position",choices=pivots},
        {key="outline",label="Outline",choices={"NONE","OUTLINE","THICKOUTLINE"},advanced=true}},
    help="Text over media. Connect String Formatter for readable aura stacks or item counts, or supported secret numbers/text through the native display-only path. Secret text stays opaque. Missing wired text invalidates the branch. Position reserves the existing layout frame."}
A.catalog.media_graphic={label="Graphic file",source=true,inputs={},outputs={media=mediaPort()},
    defaults={path="Interface\\AddOns\\BVAddonSuite\\Media\\Brand\\bv-logo-small.tga",left=0,right=1,top=0,bottom=1},fields={
        {key="path",label="Graphic path",type="string"},
        {key="left",label="Crop left (0..1)",type="float",advanced=true},{key="right",label="Crop right (0..1)",type="float",advanced=true},
        {key="top",label="Crop top (0..1)",type="float",advanced=true},{key="bottom",label="Crop bottom (0..1)",type="float",advanced=true}},
    help="Local TGA/BLP path below Interface\\AddOns\\<Addon>\\. Paths cannot traverse folders. Graph transfer carries the reference only; recipients need the asset installed separately. No filesystem browsing or image copying. Missing assets clear the graphic and report renderer availability."}
local dataDefinitions={
    player_xp={label="Player experience",outputs={{"current","Current XP","integer"},{"maximum","Required XP","integer"},{"level","Player level","integer"},{"rested","Rested XP","integer"},{"disabled","XP disabled","boolean"},{"capped","At effective level cap","boolean"}}},
    player_money={label="Player money",outputs={{"copper","Money (copper)","integer"}}},
    player_talent={label="Player talent",id="nodeID",outputs={{"configID","Active config ID","integer"},{"activeRank","Active rank","integer"},{"currentRank","Current rank","integer"},{"maxRanks","Maximum ranks","integer"},{"totalMaxRanks","Total maximum ranks","integer"},{"available","Available","boolean"},{"active","Active","boolean"}}},
    currency={label="Currency",id="currencyID",outputs={{"name","Currency name","string"},{"quantity","Quantity","float"},{"maxQuantity","Maximum quantity","float"},{"icon","Icon ID","integer"},{"discovered","Discovered","boolean"}}},
    reputation={label="Reputation",id="factionID",defaultID=0,outputs={{"factionID","Faction ID","integer"},{"name","Faction name","string"},{"reaction","Reaction","integer"},{"currentStanding","Raw standing","float"},{"currentReactionThreshold","Raw reaction threshold","float"},{"nextReactionThreshold","Raw next threshold","float"},{"kind","Reputation kind","string"},{"current","Current progress","float"},{"maximum","Rank requirement","float"},{"rewardPending","Paragon reward pending","boolean"}}},
    player_state={label="Player state",outputs={{"mounted","Mounted","boolean"},{"resting","Resting","boolean"},{"moving","Moving","boolean"}}},
    location={label="Location",outputs={{"zone","Zone","string"},{"subzone","Subzone","string"},{"mapID","Map ID","integer"},{"inInstance","In instance","boolean"},{"instanceType","Instance type","string"}}},
    item_count={label="Item count",id="itemID",outputs={{"count","Inventory count","integer"}}},
    item_equipped={label="Item equipped",id="itemID",outputs={{"equipped","Equipped","boolean"}}},
    spell_cooldown={label="Spell cooldown state",id="spellID",outputs={{"active","Cooldown active","boolean"},{"enabled","Enabled","boolean"},{"onGCD","On GCD","boolean"}}},
    spell_proc={label="Spell proc glow",id="spellID",outputs={{"active","Proc glow active","boolean"}}},
    spell_charges={label="Spell charges",id="spellID",outputs={{"currentCharges","Available charges","integer"},{"maxCharges","Maximum charges","integer"},{"active","Recharging","boolean"},{"startTime","Recharge start (s)","float"},{"duration","Recharge duration (s)","float"},{"modRate","Recharge rate","float"},{"durationObject","Recharge duration object","duration"}}},
    spell_usable={label="Spell usability",id="spellID",outputs={{"usable","Usable","boolean"},{"insufficientPower","Insufficient resource","boolean"}}},
    spell_known={label="Known spell",id="spellID",outputs={{"known","Known by player","boolean"}}},
    totem={label="Totem slot",id="slot",outputs={{"present","Present","boolean"},{"name","Name","string"},{"startTime","Start time (s)","float"},{"duration","Duration (s)","float"},{"icon","Icon ID","integer"},{"modRate","Duration rate","float"},{"spellID","Spell ID","integer"},{"durationObject","Duration object","duration"}}},
}
for kind,entry in pairs(dataDefinitions) do
    local d={label=entry.label,source=true,dataSource=true,inputs={},outputs={},defaults={},fields={}}
    for i,p in ipairs(entry.outputs) do d.outputs[p[1]]=port(p[2],p[3],nil,nil,i); d.outputs[p[1]].optional=true; d.outputs[p[1]].maySecret=true end
    if entry.id then d.defaults[entry.id]=entry.defaultID or 1; d.fields={{key=entry.id,label=({slot="Totem slot (1..4)",itemID="Item ID",currencyID="Currency ID",factionID="Faction ID (0 = watched)"})[entry.id] or "Spell ID",type="integer",picker=entry.id=="itemID" and "item" or nil}} end
    d.help="Event-driven source with independent field availability. Missing, secret and unsupported values stay unavailable; no inferred false/zero. Test mode accepts injected observations only."
    if kind=="item_count" then d.help=d.help.." Count covers carried inventory/equipment; bank, reagent bank and account bank are excluded. No global item index." end
    if kind=="player_talent" then
        d.fields[1].label="Talent node ID"
        d.help="Queries one configured trait node in the active player configuration. Active rank and Current rank are distinct native values; staged talent changes can affect Current rank. Active means a readable Active rank above zero. Unknown nodes, missing APIs and secret fields remain unavailable, never assumed rank zero. No tree scan, talent editing or automatic purchase. Node ID is not a Spell ID."
    end
    if kind=="spell_cooldown" then d.help=d.help.." On GCD is available only on SPELL_UPDATE_COOLDOWN. Inactive cooldown does not prove a spell is usable." end
    if kind=="spell_charges" or kind=="spell_usable" or kind=="spell_known" or kind=="totem" or kind=="player_xp" or kind=="player_money" or kind=="currency" or kind=="reputation" then
        d.help="Event-driven source with independent field availability. Secret scalar values are opaque runtime handles for compatible native display inputs. String Formatter supports secret numbers/text for display only; comparisons cannot inspect them. Missing APIs/observations remain unavailable. Test mode uses injected observations only."
    end
    if kind=="spell_charges" then d.help=d.help.." A non-charge or unknown spell may return no charge data, never fabricated zero charges. Start/duration/rate are native samples, not a continuously updated remaining time. The opaque duration object connects to duration media." end
    if kind=="spell_usable" then d.help=d.help.." Usable and Insufficient resource are separate native booleans. Usability does not guarantee range or cooldown readiness." end
    if kind=="spell_known" then d.help=d.help.." Checks the exact Spell ID against the player-known API, including temporarily granted spells. A talent-granted spell or passive can be checked by ID; this is not talent selection, rank or spellbook presence. No pet lookup or override inference." end
    if kind=="totem" then d.help=d.help.." Slots 1..4 describe player totems or other slot-based summons supported by the client. Readable Present=false clears stale details. Start/duration/rate are event samples; the opaque duration object supports native progress. No remaining-time polling or secret identity filters." end
    if kind=="player_xp" then d.help=d.help.." Current/Required XP connect to ordinary bar media. Rested nil remains unknown, not zero. Effective cap uses GameRulesUtil only when available; no expansion-only guess. No XP/hour, ETA or session tracker. Independent of the optional Experience addon." end
    if kind=="player_money" then d.help=d.help.." Native carried player money in copper: 100 copper = 1 silver, 10000 copper = 1 gold. No account-bank or other-character balance, no automatic text conversion." end
    if kind=="currency" then d.help=d.help.." Queries only the configured currency ID; no currency list scanning. Maximum quantity is the native value: zero is preserved and must not be treated as a positive bar limit. Missing or undiscovered data is not inferred from a failed API call." end
    if kind=="reputation" then d.help=d.help.." Faction ID 0 follows the watched faction; positive IDs query that exact faction. Raw standing/thresholds retain their native meaning. Kind labels STANDARD, FRIENDSHIP, RENOWN, PARAGON, HEADER or UNKNOWN. Current progress/Rank requirement use that model only after readable identification: reaction/friendship deltas, native renown values, or readable paragon modulo. Pending rewards remain a separate flag. Missing next thresholds and caps never become invented 1/1 bars. Independent of the optional Reputation addon." end
    A.catalog[kind]=d
end
for _,kind in ipairs({"message_send","message_receive"}) do
    local receive=kind=="message_receive"
    local d={label=receive and "Receive Addon Message" or "Send Addon Message",messageSource=receive,messageSink=not receive,sink=not receive,
        inputs={},outputs={},defaults={topic="aura.signal",payloadType="boolean",channel="LOCAL",target="",sender="",permission=true},fields={
            {key="permission",label=receive and "Allow receiving" or "Allow sending",type="boolean",optional=true,default=true},
            {key="topic",label="Routing identifier",type="string"},
            {key="payloadType",label="Payload type",choices={"boolean","number","string"}},
            {key="channel",label="Recipient scope",choices={"LOCAL","PARTY","RAID","INSTANCE_CHAT","GUILD","WHISPER"},
                choiceLabels={LOCAL="BV Aura Studio",PARTY="Party",RAID="Raid",INSTANCE_CHAT="Instance group",GUILD="Guild",WHISPER="Whisper"}}},
        help="Exchanges addon data, without posting visible chat messages. BV Aura Studio routes between your own graphs without a network connection. Other recipient scopes exchange data with other players' BV installations. Permission belongs to this node; imports reset it. External communication also respects the profile pause switch. Routing identifier is not authentication or a graph ID. Test never sends. Small bounded messages only; complete graph sharing is separate."
    }
    if not receive then
        d.fields[#d.fields+1]={key="target",label="Whisper target",type="string",advanced=true}
        d.help=d.help.." Whisper target must be a full Name-Realm. One fresh Trigger sends once. A graph containing an active receiver cannot forward messages, including delayed triggers."
    else
        d.defaults.acceptGroup=true;d.defaults.senders=""
        d.fields[#d.fields+1]={key="acceptGroup",label="Accept current group members",type="boolean",optional=true,default=true}
        d.fields[#d.fields+1]={key="senders",label="Allowed senders (Name-Realm)",type="string",optional=true,default=""}
        d.fields[#d.fields+1]={key="sender",label="Sender (optional)",type="string",advanced=true}
        d.help=d.help.." Allowed senders: up to 32 Name-Realm entries, comma separated. Group members are accepted only for Party/Raid/Instance group. Guild/Whisper require listed senders. An optional exact Sender filter narrows this node's allowed senders. Multiple matching receivers are allowed. Event is a fresh pulse; value and sender are available for that observation only."
    end
    local base=d
    d.resolve=function(config)
        local t=config.payloadType or "boolean"
        if not ({boolean=true,number=true,string=true})[t] then return nil,"Unsupported message payload type" end
        local result=A.G.Copy(base);result.resolve=nil
        local valueType=t=="number" and "float" or t
        if receive then
            result.inputs={active=port("Active","boolean",true,false,1)}
            result.outputs={event=port("Received","event",nil,nil,1),value=port("Value",valueType,nil,nil,2),sender=port("Sender","string",nil,nil,3)}
            result.outputs.value.optional=true;result.outputs.sender.optional=true
        else
            local default=t=="boolean" and true or t=="number" and 0 or ""
            result.inputs={event=port("Trigger","event",nil,true,1),value=port("Value",valueType,default,false,2)}
            result.outputs={submitted=port("Submitted","boolean",nil,nil,1),status=port("Status","string",nil,nil,2),available=port("Allowed now","boolean",nil,nil,3)}
        end
        return result
    end
    A.catalog[kind]=d
end
for _,kind in ipairs({"shake","pulse","float","fade"}) do
    local strength=({shake=5,pulse=10,float=10,fade=50})[kind]
    local d={label=({shake="Shake animation",pulse="Pulse animation",float="Float animation",fade="Fade animation"})[kind],
        clock=true,animation=kind,inputs={media=mediaPort(),strength=port((kind=="pulse" or kind=="fade") and "Strength (%)" or "Strength", "float",strength,false,2),
            speed=port("Cycles / second","float",1,false,3),active=port("Active","boolean",true,false,4),reset=port("Restart","event",nil,true,5),
            duration=port("Duration (s)","float",0,false,6),looping=port("Repeat","boolean",true,false,7)},
        outputs={media=mediaPort()},bypass={media="media"},defaults={pivot="CENTER"},fields={{key="pivot",label="Pivot",choices=pivots}},
        help="Visual-only animation on the shared demand-driven 10 Hz graph clock. No saved layout change or accumulated offsets. Strength: 0..100 pixels (Shake/Float) or percent (Pulse/Fade); speed: 0.05..2.5 cycles/s (at least four scheduled samples/cycle). Duration 0 repeats indefinitely, or plays one cycle when Repeat=false; a positive duration limits playback. At completion restore the unmodified media. Active=false, Mute or Bypass clears phase. Restart is a fresh event pulse."}
    if kind=="shake" then
        d.defaults.axis="BOTH";d.fields[#d.fields+1]={key="axis",label="Shake axis",choices={"BOTH","HORIZONTAL","VERTICAL"},optional=true,default="BOTH"}
        d.help=d.help.." Horizontal and Vertical use one axis. Both preserves the original mixed-axis shake; older nodes without this field retain that motion."
    end
    d.inputs.reset.required=false;A.catalog["animation_"..kind]=d
end
A.catalog.media_interaction={label="Clickable media",inputs={media=mediaPort(),enabled=port("Enabled","boolean",true,false,2)},
    outputs={media=mediaPort()},bypass={media="media"},defaults={key="media.click",tooltip="",feedback=false,payload={},nextPayloadId=1},fields={
        {key="key",label="Interaction key",type="string"},{key="feedback",label="Mouse feedback",type="boolean",optional=true,default=false},{key="tooltip",label="Tooltip",type="string",advanced=true}},
    help="Ordinary mouse input for this graph only. Add up to eight named scalar payload fields in node settings; matching Media event nodes adopt them automatically. Each click captures the latest rendered values for that element. Mouse feedback optionally highlights hover, shades pressed media and dims disabled live media; it adds no graph events or polling. Disabled media is click-through; Test/Layout preview never clicks into a live graph or shows mouse feedback. No protected game actions."}
A.catalog.media_event={label="Media event",inputs={active=port("Active","boolean",true,false,1)},outputs={event=port("Clicked","event",nil,nil,1),
    button=port("Button","string",nil,nil,2),shift=port("Shift","boolean",nil,nil,3),control=port("Control","boolean",nil,nil,4),alt=port("Alt","boolean",nil,nil,5)},
    defaults={key="media.click",payload={}},fields={{key="key",label="Interaction key",type="string"}},
    help="Fresh mouse-event pulse and captured payload from Click Action or legacy Clickable media in this graph with the same key. Works for ordinary displays and a single clicked Display Stack instance. Configure payload fields on the producer. Removed bindings are rejected. Secret payloads require compatible consumers; System message only accepts readable text. Active=false or Mute suppresses events."}
for key,p in pairs(A.catalog.media_event.outputs) do if key~="event" then p.optional=true end end
for _,kind in ipairs({"media_interaction","media_event"}) do
    local base=A.catalog[kind]
    base.interactionProducer=kind=="media_interaction" or nil
    base.interactionConsumer=kind=="media_event" or nil
    base.resolve=function(config)
        if kind=="media_interaction" and config.feedback~=nil and (ns.GraphValues.IsSecret(config.feedback) or type(config.feedback)~="boolean") then return nil,"Mouse feedback must be a readable boolean" end
        if not ns.GraphValues.ClickSchema(config.payload) then return nil,"Click payload needs up to eight named scalar fields" end
        if config.nextPayloadId~=nil and (not A.G.Number(config.nextPayloadId) or config.nextPayloadId<1 or config.nextPayloadId>1000000000 or config.nextPayloadId~=math.floor(config.nextPayloadId)) then return nil,"Invalid payload field ID" end
        local d=A.G.Copy(base);d.resolve=nil;d.secretInputs=d.secretInputs or {}
        for i,field in ipairs(config.payload or {}) do
            local p=port(field.label,field.type,nil,kind=="media_interaction",10+i);p.required=false;p.optional=true;p.maySecret=true
            if kind=="media_interaction" then d.inputs[field.id]=p;d.secretInputs[field.id]=true else d.outputs[field.id]=p end
        end
        return d
    end
end
A.catalog.chat_receive={label="Chat Received",nativeEvent=true,inputs={active=port("Active","boolean",true,false,1)},
    outputs={event=port("Received","event",nil,nil,1),text=port("Message","string",nil,nil,2),sender=port("Sender","string",nil,nil,3),
        channel=port("Channel","string",nil,nil,4),channelName=port("Channel name","string",nil,nil,5)},
    defaults={channel="SAY",textMode="ANY",text="",senderMode="ANY",sender="",channelName="",ignoreOwn=true},fields={
        {key="channel",label="Channel",choices={"SAY","YELL","EMOTE","WHISPER","PARTY","RAID","RAID_WARNING","INSTANCE_CHAT","GUILD","OFFICER","CHANNEL","SYSTEM"}},
        {key="textMode",label="Message filter",choices={"ANY","EXACT","CONTAINS","GLOB"}},{key="text",label="Message text / glob",type="string"},
        {key="senderMode",label="Sender filter",choices={"ANY","EXACT","CONTAINS","GLOB"}},{key="sender",label="Sender text / glob",type="string"},
        {key="channelName",label="Exact channel name (optional)",type="string",advanced=true},{key="ignoreOwn",label="Ignore own messages",type="boolean"}},
    help="Fresh readable chat events from this selected channel. EXACT/CONTAINS use literal text. GLOB matches the whole value: * means any characters, ? one character, backslash escapes the next character; use *text* for contains. Case-sensitive, not regex or Lua patterns. Invalid globs are rejected; expensive wildcard matches stop at a fixed work limit. Ignore own messages defaults on; unknown player identity is skipped conservatively. Secret or overlong text never matches. Test has no live subscription; no persistent chat log."}
for key,p in pairs(A.catalog.chat_receive.outputs)do if key~="event"then p.optional=true end end
A.catalog.chat_send={label="Chat Request",sink=true,inputs={event=port("Trigger","event",nil,true,1),text=port("Message","string","",false,2)},
    outputs={requested=port("Confirmation requested","boolean",nil,nil,1),status=port("Status","string",nil,nil,2)},defaults={channel="SAY",target=""},fields={
        {key="channel",label="Channel",choices={"SAY","YELL","EMOTE","WHISPER","PARTY","RAID","RAID_WARNING","INSTANCE_CHAT","GUILD","OFFICER","CHANNEL"}},
        {key="target",label="Character / channel name",type="string"}},
    help="A fresh event creates a 15-second review request, never an automatic chat send. Confirm the exact message with the dedicated Send button. Up to eight pending requests; one per graph/node. Message: 1..255 bytes without control characters or markup. WHISPER needs an explicit character name, CHANNEL a stable channel name. RAID_WARNING requires a home raid and leader/assistant; OFFICER requires guild membership, officer status and guild speaking permission. These eligibility checks are conservative; native channel permissions still apply. Context and restrictions are checked again on confirmation. Successful API return means submitted_unconfirmed, not delivered. Test/initial/preview suppress requests; addon-message forwarding is blocked."}
A.catalog.chat_direct=A.G.Copy(A.catalog.chat_send)
A.catalog.chat_direct.label="Send Chat"
A.catalog.chat_direct.outputs={submitted=port("Submitted","boolean",nil,nil,1),status=port("Status","string",nil,nil,2)}
A.catalog.chat_direct.help="One fresh Trigger attempts a visible chat message directly, without a confirmation dialog. Enable sending on this node. Client restrictions, channel membership and role checks apply at the moment of sending; a client requiring hardware input may reject the call. No retries, deferred sends or fallback channels. Submitted means the API returned without a detected error, not confirmed delivery. Test/initial/preview never send. Message: 1..255 bytes, no markup/control characters. Whisper needs a character; Channel a stable channel name. Imports reset the node permission."
for _,kind in ipairs({"chat_send","chat_direct","chat_receive"})do
    local d=A.catalog[kind]
    d.defaults.permission=kind~="chat_direct"
    table.insert(d.fields,1,{key="permission",label=kind=="chat_receive" and "Allow receiving" or "Allow sending",type="boolean",optional=true,default=d.defaults.permission})
end
A.catalog.player_cast={label="Player cast succeeded",nativeEvent=true,inputs={active=port("Active","boolean",true,false,1)},
    outputs={event=port("Succeeded","event",nil,nil,1),spellID=port("Spell ID","integer",nil,nil,2)},
    defaults={spellID=0},fields={{key="spellID",label="Spell ID (0=any)",type="integer"}},
    help="Fresh UNIT_SPELLCAST_SUCCEEDED for a readable player unit token. Event identity and Spell ID are checked separately; a secret Spell ID cannot satisfy a configured ID filter. Any spell (0) can emit the player event with unavailable Spell ID. Cast GUID is not read or stored. No inferred cooldown, damage or next cast."}
A.catalog.player_swing={label="Player swing",nativeEvent=true,inputs={active=port("Active","boolean",true,false,1)},
    outputs={event=port("Swing","event",nil,nil,1),duration=port("Swing duration (s)","float",nil,nil,2),hand=port("Hand","string",nil,nil,3)},
    defaults={hand="ALL"},fields={{key="hand",label="Weapon hand",choices={"ALL","MAINHAND","OFFHAND","RANGED"}}},
    help="Fresh Forever PLAYER_SWING event, independent readable duration and weapon-hand fields. ALL can emit with missing/secret fields; a hand filter requires a readable matching enum. This is a swing-timer event, not confirmation of a hit or damage. No combat-log reconstruction or estimated countdown."}
for _,kind in ipairs({"player_cast","player_swing"}) do for key,p in pairs(A.catalog[kind].outputs) do if key~="event" then p.optional=true;p.maySecret=true end end end
A.catalog.media_text={label="Text media",source=true,inputs={text=port("Text","string","AuraStudio",false,1)},outputs={media=mediaPort()},
    defaults={font="ysabeau",fontSize=20,align="CENTER",wrap=true},fields={
        {key="font",label="Font",type="string",options="fonts",advanced=true},
        {key="fontSize",label="Font size",type="float"},{key="align",label="Alignment",choices={"LEFT","CENTER","RIGHT"},advanced=true},{key="wrap",label="Wrap text",type="boolean",advanced=true}}}
A.catalog.media_text.secretInputs={text=true}
A.catalog.media_overlay.secretInputs={text=true}
for _,kind in ipairs({"media_icon","media_graphic","media_bar","media_text"}) do A.catalog[kind].inputs.style=definitionPort("Style","style",20) end
A.catalog.media_text.inputs.font=definitionPort("Font","font",19)
A.catalog.media_overlay.inputs.font=definitionPort("Font","font",19)
A.catalog.media_bar.inputs.color=port("Fill color","string","FFFFFFFF",false,3);A.catalog.media_bar.inputs.color.picker="color"

for _,kind in ipairs({"bar_duration","icon_duration"}) do
    A.catalog[kind]={label=kind=="bar_duration" and "Bar duration" or "Icon duration",inputs={media=mediaPort(),duration=port("Native duration","duration",nil,true,2)},
        secretInputs={duration=true},outputs={media=mediaPort()},bypass={media="media"},defaults={},fields={},
        help="Pass a native duration object to the matching native bar/cooldown sink. No Lua time arithmetic. A rejected client setter hides the result; unavailable duration is not zero."}
end
do
    local schemas={};for name in pairs(A.UnitDataCatalog.schemas) do schemas[#schemas+1]=name end;table.sort(schemas)
    local base={label="Unit record field",inputs={},outputs={},secretInputs={record=true},defaults={schema="aura",field="name",index=1},
        fields={{key="schema",label="Record schema",choices=schemas},{key="field",label="Field",type="string"},{key="index",label="Record index",type="integer"}},
        help="Known-field projection from a bounded unit record, duration or prediction object. List indices are 1..40. Secret scalar fields remain typed runtime handles; unknown fields cannot access native objects."}
    base.resolve=function(config)
        local schema=A.UnitDataCatalog.schemas[config.schema]
        if not schema or not A.G.Number(config.index) or config.index~=math.floor(config.index) or config.index<1 or config.index>40 then return nil,"Invalid record schema/index" end
        local kind=schema[config.field];if not kind then return nil,"Select a known record field" end
        local d=A.G.Copy(base);d.resolve=nil
        d.inputs={record=port("Record",(config.schema=="duration" or config.schema=="calculator") and config.schema or "data",nil,true,1)}
        d.outputs={value=port("Value",kind,nil,nil,1),available=port("Readable","boolean",nil,nil,2),status=port("Status","string",nil,nil,3)}
        d.outputs.value.optional=true;d.outputs.value.maySecret=true
        local choices={};for key in pairs(schema) do choices[#choices+1]=key end;table.sort(choices)
        d.fields[2]={key="field",label="Field",choices=choices};return d
    end
    A.catalog.unit_record=base
end
A.catalog.display={label="Display",sink=true,display=true,inputs={media=mediaPort(),visible=port("Visible","boolean",true,false,2)},outputs={},defaults={}}
A.catalog.display.inputs.visible.required=false
A.catalog.display.inputs.realTime=port("Real Time","duration",nil,true,3)
A.catalog.display.inputs.realTime.required=false
A.catalog.display.secretInputs={realTime=true}
A.catalog.display.help="Real Time drives an icon countdown or a bar with native aura timing. Connect Icon media or Bar media as well. A connected but unavailable timer hides the display; an unconnected timer leaves ordinary media unchanged."
A.catalog.secure_spell={label="Secure spell button",sink=true,display=true,secureAction=true,
    inputs={highlight=port("Suggest (visual only)","boolean",false,false,1)},outputs={},
    defaults={spellID=5697},fields={{key="spellID",label="Spell to cast on self",type="integer",picker="aura"}},
    help="Fixed self-cast action. Apply and enable outside combat. Left mouse release casts the configured spell on player through Blizzard's secure button; graph events never cast. Suggest only colors the button, including in combat; false or unknown never disables it. Position freely on screen with Layout Editor; frame, cursor and nameplate anchors are not supported yet. Combat freezes action, position and visibility. Pending removal applies after combat. Studio Test is a non-clickable preview. Requires a known usable spell; normal game restrictions apply."}
A.catalog.secure_spell.inputs.highlight.required=false
for _,kind in ipairs({"opacity","tint","glow","scale","size","offset","rotate","text_outline","text_shadow","icon_border"}) do
    local d={label=({opacity="Opacity",tint="Color",glow="Glow",scale="Scale",size="Size delta",offset="Position offset",rotate="Rotate graphic",text_outline="Text outline",text_shadow="Text shadow",icon_border="Icon border"})[kind],
        inputs={media=mediaPort()},outputs={media=mediaPort()},bypass={media="media"},defaults={},fields={}}
    if kind=="opacity" then d.inputs.alpha=port("Opacity (0..1)","float",1,false,2)
    elseif kind=="glow" then
        d.inputs.strength=port("Strength (0..1)","float",0.5,false,2)
        d.inputs.color=port("Color (hex)","string","FFD100",false,3)
        d.inputs.size=port("Spread (0..12 px)","float",3,false,4)
        d.inputs.speed=port("Icon speed (0..4x)","float",1,false,5)
        d.inputs.color.picker="color"; d.inputs.size.advanced=true; d.inputs.speed.advanced=true
        for i,key in ipairs({"red","green","blue","alpha"}) do
            d.inputs[key]=port("Glow "..key.." multiplier (0..1)","float",1,false,20+i);d.inputs[key].advanced=true
        end
        for i,entry in ipairs({{"scaleX","Icon scale X",1,"float"},{"scaleY","Icon scale Y",1,"float"},
            {"offsetX","Glow offset X",0,"float"},{"offsetY","Glow offset Y",0,"float"},
            {"pulse","Pulse glow",false,"boolean"},{"period","Pulse cycle (s)",1.6,"float"},{"minimum","Pulse min (0..1)",.25,"float"}}) do
            local p=port(entry[2],entry[4],entry[3],false,i+5); p.advanced=true; d.inputs[entry[1]]=p
        end
        d.defaults={iconStyle="auto",textStyle="soft"}
        d.fields={{key="iconStyle",label="Icon effect",choices={"auto","button","proc","pixel","autocast"},optional=true,default="auto"},
            {key="textStyle",label="Text effect",choices={"soft","outline","neon","shadow","pixel","autocast"},
                choiceLabels={soft="Soft glyph glow",outline="Glyph outline",neon="Neon glyph glow",shadow="Soft glyph shadow",pixel="Pixel frame around text",autocast="AutoCast frame around text"},optional=true,default="soft"}}
        d.help="Icons: native Button/Proc plus LibCustomGlow Pixel/AutoCast. Text: Soft, Outline, Neon and Shadow follow glyphs; Pixel/AutoCast frame the text box. Color picker or wired RRGGBB[AA], with independent wired RGBA multipliers. Spread changes the glow radius. Pulse and opacity affect the glow only. Pixel/AutoCast use bounded moving segments/particles; speed zero or unavailable libraries use a static halo. Hidden effects stop and return pooled resources."
    elseif kind=="text_outline" or kind=="text_shadow" or kind=="icon_border" then
        d.inputs.color=port("Color (hex)","string",kind=="text_shadow" and "000000B3" or "000000",false,2)
        if kind=="text_shadow" then
            d.inputs.x=port("Offset X (-64..64)","float",2,false,3); d.inputs.y=port("Offset Y (-64..64)","float",-2,false,4)
        else d.inputs.width=port(kind=="icon_border" and "Width (0..24)" or "Width (0..6)","float",1,false,3) end
        d.help="Independent media decoration. Values may be wired. Hex color RRGGBB[AA]; zero width/alpha hides the effect. Text effects apply only to text, icon border only to icons. Other media passes through unchanged. Geometry and saved anchors are not affected."
    elseif kind=="tint" then for i,k in ipairs({"red","green","blue"}) do d.inputs[k]=port(k.." (0..1)","float",1,false,i+1) end
    else
        if kind=="scale" then d.inputs.factor=port("Factor (0..10)","float",1,false,2)
        elseif kind=="rotate" then d.inputs.angle=port("Degrees CCW","float",0,false,2)
        else d.inputs.x=port(kind=="size" and "Width delta" or "X delta","float",0,false,2); d.inputs.y=port(kind=="size" and "Height delta" or "Y delta","float",0,false,3) end
        d.defaults.mode="visual"; d.defaults.pivot="CENTER"
        if kind~="rotate" then d.fields[#d.fields+1]={key="mode",label="Affects",choices={"visual","layout"}} end
        if kind~="offset" then d.fields[#d.fields+1]={key="pivot",label="Pivot",choices=pivots} end
    end
    A.catalog[kind]=d
end
A.catalog.circle={label="Circle position",inputs={radius=port("Radius","float",100,false,1),angle=port("Degrees CCW","float",0,false,2)},outputs={x=port("X","float",nil,nil,1),y=port("Y","float",nil,nil,2)},defaults={}}
A.catalog.rotate_offset={label="Rotate offset",inputs={x=port("X","float",0,false,1),y=port("Y","float",0,false,2),angle=port("Degrees CCW","float",0,false,3)},outputs={x=port("X","float",nil,nil,1),y=port("Y","float",nil,nil,2)},bypass={x="x",y="y"},defaults={}}
A.catalog.gate.inputs.seconds.advanced=true
A.catalog.format.inputs.template.advanced=true
A.catalog.aura.outputs.stacks.optional=true
A.catalog.aura.outputs.duration.optional=true
A.catalog.aura.outputs.icon=port("Icon media","media",nil,nil,8)
A.catalog.aura.outputs.icon.optional=true
A.catalog.aura.outputs.present.optional=true
A.catalog.remaining_estimate.outputs.value.optional=true
for _,kind in ipairs({"timer","interval"}) do A.catalog[kind].inputs.reset.required=false end
for i,entry in ipairs({{"remaining","Remaining (s)","float"},{"hasExpiration","Has expiration","boolean"}}) do
    A.catalog.aura.outputs[entry[1]]=port(entry[2],entry[3],nil,nil,i+3)
    A.catalog.aura.outputs[entry[1]].optional=true
end
for _,kind in ipairs({"hp","aura"}) do for _,p in pairs(A.catalog[kind].outputs) do p.maySecret=true end end
for _,p in pairs(A.catalog.hp.outputs) do p.optional=true end
A.catalog.aura.outputs.icon.maySecret=nil
A.catalog.aura.outputs.presentEstimate=port("Present Estimate","boolean",nil,nil,1.5)
A.catalog.aura.outputs.presentEstimate.optional=true
A.catalog.aura.outputs.durationEstimate=port("Duration Estimate (s)","float",nil,nil,3.5)
A.catalog.aura.outputs.durationEstimate.optional=true
A.catalog.aura.outputs.remainingEstimate=port("Remaining Estimate (s)","float",nil,nil,4.5)
A.catalog.aura.outputs.remainingEstimate.optional=true
local presentEstimateHelp=" Present Estimate passes readable Present through. For Secret Present, a canonical publicly mapped active CDM family can supply true. Player requires readable self-aura metadata. Target uses its readable GUID and matching target viewer binding; a readable aura instance ID is not required for this estimate. During combat, observed Target estimates are retained separately per target GUID, spell and aura type across target switches and reconciled with current readable observations. Cached-only presence expires at a known deadline. This is a family estimate, not an exact hidden aura rank or proof of absence. Missing/unavailable/faulted native observations remain unknown; native Present is unchanged."
local timingEstimateHelp=" Duration Estimate holds observed total duration while timing is Secret. Remaining Estimate counts down only from an observed timebase and becomes nil at zero or Present Estimate=false. Target combat memory restores the original timebase on returning to a target, never restarting the countdown. Current readable data takes precedence; observed removal clears the entry and reapplication needs fresh timing. No duration or cast timestamp is invented. Combat end, Stop and reapply clear Target memory. Hidden refreshes, dispels and duration changes while another target is selected can make estimates inaccurate. Native Duration and Remaining are unchanged."
local auraIconHelp=" Icon media uses the selected spell's reference artwork independently of aura presence or Secret aura data. Texture ID, where available, remains the native aura texture output."
A.catalog.aura.help="Duration is the total duration. Remaining is wall-clock seconds until a readable expiration timestamp, refreshed at 10 Hz only when connected to an active output path. Has expiration is false for permanent auras; their Remaining stays unavailable. Native Remaining never reuses a countdown when timing becomes Secret. Test signals can simulate duration and secret timing."..presentEstimateHelp..timingEstimateHelp..auraIconHelp
-- New source families share a controlled selector. Legacy kinds retain their
-- saved IDs and behavior; palette consolidation never rewrites user graphs.
local unitChoices={"player","target","target_target","focus","focus_target","pet","party_member","raid_member","mouseover"}
local unitLabels={player="Player",target="Target",target_target="Target of Target",focus="Focus",focus_target="Target of Focus",pet="Pet",party_member="Party",raid_member="Raid",mouseover="Mouseover"}
local function instancePort()
    local p=port("Instance","unitref",nil,nil,0);p.optional=true;p.maySecret=true;return p
end
local function selectorFields(collection)
    if collection then return {{key="relation",label="Nameplates",choices={"ALL","FRIENDLY","HOSTILE"},choiceLabels={ALL="All",FRIENDLY="Friendly",HOSTILE="Hostile"}}}end
    return {{key="unit",label="Unit",choices=unitChoices,choiceLabels=unitLabels},{key="slot",label="Roster slot",type="integer",advanced=true}}
end
local function sourceFamily(kind,label,family,collection)
    local base={label=label,source=true,sourceFamily=family,collectionSource=collection or nil,unitKind=collection and "nameplates" or "unit",
        inputs={},outputs={},defaults={unit="player",slot=1,relation="ALL"},fields=selectorFields(collection)}
    if family=="aura" then
        base.auraSource=true;base.outputs=A.G.Copy(A.catalog.aura.outputs);base.outputs.instance=instancePort()
        base.outputs.realTime=port("Real Time","duration",nil,nil,4.75)
        base.outputs.realTime.optional=true;base.outputs.realTime.maySecret=true
        base.outputs.texture=port("Texture ID","integer",nil,nil,9);base.outputs.texture.optional=true;base.outputs.texture.maySecret=true
        base.defaults.spellID=0;base.defaults.filter="HELPFUL"
        base.fields[#base.fields+1]={key="spellID",label="Aura / Spell ID",type="integer",picker="aura"}
        base.fields[#base.fields+1]={key="filter",label="Aura type",choices={"HELPFUL","HARMFUL"}}
    else
        base.unitSource=true;base.selectableOutputs=A.G.Copy(A.catalog.player.selectableOutputs);base.outputSelectionKey="outputs"
        if family=="cast" then
            local fields={}
            for _,entry in ipairs(A.UnitDataCatalog.entries)do
                if entry.api:match("^Unit.*Cast") or entry.api:match("^Unit.*Channel") or entry.api:match("^UnitSpellTarget")then
                    for _,field in ipairs(entry.outputs)do fields[field.key]=base.selectableOutputs[field.key]end
                end
            end
            base.selectableOutputs=fields
            base.selectableOutputs.castSucceeded=port("Cast succeeded","event",nil,nil,1);base.selectableOutputs.castSucceeded.optional=true
            base.selectableOutputs.succeededSpellID=port("Succeeded spell ID","integer",nil,nil,2);base.selectableOutputs.succeededSpellID.optional=true;base.selectableOutputs.succeededSpellID.maySecret=true
            base.defaults.outputs={instance=true,castingInfo_name=true,castingInfo_castingSpellID=true,castingDuration=true,channelDuration=true,castSucceeded=true}
        else
            base.defaults.outputs={instance=true,health=true,healthMax=true,power=true,powerMax=true}
            for _,field in ipairs(A.catalog.player.fields)do base.fields[#base.fields+1]=A.G.Copy(field)end
            for key,value in pairs(A.UnitDataCatalog.queryDefaults)do base.defaults[key]=value end
        end
        base.selectableOutputs.instance=instancePort()
    end
    base.help=collection and "Observe each current nameplate binding independently. All includes bindings without readable relation; Friendly/Hostile requires a positive readable relation. Slots are temporary and reuse creates a new instance. Connect Instance to Display Stack to keep each unit's media together."
        or "Select Player, Target, Target of Target, Focus, Target of Focus, Pet, Party, Raid or Mouseover. Mouseover observes the current unit under the pointer and clears on leave; it does not parse arbitrary item/spell tooltips. Roster slot selects 1..4 for Party or 1..40 for Raid. Secret fields remain opaque runtime values; unavailable data is not zero."
    if family=="aura" then base.help=base.help.." Aura identity/filter must be accessible. Native Remaining uses readable expiration only. Real Time forwards native timing directly to Display Real Time or a duration media node. It is an opaque timer, not numeric seconds. CDM fallback follows the configured spell family on the current unit; unsupported native calls leave it unavailable."..presentEstimateHelp..timingEstimateHelp..auraIconHelp
    elseif family=="cast" then base.help=base.help.." Current cast/channel fields and native durations come from the selected unit. No inferred cast, spell target unit or missed-event replay."end
    base.resolve=function(config)
        if collection then
            if not ({ALL=true,FRIENDLY=true,HOSTILE=true})[config.relation]then return nil,"Choose All, Friendly or Hostile nameplates"end
        else
            if not unitLabels[config.unit]then return nil,"Choose a supported unit"end
            local max=config.unit=="party_member" and 4 or 40
            if not A.G.Number(config.slot) or config.slot~=math.floor(config.slot) or config.slot<1 or config.slot>max then return nil,"Roster slot must be 1.."..max end
        end
        local d=A.G.Copy(base);d.resolve=nil
        if not collection and config.unit~="party_member" and config.unit~="raid_member" then
            for i=#d.fields,1,-1 do if d.fields[i].key=="slot" then table.remove(d.fields,i) end end
        end
        if family=="unit" then
            local needed={}
            for _,entry in ipairs(A.UnitDataCatalog.entries) do
                local selected=false;for _,field in ipairs(entry.outputs) do if config.outputs and config.outputs[field.key] then selected=true;break end end
                if selected then for _,arg in ipairs(entry.args or {}) do if type(arg)=="string" then
                    local option=arg:match("^%$option:(.+)$");if option then needed[option]=true end
                    if arg=="$auraID" or arg=="$auraSlot" then needed.auraIndex=true end
                end end end
            end
            for i=#d.fields,1,-1 do local key=d.fields[i].key;if A.UnitDataCatalog.queryDefaults[key]~=nil and not needed[key] then table.remove(d.fields,i) end end
        end
        if base.selectableOutputs then
            if type(config.outputs)~="table"then return nil,"Select source outputs"end
            d.outputs={}
            for key,value in pairs(config.outputs)do if not base.selectableOutputs[key] or value~=true then return nil,"Unknown source output selection"end;d.outputs[key]=A.G.Copy(base.selectableOutputs[key])end
            -- Keep existing wires, but do not offer unsupported options to new selections.
            if collection or config.unit~="player" then
                d.selectableOutputs=A.G.Copy(base.selectableOutputs)
                for key,p in pairs(d.selectableOutputs) do if p.playerOnly then p.disabled=true;p.label=p.label.." (Player only)" end end
            end
            if family=="unit" then
                local check=A.G.Copy(config);check.outputs={}
                local _,why=A.catalog.player.resolve(check);if why then return nil,why end
            end
        end
        return d
    end
    A.catalog[kind]=base
end
for _,family in ipairs({{"unit","Unit"},{"aura","Unit Aura"},{"cast","Unit Cast"}})do
    sourceFamily(family[1]=="unit" and "unit" or "unit_"..family[1],family[2],family[1],false)
    sourceFamily(family[1]=="unit" and "nameplates" or "nameplates_"..family[1],family[1]=="unit" and "Nameplates" or "Nameplates "..(family[1]=="aura" and "Aura" or "Cast"),family[1],true)
end
for _,kind in ipairs({"media_icon","icon","secure_spell","aura","unit_aura","nameplates_aura"}) do
    local def=A.catalog[kind]
    -- Retain the stored key for old graphs/imports. New sources use full artwork;
    -- absent old settings retain DisplayModel's legacy crop default.
    def.defaults.cropBorder=kind=="secure_spell" or kind=="icon"
    def.help=(def.help or "").." Use Icon Appearance to choose cropping. Existing stored crop settings remain compatible."
end
A.catalog.display_stack={label="Display Stack",sink=true,display=true,displayStack=true,inputs={},outputs={},secretInputs={instance=true,sort=true},
    defaults={elements={{id="media1",label="Element 1"}},rootElement="media1",nextElementId=2},fields={},
    help="One media composition per Instance. Root element reserves the stack geometry; other elements keep their offsets. Sort uses readable values only, with stable appearance order when secret or unavailable. Removing an element never renumbers the remaining inputs. One to eight elements."}
A.catalog.display_stack.resolve=function(config)
    if type(config.elements)~="table" or #config.elements<1 or #config.elements>8 then return nil,"Display Stack needs 1..8 elements"end
    if config.nextElementId~=nil and (not A.G.Number(config.nextElementId) or config.nextElementId~=math.floor(config.nextElementId) or config.nextElementId<2 or config.nextElementId>1000000000)then return nil,"Invalid next element ID"end
    local d=A.G.Copy(A.catalog.display_stack);d.resolve=nil;d.inputs={instance=port("Instance","unitref",nil,true,1),sort=port("Sort value","any",nil,true,2),visible=port("Visible","boolean",true,false,3)};d.inputs.sort.required=false;d.inputs.visible.required=false
    local seen={};local root=false
    for i,element in ipairs(config.elements)do
        if type(element)~="table" or type(element.id)~="string" or not element.id:match("^media[1-9]%d*$") or #element.id>16 or seen[element.id]then return nil,"Element IDs must be unique stable media IDs"end
        if type(element.label)~="string" or #element.label<1 or #element.label>48 or element.label:find("[%c|]")then return nil,"Element label must be 1..48 plain characters"end
        if element.layoutId~=nil and (type(element.layoutId)~="string" or #element.layoutId~=40 or not element.layoutId:match("^bv_aura:%x+$"))then return nil,"Invalid element layout anchor"end
        seen[element.id]=true;root=root or element.id==config.rootElement
        d.inputs[element.id]=port(element.label,"media",nil,true,i+3);d.inputs[element.id].required=false
    end
    if not root then return nil,"Choose an existing root element"end
    return d
end
-- Families share an operation selector only where the dataflow remains clear.
-- Legacy definitions stay callable so old saved graphs retain their contracts.
do
    local G=A.G
    local function choices(key,label,values) return {key=key,label=label,choices=values} end
    local mathOps={add=true,subtract=true,multiply=true,divide=true,modulo=true,percent=true}
    local base={label="Math",mathOperation=true,inputs={value=port("Value A","float",0,false,1),factor=port("Value B","float",1,false,2)},
        outputs={value=port("Result","float",nil,nil,1),success=port("Successful","boolean",nil,nil,2)},bypass={value="value"},defaults={operation="multiply"},
        fields={choices("operation","Operation",{"add","subtract","multiply","divide","modulo","percent"})},
        help="Readable finite numbers only. A + B, A - B, A * B, A / B, A % B or Percent = 100 * (A / B). Percent requires a positive B. Modulo follows floor division (the remainder has the divisor's sign). Division/modulo by zero, invalid percent maximum and nonfinite results produce no Result and Successful=false. Bypass passes A without calculating."}
    base.outputs.value.optional=true
    base.resolve=function(config) if not mathOps[config.operation] then return nil,"Choose a math operation" end;local d=G.Copy(base);d.resolve=nil;d.mathOperation=config.operation;return d end
    A.catalog.math=base

    local logicOps={["and"]=true,["or"]=true,xor=true,nand=true,nor=true,xnor=true,["not"]=true}
    local logic={label="Logic",booleanOperation=true,inputs={},outputs={},defaults={operation="and",count=2},minCount=2,maxCount=16,
        fields={choices("operation","Operation",{"and","or","xor","nand","nor","xnor","not"}),{key="count",label="Input count (2..16)",type="integer"}},
        help="AND/OR and their inverses NAND/NOR use decisive readable operands even when another input is unavailable. XOR is true for an odd number of true inputs; XNOR is its inverse (even parity), not an all-equal test. XOR/XNOR need every input. NOT uses Input 1 only. Connected ports cannot disappear when changing operation or input count."}
    logic.resolve=function(config)
        if not logicOps[config.operation] then return nil,"Choose a logic operation" end
        if not G.Number(config.count) or config.count~=math.floor(config.count) or config.count<2 or config.count>16 then return nil,"Input count must be 2..16" end
        local d=G.Copy(logic);d.resolve=nil;d.booleanOperation=config.operation;d.count=config.operation=="not" and 1 or config.count
        if d.count==1 then d.fields={G.Copy(logic.fields[1])};d.minCount=nil;d.maxCount=nil end
        d.inputs={};d.outputs={result=port("Result","boolean")};d.bypass={result="in1"}
        for i=1,d.count do d.inputs["in"..i]=port("Input "..i,"boolean",false,false,i) end
        return d
    end
    A.catalog.logic=logic

    local parse={label="Parse / Convert",parseValue=true,inputs={value=port("Value","any","",false,1)},outputs={},defaults={targetType="integer"},
        fields={choices("targetType","Convert to",{"string","integer","float","boolean"})},
        help="Convert readable scalar values explicitly. Integer accepts integral decimal numbers only (no rounding); Float accepts decimal/exponent notation, never hex, NaN or infinity. Boolean accepts true/false and 1/0 (text ignores surrounding spaces and letter case). Boolean to number gives 1/0. Invalid or unavailable input gives Successful=false and no Value; secret input is never inspected. Text is limited to 1024 bytes."}
    parse.resolve=function(config)
        if not ({string=true,integer=true,float=true,boolean=true})[config.targetType] then return nil,"Choose a scalar target type" end
        local d=G.Copy(parse);d.resolve=nil;d.outputs={value=port("Value",config.targetType,nil,nil,1),success=port("Successful","boolean",nil,nil,2)};d.outputs.value.optional=true;return d
    end
    A.catalog.parse=parse

    local animation={label="Animation",clock=true,inputs={},outputs={},bypass={media="media"},defaults={animation="shake",pivot="CENTER",axis="BOTH"},
        fields={choices("animation","Animation",{"shake","pulse","float","fade"})},help="Choose Shake, Pulse, Float or Fade. Common timing and media ports remain stable; the selected animation exposes only its relevant settings."}
    animation.resolve=function(config)
        local source=A.catalog["animation_"..tostring(config.animation)]
        if not source then return nil,"Choose an animation" end
        local d=G.Copy(source);d.resolve=nil;d.label=animation.label;d.fields={G.Copy(animation.fields[1])}
        for _,field in ipairs(source.fields) do d.fields[#d.fields+1]=G.Copy(field) end
        d.validate=source.validate;return d
    end
    A.catalog.animation=animation

    local memory={label="Memory",sink=true,inputs={},outputs={},defaults={operation="get",valueType="string"},
        fields={choices("operation","Action",{"get","set","delete","clear"})},help="One action per node: Get, Set, Delete or Clear. Clear affects this graph runtime's temporary map (or its current instance), never other graphs or saved data. Fresh Trigger and Done ports explicitly order actions."}
    memory.resolve=function(config)
        if not ({get=true,set=true,delete=true,clear=true})[config.operation] then return nil,"Choose a memory action" end
        local source=A.catalog["memory_"..config.operation]
        local d,why=source.resolve(config);if not d then return nil,why end
        d.label=memory.label;d.fields={G.Copy(memory.fields[1])};d.help=memory.help.." "..source.help
        for _,field in ipairs(source.fields) do d.fields[#d.fields+1]=G.Copy(field) end
        return d
    end
    A.catalog.memory=memory
    A.catalog.format_values.minCount=1;A.catalog.format_values.maxCount=16
end
do
    local d=A.catalog.media_graphic
    d.label="Graphic"
    d.defaults.source="file";d.defaults.atlas="UI-LFG-RoleIcon-Tank";d.defaults.fileID=134400
    d.fields={{key="source",label="Source",choices={"file","game","fileID","atlas"},choiceLabels={file="Addon file",game="Blizzard texture path",fileID="Texture file ID",atlas="Blizzard atlas"},optional=true,default="file"}}
    d.resolve=function(config)
        local source=config.source or "file"
        if not ({file=true,game=true,fileID=true,atlas=true})[source] then return nil,"Choose a graphic source" end
        local out=A.G.Copy(d);out.resolve=nil
        out.fields[#out.fields+1]=source=="atlas" and {key="atlas",label="Atlas name",type="string"}
            or source=="fileID" and {key="fileID",label="Texture file ID",type="integer"}
            or {key="path",label="Texture path",type="string"}
        for _,key in ipairs({"left","right","top","bottom"}) do out.fields[#out.fields+1]={key=key,label="Crop "..key.." (0..1)",type="float",advanced=true} end
        return out
    end
    d.help="Display an addon file, Blizzard texture path, texture file ID or atlas. Assets must exist on the client; missing assets clear the image. Crop uses normalized coordinates within the selected artwork/atlas. No addon UI is loaded or activated."
    A.catalog.media_crop={label="Crop / Texture",inputs={media=mediaPort(),left=port("Left (0..1)","float",0,false,2),right=port("Right (0..1)","float",1,false,3),top=port("Top (0..1)","float",0,false,4),bottom=port("Bottom (0..1)","float",1,false,5)},outputs={media=mediaPort()},bypass={media="media"},defaults={flipX=false,flipY=false,blendMode="BLEND"},
        fields={{key="flipX",label="Flip horizontal",type="boolean"},{key="flipY",label="Flip vertical",type="boolean"},{key="blendMode",label="Blend mode",choices={"BLEND","ADD","MOD","ALPHAKEY"}}},
        help="Crop any icon or graphic, including aura icons and Blizzard atlases, using normalized artwork coordinates. Replaces the default icon-border crop. Flip and blend affect artwork only; geometry and click regions stay unchanged. Atlas crop requires readable atlas coordinates. Text and bars use their own layout/style controls."}
    A.catalog.icon_border.label="Border"
    A.catalog.icon_border.defaults.style="solid"
    A.catalog.icon_border.fields[#A.catalog.icon_border.fields+1]={key="style",label="Border style",choices={"solid","corners","double"},optional=true,default="solid"}
    for _,kind in ipairs({"spin","bounce"}) do
        local original=A.G.Copy(A.catalog.animation_float);original.animation=kind;original.label="Animation / "..kind
        A.catalog["animation_"..kind]=original
    end
    A.catalog.animation.fields[1].choices={"shake","pulse","float","fade","spin","bounce"}
    A.catalog.animation.help="Choose Shake, Pulse, Float, Fade, Spin or Bounce. Common timing and media ports remain stable. Spin uses Strength as percentage of a full rotation per cycle; Bounce uses Strength as pixel height. Unsupported rotations (bars/overlays) remain explicit errors."
    for _,kind in ipairs({"encounter_event","ready_check_event"}) do
        local d={label=kind=="encounter_event" and "Encounter event" or "Ready check event",nativeEvent=true,category="triggers",
            inputs={active=port("Active","boolean",true,false,1)},outputs={event=port("Trigger","event",nil,nil,1)},defaults={phase="either"},
            fields={{key="phase",label="Event phase",choices={"either","started","ended"}}},
            help="React to a newly delivered public event. No cached event replay or inferred active state. Optional metadata stays independently unavailable/secret. Target-client event delivery requires native verification."}
        local fields=kind=="encounter_event" and {{"started","Started","boolean"},{"ended","Ended","boolean"},{"encounterID","Encounter ID","integer"},{"name","Encounter name","string"},{"difficulty","Difficulty ID","integer"},{"groupSize","Group size","integer"},{"success","Successful","boolean"}}
            or {{"started","Started","boolean"},{"ended","Ended","boolean"},{"initiator","Initiator","string"},{"timeLeft","Time limit (s)","float"},{"preempted","Preempted","boolean"}}
        for i,f in ipairs(fields) do d.outputs[f[1]]=port(f[2],f[3],nil,nil,i+1);d.outputs[f[1]].optional=true end
        A.catalog[kind]=d
    end
end
A.catalog.spell_action={label="Spell Action",source=true,actionSource=true,inputs={},outputs={action=port("Action","action",nil,nil,1)},
    defaults={spellID=5697,target="player"},fields={{key="spellID",label="Spell",type="integer",picker="aura"},
        {key="target",label="Target",choices={"player","target","targettarget","focus","focustarget"},choiceLabels={player="Player",target="Target",targettarget="Target of Target",focus="Focus",focustarget="Target of Focus"}}},
    help="Defines a spell and a stable target token for Action Display. This node never casts. The native click uses the current unit behind that token; configure and apply outside combat."}
A.catalog.action_display={label="Action Display",sink=true,display=true,actionDisplay=true,
    inputs={media=mediaPort(),action=port("Action","action",nil,true,2),highlight=port("Suggest (visual only)","boolean",false,false,3)},outputs={},defaults={},
    help="Connect Media and an Action node. Left mouse release executes its prepared action. UI and Group actions are available outside combat; game actions use the native secure button. Icon, text, button and bar media are supported. Suggest is cosmetic. Prepare outside combat. Screen-based position and size links are supported; cursor, nameplate, external-frame and template links are not. Action, geometry and visibility stay fixed in combat; pending changes apply after combat. Test never casts. Missing media shows a placeholder on the prepared action. Advanced media effects report unsupported styling."}
A.catalog.action_display.inputs.highlight.required=false
A.catalog.icon_appearance={label="Icon Appearance",inputs={media=mediaPort()},outputs={media=mediaPort()},bypass={media="media"},
    defaults={appearance="cropped",skin="none",shape="square"},fields={{key="appearance",label="Appearance",choices={"original","cropped"},choiceLabels={original="Original",cropped="Cropped (8%)"},primary=true},
        {key="skin",label="Skin",choices=ns.IconSkins.styles,choiceLabels=ns.IconSkins.labels,optional=true,default="none",primary=true},
        {key="shape",label="Shape",choices=ns.IconSkins.shapes,choiceLabels=ns.IconSkins.shapeLabels,optional=true,default="square",primary=true}},
    help="Choose artwork crop, a BV skin and one of its matching shapes. Icon Echo retains a thin outer strip of the same spell image with a transparent gap before its center. Round, hexagon and octagon variants mask the spell image itself; the click area remains rectangular. Masque controls artwork only when Skin=Masque, including its shape and crop. Choose a BV style or None to override it. Prepare action skins outside combat."}
A.catalog.media_button=A.G.Copy(A.catalog.media_text)
A.catalog.media_button.label="Button Media";A.catalog.media_button.category="media"
A.catalog.media_button.defaults.buttonStyle="wow";A.catalog.media_button.defaults.fontSize=16
A.catalog.media_button.inputs.text.label="Label";A.catalog.media_button.inputs.text.default="Cast"
table.insert(A.catalog.media_button.fields,1,{key="buttonStyle",label="Button style",choices=ns.DisplayModel.buttonStyles,choiceLabels=ns.DisplayModel.buttonLabels,primary=true})
A.catalog.media_button.help="A labeled button surface with WoW, Modern, Arcane Sigil, Runic Gold, Emberforge, Frost Crystal or Prismatic Tech appearance and native hover/pressed states. Connect to Action Display alongside Spell Action to cast, or use Clickable media for ordinary graph clicks on Display. Appearance alone does not perform an action. Font and Style are optional; Style background and border customize all BV styles. WoW uses Blizzard artwork."
for _,def in pairs(A.catalog) do
    for _,field in ipairs(def.fields or {}) do if ({operation=true,animation=true,targetType=true,source=true,unit=true,phase=true})[field.key] then field.primary=true end end
    def.validate=function(config)
        if def==A.catalog.icon_appearance and not ns.IconSkins.Supports(config.skin or "none",config.shape or "square") then return false,"Shape unavailable for this skin" end
        if config.cropBorder~=nil and type(config.cropBorder)~="boolean" then return false,"Invalid stored icon crop" end
        for _,field in ipairs(def.fields or {}) do
            local v=config[field.key]; if v==nil and field.optional then v=field.default end
            if field.choices then local found=false; for _,c in ipairs(field.choices) do if c==v then found=true end end; if not found then return false,"Invalid "..field.label end
            elseif not A.G.Accepts(field.type,v) then return false,"Invalid "..field.label end
            if field.options=="fonts" and not ns.Media:Reference("font",v) then return false,"Invalid font reference" end
            if field.options=="statusbars" and not ns.Media:Reference("statusbar",v) then return false,"Invalid texture reference" end
            if field.picker=="aura" and (v<1 or v>2147483647) then return false,"Select a positive aura Spell ID" end
            if field.picker=="icon" and not ns.IconCatalog:Reference(v) then return false,"Select a valid icon texture" end
        end
        if def==A.catalog.frame_state and config.reference~="" and (not ns.FrameLibrary or not ns.FrameLibrary:ValidateReference(config.reference)) then return false,"Invalid frame reference" end
        if def==A.catalog.chat_receive and not ns.PlayerChat.ValidReceive(config)then return false,"Invalid chat receive filter"end
        if (def==A.catalog.chat_send or def==A.catalog.chat_direct) and not ns.PlayerChat.ValidSend(config)then return false,"Invalid chat send configuration"end
        if (def.messageSource or def.messageSink or def==A.catalog.chat_receive or def==A.catalog.chat_send or def==A.catalog.chat_direct) and config.permission~=nil and type(config.permission)~="boolean"then return false,"Node permission must be a boolean"end
        if def.messageSource then
            if config.acceptGroup~=nil and type(config.acceptGroup)~="boolean"then return false,"Group permission must be a boolean"end
            if config.senders~=nil and not A.Messaging.Senders(config.senders)then return false,"Use up to 32 Name-Realm senders, comma separated"end
        end
        if def==A.catalog.media_font and not pcall(ns.DisplayModel.NewFont,config) then return false,"Invalid font definition" end
        if def==A.catalog.media_style and not pcall(ns.DisplayModel.NewStyle,config) then return false,"Invalid style definition" end
        if def.display and (type(config.layoutId)~="string" or #config.layoutId~=40 or not config.layoutId:match("^bv_aura:%x+$")) then return false,"Missing display anchor; edit this node to prepare its layout" end
        if (def==A.catalog.media_text or def==A.catalog.media_button) and (config.fontSize<4 or config.fontSize>128) then return false,"Font size must be 4..128" end
        if def==A.catalog.media_overlay and (config.fontSize<4 or config.fontSize>128) then return false,"Font size must be 4..128" end
        if def==A.catalog.icon_cooldown and (config.spellID<1 or config.spellID>2147483647) then return false,"Spell ID must be positive" end
        if def==A.catalog.media_bar and config.source~=nil and config.source~="values" and config.source~="player_health" then return false,"Invalid legacy bar source" end
        if def==A.catalog.media_bar and (not ns.DisplayModel.GlowColor(config.background) or not ns.DisplayModel.GlowColor(config.borderColor)
            or config.borderWidth<0 or config.borderWidth>24) then return false,"Invalid bar background or border" end
        if def.dataSource then for _,key in ipairs({"itemID","spellID"}) do
            if config[key]~=nil and (config[key]<1 or config[key]>2147483647) then return false,"ID must be positive" end
        end end
        if def==A.catalog.totem and (config.slot<1 or config.slot>4) then return false,"Totem slot must be 1..4" end
        if def==A.catalog.player_talent and (config.nodeID<1 or config.nodeID>2147483647) then return false,"Talent node ID must be positive" end
        if def==A.catalog.currency and (config.currencyID<1 or config.currencyID>2147483647) then return false,"Currency ID must be positive" end
        if def==A.catalog.reputation and (config.factionID<0 or config.factionID>2147483647) then return false,"Faction ID must be 0 (watched) or positive" end
        if def==A.catalog.media_graphic then
            if not pcall(ns.DisplayModel.New,"graphic",config) then return false,"Invalid graphic reference or crop" end
            for _,key in ipairs({"left","right","top","bottom"}) do if config[key]<0 or config[key]>1 then return false,"Crop must be 0..1" end end
            if config.left>=config.right or config.top>=config.bottom then return false,"Crop must have positive width and height" end
        end
        if def.messageSource or def.messageSink then
            if type(config.topic)~="string" or #config.topic<1 or #config.topic>40 or not config.topic:match("^[%w_.%-]+$") then return false,"Routing identifier: 1..40 letters, digits, dot, dash or underscore" end
            if def.messageSink and config.channel=="WHISPER" and not config.target:match("^[^%s%-]+%-%S+$") then return false,"Whisper requires Name-Realm" end
            if def.messageSource and config.sender~="" and (type(config.sender)~="string" or #config.sender>96 or config.sender:find("[%c|]") or not config.sender:match("^[^%s%-]+%-%S+$")) then return false,"Sender filter must be empty or Name-Realm" end
        end
        if def==A.catalog.media_interaction or def==A.catalog.media_event then
            if #config.key<1 or #config.key>40 or not config.key:match("^[%w_.%-]+$") then return false,"Interaction key: 1..40 letters, digits, dot, dash or underscore" end
            if config.tooltip and #config.tooltip>256 then return false,"Tooltip must be at most 256 bytes" end
        end
        if def==A.catalog.player_cast and (config.spellID<0 or config.spellID>2147483647) then return false,"Spell ID must be 0 (any) or positive" end
        return true
    end
end
-- Shape choices are scoped to the selected artwork family; legacy nodes default to square.
A.catalog.icon_appearance.resolve=function(config)
    local base=A.catalog.icon_appearance
    local valid,why=base.validate(config);if not valid then return nil,why end
    local def=A.G.Copy(base);def.resolve=nil;def.fields={}
    for _,field in ipairs(base.fields) do
        if field.key~="shape" then def.fields[#def.fields+1]=A.G.Copy(field)
        else
            local choices=ns.IconSkins.Shapes(config.skin or "none")
            if #choices>1 then local f=A.G.Copy(field);f.choices=choices;def.fields[#def.fields+1]=f end
        end
    end
    return def
end
A.order={"spell_action","action_display","icon_appearance","media_button","hp","number","boolean","constant_nil","is_nil","secret","multiply","compare","logic_and","logic_or","logic_not","logic_select","logic_branch","context","gate","timer","remaining_estimate","interval","format","chat","aura","media_icon","media_text","display","opacity","tint","glow","text_outline","text_shadow","icon_border","scale","size","offset","rotate","circle","rotate_offset"}
table.insert(A.order,1,"player")
for index,kind in ipairs({"target","focus","target_target","focus_target","party_member","raid_member","pet","nameplate"}) do table.insert(A.order,index+1,kind) end
for _,kind in ipairs({"media_font","media_style","media_bar","icon_cooldown","media_overlay","media_graphic","player_state","location","item_count","item_equipped","spell_cooldown","spell_proc","message_send","message_receive"}) do A.order[#A.order+1]=kind end
for _,kind in ipairs({"shake","pulse","float","fade"}) do A.order[#A.order+1]="animation_"..kind end
-- Hidden from creation only; retain Clickable media for existing graphs and future reuse.
-- A.order[#A.order+1]="media_interaction"
A.order[#A.order+1]="media_event"
for _,kind in ipairs({"chat_receive","chat_send","chat_direct","player_cast","player_swing","unit_record","bar_duration","icon_duration"}) do A.order[#A.order+1]=kind end
-- Preserve old serialized IDs while offering the unified source for new nodes.
for i=#A.order,1,-1 do if ({hp=true,player_state=true,context=true})[A.order[i]] then table.remove(A.order,i) end end
local consolidated={player=true,target=true,focus=true,target_target=true,focus_target=true,party_member=true,raid_member=true,pet=true,nameplate=true,aura=true,player_cast=true}
for i=#A.order,1,-1 do if consolidated[A.order[i]]then table.remove(A.order,i)end end
for i,kind in ipairs({"unit","unit_aura","unit_cast","nameplates","nameplates_aura","nameplates_cast"})do table.insert(A.order,i,kind)end
A.order[#A.order+1]="display_stack"
A.order[#A.order+1]="debug_value"
A.order[#A.order+1]="format_values"
A.order[#A.order+1]="frame_state"
-- Old spell test nodes remain loadable, but are no longer offered for new graphs.
function A.CastButtonExample()
    local g=A.G.New()
    local action=A.G.Add(g,"spell_action",A.catalog,0,0)
    local media=A.G.Add(g,"media_button",A.catalog,0,320)
    local display=A.G.Add(g,"action_display",A.catalog,400,80)
    g.nodes[media].values.text="Unending Breath"
    g.edges={{from=action,output="action",to=display,input="action"},
        {from=media,output="media",to=display,input="media"}}
    return g
end
function A.SelfBuffExample()
    local g=A.G.New()
    local aura=A.G.Add(g,"aura",A.catalog,0,0);g.nodes[aura].config.spellID=5697
    local missing=A.G.Add(g,"logic_not",A.catalog,360,0)
    local button=A.G.Add(g,"secure_spell",A.catalog,720,0)
    g.edges={{from=aura,output="present",to=missing,input="value"},{from=missing,output="result",to=button,input="highlight"}}
    return g
end
for _,operation in ipairs({"set","get","delete","clear"}) do A.order[#A.order+1]="memory_"..operation end
for _,kind in ipairs({"spell_charges","spell_usable","spell_known","totem"}) do A.order[#A.order+1]=kind end
for _,kind in ipairs({"player_xp","player_money","currency","reputation","player_talent"}) do A.order[#A.order+1]=kind end
do
    local replaced={multiply=true,logic_and=true,logic_or=true,logic_not=true,format=true,format_values=true,
        animation_shake=true,animation_pulse=true,animation_float=true,animation_fade=true,
        memory_get=true,memory_set=true,memory_delete=true,memory_clear=true,player_money=true,player_xp=true}
    for i=#A.order,1,-1 do if replaced[A.order[i]] then table.remove(A.order,i) end end
    for _,kind in ipairs({"math","logic","parse","animation","memory","media_crop","encounter_event","ready_check_event","string_formatter","round","time_format","last_unprotected_value"}) do A.order[#A.order+1]=kind end
end
-- Safe copy-on-write family upgrade. A failed structural check retains the
-- complete original graph; unknown extension nodes and custom data are intact.
function A.MigrateNodeFamilies(graph)
    local G=A.G
    if type(graph)~="table" or type(graph.nodes)~="table" or type(graph.edges)~="table" then return graph end
    local out,changed=G.Copy(graph),false
    local units={player="player",target="target",focus="focus",target_target="target_target",focus_target="focus_target",party_member="party_member",raid_member="raid_member",pet="pet"}
    local function renameInput(node,old,new)
        node.values[new]=node.values[old];node.values[old]=nil
        node.exposed[new]=node.exposed[old];node.exposed[old]=nil
        for _,edge in ipairs(out.edges) do if edge.to==node.id and edge.input==old then edge.input=new end end
    end
    for _,node in pairs(out.nodes) do
        local kind=node.type;local target,operation
        if kind=="multiply" then target,operation="math","multiply"
        elseif kind=="logic_and" or kind=="logic_or" or kind=="logic_not" then target,operation="logic",kind:sub(7)
        elseif kind:match("^animation_") and A.catalog[kind] then target,operation="animation",kind:sub(11)
        elseif kind:match("^memory_") and A.catalog[kind] then target,operation="memory",kind:sub(8)
        elseif kind=="aura" then target="unit_aura"
        elseif units[kind] or kind=="player_money" or kind=="player_xp" or kind=="player_state" then target="unit"
        elseif kind=="format" then
            -- A connected template cannot be rewritten safely. New brace tokens
            -- in old literal text also keep the legacy formatter unchanged.
            local wired=false;for _,edge in ipairs(out.edges) do if edge.to==node.id and edge.input=="template" then wired=true end end
            local template=node.values.template or "HP: {value}%"
            local stripped=type(template)=="string" and template:gsub("{value}","")
            if not wired and stripped and not stripped:find("{[^{}]+}") then target="format_values" end
        end
        if target then
            local old=G.Definition(A.catalog[kind],node)
            if not old then return graph,"legacy definition unavailable" end
            -- Explicitly retain old defaults before the new definition changes
            -- defaults or labels (AND=true, Multiply factor=3, animation strength).
            for key,p in pairs(G.Ports(old)) do if node.values[key]==nil and p.default~=nil then node.values[key]=G.Copy(p.default) end end
            local config=G.Copy(A.catalog[target].defaults)
            if kind=="aura" and node.config.cropBorder==nil then config.cropBorder=true end
            for key,value in pairs(node.config) do config[key]=value end
            node.config=config;node.type=target;changed=true
            if target=="animation" then config.animation=operation
            elseif target=="logic" then config.operation=operation;if operation=="not" then renameInput(node,"value","in1") end
            elseif target=="math" or target=="memory" then config.operation=operation
            elseif target=="format_values" then
                config.count=1;config.decimals=2;config.hideZero=false;config.hideOne=false
                node.values.template=node.values.template:gsub("{value}","{value1}");renameInput(node,"value","value1")
            elseif target=="unit" then
                config.unit=units[kind] or "player"
                local rename=kind=="player_money" and {copper="moneyCopper"} or kind=="player_xp" and {current="xpCurrent",maximum="xpMaximum",rested="xpRested",level="xpLevel",disabled="xpDisabled",capped="xpCapped"}
                if rename or kind=="player_state" then
                    config.outputs={}
                    for output in pairs(old.outputs) do config.outputs[rename and rename[output] or output]=true end
                    if rename then for _,edge in ipairs(out.edges) do if edge.from==node.id then edge.output=rename[edge.output] or edge.output end end end
                end
            elseif target=="unit_aura" then config.unit="player" end
        end
    end
    if not changed then return graph end
    local plan=G.Compile(out,A.catalog,true)
    if not plan then return graph,"legacy compatibility retained" end
    return out,"node families migrated"
end
-- Legacy icon nodes remain supported; conversion is an explicit undoable edit.
function A.TimeExample(kind)
    local g=A.G.New()
    local function add(t,x,y) return A.G.Add(g,t,A.catalog,x,y) end
    local function edge(a,out,b,input) g.edges[#g.edges+1]={from=a,output=out,to=b,input=input} end
    local source=add(kind,0,30)
    if kind=="interval" then
        g.nodes[source].values.seconds=5
        local chat=add("chat",320,30); g.nodes[chat].values.text="Interval: five seconds."
        edge(source,"event",chat,"event")
    else
        if kind=="remaining_estimate" then
            local aura=add("aura",0,430)
            edge(aura,"remaining",source,"value"); edge(aura,"present",source,"active")
        end
        local format=add("format",320,30); g.nodes[format].values.template="Time: {value} s"
        local text=add("media_text",640,30); local display=add("display",960,30)
        edge(source,"value",format,"value"); edge(format,"text",text,"text"); edge(text,"media",display,"media")
        if kind=="timer" then
            local chat=add("chat",320,440); g.nodes[chat].values.text="Timer finished."
            edge(source,"finished",chat,"event")
        end
    end
    return g
end
function A.MediaExample(text)
    local g=A.G.New(); local media=A.G.Add(g,text and "media_text" or "media_icon",A.catalog,0,30)
    local output=A.G.Add(g,"display",A.catalog,340,30)
    g.edges={{from=media,output="media",to=output,input="media"}}; return g
end
function A.LogicExample(branch)
    local g=A.G.New()
    local function add(kind,x,y) return A.G.Add(g,kind,A.catalog,x,y) end
    local function edge(from,output,to,input) g.edges[#g.edges+1]={from=from,output=output,to=to,input=input} end
    if branch then
        local source=add("boolean",0,0); g.nodes[source].config.value=true
        local gate=add("gate",300,0)
        local context=add("context",300,280)
        local route=add("logic_branch",600,0)
        local yes=add("chat",900,0); local no=add("chat",900,280)
        g.nodes[yes].values.text="Branch: in combat."
        g.nodes[no].values.text="Branch: out of combat."
        edge(source,"value",gate,"condition"); edge(gate,"event",route,"value"); edge(context,"combat",route,"condition")
        edge(route,"yes",yes,"event"); edge(route,"no",no,"event")
    else
        local source=add("boolean",0,0)
        local invert=add("logic_not",280,0)
        local select=add("logic_select",560,0); g.nodes[select].config.payloadType="string"
        g.nodes[select].values.yes="NOT / Invert: true"; g.nodes[select].values.no="NOT / Invert: false"
        local media=add("media_text",560,440); local output=add("display",900,440)
        edge(source,"value",invert,"value"); edge(invert,"result",select,"condition")
        edge(select,"value",media,"text"); edge(media,"media",output,"media")
    end
    return g
end
function A.EffectsExample(text)
    local g=A.MediaExample(text); local previous="n1"; g.edges={}
    for index,kind in ipairs(text and {"text_shadow","text_outline","glow"} or {"icon_border","glow"}) do
        local id=A.G.Add(g,kind,A.catalog,index*300,30)
        if kind=="glow" then
            g.nodes[id].values.strength=.85; g.nodes[id].values.pulse=true
            g.nodes[id].values.color=text and "FFD100" or "AE95FF"
        end
        g.edges[#g.edges+1]={from=previous,output="media",to=id,input="media"}; previous=id
    end
    g.nodes.n2.x=text and 1200 or 900
    g.edges[#g.edges+1]={from=previous,output="media",to="n2",input="media"}; return g
end
function A.OrbitExample()
    local g=A.G.New()
    local angle=A.G.Add(g,"number",A.catalog,0,0); g.nodes[angle].config.value=0
    local media=A.G.Add(g,"media_icon",A.catalog,0,220)
    local function edge(from,output,to,input) g.edges[#g.edges+1]={from=from,output=output,to=to,input=input} end
    for i=0,4 do
        local circle=A.G.Add(g,"circle",A.catalog,320,i*330)
        g.nodes[circle].values.angle=i*72; g.nodes[circle].values.radius=120
        local rotate=A.G.Add(g,"rotate_offset",A.catalog,640,i*330)
        local offset=A.G.Add(g,"offset",A.catalog,960,i*330); g.nodes[offset].config.mode="layout"
        local display=A.G.Add(g,"display",A.catalog,1280,i*330)
        edge(circle,"x",rotate,"x"); edge(circle,"y",rotate,"y"); edge(angle,"value",rotate,"angle")
        edge(rotate,"x",offset,"x"); edge(rotate,"y",offset,"y"); edge(media,"media",offset,"media"); edge(offset,"media",display,"media")
    end
    return g
end
function A.IconExample()
    local G=A.G; local g=G.New()
    local aura=G.Add(g,"aura",A.catalog,0,30)
    local icon=G.Add(g,"icon",A.catalog,310,30)
    g.edges={{from=aura,output="present",to=icon,input="visible"}}
    return g
end
function A.AuraExample()
    local G=A.G; local g=G.New()
    local aura=G.Add(g,"aura",A.catalog,0,30)
    local gate=G.Add(g,"gate",A.catalog,285,30)
    local chat=G.Add(g,"chat",A.catalog,570,30)
    g.nodes[chat].values.text="Selected player aura is active."
    g.edges={{from=aura,output="present",to=gate,input="condition"},{from=gate,output="event",to=chat,input="event"}}
    return g
end
function A.Example()
    local G=A.G; local g=G.New()
    local hp=G.Add(g,"hp",A.catalog,0,30)
    local compare=G.Add(g,"compare",A.catalog,270,0)
    local gate=G.Add(g,"gate",A.catalog,540,0)
    local fmt=G.Add(g,"format",A.catalog,270,285)
    local chat=G.Add(g,"chat",A.catalog,810,130)
    g.edges={{from=hp,output="percent",to=compare,input="value"},{from=compare,output="result",to=gate,input="condition"},
        {from=hp,output="percent",to=fmt,input="value"},{from=fmt,output="text",to=chat,input="text"},{from=gate,output="event",to=chat,input="event"}}
    return g
end

-- One editable composition; every element targets the same stable unit slot.
local _,A=...
if A.blocked then return end
local G=A.G
local Actions=BVAddonSuiteCore.Actions
local V=BVAddonSuiteCore.GraphValues
do
    local base=A.catalog.action_display
    local validate=base.validate
    base.inputs.highlight=nil
    base.inputs.hoverMedia={label="Hover Media",type="media",wire=true,required=false,optional=true,order=3}
    base.inputs.pressedMedia={label="Pressed Media",type="media",wire=true,required=false,optional=true,order=4}
    base.defaults.click_left=true;base.defaults.legacySuggest=false;base.fields={}
    for _,key in ipairs(Actions.bindingOrder) do
        base.fields[#base.fields+1]={key="click_"..key,label=Actions.bindings[key].label,type="boolean",optional=true,default=key=="left",advanced=key~="left" and key~="right"}
    end
    base.help="Enable the desired click/modifier combinations in settings; only those Action inputs appear. Unbound combinations do nothing. Click Actions emit graph-local Media Events; spell/item/macro actions remain native hardware clicks. Hover Media and Pressed Media override appearance only, with Pressed taking priority. Prepare protected bindings and geometry outside combat. Test never executes actions."
    base.resolve=function(c)
        local d=G.Copy(base);d.resolve=nil;d.inputs={media=G.Copy(base.inputs.media),hoverMedia=G.Copy(base.inputs.hoverMedia),pressedMedia=G.Copy(base.inputs.pressedMedia)}
        for i,key in ipairs(Actions.bindingOrder) do
            local selected=c["click_"..key];if selected==nil then selected=key=="left" end
            if type(selected)~="boolean" then return nil,"Click selections must be boolean" end
            if selected then d.inputs[key=="left" and "action" or "action_"..key]={label=Actions.bindings[key].label,type="action",wire=true,required=false,optional=true,order=10+i} end
        end
        if c.legacySuggest then d.inputs.highlight={label="Legacy glow condition",type="boolean",default=false,required=false,order=90,advanced=true} end
        d.validate=validate
        return d
    end
end
do
    local base={label="Click Action",interactionProducer=true,clickAction=true,inputs={},outputs={action={label="Action",type="action",order=1}},
        defaults={key="media.click",payload={},nextPayloadId=1},fields={{key="key",label="Interaction key",type="string"}},
        help="A real selected mouse/modifier click emits Media Event in this graph with this key and a captured typed payload. Add payload fields in settings. This node never executes spells or macros; graph evaluation and Test never click."}
    base.resolve=function(c)
        if type(c.key)~="string" or #c.key<1 or #c.key>40 or not c.key:match("^[%w_.%-]+$") or not V.ClickSchema(c.payload) then return nil,"Invalid click key or payload schema" end
        if c.nextPayloadId~=nil and (not G.Number(c.nextPayloadId) or c.nextPayloadId%1~=0 or c.nextPayloadId<1 or c.nextPayloadId>1000000000) then return nil,"Invalid payload ID" end
        local d=G.Copy(base);d.resolve=nil;d.secretInputs={}
        for i,f in ipairs(c.payload or {}) do
            d.inputs[f.id]={label=f.label,type=f.type,wire=true,required=false,optional=true,order=i,maySecret=true};d.secretInputs[f.id]=true
        end
        return d
    end
    A.catalog.click_action=base;A.order[#A.order+1]="click_action"
end
local units={"player","target","targettarget","focus","focustarget","pet","mouseover"}
for i=1,4 do units[#units+1]="party"..i end
for i=1,40 do units[#units+1]="raid"..i end
local optionalUnits={"default"};for _,u in ipairs(units) do optionalUnits[#optionalUnits+1]=u end
local function field(key,label,kind,choices,picker) return {key=key,label=label,type=kind,choices=choices,picker=picker} end
local function unit(c) return c.target~="default" and c.target or nil end
local function add(id,label,defaults,fields,build,help)
    local d={label=label,source=true,actionSource=true,inputs={},outputs={action={label="Action",type="action",order=1,optional=id=="macro_action"}},
        defaults=defaults,fields=fields,makeAction=build,
        help=help.." Connect Action and separate Media to Action Display. Only its selected physical click/modifier combination executes the action; graph evaluation and Test never execute it. Configure and apply outside combat."}
    d.validate=function(c)
        for _,f in ipairs(fields) do
            local v=c[f.key]
            if f.choices then local found=false;for _,choice in ipairs(f.choices) do if choice==v then found=true end end;if not found then return false,"Invalid "..f.label end
            elseif not G.Accepts(f.type,v) then return false,"Invalid "..f.label end
        end
        if id=="macro_action" and c.name=="" and (c.scope=="account" or c.scope=="character") then return true end
        if not Actions.Valid(build(c)) then return false,"Choose valid action settings" end
        return true
    end
    A.catalog[id]=d;A.order[#A.order+1]=id
end
add("item_action","Item Action",{source="item",itemID=5512,slot=13,target="default"},
    {field("source","Use","string",{"item","slot"}),field("itemID","Item ID","integer",nil,"item"),field("slot","Equipment slot","integer"),field("target","Target","string",optionalUnits)},
    function(c) return {kind="item",itemID=c.source=="item" and c.itemID or nil,slot=c.source=="slot" and c.slot or nil,unit=unit(c)} end,
    "Use an item by ID or equipment slot (1..19; trinkets 13/14). Blizzard may equip an unequipped equippable item. Default leaves targeting to the game.")
add("unit_action","Unit Action",{operation="target",target="target"},
    {field("operation","Action","string",{"target","clear","assist","focus"}),field("target","Unit","string",units)},
    function(c) return {kind=c.operation=="clear" and "target" or c.operation,unit=c.operation=="clear" and "none" or c.target} end,
    "Target, clear target, assist or focus a stable unit token. Focus requires client support. Target clicks also follow Blizzard's active spell/item cursor behavior.")
add("macro_action","Macro Action",{name="",scope="account"},
    {field("name","Saved macro","string",nil,"macro"),field("scope","Scope","string",{"account","character"})},
    function(c) if c.name~="" then return {kind="macro",name=c.name,scope=c.scope} end end,
    "Select, create or edit a saved game macro. Name and account/character scope identify it; ambiguous or missing macros stay inactive. Save in the macro editor explicitly changes the game macro outside combat. Graph imports never write macro text.")
add("pet_action","Pet Action",{slot=1,target="default"},
    {field("slot","Pet bar slot (1-10)","integer"),field("target","Target","string",optionalUnits)},
    function(c) return {kind="pet",slot=c.slot,unit=unit(c)} end,"Click a pet action bar slot. The current action in that slot belongs to the current pet.")
add("action_slot","Action Slot",{slot=1},{field("slot","Action bar slot (1-180)","integer")},
    function(c) return {kind="action",slot=c.slot} end,"Use an absolute action bar slot without page remapping. Content follows the game's slot; available slots and flyouts depend on the client.")
add("cancel_aura_action","Cancel Aura",{spellID=5697},{field("spellID","Own buff","integer",nil,"aura")},
    function(c) return {kind="cancelaura",spellID=c.spellID} end,"Cancel a cancellable buff on yourself. The spell ID resolves to Blizzard's spell name outside combat; harmful auras cannot be removed this way.")
add("marker_action","Marker Action",{source="raidtarget",marker=1,operation="toggle",target="target"},
    {field("source","Marker type","string",{"raidtarget","worldmarker"}),field("marker","Marker (1-8)","integer"),field("operation","Action","string",{"set","clear","toggle"}),field("target","Unit","string",units)},
    function(c) return {kind=c.source,marker=c.marker,operation=c.operation,unit=c.source=="raidtarget" and c.target or nil} end,
    "Set, clear or toggle a target or world marker through Blizzard's secure handler. World marker placement opens the placement cursor. Group permissions still apply.")
add("unit_menu_action","Unit Menu",{target="player"},{field("target","Unit","string",units)},
    function(c) return {kind="togglemenu",unit=c.target} end,"Open Blizzard's context menu for the selected unit. Menu content follows the unit and client.")
add("ui_action","UI Action",{operation="character"},{field("operation","Panel","string",{"character","spellbook","bags","map"})},
    function(c) return {kind="ui",operation=c.operation} end,"Toggle character, spellbook, bags or world map. Available outside combat; unsupported client APIs are reported on click.")
add("group_action","Group Action",{operation="readycheck",seconds=10},
    {field("operation","Action","string",{"readycheck","countdown"}),field("seconds","Countdown seconds","integer")},
    function(c) return {kind="group",operation=c.operation,seconds=c.seconds} end,"Start a ready check or a 1..3600 second countdown outside combat. Requires group leader or assistant; permissions are checked on each click.")
local targets={player=true,target=true,targettarget=true,focus=true,focustarget=true,party=true,raid=true}
for _,kind in ipairs({"secure_action_stack","ooc_action_stack"}) do
    local base=G.Copy(A.catalog.display_stack)
    base.label=kind=="secure_action_stack" and "Secure Action Stack" or "Out-of-Combat Action Stack"
    base.actionStack=true;base.actionMode=kind=="secure_action_stack" and "secure" or "ooc"
    base.defaults.spellID=5697;base.defaults.target="player";base.defaults.columns=1;base.defaults.spacingX=12;base.defaults.spacingY=12
    base.fields={{key="spellID",label="Spell",type="integer",picker="aura"},
        {key="target",label="Action target",choices={"player","target","targettarget","focus","focustarget","party","raid"},
            choiceLabels={player="Player",target="Target",targettarget="Target of Target",focus="Focus",focustarget="Target of Focus",party="Party members (1-4)",raid="Raid members (1-40)"}},
        {key="columns",label="Columns",type="integer"},{key="spacingX",label="Column gap",type="float"},{key="spacingY",label="Row gap",type="float"}}
    base.help="Compose up to eight icon, text or bar elements. Each element casts the same configured spell on its stable target slot; gaps are not clickable. Instance is optional for shared media; connect a matching Group source for per-member media. Party excludes player; Raid uses slots 1..40. All surfaces are prepared outside combat. Free screen root only; no nameplate/cursor/external anchors. Apply changes outside combat. Geometry and action freeze in combat; Suggest is cosmetic. Missing observations display an explicit slot placeholder. Test never casts. Native group/raid acceptance is pending."
    if base.actionMode=="ooc" then base.help=base.help.." This variant has a native out-of-combat click gate and a combat visibility driver." end
    base.validate=nil
    base.resolve=function(config)
        if not G.Number(config.spellID) or config.spellID<1 or config.spellID>2147483647 or config.spellID~=math.floor(config.spellID) then return nil,"Choose a positive Spell ID" end
        if not targets[config.target] then return nil,"Choose a supported action target" end
        if not G.Number(config.columns) or config.columns<1 or config.columns>40 or config.columns~=math.floor(config.columns) then return nil,"Columns must be 1..40" end
        for _,key in ipairs({"spacingX","spacingY"}) do if not G.Number(config[key]) or config[key]<0 or config[key]>512 then return nil,"Spacing must be 0..512" end end
        local d,why=A.catalog.display_stack.resolve(config);if not d then return nil,why end
        d.label=base.label;d.actionStack=true;d.actionMode=base.actionMode;d.defaults=base.defaults;d.fields=base.fields;d.help=base.help;d.validate=nil
        d.inputs.sort=nil;d.inputs.visible=nil;d.inputs.instance.required=false
        d.inputs.highlight={label="Suggest (visual only)",type="boolean",default=false,required=false,order=3}
        if d.actionMode=="ooc" then
            d.inputs.spell={label="Spell ID override (OOC)",type="integer",required=false,order=2}
            d.inputs.visible={label="Visible (OOC)",type="boolean",default=true,required=false,order=3}
            d.help=d.help.." Optional Spell ID override and Visible prepare changes outside combat. An unavailable connected override disables the request; it never falls back to another spell."
        end
        return d
    end
    -- Compatibility for saved/imported test graphs; creation uses Spell Action.
    A.catalog[kind]=base
end
function A.ActionStackExample(ooc)
    local g=G.New()
    local aura=G.Add(g,"aura",A.catalog,0,0);g.nodes[aura].config.spellID=5697
    local missing=G.Add(g,"logic_not",A.catalog,340,0)
    local icon=G.Add(g,"media_icon",A.catalog,0,330)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok,texture=pcall(C_Spell.GetSpellTexture,5697)
        if ok and G.Number(texture) and texture>0 then g.nodes[icon].values.texture=texture;g.nodes[icon].config.texture=tostring(texture) end
    end
    local text=G.Add(g,"media_text",A.catalog,340,330);g.nodes[text].values.text="Unending Breath / self"
    local action=G.Add(g,ooc and "ooc_action_stack" or "secure_action_stack",A.catalog,700,0)
    g.nodes[action].config.elements={{id="media1",label="Icon"},{id="media2",label="Text"}};g.nodes[action].config.nextElementId=3
    g.edges={{from=aura,output="present",to=missing,input="value"},{from=missing,output="result",to=action,input="highlight"},
        {from=icon,output="media",to=action,input="media1"},{from=text,output="media",to=action,input="media2"}}
    return g
end

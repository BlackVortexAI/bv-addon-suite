-- Common single-unit questions without exposing native record plumbing.
-- Specialized aura/cast/collection sources and the generic record reader stay
-- separate. All data still passes through UnitSource and UnitData contracts.
local _,A=...
if A.blocked then return end
local G,C,P=A.G,A.UnitDataCatalog,A.UnitSource
local I={fields={}};A.UnitInformation=I
local choices,labels={},{}
local function add(key,label,root,schema,field)
    local original=A.catalog.unit.selectableOutputs[root or key]
    assert(original,"Missing unit information source: "..tostring(root or key))
    local output=G.Copy(original);output.label=label;output.order=1;output.optional=true
    if root then
        output.type=assert(C.schemas[schema][field]);output.maySecret=true
        P.projections[key]={source=root,schema=schema,field=field}
        C.fields[key]={key=key,type=output.type,label=label}
        C.dynamic[key]=C.dynamic[root]
    end
    I.fields[key]={source=root or key,port=output}
    choices[#choices+1]=key;labels[key]=label
end
for _,item in ipairs({
    {"health","Health"},{"healthMax","Maximum health"},{"healthPercent","Health percentage"},
    {"power","Current power"},{"powerMax","Maximum power"},{"powerToken","Power type"},
    {"mana","Mana"},{"manaMax","Maximum mana"},{"rage","Rage"},{"energy","Energy"},
    {"focus","Focus resource"},{"comboPoints","Combo points"},{"runicPower","Runic power"},
    {"exists","Exists"},{"name","Name"},{"realm","Realm"},{"level","Level"},
    {"className","Class name"},{"classIcon","Class icon"},{"classColor","Class colour"},
    {"groupRolesAssigned","Group role"},{"roleIcon","Role icon"},{"combat","In combat"},
    {"isDead","Dead"},{"mounted","Mounted (Player)"},{"resting","Resting (Player)"},
    {"moving","Moving (Player)"},{"getUnitSpeed_currentSpeed","Movement speed"},
    {"moneyCopper","Money in copper (Player)"},{"xpCurrent","Experience (Player)"},
    {"xpMaximum","Experience required (Player)"},{"xpRested","Rested experience (Player)"},
}) do add(item[1],item[2]) end
for _,item in ipairs({
    {"currentHealth","Prediction: current health"},{"maximumHealth","Prediction: maximum health"},
    {"missingHealth","Prediction: missing health"},{"incomingHeals","Prediction: incoming heals"},
    {"damageAbsorbs","Prediction: damage absorbs"},{"healAbsorbs","Prediction: heal absorbs"},
}) do add("info_healPrediction_"..item[1],item[2],"healPrediction","calculator",item[1]) end
for _,item in ipairs({{"ID","Power bar: ID"},{"barType","Power bar: type"},{"minPower","Power bar: minimum"},
    {"hideFromOthers","Power bar: hidden from others"},{"forcePercentage","Power bar: percentage display"}}) do
    add("info_powerBar_"..item[1],item[2],"getUnitPowerBarInfo","powerBar",item[1])
end
local base={label="Unit information",category="sources",source=true,unitSource=true,sourceFamily="unit",unitKind="unit",
    inputs={},outputs={},defaults=G.Copy(A.catalog.unit.defaults),fields={},
    help="Choose whose data you need and one information field. Party/Raid selects one roster position; connect Slot to change it dynamically. Protected values stay protected and can only reach compatible displays. Missing data stays unknown, never zero or false. Prediction fields use native results, not inferred health. Use Unit for specialist fields, Unit Aura/Unit Cast for those observations, and Unit record field for other bounded records."}
base.defaults.outputs=nil;base.defaults.information="health"
base.resolve=function(config)
    local selected=I.fields[config.information]
    if not selected then return nil,"Choose a supported information field" end
    local query=G.Copy(config);query.outputs={[selected.source]=true}
    local unit,why=A.catalog.unit.resolve(query);if not unit then return nil,why end
    local d=G.Copy(base);d.resolve=nil;d.inputs=unit.inputs;d.slotInput=unit.slotInput
    d.outputs={[config.information]=G.Copy(selected.port)}
    d.fields={}
    for _,field in ipairs(unit.fields) do
        if field.key=="unit" then field.label="Whose data";field.primary=true end
        d.fields[#d.fields+1]=field
        if field.key=="unit" then d.fields[#d.fields+1]={key="information",label="Information",choices=choices,choiceLabels=labels,primary=true} end
    end
    return d
end
A.catalog.unit_information=base
table.insert(A.order,1,"unit_information")

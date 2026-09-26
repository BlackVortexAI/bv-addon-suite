-- Repeated party/raid adapters reuse the validated unit source contracts.
local _,A=...
if A.blocked then return end
local G=A.G
local function groupKind(config)
    local kind=config and config.kind
    if not G.IsSecret(kind) and (kind=="party" or kind=="raid") then return kind end
end
function A.CollectionKind(node)
    local def=node and A.catalog[node.type]
    if not def or not def.collectionSource then return end
    return def.groupSource and groupKind(node.config) or not def.groupSource and "nameplates" or nil
end
function A.CollectionTokens(def,config)
    if not def or not def.collectionSource then return {} end
    local kind="nameplates";if def.groupSource then kind=groupKind(config) end
    if not kind then return {} end
    local prefix,limit=kind=="party" and "party" or kind=="raid" and "raid" or "nameplate",kind=="party" and 4 or 40
    local result={};for i=1,limit do result[i]=prefix..i end;return result
end
local function register(id,original,label)
    local template=assert(A.catalog[original]);local base=G.Copy(template)
    base.label=label;base.groupSource=true;base.unitKind="group"
    base.defaults.kind="party";base.defaults.relation="ALL"
    base.fields={{key="kind",label="Group",choices={"party","raid"},choiceLabels={party="Party (1–4)",raid="Raid (1–40)"}}}
    for _,field in ipairs(template.fields) do if field.key~="relation" then base.fields[#base.fields+1]=G.Copy(field) end end
    if id=="group_units" then base.defaults.outputs.exists=true end
    base.help="Observe each current Party or Raid slot as an independent instance. Party means party1–party4 (the player is separate); Raid means raid1–raid40. Slots are temporary: roster replacement resets the old instance. Connect Instance to Display Stack to keep each unit's media together. This is ordinary read-only output, not a secure targeting or raid-frame replacement. Secret fields stay opaque and unavailable fields are not zero."
    if base.auraSource then base.help=base.help.." Aura identity/filter must be accessible; only readable expiration drives Remaining. Present Estimate passes readable Present through. For Secret player HELPFUL Present, a canonical active CDM self-aura family can supply true; otherwise it uses false. This estimate does not certify an exact hidden rank or absence. Other unavailable observations stay unavailable. Duration Estimate holds the last readable duration; Remaining Estimate has no value (nil) and clears its countdown baseline whenever Present Estimate is false. Otherwise it counts down from the last readable remaining observation while timing is Secret. After a stop, a new readable timing observation is required. Zero or elapsed remaining time also yields no value (nil). No baseline means no estimate. Absence, binding/aura changes, unavailable timing and Mute clear history; hidden refreshes can make estimates wrong."
    elseif base.sourceFamily=="cast" then base.help=base.help.." Cast succeeded is a fresh native unit event, never inferred or replayed." end
    local function validate(config)
        if not groupKind(config) then return false,"Choose Party or Raid" end
        if config.relation~="ALL" then return false,"Group sources use all current roster slots" end
        return template.validate(config)
    end
    base.validate=validate
    base.resolve=function(config)
        if not groupKind(config) then return nil,"Choose Party or Raid" end
        if config.relation~="ALL" then return nil,"Group sources use all current roster slots" end
        -- The template resolver closes over its original family. Retain only
        -- its specialized outputs, then return this group's own metadata.
        local resolved,why=template.resolve(config);if not resolved then return nil,why end
        local result=G.Copy(base);result.resolve=nil;result.outputs=resolved.outputs;result.validate=validate
        return result
    end
    A.catalog[id]=base;A.order[#A.order+1]=id
end
register("group_units","nameplates","Group units")
register("group_aura","nameplates_aura","Group aura")
register("group_cast","nameplates_cast","Group cast")
-- New nodes only: existing saved output selections are intentionally unchanged.
A.catalog.unit.defaults.outputs.exists=true

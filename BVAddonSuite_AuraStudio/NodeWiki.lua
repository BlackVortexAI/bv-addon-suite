-- Static, read-only documentation. Never inspect a runtime value or call a
-- native unit API here. Availability guidance never reads the current game state.
local _,A=...
if A.blocked then return end
local G,D=A.G,A.NodeWikiData
local W={};A.NodeWiki=W
local function plain(v,kind)local ok,hidden=pcall(G.IsSecret,v);return ok and not hidden and type(v)==kind end
local function str(v) return plain(v,"string") and #v<256 and v or nil end
local function tbl(v)
    if not plain(v,"table") then return end
    if issecrettable then local ok,value=pcall(issecrettable,v);if not ok or value then return end end
    if canaccesstable then local ok,value=pcall(canaccesstable,v);if not ok or not value then return end end
    return not getmetatable(v) and v or nil
end
local function config(node,base)
    local out={};local source=tbl(node.config) or {}
    for key,value in pairs(base.defaults or {}) do
        local chosen=source[key]
        if plain(chosen,type(value)) then
            if type(value)=="table" then
                local selected=tbl(chosen);out[key]={}
                if base.displayStack and key=="elements"then
                    for i=1,8 do
                        local item=selected and tbl(selected[i]);local id=item and str(item.id);local label=item and str(item.label)
                        if id and id:match("^media[1-9]%d*$") and #id<=16 and label and #label>0 and #label<=48 and not label:find("[%c|]")then
                            local element={id=id,label=label};local layoutId=str(item.layoutId)
                            if layoutId and #layoutId==40 and layoutId:match("^bv_aura:%x+$")then element.layoutId=layoutId end
                            out[key][#out[key]+1]=element
                        end
                    end
                    if #out[key]==0 then out[key]=G.Copy(value)end
                elseif (base.interactionProducer or base.interactionConsumer) and key=="payload" then
                    if selected and BVAddonSuiteCore.GraphValues.ClickSchema(selected) then out[key]=G.Copy(selected) end
                else
                    for k in pairs(base.selectableOutputs or {}) do
                        local flag=selected and selected[k];if plain(flag,"boolean") and flag then out[key][k]=true end
                    end
                end
            elseif type(value)=="number" then out[key]=G.Number(chosen) and chosen or value
            elseif type(value)=="string" then out[key]=#chosen<=256 and chosen or value
            else out[key]=chosen end
        else out[key]=G.Copy(value) end
    end
    return out
end
local function unit(node,base,c)
    if base.collectionSource then return base.groupSource and c.kind or "nameplates"end
    if node.type=="hp" or node.type=="player_state" or node.type=="context" then return "player" end
    return A.UnitSource.Token(base.unitKind or node.type,c)
end
-- Past captures did not retain query options. Never infer equivalence for a
-- configured query; preserve this limitation even when displaying default runs.
local function compatible(query,c)
    for _,arg in ipairs(query.args or {}) do
        if type(arg)=="string" then
            local option=arg:match("^%$option:(.+)$")
            if arg=="$spellID" then option="spellID" elseif arg=="$spellName" then option="spellName" end
            if arg=="$auraID" or arg=="$auraSlot" then option="auraIndex" end
            if option and c[option]~=nil and c[option]~=D.queryDefaults[option] then return false end
        end
    end
    return true
end
local indexed={auras=true,controls=true,numbers=true,tooltipLines=true}
local function origin(node,graph,depth)
    if depth>8 or not tbl(graph) or not tbl(graph.nodes) or not tbl(graph.edges) then return end
    local id=str(node.id);if not id then return end
    local edge=G.Binding(graph,id,"record");if not edge then return end
    local upstream=graph.nodes[edge.from];if not tbl(upstream) then return end
    local kind=str(upstream.type);local base=kind and A.catalog[kind];if not base then return end
    local c=config(upstream,base)
    if kind=="unit_record" then
        if edge.output~="value" then return end
        local root,path,schema,token,options=origin(upstream,graph,depth+1)
        if not root then return end
        local projection=D.projections["record."..c.schema.."."..c.field]
        if not projection or (schema~=c.schema and not (schema=="tooltip" and c.schema=="tooltipLines")) then return end
        if schema=="tooltip" and c.schema=="tooltipLines" then path=path..".lines" end
        if indexed[c.schema] then path=path.."["..c.index.."]" end
        return root,path.."."..c.field,projection.nestedSchema,token,options
    end
    local meta=D.nodes[kind];local port=meta and meta.outputs[edge.output];local f=port and D.fields[port.fieldId]
    if f and not port.implementationOverride then return f,f.key,f.schema,unit(upstream,base,c),c end
end

local purposes={
 macro_exists="Check is optional: unconnected nodes observe saved macros on activation and macro changes without polling; connected nodes check only on fresh events. Exists retains the last boolean result. Startup establishes state without pulses; later automatic result changes emit Found, Missing or Failed. Explicit checks emit an event each time. Failed never means missing. This node does not write or execute macros.",
 play_sound="Play a local SoundKit or exact SharedMedia sound on a fresh event. Preview and Stop preview are in node details. Choose a game channel; SoundKits also support per-playback volume. Stop, Mute and graph retirement release this node's playback. Initial evaluation and Graph Test stay silent.",
 frame_state="Observe a saved shared Frame library reference. Found and Visible report readable current state; Shown and Hidden fire only on an observed visibility transition. Initial resolution, an unavailable frame or a replaced frame never invents a transition. References travel with graph exports, even when the recipient has not loaded the target window yet. Inspection and library management are available through /bv inspect and /bv frames.",
 memory_set="Store one readable typed value under a key in this graph's temporary memory. Chain Done into the next operation to define order. Memory is bounded, never saved, and cleared when the run stops. An optional Instance isolates a nameplate's values.",
 memory_get="Read a typed value from temporary graph memory. Found distinguishes a missing key from stored false, zero or empty text. A type mismatch never coerces the stored value. Chain Trigger after a writer when order matters.",
 memory_delete="Delete one key from temporary graph memory. Connect Done to order later operations. An optional Instance selects isolated nameplate memory.",
 memory_clear="Clear this graph's temporary memory, or only the connected Instance's memory. This does not change saved settings or other graphs.",
 format_values="Legacy formatter: retain existing graphs with 1..16 values, percentage/time formatting and conditional Visible output. New graphs use String Formatter and separate utility nodes.",
 string_formatter="Compose text from literals and numbered values. Supported secret numeric/text arguments stay opaque through Text Media to native display; this does not expose readable text. No arithmetic or visibility logic.",
 round="Round, floor or ceil a readable number at 0..6 decimal places. Number supports arithmetic; Text preserves trailing zeros. Secret operands remain unavailable.",
 time_format="Format readable seconds as m:ss. Use the separate Remaining estimate node when an explicitly estimated time is wanted.",
 last_unprotected_value="Hold a node-local last readable scalar only while the input is secret. Using cached value identifies old data; missing input, Reset, Mute and runtime teardown clear it.",
 unit="Read the selected unit's health, resources and state. Choose only the outputs you need.",
 unit_aura="Find a configured buff or debuff on the selected unit and read its available fields.",
 unit_cast="Read the selected unit's current cast or channel, native durations and fresh cast-success events.",
 nameplates="Read each current nameplate independently. Connect Instance to Display Stack to keep its media together.",
 nameplates_aura="Find the configured aura separately on each matching nameplate.",
 nameplates_cast="Read current casts, channels and fresh cast-success events separately for each matching nameplate.",
 display_stack="Compose one set of media per Instance. Arrange and sort the sets at their shared layout anchor.",
 player="Read health, resources and state from your character. Choose the outputs you need.",
 target="Read health, resources and state from your current target.",focus="Read health, resources and state from your focus.",
 target_target="Read values from your target's current target.",focus_target="Read values from your focus's current target.",
 pet="Read health, resources and state from your pet.",party_member="Read values from the selected party slot. The slot can change owners.",
 raid_member="Read values from the selected raid slot. The slot can change owners.",nameplate="Read values from the selected visible nameplate slot. A slot is not a permanent enemy identity.",
 hp="Read your current and maximum health. Use Player for additional resources and outputs.",
 player_state="Read your character's movement and rest state.",context="Check whether your character is in combat.",
 boolean="Provide a fixed true or false value.",number="Provide a fixed number.",chat="Show a local system message. BV prefix is optional; this node never sends to other players. Test output keeps its Test marker.",
 chat_receive="Trigger on a selected incoming chat channel. Text and sender support exact, contains or bounded GLOB matching (* for any sequence, ? for one character; backslash escapes). GLOB matches the whole text, is case-sensitive, and is not regex or Lua patterns. Own messages are ignored by default; unreadable text or unknown ownership is skipped. Only matching fresh messages emit a pulse. Separate from Combat Log and addon messaging.",
 chat_direct="Send a visible player chat message directly on a fresh trigger when this node is permitted. No confirmation, retry or deferred send. Native context and restrictions are rechecked. Submitted means the call returned without a detected error; delivery remains unconfirmed. Imports reset permission.",
 chat_send="Request a player chat message in the chosen channel. Each fresh trigger opens a short-lived review request; only clicking Send message submits it to the game. Tests never send. Requested does not mean delivered. Whisper requires a character name; Channel requires a stable channel name. Context and restrictions are checked again when sending. Requests expire after 15 seconds and are cancelled when their graph stops.",
 circle="Place media on a circle using an angle and radius.",compare="Compare readable numbers and produce a condition.",
 display="Show connected media at its configured layout anchor.",format="Build text from readable values using a format pattern.",
 gate="Emit events according to the selected mode, condition and timing.",
 icon="Display an icon at its configured layout anchor.",media_icon="Create icon media for a Display node.",
 media_text="Create text media for a Display node. Choose a bundled, game or registered SharedMedia font. An optional Font definition overrides local font settings; Style definition controls appearance.",media_bar="Create a bar from Value/Maximum, normally connected to Unit outputs. Background color, Border color and Border width also accept graph inputs. Style replaces local styling; individually wired styling inputs override Style. Missing registered textures keep their reference and use a fallback. Older player-health bars migrate to a Unit source; capacity-limited graphs retain their old health binding internally.",
 player_talent="Observe one configured talent node in the active player configuration. Active rank and Current rank have different meanings; pending edits can affect Current rank. Unknown or secret rank is never assumed zero. Node ID is not Spell ID; this is not a talent editor.",
 media_font="Define a reusable font family, size and outline. Connect Font to Text or Text overlay. Registered fonts use stable SharedMedia names; missing registrations keep the reference and use a fallback until available.",
 media_style="Define reusable foreground, background, border and opacity. Connect Style to Icon, Graphic, Text or Bar. Connected style overrides the corresponding local appearance; an unavailable connected style produces unavailable media.",
 multiply="Multiply a readable number by a factor.",offset="Move connected media by a horizontal and vertical offset.",
 opacity="Set the opacity of connected media.",rotate="Rotate connected graphic media.",rotate_offset="Rotate a position offset.",
 scale="Scale connected media.",size="Adjust the width and height of connected media.",tint="Apply a color to connected media.",
 unit_record="Select one known field from a unit record. Choose the matching schema and, for lists, an index.",
 secret="Pass a value through and check whether it is readable or secret.",is_nil="Check whether a readable value is missing. A secret value cannot be tested for nil.",
 constant_nil="Provide an explicit missing value.",logic_and="True when all readable conditions are true.",
 logic_or="True when at least one readable condition is true.",logic_not="Invert a readable condition.",
 logic_select="Choose between two values using a readable condition.",logic_branch="Route a value to one of two outputs using a readable condition.",
 animation_fade="Animate the opacity of connected media without changing its saved layout.",
 animation_float="Animate the position of connected media with a floating motion.",
 animation_pulse="Animate the scale of connected media with a pulsing motion.",
 animation_shake="Animate connected media with a shaking motion.",
 aura="Find a configured buff or debuff on your character and read its available fields.",
 bar_duration="Drive a bar with a native duration value, including supported secret durations.",
 icon_duration="Drive an icon cooldown overlay with a native duration value.",
 glow="Color and animate icon or text glows. Pixel and AutoCast outline the media rectangle; Soft, Outline, Neon and Shadow follow text glyphs. RGBA multipliers affect only the glow.",icon_border="Add a colored border to icon media.",
 icon_cooldown="Show the configured spell's native cooldown overlay on icon media.",
 interval="Emit repeating events while active, using the configured interval.",
 item_count="Count a configured item in carried inventory and equipment.",
 item_equipped="Check whether a configured item is equipped.",location="Read your current map, zone and location state.",
 media_event="Receive one physical click and its captured values from Click Action or legacy Clickable media with the same key in this graph. Configure payload outputs on the producer.",
 media_graphic="Create graphic media from a local addon image file.",
 media_interaction="Make media clickable and send captured values to matching Media event nodes. Optional Mouse feedback is off by default: hover brightens, pressing darkens and disabled media dims. This is visual feedback for this element only; it covers the full display rectangle, including transparent areas around text.",
 media_overlay="Add text over connected media.",
 message_receive="Receive matching addon data from your own BV Aura Studio graphs or permitted players. Does not read visible chat messages.",message_send="Send typed addon data to your own BV Aura Studio graphs or permitted players. Does not post visible chat messages.",
 player_cast="Emit an event when your character successfully casts a spell.",
 player_swing="Emit a swing-timer event for your character. This does not confirm a hit or damage.",
 remaining_estimate="Estimate a countdown from the last readable remaining-time value. It does not reveal secret data.",
 spell_cooldown="Read the available cooldown state of a configured spell.",
 spell_proc="Read whether a configured spell has an active proc glow.",
 spell_charges="Read the configured spell's available charges and recharge timing. A spell without charges has unavailable values, not zero charges.",
 spell_usable="Read whether the configured spell is usable and whether it lacks power. This does not guarantee a valid target, range or a successful cast.",
 spell_known="Check whether your character knows the configured spell, including temporarily granted spells. This is not a talent-tree selection check.",
 player_xp="Read your character's current experience, level and rested XP. Missing rested XP is not zero; XP disabled and level cap are separate states.",
 player_money="Read the money carried by your character, in copper. This is not a bank or account-wide balance.",
 currency="Read one currency by its exact Currency ID. An unknown currency is not a zero balance; a maximum of zero means no reported cap.",
 reputation="Read a faction by ID, or use Faction ID 0 for your watched faction. Progress follows the identified reputation system; a pending Paragon reward is separate.",
 totem="Read the totem or temporary summon in one player slot (1 to 4). An empty slot is different from unavailable information.",
 text_outline="Add an outline to text media.",text_shadow="Add a shadow to text media.",
 timer="Count from Start to Target while active and emit an event when the target is reached.",
}
local titles={logic_and="AND",logic_or="OR",logic_branch="Branch"}
local dataMeanings={
 player_xp={current="Experience earned toward the next level.",maximum="Experience required for the next level.",level="Current character level.",rested="Rested experience reported by the client. Missing is not zero.",disabled="Whether the client reports XP gain disabled. This does not imply a level cap.",capped="Whether the native player-level-cap check reports capped. Not inferred from XP or maximum."},
 player_money={copper="Carried character money in copper. 10,000 copper equal one gold."},
 currency={name="Name of this exact currency.",quantity="Amount currently owned.",maxQuantity="Reported maximum quantity. Zero means no reported cap, not a usable bar maximum.",icon="Currency texture file ID for an icon input; not assembled media.",discovered="Whether the client reports this currency as discovered. An unknown record is not false."},
 reputation={factionID="Resolved faction ID. Configuration 0 follows the watched faction.",name="Faction name.",reaction="Native reputation reaction rank, when available.",currentStanding="Raw standard faction standing. Use Current progress for system-specific bar progress.",currentReactionThreshold="Raw standard faction lower threshold; special reputation systems use their own progress fields.",nextReactionThreshold="Raw standard faction next threshold. Missing or equal thresholds do not provide a usable range.",kind="Reputation system: STANDARD, FRIENDSHIP, RENOWN, PARAGON, HEADER or UNKNOWN.",current="System progress: readable standard/friendship rank delta, native earned renown, or a readable Paragon cycle remainder.",maximum="Reported or derived requirement. Zero is not a usable bar maximum; native renown/paragon thresholds may remain opaque. Missing cap thresholds never become 1/1.",rewardPending="Native Paragon reward-pending flag. A pending reward does not turn the current cycle into a full bar."},
 spell_charges={currentCharges="Currently available charges.",maxCharges="Maximum charge count.",active="Whether a recharge is currently active.",startTime="Readable recharge start in game uptime seconds.",duration="Readable recharge duration in seconds.",modRate="Native recharge rate modifier.",durationObject="Native recharge duration. Connect to a duration-aware media node; do not format it as a number."},
 spell_usable={usable="Native spell usability result; not proof of range, target validity or successful execution.",insufficientPower="Whether the native usability check reports insufficient power."},
 spell_known={known="Whether the player knows this spell ID, including temporarily granted spells. Does not inspect talent choices or ranks."},
 totem={present="Whether this player slot currently has a totem or temporary summon.",name="Name of the summon in this slot.",startTime="Readable summon start in game uptime seconds.",duration="Readable summon duration in seconds.",icon="Texture file ID; not an assembled media value.",modRate="Native duration rate modifier.",spellID="Summoning spell ID when supplied by the client.",durationObject="Native summon duration for duration-aware media. Unavailable if the client does not provide it."},
}
local meanings={
 classIcon="Blizzard class icon media. Connect directly to Display or a Display Stack element.",
 roleIcon="Blizzard icon for an assigned Tank, Healer or Damage role. No icon for NONE; arbitrary NPC roles are not inferred.",
 classColor="Class color as RRGGBB hex for color inputs on Glow, outline, shadow or border effects.",
 classRed="Red class-color component (0..1). Connect to Color's red input.",
 classGreen="Green class-color component (0..1). Connect to Color's green input.",
 classBlue="Blue class-color component (0..1). Connect to Color's blue input.",
 instance="Temporary unit binding. Connect to Display Stack; a reused nameplate slot gets a new instance.",
 health="Current health.",healthMax="Maximum health.",healthPercent="Current health as a percentage.",
 power="Current primary resource; follows the unit's resource type.",powerMax="Maximum primary resource.",
 powerType="Numeric primary resource type.",powerToken="Primary resource name.",exists="Whether the selected unit currently exists.",
 mana="Current mana, independent of the active resource.",manaMax="Maximum mana.",energy="Current energy.",energyMax="Maximum energy.",
 rage="Current rage.",rageMax="Maximum rage.",focus="Current focus resource.",focusMax="Maximum focus resource.",
 comboPoints="Current combo points.",comboPointsMax="Maximum combo points.",runicPower="Current runic power.",runicPowerMax="Maximum runic power.",
 resting="Whether the player is in a resting area; not remaining rested XP.",mounted="Whether the player is mounted; a taxi flight is a separate state.",
 moving="Whether the player is moving; not a world-position distance.",combat="Whether the unit is in combat.",
 name="Unit name.",realm="Unit realm.",guid="Unit identifier; slot bindings can change.",
 buffs="List of helpful auras. Use Unit record field to select an entry.",debuffs="List of harmful auras. Use Unit record field to select an entry.",
 tooltip="Structured unit tooltip. Individual fields may have different restrictions.",
 nameplateGeometry="On-screen nameplate rectangle; not world coordinates.",unitGeometry="On-screen unit rectangle; not world coordinates.",
 reaction="Reaction towards another unit; not a faction identifier.",factionGroup="Faction affiliation; not hostility towards you.",
}
local function meaning(field,port,key)
    if field then
        if meanings[field.key] then return meanings[field.key] end
        if field.schema then return "Structured "..field.schema.." value. Select fields with Unit record field." end
        local label=(field.label or key):gsub(" / ",": ")
        return label.." ("..field.type..")."
    end
    return (port.label or key).." ("..port.type..")."
end
local overviewColumns={{key="output",label="Output",width=.20},{key="meaning",label="Meaning",width=.32},{key="availability",label="Availability",width=.24},{key="secret",label="Secret behavior",width=.24}}
local detailColumns={{key="situation",label="Situation",width=.24},{key="availability",label="Availability",width=.22},{key="secret",label="Secret behavior",width=.24},{key="usage",label="Usage",width=.30}}
local function tableOf(page,title,columns,rows,empty)
    page.tables[#page.tables+1]={title=title,columns=G.Copy(columns),rows=rows,emptyText=empty or "No outputs selected. Choose an output in the node settings."}
end
local function readableUsage(kind)
    if kind=="unitref"then return "Connect directly to Display Stack's Instance input. Do not inspect or store the binding."end
    if kind=="integer" or kind=="float" then return "Use for calculations and comparisons while readable." end
    if kind=="boolean" then return "Use as a true/false condition while readable." end
    if kind=="string" then return "Use as text or compare with another readable string." end
    if kind=="data" then return "Select a known field with Unit record field. Check each field's restrictions." end
    if kind=="duration" then return "Connect to Bar duration or Icon duration." end
    if kind=="action" then return "Connect an Action node to Action Display alongside separate Media. This definition never executes by itself." end
    if kind=="calculator" then return "Select a supported field with Unit record field." end
    if kind=="event" then return "Connect to a compatible event input." end
    return "Connect to an input with the matching type."
end
local function describe(flags,kind)
    if not flags then return "Not yet verified","Not yet verified","Check availability before using this value." end
    local present=flags.readable or flags.protected or flags.opaque
    local missing=flags.unavailable or flags.unconfigured or flags.unsupported or flags.error
    local availability=present and (missing and "Context-dependent" or "Available in this context") or
        (flags.unconfigured and "Requires configuration" or flags.unsupported and "Not supported" or flags.unavailable and "Not available" or "Not yet verified")
    if flags.protected then
        return availability,flags.readable and "May be secret" or "Treat as secret","Use a compatible display input. No Lua math or comparisons while secret."
    elseif flags.opaque then
        return availability,"Restricted object","Use a compatible record or duration node. Check individual fields."
    elseif flags.readable then
        return availability,"Readable in this context",readableUsage(kind)
    end
    return availability,"Not yet verified","Do not treat a missing value as zero or false."
end
local function availability(token,f,path,c)
    if not token or not compatible(D.queries[f.queryId],c) then return end
    return D.availability[token..":"..f.queryId..":"..path]
end
local function combined(contexts)
    if not contexts then return end
    local flags={};for _,row in pairs(contexts) do for status in pairs(row) do flags[status]=true end end
    return flags
end
local function source(node,base,c,key,graph)
    local meta=D.nodes[node.type];local ref=meta and meta.outputs[key]
    if ref and ref.implementationOverride then return nil,nil,nil,nil,ref.implementationOverride end
    if base.auraSource then return nil,nil,nil,nil,{kind="aura-observation"}end
    local f=ref and ref.fieldId and D.fields[ref.fieldId]
    if not f and base.unitSource then f=D.fields["unit."..key]end
    if f then return f,f.key,unit(node,base,c),c end
    if node.type=="unit_record" and key=="value" then
        local projection=D.projections["record."..c.schema.."."..c.field]
        if not projection or c.index<1 or c.index>40 or c.index~=math.floor(c.index) then return end
        local root,path,schema,token,options=origin(node,graph,1)
        if root and (schema==c.schema or (schema=="tooltip" and c.schema=="tooltipLines")) then
            if schema=="tooltip" and c.schema=="tooltipLines" then path=path..".lines" end
            if indexed[c.schema] then path=path.."["..c.index.."]" end
            return root,path.."."..c.field,token,options
        end
    end
end
local function localStatus(kind,key,def,override)
    if key=="realTime" and def.auraSource then
        return "While current native aura timing is available","Opaque native timer",
            "Connect Real Time directly to Display Real Time together with Icon media or Bar media. Native timers can carry Secret timing without Lua arithmetic. Target changes rebind to the current aura; unavailable timing clears the display. CDM fallback follows the configured spell family. This is not a numeric estimate."
    end
    if (key=="durationEstimate" or key=="remainingEstimate") and (def.auraSource or kind=="aura") then
        return "With a readable value or a previous readable baseline","Explicit estimate while timing is Secret",
            key=="durationEstimate" and "Passes readable Duration through; while Duration is Secret, holds its last readable value. Hidden changes can make it inaccurate. Missing data, confirmed absence and binding/aura identity changes clear history. Native Duration is unchanged."
            or "When Present Estimate is false, outputs no value (nil), stops the countdown and discards the remaining baseline. Otherwise passes readable Remaining through; while timing is Secret, counts down from the last readable Remaining or expiration. After a stop, requires a new readable timing observation. Zero or elapsed remaining time outputs no value (nil) and stops the clock. Hidden refreshes can make it inaccurate; elapsed time is not proof of absence. Missing data, confirmed absence, permanent auras and binding/aura identity changes clear history. No baseline means no estimate. Native Remaining is unchanged."
    end
    if key=="presentEstimate" and (def.auraSource or kind=="aura") then
        return "With readable or Secret Present","Secret Present uses a public CDM hint or false","Readable Present passes through. Secret player HELPFUL Present can use public activity of its canonical CDM self-aura family; linked-only IDs, conflicting overrides or other units do not qualify. This does not certify an exact hidden aura rank. Without a qualifying hint the estimate is false; false is not proof of absence. Missing, unavailable and faulted Present stay unavailable. The original Present output is unchanged."
    end
    local playerField=def.unitSource and A.UnitSource.playerFields[key]
    if playerField then kind,key=playerField.kind,playerField.field end
    if def.unitSource and A.UnitSource.presentationFields[key] then return "When the class / assigned role is readable","No conversion from secret values","Built-in Blizzard artwork and colors; absent APIs or unassigned roles stay unavailable. Native acceptance remains context-dependent." end
    if kind=="media_event" then
        if key=="event" then return "Once per matching click","Readable event pulse","Receives ordinary and stack clicks; removed or recycled source bindings are rejected." end
        if key:match("^value%d+$") then return "With the matching click","Preserves payload restrictions","Captured from the clicked element. Secret values may only reach compatible consumers; System message requires readable text." end
    end
    if def.sourceFamily=="cast" and key=="castSucceeded"then return "On a fresh matching unit event","Readable event pulse","A successful cast event is not proof of a hit, damage or aura application."end
    if def.sourceFamily=="cast" and key=="succeededSpellID"then return "With a matching success event","May be secret or missing","Use only when available. A secret Spell ID cannot satisfy a readable ID comparison."end
    if key=="instance" and (def.unitSource or def.auraSource)then return "While this unit binding exists","Opaque binding","Connect directly to Display Stack's Instance input. Slot reuse creates a new instance."end
    if override then
        if override.kind=="aura-observation"then
            if key=="present"then return "When identity and filter are accessible","Requires readable identity","Unknown or blocked aura access is not proof of absence."end
            if key=="remaining" or key=="hasExpiration"then return "With readable expiration","Requires readable timing","Secret expiration never reconstructs a countdown."end
            return "When this aura field is available","May be secret","Use a compatible display input while secret. Missing is not zero."
        end
        if override.kind=="derived-readable-only" then return "Readable health + maximum > 0","Requires readable inputs","Not produced from secret health values." end
        return "Player state","Readable","Use as a Boolean condition."
    end
    if kind=="number" or kind=="boolean" then return "While active","Readable",readableUsage(kind=="number" and "float" or "boolean") end
    if kind=="secret" and (key=="isSecret" or key=="available") then return "When input status is known","Readable condition","Use as a true/false condition." end
    if kind=="unit_record" and (key=="available" or key=="status") then return "When the record is evaluated","Readable",key=="available" and "Check whether the selected field is readable." or "Read the selected field's availability status." end
    if kind=="constant_nil" then return "No value","Not applicable","Connected nil does not use a local default." end
    if kind=="is_nil" then return "When the input is readable","Secret input blocks the result","A secret value cannot be tested for nil." end
    if def.logic=="select" or def.logic=="branch" then return "When the selected input is available","Preserves selected value","The selection condition must be readable." end
    if kind=="media_interaction" and key=="media" then
        return "Live displayed media with a graph click handler","Local visual feedback does not inspect payloads","Mouse feedback covers the full display rectangle, including transparent areas around text. It is optional and local to this element. It adds no graph events, outputs or timers and performs no protected actions. Disabled media stays click-through. Layout preview and Test do not receive live interactions."
    end
    if kind=="player_xp" or kind=="player_money" or kind=="currency" or kind=="reputation" then
        local usage="Missing information is not zero or false. Use calculations only while readable."
        if kind=="player_xp" and (key=="current" or key=="maximum") then usage="Connect Current XP to Bar media Value and Required XP to Maximum. Check that Maximum is positive."
        elseif kind=="player_xp" and key=="rested" then usage="Use a readable rested value for text or calculations; an unavailable value is not zero."
        elseif kind=="player_xp" and key=="disabled" then usage="Use as a condition while readable. Disabled XP and a reached level cap are independent."
        elseif kind=="player_xp" and key=="capped" then usage="Use the native level-cap result while available. Do not infer it from an XP value or maximum."
        elseif kind=="player_money" then usage="Use readable copper for text or calculations: divide by 10,000 for gold. No automatic denomination formatting."
        elseif kind=="currency" and key=="maxQuantity" then usage="Use as Bar media Maximum only when readable and greater than zero. Zero means no reported cap."
        elseif kind=="currency" and key=="quantity" then usage="Use as Bar media Value with a readable positive Maximum quantity. Missing currency data is not a zero balance."
        elseif kind=="currency" and key=="icon" then usage="Connect this texture ID to Icon media Texture ID."
        elseif kind=="reputation" and (key=="current" or key=="maximum") then
            local secret=key=="current" and "Native RENOWN may be opaque; derived progress requires readable inputs" or "Native RENOWN/PARAGON may be opaque; derived ranges require readable inputs"
            local usage=key=="current" and "Connect to Bar media Value. STANDARD/FRIENDSHIP rank deltas and PARAGON remainder need readable operands; native RENOWN earned progress can pass through while secret."
                or "Connect to Bar media Maximum. STANDARD/FRIENDSHIP ranges need readable thresholds; native RENOWN/PARAGON thresholds can pass through while secret. Readable zero is not a usable maximum; missing cap thresholds do not become 1/1."
            return "Identified system with available progression fields",secret,usage
        elseif kind=="reputation" and key=="rewardPending" then usage="Use the native Paragon reward flag as a separate indicator. Pending rewards do not change current cycle progress."
        elseif kind=="reputation" and key=="kind" then usage="Check the reputation system before using raw thresholds. UNKNOWN must not be treated as STANDARD."
        elseif kind=="reputation" and (key=="currentStanding" or key=="currentReactionThreshold" or key=="nextReactionThreshold") then usage="Raw native value only. Prefer Current progress and Rank requirement for a normal reputation bar; special systems use separate progression fields."
        end
        return "On relevant events; requires client support","Secret values stay opaque",usage
    end
    if dataMeanings[kind] then
        return "On relevant events; requires client support",key=="durationObject" and "Opaque native duration" or "Secret values stay opaque",key=="durationObject" and "Connect to Bar duration or Icon duration. No Lua time arithmetic." or "Missing information is not zero or false."
    end
    if def.secretInputs or kind=="secret" then return "When required inputs are available","Depends on the input","Use a compatible display or transport input." end
    if def.source then return "Depends on node conditions","Not yet verified","Choose an output for details." end
    return "When required inputs are available","Requires readable inputs","Unavailable inputs do not become zero or false."
end
local function rowFor(node,base,def,c,key,port,graph)
    local f,path,token,options,override=source(node,base,c,key,graph)
    local a,s
    if f then
        local contexts=availability(token,f,path,options)
        a,s=describe(combined(contexts))
        if a=="Available in this context" and contexts then
            if contexts.peace and contexts.combat then a="In / out of combat"
            elseif contexts.peace then a="Out of combat"
            elseif contexts.combat then a="In combat" end
        end
    else a,s=localStatus(node.type,key,def,override) end
    local text=meaning(f,port,key)
    if dataMeanings[node.type] then text=dataMeanings[node.type][key] or text end
    if base.interactionProducer and key=="media"then text="Clickable media with optional local mouse-state feedback. Named payload values still come from the latest rendered element."end
    if key=="instance"then text=meanings.instance end
    if base.sourceFamily=="cast" and key=="castSucceeded"then text="Fresh successful-cast event for this unit binding."end
    if base.sourceFamily=="cast" and key=="succeededSpellID"then text="Spell identifier supplied by the matching successful-cast event."end
    if base.auraSource then
        local descriptions={present="Whether the configured aura was identified on this unit.",stacks="Current aura stack count.",duration="Total aura duration in seconds.",remaining="Seconds until a readable expiration time.",hasExpiration="Whether the readable aura expiration is nonzero.",texture="Aura texture identifier.",icon="Icon media for the configured aura."}
        text=descriptions[key] or text
    end
    if node.type=="unit_record" and key=="value" then
        text=c.schema.." / "..c.field.." (index "..c.index..")."
        if not f then a,s="Source not resolved","Not yet verified" end
    elseif node.type=="hp" then text=key=="current" and meanings.health or key=="maximum" and meanings.healthMax or "Health percentage, calculated from readable health values." end
    return {output=port.label or key,meaning=text,availability=a,secret=s}
end
local function fieldRows(node,f,path,token,c,outputType)
    local rows={};local contexts=availability(token,f,path,c)
    for _,context in ipairs({{"peace","Out of combat"},{"combat","In combat"}}) do
        local a,s,u=describe(contexts and contexts[context[1]],outputType)
        rows[#rows+1]={situation=context[2],availability=a,secret=s,usage=u}
    end
    rows[#rows+1]={situation="No unit at this slot",availability="Not available",secret="Not applicable",usage="Existing media is cleared. Missing is not zero."}
    rows[#rows+1]={situation="Other encounters",availability="Not yet verified",secret="May vary",usage="Check readability before calculations or comparisons."}
    return rows
end
function W.Page(node,topic,graph)
    local kind=tbl(node) and str(node.type);local base=kind and A.catalog[kind]
    local page={title="Node wiki",subtitle="",selectedTopic="overview",topics={{value="overview",label="Overview"}},tables={}}
    if not base then page.subtitle="This node type is not available in the current catalog.";return page end
    local c=config(node,base);local n={type=kind,config=c,id=str(node.id)}
    local definition=G.Definition(base,n) or base
    page.title=(titles[kind] or base.label or kind).." - Wiki"
    page.subtitle=purposes[kind] or ((base.help or "Connect this node's inputs and outputs to build your graph."):match("^(.-%.)%s") or base.help)
    local ports={}
    for _,spec in ipairs({{"out:","Output: ",base.selectableOutputs or definition.outputs or {}},{"in:","Input: ",G.Ports(definition)}}) do
        for _,key in ipairs(G.Ordered(spec[3])) do
            local p=spec[3][key];local id=spec[1]..key
            page.topics[#page.topics+1]={value=id,label=spec[2]..(p.label or key)};ports[id]={port=p,key=key,output=spec[1]=="out:"}
        end
    end
    topic=str(topic);if topic=="overview" or ports[topic] then page.selectedTopic=topic end
    local selected=ports[page.selectedTopic]
    if not selected then
        local rows={};for _,key in ipairs(G.Ordered(definition.outputs)) do rows[#rows+1]=rowFor(n,base,definition,c,key,definition.outputs[key],graph) end
        if #rows>0 or base.selectableOutputs then tableOf(page,"Outputs",overviewColumns,rows)
        else
            local inputs={};for _,key in ipairs(G.Ordered(G.Ports(definition))) do
                local p=G.Ports(definition)[key];inputs[#inputs+1]={output=p.label or key,meaning=p.type,availability=p.required==false and "Optional" or "When connected or configured",secret="Choose an input for details"}
                if base.displayStack then
                    local row=inputs[#inputs]
                    row.meaning=key=="instance" and "Unit binding that owns this media set." or key=="sort" and "Value used by the layout anchor's selected sort mode." or key=="visible" and "Show or hide this instance's media set." or key=="mute" and "Suppress this node." or "Media element in this instance's composition."
                    row.secret=key=="instance" and "Opaque binding" or key=="sort" and "Secret values keep appearance order" or key=="visible" and "Requires a readable condition" or key=="mute" and "Requires a readable condition" or "Supported media transports secret fields"
                end
            end
            local cols=G.Copy(overviewColumns);cols[1].label="Input";tableOf(page,"Inputs",cols,inputs,"This node has no inputs or outputs.")
        end
        if base.unitKind or kind=="player" or kind=="hp" then page.notice="Availability can change with the unit and encounter. Select an output for combat conditions and usage." end
        if base.collectionSource then page.notice="Slot observations are combined. Friendly/Hostile-specific availability is not verified."end
        if base.displayStack then page.notice="Choose the root element and element layouts in Details. Direction, spacing and sorting belong to the neutral layout anchor."end
    elseif selected.output then
        local key,p=selected.key,selected.port
        local f,path,token,options,override=source(n,base,c,key,graph)
        page.subtitle=rowFor(n,base,definition,c,key,p,graph).meaning
        if f then
            tableOf(page,p.label or key,detailColumns,fieldRows(n,f,path,token,options,p.type))
            page.notice=base.collectionSource and "Slot observations are combined. Friendly/Hostile-specific availability is not verified." or "Combat refers to your character. Readability can differ for other units and encounters."
        else
            local a,s,u=localStatus(kind,key,definition,override)
            if kind=="unit_record" and key=="value" then a,s,u="Not yet verified","Not yet verified","Connect a compatible record source to get field-specific guidance." end
            tableOf(page,p.label or key,detailColumns,{{situation="Normal use",availability=a,secret=s,usage=u}})
        end
    else
        local key,p=selected.key,selected.port;page.subtitle=(p.label or key).." input ("..p.type..")."
        local transport=definition.secretInputs and definition.secretInputs[key]
        transport=transport or (definition.logic=="select" and (key=="yes" or key=="no")) or (definition.logic=="branch" and key=="value")
        local rows={{situation="Readable input",availability="Supported",secret="Readable",usage="Use a value matching the input type."},
            {situation="Secret input",availability=transport and "Supported transport" or "Not supported",secret=transport and "Preserved" or "Cannot be evaluated",usage=transport and "Pass to a compatible display. No Lua math or comparisons." or "Use readable inputs for this operation."}}
        for _,input in pairs(definition.bypass or {}) do if input==key then rows[#rows+1]={situation="Bypass enabled",availability="Pass-through",secret="Preserved",usage="The bypass switch itself must be readable."};break end end
        if kind=="is_nil" then rows[2].usage="Secret values cannot be tested for nil." end
        if base.interactionProducer and key=="enabled"then
            rows={{situation="Enabled with Mouse feedback on",availability="Live interactive display",secret="Readable flag required",usage="The element brightens on hover and darkens while pressed. Feedback adds no graph events or protected actions."},
                {situation="Disabled",availability="Click-through",secret="Readable flag required",usage="No click is sent. Mouse feedback can dim the live element without intercepting the pointer."},
                {situation="Layout preview or Test",availability="No live interaction",secret="No payload inspection",usage="Feedback does not turn previews into live graph controls."}}
        elseif base.displayStack and key=="instance"then
            rows={{situation="Unit source binding",availability="Required connection",secret="Opaque binding",usage="Connect the Instance output from Unit or Nameplates. Each binding owns one media set."},
                {situation="Unit removed or slot reused",availability="Old instance removed",secret="No identity inspection",usage="The old media set clears. A new binding creates independent state."}}
        elseif base.displayStack and key=="sort"then
            rows={{situation="Readable number or text",availability="Optional",secret="Readable",usage="The neutral anchor chooses numeric, alphabetical or appearance order."},
                {situation="Secret or missing sort value",availability="Appearance fallback",secret="Never compared",usage="Stable appearance order keeps the list usable without inspecting the value."}}
        elseif base.displayStack and p.type=="media"then
            rows={{situation="Connected media",availability="Optional",secret="Supported fields preserved",usage="Place this element relative to the selected root element in the Layout Editor."},
                {situation="No media",availability="Element hidden",secret="Not applicable",usage="Other elements keep their stable input IDs and their own media."}}
        end
        tableOf(page,p.label or key,detailColumns,rows)
    end
    return page
end

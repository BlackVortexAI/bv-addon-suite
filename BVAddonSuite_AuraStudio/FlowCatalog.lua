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
-- Visible name "Dictionary" (in-game round 4); the internal id "array" and
-- type "array:<type>" stay for saved graphs, exports and sharing.
local base={label="Dictionary",flowOperation="array",inputs={},outputs={},defaults={valueType="string",operation="extract",by="key",sort="insertion",descending=false,count=3},
    help="Dictionary: a typed collection of key/value entries (text keys), up to 64 entries, that keeps the insertion order. Look entries up by key or by position (starting at 1). Edits return an independent dictionary. Set replaces a key, Add rejects duplicate keys. Missing timestamps sort last; ties keep their order. Dictionaries only live during one evaluation and cannot be stored in Memory."}
base.resolve=function(c)
    if not A.FlowValues.types[c.valueType] or not ({initialize=true,extract=true,set=true,add=true,remove=true,clear=true,count=true,contains=true,sort=true,snapshot=true})[c.operation]
        or not ({key=true,index=true})[c.by] or not ({insertion=true,key=true,value=true,timestamp=true})[c.sort]
        or type(c.descending)~="boolean" or not G.Number(c.count) or c.count<1 or c.count>64 or c.count%1~=0 then return nil,"Invalid dictionary configuration" end
    local d=G.Copy(base);d.resolve=nil
    d.fields={{key="operation",label="Operation",choices={"initialize","extract","set","add","remove","clear","count","contains","sort"}},{key="valueType",label="Value type",choices=types}}
    local kind="array:"..c.valueType
    d.outputs={array=port(kind,"Dictionary",nil,1),count=port("integer","Count",nil,2)}
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
        d.inputs.array={type=kind,label="Dictionary",wire=true,required=true,order=1}
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
do
    local units={"player","target","target_target","focus","focus_target","pet","party_member","raid_member","mouseover"}
    local labels={player="Player",target="Target",target_target="Target of Target",focus="Focus",focus_target="Target of Focus",pet="Pet",party_member="Party",raid_member="Raid",mouseover="Mouseover"}
    local range={label="Unit Range",flowOperation="unit_range",source=true,rangeSource=true,inputs={},outputs={},
        defaults={unit="target",slot=1,spellID=0},
        help="Distance to one unit, refreshed about four times per second while the graph runs. Exact only for group members in the open world; otherwise Min/Max form a bracket from item, interaction and spell range checks (Max empty = beyond the largest check). In combat, item and interaction checks only work on units you can attack. Spell (optional) adds In spell range for that spell. Status: exact, estimated, unknown or protected. Unknown and protected never mean out of range: the outputs stay empty. Party/Raid observe one roster slot."}
    range.resolve=function(c)
        if not labels[c.unit] then return nil,"Choose a supported unit" end
        local slotted=c.unit=="party_member" or c.unit=="raid_member"
        local max=c.unit=="party_member" and 4 or 40
        if slotted and (not G.Number(c.slot) or c.slot~=math.floor(c.slot) or c.slot<1 or c.slot>max) then return nil,"Roster slot must be 1.."..max end
        if not G.Number(c.spellID) or c.spellID<0 or c.spellID~=math.floor(c.spellID) then return nil,"Spell must be a spell ID or 0" end
        local d=G.Copy(range);d.resolve=nil
        d.fields={{key="unit",label="Unit",choices=units,choiceLabels=labels,primary=true}}
        if slotted then d.fields[#d.fields+1]={key="slot",label=c.unit=="party_member" and "Party slot (1–4)" or "Raid slot (1–40)",type="integer"} end
        d.fields[#d.fields+1]={key="spellID",label="Spell (0 = none)",type="integer",picker="aura"}
        d.outputs={min=port("float","Min (yards)",nil,1),max=port("float","Max (yards)",nil,2),status=port("string","Status",nil,4)}
        if c.spellID>0 then d.outputs.inSpell=port("boolean","In spell range",nil,3) end
        return d
    end
    add("unit_range",range)
end
-- Annotation only: no ports, never active, never executed.
-- Revision 2 (0.8.58): draggable width (config.width, default 260).
add("markdown_note",{label="Markdown Note",annotation=true,category="notes",inputs={},outputs={},revision=2,
    defaults={text="## Note\n\nDescribe what this part of the graph does.",width=260},fields={},
    validate=function(c)
        if type(c.text)~="string" or #c.text>4000 then return false,"Note text must be at most 4000 bytes" end
        if c.width~=nil and (type(c.width)~="number" or c.width~=c.width or c.width<200 or c.width>800) then return false,"Note width must be 200..800" end
        return true
    end,
    help="A description on the canvas. Line breaks and empty lines show as typed. Write Markdown in Edit: # headings, **bold**, *italic*, `code`, - lists, 1. lists, > quotes, ``` code blocks and --- rules; links show as coloured text. The note has no ports and never affects execution. It is saved and exported with the graph. Up to 4000 bytes. Drag the grip at the bottom right to change the width (200-800)."})
local function secretPort(kind,label,default,order) local p=port(kind,label,default,order);p.maySecret=true;return p end
add("text_compare",{label="Text Compare",flowOperation="text_compare",category="logic",secretInputs={value=true,other=true},
    inputs={value=secretPort("string","Text","",1),other=secretPort("string","Compare with","",2)},outputs={result=port("boolean","Condition",nil,1)},
    defaults={operation="equals",ignoreCase=false},
    fields={{key="operation",label="Operation",choices={"equals","not_equals","contains","starts_with","ends_with"},choiceLabels={equals="Equals",not_equals="Not equals",contains="Contains",starts_with="Starts with",ends_with="Ends with"},primary=true},
        {key="ignoreCase",label="Ignore case",type="boolean"}},
    validate=function(c)
        if not ({equals=true,not_equals=true,contains=true,starts_with=true,ends_with=true})[c.operation] or type(c.ignoreCase)~="boolean" then return false,"Choose a text operation" end
        return true
    end,
    help="Compare two texts literally, like string functions in programming languages: Equals, Not equals, Contains, Starts with, Ends with. No wildcards or patterns; use Regex for patterns. Ignore case folds A-Z and accented Latin capitals such as Ä, Ö, Ü, É. An empty Compare with text is contained in, starts and ends every text. Protected or missing text gives no Condition (unknown), never false. Texts longer than 4096 bytes are not compared."})
do
    local regex={label="Regex",flowOperation="regex",category="math",inputs={},outputs={},
        defaults={operation="test",pattern="\\d+",ignoreCase=false,replacement="",replaceAll=true},
        help="Regular expressions with a bounded engine (no backtracking, like RE2): literals, . [abc] [^a-z] \\d \\w \\s (and \\D \\W \\S), \\b, ^ $, groups ( ) and (?: ), alternation |, * + ? {n} {n,} {n,m} and lazy *? +? ??. Not supported: backreferences and lookaround. Test gives Matched. Match gives the first match and Groups 1-5 (empty text when a group did not take part). Replace substitutes the first or every match; the replacement inserts $0-$9 for groups and $$ for a dollar sign. Ignore case folds A-Z and accented Latin capitals. Pattern up to 256 bytes, text up to 1024 characters and a fixed step budget; exceeding a limit or protected text gives no result (unknown), never a false match. An invalid pattern is reported on the node."}
    regex.resolve=function(c)
        if not ({test=true,match=true,replace=true})[c.operation] or type(c.ignoreCase)~="boolean" or type(c.replaceAll)~="boolean" or type(c.replacement)~="string" then return nil,"Choose a regex operation" end
        if #c.replacement>256 then return nil,"Replacement must be at most 256 bytes" end
        local ok,why=A.Regex.Compile(c.pattern,c.ignoreCase);if not ok then return nil,"Pattern: "..tostring(why) end
        local d=G.Copy(regex);d.resolve=nil
        local text=port("string","Text","",1);text.maySecret=true
        d.inputs={text=text};d.secretInputs={text=true}
        d.fields={{key="operation",label="Operation",choices={"test","match","replace"},choiceLabels={test="Test",match="Match",replace="Replace"},primary=true},
            {key="pattern",label="Pattern",type="string"},{key="ignoreCase",label="Ignore case",type="boolean"}}
        if c.operation=="test" then d.outputs={matched=port("boolean","Matched",nil,1)}
        elseif c.operation=="match" then
            d.outputs={matched=port("boolean","Matched",nil,1),match=port("string","Match",nil,2)}
            for i=1,5 do d.outputs["group"..i]=port("string","Group "..i,nil,2+i) end
        else
            d.fields[#d.fields+1]={key="replacement",label="Replace with",type="string"}
            d.fields[#d.fields+1]={key="replaceAll",label="Replace all",type="boolean"}
            d.outputs={result=port("string","Result",nil,1),count=port("integer","Replacements",nil,2)}
        end
        return d
    end
    add("regex",regex)
end
do
    -- Revision 2 (0.8.54): icon, sound and click-dismiss, filled from defaults.
    -- Revision 3 (0.8.59): symbol position and size.
    local toast={label="Toast Note",flowOperation="toast",sink=true,inputs={},outputs={},revision=3,
        defaults={position="top",opacity=.9,duration=5,fade=true,fadeDuration=.4,dismissible=false,icon="",source="none",soundKit=8959,sound="lsm:None",channel="Master",volume=100,symbolPosition="left",symbolScale=1},
        help="Show a timed note on a fresh Show event. Position picks one of four screen corners or four edges; it is independent of the Layout Editor. Opacity sets the full-visibility alpha, Show for the time at full opacity. Fade in / out adds Fade time before and after. Icon shows the chosen icon or a wired Texture ID on the left. Sound plays once per note (Game SoundKit or SharedMedia, same as Play Sound; silent in Test Mode). Notes at the same position stack, newest at the screen edge, at most five. Notes are click-through unless Click to dismiss is on; a dismissible note blocks clicks beneath it. Closed fires when a note expires, is clicked away or is dropped by the stack limit; Dismissed tells whether it was clicked away. Stopping or disabling the graph removes its notes without Closed. Notes also appear in combat and Test Mode."}
    toast.resolve=function(c)
        local ok,why=A.Toasts.Valid(c);if not ok then return nil,why end
        if type(c.icon)~="string" or (c.icon~="" and not BVAddonSuiteCore.IconCatalog:Reference(c.icon)) then return nil,"Choose a valid icon or none" end
        if c.source~="none" and not BVAddonSuiteCore.Sound.Valid(c) then return nil,"Choose a valid sound, channel and volume" end
        local d=G.Copy(toast);d.resolve=nil
        d.inputs={event={type="event",label="Show",wire=true,required=true,order=1},text=port("string","Text","AuraStudio",2),
            icon={type="integer",label="Icon (Texture ID)",wire=true,required=false,optional=true,maySecret=true,order=3},
            symbol={type="symbol",label="Symbol",wire=true,required=false,optional=true,order=4}}
        d.secretInputs={icon=true}
        d.outputs={closed=port("event","Closed",nil,1),dismissed=port("boolean","Dismissed",nil,2)}
        d.fields={{key="position",label="Position",choices=A.Toasts.positions,choiceLabels=A.Toasts.labels,primary=true},
            {key="opacity",label="Opacity",type="float",slider={min=.1,max=1,step=.05,format="percent"}},
            {key="duration",label="Show for",type="float",slider={min=.5,max=60,step=.5,format="seconds"}},
            {key="fade",label="Fade in / out",type="boolean"},
            {key="fadeDuration",label="Fade time",type="float",slider={min=.1,max=3,step=.1,format="seconds"}},
            {key="dismissible",label="Click to dismiss",type="boolean"},
            {key="icon",label="Icon",type="string",picker="icon"},
            {key="symbolPosition",label="Symbol position",choices={"left","right","above","below"},choiceLabels={left="Left of the text",right="Right of the text",above="Above the text",below="Below the text"}},
            {key="symbolScale",label="Symbol size (x font size)",type="float",slider={min=.5,max=4,step=.1}},
            {key="source",label="Sound",choices={"none","soundkit","sharedmedia"},choiceLabels={none="None",soundkit="Game SoundKit",sharedmedia="SharedMedia"}}}
        if c.source=="soundkit" then
            d.fields[#d.fields+1]={key="soundKit",label="SoundKit",type="integer",picker="sound"}
            d.fields[#d.fields+1]={key="volume",label="Volume (%)",type="float",slider={min=0,max=100,step=5}}
        elseif c.source=="sharedmedia" then d.fields[#d.fields+1]={key="sound",label="Sound",type="string",picker="sound"} end
        if c.source~="none" then d.fields[#d.fields+1]={key="channel",label="Channel",choices={"Master","SFX","Music","Ambience","Dialog"}} end
        return d
    end
    add("toast_note",toast)
end
-- Capture target (in-game request 0.8.59): reads whom a unit targets at the
-- moment a new value arrives on Capture; compares with the previous capture.
do
    local units={"target","focus","mouseover","party_member","raid_member"}
    local labels={target="Your target",focus="Your focus",mouseover="Mouseover",party_member="Party member's target",raid_member="Raid member's target"}
    local capture={label="Capture target",category="sources",flowOperation="capture_target",inputs={},outputs={},defaults={unit="target",slot=1},
        help="Reads the chosen target at the moment a new value arrives on Capture (any type: event, action, boolean, number, text). Nothing is read in between. Exists, Name and GUID describe the captured target; Changed compares it with the previous capture of this node (by GUID when readable, otherwise by name) and stays empty when either side is unknown or protected. Example: capture before and after a target macro, then compare."}
    capture.resolve=function(c)
        local ok=false;for _,u in ipairs(units) do if c.unit==u then ok=true end end
        if not ok then return nil,"Choose whose target to capture" end
        local max=c.unit=="party_member" and 4 or c.unit=="raid_member" and 40
        if max and (not G.Number(c.slot) or c.slot<1 or c.slot>max or c.slot~=math.floor(c.slot)) then return nil,"Slot must be 1.."..max end
        local d=G.Copy(capture);d.resolve=nil
        d.inputs={capture={label="Capture",type="any",wire=true,required=true,order=1}}
        d.outputs={captured=port("event","Captured",nil,1),exists=port("boolean","Exists",nil,2),name=port("string","Name",nil,3),guid=port("string","GUID",nil,4),changed=port("boolean","Changed since last capture",nil,5)}
        d.outputs.name.maySecret=true;d.outputs.guid.maySecret=true
        d.fields={{key="unit",label="Whose target",choices=units,choiceLabels=labels,primary=true}}
        if max then d.fields[2]={key="slot",label=c.unit=="party_member" and "Party slot (1-4)" or "Raid slot (1-40)",type="integer",primary=true} end
        return d
    end
    add("capture_target",capture)
end
-- Symbol (Lucide, in-game request 0.8.58): media output for any media port
-- and a Symbol output for nodes that place the glyph next to their text.
do
    local c=port("string","Colour (hex)","FFFFFF",1);c.picker="color"
    add("symbol",{label="Symbol",source=true,category="media",flowOperation="symbol",defaults={symbol="star"},
        inputs={color=c},outputs={media={label="Media",type="media",order=1},symbol={label="Symbol",type="symbol",order=2}},
        fields={{key="symbol",label="Symbol",type="string",picker="symbol",primary=true}},
        validate=function(cfg)
            local S=BVAddonSuiteCore and BVAddonSuiteCore.Symbols
            if type(cfg.symbol)~="string" or (S and not S:Valid(cfg.symbol)) then return false,"Choose a symbol" end
            return true
        end,
        help="Pick a symbol (Lucide icon set). Media works on every media port, for example Display or modifiers; the colour tints it. Symbol connects to Toast Note, Text media and Button Media, which show it next to their text. Symbols are line graphics from the bundled Lucide set (ISC licence), not WoW icons."})
end
-- Colour overlay (in-game request 0.8.58). Only blend modes WoW textures
-- support natively; no pixel shaders, so no Photoshop Overlay/Soft light.
do
    local modes={"normal","multiply","add","tint","desaturate"}
    local labels={normal="Normal",multiply="Multiply (darken)",add="Add (lighten)",tint="Tint",desaturate="Greyscale + tint"}
    local overlay={label="Colour overlay",category="modifiers",bypass={media="media"},inputs={},outputs={},
        defaults={mode="normal"},
        help="Puts a colour over Icon or Graphic media. Normal lays the colour over the media, Multiply darkens by the colour, Add brightens by it, Tint colours the media itself and Greyscale + tint removes the original colours first. Strength 0..1 blends from no effect to full. WoW textures only support these blend modes; Photoshop modes such as Overlay, Soft light or Screen do not exist in the game. Transparent parts of graphics stay transparent where the client supports masks."}
    overlay.resolve=function(c)
        local ok=false;for _,m in ipairs(modes) do if c.mode==m then ok=true end end
        if not ok then return nil,"Choose an overlay mode" end
        local d=G.Copy(overlay);d.resolve=nil
        d.inputs={media={label="Media",type="media",wire=true,required=true,order=1},color=port("string","Colour (hex)","FF6040",2),strength=port("float","Strength (0..1)",.5,3)}
        d.outputs={media={label="Media",type="media",order=1}}
        d.fields={{key="mode",label="Mode",choices=modes,choiceLabels=labels,primary=true}}
        return d
    end
    add("color_overlay",overlay)
end
-- Sprite sheets (roadmap P2b): one cell, or a native FlipBook animation.
do
    local sprite={label="Sprite",bypass={media="media"},inputs={},outputs={},
        defaults={mode="frame",rows=4,columns=4,frames=16,fps=12},
        help="Treat Icon or Graphic media as a sprite sheet of Rows x Columns cells, counted row by row from the top left. Frame shows one cell; the Frame input wraps around, so a counter can drive it. Animate plays the first Frames cells natively as a FlipBook at the chosen frames per second, without per-frame Lua. Animate replaces an earlier Crop."}
    sprite.resolve=function(c)
        local function int(v,lo,hi) return G.Number(v) and v==math.floor(v) and v>=lo and v<=hi end
        if c.mode~="frame" and c.mode~="animate" then return nil,"Choose Frame or Animate" end
        if not int(c.rows,1,16) or not int(c.columns,1,16) then return nil,"Rows and columns must be 1..16" end
        if not int(c.frames,1,256) or c.frames>c.rows*c.columns then return nil,"Frames must be 1..rows x columns" end
        if c.mode=="animate" and not int(c.fps,1,60) then return nil,"Frames per second must be 1..60" end
        local d=G.Copy(sprite);d.resolve=nil
        d.inputs={media={label="Media",type="media",wire=true,required=true,order=1}}
        if c.mode=="frame" then d.inputs.frame=port("integer","Frame",1,2) end
        d.outputs={media={label="Media",type="media",order=1}}
        d.fields={{key="mode",label="Mode",choices={"frame","animate"},choiceLabels={frame="One frame",animate="Animate"},primary=true},
            {key="rows",label="Rows (1..16)",type="integer"},{key="columns",label="Columns (1..16)",type="integer"},{key="frames",label="Frames used",type="integer"}}
        if c.mode=="animate" then d.fields[#d.fields+1]={key="fps",label="Frames per second",type="float",slider={min=1,max=60,step=1}} end
        return d
    end
    add("media_sprite",sprite)
end
-- Start / main / finish lifecycle for ordinary displays (roadmap P2b).
add("display_lifecycle",{label="Show / Hide animation",bypass={media="media"},
    inputs={media={label="Media",type="media",wire=true,required=true,order=1}},outputs={media={label="Media",type="media",order=1}},
    defaults={start="fade",startTime=.3,main="none",mainPeriod=1.2,finish="fade",finishTime=.3},
    fields={{key="start",label="Start (appear)",choices={"none","fade","grow"},choiceLabels={none="None",fade="Fade in",grow="Grow"},primary=true},
        {key="startTime",label="Start time",type="float",slider={min=.05,max=5,step=.05,format="seconds"}},
        {key="main",label="Main (while shown)",choices={"none","pulse","throb"},choiceLabels={none="None",pulse="Pulse",throb="Throb"}},
        {key="mainPeriod",label="Main period",type="float",slider={min=.2,max=10,step=.1,format="seconds"}},
        {key="finish",label="Finish (disappear)",choices={"none","fade","shrink"},choiceLabels={none="None",fade="Fade out",shrink="Shrink"}},
        {key="finishTime",label="Finish time",type="float",slider={min=.05,max=5,step=.05,format="seconds"}}},
    validate=function(c)
        if not BVAddonSuiteCore.DisplayModel.LifecycleValid({start=c.start,startTime=c.startTime,main=c.main,mainPeriod=c.mainPeriod,finish=c.finish,finishTime=c.finishTime}) then return false,"Choose valid start, main and finish settings" end
        return true
    end,
    help="WeakAuras-style lifecycle for a display: Start plays when it appears, Main loops while it is shown, Finish plays when it disappears and the display hides only afterwards. Showing it again during Finish cancels the finish. Native animations, no per-frame Lua. Action Display ignores it because protected buttons cannot delay hiding."})
-- Relay: passes any value through; its node title names the block port.
add("relay",{label="Relay",flowOperation="relay",transparentInput="value",category="logic",secretInputs={value=true},
    inputs={value={label="Value",type="any",wire=true,required=false,optional=true,maySecret=true,order=1}},outputs={value={label="Value",type="any",order=1,optional=true,maySecret=true}},defaults={},fields={},
    help="Passes its input through unchanged, whatever the type. Use it as a named input or output of a building block: rename the node (double-click the title) to label the connection point, then connect it after inserting the block."})

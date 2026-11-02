local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local G,M=A.G,ns.DisplayModel
local D={}
A.DirectDisplay=D
local KINDS={icon=true,text=true,bar=true,graphic=true}
local function configKey(kind,key) return kind..key:sub(1,1):upper()..key:sub(2) end
local function mediaConfig(config)
    local kind=config.kind
    local source=A.catalog["media_"..kind]
    local out=G.Copy(source.defaults)
    for key in pairs(out) do
        local own=config[configKey(kind,key)]
        if own~=nil then out[key]=own end
    end
    -- Direct bars always receive explicit values; native player-health media
    -- remains available through the composable media pipeline.
    if kind=="bar" then out.source="values" end
    return out,source
end
D.MediaConfig=mediaConfig
-- Studio calls this before assigning config[key]; keep file/game paths separate.
function D.ChangeConfig(node,key,value)
    if key~="graphicSource" then return end
    local config=node.config
    local paths=config.graphicPathsBySource or {};config.graphicPathsBySource=paths
    paths[config.graphicSource or "file"]=config.graphicPath
    if value=="file" then config.graphicPath=paths.file or A.catalog.media_graphic.defaults.path
    elseif value=="game" then config.graphicPath=paths.game or "Interface\\Buttons\\WHITE8X8" end
end
local function port(label,kind,value,order)
    return {label=label,type=kind,default=value,required=true,wire=false,advanced=true,order=order}
end
local appearance={
    color=port("Color","string","FFFFFFFF",30),alpha=port("Opacity (0..1)","float",1,31),
    scale=port("Scale (0..10)","float",1,32),offsetX=port("Offset X","float",0,33),offsetY=port("Offset Y","float",0,34),
    widthDelta=port("Width delta","float",0,35),heightDelta=port("Height delta","float",0,36),
    glowStrength=port("Glow strength (0..1)","float",0,40),glowColor=port("Glow color","string","FFD100FF",41),glowSize=port("Glow spread (0..12)","float",3,42),
}
appearance.color.picker="color"
appearance.glowColor.picker="color"
local base={label="Display visual",category="outputs",sink=true,display=true,directDisplay=true,revision=1,inputs={},outputs={},
    defaults={kind="icon"},fields={},
    help="Show an icon, text, bar or graphic directly. Set appearance values in the inspector or expose their typed inputs for state-dependent colour, opacity, size, position and glow. Geometry applies scale, size delta, then offset in visual space. Color tints RGB; Opacity controls transparency. Secret content passes only to supported native setters; appearance must be readable. Use media and modifiers with Display for arbitrary transform order, animations and compositions."}
-- Namespaced media settings prevent a kind switch from reinterpreting an icon
-- texture ID as a statusbar texture, or a bar source as a graphic source.
for kind in pairs(KINDS) do
    for key,value in pairs(A.catalog["media_"..kind].defaults) do base.defaults[configKey(kind,key)]=G.Copy(value) end
end
base.resolve=function(config)
    if type(config)~="table" or not KINDS[config.kind] then return nil,"Choose an icon, text, bar or graphic" end
    local kind=config.kind
    local media,source=mediaConfig(config)
    local original,why=G.Definition(source,{config=media})
    if not original then return nil,why end
    local def=G.Copy(base);def.resolve=nil;def.visualKind=kind
    def.inputs=G.Copy(appearance);def.secretInputs={}
    def.fields={{key="kind",label="Show",choices={"icon","text","bar","graphic"},
        choiceLabels={icon="Icon",text="Text",bar="Bar",graphic="Graphic"},primary=true}}
    -- Studio attaches shared layout controls after catalog loading. Preserve
    -- them when specializing the visual kind instead of replacing the list.
    for _,field in ipairs(base.fields) do
        if field.layoutOption then def.fields[#def.fields+1]=G.Copy(field) end
    end
    for _,field in ipairs(original.fields or {}) do
        -- Text size is a typed appearance input, with a local inspector value.
        if not (kind=="text" and field.key=="fontSize") then
            local copy=G.Copy(field);copy.key=configKey(kind,field.key)
            def.fields[#def.fields+1]=copy
        end
    end
    local content=kind=="icon" and {"texture"} or kind=="text" and {"text"} or kind=="bar" and {"value","maximum","background","borderColor","borderWidth"} or {}
    for _,key in ipairs(content) do
        def.inputs[key]=G.Copy(original.inputs[key])
        if original.secretInputs and original.secretInputs[key] then def.secretInputs[key]=true end
        if key=="background" or key=="borderColor" or key=="borderWidth" then def.inputs[key].advanced=true end
    end
    if kind=="icon" then
        def.inputs.texture.wire=true;def.inputs.texture.required=false;def.inputs.texture.default=nil
    elseif kind=="text" then
        def.inputs.fontSize=port("Font size (4..128)","float",media.fontSize,37)
        def.inputs.outlineWidth=port("Outline width (0..6)","float",0,43)
        def.inputs.outlineColor=port("Outline color","string","000000FF",44);def.inputs.outlineColor.picker="color"
    end
    def.inputs.visible=G.Copy(A.catalog.display.inputs.visible);def.inputs.visible.order=10
    if kind=="icon" or kind=="bar" then
        def.inputs.realTime=G.Copy(A.catalog.display.inputs.realTime);def.inputs.realTime.advanced=true;def.inputs.realTime.order=11
        def.secretInputs.realTime=true
    end
    def.validate=function(current)
        local own,mediaDef=mediaConfig(current)
        local valid,message=mediaDef.validate(own)
        if not valid then return false,message end
        return A.catalog.display.validate(current)
    end
    return def
end
A.catalog.display_visual=base
A.order[#A.order+1]="display_visual"

-- Called after Runtime's controls. resolve is the existing typed/Secret-aware
-- resolver; no native value is read, formatted, compared or copied here.
function D.Evaluate(node,def,resolve,incoming)
    incoming=incoming or {}
    local visible=resolve("visible")
    if visible==nil or G.IsSecret(visible) then return nil,"unavailable" end
    if not visible then return {visible=false},"hidden" end
    local args={}
    for key in pairs(def.inputs) do
        local optional=(key=="texture" or key=="realTime") and not incoming[key]
        if key~="visible" and not optional then
            local value=resolve(key)
            if value==nil or (not def.secretInputs[key] and G.IsSecret(value)) then return nil,"unavailable" end
            args[key]=value
        end
    end
    local config=mediaConfig(node.config)
    local kind=def.visualKind
    local content
    if kind=="icon" then content=args.texture elseif kind=="text" then content=args.text elseif kind=="bar" then content=args end
    if kind=="text" then config.fontSize=args.fontSize end
    local media=M.New(kind,config,content)
    -- Reuse the same modifiers as the composable pipeline, in one documented order.
    media=M.Modify(media,"tint",{color=args.color,red=1,green=1,blue=1},{})
    media=M.Modify(media,"opacity",{alpha=args.alpha},{})
    media=M.Modify(media,"scale",{factor=args.scale},{mode="visual",pivot="CENTER"})
    media=M.Modify(media,"size",{x=args.widthDelta,y=args.heightDelta},{mode="visual",pivot="CENTER"})
    media=M.Modify(media,"offset",{x=args.offsetX,y=args.offsetY},{mode="visual"})
    media=M.Modify(media,"glow",{strength=args.glowStrength,color=args.glowColor,size=args.glowSize},{iconStyle="auto",textStyle="soft"})
    if kind=="text" then media=M.Modify(media,"text_outline",{width=args.outlineWidth,color=args.outlineColor},{}) end
    if incoming.realTime then media=M.Modify(media,kind=="icon" and "icon_duration" or "bar_duration",{duration=args.realTime},{}) end
    return {visible=true,media=media},"shown"
end

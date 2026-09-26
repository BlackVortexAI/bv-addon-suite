-- Plain, bounded media values. No native frames and no changes to saved layout.
local _,ns=...
local M={}; ns.DisplayModel=M
M.buttonStyles={"wow","modern","arcane","runic","ember","frost","tech"}
M.buttonLabels={wow="WoW",modern="Modern",arcane="Arcane Sigil",runic="Runic Gold",ember="Emberforge",frost="Frost Crystal",tech="Prismatic Tech"}
M.buttonPalettes={
    arcane={base={.10,.06,.19,1},top={.24,.13,.36,1},edge={.55,.35,.83,1},accent={.79,.59,1,1}},
    runic={base={.11,.09,.06,1},top={.24,.20,.12,1},edge={.55,.39,.15,1},accent={.94,.74,.36,1}},
    ember={base={.15,.045,.025,1},top={.32,.10,.045,1},edge={.61,.25,.08,1},accent={1,.52,.16,1}},
    frost={base={.035,.105,.16,1},top={.10,.25,.33,1},edge={.25,.59,.72,1},accent={.65,.94,1,1}},
    tech={base={.035,.055,.095,1},top={.12,.16,.24,1},edge={.21,.36,.52,1},accent={.24,.86,.94,1}},
}
local V=ns.GraphValues
M.pivots={CENTER={0,0},LEFT={-0.5,0},RIGHT={0.5,0},TOP={0,0.5},BOTTOM={0,-0.5},
    TOPLEFT={-0.5,0.5},TOPRIGHT={0.5,0.5},BOTTOMLEFT={-0.5,-0.5},BOTTOMRIGHT={0.5,-0.5}}
local function finite(v) return not V.IsSecret(v) and type(v)=="number" and v==v and math.abs(v)<math.huge end
local function bounded(v,lo,hi) return finite(v) and v>=lo and v<=hi end
function M.GraphicPath(value)
    if type(value)~="string" or #value>240 or value:find("[%c|:]") then return end
    value=value:gsub("/","\\")
    if not value:match("^Interface\\AddOns\\[%w_ %-]+\\") or value:find("\\\\",1,true) then return end
    for part in value:gmatch("[^\\]+") do if part=="." or part==".." or part:find("[^%w_%. %-]") or part:match("[%. ]$") then return end end
    local ext=value:lower():match("%.(%w+)$")
    if ext~="tga" and ext~="blp" then return end
    return value
end
function M.GameGraphicPath(value)
    if V.IsSecret(value) or type(value)~="string" or #value>240 or value:find("[%c|:]") then return end
    value=value:gsub("/","\\")
    if not value:match("^Interface\\[%w_ %-]+\\") or value:find("\\\\",1,true) then return end
    for part in value:gmatch("[^\\]+") do if part=="." or part==".." or part:find("[^%w_%. %-]") or part:match("[%. ]$") then return end end
    return value
end
function M.AtlasName(value)
    return not V.IsSecret(value) and type(value)=="string" and #value>0 and #value<=128 and not value:find("[^%w_%-]")
end
local function cropValid(c)
    return type(c)=="table" and bounded(c[1],0,1) and bounded(c[2],0,1) and bounded(c[3],0,1) and bounded(c[4],0,1)
        and c[1]<c[2] and c[3]<c[4]
end
function M.GlowColor(value)
    if type(value)~="string" then return end
    value=value:gsub("^#","")
    if (#value~=6 and #value~=8) or value:find("[^%x]") then return end
    return {tonumber(value:sub(1,2),16)/255,tonumber(value:sub(3,4),16)/255,tonumber(value:sub(5,6),16)/255,
        #value==8 and tonumber(value:sub(7,8),16)/255 or 1}
end
function M.GlowOptions(media)
    local out=ns.LayoutModel.Copy(media.glowEffect or {iconStyle="auto",textStyle="soft",color={1,.82,0,1},size=3,speed=1})
    for key,value in pairs({scaleX=1,scaleY=1,offsetX=0,offsetY=0,pulse=false,period=1.6,minimum=.25}) do
        if out[key]==nil then out[key]=value end
    end
    return out
end
local function rgba(c)
    if type(c)~="table" then return false end
    for i=1,4 do if not bounded(c[i],0,1) then return false end end
    return true
end
local function descriptor(value,kind,keys)
    if not V.PlainExcept(value,{}) or value.version~=1 or value.kind~=kind then return false end
    for k in pairs(value) do if not keys[k] then return false end end
    return true
end
local function styleColor(value)
    if not rgba(value) then return false end
    for key in pairs(value) do if type(key)~="number" or key<1 or key>4 or key~=math.floor(key) then return false end end
    return true
end
function M.Font(value)
    return descriptor(value,"font",{version=true,kind=true,family=true,size=true,outline=true})
        and ns.Media:Reference("font",value.family) and bounded(value.size,4,128)
        and ({NONE=true,OUTLINE=true,THICKOUTLINE=true})[value.outline]==true
end
function M.Style(value)
    return descriptor(value,"style",{version=true,kind=true,color=true,background=true,borderColor=true,borderWidth=true,alpha=true})
        and styleColor(value.color) and styleColor(value.background) and styleColor(value.borderColor)
        and bounded(value.borderWidth,0,24) and bounded(value.alpha,0,1)
end
function M.NewFont(config)
    assert(V.PlainExcept(config,{}),"Font settings must be readable")
    local value={version=1,kind="font",family=config.family,size=config.size,outline=config.outline}
    assert(M.Font(value),"Invalid font definition");return value
end
function M.NewStyle(config)
    assert(V.PlainExcept(config,{}),"Style settings must be readable")
    local value={version=1,kind="style",color=M.GlowColor(config.color),background=M.GlowColor(config.background),
        borderColor=M.GlowColor(config.borderColor),borderWidth=config.borderWidth,alpha=config.alpha}
    assert(M.Style(value),"Invalid style definition");return value
end
function M.ApplyStyle(media,style)
    if not style then return media end
    assert(M.Style(style),"Invalid media style")
    local m=V.RuntimeCopy(media)
    m.color=V.Copy(style.color);m.alpha=style.alpha
    if m.kind=="bar" then m.background=V.Copy(style.background);m.borderColor=V.Copy(style.borderColor);m.borderWidth=style.borderWidth
    else m.surface={background=V.Copy(style.background),borderColor=V.Copy(style.borderColor),borderWidth=style.borderWidth} end
    assert(M.Valid(m),"Invalid styled media");return m
end
function M.ApplyFont(media,font)
    if not font then return media end
    assert(M.Font(font) and media.kind=="text","Invalid text font")
    local m=V.RuntimeCopy(media);m.font=font.family;m.fontSize=font.size;m.fontFlags=font.outline
    return m
end
-- These descriptors contain identifiers only. Native values/DurationObjects are
-- fetched at the renderer boundary and never become media, trace or saved data.
function M.NativeBinding(binding)
    if type(binding)~="table" or getmetatable(binding) then return false end
    if binding.kind~="unit_health" or binding.unit~="player" then return false end
    for k in pairs(binding) do if k~="kind" and k~="unit" then return false end end
    return true
end
function M.Valid(m)
    if not V.PlainExcept(m,{value="float",maximum="float",text="string",texture="integer",duration="duration",overlay={text="string"},interaction={payload="click"}}) then return false end
    if (m.kind~="text" and V.IsSecret(m.text)) or (m.kind~="icon" and V.IsSecret(m.texture))
        or (m.kind~="bar" and (V.IsSecret(m.value) or V.IsSecret(m.maximum))) then return false end
    if type(m)~="table" or m.version~=1 or type(m.ops)~="table" or #m.ops>32 then return false end
    if m.atlas~=nil and m.kind~="icon" and m.kind~="graphic" then return false end
    if m.crop~=nil and ((m.kind~="icon" and m.kind~="graphic") or not cropValid(m.crop)) then return false end
    if m.flipX~=nil and type(m.flipX)~="boolean" or m.flipY~=nil and type(m.flipY)~="boolean" then return false end
    if m.blendMode~=nil and not ({BLEND=true,ADD=true,MOD=true,ALPHAKEY=true})[m.blendMode] then return false end
    if m.buttonStyle~=nil and (m.kind~="text" or not M.buttonLabels[m.buttonStyle]) then return false end
    if m.cropBorder~=nil and (m.kind~="icon" or type(m.cropBorder)~="boolean") then return false end
    if m.iconSkin~=nil and (m.kind~="icon" or not ns.IconSkins.Valid(m.iconSkin)) then return false end
    if m.iconShape~=nil and (m.kind~="icon" or not ns.IconSkins.Supports(m.iconSkin or "none",m.iconShape)) then return false end
    if m.kind=="icon" then
        if m.atlas~=nil then
            if m.texture~=nil or type(m.atlas)~="string" or #m.atlas<1 or #m.atlas>128 or m.atlas:find("[^%w_%-]") then return false end
        elseif not V.Accepts("integer",m.texture) and not ns.IconCatalog:Reference(m.texture) then return false end
    elseif m.kind=="graphic" then
        if m.graphicSource~=nil and not ({file=true,game=true,fileID=true,atlas=true})[m.graphicSource] then return false end
        if m.atlas then
            if not M.AtlasName(m.atlas) or m.texture~=nil then return false end
        elseif m.graphicSource=="fileID" then
            if not bounded(m.texture,1,2147483647) or m.texture~=math.floor(m.texture) then return false end
        elseif m.graphicSource=="game" then
            if not M.GameGraphicPath(m.texture) then return false end
        elseif not M.GraphicPath(m.texture) then return false end
        if type(m.texcoords)~="table" then return false end
        for i=1,4 do if not bounded(m.texcoords[i],0,1) then return false end end
        if m.texcoords[1]>=m.texcoords[2] or m.texcoords[3]>=m.texcoords[4] then return false end
    elseif m.kind=="text" then
        if (not V.Accepts("string",m.text) and (type(m.text)~="string" or #m.text>1024)) or not ns.Media:Reference("font",m.font) or not bounded(m.fontSize,4,128)
            or not ({LEFT=true,CENTER=true,RIGHT=true})[m.align] or type(m.wrap)~="boolean" then return false end
        if m.fontFlags~=nil and not ({NONE=true,OUTLINE=true,THICKOUTLINE=true})[m.fontFlags] then return false end
    elseif m.kind=="bar" then
        if not ({RIGHT=true,LEFT=true,UP=true,DOWN=true})[m.direction]
            or not ns.Media:Reference("statusbar",m.texture)
            or not rgba(m.background) or not rgba(m.borderColor) or not bounded(m.borderWidth,0,24) then return false end
        if m.nativeBinding then
            if not M.NativeBinding(m.nativeBinding) or m.value~=nil or m.maximum~=nil then return false end
        elseif not m.duration and (not (V.Accepts("float",m.value) or bounded(m.value,0,1e12))
            or not (V.Accepts("float",m.maximum) or bounded(m.maximum,0.000001,1e12))) then return false end
    else return false end
    if m.duration~=nil and ((m.kind~="bar" and m.kind~="icon") or not V.Accepts("duration",m.duration)) then return false end
    if m.cooldown then
        local c=m.cooldown
        if m.kind~="icon" or type(c)~="table" or c.kind~="spell" or not bounded(c.spellID,1,2147483647)
            or c.spellID~=math.floor(c.spellID) or type(c.showNumbers)~="boolean" then return false end
        for k in pairs(c) do if k~="kind" and k~="spellID" and k~="showNumbers" then return false end end
    end
    if m.overlay then
        local o=m.overlay
        if type(o)~="table" or (not V.Accepts("string",o.text) and (type(o.text)~="string" or #o.text>1024)) or not ns.Media:Reference("font",o.font)
            or not bounded(o.fontSize,4,128) or not M.pivots[o.point] or not rgba(o.color)
            or not ({NONE=true,OUTLINE=true,THICKOUTLINE=true})[o.outline]
            or not bounded(o.offsetX,-256,256) or not bounded(o.offsetY,-256,256) then return false end
    end
    if m.interaction then
        local i=m.interaction
        if type(i)~="table" or type(i.key)~="string" or #i.key<1 or #i.key>40 or not i.key:match("^[%w_.%-]+$")
            or type(i.enabled)~="boolean" or type(i.tooltip)~="string" or #i.tooltip>256 then return false end
        if i.payload~=nil and not V.Accepts("click",i.payload) then return false end
        if i.feedback~=nil and type(i.feedback)~="boolean" then return false end
        for key in pairs(i) do if key~="key" and key~="enabled" and key~="tooltip" and key~="payload" and key~="feedback" then return false end end
    end
    if not bounded(m.alpha,0,1) or not bounded(m.glow,0,1) or type(m.color)~="table" then return false end
    for i=1,3 do if not bounded(m.color[i],0,1) then return false end end
    if m.color[4]~=nil and not bounded(m.color[4],0,1) then return false end
    if m.surface and (type(m.surface)~="table" or not rgba(m.surface.background) or not rgba(m.surface.borderColor) or not bounded(m.surface.borderWidth,0,24)) then return false end
    if m.glowEffect then
        local g=m.glowEffect
        if type(g)~="table" or not ({auto=true,button=true,proc=true,pixel=true,autocast=true})[g.iconStyle]
            or not ({soft=true,outline=true,neon=true,shadow=true,pixel=true,autocast=true})[g.textStyle] or not bounded(g.size,0,12) or not bounded(g.speed,0,4)
            or type(g.color)~="table" then return false end
        for i=1,4 do if not bounded(g.color[i],0,1) then return false end end
        local o=M.GlowOptions(m)
        if not bounded(o.scaleX,.1,4) or not bounded(o.scaleY,.1,4) or not bounded(o.offsetX,-256,256)
            or not bounded(o.offsetY,-256,256) or type(o.pulse)~="boolean" or not bounded(o.period,.2,30)
            or not bounded(o.minimum,0,1) then return false end
    end
    for _,key in ipairs({"textOutline","textShadow","iconBorder"}) do
        local e=m[key]
        if e~=nil then
            if type(e)~="table" or not rgba(e.color) then return false end
            if key=="textShadow" then
                if not bounded(e.x,-64,64) or not bounded(e.y,-64,64) then return false end
            elseif not bounded(e.width,0,key=="textOutline" and 6 or 24) then return false end
            if key=="iconBorder" and e.style~=nil and not ({solid=true,corners=true,double=true})[e.style] then return false end
        end
    end
    for _,op in ipairs(m.ops) do
        if type(op)~="table" or not ({visual=true,layout=true})[op.mode] or not M.pivots[op.pivot] then return false end
        if op.kind=="offset" or op.kind=="size" then
            if not bounded(op.x,-10000,10000) or not bounded(op.y,-10000,10000) then return false end
        elseif op.kind=="scale" then if not bounded(op.factor,0,10) then return false end
        elseif op.kind=="rotate" then
            if op.mode~="visual" or not bounded(op.angle,-360000,360000) then return false end
            if (m.kind=="bar" or m.cooldown or m.duration or m.overlay) and op.angle%360~=0 then return false end
        else return false end
    end
    return true
end
function M.New(kind,config,text)
    local m={version=1,kind=kind,alpha=1,color={1,1,1},glow=0,ops={}}
    if kind=="icon" then
        m.cropBorder=config.cropBorder~=false
        if config.atlas then m.atlas=config.atlas else m.texture=text~=nil and text or ns.IconCatalog:Reference(config.texture) end
    elseif kind=="graphic" then
        m.graphicSource=config.source or "file"
        if m.graphicSource=="atlas" then m.atlas=config.atlas
        elseif m.graphicSource=="fileID" then m.texture=config.fileID
        elseif m.graphicSource=="game" then m.texture=M.GameGraphicPath(config.path)
        else m.texture=M.GraphicPath(config.path) end
        m.texcoords={config.left,config.right,config.top,config.bottom}
    elseif kind=="bar" then
        m.texture=config.texture; m.direction=config.direction
        m.background=M.GlowColor(text and text.background or config.background)
        m.borderColor=M.GlowColor(text and text.borderColor or config.borderColor)
        m.borderWidth=text and text.borderWidth or config.borderWidth
        if text and text.color then m.color=M.GlowColor(text.color) end
        if config.source=="player_health" then m.nativeBinding={kind="unit_health",unit="player"}
        else m.value=text.value; m.maximum=text.maximum end
    else m.text=text; m.font=config.font; m.fontSize=config.fontSize; m.align=config.align; m.wrap=config.wrap end
    assert(M.Valid(m),"Invalid media definition"); return m
end
function M.NewButton(config,text)
    local m=M.New("text",config,text);m.buttonStyle=config.buttonStyle
    assert(M.Valid(m),"Invalid button appearance");return m
end
function M.Equal(a,b)
    if V.IsSecret(a) or V.IsSecret(b) then return false end
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not M.Equal(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
function M.Summary(value)
    if V.IsSecret(value) then return "protected" end
    if type(value)=="table" and value.version==1 and value.kind then
        return value.kind.." / "..tostring(#(value.ops or {})).." transforms / alpha "..tostring(value.alpha)
    end
    return tostring(value)
end
-- Input snapshots change independently of the image. Runtime handles in actual
-- visual properties retain the conservative, non-comparing equality contract.
function M.SameVisual(a,b)
    if V.IsSecret(a) or V.IsSecret(b) or type(a)~="table" or type(b)~="table" then return M.Equal(a,b) end
    for key,value in pairs(a) do if key~="interaction" and not M.Equal(value,b[key]) then return false end end
    for key in pairs(b) do if key~="interaction" and a[key]==nil then return false end end
    return true
end
function M.SameLayout(a,b)
    local x,y=a and a.ops or {},b and b.ops or {}
    local i,j=1,1
    while true do
        while x[i] and x[i].mode~="layout" do i=i+1 end
        while y[j] and y[j].mode~="layout" do j=j+1 end
        if not M.Equal(x[i],y[j]) then return false end
        if not x[i] then return true end
        i,j=i+1,j+1
    end
end
function M.Rotate(x,y,degrees)
    local a=math.rad(degrees%360); local c,s=math.cos(a),math.sin(a)
    return x*c-y*s,x*s+y*c
end
function M.Modify(media,kind,args,config)
    local m=V.RuntimeCopy(media)
    if kind=="icon_appearance" then
        assert(m.kind=="icon","Icon Appearance requires icon media")
        assert(config.appearance=="original" or config.appearance=="cropped","Unknown icon appearance")
        m.crop=nil;m.cropBorder=config.appearance=="cropped"
        assert(ns.IconSkins.Valid(config.skin or "none"),"Unknown icon skin")
        m.iconSkin=config.skin~="none" and config.skin or nil
        assert(ns.IconSkins.Supports(config.skin or "none",config.shape or "square"),"Shape unavailable for this skin")
        m.iconShape=config.shape~="square" and config.shape or nil
    elseif kind=="bar_duration" or kind=="icon_duration" then
        assert(m.kind==(kind=="bar_duration" and "bar" or "icon"),"Duration needs matching media")
        assert(V.Accepts("duration",args.duration),"Runtime duration required")
        m.duration=args.duration;m.cooldown=nil;m.nativeBinding=nil
    elseif kind=="media_interaction" then m.interaction={key=config.key,enabled=args.enabled,tooltip=config.tooltip,feedback=config.feedback==true,payload=V.ClickCapture(config.payload,args)}
    elseif kind=="media_overlay" then
        m.overlay={text=args.text,font=config.font,fontSize=config.fontSize,point=config.point,
            color=M.GlowColor(args.color),outline=config.outline,offsetX=args.x,offsetY=args.y}
        if args.font then assert(M.Font(args.font),"Invalid overlay font");m.overlay.font=args.font.family;m.overlay.fontSize=args.font.size;m.overlay.outline=args.font.outline end
    elseif kind=="icon_cooldown" then
        assert(m.kind=="icon","Cooldown overlay requires icon media")
        m.cooldown={kind="spell",spellID=config.spellID,showNumbers=config.showNumbers};m.duration=nil
    elseif kind=="opacity" then m.alpha=args.alpha
    elseif kind=="tint" then m.color={args.red,args.green,args.blue}
    elseif kind=="glow" then
        m.glow=args.strength
        m.glowEffect={iconStyle=config.iconStyle or "auto",textStyle=config.textStyle or "soft",
            color=M.GlowColor(args.color or "FFD100"),size=args.size or 3,speed=args.speed or 1,
            scaleX=args.scaleX or 1,scaleY=args.scaleY or 1,offsetX=args.offsetX or 0,offsetY=args.offsetY or 0,
            pulse=args.pulse==true,period=args.period or 1.6,minimum=args.minimum or .25}
        if m.glowEffect.color then
            for i,key in ipairs({"red","green","blue","alpha"}) do
                local multiplier=args[key]==nil and 1 or args[key]
                assert(bounded(multiplier,0,1),"Glow color channels must be 0..1")
                m.glowEffect.color[i]=m.glowEffect.color[i]*multiplier
            end
        end
    elseif kind=="text_outline" then m.textOutline={color=M.GlowColor(args.color),width=args.width}
    elseif kind=="text_shadow" then m.textShadow={color=M.GlowColor(args.color),x=args.x,y=args.y}
    elseif kind=="icon_border" then m.iconBorder={color=M.GlowColor(args.color),width=args.width,style=config.style or "solid"}
    elseif kind=="media_crop" then
        assert(m.kind=="icon" or m.kind=="graphic","Crop requires icon or graphic media")
        m.crop={args.left,args.right,args.top,args.bottom};m.flipX=config.flipX==true;m.flipY=config.flipY==true;m.blendMode=config.blendMode or "BLEND"
    else
        assert(#m.ops<32,"At most 32 geometric transforms per display")
        m.ops[#m.ops+1]={kind=kind,mode=config.mode or "visual",pivot=config.pivot or "CENTER",x=args.x,y=args.y,factor=args.factor,angle=args.angle}
    end
    assert(M.Valid(m),"Display property out of range"); return m
end
-- Operation order is preserved inside each space. Layout always precedes visual.
function M.Transform(rect,media,mode)
    local r={x=rect.x,y=rect.y,width=rect.width,height=rect.height,angle=0,fontScale=1}
    for _,op in ipairs(media and media.ops or {}) do if op.mode==mode then
        local p=M.pivots[op.pivot]
        if op.kind=="offset" then r.x=r.x+op.x; r.y=r.y+op.y
        elseif op.kind=="rotate" then
            local px,py=p[1]*r.width,p[2]*r.height
            px,py=M.Rotate(px,py,r.angle)
            local rx,ry=M.Rotate(-px,-py,op.angle)
            r.x,r.y=r.x+px+rx,r.y+py+ry; r.angle=r.angle+op.angle
        else
            local w,h
            if op.kind=="scale" then w,h=r.width*op.factor,r.height*op.factor; r.fontScale=r.fontScale*op.factor
            else w,h=r.width+op.x,r.height+op.y end
            w,h=math.max(0,math.min(5000,w)),math.max(0,math.min(2000,h))
            local dx,dy=M.Rotate(p[1]*(r.width-w),p[2]*(r.height-h),r.angle)
            r.x,r.y=r.x+dx,r.y+dy; r.width,r.height=w,h
        end
    end end
    return r
end

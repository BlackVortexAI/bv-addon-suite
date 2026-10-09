local _, ns = ...

-- Shared visual primitives. Each context owns its palette and lifecycle; the
-- isolated DesignLab and production UI use this same implementation.
local DesignSystem = {}
ns.DesignSystem = DesignSystem
-- Native base dimensions are 90% of the design grid. User scale remains a
-- separate 1.0 multiplier; these helpers do not replace any native API method.
local M = { baseScale=.9 }
DesignSystem.Metrics = M
function M.ToNative(value) return value*M.baseScale end
function M.ToDesign(value) return value/M.baseScale end
local function scaledArgs(...)
    local args,count={...},select("#",...)
    for i=1,count do if type(args[i])=="number" then args[i]=M.ToNative(args[i]) end end
    return args,count
end
function M.Point(region,...)
    local args,count=scaledArgs(...); region:SetPoint(unpack(args,1,count))
end
function M.Size(region,width,height) region:SetSize(M.ToNative(width),M.ToNative(height)) end
function M.Width(region,width) region:SetWidth(M.ToNative(width)) end
function M.Height(region,height) region:SetHeight(M.ToNative(height)) end
function M.GetWidth(region) return M.ToDesign(region:GetWidth()) end
function M.GetHeight(region) return M.ToDesign(region:GetHeight()) end
function M.LineStart(region,...)
    local args,count=scaledArgs(...); region:SetStartPoint(unpack(args,1,count))
end
function M.LineEnd(region,...)
    local args,count=scaledArgs(...); region:SetEndPoint(unpack(args,1,count))
end
function M.Thickness(region,value) region:SetThickness(M.ToNative(value)) end
function M.TextInsets(region,...)
    local args,count=scaledArgs(...); region:SetTextInsets(unpack(args,1,count))
end
function M.ResizeBounds(region,...)
    local args,count=scaledArgs(...); region:SetResizeBounds(unpack(args,1,count))
end
local media = "Interface\\AddOns\\BVAddonSuite\\Media\\"
DesignSystem.logoTexture=media.."Brand\\bv-logo.tga"
DesignSystem.smallLogoTexture=media.."Brand\\bv-logo-small.tga"
DesignSystem.minimapLogoTexture=media.."Brand\\bv-logo-minimap.tga"
local fonts = {
    regular = media .. "Fonts\\AlegreyaSans-Regular.ttf",
    bold = media .. "Fonts\\AlegreyaSans-Bold.ttf",
    display = media .. "Fonts\\Ysabeau-Bold.ttf",
}
DesignSystem.palettes = {
    violet = { name="Arcane Violet", bg={.067,.067,.106}, panel={.122,.114,.184}, raised={.157,.141,.224},
        accent={.733,.643,.973}, secondary={.851,.686,.627}, text={.941,.929,.976}, muted={.706,.682,.776}, edge={.45,.40,.57} },
    ember = { name="Ember Atelier", bg={.094,.078,.075}, panel={.169,.137,.122}, raised={.208,.169,.141},
        accent={.906,.741,.514}, secondary={.663,.780,.749}, text={.953,.925,.886}, muted={.757,.702,.647}, edge={.52,.43,.32} },
    tide = { name="Moonlit Tide", bg={.051,.086,.106}, panel={.090,.153,.184}, raised={.122,.192,.231},
        accent={.537,.788,.827}, secondary={.710,.710,.925}, text={.906,.945,.953}, muted={.647,.737,.769}, edge={.34,.48,.55} },
}
local shared = { success={.58,.77,.69}, warning={.89,.74,.49}, danger={.93,.64,.69}, conditional={.47,.70,.94} }
DesignSystem.shared = shared
DesignSystem.signals={
    pending={color="accent",label="No sample",help="No matching live/test observation. Draft or frozen data is not a current gameplay value."},
    conditional={color="conditional",label="May be secret",help="This source can return secret data depending on the client and situation. No current matching observation is available."},
    readable={color="success",label="Readable",help="A usable value is available. Zero, false and empty text are valid values."},
    protected={color="warning",label="Secret",help="The value is currently secret, or depends on a secret input. No secret contents enter graph arithmetic."},
    unavailable={color="muted",label="No value",help="No usable value: missing observation, explicit Nil, muted/inactive branch, absent or permanent aura. Hover a port for its exact state."},
    faulted={color="danger",label="Fault",help="Evaluation failed. The affected output is unavailable; details are recorded in graph diagnostics."},
}
local Factory = {}
Factory.__index = Factory
function DesignSystem:New(owner)
    return setmetatable({ owner=owner, theme="violet", opacity=.94, paints={}, edits={} }, Factory)
end
local aliases={surface="panel",canvas="bg",ink="bg",hover="raised"}
function Factory:Color(key, alpha)
    key=aliases[key] or key
    if self.colorResolver then return self.colorResolver(key,alpha) end
    local c = self.palette and self.palette[key] or DesignSystem.palettes[self.theme][key] or shared[key]
    return c[1],c[2],c[3],alpha or c[4] or 1
end
function Factory:Bind(fn,widget)
    if self.registerPaint then assert(widget,"Production paint needs a lifecycle owner"); self.registerPaint(widget,fn)
    else self.paints[#self.paints+1]=fn; fn() end
end
function Factory:Refresh()
    self.palette=DesignSystem.palettes[self.theme]
    for _,paint in ipairs(self.paints) do paint() end
end
function Factory:Font(region, size, weight)
    region.bvFontSize,region.bvFontWeight=size or 14,weight or "regular"
    local fontSize=M.ToNative(size or 14)
    if self.fontResolver then self.fontResolver(region,fontSize,weight); return end
    if not region:SetFont(fonts[weight or "regular"],fontSize, "") then
        region:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"")
    end
end
function Factory:Label(parent, text, size, color, weight)
    local label=parent:CreateFontString(nil,"OVERLAY")
    self:Font(label,size,weight)
    label:SetJustifyH("LEFT"); label:SetJustifyV("MIDDLE")
    label:SetText(text or "")
    -- A composite control may own its text color; do not install a second
    -- generic paint callback that can fight its selected/hover states.
    self:Bind(function()
        self:Font(label,label.bvFontSize,label.bvFontWeight)
        if color~=false then label:SetTextColor(self:Color(color or "text")) end
        if label.bvAfterFont then label.bvAfterFont() end
    end,label)
    return label
end

local function slice(parent,path,corner,layer,sublevel,expand)
    local pieces={}; local c=corner or 6; local e=expand or 0
    local uv=path:find("shadow",1,true) and 20/64 or 8/64
    local bands={{0,uv},{uv,1-uv},{1-uv,1}}
    for row=1,3 do for col=1,3 do
        local t=parent:CreateTexture(nil,layer or "BACKGROUND",nil,sublevel or 0)
        t:SetTexture(path); t:SetTexCoord(bands[col][1],bands[col][2],bands[row][1],bands[row][2])
        if row==1 and col==1 then M.Point(t,"TOPLEFT",-e,e); M.Size(t,c,c)
        elseif row==1 and col==3 then M.Point(t,"TOPRIGHT",e,e); M.Size(t,c,c)
        elseif row==3 and col==1 then M.Point(t,"BOTTOMLEFT",-e,-e); M.Size(t,c,c)
        elseif row==3 and col==3 then M.Point(t,"BOTTOMRIGHT",e,-e); M.Size(t,c,c)
        elseif row==1 then M.Point(t,"TOPLEFT",c-e,e); M.Point(t,"TOPRIGHT",e-c,e); M.Height(t,c)
        elseif row==3 then M.Point(t,"BOTTOMLEFT",c-e,-e); M.Point(t,"BOTTOMRIGHT",e-c,-e); M.Height(t,c)
        elseif col==1 then M.Point(t,"TOPLEFT",-e,e-c); M.Point(t,"BOTTOMLEFT",-e,c-e); M.Width(t,c)
        elseif col==3 then M.Point(t,"TOPRIGHT",e,e-c); M.Point(t,"BOTTOMRIGHT",e,c-e); M.Width(t,c)
        else M.Point(t,"TOPLEFT",c-e,e-c); M.Point(t,"BOTTOMRIGHT",e-c,c-e) end
        pieces[#pieces+1]=t
    end end
    return pieces
end
DesignSystem.Slice=slice
function Factory:Skin(frame,fill,corner,alpha,shadow)
    -- In-game style contexts (UI/StyleFamilies.lua) draw the family's border.
    if self.skinner then return self.skinner(frame,fill,corner,alpha,shadow) end
    local fills=slice(frame,media.."DesignLab\\surface.tga",corner,"BACKGROUND",0)
    local borders=slice(frame,media.."DesignLab\\border.tga",corner,"BORDER",0)
    if shadow then slice(frame,media.."DesignLab\\shadow.tga",20,"BACKGROUND",-2,10) end
    frame.fills,frame.borders=fills,borders
    function frame:PaintSurface(background,edge,opacity)
        for _,t in ipairs(fills) do t:SetVertexColor(unpack(background)) end
        for _,t in ipairs(borders) do t:SetVertexColor(unpack(edge)) end
        if opacity then for _,t in ipairs(fills) do t:SetAlpha(opacity) end end
    end
    self:Bind(function()
        if frame.surfacePaintOwned then return end
        frame:PaintSurface({self:Color(fill or "panel")},{self:Color("edge",.45)},type(alpha)=="function" and alpha() or alpha or 1)
    end,frame)
    return frame
end
function Factory:Panel(parent,width,height,fill,corner,alpha)
    fill=aliases[fill] or fill or "panel"
    local panel=CreateFrame("Frame",nil,parent); M.Size(panel,width or 100,height or 100)
    self:Skin(panel,fill or "panel",corner or 6,alpha)
    if fill=="panel" or fill=="raised" then
        panel.sheen=self:Gradient(panel,"VERTICAL","secondary",.015,"accent",.045,corner or 6)
    end
    return panel
end
function Factory:Gradient(parent,orientation,fromKey,fromAlpha,toKey,toAlpha,inset)
    -- A gradient is a flat color field, never a stretched rounded-corner mask.
    -- Rounded contours remain exclusively owned by the native nine-slice.
    local gradient=parent:CreateTexture(nil,"BACKGROUND",nil,1)
    gradient:SetColorTexture(1,1,1,1)
    M.Point(gradient,"TOPLEFT",inset or 0,-(inset or 0)); M.Point(gradient,"BOTTOMRIGHT",-(inset or 0),inset or 0)
    self:Bind(function()
        if gradient.SetGradient and CreateColor then
            gradient:SetGradient(orientation,CreateColor(self:Color(fromKey,fromAlpha)),CreateColor(self:Color(toKey,toAlpha)))
        else gradient:SetVertexColor(self:Color(fromKey,fromAlpha)) end
    end,gradient)
    return gradient
end
-- Brand artwork keeps its authored colors; unlike semantic icons it never
-- participates in palette tinting. Textures are intrinsically mouse-transparent.
function Factory:Logo(parent,size)
    local logo=parent:CreateTexture(nil,"ARTWORK")
    logo:SetTexture((size or 32)<=32 and DesignSystem.smallLogoTexture or DesignSystem.logoTexture); logo:SetVertexColor(1,1,1,1)
    M.Size(logo,size or 32,size or 32)
    return logo
end
function Factory:Rule(parent,color)
    local rule=parent:CreateTexture(nil,"ARTWORK"); M.Height(rule,1)
    self:Bind(function() rule:SetColorTexture(self:Color(color or "edge",.28)) end,rule)
    return rule
end
local icons={
    clock={lines={{8,4,8,8},{8,8,11,10}},circles={{8,8,6}}},
    close={{3,3,13,13},{3,13,13,3}}, minus={{3,8,13,8}}, plus={{3,8,13,8},{8,3,8,13}},
    max={{3,3,13,3},{13,3,13,13},{13,13,3,13},{3,13,3,3}},
    restore={{2,5,11,5},{11,5,11,14},{11,14,2,14},{2,14,2,5},{5,2,14,2},{14,2,14,11}},
    save={{2,2,12,2},{12,2,14,4},{14,4,14,14},{14,14,2,14},{2,14,2,2},{5,2,5,6},{5,6,11,6},{11,6,11,2},{5,14,5,9},{5,9,11,9},{11,9,11,14}},
    check={{3,8,6.5,11.5},{6.5,11.5,13,4}}, chevron={{4,6,8,10},{8,10,12,6}},
    spark={{8,1,10,6},{10,6,15,8},{15,8,10,10},{10,10,8,15},{8,15,6,10},{6,10,1,8},{1,8,6,6},{6,6,8,1}},
    grid={{2,2,6,2},{6,2,6,6},{6,6,2,6},{2,6,2,2},{10,2,14,2},{14,2,14,6},{14,6,10,6},{10,6,10,2},{2,10,6,10},{6,10,6,14},{6,14,2,14},{2,14,2,10},{10,10,14,10},{14,10,14,14},{14,14,10,14},{10,14,10,10}},
    play={{4,2,13,8},{13,8,4,14},{4,14,4,2}}, search={{11,11,15,15},{3,2,8,2},{8,2,11,5},{11,5,11,8},{11,8,8,11},{8,11,3,11},{3,11,1,8},{1,8,1,5},{1,5,3,2}},
    info={lines={{8,22/3,8,34/3}},circles={{8,8,6}},dots={{8,14/3,2.4}}},
    tree={{3,3,3,12},{3,7,12,7},{3,12,12,12}},
    folder={{2,4,7,4},{7,4,9,6},{9,6,14,6},{14,6,14,13},{14,13,2,13},{2,13,2,4}},
    right={{6,4,10,8},{10,8,6,12}},
    undo={{6,3,2,7},{2,7,6,11},{2,7,10,7},{10,7,13,10},{13,10,13,13}},
    fit={{2,6,2,2},{2,2,6,2},{10,2,14,2},{14,2,14,6},{14,10,14,14},{14,14,10,14},{6,14,2,14},{2,14,2,10}},
    edit={{3,10,10,3},{10,3,13,6},{13,6,6,13},{6,13,2,14},{2,14,3,10}},
    -- "search" also serves the item browse button (Lucide glyph when bundled).
    gear={lines={{12.8,8,15,8},{3.2,8,1,8},{8,12.8,8,15},{8,3.2,8,1},{11.4,11.4,13,13},{4.6,11.4,3,13},{4.6,4.6,3,3},{11.4,4.6,13,3}},circles={{8,8,4.6},{8,8,1.8}}},
    sliders={{2,4,5,4},{9,4,14,4},{2,12,8,12},{12,12,14,12},{5,2,9,2},{9,2,9,6},{9,6,5,6},{5,6,5,2},{8,10,12,10},{12,10,12,14},{12,14,8,14},{8,14,8,10}},
}
DesignSystem.categories={sources={label="Sources",icon="spark"},time={label="Time",icon="clock"},logic={label="Logic",icon="tree"},
    math={label="Values / Math",icon="plus"},media={label="Media",icon="grid"},modifiers={label="Modifiers",icon="sliders"},outputs={label="Outputs",icon="play"},
    triggers={label="Triggers",icon="spark"},memory={label="Memory",icon="folder"},notes={label="Notes",icon="edit"}}
DesignSystem.categoryOrder={"sources","triggers","time","logic","math","memory","media","modifiers","outputs","notes"}
function DesignSystem.NodeCategory(kind,def)
    if def.category and DesignSystem.categories[def.category] then return def.category end
    if kind=="array" or kind=="memory_output" or kind=="memory" or def.memoryOperation then return "memory" end
    if ({media_icon=true,media_text=true,media_graphic=true,media_font=true,media_style=true,media_bar=true,bar_duration=true})[kind] then return "media" end
    if def.display or def.sink then return "outputs" end
    if def.flowOperation=="timestamp" or def.flowOperation=="debounce" then return "time" end
    if def.nativeEvent or kind=="frame_state" or kind=="media_event" or kind=="message_receive" or kind=="chat_receive" then return "triggers" end
    if def.clock or ({timer=true,remaining_estimate=true,interval=true})[kind] then return "time" end
    if def.logic or kind=="logic" or kind:find("logic_",1,true) or ({gate=true,is_nil=true,secret=true,compare=true})[kind] then return "logic" end
    if ({math=true,multiply=true,format=true,format_values=true,parse=true,number=true,boolean=true,constant_nil=true})[kind] then return "math" end
    if kind=="animation" then return "modifiers" end
    if def.bypass or ({circle=true,rotate_offset=true})[kind] then return "modifiers" end
    return "sources"
end
function Factory:Icon(parent,name,size,color)
    local icon=CreateFrame("Frame",nil,parent); M.Size(icon,size or 16,size or 16)
    icon:EnableMouse(false); icon.lines={}; icon.circles={}; icon.dots={}
    -- Lucide graphic when available (a UI name or, since all of Lucide is in
    -- the atlas, any Lucide name); the line drawing stays as fallback.
    local symbol=ns.Symbols and (ns.Symbols:UIName(name) or (ns.Symbols:Valid(name) and name))
    if symbol then
        local path,l,r,t,b=ns.Symbols:Coords(symbol,M.ToNative(size or 16))
        local glyph=icon:CreateTexture(nil,"OVERLAY")
        local ok,loaded=pcall(glyph.SetTexture,glyph,path)
        if ok and loaded~=false then
            glyph:SetAllPoints(icon);glyph:SetTexCoord(l,r,t,b);icon.glyph=glyph;icon.symbol=symbol
            function icon:SetColor(...) self.glyph:SetVertexColor(...) end
            self:Bind(function() icon:SetColor(self:Color(icon.colorRole or color or "accent")) end,icon)
            return icon
        end
        glyph:Hide()
    end
    local definition=icons[name] or icons.spark
    local function addLine(p,collection)
        local line=icon:CreateLine(nil,"OVERLAY"); M.Thickness(line,1.4)
        M.LineStart(line,"TOPLEFT",icon,p[1]*(size or 16)/16,-p[2]*(size or 16)/16)
        M.LineEnd(line,"TOPLEFT",icon,p[3]*(size or 16)/16,-p[4]*(size or 16)/16)
        local target=collection or icon.lines
        target[#target+1]=line
    end
    for _,p in ipairs(definition.lines or definition) do addLine(p) end
    for _,circle in ipairs(definition.circles or {}) do
        local ring=icon:CreateTexture(nil,"OVERLAY")
        ring:SetTexture(media.."DesignLab\\radio-ring.tga")
        local diameter=(circle[3]*2+1.4)*(size or 16)/16
        M.Size(ring,diameter,diameter)
        M.Point(ring,"CENTER",icon,"TOPLEFT",circle[1]*(size or 16)/16,-circle[2]*(size or 16)/16)
        icon.circles[#icon.circles+1]=ring
    end
    -- Points are area primitives: a tiny Line is not a reliable native dot.
    for _,point in ipairs(definition.dots or {}) do
        local dot=icon:CreateTexture(nil,"OVERLAY")
        dot:SetTexture(media.."DesignLab\\radio-dot.tga")
        M.Size(dot,point[3]*(size or 16)/16,point[3]*(size or 16)/16)
        M.Point(dot,"CENTER",icon,"TOPLEFT",point[1]*(size or 16)/16,-point[2]*(size or 16)/16)
        icon.dots[#icon.dots+1]=dot
    end
    function icon:SetColor(...)
        for _,line in ipairs(self.lines) do line:SetColorTexture(...) end
        for _,ring in ipairs(self.circles) do ring:SetVertexColor(...) end
        for _,dot in ipairs(self.dots) do dot:SetVertexColor(...) end
    end
    self:Bind(function() icon:SetColor(self:Color(icon.colorRole or color or "accent")) end,icon)
    return icon
end

-- Grid lives on the canvas itself, below child cards/wires. No input surface
-- and no timer: redraw only when the viewport transform actually changes.
function Factory:CanvasGrid(canvas)
    local grid={lines={},style=self}
    canvas.surfacePaintOwned=true
    self:Bind(function()
        local r,g,b=self:Color("bg")
        canvas:PaintSurface({r*.62,g*.62,b*.62,1},{self:Color("edge",.4)},1)
        for _,line in ipairs(grid.lines) do line:SetColorTexture(self:Color("edge",line.major and .22 or .09)) end
    end,canvas)
    function grid:Update(width,height,panX,panY,zoom)
        local key=table.concat({width,height,panX,panY,zoom},":")
        if key==self.key then return end; self.key=key
        local step=32*zoom; while step<18 do step=step*2 end
        local index=0
        local function axis(length,offset,vertical)
            local first=math.ceil((1-offset)/step); local last=math.floor((length-1-offset)/step)
            for n=first,last do
                index=index+1; if index>512 then return end
                local line=self.lines[index]
                if not line then line=canvas:CreateTexture(nil,"ARTWORK",nil,-1); self.lines[index]=line end
                line.major=n%4==0; line:ClearAllPoints()
                local position=offset+n*step
                M.Point(line,"TOPLEFT",canvas,"TOPLEFT",vertical and position or 1,vertical and -1 or -position)
                M.Size(line,vertical and .7 or width-2,vertical and height-2 or .7)
                line:SetColorTexture(self.style:Color("edge",line.major and .22 or .09)); line:Show()
            end
        end
        axis(width,panX,true); axis(height,panY,false)
        for i=index+1,#self.lines do self.lines[i]:Hide() end
    end
    return grid
end
function Factory:Tooltip(control,title,body)
    control.tooltipTitle,control.tooltipBody=title,body
    if control.tooltipHooked then return end
    control.tooltipHooked=true
    local function show()
        if control.IsEnabled and not control:IsEnabled() then return end
        if not control.tooltipTitle and not control.tooltipBody and not control.labelTruncated then return end
        local full=control.fullLabel or ""
        local heading=control.tooltipTitle or "Full label"
        local copy=control.tooltipBody or ""
        if full~="" and (full~=heading or control.labelTruncated) then copy=full..(copy~="" and "\n\n"..copy or "") end
        if heading~="" then self.owner:ShowTooltip(control,heading,copy) end
    end
    -- tooltipDelay (seconds): settings rows explain themselves only after the
    -- pointer rests on them, so moving across a page stays quiet.
    local function cancel() if control.tooltipTimer then control.tooltipTimer:Cancel();control.tooltipTimer=nil end end
    control:HookScript("OnEnter",function()
        cancel()
        if control.tooltipDelay and C_Timer then
            control.tooltipTimer=C_Timer.NewTimer(control.tooltipDelay,function() control.tooltipTimer=nil;show() end)
        else show() end
    end)
    control:HookScript("OnLeave",function() cancel();self.owner:HideTooltip() end)
    control:HookScript("OnHide",function() cancel();self.owner:HideTooltip() end)
end
function Factory:Button(parent,text,width,callback,kind)
    local button=CreateFrame("Button",nil,parent); M.Size(button,width or 112,32)
    self:Skin(button,"raised",4)
    button.kind=kind or "secondary"
    button.label=self:Label(button,text,kind=="nav" and 13 or 14,false,kind=="primary" and "bold" or "regular")
    button.label:SetWordWrap(false); button.label:SetDrawLayer("OVERLAY",7)
    if button.label.SetMaxLines then button.label:SetMaxLines(1) end
    button.label:SetJustifyV("MIDDLE")
    local left,right,alignment=8,8,"CENTER"
    local fitLabel
    local function labelGeometry()
        button.label:ClearAllPoints(); M.Point(button.label,"CENTER",(left-right)/2,0)
        M.Size(button.label,math.max(1,M.GetWidth(button)-left-right),math.max(1,M.GetHeight(button)-2))
        button.label:SetJustifyH(alignment)
        if fitLabel then fitLabel() end
    end
    fitLabel=function()
        local label=button.label
        local current=label:GetText() or ""
        if current~=button.renderedLabel then button.fullLabel=current end
        local full=button.fullLabel or ""
        local width=M.GetWidth(label)
        local function measure(candidate)
            if label.GetUnboundedStringWidthForText then return M.ToDesign(label:GetUnboundedStringWidthForText(candidate)) end
            label:SetText(candidate)
            return M.ToDesign(label:GetUnboundedStringWidth())
        end
        local display=full
        button.labelTruncated=false
        if label.GetUnboundedStringWidthForText or label.GetUnboundedStringWidth then
            if measure(full)>width then
                button.labelTruncated=true
                local characters,index={},1
                -- Cut only at UTF-8 character boundaries (including localized labels).
                while index<=#full do
                    local byte=full:byte(index)
                    local count=byte>=240 and 4 or byte>=224 and 3 or byte>=192 and 2 or 1
                    characters[#characters+1]=full:sub(index,index+count-1); index=index+count
                end
                local first,last,best=0,#characters,""
                while first<=last do
                    local middle=math.floor((first+last)/2)
                    local candidate=table.concat(characters,"",1,middle).."…"
                    if measure(candidate)<=width then best=candidate; first=middle+1 else last=middle-1 end
                end
                display=best
            end
        end
        label:SetText(display); button.renderedLabel=display
    end
    button.label.bvAfterFont=fitLabel
    function button:SetLabelText(value)
        self.fullLabel=tostring(value or ""); self.renderedLabel=nil
        self.label:SetText(self.fullLabel); fitLabel()
    end
    -- The label is our own font string, not the button's: SetText and
    -- GetText go to it (Florian 2026-10-09: the tracker kept "Start" while
    -- running, the editor's Area button never said "Finish").
    function button:SetText(value) self:SetLabelText(value) end
    function button:GetText() return self.fullLabel or "" end
    function button:SetLabelInsets(first,last,justify)
        left,right,alignment=first or 8,last or 8,justify or "CENTER"; labelGeometry()
    end
    button:SetScript("OnSizeChanged",labelGeometry); labelGeometry()
    if kind=="nav" then button:SetLabelInsets(36,8,"LEFT") end
    if kind=="nav" or kind=="tab" then
        button.selection=button:CreateTexture(nil,"ARTWORK")
        if kind=="nav" then
            M.Width(button.selection,2); M.Point(button.selection,"TOPLEFT",0,-5); M.Point(button.selection,"BOTTOMLEFT",0,5)
        else M.Height(button.selection,2); M.Point(button.selection,"BOTTOMLEFT"); M.Point(button.selection,"BOTTOMRIGHT") end
    end
    local function render()
        fitLabel()
        local kind=button.presentationKind or kind
        local primary=kind=="primary" or (button.selected and kind~="nav" and kind~="tab" and kind~="menu")
        local fill,fillAlpha,edge,edgeAlpha,textColor="raised",.7,"edge",.4,"text"
        if kind=="resize" then fill,fillAlpha,edge,edgeAlpha,textColor=button.hovered and "text" or "accent",1,"bg",1,"bg"
        elseif primary then fill,fillAlpha,edge,edgeAlpha,textColor="accent",1,"accent",.65,"bg"
        elseif kind=="nav" then
            fill,fillAlpha="accent",button.selected and .14 or button.hovered and .07 or 0
            edge,edgeAlpha="accent",button.selected and .18 or 0
            textColor=button.selected and "text" or button.hovered and "text" or "muted"
        elseif kind=="tab" then
            fillAlpha,edgeAlpha=0,0; textColor=button.selected and "text" or button.hovered and "accent" or "muted"
        elseif kind=="menu" then
            -- Menu entries (0.8.73): flat rows, hover band, current value in accent.
            fill,fillAlpha,edgeAlpha="accent",button.hovered and .16 or button.selected and .07 or 0,0
            textColor=button.danger and "danger" or button.selected and "accent" or "text"
        elseif kind=="window" or kind=="ghost" then
            fillAlpha=button.hovered and .35 or 0; edgeAlpha=kind=="window" and button.hovered and .25 or 0
            textColor=button.hovered and "text" or "muted"
        elseif kind=="danger" then fill,fillAlpha,edge,edgeAlpha,textColor="danger",.045,"danger",.25,"danger"
        elseif button.hovered then fill,fillAlpha,edge,edgeAlpha="accent",.13,"accent",.48 end
        button:PaintSurface({self:Color(fill)},{self:Color(edge,edgeAlpha)},fillAlpha)
        button.label:SetTextColor(self:Color(textColor))
        if button.icon then button.icon.colorRole=textColor; button.icon:SetColor(self:Color(textColor)) end
        if button.selection then button.selection:SetColorTexture(self:Color("accent")); button.selection:SetShown(button.selected==true) end
        button:SetAlpha(button:IsEnabled() and 1 or .4)
    end
    self:Bind(render,button)
    button:SetScript("OnEnter",function() button.hovered=true; render() end)
    button:SetScript("OnLeave",function() button.hovered=false; render() end)
    button:SetScript("OnHide",function() button.hovered=false; render() end)
    button:SetScript("OnShow",render)
    button:SetScript("OnEnable",render); button:SetScript("OnDisable",render)
    button:SetScript("OnMouseDown",function() if button:IsEnabled() then button:SetAlpha(.8) end end)
    button:SetScript("OnMouseUp",render)
    button:SetScript("OnClick",function() if callback then callback(button) end end)
    function button:SetSelected(value) self.selected=value; render() end
    self:Tooltip(button)
    return button
end
function Factory:IconButton(parent,name,callback,kind)
    local button=self:Button(parent,"",32,callback,kind)
    button.icon=self:Icon(button,name,16,"text"); M.Point(button.icon,"CENTER")
    return button
end
function Factory:Input(parent,width,multiline,initial,changed,bare)
    local box=CreateFrame("EditBox",nil,parent); M.Size(box,width or 240,multiline and 72 or 32)
    if not bare then self:Skin(box,"bg",4,.85) end
    self:Font(box,14)
    box:SetAutoFocus(false); box:SetMaxLetters(multiline and 400 or 64)
    box:SetMultiLine(multiline==true); M.TextInsets(box,10,10,multiline and 9 or 0,multiline and 9 or 0)
    box:SetJustifyH("LEFT"); box:SetJustifyV(multiline and "TOP" or "MIDDLE")
    box:SetText(initial or "")
    local function paint()
        if not bare then box:PaintSurface({self:Color("bg")},{self:Color(box.invalid and "danger" or box.focused and "accent" or "edge",.7)},.85) end
        box:SetTextColor(self:Color("text"))
    end
    self:Bind(function() self:Font(box,14); paint() end,box)
    box:SetScript("OnEditFocusGained",function() box.focused=true; paint() end)
    box:SetScript("OnEditFocusLost",function() box.focused=false; paint() end)
    box:SetScript("OnEscapePressed",function() box:ClearFocus() end)
    if not multiline then box:SetScript("OnEnterPressed",function() box:ClearFocus() end) end
    box:SetScript("OnHide",function() box:ClearFocus() end)
    box:SetScript("OnTextChanged",function(_,user) if changed and user then changed(box:GetText(),box) end end)
    function box:SetInvalid(value) self.invalid=value; paint() end
    if not self.registerPaint then self.edits[#self.edits+1]=box end
    return box
end
function Factory:Slider(parent,width,min,max,step,value,changed)
    local slider=CreateFrame("Slider",nil,parent); M.Size(slider,width or 160,24)
    slider:SetOrientation("HORIZONTAL"); slider:SetMinMaxValues(min,max); slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.track=slider:CreateTexture(nil,"BACKGROUND"); M.Point(slider.track,"LEFT",0,0); M.Point(slider.track,"RIGHT",0,0); M.Height(slider.track,4)
    slider:SetThumbTexture(media.."DesignLab\\surface.tga")
    M.Size(slider:GetThumbTexture(),10,16)
    self:Bind(function() slider.track:SetColorTexture(self:Color("edge",.45)); slider:GetThumbTexture():SetVertexColor(self:Color("accent")) end,slider)
    slider:SetValue(value)
    slider:SetScript("OnValueChanged",function(_,v) if changed then changed(v) end end)
    return slider
end
function Factory:Check(parent,text,value,changed,radio)
    local control=CreateFrame("Button",nil,parent); M.Size(control,160,28)
    control.label=self:Label(control,text,14,"text"); M.Point(control.label,"LEFT",26,0)
    M.Point(control.label,"RIGHT",-2,0); M.Height(control.label,28)
    control.mark=CreateFrame("Frame",nil,control); M.Size(control.mark,16,16); M.Point(control.mark,"LEFT",0,0)
    if radio then
        control.ring={}
        for i=1,16 do
            local a,b=(i-1)*math.pi/8,i*math.pi/8
            local l=control.mark:CreateLine(nil,"ARTWORK"); M.Thickness(l,1)
            M.LineStart(l,"CENTER",control.mark,7*math.cos(a),7*math.sin(a)); M.LineEnd(l,"CENTER",control.mark,7*math.cos(b),7*math.sin(b))
            control.ring[#control.ring+1]=l
        end
        control.tick=control.mark:CreateTexture(nil,"OVERLAY")
        control.tick:SetTexture(media.."DesignLab\\radio-dot.tga"); M.Size(control.tick,8,8); M.Point(control.tick,"CENTER")
    else self:Skin(control.mark,"bg",3); control.mark.surfacePaintOwned=true; control.tick=self:Icon(control.mark,"check",14,"bg"); M.Point(control.tick,"CENTER") end
    local function render()
        if radio then
            for _,line in ipairs(control.ring) do line:SetColorTexture(self:Color(control.value and "accent" or "edge")) end
            control.tick:SetVertexColor(self:Color("accent"))
        else control.mark:PaintSurface({self:Color(control.value and "accent" or "bg")},{self:Color("edge",.7)},1) end
        control.tick:SetShown(control.value); control:SetAlpha(control:IsEnabled() and 1 or .4)
    end
    function control:SetValue(v) self.value=v==true; render() end
    control:SetValue(value); self:Bind(render,control)
    control:SetScript("OnClick",function() control:SetValue(radio or not control.value); if changed then changed(control.value) end end)
    control:SetScript("OnEnable",render); control:SetScript("OnDisable",render)
    return control
end
function Factory:Switch(parent,value,changed)
    local button=CreateFrame("Button",nil,parent); M.Size(button,36,20); self:Skin(button,"raised",4)
    button.thumb=self:Panel(button,12,12,"muted",3); button.thumb.surfacePaintOwned=true
    local function paint()
        button:SetAlpha(button:IsEnabled() and 1 or .4)
        button:PaintSurface({self:Color(button.value and "accent" or "raised")},{self:Color("edge",.6)},button.value and .22 or 1)
        button.thumb:ClearAllPoints(); M.Point(button.thumb,button.value and "RIGHT" or "LEFT",button.value and -4 or 4,0)
        button.thumb:PaintSurface({self:Color(button.value and "accent" or "muted")},{self:Color(button.value and "accent" or "muted")},1)
    end
    function button:SetValue(v) self.value=v==true; paint() end
    button:SetValue(value); self:Bind(paint,button)
    button:SetScript("OnEnable",paint); button:SetScript("OnDisable",paint)
    button:SetScript("OnClick",function() button:SetValue(not button.value); if changed then changed(button.value) end end)
    return button
end
-- Graph primitives share the same palette and base metrics as all controls.
-- The hit target is deliberately larger than its visible circular port.
function Factory:GraphPort(parent,options)
    options=options or {}
    local port=CreateFrame("Button",nil,parent); M.Size(port,18,18)
    port:EnableMouse(true); port:RegisterForClicks("LeftButtonUp","RightButtonUp")
    port.halo=port:CreateTexture(nil,"ARTWORK")
    port.halo:SetTexture(media.."DesignLab\\radio-dot.tga"); M.Size(port.halo,14,14); M.Point(port.halo,"CENTER")
    port.dot=port:CreateTexture(nil,"OVERLAY")
    port.dot:SetTexture(media.."DesignLab\\radio-dot.tga"); M.Size(port.dot,8,8); M.Point(port.dot,"CENTER")
    local function paint()
        local emphasis=port.hovered or port.selected or port.compatible==true
        local signal=DesignSystem.signals[port.signal] or DesignSystem.signals.unavailable
        local color=port.compatible==false and "muted" or port.signal and signal.color or (options.color or "accent")
        port.dot:SetVertexColor(self:Color(color,port.compatible==false and .4 or (port.connected or emphasis) and 1 or .8))
        port.halo:SetVertexColor(self:Color(color,emphasis and .22 or port.connected and .12 or .055))
        port:SetAlpha(port:IsEnabled() and 1 or .35)
    end
    function port:SetSelected(value) self.selected=value==true; paint() end
    function port:SetConnected(value) self.connected=value==true; paint() end
    function port:SetCompatible(value) self.compatible=value; paint() end
    function port:SetSignal(value) if self.signal~=value then self.signal=value; paint() end end
    port:SetScript("OnEnter",function() port.hovered=true; paint() end)
    port:SetScript("OnLeave",function() port.hovered=false; paint() end)
    port:SetScript("OnHide",function() port.hovered=false; paint() end)
    port:SetScript("OnEnable",paint); port:SetScript("OnDisable",paint)
    if options.onClick then port:SetScript("OnClick",options.onClick) end
    self:Bind(paint,port)
    return port
end
-- Native world-space grip: a simple vector arrow stays legible without a font
-- glyph or the label insets of a full-size button. Geometry is deliberately 14px.
function Factory:ResizeGrip(parent)
    local grip=self:Button(parent,"",24,nil,"resize");grip:SetSize(14,14);grip.label:Hide()
    grip.arrow={}
    for i=1,5 do
        local line=grip:CreateLine(nil,"OVERLAY");line:SetThickness(1.5);grip.arrow[i]=line
    end
    function grip:SetDirection(sx,sy)
        local diagonal=sx*sy
        if self.diagonal==diagonal then return end
        self.diagonal=diagonal
        local segments={{-3,-3,3,3},{-3,-3,-3,0},{-3,-3,0,-3},{3,3,3,0},{3,3,0,3}}
        for i,p in ipairs(segments)do
            self.arrow[i]:SetStartPoint("CENTER",self,p[1],p[2]*diagonal)
            self.arrow[i]:SetEndPoint("CENTER",self,p[3],p[4]*diagonal)
        end
    end
    self:Bind(function()for _,line in ipairs(grip.arrow)do line:SetColorTexture(self:Color("bg"))end end,grip)
    grip:SetDirection(1,-1)
    return grip
end
-- Single-line native-unit captions, including UTF-8-safe ellipsis.
function Factory:FitCaption(label,text,width)
    text=text:gsub("[\r\n\t]+"," ")
    label:SetWordWrap(false);label:SetWidth(math.max(1,width));label:SetText(text)
    local natural=label:GetUnboundedStringWidth()
    if natural<=width then return natural end
    local chars,index={},1
    while index<=#text do
        local byte=text:byte(index);local count=byte>=240 and 4 or byte>=224 and 3 or byte>=192 and 2 or 1
        chars[#chars+1]=text:sub(index,index+count-1);index=index+count
    end
    local first,last,best=0,#chars,""
    while first<=last do
        local middle=math.floor((first+last)/2)
        local candidate=table.concat(chars,"",1,middle).."…";label:SetText(candidate)
        if label:GetUnboundedStringWidth()<=width then best=candidate;first=middle+1 else last=middle-1 end
    end
    label:SetText(best);return natural
end
function Factory:GraphLegend(parent)
    local frame=CreateFrame("Frame",nil,parent); frame.items={}
    for _,key in ipairs({"pending","conditional","readable","protected","unavailable","faulted"}) do
        local info=DesignSystem.signals[key]; local item=CreateFrame("Frame",nil,frame)
        item.port=self:GraphPort(item); item.port:SetSignal(key); item.port:EnableMouse(false); M.Point(item.port,"LEFT",item,"LEFT",0,0)
        item.label=self:Label(item,info.label,10,info.color); M.Point(item.label,"LEFT",item,"LEFT",20,0); item.label:SetWordWrap(false)
        item:EnableMouse(true); ns.UI:AttachTooltip(item,info.label,info.help)
        item.designWidth=({pending=100,conditional=128,readable=100,protected=78,unavailable=100,faulted=72})[key]
        M.Size(item,item.designWidth,20); frame.items[#frame.items+1]=item
    end
    function frame:Arrange(width,compact)
        local x,y=0,0
        for _,item in ipairs(self.items) do
            local itemWidth=compact and 22 or item.designWidth
            item.label:SetShown(not compact); M.Width(item,itemWidth)
            if x>0 and x+itemWidth>width then x=0; y=y+22 end
            item:ClearAllPoints(); M.Point(item,"TOPLEFT",self,"TOPLEFT",x,-y); x=x+itemWidth
        end
        M.Size(self,width,y+22); return y+22
    end
    return frame
end

-- One dialog material/chrome for gallery demonstrations and production tasks.
function Factory:Dialog(parent,width,height,name)
    local dialog=CreateFrame("Frame",name,parent); dialog:Hide(); M.Size(dialog,width,height)
    self:Skin(dialog,"panel",8,nil,true); dialog:EnableMouse(true)
    dialog.isDialog=true
    dialog.title=self:Label(dialog,"",16,"text","bold"); M.Point(dialog.title,"TOPLEFT",18,-10); dialog.title:SetWordWrap(false)
    dialog.close=self:IconButton(dialog,"close",function() dialog:Hide() end,"ghost"); M.Point(dialog.close,"TOPRIGHT",-8,-4)
    dialog.rule=self:Rule(dialog); M.Point(dialog.rule,"TOPLEFT",1,-36); M.Point(dialog.rule,"TOPRIGHT",-1,-36)
    dialog.content=CreateFrame("Frame",nil,dialog); M.Point(dialog.content,"TOPLEFT",0,-36); M.Point(dialog.content,"BOTTOMRIGHT",0,0)
    dialog:HookScript("OnSizeChanged",function() M.Size(dialog.title,math.max(1,M.GetWidth(dialog)-72),22) end)
    M.Size(dialog.title,width-72,22)
    return dialog
end

-- A cubic Bezier is approximated only when its endpoints change. Flatness-based
-- subdivision is bounded at 32 segments; old native Lines are reused and hidden.
function Factory:GraphWire(parent,color)
    local wire=CreateFrame("Frame",nil,parent); wire:SetAllPoints(parent); wire:EnableMouse(false)
    wire:SetFrameLevel(parent:GetFrameLevel()); wire.segments={}; wire.segmentCount=0
    local function paint()
        local rgba=wire.color or {self:Color(color or "accent",.9)}
        for _,line in ipairs(wire.segments) do line:SetColorTexture(unpack(rgba)) end
    end
    function wire:SetColor(...) self.color={...}; paint() end
    function wire:ClearColor() self.color=nil; paint() end
    function wire:SetEndpoints(x1,y1,x2,y2,zoom)
        zoom=zoom or 1
        for _,value in ipairs({x1,y1,x2,y2,zoom}) do
            assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Invalid graph wire geometry")
        end
        assert(zoom>0,"Invalid graph wire zoom")
        local previous=self.endpoints
        if previous and previous[1]==x1 and previous[2]==y1 and previous[3]==x2 and previous[4]==y2 and previous[5]==zoom then return end
        self.endpoints={x1,y1,x2,y2,zoom}
        local handle=math.max(32,math.min(240,math.abs(x2-x1)*.5))
        self.controlPoints={x1,y1,x1+handle,y1,x2-handle,y2,x2,y2}
        local points={{x=x1,y=y1,t=0}}
        local tolerance=.65/M.ToNative(zoom)
        local function distance(px,py,ax,ay,bx,by)
            local dx,dy=bx-ax,by-ay
            local length=math.sqrt(dx*dx+dy*dy)
            if length<.0001 then return math.sqrt((px-ax)^2+(py-ay)^2) end
            return math.abs(dy*px-dx*py+bx*ay-by*ax)/length
        end
        local function leaf(ax,ay,bx,by,cx,cy,dx,dy,first,last)
            local chord=math.sqrt((dx-ax)^2+(dy-ay)^2)
            local polygon=math.sqrt((bx-ax)^2+(by-ay)^2)+math.sqrt((cx-bx)^2+(cy-by)^2)+math.sqrt((dx-cx)^2+(dy-cy)^2)
            local error=math.max(distance(bx,by,ax,ay,dx,dy),distance(cx,cy,ax,ay,dx,dy),polygon-chord)
            return {ax,ay,bx,by,cx,cy,dx,dy,first,last,error}
        end
        if x1~=x2 or y1~=y2 then
            local leaves={leaf(x1,y1,x1+handle,y1,x2-handle,y2,x2,y2,0,1)}
            -- Spend the bounded segment budget where curvature needs it most,
            -- rather than imposing the same subdivision depth on every region.
            while #leaves<32 do
                local worst,error=nil,tolerance
                for index,item in ipairs(leaves) do if item[11]>error then worst,error=index,item[11] end end
                if not worst then break end
                local p=leaves[worst]
                local abx,aby,bcx,bcy,cdx,cdy=(p[1]+p[3])/2,(p[2]+p[4])/2,(p[3]+p[5])/2,(p[4]+p[6])/2,(p[5]+p[7])/2,(p[6]+p[8])/2
                local ex,ey,fx,fy=(abx+bcx)/2,(aby+bcy)/2,(bcx+cdx)/2,(bcy+cdy)/2
                local mx,my,mid=(ex+fx)/2,(ey+fy)/2,(p[9]+p[10])/2
                leaves[worst]=leaf(p[1],p[2],abx,aby,ex,ey,mx,my,p[9],mid)
                table.insert(leaves,worst+1,leaf(mx,my,fx,fy,cdx,cdy,p[7],p[8],mid,p[10]))
            end
            for _,item in ipairs(leaves) do points[#points+1]={x=item[7],y=item[8],t=item[10]} end
        end
        self.points=points; self.segmentCount=0; self.zoom=zoom
        for index=1,#points-1 do
            local start,finish=points[index],points[index+1]
            if math.abs(start.x-finish.x)+math.abs(start.y-finish.y)>.000001 then
                self.segmentCount=self.segmentCount+1
                local line=self.segments[self.segmentCount]
                if not line then line=self:CreateLine(nil,"BACKGROUND"); self.segments[self.segmentCount]=line end
                M.Thickness(line,1.5*zoom)
                M.LineStart(line,"TOPLEFT",self,start.x*zoom,-start.y*zoom)
                M.LineEnd(line,"TOPLEFT",self,finish.x*zoom,-finish.y*zoom)
                line:Show()
            end
        end
        for index=self.segmentCount+1,#self.segments do self.segments[index]:Hide() end
        paint()
    end
    self:Bind(paint,wire)
    return wire
end

function Factory:Dropdown(parent,width,options,value,changed)
    local button=self:Button(parent,"",width,function(control) self.owner:ShowDropdown(control) end)
    button.options,button.changed=options,changed
    -- Its list opens in the same style (in-game style families, 0.8.95).
    button.bvStyle=self
    button:SetLabelInsets(10,28,"LEFT")
    button.arrow=self:Icon(button,"chevron",12,"muted"); M.Point(button.arrow,"RIGHT",-9,0)
    function button:SetValue(v)
        self.value=v
        for _,option in ipairs(self.options) do if option.value==v then self:SetLabelText(option.label); break end end
    end
    button:SetValue(value)
    return button
end

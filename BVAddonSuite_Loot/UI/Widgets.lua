local _,L=...
if not L.ready then return end
-- Shared view parts: movable stack anchors (Layout Editor elements), item
-- tooltips with the integration info tip, and the small option buttons.
local ns=L.ns
local UI,Theme,D=ns.UI,ns.Theme,ns.DesignSystem.Metrics
local W={}
L.Widgets=W

local function owned(frame) if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(frame) end;return frame end
W.Owned=owned

-- One captured Interface style and one passive material carrier per view.
-- Fade animations belong to the outer host; opacity never affects content.
function W:Style()
    local style=ns.Config and ns.Config:EnsureShellStyle()
    return style and style.materialProfile=="interface" and style or nil
end
function W:Surface(parent,width,height,group,style)
    local f=owned(CreateFrame("Frame",nil,parent));D.Size(f,width,height)
    f.bvStyle=style;f.bvTooltipStyle=style;f.lootSurfaceGroup=group
    f.materialCarrier=CreateFrame("Frame",nil,f);f.materialCarrier:SetAllPoints(f);f.materialCarrier:EnableMouse(false)
    f.material=UI:WithStyle(style,UI.Panel,UI,f.materialCarrier,width,height,"dialog",4,1)
    f.material:SetAllPoints(f.materialCarrier);f.material:EnableMouse(false)
    if group~="tooltip" and ns.InterfaceSurfaces and ns.InterfaceSurfaces.AttachHUD then ns.InterfaceSurfaces:AttachHUD(style,f.material) end
    f.content=CreateFrame("Frame",nil,f);f.content:SetAllPoints(f);f.content:EnableMouse(false)
    f.content:SetFrameLevel(f.material:GetFrameLevel()+1);f.content.bvTooltipStyle=style;f.content.bvStyle=style
    f.qualitySeam=f.material:CreateTexture(nil,"OVERLAY");f.qualitySeam:SetTexture("Interface\\Buttons\\WHITE8X8")
    D.Point(f.qualitySeam,"TOPLEFT",f.material,"TOPLEFT",0,0);D.Point(f.qualitySeam,"BOTTOMLEFT",f.material,"BOTTOMLEFT",0,0);D.Width(f.qualitySeam,4)
    if f.qualitySeam.SetSnapToPixelGrid then f.qualitySeam:SetSnapToPixelGrid(false)end
    if f.qualitySeam.SetTexelSnappingBias then f.qualitySeam:SetTexelSnappingBias(0)end
    style:Bind(function() W:PaintSurface(f) end,f)
    W:PaintSurface(f)
    return f
end
function W:PaintSurface(f)
    if not f.materialCarrier then return end
    local cfg=L:Config();local roll=f.lootSurfaceGroup=="roll"
    local on=roll and cfg.rollBackground or not roll and cfg.panelBackground
    local opacity=(roll and cfg.rollBgOpacity or cfg.panelOpacity)/100
    local own=roll and cfg.rollBgOwnColor or not roll and cfg.panelBgOwnColor
    if f.lootSurfaceGroup=="tooltip" then on=true;opacity=1;own=false end
    local r,g,b,a=f.bvStyle:Color("bg")
    a=1
    if own then r,g,b,a=UI:RGBA(roll and cfg.rollBgColor or cfg.panelBgColor)end
    -- Synchronize the passive carrier before its size-dependent slice paint.
    f.material:SetSize(math.max(1,f:GetWidth()),math.max(1,f:GetHeight()))
    f.material:PaintSurface({r,g,b,1},nil,1)
    f.materialCarrier:SetAlpha(on and opacity*(a or 1) or 0)
    f.qualitySeam:SetShown(f.lootQuality~=nil)
    if f.lootQuality then f.qualitySeam:SetVertexColor(unpack(f.lootQuality))end
end
function W:Quality(f,r,g,b)
    if not f.materialCarrier then return end
    f.lootQuality={r,g,b,1};W:PaintSurface(f)
end
function W:Label(style,...)
    if not style then return UI:GameLabel(L.ID,...)end
    local label=UI:WithStyle(style,UI.Label,UI,...)
    style:Bind(function()if label.bvLootRole then label:SetTextColor(style:Color(label.bvLootRole))elseif label.bvLootColor then label:SetTextColor(unpack(label.bvLootColor))end end,label)
    return label
end
-- Keep the model name intact; re-fit only the displayed caption in native units.
function W:Caption(style,label,text)
    if not style then label:SetText(text);return end
    label.bvLootCaption=text
    if not label.bvLootCaptionFit then
        local previous=label.bvAfterFont
        label.bvLootCaptionFit=function()
            style:FitCaption(label,label.bvLootCaption or "",label:GetWidth())
        end
        label.bvAfterFont=function()if previous then previous()end;label.bvLootCaptionFit()end
    end
    label.bvLootCaptionFit()
end
function W:RememberColors(...)
    for i=1,select("#",...) do local label=select(i,...);label.bvLootColor={label:GetTextColor()}end
end


-- A stack anchor is one Layout Editor element. Its rectangle holds the first
-- entry; further entries continue in the grow direction. Width = entry width.
function W:Anchor(def)
    local anchor={def=def,items={}}
    anchor.frame=owned(CreateFrame("Frame",nil,UIParent))
    anchor.frame:SetFrameStrata(def.strata or "HIGH");anchor.frame:EnableMouse(false)
    anchor.frame:SetSize(1,1);anchor.frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
    function anchor:Width() return self.rect and D.ToDesign(self.rect.width) or def.width() end
    function anchor:Apply(rect)
        self.rect=rect
        local frame=self.frame
        frame:ClearAllPoints();frame:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
        frame:SetSize(math.max(1,rect.width),math.max(1,rect.height))
        if def.resized then def.resized(self:Width()) end
        self:Arrange()
    end
    -- items: frames in stack order (index 1 sits in the anchor rectangle).
    function anchor:Arrange(items)
        self.items=items or self.items
        local grow,spacing=def.grow(),def.spacing()
        local offset=0
        for _,item in ipairs(self.items) do
            item:ClearAllPoints()
            if grow=="DOWN" then D.Point(item,"TOPLEFT",self.frame,"TOPLEFT",0,-offset)
            else D.Point(item,"BOTTOMLEFT",self.frame,"BOTTOMLEFT",0,offset) end
            offset=offset+D.GetHeight(item)+spacing
        end
    end
    ns.Layout:Register(def.layout,{label=def.label,autoHeight=true,
        limits={minWidth=120,maxWidth=1200,minHeight=12,maxHeight=400},
        defaults=function() return {width=D.ToNative(def.width()),height=D.ToNative(def.height()),screen=def.screen,x=def.x,y=def.y} end,
        measure=function(rect) return D.ToNative(def.height()) end,
        apply=function(rect) anchor:Apply(rect) end,
        enabled=function() return L:Active() and def.enabled() end,
        preview=function(value) anchor.preview=value==true;if def.preview then def.preview(anchor.preview) end end})
    return anchor
end
function W:Refresh() if ns.Layout then ns.Layout:Refresh(true) end end

-- Item tooltip plus the integration info tip beside it.
function W:ItemTooltip(owner,context)
    local tip=GameTooltip
    if tip and context.link then
        tip:SetOwner(owner,"ANCHOR_RIGHT")
        -- Roll-specific tooltip first; when the client has nothing for that
        -- roll id (simulation, ended roll) fall back to the item link.
        -- Always the item link (rolls carry GetLootRollItemLink): a roll-id
        -- tooltip stays empty for unknown or simulated ids while the client
        -- still opens its comparison tooltip next to it (0.8.82, Florian).
        local filled=false
        if tip.SetHyperlink then
            pcall(tip.SetHyperlink,tip,context.link)
            filled=tip.NumLines==nil or (tip:NumLines() or 0)>0
        end
        -- Unknown to this client: name and a note, never an empty box.
        if not filled then
            local info=L.Item(context.link)
            local r,g,b=L.QualityColor(info.quality or context.quality or 1)
            tip:SetText(info.name or context.name or (type(context.link)=="string" and context.link:match("%[(.-)%]")) or "?",r,g,b)
            tip:AddLine("No item information from the client for this item.",.7,.7,.7,true)
        end
        if L.debug then L:Print(string.format("tooltip %s: roll=%s lines=%s link=%s",tostring(context.source),tostring(context.rollID),
            tostring(tip.NumLines and tip:NumLines()),tostring(context.link):gsub("|","||"))) end
        if context.extra then for _,line in ipairs(context.extra) do tip:AddLine(line[1],line[2],line[3],line[4],true) end end
        tip:Show()
    end
    self:InfoTip(owner,context)
end
function W:TextTooltip(owner,title,lines)
    local tip=GameTooltip
    if tip then
        tip:SetOwner(owner,"ANCHOR_TOP");tip:SetText(title)
        for _,line in ipairs(lines or {}) do
            if type(line)=="table" then tip:AddLine(line[1],line[2] or 1,line[3] or 1,line[4] or 1,true) else tip:AddLine(line,1,1,1,true) end
        end
        tip:Show()
    else
        local body={}
        for _,line in ipairs(lines or {}) do body[#body+1]=type(line)=="table" and line[1] or line end
        UI:ShowTooltip(owner,title,table.concat(body,"\n"))
    end
end
-- With an owner only that owner's tooltip closes: moving from a bar onto its
-- icon must not close the icon's freshly opened tooltip.
function W:HideTooltip(owner)
    local tip=GameTooltip
    if owner and tip and tip.GetOwner and tip:GetOwner()~=owner then return end
    if tip then tip:Hide() end
    UI:HideTooltip()
    if self.info and (not owner or self.info.bvOwner==owner) then self.info:Hide() end
end
-- Integration sections ("additional tooltip"): only shown when a provider answers.
function W:InfoTip(owner,context)
    local sections=L.Integrations:Sections(context)
    if #sections==0 then if self.info then self.info:Hide() end;return end
    local ownerStyle
    local parent=owner
    while parent and not ownerStyle do ownerStyle=parent.bvStyle;parent=parent.GetParent and parent:GetParent() end
    local captured=ownerStyle and ownerStyle.materialProfile=="interface" and ownerStyle or nil
    local tipStyle=captured or UI:ToolStyle()
    self.infoByStyle=self.infoByStyle or {}
    local tip=self.infoByStyle[tipStyle]
    if self.info and self.info~=tip then self.info:Hide() end
    if not tip then
        tip=owned(UI:WithStyle(tipStyle,UI.Panel,UI,UIParent,240,40,"raised"));tip.bvStyle=captured;self.infoByStyle[tipStyle]=tip
        tip:SetFrameStrata("TOOLTIP");tip:EnableMouse(false);tip:SetClampedToScreen(true)
        tip.rows={}
    end
    self.info=tip
    local y,row=10,0
    local function line(left,right,size,r,g,b,accent)
        row=row+1
        local item=tip.rows[row]
        if not item then
            item={left=tipStyle:Label(tip,"",12,false),right=tipStyle:Label(tip,"",12,false)}
            item.right:SetJustifyH("RIGHT");tip.rows[row]=item
            tipStyle:Bind(function()
                if item.size then tipStyle:Font(item.left,item.size);tipStyle:Font(item.right,item.size) end
                if item.accent then item.left:SetTextColor(tipStyle:Color(captured and "accentText" or "accent")) elseif item.tint then item.left:SetTextColor(unpack(item.tint)) end
                item.right:SetTextColor(1,1,1)
            end,item.left)
        end
        item.size=size;item.accent=accent;item.tint={r or 1,g or 1,b or 1}
        tipStyle:Font(item.left,size);tipStyle:Font(item.right,size)
        UI:Place(item.left,tip,12,y);D.Size(item.left,216,size+4)
        UI:Place(item.right,tip,12,y);D.Size(item.right,216,size+4)
        item.left:SetText(left or "");item.right:SetText(right or "")
        if accent then item.left:SetTextColor(tipStyle:Color(captured and "accentText" or "accent")) else item.left:SetTextColor(r or 1,g or 1,b or 1) end
        item.right:SetTextColor(1,1,1)
        item.left:Show();item.right:SetShown(right~=nil)
        y=y+size+6
    end
    for index,section in ipairs(sections) do
        if index>1 then y=y+4 end
        line(section.title,nil,12,nil,nil,nil,true)
        for _,entry in ipairs(section.lines) do line(entry.left,entry.right,11,entry.r,entry.g,entry.b) end
    end
    for index=row+1,#tip.rows do tip.rows[index].left:Hide();tip.rows[index].right:Hide() end
    D.Height(tip,y+6)
    tip.bvOwner=owner
    tip:SetScale(owner:GetEffectiveScale()/UIParent:GetEffectiveScale())
    tip:ClearAllPoints()
    local anchor=GameTooltip and GameTooltip:IsShown() and GameTooltip or owner
    tip:SetPoint("TOPLEFT",anchor,"TOPRIGHT",4,0)
    tip:Show()
end

-- Roll option button: Blizzard roll art, count in the corner.
function W:OptionButton(parent,size,capturedStyle)
    local b=CreateFrame("Button",nil,parent);D.Size(b,size,size)
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints(b)
    b.glow=b:CreateTexture(nil,"HIGHLIGHT");b.glow:SetAllPoints(b);b.glow:SetColorTexture(1,1,1,.12)
    b.bvStyle=capturedStyle;b.bvTooltipStyle=capturedStyle
    b.count=W:Label(capturedStyle,b,"",11,false,true);b.count:SetJustifyH("RIGHT")
    D.Point(b.count,"BOTTOMRIGHT",b,"BOTTOMRIGHT",4,-3);D.Size(b.count,24,12)
    b.count:SetTextColor(1,1,1)
    function b:SetOption(option,enabled,count,selected,def)
        def=def or L.OPTIONS[option]
        self.option=option
        -- Not "def.symbol and Coords(...)": and/or keeps only the path, the
        -- atlas coordinates would be lost (0.8.84, empty custom button).
        local path,l,r,t,bb
        if def.symbol then path,l,r,t,bb=ns.Symbols:Coords(def.symbol,64) end
        if path then
            self.icon:SetTexture(path);self.icon:SetTexCoord(l,r,t,bb)
            self.icon:SetVertexColor(def.color[1],def.color[2],def.color[3])
        else
            self.icon:SetTexture(def.texture);self.icon:SetTexCoord(0,1,0,1)
            if def.tint then self.icon:SetVertexColor(def.tint[1],def.tint[2],def.tint[3]) else self.icon:SetVertexColor(1,1,1) end
        end
        self.icon:SetDesaturated(not enabled)
        self:SetAlpha(enabled and 1 or .35)
        self.count:SetText(count and count>0 and tostring(count) or (count==0 and "0" or ""))
        self.count.bvLootRole=capturedStyle and selected and "accentText" or nil
        if selected then self.count:SetTextColor((capturedStyle or Theme):Color(capturedStyle and "accentText" or "accent")) else self.count:SetTextColor(1,1,1) end
        W:RememberColors(self.count)
    end
    function b:Resize(s) D.Size(self,s,s) end
    return b
end

-- Quality-colored item icon with item level and stack count. game: the
-- module's in-game style (fonts, border width of the family); the master loot
-- window keeps the tool style.
function W:ItemIcon(parent,size,game,capturedStyle)
    local f=CreateFrame("Button",nil,parent);D.Size(f,size,size);f.bvStyle=capturedStyle
    local function label(...) if capturedStyle then return UI:WithStyle(capturedStyle,UI.Label,UI,...) end;if game then return UI:GameLabel(L.ID,...) end;return UI:Label(...) end
    f.border=f:CreateTexture(nil,"BACKGROUND");f.border:SetAllPoints(f);f.border:SetColorTexture(0,0,0,1)
    f.icon=f:CreateTexture(nil,"ARTWORK")
    f.icon:SetTexCoord(.08,.92,.08,.92)
    f.bvLevel=label(f,"",11,false,true);D.Point(f.bvLevel,"BOTTOM",f,"BOTTOM",0,1);f.bvLevel:SetJustifyH("CENTER");D.Size(f.bvLevel,size,12)
    f.bvLevel:SetTextColor(1,1,1)
    f.bvStack=label(f,"",11,false,true);D.Point(f.bvStack,"TOPRIGHT",f,"TOPRIGHT",-2,-2);f.bvStack:SetJustifyH("RIGHT");D.Size(f.bvStack,size,12)
    f.bvStack:SetTextColor(1,1,1)
    if capturedStyle then
        capturedStyle:Bind(function() f.bvLevel:SetTextColor(1,1,1) end,f.bvLevel)
        capturedStyle:Bind(function() f.bvStack:SetTextColor(1,1,1) end,f.bvStack)
    end
    function f:Edge()
        local edge=game and select(2,L:Family()).iconEdge or 1
        if self.bvEdge==edge then return end
        self.bvEdge=edge
        self.icon:ClearAllPoints()
        D.Point(self.icon,"TOPLEFT",self,"TOPLEFT",edge,-edge);D.Point(self.icon,"BOTTOMRIGHT",self,"BOTTOMRIGHT",-edge,edge)
    end
    f:Edge()
    function f:SetItem(icon,quality,level,count)
        self:Edge()
        self.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local r,g,b=L.QualityColor(quality or 1)
        self.border:SetColorTexture(r,g,b,1)
        self.bvLevel:SetText(level and level>1 and tostring(level) or "")
        self.bvStack:SetText(count and count>1 and tostring(count) or "")
    end
    function f:Resize(s) D.Size(self,s,s);D.Width(self.bvLevel,s);D.Width(self.bvStack,s) end
    return f
end

-- One fade group per frame: order 1 fades in, order 2 fades out after hold.
function W:Fader(frame)
    local group=frame:CreateAnimationGroup();group:SetToFinalAlpha(true)
    local fadeIn=group:CreateAnimation("Alpha");fadeIn:SetOrder(1)
    local fadeOut=group:CreateAnimation("Alpha");fadeOut:SetOrder(2)
    local fader={group=group}
    function fader:Run(hold,fadeOutTime)
        group:Stop()
        fadeIn:SetFromAlpha(0);fadeIn:SetToAlpha(1);fadeIn:SetDuration(.2);fadeIn:SetStartDelay(0)
        if hold then
            fadeOut:SetFromAlpha(1);fadeOut:SetToAlpha(0);fadeOut:SetDuration(fadeOutTime or .4);fadeOut:SetStartDelay(hold)
        else
            fadeOut:SetFromAlpha(1);fadeOut:SetToAlpha(1);fadeOut:SetDuration(.01);fadeOut:SetStartDelay(0)
        end
        frame:SetAlpha(1);group:Play()
    end
    function fader:Stop() group:Stop();frame:SetAlpha(1) end
    return fader
end

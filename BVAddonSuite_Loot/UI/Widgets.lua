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
    local tip=self.info
    if not tip then
        tip=owned(UI:Panel(UIParent,240,40,"raised"));self.info=tip
        tip:SetFrameStrata("TOOLTIP");tip:EnableMouse(false);tip:SetClampedToScreen(true)
        tip.rows={}
    end
    local y,row=10,0
    local function line(left,right,size,r,g,b,accent)
        row=row+1
        local item=tip.rows[row]
        if not item then
            item={left=UI:Label(tip,"",12,false),right=UI:Label(tip,"",12,false)}
            item.right:SetJustifyH("RIGHT");tip.rows[row]=item
        end
        ns.Theme:Font(item.left,size);ns.Theme:Font(item.right,size)
        UI:Place(item.left,tip,12,y);D.Size(item.left,216,size+4)
        UI:Place(item.right,tip,12,y);D.Size(item.right,216,size+4)
        item.left:SetText(left or "");item.right:SetText(right or "")
        if accent then item.left:SetTextColor(Theme:Color("accent")) else item.left:SetTextColor(r or 1,g or 1,b or 1) end
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
function W:OptionButton(parent,size)
    local b=CreateFrame("Button",nil,parent);D.Size(b,size,size)
    b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetAllPoints(b)
    b.glow=b:CreateTexture(nil,"HIGHLIGHT");b.glow:SetAllPoints(b);b.glow:SetColorTexture(1,1,1,.12)
    b.count=UI:Label(b,"",11,false,true);b.count:SetJustifyH("RIGHT")
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
        if selected then self.count:SetTextColor(Theme:Color("accent")) else self.count:SetTextColor(1,1,1) end
    end
    function b:Resize(s) D.Size(self,s,s) end
    return b
end

-- Quality-colored item icon with item level and stack count.
function W:ItemIcon(parent,size)
    local f=CreateFrame("Button",nil,parent);D.Size(f,size,size)
    f.border=f:CreateTexture(nil,"BACKGROUND");f.border:SetAllPoints(f);f.border:SetColorTexture(0,0,0,1)
    f.icon=f:CreateTexture(nil,"ARTWORK");D.Point(f.icon,"TOPLEFT",f,"TOPLEFT",1,-1);D.Point(f.icon,"BOTTOMRIGHT",f,"BOTTOMRIGHT",-1,1)
    f.icon:SetTexCoord(.08,.92,.08,.92)
    f.bvLevel=UI:Label(f,"",11,false,true);D.Point(f.bvLevel,"BOTTOM",f,"BOTTOM",0,1);f.bvLevel:SetJustifyH("CENTER");D.Size(f.bvLevel,size,12)
    f.bvLevel:SetTextColor(1,1,1)
    f.bvStack=UI:Label(f,"",11,false,true);D.Point(f.bvStack,"TOPRIGHT",f,"TOPRIGHT",-2,-2);f.bvStack:SetJustifyH("RIGHT");D.Size(f.bvStack,size,12)
    f.bvStack:SetTextColor(1,1,1)
    function f:SetItem(icon,quality,level,count)
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

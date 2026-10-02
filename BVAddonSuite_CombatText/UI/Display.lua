local _,L=...
if not L.ready then return end
-- Text display: two movable anchors (Layout Editor), nameplate positions and
-- a pool of animated text frames. Frames are reused; a timer returns them to
-- the pool when their animation is over.
local ns=L.ns
local D=ns.DesignSystem.Metrics
local A=L.Animation
local Display={pool={},active={},anchors={},moving={},maxActive=40,step=1/30}
L.Display=Display

local function owned(frame) if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(frame) end;return frame end

-- Anchors ---------------------------------------------------------------------------
local ANCHORS={
    {key="outgoing",layout="bv:combattext_outgoing",label="Combat Text: Outgoing",x=260,y=60},
    {key="incoming",layout="bv:combattext_incoming",label="Combat Text: Incoming",x=-260,y=60},
}
local LANES={0,-36,36,-18,18}
for _,def in ipairs(ANCHORS) do
    local anchor={def=def,lane=0}
    local frame=owned(CreateFrame("Frame",nil,UIParent))
    frame:SetFrameStrata("MEDIUM");frame:EnableMouse(false)
    frame:SetSize(1,1);frame:SetPoint("CENTER",UIParent,"CENTER",def.x,def.y)
    anchor.frame=frame
    local box=frame:CreateTexture(nil,"BACKGROUND")
    box:SetAllPoints(frame);box:SetColorTexture(.9,.74,.51,.18);box:Hide()
    local label=frame:CreateFontString(nil,"OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF",12,"OUTLINE");label:SetPoint("CENTER",frame,"CENTER",0,0)
    label:SetText(def.label);label:Hide()
    anchor.box,anchor.label=box,label
    function anchor:Apply(rect)
        frame:ClearAllPoints();frame:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
        frame:SetSize(math.max(1,rect.width),math.max(1,rect.height))
    end
    function anchor:Preview(on) box:SetShown(on);label:SetShown(on) end
    -- Spread texts that start at the same time over a few lanes.
    function anchor:NextLane() self.lane=self.lane%#LANES+1;return LANES[self.lane] end
    Display.anchors[def.key]=anchor
    ns.Layout:Register(def.layout,{label=def.label,
        limits={minWidth=20,maxWidth=600,minHeight=20,maxHeight=600},
        defaults=function() return {width=D.ToNative(120),height=D.ToNative(40),screen="CENTER",x=def.x,y=def.y} end,
        apply=function(rect) anchor:Apply(rect) end,
        enabled=function() return L:Active() end,
        preview=function(value) anchor:Preview(value==true) end})
end

-- Text frames -------------------------------------------------------------------------
local function fontPath(cfg)
    if cfg.font~="inherit" and ns.Media then
        local ok,path=pcall(ns.Media.Font,ns.Media,cfg.font)
        if ok and path then return path end
    end
    if ns.Media then
        local ok,path=pcall(ns.Media.Font,ns.Media,ns.Settings:Get("font"))
        if ok and path then return path end
    end
    return "Fonts\\FRIZQT__.TTF"
end
function Display:Acquire()
    -- Too many texts at once: the oldest one makes room.
    if #self.active>=self.maxActive then self:Release(self.active[1]) end
    local item=table.remove(self.pool)
    if not item then
        local frame=owned(CreateFrame("Frame",nil,UIParent))
        frame:SetFrameStrata("MEDIUM");frame:EnableMouse(false);frame:SetSize(1,1)
        local text=frame:CreateFontString(nil,"OVERLAY")
        text:SetPoint("CENTER",frame,"CENTER",0,0)
        local icon=frame:CreateTexture(nil,"OVERLAY")
        icon:SetTexCoord(.08,.92,.08,.92);icon:Hide()
        A:Attach(frame)
        item={frame=frame,text=text,icon=icon,serial=0}
    end
    self.active[#self.active+1]=item
    return item
end
function Display:Release(item)
    if not item or not item.live then return end
    item.live=false;item.serial=item.serial+1
    item.frame.animGroup:Stop();item.frame:Hide();item.frame:ClearAllPoints()
    for i,other in ipairs(self.active) do if other==item then table.remove(self.active,i);break end end
    self.moving[item]=nil
    item.plate,item.plateFrame=nil,nil
    self.pool[#self.pool+1]=item
end
function Display:Clear() while #self.active>0 do self:Release(self.active[1]) end end

-- Nameplate frame of a unit, or nil when none is shown or it is forbidden.
function Display:Plate(unit)
    if not unit or not L:Config().plates or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
    local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,unit)
    if not ok or type(plate)~="table" then return nil end
    if plate.IsForbidden then local okF,forbidden=pcall(plate.IsForbidden,plate);if not okF or forbidden then return nil end end
    return plate
end
-- Texts at a nameplate stay anchored to it and follow the enemy. The client
-- drops Translation animations on frames anchored to a plate (0.2.0/0.2.1,
-- Florian in game) and the plate's position is not readable (0.2.2 fell back
-- to the outgoing anchor), so a ticker moves the anchor offset while plate
-- texts fly; alpha and scale stay with the AnimationGroup.
function Display:Move()
    local now=GetTime()
    local any=false
    for item,m in pairs(self.moving) do
        local x,y=A:Offset(m.keys,(now-m.start)/m.duration)
        item.frame:ClearAllPoints()
        if not pcall(item.frame.SetPoint,item.frame,"BOTTOM",m.plate,"TOP",x*m.distance,y*m.distance) then self.moving[item]=nil
        else any=true end
    end
    if not any and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function Display:StartMoving()
    if self.ticker then return end
    self.ticker=C_Timer.NewTicker(self.step,function() self:Move() end)
end
-- The plate frame is reused for another unit: its texts must not jump along.
function Display:PlateRemoved(unit)
    for item in pairs(self.moving) do if item.plate==unit then self:Release(item) end end
end

-- Shows one text. entry: {category, text, crit, school r/g/b, unit}.
-- override: style used instead of the category's (animation preview).
function Display:Show(entry,override)
    local cfg=L:Config()
    local style=override or cfg.categories[entry.category]
    if not style or not style.enabled then return nil end
    local anchorKey=style.anchor
    local plate
    if anchorKey=="nameplate" or anchorKey=="auto" then
        plate=entry.unit and entry.unit~="player" and self:Plate(entry.unit) or nil
        if not plate then
            if entry.unit and entry.unit~="player" and L.Sources.Count then L.Sources.Count("no nameplate frame") end
            anchorKey=anchorKey=="auto" and (entry.incoming and "incoming" or "outgoing") or "outgoing"
        end
    end
    local anchor=self.anchors[anchorKey]
    local item=self:Acquire()
    item.live=true;item.serial=item.serial+1
    local frame,text=item.frame,item.text
    local size=style.size*(entry.crit and style.crit or 1)
    text:SetFont(fontPath(cfg),size,cfg.outline)
    local r,g,b,a=L.Format.Color(style.color)
    if style.school and entry.r then r,g,b=entry.r,entry.g,entry.b end
    -- Values on enemies not fighting you: own color (optional) and transparency.
    if entry.foreign then
        if cfg.foreignTint then r,g,b=L.Format.Color(cfg.foreignColor) end
        a=a*cfg.foreignAlpha
    end
    text:SetTextColor(r,g,b,a)
    text:SetText(entry.text)
    -- Spell icon (best guess, see Attribution.lua) beside the text.
    local texture=cfg.icons~="off" and L.Attribution.Icon(entry.spell) or nil
    local icon=item.icon
    icon:ClearAllPoints()
    if texture then
        local edge=math.floor(size*cfg.iconSize+.5)
        icon:SetTexture(texture);icon:SetSize(edge,edge);icon:SetAlpha(a)
        if cfg.icons=="right" then icon:SetPoint("LEFT",text,"RIGHT",3,0) else icon:SetPoint("RIGHT",text,"LEFT",-3,0) end
        icon:Show()
    else icon:Hide() end
    item.spell=texture and entry.spell or nil
    local jitter=math.random()*2-1
    local index=tonumber(style.animation:match("^custom(%d)$"))
    local custom=index and cfg.customAnimations[index]
    local keys=A:Keys(style,entry.crit,jitter,custom and custom.keys)
    local distance=D.ToNative(style.distance)
    local x,y=(keys[1].x or 0)*distance,(keys[1].y or 0)*distance
    frame:ClearAllPoints()
    if plate and not pcall(frame.SetPoint,frame,"BOTTOM",plate,"TOP",x,y) then
        frame:ClearAllPoints();plate=nil
        if L.Sources.Count then L.Sources.Count("plate anchor refused") end
    end
    if plate then
        item.plate,item.plateFrame=entry.unit,plate
        self.moving[item]={keys=keys,start=GetTime(),duration=style.duration,distance=distance,plate=plate}
        self:StartMoving()
    else
        anchor=anchor or (anchorKey~="nameplate" and anchorKey~="auto" and self.anchors[anchorKey]) or (entry.incoming and self.anchors.incoming) or self.anchors.outgoing
        local lane=(style.animation~="fountain" and style.animation~="rain") and anchor:NextLane() or 0
        frame:SetPoint("CENTER",anchor.frame,"CENTER",x+D.ToNative(lane),y)
    end
    frame:SetFrameLevel(10+(#self.active%40))
    frame:Show()
    A:Play(frame,keys,style.duration,distance,plate~=nil)
    local serial=item.serial
    C_Timer.NewTimer(style.duration+.05,function() if item.serial==serial then self:Release(item) end end)
    return item
end

-- Plays a custom animation (1..3) at the outgoing anchor with the outgoing style.
function Display:Preview(index,crit)
    local base=L:Config().categories.outgoing
    local style={}
    for key,value in pairs(base) do style[key]=value end
    style.enabled,style.anchor,style.animation=true,"outgoing","custom"..index
    return self:Show({category="outgoing",text=crit and "36.5k" or "12.3k",crit=crit},style)
end
function Display:Enable(context)
    context:Defer(function() self:Clear();if self.ticker then self.ticker:Cancel();self.ticker=nil end end)
    context:Subscribe("NAME_PLATE_UNIT_REMOVED",function(_,unit) self:PlateRemoved(unit) end)
end

local _,P=...
if not P.ready then return end
-- The map in its window: an own scale (50-150 %) and, when movable, an own
-- position: drag the map's title bar, double-click resets, Ctrl+wheel there
-- scales. Blizzard's panel manager places the map again on every layout
-- change (opening, the side panel, other windows; Florian 2026-10-08: it
-- jumped back), so ours follows each of Blizzard's SetPoint calls at once.
-- Maximized, the map stays Blizzard's. Another addon moving or scaling the
-- map (P.Guard) keeps that part; ours stays out. Map 0.2: the map reopens
-- on the same map, zoom and section while you are still in the same zone. Our quest log beside the
-- map is parented to it and follows.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local W={}
P.Window=W

function W:Maximized()
    local map=P:WorldMap()
    return map and map.IsMaximized and map:IsMaximized()==true or false
end
function W:Handle()
    local map=P:WorldMap()
    if self.handle or not map then return self.handle end
    -- Over the title bar, leaving Blizzard's buttons at the right free.
    local h=CreateFrame("Button",nil,map);h:RegisterForDrag("LeftButton");h:RegisterForClicks("LeftButtonUp")
    h:SetPoint("TOPLEFT",map,"TOPLEFT",M.ToNative(60),0);h:SetPoint("TOPRIGHT",map,"TOPRIGHT",-M.ToNative(90),0);h:SetHeight(M.ToNative(22))
    h:SetFrameLevel(map:GetFrameLevel()+15)
    h:SetScript("OnDragStart",function() W:StartMove() end)
    h:SetScript("OnDragStop",function() W:StopMove() end)
    h:SetScript("OnDoubleClick",function() W:Reset() end)
    h:EnableMouseWheel(true)
    h:SetScript("OnMouseWheel",function(_,delta)
        if IsControlKeyDown and IsControlKeyDown() then W:Scale(P:Config().scale+delta*5) end
    end)
    UI:AttachTooltip(h,"Move the map","Drag to move. Double-click resets the position. Ctrl+mouse wheel scales.")
    self.handle=h
    return h
end
-- Ours only while no other addon moves or scales the map.
function W:Movable() return P:Config().movable and not P.Guard:Owner("move") end
function W:Scaling() return not P.Guard:Owner("scale") end
function W:StartMove()
    local map=P:WorldMap()
    if not (map and self:Movable()) or self:Maximized() then return end
    self.moving=true
    map:SetMovable(true);map:SetClampedToScreen(true);map:StartMoving()
end
function W:StopMove()
    local map=P:WorldMap()
    if not (self.moving and map) then return end
    self.moving=false
    map:StopMovingOrSizing()
    -- Stored as the top-left corner in UIParent coordinates (scale-free).
    local left,top=map:GetLeft(),map:GetTop()
    local scale=map:GetScale() or 1
    if left and top then P:Config().position={x=left*scale,y=top*scale} end
    self:Apply()
end
function W:Reset()
    P:Config().position=nil
    local map=P:WorldMap()
    if map and map:IsShown() and not self:Maximized() then
        -- Blizzard's own place: hide and show through the panel manager.
        if HideUIPanel and ShowUIPanel then pcall(HideUIPanel,map);pcall(ShowUIPanel,map) end
    end
    self:Apply()
end
function W:Scale(value)
    local c=P:Config()
    c.scale=math.max(50,math.min(150,math.floor((value or 100)+.5)))
    self:Apply()
    if ns.Config then ns.Config:Refresh() end
end
-- Scale and position onto the map (window mode only).
function W:Apply()
    local map=P:WorldMap()
    if not map then return end
    local c=P:Config()
    local on=P:Active() and not self:Maximized()
    local handle=self:Handle()
    local movable=self:Movable()
    if handle then handle:SetShown(on and movable) end
    if not on then
        if self.applied then map:SetScale(1);self.applied=false end
        return
    end
    self.applying=true
    local scale=map:GetScale() or 1
    if self:Scaling() then scale=c.scale/100;map:SetScale(scale);self.applied=true end
    if movable and c.position and not self.moving then
        map:ClearAllPoints()
        map:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",c.position.x/scale,c.position.y/scale)
    end
    self.applying=false
end

-- Zoom and section: remembered on close, restored on open in the same zone
-- (a zone change opens on your map as Blizzard does).
function W:Remember()
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    if not (map and map.GetMapID) then return end
    local view={mapID=map:GetMapID(),player=P.Call("C_Map.GetBestMapForUnit","player")}
    if scroll and scroll.GetCanvasScale then
        local ok,scale=pcall(scroll.GetCanvasScale,scroll)
        local okH,h=pcall(scroll.GetNormalizedHorizontalScroll,scroll)
        local okV,v=pcall(scroll.GetNormalizedVerticalScroll,scroll)
        if ok and okH and okV then view.scale,view.h,view.v=scale,h,v end
    end
    self.view=view
end
function W:Restore()
    local view,map=self.view,P:WorldMap()
    if not (P:Config().rememberZoom and view and map and map.SetMapID) then return end
    -- Not in combat: setting the map's zoom from here could block a
    -- protected call of the map's own code (pins in combat).
    if InCombatLockdown and InCombatLockdown() then return end
    if view.player~=P.Call("C_Map.GetBestMapForUnit","player") then self.view=nil;return end
    if map:GetMapID()~=view.mapID then pcall(map.SetMapID,map,view.mapID) end
    local scroll=map.ScrollContainer
    if view.scale and scroll and scroll.InstantPanAndZoom then pcall(scroll.InstantPanAndZoom,scroll,view.scale,view.h,view.v) end
end
function W:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        -- Blizzard places the map on show; ours follows a moment later.
        map:HookScript("OnShow",function() if P:Active() then W:Apply();C_Timer.NewTimer(0,function() W:Apply();W:Restore() end) end end)
        map:HookScript("OnHide",function() if P:Active() then W:Remember() end end)
        -- Blizzard placed the map: ours again (not while dragging, not our own
        -- call). Once per frame, after Blizzard's last anchor of the batch, so
        -- a second anchor of theirs never stretches ours.
        hooksecurefunc(map,"SetPoint",function()
            if W.applying or W.moving or W.pending or not P:Active() then return end
            local c=P:Config()
            if not (W:Movable() and c.position) or W:Maximized() then return end
            W.pending=C_Timer.NewTimer(0,function() W.pending=nil;W:Apply() end)
        end)
        if map.SetMaximized then hooksecurefunc(map,"SetMaximized",function() W:Apply() end) end
        if map.SetMinimized then hooksecurefunc(map,"SetMinimized",function() W:Apply() end) end
    end
    context:Defer(function()
        local m=P:WorldMap()
        if m and W.applied then m:SetScale(1);W.applied=false end
        if W.handle then W.handle:Hide() end
        if W.pending then W.pending:Cancel();W.pending=nil end
    end)
    self:Apply()
end

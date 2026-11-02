local _,P=...
if not P.ready then return end
-- Own window geometry around the native WorldMapFrame. Canvas objects, pins,
-- data providers and the native map lifecycle remain owned by the client.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local W={}
P.Window=W
local function points(frame)
    local out={};for i=1,frame:GetNumPoints() do out[i]={frame:GetPoint(i)} end;return out
end
local function anchor(frame,saved)
    frame:ClearAllPoints();for _,point in ipairs(saved) do frame:SetPoint(unpack(point)) end
end
local function clamp(v,a,b) return math.max(a,math.min(math.max(a,b),v)) end
local function finite(v) return type(v)=="number" and v==v and v>-math.huge and v<math.huge end
local function canvasReady(scroll)
    local levels=scroll and scroll.zoomLevels
    if type(levels)~="table" or #levels==0 then return false end
    local first,last=levels[1],levels[#levels]
    return type(first)=="table" and type(last)=="table" and finite(first.scale) and first.scale>0
        and finite(last.scale) and last.scale>=first.scale
end
function W:Combat() return InCombatLockdown and InCombatLockdown() or false end
function W:Maximized()
    local map=P:WorldMap()
    return self.maximized or map and map.IsMaximized and map:IsMaximized()==true or false
end
function W:Movable() return P:Config().movable and not P.Guard:Owner("move") end
function W:Scaling() return not P.Guard:Owner("scale") end
function W:CanResize()
    local map=P:WorldMap();local sc=map and map.ScrollContainer
    return P:Active() and self:Scaling() and not P.Guard:Owner("move") and sc
        and (type(map.OnFrameSizeChanged)=="function" or type(sc.OnCanvasSizeChanged)=="function") and true or false
end
function W:Handle()
    if P.WindowSkin:Build() then self.handle=P.WindowSkin.handle end
    return self.handle
end
function W:Capture()
    local map=P:WorldMap()
    if self.saved or not map then return end
    self.saved={width=map:GetWidth(),height=map:GetHeight(),scale=map:GetScale(),points=points(map),
        movable=map.IsMovable and map:IsMovable(),clamped=map.IsClampedToScreen and map:IsClampedToScreen(),
        maximized=map.IsMaximized and map:IsMaximized()}
    local sc=map.ScrollContainer
    if sc then self.saved.scroll={points=points(sc),width=sc:GetWidth(),height=sc:GetHeight()} end
end
function W:SavePosition()
    local map=P:WorldMap();local left,top=map:GetLeft(),map:GetTop()
    local ratio=map:GetEffectiveScale()/UIParent:GetEffectiveScale()
    if left and top then P:Config().position={x=left*ratio,y=top*ratio} end
end
function W:StartMove()
    local map=P:WorldMap()
    if not (P:Active() and map and self:Movable()) or self:Maximized() or self:Combat() then return end
    self.moving=true;map:SetMovable(true);map:SetClampedToScreen(true);map:StartMoving()
end
function W:StopMove()
    local map=P:WorldMap();if not (self.moving and map) then return end
    if self:Combat() then self.pendingCombat=true;return end
    self.moving=false;map:StopMovingOrSizing();self:SavePosition();self:Apply()
end
function W:CloseMenus()
    P.WindowSkin:CloseFilterMenu()
    local owner=UI.dropdown and UI.dropdown.owner
    local map=P:WorldMap()
    for _=1,20 do
        if not owner then return end
        if owner==map then UI:CloseDropdown();return end
        owner=owner.GetParent and owner:GetParent()
    end
end
function W:Reset()
    if self:Combat() then return end
    P:Config().position=nil
    local map=P:WorldMap()
    if map and self.saved and not self:Maximized() then
        self.applying=true;anchor(map,self.saved.points);self.applying=false
    end
    self:Apply()
end
function W:ResetSize()
    if self:Combat() then return end
    local c=P:Config();c.windowWidth=P.DEFAULTS.windowWidth;c.windowHeight=P.DEFAULTS.windowHeight
    self:Apply()
end
function W:Scale(value)
    if self:Combat() or not self:Scaling() then return end
    P:Config().scale=clamp(math.floor((value or 100)+.5),50,150)
    self:Apply();if ns.Config then ns.Config:Refresh() end
end
function W:Navigate(id)
    local map=P:WorldMap()
    if not self:Combat() and P:Active() and type(id)=="number" and map and map.SetMapID then map:SetMapID(id) end
end
function W:Up()
    local map=P:WorldMap();local info=map and map.GetMapID and P.Call("C_Map.GetMapInfo",map:GetMapID())
    if type(info)=="table" and type(info.parentMapID)=="number" and info.parentMapID>0 then self:Navigate(info.parentMapID) end
end
function W:ToggleMaximize()
    if self:Combat() or not self:CanResize() then return end
    local map=P:WorldMap();local max=self:Maximized()
    local action
    if max then action=map.HandleUserActionMinimizeSelf or map.Minimize
    else action=map.HandleUserActionMaximizeSelf or map.Maximize end
    if type(action)=="function" then action(map)
    else self.maximized=not max end
    self:Apply()
end
-- The quest module can run without Map. It asks for this optional docking
-- contract instead of inheriting knowledge of our chrome or sizing rules.
function W:DockAnchor()
    local skin=P.WindowSkin
    return P:Active() and skin.active and skin.dock or P:WorldMap()
end
function W:QuestPanes()
    local q=ns.Quest
    return q and q:Active() and q.Panes and q.Panes.frame and q.Panes.frame:IsShown() and q.Panes or nil
end
function W:Screen()
    local map=P:WorldMap();local ratio=UIParent:GetEffectiveScale()/map:GetEffectiveScale()
    return UIParent:GetWidth()*ratio,UIParent:GetHeight()*ratio
end
function W:NativePanelWidth()
    local panel=rawget(_G,"QuestMapFrame")
    if not (panel and panel:IsShown()) then return 0 end
    local owner=panel:GetParent();local map=P:WorldMap()
    for _=1,10 do if owner==map then return panel:GetWidth() end;if not owner then break end;owner=owner:GetParent() end
    return 0
end
-- Widths are transient fit results, never written over the user's pane sizes.
function W:DockLayout()
    return self.dockLayout
end
function W:Geometry()
    local c=P:Config();local sw,sh=self:Screen();local q=self:QuestPanes()
    local layout=q and q:Measure() or {left=0,right=0,widths={}}
    local native=self:NativePanelWidth()
    local margin=M.ToNative(12);local maxWidth=math.max(240,sw-2*margin)
    local minMap=M.ToNative(360)+native
    local extra=layout.left+layout.right
    if extra>0 and extra>maxWidth-minMap then
        local rail=M.ToNative(34)
        local factor=math.max(.1,(maxWidth-minMap-rail)/math.max(1,extra-rail))
        layout=q:Measure(factor);extra=layout.left+layout.right
    end
    local available=math.max(240,maxWidth-extra)
    local width=self:Maximized() and available or math.min(M.ToNative(c.windowWidth)+native,available)
    local height=self:Maximized() and sh-2*margin or math.min(M.ToNative(c.windowHeight),sh-2*margin)
    self.dockLayout=layout
    return math.max(240,width),math.max(200,height),layout.left,layout.right,native
end
function W:RefreshCanvas(view)
    local map=P:WorldMap();local sc=map and map.ScrollContainer
    -- A hidden, never-opened native map has no zoom levels yet. Its resize
    -- callback can return without initializing them; panning afterwards calls
    -- native layer selection, which iterates the missing table. Let the native
    -- first OnShow/SetMapID establish the canvas instead of manufacturing data.
    if not canvasReady(sc) then return end
    -- Native resize recalculates zoom levels and resets zoom. Restore the old
    -- center/scale, clamped to the newly available range, after that callback.
    if type(map.OnFrameSizeChanged)=="function" then map:OnFrameSizeChanged()
    elseif type(sc.OnCanvasSizeChanged)=="function" then sc:OnCanvasSizeChanged() end
    if not canvasReady(sc) then return end
    if view and sc.InstantPanAndZoom then
        local levels=sc.zoomLevels
        local scale=view.scale
        if type(levels)=="table" and #levels>0 then scale=clamp(scale,levels[1].scale,levels[#levels].scale) end
        sc:InstantPanAndZoom(scale,view.h,view.v)
    end
    if ns.MapPins then ns.MapPins:Refresh() end
    if P.Terrain then P.Terrain:Refresh() end
end
function W:CurrentView()
    local map=P:WorldMap();local sc=map and map.ScrollContainer
    if not (canvasReady(sc) and sc.GetCanvasScale and sc.GetNormalizedHorizontalScroll and sc.GetNormalizedVerticalScroll) then return end
    local scale,h,v=sc:GetCanvasScale(),sc:GetNormalizedHorizontalScroll(),sc:GetNormalizedVerticalScroll()
    if finite(scale) and scale>0 and finite(h) and finite(v) then return {scale=scale,h=h,v=v} end
end
function W:Clamp(left,right)
    local map=P:WorldMap();local sw,sh=self:Screen()
    local x,y=map:GetLeft(),map:GetTop()
    if not (x and y) then return end
    local nx=clamp(x,left,sw-map:GetWidth()-right)
    local ny=clamp(y,map:GetHeight(),sh)
    if math.abs(x-nx)>.5 or math.abs(y-ny)>.5 then
        map:ClearAllPoints();map:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",nx,ny)
    end
end
function W:Apply()
    if self.applying then return end
    if self:Combat() then self.pendingCombat=true;return end
    local map=P:WorldMap();if not map then return end
    if not P:Active() then return self:Release() end
    self:Capture()
    local skin=P.WindowSkin
    if not skin:Build() then return end
    self.handle=skin.handle
    self.applying=true
    local c=P:Config();local resizing=self:CanResize()
    if self:Scaling() then
        map:SetScale(self:Maximized() and 1 or c.scale/100);self.applied=true
    end
    local left,right=0,0
    if resizing then
        local view=self.resizeView or self:CurrentView()
        local width,height,native
        width,height,left,right,native=self:Geometry()
        local sc=map.ScrollContainer
        local changed=not self.geometry or math.abs(map:GetWidth()-width)>.1 or math.abs(map:GetHeight()-height)>.1
            or self.geometry.native~=native
        map:SetSize(width,height)
        sc:ClearAllPoints()
        M.Point(sc,"TOPLEFT",map,"TOPLEFT",skin.EDGE,-skin.TOP)
        sc:SetPoint("BOTTOMRIGHT",map,"BOTTOMRIGHT",-M.ToNative(skin.EDGE)-native,M.ToNative(skin.BOTTOM))
        self.geometry={native=native};self.ownedGeometry=true
        if self:Maximized() then map:ClearAllPoints();map:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left+M.ToNative(12),select(2,self:Screen())-M.ToNative(12))
        elseif self:Movable() and c.position and not self.moving then
            local ratio=map:GetEffectiveScale()/UIParent:GetEffectiveScale()
            map:ClearAllPoints();map:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",c.position.x/ratio,c.position.y/ratio)
        end
        if not self.moving then self:Clamp(left,right) end
        if changed then self:RefreshCanvas(view) end
    else
        self.dockLayout=nil
        -- Honor external geometry owners; a native maximized canvas also stays
        -- native on clients without the supported resize callback.
        if self.ownedGeometry then self:RestoreGeometry() end
        local q=self:QuestPanes();local layout=q and q:Measure()
        if layout then left,right=layout.left,layout.right end
        if self:Movable() and c.position and not self:Maximized() and not self.moving then
            local ratio=map:GetEffectiveScale()/UIParent:GetEffectiveScale()
            map:ClearAllPoints();map:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",c.position.x/ratio,c.position.y/ratio)
        end
    end
    skin:Apply(left,right)
    local q=self:QuestPanes();if q then q:Layout() end
    self.applying=false
end
function W:RestoreGeometry()
    local map=P:WorldMap();local saved=self.saved
    if not (map and saved and self.ownedGeometry) then return end
    map:SetSize(saved.width,saved.height)
    if saved.scroll and map.ScrollContainer then
        local sc=map.ScrollContainer;sc:SetSize(saved.scroll.width,saved.scroll.height);anchor(sc,saved.scroll.points)
    end
    self.ownedGeometry=false;self.geometry=nil
    self:RefreshCanvas(self:CurrentView())
end
function W:Release()
    if self:Combat() then self.pendingRelease=true;return end
    self.applying=true
    self:StopResize(true)
    local map=P:WorldMap()
    if self.moving and map then map:StopMovingOrSizing();self.moving=false end
    self:CloseMenus()
    -- Cleanup must finish even when a native callback fails. Preserve the first
    -- error for Modules/cleanup after relinquishing all our visible state.
    local failure
    local function restore(fn,...)
        local good,reason=pcall(fn,...);if not good then failure=failure or reason end
    end
    if map and self.saved and self.saved.maximized~=nil and map.IsMaximized
        and map:IsMaximized()~=self.saved.maximized and self.ownedGeometry then
        local action
        if self.saved.maximized then action=map.HandleUserActionMaximizeSelf or map.Maximize
        else action=map.HandleUserActionMinimizeSelf or map.Minimize end
        if type(action)=="function" then restore(action,map) end
    end
    restore(self.RestoreGeometry,self)
    if map and self.saved then
        if self.applied then restore(map.SetScale,map,self.saved.scale) end
        if self:Movable() then restore(anchor,map,self.saved.points) end
        if self.saved.movable~=nil then restore(map.SetMovable,map,self.saved.movable) end
        if self.saved.clamped~=nil then restore(map.SetClampedToScreen,map,self.saved.clamped) end
    end
    restore(P.WindowSkin.Release,P.WindowSkin)
    self.applied,self.maximized,self.saved,self.dockLayout=nil,nil,nil,nil
    self.ownedGeometry,self.geometry=nil,nil
    local q=self:QuestPanes();if q then restore(q.Layout,q) end
    self.applying=false
    if failure then error(failure,0) end
end
function W:StartResize()
    if self:Combat() or not self:CanResize() or self:Maximized() then return end
    local x,y=GetCursorPosition();local map=P:WorldMap()
    self.resize={x=x,y=y,width=map:GetWidth()-self:NativePanelWidth(),height=map:GetHeight(),scale=map:GetEffectiveScale()}
    self.resizeView=self:CurrentView()
    if self.resizeTicker then self.resizeTicker:Cancel() end
    self.resizeTicker=C_Timer.NewTicker(.03,function()
        if W:Combat() or not P:Active() then W:StopResize(true);return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then W:StopResize();return end
        W:ResizeStep()
    end)
end
function W:ResizeStep()
    local d=self.resize;if not d or self:Combat() then return end
    local x,y=GetCursorPosition();local c=P:Config()
    c.windowWidth=clamp(math.floor(M.ToDesign(d.width+(x-d.x)/d.scale)+.5),360,2400)
    c.windowHeight=clamp(math.floor(M.ToDesign(d.height+(d.y-y)/d.scale)+.5),240,1600)
    self:Apply()
end
function W:StopResize(cancel)
    if self.resize and not cancel then self:ResizeStep();self:SavePosition() end
    self.resize=nil;self.resizeView=nil
    if self.resizeTicker then self.resizeTicker:Cancel();self.resizeTicker=nil end
end
function W:Schedule()
    if self.applying or self.moving or self.pending or not P:Active() then return end
    self.pending=C_Timer.NewTimer(0,function() W.pending=nil;W:Apply() end)
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
    -- The seamless map's zoom onto the zone just opened gives way to this view.
    if P.Seamless then P.Seamless.focus=nil end
end
function W:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() if P:Active() then W:Apply();C_Timer.NewTimer(0,function() if P:Active() then W:Apply();W:Restore() end end) end end)
        map:HookScript("OnHide",function() W:StopResize(true);W:StopMove();W:CloseMenus();if P:Active() then W:Remember() end end)
        map:HookScript("OnSizeChanged",function() W:Schedule() end)
        hooksecurefunc(map,"SetPoint",function() W:Schedule() end)
        for _,name in ipairs({"SetMaximized","SetMinimized","Maximize","Minimize","SynchronizeDisplayState","OnMapChanged","AddOverlayFrame"}) do
            if type(map[name])=="function" then hooksecurefunc(map,name,function() W:Schedule() end) end
        end
        local panel=rawget(_G,"QuestMapFrame")
        if panel then panel:HookScript("OnShow",function() W:Schedule() end);panel:HookScript("OnHide",function() W:Schedule() end) end
        -- Restoration must survive disabling the module during combat.
        self.events=CreateFrame("Frame");self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
        self.events:RegisterEvent("DISPLAY_SIZE_CHANGED");self.events:RegisterEvent("UI_SCALE_CHANGED")
        self.events:SetScript("OnEvent",function(_,event)
            if event~="PLAYER_REGEN_ENABLED" then W:Schedule();return end
            if W.pendingRelease then W.pendingRelease=nil;W:Release() end
            if W.pendingCombat then W.pendingCombat=nil;if P:Active() then W:StopMove();W:Apply() end end
        end)
    end
    context:Defer(function()
        if W.pending then W.pending:Cancel();W.pending=nil end
        W:Release()
    end)
    self:Apply()
end

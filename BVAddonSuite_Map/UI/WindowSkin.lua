local _,P=...
if not P.ready then return end
-- Presentation only. The native map, canvas, providers and third-party children
-- remain the same objects; Window owns geometry and restores it on release.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local S={hidden={},hooked={},controls={},placed={},placementHooks={},pinSkins={}}
P.WindowSkin=S
S.TOP,S.BOTTOM,S.EDGE=82,18,6

function S:Suppress(region)
    if not (region and region.Hide and region.Show) then return end
    local entry=self.hidden[region]
    if not entry then
        entry={shown=region:IsShown()};self.hidden[region]=entry
        -- Native layout can show its decorations again. Only these explicit
        -- decorations are suppressed, never BorderFrame or unknown children.
        if not self.hooked[region] then
            self.hooked[region]=true
            hooksecurefunc(region,"Show",function()
                local current=S.hidden[region]
                if current and S.active and not S.restoring then current.shown=true;region:Hide() end
            end)
            hooksecurefunc(region,"SetShown",function(_,shown)
                local current=S.hidden[region]
                if current and S.active and not S.restoring then
                    current.shown=not not shown;if shown then region:Hide() end
                end
            end)
        end
    end
    region:Hide()
end
function S:RestoreRegion(region)
    local entry=region and self.hidden[region]
    if entry then self.hidden[region]=nil;region:SetShown(entry.shown) end
end
-- Native overlays are anonymous on this client. Identify their actual mixins,
-- not their texture, screen location or another addon's similarly named button.
local function matches(frame,name,method)
    local mixin=rawget(_G,name);method=method or "OnLoad"
    return mixin and type(mixin[method])=="function" and frame[method]==mixin[method]
end
function S:FindControls(map)
    local function visit(frame)
        if matches(frame,"WorldMapTrackingOptionsButtonMixin") then self.controls.filter=frame
        elseif matches(frame,"WorldMapTrackingPinButtonMixin") then self.controls.pin=frame
        elseif matches(frame,"WorldMapCoordsPanelMixin") then self.controls.coords=frame end
    end
    for _,frame in ipairs(map.overlayFrames or {}) do visit(frame) end
    if map.GetChildren then for _,frame in ipairs({map:GetChildren()}) do visit(frame) end end
    self.controls.quest=map.SidePanelToggle
end
function S:ControlVisibility()
    if not self.active then return end
    local c=self.controls;local q=ns.Quest
    if q and q:Active() then self:Suppress(c.quest) else self:RestoreRegion(c.quest) end
    local strip=P.Coords and P.Coords.strip
    if strip and strip:IsShown() then self:Suppress(c.coords) else self:RestoreRegion(c.coords) end
end
function S:PlaceControl(frame,parent,point,relativePoint,x,y,size,level)
    if not frame then return end
    if not self.placed[frame] then
        local saved={points={},width=frame:GetWidth(),height=frame:GetHeight(),level=frame:GetFrameLevel(),strata=frame:GetFrameStrata()}
        for i=1,frame:GetNumPoints() do saved.points[i]={frame:GetPoint(i)} end
        self.placed[frame]=saved
        if not self.placementHooks[frame] then
            self.placementHooks[frame]=true
            hooksecurefunc(frame,"SetPoint",function() if S.active and not S.restoring then P.Window:Schedule() end end)
        end
    end
    -- Keep the native parent: mixin callbacks use GetParent():GetMapID().
    frame:ClearAllPoints();M.Point(frame,point,parent,relativePoint,x,y);M.Size(frame,size,size)
    frame:SetFrameLevel(level);frame:SetFrameStrata(P:MapStrata() or "HIGH")
end
function S:SkinButton(button,symbol)
    if not button then return end
    local skin=self.pinSkins[button]
    if not skin then
        skin={art={}};self.pinSkins[button]=skin
        -- Only regions of this positively identified native button, never its
        -- children. Alpha preserves Blizzard's active/pressed texture state.
        for _,region in ipairs({button:GetRegions()}) do skin.art[region]=region:GetAlpha() end
        local visual=P:MapButton(button,symbol,nil,self.style);skin.visual=visual
        visual:EnableMouse(false);visual:SetAllPoints(button)
        if visual.icon then visual.icon:EnableMouse(false) end
        local function sync()
            if not S.active or not skin.owned then return end
            if button:IsEnabled() then visual:Enable() else visual:Disable() end
            visual:SetActive(button.isActive==true or (button.IsMenuOpen and button:IsMenuOpen())==true)
        end
        for _,event in ipairs({"OnEnter","OnLeave","OnMouseDown","OnMouseUp","OnHide"}) do
            button:HookScript(event,function(_, ...)
                if not (S.active and skin.owned) then return end
                local script=visual:GetScript(event);if script then script(visual,...) end
                sync()
            end)
        end
        for _,event in ipairs({"OnEnable","OnDisable","OnShow"}) do button:HookScript(event,sync) end
        if type(button.SetActive)=="function" then hooksecurefunc(button,"SetActive",sync) end
        for _,method in ipairs({"OnMenuOpened","OnMenuClosed"}) do
            if type(button[method])=="function" then hooksecurefunc(button,method,sync) end
        end
        skin.sync=sync
    end
    if not skin.owned then
        for region in pairs(skin.art) do skin.art[region]=region:GetAlpha();region:SetAlpha(0) end
        skin.owned=true
    end
    skin.visual:SetFrameLevel(button:GetFrameLevel()+1);skin.visual:Show();skin.sync()
end
-- The native dropdown owns its entries, selections, submenu and dismiss logic.
-- Its popup is pooled: presentation changes must be undone before native release
-- so a later, unrelated dropdown cannot inherit our colours or opacity.
local function resetFilterEntry(frame)
    local saved=frame.bvMapFilterText
    if not saved then return end
    saved.region:SetTextColor(unpack(saved.color));saved.region:SetAlpha(saved.alpha)
    frame.bvMapFilterText=nil
end
local function initializeFilterEntry(frame)
    if not S.active then return end
    -- Use the actual caption supplied by MenuVariants. Do this before native
    -- ButtonFinalInitializer caches the enabled text colour, and on every
    -- compositor reinitialization (selection, regeneration, submenu opening).
    local text=frame.fontString
    if not text then return end
    frame.bvMapFilterText={region=text,color={text:GetTextColor()},alpha=text:GetAlpha()}
    text:SetTextColor(S.style:Color("text",1));text:SetAlpha(1)
end
local function initializeFilterDescriptions(root)
    for _,entry in root:EnumerateElementDescriptions() do
        entry:AddInitializer(initializeFilterEntry)
        entry:AddResetter(resetFilterEntry)
        initializeFilterDescriptions(entry)
    end
end
function S:FilterSurface(button)
    if not (button and MenuVariants and MenuVariants.GetDefaultMenuMixin) then return end
    local saved=self.filterSurface
    if saved and button.menuMixin==saved.mixin then return end
    local original=button.menuMixin
    local base=original or MenuVariants.GetDefaultMenuMixin()
    local mixin={};for key,value in pairs(base) do mixin[key]=value end
    -- DropdownButton's supported menuMixin chooses the compositor's skin.
    -- Preserve native insets/layout; replace Generate rather than covering its
    -- gold atlas with another rectangle. Submenus use the same shared style.
    function mixin:Generate()
        local fill=self:AttachTexture();fill:SetDrawLayer("BACKGROUND",-8);fill:SetAllPoints(self)
        fill:SetColorTexture(S.style:Color("bg",1));self.bvMapSurface=fill
        for _,side in ipairs({"TOP","BOTTOM","LEFT","RIGHT"}) do
            local edge=self:AttachTexture();edge:SetDrawLayer("BORDER",-7)
            edge:SetColorTexture(S.style:Color("controlEdge",1))
            if side=="TOP" or side=="BOTTOM" then
                edge:SetPoint(side.."LEFT",self,side.."LEFT",0,0);edge:SetPoint(side.."RIGHT",self,side.."RIGHT",0,0);edge:SetHeight(1)
            else
                edge:SetPoint("TOP"..side,self,"TOP"..side,0,0);edge:SetPoint("BOTTOM"..side,self,"BOTTOM"..side,0,0);edge:SetWidth(1)
            end
        end
    end
    self.filterSurface={button=button,original=original,mixin=mixin};button.menuMixin=mixin
end
function S:RestoreFilterMenu()
    local state=self.filterMenu;if not state then return end
    self.filterMenu=nil
    if state.fill then state.fill:Hide() end
    state.menu:SetAlpha(state.alpha)
end
function S:PaintFilterMenu(menu)
    if not (self.active and menu and menu.GetRegions) then return end
    if self.filterMenu and self.filterMenu.menu~=menu then self:RestoreFilterMenu() end
    local state=self.filterMenu
    if not state then
        -- MenuProxy forbids CreateTexture. Its compositor owns attachments and
        -- releases them on close, so acquire anew for every open menu session.
        local fill=menu.bvMapSurface
        state={menu=menu,alpha=menu:GetAlpha(),fill=fill};self.filterMenu=state
    end
    if state.fill then state.fill:SetColorTexture(self.style:Color("bg",1));state.fill:Show() end
    menu:SetAlpha(1)
end
function S:Filter(button)
    self:FilterSurface(button)
    self:SkinButton(button,"sliders-horizontal")
    if button and not self.filterDescriptionHook and Menu and type(Menu.PopulateDescription)=="function" then
        self.filterDescriptionHook=true
        -- After the original generator and addon modifications, but BEFORE
        -- RegisterMenu constructs rows, including regeneration of an open menu.
        hooksecurefunc(Menu,"PopulateDescription",function(_,owner,root)
            if S.active and owner==S.controls.filter then initializeFilterDescriptions(root) end
        end)
    end
    if not button or self.filterHook==button then return end
    self.filterHook=button
    if type(button.OnMenuOpened)=="function" then
        hooksecurefunc(button,"OnMenuOpened",function(_,menu) if S.active then S:PaintFilterMenu(menu) end end)
    end
    if type(button.OnMenuClosed)=="function" then hooksecurefunc(button,"OnMenuClosed",function() S:RestoreFilterMenu() end) end
end
function S:CloseFilterMenu()
    local button=self.controls.filter
    if self.filterMenu and button and type(button.CloseMenu)=="function" then button:CloseMenu() end
    self:RestoreFilterMenu()
end
function S:NativeControls(map)
    self:FindControls(map);self:ControlVisibility()
    local c=self.controls
    self:PlaceControl(c.filter,self.nav,"RIGHT","RIGHT",0,0,32,P.BUTTONLEVEL+11)
    self:PlaceControl(c.pin,map.ScrollContainer or map,"TOPLEFT","TOPLEFT",6,-6,34,P.BUTTONLEVEL)
    self:SkinButton(c.pin,"map-pin");self:Filter(c.filter)
end
function S:Native(map)
    local border=map.BorderFrame
    for _,owner in ipairs({map,border or false,map.MiniBorderFrame or false}) do
        if owner then
            for _,key in ipairs({"Bg","Background","NineSlice","TopTileStreaks","TitleText","TitleContainer","PortraitContainer","Portrait","CloseButton","MaximizeMinimizeFrame","Underlay","InsetBorderTop","Tutorial"}) do self:Suppress(owner[key]) end
        end
    end
    -- Unknown regions and children may belong to another addon. Do not blanket
    -- hide GetRegions/GetChildren or the native BorderFrame itself.
    self:Suppress(map.NavBar)
    self:Suppress(map.ContinentDropdown);self:Suppress(map.ZoneDropdown)
    local title=rawget(_G,"WorldMapTitleButton")
    if title and title:GetParent()==map then self:Suppress(title) end
end
function S:Release()
    self:CloseFilterMenu()
    local surface=self.filterSurface
    if surface and surface.button.menuMixin==surface.mixin then surface.button.menuMixin=surface.original end
    self.filterSurface=nil
    self.active=false;self.restoring=true
    for frame,saved in pairs(self.placed) do
        frame:ClearAllPoints();for _,point in ipairs(saved.points) do frame:SetPoint(unpack(point)) end
        frame:SetSize(saved.width,saved.height);frame:SetFrameLevel(saved.level);frame:SetFrameStrata(saved.strata)
    end
    self.placed={}
    for _,skin in pairs(self.pinSkins) do
        if skin.owned then for region,alpha in pairs(skin.art) do region:SetAlpha(alpha) end end
        skin.owned=false;skin.visual:Hide()
    end
    for region,entry in pairs(self.hidden) do region:SetShown(entry.shown) end
    self.hidden={};self.restoring=false
    if self.frame then self.frame:Hide() end
end
function S:Options()
    local map=P:WorldMap();local id=map and map.GetMapID and map:GetMapID()
    local chain,out,seen={},{},{}
    for _=1,10 do
        if type(id)~="number" or id==0 or seen[id] then break end
        seen[id]=true
        local info=P.Call("C_Map.GetMapInfo",id)
        if type(info)~="table" then break end
        table.insert(chain,1,{value=id,label=info.name or tostring(id)})
        id=info.parentMapID
    end
    for _,item in ipairs(chain) do out[#out+1]=item end
    local children=map and map.GetMapID and P.Call("C_Map.GetMapChildrenInfo",map:GetMapID())
    local sorted={}
    for _,info in ipairs(type(children)=="table" and children or {}) do
        if type(info.mapID)=="number" and type(info.name)=="string" and not seen[info.mapID] then
            seen[info.mapID]=true;sorted[#sorted+1]={value=info.mapID,label=info.name}
        end
    end
    table.sort(sorted,function(a,b) return a.label<b.label end)
    for _,item in ipairs(sorted) do out[#out+1]=item end
    return out
end
function S:Build()
    if self.frame then return self.frame end
    local map=P:WorldMap()
    local style=ns.Config and ns.Config:EnsureShellStyle()
    if not (map and style and style.materialProfile=="interface") then return end
    self.style=style
    UI:WithStyle(style,function()
        local f=CreateFrame("Frame",nil,map);self.frame=f;f:EnableMouse(false)
        f:SetFrameLevel(map:GetFrameLevel())
        local chrome=UI:WindowChrome(f,style,{title="World map",
            onClose=function() if HideUIPanel then HideUIPanel(map) else map:Hide() end end,
            onMaximize=function() P.Window:ToggleMaximize() end,
            onDragStart=function() P.Window:StartMove() end,
            onDragStop=function() P.Window:StopMove() end,
            onResizeStart=function() P.Window:StartResize() end,
            onResizeStop=function() P.Window:StopResize() end})
        self.chrome=chrome;chrome.minimize:Hide()
        chrome.titlebar:SetFrameLevel(P.BUTTONLEVEL+20)
        chrome.grip:SetFrameLevel(P.BUTTONLEVEL+20)
        -- A separate handle allows native maximized windows to keep their title.
        local h=CreateFrame("Button",nil,chrome.titlebar);self.handle=h
        M.Point(h,"TOPLEFT",chrome.titlebar,"TOPLEFT",44,0);M.Point(h,"BOTTOMRIGHT",chrome.titlebar,"BOTTOMRIGHT",-90,0)
        h:RegisterForDrag("LeftButton");h:EnableMouseWheel(true)
        h:SetScript("OnDragStart",function() P.Window:StartMove() end)
        h:SetScript("OnDragStop",function() P.Window:StopMove() end)
        h:SetScript("OnDoubleClick",function() P.Window:Reset() end)
        h:SetScript("OnMouseWheel",function(_,delta)
            if IsControlKeyDown and IsControlKeyDown() then P.Window:Scale(P:Config().scale+delta*5) end
        end)
        UI:AttachTooltip(h,"Move the map","Drag to move. Double-click resets the position. Ctrl+wheel changes UI scale; the corner changes window size.")
        local nav=CreateFrame("Frame",nil,f);self.nav=nav
        M.Point(nav,"TOPLEFT",map,"TOPLEFT",S.EDGE,-44);M.Point(nav,"TOPRIGHT",map,"TOPRIGHT",-S.EDGE,-44);M.Height(nav,34)
        nav:SetFrameLevel(P.BUTTONLEVEL+10)
        self.up=UI:IconButton(nav,"arrow-up",function() P.Window:Up() end)
        M.Point(self.up,"LEFT",nav,"LEFT",0,0)
        UI:AttachTooltip(self.up,"Parent map","Open the containing zone, continent or world map.")
        self.location=UI:Dropdown(nav,300,{},function(id) P.Window:Navigate(id) end)
        self.location:SetOptionsProvider(function() return S:Options() end)
        M.Point(self.location,"LEFT",self.up,"RIGHT",6,0)
        self.dock=CreateFrame("Frame",nil,map)
        M.Point(self.dock,"TOPLEFT",map,"TOPLEFT",0,-S.TOP)
        M.Point(self.dock,"BOTTOMRIGHT",map,"BOTTOMRIGHT",0,S.BOTTOM)
        self.dock:EnableMouse(false)
    end)
    return self.frame
end
function S:Apply(left,right)
    local f=self:Build();if not f then return end
    local map=P:WorldMap();self.active=true
    f:ClearAllPoints();f:SetPoint("TOPLEFT",map,"TOPLEFT",-left,0);f:SetPoint("BOTTOMRIGHT",map,"BOTTOMRIGHT",right,0)
    f:SetSize(map:GetWidth()+left+right,map:GetHeight())
    self.dock:SetSize(map:GetWidth(),math.max(1,map:GetHeight()-M.ToNative(S.TOP+S.BOTTOM)))
    self:Native(map);self:NativeControls(map);f:Show()
    self.chrome:SetMaximized(P.Window:Maximized())
    self.handle:SetShown(P.Window:Movable() and not P.Window:Maximized())
    self.chrome.grip:SetShown(P.Window:CanResize() and not P.Window:Maximized())
    self.location:SetWidth(math.max(M.ToNative(100),map:GetWidth()-M.ToNative(self.controls.filter and 92 or 54)))
    self.location:SetOptions(self:Options())
    local id=map.GetMapID and map:GetMapID()
    self.location:SetValue(id)
    local info=id and P.Call("C_Map.GetMapInfo",id)
    if type(info)=="table" and type(info.parentMapID)=="number" and info.parentMapID>0 and not P.Window:Combat() then self.up:Enable() else self.up:Disable() end
    if P.Window:CanResize() then self.chrome.maximize:Enable() else self.chrome.maximize:Disable() end
    return f
end

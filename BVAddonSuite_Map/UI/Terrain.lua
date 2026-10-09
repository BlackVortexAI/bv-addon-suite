local _,P=...
if not P.ready then return end
-- Terrain map style (Florian 2026-10-08): on zone maps the client's own
-- minimap tiles (Core's MapTerrain) lie over Blizzard's map art and under
-- every pin, so the map works as before (zoom, clicks, tooltips, other
-- addons' pins). The names painted into Blizzard's art are covered, so the
-- area names come from Core's overlay labels, in our font. Continents and
-- the world keep Blizzard's map. A button beside the search switches it;
-- the setting "Map style" too. Tiles load a few per frame and stay cached
-- (with their textures) while you switch zones. Opacity (Florian
-- 2026-10-09): below 100 % Blizzard's map shows through; below
-- LABELALPHA its painted names do, and ours stay away (no names twice).
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local R={shown={},cache={},order={},labels={},spare={}}
P.Terrain=R
local BATCH,CACHE=24,128
R.LABELALPHA=.7

function R:On() return P:Active() and P:Config().mapStyle=="terrain" end
-- Our layer on the canvas: above the exploration overlays (Blizzard's and
-- ours), below every other pin.
function R:Layer(canvas)
    local layer=self.layer
    if not layer then layer=CreateFrame("Frame",nil,canvas);layer:EnableMouse(false);self.layer=layer
    elseif layer:GetParent()~=canvas then layer:SetParent(canvas) end
    layer:ClearAllPoints();layer:SetAllPoints(canvas)
    local map=P:WorldMap()
    local manager=map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    local level
    if manager and manager.GetValidFrameLevel then
        local ok,value=pcall(manager.GetValidFrameLevel,manager,"PIN_FRAME_LEVEL_MAP_EXPLORATION")
        if ok and type(value)=="number" then level=value+1 end
    end
    layer:SetFrameLevel(level or canvas:GetFrameLevel()+1)
    return layer
end
-- Shown tiles go to the cache, textures kept; the oldest beyond CACHE give them up.
function R:Hide()
    for key,tex in pairs(self.shown) do tex:Hide();self.shown[key]=nil;self.cache[key]=tex;self.order[#self.order+1]=key end
    while #self.order>CACHE do
        local key=table.remove(self.order,1)
        local tex=self.cache[key]
        if tex then tex:SetTexture(nil);self.cache[key]=nil;self.spare[#self.spare+1]=tex end
    end
end
function R:Stash()
    self:Hide()
    for _,label in ipairs(self.labels) do label:Hide() end
    if self.layer then self.layer:Hide() end
    self.view=nil
end
function R:Count() local n=0;for _ in pairs(self.shown) do n=n+1 end;return n end
function R:Refresh()
    local canvas,_,map=ns.MapPins:Canvas()
    if not (self:On() and canvas and map and map:IsShown() and map.GetMapID) then return self:Stash() end
    local mapID=map:GetMapID()
    local info=P.Call("C_Map.GetMapInfo",mapID)
    local Terrain=ns.MapTerrain
    local frame=type(info)=="table" and info.mapType==3 and Terrain:Frame(mapID)
    local tile,source
    if frame then tile,source=Terrain:Source(frame.instance) end
    if not tile then return self:Stash() end
    local scale=ns.MapPins:CanvasScale()
    local w,h=canvas:GetWidth(),canvas:GetHeight()
    local view=mapID..":"..source..":"..w..":"..h
    local layer=self:Layer(canvas);layer:Show()
    if self.view~=view then
        -- Another map or size: everything placed anew (textures from the cache).
        self:Hide()
        self.view=view
    end
    local c0,c1,r0,r1=Terrain.Range(frame,0,0,1,1)
    local loaded,pending=0,false
    for c=c0,c1 do
        for r=r0,r1 do
            local key=frame.instance*10000+c*100+r
            if not self.shown[key] then
                local tex=self.cache[key]
                local file=not tex and tile(c,r)
                if tex or file then
                    if file and loaded>=BATCH then pending=true
                    else
                        if tex then
                            self.cache[key]=nil
                            for i=#self.order,1,-1 do if self.order[i]==key then table.remove(self.order,i) end end
                        else
                            loaded=loaded+1
                            tex=table.remove(self.spare) or layer:CreateTexture(nil,"BACKGROUND")
                            -- A file the client lacks: no green placeholder.
                            if not Terrain:Load(tex,file) then self.spare[#self.spare+1]=tex;tex=nil end
                        end
                        if tex and tex:GetParent()~=layer then tex:SetParent(layer) end
                        -- Cut to the map's rectangle (the canvas shows nothing beyond it).
                        local x0,y0,x1,y1=Terrain.Rect(frame,c,r)
                        local u0,v0,u1,v1=math.max(0,x0),math.max(0,y0),math.min(1,x1),math.min(1,y1)
                        if not tex then
                        elseif u1>u0 and v1>v0 then
                            tex:SetTexCoord((u0-x0)/(x1-x0),(u1-x0)/(x1-x0),(v0-y0)/(y1-y0),(v1-y0)/(y1-y0))
                            tex:ClearAllPoints();tex:SetPoint("TOPLEFT",layer,"TOPLEFT",u0*w,-v0*h)
                            tex:SetSize((u1-u0)*w,(v1-v0)*h);tex:Show()
                            self.shown[key]=tex
                        else self.cache[key]=tex;self.order[#self.order+1]=key end
                    end
                end
            end
        end
    end
    local alpha=(P:Config().terrainAlpha or 100)/100
    for _,tex in pairs(self.shown) do tex:SetVertexColor(1,1,1,alpha) end
    -- Area names in our font, kept the same size at every zoom.
    local labels=alpha>=self.LABELALPHA and ns.MapOverlays and ns.MapOverlays:Labels(mapID) or {}
    local named={}
    for _,label in ipairs(labels) do if label.name~="" then named[#named+1]=label end end
    labels=named
    for i,label in ipairs(labels) do
        local text=self.labels[i]
        if not text then
            text=layer:CreateFontString(nil,"OVERLAY");self.labels[i]=text
            if text.SetShadowOffset then text:SetShadowOffset(1,-1);text:SetShadowColor(0,0,0,1) end
        end
        ns.Styles:Font("bv",text,M.ToNative(12)/scale,"bold","OUTLINE")
        text:SetText(label.name);text:SetTextColor(1,.95,.85,.95)
        text:ClearAllPoints();text:SetPoint("CENTER",layer,"TOPLEFT",label.x*w,-label.y*h);text:Show()
    end
    for i=#labels+1,#self.labels do self.labels[i]:Hide() end
    self.scale=scale
    if pending and not self.timer then self.timer=C_Timer.NewTimer(0,function() R.timer=nil;R:Refresh() end) end
end
-- The switch beside the search magnifier.
function R:Button()
    local map=P:WorldMap()
    if self.button or not map then return self.button end
    local parent=map.ScrollContainer or map
    UI:WithStyle(P:Style(),function()
        self.button=P:MapButton(parent,"layers",function() R:Toggle() end)
        self.locate=P:MapButton(parent,"locate-fixed",function() P:Locate() end)
        M.Point(self.locate,"LEFT",self.button,"RIGHT",6,0)
        UI:AttachTooltip(self.locate,"Where am I","Back to your zone with the whole zone in view.")
        -- Remove all waypoints (Florian 2026-10-08).
        self.clear=P:MapButton(parent,"trash-2",function() P.Waypoints:Clear() end)
        M.Point(self.clear,"LEFT",self.locate,"RIGHT",6,0)
        UI:AttachTooltip(self.clear,"Remove all waypoints","Clears the waypoint queue (with TomTom: TomTom keeps its own).")
        UI:AttachTooltip(self.button,"Map style","Terrain (the game's own minimap tiles) or Blizzard's map, on zone maps.")
    end)
    return self.button
end
function R:Toggle()
    local c=P:Config()
    c.mapStyle=c.mapStyle=="terrain" and "blizzard" or "terrain"
    self:Apply()
    if ns.Config then ns.Config:Refresh() end
end
-- Watching the map while it is open: map, zoom and size changes.
function R:Watch(on)
    if on and not self.ticker then
        self.ticker=C_Timer.NewTicker(.2,function()
            local canvas,_,map=ns.MapPins:Canvas()
            if not (map and map:IsShown() and canvas) then return R:Watch(false) end
            if R.scale~=ns.MapPins:CanvasScale() or not R.view or not R.view:find("^"..tostring(map:GetMapID())..":") then R:Refresh() end
        end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function R:Apply()
    local button=P:Active() and self:Button()
    if self.button then
        self.button:SetShown(P:Active() and true or false)
        self.locate:SetShown(P:Active() and true or false)
        self.clear:SetShown(P:Active() and true or false)
        self.button:SetActive(self:On())
        -- Beside the search magnifier, or in its place when the search is off.
        local search=P.Search and P.Search.button
        local parent=self.button:GetParent()
        self.button:ClearAllPoints()
        if search and search:IsShown() then M.Point(self.button,"LEFT",search,"RIGHT",6,0)
        else M.Point(self.button,"TOPLEFT",parent,"TOPLEFT",6,-6) end
    end
    local map=P:WorldMap()
    self:Refresh()
    self:Watch(self:On() and map and map:IsShown() and true or false)
    return button
end
function R:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() R:Apply() end)
        map:HookScript("OnHide",function() R:Watch(false) end)
        if type(map.OnMapChanged)=="function" then hooksecurefunc(map,"OnMapChanged",function() R:Refresh() end) end
    end
    context:Defer(function() R:Watch(false);R:Stash();if R.button then R.button:Hide();R.locate:Hide();R.clear:Hide() end end)
    self:Apply()
end

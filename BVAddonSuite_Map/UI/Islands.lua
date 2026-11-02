local _,P=...
if not P.ready then return end
-- Zones with no continent above them (Florian 2026-10-23, in game on Zephras
-- Isle): C_Map gives Zephras Isle (2521) as a zone right under the world map
-- (947), and the world map has no clickable area for it, so once you left
-- the island's map you could not go back without reopening the map. The
-- world map's art paints the island in the sea between the continents; a
-- button over the painting opens its map, with its name in our font. The
-- client's own rectangle of the zone on the world map wins when it has one.
-- Only the client's parents count: Routing's own continent for the island
-- (2665) is never assumed above 2521.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local I={buttons={}}
P.Islands=I
-- Per world instance: where the world map paints the island (hit, 0..1 of
-- the world map: minX, maxX, minY, maxY) and the rectangle its zone map gets
-- there (rect: the terrain style's overview, the island's land centred on
-- the painting, true to its proportions). Measured on the world map art
-- (interface/worldmap/world/world1..12, client 1.60.1.70532) on 2026-10-23.
I.SPOTS={[2991]={hit={.505,.560,.625,.750},rect={.4884,.5733,.6427,.7276}}}

-- A zone (type 3) whose parents reach no continent (type 2).
function I:Rootless(mapID)
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" or info.mapType~=3 then return false end
    for _=1,8 do
        local parent=info.parentMapID
        if type(parent)~="number" or parent==0 or parent==mapID then return true end
        info=P.Call("C_Map.GetMapInfo",parent)
        if type(info)~="table" then return true end
        if info.mapType==2 then return false end
        mapID=parent
    end
    return true
end
-- The rootless zones lying right under a map (the world map), one per
-- instance (2521 before 2665): mapID, name, rect (the zone map's rectangle
-- there) and hit (where to click).
function I:List(world)
    local out,seen,ids={},{},{}
    for mapID in pairs(P.MAPFRAMES or {}) do ids[#ids+1]=mapID end
    table.sort(ids)
    for _,mapID in ipairs(ids) do
        local frame=P.MAPFRAMES[mapID]
        local info=P.Call("C_Map.GetMapInfo",mapID)
        if not seen[frame.instance] and type(info)=="table" and info.parentMapID==world and self:Rootless(mapID) then
            local spot=self.SPOTS[frame.instance]
            local minX,maxX,minY,maxY
            if P.Seamless then minX,maxX,minY,maxY=P.Seamless:Rect(mapID,world) end
            local rect=minX and {minX,maxX,minY,maxY} or spot and spot.rect
            if rect then
                seen[frame.instance]=true
                local name=type(info.name)=="string" and not P.Secret(info.name) and info.name or ""
                out[#out+1]={mapID=mapID,name=name,instance=frame.instance,rect=rect,hit=minX and rect or spot.hit}
            end
        end
    end
    return out
end
-- A rootless zone's rectangle on a map: the client's, or its spot's.
function I:Rect(mapID,shown)
    for _,island in ipairs(self:List(shown)) do
        if island.mapID==mapID then return island.rect[1],island.rect[2],island.rect[3],island.rect[4] end
    end
end
-- The rootless zone at a point of the world map (0..1), or nil.
function I:At(world,x,y)
    for _,island in ipairs(self:List(world)) do
        local h=island.hit
        if x>=h[1] and x<=h[2] and y>=h[3] and y<=h[4] then return island.mapID end
    end
end
-- Its map (no map changes from here in combat, as on the seamless map).
function I:Open(mapID)
    local map=P:WorldMap()
    if not (map and map.SetMapID) or (InCombatLockdown and InCombatLockdown()) then return false end
    return pcall(map.SetMapID,map,mapID)
end
function I:Button(index,canvas)
    local button=self.buttons[index]
    if not button then
        button=CreateFrame("Button",nil,canvas);button:RegisterForClicks("LeftButtonUp")
        -- The feathered square lights the island under the cursor.
        button.glow=button:CreateTexture(nil,"ARTWORK");button.glow:SetAllPoints(button)
        pcall(button.glow.SetTexture,button.glow,P.Terrain and P.Terrain.MASK or "Interface\\Buttons\\WHITE8X8")
        button.glow:SetVertexColor(1,.95,.85,.25);button.glow:Hide()
        button.label=button:CreateFontString(nil,"OVERLAY")
        if button.label.SetShadowOffset then button.label:SetShadowOffset(1,-1);button.label:SetShadowColor(0,0,0,1) end
        button:SetScript("OnEnter",function(self) self.glow:Show() end)
        button:SetScript("OnLeave",function(self) self.glow:Hide() end)
        button:SetScript("OnClick",function(self) I:Open(self.mapID) end)
        UI:WithStyle(P:Style(),function() UI:AttachTooltip(button,"Island","Click: open its map. It has no area of its own on Blizzard's world map.") end)
        self.buttons[index]=button
    end
    if button:GetParent()~=canvas then button:SetParent(canvas) end
    return button
end
-- On the world map: a button over each rootless zone's island, its name
-- beneath, kept the same size at every zoom.
function I:Refresh()
    local canvas,_,map=ns.MapPins:Canvas()
    local shown=P:Active() and canvas and map and map:IsShown() and map.GetMapID and map:GetMapID()
    local info=type(shown)=="number" and P.Call("C_Map.GetMapInfo",shown)
    local list=type(info)=="table" and info.mapType==1 and self:List(shown) or {}
    local w=canvas and canvas:GetWidth() or 0
    local h=canvas and canvas:GetHeight() or 0
    local scale=ns.MapPins:CanvasScale()
    for i,island in ipairs(list) do
        local button=self:Button(i,canvas)
        local r=island.hit
        button.mapID=island.mapID
        button:SetFrameLevel((P.Terrain and P.Terrain.layer and P.Terrain.layer:GetFrameLevel() or canvas:GetFrameLevel())+10)
        button:ClearAllPoints();button:SetPoint("TOPLEFT",canvas,"TOPLEFT",r[1]*w,-r[3]*h)
        button:SetSize((r[2]-r[1])*w,(r[4]-r[3])*h)
        ns.Styles:Font("bv",button.label,M.ToNative(15)/scale,"bold","OUTLINE")
        button.label:SetText(island.name);button.label:SetTextColor(1,.95,.85,.95)
        button.label:ClearAllPoints();button.label:SetPoint("TOP",button,"BOTTOM",0,-2/scale)
        button.tooltipTitle=island.name~="" and island.name or "Island"
        button:Show()
    end
    for i=#list+1,#self.buttons do self.buttons[i]:Hide() end
    self.scale=scale
end
function I:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() I:Refresh() end)
        if type(map.OnMapChanged)=="function" then hooksecurefunc(map,"OnMapChanged",function() I:Refresh() end) end
        if type(map.OnCanvasScaleChanged)=="function" then hooksecurefunc(map,"OnCanvasScaleChanged",function() if I.scale~=ns.MapPins:CanvasScale() then I:Refresh() end end) end
    end
    context:Defer(function() for _,button in ipairs(I.buttons) do button:Hide() end end)
    self:Refresh()
end

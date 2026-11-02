local _,P=...
if not P.ready then return end
-- Seamless map (Florian 2026-10-22, after OpenMap): one map per continent
-- to pan and zoom over freely, with the terrain tiles for the part in view
-- (UI/Terrain) and zoom levels down to the tiles' own size (UI/Zoom).
-- Blizzard's map keeps its zone maps; ours stays on the continent: a zone
-- map coming up (the map opening on your zone, a click on a zone of the
-- continent, "where am I") becomes the continent map zoomed onto that zone.
-- Dungeons, maps of another instance, the world map and combat (no map
-- changes from here then) keep their native behavior.
local ns=P.ns
local S={frames={}}
P.Seamless=S
-- Pixels an ADT tile (533 1/3 yd) gets at the closest zoom: 1.5 x the
-- tile's own 256, and the step between the levels added.
S.TILEPX=384
S.STEP=1.5
S.MAXLEVELS=12

-- The only map mode while the module is active: painted zones stitched
-- onto the continent, with minimap detail at close zoom (UI/Terrain).
function S:On() return P:Active() end
function S:Combat() return InCombatLockdown and InCombatLockdown() or false end
-- A zone's rectangle on the continent (0..1), or nil.
function S:Rect(zone,cont)
    local minX,maxX,minY,maxY=P.Call("C_Map.GetMapRectOnMap",zone,cont)
    if type(minX)=="number" and type(maxX)=="number" and maxX>minX and type(minY)=="number" and type(maxY)=="number" and maxY>minY and not P.Secret(minX) then
        return minX,maxX,minY,maxY
    end
end
-- The map's frame (Core's MapTerrain: its corners in the world). A
-- continent the client gives no world position for (WoW Forever answers
-- for zones) gets one from a zone's frame and that zone's rectangle on the
-- continent, kept once found.
function S:Frame(mapID)
    local Terrain=ns.MapTerrain
    if not (Terrain and type(mapID)=="number") then return nil end
    local frame=Terrain:Frame(mapID)
    if frame then return frame end
    frame=self.frames[mapID]
    if frame then return frame end
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" or info.mapType~=2 then return nil end
    local children=P.Call("C_Map.GetMapChildrenInfo",mapID,3,true)
    for _,zone in ipairs(type(children)=="table" and children or {}) do
        local zf=type(zone)=="table" and type(zone.mapID)=="number" and Terrain:Frame(zone.mapID)
        local minX,maxX,minY,maxY
        if zf then minX,maxX,minY,maxY=self:Rect(zone.mapID,mapID) end
        if minX then
            local dx,dy=zf.dx/(maxX-minX),zf.dy/(maxY-minY)
            local a={}
            a[zf.ix]=zf.a[zf.ix]-minX*dx
            a[zf.iy]=zf.a[zf.iy]-minY*dy
            frame={instance=zf.instance,a=a,ix=zf.ix,iy=zf.iy,dx=dx,dy=dy,derived=zone.mapID}
            self.frames[mapID]=frame
            return frame
        end
    end
    return nil
end
-- A zone with no continent above it and terrain tiles of its own (Zephras
-- Isle, Florian 2026-10-23: zooming in close showed no detail there): it is
-- its own seamless map, zoom levels down to the tiles' size and the tiles
-- blended in on Blizzard's art (UI/Terrain, Detail). Its frame, or nil.
function S:Alone(mapID)
    if not (P.Islands and P.Islands:Rootless(mapID)) then return nil end
    return self:ZoneFrame(mapID)
end
-- A zone map (type 3) with terrain tiles: its frame, or nil. Such a zone
-- gets the tiles blended in at the closest zooms if its own map stays open.
function S:ZoneFrame(mapID)
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" or info.mapType~=3 then return nil end
    local frame=P.Terrain and P.Terrain:Frame(mapID)
    if frame and ns.MapTerrain:Source(frame.instance) then return frame end
end
-- Whether the client's parents of a map reach another map.
local function under(mapID,top)
    for _=1,8 do
        local info=P.Call("C_Map.GetMapInfo",mapID)
        if type(info)~="table" then return false end
        mapID=info.parentMapID
        if mapID==top then return true end
        if type(mapID)~="number" or mapID==0 then return false end
    end
    return false
end
-- The continent map the seamless map shows for a zone: the zone (type 3)
-- has a valid rectangle on a continent (type 2);
-- only a continent the client itself has above the zone.
function S:ContinentOf(mapID)
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" or info.mapType~=3 or not ns.MapPins then return nil end
    local cont=ns.MapPins:Continent(mapID)
    if not (cont and under(mapID,cont)) then return nil end
    -- Painted maps need only a valid rectangle on their parent continent.
    return self:Rect(mapID,cont) and cont or nil
end
-- Blizzard's art on the continent: the closest zoom shows the smallest
-- zone's art at its own size (its 1002 px across its rectangle), at most
-- MAXSCALE; kept per continent.
S.MAXSCALE=20
S.closest={}
function S:ArtScale(cont)
    local scale=self.closest[cont]
    if scale then return scale end
    local widest=1
    local children=P.Call("C_Map.GetMapChildrenInfo",cont,3,true)
    for _,zone in ipairs(type(children)=="table" and children or {}) do
        local minX,maxX
        if type(zone)=="table" and type(zone.mapID)=="number" then minX,maxX=self:Rect(zone.mapID,cont) end
        if minX and maxX and maxX-minX>0 and maxX-minX<widest then widest=maxX-minX end
    end
    scale=math.min(self.MAXSCALE,1/widest)
    if widest<1 then self.closest[cont]=scale end
    return scale
end
-- Zooms the open continent map onto a zone: the zone fills the view, within
-- the zoom levels (ours added first when the map's own rebuild left them
-- out); the view's middle on the zone's middle.
function S:Zoom(zone,cont)
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    local canvas=scroll and scroll.Child
    if not (canvas and scroll.InstantPanAndZoom) then return false end
    local minX,maxX,minY,maxY=self:Rect(zone,cont)
    if not minX then return false end
    local cw,ch=canvas:GetWidth(),canvas:GetHeight()
    local sw,sh=scroll:GetWidth(),scroll:GetHeight()
    if not (cw>0 and ch>0 and sw>0 and sh>0) then return false end
    if P.Zoom then P.Zoom:Ensure(scroll) end
    local scale=math.min(sw/((maxX-minX)*cw),sh/((maxY-minY)*ch))
    local levels=scroll.zoomLevels
    if type(levels)=="table" and #levels>0 and type(levels[1])=="table" and type(levels[#levels])=="table" then
        local lo,hi=levels[1].scale,levels[#levels].scale
        if type(lo)=="number" and type(hi)=="number" then scale=math.max(math.min(lo,hi),math.min(math.max(lo,hi),scale)) end
    end
    pcall(scroll.InstantPanAndZoom,scroll,scale,(minX+maxX)/2,(minY+maxY)/2)
    return true
end
-- Shows a zone on the seamless map: the continent, zoomed onto the zone.
-- false when the zone is not covered (then Blizzard's zone map is right).
function S:Focus(zone)
    local map=P:WorldMap()
    if not (self:On() and map and map.SetMapID and map.GetMapID) or self:Combat() then return false end
    local cont=self:ContinentOf(zone)
    if not cont then return false end
    if map:GetMapID()~=cont then
        self.redirecting=true
        local ok=pcall(map.SetMapID,map,cont)
        self.redirecting=false
        if not ok then return false end
    end
    self.focus=nil
    self:Zoom(zone,cont)
    return true
end
-- Blizzard changed the map: a zone becomes its continent at once (no zone
-- map shown), the zoom onto the zone a moment later, after Blizzard's own
-- zoom reset of the batch. A remembered view coming back on this map
-- (P.Window, the map just reopened) cancels that zoom.
function S:Changed()
    if self.redirecting or not self:On() or self:Combat() then return end
    local map=P:WorldMap()
    local mapID=map and map.GetMapID and map:GetMapID()
    if type(mapID)~="number" or P.Secret(mapID) then return end
    local cont=self:ContinentOf(mapID)
    if not cont then return end
    self.redirecting=true
    pcall(map.SetMapID,map,cont)
    self.redirecting=false
    self.focus=mapID
    if self.pending then return end
    self.pending=C_Timer.NewTimer(0,function()
        S.pending=nil
        local zone=S.focus;S.focus=nil
        if not (zone and S:On()) or S:Combat() then return end
        local m=P:WorldMap()
        if not (m and m:IsShown() and m.GetMapID and m:GetMapID()==cont) then return end
        S:Zoom(zone,cont)
    end)
end
-- The zoom levels a continent or a zone with tiles gets beyond Blizzard's
-- last one (last: its scale): up to the tiles' own size, or nil (a
-- map without supported detail).
function S:Levels(scroll,last)
    local map=P:WorldMap()
    local mapID=map and map.GetMapID and map:GetMapID()
    local canvas=scroll and scroll.Child
    if not (P:Active() and type(mapID)=="number" and canvas and type(last)=="number" and last>0) then return nil end
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" then return nil end
    -- The seamless continent, or an isolated zone with tiles while they blend in.
    local zone=info.mapType==3 and self:ZoneFrame(mapID)
    if info.mapType==2 then
        if not self:On() then return nil end
    elseif not (zone and (P:Config().blend or 0)>0) then return nil end
    -- Down to the tiles' own size; without tiles, to the smallest zone's art.
    local target
    local Terrain=ns.MapTerrain
    local frame=zone or self:Frame(mapID)
    local across=frame and Terrain:Source(frame.instance) and math.abs(frame.dx)/Terrain.ADT
    local width=canvas:GetWidth()
    if across and across>0 and width>0 then target=self.TILEPX*across/width
    else
        target=self:ArtScale(mapID)
        if target<=1 then return nil end
    end
    -- Deeper over the cities (Florian 2026-10-27, after OpenMap): down to a
    -- city map's own size (its art's width across its rectangle, Ironforge
    -- about 680 px per ADT tile); elsewhere the wheel stops at the tiles' size
    -- (Wheel, self.limit).
    local deep=target
    if info.mapType==2 then deep=math.max(target,self:CityScale(mapID,width)) end
    local out,scale,limit={},last,nil
    while scale<deep and #out<self.MAXLEVELS do
        scale=scale*self.STEP;out[#out+1]=scale
        if not limit and scale>=target then limit=scale end
    end
    self.limit=deep>target and limit and {mapID=mapID,scale=limit} or nil
    return out
end
-- The scale at which the smallest city of a continent shows its own map at
-- its own size, or 0.
function S:CityScale(cont,width)
    local R=P.Terrain
    if not (R and R.IsCity and width>0) then return 0 end
    local best=0
    for _,zone in ipairs(R:Zones(cont)) do
        if R:IsCity(zone.mapID) then
            local layers=P.Call("C_Map.GetMapArtLayers",zone.mapID)
            local art=type(layers)=="table" and type(layers[1])=="table" and layers[1] or {}
            local LW=(art.layerWidth or 0)>0 and art.layerWidth or 1002
            best=math.max(best,LW/((zone.maxX-zone.minX)*width))
        end
    end
    return best
end
-- Whether a point of a continent (0..1) lies in one of its cities.
function S:InCity(cont,x,y)
    local R=P.Terrain
    if not (R and R.IsCity) then return false end
    for _,zone in ipairs(R:Zones(cont)) do
        if x>=zone.minX and x<=zone.maxX and y>=zone.minY and y<=zone.maxY and R:IsCity(zone.mapID) then return true end
    end
    return false
end
-- A changed setting: the zone map shown becomes the seamless map; the
-- continent's zoom levels follow (P.Zoom).
function S:Apply()
    local map=P:WorldMap()
    if not (map and map:IsShown() and map.GetMapID) then return end
    if P.Zoom then P.Zoom:Apply() end
    if self:On() then
        local mapID=map:GetMapID()
        if type(mapID)=="number" and self:ContinentOf(mapID) then self:Focus(mapID) end
    end
end
-- The mouse wheel across maps (Florian 2026-10-22: the whole map without a
-- click): wheeling back on a continent that already shows whole goes to
-- the world map; wheeling forward on the world map over a continent (or a
-- zone of its own there, Zephras Isle) opens it where the cursor is.
-- Blizzard's own zoom has run before this (a hook): the zoom it aimed at
-- last time tells whether the continent was already at its smallest.
function S:ZoomTarget(scroll)
    if type(scroll.targetScale)=="number" then return scroll.targetScale end
    local ok,scale=pcall(scroll.GetCanvasScale,scroll)
    return ok and type(scale)=="number" and scale or nil
end
function S:MinScale(scroll)
    local levels=scroll.zoomLevels
    local first=type(levels)=="table" and levels[1]
    return type(first)=="table" and type(first.scale)=="number" and first.scale or nil
end
-- The middle of a continent's land (its zones' rectangles), 0..1 of its map.
function S:LandCentre(cont)
    local zones=P.Terrain and P.Terrain:Zones(cont) or {}
    local minX,maxX,minY,maxY
    for _,zone in ipairs(zones) do
        minX=math.min(minX or zone.minX,zone.minX);maxX=math.max(maxX or zone.maxX,zone.maxX)
        minY=math.min(minY or zone.minY,zone.minY);maxY=math.max(maxY or zone.maxY,zone.maxY)
    end
    if not minX then return .5,.5 end
    return (minX+maxX)/2,(minY+maxY)/2
end
-- After the jump from the world map onto a continent the cursor lies
-- elsewhere on the new map (Florian 2026-10-22: the next wheels zoomed into
-- the sea): for CENTRE seconds after each wheel the zoom goes to the middle
-- of the continent's land instead of the cursor.
S.CENTRE=.8
function S:Wheel(delta)
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    if not (self:On() and scroll and map.GetMapID and map.SetMapID) or self:Combat() then return end
    local mapID=map:GetMapID()
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" then return end
    local now=GetTime and GetTime() or 0
    if delta>0 and info.mapType==2 and self.centreUntil and now<self.centreUntil then
        local target=self:ZoomTarget(scroll)
        local cx,cy=self:LandCentre(mapID)
        if target and scroll.InstantPanAndZoom then pcall(scroll.InstantPanAndZoom,scroll,target,cx,cy) end
        self.centreUntil=now+self.CENTRE
        return
    end
    self.centreUntil=nil
    -- Past the tiles' own size only over a city: elsewhere the zoom stays at it.
    local limit=self.limit
    if delta>0 and info.mapType==2 and limit and limit.mapID==mapID then
        local target=self:ZoomTarget(scroll)
        if target and target>limit.scale*1.001 then
            local ok,x,y=false
            if scroll.GetNormalizedCursorPosition then ok,x,y=pcall(scroll.GetNormalizedCursorPosition,scroll) end
            if not (ok and type(x)=="number" and type(y)=="number") then
                x=scroll.GetNormalizedHorizontalScroll and scroll:GetNormalizedHorizontalScroll() or .5
                y=scroll.GetNormalizedVerticalScroll and scroll:GetNormalizedVerticalScroll() or .5
            end
            if not self:InCity(mapID,x,y) then
                if type(scroll.SetZoomTarget)=="function" then pcall(scroll.SetZoomTarget,scroll,limit.scale)
                elseif scroll.InstantPanAndZoom then
                    local h=scroll.GetNormalizedHorizontalScroll and scroll:GetNormalizedHorizontalScroll() or .5
                    local v=scroll.GetNormalizedVerticalScroll and scroll:GetNormalizedVerticalScroll() or .5
                    pcall(scroll.InstantPanAndZoom,scroll,limit.scale,h,v)
                end
            end
        end
        self.lastTarget=nil
        return
    end
    if delta<0 and info.mapType==2 then
        local min,target=self:MinScale(scroll),self:ZoomTarget(scroll)
        local wasSmallest=self.lastTarget and min and self.lastTarget<=min*1.001
        self.lastTarget=target
        local parent=info.parentMapID
        if wasSmallest and type(parent)=="number" and parent>0 then
            self.lastTarget=nil
            if type(map.NavigateToParentMap)=="function" then pcall(map.NavigateToParentMap,map) else pcall(map.SetMapID,map,parent) end
        end
    elseif delta>0 and info.mapType==1 and scroll.GetNormalizedCursorPosition then
        local ok,x,y=pcall(scroll.GetNormalizedCursorPosition,scroll)
        if not (ok and type(x)=="number" and type(y)=="number") then return end
        local children=P.Call("C_Map.GetMapChildrenInfo",mapID,nil,false)
        for _,child in ipairs(type(children)=="table" and children or {}) do
            if type(child)=="table" and type(child.mapID)=="number" and (child.mapType==2 or child.mapType==3) then
                local minX,maxX,minY,maxY=self:Rect(child.mapID,mapID)
                if minX and x>=minX and x<=maxX and y>=minY and y<=maxY then
                    self.lastTarget=nil
                    pcall(map.SetMapID,map,child.mapID)
                    -- The continent whole, the next wheels zooming onto its land's middle.
                    local min=self:MinScale(scroll)
                    local cx,cy=self:LandCentre(child.mapID)
                    if min and scroll.InstantPanAndZoom then pcall(scroll.InstantPanAndZoom,scroll,min,cx,cy) end
                    self.centreUntil=now+self.CENTRE
                    return
                end
            end
        end
        -- A zone with no area of its own there (Zephras Isle): its island.
        local island=P.Islands and P.Islands:At(mapID,x,y)
        if island then self.lastTarget=nil;pcall(map.SetMapID,map,island) end
    else self.lastTarget=nil end
end
function S:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        if type(map.OnMapChanged)=="function" then hooksecurefunc(map,"OnMapChanged",function() S.lastTarget=nil;S:Changed() end) end
        local scroll=map.ScrollContainer
        if scroll and scroll.HookScript then scroll:HookScript("OnMouseWheel",function(_,delta) S:Wheel(delta) end) end
    end
    context:Defer(function() if S.pending then S.pending:Cancel();S.pending=nil end;S.focus=nil end)
    self:Apply()
end

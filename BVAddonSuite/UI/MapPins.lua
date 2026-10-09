local _,ns=...
-- Map pins (Core 0.8.96, docs/map-gather-plan.md phase 2): one pin layer
-- for every package, on the world map and the minimap. A provider hands in
-- points (map ID and 0..1 coordinates, any map: they are moved onto the map
-- shown through the world position) and may ask for lines between them (a
-- waypoint path). Pins keep their size at any zoom; minimap pins follow its
-- zoom, shape and rotation, and may stick to the edge when far away.
-- Blizzard's map stays Blizzard's: our pins live on frames of our own on top
-- of its canvas. Refreshed by light tickers only while something shows (no
-- per-frame scripts in this project).
local UI,M=ns.UI,ns.DesignSystem.Metrics
local P={providers={},order={},worldPins={},worldLines={},miniPins={}}
ns.MapPins=P
local WHITE="Interface\\Buttons\\WHITE8X8"
-- A filled white disc (Blizzard's round portrait mask) behind every pin.
local DISC="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
-- Minimap view diameters in yards per zoom level when the client cannot
-- tell (outdoor, indoor); C_Minimap.GetViewRadius is used when present.
local OUTDOOR={[0]=466+2/3,[1]=400,[2]=333+1/3,[3]=266+2/3,[4]=200,[5]=133+1/3}
local INDOOR={[0]=300,[1]=240,[2]=180,[3]=120,[4]=80,[5]=50}

local function call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
local function secret(value) return issecretvalue and issecretvalue(value) or false end
local function xy(vector)
    if type(vector)~="table" and type(vector)~="userdata" then return nil end
    if type(vector.GetXY)=="function" then
        local ok,x,y=pcall(vector.GetXY,vector)
        if ok and type(x)=="number" and not secret(x) then return x,y end
        return nil
    end
    if type(vector.x)=="number" then return vector.x,vector.y end
end
P.Call,P.XY=call,xy

-- provider: points() -> {{mapID,x,y,symbol,color={r,g,b},size,key,...}}, or
-- pointsFor(mapID) for large sets (only the points of that map: no world
-- conversion per point, e.g. thousands of gathering nodes),
-- lines (true: connect the points in order), minimap (true: show there too),
-- point.disc {r,g,b} (another pin ground), point.dim (fainter on the
-- minimap: another level than the player), point.noPin (only the line to
-- it, e.g. a loop closing on its first point), point.lead (a line from you
-- to it in point.leadColor: the leg you walk now), point.dot (a small dot
-- instead of a pin), point.alpha / point.lineAlpha (opacity of its pin and
-- of the line to it), arrows (true: chevrons
-- along the lines show the way, Florian 2026-10-08),
-- edge (true: far points stick to the minimap's edge), world (false: the
-- minimap only, for a provider that splits world map and minimap lists),
-- onClick(point,button),
-- onDrag(point,mapID,x,y) (pins can be dragged), tooltip(point) -> title,text.
function P:Register(id,provider)
    assert(type(id)=="string" and type(provider)=="table" and (type(provider.points)=="function" or type(provider.pointsFor)=="function"),"Invalid map pin provider")
    if not self.providers[id] then self.order[#self.order+1]=id end
    self.providers[id]=provider
    self:Hook()
    self:Refresh()
end
function P:Unregister(id)
    if not self.providers[id] then return end
    self.providers[id]=nil
    for i=#self.order,1,-1 do if self.order[i]==id then table.remove(self.order,i) end end
    self:Refresh()
end
-- Something of a provider changed: everything is painted anew.
P.revision=0
function P:Refresh()
    self.revision=self.revision+1
    self:PaintWorld()
    self:PaintMinimap()
end

-- The provider's points for a map (all of them, or only that map's).
function P:Points(provider,mapID)
    local ok,points
    if provider.pointsFor then ok,points=pcall(provider.pointsFor,mapID) else ok,points=pcall(provider.points) end
    if ok and type(points)=="table" then return points end
    return nil
end
-- Moves a point onto another map; nil when the two maps share no
-- continent. Through the world position first; where the client gives no
-- answer there (WoW Forever, probe 2026-10-08), through the maps' rectangles
-- on their continent (C_Map.GetMapRectOnMap).
P.moved=setmetatable({},{__mode="k"})
function P:OnMap(point,mapID,remember)
    if point.mapID==mapID then return point.x,point.y end
    if type(mapID)~="number" or type(point.mapID)~="number" then return nil end
    -- remember: the point is a lasting table (a provider's cached points, a
    -- followed route) and keeps where it lies on the last map it was moved
    -- to (two client calls each, for every point of a long route on every
    -- repaint, made the frame rate drop; Florian 2026-10-09). Throwaway
    -- points never do: a memo for each made the route editor lag.
    if not remember then return self:Move(point,mapID) end
    local memo=self.moved[point]
    if memo and memo.map==mapID and memo.from==point.mapID and memo.px==point.x and memo.py==point.y then
        if memo.x then return memo.x,memo.y end
        return nil
    end
    local x,y=self:Move(point,mapID)
    if not memo then memo={};self.moved[point]=memo end
    memo.map,memo.from,memo.px,memo.py,memo.x,memo.y=mapID,point.mapID,point.x,point.y,x or false,y
    return x,y
end
function P:Move(point,mapID)
    local vector=rawget(_G,"CreateVector2D")
    if vector then
        local continent,world=call("C_Map.GetWorldPosFromMapPos",point.mapID,vector(point.x,point.y))
        if continent and world then
            -- It returns the map ID first, then the position.
            local _,position=call("C_Map.GetMapPosFromWorldPos",continent,world,mapID)
            local x,y=xy(position)
            if x then return x,y end
        end
    end
    return self:ViaRects(point,mapID)
end
-- A map's rectangle on an ancestor map (0..1 of that map), or nil.
local function rect(mapID,top)
    local minX,maxX,minY,maxY=call("C_Map.GetMapRectOnMap",mapID,top)
    if type(minX)=="number" and type(maxX)=="number" and maxX>minX and type(minY)=="number" and maxY>minY and not secret(minX) then
        return minX,maxX,minY,maxY
    end
end
-- The continent a map lies on (map type 2), or nil.
function P:Continent(mapID)
    for _=1,8 do
        local info=call("C_Map.GetMapInfo",mapID)
        if type(info)~="table" then return nil end
        if info.mapType==2 then return mapID end
        mapID=info.parentMapID
        if type(mapID)~="number" or mapID==0 then return nil end
    end
end
function P:ViaRects(point,mapID)
    -- The shown map contains the point's map (a zone's point on its continent).
    local minX,maxX,minY,maxY=rect(point.mapID,mapID)
    if minX then return minX+point.x*(maxX-minX),minY+point.y*(maxY-minY) end
    -- The point's map contains the shown one (a continent point on a zone).
    minX,maxX,minY,maxY=rect(mapID,point.mapID)
    if minX then return (point.x-minX)/(maxX-minX),(point.y-minY)/(maxY-minY) end
    -- Two zones of one continent: through the continent.
    local continent=self:Continent(point.mapID)
    if not continent or continent~=self:Continent(mapID) then return nil end
    local aMinX,aMaxX,aMinY,aMaxY=rect(point.mapID,continent)
    local bMinX,bMaxX,bMinY,bMaxY=rect(mapID,continent)
    if not (aMinX and bMinX) then return nil end
    local cx,cy=aMinX+point.x*(aMaxX-aMinX),aMinY+point.y*(aMaxY-aMinY)
    return (cx-bMinX)/(bMaxX-bMinX),(cy-bMinY)/(bMaxY-bMinY)
end

-- Chevrons along a line (x, y relative to the anchor, y up): every SPACING
-- pixels a ">" of two short lines pointing from the first point to the
-- second, light so they read on any line colour. store: the pool.
function P:Chevrons(store,overlay,anchor,point,x1,y1,x2,y2,size,thickness,spacing,count,alpha)
    local dx,dy=x2-x1,y2-y1
    local length=math.sqrt(dx*dx+dy*dy)
    if length<spacing*.75 then return count end
    local ux,uy=dx/length,dy/length
    local n=math.max(1,math.floor(length/spacing))
    local start=(length-(n-1)*spacing)/2
    for k=0,n-1 do
        local d=start+k*spacing+size/2
        local tx,ty=x1+ux*d,y1+uy*d
        local bx,by=tx-ux*size,ty-uy*size
        for side=-1,1,2 do
            count=count+1
            local line=store[count]
            if not line then line=overlay:CreateLine(nil,"OVERLAY",nil,3);line:SetTexture(WHITE);store[count]=line end
            if line:GetParent()~=overlay then line:SetParent(overlay) end
            line:SetVertexColor(1,1,1,.9*(alpha or 1));line:SetThickness(thickness)
            line:SetStartPoint(point,anchor,bx-uy*size*.65*side,by+ux*size*.65*side)
            line:SetEndPoint(point,anchor,tx,ty)
            line:Show()
        end
    end
    return count
end

-- World map ---------------------------------------------------------------------------
local function worldMap() return rawget(_G,"WorldMapFrame") end
function P:Canvas()
    local map=worldMap()
    local scroll=map and map.ScrollContainer
    return scroll and scroll.Child or nil,scroll,map
end
function P:CanvasScale()
    local _,scroll=self:Canvas()
    if scroll and scroll.GetCanvasScale then
        local ok,scale=pcall(scroll.GetCanvasScale,scroll)
        if ok and type(scale)=="number" and scale>0 then return scale end
    end
    return 1
end
-- A dark filled disc, a ring in the point's colour and the symbol in it:
-- readable on the light parchment of the world map and on the minimap
-- (Florian 2026-10-08: yellow on yellow was hard to see).
local function paintIcon(pin,point,size)
    -- point.dot: only a small filled dot in the point's colour (routes:
    -- many points stay readable, Florian 2026-10-08).
    if point.dot then
        local c=point.color or {1,.82,.2}
        -- point.hollow: a ring only (Florian 2026-10-09: a filled dot looked
        -- like the game's own tracking dot).
        if point.hollow then
            pin.disc:SetVertexColor(0,0,0,0);pin.ring:Show();pin.ring:SetVertexColor(c[1],c[2],c[3],1)
        else pin.disc:SetVertexColor(c[1],c[2],c[3],1);pin.ring:Hide() end
        pin.icon:Hide()
        return
    end
    pin.ring:Show();pin.icon:Show()
    local symbol=point.symbol or "map-pin"
    local path,l,r,t,b=ns.Symbols:Coords(symbol,size)
    if path then pin.icon:SetTexture(path);pin.icon:SetTexCoord(l,r,t,b) end
    local c=point.color or {1,.82,.2}
    pin.icon:SetVertexColor(c[1],c[2],c[3],1)
    -- point.disc: another ground (e.g. earth brown for underground nodes).
    local d=point.disc or {.06,.06,.08}
    pin.disc:SetVertexColor(d[1],d[2],d[3],.88)
    pin.ring:SetVertexColor(c[1],c[2],c[3],1)
end
local function pinTextures(pin)
    pin.disc=pin:CreateTexture(nil,"BACKGROUND");pin.disc:SetAllPoints(pin);pin.disc:SetTexture(DISC)
    pin.ring=pin:CreateTexture(nil,"BORDER");pin.ring:SetAllPoints(pin)
    local path,l,r,t,b=ns.Symbols:Coords("circle",32)
    if path then pin.ring:SetTexture(path);pin.ring:SetTexCoord(l,r,t,b) else pin.ring:SetTexture(WHITE) end
    pin.icon=pin:CreateTexture(nil,"ARTWORK");pin.icon:SetPoint("CENTER")
end
-- Our layer above Blizzard's map tiles and pins: those live on their own
-- frames with high levels (its pin level manager), so frames or lines right
-- on the canvas stay hidden beneath them while still taking the mouse
-- (Florian 2026-10-08: tooltips, but no pins or lines).
function P:Overlay(canvas)
    local overlay=self.overlay
    if not overlay then
        overlay=CreateFrame("Frame",nil,canvas);overlay:EnableMouse(false)
        self.overlay=overlay
    elseif overlay:GetParent()~=canvas then overlay:SetParent(canvas) end
    overlay:ClearAllPoints();overlay:SetAllPoints(canvas)
    local map=worldMap()
    local level
    local manager=map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if manager and manager.GetValidFrameLevel then
        local ok,value=pcall(manager.GetValidFrameLevel,manager,"PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
        if ok and type(value)=="number" then level=value+1 end
    end
    level=math.min(9000,math.max(level or 0,canvas:GetFrameLevel()+2000))
    overlay:SetFrameLevel(level)
    return overlay
end
function P:WorldPin(index,canvas)
    local pin=self.worldPins[index]
    local overlay=self:Overlay(canvas)
    if pin then if pin:GetParent()~=overlay then pin:SetParent(overlay) end;return pin end
    pin=CreateFrame("Button",nil,overlay);pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
    pinTextures(pin)
    pin.label=pin:CreateFontString(nil,"OVERLAY");pin.label:SetPoint("BOTTOM",pin,"TOP",0,2)
    pin:SetScript("OnClick",function(owner,button) local p=owner.provider;if p and p.onClick then p.onClick(owner.point,button) end end)
    pin:SetScript("OnEnter",function(owner)
        local p=owner.provider;if not (p and p.tooltip) then return end
        local title,text=p.tooltip(owner.point)
        if title then UI:ShowTooltip(owner,title,text or "") end
    end)
    pin:SetScript("OnLeave",function(owner) UI:HideTooltip(owner) end)
    pin:RegisterForDrag("LeftButton")
    pin:SetScript("OnDragStart",function(owner) P:StartDrag(owner) end)
    pin:SetScript("OnDragStop",function(owner) P:StopDrag(owner) end)
    self.worldPins[index]=pin
    return pin
end
-- A coloured line over a wider dark one, so it reads on any map.
function P:WorldLine(index,canvas)
    local line=self.worldLines[index]
    if line then return line end
    local overlay=self:Overlay(canvas)
    line=overlay:CreateLine(nil,"OVERLAY",nil,2)
    line:SetTexture(WHITE)
    line.shadow=overlay:CreateLine(nil,"OVERLAY",nil,1)
    line.shadow:SetTexture(WHITE)
    local show,hide=line.Show,line.Hide
    function line:Show() show(self);self.shadow:Show() end
    function line:Hide() hide(self);self.shadow:Hide() end
    self.worldLines[index]=line
    return line
end
-- Paints every provider's points on the map shown (and their lines).
function P:PaintWorld()
    local canvas,_,map=self:Canvas()
    local used,lines,arrows=0,0,0
    if canvas and map and map:IsShown() and map.GetMapID then
        local shown=map:GetMapID()
        local scale=self:CanvasScale()
        local w,h=canvas:GetWidth(),canvas:GetHeight()
        self.worldArrows=self.worldArrows or {}
        local playerX,playerY=xy(call("C_Map.GetPlayerMapPosition",shown,"player"))
        for _,id in ipairs(self.order) do
            local provider=self.providers[id]
            local points
            if provider.world~=false then points=self:Points(provider,shown) end
            if points then
                local previous
                for _,point in ipairs(points) do
                    local x,y=self:OnMap(point,shown,true)
                    if x and x>=-.05 and x<=1.05 and y>=-.05 and y<=1.05 then
                        -- The leg you walk now: from you to this point.
                        if point.lead and playerX then
                            lines=lines+1
                            local line=self:WorldLine(lines,canvas)
                            local c=point.leadColor or point.color or {1,1,1}
                            line:SetVertexColor(c[1],c[2],c[3],.95*(point.lineAlpha or 1));line:SetThickness(M.ToNative(3)/scale)
                            line.shadow:SetVertexColor(0,0,0,.7*(point.lineAlpha or 1));line.shadow:SetThickness(M.ToNative(6)/scale)
                            for _,l in ipairs({line,line.shadow}) do
                                l:SetStartPoint("TOPLEFT",canvas,playerX*w,-playerY*h);l:SetEndPoint("TOPLEFT",canvas,x*w,-y*h)
                            end
                            line:Show()
                            if provider.arrows then
                                arrows=self:Chevrons(self.worldArrows,self:Overlay(canvas),canvas,"TOPLEFT",playerX*w,-playerY*h,x*w,-y*h,
                                    M.ToNative(5)/scale,M.ToNative(1.6)/scale,M.ToNative(46)/scale,arrows,point.lineAlpha)
                            end
                        end
                        if not point.noPin then
                        used=used+1
                        local pin=self:WorldPin(used,canvas)
                        pin.provider,pin.point,pin.mapID=provider,point,shown
                        local size=M.ToNative(point.size or 18)/scale
                        pin:SetSize(size,size);pin.icon:SetSize(size*.62,size*.62)
                        pin:ClearAllPoints();pin:SetPoint("CENTER",canvas,"TOPLEFT",x*w,-y*h)
                        pin:SetFrameLevel(self.overlay:GetFrameLevel()+1)
                        paintIcon(pin,point,M.ToNative(point.size or 18))
                        pin:SetAlpha(point.alpha or 1)
                        if point.label then
                            ns.Styles:Font("bv",pin.label,M.ToNative(11)/scale,"bold","OUTLINE")
                            pin.label:SetText(point.label);pin.label:Show()
                        else pin.label:Hide() end
                        pin:EnableMouse(provider.onClick~=nil or provider.tooltip~=nil or provider.onDrag~=nil)
                        pin:Show()
                        end
                        if provider.lines and previous then
                            lines=lines+1
                            local line=self:WorldLine(lines,canvas)
                            local c=point.lineColor or point.color or {1,.82,.2}
                            line:SetVertexColor(c[1],c[2],c[3],.95*(point.lineAlpha or 1))
                            line:SetThickness(M.ToNative(2.5)/scale)
                            line.shadow:SetVertexColor(0,0,0,.7*(point.lineAlpha or 1))
                            line.shadow:SetThickness(M.ToNative(5)/scale)
                            for _,l in ipairs({line,line.shadow}) do
                                l:SetStartPoint("TOPLEFT",canvas,previous[1]*w,-previous[2]*h)
                                l:SetEndPoint("TOPLEFT",canvas,x*w,-y*h)
                            end
                            line:Show()
                            if provider.arrows then
                                arrows=self:Chevrons(self.worldArrows,self:Overlay(canvas),canvas,"TOPLEFT",previous[1]*w,-previous[2]*h,x*w,-y*h,
                                    M.ToNative(5)/scale,M.ToNative(1.6)/scale,M.ToNative(46)/scale,arrows,point.lineAlpha)
                            end
                        end
                        previous={x,y}
                    elseif provider.lines then previous=nil end
                end
            end
        end
        self.view={shown,scale,w,h}
    end
    for i=used+1,#self.worldPins do self.worldPins[i]:Hide();self.worldPins[i].point=nil end
    for i=lines+1,#self.worldLines do self.worldLines[i]:Hide() end
    for i=arrows+1,#(self.worldArrows or {}) do self.worldArrows[i]:Hide() end
    self:WorldWatch(used>0 or lines>0)
end
-- The map's zoom, size or shown map changed: paint again (five times a
-- second while pins are on an open map).
function P:WorldWatch(on)
    local map=worldMap()
    on=on and map and map:IsShown()
    if on and not self.worldTicker then
        self.worldTicker=C_Timer.NewTicker(.2,function()
            local canvas,_,m=P:Canvas()
            if not (m and m:IsShown() and canvas) then return P:WorldWatch(false) end
            local view=P.view or {}
            if view[1]~=m:GetMapID() or view[2]~=P:CanvasScale() or view[3]~=canvas:GetWidth() or view[4]~=canvas:GetHeight() then P:PaintWorld() end
        end)
    elseif not on and self.worldTicker then self.worldTicker:Cancel();self.worldTicker=nil end
end
-- Dragging a pin: it follows the cursor on the canvas; on release the
-- provider gets the new position on the map shown.
function P:StartDrag(pin)
    local provider=pin.provider
    if not (provider and provider.onDrag) then return end
    local _,scroll=self:Canvas()
    if not (scroll and scroll.GetNormalizedCursorPosition) then return end
    self.dragging=pin
    if self.dragTicker then self.dragTicker:Cancel() end
    self.dragTicker=C_Timer.NewTicker(.03,function()
        local canvas=P:Canvas()
        local ok,x,y=pcall(scroll.GetNormalizedCursorPosition,scroll)
        if ok and type(x)=="number" and canvas then
            pin:ClearAllPoints();pin:SetPoint("CENTER",canvas,"TOPLEFT",x*canvas:GetWidth(),-y*canvas:GetHeight())
        end
    end)
end
function P:StopDrag(pin)
    if self.dragTicker then self.dragTicker:Cancel();self.dragTicker=nil end
    if self.dragging~=pin then return end
    self.dragging=nil
    local _,scroll=self:Canvas()
    local ok,x,y=pcall(scroll.GetNormalizedCursorPosition,scroll)
    if ok and type(x)=="number" and x>=0 and x<=1 and y>=0 and y<=1 and pin.provider and pin.provider.onDrag then
        pcall(pin.provider.onDrag,pin.point,pin.mapID,x,y)
    end
    self:Refresh()
end

-- Minimap ---------------------------------------------------------------------------
-- Yards from the minimap's centre to its edge.
function P:MinimapRadius()
    local radius=call("C_Minimap.GetViewRadius")
    if type(radius)=="number" and radius>0 and not secret(radius) then return radius end
    local minimap=rawget(_G,"Minimap")
    local zoom=minimap and minimap.GetZoom and minimap:GetZoom() or 0
    local indoors=call("IsIndoors")==true
    return ((indoors and INDOOR or OUTDOOR)[zoom] or 300)/2
end
-- The minimap pins and lines sit on a layer of their own over the minimap.
-- Normally it is the minimap's child; a host (Gather's HUD) may take it, so
-- the minimap's opacity fades the map but not the pins (Florian 2026-10-09:
-- "the lines full, only the background see-through").
function P:MinimapLayer(minimap)
    minimap=minimap or rawget(_G,"Minimap")
    if not minimap then return nil end
    local layer=self.miniLayer
    if not layer then
        layer=CreateFrame("Frame",nil,minimap);layer:EnableMouse(false);layer.bvKeep=true
        self.miniLayer=layer
    end
    -- Placed again only when host, strata or level changed (asked per pin).
    local host=self.miniHost or minimap
    local key=tostring(host)..minimap:GetFrameStrata()..minimap:GetFrameLevel()
    if layer.placed~=key then
        layer.placed=key
        if layer:GetParent()~=host then layer:SetParent(host) end
        layer:ClearAllPoints();layer:SetAllPoints(minimap)
        layer:SetFrameStrata(minimap:GetFrameStrata());layer:SetFrameLevel(minimap:GetFrameLevel()+5)
    end
    return layer
end
-- host: a frame that is not faded with the minimap, or nil (the minimap again).
function P:SetMinimapHost(host)
    self.miniHost=host
    self:MinimapLayer()
    self.miniView=nil
    self:PaintMinimap()
end
function P:MinimapPin(index,minimap)
    local pin=self.miniPins[index]
    if pin then return pin end
    pin=CreateFrame("Button",nil,self:MinimapLayer(minimap));pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
    -- Ours: a HUD that hides other addons' minimap buttons keeps it.
    pin.bvKeep=true
    pinTextures(pin)
    pin:SetScript("OnClick",function(owner,button) local p=owner.provider;if p and p.onClick then p.onClick(owner.point,button) end end)
    pin:SetScript("OnEnter",function(owner)
        local p=owner.provider;if not (p and p.tooltip) then return end
        local title,text=p.tooltip(owner.point)
        if title then UI:ShowTooltip(owner,title,text or "") end
    end)
    pin:SetScript("OnLeave",function(owner) UI:HideTooltip(owner) end)
    self.miniPins[index]=pin
    return pin
end
-- A segment between two minimap points (radius 1 = the edge), cut to what
-- lies inside the round or square minimap; nil when nothing does.
local function clip(x1,y1,x2,y2,square)
    local dx,dy=x2-x1,y2-y1
    local t0,t1=0,1
    if square then
        for _,edge in ipairs({{-dx,x1+1},{dx,1-x1},{-dy,y1+1},{dy,1-y1}}) do
            local p,q=edge[1],edge[2]
            if p==0 then if q<0 then return nil end
            else
                local r=q/p
                if p<0 then if r>t1 then return nil elseif r>t0 then t0=r end
                else if r<t0 then return nil elseif r<t1 then t1=r end end
            end
        end
    else
        local a=dx*dx+dy*dy
        if a==0 then return nil end
        local b=2*(x1*dx+y1*dy)
        local c=x1*x1+y1*y1-1
        local disc=b*b-4*a*c
        if disc<=0 then return nil end
        local root=math.sqrt(disc)
        t0=math.max(0,(-b-root)/(2*a));t1=math.min(1,(-b+root)/(2*a))
        if t0>=t1 then return nil end
    end
    return x1+t0*dx,y1+t0*dy,x1+t1*dx,y1+t1*dy
end
function P:MinimapLine(index,minimap)
    local layer=self:MinimapLayer(minimap)
    if not self.miniOverlay then
        self.miniOverlay=CreateFrame("Frame",nil,layer);self.miniOverlay:EnableMouse(false);self.miniOverlay.bvKeep=true
        self.miniOverlay:SetAllPoints(minimap)
    end
    self.miniOverlay:SetFrameLevel(layer:GetFrameLevel()+1)
    self.miniLines=self.miniLines or {}
    local line=self.miniLines[index]
    if line then return line end
    line=self.miniOverlay:CreateLine(nil,"OVERLAY",nil,2);line:SetTexture(WHITE)
    line.shadow=self.miniOverlay:CreateLine(nil,"OVERLAY",nil,1);line.shadow:SetTexture(WHITE)
    local show,hide=line.Show,line.Hide
    function line:Show() show(self);self.shadow:Show() end
    function line:Hide() hide(self);self.shadow:Hide() end
    self.miniLines[index]=line
    return line
end
function P:PaintMinimap()
    local minimap=rawget(_G,"Minimap")
    local used,lines,arrows=0,0,0
    self.miniArrows=self.miniArrows or {}
    local playerMap=call("C_Map.GetBestMapForUnit","player")
    local px,py,width,height
    if type(playerMap)=="number" then
        px,py=xy(call("C_Map.GetPlayerMapPosition",playerMap,"player"))
        width,height=call("C_Map.GetMapWorldSize",playerMap)
    end
    if minimap and minimap:IsShown() and px and type(width)=="number" and width>0 then
        local radius=self:MinimapRadius()
        local half=minimap:GetWidth()/2
        local rotate=call("GetCVar","rotateMinimap")=="1"
        local facing=rotate and call("GetPlayerFacing") or 0
        if type(facing)~="number" or secret(facing) then facing=0 end
        local square=call("GetMinimapShape")=="SQUARE"
        -- Nothing moved, turned, zoomed or changed since the last time: the
        -- pins stay as they are (Florian 2026-10-09: high CPU while idle).
        local view=string.format("%d:%.5f:%.5f:%.3f:%.1f:%.1f:%d",playerMap,px,py,facing,radius,half,self.revision)
        if view==self.miniView then return end
        self.miniView=view
        for _,id in ipairs(self.order) do
            local provider=self.providers[id]
            if provider.minimap then
                local points=self:Points(provider,playerMap)
                if points then
                    local previous,lastX,lastY
                    for _,point in ipairs(points) do
                        local x,y=self:OnMap(point,playerMap,true)
                        if not x then previous=nil end
                        if x then
                            local east,north=(x-px)*width,-(y-py)*height
                            if rotate then
                                local c,s=math.cos(-facing),math.sin(-facing)
                                east,north=east*c-north*s,east*s+north*c
                            end
                            local dx,dy=east/radius,north/radius
                            -- The leg you walk now: from the minimap's middle (you) to this point.
                            if point.lead then
                                local x1,y1,x2,y2=clip(0,0,dx,dy,square)
                                if x1 then
                                    lines=lines+1
                                    local line=self:MinimapLine(lines,minimap)
                                    local c=point.leadColor or point.color or {1,1,1}
                                    line:SetVertexColor(c[1],c[2],c[3],.95*(point.lineAlpha or 1));line:SetThickness(M.ToNative(2.5))
                                    line.shadow:SetVertexColor(0,0,0,.6*(point.lineAlpha or 1));line.shadow:SetThickness(M.ToNative(5))
                                    for _,l in ipairs({line,line.shadow}) do
                                        l:SetStartPoint("CENTER",minimap,x1*half,y1*half);l:SetEndPoint("CENTER",minimap,x2*half,y2*half)
                                    end
                                    line:Show()
                                    if provider.arrows then
                                        arrows=self:Chevrons(self.miniArrows,self.miniOverlay,minimap,"CENTER",x1*half,y1*half,x2*half,y2*half,
                                            M.ToNative(4),M.ToNative(1.4),M.ToNative(26),arrows,point.lineAlpha)
                                    end
                                end
                            end
                            -- The path between this point and the one before,
                            -- cut at the minimap's edge (Florian 2026-10-08).
                            if provider.lines and previous then
                                local x1,y1,x2,y2=clip(lastX,lastY,dx,dy,square)
                                if x1 then
                                    lines=lines+1
                                    local line=self:MinimapLine(lines,minimap)
                                    local c=point.lineColor or point.color or {1,.82,.2}
                                    line:SetVertexColor(c[1],c[2],c[3],.95*(point.lineAlpha or 1));line:SetThickness(M.ToNative(2))
                                    line.shadow:SetVertexColor(0,0,0,.6*(point.lineAlpha or 1));line.shadow:SetThickness(M.ToNative(4))
                                    for _,l in ipairs({line,line.shadow}) do
                                        l:SetStartPoint("CENTER",minimap,x1*half,y1*half);l:SetEndPoint("CENTER",minimap,x2*half,y2*half)
                                    end
                                    line:Show()
                                    if provider.arrows then
                                        arrows=self:Chevrons(self.miniArrows,self.miniOverlay,minimap,"CENTER",x1*half,y1*half,x2*half,y2*half,
                                            M.ToNative(4),M.ToNative(1.4),M.ToNative(26),arrows,point.lineAlpha)
                                    end
                                end
                            end
                            -- No table per point (garbage on every repaint).
                            previous,lastX,lastY=true,dx,dy
                            local far
                            if square then far=math.max(math.abs(dx),math.abs(dy))>1 else far=dx*dx+dy*dy>1 end
                            if (not far or provider.edge) and not point.noPin then
                                if far then
                                    local scale=square and math.max(math.abs(dx),math.abs(dy)) or math.sqrt(dx*dx+dy*dy)
                                    dx,dy=dx/scale,dy/scale
                                end
                                used=used+1
                                local pin=self:MinimapPin(used,minimap)
                                pin.provider,pin.point=provider,point
                                local size=M.ToNative((point.size or 18)*(far and .7 or .8))
                                pin:SetSize(size,size);pin.icon:SetSize(size*.62,size*.62)
                                pin:ClearAllPoints();pin:SetPoint("CENTER",minimap,"CENTER",dx*half,dy*half)
                                pin:SetFrameLevel(self:MinimapLayer(minimap):GetFrameLevel()+3)
                                paintIcon(pin,point,size)
                                -- point.dim: on another level than you (cave or surface).
                                pin:SetAlpha((far and .6 or 1)*(point.dim and .45 or 1)*(point.alpha or 1))
                                pin:EnableMouse(provider.onClick~=nil or provider.tooltip~=nil)
                                pin:Show()
                            end
                        end
                    end
                end
            end
        end
    end
    if used==0 and lines==0 then self.miniView=nil end
    for i=used+1,#self.miniPins do self.miniPins[i]:Hide();self.miniPins[i].point=nil end
    for i=lines+1,#(self.miniLines or {}) do self.miniLines[i]:Hide() end
    for i=arrows+1,#self.miniArrows do self.miniArrows[i]:Hide() end
    self:MinimapWatch(self:HasMinimapPoints())
end
function P:HasMinimapPoints()
    for _,id in ipairs(self.order) do
        local provider=self.providers[id]
        if provider.minimap then
            local playerMap=call("C_Map.GetBestMapForUnit","player")
            local points=self:Points(provider,playerMap)
            if points and #points>0 then return true end
        end
    end
    return false
end
-- Ten times a second while a provider shows on the minimap (you move).
function P:MinimapWatch(on)
    if on and not self.miniTicker then self.miniTicker=C_Timer.NewTicker(.1,function() P:PaintMinimap() end)
    elseif not on and self.miniTicker then self.miniTicker:Cancel();self.miniTicker=nil end
end

-- The world map: pins on show, gone on hide (its map changes too).
function P:Hook()
    local map=worldMap()
    if self.hooked or not map then return end
    self.hooked=true
    map:HookScript("OnShow",function() P:PaintWorld() end)
    map:HookScript("OnHide",function() P:PaintWorld() end)
    if map.OnMapChanged then hooksecurefunc(map,"OnMapChanged",function() P:PaintWorld() end) end
end

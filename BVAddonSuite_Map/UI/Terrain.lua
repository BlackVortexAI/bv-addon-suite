local _,P=...
if not P.ready then return end
-- Seamless painted maps with minimap detail blended in only at close zoom.
-- Tiles load in batches and remain cached while panning or changing zones.
-- Map pins, clicks and Blizzard's own world map keep their original layers.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local R={shown={},cache={},order={},labels={},leaders={},spare={},fills={},arts={},masks={},zones={}}
P.Terrain=R
local BATCH,CACHE=24,640
-- The sea colour: the mean of the client's dark water tiles (measured by
-- tools/build_map_overviews.py, Data/Overviews), so fills and water meet
-- without an edge.
R.SEA=P.SEA or {5/255,5/255,5/255}
-- Seamless map: tiles for the part in view and this much of the view's
-- size around it; beyond SEAMLESSMAX tiles, keep the painted map.
R.MARGIN=.5
R.SEAMLESSMAX=600
-- Tiles of instances Core's file list lacks (Zephras Isle): into Core's
-- table once, so MapTerrain serves them like the others.
for instance,data in pairs(P.TILES or {}) do
    if ns.MinimapTileData and ns.MinimapTileData[instance]==nil then ns.MinimapTileData[instance]=data end
end

-- The tiles blended in at close zoom on Blizzard's zone maps (setting
-- "blend"), including isolated zones.
function R:Blending() return P:Active() and (P:Config().blend or 0)>0 end
-- A map's frame: a known correction first (Zephras Isle, whose world
-- position the client reports on Kalimdor), then the seamless map's (a
-- continent's from a zone), then Core's.
function R:Frame(mapID)
    local over=P.MAPFRAMES and P.MAPFRAMES[mapID]
    if over then return over end
    if P.Seamless then return P.Seamless:Frame(mapID) end
    return ns.MapTerrain:Frame(mapID)
end
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
-- A shown tile goes to the cache, texture kept.
function R:Release(key)
    local tex=self.shown[key]
    if not tex then return end
    tex:Hide();self.shown[key]=nil;self.cache[key]=tex;self.order[#self.order+1]=key
end
-- The oldest cached tiles beyond CACHE give their textures up.
function R:Trim()
    while #self.order>CACHE do
        local key=table.remove(self.order,1)
        local tex=self.cache[key]
        if tex then tex:SetTexture(nil);self.cache[key]=nil;self.spare[#self.spare+1]=tex end
    end
end
function R:Hide()
    for key in pairs(self.shown) do self:Release(key) end
    self:Trim()
    self:Fills(0)
end
function R:Stash()
    self:Hide()
    self:Shown(self.arts,0)
    for _,mask in ipairs(self.masks) do mask:Hide() end
    if self.landMask then self.landMask:Hide() end
    if self.paper then self.paper:Hide() end
    self:Shown(self.labels,0)
    self:Shown(self.leaders,0)
    if self.layer then self.layer:Hide() end
    self.view=nil
end
function R:Count() local n=0;for _ in pairs(self.shown) do n=n+1 end;return n end
local function visible(list) local n=0;for _,item in ipairs(list) do if item:IsShown() then n=n+1 end end;return n end
function R:FillCount() return visible(self.fills) end
function R:ArtCount() return visible(self.arts) end
-- Entries from index on are hidden.
function R:Shown(list,from) for i=from+1,#list do list[i]:Hide() end end
function R:Fills(from) self:Shown(self.fills,from) end
-- A rectangle (0..1 of the map) in the sea colour.
function R:Fill(index,layer,u0,v0,u1,v1,w,h,alpha)
    local fill=self.fills[index]
    if not fill then fill=layer:CreateTexture(nil,"BACKGROUND",nil,-1);fill:SetDrawLayer("BACKGROUND",-1);self.fills[index]=fill end
    if fill:GetParent()~=layer then fill:SetParent(layer) end
    fill:SetColorTexture(self.SEA[1],self.SEA[2],self.SEA[3],alpha)
    fill:ClearAllPoints();fill:SetPoint("TOPLEFT",layer,"TOPLEFT",u0*w,-v0*h)
    fill:SetSize((u1-u0)*w,(v1-v0)*h);fill:Show()
end
-- Where the scroll frame looks on the canvas (0..1), plus the margin: from
-- the view's middle (the normalized scroll) and its size in canvas units.
function R:Window(scroll,canvas,scale,margin)
    if not (scroll and scroll.GetNormalizedHorizontalScroll and scroll.GetNormalizedVerticalScroll) then return 0,0,1,1 end
    local okH,cx=pcall(scroll.GetNormalizedHorizontalScroll,scroll)
    local okV,cy=pcall(scroll.GetNormalizedVerticalScroll,scroll)
    local w,h=canvas:GetWidth()*scale,canvas:GetHeight()*scale
    if not (okH and okV and type(cx)=="number" and type(cy)=="number" and w>0 and h>0) then return 0,0,1,1 end
    local overscan=1+2*(margin or self.MARGIN)
    local hw,hh=scroll:GetWidth()/2/w*overscan,scroll:GetHeight()/2/h*overscan
    if hw<=0 or hh<=0 then return 0,0,1,1 end
    return math.max(0,cx-hw),math.max(0,cy-hh),math.min(1,cx+hw),math.min(1,cy+hh)
end
-- What the watcher compares to see a pan or a resized view.
function R:PanKey(scroll)
    if not (scroll and scroll.GetNormalizedHorizontalScroll and scroll.GetNormalizedVerticalScroll) then return "" end
    local okH,h=pcall(scroll.GetNormalizedHorizontalScroll,scroll)
    local okV,v=pcall(scroll.GetNormalizedVerticalScroll,scroll)
    if not (okH and okV and type(h)=="number" and type(v)=="number") then return "" end
    return string.format("%.3f:%.3f:%d:%d",h,v,scroll:GetWidth(),scroll:GetHeight())
end
-- Label placement uses canvas units for both glyph extents and anchors. The
-- visible rectangle excludes the tile prefetch margin, so offscreen zones
-- cannot consume rows or send a leader into the viewport.
local function overlaps(a,b)
    return math.abs(a.x-b.x)<a.halfWidth+b.halfWidth and math.abs(a.y-b.y)<a.halfHeight+b.halfHeight
end

-- At this column, jump past occupied rows until the next free baseline.
local function freeRow(item,x,direction,placed,top,bottom,startY)
    local y=math.max(top+item.halfHeight,math.min(startY or item.anchorY,bottom-item.halfHeight))
    while y-item.halfHeight>=top and y+item.halfHeight<=bottom do
        local nextY=y
        for _,other in ipairs(placed) do
            if math.abs(x-other.x)<item.halfWidth+other.halfWidth then
                local clearance=item.halfHeight+other.halfHeight
                if math.abs(y-other.y)<clearance then
                    local edge=other.y+direction*(clearance+.01)
                    nextY=direction<0 and math.min(nextY,edge) or math.max(nextY,edge)
                end
            end
        end
        if nextY==y then return y end
        y=nextY
    end
end

local function packLabels(items,left,top,right,bottom,unit)
    local placed={}
    local west,east=right,left
    for i,a in ipairs(items) do
        if a.x-a.halfWidth<left or a.x+a.halfWidth>right or a.y-a.halfHeight<top or a.y+a.halfHeight>bottom then a.callout=true end
        for j=i+1,#items do
            local b=items[j]
            if overlaps(a,b) then a.callout,b.callout=true,true end
        end
    end
    for _,a in ipairs(items) do
        if a.callout then west=math.min(west,a.anchorX);east=math.max(east,a.anchorX)
        else placed[#placed+1]=a end
    end
    -- Keep north/south order stable, including coincident anchors.
    table.sort(items,function(a,b)
        if a.anchorY~=b.anchorY then return a.anchorY<b.anchorY end
        if a.anchorX~=b.anchorX then return a.anchorX<b.anchorX end
        return a.index<b.index
    end)
    for _,item in ipairs(items) do
        if item.callout then
            local bestScore,bestX,bestY,bestSide
            for side=-1,1,2 do
                local x=side<0 and math.max(left+item.halfWidth,west-24*unit-item.halfWidth)
                    or math.min(right-item.halfWidth,east+24*unit+item.halfWidth)
                if (x-item.anchorX)*side>=item.halfWidth+6*unit and x-item.halfWidth>=left and x+item.halfWidth<=right then
                    for direction=-1,1,2 do
                        local y=freeRow(item,x,direction,placed,top,bottom)
                        if y then
                            local score=math.abs(x-item.anchorX)+2*math.abs(y-item.anchorY)
                            if not bestScore or score<bestScore then bestScore,bestX,bestY,bestSide=score,x,y,side end
                        end
                    end
                end
            end
            -- Narrow portrait views can have room above/below the zone even
            -- when its localized name cannot fit in either side column.
            if not bestX and 2*item.halfWidth<=right-left then
                local x=math.max(left+item.halfWidth,math.min(item.anchorX,right-item.halfWidth))
                for direction=-1,1,2 do
                    local offset=item.halfHeight+10*unit
                    local y=freeRow(item,x,direction,placed,top,bottom,item.anchorY+direction*offset)
                    if y and (y-item.anchorY)*direction>=offset then
                        local score=math.abs(y-item.anchorY)
                        if not bestScore or score<bestScore then
                            bestScore,bestX,bestY=score,x,y
                            item.vertical=direction
                        end
                    end
                end
            end
            item.x,item.y,item.side=bestX,bestY,bestSide
            if bestX then placed[#placed+1]=item end
        end
    end
end

function R:Leader(index,layer,x1,y1,x2,y2,unit)
    local line=self.leaders[index]
    if not line then
        line=layer:CreateLine(nil,"ARTWORK");self.leaders[index]=line
        line:SetColorTexture(.96,.82,.57,.84)
    end
    line:SetThickness(unit)
    line:SetStartPoint("TOPLEFT",layer,x1,-y1)
    line:SetEndPoint("TOPLEFT",layer,x2,-y2)
    line:Show()
end

function R:PaintLabels(labels,layer,w,h,scale,scroll)
    local items={}
    local u0,v0,u1,v1=self:Window(scroll,layer:GetParent(),scale,0)
    local left,top,right,bottom=u0*w,v0*h,u1*w,v1*h
    local unit=M.ToNative(1)/scale
    for _,label in ipairs(labels) do
        local x,y=label.x*w,label.y*h
        if x>=left and x<=right and y>=top and y<=bottom then
            local index=#items+1
            local text=self.labels[index]
            if not text then
                text=layer:CreateFontString(nil,"OVERLAY");self.labels[index]=text
                text:SetWordWrap(false)
                if text.SetShadowOffset then text:SetShadowOffset(1,-1);text:SetShadowColor(0,0,0,1) end
            end
            ns.Styles:Font("bv",text,unit*(label.big and 18 or label.zone and 15 or 12),"bold","OUTLINE")
            text:SetText(label.name);text:SetTextColor(1,.95,.85,.95)
            items[index]={index=index,text=text,anchorX=x,anchorY=y,x=x,y=y,
                halfWidth=text:GetStringWidth()/2+3*unit,halfHeight=text:GetStringHeight()/2+2*unit}
        end
    end
    packLabels(items,left,top,right,bottom,unit)
    local lines=0
    for _,item in ipairs(items) do
        local text=item.text
        if item.x then
            text:ClearAllPoints();text:SetPoint("CENTER",layer,"TOPLEFT",item.x,-item.y);text:Show()
            if item.side then
                local endX=item.x-item.side*item.halfWidth
                local bendX=endX-item.side*5*unit
                self:Leader(lines+1,layer,item.anchorX,item.anchorY,bendX,item.y,unit)
                self:Leader(lines+2,layer,bendX,item.y,endX,item.y,unit)
                lines=lines+2
            elseif item.vertical then
                self:Leader(lines+1,layer,item.anchorX,item.anchorY,item.x,item.y-item.vertical*item.halfHeight,unit)
                lines=lines+1
            end
        else text:Hide() end
    end
    self:Shown(self.labels,#items)
    self:Shown(self.leaders,lines)
end
-- A continent's zones with their rectangles, large first (a town inside a
-- zone comes later and lies on top); built once per continent.
function R:Zones(cont)
    local list=self.zones[cont]
    if list then return list end
    list={}
    local children=P.Call("C_Map.GetMapChildrenInfo",cont,3,true)
    for _,zone in ipairs(type(children)=="table" and children or {}) do
        local minX,maxX,minY,maxY
        if type(zone)=="table" and type(zone.mapID)=="number" and P.Seamless then minX,maxX,minY,maxY=P.Seamless:Rect(zone.mapID,cont) end
        if minX then
            list[#list+1]={mapID=zone.mapID,name=type(zone.name)=="string" and not P.Secret(zone.name) and zone.name or "",
                minX=minX,maxX=maxX,minY=minY,maxY=maxY,area=(maxX-minX)*(maxY-minY)}
        end
    end
    table.sort(list,function(a,b) if a.area~=b.area then return a.area>b.area end return a.mapID<b.mapID end)
    for i,zone in ipairs(list) do
        for j=1,i-1 do
            local outer=list[j]
            if zone.minX>=outer.minX and zone.maxX<=outer.maxX and zone.minY>=outer.minY and zone.maxY<=outer.maxY then zone.inner=true end
        end
    end
    if #list>0 then self.zones[cont]=list end
    return list
end
-- The tiles of a window (columns c0..c1, rows r0..r1) placed on the layer,
-- a few loaded per frame, the rest on the next; those outside the window go
-- back to the cache. alpha: their opacity; withFills: the sea colour where a
-- tile is missing or flat sea; sub: their sublevel. The number of fills.
function R:Tiles(frame,tile,layer,w,h,c0,c1,r0,r1,alpha,withFills,sub)
    local Terrain=ns.MapTerrain
    for key in pairs(self.shown) do
        local c,r=math.floor(key%10000/100),key%100
        if c<c0 or c>c1 or r<r0 or r>r1 then self:Release(key) end
    end
    self:Trim()
    local loaded,pending,fills=0,false,0
    local seas=P.SEATILES and P.SEATILES[frame.instance]
    for c=c0,c1 do
        for r=r0,r1 do
            local key=frame.instance*10000+c*100+r
            if not self.shown[key] then
                local tex=self.cache[key]
                local file=not tex and tile(c,r)
                -- A flat sea file (Data/Overviews): the fill instead.
                if file and seas and seas[c*100+r] then file=nil end
                local missing=not (tex or file)
                -- Cut to the map's rectangle (the canvas shows nothing beyond it).
                local tx0,ty0,tx1,ty1=Terrain.Rect(frame,c,r)
                local u0,v0,u1,v1=math.max(0,tx0),math.max(0,ty0),math.min(1,tx1),math.min(1,ty1)
                local inside=u1>u0 and v1>v0
                if (tex or file) and inside then
                    if file and loaded>=BATCH then pending=true
                    else
                        if tex then
                            self.cache[key]=nil
                            for i=#self.order,1,-1 do if self.order[i]==key then table.remove(self.order,i) end end
                        else
                            loaded=loaded+1
                            tex=table.remove(self.spare) or layer:CreateTexture(nil,"BACKGROUND")
                            -- A file the client lacks: no green placeholder, the sea instead.
                            if not Terrain:Load(tex,file) then self.spare[#self.spare+1]=tex;tex=nil;missing=true end
                        end
                        if tex then
                            if tex:GetParent()~=layer then tex:SetParent(layer) end
                            tex:SetTexCoord((u0-tx0)/(tx1-tx0),(u1-tx0)/(tx1-tx0),(v0-ty0)/(ty1-ty0),(v1-ty0)/(ty1-ty0))
                            tex:ClearAllPoints();tex:SetPoint("TOPLEFT",layer,"TOPLEFT",u0*w,-v0*h)
                            tex:SetSize((u1-u0)*w,(v1-v0)*h);tex:Show()
                            self.shown[key]=tex
                        end
                    end
                elseif tex then self.cache[key]=tex;self.order[#self.order+1]=key end
                if withFills and missing and inside then fills=fills+1;self:Fill(fills,layer,u0,v0,u1,v1,w,h,alpha) end
            end
        end
    end
    for _,tex in pairs(self.shown) do tex:SetVertexColor(1,1,1,alpha);tex:SetDrawLayer("BACKGROUND",sub) end
    if pending and not self.timer then self.timer=C_Timer.NewTimer(0,function() R.timer=nil;R:Refresh() end) end
    return fills
end
-- The feathered square (Media/Overview/mask.tga, tools/build_map_overviews.py):
-- stretched to an overlay's and to a zone's rectangle it fades the pieces'
-- edges into the neighbour (docs/map-seamless-plan.md).
R.MASK="Interface\\AddOns\\BVAddonSuite_Map\\Media\\Overview\\mask"
-- Blank parchment (cut from a zone map's own base art, tiled) for land no
-- zone map reaches, under the land mask (Florian 2026-10-22: flat colour
-- looked like mud). One repeat of the tile spans this many canvas pixels.
R.PAPER="Interface\\AddOns\\BVAddonSuite_Map\\Media\\Overview\\parchment"
R.PAPERPX=240
-- Blizzard's map on the seamless continent: the zones' art whenever at
-- most STITCHMAX zones are in view, which is always on a continent
-- (Florian 2026-10-22: the painted zones came in far too late, the whole
-- continent never showed as one painting); zone names while at least
-- NAMEZONES are in view, the tiles blended in from BLENDPX pixels per tile on.
R.STITCHMAX=64
R.NAMEZONES=4
-- The tiles come in from BLENDPX pixels per tile on and are fully there
-- (the painting gone, Florian 2026-10-22: both over each other looked odd)
-- from BLENDFULL on, the setting "blend" being their final opacity.
R.BLENDPX=120
R.BLENDFULL=240
-- A mask from the pool, anchored to a rectangle (0..1 of the map); nil
-- without mask textures in the client.
function R:Mask(index,layer,x0,y0,x1,y1,w,h,file)
    local mask=self.masks[index]
    file=file or self.MASK
    if not mask then
        if type(layer.CreateMaskTexture)~="function" then return nil end
        mask=layer:CreateMaskTexture()
        self.masks[index]=mask
    end
    if mask.file~=file then
        if mask.SetTexture then pcall(mask.SetTexture,mask,file,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE") end
        mask.file=file
    end
    mask:ClearAllPoints();mask:SetPoint("TOPLEFT",layer,"TOPLEFT",x0*w,-y0*h)
    mask:SetSize(math.max(1,(x1-x0)*w),math.max(1,(y1-y0)*h));mask:Show()
    return mask
end
-- The masks a piece carries, replaced as a whole.
local function setMasks(tex,a,b)
    if type(tex.AddMaskTexture)~="function" then return end
    local old=tex.bvMasks
    if old and old[1]==a and old[2]==b then return end
    if old and type(tex.RemoveMaskTexture)=="function" then for _,m in ipairs(old) do tex:RemoveMaskTexture(m) end end
    local list={}
    if a then tex:AddMaskTexture(a);list[#list+1]=a end
    if b then tex:AddMaskTexture(b);list[#list+1]=b end
    tex.bvMasks=list
end
-- A zone's painted land (its overlays, explored and unexplored alike, Core's
-- MapOverlays) in its rectangle on the continent: pieces of the art's tile
-- size cut to their content, each masked on its overlay's and on its
-- zone's rectangle. used, masks: the pools' counts so far; the new counts.
-- The land of the instance as a mask (Data/Overviews' land texture, its
-- alpha the terrain data's land): on the zones' base art it keeps the
-- painted land and drops the painted sea and parchment borders.
function R:LandMask(layer,frame,land,w,h)
    if type(layer.CreateMaskTexture)~="function" then return nil end
    local mask=self.landMask
    if not mask then mask=layer:CreateMaskTexture();self.landMask=mask end
    if mask.file~=land.file then
        if mask.SetTexture then pcall(mask.SetTexture,mask,land.file,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE") end
        mask.file=land.file
    end
    local Terrain=ns.MapTerrain
    local x0,y0=Terrain.Rect(frame,land.c0,land.r0)
    local _,_,x1,y1=Terrain.Rect(frame,land.c1,land.r1)
    if not (x1>x0 and y1>y0) then return nil end
    -- The texture is a power of two with the land in its top left part: the
    -- mask spans the whole texture, so no texture coordinates are needed
    -- (a mask texture may not take them, Florian 2026-10-22: no base art).
    local tw,th=(land.c1-land.c0+1)*land.ppt/land.width,(land.r1-land.r0+1)*land.ppt/land.height
    mask:ClearAllPoints();mask:SetPoint("TOPLEFT",layer,"TOPLEFT",x0*w,-y0*h)
    mask:SetSize((x1-x0)*w/tw,(y1-y0)*h/th);mask:Show()
    self.baseCount=0
    return mask
end
-- A piece of a zone's art on the layer: file, cut and place, masks, sublevel.
function R:Piece(layer,used,file,pw,ph,fw,fh,x,y,width,height,sub,alpha,maskA,maskB)
    local tex=self.arts[used+1]
    if not tex then tex=layer:CreateTexture(nil,"BACKGROUND");self.arts[used+1]=tex end
    if tex:GetParent()~=layer then tex:SetParent(layer) end
    if tex.file~=file then
        if ns.MapTerrain:Load(tex,file) then tex.file=file else tex.file=nil end
    end
    if not tex.file then return used end
    tex:SetDrawLayer("BACKGROUND",sub)
    tex:SetTexCoord(0,pw/fw,0,ph/fh)
    tex:ClearAllPoints();tex:SetPoint("TOPLEFT",layer,"TOPLEFT",x,y)
    tex:SetSize(width,height);tex:SetVertexColor(1,1,1,alpha or 1)
    setMasks(tex,maskA,maskB)
    tex:Show()
    return used+1
end
function R:ZoneArt(zone,layer,w,h,used,masks,alpha,landMask)
    local overlays=ns.MapOverlays and ns.MapOverlays:All(zone.mapID) or {}
    if #overlays==0 then return used,masks end
    local layers=P.Call("C_Map.GetMapArtLayers",zone.mapID)
    local art=type(layers)=="table" and type(layers[1])=="table" and layers[1] or {}
    local LW=(art.layerWidth or 0)>0 and art.layerWidth or 1002
    local LH=(art.layerHeight or 0)>0 and art.layerHeight or 668
    local TW=(art.tileWidth or 0)>0 and art.tileWidth or 256
    local TH=(art.tileHeight or 0)>0 and art.tileHeight or 256
    local rw,rh=zone.maxX-zone.minX,zone.maxY-zone.minY
    masks=masks+1
    local zoneMask=self:Mask(masks,layer,zone.minX,zone.minY,zone.maxX,zone.maxY,w,h)
    -- The zone's base art beneath (Florian 2026-10-22: the zone maps draw
    -- past their borders, the land between zones as parchment with the
    -- mountains' line drawing, the look of unknown land in the game), cut
    -- to the land by the land mask, faded at the zone's edge.
    if landMask then
        local textures=P.Call("C_Map.GetMapArtLayerTextures",zone.mapID,1)
        if type(textures)=="table" then
            local cols,rows=math.ceil(LW/TW),math.ceil(LH/TH)
            for j=0,rows-1 do
                for i=0,cols-1 do
                    local file=textures[j*cols+i+1]
                    if file then
                        local pw,ph=math.min(TW,LW-i*TW),math.min(TH,LH-j*TH)
                        local fw,fh=16,16
                        while fw<pw do fw=fw*2 end
                        while fh<ph do fh=fh*2 end
                        local before=used
                        used=self:Piece(layer,used,file,pw,ph,fw,fh,(zone.minX+i*TW/LW*rw)*w,-(zone.minY+j*TH/LH*rh)*h,pw/LW*rw*w,ph/LH*rh*h,-1,alpha,zoneMask,landMask)
                        if used>before then self.baseCount=(self.baseCount or 0)+1 end
                    end
                end
            end
        end
    end
    for _,info in ipairs(overlays) do
        local width,height,files=info.textureWidth or 0,info.textureHeight or 0,info.fileDataIDs
        if width>0 and height>0 and type(files)=="table" then
            local ox,oy=info.offsetX or 0,info.offsetY or 0
            masks=masks+1
            local overlayMask=self:Mask(masks,layer,zone.minX+ox/LW*rw,zone.minY+oy/LH*rh,zone.minX+(ox+width)/LW*rw,zone.minY+(oy+height)/LH*rh,w,h)
            local wide,tall=math.ceil(width/TW),math.ceil(height/TH)
            for j=1,tall do
                local ph,fh=TH,TH
                if j==tall then ph=height%TH;if ph==0 then ph=TH end;fh=16;while fh<ph do fh=fh*2 end end
                for k=1,wide do
                    local pw,fw=TW,TW
                    if k==wide then pw=width%TW;if pw==0 then pw=TW end;fw=16;while fw<pw do fw=fw*2 end end
                    local file=files[(j-1)*wide+k]
                    if file then
                        local x,y=zone.minX+(ox+TW*(k-1))/LW*rw,zone.minY+(oy+TH*(j-1))/LH*rh
                        used=self:Piece(layer,used,file,pw,ph,fw,fh,x*w,-y*h,pw/LW*rw*w,ph/LH*rh*h,zone.inner and 1 or 0,alpha,overlayMask,zoneMask)
                    end
                end
            end
        end
    end
    return used,masks
end
-- The capitals (Florian 2026-10-27, after OpenMap): a zone map without
-- exploration overlays is a city's own map (Orgrimmar, Undercity and so on).
-- On the seamless continent it lies in its rectangle above the tiles, cut down
-- to its plan (Media/Overview/city_<uiMapID>, tools/build_map_overviews.py:
-- parchment, frame, crest and name banner gone, a wide soft edge), in both map
-- styles; a city without a cut gets the round feather. It comes in as it grows
-- on screen: from CITYFADE[1] to CITYFADE[2] of the view's width (sooner where
-- the zone paints it as no more than a blur). CITYTILES: how far the minimap
-- tiles may still show through it (0: the city map stays whole above them,
-- Florian's choice; 1: they take over as on the zones; between: a cap).
R.CITYDIR="Interface\\AddOns\\BVAddonSuite_Map\\Media\\Overview\\city_"
R.ROUND="Interface\\AddOns\\BVAddonSuite_Map\\Media\\Overview\\mask_round"
R.CITYCUTS={[1453]=true,[1454]=true,[1455]=true,[1456]=true,[1457]=true,[1458]=true}
R.CITYFADE={.2,.4}
R.CITYFADEOF={[1454]={.08,.25},[1456]={.08,.25}}
R.CITYTILES=0
R.CITYLEVEL=3
-- A zone map (type 3) with art and no overlays at all: a city.
function R:IsCity(mapID)
    local info=P.Call("C_Map.GetMapInfo",mapID)
    if type(info)~="table" or info.mapType~=3 then return false end
    if #(ns.MapOverlays and ns.MapOverlays:All(mapID) or {})>0 then return false end
    local textures=P.Call("C_Map.GetMapArtLayerTextures",mapID,1)
    return type(textures)=="table" and textures[1]~=nil
end
-- The mask a city's map is cut with.
function R:CityMask(mapID) return self.CITYCUTS[mapID] and self.CITYDIR..mapID or self.ROUND end
local function smooth(x,a,b)
    local t=math.max(0,math.min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)
end
-- How far a city is in: from the share of the view's width its rectangle
-- (width rw of a canvas of width w) takes at this scale.
function R:CityAlpha(mapID,rw,w,scale,scroll)
    local sw=scroll and scroll.GetWidth and scroll:GetWidth() or 0
    if not (sw>0 and w>0) then return 1 end
    local fade=self.CITYFADEOF[mapID] or self.CITYFADE
    return smooth(rw*w*scale/sw,fade[1],fade[2])
end
-- A city's own map in its rectangle (zone: mapID, minX..maxY on the map
-- shown), above the tiles, cut by its mask. used, masks: the pools' counts.
function R:City(zone,layer,w,h,used,masks,alpha)
    if alpha<.005 then return used,masks end
    local textures=P.Call("C_Map.GetMapArtLayerTextures",zone.mapID,1)
    if type(textures)~="table" then return used,masks end
    local layers=P.Call("C_Map.GetMapArtLayers",zone.mapID)
    local art=type(layers)=="table" and type(layers[1])=="table" and layers[1] or {}
    local LW=(art.layerWidth or 0)>0 and art.layerWidth or 1002
    local LH=(art.layerHeight or 0)>0 and art.layerHeight or 668
    local TW=(art.tileWidth or 0)>0 and art.tileWidth or 256
    local TH=(art.tileHeight or 0)>0 and art.tileHeight or 256
    local rw,rh=zone.maxX-zone.minX,zone.maxY-zone.minY
    masks=masks+1
    local cut=self:Mask(masks,layer,zone.minX,zone.minY,zone.maxX,zone.maxY,w,h,self:CityMask(zone.mapID))
    local cols,rows=math.ceil(LW/TW),math.ceil(LH/TH)
    for j=0,rows-1 do
        for i=0,cols-1 do
            local file=textures[j*cols+i+1]
            if file then
                local pw,ph=math.min(TW,LW-i*TW),math.min(TH,LH-j*TH)
                local fw,fh=16,16
                while fw<pw do fw=fw*2 end
                while fh<ph do fh=fh*2 end
                used=self:Piece(layer,used,file,pw,ph,fw,fh,(zone.minX+i*TW/LW*rw)*w,-(zone.minY+j*TH/LH*rh)*h,pw/LW*rw*w,ph/LH*rh*h,self.CITYLEVEL,alpha,cut,nil)
            end
        end
    end
    return used,masks
end
-- The cities of a continent in a window (0..1), each at its alpha (the tiles'
-- crossfade taken off by CITYTILES); kept with their alpha for the names.
function R:Cities(mapID,layer,w,h,scale,scroll,x0,y0,x1,y1,tiles,used,masks)
    local shown={}
    for _,zone in ipairs(self:Zones(mapID)) do
        if zone.maxX>x0 and zone.minX<x1 and zone.maxY>y0 and zone.minY<y1 and self:IsCity(zone.mapID) then
            local alpha=self:CityAlpha(zone.mapID,zone.maxX-zone.minX,w,scale,scroll)*(1-math.min(tiles,self.CITYTILES))
            used,masks=self:City(zone,layer,w,h,used,masks,alpha)
            if alpha>=.005 then shown[#shown+1]={zone=zone,alpha=alpha} end
        end
    end
    self.cities=shown
    return used,masks
end
-- Our area names stay away from a city whose own map (with its painted names) is mostly in.
function R:UnderCity(label)
    for _,c in ipairs(self.cities or {}) do
        local z=c.zone
        if c.alpha>=.5 and label.x>=z.minX and label.x<=z.maxX and label.y>=z.minY and label.y<=z.maxY then return true end
    end
    return false
end
-- The crossfade: how far the tiles are in at this zoom (0 .. the setting),
-- from the pixels a tile gets on a map of width w.
function R:Blend(frame,w,scale)
    local Terrain=ns.MapTerrain
    local across=frame and math.abs(frame.dx)/Terrain.ADT or 0
    if not (frame and Terrain:Source(frame.instance) and across>0) then return 0 end
    local px=w*scale/across
    return math.max(0,math.min(1,(px-self.BLENDPX)/(self.BLENDFULL-self.BLENDPX)))*(P:Config().blend or 0)/100
end
-- A zone without a supported continent (such as Zephras Isle): its own art stays,
-- the tiles of the land in view blended in at the closest zooms as on a
-- continent (Florian 2026-10-23: no minimap detail when zooming in).
function R:Detail(mapID,canvas,scroll,frame)
    local scale=ns.MapPins:CanvasScale()
    local w,h=canvas:GetWidth(),canvas:GetHeight()
    local view=mapID..":detail:"..w..":"..h
    local layer=self:Layer(canvas);layer:Show()
    if self.view~=view then self:Hide();self.view=view end
    self:Shown(self.arts,0)
    for _,mask in ipairs(self.masks) do mask:Hide() end
    if self.landMask then self.landMask:Hide() end
    if self.paper then self.paper:Hide() end
    local x0,y0,x1,y1=self:Window(scroll,canvas,scale)
    self.pan=self:PanKey(scroll)
    local Terrain=ns.MapTerrain
    local tile=Terrain:Source(frame.instance)
    local tiles=self:Blend(frame,w,scale)
    -- A city without a supported continent keeps its own painted plan.
    if self:IsCity(mapID) then tiles=math.min(tiles,self.CITYTILES) end
    if tile and tiles>0 then
        local c0,c1,r0,r1=Terrain.Range(frame,x0,y0,x1,y1)
        if (c1-c0+1)*(r1-r0+1)<=self.SEAMLESSMAX then self:Tiles(frame,tile,layer,w,h,c0,c1,r0,r1,tiles,false,2) else self:Hide() end
    else self:Hide() end
    self.cities={}
    self:PaintLabels({},layer,w,h,scale)
    self.scale=scale
end
-- Blizzard's map on the seamless continent (Florian 2026-10-22, after
-- OpenMap, docs/map-seamless-plan.md): the zones' painted land stitched
-- onto the continent for the part in view with blended borders, the
-- minimap tiles of the land blended in at the closest zooms (the painted
-- sea stays), zone names while the view is wide; Blizzard's continent art
-- stays beneath and shows alone far out.
function R:Stitch(mapID,canvas,scroll,frame)
    local scale=ns.MapPins:CanvasScale()
    local w,h=canvas:GetWidth(),canvas:GetHeight()
    local view=mapID..":stitch:"..w..":"..h
    local layer=self:Layer(canvas);layer:Show()
    if self.view~=view then self:Hide();self.view=view end
    local x0,y0,x1,y1=self:Window(scroll,canvas,scale)
    self.pan=self:PanKey(scroll)
    local inView={}
    for _,zone in ipairs(self:Zones(mapID)) do
        if zone.maxX>x0 and zone.minX<x1 and zone.maxY>y0 and zone.minY<y1 then inView[#inView+1]=zone end
    end
    local stitched=#inView>0 and #inView<=self.STITCHMAX
    local Terrain=ns.MapTerrain
    local tile=frame and Terrain:Source(frame.instance)
    local tiles=self:Blend(frame,w,scale)
    local land=frame and P.LANDS and P.LANDS[frame.instance]
    local landMask=stitched and land and not self.noLandMask and self:LandMask(layer,frame,land,w,h) or nil
    if self.landMask and not landMask then self.landMask:Hide() end
    local used,masks=0,0
    if stitched then for _,zone in ipairs(inView) do used,masks=self:ZoneArt(zone,layer,w,h,used,masks,1-tiles,landMask) end end
    used,masks=self:Cities(mapID,layer,w,h,scale,scroll,x0,y0,x1,y1,tiles,used,masks)
    self:Shown(self.arts,used)
    -- Land no zone map reaches: blank parchment tiled over the land (the
    -- land mask cuts it to the land), above the continent painting whose
    -- letters showed through the gaps (Florian 2026-10-22); its sea stays.
    local paper=self.paper
    if stitched and landMask then
        if not paper then
            paper=layer:CreateTexture(nil,"BACKGROUND",nil,-2);paper:SetDrawLayer("BACKGROUND",-2);self.paper=paper
            pcall(paper.SetTexture,paper,self.PAPER,"REPEAT","REPEAT")
            if paper.AddMaskTexture then paper:AddMaskTexture(landMask) end
        end
        if paper:GetParent()~=layer then paper:SetParent(layer) end
        local pw,ph=landMask:GetWidth(),landMask:GetHeight()
        paper:ClearAllPoints();paper:SetPoint("TOPLEFT",landMask,"TOPLEFT",0,0);paper:SetSize(pw,ph)
        paper:SetTexCoord(0,pw/self.PAPERPX,0,ph/self.PAPERPX);paper:SetVertexColor(1,1,1,1-tiles);paper:Show()
    elseif paper then paper:Hide() end
    for i=masks+1,#self.masks do self.masks[i]:Hide() end
    if stitched and tiles>0 then
        local c0,c1,r0,r1=Terrain.Range(frame,x0,y0,x1,y1)
        if (c1-c0+1)*(r1-r0+1)<=self.SEAMLESSMAX then self:Tiles(frame,tile,layer,w,h,c0,c1,r0,r1,tiles,false,2) else self:Hide() end
    else self:Hide() end
    local labels={}
    if not stitched or #inView>=self.NAMEZONES then
        for _,zone in ipairs(inView) do
            if zone.name~="" and not zone.inner then labels[#labels+1]={name=zone.name,x=(zone.minX+zone.maxX)/2,y=(zone.minY+zone.maxY)/2,zone=true} end
        end
    end
    self:PaintLabels(labels,layer,w,h,scale,scroll)
    self.scale=scale
end
function R:Refresh()
    local canvas,scroll,map=ns.MapPins:Canvas()
    if not (P:Active() and canvas and map and map:IsShown() and map.GetMapID) then return self:Stash() end
    local mapID=map:GetMapID()
    local info=P.Call("C_Map.GetMapInfo",mapID)
    local kind=type(info)=="table" and info.mapType
    if kind==2 then return self:Stitch(mapID,canvas,scroll,self:Frame(mapID)) end
    local zone=kind==3 and self:Blending() and P.Seamless and P.Seamless:ZoneFrame(mapID)
    if zone then return self:Detail(mapID,canvas,scroll,zone) end
    return self:Stash()
end
-- A map button's symbol swapped (the route button shows its mode).
function R:Glyph(button,name)
    local icon=button and button.icon
    if not (icon and icon.glyph) or icon.symbol==name then return end
    local path,l,r,t,b=ns.Symbols:Coords(name,M.ToNative(18))
    if not path then return end
    icon.glyph:SetTexture(path);icon.glyph:SetTexCoord(l,r,t,b);icon.symbol=name
end
-- Actions beside search: locate, clear waypoints and (with Routing) Ctrl+click mode.
function R:Button()
    local map=P:WorldMap()
    if self.locate or not map then return self.locate end
    local parent=map.ScrollContainer or map
    -- Map controls belong to the captured Interface; map art/HUD keep P:Style().
    local style=ns.Config and ns.Config:EnsureShellStyle()
    if not style or style.materialProfile~="interface" then return end
    self.style=style
    UI:WithStyle(style,function()
        self.locate=P:MapButton(parent,"locate-fixed",function() P:Locate() end,style)
        UI:AttachTooltip(self.locate,"Where am I","Back to your zone with the whole zone in view.")
        -- Remove all waypoints (Florian 2026-10-08).
        self.clear=P:MapButton(parent,"trash-2",function() P.Waypoints:Clear() end,style)
        M.Point(self.clear,"LEFT",self.locate,"RIGHT",6,0)
        UI:AttachTooltip(self.clear,"Remove all waypoints","Clears the waypoint queue (with TomTom: TomTom keeps its own).")
        -- Ctrl+click: Blizzard's waypoint (pin) or Routing's way (route);
        -- the symbol shows the mode (Florian 2026-10-22).
        self.route=P:MapButton(parent,"map-pin",function() P.Path:ToggleCtrl() end,style)
        M.Point(self.route,"LEFT",self.clear,"RIGHT",6,0)
        UI:AttachTooltip(self.route,"Ctrl+click","Pin: Ctrl+click sets Blizzard's waypoint, Ctrl+Shift+click plans Routing's way. Route: the other way round. Click to switch.")
    end)
    return self.locate
end
-- Watching the map while it is open: map, zoom, size and pan changes.
function R:Watch(on)
    if on and not self.ticker then
        self.ticker=C_Timer.NewTicker(.2,function()
            local canvas,scroll,map=ns.MapPins:Canvas()
            if not (map and map:IsShown() and canvas) then return R:Watch(false) end
            if R.scale~=ns.MapPins:CanvasScale() or not R.view or not R.view:find("^"..tostring(map:GetMapID())..":") then R:Refresh()
            elseif R.pan~=R:PanKey(scroll) then R:Refresh() end
        end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function R:Apply()
    local button=P:Active() and self:Button()
    if self.locate then
        local on=P:Active() and true or false
        self.locate:SetShown(on);self.clear:SetShown(on)
        local route=on and P:Config().routeClick and P.Path and P.Path:Routing()~=nil
        local routes=route and P.Path:CtrlRoutes() or false
        self.route:SetShown(route and true or false)
        self.route:SetActive(routes)
        self:Glyph(self.route,routes and "route" or "map-pin")
        -- Beside the search magnifier, or in its place when the search is off.
        local search=P.Search and P.Search.button
        local parent=self.locate:GetParent()
        self.locate:ClearAllPoints()
        if search and search:IsShown() then M.Point(self.locate,"LEFT",search,"RIGHT",6,0)
        else self.locate:SetPoint("TOPLEFT",parent,"TOPLEFT",P:WorldMap() and P.Search and P.Search:Left(P:WorldMap(),parent) or 6,-6) end
    end
    local map=P:WorldMap()
    self:Refresh()
    self:Watch(P:Active() and map and map:IsShown() and true or false)
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
    context:Defer(function()
        R:Watch(false);R:Stash()
        if R.locate then for _,key in ipairs({"locate","clear","route"}) do R[key]:Hide() end end
    end)
    self:Apply()
end

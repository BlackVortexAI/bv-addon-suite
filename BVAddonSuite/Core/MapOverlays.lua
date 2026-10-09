local _,ns=...
-- Map overlays (Florian 2026-10-08: show unexplored areas like Leatrix
-- Maps, in Gather's route editor and the Map module). The client hands out
-- only the explored ones (C_MapExplorationInfo.GetExploredMapTextures);
-- MapOverlayData holds all of them, generated from the client's own tables
-- (tools/build_map_overlays.py). All(mapID) returns every overlay of a map
-- in the shape of GetExploredMapTextures plus explored=true/false.
local O={cache={}}
ns.MapOverlays=O

local function call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
local function data() return ns.MapOverlayData and ns.MapOverlayData.art or {} end
function O:Explored(mapID)
    local list=call("C_MapExplorationInfo.GetExploredMapTextures",mapID)
    return type(list)=="table" and list or {}
end
-- A map's art ID: the client's answer, the client's table (UiMapXMapArt),
-- else the art whose overlays hold the files of the explored ones.
function O:Art(mapID)
    if type(mapID)~="number" then return nil end
    local art=call("C_Map.GetMapArtID",mapID)
    if type(art)=="number" and data()[art] then return art end
    -- The client's own table (UiMapXMapArt), for zones never explored.
    local fixed=ns.MapOverlayData and ns.MapOverlayData.maps and ns.MapOverlayData.maps[mapID]
    if fixed and data()[fixed] then return fixed end
    local files={}
    for _,info in ipairs(self:Explored(mapID)) do
        for _,file in ipairs(type(info)=="table" and type(info.fileDataIDs)=="table" and info.fileDataIDs or {}) do files[file]=true end
    end
    if not next(files) then return nil end
    for id,overlays in pairs(data()) do
        for _,entry in ipairs(overlays) do
            for i=5,#entry do if files[entry[i]] then return id end end
        end
    end
    return nil
end
local function key(w,h,x,y) return w..":"..h..":"..x..":"..y end
-- Every overlay of a map: the explored ones from the client, the others
-- from the data. Without data for the map only the explored ones.
function O:All(mapID)
    local explored=self:Explored(mapID)
    local out,seen={},{}
    for _,info in ipairs(explored) do
        if type(info)=="table" then
            out[#out+1]={textureWidth=info.textureWidth,textureHeight=info.textureHeight,offsetX=info.offsetX or 0,offsetY=info.offsetY or 0,
                fileDataIDs=info.fileDataIDs,explored=true}
            seen[key(info.textureWidth or 0,info.textureHeight or 0,info.offsetX or 0,info.offsetY or 0)]=true
        end
    end
    local art=self.cache[mapID]
    if art==nil then art=self:Art(mapID) or false;if art or #explored>0 then self.cache[mapID]=art end end
    for _,entry in ipairs(art and data()[art] or {}) do
        if not seen[key(entry[1],entry[2],entry[3],entry[4])] then
            local files={}
            for i=5,#entry do files[#files+1]=entry[i] end
            out[#out+1]={textureWidth=entry[1],textureHeight=entry[2],offsetX=entry[3],offsetY=entry[4],fileDataIDs=files,explored=false}
        end
    end
    return out
end
-- Area names of a map at the middle of their hit rectangles (Florian
-- 2026-10-08: our own subzone labels): {areaID, x, y (0..1 of the map),
-- name, left, top, right, bottom (its hit rectangle, 0..1)}.
function O:Labels(mapID)
    local art=self.cache[mapID]
    if art==nil then art=self:Art(mapID) or false;if art then self.cache[mapID]=art end end
    local flat=art and ns.MapOverlayData and ns.MapOverlayData.labels and ns.MapOverlayData.labels[art]
    if not flat then return {} end
    local layers=call("C_Map.GetMapArtLayers",mapID)
    local layer=type(layers)=="table" and layers[1]
    local width=type(layer)=="table" and layer.layerWidth or 1002
    local height=type(layer)=="table" and layer.layerHeight or 668
    local out={}
    for i=1,#flat-6,7 do
        local name=call("C_Map.GetAreaInfo",flat[i])
        if type(name)~="string" or (issecretvalue and issecretvalue(name)) then name="" end
        out[#out+1]={areaID=flat[i],x=flat[i+1]/width,y=flat[i+2]/height,name=name,
            left=flat[i+3]/width,top=flat[i+4]/height,right=flat[i+5]/width,bottom=flat[i+6]/height}
    end
    return out
end

-- Factions (Florian 2026-10-08: as Horde never run through an Alliance
-- base, and only your own flight masters). Flight masters carry their
-- faction (Enum.FlightPathFaction: 1 Horde, 2 Alliance, 0 neutral).
function O.PlayerFaction()
    local faction=call("UnitFactionGroup","player")
    return (faction=="Horde" or faction=="Alliance") and faction or nil
end
function O.HostileNode(faction)
    local mine=O.PlayerFaction()
    if mine=="Horde" then return faction==2 end
    if mine=="Alliance" then return faction==1 end
    return false
end
-- Enemy places of a map as rectangles (0..1): areas of an enemy capital
-- (AreaTable) and the area around each enemy flight master (its overlay
-- hit rectangle, else 120 yards around it). {left, top, right, bottom, name}.
function O:Hostile(mapID)
    local mine=self.PlayerFaction()
    if not mine then return {} end
    local enemyMask=mine=="Horde" and 2 or 4
    local data=ns.MapOverlayData or {}
    local capitals={}
    for _,id in ipairs(data.capitals or {}) do capitals[id]=true end
    local labels=self:Labels(mapID)
    local out={}
    for _,label in ipairs(labels) do
        if capitals[label.areaID] and (data.factions or {})[label.areaID]==enemyMask then
            out[#out+1]={left=label.left,top=label.top,right=label.right,bottom=label.bottom,name=label.name}
        end
    end
    local nodes=call("C_TaxiMap.GetTaxiNodesForMap",mapID)
    for _,node in ipairs(type(nodes)=="table" and nodes or {}) do
        local position=type(node)=="table" and node.position
        local ok,x,y=false
        if position and position.GetXY then ok,x,y=pcall(position.GetXY,position) end
        if ok and type(x)=="number" and self.HostileNode(node.faction) then
            local best
            for _,label in ipairs(labels) do
                if x>=label.left and x<=label.right and y>=label.top and y<=label.bottom then
                    local size=(label.right-label.left)*(label.bottom-label.top)
                    if not best or size<best.size then best={size=size,label=label} end
                end
            end
            if best then
                local l=best.label
                out[#out+1]={left=l.left,top=l.top,right=l.right,bottom=l.bottom,name=l.name~="" and l.name or node.name}
            else
                local width,height=call("C_Map.GetMapWorldSize",mapID)
                if type(width)~="number" or width<=0 then width,height=1000,1000 end
                local rx,ry=120/width,120/height
                out[#out+1]={left=x-rx,top=y-ry,right=x+rx,bottom=y+ry,name=node.name}
            end
        end
    end
    return out
end

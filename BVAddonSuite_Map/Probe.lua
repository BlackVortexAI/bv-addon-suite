local _,P=...
if not P.ready then return end
-- /bv map probe (plan phase 0): one copyable report of what the map, quest
-- and gather features rely on but tests cannot show, read on demand from
-- the client: pin and minimap APIs, Blizzard's waypoint and navigation,
-- data for dungeon entrances, level ranges and unexplored areas, points of
-- interest and flight points, the gathering spells and the last cast,
-- addon messages. Only reads; nothing is changed. Values are numbers and
-- yes/no; no names of players.
local ns=P.ns
local R={}
P.Probe=R

local function exists(path)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return false end;f=f[part] end
    return type(f)=="function"
end
local function value(v)
    if P.Secret(v) then return "secret" end
    if type(v)=="number" then return (math.floor(v*1000+.5)/1000).."" end
    if type(v)=="table" then return "table" end
    return tostring(v)
end
local function count(t) if type(t)~="table" then return value(t) end;local n=0;for _ in pairs(t) do n=n+1 end;return n.."" end

function R:Report()
    local lines={}
    local function add(text) lines[#lines+1]=text end
    local function api(path,...)
        if not exists(path) then add(path..": missing");return nil end
        local result={pcall(P.Call,path,...)}
        return unpack(result,2)
    end
    local version,build,_,interface=P.Call("GetBuildInfo")
    add("BV map probe "..date("%Y-%m-%d %H:%M"))
    add("Client: "..value(version).." build "..value(build).." interface "..value(interface))
    add("Packages: Map "..(P:Active() and "on" or "off").."  Quest "..tostring(ns.Quest and ns.Quest:Active() and "on" or "off").."  Gather "..tostring(ns.Gather and ns.Gather:Active() and "on" or "off"))
    add("")
    add("[Player position]")
    local mapID=api("C_Map.GetBestMapForUnit","player")
    add("C_Map.GetBestMapForUnit: "..value(mapID))
    local x,y=P:PlayerPosition(mapID)
    add("Player position: "..(x and (value(x)..", "..value(y)) or "none"))
    local width,height=api("C_Map.GetMapWorldSize",mapID)
    add("C_Map.GetMapWorldSize: "..value(width).." x "..value(height))
    local vector=rawget(_G,"CreateVector2D")
    add("CreateVector2D: "..(vector and "yes" or "missing"))
    if vector and x then
        local continent,world=api("C_Map.GetWorldPosFromMapPos",mapID,vector(x,y))
        add("C_Map.GetWorldPosFromMapPos: continent "..value(continent).." world "..(world and "yes" or "nil"))
        if world then
            local _,back=api("C_Map.GetMapPosFromWorldPos",continent,world,mapID)
            local bx,by
            if ns.MapPins then bx,by=ns.MapPins.XY(back) end
            add("C_Map.GetMapPosFromWorldPos round trip: "..(bx and (value(bx)..", "..value(by)) or "nil"))
        end
    end
    local continent=ns.MapPins and ns.MapPins:Continent(mapID)
    add("Continent (map type 2): "..value(continent))
    if continent then
        local minX,maxX,minY,maxY=api("C_Map.GetMapRectOnMap",mapID,continent)
        add("C_Map.GetMapRectOnMap(map, continent): "..value(minX).." - "..value(maxX).." x "..value(minY).." - "..value(maxY))
        if x then
            local cx,cy=ns.MapPins:OnMap({mapID=mapID,x=x,y=y},continent)
            local bx,by
            if cx then bx,by=ns.MapPins:OnMap({mapID=continent,x=cx,y=cy},mapID) end
            add("Map -> continent -> map: "..(bx and (value(bx)..", "..value(by)) or "nil"))
        end
    end
    local mapInfo=api("C_Map.GetMapInfo",mapID)
    add("Map type: "..value(type(mapInfo)=="table" and mapInfo.mapType).."  IsIndoors: "..value(api("IsIndoors")).."  Subzone: "..value(api("GetSubZoneText")))
    local _,_,z=api("UnitPosition","player")
    add("UnitPosition height (z): "..value(z))
    add("GetPlayerFacing: "..value(api("GetPlayerFacing")))
    add("UnitPosition: "..value((api("UnitPosition","player"))))
    -- The route editor draws the zone itself from these (Gather).
    local layers=api("C_Map.GetMapArtLayers",mapID)
    local layer=type(layers)=="table" and layers[1]
    if type(layer)=="table" then
        add("C_Map.GetMapArtLayers: "..#layers.." layer(s), "..value(layer.layerWidth).." x "..value(layer.layerHeight)..", tiles "..value(layer.tileWidth).." x "..value(layer.tileHeight))
    else add("C_Map.GetMapArtLayers: "..value(layers)) end
    add("C_Map.GetMapArtID: "..value(api("C_Map.GetMapArtID",mapID)).."  Overlay art found: "..value(ns.MapOverlays and ns.MapOverlays:Art(mapID)))
    local textures=api("C_Map.GetMapArtLayerTextures",mapID,1)
    add("C_Map.GetMapArtLayerTextures(map, 1): "..(type(textures)=="table" and (#textures.." texture(s), first "..value(textures[1])) or value(textures)))
    local children=continent and api("C_Map.GetMapChildrenInfo",continent,3,true)
    add("C_Map.GetMapChildrenInfo(continent, zones): "..(type(children)=="table" and (#children.." zone(s)") or value(children)))
    add("")
    add("[Minimap]")
    add("C_Minimap.GetViewRadius: "..value(api("C_Minimap.GetViewRadius")))
    local minimap=rawget(_G,"Minimap")
    add("Minimap zoom: "..value(minimap and minimap.GetZoom and minimap:GetZoom()).."  size "..value(minimap and minimap:GetWidth()))
    add("rotateMinimap: "..value(api("GetCVar","rotateMinimap")).."  GetMinimapShape: "..value(api("GetMinimapShape")).."  IsIndoors: "..value(api("IsIndoors")))
    add("")
    add("[World map]")
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    add("WorldMapFrame: "..(map and "yes" or "missing").."  OnMapChanged: "..(map and map.OnMapChanged and "yes" or "no").."  IsMaximized: "..(map and map.IsMaximized and "yes" or "no"))
    add("ScrollContainer.Child: "..(scroll and scroll.Child and "yes" or "no").."  GetCanvasScale: "..(scroll and scroll.GetCanvasScale and "yes" or "no")
        .."  GetNormalizedCursorPosition: "..(scroll and scroll.GetNormalizedCursorPosition and "yes" or "no").."  InstantPanAndZoom: "..(scroll and scroll.InstantPanAndZoom and "yes" or "no"))
    add("mapFade CVar: "..value(api("GetCVarBool","mapFade")))
    -- Painted map layers and seamless detail diagnostics.
    local canvas=scroll and scroll.Child
    add("detailLayerPool: "..(map and map.detailLayerPool and "yes" or "no").."  RefreshDetailLayers: "..(map and type(map.RefreshDetailLayers)=="function" and "yes" or "no")
        .."  AdjustDetailLayerAlpha: "..(map and type(map.AdjustDetailLayerAlpha)=="function" and "yes" or "no"))
    if canvas then
        local names={}
        for _,child in ipairs({canvas:GetChildren()}) do
            local keys={}
            for key in pairs(child) do
                if type(key)=="string" and (key:lower():find("layer",1,true) or key:lower():find("tile",1,true) or key:lower():find("detail",1,true)) then keys[#keys+1]=key end
            end
            table.sort(keys)
            names[#names+1]=(child.GetName and child:GetName() or "?")..(#keys>0 and (" {"..table.concat(keys,",").."}") or "").." L"..child:GetFrameLevel().." a"..string.format("%.2f",child:GetAlpha())
        end
        add("Canvas children ("..#names.."): "..table.concat(names,"; "))
        add("Canvas size: "..value(canvas:GetWidth()).." x "..value(canvas:GetHeight()).."  scroll "..value(scroll:GetWidth()).." x "..value(scroll:GetHeight()).."  scale "..value(ns.MapPins and ns.MapPins:CanvasScale()))
        local levels=scroll.zoomLevels
        local list={}
        for i,level in ipairs(type(levels)=="table" and levels or {}) do list[i]=string.format("%.2f%s",level.scale or 0,level.bv and "*" or "") end
        add("Zoom levels ("..#list.."): "..table.concat(list," ").."  (* ours)")
        local shown=map and map.GetMapID and map:GetMapID()
        local Terrain=ns.MapTerrain
        add("Map shown: "..value(shown).."  frame (Core): "..(Terrain and Terrain:Frame(shown) and "yes" or "no").."  frame (ours): "..(P.Terrain and P.Terrain:Frame(shown) and "yes" or "no")
            .."  seamless: "..(P.Seamless and P.Seamless:On() and "on" or "off").."  continent of it: "..value(P.Seamless and P.Seamless:ContinentOf(shown)))
        if P.Terrain then
            local T=P.Terrain
            add("Close-zoom detail: tiles "..T:Count().."  fills "..T:FillCount())
            local lm=T.landMask
            add("Stitch: art pieces "..T:ArtCount().."  base pieces "..tostring(T.baseCount).."  masks "..#T.masks.."  land mask "..(lm and (tostring(lm.file).." "..value(lm:GetWidth()).." x "..value(lm:GetHeight()).." shown "..tostring(lm:IsShown())) or "none")
                .."  MaskTexture.SetTexCoord "..(lm and type(lm.SetTexCoord)=="function" and "yes" or "no"))
            local sample
            for _,tex in ipairs(T.arts) do if tex:IsShown() and tex.sublevel==nil then sample=tex;break end end
            local first=T.arts[1]
            if first then add("First art piece: file "..tostring(first.file).."  shown "..tostring(first:IsShown()).."  masks "..tostring(first.GetNumMaskTextures and first:GetNumMaskTextures()).."  alpha "..value(select(4,first:GetVertexColor()))) end
            local zone=T:Zones(shown)[1]
            if zone then
                local textures=P.Call("C_Map.GetMapArtLayerTextures",zone.mapID,1)
                add("Base art of "..zone.name..": "..(type(textures)=="table" and (#textures.." texture(s), first "..tostring(textures[1])) or value(textures)))
            end
        end
    end
    add("")
    add("[Waypoints and navigation]")
    add("UiMapPoint.CreateFromCoordinates: "..(exists("UiMapPoint.CreateFromCoordinates") and "yes" or "missing"))
    add("C_Map.CanSetUserWaypointOnMap: "..value(api("C_Map.CanSetUserWaypointOnMap",mapID)))
    add("C_Map.HasUserWaypoint: "..value(api("C_Map.HasUserWaypoint")).."  C_SuperTrack.IsSuperTrackingUserWaypoint: "..value(api("C_SuperTrack.IsSuperTrackingUserWaypoint")))
    add("C_Navigation.GetDistance: "..value(api("C_Navigation.GetDistance")))
    add("C_QuestLog.GetNextWaypoint: "..(exists("C_QuestLog.GetNextWaypoint") and "yes" or "missing").."  GetQuestUiMapID: "..(exists("GetQuestUiMapID") and "yes" or "missing"))
    add("C_DeathInfo.GetCorpseMapPosition: "..(exists("C_DeathInfo.GetCorpseMapPosition") and "yes" or "missing"))
    add("TomTom: "..(rawget(_G,"TomTom") and "loaded" or "no"))
    add("")
    add("[Map data for later features]")
    add("C_EncounterJournal.GetDungeonEntrancesForMap: "..count(api("C_EncounterJournal.GetDungeonEntrancesForMap",mapID)))
    local low,high=api("C_Map.GetMapLevels",mapID)
    add("C_Map.GetMapLevels: "..value(low).." - "..value(high))
    add("C_MapExplorationInfo.GetExploredMapTextures: "..count(api("C_MapExplorationInfo.GetExploredMapTextures",mapID)))
    add("C_AreaPoiInfo.GetAreaPOIForMap: "..count(api("C_AreaPoiInfo.GetAreaPOIForMap",mapID)))
    add("C_TaxiMap.GetTaxiNodesForMap: "..count(api("C_TaxiMap.GetTaxiNodesForMap",mapID)))
    -- Zones with no continent above them (Zephras Isle): what the client says of them on the world map.
    for _,id in ipairs({2521,2665}) do
        local zi=api("C_Map.GetMapInfo",id)
        local a,b,c,d=api("C_Map.GetMapRectOnMap",id,947)
        add("Map "..id..": type "..value(type(zi)=="table" and zi.mapType).." parent "..value(type(zi)=="table" and zi.parentMapID).."  no continent: "..value(P.Islands and P.Islands:Rootless(id))
            .."  rect on 947: "..value(a).." - "..value(b).." x "..value(c).." - "..value(d).."  alone (own seamless map): "..(P.Seamless and P.Seamless:Alone(id) and "yes" or "no"))
    end
    add("Islands on 947: "..(P.Islands and #P.Islands:List(947) or 0).."  shown buttons: "..(function() local n=0;for _,b in ipairs(P.Islands and P.Islands.buttons or {}) do if b:IsShown() then n=n+1 end end;return n end)())
    add("C_Map.GetMapChildrenInfo(946): "..count(api("C_Map.GetMapChildrenInfo",946,nil,true)).."  (947): "..count(api("C_Map.GetMapChildrenInfo",947,nil,true)))
    add("")
    add("[Gathering]")
    for _,id in ipairs({2366,2575,3365,7620}) do
        local name=P.Call("C_Spell.GetSpellName",id) or P.Call("GetSpellInfo",id)
        add("Spell "..id..": "..value(name))
    end
    local gather=ns.Gather
    local last=gather and gather.Record and gather.Record.lastCast
    add("Last cast seen by Gather: "..(last and ("spell "..value(last.spellID).." target "..(last.target and "named" or "none").." kind "..tostring(last.kind)) or "none (gather something with Gather on)"))
    add("GatherMate2: "..(gather and gather:GatherMate() and "loaded" or "no").."  GatherMate2HerbDB: "..(rawget(_G,"GatherMate2HerbDB") and "present" or "no"))
    add("")
    add("[Addon messages]")
    add("C_ChatInfo.SendAddonMessage: "..(exists("C_ChatInfo.SendAddonMessage") and "yes" or "missing").."  RegisterAddonMessagePrefix: "..(exists("C_ChatInfo.RegisterAddonMessagePrefix") and "yes" or "missing"))
    add("Prefixes registered: path "..value(api("C_ChatInfo.IsAddonMessagePrefixRegistered","BVMAPPATH1")).."  gather "..value(api("C_ChatInfo.IsAddonMessagePrefixRegistered","BVGATHER1")))
    add("IsInGroup "..value(api("IsInGroup")).."  IsInGuild "..value(api("IsInGuild")))
    return table.concat(lines,"\n")
end
function R:Open()
    local ok,text=pcall(self.Report,self)
    ns.UI:DiagnosticReport("Map probe",ok and text or ("Probe failed: "..tostring(text)))
end

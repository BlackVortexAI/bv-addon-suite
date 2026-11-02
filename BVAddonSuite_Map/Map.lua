local package,P=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.96 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.2.10","0.8.96",1) then return end
-- Map package (docs/map-quest-concept.md, own package by Florian's choice on
-- 2026-10-08): coordinates, transparency while moving, map size and position,
-- waypoints. Blizzard's map is never replaced; other map addons keep working.
-- Waypoints go to TomTom when it is there (Florian: never disturb existing
-- systems); without it /way uses Blizzard's own user waypoint and arrow.
-- Files fill P (package-private): Zones, Navigation, Guard, Fade, Waypoints,
-- ZoneBanner, Path, Share, UI/Coords, UI/Window, UI/Arrow, UI/WaypointList, UI/Search, Options.
P.ns=ns
ns.Map=P
P.ready=true
P.ID="map"

P.DEFAULTS={enabled=false,
    -- Coordinates on the map (player and cursor). The minimap shows them itself
    -- (Blizzard, Florian 2026-10-08), so there is no minimap line.
    coords=true,coordsPlayer=true,coordsCursor=true,coordsDecimals=1,
    -- Transparency while moving: opacity, scope, full on mouseover, fade time.
    fade=true,fadeOpacity=45,fadeScope="all",fadeMouseover=true,fadeTime=3,
    -- BV shell: independent window dimensions, UI scale and saved position.
    scale=100,movable=true,windowWidth=900,windowHeight=600,
    -- Waypoints: /way when no other addon has it; queue, arrival distance,
    -- named sets, corpse waypoint; our arrow (only without TomTom).
    waypoints={},arrival=10,sets={},corpse=true,arrow=true,
    -- Map 0.2: reopen on the same zoom and section; search on the map.
    rememberZoom=true,search=true,
    -- Use ours anyway although another addon handles that part (Florian 2026-10-08).
    forceMove=false,forceScale=false,forceCoords=false,
    -- Zone banner (stage types zone and subzone; from the Quest package on
    -- 2026-10-08): quests of the zone and "Discovered" in it.
    zoneQuests=true,zoneDiscovered=true,
    -- Travel path (phase 2b): pins and lines for the queue, Alt+click adds,
    -- shared paths from others (always with a preview).
    pathPins=true,altClick=true,shareReceive=true,
    -- Ctrl+Shift+click: Routing's way there, when BV Routing is loaded; and
    -- the clicks the map knows, written small at its bottom (Florian 2026-10-16).
    routeClick=true,legend=true,
    -- Small arrows at the map's edges to the next zone (Florian 2026-10-16).
    neighbors=true,
    -- Path colours (hex RRGGBB): empty = the style's accent; the next target.
    pathColor="",nextColor="5FD16B",
    -- The leg from you to the next target as its own line (with arrows).
    pathLead=true,
    -- Opacity of the path's pins and lines in percent.
    pathPinAlpha=100,pathLineAlpha=95,
    -- Unexplored areas shown on the world map (Leatrix Maps' reveal wins).
    unexplored=true,forceReveal=false,
    -- Blizzard's map on the seamless continent (Florian 2026-10-22, after
    -- OpenMap): at the closest zoom levels the minimap tiles take over from
    -- the painting, up to this opacity (100 = the painting gone, 0 = never).
    blend=100,
    -- Flight masters of your own faction only (and neutral ones).
    ownFlights=true,
    -- Flight times learned from your own flights, shown at the flight master.
    learnFlights=true,
    -- Closer than Blizzard's closest zoom (Florian 2026-10-09): off, x2, x4.
    extraZoom="off",
    -- With Routing: Ctrl+click plans its way and Ctrl+Shift+click sets
    -- Blizzard's waypoint, instead of the other way round (Florian 2026-10-22).
    ctrlRoute=false,
    styleFamily="inherit"}
local CHOICES={fadeScope={all=true,map=true,panes=true},extraZoom={off=true,x2=true,x4=true}}
local function num(value,default,low,high)
    if type(value)~="number" or value~=value then value=default end
    return math.max(low,math.min(high,math.floor(value+.5)))
end
function P:Config()
    local cfg=ns.Settings:Module(self.ID)
    -- The zone banner's two switches move over from the Quest package once.
    if cfg.zoneMoved~=1 then
        local quest=ns.Settings:Module("quest")
        for _,key in ipairs({"zoneQuests","zoneDiscovered"}) do
            if cfg[key]==nil and quest[key]~=nil then cfg[key]=quest[key] end
            quest[key]=nil
        end
        cfg.zoneMoved=1
    end
    for key,value in pairs(self.DEFAULTS) do if cfg[key]==nil then cfg[key]=type(value)=="table" and {} or value end end
    for key,valid in pairs(CHOICES) do if not valid[cfg[key]] then cfg[key]=self.DEFAULTS[key] end end
    for _,key in ipairs({"coords","coordsPlayer","coordsCursor","fade","fadeMouseover","movable","corpse","arrow","rememberZoom","search","forceMove","forceScale","forceCoords","zoneQuests","zoneDiscovered","pathPins","altClick","routeClick","legend","neighbors","shareReceive","unexplored","forceReveal","ownFlights","pathLead","learnFlights","ctrlRoute"}) do cfg[key]=cfg[key]==true end
    cfg.coordsDecimals=num(cfg.coordsDecimals,1,0,2);cfg.fadeOpacity=num(cfg.fadeOpacity,45,10,100)
    -- Fade time in tenths of a second (0.1 .. 1.0 s).
    -- The blend became a crossfade on 2026-10-22 (Florian: the painting under the tiles looked odd); once to the new default.
    if cfg.blendMoved~=1 then cfg.blend=nil;cfg.blendMoved=1 end
    cfg.blend=num(cfg.blend,100,0,100)
    cfg.pathPinAlpha=num(cfg.pathPinAlpha,100,10,100);cfg.pathLineAlpha=num(cfg.pathLineAlpha,95,10,100)
    cfg.fadeTime=num(cfg.fadeTime,3,1,10);cfg.scale=num(cfg.scale,100,50,150);cfg.arrival=num(cfg.arrival,10,3,50)
    if cfg.styleFamily~="inherit" and not ns.Styles.families[cfg.styleFamily] then cfg.styleFamily="inherit" end
    if type(cfg.waypoints)~="table" then cfg.waypoints={} end
    if type(cfg.sets)~="table" then cfg.sets={} end
    for key,default in pairs({pathColor="",nextColor="5FD16B"}) do
        if type(cfg[key])~="string" or not (cfg[key]=="" or cfg[key]:match("^%x%x%x%x%x%x")) then cfg[key]=default end
    end
    if cfg.position~=nil and type(cfg.position)~="table" then cfg.position=nil end
    -- Retired map modes (2026-10-29): old profiles always use the seamless painted map.
    cfg.mapStyle=nil;cfg.seamless=nil;cfg.terrainAlpha=nil
    cfg.windowWidth=num(cfg.windowWidth,900,360,2400);cfg.windowHeight=num(cfg.windowHeight,600,240,1600)
    cfg.coordsMinimap=nil
    return cfg
end
function P:Active() return self.context~=nil end
function P:Style() return ns.UI:GameStyle(self.ID) end
-- Our buttons on the world map (search and navigation): a solid surface, above
-- every pin and Blizzard's quest areas (Florian 2026-10-08: the map style
-- button lay under the quest highlights and was hard to see).
-- AbovePins is capped at 9000. Leave headroom below WoW's 10000 limit:
-- native dropdowns add 500 to their owner, then raise rows another 20.
-- 9600 collapsed the filter's backdrop and text onto the same capped level.
P.BUTTONLEVEL=9100
-- Back to where you are (Florian 2026-10-08): your zone, zoom reset.
function P:Locate()
    local map=self:WorldMap()
    local mapID=self.Call("C_Map.GetBestMapForUnit","player")
    if not (map and map.SetMapID) then return false end
    if type(mapID)~="number" then self:Print("No map for your position here.");return false end
    if self.Window then self.Window.view=nil end
    -- The seamless map: the continent zoomed onto your zone.
    if self.Seamless and self.Seamless:Focus(mapID) then return true end
    if map:GetMapID()~=mapID then pcall(map.SetMapID,map,mapID) end
    if map.ResetZoom then pcall(map.ResetZoom,map)
    elseif map.ScrollContainer and map.ScrollContainer.ResetZoom then pcall(map.ScrollContainer.ResetZoom,map.ScrollContainer) end
    return true
end
function P:MapButton(parent,icon,callback,capturedStyle)
    local function build() return ns.UI:IconButton(parent,icon,callback) end
    local button=capturedStyle and ns.UI:WithStyle(capturedStyle,build) or build()
    local strata=self:MapStrata()
    if strata then button:SetFrameStrata(strata) end
    button:SetFrameLevel(self.BUTTONLEVEL)
    button.bvMapButton=true
    ns.DesignSystem.Metrics.Size(button,34,34)
    if button.icon then ns.DesignSystem.Metrics.Size(button.icon,18,18) end
    -- On: the icon in the accent colour.
    -- The icon is a frame with a glyph (DesignSystem Icon): its colour role
    -- also survives a theme refresh. The button repaints its icon on hover,
    -- click and leave from iconRole (Florian 2026-10-23: the seamless switch
    -- went white again as the mouse left it, its state never showed).
    function button:SetActive(on)
        local icon=self.icon
        if not icon then return end
        local role=capturedStyle and capturedStyle.materialProfile=="interface" and "accentText" or "accent"
        self.iconRole=on and role or nil
        icon.colorRole=on and role or "text"
        if icon.SetColor then icon:SetColor((capturedStyle or P:Style()):Color(icon.colorRole)) end
    end
    return button
end
function P:Family() return ns.Styles:Family(self.ID) end
function P:Print(text) ns:Print(text,"Map") end
function P:WorldMap() return rawget(_G,"WorldMapFrame") end
-- Our things on the map above the map's own pins (Florian 2026-10-16: a
-- neighbour zone's highlight lay over the arrow; the canvas gives its pins
-- high frame levels): this far above the map's scroll frame, kept so.
P.ABOVEPINS=2000
-- The map window's frame (BorderFrame and its NineSlice edges) lies in a
-- higher strata than the canvas (Florian's /fstack 2026-10-16: HIGH, level
-- 500, over the arrows and buttons): ours go into that strata too.
function P:MapStrata()
    local map=self:WorldMap()
    local border=map and map.BorderFrame
    local strata=border and border.GetFrameStrata and border:GetFrameStrata()
    local level=border and border.GetFrameLevel and border:GetFrameLevel() or 0
    local nine=border and border.NineSlice
    if nine and nine.GetFrameLevel then level=math.max(level,nine:GetFrameLevel()) end
    return strata,level
end
function P:AbovePins(frame,parent)
    local strata,level=self:MapStrata()
    if strata then frame:SetFrameStrata(strata) end
    frame:SetFrameLevel(math.min(9000,math.max((parent or frame:GetParent()):GetFrameLevel()+self.ABOVEPINS,level+10)))
end
-- Client calls through one place so tests and missing APIs never fault.
function P.Call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
function P.Secret(value) return issecretvalue and issecretvalue(value) or false end

-- Player position on a map (0..1), nil inside instances or when unknown.
function P:PlayerPosition(mapID)
    mapID=mapID or self.Call("C_Map.GetBestMapForUnit","player")
    if type(mapID)~="number" or self.Secret(mapID) then return nil end
    local position=self.Call("C_Map.GetPlayerMapPosition",mapID,"player")
    if type(position)~="table" and type(position)~="userdata" then return nil end
    local ok,x,y=pcall(position.GetXY,position)
    if not ok or type(x)~="number" or type(y)~="number" or self.Secret(x) or (x==0 and y==0) then return nil end
    return x,y,mapID
end
-- A point on a continent map as the point of the zone there: the seamless
-- map shows the continent, but waypoints, routes and coordinates stay the
-- zone's. Any other map, or no zone there: unchanged.
function P:ZoneAt(mapID,x,y)
    local info=self.Call("C_Map.GetMapInfo",mapID)
    if not (type(info)=="table" and info.mapType==2 and ns.MapPins and type(x)=="number") then return mapID,x,y end
    local at=self.Call("C_Map.GetMapInfoAtPosition",mapID,x,y)
    local guard=0
    while type(at)=="table" and at.mapType and at.mapType>3 and at.parentMapID and guard<4 do
        at=self.Call("C_Map.GetMapInfo",at.parentMapID);guard=guard+1
    end
    if not (type(at)=="table" and at.mapType==3 and type(at.mapID)=="number" and at.mapID~=mapID) then return mapID,x,y end
    local zx,zy=ns.MapPins:OnMap({mapID=mapID,x=x,y=y},at.mapID)
    if not zx then return mapID,x,y end
    return at.mapID,zx,zy
end
-- "45.2, 67.8" in the chosen precision.
function P:Format(x,y)
    if not x then return "—" end
    local d=self:Config().coordsDecimals
    local f="%."..d.."f, %."..d.."f"
    return string.format(f,x*100,y*100)
end

ns.Modules:Register({id=P.ID,OnEnable=function(context)
    P.context=context
    context:Defer(function() P.context=nil end)
    P:Config()
    P.Coords:Enable(context)
    P.Neighbors:Enable(context)
    P.Fade:Enable(context)
    P.Window:Enable(context)
    P.Waypoints:Enable(context)
    P.Arrow:Enable(context)
    P.Search:Enable(context)
    P.ZoneBanner:Enable(context)
    P.Path:Enable(context)
    P.Share:Enable(context)
    P.Reveal:Enable(context)
    P.FlightTimes:Enable(context)
    P.Terrain:Enable(context)
    P.Flights:Enable(context)
    P.Zoom:Enable(context)
    P.Seamless:Enable(context)
    P.Islands:Enable(context)
end})

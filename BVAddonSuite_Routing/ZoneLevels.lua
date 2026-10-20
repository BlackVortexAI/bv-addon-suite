local _,Routing=...
if not Routing.ready then return end
-- Zone levels (Florian 2026-10-16: a way through a zone far above your level
-- is said, or avoided): the game tells none on this client (C_Map.GetMapLevels
-- answers 0-0, Map probe 2026-10-08), so the known Classic ranges by map ID.
-- Cities and their maps have none (never too high).
Routing.ZONE_LEVELS={
    [1411]={1,10},[1412]={1,10},[1420]={1,10},[1426]={1,10},[1429]={1,10},[1438]={1,10},
    [1413]={10,25},[1421]={10,20},[1432]={10,20},[1436]={10,20},[1439]={10,20},
    [1433]={15,25},[1442]={15,27},[1440]={18,30},[1431]={18,30},[1424]={20,30},[1437]={20,30},
    [1441]={25,35},[1416]={30,40},[1417]={30,40},[1443]={30,40},[1434]={30,45},
    [1418]={35,45},[1435]={35,45},[1445]={35,45},
    [1444]={40,50},[1425]={40,50},[1446]={40,50},[1427]={43,50},
    [1419]={45,55},[1447]={45,55},[1448]={48,55},[1449]={48,55},
    [1428]={50,58},[1422]={51,58},[1423]={53,60},[1430]={55,60},[1451]={55,60},[1452]={55,60},
}
-- How zones above your level are treated: the setting, "avoid" in the
-- safe mode (unless switched off).
function Routing:ZoneMode()
    local c=self:Config()
    if self:RouteMode()=="safe" and c.zoneLevels~="off" then return "avoid" end
    return c.zoneLevels
end
-- The mode of the way now (Florian 2026-10-16): switched for this way in
-- the guide, else Routing's setting (the default for every new way).
function Routing:RouteMode()
    local N=self.Navigate
    return N and N.modeOverride or self:Config().routeMode
end
-- A zone is above you when its lowest level is higher than yours.
function Routing:ZoneAbove(mapID,level)
    local range=self.ZONE_LEVELS[mapID]
    level=level or UnitLevel("player") or 1
    if not range then return nil end
    if range[1]>level then return range end
end
-- The zone (map type 3) at a point of a continent, or nil.
function Routing:ZoneAt(cont,x,y)
    if not (C_Map and C_Map.GetMapInfoAtPosition) then return nil end
    local ok,info=pcall(C_Map.GetMapInfoAtPosition,cont,x,y)
    if not (ok and type(info)=="table") then return nil end
    -- A city or a part of a zone: its zone.
    local guard=0
    while info and info.mapType and info.mapType>3 and info.parentMapID and guard<4 do
        local okP,parent=pcall(C_Map.GetMapInfo,info.parentMapID)
        info=okP and parent or nil;guard=guard+1
    end
    return info and info.mapType==3 and info.mapID or nil,info and info.name
end

local _,G=...
if not G.ready then return end
-- The map a route is planned and drawn on (Claude 2026-10-26, Florian: Gather on the navmesh alone, BV Routing's grid
-- out of the way): the continent its zones lie on (one zone alone: that zone), the zones' rectangle on it, and the
-- conversions between a zone's points and the space's. No cells, no terrain: the ways are BV Routing's navmesh
-- (RoutePlanNav.lua), whose continent coordinates are the space's.
local ns=G.ns
local S={}
G.Space=S
S.CELL=8   -- yards: the navmesh's cells (painting a polygon samples it this fine)
local function call(...) return G.Call(...) end
-- A point of one map on another: maps are straight projections of the world, three points give the whole
-- conversion, kept per pair of maps (no client call after that).
S.affines={}
function S.Convert(from,to,x,y)
    local T=ns.MapTerrain
    if T and T.RoutingPosition then
        local handled,cx,cy=T:RoutingPosition(from,to,x,y)
        if handled then return cx,cy end
    end
    if from==to then return x,y end
    local key=from*100000+to
    local a=S.affines[key]
    if a==nil then
        a=false
        local pins=ns.MapPins
        local ox,oy=pins:OnMap({mapID=from,x=0,y=0},to)
        local ux,uy=pins:OnMap({mapID=from,x=1,y=0},to)
        local vx,vy=pins:OnMap({mapID=from,x=0,y=1},to)
        if ox and ux and vx then a={ux-ox,vx-ox,ox,uy-oy,vy-oy,oy} end
        S.affines[key]=a
    end
    if not a then return ns.MapPins:OnMap({mapID=from,x=x,y=y},to) end
    return a[1]*x+a[2]*y+a[3],a[4]*x+a[5]*y+a[6]
end
-- The space of some zones: {mapID, width, height (yards), minX, maxX, minY, maxY (the zones on it), zones}.
function S.Space(zones)
    S.affines={}
    local pins=ns.MapPins
    local continent=pins and pins:Continent(zones[1])
    for i=2,#zones do if not pins or pins:Continent(zones[i])~=continent then continent=nil end end
    local space=continent or zones[1]
    local width,height=call("C_Map.GetMapWorldSize",space)
    if type(width)~="number" or width<=0 then width,height=1000,1000 end
    local minX,maxX,minY,maxY=1,0,1,0
    for _,zone in ipairs(zones) do
        local a,b,c,d
        -- (the zone's corners carried over, as every point is; the client's rectangle where that cannot be done)
        if zone==space then a,b,c,d=0,1,0,1
        else
            local x0,y0=S.Convert(zone,space,0,0)
            local x1,y1=S.Convert(zone,space,1,1)
            if type(x0)=="number" and type(x1)=="number" and type(y0)=="number" and type(y1)=="number" and x1~=x0 and y1~=y0 then
                a,b,c,d=math.min(x0,x1),math.max(x0,x1),math.min(y0,y1),math.max(y0,y1)
            else a,b,c,d=call("C_Map.GetMapRectOnMap",zone,space) end
        end
        if type(a)~="number" or not (type(b)=="number" and b>a and type(d)=="number" and d>c) then a,b,c,d=0,1,0,1 end
        minX,maxX,minY,maxY=math.min(minX,a),math.max(maxX,b),math.min(minY,c),math.max(maxY,d)
    end
    return {mapID=space,width=width,height=height,minX=minX,maxX=maxX,minY=minY,maxY=maxY,zones=zones}
end
-- Zone point <-> space point.
function S.ToSpace(s,mapID,x,y)
    if mapID==s.mapID then return x,y end
    return S.Convert(mapID,s.mapID,x,y)
end
function S.FromSpace(s,x,y)
    for _,zone in ipairs(s.zones) do
        local zx,zy=S.Convert(s.mapID,zone,x,y)
        if zx and zx>=0 and zx<=1 and zy>=0 and zy<=1 then return zone,zx,zy end
    end
    return s.mapID,x,y
end
-- Yards on the space map.
function S.Yards(s,x1,y1,x2,y2)
    local dx,dy=(x2-x1)*s.width,(y2-y1)*s.height
    return math.sqrt(dx*dx+dy*dy)
end
-- Inside a polygon {x1, y1, x2, y2, ...} (even-odd).
function S.Inside(poly,x,y)
    local inside=false
    local n=#poly/2
    local j=n
    for i=1,n do
        local xi,yi,xj,yj=poly[2*i-1],poly[2*i],poly[2*j-1],poly[2*j]
        if (yi>y)~=(yj>y) and x<(xj-xi)*(y-yi)/(yj-yi)+xi then inside=not inside end
        j=i
    end
    return inside
end

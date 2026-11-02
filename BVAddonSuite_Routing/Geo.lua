local _,Routing=...
if not Routing.ready then return end
-- Routing's map geometry (Claude 2026-10-27, the grid's removal, Phase 2: what Grid.lua held that is no grid):
-- converting points between maps, a point in a painted polygon, rounding a line's corners, the capitals of each side.
local ns=Routing.ns
local R={}
Routing.Geo=R
-- A point of one map on another: maps are straight projections of the
-- world, so three points give the whole conversion; it is kept per pair of
-- maps and costs no client call after that (Florian 2026-10-09: the route
-- editor lagged, two client calls for every node, stroke and tile on each
-- redraw).
R.affines={}
function R.Convert(from,to,x,y)
    local T=ns.MapTerrain
    if T and T.RoutingPosition then
        local handled,cx,cy=T:RoutingPosition(from,to,x,y)
        if handled then return cx,cy end
    end
    if from==to then return x,y end
    local key=from*100000+to
    local a=R.affines[key]
    if a==nil then
        a=false
        local pins=ns.MapPins
        local ox,oy=pins:OnMap({mapID=from,x=0,y=0},to)
        local ux,uy=pins:OnMap({mapID=from,x=1,y=0},to)
        local vx,vy=pins:OnMap({mapID=from,x=0,y=1},to)
        if ox and ux and vx then a={ux-ox,vx-ox,ox,uy-oy,vy-oy,oy} end
        R.affines[key]=a
    end
    if not a then return ns.MapPins:OnMap({mapID=from,x=x,y=y},to) end
    return a[1]*x+a[2]*y+a[3],a[4]*x+a[5]*y+a[6]
end
-- A point inside a polygon (corners x1, y1, x2, y2, ... on its map; even-odd rule).
function R.Inside(poly,x,y)
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
R.HORDECAPITALS={1454,1456,1458}
R.ALLIANCECAPITALS={1453,1455,1457}
-- Corners rounded off (Florian 2026-10-12: the way up a corkscrew ramp, a
-- flight tower's, came out a polygon): each corner turning more than
-- ROUNDTURN is cut ROUND of the way to its neighbours (at most ROUNDCUT
-- yards), twice over; only where the cut is clear (ok). The ends and points
-- marked fixed (a transition's ends) stay where they are.
R.ROUND=.25
R.ROUNDCUT=4
R.ROUNDTURN=math.rad(12)
function R.Round(points,yards,ok,pace)
    for _=1,2 do
        if #points<3 then return points end
        local out={points[1]}
        for i=2,#points-1 do
            if pace and i%32==0 then pace() end
            local a,p,b=points[i-1],points[i],points[i+1]
            local da,db=yards(p[1],p[2],a[1],a[2]),yards(p[1],p[2],b[1],b[2])
            local keep=p.fixed or da<=0 or db<=0
            if not keep then
                local ux,uy,vx,vy=p[1]-a[1],p[2]-a[2],b[1]-p[1],b[2]-p[2]
                local cross,dot=ux*vy-uy*vx,ux*vx+uy*vy
                keep=math.abs(math.atan2(cross,dot))<R.ROUNDTURN
            end
            if not keep then
                local ta,tb=math.min(R.ROUND,R.ROUNDCUT/da),math.min(R.ROUND,R.ROUNDCUT/db)
                local q={p[1]+(a[1]-p[1])*ta,p[2]+(a[2]-p[2])*ta}
                local r={p[1]+(b[1]-p[1])*tb,p[2]+(b[2]-p[2])*tb}
                if not ok or ok(q,r) then out[#out+1]=q;out[#out+1]=r else out[#out+1]=p end
            else out[#out+1]=p end
        end
        out[#out+1]=points[#points]
        points=out
    end
    return points
end
-- The continent a map lies on and a point of it there.
function Routing:OnContinent(mapID,x,y)
    local cont=ns.MapPins and ns.MapPins:Continent(mapID)
    if not cont then return nil end
    local cx,cy=R.Convert(mapID,cont,x,y)
    if not cx then return nil end
    return cont,cx,cy
end

local _,Routing=...
if not Routing.ready then return end
-- Route grid (Gather plan phase 5b; BV Routing's own since 2026-10-10): one
-- raster over the zones of a way, in the coordinates of their continent
-- (or of the one zone), 8 yards a cell.
-- Painted areas mark cells: no-go (blocked), preferred (cheaper), high-risk
-- (dearer, or blocked by the setting). A leg whose straight line crosses
-- nothing costly stays straight; otherwise A* finds the way round and the
-- path is pulled tight again (string pulling). Searches run as coroutines in
-- small slices (Grid.Run), so nothing stutters.
local ns=Routing.ns
local R={}
Routing.Grid=R
R.CELL=8
-- Cities get finer cells (Florian 2026-10-11, Orgrimmar: a small walked
-- area came out as a few 8-yard boxes, over its edge here, short of it
-- there). A space of a map with levels (a city drawn in Route Studio) of
-- at most FINEAREA square yards (Undercity 0.6, Orgrimmar 2.0 million) is
-- cut into FINE-yard cells; zones and continents keep CELL (cheap
-- searches; the terrain's slopes are measured on CELL steps).
R.FINE=4
R.FINEAREA=2200000
-- A map set to finer cells still (Route Studio, Florian 2026-10-13: where
-- 4 yards are too coarse, e.g. narrow gaps between painting): its
-- settings' cell, at least FINEST. Measured with Florian's data (the walk
-- simulator, 20 routes each): at 2 yards preparing a space took about 3.5x
-- (Orgrimmar) and 1.7x (Undercity) as long, a search 2.5x to 2.8x.
R.FINEST=2
function R.CellSize(yards,zones)
    if not (type(yards)=="number" and yards>0 and yards<=R.FINEAREA) then return R.CELL end
    local cell
    local maps=Routing:Data().maps or {}
    for _,zone in ipairs(zones or {}) do
        if #(Routing:ReadLevels(zone) or {})>0 then
            local m=maps[zone]
            local want=type(m)=="table" and tonumber(m.cell) or R.FINE
            want=math.max(R.FINEST,math.min(R.FINE,want))
            cell=math.min(cell or want,want)
        end
    end
    return cell or R.CELL
end
-- The cell size of one map on its own (Route Studio draws areas with it).
function R.CellFor(mapID)
    local w,h=Routing.Call("C_Map.GetMapWorldSize",mapID)
    if type(w)~="number" or w<=0 then w,h=1000,1000 end
    return R.CellSize(w*h,{mapID})
end
-- swim (Florian 2026-10-14): painted water, walkable at the cost of
-- swimming (city canals the terrain data does not know; also outdoors).
local NOGO,PREFER,RISK,ENEMY,WALL,SWIM=1,2,3,4,5,6
R.KIND={nogo=NOGO,prefer=PREFER,risk=RISK,swim=SWIM}
R.WALL=WALL

local function call(...) return Routing.Call(...) end
-- The space a set of zones shares: their continent when they have one.
-- level (Route Studio's levels; nil or 0 the ground): a space above or
-- below the ground has no terrain; only its painted streets are walkable.
function R.Space(zones,level)
    R.affines={}
    local pins=ns.MapPins
    local continent=pins and pins:Continent(zones[1])
    for i=2,#zones do if not pins or pins:Continent(zones[i])~=continent then continent=nil end end
    local space=continent or zones[1]
    local width,height=call("C_Map.GetMapWorldSize",space)
    if type(width)~="number" or width<=0 then width,height=1000,1000 end
    local minX,maxX,minY,maxY=1,0,1,0
    for _,zone in ipairs(zones) do
        local a,b,c,d
        -- Where the zone lies on its space: its corners carried over through
        -- the world, as every point is (Florian 2026-10-12: for Undercity
        -- the client's rectangle was the whole Eastern Kingdoms, searched
        -- in 8-yard cells, and the town fell apart). The client's rectangle
        -- only when that cannot be done.
        if zone==space then a,b,c,d=0,1,0,1
        else
            local x0,y0=R.Convert(zone,space,0,0)
            local x1,y1=R.Convert(zone,space,1,1)
            if type(x0)=="number" and type(x1)=="number" and type(y0)=="number" and type(y1)=="number" and x1~=x0 and y1~=y0 then
                a,b,c,d=math.min(x0,x1),math.max(x0,x1),math.min(y0,y1),math.max(y0,y1)
            else a,b,c,d=call("C_Map.GetMapRectOnMap",zone,space) end
        end
        if type(a)~="number" or not (type(b)=="number" and b>a and type(d)=="number" and d>c) then a,b,c,d=0,1,0,1 end
        minX,maxX,minY,maxY=math.min(minX,a),math.max(maxX,b),math.min(minY,c),math.max(maxY,d)
    end
    -- The settings once per space: Config() checks every setting on each
    -- call, and the search asked it for every cell (2026-10-10: 44 % of a
    -- navigation search).
    local s={mapID=space,width=width,height=height,minX=minX,maxX=maxX,minY=minY,maxY=maxY,zones=zones,cfg=Routing:Config()}
    s.cell=R.CellSize((maxX-minX)*width*(maxY-minY)*height,zones)
    s.cols=math.max(1,math.ceil((maxX-minX)*width/s.cell))
    s.rows=math.max(1,math.ceil((maxY-minY)*height/s.cell))
    s.cells={}
    -- Cells painted as street only by their edge (loose; Florian
    -- 2026-10-13: the line pulled tight cut every corner of a walked area):
    -- walkable for the search, but on a level the line is not pulled
    -- across them (R.Clear).
    s.loose={}
    s.level=level~=0 and level or nil
    if s.level then return s end
    -- Terrain (slopes, water) where the local data has it and the setting wants it.
    local frame=s.cfg.routeTerrain and ns.MapTerrain and ns.MapTerrain:Frame(space)
    if frame and ns.MapTerrain:Data(frame.instance) then s.terrain,s.ground,s.steep,s.elevation,s.walls=frame,{},{},{},{} end
    return s
end
-- A point of one map on another: maps are straight projections of the
-- world, so three points give the whole conversion; it is kept per pair of
-- maps and costs no client call after that (Florian 2026-10-09: the route
-- editor lagged, two client calls for every node, stroke and tile on each
-- redraw). Kept until the next space is made.
R.affines={}
function R.Convert(from,to,x,y)
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
-- Zone point <-> space point (normalized on the space map).
function R.ToSpace(s,mapID,x,y)
    if mapID==s.mapID then return x,y end
    return R.Convert(mapID,s.mapID,x,y)
end
function R.FromSpace(s,x,y)
    for _,zone in ipairs(s.zones) do
        local zx,zy=R.Convert(s.mapID,zone,x,y)
        if zx and zx>=0 and zx<=1 and zy>=0 and zy<=1 then return zone,zx,zy end
    end
    return s.mapID,x,y
end
-- Yards on the space map.
function R.Yards(s,x1,y1,x2,y2)
    local dx,dy=(x2-x1)*s.width,(y2-y1)*s.height
    return math.sqrt(dx*dx+dy*dy)
end
function R.Cell(s,x,y)
    local cx=math.floor((x-s.minX)*s.width/(s.cell or R.CELL))
    local cy=math.floor((y-s.minY)*s.height/(s.cell or R.CELL))
    if cx<0 or cy<0 or cx>=s.cols or cy>=s.rows then return nil end
    return cx,cy
end
-- A space point in an enemy base (after painting: a painted stroke there wins).
function R.InEnemy(s,x,y)
    local cx,cy=R.Cell(s,x,y)
    return cx~=nil and s.cells[cy*s.cols+cx]==ENEMY
end
function R.Center(s,cx,cy)
    return s.minX+(cx+.5)*(s.cell or R.CELL)/s.width,s.minY+(cy+.5)*(s.cell or R.CELL)/s.height
end
R.HORDECAPITALS={1454,1456,1458}
R.ALLIANCECAPITALS={1453,1455,1457}
-- Enemy places (Core: enemy capitals, areas around enemy flight masters)
-- first, so painted strokes can still open a way through.
function R.Enemies(s)
    -- (Off for a way into an enemy base, Florian 2026-10-14: Navigate.enemyOff.)
    local N=Routing.Navigate
    if (N and N.enemyOff) or Routing:Config().enemy=="ignore" or not (ns.MapOverlays and ns.MapOverlays.Hostile) then return end
    local function mark(x0,y0,x1,y1)
        if not (x0 and x1) then return end
        local a,b=R.Cell(s,math.max(s.minX,math.min(x0,x1)),math.max(s.minY,math.min(y0,y1)))
        local c,d=R.Cell(s,math.min(s.maxX-1e-9,math.max(x0,x1)),math.min(s.maxY-1e-9,math.max(y0,y1)))
        if a and c then
            for cy=b,d do R.Pace(c-a+1);for cx=a,c do s.cells[cy*s.cols+cx]=ENEMY end end
        end
    end
    -- The other side's capitals, all of their maps (Florian 2026-10-15:
    -- Core's enemy places of a capital are the rectangles of its map
    -- labels; most of a city was not avoided).
    local mine=ns.MapOverlays.PlayerFaction and ns.MapOverlays.PlayerFaction()
    local enemy=mine=="Horde" and R.ALLIANCECAPITALS or mine=="Alliance" and R.HORDECAPITALS or {}
    for _,city in ipairs(enemy) do
        local x0,y0=R.ToSpace(s,city,0,0)
        local x1,y1=R.ToSpace(s,city,1,1)
        if x0 and x1 and math.max(x0,x1)>=s.minX and math.min(x0,x1)<=s.maxX and math.max(y0,y1)>=s.minY and math.min(y0,y1)<=s.maxY then mark(x0,y0,x1,y1) end
    end
    for _,zone in ipairs(s.zones) do
        for _,place in ipairs(ns.MapOverlays:Hostile(zone)) do
            local x0,y0=R.ToSpace(s,zone,place.left,place.top)
            local x1,y1=R.ToSpace(s,zone,place.right,place.bottom)
            if x0 and x1 then
                local a,b=R.Cell(s,math.max(s.minX,math.min(x0,x1)),math.max(s.minY,math.min(y0,y1)))
                local c,d=R.Cell(s,math.min(s.maxX-1e-9,math.max(x0,x1)),math.min(s.maxY-1e-9,math.max(y0,y1)))
                if a and c then
                    -- Row by row with the pace (Claude 2026-10-20: the enemy places of a continent at
                    -- once were one piece of 60-80 ms and 10 MB in game).
                    for cy=b,d do R.Pace(c-a+1);for cx=a,c do s.cells[cy*s.cols+cx]=ENEMY end end
                end
            end
        end
    end
end
-- Transitions (bridges, tunnels, cave entrances, Florian 2026-10-08): a
-- link from one cell to another at its walking length; one-way ones only
-- forwards. s.links[from] = {{to, yards}}; s.linked[from .. ">" .. to] =
-- its exact ends {ax, ay, bx, by} (the way passes there, not at the cells'
-- middles).
-- Transitions within this space's level (both ends on it); those between
-- levels belong to the travel plan (Navigate), not to one grid.
function R.SameLevel(s,link)
    -- A lift is never walked as a link of the grid, also from ground to
    -- ground (Codex 2026-10-16, the Great Lift: walked as a line, no wait);
    -- it is a transition of its own (N:Doors).
    if link.kind=="lift" then return false end
    local level=s.level or 0
    return (link.a.level or 0)==level and (link.b.level or 0)==level
end
-- An end on a cell no way may enter (set right beside a wall, on a level
-- just off its painted street; Florian's Undercity 2026-10-10: three ends
-- 4 yards outside a ring wall lay on its cells): the nearest walkable cell
-- within SNAP cells takes its place.
-- Yards round a point searched for a walkable cell (Florian 2026-10-11: in
-- cells, the finer city cells halved it and transition ends got stuck).
R.SNAPYARDS=16
function R.Snap(s,cx,cy)
    if not cx or R.CellCost(s,cx,cy) then return cx,cy end
    local best,bestD
    local reach=math.ceil(R.SNAPYARDS/(s.cell or R.CELL))
    for dy=-reach,reach do
        for dx=-reach,reach do
            local nx,ny=cx+dx,cy+dy
            local d=dx*dx+dy*dy
            if (not bestD or d<bestD) and nx>=0 and ny>=0 and nx<s.cols and ny<s.rows and R.CellCost(s,nx,ny) then best,bestD={nx,ny},d end
        end
    end
    if best then return best[1],best[2] end
    return cx,cy
end
-- A transition's end on a blocked cell (Florian 2026-10-11: ends right on
-- Undercity's ring walls; the nearest free cell could lie on the other
-- side, both ends then on one side and the passage gone): the free cell on
-- its own side, a cell further away from the other end (ox, oy); else the
-- nearest.
function R.SnapAway(s,x,y,ox,oy)
    local cx,cy=R.Cell(s,x,y)
    if not cx or R.CellCost(s,cx,cy) then return cx,cy end
    local dx,dy=(x-ox)*s.width,(y-oy)*s.height
    local len=math.sqrt(dx*dx+dy*dy)
    if len>0 then
        for _,step in ipairs({(s.cell or R.CELL),(s.cell or R.CELL)*1.5,(s.cell or R.CELL)*2}) do
            local px,py=x+dx/len*step/s.width,y+dy/len*step/s.height
            local nx,ny=R.Cell(s,px,py)
            if nx and R.CellCost(s,nx,ny) then return nx,ny end
        end
    end
    return R.Snap(s,cx,cy)
end
-- On a level of given ways only (Florian 2026-10-11: every transition was
-- stuck in Check map), a transition's end off the ways is joined to the
-- nearest way within JOINYARDS by a straight piece, never through a wall.
R.JOINYARDS=20
function R.JoinEnds(s,links)
    if not (s.waysOnly and s.onway) then return end
    local reach=math.ceil(R.JOINYARDS/(s.cell or R.CELL))
    local zones={}
    for _,zone in ipairs(s.zones) do zones[zone]=true end
    for _,link in ipairs(links or {}) do
        for _,e in ipairs({link.a,link.b}) do
            if type(e)=="table" and zones[e.mapID] and (e.level or 0)==(s.level or 0) then
                local x,y=R.ToSpace(s,e.mapID,e.x,e.y)
                local cx,cy
                if x then cx,cy=R.Cell(s,x,y) end
                if cx and not R.CellCost(s,cx,cy) then
                    local best,bestD
                    for dy=-reach,reach do
                        for dx=-reach,reach do
                            local nx,ny=cx+dx,cy+dy
                            local d=dx*dx+dy*dy
                            if (not bestD or d<bestD) and nx>=0 and ny>=0 and nx<s.cols and ny<s.rows and s.onway[ny*s.cols+nx] then best,bestD={nx,ny},d end
                        end
                    end
                    if best then
                        local steps=math.max(math.abs(best[1]-cx),math.abs(best[2]-cy))
                        local piece,blocked={},false
                        for i=0,steps do
                            local px=cx+math.floor((best[1]-cx)*i/math.max(1,steps)+.5)
                            local py=cy+math.floor((best[2]-cy)*i/math.max(1,steps)+.5)
                            if s.cells[py*s.cols+px]==WALL then blocked=true;break end
                            piece[#piece+1]=py*s.cols+px
                        end
                        if not blocked then
                            for i,index in ipairs(piece) do
                                s.onway[index]=true
                                -- The piece is a way of its own for the steps along ways.
                                local prev=piece[i-1]
                                if s.wayAdj and prev and prev~=index then s.wayAdj[prev..">"..index]=true;s.wayAdj[index..">"..prev]=true end
                            end
                        end
                    end
                end
            end
        end
    end
end
function R.Links(s,links)
    -- Given ways (R.Ways) may have added theirs already.
    s.links,s.linked,s.back=s.links or {},s.linked or {},s.back or {}
    for _,link in ipairs(links or {}) do
      if R.SameLevel(s,link) then
        local ax,ay=R.ToSpace(s,link.a.mapID,link.a.x,link.a.y)
        local bx,by=R.ToSpace(s,link.b.mapID,link.b.x,link.b.y)
        local acx,acy,bcx,bcy
        if ax and bx then
            acx,acy=R.SnapAway(s,ax,ay,bx,by)
            bcx,bcy=R.SnapAway(s,bx,by,ax,ay)
        end
        if acx and bcx then
            local a,b=acy*s.cols+acx,bcy*s.cols+bcx
            local yards=R.Yards(s,ax,ay,bx,by)
            -- A walked transition (a ramp): as long as its shape, and on the
            -- same map walked along it (Codex 2026-10-16: a bent bridge on the
            -- ground was walked as the straight line between its ends).
            local shape
            if type(link.path)=="table" and #link.path>=6 then
                local along,lx,ly=0,nil,nil
                shape={}
                for i=1,#link.path-1,2 do
                    local px,py=R.ToSpace(s,link.a.mapID,link.path[i],link.path[i+1])
                    if px and lx then along=along+R.Yards(s,lx,ly,px,py) end
                    if px then shape[#shape+1]={px,py} end
                    lx,ly=px,py
                end
                if along>yards then yards=along end
            end
            local back
            if shape then back={};for i=#shape,1,-1 do back[#back+1]=shape[i] end end
            s.links[a]=s.links[a] or {};table.insert(s.links[a],{b,yards});s.linked[a..">"..b]={ax,ay,bx,by,shape=shape}
            s.back[b]=s.back[b] or {};table.insert(s.back[b],{a,yards})
            if not link.oneway then
                s.links[b]=s.links[b] or {};table.insert(s.links[b],{a,yards});s.linked[b..">"..a]={bx,by,ax,ay,shape=back}
                s.back[a]=s.back[a] or {};table.insert(s.back[a],{b,yards})
            end
        end
      end
    end
end
-- Painted strokes of the zones (in order, later ones win) into the cells.
-- A polygon (corners x1, y1, x2, y2, ... on its zone) fills every cell
-- whose middle lies inside it (even-odd rule).
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
-- Painting a space gives the frame back now and then (Florian 2026-10-14:
-- a generated Undercity of 1000 areas on 34 levels with 2-yard cells, the
-- first way on a level painted it in one piece): after about PAINTSTEP
-- cells, while it runs as a coroutine (R.Run), as the search does.
R.PAINTSTEP=4000
R.painted=0
-- With the game's clock by time (R.Breathe, every PAINTLOOK cells; Claude
-- 2026-10-20: rows of a large polygon cost far more than their cells).
R.PAINTLOOK=300
function R.Pace(cells)
    R.painted=R.painted+cells
    if R.sliceBegan and rawget(_G,"debugprofilestop") then
        if R.painted>=R.PAINTLOOK then R.painted=0;R.Breathe() end
    elseif R.painted>=R.PAINTSTEP then
        R.painted=0
        if coroutine.running() then coroutine.yield() end
    end
end
-- By time, where the work of a step varies (the plan's network search): yields
-- once the slice has run SLICE ms (Claude 2026-10-20: a step count let one
-- slice run 150-180 ms in game). Never inside a metamethod (Lua 5.1 cannot
-- yield there).
R.SLICE=6
function R.Breathe()
    local clock=R.sliceBegan and rawget(_G,"debugprofilestop")
    if clock and clock()-R.sliceBegan>=(R.sliceLimit or R.SLICE) and coroutine.running() then coroutine.yield() end
end
-- Where a row of the polygon is crossed (R.Inside's own sums, so the
-- answer is the same): its x, sorted. A point of that row lies inside when
-- an odd number of them lies to its right.
local function crossings(poly,y)
    local out={}
    local n=#poly/2
    local j=n
    for i=1,n do
        local xi,yi,xj,yj=poly[2*i-1],poly[2*i],poly[2*j-1],poly[2*j]
        if (yi>y)~=(yj>y) then out[#out+1]=(xj-xi)*(y-yi)/(yj-yi)+xi end
        j=i
    end
    table.sort(out)
    return out
end
-- How many crossings lie right of x (strictly, as R.Inside: x < cross).
local function rightOf(xs,x)
    local lo,hi=1,#xs+1
    while lo<hi do
        local mid=math.floor((lo+hi)/2)
        if xs[mid]>x then hi=mid else lo=mid+1 end
    end
    return #xs-lo+1
end
-- A polygon's cells (Florian 2026-10-14: painting was half of a way's
-- time in Undercity): row by row from its crossings instead of every
-- corner for every cell; the same cells as R.PolygonByCell (spec).
function R.Polygon(s,zone,area)
    local poly={}
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    for i=1,#area.poly-1,2 do
        local x,y=R.ToSpace(s,zone,area.poly[i],area.poly[i+1])
        if not x then return end
        poly[#poly+1]=x;poly[#poly+1]=y
        minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
    end
    local a,b=R.Cell(s,math.max(s.minX,minX),math.max(s.minY,minY))
    local c,d=R.Cell(s,math.min(s.maxX-1e-9,maxX),math.min(s.maxY-1e-9,maxY))
    if not (a and c) then return end
    local code=R.KIND[area.kind]
    local inset=tonumber(area.inset) or 0
    local generous=area.kind=="prefer"
    local hx,hy=(s.cell or R.CELL)/2/s.width,(s.cell or R.CELL)/2/s.height
    local w,h=s.width,s.height
    local function ok(xs,x,y) return rightOf(xs,x)%2==1 and (inset<=0 or R.EdgeDistance(poly,x,y,w,h)>=inset) end
    for cy=b,d do
        R.Pace(c-a+1)
        local _,y=R.Center(s,a,cy)
        local mid=crossings(poly,y)
        local up,down
        if generous then up,down=crossings(poly,y-hy/2),crossings(poly,y+hy/2) end
        if #mid>0 or (generous and (#up>0 or #down>0)) then
            for cx=a,c do
                local x=R.Center(s,cx,cy)
                local i=cy*s.cols+cx
                if ok(mid,x,y) then s.cells[i]=code;s.loose[i]=nil
                elseif generous and (ok(up,x-hx/2,y-hy/2) or ok(up,x+hx/2,y-hy/2) or ok(down,x-hx/2,y+hy/2) or ok(down,x+hx/2,y+hy/2)) then
                    s.cells[i]=code;s.loose[i]=true
                end
            end
        end
    end
end
-- The way before (each cell against every corner): kept for the spec that
-- holds R.Polygon to the same cells.
function R.PolygonByCell(s,zone,area)
    local poly={}
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    for i=1,#area.poly-1,2 do
        local x,y=R.ToSpace(s,zone,area.poly[i],area.poly[i+1])
        if not x then return end
        poly[#poly+1]=x;poly[#poly+1]=y
        minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
    end
    local a,b=R.Cell(s,math.max(s.minX,minX),math.max(s.minY,minY))
    local c,d=R.Cell(s,math.min(s.maxX-1e-9,maxX),math.min(s.maxY-1e-9,maxY))
    if not (a and c) then return end
    local code=R.KIND[area.kind]
    -- inset (yards): only cells this far inside its edge (Florian
    -- 2026-10-11: an area walked along the walls kept the way on them).
    local inset=tonumber(area.inset) or 0
    local hx,hy=(s.cell or R.CELL)/2/s.width,(s.cell or R.CELL)/2/s.height
    -- Each cell's test walks all corners: weighed by them.
    local weight=math.max(1,#poly/2/16)
    for cy=b,d do
        R.Pace((c-a+1)*weight)
        for cx=a,c do
            local x,y=R.Center(s,cx,cy)
            if R.Covers(poly,x,y,hx,hy,inset,s.width,s.height,false) then s.cells[cy*s.cols+cx]=code;s.loose[cy*s.cols+cx]=nil
            elseif area.kind=="prefer" and R.Covers(poly,x,y,hx,hy,inset,s.width,s.height,true) then s.cells[cy*s.cols+cx]=code;s.loose[cy*s.cols+cx]=true end
        end
    end
end
-- Does an area take a cell (middle x, y; half its size hx, hy)? Its middle
-- inside, inset yards from the edge; a street also with part of it
-- (Florian 2026-10-11: a small walked area kept three cells in its middle):
-- a quarter point of the cell inside is enough. No-go only by its middle,
-- so narrow passages beside it stay open.
function R.Covers(poly,x,y,hx,hy,inset,w,h,generous)
    local function ok(px,py) return R.Inside(poly,px,py) and (inset<=0 or R.EdgeDistance(poly,px,py,w,h)>=inset) end
    if ok(x,y) then return true end
    if not generous then return false end
    return ok(x-hx/2,y-hy/2) or ok(x+hx/2,y-hy/2) or ok(x-hx/2,y+hy/2) or ok(x+hx/2,y+hy/2)
end
-- Yards from a point to the nearest edge of a polygon (w, h: yards of a
-- unit of x and y).
function R.EdgeDistance(poly,x,y,w,h)
    local n=#poly/2
    local best=math.huge
    for i=1,n do
        local ax,ay=poly[2*i-1]*w,poly[2*i]*h
        local j=i%n+1
        local bx,by=poly[2*j-1]*w,poly[2*j]*h
        local px,py=x*w,y*h
        local vx,vy=bx-ax,by-ay
        local len=vx*vx+vy*vy
        local t=len>0 and math.max(0,math.min(1,((px-ax)*vx+(py-ay)*vy)/len)) or 0
        local ex,ey=ax+vx*t-px,ay+vy*t-py
        local d=math.sqrt(ex*ex+ey*ey)
        if d<best then best=d end
    end
    return best
end
-- A map whose ground is walkable only where painted (Florian 2026-10-11:
-- "make the whole layer no-go and paint the positive in"): on the ground,
-- its rectangle no-go first; strokes, areas and ways open it again.
function R.PaintedOnly(s)
    if s.level then return end
    local maps=s.data and s.data.maps or Routing:Data().maps
    for _,zone in ipairs(s.zones) do
        local m=type(maps)=="table" and maps[zone]
        if type(m)=="table" and m.paintedOnly then
            local x0,y0=R.ToSpace(s,zone,0,0)
            local x1,y1=R.ToSpace(s,zone,1,1)
            if x0 and x1 then
                local a,b=R.Cell(s,math.max(s.minX,math.min(x0,x1)),math.max(s.minY,math.min(y0,y1)))
                local c,d=R.Cell(s,math.min(s.maxX-1e-9,math.max(x0,x1)),math.min(s.maxY-1e-9,math.max(y0,y1)))
                if a and c then
                    for cy=b,d do R.Pace(c-a+1);for cx=a,c do s.cells[cy*s.cols+cx]=NOGO end end
                end
            end
        end
    end
end
-- An area's circles (Route Studio's fill "circles", Florian 2026-10-11 and
-- 13): middles on a grid inside the shape, CIRCLESTEP x r apart
-- (overlapping), at least one (its middle). poly in map units, w, h: yards
-- of a unit. Flat {x1, y1, ...}.
R.CIRCLESTEP=1.4
R.MAXCIRCLES=20000
function R.CircleCenters(poly,r,w,h)
    local out={}
    if type(poly)~="table" or #poly<6 or not (r and r>0) then return out end
    local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
    local sx,sy,n=0,0,#poly/2
    for i=1,#poly-1,2 do
        minX,minY,maxX,maxY=math.min(minX,poly[i]),math.min(minY,poly[i+1]),math.max(maxX,poly[i]),math.max(maxY,poly[i+1])
        sx,sy=sx+poly[i],sy+poly[i+1]
    end
    local stepX,stepY=r*R.CIRCLESTEP/w,r*R.CIRCLESTEP/h
    local cols,rows=math.floor((maxX-minX)/stepX),math.floor((maxY-minY)/stepY)
    -- (A huge shape with tiny circles: at its middle only.)
    if (cols+1)*(rows+1)<=R.MAXCIRCLES then
        local x0,y0=(minX+maxX)/2-cols*stepX/2,(minY+maxY)/2-rows*stepY/2
        for j=0,rows do
            for i=0,cols do
                local x,y=x0+i*stepX,y0+j*stepY
                if R.Inside(poly,x,y) then out[#out+1]=x;out[#out+1]=y end
            end
        end
    end
    if #out==0 then out[1],out[2]=sx/n,sy/n end
    return out
end
-- The cells a circle (middle x, y in the space; r yards) takes: those whose
-- middle lies inside it, and the one under its middle (loose when its
-- middle is not; so too, for an area of circles, cells whose middle lies
-- outside the area: clip, its corners in the space).
local function circle(s,x,y,r,code,clip)
    local cx0,cy0=R.Cell(s,x,y)
    if not cx0 then return end
    local reach=math.ceil(r/(s.cell or R.CELL))+1
    R.Pace((2*reach+1)*(2*reach+1))
    for dy=-reach,reach do
        for dx=-reach,reach do
            local cx,cy=cx0+dx,cy0+dy
            if cx>=0 and cy>=0 and cx<s.cols and cy<s.rows then
                local mx,my=R.Center(s,cx,cy)
                local inside=R.Yards(s,mx,my,x,y)<=r
                if (dx==0 and dy==0) or inside then
                    local i=cy*s.cols+cx
                    s.cells[i]=code
                    if inside and not (clip and not R.Inside(clip,mx,my)) then s.loose[i]=nil else s.loose[i]=true end
                end
            end
        end
    end
end
function R.Paint(s,areas)
    R.Enemies(s)
    R.PaintedOnly(s)
    for _,zone in ipairs(s.zones) do
        for _,stroke in ipairs(areas[zone] or {}) do
          if (stroke.level or 0)==(s.level or 0) then
            if stroke.poly and stroke.fill=="circles" then
                -- An area filled with circles: each like a stroke of its size.
                local w,h=Routing.Call("C_Map.GetMapWorldSize",zone)
                w,h=type(w)=="number" and w>0 and w or 1000,type(h)=="number" and h>0 and h or 1000
                local r=tonumber(stroke.cr) or 8
                local c=R.CircleCenters(stroke.poly,r,w,h)
                local clip={}
                for i=1,#stroke.poly-1,2 do
                    local x,y=R.ToSpace(s,zone,stroke.poly[i],stroke.poly[i+1])
                    if x then clip[#clip+1]=x;clip[#clip+1]=y end
                end
                for i=1,#c-1,2 do
                    local x,y=R.ToSpace(s,zone,c[i],c[i+1])
                    if x then circle(s,x,y,r,R.KIND[stroke.kind],#clip>=6 and clip or nil) end
                end
            elseif stroke.poly then R.Polygon(s,zone,stroke) end
            -- A stroke: the cells whose middle lies inside it, and the one
            -- under its centre (Florian 2026-10-11: a 6-yard no-go stroke
            -- was rounded up to a 24-yard cross of cells, and a narrow gap
            -- between two no-go lines closed in the grid though it was open
            -- on the map).
            if not stroke.poly then
                local x,y=R.ToSpace(s,zone,stroke.x,stroke.y)
                if x then circle(s,x,y,stroke.r or 20,R.KIND[stroke.kind]) end
            end
          end
        end
    end
end
-- Walls (Route Studio, Florian 2026-10-10): lines, circles and arcs that no
-- way crosses; a transition leads through. Each wall marks the cells it
-- runs through (sampled every half cell), joined edge to edge (a step at a
-- slant marks the corner cell too), so neither the search nor a line pulled
-- tight (R.Clear) slips through between two of its cells. Only this
-- space's level. Circles and arcs: centre x, y (map),
-- r in yards, from and to in degrees clockwise from north (a full circle
-- without them). walls[mapID] = {wall, ...}.
function R.WallPoints(s,zone,wall)
    local out={}
    if wall.kind=="circle" or wall.kind=="arc" then
        local x,y=R.ToSpace(s,zone,wall.x,wall.y)
        if not (x and wall.r) then return out end
        local from=wall.kind=="arc" and (wall.from or 0) or 0
        local to=wall.kind=="arc" and (wall.to or 360) or 360
        if to<from then to=to+360 end
        local length=math.rad(to-from)*wall.r
        local n=math.max(8,math.ceil(length/((s.cell or R.CELL)/2)))
        for i=0,n do
            local a=math.rad(from+(to-from)*i/n)
            out[#out+1]={x+math.sin(a)*wall.r/s.width,y-math.cos(a)*wall.r/s.height}
        end
    else
        for i=1,#(wall.points or {})-1,2 do
            local x,y=R.ToSpace(s,zone,wall.points[i],wall.points[i+1])
            if x then out[#out+1]={x,y} end
        end
    end
    return out
end
function R.Walls(s,walls)
    for _,zone in ipairs(s.zones) do
        for _,wall in ipairs(type(walls)=="table" and walls[zone] or {}) do
            if (wall.level or 0)==(s.level or 0) then
                local points=R.WallPoints(s,zone,wall)
                for i=2,#points do
                    local ax,ay,bx,by=points[i-1][1],points[i-1][2],points[i][1],points[i][2]
                    local n=math.max(1,math.ceil(R.Yards(s,ax,ay,bx,by)/((s.cell or R.CELL)/2)))
                    local lx,ly
                    for j=0,n do
                        local cx,cy=R.Cell(s,ax+(bx-ax)*j/n,ay+(by-ay)*j/n)
                        if cx then
                            s.cells[cy*s.cols+cx]=WALL
                            if lx and cx~=lx and cy~=ly then s.cells[ly*s.cols+cx]=WALL end
                        end
                        lx,ly=cx,cy
                    end
                end
            end
        end
    end
end
-- Terrain cost of a cell (Florian 2026-10-08: avoid steep slopes and
-- water): steeper is dearer, the steepest (not walkable by the data) very
-- dear rather than blocked (jumping still gets you up some of it); water
-- by "Avoid water", magma and slime almost never. Cached per cell.
R.SLOPE={1,1.2,2.5,8}
-- Values the expert settings can change (UI/Expert.lua): steep slope,
-- swimming, roads and walked ways, the straight-line limit.
R.STEEP=8;R.SWIM=6;R.ROAD=.6;R.CLEAR=1.25
-- Roads and walked ways apart (Florian 2026-10-16: a slider each; roads a
-- loose preference, never more): Routing's settings in percent of open ground.
-- The safe mode (Routing's setting routeMode): roads at most SAFEROAD,
-- swimming SAFESWIM.
R.SAFEROAD=.4;R.SAFESWIM=12
function R.RoadCost(s)
    local c=s and s.cfg or Routing:Config()
    local cost=(c.roadPercent or R.ROAD*100)/100
    if Routing:RouteMode()=="safe" then cost=math.min(cost,R.SAFEROAD) end
    return cost
end
function R.WalkedCost(s) return ((s and s.cfg or Routing:Config()).walkedPercent or R.ROAD*100)/100 end
-- Zones above your level, avoided (Florian 2026-10-16): their ground this
-- many times dearer (a way through one stays possible when there is no other).
R.HIGHZONE=4
R.ZONEBLOCK=16   -- cells of a block whose zone is asked once
-- Painted water (kind swim): as deep water of the terrain, SWIM with
-- "Avoid water", else 1.5 (swimming is slower and leaves the mount); on a
-- level half of it, as its streets cost half of plain ground.
function R.SwimCost(s)
    local c=s.cfg or Routing:Config()
    if Routing:RouteMode()=="safe" then return R.SAFESWIM end
    return c.avoidWater and R.SWIM or 1.5
end
-- Cities (navigation prototype, Florian 2026-10-10): the terrain data is
-- the ground only; buildings, walls and caves of the capitals (their own
-- models) are missing, so a way there went straight through them. With
-- R.Cities a city's cells count only where someone walked (Trace, within
-- CITYREACH terrain cells, bridging the gaps between samples): walked like a
-- road, else CITY times dearer (not blocked: a way always comes out). On
-- walked city cells the ground's walls and slopes do not count (under
-- buildings they are not the real ones).
R.CITY=25;R.CITYREACH=2
-- An open level's unpainted cells (Route Studio: "Only painted walkable"
-- switched off): walkable, this much dearer than a street.
R.OPEN=10
-- Walked ways (recorded by BV Gather, which sets these): WalkCount(instance,
-- X, Y) -> times walked in that terrain cell; PreferWalked() -> cells walked
-- WALKED times or more count like a road. Without Gather: nil.
R.WalkCount,R.PreferWalked,R.WALKED=nil,nil,3
function R.Cities(s,maps)
    s.cities,s.cityWalked={},{}
    for _,mapID in ipairs(maps) do
        local minX,maxX,minY,maxY=call("C_Map.GetMapRectOnMap",mapID,s.mapID)
        if type(minX)=="number" and maxX>minX then s.cities[#s.cities+1]={minX,maxX,minY,maxY} end
    end
end
local function cityCost(s,index,x,y)
    for _,r in ipairs(s.cities) do
        if x>=r[1] and x<=r[2] and y>=r[3] and y<=r[4] then
            local f=s.terrain
            local X,Y=f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx
            local step=ns.MapTerrain.ADT/64
            local walked=false
            if R.WalkCount then
                for dx=-R.CITYREACH,R.CITYREACH do
                    for dy=-R.CITYREACH,R.CITYREACH do
                        if R.WalkCount(f.instance,X+dx*step,Y+dy*step)>0 then walked=true;break end
                    end
                    if walked then break end
                end
            end
            -- Painted streets (Route Studio) count like walked ones.
            if s.cells[index]==PREFER then walked=true end
            s.cityWalked[index]=walked
            return walked and R.WalkedCost(s) or R.CITY
        end
    end
end
-- The space's terrain caches (ground cost, steep, height) in blocks of CHUNK cells
-- (Claude 2026-10-20: one table of millions of cells, written while the game's
-- collector ran, was gone through again at once at the end of its round, 44 ms
-- for 2 million offline and stops of 465-793 ms in game; blocks keep that small).
R.CHUNK=4096
function R.CacheGet(t,i) local b=t[i-i%R.CHUNK];return b and b[i] end
function R.CacheSet(t,i,v)
    local k=i-i%R.CHUNK
    local b=t[k];if not b then b={};t[k]=b end
    b[i]=v
end
local cacheGet,cacheSet=R.CacheGet,R.CacheSet
function R.Ground(s,cx,cy)
    if not s.terrain then return 1 end
    local index=cy*s.cols+cx
    local cost=cacheGet(s.ground,index)
    if cost then return cost end
    local f=s.terrain
    local x,y=R.Center(s,cx,cy)
    if s.cities then
        cost=cityCost(s,index,x,y)
        if cost then
            -- A city's rectangle reaches over the open ground around it
            -- (Florian/Codex 2026-10-15: Undercity's covers the road to
            -- Silverpine and the hills beside it, the way went over an 81
            -- degree slope): on cells nobody walked or painted the terrain's
            -- steep slopes still count, and its dry roads stay roads.
            if s.cityWalked[index]==false then
                local code=ns.MapTerrain:Code(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
                if code then
                    if code%4==3 then cacheSet(s.steep,index,true) end
                    local dry=math.floor(code/4)%4==0
                    if dry and code%4~=3 and (s.cfg or Routing:Config()).preferRoads and (code%64>=32 or (s.roads and s.roads[index])) then cost=R.RoadCost(s) end
                end
            end
            cacheSet(s.ground,index,cost);return cost
        end
    end
    local code=ns.MapTerrain:Code(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
    local dry=true
    if not code then cost=1
    else
        local water=math.floor(code/4)%4
        dry=water==0
        -- A steep slope stays steep also under a road (Codex 2026-10-16: the
        -- road bit skipped the steep mark, and the climb was allowed).
        if dry and code%4==3 then cacheSet(s.steep,index,true) end
        -- Roads (the client's road textures, Florian 2026-10-08: safe ways
        -- marked in advance; and Road Studio's roads, 2026-10-16) are a
        -- preference: cheaper where walkable and dry, never more.
        -- No road discount on a steep cell at all (Codex 2026-10-16).
        if dry and code%4~=3 and (s.cfg or Routing:Config()).preferRoads and (code%64>=32 or (s.roads and s.roads[index])) then cost=R.RoadCost(s)
        elseif water==3 then cost=20
        elseif water==2 then cost=R.SwimCost(s)
        elseif water==1 then cost=1.2
        else cost=R.SLOPE[code%4+1] end
    end
    -- Ways walked often (Trace) are cheaper, like a road (their own factor).
    if R.WalkCount and R.PreferWalked and R.PreferWalked() then
        local f=s.terrain
        local wx,wy=R.Center(s,cx,cy)
        if R.WalkCount(f.instance,f.a[f.iy]+wy*f.dy,f.a[f.ix]+wx*f.dx)>=R.WALKED then cost=math.min(cost,R.WalkedCost(s)) end
    end
    -- A zone above your level, avoided: dearer.
    if s.highZones and R.HighZone(s,cx,cy) then cost=cost*R.HIGHZONE end
    cacheSet(s.ground,index,cost)
    return cost
end
-- What makes a cell hard going, for the difficult spots of a route
-- (Florian 2026-10-09: the data cannot know everything; tell the player
-- where to paint): "risk", "enemy", "magma", "swim" (with Avoid water),
-- "steep" (not walkable by the slope data) or nil. Preferred ground is the
-- player's own choice: never a difficult spot.
function R.Hazard(s,cx,cy)
    local code=s.cells[cy*s.cols+cx]
    if code==PREFER then return nil end
    if code==RISK then return "risk" end
    if code==ENEMY then return "enemy" end
    if code==SWIM then return (s.cfg or Routing:Config()).avoidWater and "swim" or nil end
    if not s.terrain then return nil end
    local f=s.terrain
    local x,y=R.Center(s,cx,cy)
    local t=ns.MapTerrain:Code(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
    if not t then return nil end
    local water=math.floor(t/4)%4
    if water==3 then return "magma" end
    if water==2 and (s.cfg or Routing:Config()).avoidWater then return "swim" end
    if water==0 and t%4==3 then return "steep" end
    return nil
end
-- Ground height of a cell (yards), cached; nil without height data.
function R.Height(s,cx,cy)
    local index=cy*s.cols+cx
    local h=cacheGet(s.elevation,index)
    if h==nil then
        local f=s.terrain
        local x,y=R.Center(s,cx,cy)
        h=ns.MapTerrain:Height(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx) or false
        cacheSet(s.elevation,index,h)
    end
    return h or nil
end
-- Cliffs have a direction (Florian 2026-10-08): down a steep face is fine
-- for a short drop ("safe", a step falls at most SAFEDROP yards) or for any
-- drop ("always": Slow Fall, Levitate); up stays as dear as before.
R.SAFEDROP=12
-- Up a steep face is not walkable at all (Florian 2026-10-09: the route
-- dropped into a ditch nobody gets out of); without heights it stays dear.
-- goal: the cell is the end of the leg (a node on a slope): a small step
-- up into it is fine, a climb out of a ditch is not (Florian 2026-10-09).
R.GOALSTEP=4
-- A step that rises or falls more than R.MAXRISE is a cliff too, whatever
-- the slope class says (Florian 2026-10-09, Durotar 54,27: the slope cells
-- are 8 yd, the heights 16 yd; at an edge a cell counted as flat although
-- it lay 33 yd higher, and the route climbed the wall).
R.MAXRISE=14
-- Walls between neighbouring cells from the full vertex heights (Core
-- MapTerrain:Wall, data from tools/build_terrain_data.py). Florian
-- 2026-10-09, Durotar 53,29: the heights lie 16 yd apart, a 36 yd wall
-- became a ramp of 17 yd per cell, and the search went up it at a slant,
-- where each step rose less than R.MAXRISE. Florian's idea: walls known in
-- advance from the fine heights. 0 none, 1 up from a to b, 2 down, 3 both.
function R.TerrainCell(s,x,y)
    local f=s.terrain
    return ns.MapTerrain.Cell(f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
end
-- Fall heights (Florian 2026-10-09: "Short drops" judged by the coarse
-- heights let high cliffs pass): per wall the height of its steep face as
-- a class (data layers falls/falls2, three bits per direction), read here
-- as the class's upper bound in yards.
R.FALLS={4,6,8,12,16,20,30,60}
local FALLLAYER={[1]={"falls",0},[64]={"falls",3},[65]={"falls2",0},[63]={"falls2",3}}
function R.FallOf(instance,gx1,gy1,gx2,gy2)
    local dx,dy=gx2-gx1,gy2-gy1
    if dy<0 or (dy==0 and dx<0) then gx1,gy1,dx,dy=gx2,gy2,-dx,-dy end
    local which=FALLLAYER[dy*64+dx]
    if not which then return nil end
    local col,row=math.floor(gx1/64),math.floor(gy1/64)
    local codes=ns.MapTerrain:Codes(instance,col,row,which[1])
    if not codes then return nil end
    local class=math.floor((codes[(gy1-row*64)*64+(gx1-col*64)+1] or 0)/2^which[2])%8
    return R.FALLS[class+1]
end
-- The wall between two space points and, for a wall, its fall height
-- (nil without fall data).
local function fineWall(s,wall,fall,ax,ay,bx,by)
    if not R.FineWall then return wall,fall end
    local extra,height=R.FineWall(s,ax,ay,bx,by)
    if extra==0 then return wall,fall end
    local up=wall%2==1 or extra%2==1
    local down=wall>=2 or extra>=2
    return (up and 1 or 0)+(down and 2 or 0),(fall or height) and math.max(fall or 0,height or 0)
end
function R.Wall(s,ax,ay,bx,by)
    local T=ns.MapTerrain
    if not (type(s.terrain)=="table" and s.terrain.a and T.Wall) then return 0 end
    local gx1,gy1=R.TerrainCell(s,ax,ay)
    local gx2,gy2=R.TerrainCell(s,bx,by)
    if gx1==gx2 and gy1==gy2 then return fineWall(s,0,nil,ax,ay,bx,by) end
    local wall=T:Wall(s.terrain.instance,gx1,gy1,gx2,gy2)
    local fall=wall~=0 and R.FallOf(s.terrain.instance,gx1,gy1,gx2,gy2) or nil
    return fineWall(s,wall,fall,ax,ay,bx,by)
end
-- The walls on a line, sampled every 2 yards (the route cells and the
-- terrain cells do not line up; a slanted step may cross two terrain edges).
-- Each sample's terrain cell is found once and compared with the last one
-- (2026-10-10: R.Wall per piece found both ends again; same result).
function R.LineWall(s,ax,ay,bx,by)
    local T=ns.MapTerrain
    if not (type(s.terrain)=="table" and s.terrain.a and T.Wall) then return 0 end
    local instance=s.terrain.instance
    local n=math.max(1,math.ceil(R.Yards(s,ax,ay,bx,by)/2))
    local up,down,fall=false,false,nil
    local gx1,gy1=R.TerrainCell(s,ax,ay)
    for i=1,n do
        local gx2,gy2=R.TerrainCell(s,ax+(bx-ax)*i/n,ay+(by-ay)*i/n)
        if gx2~=gx1 or gy2~=gy1 then
            local wall=T:Wall(instance,gx1,gy1,gx2,gy2)
            if wall~=0 then
                if wall==1 or wall==3 then up=true end
                if wall==2 or wall==3 then
                    down=true
                    local height=R.FallOf(instance,gx1,gy1,gx2,gy2)
                    if height then fall=math.max(fall or 0,height) end
                end
            end
            gx1,gy1=gx2,gy2
        end
    end
    return fineWall(s,(up and 1 or 0)+(down and 2 or 0),fall,ax,ay,bx,by)
end
-- The wall between two route cells (cached per pair).
function R.CellWall(s,cx,cy,nx,ny)
    if not s.walls then return 0 end
    local key=(cy*s.cols+cx)*9+(ny-cy+1)*3+(nx-cx+1)
    local wall=s.walls[key]
    if wall==nil then
        local ax,ay=R.Center(s,cx,cy)
        local bx,by=R.Center(s,nx,ny)
        local fall
        wall,fall=R.LineWall(s,ax,ay,bx,by)
        s.walls[key]=wall
        if fall then s.falls=s.falls or {};s.falls[key]=fall end
    end
    return wall,s.falls and s.falls[key]
end
function R.Step(s,cx,cy,nx,ny,cost,goal)
    if s.wayAdj and not R.WayStep(s,cy*s.cols+cx,ny*s.cols+nx) then return nil end
    if not s.terrain then return cost end
    local walked=s.cityWalked
    if walked and walked[cy*s.cols+cx] and walked[ny*s.cols+nx] then return cost end
    local onway=s.onway
    if onway and onway[cy*s.cols+cx] and onway[ny*s.cols+nx] then return cost end
    local from,to=R.Height(s,cx,cy),R.Height(s,nx,ny)
    if not (from and to) then return cost end
    local wall,fall=R.CellWall(s,cx,cy,nx,ny)
    -- A wall up (or a ridge) is never climbed; a wall down is a drop, short
    -- by its fall height from the fine heights (the coarse ones where the
    -- data has none).
    if wall==1 or wall==3 then return nil end
    if wall==2 then
        local mode=(s.cfg or Routing:Config()).cliffs
        if mode=="always" or (mode=="safe" and (fall or (from-to))<=R.SAFEDROP) then return cost*1.5 end
        -- Known to be higher than a short drop: never ("never down a mountain").
        if mode=="safe" and fall then return nil end
        return cost*R.SLOPE[4]
    end
    local cliff=cacheGet(s.steep,ny*s.cols+nx) or math.abs(to-from)>R.MAXRISE
    if not cliff then return cost end
    if to>from+1 then
        if goal and to-from<=R.GOALSTEP then return cost end
        return nil
    end
    if to>=from-1 then return cost end
    local mode=(s.cfg or Routing:Config()).cliffs
    if mode=="never" then return cost end
    if mode=="always" or from-to<=R.SAFEDROP then return cost/R.SLOPE[4]*1.5 end
    return cost
end
-- Does the way from one space point to another drop down a steep face
-- (Florian 2026-10-09: show where to jump, so nobody jumps by accident)?
-- Sampled every half cell: a step onto a steep cell that is R.DROP yards
-- or more lower.
R.DROP=12
-- peak: the highest ground of the way just before (a fall spread over two
-- cells is one jump; Florian 2026-10-09, Durotar 54,27: 28 to 11 yards was
-- not marked). Returns the jump and the highest ground of this piece's end.
function R.Drops(s,x1,y1,x2,y2,peak)
    if not s.terrain then return false end
    local steps=math.max(1,math.ceil(R.Yards(s,x1,y1,x2,y2)/((s.cell or R.CELL)/2)))
    local lastCx,lastCy,lastH,lastX,lastY
    local jump=false
    for i=0,steps do
        local t=i/steps
        local px,py=x1+(x2-x1)*t,y1+(y2-y1)*t
        if lastX and not jump then
            local wall=R.Wall(s,lastX,lastY,px,py)
            if wall==2 then jump=true end
        end
        lastX,lastY=px,py
        local cx,cy=R.Cell(s,px,py)
        if cx and (cx~=lastCx or cy~=lastCy) then
            local h=R.Height(s,cx,cy)
            -- A fall of R.DROP or more from the ground just before is a jump
            -- (heights alone: the slope class misses edges, see R.Step).
            if h then
                if (lastH and lastH-h>=R.DROP) or (peak and peak-h>=R.DROP) then jump=true end
                peak=math.max(peak or h,h)
                -- The reference sinks with the way: only the last stretch counts.
                if lastH and h<lastH then peak=math.max(h,peak-((s.cell or R.CELL)/2)) end
            end
            lastCx,lastCy,lastH=cx,cy,h or lastH
        end
    end
    return jump,lastH
end
-- Cost of entering a cell per yard; nil = blocked. Painted areas win over
-- the terrain: preferred ground is cheap whatever its slope.
-- s.costs: during a calculation the cost of each cell is kept (the
-- searches ask for the same cells again and again; Florian 2026-10-09:
-- calculating took long). Painting in the editor has no cache.
function R.Cost(s,cx,cy)
    local costs=s.costs
    if costs then
        local index=cy*s.cols+cx
        local known=costs[index]
        if known~=nil then return known or nil end
        local value=R.CellCost(s,cx,cy)
        costs[index]=value or false
        return value
    end
    return R.CellCost(s,cx,cy)
end
function R.CellCost(s,cx,cy)
    local cost=R.BaseCost(s,cx,cy)
    local i=cy*s.cols+cx
    -- Along a given way where walkable anyway: as cheap as the way.
    if cost and s.waycheap and s.waycheap[i] then return math.min(cost,R.WAYCOST) end
    -- Near a wall or the edge: dearer (not on a given way's point).
    local d=cost and s.near and s.near[i]
    if d and not (s.onway and s.onway[i]) then cost=cost*(1+R.NEAR*(s.nearK+1-d)/s.nearK) end
    return cost
end
function R.BaseCost(s,cx,cy)
    local code=s.cells[cy*s.cols+cx]
    -- On a given way: cheapest of all, on any level, also where no-go is
    -- painted over it (Florian 2026-10-11: no-go over the passages through
    -- Undercity's ring wall cut the town in two; a way set by hand wins).
    -- Walls stay walls (a way passes them by its links).
    if code==WALL then return nil end
    if s.onway and s.onway[cy*s.cols+cx] then return R.WAYCOST end
    if code==NOGO then return nil end
    -- Above the ground (a level of Route Studio): only what is painted as
    -- a street can be walked; the terrain data knows nothing up there.
    -- A level of given ways only (Florian 2026-10-11): its painted streets
    -- only tell the level, the ways lead.
    -- A level set open (Florian 2026-10-11: "only green" by default, per
    -- level switchable): the unpainted walkable too, OPEN times dearer.
    if (s.level or 0)~=0 then
        if s.waysOnly then return nil end
        if code==PREFER then return .5 end
        if code==SWIM then return R.SwimCost(s)*.5 end
        if s.open and code==nil then return R.OPEN end
        return nil
    end
    if code==PREFER then
        -- A painted street in a city: the ground's walls there are not the
        -- real ones (marks it as walked for R.Step).
        if s.cities and s.terrain then R.Ground(s,cx,cy) end
        return .5
    end
    if code==SWIM then return R.SwimCost(s) end
    local cost=1
    if code==RISK then
        local mode=(s.cfg or Routing:Config()).risk
        if mode=="block" then return nil end
        if mode=="avoid" then cost=4 end
    elseif code==ENEMY then
        -- Enemy base: guards; avoided hard, or never with "block".
        if (s.cfg or Routing:Config()).enemy=="block" then return nil end
        cost=10
    end
    return cost*R.Ground(s,cx,cy)
end
-- The straight line between two space points touches only plain,
-- preferred or gently sloped cells (sampled every half cell). Also its cost
-- (the cells' cost per yard along it), for pulling a way tight without
-- leaving a road (R.Trace).
function R.Clear(s,x1,y1,x2,y2)
    local yards=R.Yards(s,x1,y1,x2,y2)
    local steps=math.max(1,math.ceil(yards/((s.cell or R.CELL)/2)))
    local piece=yards/steps
    local sum=0
    local last,lx,ly
    local cells,cols=s.cells,s.cols
    for i=0,steps do
        local t=i/steps
        local px,py=x1+(x2-x1)*t,y1+(y2-y1)*t
        local cx,cy=R.Cell(s,px,py)
        if cx then
            local cost=R.Cost(s,cx,cy)
            -- Gentle slopes and shallow water still count as a clear line.
            if not cost or cost>R.CLEAR then return false end
            if i>0 then sum=sum+cost*piece end
            -- On a level: not across a street cell taken only by its edge
            -- (unless a given way's point lies there).
            if s.level and s.loose and s.loose[cy*cols+cx] and not (s.onway and s.onway[cy*cols+cx]) then return false end
            if s.wayAdj and lx and (cx~=lx or cy~=ly) and not R.WayStep(s,ly*cols+lx,cy*cols+cx) then return false end
            if s.terrain and last and R.Wall(s,last[1],last[2],px,py)~=0 then return false end
            -- At a slant past the corner of a painted wall, or of any cell
            -- not walkable (Claude's walk simulation 2026-10-12: the line
            -- pulled tight slipped between two closed cells the search went
            -- round; the search cuts no corners either): not through.
            if lx and cx~=lx and cy~=ly and (cells[ly*cols+cx]==WALL or cells[cy*cols+lx]==WALL or not R.Cost(s,cx,ly) or not R.Cost(s,lx,cy)) then return false end
            last,lx,ly={px,py},cx,cy
        end
    end
    return true,sum
end

-- Can you walk the straight line from one space point to the other, in
-- this direction? Every step from cell to cell as the search would allow
-- it (blocked cells, walls up, climbs; corners not cut).
function R.Walkable(s,x1,y1,x2,y2)
    -- Cell-centre steps alone do not certify the actual smoothed line.
    -- Bounded fine source patches retain the direction and full face height.
    if R.FineWall then
        local wall,fall=R.FineWall(s,x1,y1,x2,y2)
        if wall%2==1 or (wall>=2 and (s.cfg or Routing:Config()).cliffs=="safe" and (fall or 0)>R.SAFEDROP) then return false end
    end
    local steps=math.max(1,math.ceil(R.Yards(s,x1,y1,x2,y2)/((s.cell or R.CELL)/2)))
    local lx,ly
    for i=0,steps do
        local cx,cy=R.Cell(s,x1+(x2-x1)*i/steps,y1+(y2-y1)*i/steps)
        if not cx then return false end
        if lx and (cx~=lx or cy~=ly) then
            local cost=R.Cost(s,cx,cy)
            if not cost or not R.Step(s,lx,ly,cx,cy,cost,false) then return false end
            if cx~=lx and cy~=ly and (not R.Cost(s,cx,ly) or not R.Cost(s,lx,cy)) then return false end
        elseif not lx and not R.Cost(s,cx,cy) then return false end
        lx,ly=cx,cy
    end
    return true
end

-- A* on the cells (8 neighbours, octile heuristic), yielding every 400 steps.
local SQRT2=math.sqrt(2)
-- A binary heap in two flat arrays (keys, values): no table per entry.
local function heapPush(keys,vals,n,key,value)
    n=n+1
    local i=n
    while i>1 do
        local parent=math.floor(i/2)
        if keys[parent]<=key then break end
        keys[i],vals[i]=keys[parent],vals[parent];i=parent
    end
    keys[i],vals[i]=key,value
    return n
end
local function heapPop(keys,vals,n)
    local topKey,topValue=keys[1],vals[1]
    local key,value=keys[n],vals[n]
    keys[n],vals[n]=nil,nil;n=n-1
    if n>0 then
        local i=1
        while true do
            local l=i*2
            if l>n then break end
            local c=l
            if l+1<=n and keys[l+1]<keys[l] then c=l+1 end
            if keys[c]>=key then break end
            keys[i],vals[i]=keys[c],vals[c];i=c
        end
        keys[i],vals[i]=key,value
    end
    return topKey,topValue,n
end
-- The search over the cells from start: to one goal (with the octile
-- distance as estimate) or, with goals = {[index]=true}, to all of them
-- (no estimate). Ends when every goal is reached, after limit steps or past
-- maxCost. Returns cost and from of the cells it reached.
-- reverse: the steps the other way round (who can reach start), used to
-- tell quickly that a goal on a plateau cannot be reached. The fourth
-- result: every reachable cell was seen (nothing left to search).
-- corridor (R.Coarse): only cells within its coarse cells are searched.
function R.Explore(s,start,goal,goals,limit,maxCost,reverse,weight,corridor)
    local cols,rows,CELL=s.cols,s.rows,s.cell or (s.cell or R.CELL)
    local inside,CF,CC=corridor and corridor.cells,corridor and corridor.F,corridor and corridor.ccols
    -- The cheapest a yard can cost: preferred ground, or given ways where
    -- the space has some (only there, a weaker estimate looks at more cells).
    -- The estimate never counts more, so the ways found stay the shortest.
    -- Roads and walked ways may be set cheaper still (Routing's sliders,
    -- Codex 2026-10-16: at 45 % the estimate was too high).
    local FLOOR=math.min(.5,R.RoadCost(s),R.WalkedCost(s))
    if s.hasWays then FLOOR=math.min(FLOOR,R.WAYCOST) end
    -- The estimate: the octile distance to the goal, or to the nearest of
    -- the goals (still never too high, so the ways found stay the shortest).
    local targets={}
    if goal then targets[1]={goal%cols,math.floor(goal/cols)}
    elseif goals then for index in pairs(goals) do targets[#targets+1]={index%cols,math.floor(index/cols)} end end
    local function h(cx,cy)
        local best
        for i=1,#targets do
            local dx,dy=math.abs(cx-targets[i][1]),math.abs(cy-targets[i][2])
            local d=(math.max(dx,dy)+(SQRT2-1)*math.min(dx,dy))*CELL*FLOOR*(weight or 1)
            if not best or d<best then best=d end
        end
        return best or 0
    end
    local keys,vals,n={},{},0
    local cost,from,closed={[start]=0},{},{}
    local left=0
    if goals then for _ in pairs(goals) do left=left+1 end end
    n=heapPush(keys,vals,n,h(start%cols,math.floor(start/cols)),start)
    local steps=0
    limit=limit or 60000
    local Cost,Step,links=R.Cost,R.Step,reverse and s.back or s.links
    local ended=false
    while n>0 do
        local f,current
        f,current,n=heapPop(keys,vals,n)
        if not closed[current] then
            closed[current]=true
            if current==goal then ended=true;break end
            if goals and goals[current] then left=left-1;if left<=0 then ended=true;break end end
            local g=cost[current]
            if maxCost and g>maxCost then ended=true;break end
            steps=steps+1
            if steps>limit then return cost,from,false end
            if steps%400==0 and coroutine.running() then coroutine.yield() end
            local cx,cy=current%cols,math.floor(current/cols)
            for dy=-1,1 do
                local ny=cy+dy
                if ny>=0 and ny<rows then
                    for dx=-1,1 do
                        local nx=cx+dx
                        if (dx~=0 or dy~=0) and nx>=0 and nx<cols then
                            local index=ny*cols+nx
                            if not closed[index] and (not inside or inside[math.floor(nx/CF)+math.floor(ny/CF)*CC]) then
                                local step
                                if reverse then
                                    -- Walking from the neighbour into this cell.
                                    step=Cost(s,cx,cy)
                                    if step and Cost(s,nx,ny) then step=Step(s,nx,ny,cx,cy,step,current==start) else step=nil end
                                else
                                    step=Cost(s,nx,ny)
                                    if step then step=Step(s,cx,cy,nx,ny,step,index==goal or (goals and goals[index])) end
                                end
                                -- No corner cutting past blocked cells.
                                if step and dx~=0 and dy~=0 and (not Cost(s,cx+dx,cy) or not Cost(s,cx,cy+dy)) then step=nil end
                                if step then
                                    local ng=g+step*CELL*((dx~=0 and dy~=0) and SQRT2 or 1)
                                    local old=cost[index]
                                    if not old or ng<old then
                                        cost[index]=ng;from[index]=current
                                        n=heapPush(keys,vals,n,ng+h(nx,ny),index)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            for _,link in ipairs(links and links[current] or {}) do
                local index=link[1]
                local ng=g+link[2]
                if not closed[index] and (not cost[index] or ng<cost[index])
                    and (not inside or inside[math.floor((index%cols)/CF)+math.floor(math.floor(index/cols)/CF)*CC]) then
                    cost[index]=ng;from[index]=current
                    n=heapPush(keys,vals,n,ng+h(index%cols,math.floor(index/cols)),index)
                end
            end
        end
    end
    return cost,from,true,not ended
end
-- Every cell you can walk to from start (reverse: that can walk to start),
-- without costs: a flood over the walkable steps and transitions, within
-- box {x0,y0,x1,y1} (cells) when given. Returns {[cell]=true}.
function R.Flood(s,start,reverse,box)
    local cols,rows=s.cols,s.rows
    local x0,y0,x1,y1=0,0,cols-1,rows-1
    if box then x0,y0,x1,y1=math.max(0,box[1]),math.max(0,box[2]),math.min(cols-1,box[3]),math.min(rows-1,box[4]) end
    local Cost,Step,links=R.Cost,R.Step,reverse and s.back or s.links
    local seen,queue,head={[start]=true},{start},1
    while head<=#queue do
        local current=queue[head];head=head+1
        if head%2000==0 and coroutine.running() then coroutine.yield() end
        local cx,cy=current%cols,math.floor(current/cols)
        for dy=-1,1 do
            local ny=cy+dy
            if ny>=y0 and ny<=y1 then
                for dx=-1,1 do
                    local nx=cx+dx
                    local index=ny*cols+nx
                    if (dx~=0 or dy~=0) and nx>=x0 and nx<=x1 and not seen[index] then
                        local step
                        if reverse then
                            step=Cost(s,cx,cy)
                            if step and Cost(s,nx,ny) then step=Step(s,nx,ny,cx,cy,step,false) else step=nil end
                        else
                            step=Cost(s,nx,ny)
                            if step then step=Step(s,cx,cy,nx,ny,step,false) end
                        end
                        if step and dx~=0 and dy~=0 and (not Cost(s,cx+dx,cy) or not Cost(s,cx,cy+dy)) then step=nil end
                        if step then seen[index]=true;queue[#queue+1]=index end
                    end
                end
            end
        end
        for _,link in ipairs(links and links[current] or {}) do
            local index=link[1]
            if not seen[index] then seen[index]=true;queue[#queue+1]=index end
        end
    end
    return seen
end
-- weight > 1 (navigation): the estimate counts more, the search heads for
-- the goal and looks at far fewer cells; the way may be a little longer
-- than the shortest. Routes keep 1 (the shortest way between stops).
R.NEARWEIGHT=2
-- project: the goal is a place to get to, not a fixed end (a transition's):
-- on a blocked cell the way ends in the free cell it was moved to, not on
-- the blocked spot (Florian/Codex 2026-10-14: Stormwind's Jarel Moor, the
-- last piece ran onto no-go where the data has no floor).
-- Long ways on the ground (Florian 2026-10-15: a 1500-yard leg through Dun
-- Morogh's mountains looked at 100,000 cells, 27 s in the game): first a
-- coarse way on cells of about COARSEYARDS (each judged by a few of its
-- own cells, transitions kept), then the fine search only in a corridor of
-- CORRIDOR coarse cells round it. Not found there (a cliff the coarse way
-- missed): the whole search as before; nothing the corridor left out is
-- taken as apart. The way may differ a little from the shortest of all.
R.COARSEYARDS=32
R.COARSEMIN=400
R.CORRIDOR=4   -- coarse cells round the coarse way; a second try twice as wide
R.COARSELIMIT=40000
R.COARSEROUNDS=8    -- coarse ways tried round where the fine search got stuck
R.COARSEBLOCK=2     -- coarse cells of the way ahead of where it got stuck,
R.COARSEBLOCKR=3    -- each left out with this many round it
local COARSESAMPLES={{.5,.5},{.25,.25},{.75,.25},{.25,.75},{.75,.75}}
-- blocked: coarse cells left out (a round before stuck there, R.Search).
-- Returns the corridor {cells, F, ccols, path (coarse cells, start first)}.
function R.Coarse(s,start,goal,weight,width,blocked)
    local cols,rows,cell=s.cols,s.rows,s.cell or R.CELL
    local c=s.coarse
    if not c then
        local F=math.max(2,math.floor(R.COARSEYARDS/cell+.5))
        c={F=F,ccols=math.ceil(cols/F),crows=math.ceil(rows/F),cost={}}
        -- Transitions between coarse cells.
        c.links={}
        for from,list in pairs(s.links or {}) do
            local a=math.floor((from%cols)/F)+math.floor(math.floor(from/cols)/F)*c.ccols
            for _,l in ipairs(list) do
                local b=math.floor((l[1]%cols)/F)+math.floor(math.floor(l[1]/cols)/F)*c.ccols
                if a~=b then c.links[a]=c.links[a] or {};c.links[a][#c.links[a]+1]={b,l[2]} end
            end
        end
        s.coarse=c
    end
    local F,ccols,crows,memo=c.F,c.ccols,c.crows,c.cost
    local function cid(i) return math.floor((i%cols)/F)+math.floor(math.floor(i/cols)/F)*ccols end
    local sid,gid=cid(start),cid(goal)
    -- A coarse cell: the cheapest of its samples (nil: none walkable).
    local function ccost(id)
        if id==sid or id==gid then return 1 end
        if blocked and blocked[id] then return nil end
        local v=memo[id]
        if v~=nil then return v or nil end
        local bx,by=(id%ccols)*F,math.floor(id/ccols)*F
        local best
        for _,o in ipairs(COARSESAMPLES) do
            local x,y=bx+math.floor(F*o[1]),by+math.floor(F*o[2])
            if x<cols and y<rows then
                local v2=R.Cost(s,x,y)
                if v2 and (not best or v2<best) then best=v2 end
            end
        end
        memo[id]=best or false
        return best
    end
    local yards=F*cell
    local gx,gy=gid%ccols,math.floor(gid/ccols)
    local function h(x,y)
        local dx,dy=math.abs(x-gx),math.abs(y-gy)
        return (math.max(dx,dy)+(SQRT2-1)*math.min(dx,dy))*yards*math.min(.5,R.RoadCost(s),R.WalkedCost(s))*(weight or 1)
    end
    local keys,vals,n={},{},0
    local g,from,closed={[sid]=0},{},{}
    n=heapPush(keys,vals,n,h(sid%ccols,math.floor(sid/ccols)),sid)
    local steps=0
    while n>0 do
        local _,cur
        _,cur,n=heapPop(keys,vals,n)
        if not closed[cur] then
            closed[cur]=true
            if cur==gid then break end
            steps=steps+1
            if steps>R.COARSELIMIT then return nil end
            if steps%400==0 and coroutine.running() then coroutine.yield() end
            local cx,cy=cur%ccols,math.floor(cur/ccols)
            local here=ccost(cur) or 1
            for dy=-1,1 do
                local ny=cy+dy
                if ny>=0 and ny<crows then
                    for dx=-1,1 do
                        local nx=cx+dx
                        if (dx~=0 or dy~=0) and nx>=0 and nx<ccols then
                            local id=ny*ccols+nx
                            local there=not closed[id] and ccost(id)
                            if there then
                                local ng=g[cur]+(here+there)/2*yards*((dx~=0 and dy~=0) and SQRT2 or 1)
                                if not g[id] or ng<g[id] then g[id]=ng;from[id]=cur;n=heapPush(keys,vals,n,ng+h(nx,ny),id) end
                            end
                        end
                    end
                end
            end
            for _,l in ipairs(c.links[cur] or {}) do
                local id=l[1]
                local ng=g[cur]+l[2]
                if not closed[id] and (not g[id] or ng<g[id]) then g[id]=ng;from[id]=cur;n=heapPush(keys,vals,n,ng+h(id%ccols,math.floor(id/ccols)),id) end
            end
        end
    end
    if not from[gid] and sid~=gid then return nil end
    -- The corridor: the coarse way and CORRIDOR coarse cells round it.
    local cells,path={},{}
    local id=gid
    while id do
        table.insert(path,1,id)
        local cx,cy=id%ccols,math.floor(id/ccols)
        local w=width or R.CORRIDOR
        for dy=-w,w do for dx=-w,w do
            local x,y=cx+dx,cy+dy
            if x>=0 and y>=0 and x<ccols and y<crows then cells[y*ccols+x]=true end
        end end
        id=from[id]
    end
    return {cells=cells,F=F,ccols=ccols,path=path}
end
-- After an optimistic coarse corridor failed, keep a concrete entry cell
-- for each search node. Flood only its small block before choosing an exit.
-- Entry points and local floods live for this search only: no component cache.
-- This is still only a corridor hint. The normal weighted fine search must
-- validate it; a failed hint never proves that a route is impossible.
function R.CoarseFromEntry(s,start,goal,weight,width,blocked,work)
 -- Read existing terrain memo entries, but keep probe-only values in
 -- block-local scratch tables. Discard them before the next block; failed
 -- hints must not grow the navigation space's retained terrain caches.
 local base=s;s=setmetatable({},{__index=base})
 local scratch={"costs","ground","steep","elevation","walls","falls","cityWalked","highZones"}
 local cols,rows=s.cols,s.rows;local F=8;local CC=math.ceil(cols/F);local CR=math.ceil(rows/F);local cell=s.cell or R.CELL
 local function tile(i)return math.floor((i%cols)/F)+math.floor(math.floor(i/cols)/F)*CC end
 local sid,gid=tile(start),tile(goal);local floor=math.min(.5,R.RoadCost(s),R.WalkedCost(s))
 local function heuristic(i)
  local dx,dy=math.abs(i%cols-goal%cols),math.abs(math.floor(i/cols)-math.floor(goal/cols))
  return(math.max(dx,dy)+(SQRT2-1)*math.min(dx,dy))*cell*floor*4
 end
 local keys,vals,n={},{},0;local g,from,entry,closed={[sid]=0},{},{[sid]=start},{}
 n=heapPush(keys,vals,n,heuristic(start),sid);local count=0;local sinceYield=0;local found
 while n>0 do
  local current,unused;unused,current,n=heapPop(keys,vals,n)
  if not closed[current]then
   count=count+1;if count>R.COARSELIMIT then return nil end
   closed[current]=true
   for _,key in ipairs(scratch)do
    local original=base[key]
    if original then s[key]=setmetatable({},{__index=original})
    elseif key=="falls" then s[key]={} end
   end
   local origin=entry[current]
   if work.left<F*F then return nil end
   local reachable=R.Explore(s,origin,nil,nil,F*F,nil,nil,0,{F=F,ccols=CC,cells={[current]=true}})
   for _ in pairs(reachable)do work.left=work.left-1;sinceYield=sinceYield+1 end
   if sinceYield>=400 then sinceYield=0;if coroutine.running()then coroutine.yield()end end
   if reachable[goal]then found=current;break end
   local function offer(a,b,cost)
    local next=tile(b)
    if next~=current and not closed[next]and(next==sid or next==gid or not(blocked and blocked[next]))then
     local dx,dy=a%cols-origin%cols,math.floor(a/cols)-math.floor(origin/cols)
     local ng=g[current]+math.sqrt(dx*dx+dy*dy)*cell*floor+cost
     if not g[next]or ng<g[next]then g[next]=ng;from[next]=current;entry[next]=b;n=heapPush(keys,vals,n,ng+heuristic(b),next)end
    end
   end
   for a in pairs(reachable)do
    local ax,ay=a%cols,math.floor(a/cols)
    for dy=-1,1 do for dx=-1,1 do
     local bx,by=ax+dx,ay+dy;local b=by*cols+bx
     if(dx~=0 or dy~=0)and bx>=0 and by>=0 and bx<cols and by<rows and tile(b)~=current and not closed[tile(b)]then
      local cost=R.Cost(s,bx,by)
      if cost then cost=R.Step(s,ax,ay,bx,by,cost,b==goal)end
      if cost and dx~=0 and dy~=0 and(not R.Cost(s,ax,by)or not R.Cost(s,bx,ay))then cost=nil end
      if cost then offer(a,b,cell*floor*((dx~=0 and dy~=0)and SQRT2 or 1))end
     end
    end end
    for _,link in ipairs(s.links and s.links[a]or{})do offer(a,link[1],link[2])end
   end
  end
 end
 if not found then return nil end
 local path,cells={},{};local at=found
 while at do table.insert(path,1,at);at=from[at]end
 for _,id in ipairs(path)do local x,y=id%CC,math.floor(id/CC)
  for dy=-2,2 do for dx=-2,2 do local nx,ny=x+dx,y+dy;if nx>=0 and ny>=0 and nx<CC and ny<CR then cells[ny*CC+nx]=true end end end
 end
 return{F=F,ccols=CC,cells=cells,path=path}
end

-- coarse: long ways on the ground through R.Coarse's corridor (Navigate's).
function R.Search(s,x1,y1,x2,y2,limit,weight,project,coarse)
    -- Keeping off walls needs a search that weighs the costs (Florian
    -- 2026-10-13: at weight 4 the line still ran along a no-go edge; on his
    -- ring 13 % of the line near an edge, 3 % at weight 2, 7 % more time).
    if s.near and weight and weight>R.NEARWEIGHT then weight=R.NEARWEIGHT end
    -- Start and goal on a blocked cell (a transition's end beside a wall):
    -- the nearest walkable one.
    local sx,sy=R.Snap(s,R.Cell(s,x1,y1))
    local gx,gy=R.Cell(s,x2,y2)
    local tx,ty=R.Snap(s,gx,gy)
    -- Why there is no way (Codex/Florian 2026-10-16, kept apart all the way
    -- to the log): "nopath" proven, "limit" not decided within the search's
    -- limit, "unknown" the data cannot tell (start or goal on no walkable cell).
    if not (sx and tx) then return nil,"unknown","off" end
    if project and (tx~=gx or ty~=gy) then x2,y2=R.Center(s,tx,ty) end
    local cols=s.cols
    local start,goal=sy*cols+sx,ty*cols+tx
    if R.Apart(s,start,goal) then return nil,"nopath","apart" end
    -- A short way first (Claude 2026-10-14: the check below cost three
    -- to four times the search itself in Undercity and Darnassus, whose legs
    -- are mostly short): searched to its end within PRECHECK cells, it is
    -- the same as the whole search would find.
    limit=limit or 60000
    local cost,from,ok,all=R.Explore(s,start,goal,nil,math.min(limit,R.PRECHECK),nil,nil,weight)
    -- Long, on the ground: the corridor of a coarse way first (R.Coarse).
    if coarse and not ok and limit>R.PRECHECK and not s.level and R.Yards(s,x1,y1,x2,y2)>=R.COARSEMIN then
        -- Stuck in the corridor (a cliff, a wall, a river the coarse way did
        -- not see; Florian 2026-10-15): where the search came nearest the
        -- goal, the next coarse cells of the way are left out and a coarse
        -- way round them is tried, COARSEROUNDS times.
        local blocked={}
        local gx,gy=goal%cols,math.floor(goal/cols)
        -- Spend the remaining coarse-round allowance on fine-cell visits,
        -- shared across all entry attempts, rather than multiplying it per block.
        local entryWork={left=R.COARSELIMIT*math.max(0,R.COARSEROUNDS-1)}
        for attempt=1,R.COARSEROUNDS do
            -- The first attempt keeps the existing route selection unchanged.
            -- Entry blocks have their own indexing; do not carry 32-yard
            -- exclusions into their 64-yard search.
            if attempt==2 then blocked={} end
            local corridor
            if attempt==1 then corridor=R.Coarse(s,start,goal,weight,R.CORRIDOR,blocked)
            else corridor=R.CoarseFromEntry(s,start,goal,weight,R.CORRIDOR,blocked,entryWork) end
            if corridor then
            local ccost,cfrom,cok=R.Explore(s,start,goal,nil,limit,nil,nil,weight,corridor)
            if cok and cfrom[goal] then return R.Trace(s,cfrom,start,goal,x1,y1,x2,y2) end
            if not cok then break end
            local near,nearD
            for i in pairs(ccost) do
                local dx,dy=i%cols-gx,math.floor(i/cols)-gy
                local d=dx*dx+dy*dy
                if not nearD or d<nearD then near,nearD=i,d end
            end
            if not near then break end
            local F,CC=corridor.F,corridor.ccols
            local at=math.floor((near%cols)/F)+math.floor(math.floor(near/cols)/F)*CC
            -- Its place on the coarse way (the nearest coarse cell of it).
            local k,kd
            for j,id in ipairs(corridor.path) do
                local dx,dy=id%CC-at%CC,math.floor(id/CC)-math.floor(at/CC)
                local d=dx*dx+dy*dy
                if not kd or d<kd then k,kd=j,d end
            end
            -- A block round it, so the next coarse way runs clearly apart.
            local any=false
            for j=k+1,math.min(#corridor.path-1,k+R.COARSEBLOCK) do
                local id=corridor.path[j]
                local bx,by=id%CC,math.floor(id/CC)
                for dy=-R.COARSEBLOCKR,R.COARSEBLOCKR do for dx=-R.COARSEBLOCKR,R.COARSEBLOCKR do
                    local x,y=bx+dx,by+dy
                    if x>=0 and y>=0 and x<CC then blocked[y*CC+x]=true;any=true end
                end end
            end
            if not any then break end
            elseif attempt>1 then break end
        end
    end
    if not ok and limit>R.PRECHECK then
        -- Then the other way round from the goal, briefly: a goal on a
        -- plateau or in a closed hollow nobody gets into shows at once,
        -- without searching the whole map (Florian 2026-10-09: calculating
        -- took long).
        local reached,_,done,exhausted=R.Explore(s,goal,start,nil,R.PRECHECK,nil,true)
        if done and exhausted and not reached[start] then return nil,"nopath","enclosed" end
        cost,from,ok,all=R.Explore(s,start,goal,nil,limit,nil,nil,weight)
    end
    -- Given up at the limit: said so (why not, not searched again). Once
    -- back from the goal, up to BACKLIMIT cells (Florian 2026-10-14: a
    -- trainer in a cellar no data has; every gate of Stormwind searched
    -- LIMIT cells to it): all that leads there, when that ends, is kept
    -- and the next search to it fails at once.
    if not ok then
        -- (Once a goal: a smaller limit after failures lost true ways,
        -- Codex 2026-10-14; only what is proven apart is kept.)
        s.backTried=s.backTried or {}
        if not s.backTried[goal] then
            s.backTried[goal]=true
            local back,_,done,exhausted=R.Explore(s,goal,start,nil,R.BACKLIMIT,nil,true)
            if done and exhausted and not back[start] then R.KeepApart(s,back,goal,true);return nil,"nopath","apart" end
        end
        return nil,"limit"
    end
    -- Searched to the end without the goal: what start reaches is kept.
    if all and not from[goal] and start~=goal then R.KeepApart(s,cost,goal);return nil,"nopath","searched" end
    return R.Trace(s,from,start,goal,x1,y1,x2,y2)
end
-- Parts that do not meet (Florian/Codex 2026-10-14: Rut'theran Village
-- and Darnassus without the portal; every leg between them searched all of
-- Teldrassil again, 200,000 cells, 4 to 19 s): a search that ran to the end
-- without its goal leaves all it reached; nothing in there reaches further
-- (links and drops included). A later search from in there to a goal
-- outside fails at once: the same goal surely; another goal only when no
-- cell beside it lies in there (the step into a goal may climb a little,
-- R.Step). Kept with the space, at most KEEPAPART of them.
R.KEEPAPART=6
-- reverse: the cells that can walk to goal, all of them (a search back
-- from the goal that ran to its end): from anywhere else no way to that
-- same goal.
function R.KeepApart(s,reached,goal,reverse)
    s.apart=s.apart or {}
    local list=s.apart
    list[#list+1]={cells=reached,goal=goal,reverse=reverse}
    while #list>R.KEEPAPART do table.remove(list,1) end
end
function R.Apart(s,start,goal)
    local cols=s.cols
    for _,part in ipairs(s.apart or {}) do
        local cells=part.cells
        if part.reverse then
            if part.goal==goal and not cells[start] then return true end
        elseif cells[start] and not cells[goal] then
            if part.goal==goal then return true end
            local beside=false
            local gx,gy=goal%cols,math.floor(goal/cols)
            for dy=-1,1 do for dx=-1,1 do
                if (dx~=0 or dy~=0) and cells[(gy+dy)*cols+gx+dx] then beside=true end
            end end
            if not beside then return true end
        end
    end
    return false
end
-- The way back from goal to start through from, pulled tight.
-- Corners rounded off (Florian 2026-10-12: the way up a corkscrew ramp, a
-- flight tower's, came out a polygon): each corner turning more than
-- ROUNDTURN is cut ROUND of the way to its neighbours (at most ROUNDCUT
-- yards), twice over; only where the cut is clear (ok). The ends and points
-- marked fixed (a transition's ends) stay where they are.
R.ROUND=.25
R.ROUNDCUT=4
R.ROUNDTURN=math.rad(12)
function R.Round(points,yards,ok)
    for _=1,2 do
        if #points<3 then return points end
        local out={points[1]}
        for i=2,#points-1 do
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

-- A straight line may cost this much more than the cells it replaces
-- (rounding of the samples), in cost-yards.
R.PULLSLACK=1
function R.Trace(s,from,start,goal,x1,y1,x2,y2)
    local cols=s.cols
    if not from[goal] and start~=goal then return nil end
    -- Cells back to the start, then pulled tight: a point is kept only where
    -- the line from the last kept one stops being clear, or would cost more
    -- than the cells it replaces (Florian 2026-10-16: the line pulled tight
    -- left the road the search had taken, and waded beside a bridge; open
    -- ground and shallow water count as clear).
    local cells={}
    local index=goal
    while index do table.insert(cells,1,index);index=from[index] end
    local points={{x1,y1}}
    local anchor={x1,y1}
    local previous
    -- The cost of the cells walked so far (per yard, from cell to cell).
    local walked,anchorCost,previousCost=0,0,0
    local lastX,lastY=x1,y1
    for i=2,#cells do
        local cx,cy=cells[i]%cols,math.floor(cells[i]/cols)
        local px,py=R.Center(s,cx,cy)
        walked=walked+(R.Cost(s,cx,cy) or R.CLEAR)*R.Yards(s,lastX,lastY,px,py)
        lastX,lastY=px,py
        local link=s.linked and s.linked[cells[i-1]..">"..cells[i]]
        if link then
            -- Through a transition or a given way: both of its ends stay on
            -- the way, where they were set.
            local start=type(link)=="table" and {link[1],link[2]} or previous
            if start and (start[1]~=anchor[1] or start[2]~=anchor[2]) then points[#points+1]={start[1],start[2],fixed=true} end
            -- Its shape between the ends (without the first and last point, the ends themselves).
            if type(link)=="table" and link.shape then
                for j=2,#link.shape-1 do points[#points+1]={link.shape[j][1],link.shape[j][2],fixed=true} end
            end
            if type(link)=="table" then px,py=link[3],link[4];lastX,lastY=px,py end
            points[#points+1]={px,py,link=true,fixed=true};anchor={px,py};anchorCost=walked
        elseif previous then
            local clear,cost=R.Clear(s,anchor[1],anchor[2],px,py)
            -- On terrain also walkable step by step in this direction (Codex
            -- 2026-10-16: two clear lines crossed a step the search refuses).
            if clear and s.terrain and cost<=walked-anchorCost+R.PULLSLACK and not R.Walkable(s,anchor[1],anchor[2],px,py) then clear=false end
            if not clear or cost>walked-anchorCost+R.PULLSLACK then
                points[#points+1]=previous;anchor=previous;anchorCost=previousCost
            end
        end
        previous={px,py};previousCost=walked
    end
    -- The exact goal after the last cell: straight from the last kept point
    -- only where that is walkable, else by the last cell's middle (Codex
    -- 2026-10-16: before the Great Lift the appended goal cut a slope).
    -- Only on terrain, and only when the way by the last cell is walkable
    -- where the straight one is not (Codex 2026-10-16: on city levels the
    -- middle was added unproven and 49 of 52 reference ways changed).
    local last=points[#points]
    if s.terrain and previous and last and not last.fixed and (previous[1]~=anchor[1] or previous[2]~=anchor[2])
        and not R.Walkable(s,anchor[1],anchor[2],x2,y2)
        and R.Walkable(s,anchor[1],anchor[2],previous[1],previous[2]) and R.Walkable(s,previous[1],previous[2],x2,y2) then
        points[#points+1]=previous
    end
    points[#points+1]={x2,y2}
    local round=R.Round(points,function(ax,ay,bx,by) return R.Yards(s,ax,ay,bx,by) end,function(q,r) return R.Clear(s,q[1],q[2],r[1],r[2]) and (not s.terrain or R.Walkable(s,q[1],q[2],r[1],r[2])) end)
    -- The rounded way checked as a whole (Codex 2026-10-16: in Silverpine a
    -- rounded piece crossed a steep cell neither Clear nor Walkable allow):
    -- more pieces you cannot walk, or more that are not clear, than the way
    -- before rounding: that one. Not walkable is never traded for clear.
    local hardR,softR=R.Unclear(s,round)
    local hardP,softP=R.Unclear(s,points)
    if hardR>hardP or hardR+softR>hardP+softP then return points end
    return round
end
-- Pieces of a way that cannot be walked (Walkable refuses them), and those
-- whose straight line is only not clear (both ends of a transition or given
-- way left out: they cross by design).
function R.Unclear(s,points)
    local hard,soft=0,0
    for i=2,#points do
        local a,b=points[i-1],points[i]
        if not (a.fixed and b.fixed) then
            if s.terrain and not R.Walkable(s,a[1],a[2],b[1],b[2]) then hard=hard+1
            elseif not R.Clear(s,a[1],a[2],b[1],b[2]) then soft=soft+1 end
        end
    end
    return hard,soft
end

-- Runs a function as a coroutine in slices (a few milliseconds per frame).
-- label: what runs, beside the mouse pointer meanwhile (Routing.Busy,
-- Florian 2026-10-14; else R.nextLabel, set just before the call); it goes
-- when the run ends or is cancelled.
R.BUDGET=8
R.PRECHECK=3000
R.BACKLIMIT=60000
-- Returns its handle: handle:Cancel() stops it. Not the ticker itself:
-- the game's tickers are read-only (Florian 2026-10-14: "Attempted to
-- assign to read-only key Cancel").
-- Where a coroutine stands (file:line, innermost first; Claude 2026-10-20: in
-- game one piece ran 211 ms that never did offline, the log says where).
function R.Where(c)
    if not c then return nil end
    -- The game has no debug.getinfo: its debugstack(thread, start, count1, count2).
    local stack=rawget(_G,"debugstack")
    if stack then
        local ok,text=pcall(stack,c,0,6,0)
        if not ok or type(text)~="string" then return nil end
        local out={}
        for file,line in text:gmatch("([%w_]+)%.lua\"?%]?:(%d+)") do
            if #out<4 then out[#out+1]=file..":"..line end
        end
        return #out>0 and table.concat(out,"<") or nil
    end
    local getinfo=debug and debug.getinfo
    if not getinfo then return nil end
    local out={}
    for level=0,8 do
        local ok,info=pcall(getinfo,c,level,"Sl")
        if not ok or not info then break end
        if info.what~="C" and #out<4 then
            local file=tostring(info.short_src or "?"):match("([%w_]+)%.lua") or "?"
            out[#out+1]=file..":"..tostring(info.currentline or 0)
        end
    end
    return #out>0 and table.concat(out,"<") or nil
end
function R.Run(fn,done,label)
    local co=coroutine.create(fn)
    local ticker
    local handle={}
    local busy=Routing.Busy
    local function stop()
        if ticker then ticker:Cancel() end
        if busy then busy:Stop(handle) end
    end
    function handle:Cancel() stop() end
    -- Several slices per frame while they take less than R.BUDGET ms (the
    -- real ways of a large route are many searches; one slice per frame
    -- made it slow), so the game keeps its frame rate.
    local clock=rawget(_G,"debugprofilestop")
    -- What it cost (Florian 2026-10-14: the log tells it): milliseconds of
    -- its own work, frames it ran in.
    handle.cpu,handle.frames,handle.longest=0,0,0
    local function step()
        -- The frame's share (Routing:FrameBudget, the setting); nothing while you fight.
        local budget=Routing.FrameBudget and Routing:FrameBudget(R.BUDGET) or R.BUDGET
        if budget<=0 then handle.paused=(handle.paused or 0)+1;return end
        R.sliceLimit=math.min(R.SLICE,budget)
        local began=clock and clock()
        handle.frames=handle.frames+1
        repeat
            local t=clock and clock()
            R.sliceBegan=t
            local kb=collectgarbage and collectgarbage("count")
            local ok,result=coroutine.resume(co)
            if clock then
                local d=clock()-t;handle.cpu=handle.cpu+d
                local at=R.Where(R.inner or co)
                if d>handle.longest then
                    handle.longest,handle.longestFrom,handle.longestTo=d,handle.at,at
                    handle.longestKB=kb and collectgarbage("count")-kb
                end
                handle.at=at
            end
            if not ok then stop();Routing:Print("Way failed: "..tostring(result));if done then done(nil) end;return end
            if coroutine.status(co)=="dead" then stop();if done then done(result) end;return end
        until not clock or clock()-began>=budget
    end
    -- label false: quiet, nothing beside the pointer (work in the background).
    if busy and label~=false then busy:Start(handle,label or R.nextLabel) end
    R.nextLabel=nil
    ticker=C_Timer.NewTicker(.01,step)
    return handle
end

-- Given ways (Route Studio, Florian 2026-10-10: where walls and
-- transitions alone do not lead the way well, a way is set by hand): a line
-- of points on a map and level, one way only if marked. The search follows
-- it exactly from point to point (each piece a link, so it also passes
-- where a wall stands) at WAYCOST of its length. Its points are walkable
-- (onway: entered and left there, also on no-go). The cells between its
-- points are only cheaper where they are walkable anyway (waycheap):
-- Florian 2026-10-13, a way's cells made walkable let the line pulled
-- tight leave the way across unpainted ground and no-go beside it ("what
-- do we define ways for?"). On a level of ways only its cells stay the
-- streets (onway), as there nothing else is walkable.
R.WAYCOST=.3
-- On a level of given ways only, a step from cell to cell only where a way
-- runs from the one to the other (Codex 2026-10-16, Freewind's west spiral:
-- two way cells merely side by side were stepped across, the curve cut).
function R.WayStep(s,a,b)
    return not (s.waysOnly and s.wayAdj) or s.wayAdj[a..">"..b]==true
end
function R.Ways(s,ways)
    s.onway,s.waycheap={},{}
    s.wayAdj=s.waysOnly and {} or nil
    s.links,s.linked,s.back=s.links or {},s.linked or {},s.back or {}
    for _,zone in ipairs(s.zones) do
        for _,way in ipairs(type(ways)=="table" and ways[zone] or {}) do
            if (way.level or 0)==(s.level or 0) and type(way.points)=="table" then
                local points={}
                for i=1,#way.points-1,2 do
                    local x,y=R.ToSpace(s,zone,way.points[i],way.points[i+1])
                    if x then points[#points+1]={x,y} end
                end
                if #points>=2 then s.hasWays=true end
                -- Links from cell to cell along the way: from the first point
                -- of a run in one cell to the first point in another, with
                -- every point between as its shape (Codex 2026-10-16, Freewind
                -- Post: dense points in one cell kept only one piece, the
                -- spiral was cut short).
                local from=1
                for i=2,#points do
                    local ax,ay,bx,by=points[i-1][1],points[i-1][2],points[i][1],points[i][2]
                    local acx,acy=R.Cell(s,ax,ay)
                    local bcx,bcy=R.Cell(s,bx,by)
                    local fx,fy=points[from][1],points[from][2]
                    local fcx,fcy=R.Cell(s,fx,fy)
                    if not fcx then from=i
                    elseif bcx and (bcx~=fcx or bcy~=fcy) then
                        local a,b=fcy*s.cols+fcx,bcy*s.cols+bcx
                        local shape,yards={},0
                        for k=from,i do
                            shape[#shape+1]=points[k]
                            if k>from then yards=yards+R.Yards(s,points[k-1][1],points[k-1][2],points[k][1],points[k][2]) end
                        end
                        yards=yards*R.WAYCOST
                        local back
                        if #shape>2 then back={};for k=#shape,1,-1 do back[#back+1]=shape[k] end else shape=nil end
                        s.links[a]=s.links[a] or {};table.insert(s.links[a],{b,yards});s.linked[a..">"..b]={fx,fy,bx,by,shape=shape}
                        s.back[b]=s.back[b] or {};table.insert(s.back[b],{a,yards})
                        if not way.oneway then
                            s.links[b]=s.links[b] or {};table.insert(s.links[b],{a,yards});s.linked[b..">"..a]={bx,by,fx,fy,shape=back}
                            s.back[a]=s.back[a] or {};table.insert(s.back[a],{b,yards})
                        end
                        from=i
                    end
                    -- A one-way way only by its links (its cells would lead
                    -- back); its two ends stay walkable, so it can be
                    -- entered and left on a level too.
                    if way.oneway then
                        if acx and i==2 then s.onway[acy*s.cols+acx]=true end
                        if bcx and i==#points then s.onway[bcy*s.cols+bcx]=true end
                    else
                        if acx then s.onway[acy*s.cols+acx]=true end
                        if bcx then s.onway[bcy*s.cols+bcx]=true end
                        local n=math.max(1,math.ceil(R.Yards(s,ax,ay,bx,by)/((s.cell or R.CELL)/2)))
                        local last
                        for j=0,n do
                            local cx,cy=R.Cell(s,ax+(bx-ax)*j/n,ay+(by-ay)*j/n)
                            if cx then
                                local here=cy*s.cols+cx
                                if j>0 and j<n then
                                    if s.waysOnly then s.onway[here]=true else s.waycheap[here]=true end
                                end
                                -- The cells the way runs through, one after another.
                                if s.wayAdj and last and last~=here then s.wayAdj[last..">"..here]=true;s.wayAdj[here..">"..last]=true end
                                last=here
                            end
                        end
                    end
                end
            end
        end
    end
end
-- Everything Routing's store knows for a space: painted areas, walls,
-- transitions and given ways of its level (on the ground: also enemy bases).
-- Road Studio's roads (Data/Roads.lua, BVRoutingRoads: per continent
-- polylines in its 0..1 coordinates with their width in yards) as cells of
-- the ground's space: cheaper there (R.Ground), nothing else.
-- The last spaces' road cells, by the data and the space's grid (Claude 2026-10-20:
-- each new way painted a continent's roads again, 300 ms and 8 MB in game).
R.roadCache={}
R.ROADCACHE=2
function R.Roads(s)
    s.roads=nil
    if (s.level or 0)~=0 then return end
    local data=rawget(_G,"BVRoutingRoads")
    local list=type(data)=="table" and type(data.cont)=="table" and data.cont[s.mapID]
    if type(list)~="table" then return end
    local cell,cols,rows=s.cell or R.CELL,s.cols,s.rows
    local id=table.concat({tostring(list),s.mapID,cell,cols,rows,s.minX,s.minY,s.maxX,s.maxY},":")
    for _,c in ipairs(R.roadCache) do if c.id==id then s.roads=c.roads;return end end
    local roads,count={},0
    for _,road in ipairs(list) do
        local p=type(road)=="table" and road.p
        if type(p)=="table" then
            -- Only the width the data shows (Codex 2026-10-16: no width given is
            -- the centre line's cells alone, not a band around it).
            local rc=math.floor(math.max(0,(tonumber(road.w) or 0)/2)/cell)
            for i=1,#p-3,2 do
                -- Given back by time, counted over all roads (many are short).
                count=count+1;if count%8==0 then R.Breathe() end
                local ax,ay,bx,by=p[i],p[i+1],p[i+2],p[i+3]
                local n=math.max(1,math.ceil(R.Yards(s,ax,ay,bx,by)/(cell/2)))
                for j=0,n do
                    local cx,cy=R.Cell(s,ax+(bx-ax)*j/n,ay+(by-ay)*j/n)
                    if cx then
                        for dy=-rc,rc do for dx=-rc,rc do
                            local x,y=cx+dx,cy+dy
                            if x>=0 and y>=0 and x<cols and y<rows then roads[y*cols+x]=true end
                        end end
                    end
                end
            end
        end
    end
    table.insert(R.roadCache,1,{id=id,roads=roads})
    while #R.roadCache>R.ROADCACHE do table.remove(R.roadCache) end
    s.roads=roads
end
-- Is a cell in a zone above your level? Asked per block of ZONEBLOCK cells.
function R.HighZone(s,cx,cy)
    local B=R.ZONEBLOCK
    local key=math.floor(cy/B)*1e5+math.floor(cx/B)
    local known=s.highZones[key]
    if known==nil then
        local x,y=R.Center(s,math.floor(cx/B)*B+math.floor(B/2),math.floor(cy/B)*B+math.floor(B/2))
        local zone=Routing.ZoneAt and Routing:ZoneAt(s.mapID,x,y)
        known=(zone and Routing:ZoneAbove(zone,s.playerLevel)) and true or false
        s.highZones[key]=known
    end
    return known
end
-- What preparing spaces cost, per part (ms of time between its start and end,
-- KB the memory grew; Claude 2026-10-20: the first way in game ran one piece of
-- 200 ms there that never did offline). Navigate's cost line says it.
R.prepCost={}
local function timed(name,fn,...)
    local clock=rawget(_G,"debugprofilestop")
    local t=clock and clock()
    local kb=collectgarbage and collectgarbage("count")
    fn(...)
    local c=R.prepCost[name] or {0,0,0};R.prepCost[name]=c
    c[1]=c[1]+(t and clock()-t or 0);c[2]=c[2]+(kb and collectgarbage("count")-kb or 0);c[3]=c[3]+1
end
function R.PrepCostText()
    local out={}
    for _,name in ipairs({"level","roads","data","paint","walls","ways","joinends","links","clearance"}) do
        local c=R.prepCost[name]
        if c then out[#out+1]=string.format("%s %.0f ms %+.0f KB",name,c[1],c[2]) end
    end
    return #out>0 and table.concat(out,", ") or nil
end
function R.Prepare(s)
    local level
    timed("level",function() level=s.level and Routing.Level and Routing.Level:Find(s.level) end)
    timed("roads",R.Roads,s)
    -- Zones above your level avoided (Routing's setting): their blocks known as asked.
    if (s.level or 0)==0 and Routing:ZoneMode()=="avoid" then s.highZones={};s.playerLevel=UnitLevel and UnitLevel("player") or nil else s.highZones=nil end
    s.waysOnly=type(level)=="table" and level.waysOnly==true or nil
    s.open=type(level)=="table" and level.open==true or nil
    -- Your store with the shipped maps (Routing:Data).
    local data
    timed("data",function() data=Routing:Data() end)
    s.data=data
    timed("paint",R.Paint,s,data.areas)
    timed("walls",R.Walls,s,data.walls)
    -- Ways before transitions: a transition's end may snap onto a way.
    timed("ways",R.Ways,s,data.ways)
    timed("joinends",R.JoinEnds,s,data.links)
    timed("links",R.Links,s,data.links)
    timed("clearance",R.Clearance,s)
    return s
end
-- Keeping off walls (Florian 2026-10-13: "a player does not like to run
-- straight at a corner or along a wall"): on a level, the walkable cells
-- within the map's clearance (yards; CLEARANCE unless its settings say,
-- 0: off) of anything not walkable (a wall, no-go, the edge of the
-- painting) cost more, the nearer the more (1 + NEAR times at the edge).
-- Narrow passages stay walkable; the search (at most NEARWEIGHT, so it
-- weighs the costs) and the line pulled tight (cost above CLEAR) keep to
-- their middle where there is room. Given ways and transitions are left
-- as drawn. Measured on Florian's Undercity ring (2-yard cells): 32 % of
-- the line within 1.5 yards of an edge before, 3 % after.
R.CLEARANCE=4
R.NEAR=2
R.MAXCLEARANCE=8
function R.ClearanceOf(zones)
    local maps=Routing:Data().maps or {}
    local yards
    for _,zone in ipairs(zones or {}) do
        local m=maps[zone]
        local v=type(m)=="table" and tonumber(m.clearance)
        if v then yards=math.min(yards or v,v) end
    end
    return math.max(0,math.min(R.MAXCLEARANCE,yards or R.CLEARANCE))
end
function R.Clearance(s)
    s.near,s.nearK=nil,nil
    local yards=R.ClearanceOf(s.zones)
    if not (s.level and yards>0) then return end
    local cols,rows=s.cols,s.rows
    local K=math.max(1,math.ceil(yards/(s.cell or R.CELL)))
    local open={}
    if s.open then
        for cy=0,rows-1 do
            R.Pace(cols)
            for cx=0,cols-1 do
                if R.BaseCost(s,cx,cy) then open[cy*cols+cx]=true end
            end
        end
    else
        -- On a level not set open only painted cells and given ways can be
        -- walked (BaseCost): those asked, not the whole grid (Claude
        -- 2026-10-14: a third of preparing a Undercity level). The same cells.
        for _,set in ipairs({s.cells,s.onway or {}}) do
            for i in pairs(set) do
                if not open[i] and type(i)=="number" and i>=0 and i<cols*rows then
                    R.Pace(1)
                    if R.BaseCost(s,i%cols,math.floor(i/cols)) then open[i]=true end
                end
            end
        end
    end
    local near,queue,head={},{},1
    for i in pairs(open) do
        R.Pace(1)
        local cx,cy=i%cols,math.floor(i/cols)
        local edge=false
        for dy=-1,1 do
            for dx=-1,1 do
                local nx,ny=cx+dx,cy+dy
                if (dx~=0 or dy~=0) and (nx<0 or ny<0 or nx>=cols or ny>=rows or not open[ny*cols+nx]) then edge=true end
            end
        end
        if edge then near[i]=1;queue[#queue+1]=i end
    end
    while head<=#queue do
        local i=queue[head];head=head+1
        R.Pace(1)
        local d=near[i]
        if d<K then
            local cx,cy=i%cols,math.floor(i/cols)
            for dy=-1,1 do
                for dx=-1,1 do
                    local nx,ny=cx+dx,cy+dy
                    local j=ny*cols+nx
                    if nx>=0 and ny>=0 and nx<cols and ny<rows and open[j] and not near[j] then near[j]=d+1;queue[#queue+1]=j end
                end
            end
        end
    end
    s.near,s.nearK=near,K
end

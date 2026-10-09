local _,G=...
if not G.ready then return end
-- Route grid (plan phase 5b): one raster over the zones of a route, in the
-- coordinates of their continent (or of the one zone), 8 yards a cell.
-- Painted areas mark cells: no-go (blocked), preferred (cheaper), high-risk
-- (dearer, or blocked by the setting). A leg whose straight line crosses
-- nothing costly stays straight; otherwise A* finds the way round and the
-- path is pulled tight again (string pulling). Searches run as coroutines in
-- small slices (G.Grid.Run), so nothing stutters.
local ns=G.ns
local R={}
G.Grid=R
R.CELL=8
local NOGO,PREFER,RISK,ENEMY=1,2,3,4
R.KIND={nogo=NOGO,prefer=PREFER,risk=RISK}

local function call(...) return G.Call(...) end
-- The space a set of zones shares: their continent when they have one.
function R.Space(zones)
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
        if zone==space then a,b,c,d=0,1,0,1 else a,b,c,d=call("C_Map.GetMapRectOnMap",zone,space) end
        if type(a)~="number" then a,b,c,d=0,1,0,1 end
        minX,maxX,minY,maxY=math.min(minX,a),math.max(maxX,b),math.min(minY,c),math.max(maxY,d)
    end
    local s={mapID=space,width=width,height=height,minX=minX,maxX=maxX,minY=minY,maxY=maxY,zones=zones}
    s.cols=math.max(1,math.ceil((maxX-minX)*width/R.CELL))
    s.rows=math.max(1,math.ceil((maxY-minY)*height/R.CELL))
    s.cells={}
    -- Terrain (slopes, water) where the local data has it and the setting wants it.
    local frame=G:Config().routeTerrain and ns.MapTerrain and ns.MapTerrain:Frame(space)
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
    local cx=math.floor((x-s.minX)*s.width/R.CELL)
    local cy=math.floor((y-s.minY)*s.height/R.CELL)
    if cx<0 or cy<0 or cx>=s.cols or cy>=s.rows then return nil end
    return cx,cy
end
-- A space point in an enemy base (after painting: a painted stroke there wins).
function R.InEnemy(s,x,y)
    local cx,cy=R.Cell(s,x,y)
    return cx~=nil and s.cells[cy*s.cols+cx]==ENEMY
end
function R.Center(s,cx,cy)
    return s.minX+(cx+.5)*R.CELL/s.width,s.minY+(cy+.5)*R.CELL/s.height
end
-- Enemy places (Core: enemy capitals, areas around enemy flight masters)
-- first, so painted strokes can still open a way through.
function R.Enemies(s)
    if G:Config().enemy=="ignore" or not (ns.MapOverlays and ns.MapOverlays.Hostile) then return end
    for _,zone in ipairs(s.zones) do
        for _,place in ipairs(ns.MapOverlays:Hostile(zone)) do
            local x0,y0=R.ToSpace(s,zone,place.left,place.top)
            local x1,y1=R.ToSpace(s,zone,place.right,place.bottom)
            if x0 and x1 then
                local a,b=R.Cell(s,math.max(s.minX,math.min(x0,x1)),math.max(s.minY,math.min(y0,y1)))
                local c,d=R.Cell(s,math.min(s.maxX-1e-9,math.max(x0,x1)),math.min(s.maxY-1e-9,math.max(y0,y1)))
                if a and c then
                    for cy=b,d do for cx=a,c do s.cells[cy*s.cols+cx]=ENEMY end end
                end
            end
        end
    end
end
-- Transitions (bridges, tunnels, cave entrances, Florian 2026-10-08): a
-- link from one cell to another at its walking length; one-way ones only
-- forwards. s.links[from] = {{to, yards}}.
function R.Links(s,links)
    s.links,s.linked,s.back={},{},{}
    for _,link in ipairs(links or {}) do
        local ax,ay=R.ToSpace(s,link.a.mapID,link.a.x,link.a.y)
        local bx,by=R.ToSpace(s,link.b.mapID,link.b.x,link.b.y)
        local acx,acy,bcx,bcy
        if ax then acx,acy=R.Cell(s,ax,ay) end
        if bx then bcx,bcy=R.Cell(s,bx,by) end
        if acx and bcx then
            local a,b=acy*s.cols+acx,bcy*s.cols+bcx
            local yards=R.Yards(s,ax,ay,bx,by)
            s.links[a]=s.links[a] or {};table.insert(s.links[a],{b,yards});s.linked[a..">"..b]=true
            s.back[b]=s.back[b] or {};table.insert(s.back[b],{a,yards})
            if not link.oneway then
                s.links[b]=s.links[b] or {};table.insert(s.links[b],{a,yards});s.linked[b..">"..a]=true
                s.back[a]=s.back[a] or {};table.insert(s.back[a],{b,yards})
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
    for cy=b,d do
        for cx=a,c do
            local x,y=R.Center(s,cx,cy)
            if R.Inside(poly,x,y) then s.cells[cy*s.cols+cx]=code end
        end
    end
end
function R.Paint(s,areas)
    R.Enemies(s)
    for _,zone in ipairs(s.zones) do
        for _,stroke in ipairs(areas[zone] or {}) do
            if stroke.poly then R.Polygon(s,zone,stroke) end
            local x,y
            if not stroke.poly then x,y=R.ToSpace(s,zone,stroke.x,stroke.y) end
            local center=x and {R.Cell(s,x,y)}
            if center and center[1] then
                local radius=math.max(1,math.floor((stroke.r or 20)/R.CELL+.5))
                local code=R.KIND[stroke.kind]
                for dy=-radius,radius do
                    for dx=-radius,radius do
                        if dx*dx+dy*dy<=radius*radius then
                            local cx,cy=center[1]+dx,center[2]+dy
                            if cx>=0 and cy>=0 and cx<s.cols and cy<s.rows then s.cells[cy*s.cols+cx]=code end
                        end
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
function R.Ground(s,cx,cy)
    if not s.terrain then return 1 end
    local index=cy*s.cols+cx
    local cost=s.ground[index]
    if cost then return cost end
    local f=s.terrain
    local x,y=R.Center(s,cx,cy)
    local code=ns.MapTerrain:Code(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
    if not code then cost=1
    else
        local water=math.floor(code/4)%4
        -- Roads (the client's road textures, Florian 2026-10-08: safe ways
        -- marked in advance) are preferred like painted preferred ground.
        if code%64>=32 and G:Config().preferRoads and water==0 then cost=R.ROAD
        elseif water==3 then cost=20
        elseif water==2 then cost=G:Config().avoidWater and R.SWIM or 1.5
        elseif water==1 then cost=1.2
        else
            cost=R.SLOPE[code%4+1]
            if code%4==3 then s.steep[index]=true end
        end
    end
    -- Ways walked often (Trace) are cheaper, like a road.
    if G:Config().preferWalked and G.Trace then
        local f=s.terrain
        local wx,wy=R.Center(s,cx,cy)
        if G.Trace:Count(f.instance,f.a[f.iy]+wy*f.dy,f.a[f.ix]+wx*f.dx)>=G.Trace.WALKED then cost=math.min(cost,R.ROAD) end
    end
    s.ground[index]=cost
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
    if not s.terrain then return nil end
    local f=s.terrain
    local x,y=R.Center(s,cx,cy)
    local t=ns.MapTerrain:Code(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx)
    if not t then return nil end
    local water=math.floor(t/4)%4
    if water==3 then return "magma" end
    if water==2 and G:Config().avoidWater then return "swim" end
    if water==0 and t%4==3 then return "steep" end
    return nil
end
-- Ground height of a cell (yards), cached; nil without height data.
function R.Height(s,cx,cy)
    local index=cy*s.cols+cx
    local h=s.elevation[index]
    if h==nil then
        local f=s.terrain
        local x,y=R.Center(s,cx,cy)
        h=ns.MapTerrain:Height(f.instance,f.a[f.iy]+y*f.dy,f.a[f.ix]+x*f.dx) or false
        s.elevation[index]=h
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
function R.Wall(s,ax,ay,bx,by)
    local T=ns.MapTerrain
    if not (type(s.terrain)=="table" and s.terrain.a and T.Wall) then return 0 end
    local gx1,gy1=R.TerrainCell(s,ax,ay)
    local gx2,gy2=R.TerrainCell(s,bx,by)
    if gx1==gx2 and gy1==gy2 then return 0 end
    return T:Wall(s.terrain.instance,gx1,gy1,gx2,gy2)
end
-- The walls on a line, sampled every 2 yards (the route cells and the
-- terrain cells do not line up; a slanted step may cross two terrain edges).
function R.LineWall(s,ax,ay,bx,by)
    local n=math.max(1,math.ceil(R.Yards(s,ax,ay,bx,by)/2))
    local up,down=false,false
    local lx,ly=ax,ay
    for i=1,n do
        local px,py=ax+(bx-ax)*i/n,ay+(by-ay)*i/n
        local wall=R.Wall(s,lx,ly,px,py)
        if wall==1 or wall==3 then up=true end
        if wall==2 or wall==3 then down=true end
        lx,ly=px,py
    end
    return (up and 1 or 0)+(down and 2 or 0)
end
-- The wall between two route cells (cached per pair).
function R.CellWall(s,cx,cy,nx,ny)
    if not s.walls then return 0 end
    local key=(cy*s.cols+cx)*9+(ny-cy+1)*3+(nx-cx+1)
    local wall=s.walls[key]
    if wall==nil then
        local ax,ay=R.Center(s,cx,cy)
        local bx,by=R.Center(s,nx,ny)
        wall=R.LineWall(s,ax,ay,bx,by)
        s.walls[key]=wall
    end
    return wall
end
function R.Step(s,cx,cy,nx,ny,cost,goal)
    if not s.terrain then return cost end
    local from,to=R.Height(s,cx,cy),R.Height(s,nx,ny)
    if not (from and to) then return cost end
    local wall=R.CellWall(s,cx,cy,nx,ny)
    -- A wall up (or a ridge) is never climbed; a wall down is a drop.
    if wall==1 or wall==3 then return nil end
    if wall==2 then
        local mode=G:Config().cliffs
        if mode=="always" or (mode=="safe" and from-to<=R.SAFEDROP) then return cost*1.5 end
        return cost*R.SLOPE[4]
    end
    local cliff=s.steep[ny*s.cols+nx] or math.abs(to-from)>R.MAXRISE
    if not cliff then return cost end
    if to>from+1 then
        if goal and to-from<=R.GOALSTEP then return cost end
        return nil
    end
    if to>=from-1 then return cost end
    local mode=G:Config().cliffs
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
    local steps=math.max(1,math.ceil(R.Yards(s,x1,y1,x2,y2)/(R.CELL/2)))
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
                if lastH and h<lastH then peak=math.max(h,peak-(R.CELL/2)) end
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
    local code=s.cells[cy*s.cols+cx]
    if code==NOGO then return nil end
    if code==PREFER then return .5 end
    local cost=1
    if code==RISK then
        local mode=G:Config().risk
        if mode=="block" then return nil end
        if mode=="avoid" then cost=4 end
    elseif code==ENEMY then
        -- Enemy base: guards; avoided hard, or never with "block".
        if G:Config().enemy=="block" then return nil end
        cost=10
    end
    return cost*R.Ground(s,cx,cy)
end
-- The straight line between two space points touches only plain,
-- preferred or gently sloped cells (sampled every half cell).
function R.Clear(s,x1,y1,x2,y2)
    local yards=R.Yards(s,x1,y1,x2,y2)
    local steps=math.max(1,math.ceil(yards/(R.CELL/2)))
    local last
    for i=0,steps do
        local t=i/steps
        local px,py=x1+(x2-x1)*t,y1+(y2-y1)*t
        local cx,cy=R.Cell(s,px,py)
        if cx then
            local cost=R.Cost(s,cx,cy)
            -- Gentle slopes and shallow water still count as a clear line.
            if not cost or cost>R.CLEAR then return false end
            if s.terrain and last and R.Wall(s,last[1],last[2],px,py)~=0 then return false end
            last={px,py}
        end
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
function R.Explore(s,start,goal,goals,limit,maxCost,reverse)
    local cols,rows,CELL=s.cols,s.rows,R.CELL
    -- The estimate: the octile distance to the goal, or to the nearest of
    -- the goals (still never too high, so the ways found stay the shortest).
    local targets={}
    if goal then targets[1]={goal%cols,math.floor(goal/cols)}
    elseif goals then for index in pairs(goals) do targets[#targets+1]={index%cols,math.floor(index/cols)} end end
    local function h(cx,cy)
        local best
        for i=1,#targets do
            local dx,dy=math.abs(cx-targets[i][1]),math.abs(cy-targets[i][2])
            local d=(math.max(dx,dy)+(SQRT2-1)*math.min(dx,dy))*CELL*.5
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
                            if not closed[index] then
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
                if not closed[index] and (not cost[index] or ng<cost[index]) then
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
function R.Search(s,x1,y1,x2,y2,limit)
    local sx,sy=R.Cell(s,x1,y1)
    local tx,ty=R.Cell(s,x2,y2)
    if not (sx and tx) then return nil end
    local cols=s.cols
    local start,goal=sy*cols+sx,ty*cols+tx
    -- First, the other way round from the goal, briefly: a goal on a
    -- plateau or in a closed hollow nobody gets into shows at once, without
    -- searching the whole map (Florian 2026-10-09: calculating took long).
    local reached,_,done,exhausted=R.Explore(s,goal,start,nil,R.PRECHECK,nil,true)
    if done and exhausted and not reached[start] then return nil end
    local _,from,ok=R.Explore(s,start,goal,nil,limit)
    if not ok then return nil end
    return R.Trace(s,from,start,goal,x1,y1,x2,y2)
end
-- The way back from goal to start through from, pulled tight.
function R.Trace(s,from,start,goal,x1,y1,x2,y2)
    local cols=s.cols
    if not from[goal] and start~=goal then return nil end
    -- Cells back to the start, then pulled tight: a point is kept only where
    -- the line from the last kept one stops being clear.
    local cells={}
    local index=goal
    while index do table.insert(cells,1,index);index=from[index] end
    local points={{x1,y1}}
    local anchor={x1,y1}
    local previous
    for i=2,#cells do
        local px,py=R.Center(s,cells[i]%cols,math.floor(cells[i]/cols))
        if s.linked and s.linked[cells[i-1]..">"..cells[i]] then
            -- Through a transition: both of its ends stay on the way.
            if previous and (previous[1]~=anchor[1] or previous[2]~=anchor[2]) then points[#points+1]=previous end
            points[#points+1]={px,py,link=true};anchor={px,py}
        elseif not R.Clear(s,anchor[1],anchor[2],px,py) and previous then
            points[#points+1]=previous;anchor=previous
        end
        previous={px,py}
    end
    points[#points+1]={x2,y2}
    return points
end

-- Runs a function as a coroutine in slices (a few milliseconds per frame).
R.BUDGET=8
R.PRECHECK=3000
function R.Run(fn,done)
    local co=coroutine.create(fn)
    local ticker
    -- Several slices per frame while they take less than R.BUDGET ms (the
    -- real ways of a large route are many searches; one slice per frame
    -- made it slow), so the game keeps its frame rate.
    local clock=rawget(_G,"debugprofilestop")
    local function step()
        local began=clock and clock()
        repeat
            local ok,result=coroutine.resume(co)
            if not ok then ticker:Cancel();G:Print("Route failed: "..tostring(result));if done then done(nil) end;return end
            if coroutine.status(co)=="dead" then ticker:Cancel();if done then done(result) end;return end
        until not clock or clock()-began>=R.BUDGET
    end
    ticker=C_Timer.NewTicker(.01,step)
    return ticker
end

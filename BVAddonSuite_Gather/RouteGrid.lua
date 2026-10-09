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
    if frame and ns.MapTerrain:Data(frame.instance) then s.terrain,s.ground,s.steep,s.elevation=frame,{},{},{} end
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
    s.links,s.linked={},{}
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
            if not link.oneway then s.links[b]=s.links[b] or {};table.insert(s.links[b],{a,yards});s.linked[b..">"..a]=true end
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
        if code%64>=32 and G:Config().preferRoads and water==0 then cost=.6
        elseif water==3 then cost=20
        elseif water==2 then cost=G:Config().avoidWater and 6 or 1.5
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
        if G.Trace:Count(f.instance,f.a[f.iy]+wy*f.dy,f.a[f.ix]+wx*f.dx)>=G.Trace.WALKED then cost=math.min(cost,.6) end
    end
    s.ground[index]=cost
    return cost
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
function R.Step(s,cx,cy,nx,ny,cost,goal)
    if not (s.terrain and s.steep[ny*s.cols+nx]) then return cost end
    local from,to=R.Height(s,cx,cy),R.Height(s,nx,ny)
    if not (from and to) then return cost end
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
-- Cost of entering a cell per yard; nil = blocked. Painted areas win over
-- the terrain: preferred ground is cheap whatever its slope.
function R.Cost(s,cx,cy)
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
    for i=0,steps do
        local t=i/steps
        local cx,cy=R.Cell(s,x1+(x2-x1)*t,y1+(y2-y1)*t)
        if cx then
            local cost=R.Cost(s,cx,cy)
            -- Gentle slopes and shallow water still count as a clear line.
            if not cost or cost>1.25 then return false end
        end
    end
    return true
end

-- A* on the cells (8 neighbours, octile heuristic), yielding every 400 steps.
local SQRT2=math.sqrt(2)
local function push(heap,node)
    heap[#heap+1]=node
    local i=#heap
    while i>1 do
        local parent=math.floor(i/2)
        if heap[parent][1]<=heap[i][1] then break end
        heap[parent],heap[i]=heap[i],heap[parent];i=parent
    end
end
local function pop(heap)
    local top=heap[1]
    local last=table.remove(heap)
    if #heap>0 then
        heap[1]=last
        local i=1
        while true do
            local l,r,s=i*2,i*2+1,i
            if heap[l] and heap[l][1]<heap[s][1] then s=l end
            if heap[r] and heap[r][1]<heap[s][1] then s=r end
            if s==i then break end
            heap[i],heap[s]=heap[s],heap[i];i=s
        end
    end
    return top
end
function R.Search(s,x1,y1,x2,y2,limit)
    local sx,sy=R.Cell(s,x1,y1)
    local tx,ty=R.Cell(s,x2,y2)
    if not (sx and tx) then return nil end
    local cols=s.cols
    local start,goal=sy*cols+sx,ty*cols+tx
    local function h(cx,cy) local dx,dy=math.abs(cx-tx),math.abs(cy-ty);return (math.max(dx,dy)+(SQRT2-1)*math.min(dx,dy))*R.CELL*.5 end
    local open,cost,from={},{[start]=0},{}
    push(open,{h(sx,sy),start})
    local steps=0
    limit=limit or 60000
    while #open>0 do
        local node=pop(open)
        local current=node[2]
        if current==goal then break end
        steps=steps+1
        if steps>limit then return nil end
        if steps%400==0 and coroutine.running() then coroutine.yield() end
        local cx,cy=current%cols,math.floor(current/cols)
        for dy=-1,1 do
            for dx=-1,1 do
                if dx~=0 or dy~=0 then
                    local nx,ny=cx+dx,cy+dy
                    if nx>=0 and ny>=0 and nx<cols and ny<s.rows then
                        local step=R.Cost(s,nx,ny)
                        if step then step=R.Step(s,cx,cy,nx,ny,step,ny*cols+nx==goal) end
                        -- No corner cutting past blocked cells.
                        if step and dx~=0 and dy~=0 and (not R.Cost(s,cx+dx,cy) or not R.Cost(s,cx,cy+dy)) then step=nil end
                        if step then
                            local index=ny*cols+nx
                            local g=cost[current]+step*R.CELL*((dx~=0 and dy~=0) and SQRT2 or 1)
                            if not cost[index] or g<cost[index] then
                                cost[index]=g;from[index]=current
                                push(open,{g+h(nx,ny),index})
                            end
                        end
                    end
                end
            end
        end
        for _,link in ipairs(s.links and s.links[current] or {}) do
            local index=link[1]
            local g=cost[current]+link[2]
            if not cost[index] or g<cost[index] then
                cost[index]=g;from[index]=current
                push(open,{g+h(index%cols,math.floor(index/cols)),index})
            end
        end
    end
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
function R.Run(fn,done)
    local co=coroutine.create(fn)
    local ticker
    local function step()
        local ok,result=coroutine.resume(co)
        if not ok then ticker:Cancel();G:Print("Route failed: "..tostring(result));if done then done(nil) end;return end
        if coroutine.status(co)=="dead" then ticker:Cancel();if done then done(result) end end
    end
    ticker=C_Timer.NewTicker(.01,step)
    return ticker
end

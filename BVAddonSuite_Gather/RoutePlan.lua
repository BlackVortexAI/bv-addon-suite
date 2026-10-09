local _,G=...
if not G.ready then return end
-- Route planning for the editor (plan phase 5b, Florian 2026-10-08): the
-- chosen nodes of one or more zones, those within the pass-by radius of one
-- another become one stop (you see and reach them from there), the stops
-- become the shortest loop (nearest neighbour, 2-opt, Or-opt), and every
-- leg that crosses a painted no-go or high-risk area goes round it
-- (G.Grid). Routes and painted areas are kept account-wide in BVGatherDB.
local ns=G.ns
local Grid=G.Grid
local P={}
G.Plan=P
P.FOOT,P.MOUNT=7,11.2

function P:Store()
    local db=G.Data.db or G.Data:Init()
    if type(db.routes)~="table" then db.routes={} end
    if type(db.areas)~="table" then db.areas={} end
    if type(db.links)~="table" then db.links={} end
    return db
end
-- Painted strokes per zone: {x, y (zone), r (yards), kind}.
function P:Areas() return self:Store().areas end
function P:Strokes(mapID)
    local areas=self:Areas()
    if type(areas[mapID])~="table" then areas[mapID]={} end
    return areas[mapID]
end

-- Transitions: {a = {mapID, x, y}, b = {...}, oneway, name}.
function P:Links() return self:Store().links end
function P:AddLink(a,b,oneway,name)
    local links=self:Links()
    links[#links+1]={a=a,b=b,oneway=oneway or nil,name=name or ("Transition "..(#links+1))}
    return links[#links]
end
function P:RemoveLink(index) table.remove(self:Links(),index) end
-- A search area (Florian 2026-10-09: "only the south of Silverpine", a
-- choice for this route, not a no-go area): {mapID, poly = {x1, y1, ...}}.
function P.InArea(area,zone,node)
    if not area or not area.poly or #area.poly<6 then return true end
    local x,y=node.x,node.y
    if zone~=area.mapID then
        x,y=Grid.Convert(zone,area.mapID,x,y)
        if not x then return false end
    end
    return Grid.Inside(area.poly,x,y)
end
-- "Test 1 (Silverpine Forest)": a route with the zones it lies in.
function P:Label(name)
    local route=self:Load(name)
    local zones={}
    for _,zone in ipairs(route and route.zones or {}) do
        local info=G.Call("C_Map.GetMapInfo",zone)
        zones[#zones+1]=type(info)=="table" and info.name or ("Map "..zone)
    end
    return #zones>0 and (name.." ("..table.concat(zones,", ")..")") or name
end
-- The node names of some zones as {kind, name, count}, by kind then count.
local function label(kind,node) return node.name or ("Unknown "..G.TYPE[kind].label:lower()) end
function P.Key(kind,name) return kind..":"..name end
-- Underground only when asked; known spawns nobody has seen only with "Known spawns in routes".
local function usable(node,kind,zone)
    if node.under and not G:Config().routeUnderground then return false end
    if not G:Config().routeKnown and kind then
        local s=G.Data:Sources(kind,zone,node)
        if not s.own and s.known and not (s.gathermate or s.text or s.import or s.shared) then return false end
    end
    return true
end
function P:Names(zones,area)
    local counts,out={},{}
    for _,t in ipairs(G.TYPES) do
        for _,zone in ipairs(zones) do
            for _,node in ipairs(G.Data:Nodes(t.id,zone) or {}) do
                if usable(node,t.id,zone) and P.InArea(area,zone,node) then
                    local key=P.Key(t.id,label(t.id,node))
                    if not counts[key] then counts[key]={kind=t.id,name=label(t.id,node),count=0,key=key};out[#out+1]=counts[key] end
                    counts[key].count=counts[key].count+1
                end
            end
        end
    end
    local order={};for i,t in ipairs(G.TYPES) do order[t.id]=i end
    table.sort(out,function(a,b)
        if a.kind~=b.kind then return order[a.kind]<order[b.kind] end
        if a.count~=b.count then return a.count>b.count end
        return a.name<b.name
    end)
    return out
end
-- Chosen nodes on the space map as {x, y (space), X, Y (yards), kind, node, mapID}.
function P:Nodes(s,chosen,area)
    local out={}
    for _,t in ipairs(G.TYPES) do
        for _,zone in ipairs(s.zones) do
            for _,node in ipairs(G.Data:Nodes(t.id,zone) or {}) do
                if usable(node,t.id,zone) and chosen[P.Key(t.id,label(t.id,node))] and P.InArea(area,zone,node) then
                    local x,y=Grid.ToSpace(s,zone,node.x,node.y)
                    -- Known spawns nobody has found yet count half for "worth the
                    -- way": something grows there only some of the time.
                    local src=G.Data:Sources(t.id,zone,node)
                    local unseen=not src.own and src.known and not (src.gathermate or src.text or src.import or src.shared)
                    if x then out[#out+1]={x=x,y=y,X=x*s.width,Y=y*s.height,kind=t.id,node=node,mapID=zone,weight=unseen and P.KNOWN or 1} end
                end
            end
        end
    end
    return out
end

-- Stops: nodes join a stop while every one of them stays within the radius
-- of its middle (greedy, nearest stop first).
local function yards(a,b) local dx,dy=a.X-b.X,a.Y-b.Y;return math.sqrt(dx*dx+dy*dy) end
-- The way between two stops for ordering them: the distance, plus P.CLIMB
-- yards per yard of height when they lie on different levels (Florian
-- 2026-10-09: a route went in and out of a ravine again and again; out of
-- it there is only a long way round). Stops of one level come one after
-- another, a ravine is entered once. Since the real ways to the nearest
-- stops are measured (P.Ways) this only weighs pairs without a measured way;
-- offline sweeps on Durotar 2026-10-09 gave the shortest routes with 0.
P.CLIMB=0
-- How much a known spawn you never found counts for "worth the way".
P.KNOWN=.5
-- Real ways between neighbouring stops (P.Ways during a calculation):
-- where known they replace the estimate.
P.real=nil
local function way(a,b)
    local known=P.real and P.real[a] and P.real[a][b]
    if known then return known end
    local d=yards(a,b)
    if a.Z and b.Z then
        local dz=math.abs(a.Z-b.Z)
        if dz>P.LEVEL then d=d+dz*P.CLIMB end
    end
    return d
end
-- fits(a,b): may two nodes share a stop (beyond the radius)? Nodes on
-- different levels never do (P.LEVEL, Florian 2026-10-09: a node down in a
-- ravine is not reached from its edge; it gets its own stop down there).
P.LEVEL=6
function P.Cluster(nodes,radius,fits)
    table.sort(nodes,function(a,b) if a.X~=b.X then return a.X<b.X end return a.Y<b.Y end)
    local stops={}
    for i,node in ipairs(nodes) do
        local best,bestDistance
        for _,stop in ipairs(stops) do
            local d=yards(stop,node)
            if d<=radius*2 and (not bestDistance or d<bestDistance) then
                local n=#stop.nodes+1
                local mid={X=(stop.X*(n-1)+node.X)/n,Y=(stop.Y*(n-1)+node.Y)/n}
                local ok=yards(mid,node)<=radius
                for _,member in ipairs(stop.nodes) do
                    if ok and (yards(mid,member)>radius or (fits and not fits(member,node))) then ok=false end
                end
                if ok then best,bestDistance=stop,d end
            end
        end
        if best then
            local n=#best.nodes+1
            best.X,best.Y=(best.X*(n-1)+node.X)/n,(best.Y*(n-1)+node.Y)/n
            best.nodes[n]=node
        else stops[#stops+1]={X=node.X,Y=node.Y,nodes={node}} end
        if i%60==0 and coroutine.running() then coroutine.yield() end
    end
    return stops
end

-- Tour through the stops: a loop (back to the first) or a line.
local function successor(order,i,loop)
    if i<#order then return order[i+1] end
    return loop and order[1] or nil
end
function P.Length(order,loop)
    local total=0
    for i=1,#order do local b=successor(order,i,loop);if b then total=total+way(order[i],b) end end
    return total
end
-- Worth the way (Florian 2026-10-09: not a long walk for one ore): a run of
-- one to WORTHRUN neighbouring stops goes when the way it adds to the tour
-- (the way through it minus the shortcut without it) costs more yards per
-- node than the limit. The worst run goes first, then the tour is looked at
-- again, until every run is worth its way. Runs, not single stops: a far
-- group of three stops looks cheap one by one but not together. Returns the
-- tour and the removed stops.
P.WORTHRUN=8
-- Orders worked out for a loop (from different stops), the shortest kept.
P.RESTARTS=8
P.JUMPLENGTH=25
-- How far a calculation is (Florian 2026-10-09: "Calculating..." looked as
-- if it hung): 0..1 and what it is doing; the editor shows it as a bar.
P.progress={value=0,text=""}
function P.Report(value,text) P.progress.value=math.max(0,math.min(1,value));if text then P.progress.text=text end end
function P.Prune(order,loop,start,limit)
    local removed={}
    if not (limit and limit>0) then return order,removed end
    local function at(i)
        local n=#order
        if loop then return order[(i-1)%n+1] end
        if i<1 then return start end
        return order[i]
    end
    while #order>2 do
        local n=#order
        local best,bestRatio,bestLength
        for i=1,n do
            for k=1,math.min(P.WORTHRUN,n-2) do
                if not loop and i+k-1>n then break end
                local prev,nxt=at(i-1),at(i+k)
                local through=0
                for m=i,i+k-2 do through=through+way(at(m),at(m+1)) end
                if prev then through=through+way(prev,at(i)) end
                if nxt then through=through+way(at(i+k-1),nxt) end
                local shortcut=(prev and nxt) and way(prev,nxt) or 0
                local nodes=0
                for m=i,i+k-1 do for _,node in ipairs(at(m).nodes) do nodes=nodes+(type(node)=="table" and node.weight or 1) end end
                local ratio=(through-shortcut)/math.max(1,nodes)
                if not bestRatio or ratio>bestRatio then best,bestRatio,bestLength=i,ratio,k end
            end
        end
        if not bestRatio or bestRatio<=limit then break end
        P.Report(.4,"Checking which stops are worth the way")
        local cut={}
        for m=best,best+bestLength-1 do cut[#cut+1]=at(m) end
        local gone={};for _,stop in ipairs(cut) do gone[stop]=true;removed[#removed+1]=stop end
        local kept={};for _,stop in ipairs(order) do if not gone[stop] then kept[#kept+1]=stop end end
        order=kept
        if coroutine.running() then coroutine.yield() end
    end
    return order,removed
end
-- For each stop the real way to its P.NEIGHBOURS nearest stops (A*, or
-- the straight line where it is clear), kept both ways for ordering and the
-- path for the route itself. A way that is not found within the search
-- limit counts P.LOST times the straight line (3 gave the shortest routes
-- in the Durotar sweeps 2026-10-09; 5 kept detours to avoid lost legs).
P.NEIGHBOURS=6;P.LOST=3;P.SEARCH=15000
P.paths={}
local function pathYards(s,path)
    local total=0
    for k=2,#path do total=total+Grid.Yards(s,path[k-1][1],path[k-1][2],path[k][1],path[k][2]) end
    return total
end
-- One search per stop reaches all its neighbours at once (Florian
-- 2026-10-09: calculating took long; before, one search per pair). It stops
-- once every neighbour is reached or the way would cost more than P.BOUND
-- times P.LOST times the farthest straight line: such a way counts as lost
-- for the order anyway.
P.BOUND=3
-- Stops you can walk to and back from (Florian 2026-10-09: "if there is no
-- way to a spot, why use it at all?"; red straight lines to stops on
-- plateaus and in pits). One search over the whole map from a stop, one the
-- other way round: the stops both reach belong together. Tried from up to
-- P.ROOTS stops (one might itself sit on an island); the biggest group wins,
-- the rest stays out of the route. With a start (where you stand) the
-- stops are those you can reach from there (and, in a loop, come back from).
-- Returns kept, left out.
P.ROOTS=3;P.REACH=600000;P.MARGIN=400
function P.Reachable(s,stops,start,loop)
    if #stops<2 then return stops,{} end
    local cells={}
    for i,stop in ipairs(stops) do local cx,cy=Grid.Cell(s,stop.x,stop.y);cells[i]=cx and cy*s.cols+cx end
    -- Only round the stops (and P.MARGIN yards beyond): ways far outside
    -- them do not matter for the route.
    local box={math.huge,math.huge,-math.huge,-math.huge}
    for i in ipairs(stops) do
        local cell=cells[i]
        if cell then
            local cx,cy=cell%s.cols,math.floor(cell/s.cols)
            box[1],box[2],box[3],box[4]=math.min(box[1],cx),math.min(box[2],cy),math.max(box[3],cx),math.max(box[4],cy)
        end
    end
    if start then
        local cx,cy=Grid.Cell(s,start.X/s.width,start.Y/s.height)
        if cx then box[1],box[2],box[3],box[4]=math.min(box[1],cx),math.min(box[2],cy),math.max(box[3],cx),math.max(box[4],cy) end
    end
    local margin=math.ceil(P.MARGIN/Grid.CELL)
    box={box[1]-margin,box[2]-margin,box[3]+margin,box[4]+margin}
    local best,tried={},{}
    local from
    if start then
        local cx,cy=Grid.Cell(s,start.X/s.width,start.Y/s.height)
        -- (Standing on blocked ground, e.g. inside a painted no-go area:
        -- the stops decide among themselves.)
        from=cx and Grid.Cost(s,cx,cy) and cy*s.cols+cx or nil
    end
    for _=1,from and 1 or P.ROOTS do
        local root=from
        if not root then
            for i,stop in ipairs(stops) do if cells[i] and not tried[stop] and not best[stop] then root=cells[i];tried[stop]=true;break end end
        end
        if not root then break end
        local there=Grid.Flood(s,root,false,box)
        local back=(loop or not from) and Grid.Flood(s,root,true,box) or there
        -- A node at the foot of a rock lies on a cell nobody walks onto;
        -- you mine it from beside it: a neighbouring cell will do (the stop
        -- moves there).
        local group,count={},0
        for i,stop in ipairs(stops) do
            local cell=cells[i]
            if cell then
                local cx,cy=cell%s.cols,math.floor(cell/s.cols)
                local spot
                if there[cell] and back[cell] then spot=cell
                else
                    for dy=-1,1 do for dx=-1,1 do
                        local nx,ny=cx+dx,cy+dy
                        local near=ny*s.cols+nx
                        if not spot and nx>=0 and ny>=0 and nx<s.cols and ny<s.rows and there[near] and back[near] then spot=near end
                    end end
                end
                if spot then group[stop]=spot;count=count+1 end
            end
        end
        local size=0;for _ in pairs(best) do size=size+1 end
        if count>size then best=group end
        if count*2>=#stops then break end
    end
    local kept,out={},{}
    for i,stop in ipairs(stops) do
        local spot=best[stop]
        if spot then
            if spot~=cells[i] then
                stop.x,stop.y=Grid.Center(s,spot%s.cols,math.floor(spot/s.cols))
                stop.X,stop.Y=stop.x*s.width,stop.y*s.height
            end
            kept[#kept+1]=stop
        else out[#out+1]=stop end
    end
    return kept,out
end
function P.Ways(s,stops)
    P.real,P.paths={},{}
    local n=#stops
    if n<4 or P.NEIGHBOURS<=0 then return end
    local function set(a,b,d)
        P.real[a]=P.real[a] or {};P.real[b]=P.real[b] or {}
        P.real[a][b]=d;if not P.real[b][a] then P.real[b][a]=d end
    end
    for i,a in ipairs(stops) do
        P.Report(.08+.32*(i-1)/n,string.format("Measuring the ways (%d of %d)",i,n))
        local near={}
        for _,b in ipairs(stops) do if b~=a then near[#near+1]={b,yards(a,b)} end end
        table.sort(near,function(p,q) return p[2]<q[2] end)
        local wanted,goals,farthest={},{},0
        for k=1,math.min(P.NEIGHBOURS,#near) do
            local b,d=near[k][1],near[k][2]
            if not (P.real[a] and P.real[a][b]) then
                if Grid.Clear(s,a.x,a.y,b.x,b.y) then set(a,b,d)
                else
                    local cx,cy=Grid.Cell(s,b.x,b.y)
                    if cx then wanted[#wanted+1]={b,d,cy*s.cols+cx};goals[cy*s.cols+cx]=true;farthest=math.max(farthest,d) end
                end
            end
        end
        local sx,sy=Grid.Cell(s,a.x,a.y)
        -- (All stops here can reach each other: P.Reachable came first.)
        if #wanted>0 and sx then
            local start=sy*s.cols+sx
            local _,from=Grid.Explore(s,start,nil,goals,P.SEARCH*2,farthest*P.LOST*P.BOUND)
            for _,w in ipairs(wanted) do
                local b,d,cell=w[1],w[2],w[3]
                local path=not w.lost and (from[cell] or cell==start) and Grid.Trace(s,from,start,cell,a.x,a.y,b.x,b.y)
                if path then
                    set(a,b,pathYards(s,path))
                    P.paths[a]=P.paths[a] or {};P.paths[a][b]=path
                else set(a,b,d*P.LOST) end
            end
        end
        if coroutine.running() then coroutine.yield() end
    end
end
function P.Tour(stops,loop,start)
    local left,order={},{}
    for i,stop in ipairs(stops) do left[i]=stop end
    local current=start or stops[1]
    while #left>0 do
        local best,bestDistance=1,math.huge
        for i,stop in ipairs(left) do local d=way(current,stop);if d<bestDistance then best,bestDistance=i,d end end
        current=table.remove(left,best);order[#order+1]=current
    end
    local n=#order
    if n<4 then return order end
    local improved,passes=true,0
    while improved and passes<30 do
        improved,passes=false,passes+1
        P.Report(.4+.04*passes/30,"Ordering the stops")
        -- 2-opt: reverse order[i+1..j] when the two new edges are shorter.
        for i=1,n-2 do
            for j=i+2,n do
                local a,b,c,d=order[i],order[i+1],order[j],successor(order,j,loop)
                if d~=a then
                    local before=way(a,b)+(d and way(c,d) or 0)
                    local after=way(a,c)+(d and way(b,d) or 0)
                    if after+1e-6<before then
                        local lo,hi=i+1,j
                        while lo<hi do order[lo],order[hi]=order[hi],order[lo];lo,hi=lo+1,hi-1 end
                        improved=true
                    end
                end
            end
            if i%40==0 and coroutine.running() then coroutine.yield() end
        end
        -- Or-opt: move a run of one to three stops between two others.
        for size=1,3 do
            for i=2,n-size do
                local first,last=i,i+size-1
                local prev,nxt=order[first-1],successor(order,last,loop)
                if nxt then
                    local gain=way(prev,order[first])+way(order[last],nxt)-way(prev,nxt)
                    for j=1,n do
                        local a,b=order[j],successor(order,j,loop)
                        if b and (j<first-1 or j>last) and b~=order[first] then
                            local cost=way(a,order[first])+way(order[last],b)-way(a,b)
                            if cost+1e-6<gain then
                                local run={}
                                for k=first,last do run[#run+1]=order[k] end
                                for _=first,last do table.remove(order,first) end
                                local at=j<first and j or j-size
                                for k,stop in ipairs(run) do table.insert(order,at+k,stop) end
                                improved=true
                                break
                            end
                        end
                    end
                end
            end
            if coroutine.running() then coroutine.yield() end
        end
    end
    return order
end

-- The whole plan (runs as a coroutine, G.Grid.Run): zones, chosen keys,
-- options {loop, radius, start {mapID,x,y}}. Result: {points = {{mapID, x, y,
-- stop, count}}, length (yards), stops, skipped (in blocked areas),
-- detours, unreachable}.
function P:Build(zones,chosen,options)
    P.Report(0,"Reading the map")
    local s=Grid.Space(zones)
    Grid.Paint(s,self:Areas())
    Grid.Links(s,self:Links())
    local nodes=self:Nodes(s,chosen,options.area)
    -- Nodes in enemy bases stay out unless enemies are ignored (Florian
    -- 2026-10-09: a Horde route led into Southshore for its herbs).
    local enemy=0
    if G:Config().enemy~="ignore" then
        local kept={}
        for _,node in ipairs(nodes) do
            if Grid.InEnemy(s,node.x,node.y) then enemy=enemy+1 else kept[#kept+1]=node end
        end
        nodes=kept
    end
    -- "Within sight" (Florian 2026-10-09): stops so that every node lies in
    -- sight of one; a stop that falls on blocked ground moves to its member
    -- nearest to the middle.
    local sight=options.goal=="sight"
    -- With heights: a stop only for nodes on one level (not "within sight":
    -- there it is enough to see the node).
    local level
    if s.terrain and not sight then
        for _,node in ipairs(nodes) do
            local cx,cy=Grid.Cell(s,node.x,node.y)
            node.Z=cx and Grid.Height(s,cx,cy) or nil
        end
        level=function(a,b) return not (a.Z and b.Z) or math.abs(a.Z-b.Z)<=P.LEVEL end
    end
    local stops=P.Cluster(nodes,sight and (options.sight or 150) or options.radius or 30,level)
    local open,skipped={},0
    for _,stop in ipairs(stops) do
        stop.x,stop.y=stop.X/s.width,stop.Y/s.height
        -- The stop's level: the mean height of its nodes (with heights).
        if level then
            local sum,n=0,0
            for _,node in ipairs(stop.nodes) do if node.Z then sum,n=sum+node.Z,n+1 end end
            stop.Z=n>0 and sum/n or nil
        end
        local cx,cy=Grid.Cell(s,stop.x,stop.y)
        if sight and cx and not Grid.Cost(s,cx,cy) then
            local best,bestDistance
            for _,node in ipairs(stop.nodes) do
                local d=yards(stop,node)
                local nx,ny=Grid.Cell(s,node.x,node.y)
                if nx and Grid.Cost(s,nx,ny) and (not bestDistance or d<bestDistance) then best,bestDistance=node,d end
            end
            if best then stop.X,stop.Y,stop.x,stop.y=best.X,best.Y,best.x,best.y;cx,cy=Grid.Cell(s,stop.x,stop.y) end
        end
        if cx and not Grid.Cost(s,cx,cy) then skipped=skipped+#stop.nodes else open[#open+1]=stop end
    end
    local start
    if options.start then
        local x,y=Grid.ToSpace(s,options.start.mapID,options.start.x,options.start.y)
        if x then start={X=x*s.width,Y=y*s.height} end
    end
    -- The real ways to the nearest stops first (Florian 2026-10-09: two
    -- hollows 81 yd apart were 1,463 yd apart on foot; ordered by the
    -- straight line, the route went to and fro between them).
    -- From here on the cells' costs stay as they are: kept for the searches.
    s.costs={}
    P.Report(.05,"Finding the stops you can reach")
    local cut
    open,cut=P.Reachable(s,open,start,options.loop)
    P.lastCut=cut
    local cutoff=0;for _,stop in ipairs(cut) do cutoff=cutoff+#stop.nodes end
    P.Ways(s,open)
    P.Report(.4,"Ordering the stops")
    local order=P.Tour(open,options.loop,start)
    -- A loop has no fixed start: the order is also worked out from other
    -- stops and the shortest is kept (Florian 2026-10-09; the order fell
    -- into very different local optima, 21,500 to 24,500 yd).
    if options.loop and #open>=8 then
        local best=P.Length(order,true)
        for k=1,P.RESTARTS-1 do
            local from=open[math.floor(k*#open/P.RESTARTS)+1]
            local other=P.Tour(open,true,from)
            local length=P.Length(other,true)
            if length<best then best,order=length,other end
        end
    end
    local removed
    order,removed=P.Prune(order,options.loop,start,options.worth)
    local unworth=0;for _,stop in ipairs(removed) do unworth=unworth+#stop.nodes end
    local result={points={},length=0,stops=#order,nodes=#nodes,skipped=skipped,enemy=enemy,unworth=unworth,unworthStops=#removed,cutoff=cutoff,cutoffStops=#cut,worth=options.worth,detours=0,unreachable=0,zones=zones,loop=options.loop,goal=sight and "sight" or "visit"}
    local spots={}
    local function add(x,y,stop)
        local mapID,zx,zy=Grid.FromSpace(s,x,y)
        result.points[#result.points+1]={mapID=mapID,x=zx,y=zy,stop=stop and true or nil,count=stop and #stop.nodes or nil}
        spots[#result.points]={x,y}
    end
    -- A leg without a way round stays a straight line: its end point is
    -- marked gap, drawn red and never counted as a jump.
    local gap=false
    for i,stop in ipairs(order) do
        P.Report(.45+.55*(i-1)/math.max(1,#order),string.format("Finding the ways (%d of %d)",i,#order))
        add(stop.x,stop.y,stop)
        if gap then result.points[#result.points].gap=true;gap=false end
        local nxt=successor(order,i,options.loop)
        if nxt and #order>1 then
            local legs={{stop.x,stop.y},{nxt.x,nxt.y}}
            if not Grid.Clear(s,stop.x,stop.y,nxt.x,nxt.y) then
                local path=P.paths[stop] and P.paths[stop][nxt] or Grid.Search(s,stop.x,stop.y,nxt.x,nxt.y)
                -- Both are reachable: a way exists, only farther than the
                -- first search went.
                if not path and s.terrain then path=Grid.Search(s,stop.x,stop.y,nxt.x,nxt.y,P.REACH) end
                if path and options.smooth then path=P.Smooth(s,path) end
                if path then
                    legs=path
                    if #path>2 then result.detours=result.detours+1 end
                    for k=2,#path-1 do add(path[k][1],path[k][2]) end
                else result.unreachable=result.unreachable+1;gap=true end
            end
            for k=2,#legs do result.length=result.length+Grid.Yards(s,legs[k-1][1],legs[k-1][2],legs[k][1],legs[k][2]) end
        end
    end
    -- Side trips to a stop: one way there and back, the tip shortened.
    if P.SPURS then P.Spurs(s,result,spots) end
    -- The pieces that drop down a cliff: drop on the point they lead to
    -- (in a loop the first point for the closing piece).
    local n=#result.points
    local peak
    for j=1,n do
        local a,b=spots[j-1] or (options.loop and n>2 and spots[n]),spots[j]
        if j==1 and gap then result.points[1].gap=true end
        local jump,ground=false,nil
        if a and b and not result.points[j].gap then jump,ground=Grid.Drops(s,a[1],a[2],b[1],b[2],peak) end
        peak=ground and math.max(ground,(peak or ground)-Grid.Yards(s,a[1],a[2],b[1],b[2])/2) or nil
        if jump then
            result.points[j].drop=true
            -- Pieces in a row are one jump.
            if not (result.points[j-1] and result.points[j-1].drop) then result.drops=(result.drops or 0)+1 end
        end
        if j%200==0 and coroutine.running() then coroutine.yield() end
    end
    -- A jump is drawn over at least P.JUMPLENGTH yards from where it starts
    -- (Florian 2026-10-09: the edge fell on a 7-yard piece just before it,
    -- too short to see on the minimap).
    local starts={}
    for j=1,n do if result.points[j].drop and not (result.points[j-1] and result.points[j-1].drop) then starts[#starts+1]=j end end
    for _,j in ipairs(starts) do
        local length,k=0,j
        while k<=n and length<P.JUMPLENGTH do
            local a,b=spots[k-1],spots[k]
            if not (a and b) or result.points[k].gap then break end
            result.points[k].drop=true
            length=length+Grid.Yards(s,a[1],a[2],b[1],b[2])
            k=k+1
        end
    end
    result.issues=P.Issues(s,result,spots,order,cut,options.loop)
    P.real,P.paths=nil,{}
    P.Report(1,"Done")
    return result
end
-- Difficult spots (Florian 2026-10-09: "we will never know every map
-- perfectly; tell the player, who can paint a no-go area and calculate
-- again"). Along the route: runs over hard ground (Grid.Hazard) at least
-- P.ISSUERUN yards long (any length for magma, enemies and high risk), legs
-- far longer than the straight line (a shortcut may exist: a transition),
-- legs without a way, and the stops left out. Close ones of a kind are one.
-- Each: {kind, mapID, x, y, yards}.
P.ISSUERUN={steep=24,swim=20,magma=0,enemy=0,risk=0}
-- Hard ground this close to a stop is the node's own rock; jumps are
-- already orange: neither counts as steep ground.
P.ISSUENEAR=15
P.DETOUR=3;P.DETOURYARDS=200;P.ISSUEMERGE=60
function P.Issues(s,result,spots,order,cut,loop)
    local found={}
    local function add(kind,x,y,yards)
        for _,issue in ipairs(found) do
            if issue.kind==kind and Grid.Yards(s,issue.sx,issue.sy,x,y)<P.ISSUEMERGE then
                issue.yards=(issue.yards or 0)+(yards or 0);return
            end
        end
        found[#found+1]={kind=kind,sx=x,sy=y,yards=yards}
    end
    local points=result.points
    local n=#points
    -- Drops higher than "Short drops" allows (no way round them was found).
    local mode=G:Config().cliffs
    if mode~="always" then
        for j=2,n do
            local a,b=spots[j-1],spots[j]
            if a and b and points[j].drop and not points[j].gap then
                local wall,fall=Grid.LineWall(s,a[1],a[2],b[1],b[2])
                if (wall==2 or wall==3) and fall and fall>Grid.SAFEDROP then add("highdrop",b[1],b[2],fall) end
            end
        end
    end
    local run,runKind,runX,runY=0,nil,nil,nil
    local function close()
        if runKind and run>=(P.ISSUERUN[runKind] or 0) then add(runKind,runX,runY,run) end
        run,runKind=0,nil
    end
    for j=1,n do
        local a,b=spots[j-1] or (loop and n>2 and spots[n]),spots[j]
        if a and b and not points[j].gap then
            local yards=Grid.Yards(s,a[1],a[2],b[1],b[2])
            local stopA=points[j-1] and points[j-1].stop or (j==1 and points[n].stop)
            local stopB=points[j].stop
            local steps=math.max(1,math.ceil(yards/(Grid.CELL/2)))
            for i=1,steps do
                local px,py=a[1]+(b[1]-a[1])*i/steps,a[2]+(b[2]-a[2])*i/steps
                local cx,cy=Grid.Cell(s,px,py)
                local kind=cx and Grid.Hazard(s,cx,cy)
                if kind=="steep" and (points[j].drop or (stopA and yards*i/steps<P.ISSUENEAR) or (stopB and yards*(steps-i)/steps<P.ISSUENEAR)) then kind=nil end
                if kind~=runKind then close() end
                if kind then
                    if not runKind then runKind,runX,runY=kind,px,py end
                    run=run+yards/steps
                end
            end
        elseif points[j].gap and a and b then
            close()
            add("gap",(a[1]+b[1])/2,(a[2]+b[2])/2)
        end
        if j%200==0 and coroutine.running() then coroutine.yield() end
    end
    close()
    -- Long ways round between two stops next to each other.
    local stopAt={}
    for j=1,n do if points[j].stop then stopAt[#stopAt+1]=j end end
    for k=1,#stopAt do
        local i,j=stopAt[k],stopAt[k+1] or (loop and stopAt[1])
        if j and j~=i then
            local way,q=0,i
            while q~=j do
                local nq=q%n+1
                if points[nq].gap then way=nil;break end
                way=way+Grid.Yards(s,spots[q][1],spots[q][2],spots[nq][1],spots[nq][2])
                q=nq
            end
            local straight=Grid.Yards(s,spots[i][1],spots[i][2],spots[j][1],spots[j][2])
            if way and way>straight*P.DETOUR and way-straight>P.DETOURYARDS then
                add("detour",(spots[i][1]+spots[j][1])/2,(spots[i][2]+spots[j][2])/2,way-straight)
            end
        end
    end
    for _,stop in ipairs(cut or {}) do add("cut",stop.x,stop.y,#stop.nodes) end
    local issues={}
    for _,issue in ipairs(found) do
        local mapID,x,y=Grid.FromSpace(s,issue.sx,issue.sy)
        if mapID then issues[#issues+1]={kind=issue.kind,mapID=mapID,x=x,y=y,yards=issue.yards and math.floor(issue.yards+.5) or nil} end
    end
    return issues
end
-- Side trips (Florian 2026-10-09, after the release: the route liked
-- little loops). A stop off the main way is reached by one leg and left by
-- the next; both are searched and pulled tight on their own, so they cross
-- and draw a loop, or run side by side. Where they meet again (within
-- P.SPURJOIN yards, or crossing), the shorter of the two is used both ways -
-- only if it can be walked back: no jump on it (a jump stays one way,
-- Florian), no wall, every step allowed the other way round. Then the tip
-- is shortened by up to P.TRIM yards (following counts a point reached at
-- 20 yards anyway).
P.SPURS=true;P.SPURJOIN=8;P.TRIM=10
local function crosses(a,b,c,d)
    local function o(p,q,r) return (q[1]-p[1])*(r[2]-p[2])-(q[2]-p[2])*(r[1]-p[1]) end
    return o(a,b,c)*o(a,b,d)<0 and o(c,d,a)*o(c,d,b)<0
end
function P.Spurs(s,result,spots)
    local seq={}
    for i,point in ipairs(result.points) do seq[i]={spots[i][1],spots[i][2],point} end
    local function yd(a,b) return Grid.Yards(s,a[1],a[2],b[1],b[2]) end
    local function length(list) local l=0;for q=2,#list do l=l+yd(list[q-1],list[q]) end;return l end
    local function back(list)
        for q=1,#list-1 do
            local a,b=list[q],list[q+1]
            if b[3].gap or b[3].link or Grid.Drops(s,a[1],a[2],b[1],b[2]) or not Grid.Walkable(s,b[1],b[2],a[1],a[2]) then return false end
        end
        return true
    end
    local function copy(e) return {e[1],e[2],{mapID=e[3].mapID,x=e[3].x,y=e[3].y}} end
    local changed=0
    local k=2
    while k<#seq do
        if seq[k][3].stop and not seq[k][3].gap and not (seq[k+1] and seq[k+1][3].gap) then
            local lo=k-1;while lo>1 and not seq[lo][3].stop do lo=lo-1 end
            local hi=k+1;while hi<#seq and not seq[hi][3].stop do hi=hi+1 end
            -- The meeting farthest from the stop.
            local i0,o0
            for i=lo,k-1 do
                for o=hi,k+1,-1 do
                    if not i0 then
                        local near=yd(seq[i],seq[o])<=P.SPURJOIN
                        local crossed=i<k-1 and o>k+1 and crosses(seq[i],seq[i+1],seq[o-1],seq[o])
                        if (near or crossed) and (near and yd(seq[i],seq[o])<.5 or Grid.Walkable(s,seq[i][1],seq[i][2],seq[o][1],seq[o][2])) then i0,o0=i,o end
                    end
                end
            end
            if i0 then
                local into,out={},{}
                for q=i0,k do into[#into+1]=seq[q] end
                for q=k,o0 do out[#out+1]=seq[q] end
                local useIn=back(into) and length(into)
                local useOut=back(out) and length(out)
                local spur
                if useIn and (not useOut or useIn<=useOut) then
                    -- There by the first leg, back the same way.
                    spur={};for q=k,i0,-1 do spur[#spur+1]=seq[q] end
                    local new={}
                    for q=1,k do new[#new+1]=seq[q] end
                    for q=k-1,i0,-1 do new[#new+1]=copy(seq[q]) end
                    for q=o0,#seq do new[#new+1]=seq[q] end
                    seq=new;changed=changed+1
                elseif useOut then
                    -- There the way the second leg comes back.
                    spur={};for q=k,o0 do spur[#spur+1]=seq[q] end
                    local new={}
                    for q=1,i0 do new[#new+1]=seq[q] end
                    for q=o0,k+1,-1 do new[#new+1]=copy(seq[q]) end
                    local at=#new+1
                    for q=k,#seq do new[#new+1]=seq[q] end
                    seq=new;k=at;changed=changed+1
                end
                -- The tip: both sides of the stop are now the same way.
                if spur and P.TRIM>0 and #spur>=2 and length(spur)>P.TRIM+2 then
                    local stop=seq[k]
                    local left,walked,q=P.TRIM,0,1
                    while q<#spur and walked+yd(spur[q],spur[q+1])<left do walked=walked+yd(spur[q],spur[q+1]);q=q+1 end
                    local a,b=spur[q],spur[q+1]
                    local t=(left-walked)/math.max(.01,yd(a,b))
                    local x,y=a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t
                    local mapID,zx,zy=Grid.FromSpace(s,x,y)
                    if mapID then
                        local p=stop[3]
                        local tip={x,y,{mapID=mapID,x=zx,y=zy,stop=p.stop,count=p.count}}
                        -- q points of the way lie between the stop and the new tip on each side.
                        local new={}
                        for r=1,k-q do new[#new+1]=seq[r] end
                        new[#new+1]=tip
                        local at=#new
                        for r=k+q,#seq do new[#new+1]=seq[r] end
                        seq=new;k=at
                    end
                end
            end
        end
        k=k+1
        if k%50==0 and coroutine.running() then coroutine.yield() end
    end
    if changed==0 then return end
    local points,newSpots={},{}
    local total=0
    for i,e in ipairs(seq) do
        points[i]=e[3];newSpots[i]={e[1],e[2]}
        if i>1 then total=total+yd(seq[i-1],e) end
    end
    if result.loop and #seq>2 then total=total+yd(seq[#seq],seq[1]) end
    for i=1,#points do result.points[i]=points[i];spots[i]=newSpots[i] end
    for i=#points+1,#result.points do result.points[i]=nil;spots[i]=nil end
    result.length=total;result.spurs=changed
end
-- Optional curves (Florian 2026-10-08: only when wanted): each corner of a
-- way round is cut (Chaikin), twice; a cut whose new short piece would run
-- into something costly keeps that corner, the rest stays on the old lines.
function P.Smooth(s,path)
    if #path<3 then return path end
    local points=path
    for _=1,2 do
        local out={points[1]}
        for i=2,#points-1 do
            local a,b,c=points[i-1],points[i],points[i+1]
            local p1={b[1]+(a[1]-b[1])*.25,b[2]+(a[2]-b[2])*.25}
            local p2={b[1]+(c[1]-b[1])*.25,b[2]+(c[2]-b[2])*.25}
            if Grid.Clear(s,p1[1],p1[2],p2[1],p2[2]) then out[#out+1]=p1;out[#out+1]=p2 else out[#out+1]=b end
        end
        out[#out+1]=points[#points]
        points=out
    end
    return points
end
-- Length of saved points (after editing them by hand).
function P.Measure(points,loop)
    local total=0
    for i=1,#points do
        local a,b=points[i],points[i+1] or (loop and #points>2 and points[1])
        if b then
            local x1,y1,x2,y2=a.x,a.y,b.x,b.y
            local mapID=a.mapID
            if b.mapID~=mapID and ns.MapPins then x2,y2=ns.MapPins:OnMap(b,mapID) end
            local d=x2 and G.Data.Yards(mapID,x1,y1,x2,y2)
            if d then total=total+d end
        end
    end
    return total
end
function P.Minutes(yards,speed) return math.max(1,math.floor(yards/speed/60+.5)) end

-- Saved routes.
function P:Routes()
    local names={}
    for name in pairs(self:Store().routes) do names[#names+1]=name end
    table.sort(names)
    return names
end
function P:Save(name,route)
    name=type(name)=="string" and name:gsub("^%s+",""):gsub("%s+$","") or ""
    if name=="" or not route then return false end
    local copy={zones={},chosen={},points={},loop=route.loop and true or false,radius=route.radius,length=route.length,goal=route.goal,sight=route.sight}
    if route.issues then
        copy.issues={}
        for i,issue in ipairs(route.issues) do copy.issues[i]={kind=issue.kind,mapID=issue.mapID,x=issue.x,y=issue.y,yards=issue.yards} end
    end
    for i,zone in ipairs(route.zones or {}) do copy.zones[i]=zone end
    for key,on in pairs(route.chosen or {}) do if on then copy.chosen[key]=true end end
    for i,point in ipairs(route.points) do copy.points[i]={mapID=point.mapID,x=point.x,y=point.y,stop=point.stop,count=point.count,drop=point.drop,gap=point.gap} end
    if route.area and route.area.poly then
        copy.area={mapID=route.area.mapID,poly={}}
        for i,v in ipairs(route.area.poly) do copy.area.poly[i]=v end
    end
    self:Store().routes[name]=copy
    return true
end
function P:Load(name) return self:Store().routes[name] end
function P:Delete(name) self:Store().routes[name]=nil end
-- The route as the Map package's waypoints; a loop starts over after the
-- last point (Map 0.2 loop waypoints).
function P:Follow(name,route)
    local waypoints=ns.Map and ns.Map.Active and ns.Map:Active() and ns.Map.Waypoints
    if not waypoints then G:Print("Routes need BV Addon Suite - Map (on).");return false end
    if waypoints:TomTom() then G:Print("TomTom keeps the waypoints: routes need the Map package's own waypoints.");return false end
    local set,n={},0
    for _,point in ipairs(route.points) do
        local title
        if point.stop then n=n+1;title=string.format("%s %d",name,n)..((point.count or 1)>1 and (" ("..point.count..")") or "") else title=name.." (way)" end
        set[#set+1]={mapID=point.mapID,x=point.x,y=point.y,title=title,loop=route.loop or nil}
    end
    if #set==0 then return false end
    local key="Route: "..name
    ns.Map:Config().sets[key]=set
    waypoints:LoadSet(key)
    G:Print(string.format("%s: %d stops, %d yards%s.",name,n,math.floor((route.length or 0)+.5),route.loop and ", loop" or ""))
    return true
end

-- Painted areas and transitions as text (Florian 2026-10-08: shareable):
-- "BVAREAS1", then per line "s,mapID,x,y,r,kind" (a stroke),
-- "p,mapID,kind,x1,y1,x2,y2,..." (a polygon) or
-- "l,mapA,ax,ay,mapB,bx,by,oneway,name" (a transition).
local AREAS="BVAREAS1"
function P:ExportAreas(zones)
    local lines={AREAS}
    local want={};for _,zone in ipairs(zones) do want[zone]=true end
    for _,zone in ipairs(zones) do
        for _,area in ipairs(self:Strokes(zone)) do
            if area.poly then
                local parts={"p",zone,area.kind}
                for _,v in ipairs(area.poly) do parts[#parts+1]=string.format("%.4f",v) end
                lines[#lines+1]=table.concat(parts,",")
            else
                lines[#lines+1]=string.format("s,%d,%.4f,%.4f,%d,%s",zone,area.x,area.y,area.r or 20,area.kind)
            end
        end
    end
    for _,link in ipairs(self:Links()) do
        if want[link.a.mapID] or want[link.b.mapID] then
            lines[#lines+1]=string.format("l,%d,%.4f,%.4f,%d,%.4f,%.4f,%d,%s",link.a.mapID,link.a.x,link.a.y,link.b.mapID,link.b.x,link.b.y,
                link.oneway and 1 or 0,(link.name or ""):gsub("[%c,|]"," "))
        end
    end
    return table.concat(lines,"\n"),#lines-1
end
-- Reads shared areas and transitions; apply=false only counts. Areas and
-- transitions already there are not doubled.
local KINDS={nogo=true,prefer=true,risk=true}
function P:ImportAreas(text,apply)
    if type(text)~="string" or not text:find(AREAS,1,true) then return nil end
    local count={areas=0,links=0,new=0}
    local function same(a,b) return math.abs(a-b)<.0002 end
    for line in text:gmatch("[^\r\n]+") do
        local kind=line:match("^%s*([spl]),")
        local fields={}
        for field in line:gmatch("[^,]+") do fields[#fields+1]=field end
        if kind=="s" and #fields>=6 and KINDS[fields[6]] then
            local zone,x,y,r=tonumber(fields[2]),tonumber(fields[3]),tonumber(fields[4]),tonumber(fields[5])
            if zone and x and y and r then
                count.areas=count.areas+1
                local known=false
                for _,area in ipairs(self:Strokes(zone)) do if not area.poly and area.kind==fields[6] and same(area.x,x) and same(area.y,y) then known=true end end
                if not known then count.new=count.new+1;if apply then local list=self:Strokes(zone);list[#list+1]={x=x,y=y,r=r,kind=fields[6]} end end
            end
        elseif kind=="p" and #fields>=9 and KINDS[fields[3]] then
            local zone=tonumber(fields[2])
            local poly={}
            for i=4,#fields do poly[#poly+1]=tonumber(fields[i]) end
            if zone and #poly>=6 and #poly%2==0 then
                count.areas=count.areas+1
                local known=false
                for _,area in ipairs(self:Strokes(zone)) do
                    if area.poly and #area.poly==#poly and area.kind==fields[3] then
                        local equal=true;for i=1,#poly do if not same(area.poly[i],poly[i]) then equal=false end end
                        if equal then known=true end
                    end
                end
                if not known then count.new=count.new+1;if apply then local list=self:Strokes(zone);list[#list+1]={kind=fields[3],poly=poly} end end
            end
        elseif kind=="l" and #fields>=8 then
            local a={mapID=tonumber(fields[2]),x=tonumber(fields[3]),y=tonumber(fields[4])}
            local b={mapID=tonumber(fields[5]),x=tonumber(fields[6]),y=tonumber(fields[7])}
            if a.mapID and a.x and a.y and b.mapID and b.x and b.y then
                count.links=count.links+1
                local known=false
                for _,link in ipairs(self:Links()) do
                    if link.a.mapID==a.mapID and same(link.a.x,a.x) and same(link.a.y,a.y) and link.b.mapID==b.mapID and same(link.b.x,b.x) and same(link.b.y,b.y) then known=true end
                end
                if not known then count.new=count.new+1;if apply then self:AddLink(a,b,fields[8]=="1",fields[9]) end end
            end
        end
    end
    return count
end

-- Text exchange: "BVROUTE1 <name>", "loop" or "line", then "mapID,x,y,stop".
local HEADER="BVROUTE1"
function P:Export(name,route)
    local lines={HEADER.." "..(name or "Route"):gsub("[%c|]"," "),route.loop and "loop" or "line"}
    for _,point in ipairs(route.points) do
        lines[#lines+1]=string.format("%d,%.4f,%.4f,%d",point.mapID,point.x,point.y,point.stop and (point.count or 1) or 0)
    end
    return table.concat(lines,"\n")
end
function P:Import(text)
    if type(text)~="string" then return nil end
    local name=text:match(HEADER.."[ \t]*([^\r\n]*)")
    if not name then return nil end
    name=name:gsub("%s+$","");if name=="" then name="Imported route" end
    local route={points={},zones={},chosen={},loop=text:match("\n%s*loop%s*\n")~=nil or text:match("\n%s*loop%s*$")~=nil}
    local seen={}
    for line in text:gmatch("[^\r\n]+") do
        local mapID,x,y,count=line:match("^%s*(%d+),([%d%.]+),([%d%.]+),(%d+)%s*$")
        mapID,x,y,count=tonumber(mapID),tonumber(x),tonumber(y),tonumber(count)
        if mapID and x and y and x>=0 and x<=1 and y>=0 and y<=1 then
            route.points[#route.points+1]={mapID=mapID,x=x,y=y,stop=count>0 or nil,count=count>0 and count or nil}
            if not seen[mapID] then seen[mapID]=true;route.zones[#route.zones+1]=mapID end
        end
    end
    if #route.points==0 then return nil end
    route.length=P.Measure(route.points,route.loop)
    return name,route
end

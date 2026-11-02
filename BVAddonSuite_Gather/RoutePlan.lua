local _,G=...
if not G.ready then return end
-- Route planning for the editor (plan phase 5b, Florian 2026-10-08): the
-- chosen nodes of one or more zones, those within the pass-by radius of one
-- another become one stop (you see and reach them from there), the stops
-- become the shortest loop (nearest neighbour, 2-opt, Or-opt), and every
-- leg is a way on BV Routing's navmesh (RoutePlanNav.lua; since 2026-10-26 the
-- only planner). Routes are kept account-wide in BVGatherDB; painted areas and
-- transitions are BV Routing's since 2026-10-10 (BVRoutingDB, shared with
-- Route Studio and /bv route).
local ns=G.ns
local Space=G.Space
local P={}
G.Plan=P
-- A pause inside the plan (its slices): BV Routing's navmesh, if another plan used another continent in between,
-- made current again for this one (Routing.Hpa.Yield; Claude 2026-10-26).
function P.Yield()
    local H=G.Routing and G.Routing.Hpa
    if H and H.Yield then H.Yield() else coroutine.yield() end
end
-- The frame given back by the clock inside the plan's slices (BV Routing's navmesh: its continent made current again
-- after it).
function P.Breathe()
    local H=G.Routing and G.Routing.Hpa
    if H and H.Breathe then H.Breathe() end
end
P.FOOT,P.MOUNT=7,11.2

function P:Store()
    local db=G.Data.db or G.Data:Init()
    if type(db.routes)~="table" then db.routes={} end
    -- Areas and transitions painted before 2026-10-10 move to BV Routing once.
    if db.areas~=nil or db.links~=nil then
        G.Routing:Adopt(db.areas,db.links)
        db.areas,db.links=nil,nil
    end
    return db
end
-- Painted strokes per zone: {x, y (zone), r (yards), kind} (BV Routing's).
function P:Areas() self:Store();return G.Routing:Areas() end
function P:Strokes(mapID) self:Store();return G.Routing:Strokes(mapID) end

-- Transitions: {a = {mapID, x, y}, b = {...}, oneway, name} (BV Routing's).
function P:Links() self:Store();return G.Routing:Links() end
function P:AddLink(a,b,oneway,name) self:Store();return G.Routing:AddLink(a,b,oneway,name) end
function P:RemoveLink(index) G.Routing:RemoveLink(index) end
-- A search area (Florian 2026-10-09: "only the south of Silverpine", a
-- choice for this route, not a no-go area): {mapID, poly = {x1, y1, ...}}.
function P.InArea(area,zone,node)
    if not area or not area.poly or #area.poly<6 then return true end
    local x,y=node.x,node.y
    if zone~=area.mapID then
        x,y=Space.Convert(zone,area.mapID,x,y)
        if not x then return false end
    end
    return Space.Inside(area.poly,x,y)
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
function P.Key(kind,name,under) return kind..":"..name..(under and ":underground" or "") end
-- Old saved selections covered both layers when the global switch was on.
-- Copy on editor load; never rewrite the saved geometry or user's selection.
function P:Choices(route)
    local chosen={}
    for key,on in pairs(route.chosen or {}) do if on then
        chosen[key]=true
        if not route.selectionVersion and G:Config().routeUnderground and not key:find(":underground$",1) then
            chosen[key..":underground"]=true
        end
    end end
    return chosen
end
-- Underground only when asked; known spawns nobody has seen only with "Known spawns in routes".
local function usable(node,kind,zone)
    -- Explicit per-resource underground choices in the editor. The global
    -- option is only the initial selection for new routes (and the quick route).
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
                    local key=P.Key(t.id,label(t.id,node),node.under)
                    if not counts[key] then counts[key]={kind=t.id,name=label(t.id,node),under=node.under,count=0,unknown=0,key=key};out[#out+1]=counts[key] end
                    counts[key].count=counts[key].count+1
                    if not node.under and node.layer~="surface" then counts[key].unknown=counts[key].unknown+1 end
                end
            end
        end
    end
    local order={};for i,t in ipairs(G.TYPES) do order[t.id]=i end
    table.sort(out,function(a,b)
        if a.kind~=b.kind then return order[a.kind]<order[b.kind] end
        if a.count~=b.count then return a.count>b.count end
        return a.key<b.key
    end)
    return out
end
-- Chosen nodes on the space map as {x, y (space), X, Y (yards), kind, node, mapID}.
function P:Nodes(s,chosen,area)
    local out={}
    for _,t in ipairs(G.TYPES) do
        for _,zone in ipairs(s.zones) do
            for _,node in ipairs(G.Data:Nodes(t.id,zone) or {}) do
                if usable(node,t.id,zone) and chosen[P.Key(t.id,label(t.id,node),node.under)] and P.InArea(area,zone,node) then
                    local x,y=Space.ToSpace(s,zone,node.x,node.y)
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
-- The way between two stops for ordering them: the real one where it is measured (RoutePlanNav: the nearest
-- stops, then every step of the order), else the straight line.
-- How much a known spawn you never found counts for "worth the way".
P.KNOWN=.5
-- Real ways between neighbouring stops (P.Ways during a calculation):
-- where known they replace the estimate.
P.real=nil
local function way(a,b)
    local known=P.real and P.real[a] and P.real[a][b]
    if known then return known end
    -- (the navmesh planner's estimate from its precomputed zone costs, RoutePlanNav: P.est)
    local e=P.est and P.est[a] and P.est[a][b]
    if e then return e end
    return yards(a,b)
end
-- fits(a,b): may two nodes share a stop (beyond the radius)? On the navmesh: only where one is walked to from the
-- other in a straight line (Florian 2026-10-09: a node down in a ravine is not reached from its edge; it gets its own
-- stop down there).
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
        if i%60==0 and coroutine.running() then P.Yield() end
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
-- These tables belong to one calculation, never to the saved/finished route.
-- Cancellation stops the coroutine before BuildNav's normal cleanup runs.
function P.ClearWork()
    P.est,P.real,P.lastCut,P.passReach=nil,nil,nil,nil
    P.paths={}
end
-- Each stage of a calculation has a fixed part of the bar (P.Stage from..to); inside it the bar moves by a counter
-- that only grows (P.Step: work done of the stage's total), and the number shown never goes back, only up or
-- standing (Florian 2026-10-26: ordering the stops jumped between 40 and 41 %, every new tour of the ordering
-- started its part over). P.Begin starts a calculation at 0.
function P.Begin(text) P.ClearWork();P.progress.value=0;P.progress.text=text or "";P.stage=nil end
function P.Report(value,text)
    value=math.max(0,math.min(1,value))
    if value>P.progress.value then P.progress.value=value end
    if text then P.progress.text=text end
end
function P.Stage(from,to,text,total) P.stage={from=from,to=to,total=math.max(1,total or 1),done=0};P.Report(from,text) end
function P.Step(done,text)
    local st=P.stage
    if not st then if text then P.progress.text=text end return end
    P.Report(st.from+(st.to-st.from)*math.min(1,math.max(0,done)/st.total),text)
end
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
        P.Report(0,"Checking which stops are worth the way")
        local cut={}
        for m=best,best+bestLength-1 do cut[#cut+1]=at(m) end
        local gone={};for _,stop in ipairs(cut) do gone[stop]=true;removed[#removed+1]=stop end
        local kept={};for _,stop in ipairs(order) do if not gone[stop] then kept[#kept+1]=stop end end
        order=kept
        if coroutine.running() then P.Yield() end
    end
    return order,removed
end
-- For each stop the real way to its P.NEIGHBOURS nearest stops (RoutePlanNav: P.NavWays). A way further round than
-- the search to the neighbours goes is measured by itself; P.LOST times the farthest straight line is how far that
-- search goes past the first one reached. The stops' box and P.MARGIN yards round it: where the stops you can
-- reach are looked for (P.NavReachable).
P.NEIGHBOURS=6;P.LOST=3;P.MARGIN=400
P.paths={}
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
    -- (one tour is one unit of the stage's counter, P.stage.done; its 2-opt passes, at most 30, inside it)
    local st=P.stage
    local base=st and st.done or 0
    local improved,passes=true,0
    while improved and passes<30 do
        improved,passes=false,passes+1
        P.Step(base+passes/30,"Ordering the stops")
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
            if i%40==0 and coroutine.running() then P.Yield()
            -- (by the clock between: Claude 2026-10-25, one slice of the ordering ran 74-114 ms offline)
            elseif i%8==0 then P.Breathe() end
        end
        -- Or-opt: move a run of one to three stops between two others.
        for size=1,3 do
            for i=2,n-size do
                if i%8==0 then P.Breathe() end
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
            if coroutine.running() then P.Yield() end
        end
    end
    if st then st.done=base+1 end
    return order
end

-- The whole plan (runs as a coroutine, BV Routing's scheduler G.Scheduler.Run): zones, chosen keys,
-- options {loop, radius, start {mapID,x,y}}. Result: {points = {{mapID, x, y,
-- stop, count}}, length (yards), stops, skipped (in blocked areas),
-- detours, unreachable}.
function P:Build(zones,chosen,options)
    P.Begin("Reading the map")
    local s=Space.Space(zones)
    -- On BV Routing's navmesh (RoutePlanNav.lua). Without its data for the continent, or with BV Routing set to its
    -- classic planner, no route (Claude 2026-10-26, Florian: the grid is gone from Gather).
    local planner,why=self:Planner(s)
    P.lastPlanner,P.lastPlannerWhy=planner,why
    if planner~="navmesh" then
        G:Print("No route: "..tostring(why)..". Gather plans on BV Routing's navmesh.")
        P.Report(1,"No route")
        return nil
    end
    return self:BuildNav(s,zones,chosen,options)
end
-- Difficult spots (Florian 2026-10-09: "we will never know every map
-- perfectly; tell the player, who can paint a no-go area and calculate
-- again"). Along the route: runs over hard ground (geo.Hazard) at least
-- P.ISSUERUN yards long (any length for magma, enemies and high risk), legs
-- far longer than the straight line (a shortcut may exist: a transition),
-- legs without a way, and the stops left out. Close ones of a kind are one.
-- Each: {kind, mapID, x, y, yards}.
P.ISSUERUN={steep=24,swim=20,magma=0,enemy=0,risk=0}
-- Hard ground this close to a stop is the node's own rock; jumps are
-- already orange: neither counts as steep ground.
P.ISSUENEAR=15
P.DETOUR=3;P.DETOURYARDS=200;P.ISSUEMERGE=60
-- geo: what the issues and side trips ask the ground (RoutePlanNav's navGeo): Drops, Walkable, Hazard, HighDrop.
function P.Issues(s,result,spots,order,cut,loop,geo)
    local found={}
    local function add(kind,x,y,yards)
        for _,issue in ipairs(found) do
            if issue.kind==kind and Space.Yards(s,issue.sx,issue.sy,x,y)<P.ISSUEMERGE then
                issue.yards=(issue.yards or 0)+(yards or 0);return
            end
        end
        found[#found+1]={kind=kind,sx=x,sy=y,yards=yards}
    end
    local points=result.points
    local n=#points
    -- Drops higher than "Short drops" allows (no way round them was found).
    local mode=G.Routing:Config().cliffs
    if mode~="always" then
        for j=2,n do
            local a,b=spots[j-1],spots[j]
            if a and b and points[j].drop and not points[j].gap then
                local fall=geo.HighDrop(s,a[1],a[2],b[1],b[2])
                if fall then add("highdrop",b[1],b[2],fall) end
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
            local yards=Space.Yards(s,a[1],a[2],b[1],b[2])
            local stopA=points[j-1] and points[j-1].stop or (j==1 and points[n].stop)
            local stopB=points[j].stop
            local steps=math.max(1,math.ceil(yards/(Space.CELL/2)))
            for i=1,steps do
                local px,py=a[1]+(b[1]-a[1])*i/steps,a[2]+(b[2]-a[2])*i/steps
                local kind=geo.Hazard(s,px,py)
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
        if j%200==0 and coroutine.running() then P.Yield() end
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
                way=way+Space.Yards(s,spots[q][1],spots[q][2],spots[nq][1],spots[nq][2])
                q=nq
            end
            local straight=Space.Yards(s,spots[i][1],spots[i][2],spots[j][1],spots[j][2])
            if way and way>straight*P.DETOUR and way-straight>P.DETOURYARDS then
                add("detour",(spots[i][1]+spots[j][1])/2,(spots[i][2]+spots[j][2])/2,way-straight)
            end
        end
    end
    for _,stop in ipairs(cut or {}) do add("cut",stop.x,stop.y,#stop.nodes) end
    local issues={}
    for _,issue in ipairs(found) do
        local mapID,x,y=Space.FromSpace(s,issue.sx,issue.sy)
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
function P.Spurs(s,result,spots,geo)
    local seq={}
    for i,point in ipairs(result.points) do seq[i]={spots[i][1],spots[i][2],point} end
    local function yd(a,b) return Space.Yards(s,a[1],a[2],b[1],b[2]) end
    local function length(list) local l=0;for q=2,#list do l=l+yd(list[q-1],list[q]) end;return l end
    local function back(list)
        for q=1,#list-1 do
            local a,b=list[q],list[q+1]
            if b[3].gap or b[3].link or geo.Drops(s,a[1],a[2],b[1],b[2]) or not geo.Walkable(s,b[1],b[2],a[1],a[2]) then return false end
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
                        if (near or crossed) and (near and yd(seq[i],seq[o])<.5 or geo.Walkable(s,seq[i][1],seq[i][2],seq[o][1],seq[o][2])) then i0,o0=i,o end
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
                    local mapID,zx,zy=Space.FromSpace(s,x,y)
                    -- (the pieces to the new tip walkable on their own: on the navmesh a piece of a line is not always
                    -- a line on the graph; Claude 2026-10-26)
                    local before,after=seq[k-q],seq[k+q]
                    if mapID and before and after and not (geo.Walkable(s,before[1],before[2],x,y) and geo.Walkable(s,x,y,after[1],after[2])) then mapID=nil end
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
        if k%50==0 and coroutine.running() then P.Yield() end
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
    local copy={zones={},chosen={},points={},selectionVersion=route.selectionVersion,loop=route.loop and true or false,radius=route.radius,length=route.length,goal=route.goal,sight=route.sight}
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
local KINDS={nogo=true,prefer=true,risk=true,swim=true}
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

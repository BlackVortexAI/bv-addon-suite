local _,G=...
if not G.ready then return end
-- Gathering routes on BV Routing's navmesh (Claude 2026-10-25, prototype; Florian: the old grid planner is to be
-- replaced entirely, and Gather was its last user). The same plan as P:Build (stops, the stops you can reach, the
-- real ways to the nearest stops, the shortest order, worth the way, side trips, difficult spots), measured on the
-- navmesh graph (Routing.Hpa) instead of the grid and the terrain data:
--   * a node's place is a navmesh node (its cell's layer; underground nodes the layer apart from the terrain's);
--     nodes share a stop only where the straight line between them is walkable on the graph (a node down in a
--     ravine or in a cave below is not reached from above: the grid compared heights for that, P.LEVEL);
--   * the stops you can reach: the abstract graph's components round them (H.RegionComponents), each stop joined to it
--     by a flood to the nearest entrance (H.Entrance);
--   * the real ways to the P.NEIGHBOURS nearest stops: one search from each stop to all of them (H.FindMany);
--   * each leg of the order: straight where the line is clear (H.Line), else found on the cells of the clusters
--     round the abstract way (H.Find, corridor 0, then 1) and pulled tight (H.Pull);
--   * your own painted areas and your walked ways: BV Routing's overlay of the continent (HpaOverlay.lua).
-- Drops down a cliff are the navmesh data's one-way jumps (tools/hpa/hierarchy.py drops_of; Routing's "Down cliffs");
-- curves (options.smooth) cut corners where the line stays clear. Not on the navmesh: Route Studio's levels (the
-- navmesh's own layers stand in for them).
local Space=G.Space
local P=G.Plan
local floor,min,max,sqrt,huge=math.floor,math.min,math.max,math.sqrt,math.huge
local function clock() local f=rawget(_G,"debugprofilestop");return f and f() or 0 end
local function hpa() return G.Routing and G.Routing.Hpa end
local NOGO,PREFER,RISK,ENEMY,WALL,SWIM=1,2,3,4,5,6
P.NAVENTRANCE=12000   -- nodes a stop's flood to the nearest entrance looks at, at most
P.NAVCORRIDOR=nil     -- the legs refined inside the abstract way's clusters (0: the best way in them, slower)
P.NAVSNAP=2           -- cells round a stop off its group where a layer of the group is looked for
P.NAVSLACKMIN=200   -- cost yards the search to the neighbours goes on past the first one reached, at least

-- "navmesh" for a space, or nil and why not.
function P:Planner(s)
    local H=hpa()
    if not (H and H.SetOverlay) then return nil,"no navmesh planner" end
    -- (the space is a continent's map when its zones share one; the navmesh data is per continent)
    local cont=s and s.mapID
    if not cont then return nil,"no space" end
    local missing=H:Missing(cont)
    if missing then return nil,missing end
    if not H:Active(cont) then return nil,"navmesh not active" end
    return "navmesh"
end

---------------------------------------------------------------- points and nodes
-- The navmesh cell of a space point (the space is the continent's map).
local function cellAt(H,x,y)
    local g=H.geo
    local cx,cy=floor((x-g.minX)*g.width/H.cell),floor((y-g.minY)*g.height/H.cell)
    if cx<0 or cy<0 or cx>=H.cols or cy>=H.rows then return nil end
    return cy*H.cols+cx,cx,cy
end
-- A node's navmesh node: its cell's walkable layers (or the nearest walkable cell within 3); with the spawn's height
-- (known spawns, BV Gather Data: z in world yards) the layers within H.ZTRY of it, nearest first; without one,
-- underground the first layer apart from the terrain's.
function P.NavNode(H,x,y,under,z)
    local list=H.Nodes(x,y,z)
    if z then return list[1] end
    if under then
        for _,n in ipairs(list) do
            local c=H.classes[H.ClassOf(n)]
            if c and c[3]==0 then return n end
        end
    end
    return list[1]
end
-- Walkable on the graph between two space points (any of their cells' layers).
local function walkable(H,x1,y1,x2,y2)
    local A,B=H.Nodes(x1,y1,nil),H.Nodes(x2,y2,nil)
    for i=1,min(3,#A) do for j=1,min(3,#B) do if H.LineAny(A[i],B[j]) then return true end end end
    return false
end
P.NavWalkable=walkable
-- What the issues and side trips ask the ground, on the navmesh.
local function navGeo(H,fallAt)
    local cfg=G.Routing:Config()
    return {
        -- a drop down a cliff leads to that place (BuildNav: the route's drops)
        Drops=function(_,_,_,x2,y2) return fallAt~=nil and fallAt[x2..":"..y2]~=nil end,
        Walkable=function(_,x1,y1,x2,y2) return walkable(H,x1,y1,x2,y2) end,
        -- further than "Down cliffs: safe" allows (H.SAFEDROP)
        HighDrop=function(_,_,_,x2,y2)
            local fall=fallAt and fallAt[x2..":"..y2]
            if fall and fall>H.SAFEDROP then return fall end
        end,
        -- on the node's class (its paint and terrain code)
        Hazard=function(_,px,py)
            local n=H.Nodes(px,py,nil)[1]
            local c=n and H.classes[H.ClassOf(n)]
            if not c then return nil end
            local paint,code=H.SidePaint(c[1]),c[4]
            if paint==PREFER then return nil end
            if paint==RISK then return "risk" end
            if paint==ENEMY then return "enemy" end
            if paint==SWIM then return cfg.avoidWater and "swim" or nil end
            if code==nil or code==255 then return nil end
            local water=floor(code/4)%4
            if water==3 then return "magma" end
            if water==2 and cfg.avoidWater then return "swim" end
            if water==0 and code%4==3 then return "steep" end
            return nil
        end,
    }
end
P.NavGeo=navGeo

---------------------------------------------------------------- the plan
local function yards(a,b) local dx,dy=a.X-b.X,a.Y-b.Y;return sqrt(dx*dx+dy*dy) end
local function polyYards(s,pts)
    local total=0
    for k=2,#pts do total=total+Space.Yards(s,pts[k-1][1],pts[k-1][2],pts[k][1],pts[k][2]) end
    return total
end
-- Does node b follow node a on the graph (a step or a jump)?
local function follows(H,a,b)
    if a==b then return true end
    local ok=false
    H.Each(a,function(v) if v==b then ok=true end end)
    if ok then return true end
    local js=H.jumpFrom[a]
    if type(js)=="number" then js={js} end
    for _,j in ipairs(js or {}) do if H.JumpTo(j)==b then return true end end
    js=H.jumpTo[a]
    if type(js)=="number" then js={js} end
    for _,j in ipairs(js or {}) do if H.JumpFrom(j)==b then return true end end
    return false
end
local function chainOk(H,nodes)
    for i=2,#nodes do
        if not H.Cost(nodes[i]) or not follows(H,nodes[i-1],nodes[i]) then return false end
    end
    return true
end
-- A leg between two stops: nil straight (the line is clear), false no way, else its points and pulled nodes.
function P.NavLeg(H,a,b,stats)
    if a.hn==b.hn or H.Line(a.hn,b.hn) then return nil end
    local t0=clock()
    -- The abstract way refined inside its own clusters (corridor nil: cheapest); where that is not a way on the cells
    -- (painting over an entrance: the overlay), the best way inside the clusters it touches, then a ring wider.
    local nodes=H.Find(a.hn,b.hn,P.NAVCORRIDOR,false)
    for _,corridor in ipairs({0,1}) do
        if not nodes or chainOk(H,nodes) then break end
        if stats then stats.wider=(stats.wider or 0)+1 end
        nodes=H.Find(a.hn,b.hn,corridor,false)
    end
    if nodes and not chainOk(H,nodes) then nodes=nil end
    if not nodes then if stats then stats.legMs=(stats.legMs or 0)+clock()-t0 end;return false end
    local pulled=H.Pull(nodes)
    local jumps={}
    for i=2,#pulled do
        local js=H.jumpFrom[pulled[i-1]]
        if type(js)=="number" then js={js} end
        for _,j in ipairs(js or {}) do if H.JumpTo(j)==pulled[i] then jumps[i]=j end end
    end
    local pts=H.Points(pulled,jumps,a.x,a.y,b.x,b.y)
    -- The drops down a cliff: {[point index]=fall}, at the point each leads to (H.Points: a stored walk's shape before
    -- its node; the last node is the leg's end).
    local drops
    local idx=1
    for i=2,#pulled do
        local j=jumps[i]
        if i<#pulled then
            if j and H.JumpNet(j) then idx=idx+#(H.JumpPoints(j) or {}) end
            idx=idx+1
        else idx=#pts end
        if j and H.JumpDrop(j) then drops=drops or {};drops[idx]=H.JumpFall(j) end
    end
    if stats then stats.legMs=(stats.legMs or 0)+clock()-t0;stats.legNodes=(stats.legNodes or 0)+#nodes end
    return pts,pulled,drops
end

-- Optional curves on the navmesh (as P.Smooth on the grid, Florian 2026-10-08: only when wanted): each corner cut
-- (Chaikin), twice; a cut whose new pieces are no clear lines on the graph (H.Line: no dearer node crossed) keeps
-- that corner.
function P.NavSmooth(H,path)
    if #path<3 then return path end
    local function clear(p,q)
        local A,B=H.Nodes(p[1],p[2],nil),H.Nodes(q[1],q[2],nil)
        for i=1,min(2,#A) do for j=1,min(2,#B) do if H.Line(A[i],B[j]) then return true end end end
        return false
    end
    local points=path
    for _=1,2 do
        local out={points[1]}
        for i=2,#points-1 do
            local a,b,c=points[i-1],points[i],points[i+1]
            local p1={b[1]+(a[1]-b[1])*.25,b[2]+(a[2]-b[2])*.25}
            local p2={b[1]+(c[1]-b[1])*.25,b[2]+(c[2]-b[2])*.25}
            -- (all three new pieces: from the last point kept, the cut, on to the next corner)
            if clear(out[#out],p1) and clear(p1,p2) and clear(p2,c) then out[#out+1]=p1;out[#out+1]=p2 else out[#out+1]=b end
        end
        out[#out+1]=points[#points]
        points=out
    end
    return points
end
-- Stops passed by (Florian 2026-10-26, Durotar in game: the route made a little hook round a rock right up to the
-- node, where it could have been gathered on the way past): a stop's nodes are gathered from the route where it
-- passes within P.GATHERREACH yards of each of them, seen from there (H.Line clear from the route's place to the node:
-- the same surface, no wall between; a node behind a long wall is no node passed by, whatever the distance). Round each
-- stop the places before and after it along the way (P.PASSCUTS yards) are tried, the farthest pair first: a straight
-- piece between them clear on the graph that passes within reach of every node of the stop replaces the way through
-- the stop; the stop's mark goes onto that piece, where it comes nearest to the nodes. Returns how many.
-- (7 yd: Florian's Thunder Ridge stop 2026-10-26 was 6.6 yd from the way past it and he gathers such nodes in passing;
-- the herb or vein itself is a yard or two wide)
P.GATHERREACH=7
-- A hook to a stop no longer than this one way (twice it there and back) is left out whether its nodes are seen from
-- the way or not (Florian 2026-10-26, NavDurotar4/5 north-east of Razor Hill: a 14-yd hook into a pile of rocks to a
-- node beside the way; "a hook under ~15 yd is in passing in practice, you walk the few steps") - within the pass-by
-- radius still.
P.SHORTHOOK=15
-- How near the way must pass a stop's nodes (Claude 2026-10-26, Florian's NavDurotar3: 24 of its 81 hooks went to stops
-- whose nodes lay seen 7-45 yd beside the way, hooks into the open): the pass-by radius, at least GATHERREACH - from
-- the way you see and reach them as from the stop, which stands for its nodes within that radius. Not "within sight"
-- (its stops stand for what you see from afar).
function P.PassReach(options,sight)
    if sight then return P.GATHERREACH end
    return math.max(P.GATHERREACH,tonumber(options and options.radius) or 0)
end
local function nodeAt(H,x,y,z) return H.Nodes(x,y,z)[1] end
-- The point of piece a-b nearest to p (space x, y), and its yards from p.
local function nearestOn(s,a,b,p)
    local ax,ay=a[1]*s.width,a[2]*s.height
    local dx,dy=b[1]*s.width-ax,b[2]*s.height-ay
    local L=dx*dx+dy*dy
    local px,py=p[1]*s.width,p[2]*s.height
    local t=L>0 and math.max(0,math.min(1,((px-ax)*dx+(py-ay)*dy)/L)) or 0
    local cx,cy=ax+dx*t,ay+dy*t
    return {cx/s.width,cy/s.height},sqrt((cx-px)^2+(cy-py)^2)
end
-- Does the piece a-b pass every node of the stop within reach, seen from it? Returns the mark's place or nil.
-- na, nb: the nodes at a and b (given: the mark's pieces to them are checked as well).
local function clear(H,u,v) return u and v and (u==v or H.Line(u,v)) end
function P.PassesBy(H,s,a,b,nodes,na,nb,blind)
    local mark,best
    for _,node in ipairs(nodes) do
        local c,d=nearestOn(s,a,b,{node.x,node.y})
        if d>(P.passReach or P.GATHERREACH) then return nil end
        -- (seen: the line to the node on the graph at any cost, H.LineAny - a node on a rock's steep foot is gathered
        -- from beside it; Claude 2026-10-26, Florian's Thunder Ridge stop: the line at the way's costs ended at the
        -- slope 6 yd short of it, and the way made a hook round the rock)
        -- (any layer of the place: the node's height picks the layer of the node, not of the place it is seen from -
        -- at Thunder Ridge a rock's top over the place had the node's height, the ground beside it the sight)
        local seen=false
        if node.hn then
            for _,cn in ipairs(H.Nodes(c[1],c[2],nil)) do
                if not seen and (cn==node.hn or H.LineAny(cn,node.hn)) then seen=true end
            end
        end
        if not seen and not blind then return nil end
        if not best or d<best then mark,best=c,d end
    end
    -- (the two pieces the mark splits the piece into: clear on their own too)
    if mark and na then
        local mn=nodeAt(H,mark[1],mark[2])
        if not (clear(H,na,mn) and clear(H,mn,nb)) then return nil end
    end
    return mark
end
-- Places along the way from point k backwards (step -1) or forwards (+1), PASSCUTS yards from it as far as the way
-- goes without passing another stop, a gap or a drop: {x, y, the index of the point beyond it, yards from k}.
-- (out to 120 yd: the Thunder Ridge stop's hook round the rock was 108 yd, 54 each way; up to 40 never reached
-- back to the way past it)
P.PASSCUTS={120,90,70,55,40,30,20,14,9,6}
local function cutsFrom(s,pts,spots,k,step)
    local out={}
    local along,i=0,k
    local own=0
    while true do
        local r=i+step
        if r<1 or r>#pts then break end
        if step<0 and (pts[i].gap or pts[i].drop) then break end
        if step>0 and (pts[r].gap or pts[r].drop) then break end
        local a,b=spots[i],spots[r]
        local seg=Space.Yards(s,a[1],a[2],b[1],b[2])
        -- (the cuts from the nearest out: PASSCUTS is from the farthest in)
        for c=#P.PASSCUTS,1,-1 do
            local d=P.PASSCUTS[c]
            if d>along and d<=along+seg and not out[c] then
                local t=(d-along)/math.max(1e-6,seg)
                out[c]={a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,r,d}
            end
        end
        along=along+seg
        if along>=P.PASSCUTS[1] or pts[r].stop then break end
        -- (the way's own points too: a hook's corner may be the one place the node is seen from; Thunder Ridge)
        own=own+1;out[#P.PASSCUTS+own]={b[1],b[2],r,along}
        i=r
    end
    return out
end
-- A short spike to a stop - the way goes out to it and back the same way, no more than SHORTHOOK yards out - is left out
-- when every node of the stop lies within the pass-by radius of where the spike leaves the way: the stop's mark goes
-- there (Florian 2026-10-26, NavDurotar5 north-east of Razor Hill: 14 yd out to the edge of a pile of rocks and back,
-- the node behind it; neither seen from the way nor on a straight piece past it, so no pass-by took it). Returns how
-- many; the points and the length changed in place.
function P.TrimSpikes(H,s,result,spots,nodesOf)
    local pts=result.points
    local trimmed=0
    local reach=P.passReach or P.GATHERREACH
    -- (again while one goes: a spike's base may itself be the tip of a shorter one)
    local again=true
    while again do
    again=false
    local q=2
    while q<#pts do
        local p=pts[q]
        local nodes=p.stop and nodesOf[p]
        if nodes then
            -- outwards from the stop while both sides walk back over the same ground
            local i,j=q-1,q+1
            -- (points on the stop's own spot - a cut and the mark of a pass-by that ended at the tip - are part of it)
            local function at(k) return Space.Yards(s,spots[k][1],spots[k][2],spots[q][1],spots[q][2])<=.5 end
            while i>1 and at(i) do i=i-1 end
            while j<#pts and at(j) do j=j+1 end
            local out=Space.Yards(s,spots[i][1],spots[i][2],spots[q][1],spots[q][2])
            while i>1 and j<#pts and Space.Yards(s,spots[i-1][1],spots[i-1][2],spots[j+1][1],spots[j+1][2])<=1 and not pts[i-1].stop and not pts[j+1].stop
                and out+Space.Yards(s,spots[i-1][1],spots[i-1][2],spots[i][1],spots[i][2])<=P.SHORTHOOK do
                out=out+Space.Yards(s,spots[i-1][1],spots[i-1][2],spots[i][1],spots[i][2])
                i,j=i-1,j+1
            end
            -- (the way past: from where the spike leaves to where it comes back, the same point or a straight piece
            -- walkable between them; the stop's mark on it, nearest the stop)
            local base=spots[i]
            local twin=Space.Yards(s,base[1],base[2],spots[j][1],spots[j][2])
            local spike=out<=P.SHORTHOOK and out>=1
            if spike and twin>1 then
                local back=Space.Yards(s,spots[q][1],spots[q][2],spots[j][1],spots[j][2])
                spike=twin<out+back and clear(H,nodeAt(H,base[1],base[2]),nodeAt(H,spots[j][1],spots[j][2]))
                if spike then base=nearestOn(s,base,spots[j],spots[q]) end
            end
            -- (a trim that leaves out no point is none: the stop would only move)
            if spike and (q-i-1)+(j-q-1)+(twin<=1 and 1 or 0)<1 then spike=false end
            if spike then
                for _,node in ipairs(nodes) do
                    if Space.Yards(s,base[1],base[2],node.x,node.y)>reach then spike=false;break end
                end
            end
            if spike then
                -- the stop onto the base; the spike's points out
                local mapID,zx,zy=Space.FromSpace(s,base[1],base[2])
                p.mapID,p.x,p.y=mapID,zx,zy
                p.passedBy=true
                -- (out: the points between the base and the stop and between the stop and its twin; a twin on the
                -- base's spot too: the stop takes its place)
                for _=i+1,q-1 do table.remove(pts,i+1);table.remove(spots,i+1) end
                local stopAt=i+1
                spots[stopAt]={base[1],base[2]}
                local drop=j-q-1
                if twin<=1 then drop=drop+1 end
                for _=1,drop do table.remove(pts,stopAt+1);table.remove(spots,stopAt+1) end
                trimmed=trimmed+1
                again=true
                q=stopAt+1
            else q=q+1 end
        else q=q+1 end
    end
    end
    if trimmed>0 then
        local total=0
        for k=2,#spots do total=total+Space.Yards(s,spots[k-1][1],spots[k-1][2],spots[k][1],spots[k][2]) end
        if result.loop and #spots>2 then total=total+Space.Yards(s,spots[#spots][1],spots[#spots][2],spots[1][1],spots[1][2]) end
        result.length=total
    end
    return trimmed
end
function P.NavPassBy(H,s,result,spots,stopOf)
    local pts=result.points
    local passed=0
    -- per stop passed by: {cut before (x, y, first point dropped), cut after (x, y, first point kept), mark}
    local plan={}
    for k=2,#pts-1 do
        local stop=stopOf[k]
        if stop and not pts[k].gap and not pts[k].drop and not (pts[k+1] and (pts[k+1].gap or pts[k+1].drop)) then
            local nodes={}
            for _,node in ipairs(stop.nodes) do
                local nd=node.node
                nodes[#nodes+1]={x=node.x,y=node.y,hn=node.hn,z=nd and (nd.z or (nd.from and nd.from.z))}
            end
            local before,after=cutsFrom(s,pts,spots,k,-1),cutsFrom(s,pts,spots,k,1)
            -- each cut on its node's place (the line checked is the line drawn), the piece from the point kept beyond
            -- it clear; false where not. Only the cuts of pairs that pass the nodes on the map are snapped (Claude
            -- 2026-10-26: snapping every cut of every stop cost 25 MB and half a second on a route of 140 stops).
            local snapped={}
            local function snap(cut)
                local v=snapped[cut]
                if v~=nil then return v or nil end
                local n=nodeAt(H,cut[1],cut[2])
                local keep=spots[cut[3]]
                v=false
                if n and clear(H,nodeAt(H,keep[1],keep[2]),n) then
                    local x,y=H.Point(n)
                    v={x,y,cut[3],cut[4],n}
                end
                snapped[cut]=v
                return v or nil
            end
            -- (within reach on the map, the snap's few yards allowed for)
            local function near(a,b,slack,list)
                for _,node in ipairs(list or nodes) do
                    local _,d=nearestOn(s,a,b,{node.x,node.y})
                    if d>(P.passReach or P.GATHERREACH)+slack then return false end
                end
                return true
            end
            local best
            if next(before) and next(after) then
                local cand={}
                -- (only cuts after the piece of the stop passed by just before: its cut after is where this one may begin;
                -- Claude 2026-10-26, NavDurotar4: 46 stops were left with their hooks because the best pair of the next
                -- one began inside that piece)
                local from=plan.last or 0
                for _,a in pairs(before) do
                    if a[3]>=from then
                        for _,b in pairs(after) do
                            if near(a,b,H.cell) then cand[#cand+1]={a,b,a[4]+b[4]-Space.Yards(s,a[1],a[2],b[1],b[2])} end
                        end
                    end
                end
                table.sort(cand,function(p,q) return p[3]>q[3] end)
                for _,c in ipairs(cand) do
                    if c[3]<=.5 then break end
                    local a,b=snap(c[1]),snap(c[2])
                    if a and b and near(a,b,0) and clear(H,a[5],b[5]) then
                        local mark=P.PassesBy(H,s,a,b,nodes,a[5],b[5],c[3]<=2*P.SHORTHOOK)
                        if mark then best={a,b,mark,nodes=nodes,members={{k,nodes}}};break end
                    end
                end
                -- Close behind the stop passed by just before (no cut between): both on one piece, from that one's cut
                -- before to a cut after this one, if it passes all their nodes (NavDurotar4: 39 such stops).
                local prev=not best and plan.lastK and plan[plan.lastK]
                if prev then
                    local all={}
                    for _,n in ipairs(prev.nodes) do all[#all+1]=n end
                    for _,n in ipairs(nodes) do all[#all+1]=n end
                    local list={}
                    for _,b in pairs(after) do list[#list+1]=b end
                    table.sort(list,function(p,q) return p[4]>q[4] end)
                    local a=prev[1]
                    for _,c in ipairs(list) do
                        if near(a,c,H.cell,all) then
                            local b=snap(c)
                            if b and near(a,b,0,all) and clear(H,a[5],b[5]) then
                                -- (every stop on the piece its own mark on the new one)
                                local marks={}
                                local members={}
                                for _,mb in ipairs(prev.members) do members[#members+1]=mb end
                                members[#members+1]={k,nodes}
                                for i,mb in ipairs(members) do
                                    local mk=P.PassesBy(H,s,a,b,mb[2],a[5],b[5])
                                    if not mk then marks=nil;break end
                                    marks[i]=mk
                                end
                                if marks then
                                    prev[2],prev[3]=b,marks[1]
                                    prev.nodes,prev.members=all,members
                                    prev.more={}
                                    for i=2,#members do prev.more[#prev.more+1]={members[i][1],marks[i]} end
                                    plan.last=b[3]
                                    passed=passed+1
                                    break
                                end
                            end
                        end
                    end
                end
            end
            -- (not past a stop already passed by just before)
            if best and not (plan.last and best[1][3]<plan.last) then
                plan[k]=best
                plan.last,plan.lastK=best[2][3],k
                passed=passed+1
            end
        end
        if stop then P.Breathe() end
    end
    -- (the stops' nodes by their points: the short spikes below)
    local nodesOf={}
    for k=1,#pts do local st=stopOf[k];if st then nodesOf[pts[k]]=st.nodes end end
    if passed==0 then return P.TrimSpikes(H,s,result,spots,nodesOf) end
    -- the route again: up to the cut before, the cut, the stop's mark, the cut after, on from the point after it
    local np,ns={},{}
    local function put(point,spot) np[#np+1]=point;ns[#ns+1]=spot end
    local function at(x,y)
        local mapID,zx,zy=Space.FromSpace(s,x,y)
        return {mapID=mapID,x=zx,y=zy}
    end
    local i=1
    while i<=#pts do
        local nextPlan
        for k=i,#pts do if plan[k] then nextPlan=k;break end end
        if nextPlan and plan[nextPlan][1][3]==i then
            local cut=plan[nextPlan]
            local a,b,mark=cut[1],cut[2],cut[3]
            -- (the point beyond the cut stays: the points after it up to the cut after are left out)
            put(pts[i],spots[i])
            put(at(a[1],a[2]),{a[1],a[2]})
            -- (the stop's mark, and those of the stops passed by on the same piece after it: in their order along it)
            local marks={{pts[nextPlan],mark}}
            for _,more in ipairs(cut.more or {}) do marks[#marks+1]={pts[more[1]],more[2]} end
            table.sort(marks,function(p,q) return Space.Yards(s,a[1],a[2],p[2][1],p[2][2])<Space.Yards(s,a[1],a[2],q[2][1],q[2][2]) end)
            for _,mk in ipairs(marks) do
                local stop,mm=mk[1],at(mk[2][1],mk[2][2])
                stop.mapID,stop.x,stop.y=mm.mapID,mm.x,mm.y
                stop.passedBy=true
                put(stop,{mk[2][1],mk[2][2]})
            end
            put(at(b[1],b[2]),{b[1],b[2]})
            i=b[3]
        else
            put(pts[i],spots[i])
            i=i+1
        end
    end
    for q=1,#np do pts[q]=np[q];spots[q]=ns[q] end
    for q=#np+1,#pts do pts[q]=nil;spots[q]=nil end
    local total=0
    for q=2,#ns do total=total+Space.Yards(s,ns[q-1][1],ns[q-1][2],ns[q][1],ns[q][2]) end
    if result.loop and #ns>2 then total=total+Space.Yards(s,ns[#ns][1],ns[#ns][2],ns[1][1],ns[1][2]) end
    result.length=total
    return passed+P.TrimSpikes(H,s,result,spots,nodesOf)
end
function P:BuildNav(s,zones,chosen,options)
    local H=hpa()
    local stats={planner="navmesh",cont=s.mapID}
    local t0=clock()
    self:Store()
    H:Use(s.mapID)
    -- Your painting and walked ways laid over the navmesh (BV Routing keeps them with the continent: built again only
    -- when they changed).
    P.Report(.01,"Laying your painting over the map")
    local o,ov=H:RefreshOverlay(s.mapID)
    H:Costs()
    stats.overlay=ov or {strokes=0,painted=0,walked=0}
    if o then stats.overlayNodes,stats.overlayDirty,stats.overlayMs=o.nodes,o.dirty,o.ms end
    local nodes=self:Nodes(s,chosen,options.area)
    -- Nodes on enemy ground stay out unless enemies are ignored (Florian 2026-10-09: a Horde route led into Southshore
    -- for its herbs): the other side's places of the navmesh classes (H.SidePaint, every layer of the node's cell).
    local enemy=0
    if G.Routing:Config().enemy~="ignore" then
        local kept={}
        for i,node in ipairs(nodes) do
            local hostile=false
            local cell=cellAt(H,node.x,node.y)
            if cell then
                for _,n in ipairs(H.CellNodes(cell)) do
                    local c=H.classes[H.ClassOf(n)]
                    if c and H.SidePaint(c[1])==ENEMY then hostile=true end
                end
            end
            if hostile then enemy=enemy+1 else kept[#kept+1]=node end
            if i%64==0 then P.Breathe() end
        end
        nodes=kept
    end
    local sight=options.goal=="sight"
    local offmesh=0
    -- (layered: a node's cell has more than one walkable layer, and the node no height to tell which; counted)
    stats.layered=0
    for i,node in ipairs(nodes) do
        local nd=node.node
        local z=nd and (nd.z or (nd.from and nd.from.z))
        if z then stats.withZ=(stats.withZ or 0)+1 end
        node.hn=P.NavNode(H,node.x,node.y,nd and nd.under,z)
        local cell=cellAt(H,node.x,node.y)
        if cell then
            local walk=0
            for _,n in ipairs(H.CellNodes(cell)) do if H.Cost(n) then walk=walk+1 end end
            if walk>1 then stats.layered=stats.layered+1 end
        end
        if i%32==0 then P.Breathe() end
    end
    -- Nodes share a stop only where one is walked to from the other in a straight line (not within sight: there
    -- seeing is enough).
    local fits
    if not sight then fits=function(a,b) return not (a.hn and b.hn) or a.hn==b.hn or H.LineAny(a.hn,b.hn) end end
    local t1=clock()
    local stops=P.Cluster(nodes,sight and (options.sight or 150) or options.radius or 30,fits)
    stats.clusterMs=clock()-t1
    local open,skipped={},0
    for i,stop in ipairs(stops) do
        if i%16==0 then P.Breathe() end
        stop.x,stop.y=stop.X/s.width,stop.Y/s.height
        -- The stop's node: a layer at its middle walked to in a straight line from its member nearest the middle,
        -- else the stop moves onto that member.
        local nearest,nd
        for _,node in ipairs(stop.nodes) do
            if node.hn then local d=yards(stop,node);if not nd or d<nd then nearest,nd=node,d end end
        end
        local cell=cellAt(H,stop.x,stop.y)
        -- (painted over: no-go or blocked high risk on every layer of its cell, shipped or yours; P:Build leaves such
        -- stops out)
        local blocked=false
        if cell then
            local painted,walk=false,false
            for _,n in ipairs(H.CellNodes(cell)) do
                local c=H.classes[H.ClassOf(n)]
                if c and H.SidePaint(c[1])~=0 then painted=true end
                if H.Cost(n) then walk=true end
            end
            blocked=painted and not walk
        end
        if blocked then skipped=skipped+#stop.nodes
        elseif not nearest then offmesh=offmesh+#stop.nodes;skipped=skipped+#stop.nodes
        else
            for _,n in ipairs(H.Nodes(stop.x,stop.y,nil)) do
                if not stop.hn and (n==nearest.hn or H.LineAny(n,nearest.hn)) then stop.hn=n end
            end
            if not stop.hn then
                stop.hn=nearest.hn
                stop.X,stop.Y,stop.x,stop.y=nearest.X,nearest.Y,nearest.x,nearest.y
            end
            -- (a node of another cell, the nearest walkable one where the stop's own has none: the stop moves onto it,
            -- else the way would end with a straight piece from there across what is not walkable; Claude 2026-10-26,
            -- Durotar copper)
            local here=cellAt(H,stop.x,stop.y)
            if here and H.CellOf(stop.hn)~=here then
                stop.x,stop.y=H.Point(stop.hn)
                stop.X,stop.Y=stop.x*s.width,stop.y*s.height
            end
            open[#open+1]=stop
        end
    end
    local start
    if options.start then
        local x,y=Space.ToSpace(s,options.start.mapID,options.start.x,options.start.y)
        -- Player position is only a hint for where to begin visiting the
        -- resources. No approach from the player's floor is part of this route.
        if x then start={X=x*s.width,Y=y*s.height,x=x,y=y} end
    end
    P.Report(.05,"Finding the stops you can reach")
    local cut
    t1=clock()
    open,cut=P.NavReachable(s,H,open)
    stats.reachMs=clock()-t1
    P.lastCut=cut
    local cutoff=0;for _,stop in ipairs(cut) do cutoff=cutoff+#stop.nodes end
    t1=clock()
    P.NavWays(s,H,open,stats)
    stats.waysMs=clock()-t1
    P.Stage(.4,.5,"Ordering the stops",P.NAVORDERROUNDS*((options.loop and #open>=8) and P.RESTARTS or 1))
    t1=clock()
    -- The order on the measured ways; a step of it between two stops never measured (no neighbours of each other: the
    -- straight line was its estimate) measured now and the order made again, until every step is measured (Claude
    -- 2026-10-26, Florian's look at Durotar copper: straight estimates across ravines and mountains gave long
    -- crossings of the whole zone).
    local order,removed
    stats.measuredLater=0
    -- Pairs never measured: the zone's precomputed costs between clusters (Hpa.ZoneCost, Data/NavZones; Claude
    -- 2026-10-26, Florian's NavDurotar3: straight lines across rocks ordered corridors to be walked twice), else the
    -- straight line. Per stop its zone's table (its nodes' zone).
    local tables={}
    local function tableOf(stop)
        local node=stop.nodes and stop.nodes[1]
        local z=node and node.mapID
        if not z then return nil end
        local v=tables[z]
        if v==nil then v=H.ZoneTable and H.ZoneTable(H.cont,z) or false;tables[z]=v end
        return v or nil
    end
    local estimated=0
    P.est={}
    local rep={}
    for i,a in ipairs(open) do
        local t=tableOf(a)
        if t and a.hn then rep[a]=H.ZoneRep(t,a.hn) end
        if i%16==0 then P.Breathe() end
    end
    for i,a in ipairs(open) do
        local t=tableOf(a)
        local row=P.est[a] or {};P.est[a]=row
        if t and rep[a] then
            for j=i+1,#open do
                local b=open[j]
                if rep[b] and tableOf(b)==t then
                    local e=H.ZoneCost(t,rep[a],rep[b],a.x,a.y,b.x,b.y)
                    -- (near pairs - the same cluster or the next - whose straight line is clear: the line itself; the
                    -- representatives tell nothing more there)
                    if e and math.abs(a.X-b.X)<t.span and math.abs(a.Y-b.Y)<t.span and H.Line(a.hn,b.hn) then e=yards(a,b) end
                    if e then row[b]=e;local back=P.est[b] or {};P.est[b]=back;back[a]=e;estimated=estimated+1 end
                end
                -- Pair estimates are quadratic in the stop count. Check inside
                -- each row so large selections cannot block a frame for 16 rows.
                if (j-i)%32==0 then P.Breathe() end
            end
        end
        P.Breathe()
    end
    for round=1,P.NAVORDERROUNDS do
        order=P.Tour(open,options.loop,start)
        if options.loop and #open>=8 then
            local best=P.Length(order,true)
            for k=1,P.RESTARTS-1 do
                local from=open[floor(k*#open/P.RESTARTS)+1]
                local other=P.Tour(open,true,from)
                local length=P.Length(other,true)
                if length<best then best,order=length,other end
            end
        end
        order,removed=P.Prune(order,options.loop,nil,options.worth)
        local seq={}
        for _,stop in ipairs(order) do seq[#seq+1]=stop end
        local fresh=0
        for i=2,#seq+((options.loop and #seq>2) and 1 or 0) do
            local a,b=seq[i-1],seq[i] or seq[1]
            if not (P.real and P.real[a] and P.real[a][b]) then
                fresh=fresh+1
                P.NavMeasure(s,H,a,b,stats)
                P.Breathe()
            end
        end
        stats.measuredLater=stats.measuredLater+fresh
        stats.orderRounds=round
        if fresh==0 then break end
    end
    P.est=nil
    stats.estimated=estimated
    stats.orderMs=clock()-t1
    local unworth=0;for _,stop in ipairs(removed) do unworth=unworth+#stop.nodes end
    local result={points={},length=0,stops=#order,nodes=#nodes,skipped=skipped,enemy=enemy,unworth=unworth,unworthStops=#removed,cutoff=cutoff,cutoffStops=#cut,worth=options.worth,detours=0,unreachable=0,zones=zones,loop=options.loop,goal=sight and "sight" or "visit",planner="navmesh",offmesh=offmesh}
    local spots={}
    local stopOf={}
    local function add(x,y,stop)
        local mapID,zx,zy=Space.FromSpace(s,x,y)
        result.points[#result.points+1]={mapID=mapID,x=zx,y=zy,stop=stop and true or nil,count=stop and #stop.nodes or nil}
        spots[#result.points]={x,y}
        stopOf[#result.points]=stop
    end
    local gap=false
    -- (a drop down a cliff leading to the next stop: its fall, put on that stop's point)
    local pendingDrop
    t1=clock()
    stats.legs,stats.straight,stats.refined=0,0,0
    P.Stage(.5,1,nil,#order)
    for i,stop in ipairs(order) do
        P.Step(i-1,string.format("Finding the ways (%d of %d)",i,#order))
        add(stop.x,stop.y,stop)
        if gap then result.points[#result.points].gap=true;gap=false end
        if pendingDrop then result.points[#result.points].drop=true;result.points[#result.points].fall=pendingDrop;pendingDrop=nil end
        local nxt=P.Successor(order,i,options.loop)
        if nxt and #order>1 then
            stats.legs=stats.legs+1
            local legs={{stop.x,stop.y},{nxt.x,nxt.y}}
            local path,_,drops=P.NavLeg(H,stop,nxt,stats)
            -- (a drop's point kept by its place: the curves move the points)
            local dropAt
            if drops then
                dropAt={}
                for k,fall in pairs(drops) do dropAt[path[k][1]..":"..path[k][2]]=fall end
            end
            if path and options.smooth then path=P.NavSmooth(H,path) end
            if path==nil then stats.straight=stats.straight+1
            elseif path then
                stats.refined=stats.refined+1
                legs=path
                if #path>2 then result.detours=result.detours+1 end
                for k=2,#path-1 do
                    add(path[k][1],path[k][2])
                    local fall=dropAt and dropAt[path[k][1]..":"..path[k][2]]
                    if fall then result.points[#result.points].drop=true;result.points[#result.points].fall=fall end
                end
                local fall=dropAt and dropAt[path[#path][1]..":"..path[#path][2]]
                if fall then pendingDrop=fall end
            else result.unreachable=result.unreachable+1;gap=true end
            for k=2,#legs do result.length=result.length+Space.Yards(s,legs[k-1][1],legs[k-1][2],legs[k][1],legs[k][2]) end
        end
        P.Breathe()
    end
    if gap and result.points[1] then result.points[1].gap=true end
    if pendingDrop and result.points[1] then result.points[1].drop=true;result.points[1].fall=pendingDrop end
    stats.legsMs=clock()-t1
    -- The drops: counted (pieces in a row are one), each drawn over at least P.JUMPLENGTH yards (as on the grid), their
    -- fall for the issues by the place they lead to.
    -- Stops passed by: the route through within reach of their nodes, no hook to them (P.NavPassBy).
    t1=clock()
    P.passReach=P.PassReach(options,sight)
    stats.passedBy=P.NavPassBy(H,s,result,spots,stopOf)
    P.passReach=nil
    stats.passByMs=clock()-t1
    local fallAt={}
    for j,point in ipairs(result.points) do local p=spots[j];if p and point.fall then fallAt[p[1]..":"..p[2]]=point.fall end end
    local n=#result.points
    for j=1,n do
        if result.points[j].drop and not (result.points[j-1] and result.points[j-1].drop) then
            result.drops=(result.drops or 0)+1
            local length,k=0,j+1
            while k<=n and length<P.JUMPLENGTH and not result.points[k].gap and not result.points[k].stop do
                result.points[k].drop=true
                length=length+Space.Yards(s,spots[k-1][1],spots[k-1][2],spots[k][1],spots[k][2])
                k=k+1
            end
        end
    end
    stats.drops=result.drops
    local geo=navGeo(H,fallAt)
    if P.SPURS then P.Spurs(s,result,spots,geo) end
    result.issues=P.Issues(s,result,spots,order,cut,options.loop,geo)
    P.ClearWork()
    stats.ms=clock()-t0
    result.nav=stats
    P.lastNav=stats
    P.Report(1,"Done")
    return result
end
function P.Successor(order,i,loop)
    if i<#order then return order[i+1] end
    return loop and order[1] or nil
end

-- The stops you can walk to and back from (the navmesh has no direction: one walks back the way one came). The
-- abstract graph's components inside the stops' box (and P.MARGIN yards round it); each stop in the component of the
-- entrance it floods to first. Keep the largest resource component. The
-- player's floor is not an endpoint of a gathering route (Florian2026-10-29).
function P.NavReachable(s,H,stops)
    if #stops<2 then return stops,{} end
    local C,cols=H.C,H.cols
    local x0,y0,x1,y1=huge,huge,-huge,-huge
    local function box(n)
        local c=H.CellOf(n)
        local X,Y=floor((c%cols)/C),floor(floor(c/cols)/C)
        x0,y0,x1,y1=min(x0,X),min(y0,Y),max(x1,X),max(y1,Y)
    end
    for _,stop in ipairs(stops) do box(stop.hn) end
    local m=math.ceil(P.MARGIN/(C*H.cell))
    local region={}
    for Y=max(0,y0-m),min(H.crows-1,y1+m) do for X=max(0,x0-m),min(H.ccols-1,x1+m) do region[X+Y*H.ccols]=true end end
    local comp=H.RegionComponents(region)
    local island={}
    local function group(n)
        if island[n] then return island[n] end
        local e,seen=H.Entrance(n,P.NAVENTRANCE)
        if e then return comp[e] or ("outside:"..e) end
        local key="island:"..n
        for v in pairs(seen or {}) do island[v]=key end
        island[n]=key
        return key
    end
    local of,size={},{}
    for i,stop in ipairs(stops) do
        local k=group(stop.hn)
        of[stop]=k;size[k]=(size[k] or 0)+1
        if i%8==0 then P.Breathe() end
    end
    local want
    local best=0
    for k,n in pairs(size) do if n>best or (n==best and tostring(k)<tostring(want)) then want,best=k,n end end
    -- A stop off its group (its layer a roof, a rock's top, a pocket of navmesh): another layer of its cell or of the
    -- cells round it (P.NAVSNAP) that belongs to it will do; the stop moves there (as P.Reachable's neighbour cell).
    local g=H.geo
    local kept,out={},{}
    for _,stop in ipairs(stops) do
        if of[stop]~=want then
            local c=H.CellOf(stop.hn)
            local cx,cy=c%cols,floor(c/cols)
            local best,bd
            for dy=-P.NAVSNAP,P.NAVSNAP do for dx=-P.NAVSNAP,P.NAVSNAP do
                local nx,ny=cx+dx,cy+dy
                local d=dx*dx+dy*dy
                if nx>=0 and ny>=0 and nx<cols and ny<H.rows and (not bd or d<bd) then
                    for _,n in ipairs(H.CellNodes(ny*cols+nx)) do
                        if (not bd or d<bd) and H.Cost(n) and n~=stop.hn and group(n)==want then best,bd=n,d end
                    end
                end
            end end
            if best then
                local bc=H.CellOf(best)
                if bc~=c then
                    stop.x,stop.y=g.minX+(bc%cols+.5)*H.cell/g.width,g.minY+(floor(bc/cols)+.5)*H.cell/g.height
                    stop.X,stop.Y=stop.x*s.width,stop.y*s.height
                end
                stop.hn=best;of[stop]=want
            end
        end
        if of[stop]==want then kept[#kept+1]=stop else out[#out+1]=stop end
    end
    return kept,out
end

-- The real way between two stops measured by itself (the abstract graph only): its yards both ways in P.real; none
-- (the stops never meet): NAVNOWAY yards.
P.NAVORDERROUNDS=2
P.NAVNOWAY=1e6
function P.NavMeasure(s,H,a,b,stats)
    P.real=P.real or {}
    local d
    if a.hn==b.hn or H.Line(a.hn,b.hn) then d=yards(a,b)
    else
        local nodes,_,st=H.Find(a.hn,b.hn,nil,true)
        if nodes then d=H.ChainYards(nodes,st.jumps,a.x,a.y,b.x,b.y) else d=P.NAVNOWAY end
        if stats then stats.measured=(stats.measured or 0)+1 end
    end
    P.real[a]=P.real[a] or {};P.real[b]=P.real[b] or {}
    P.real[a][b]=d;P.real[b][a]=P.real[b][a] or d
    return d
end
-- For each stop the real way to its P.NEIGHBOURS nearest stops: straight where the line is clear, else one search
-- to all of them (H.FindMany); one without a way counts P.LOST times the straight line (as P.Ways).
function P.NavWays(s,H,stops,stats)
    P.real,P.paths={},{}
    local n=#stops
    if n<4 or P.NEIGHBOURS<=0 then return end
    local function set(a,b,d)
        P.real[a]=P.real[a] or {};P.real[b]=P.real[b] or {}
        P.real[a][b]=d;if not P.real[b][a] then P.real[b][a]=d end
    end
    stats.searches,stats.clear,stats.found,stats.lost=0,0,0,0
    stats.abstractNodes,stats.localNodes=0,0
    P.Stage(.08,.4,nil,n)
    for i,a in ipairs(stops) do
        P.Step(i-1,string.format("Measuring the ways (%d of %d)",i,n))
        local near={}
        for _,b in ipairs(stops) do if b~=a then near[#near+1]={b,yards(a,b)} end end
        table.sort(near,function(p,q) return p[2]<q[2] end)
        local wanted,goals,seen,farthest={},{},{},0
        for k=1,math.min(P.NEIGHBOURS,#near) do
            local b,d=near[k][1],near[k][2]
            if not (P.real[a] and P.real[a][b]) then
                if a.hn==b.hn or H.Line(a.hn,b.hn) then set(a,b,d);stats.clear=stats.clear+1
                else
                    wanted[#wanted+1]={b,d}
                    farthest=math.max(farthest,d)
                    if not seen[b.hn] then seen[b.hn]=true;goals[#goals+1]=b.hn end
                end
            end
        end
        if #goals>0 then
            stats.searches=stats.searches+1
            -- (the search goes on past the first end reached by at most P.LOST times the farthest straight line, in
            -- cost: a way further round counts as lost anyway; H.FindMany's own slack is made for a town's edge)
            local slack=H.MANYSLACK
            H.MANYSLACK=math.max(P.NAVSLACKMIN,farthest*P.LOST)
            local found=H.FindMany(a.hn,goals)
            H.MANYSLACK=slack
            local ms=H.manyStats
            if ms then stats.abstractNodes=stats.abstractNodes+(ms.abstractNodes or 0);stats.localNodes=stats.localNodes+(ms.localNodes or 0) end
            for _,w in ipairs(wanted) do
                local b,d=w[1],w[2]
                local r=found[b.hn]
                if r then
                    set(a,b,polyYards(s,H.Points(r.nodes,r.jumps,a.x,a.y,b.x,b.y)))
                    stats.found=stats.found+1
                else
                    -- (further round than the search went: measured by itself on the abstract graph, its real length,
                    -- not P.LOST times the line; Claude 2026-10-26)
                    stats.lost=stats.lost+1
                    P.NavMeasure(s,H,a,b,stats)
                end
            end
        end
        P.Breathe()
    end
end

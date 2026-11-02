local _,Routing=...
if not Routing.ready then return end
-- The navmesh planner (Claude 2026-10-25, Florian: "mach mit dem Planer weiter"; the prototype of
-- artifacts/terrain-diagnosis/2026-10-24-hpa-prototype): walks on the ground of a continent found on a graph
-- made offline from the game server's navmesh (tools/hpa/build.py, Data/Nav_<continent>.lua), in two layers:
-- the cells (8 yards, every layer of a cell its own node: a tunnel under a mountain, a bridge over a river, a
-- floor of a house) and above them a small abstract graph (clusters of 32 x 32 cells, their entrances, the
-- distances between the entrances of a cluster, the precomputed walks as extra edges). A walk is first measured
-- on the abstract graph only (a few milliseconds, no cells, no terrain asked); only the walks of the final way
-- are refined once on the cells and pulled tight (Hpa:Refine). Costs come from classes stored without any setting
-- (paint, roads, water, slope, zone) and your settings at the time of the way (Hpa:ClassCost, Grid's rules).
-- Switched with /bv route planner navmesh | classic (the setting "planner"); navmesh is the default (Florian
-- 2026-10-25: it replaces the classic planner). Without data
-- for a continent, or data made from other routing data, the classic planner plans as before.
local H={}
Routing.Hpa=H
local floor,byte,char,min,max,abs,sqrt=math.floor,string.byte,string.char,math.min,math.max,math.abs,math.sqrt
local DX={-1,0,1,-1,1,-1,0,1}
local DY={-1,-1,-1,0,0,1,1,1}
local DIAG={true,false,true,false,false,true,false,true}
local SQRT2=sqrt(2)
H.DX,H.DY,H.DIAG=DX,DY,DIAG
H.NONE=16777215
-- The distances inside a cluster, 2 bytes (data version 2): exact below 32768 (quarter cost units), above in steps of
-- 64 (16 cost units); DMNONE: no way.
H.DMNONE=65535
local DMNONE=H.DMNONE
function H.EncodeDist(v)
    if v<32768 then return v end
    return min(65534,32768+math.ceil((v-32768)/64))
end
H.QUANT=4
H.CLEAR=1.25     -- a straight line crosses no node dearer than this (Grid.CLEAR)
H.PULLSLACK=1    -- Grid.PULLSLACK
H.CLEARANCE,H.MAXCLEARANCE=4,8 -- preferred boundary distance, reduced at narrow passages
H.TRIES=3        -- layers tried at each end of a walk (a point does not tell its layer without its height)
H.LOOK=48        -- nodes searched between two looks at the frame's clock (Scheduler.SearchBreathe)
local function u16(s,i) local a,b=byte(s,i,i+1);return a+b*256 end
local function u24(s,i) local a,b,c=byte(s,i,i+2);return a+b*256+c*65536 end
local function u32(s,i) local a,b,c,d=byte(s,i,i+3);return a+b*256+c*65536+d*16777216 end
H.u16,H.u24,H.u32=u16,u24,u32
-- The frame given back inside a search; the continent this search runs on made current again after it (Claude
-- 2026-10-26, Florian: Gather on the navmesh, a way of Navigate on another continent may be planned in between:
-- every continent keeps its own state, H:Use swaps references). While another plan builds a continent's state,
-- this one waits.
-- (Claude 2026-10-28, Florian: "/bv route Protector Weaver" right after a teleport, "Way failed: Scheduler.lua:33:
-- stack overflow": the wait gave the frame back through the scheduler's Breathe, which is wrapped below to wait here
-- too, so every round of the wait began a wait inside the last one, without end while the other plan built. Now one
-- wait per coroutine; a nested call returns at once, and the wait itself gives the frame back each round.)
local waiting=setmetatable({},{__mode="k"})
local function waitBuilt()
    local G=Routing.Scheduler
    local co=coroutine.running()
    local b=H.building
    if not (b and b.co~=co and co and G and G.SearchBreathe) then return end
    if waiting[co] then return end
    waiting[co]=true
    -- (how long, for the way's log: H.stats.waitMs)
    local f=rawget(_G,"debugprofilestop")
    local t0=f and f()
    while b and b.co~=co do
        coroutine.yield()
        b=H.building
    end
    waiting[co]=nil
    if t0 and H.stats then H.stats.waitMs=(H.stats.waitMs or 0)+f()-t0 end
end
local function breathe()
    local G=Routing.Scheduler
    if not (G and G.SearchBreathe) then return end
    local c,f=H.cont,H.faction
    G.SearchBreathe()
    if not c then return end
    waitBuilt()
    if H.cont~=c or H.faction~=f then H:Use(c) end
end
H.Breathe=breathe
-- A plan's own pauses outside the searches (Scheduler.Breathe, Scheduler.Pace: Gather's and Navigate's slices) make
-- its continent current again too (the scheduler's fields replaced here).
function H.Yield()
    local c,f=H.cont,H.faction
    coroutine.yield()
    if not c then return end
    waitBuilt()
    if H.cont~=c or H.faction~=f then H:Use(c) end
end
do
    local G=Routing.Scheduler
    local function wrap(name)
        local f=G and G[name]
        if type(f)~="function" then return end
        G[name]=function(...)
            local c,fa=H.cont,H.faction
            f(...)
            if c and coroutine.running() then
                waitBuilt()
                if H.cont~=c or H.faction~=fa then H:Use(c) end
            end
        end
    end
    wrap("Breathe");wrap("Pace")
end

---------------------------------------------------------------- the planner switch
-- The navmesh planner is the default (Florian 2026-10-25: it replaces the classic one, continent by continent as
-- their data comes; where none is, the classic one plans). "classic" stays to compare.
-- Why the navmesh planner cannot plan on a continent (nil: it can).
function H:Missing(cont)
    local data=rawget(_G,"BVRoutingNav")
    local d=type(data)=="table" and data[cont]
    if type(d)~="table" then return "no navmesh data for this continent" end
    if d.version~=2 then return "navmesh data of another version" end
    if d.dataRevision~=Routing.DATAREVISION then return "navmesh data made from other routing data" end
    return nil
end
-- The navmesh planner plans there (without making its data current: no switch of continents).
function H:Has(cont) return cont~=nil and not self:Missing(cont) end
-- On for this continent: the setting, its data, made from this routing data.
function H:Active(cont)
    if not cont then return false end
    if self:Missing(cont) then return false end
    return self:Use(cont)
end

---------------------------------------------------------------- the data
-- The continent's data made current: its fields on H, as the searches read them. Each continent (and faction) keeps
-- its own state (Claude 2026-10-26: Gather plans on one continent while Navigate may plan on another; the state of
-- the one left is kept, coming back swaps the references, nothing is built again). H.STATE: the fields made here or
-- later (costs, the overlay, caches); the data's own fields come from BVRoutingNav. H.cont=nil (the data replaced):
-- every state anew.
H.STATE={"cont","faction","tails","tailAt","jumpPts","ccols","crows","NC","NX","netOk","jumps","jumpFrom","jumpTo","ajump",
    "costKey","cc","jcost","floor","acomp","dropsFrom","partReach","nopath","localCache","localCount","reachPick","classes","dm","ClassOf","vclass","baseClasses","baseDm",
    "ccAdjusted","NK0","overlayStats","overlaySig","overlayRev"}
H.states={}
local exKeyOf
local function saveState()
    local d=H.stateData
    if not (H.cont and d) then return end
    local st={data=d}
    for _,k in ipairs(H.STATE) do st[k]=H[k] end
    st.ex=exKeyOf()
    H.states[H.cont..":"..tostring(H.faction)]=st
end
local function setData(d)
    for k in pairs(H.dataKeys or {}) do H[k]=nil end
    local keys={}
    for k,v in pairs(d) do H[k]=v;keys[k]=true end
    H.dataKeys=keys
    H.stateData=d
end
local function build(cont,d,faction)
    local b={co=coroutine.running(),cont=cont}
    H.building=b
    local function pause()
        local G=Routing.Scheduler
        if G and G.SearchBreathe then G.SearchBreathe() end
        -- (taken over by a plan outside the frame's slices: built again)
        return b.broken
    end
    setData(d)
    H.cont=cont
    H.ClearExtras()
    H.UseTails(cont,d)
    H.jumpPts={}
    H.ccols=math.ceil(H.cols/H.C);H.crows=math.ceil(H.rows/H.C)
    H.NC=H.cols*H.rows
    H.NX=#H.xcls/2
    H.ClassOf=H.BaseClassOf
    H.vclass,H.baseClasses,H.baseDm,H.ccAdjusted,H.NK0,H.overlayStats,H.overlaySig=nil,nil,nil,nil,nil,nil,nil
    H.nopath,H.reachPick={},{}
    -- The jumps of your faction: the data's own transitions on the ground and the precomputed walks, those with
    -- their shape baked in (shape; Florian 2026-10-25: no network shipped beside the navmesh).
    local mask=faction=="Horde" and 1 or faction=="Alliance" and 2 or 3
    -- (jumpFrom/jumpTo[node]: a jump's number, or a list of them where a node has several)
    local jumps,jumpFrom,jumpTo,ajump={},{},{},{}
    H.jumps,H.jumpFrom,H.jumpTo,H.ajump=jumps,jumpFrom,jumpTo,ajump
    local function add(map,n,i)
        local v=map[n]
        if not v then map[n]=i elseif type(v)=="number" then map[n]={v,i} else v[#v+1]=i end
    end
    for i=1,(d.jn or 0) do
        if i%256==0 and pause() then return false end
        local net,f,shaped=H.JumpNet(i),H.JumpFaction(i),H.JumpShaped(i)
        if (not net or shaped) and (f==0 or f==3 or f==mask) then
            jumps[#jumps+1]=i
            add(jumpFrom,H.JumpFrom(i),i)
            add(jumpTo,H.JumpTo(i),i)
        end
    end
    for c,i in ipairs(jumps) do
        if c%128==0 and pause() then return false end
        for _,n in ipairs({H.JumpFrom(i),H.JumpTo(i)}) do
            if not ajump[n] then
                local cid=H.ClusterOfCell(H.CellOf(n))
                local f,k=H.afirst[cid],H.acount[cid]
                if f then for a=f,f+k-1 do if u32(H.anode,(a-1)*4+1)==n then ajump[n]=a;break end end end
            end
        end
    end
    H.faction=faction
    H.costKey=nil
    if H.Components(pause)==false then return false end
    return true
end
-- A cancelled/failed scheduler coroutine will never finish its preparation.
-- Invalidate only that partial working state; completed continent snapshots
-- remain reusable, and another coroutine's builder must not be disturbed.
function H:CancelBuild(co)
    local b=self.building
    if not (b and b.co==co) then return end
    b.broken=true
    self.building=nil
    self.stateData=nil -- do not save or accept the partially built state
end
-- Your faction ("Horde", "Alliance"; nil: none, the build).
function H.Faction()
    local ok,faction=pcall(UnitFactionGroup,"player")
    return ok and (faction=="Horde" or faction=="Alliance") and faction or nil
end
function H:Use(cont)
    local faction=H.Faction()
    local d=rawget(_G,"BVRoutingNav")[cont]
    waitBuilt()
    if H.cont==cont and H.faction==faction and H.stateData==d and not H.building then return true end
    if H.building and H.building.co~=coroutine.running() then
        -- (a plan outside the frame's slices needs the data while another builds a state: it takes over)
        H.building.broken=true
        H.building=nil
    elseif H.cont==nil then H.states={}
    elseif not H.building then saveState() end
    local st=H.states[cont..":"..tostring(faction)]
    if st and st.data==d then
        setData(d)
        for _,k in ipairs(H.STATE) do H[k]=st[k] end
        H.ClassOf=st.ClassOf or H.BaseClassOf
        exKeyOf(st.ex)
        return true
    end
    while true do
        local ok=build(cont,d,faction)
        if H.building and H.building.co==coroutine.running() then H.building=nil end
        if ok then break end
        -- (broken: rebuilt from the start once the plan that took over is done)
        waitBuilt()
    end
    saveState()
    return true
end
---------------------------------------------------------------- the zones' cluster costs (Data/NavZones_<cont>.lua)
-- Precomputed offline (tools/hpa/zones.py, Claude 2026-10-26, Florian: Gather's order by the real ways, "vorberechnen"):
-- per zone with known spawns one representative per cluster holding spawns, and the yards of the cheapest way between
-- them on the abstract graph, counted as Hpa.ChainYards counts (u16 in quant yards, upper triangle; 65535: none). Bound to the Nav data it was made for (navStamp).
-- H.ZoneCost: a pair's straight line plus what the way between their clusters' representatives is longer than the
-- straight line between those (rocks, canyons, water between); nil where the table does not have both.
H.zoneTables={}
function H.ZoneTable(cont,mapID)
    local d=(rawget(_G,"BVRoutingNav") or {})[cont]
    local key=cont..":"..tostring(mapID)
    local hit=H.zoneTables[key]
    if hit and hit.data==d then return hit.t or nil end
    local all=rawget(_G,"BVRoutingNavZones")
    local f=type(all)=="table" and all[cont]
    local z=type(f)=="table" and f.version==2 and type(d)=="table" and f.navStamp==H.NavStamp(d) and type(f.zones)=="table" and f.zones[mapID]
    local t=false
    if type(z)=="table" and type(z.reps)=="string" and type(z.d)=="string" then
        local n=#z.reps/3
        local group,cluster,pos={},{},{}
        local cols,NC=d.cols,d.cols*d.rows
        local ccols=math.ceil(cols/d.C)
        for i=1,n do
            local m=u24(z.reps,(i-1)*3+1)
            group[m-byte(d.ac,(m-1)*5+1)]=i
            local node=u32(d.anode,(m-1)*4+1)
            local c=node<NC and node or u24(d.xcell,(node-NC)*3+1)
            local cid=floor((c%cols)/d.C)+floor(floor(c/cols)/d.C)*ccols
            cluster[cid]=cluster[cid] or i
            pos[i]={d.geo.minX+((c%cols)+.5)*d.cell/d.geo.width,d.geo.minY+(floor(c/cols)+.5)*d.cell/d.geo.height}
        end
        t={n=n,group=group,cluster=cluster,pos=pos,d=z.d,quant=f.quant or 4,geo=d.geo,span=2*d.C*d.cell}
    end
    H.zoneTables[key]={data=d,t=t}
    return t or nil
end
-- A node's representative in a zone's table: the group of entrances it reaches first inside its cluster (the data in
-- use must be the table's continent's), else its cluster's first; nil where the table has neither.
function H.ZoneRep(t,n)
    local cid=H.ClusterOfCell(H.CellOf(n))
    local f,k=H.afirst[cid],H.acount[cid]
    if f then
        local targ={};for m=f,f+k-1 do targ[H.ANode(m)]=m end
        local d=H.Local({[cid]=true},n,{targets=targ,any=true})
        local best,bd
        for an,m in pairs(targ) do if d[an] and (not bd or d[an]<bd) then best,bd=m,d[an] end end
        if best then
            local i=t.group[best-byte(H.ac,(best-1)*5+1)]
            if i then return i end
        end
    end
    return t.cluster[cid]
end
-- The estimate between two points with their representatives i, j: the straight line plus what the way between the
-- representatives is longer than the straight line between them; nil without a way.
function H.ZoneCost(t,i,j,ax,ay,bx,by)
    local g=t.geo
    local line=sqrt(((bx-ax)*g.width)^2+((by-ay)*g.height)^2)
    if i==j then return line end
    if i>j then i,j=j,i end
    local n=t.n
    local o=((i-1)*n-(i-1)*i/2+(j-i)-1)*2+1
    local a,b=byte(t.d,o,o+1)
    local q=a+b*256
    if q==65535 then return nil end
    local pa,pb=t.pos[i],t.pos[j]
    local repLine=sqrt(((pb[1]-pa[1])*g.width)^2+((pb[2]-pa[2])*g.height)^2)
    return line+max(0,q*t.quant-repLine)
end
---------------------------------------------------------------- the NPCs' end pieces (Data/NavTails_<cont>.lua)
-- Precomputed offline (tools/hpa/tails.py, Claude 2026-10-25, Florian: "vorberechnen statt zur Laufzeit rechnen"):
-- for each service NPC of a town or city with a navmesh polygon, the way on the polygons from the nearest node of
-- the graph that reaches far (no splinter) to just before the NPC. A way to that NPC plans to that node and goes on
-- along the piece (Harick behind his counter: up the outer stair, not to the wall outside). Bound to the Nav data it
-- was made for (H.NavStamp); another one: none used, the reach rule (ReachNodes) as before.
-- tk: per piece 21 bytes: NPC x, y (u24, 1/8 yd from the grid's corner), entry node (u24), entry x, y (u24),
-- first point in tp (u24), points (u8), yards (u16, 1/4 yd); tp: points x, y (u24), z (u16, 1/16 yd + 32768).
function H.NavStamp(d)
    local a=type(d.anode)=="string" and d.anode or ""
    local sum=0
    for i=1,#a,997 do sum=(sum+byte(a,i)*i)%1000003 end
    return table.concat({tostring(d.dataRevision),#a,type(d.xe)=="string" and #d.xe or 0,type(d.iedge)=="string" and #d.iedge or 0,d.jn or 0,sum},":")
end
local TK=21
function H.UseTails(cont,d)
    H.tails,H.tailAt=nil,nil
    local all=rawget(_G,"BVRoutingNavTails")
    local t=type(all)=="table" and all[cont]
    if type(t)~="table" or t.version~=1 or t.navStamp~=H.NavStamp(d) then return end
    H.tails=t
end
-- The end piece for a goal (an NPC by its spot), or nil.
function H.TailFor(goal)
    local t=H.tails
    if not (t and goal and goal.x) then return nil end
    if not H.tailAt then
        local at={}
        for i=0,#t.tk/TK-1 do at[u24(t.tk,i*TK+1)..":"..u24(t.tk,i*TK+4)]=i end
        H.tailAt=at
    end
    local g=H.geo
    local x8,y8=floor((goal.x-g.minX)*g.width*8+.5),floor((goal.y-g.minY)*g.height*8+.5)
    local i
    for dy=-2,2 do for dx=-2,2 do i=i or H.tailAt[(x8+dx)..":"..(y8+dy)] end end
    if not i then return nil end
    local o=i*TK
    local node=u24(t.tk,o+7)
    local ex,ey=g.minX+u24(t.tk,o+10)/8/g.width,g.minY+u24(t.tk,o+13)/8/g.height
    local p0,n=u24(t.tk,o+16),byte(t.tk,o+19)
    local pts={}
    for k=p0,p0+n-1 do
        local q=k*8
        pts[#pts+1]={g.minX+u24(t.tp,q+1)/8/g.width,g.minY+u24(t.tp,q+4)/8/g.height}
    end
    return {node=node,x=ex,y=ey,pts=pts,yards=u16(t.tk,o+20)/4}
end
-- Which abstract nodes can reach each other at all (Claude 2026-10-25: a walk between two parts that never meet
-- searched the whole continent before it failed, 0.3-0.4 s; Thunder Bluff's mesa and the plain below): groups,
-- crossings between clusters and your faction's jumps joined; H.acomp per abstract node its part (u24 string).
-- pause: the build's own (H:Use; true when it was taken over: false back), else breathe.
function H.Components(pause)
    pause=pause or function() breathe();return false end
    if not (H.ac and H.anode and H.ioff) then H.acomp=nil;return end
    local NA=#H.anode/4
    local parent={}
    local function root(i)
        local r=i
        while parent[r] and parent[r]~=r do r=parent[r] end
        while parent[i] and parent[i]~=r do local nx=parent[i];parent[i]=r;i=nx end
        return r
    end
    local function join(a,c)
        local ra,rc=root(a),root(c)
        if ra~=rc then if ra<rc then parent[rc]=ra else parent[ra]=rc end end
    end
    for m=1,NA do
        if m%512==0 and pause() then return false end
        parent[m]=parent[m] or m
        local pos=byte(H.ac,(m-1)*5+1)
        if pos>0 then join(m,m-pos) end
        local e0,e1=u24(H.ioff,(m-1)*3+1),u24(H.ioff,m*3+1)
        for e=e0,e1-1 do local t=u24(H.iedge,e*6+1);parent[t]=parent[t] or t;join(m,t) end
    end
    -- (the drops down a cliff only one way: the parts they lead from and to, H.dropsFrom; Claude 2026-10-26, Brill to
    -- Undercity: drops into the ruins' shafts joined the city with the ground, and every walk to the inn on the
    -- city's level searched the whole graph before it found none, 0.1-0.3 s each)
    local drops={}
    for c,i in ipairs(H.jumps) do
        if c%256==0 and pause() then return false end
        local a,t=H.ajump[H.JumpFrom(i)],H.ajump[H.JumpTo(i)]
        if a and t then
            if H.JumpDrop(i) then drops[#drops+1]=a;drops[#drops+1]=t else join(a,t) end
        end
    end
    local out={}
    for m=1,NA do
        if m%512==0 and pause() then return false end
        local r=root(m)
        out[m]=char(r%256,floor(r/256)%256,floor(r/65536))
    end
    H.acomp=table.concat(out)
    local from={}
    for k=1,#drops-1,2 do
        local ra,rt=root(drops[k]),root(drops[k+1])
        if ra~=rt then
            local l=from[ra];if not l then l={};from[ra]=l end
            l[#l+1]=rt
        end
    end
    H.dropsFrom,H.partReach=from,{}
    return true
end
-- Does one of the parts ps reach one of the parts pg, on foot or down drops (one way)? Kept per pair of parts.
function H.PartsMeet(ps,pg)
    for p in pairs(pg) do if ps[p] then return true end end
    local from=H.dropsFrom
    if not (from and next(from)) then return false end
    for a in pairs(ps) do
        for b in pairs(pg) do
            local key=a*16777216+b
            local v=H.partReach[key]
            if v==nil then
                v=false
                local seen,queue,head={[a]=true},{a},1
                while head<=#queue and not v do
                    local u=queue[head];head=head+1
                    for _,w in ipairs(from[u] or {}) do
                        if w==b then v=true break end
                        if not seen[w] then seen[w]=true;queue[#queue+1]=w end
                    end
                end
                H.partReach[key]=v
            end
            if v then return true end
        end
    end
    return false
end
-- Do two points lie on one surface the graph walks between nearby (Claude 2026-10-25, Florian: a painted level's
-- border on the same plain is no step)? A search from one to the other inside the clusters round both; kept per
-- pair of points (per continent, kept while the data stays; made after login for your continent, H:Prepare).
H.joined={}
-- The answers precomputed offline for the shipped transitions (tools/hpa/flat.py, Data/NavFlat_<cont>.lua, Claude
-- 2026-10-26: Brill to Undercity after a teleport from Kalimdor spent 0.6 s offline, about 2 s in the game, on these
-- searches in its first plan): "\n<key>=1\n" or "=0", bound to the continent's navmesh data by its stamp. Not while a
-- setting blocks ground the build walked on (enemies or high risk "block").
H.flatPre={}
function H.JoinedKnown(cont,key)
    local cfg=Routing:Config()
    if cfg.enemy=="block" or cfg.risk=="block" then return nil end
    local d=(rawget(_G,"BVRoutingNav") or {})[cont]
    local pre=H.flatPre[cont]
    if not pre or pre.data~=d then
        local t=(rawget(_G,"BVRoutingNavFlat") or {})[cont]
        local ok=type(d)=="table" and type(t)=="table" and t.version==1 and type(t.keys)=="string" and t.navStamp==H.NavStamp(d)
        pre={data=d,keys=ok and t.keys or false}
        H.flatPre[cont]=pre
    end
    if not pre.keys then return nil end
    local i=pre.keys:find("\n"..key.."=",1,true)
    if not i then return nil end
    return pre.keys:byte(i+#key+2)==49
end
function H.JoinedKey(cont,ax,ay,az,bx,by,bz)
    return string.format("%d:%.5f:%.5f:%.1f:%.5f:%.5f:%.1f",cont,ax,ay,az or -1e4,bx,by,bz or -1e4)
end
function H:Joined(cont,ax,ay,az,bx,by,bz)
    local key=H.JoinedKey(cont,ax,ay,az,bx,by,bz)
    local v=H.joined[key]
    if v~=nil then return v end
    v=H.JoinedKnown(cont,key)
    if v~=nil then H.joined[key]=v;return v end
    if not self:Active(cont) then return false end
    self:Costs()
    local A,B=H.Nodes(ax,ay,az),H.Nodes(bx,by,bz)
    v=false
    if A[1] and B[1] then
        local region=H.RegionOf(A[1])
        for cid in pairs(H.RegionOf(B[1])) do region[cid]=true end
        local d=H.Local(region,A[1],{target=B[1]})
        v=d[B[1]]~=nil
    end
    H.joined[key]=v
    return v
end
-- The parts the abstract nodes of a region reach (from a node s with its local distances d): {[part]=true}.
local function partsOf(targ,d)
    local out={}
    for n,a in pairs(targ) do if d[n] then out[u24(H.acomp,(a-1)*3+1)]=true end end
    return out
end

---------------------------------------------------------------- costs from classes and your settings
-- Mirrors Grid.BaseCost/Ground/CellCost on the stored classes {paint, flags, terrain, code, zone}: flags 1 on a
-- given way, 2 cheap beside it, 4 a Road Studio road, 8 in a city's rectangle, 16 under a town's ground level;
-- terrain 1 the cell's terrain layer (its code: slope 2 bits, water 2 bits, road 32), 0 a layer apart from it
-- (a tunnel, a bridge, a floor; slope 0, water by the navmesh). Walked ways (Gather) are not stored: a city's
-- cells count as not walked.
local NOGO,PREFER,RISK,ENEMY,WALL,SWIM=1,2,3,4,5,6
-- The costs of ground (Claude 2026-10-26: the navmesh's own, no longer read from Routing's grid; the values the
-- grid used, Gather's expert settings change them): slope classes 0-3 (the steepest you can still walk), swimming
-- with "Avoid water" and in the safe mode, roads at most in the safe mode, a zone above your level, a given way.
H.SLOPE={1,1.2,2.5,8};H.STEEP=8
H.SWIM=6;H.SAFESWIM=12;H.SAFEROAD=.4;H.ROAD=.6;H.HIGHZONE=4;H.WAYCOST=.3
H.RECORDED=.8   -- each yard of Florian's recorded ways counts this much (the network's RECORDED, Transit.lua until 2026-10-27)
-- A place's side (tools/hpa/attrs.py, since 2026-10-26: 7 the Horde's, 8 the Alliance's - their capitals and the
-- areas round their flight masters): the other side's is enemy ground for you (H.faction, the continent's state);
-- your own side's, or without a faction, plain ground. Other paint (your own strokes, the overlay) as it is.
H.HORDESIDE,H.ALLIANCESIDE=7,8
function H.SidePaint(paint)
    if paint==H.HORDESIDE then return H.faction=="Alliance" and ENEMY or 0 end
    if paint==H.ALLIANCESIDE then return H.faction=="Horde" and ENEMY or 0 end
    return paint
end
-- Whether a continent point lies on enemy ground for you (a place of the other side, an enemy area painted): the
-- paint of its cell's largest layer, whatever the setting costs it (Florian 2026-10-27, Navigate:EnemyOnWay).
-- inside: the four cells round it too (a way along its edge touches its cells, one through it does not).
local function enemyCell(cx,cy)
    if cx<0 or cy<0 or cx>=H.cols or cy>=H.rows then return false end
    local c=H.classes and H.classes[H.ClassOf(cy*H.cols+cx)]
    return c~=nil and H.SidePaint(c[1])==ENEMY
end
function H.EnemyAt(x,y,inside)
    local g=H.geo
    if not g then return false end
    local cx,cy=floor((x-g.minX)*g.width/H.cell),floor((y-g.minY)*g.height/H.cell)
    if not enemyCell(cx,cy) then return false end
    return not inside or (enemyCell(cx-1,cy) and enemyCell(cx+1,cy) and enemyCell(cx,cy-1) and enemyCell(cx,cy+1))
end
function H.ClassCost(c,cfg,mode,zoneAbove)
    local paint,flags,code,zone=H.SidePaint(c[1]),c[2],c[4],c[5]
    if code==255 then code=nil end
    local onway,waycheap,road=flags%2==1,floor(flags/2)%2==1,floor(flags/4)%2==1
    local roadCost=(cfg.roadPercent or H.ROAD*100)/100
    if mode=="safe" then roadCost=min(roadCost,H.SAFEROAD) end
    local swimCost=mode=="safe" and H.SAFESWIM or (cfg.avoidWater and H.SWIM or 1.5)
    -- (A city's rectangle, flag 8, costs nothing extra here: Grid makes it CITY times dearer because the terrain
    -- data lacks the capitals' buildings and walls; the navmesh has them. Claude 2026-10-25, Florian: capitals over
    -- the navmesh.)
    local function ground()
        local cost
        if not code then cost=1
        else
            local water=floor(code/4)%4
            local dry=water==0
            if dry and code%4~=3 and cfg.preferRoads and (code%64>=32 or road) then cost=roadCost
            elseif water==3 then cost=20
            elseif water==2 then cost=swimCost
            elseif water==1 then cost=1.2
            else cost=H.SLOPE[code%4+1] end
        end
        if zoneAbove and zone~=0 and zoneAbove(zone) then cost=cost*H.HIGHZONE end
        return cost
    end
    local cost
    if paint==WALL then return nil end
    if onway then cost=H.WAYCOST
    elseif paint==NOGO then return nil
    elseif paint==PREFER then cost=.5
    elseif paint==SWIM then cost=swimCost
    else
        cost=1
        if paint==RISK then
            if cfg.risk=="block" then return nil end
            if cfg.risk=="avoid" then cost=4 end
        elseif paint==ENEMY then
            if cfg.enemy=="block" then return nil end
            -- ("Ignore enemies": their ground like any other; Claude 2026-10-26, it cost 10 times as with "avoid")
            if cfg.enemy~="ignore" then cost=10 end
        end
        -- (Under a town's ground level, flag 16, nothing extra either: Grid makes it TOWNGROUND times dearer so that a
        -- walk on the ground space goes round or through the town's own level; here the town's level is walked on
        -- this same graph, and the factor made a walk from inside the town flee its rectangle by the nearest side and
        -- run round outside it. Claude 2026-10-25 after the Razor Hill diagnosis, Florian from Razor Hill's inn: east
        -- up the slope and over the rock domes instead of up the street.)
        cost=cost*ground()
    end
    if waycheap then cost=min(cost,H.WAYCOST) end
    return cost
end
-- The costs of the classes and the jumps for your settings now (made again when a setting they read changes).
function H:Costs()
    local cfg=Routing:Config()
    -- Enemy ground for this plan (Navigate:EnemyMode, Florian 2026-10-27: a way only through an enemy base is asked
    -- for, and then planned as "Avoid"; the setting itself unchanged): the classes costed with a copy that says so.
    local N=Routing.Navigate
    local enemy=N and N.EnemyMode and N:EnemyMode() or cfg.enemy
    if enemy~=cfg.enemy then cfg=setmetatable({enemy=enemy},{__index=cfg}) end
    H.costCfg=cfg
    local mode=Routing:RouteMode()
    local zoneMode=Routing:ZoneMode()
    local level=UnitLevel and UnitLevel("player") or 0
    local key=table.concat({tostring(cfg.roadPercent),tostring(cfg.avoidWater),tostring(cfg.preferRoads),tostring(cfg.risk),
        tostring(enemy),tostring(mode),tostring(zoneMode),tostring(level),tostring(H.cont),tostring(H.faction),
        tostring(cfg.walkedPercent),tostring(H.PreferWalked and H.PreferWalked() or false),tostring(H.overlayRev),tostring(cfg.cliffs)},"|")
    if H.costKey==key then return end
    local zoneAbove
    if zoneMode=="avoid" then zoneAbove=function(z) return Routing:ZoneAbove(z,level) end end
    local cc,lo={},1e9
    for i,c in ipairs(H.classes) do
        if i%256==0 then breathe() end
        local v=H.ClassCost(c,cfg,mode,zoneAbove)
        cc[i]=v or false
        if v and v<lo then lo=v end
    end
    H.cc=cc
    local roadCost=(cfg.roadPercent or 60)/100
    if mode=="safe" then roadCost=min(roadCost,H.SAFEROAD) end
    local jl=1e9
    local jcost={}
    -- The water of a precomputed walk at the cells' water costs for your settings (swum: as deep water, SWIM with
    -- "Avoid water", SAFESWIM when safe; waded: as shallow water) rather than the network's fixed SWIM/WADE (Claude
    -- 2026-10-25, Theramore -> Gadgetzan: a recorded walk's swum yard cost 2.4, a swum cell 6; the way swam 393 yd
    -- along the recordings where 227 yd will do).
    local swimCost=mode=="safe" and H.SAFESWIM or (cfg.avoidWater and H.SWIM or 1.5)
    local wadeCost=1.2
    for c,i in ipairs(H.jumps) do
        if c%256==0 then breathe() end
        local yards,line,road,water,swim,recorded=H.JumpRank(i)
        local cost=yards
        if H.JumpLift(i) then cost=H.LiftYards(i)
        elseif H.JumpDrop(i) then
            local cliffs=cfg.cliffs or "safe"
            if cliffs=="never" then cost=yards*H.DROPDEAR
            elseif cliffs=="safe" and H.JumpFall(i)>H.SAFEDROP then cost=false
            else cost=yards*H.DROPCOST end
        elseif H.JumpNet(i) then
            -- The road part cheaper, water dearer, Florian's recorded ways RECORDED
            if road then cost=cost*(road*roadCost+(1-road)) end
            local w=min(water,yards)
            if w>0 then cost=cost+w*((swim and swimCost or wadeCost)-1) end
            if recorded then cost=cost*H.RECORDED end
        end
        jcost[i]=cost
        if cost and line>0 then jl=min(jl,cost/line) end
    end
    H.jcost=jcost
    H.floor=min(lo,jl)
    H.costKey=key
    H.nopath={}
    H.localCache,H.localCount={},0
end

---------------------------------------------------------------- the jumps (data version 2: packed)
-- jd: per jump 19 bytes: from (u24), to (u24), yards and line (u24 each, 1/8 yd), road share (u8, /200; 255 none),
-- water yards (u16, 1/2 yd), flags (u8: 1 a precomputed walk, 2 swim, 4 Florian's recording, 8/16 factions Horde/
-- Alliance, none: both), raw network edge (u24, 0 none); jso: per jump where its shape begins in jsh (u24, one more).
local JB=19
function H.JumpFrom(i) return u24(H.jd,(i-1)*JB+1) end
function H.JumpTo(i) return u24(H.jd,(i-1)*JB+4) end
local function jflags(i) return byte(H.jd,(i-1)*JB+16) end
function H.JumpNet(i) return jflags(i)%2==1 end
-- A drop down a cliff (flag 32; tools/hpa/hierarchy.py drops_of): one way, its fall in yards in the water field.
function H.JumpDrop(i) return floor(jflags(i)/32)%2==1 end
function H.JumpFall(i) return u16(H.jd,(i-1)*JB+14)/2 end
-- Down cliffs (Routing's setting cliffs, as Grid.Step): "never" a drop very dear (DROPDEAR), "safe" up to SAFEDROP
-- yards, "always" any; both at DROPCOST times its yards.
H.SAFEDROP=12;H.DROPCOST=1.5;H.DROPDEAR=8
function H.JumpFaction(i) return floor(jflags(i)/8)%4 end
-- A lift (flag 64; tools/hpa/hierarchy.py lifts_of, Claude 2026-10-26, Florian: lifts are the quick, usual way, one
-- search weighs them against the walk): the data's lifts and the rides his recordings make that no data lift has
-- (Thunder Bluff's second cabins). Its seconds in the water field (0: unknown, LIFTSECONDS); raw: its number in the
-- data's lifts list {id, name, seconds, recorded, a, b, za, zb}. It costs its seconds times N.WAIT (half waiting, half
-- riding, as the transports) at your speed on foot, in yards.
H.LIFTSECONDS=40
function H.JumpLift(i) return floor(jflags(i)/64)%2==1 end
function H.JumpLiftOf(i) local r=u24(H.jd,(i-1)*JB+17);return H.lifts and H.lifts[r] end
function H.LiftSeconds(i) local v=u16(H.jd,(i-1)*JB+14)/2;return v>0 and v or H.LIFTSECONDS end
function H.LiftYards(i)
    local N=Routing.Navigate
    local speed=N and N.Speed and N:Speed() or 7
    return H.LiftSeconds(i)*((N and N.WAIT) or .75)*speed
end
-- The data lifts' link ids of a continent's navmesh data (Navigate leaves those doors out: the graph rides them).
H.liftIds={}
function H.LiftIds(cont)
    local d=(rawget(_G,"BVRoutingNav") or {})[cont]
    local hit=H.liftIds[cont]
    if hit and hit.data==d then return hit.ids end
    local ids={}
    for _,l in ipairs(type(d)=="table" and type(d.lifts)=="table" and d.lifts or {}) do
        if type(l.id)=="string" and l.id~="" then ids[l.id]=true end
    end
    H.liftIds[cont]={data=d,ids=ids}
    return ids
end
function H.JumpShaped(i) return H.jso~=nil and u24(H.jso,i*3+1)>u24(H.jso,(i-1)*3+1) end
-- yards, line, road share (nil: none), water yards, swim, recorded
function H.JumpRank(i)
    local o=(i-1)*JB
    local road=byte(H.jd,o+13)
    local f=jflags(i)
    return u24(H.jd,o+7)/8,u24(H.jd,o+10)/8,road~=255 and road/200 or nil,u16(H.jd,o+14)/2,floor(f/2)%2==1,floor(f/4)%2==1
end
function H.JumpRaw(i) local r=u24(H.jd,(i-1)*JB+17);return r>0 and r or nil end

---------------------------------------------------------------- graph access
-- Data version 2 (Claude 2026-10-25, Florian: "mach mit dem Speicher weiter"; tools/hpa/hierarchy.py load): cell
-- types per cluster with a palette, extra layers by cell (u24) with their steps a byte each (direction and the layer
-- of the cell there), a base node's steps to other layers found from those layers' own lists.
function H.CellOf(n) if n<H.NC then return n end;return u24(H.xcell,(n-H.NC)*3+1) end
function H.ClusterOfCell(i) local cols,C=H.cols,H.C;return floor((i%cols)/C)+floor(floor(i/cols)/C)*H.ccols end
local function typeOfCell(i)
    local cols,C=H.cols,H.C
    local x,y=i%cols,floor(i/cols)
    local X,Y=floor(x/C),floor(y/C)
    local s=H.cl[X+Y*H.ccols]
    if not s then return H.blockedType end
    local w=min(C,cols-X*C)
    local j=(y-Y*C)*w+(x-X*C)
    local mode=byte(s,1)
    if mode==1 then local a,b=byte(s,j*2+2,j*2+3);return a+b*256 end
    local n=byte(s,2)
    local p
    if mode==2 then p=byte(s,3+n*2+j)
    else local v=byte(s,3+n*2+floor(j/2));p=j%2==0 and v%16 or floor(v/16) end
    local a,b=byte(s,3+p*2,4+p*2)
    return a+b*256
end
H.TypeOfCell=typeOfCell
function H.ClassOf(n)
    if n<H.NC then return u16(H.ttcls,typeOfCell(n)*2+1)%32768 end
    return u16(H.xcls,(n-H.NC)*2+1)%2048
end
-- (the stored class; H.ClassOf is replaced while an overlay is set, HpaOverlay.lua)
H.BaseClassOf=H.ClassOf
function H.Cost(n) local k=H.ClassOf(n);return k>0 and H.cc[k] or nil end
-- The first extra layer of a cell (its index) and how many it has: halving inside its grid row (xrow).
-- (a small direct-mapped cache, EXCACHE slots, cleared when the data changes: the searches ask the same cells again
-- and again; Claude 2026-10-25, the halving made cold plans 10-40 % slower)
H.EXCACHE=4096
local exKey,exFirst,exCount={},{},{}
function H.ClearExtras() exKey,exFirst,exCount={},{},{} end
-- (the cache kept with a continent's state, H:Use)
exKeyOf=function(t)
    if t then exKey,exFirst,exCount=t[1],t[2],t[3];return end
    return {exKey,exFirst,exCount}
end
function H.Extras(cell)
    local slot=cell%H.EXCACHE+1
    if exKey[slot]==cell then return exFirst[slot],exCount[slot] end
    local first,count=H.ExtrasOf(cell)
    exKey[slot],exFirst[slot],exCount[slot]=cell,first,count
    return first,count
end
function H.ExtrasOf(cell)
    local y=floor(cell/H.cols)
    local lo,hi=u24(H.xrow,y*3+1),u24(H.xrow,y*3+4)
    local top=hi
    while lo<hi do local m=floor((lo+hi)/2);if u24(H.xcell,m*3+1)<cell then lo=m+1 else hi=m end end
    local k=lo
    while k<top and u24(H.xcell,k*3+1)==cell do k=k+1 end
    return lo,k-lo
end
-- The steps an extra layer lists: first byte in xe and count.
local function listed(k)
    local b=floor(k/16)
    local o=u24(H.xblk,b*3+1)
    for i=b*16,k-1 do o=o+floor(u16(H.xcls,i*2+1)/2048) end
    return o,floor(u16(H.xcls,k*2+1)/2048)
end
-- Every step from node n: f(v, direction). The graph has no direction (the navmesh has none, and no jumps down).
function H.Each(n,f)
    local cols,NC=H.cols,H.NC
    if n<NC then
        local t=typeOfCell(n)
        local bits=byte(H.ttbits,t+1)
        if bits>0 then
            for d=1,8 do
                if floor(bits/2^(d-1))%2==1 then f(n+DY[d]*cols+DX[d],d) end
            end
        end
        -- steps to other layers round it: those layers list them (direction back to here, layer 0)
        if u16(H.ttcls,t*2+1)>=32768 then
            local x,y=n%cols,floor(n/cols)
            for d=1,8 do
                local nx,ny=x+DX[d],y+DY[d]
                if nx>=0 and ny>=0 and nx<cols and ny<H.rows then
                    local c=ny*cols+nx
                    local first,count=H.Extras(c)
                    local back=(8-d)*32
                    for k=first,first+count-1 do
                        local o,m=listed(k)
                        for e=o,o+m-1 do if byte(H.xe,e+1)==back then f(NC+k,d) end end
                    end
                end
            end
        end
        return
    end
    local k=n-NC
    local c=u24(H.xcell,k*3+1)
    local o,m=listed(k)
    for e=o,o+m-1 do
        local v=byte(H.xe,e+1)
        local d=floor(v/32)+1
        local ly=v%32
        local c2=c+DY[d]*cols+DX[d]
        if ly==0 then f(c2,d) else local first=H.Extras(c2);f(NC+first+ly-1,d) end
    end
end
function H.heapPush(keys,vals,n,key,value)
    n=n+1
    local i=n
    while i>1 do
        local parent=floor(i/2)
        if keys[parent]<=key then break end
        keys[i],vals[i]=keys[parent],vals[parent];i=parent
    end
    keys[i],vals[i]=key,value
    return n
end
function H.heapPop(keys,vals,n)
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
local heapPush,heapPop=H.heapPush,H.heapPop

---------------------------------------------------------------- search on the cells
-- Inside region {[cluster]=true} from src: o.target (A* to it), o.targets {[node]=true} (until all reached),
-- o.reverse (who can walk to src), o.jumps (the jumps too), o.seeds {[node]=cost} (more starts, src may be nil).
-- Returns dist, from, nodes searched.
function H.Local(region,src,o)
    local cols,cell=H.cols,H.cell
    local reverse,target,targets=o.reverse,o.target,o.targets
    local left=0
    if targets then for _ in pairs(targets) do left=left+1 end end
    local FL=H.floor*cell
    local tx,ty
    if target then local tc=H.CellOf(target);tx,ty=tc%cols,floor(tc/cols) end
    local function h(v)
        if not target then return 0 end
        local c=H.CellOf(v)
        local dx,dy=abs(c%cols-tx),abs(floor(c/cols)-ty)
        return (max(dx,dy)+(SQRT2-1)*min(dx,dy))*FL
    end
    local keys,vals,n={},{},0
    local dist,from,closed={},{},{}
    if src then dist[src]=0;n=heapPush(keys,vals,n,h(src),src) end
    for v,d in pairs(o.seeds or {}) do
        if not dist[v] or d<dist[v] then dist[v]=d;n=heapPush(keys,vals,n,d+h(v),v) end
    end
    local count=0
    local cc,ClassOf,CellOf,ClusterOfCell=H.cc,H.ClassOf,H.CellOf,H.ClusterOfCell
    local u,g,ucost
    local function relax(v,d)
        if closed[v] or not region[ClusterOfCell(CellOf(v))] then return end
        local c
        if reverse then c=ucost else local k=ClassOf(v);c=k>0 and cc[k] or nil end
        if not c then return end
        local ng=g+c*cell*(DIAG[d] and SQRT2 or 1)
        local old=dist[v]
        if not old or ng<old then dist[v]=ng;from[v]=u;n=heapPush(keys,vals,n,ng+h(v),v) end
    end
    local look=H.LOOK
    while n>0 do
        local _
        _,u,n=heapPop(keys,vals,n)
        if not closed[u] then
            closed[u]=true
            count=count+1
            if count%look==0 then breathe() end
            if u==target then break end
            if targets and targets[u] then left=left-1;if left<=0 or o.any then break end end
            g=dist[u]
            if reverse then local k=ClassOf(u);ucost=k>0 and cc[k] or nil end
            H.Each(u,relax)
            if o.jumps then
                local js=(reverse and H.jumpTo or H.jumpFrom)[u]
                if js then
                    if type(js)=="number" then js={js} end
                    for _,j in ipairs(js) do
                        local v=reverse and H.JumpFrom(j) or H.JumpTo(j)
                        local jc=H.jcost[j]
                        if jc and not closed[v] and region[ClusterOfCell(CellOf(v))] then
                            local ng=g+jc
                            if not dist[v] or ng<dist[v] then dist[v]=ng;from[v]=u;n=heapPush(keys,vals,n,ng+h(v),v) end
                        end
                    end
                end
            end
        end
    end
    return dist,from,count
end

---------------------------------------------------------------- search on the abstract graph
function H.ANode(a) return u32(H.anode,(a-1)*4+1) end
local function regionOf(n)
    local cols,C=H.cols,H.C
    local i=H.CellOf(n)
    local x,y=i%cols,floor(i/cols)
    local r={}
    for dy=-1,1 do for dx=-1,1 do
        local nx,ny=x+dx,y+dy
        if nx>=0 and ny>=0 and nx<cols and ny<H.rows then r[floor(nx/C)+floor(ny/C)*H.ccols]=true end
    end end
    return r
end
H.RegionOf=regionOf
local function acl(a) return H.ClusterOfCell(H.CellOf(H.ANode(a))) end
local function backtrack(fromT,a,b)
    local out={}
    local x=b
    while x do table.insert(out,1,x);if x==a then break end;x=fromT[x] end
    return out
end
-- The way from node s to node g. abstract: only the abstract chain (s, the entrances, g; jumps in stats.jumps).
-- Else refined on the cells inside the chain's clusters (corridor nil), or afterwards the best way inside the
-- clusters the chain touches (corridor 0) and the ring round them (1). Returns nodes, cost, stats.
-- A node's search to the abstract nodes of the clusters round it (its region), kept for the walks after it (Claude
-- 2026-10-26, Brill to Undercity: the walks to the inn on the city's level found no way, each from three layers to
-- three, and searched the same cells round the same ends 110 times, 1.7 of 2.1 s). Kept while the costs stay
-- (H:Costs), at most LOCALCACHE of them. targets: the region's abstract nodes (the same for the same node).
H.LOCALCACHE=64
H.localCache,H.localCount={},0
function H.LocalOf(region,n,targets,reverse,keep)
    local key=reverse and -n-1 or n
    if keep then
        local c=H.localCache[key]
        if c then return c[1],c[2],0 end
    end
    local d,f,count=H.Local(region,n,{targets=targets,reverse=reverse})
    if keep then
        if H.localCount>=H.LOCALCACHE then H.localCache,H.localCount={},0 end
        H.localCache[key]={d,f}
        H.localCount=H.localCount+1
    end
    return d,f,count
end
-- The part a node is in (H.acomp): of the first abstract node of its region it walks to (reverse: that walks to it),
-- or nil (none in reach there). targ: {[node]=abstract index}. Kept with the local searches (H.localCache).
function H.PartOf(region,n,targ,reverse)
    local key="p"..(reverse and -n-1 or n)
    local v=H.localCache[key]
    if v~=nil then return v or nil end
    local d=H.Local(region,n,{targets=targ,reverse=reverse,any=true})
    v=false
    for nd,a in pairs(targ) do if d[nd] then v=u24(H.acomp,(a-1)*3+1);break end end
    if H.localCount>=H.LOCALCACHE then H.localCache,H.localCount={},0 end
    H.localCache[key]=v
    H.localCount=H.localCount+1
    return v or nil
end
function H.Find(s,g,corridor,abstract)
    local cols,cell=H.cols,H.cell
    local stats={}
    if s==g then return {s},0,stats end
    local sreg,greg=regionOf(s),regionOf(g)
    local starg,gtarg={},{}
    for cid in pairs(sreg) do local f,k=H.afirst[cid],H.acount[cid];if f then for j=0,k-1 do starg[H.ANode(f+j)]=f+j end end end
    for cid in pairs(greg) do local f,k=H.afirst[cid],H.acount[cid];if f then for j=0,k-1 do gtarg[H.ANode(f+j)]=f+j end end end
    local st={};for i in pairs(starg) do st[i]=true end
    local gt={};for i in pairs(gtarg) do gt[i]=true end
    local direct=false
    for cid in pairs(sreg) do if greg[cid] then direct=true end end
    if direct then st[g]=true end
    -- (first the part each end is in, from the first abstract node it reaches - one node will do, they all lie in
    -- one part; parts that never meet: no way, without searching the clusters round both ends; Claude 2026-10-26,
    -- Brill to Undercity's inn)
    if H.acomp then
        local pa,pb=H.PartOf(sreg,s,starg,false),H.PartOf(greg,g,gtarg,true)
        -- (an end that reaches no abstract node round it - the inn in a closed hall below - is walked to from
        -- nowhere else: every way in crosses an entrance or a jump's end, and those are abstract nodes. Ends whose
        -- regions meet (direct) may still walk to each other inside them; then both reach the same abstract nodes,
        -- or neither reaches any: only that case is searched)
        local apart
        if direct then apart=(pa==nil)~=(pb==nil) or (pa~=nil and not H.PartsMeet({[pa]=true},{[pb]=true}))
        else apart=pa==nil or pb==nil or not H.PartsMeet({[pa]=true},{[pb]=true}) end
        if apart then
            stats.apart=true
            H.stats.apartEarly=(H.stats.apartEarly or 0)+1
            return nil,nil,stats
        end
    end
    local sdist,sfrom,c1=H.LocalOf(sreg,s,st,false,not direct)
    local gdist,gfrom,c2=H.LocalOf(greg,g,gt,true,not direct)
    stats.localNodes=c1+c2
    if H.acomp and not (direct and sdist[g]) then
        local meet=H.PartsMeet(partsOf(starg,sdist),partsOf(gtarg,gdist))
        if not meet then H.stats.apartLate=(H.stats.apartLate or 0)+1 end
        if not meet then stats.apart=true;return nil,nil,stats end
    end
    local gc=H.CellOf(g)
    local gx,gy=gc%cols,floor(gc/cols)
    local FL=H.floor*cell
    local function h(n)
        local c=H.CellOf(n)
        local dx,dy=abs(c%cols-gx),abs(floor(c/cols)-gy)
        return (max(dx,dy)+(SQRT2-1)*min(dx,dy))*FL
    end
    local keys,vals,n={},{},0
    local dist,from,closed,via={},{},{},{}
    local best=direct and sdist[g] or nil
    local function relax(m,ng,p,how)
        if m==-1 then
            if not best or ng<best then best=ng;from[-1]=p end
            return
        end
        local old=dist[m]
        if not old or ng<old then dist[m]=ng;from[m]=p;via[m]=how;n=heapPush(keys,vals,n,ng+h(H.ANode(m)),m) end
    end
    if best then from[-1]=0 end
    for i,m in pairs(starg) do if sdist[i] then relax(m,sdist[i],0) end end
    local expanded=0
    local QUANT,NONE=H.QUANT,H.NONE
    while n>0 do
        local f,m
        f,m,n=heapPop(keys,vals,n)
        if best and f>=best then break end
        if not closed[m] then
            closed[m]=true
            expanded=expanded+1
            if expanded%H.LOOK==0 then breathe() end
            local gm=dist[m]
            local mn=H.ANode(m)
            if gdist[mn] then relax(-1,gm+gdist[mn],m) end
            -- (only the nodes of its group: H.ac, place in the group, its size, the block's first entry)
            local row=H.dm[acl(m)]
            local ao=(m-1)*5
            local pos,kc=byte(H.ac,ao+1,ao+2)
            local g0=m-pos
            local base=u24(H.ac,ao+3)+pos*kc
            for b=0,kc-1 do
                local t=g0+b
                if b~=pos and not closed[t] then
                    local o=(base+b)*2+1
                    local x1,x2=byte(row,o,o+1)
                    local v=x1+x2*256
                    if v~=DMNONE then
                        if v>=32768 then v=32768+(v-32768)*64 end
                        relax(t,gm+v/QUANT,m,"intra")
                    end
                end
            end
            local e0,e1=u24(H.ioff,(m-1)*3+1),u24(H.ioff,m*3+1)
            for e=e0,e1-1 do
                local o=e*6+1
                local t=u24(H.iedge,o)
                if not closed[t] then relax(t,gm+u24(H.iedge,o+3)/QUANT,m,"step") end
            end
            local js=H.jumpFrom[mn]
            if js then
                if type(js)=="number" then js={js} end
                for _,j in ipairs(js) do
                    local t=H.ajump[H.JumpTo(j)]
                    local jc=H.jcost[j]
                    if t and jc and not closed[t] then relax(t,gm+jc,m,j) end
                end
            end
        end
    end
    stats.abstractNodes=expanded
    if not best then return nil,nil,stats end
    local chain={}
    local at=-1
    while at~=0 do table.insert(chain,1,at);at=from[at] end
    if abstract then
        local out,jumps={s},{}
        for _,m in ipairs(chain) do
            if m~=-1 then
                out[#out+1]=H.ANode(m)
                if type(via[m])=="number" then jumps[#out]=via[m] end
            end
        end
        if out[#out]~=g then out[#out+1]=g end
        stats.jumps=jumps
        return out,best,stats
    end
    local nodes={s}
    local function append(list) for j=2,#list do nodes[#nodes+1]=list[j] end end
    local prev=0
    for _,m in ipairs(chain) do
        if m==-1 then
            if prev==0 then append(backtrack(sfrom,s,g))
            else
                local x=H.ANode(prev)
                local out={x}
                while x~=g do x=gfrom[x];out[#out+1]=x end
                append(out)
            end
        else
            local mn=H.ANode(m)
            if prev==0 then append(backtrack(sfrom,s,mn))
            elseif via[m]=="intra" then
                local _,f2=H.Local({[acl(m)]=true},H.ANode(prev),{target=mn})
                append(backtrack(f2,H.ANode(prev),mn))
            else nodes[#nodes+1]=mn end
        end
        prev=m
    end
    if corridor then
        local region={}
        for _,c in ipairs(nodes) do region[H.ClusterOfCell(H.CellOf(c))]=true end
        if corridor>0 then
            local more={}
            for cid in pairs(region) do
                local X,Y=cid%H.ccols,floor(cid/H.ccols)
                for dy=-corridor,corridor do for dx=-corridor,corridor do
                    local x,y=X+dx,Y+dy
                    if x>=0 and y>=0 and x<H.ccols and y<H.crows then more[x+y*H.ccols]=true end
                end end
            end
            region=more
        end
        local d,f=H.Local(region,s,{target=g,jumps=true})
        if d[g] then nodes=backtrack(f,s,g);best=d[g] end
    end
    return nodes,best,stats
end
-- From node s to each of goals (nodes near each other: the crossings of a town's edge), in one search (Claude
-- 2026-10-25, Florian's way to Menethil's inn: the plan measured one crossing at a time, the nearest by the line
-- first, and took a harbour crossing reached by swimming; the gate was never measured). The abstract graph is
-- searched towards the box round the goals' clusters (A*, the distance to the box: exact on every abstract node
-- in it), then the cells round the goals from all of those at once. MANYSLACK: how much dearer than the first
-- abstract node in the box the search still goes on. Returns {[goal]={nodes, cost, jumps}} (nodes: the abstract
-- chain, then the cells to the goal; jumps as H.Find's stats.jumps) and whether a goal left out counts as without a
-- way: always (every abstract node in the box reached, the graph searched out, or the search cut MANYSLACK dearer
-- than the nearest end: a crossing that much further round is never the one to take; Claude 2026-10-25, Menethil:
-- searched alone, the crossing on the wall's other side searched the whole continent, 0.3 s).
H.MANYSLACK=4000
function H.FindMany(s,goals)
    local cols,cell,C=H.cols,H.cell,H.C
    local sreg=regionOf(s)
    local greg={}
    local bx0,by0,bx1,by1
    for _,g in ipairs(goals) do
        for cid in pairs(regionOf(g)) do
            greg[cid]=true
            local X,Y=cid%H.ccols,floor(cid/H.ccols)
            bx0,by0=min(bx0 or X*C,X*C),min(by0 or Y*C,Y*C)
            bx1,by1=max(bx1 or X*C+C-1,X*C+C-1),max(by1 or Y*C+C-1,Y*C+C-1)
        end
    end
    local inBox={}
    for cid in pairs(greg) do local f,k=H.afirst[cid],H.acount[cid];if f then for j=0,k-1 do inBox[f+j]=true end end end
    local left=0
    for _ in pairs(inBox) do left=left+1 end
    local starg={}
    for cid in pairs(sreg) do local f,k=H.afirst[cid],H.acount[cid];if f then for j=0,k-1 do starg[H.ANode(f+j)]=f+j end end end
    local st={};for i in pairs(starg) do st[i]=true end
    -- (no end whose part meets yours, and none near: no way to any, sure; as H.Find)
    if H.acomp then
        local near=false
        for cid in pairs(sreg) do if greg[cid] then near=true end end
        if not near then
            local pa=H.PartOf(sreg,s,starg,false)
            local any=false
            if pa then
                for _,g in ipairs(goals) do
                    if not any then
                        local gr=regionOf(g)
                        local gt={}
                        for cid in pairs(gr) do local f,k=H.afirst[cid],H.acount[cid];if f then for j=0,k-1 do gt[H.ANode(f+j)]=f+j end end end
                        local pb=H.PartOf(gr,g,gt,true)
                        if pb and H.PartsMeet({[pa]=true},{[pb]=true}) then any=true end
                    end
                end
            end
            if not any then
                H.stats.apartEarly=(H.stats.apartEarly or 0)+1
                H.manyStats={localNodes=0,abstractNodes=0}
                return {},true
            end
        end
    end
    local sdist,sfrom,c1=H.LocalOf(sreg,s,st,false,true)
    local FL=H.floor*cell
    local function h(nd)
        local c=H.CellOf(nd)
        local x,y=c%cols,floor(c/cols)
        local dx=max(0,bx0-x,x-bx1)
        local dy=max(0,by0-y,y-by1)
        return (max(dx,dy)+(SQRT2-1)*min(dx,dy))*FL
    end
    local keys,vals,n={},{},0
    local dist,from,closed,via={},{},{},{}
    local function relax(m,ng,p,how)
        local old=dist[m]
        if not old or ng<old then dist[m]=ng;from[m]=p;via[m]=how;n=heapPush(keys,vals,n,ng+h(H.ANode(m)),m) end
    end
    for i,m in pairs(starg) do if sdist[i] then relax(m,sdist[i],0) end end
    local expanded,first,cut=0,nil,false
    local QUANT,NONE=H.QUANT,H.NONE
    while n>0 and left>0 do
        local f,m
        f,m,n=heapPop(keys,vals,n)
        if first and f>first+H.MANYSLACK then cut=true;break end
        if not closed[m] then
            closed[m]=true
            expanded=expanded+1
            if expanded%H.LOOK==0 then breathe() end
            if inBox[m] then left=left-1;first=first or f end
            local gm=dist[m]
            -- (only the nodes of its group: H.ac, place in the group, its size, the block's first entry)
            local row=H.dm[acl(m)]
            local ao=(m-1)*5
            local pos,kc=byte(H.ac,ao+1,ao+2)
            local g0=m-pos
            local base=u24(H.ac,ao+3)+pos*kc
            for b=0,kc-1 do
                local t=g0+b
                if b~=pos and not closed[t] then
                    local o=(base+b)*2+1
                    local x1,x2=byte(row,o,o+1)
                    local v=x1+x2*256
                    if v~=DMNONE then
                        if v>=32768 then v=32768+(v-32768)*64 end
                        relax(t,gm+v/QUANT,m,"intra")
                    end
                end
            end
            local e0,e1=u24(H.ioff,(m-1)*3+1),u24(H.ioff,m*3+1)
            for e=e0,e1-1 do
                local o=e*6+1
                local t=u24(H.iedge,o)
                if not closed[t] then relax(t,gm+u24(H.iedge,o+3)/QUANT,m,"step") end
            end
            local js=H.jumpFrom[H.ANode(m)]
            if js then
                if type(js)=="number" then js={js} end
                for _,j in ipairs(js) do
                    local t=H.ajump[H.JumpTo(j)]
                    local jc=H.jcost[j]
                    if t and jc and not closed[t] then relax(t,gm+jc,m,j) end
                end
            end
        end
    end
    -- The cells round the goals, from every abstract node reached in the box (and from s when it lies in it).
    local seeds,seedA={},{}
    for m in pairs(inBox) do
        if closed[m] then local nd=H.ANode(m);if not seeds[nd] or dist[m]<seeds[nd] then seeds[nd]=dist[m];seedA[nd]=m end end
    end
    if greg[H.ClusterOfCell(H.CellOf(s))] then seeds[s]=0;seedA[s]=0 end
    local targets={}
    for _,g in ipairs(goals) do targets[g]=true end
    local ldist,lfrom,c2=H.Local(greg,nil,{targets=targets,seeds=seeds})
    H.manyStats={localNodes=c1+c2,abstractNodes=expanded}
    local out={}
    for _,g in ipairs(goals) do
        breathe()
        if ldist[g] then
            local tail={g}
            local x=g
            while seedA[x]==nil do x=lfrom[x];table.insert(tail,1,x) end
            local chain={}
            local m=seedA[x]
            while m and m~=0 do table.insert(chain,1,m);m=from[m] end
            local nodes,jumps={s},{}
            for _,a in ipairs(chain) do
                local nd=H.ANode(a)
                if nodes[#nodes]~=nd then nodes[#nodes+1]=nd end
                if type(via[a])=="number" then jumps[#nodes]=via[a] end
            end
            for i=2,#tail do nodes[#nodes+1]=tail[i] end
            if #tail==1 and nodes[#nodes]~=g then nodes[#nodes+1]=g end
            out[g]={nodes=nodes,cost=ldist[g],jumps=jumps}
        end
    end
    H.manyStats.cut=cut
    return out,true
end

---------------------------------------------------------------- points, pulling tight
function H.Point(n)
    local c=H.CellOf(n)
    local g=H.geo
    return g.minX+((c%H.cols)+.5)*H.cell/g.width,g.minY+(floor(c/H.cols)+.5)*H.cell/g.height
end
-- The straight line from node a to node b on the graph, sampled every quarter cell: each new cell must hold a node
-- joined by a step to one before (the line keeps its layers: through a tunnel, not over the mountain), none
-- dearer than CLEAR. Every layer of a cell so joined is followed, not the first found alone (Claude 2026-10-27,
-- gather_cases elwynn_copper: a diagonal line through a cell of two layers took the one that did not lead on).
-- Returns whether it reaches b, and its cost (along the layers that lead to b, the cheapest).
function H.Line(a,b)
    local cols,cell=H.cols,H.cell
    local ca,cb=H.CellOf(a),H.CellOf(b)
    local ax,ay,bx,by=ca%cols+.5,floor(ca/cols)+.5,cb%cols+.5,floor(cb/cols)+.5
    local dx,dy=bx-ax,by-ay
    local len=sqrt(dx*dx+dy*dy)
    local n=max(1,math.ceil(len*4))
    local piece=len*cell/n
    local ux,uy=floor(ax),floor(ay)
    -- the layers the line may be on in the cell it is in, each with its cost so far
    local cur,cost={a},{[a]=0}
    -- Two private frontiers per invocation, reused as the line enters cells.
    -- No global scratch state: nested/interleaved plans cannot share buffers.
    local nxt,nc={},{}
    local want,cu
    local function visit(v)
        if H.CellOf(v)==want then
            local cv=H.Cost(v)
            if cv and cv<=H.CLEAR and (not nc[v] or cu<nc[v]) then
                if not nc[v] then nxt[#nxt+1]=v end
                nc[v]=cu
            end
        end
    end
    local polygons={}
    for i=1,n do
        local x,y=floor(ax+dx*i/n),floor(ay+dy*i/n)
        if x~=ux or y~=uy then
            want=y*cols+x
            for j=#nxt,1,-1 do nxt[j]=nil end
            for u in pairs(nc) do nc[u]=nil end
            for _,u in ipairs(cur) do
                cu=cost[u]
                H.Each(u,visit)
            end
            if #nxt==0 then return false end
            cur,nxt=nxt,cur
            cost,nc=nc,cost
            ux,uy=x,y
        end
        -- Reachable adjacent cells do not prove that this straight piece
        -- crosses their actual floor (Undercity's Royal Quarter stair).
        -- Where precise polygons exist, keep only layers covering the sample.
        if H.pn then
            local px,py=(ax+dx*i/n)*cell,(ay+dy*i/n)*cell
            -- Compact this line's private frontier in place. Sampling every
            -- quarter cell used to allocate a filter table each time, even
            -- when the same single floor remained valid throughout the cell.
            local count,kept=#cur,0
            for j=1,count do
                local u=cur[j]
                local ps=polygons[u]
                if ps==nil then ps=H.NodePolys(u) or false;polygons[u]=ps end
                local inside=not ps
                if ps then for _,p in ipairs(ps) do if H.PolyHas(p,px,py) then inside=true;break end end end
                if inside then kept=kept+1;cur[kept]=u else cost[u]=nil end
            end
            for j=kept+1,count do cur[j]=nil end
            if kept==0 then return false end
        end
        -- (each piece of the line at the cost of the cell it ends in, as Grid.Clear sums it)
        for _,u in ipairs(cur) do cost[u]=cost[u]+(H.Cost(u) or 0)*piece end
    end
    if cost[b] then return true,cost[b] end
    return false,cost[cur[1]]
end
-- A chain pulled tight (as Grid.Trace, on the graph): a node kept only where the line from the last kept one stops
-- being walkable or costs more than the steps it replaces. Jumps stay as they are.
function H.Pull(nodes)
    local cols=H.cols
    local out={nodes[1]}
    local walked={0}
    for i=2,#nodes do
        local ca,cb=H.CellOf(nodes[i-1]),H.CellOf(nodes[i])
        local d=sqrt((ca%cols-cb%cols)^2+(floor(ca/cols)-floor(cb/cols))^2)*H.cell
        walked[i]=walked[i-1]+(H.Cost(nodes[i]) or 0)*d
    end
    local anchor=1
    for i=2,#nodes do
        if i%8==0 then breathe() end
        local a,b=nodes[i-1],nodes[i]
        local ca,cb=H.CellOf(a),H.CellOf(b)
        -- (a lift or teleport between neighbouring cells stays (a drop may be pulled over, it is walked off anyway): pulled over, the line went past it
        -- and the walk lost its jump; Claude 2026-10-28, the Wizard's Sanctum's portal down into the hall)
        local js=H.jumpFrom[a]
        if type(js)=="number" then js={js} end
        local jumped=false
        for _,j in ipairs(js or {}) do if H.JumpTo(j)==b and H.JumpLift(j) then jumped=true end end
        if jumped or max(abs(ca%cols-cb%cols),abs(floor(ca/cols)-floor(cb/cols)))>1 then
            if out[#out]~=a then out[#out+1]=a end
            out[#out+1]=b
            anchor=i
        else
            local ok,cost=H.Line(nodes[anchor],b)
            if not (ok and cost<=walked[i]-walked[anchor]+H.PULLSLACK) then
                if out[#out]~=a then out[#out+1]=a end
                anchor=i-1
            end
        end
    end
    if out[#out]~=nodes[#nodes] then out[#out+1]=nodes[#nodes] end
    return out
end

---------------------------------------------------------------- the walks of Navigate
-- The nodes of a continent point: the cell's layers walkable now, the one nearest z first (z: a door's floor, the
-- goal NPC's height), else the cell's largest layer first; none: the nearest walkable cell within 3.
H.ZTRY=15
function H.Nodes(x,y,z)
    local g=H.geo
    local cx,cy=floor((x-g.minX)*g.width/H.cell),floor((y-g.minY)*g.height/H.cell)
    if cx<0 or cy<0 or cx>=H.cols or cy>=H.rows then return {} end
    local cell=cy*H.cols+cx
    local list={}
    if H.Cost(cell) then list[1]={cell} end
    -- (extra layers are numbered in cell order: found by halving)
    local lo,count=H.Extras(cell)
    local k,bz=lo,nil
    while k<lo+count do
        if not bz then local d=byte(H.zd,k+1);if d>=128 then d=d-256 end;bz=(u16(H.zx,k*2+1)-32768)/10+d*2 end
        local n=H.NC+k
        if H.Cost(n) then list[#list+1]={n,(u16(H.zx,k*2+1)-32768)/10} end
        k=k+1
    end
    if z and #list>1 then
        if list[1][1]<H.NC then list[1][2]=bz end
        table.sort(list,function(a,b) return abs((a[2] or 1e9)-z)<abs((b[2] or 1e9)-z) end)
        -- A known height rules out the layers far from it (Claude 2026-10-25, Florian in Thunder Bluff: from the
        -- lift's foot, z 69, the third layer tried was the mesa's top, z 130, and the walk "found" there went up
        -- without the lift): those within ZTRY yards and those of unknown height stay, else the nearest alone.
        local keep={}
        for _,e in ipairs(list) do if not e[2] or abs(e[2]-z)<=H.ZTRY then keep[#keep+1]=e end end
        if #keep==0 then keep[1]=list[1] end
        list=keep
    end
    -- At a height whose layers here are all splinters (Ironforge, Mekkatorque on his stage): the nearest layer at
    -- that height (ZNEAR yd) round it, within 3 cells, that reaches further, first (else the floor of the hall is
    -- missed and the largest layer, the mountain above, is taken).
    if z then
        local here=false
        -- (a layer of unknown height here, a cell's only one, counts as at that height)
        for _,e in ipairs(list) do if (not e[2] or abs(e[2]-z)<=H.ZNEAR) and not H.Small(e[1]) then here=true;break end end
        if not here then
            local best
            for r=1,3 do
                for dy=-r,r do for dx=-r,r do
                    if not best and max(abs(dx),abs(dy))==r then
                        local nx,ny=cx+dx,cy+dy
                        if nx>=0 and ny>=0 and nx<H.cols and ny<H.rows then
                            breathe()
                            local first,cnt=H.Extras(ny*H.cols+nx)
                            for k=first,first+cnt-1 do
                                local zz=(u16(H.zx,k*2+1)-32768)/10
                                local n=H.NC+k
                                if not best and abs(zz-z)<=H.ZNEAR and H.Cost(n) and not H.Small(n) then best={n,zz} end
                            end
                        end
                    end
                end end
                if best then break end
            end
            if best then table.insert(list,1,best) end
        end
    end
    -- A level's height is an estimate across a cell, not the exact floor under
    -- the point. Among nearby heights prefer the polygon actually containing
    -- it: at Doras the closer height belonged to the ramp beside the platform,
    -- and refining from there drew the first segment through open air.
    if z and #list>1 and H.pn then
        local px,py=(x-g.minX)*g.width,(y-g.minY)*g.height
        local under,rest={},{}
        for _,e in ipairs(list) do
            local contains=false
            if not e[2] or abs(e[2]-z)<=H.ZNEAR then
                for _,p in ipairs(H.NodePolys(e[1]) or {}) do
                    if H.PolyHas(p,px,py) then contains=true;break end
                end
            end
            local into=contains and under or rest
            into[#into+1]=e
        end
        for _,e in ipairs(rest) do under[#under+1]=e end
        list=under
    end
    -- No height (your own spot without NPCs near to measure it): where the data has the navmesh's polygons, the
    -- layers with a polygon right under the point first (Claude 2026-10-25, Thelsamar's inn: the cell's largest
    -- layer was the ground outside, and the way ran through the wall).
    if not z and #list>1 and H.pn then
        local px,py=(x-g.minX)*g.width,(y-g.minY)*g.height
        local under={}
        for _,e in ipairs(list) do
            -- (within a yard: a spot on a polygon's edge)
            for _,p in ipairs(H.NodePolys(e[1]) or {}) do
                if H.PolyHas(p,px,py) or H.PolyHas(p,px+1,py) or H.PolyHas(p,px-1,py) or H.PolyHas(p,px,py+1) or H.PolyHas(p,px,py-1) then under[e[1]]=true;break end
            end
        end
        -- (of those the terrain's own layer first: a ground floor rather than the roof over it)
        local first,second,rest={},{},{}
        for _,e in ipairs(list) do
            local c=H.classes[H.ClassOf(e[1])]
            if under[e[1]] and c and c[3]==1 then first[#first+1]=e elseif under[e[1]] then second[#second+1]=e else rest[#rest+1]=e end
        end
        for _,e in ipairs(second) do first[#first+1]=e end
        for _,e in ipairs(rest) do first[#first+1]=e end
        list=first
    end
    -- Splinters last (Claude 2026-10-25, Ironforge: beside Mekkatorque the layers nearest his height were bits of a
    -- stage reaching 1-6 nodes; the three tried were all such, the floor never, and every walk from him failed):
    -- a layer whose steps reach fewer than SMALL nodes comes after the others.
    if #list>1 then
        local big,small={},{}
        for _,e in ipairs(list) do breathe();if H.Small(e[1]) then small[#small+1]=e else big[#big+1]=e end end
        if #big>0 and #small>0 then
            for _,e in ipairs(small) do big[#big+1]=e end
            list=big
        end
    end
    local out={}
    for i,e in ipairs(list) do out[i]=e[1] end
    if #out==0 then
        for r=1,3 do
            local best,bd
            for dy=-r,r do for dx=-r,r do
                if max(abs(dx),abs(dy))==r then
                    local nx,ny=cx+dx,cy+dy
                    if nx>=0 and ny>=0 and nx<H.cols and ny<H.rows and H.Cost(ny*H.cols+nx) then
                        local d=dx*dx+dy*dy
                        if not bd or d<bd then best,bd=ny*H.cols+nx,d end
                    end
                end
            end end
            if best then out[1]=best;break end
        end
    end
    return out
end
-- Does node n reach fewer than SMALL nodes on walkable steps (a splinter of a layer)?
H.SMALL=40
H.ZNEAR=4
function H.Small(n)
    local seen,q,head={[n]=true},{n},1
    while head<=#q do
        local u=q[head];head=head+1
        H.Each(u,function(v) if not seen[v] and #q<H.SMALL and H.Cost(v) then seen[v]=true;q[#q+1]=v end end)
        if #q>=H.SMALL then return false end
    end
    return true
end
-- The ends' layers tried in turn (at most TRIES each) until one pair has a way.
-- An NPC or object you go to is reached where you can talk to it, not on its own spot (Claude 2026-10-25, Florian:
-- Harick stands behind his counter in Ironforge; his own spot is reached only round the back, from outside): the
-- goal's end is every layer within REACH yd of it across and REACHZ yd in height (the cell's and its neighbours'),
-- the one the way reaches dearest-least taken, and the way ends at that layer's point nearest the goal.
H.REACH=4.5
H.REACHZ=3
function H.GoalAt(x,y)
    local N=Routing.Navigate
    local g=N and N.goal
    if not (g and type(g.z)=="number" and g.x and g.y) then return nil end
    local gm=H.geo
    local d=sqrt(((x-g.x)*gm.width)^2+((y-g.y)*gm.height)^2)
    if d>8 then return nil end
    return g
end
function H.ReachNodes(x,y,z)
    local g=H.geo
    local px,py=(x-g.minX)*g.width,(y-g.minY)*g.height
    local cell=H.cell
    local cx,cy=floor(px/cell),floor(py/cell)
    local out,small={},{}
    for dy=-1,1 do for dx=-1,1 do
        local nx,ny=cx+dx,cy+dy
        if nx>=0 and ny>=0 and nx<H.cols and ny<H.rows then
            -- (the point of the cell nearest the goal)
            local qx=min(max(px,nx*cell),(nx+1)*cell)
            local qy=min(max(py,ny*cell),(ny+1)*cell)
            if sqrt((qx-px)^2+(qy-py)^2)<=H.REACH then
                local c=ny*H.cols+nx
                local first,count=H.Extras(c)
                local bz
                if count>0 then local d=byte(H.zd,first+1);if d>=128 then d=d-256 end;bz=(u16(H.zx,first*2+1)-32768)/10+d*2 end
                local cand={}
                if H.Cost(c) then cand[#cand+1]={c,bz} end
                for k=first,first+count-1 do
                    local n=H.NC+k
                    if H.Cost(n) then cand[#cand+1]={n,(u16(H.zx,k*2+1)-32768)/10} end
                end
                for _,e in ipairs(cand) do
                    -- (a layer of unknown height only in the goal's own cell: round it, the largest layer can be
                    -- the plain under Thunder Bluff's mesa, beside Pala's inn on top)
                    if not z or (e[2] and abs(e[2]-z)<=H.REACHZ) or (not e[2] and dx==0 and dy==0) then
                        local cxx,cyy=g.minX+qx/g.width,g.minY+qy/g.height
                        local row={e[1],cxx,cyy}
                        if H.Small(e[1]) then small[#small+1]=row else out[#out+1]=row end
                    end
                end
            end
        end
    end end
    if #out==0 then out=small end
    return out
end
-- Pairs that cannot meet are not searched (Claude 2026-10-25, a 5-yd walk in Ironforge took 0.4 s): a splinter
-- (H.Small: its whole part of the graph under SMALL nodes) never meets a node of a larger part.
-- Searches known to find no way (Claude 2026-10-25, Florian in Thunder Bluff: four walks found none in 0.4-0.9 s
-- each, and the same ones again in every new plan): kept per pair of nodes while the costs stay (H:Costs). H.Find
-- has no limit: its "none" is sure.
H.nopath={}
local function find(s,g,corridor,abstract)
    local k=not corridor and s*16777216+g
    if k and H.nopath[k] then H.stats.nopathKnown=(H.stats.nopathKnown or 0)+1;return nil end
    local nodes,cost,st=H.Find(s,g,corridor,abstract)
    if not nodes and k then H.nopath[k]=true end
    return nodes,cost,st
end
function H.Query(x1,y1,z1,x2,y2,z2,corridor,abstract)
    local A=H.Nodes(x1,y1,z1)
    local tries=0
    local goal=H.GoalAt(x2,y2)
    local tail=goal and H.TailFor(goal)
    if tail then
        for i=1,min(H.TRIES,#A) do
            tries=tries+1
            local nodes,cost,st=find(A[i],tail.node,corridor,abstract)
            if nodes then return nodes,cost,st,tries,tail.x,tail.y,tail end
        end
    end
    if goal then
        local reach=H.ReachNodes(goal.x,goal.y,goal.z)
        if #reach>1 then
            local goals,at={},{}
            for _,r in ipairs(reach) do goals[#goals+1]=r[1];at[r[1]]=r end
            -- (the walk's choice kept for its refining at the end: one search to all of them per walk)
            local key=string.format("%.6f:%.6f:%.6f:%.6f",x1,y1,x2,y2)
            for i=1,min(H.TRIES,#A) do
                tries=tries+1
                local best=H.reachPick[key..":"..A[i]]
                if not best then
                    local found=H.FindMany(A[i],goals)
                    local bc
                    for g,r in pairs(found) do if not bc or r.cost<bc then best,bc=g,r.cost end end
                    if best then H.reachPick[key..":"..A[i]]=best end
                end
                if best then
                    local nodes,cost,st=find(A[i],best,corridor,abstract)
                    if nodes then return nodes,cost,st,tries,at[best][2],at[best][3] end
                end
            end
        end
    end
    local B=H.Nodes(x2,y2,z2)
    local smallA,smallB={},{}
    for i=1,min(H.TRIES,#A) do
        for j=1,min(H.TRIES,#B) do
            if smallA[i]==nil then smallA[i]=H.Small(A[i]) end
            if smallB[j]==nil then smallB[j]=H.Small(B[j]) end
            if smallA[i]==smallB[j] then
                tries=tries+1
                local nodes,cost,st=find(A[i],B[j],corridor,abstract)
                if nodes then return nodes,cost,st,tries end
            end
        end
    end
    return nil,nil,nil,tries
end
-- A precomputed walk's stored shape (jump number j): baked into the data (jsh from jso: zigzag varints of 1/8 yd from
-- the grid's corner, each point after the first as the difference; tools/hpa/hierarchy.py shape_bytes), else straight
-- from the shipped network (its raw edge), without building the network's tables.
-- (decoded once per jump and way: a town's crossings measured at once share most of their jumps; Claude 2026-10-25,
-- Theramore -> Gadgetzan: 2776 decodes of 61 jumps for 43 crossings)
H.jumpPts={}
function H.JumpPoints(j)
    local hit=H.jumpPts[j]
    if hit~=nil then return hit or nil end
    local pts=H.JumpPointsOf(j)
    H.jumpPts[j]=pts or false
    return pts
end
function H.JumpPointsOf(j)
    local s
    if H.JumpShaped(j) then s=H.jsh:sub(u24(H.jso,(j-1)*3+1)+1,u24(H.jso,j*3+1)) end
    if s then
        local g=H.geo
        local out,x,y,u,f,axis={},0,0,0,1,1
        for i=1,#s do
            local b=byte(s,i)
            u=u+(b%128)*f
            if b>=128 then f=f*128
            else
                local d=u%2==0 and u/2 or -(u+1)/2
                if axis==1 then x=x+d;axis=2 else y=y+d;out[#out+1]={g.minX+x/8/g.width,g.minY+y/8/g.height};axis=1 end
                u,f=0,1
            end
        end
        return out
    end
    return nil
end
-- Whether a continent point lies in node n's cell.
local function inCell(n,x,y)
    local g=H.geo
    local cx,cy=floor((x-g.minX)*g.width/H.cell),floor((y-g.minY)*g.height/H.cell)
    return cy*H.cols+cx==H.CellOf(n)
end
H.InCell=inCell
-- A precomputed walk's shape begins and ends at its exact points, inside the cells of its end nodes: the cells' middles
-- beside them are left out (Claude 2026-10-26, Florian's walk Brill -> Undercity: each middle lay a few yards back
-- from the shape's end, the way went out and back there, and the tracker, never seeing you walk that spur, stopped
-- before it - the walked part stayed drawn, arrows both ways).
-- A node's height: an extra layer's own, a cell's base layer's from its first extra layer (as H.Nodes); nil unknown.
function H.NodeZ(n)
    if n>=H.NC then return (u16(H.zx,(n-H.NC)*2+1)-32768)/10 end
    local lo,count=H.Extras(n)
    if count>0 then local d=byte(H.zd,lo+1);if d>=128 then d=d-256 end;return (u16(H.zx,lo*2+1)-32768)/10+d*2 end
    return nil
end
function H.Points(nodes,jumps,x1,y1,x2,y2)
    local pts={{x1,y1}}
    local middle={}
    for i=2,#nodes-1 do
        local j=jumps and jumps[i]
        local shape=j and H.JumpNet(j) and H.JumpPoints(j) or nil
        if shape and #shape==0 then shape=nil end
        if shape then
            -- (never a lift's end: Navigate splits the walk there)
            if middle[#pts] and not pts[#pts].lift and inCell(nodes[i-1],shape[1][1],shape[1][2]) then pts[#pts]=nil;middle[#pts+1]=nil end
            for _,p in ipairs(shape) do pts[#pts+1]={p[1],p[2]} end
        end
        if not (shape and inCell(nodes[i],shape[#shape][1],shape[#shape][2])) then
            local x,y=H.Point(nodes[i])
            -- (with the node's height where known: Navigate's loop cut tells a climb from a spur by it)
            pts[#pts+1]={x,y,z=H.NodeZ(nodes[i])}
            middle[#pts]=true
        end
        -- (a lift ridden to here from the point before: Navigate makes it a step of its own)
        if j and H.JumpLift(j) then pts[#pts].lift=j end
    end
    -- (a lift into the last node, the walk's end there: marked on the end; a short piece of a walk between a climb
    -- drawn on the polygons and the end piece is often just the lift's two nodes - the Wizard's Sanctum's portal down
    -- into the hall lost its step "Use the teleport"; Claude 2026-10-28)
    local jl=#nodes>=2 and jumps and jumps[#nodes]
    pts[#pts+1]={x2,y2,lift=(jl and H.JumpLift(jl)) and jl or nil}
    return pts
end
-- What a way's walks cost the planner (the log): counts and milliseconds.
H.stats={}
H.reachPick={}
function H:Begin() H.stats={walks=0,walkMs=0,tries=0,refined=0,refineMs=0,longestRefineMs=0};H.jumpPts={};H.reachPick={} end
local function clock() local f=rawget(_G,"debugprofilestop");return f and f() or 0 end
H.ABSTRACT="navmesh (abstract)"
-- A walk on the ground for Navigate (N:Walk): measured on the abstract graph only. Returns path, note, ok, status.
---------------------------------------------------------------- towns' levels on the navmesh
-- A town's levels (Data/Towns.lua: its ground level, buildings, a cellar found on the navmesh) are walked on the same
-- graph as the ground (Claude 2026-10-25, Florian: the towns' walks on the classic grid took 1-10 s each): their ends
-- on the layer at the level's height.
-- Since the capitals followed (Claude 2026-10-25): every level that knows its height (height samples, z or a band),
-- the capitals' painted levels (Data/Maps.lua) as much as the towns'; a level without one walks the classic way.
function H.TownLevel(level)
    if not level or not Routing.Level then return false end
    local lv=Routing.Level:Find(level)
    if type(lv)~="table" then return false end
    local id=tostring(lv.id or "")
    if lv.townGround==true or lv.origin=="navmesh" or id:sub(1,5)=="town-" then return true end
    return (type(lv.heights)=="table" and #lv.heights>=4) or type(lv.z)=="number" or (type(lv.lo)=="number" and type(lv.hi)=="number")
end
-- A level's height at a continent point: its nearest height sample (heights: zone x, y, low, high), else its band.
H.levelZ={}
function H.LevelZ(level,cont,x,y)
    local lv,mapID=Routing.Level:Find(level)
    if type(lv)~="table" then return nil end
    local pts=H.levelZ[level]
    if pts==nil then
        pts={}
        local hs=type(lv.heights)=="table" and lv.heights or {}
        for i=1,#hs-3,4 do
            local c,cx,cy=Routing:OnContinent(mapID,hs[i],hs[i+1])
            if c==cont then pts[#pts+1]=cx;pts[#pts+1]=cy;pts[#pts+1]=(hs[i+2]+hs[i+3])/2 end
        end
        H.levelZ[level]=pts
    end
    local best,bd
    for i=1,#pts,3 do
        local d=(pts[i]-x)^2+(pts[i+1]-y)^2
        if not bd or d<bd then best,bd=pts[i+2],d end
    end
    if best then return best end
    if type(lv.z)=="number" then return lv.z end
    if type(lv.lo)=="number" and type(lv.hi)=="number" then return (lv.lo+lv.hi)/2 end
end
-- The heights of a walk's ends: a door's floor, the goal NPC's or yours, else the level's.
local function endZ(self,doors,key,level,cont,x,y)
    local z=doors and doors[key] or self.Z(x,y)
    if z==nil and level then z=H.LevelZ(level,cont,x,y) end
    return z
end
function H:Walk(cont,x1,y1,x2,y2,doors,level)
    local t0=clock()
    -- (your continent made current: another plan may have used another one in between)
    self:Use(cont)
    self:Costs()
    local z1=endZ(self,doors,"from",level,cont,x1,y1)
    local z2=endZ(self,doors,"to",level,cont,x2,y2)
    local nodes,_,st,tries,ex,ey,tail=H.Query(x1,y1,z1,x2,y2,z2,nil,true)
    if ex then x2,y2=ex,ey end
    local s=H.stats
    s.walks=(s.walks or 0)+1;s.tries=(s.tries or 0)+tries;s.walkMs=(s.walkMs or 0)+clock()-t0
    if not nodes then return {{x1,y1},{x2,y2}},"navmesh: no way on the ground",false,"nopath" end
    return H.AddTail(H.Points(nodes,st.jumps,x1,y1,x2,y2),tail),H.ABSTRACT,true,"ok"
end
-- A path with an NPC's end piece after it (its first point is the path's end).
function H.AddTail(path,tail)
    if not (path and tail) then return path end
    for i=2,#tail.pts do path[#path+1]=tail.pts[i] end
    if tail.stats~=false then H.stats.tails=(H.stats.tails or 0)+1 end
    return path
end
-- The yards of a chain of nodes (from x1, y1 to x2, y2): straight between nodes, a jump's own yards (Claude
-- 2026-10-25, the diagnosis: building every crossing's points and shapes took 110-167 ms of a town's search).
function H.ChainYards(nodes,jumps,x1,y1,x2,y2)
    local g=H.geo
    local function yd(ax,ay,bx,by) return sqrt(((bx-ax)*g.width)^2+((by-ay)*g.height)^2) end
    local px,py=x1,y1
    local total=0
    for i=2,#nodes do
        local x,y
        if i==#nodes then x,y=x2,y2 else x,y=H.Point(nodes[i]) end
        local j=jumps and jumps[i]
        if j and H.JumpLift(j) then total=total+H.LiftYards(j)
        elseif j then total=total+(H.JumpRank(j)) else total=total+yd(px,py,x,y) end
        px,py=x,y
    end
    if #nodes<2 then total=yd(x1,y1,x2,y2) end
    return total
end
-- Walks on the ground from one point to several ends (H.FindMany): ends {{x, y, z}, ...}. Returns {[i]=yards} for
-- the ends with a way, and {[i]=true} for those with none for sure (the others: measured one by one, if asked).
function H:WalkMany(cont,x1,y1,z1,ends)
    local t0=clock()
    -- (your continent made current: another plan may have used another one in between)
    self:Use(cont)
    self:Costs()
    local A=H.Nodes(x1,y1,z1)
    local goals,byNode={},{}
    for i,e in ipairs(ends) do
        local g=H.Nodes(e[1],e[2],e[3])[1]
        if g then
            if not byNode[g] then goals[#goals+1]=g;byNode[g]={} end
            table.insert(byNode[g],i)
        end
    end
    local out,none={},{}
    if A[1] and #goals>0 then
        local found,sure=H.FindMany(A[1],goals)
        for _,g in ipairs(goals) do
            local r=found[g]
            breathe()
            for _,i in ipairs(byNode[g]) do
                if r then out[i]=H.ChainYards(r.nodes,r.jumps,x1,y1,ends[i][1],ends[i][2]) elseif sure then none[i]=true end
            end
        end
    end
    local s=H.stats
    s.many=(s.many or 0)+1;s.walkMs=(s.walkMs or 0)+clock()-t0
    return out,none
end
-- The height of a leg's end when the way knows it: the goal NPC's.
-- Your own spot (Claude 2026-10-25, from Thelsamar's inn: without a height the cell's largest layer, the ground
-- outside, was taken and the way ran through the inn's wall): the middle of your height band from the NPCs near
-- (Height:Now) when it is at most ZSPAN yards wide.
H.ZSPAN=12
function H.Z(x,y)
    local N=Routing.Navigate
    local g=N and N.goal
    if g and type(g.z)=="number" and abs(x-g.x)<1e-7 and abs(y-g.y)<1e-7 then return g.z end
    local Height=Routing.Height
    if N and Height and Height.Now then
        local _,hx,hy=N:Here()
        if hx and abs(x-hx)<1e-7 and abs(y-hy)<1e-7 then
            local m=Height:Now()
            local span,low,high=Height.Span(m and m.set)
            if span and span<=H.ZSPAN then return (low+high)/2 end
        end
    end
end
-- A walk of the final way refined on the cells and pulled tight. Returns path or nil.
---------------------------------------------------------------- the ends inside buildings: the navmesh's polygons
-- Round the places inside buildings the data keeps the navmesh's own polygons (tools/hpa/polys.py: pn/pno/pnl the
-- polygons under a graph node; pc a polygon's corner and neighbour counts, pblk where each 16 polygons' corners
-- (pvi) and neighbours (pa: delta and own edge, see polyNear) begin; vx the corners: x, y in
-- 1/8 yd from the grid's corner, z in 1/16 yd). A walk's end there goes from polygon
-- to polygon (A*) and is pulled tight through the shared edges (the funnel, as Detour's findStraightPath), then the
-- cells take over (Claude 2026-10-25, Florian: "Start/Ziel in Gebaeuden").
H.POLYLOOK=4000  -- polygons searched at most for one end
function H.NodePolys(n)
    local pn=H.pn
    if not pn then return nil end
    local lo,hi=0,#pn/3-1
    while lo<=hi do
        local m=floor((lo+hi)/2)
        local v=u24(pn,m*3+1)
        if v==n then
            local a,b=u24(H.pno,m*3+1),u24(H.pno,m*3+4)
            local out={}
            for i=a,b-1 do out[#out+1]=u24(H.pnl,i*3+1) end
            return out
        end
        if v<n then lo=m+1 else hi=m-1 end
    end
    return nil
end
-- Where a polygon's corners and neighbours begin, and how many: first corner, corners, first neighbour, neighbours.
local function polyAt(p)
    local blk=floor(p/16)
    local c,nb=u24(H.pblk,blk*6+1),u24(H.pblk,blk*6+4)
    for i=blk*16,p-1 do local v=byte(H.pc,i+1);c=c+v%8;nb=nb+floor(v/8) end
    local v=byte(H.pc,p+1)
    return c,v%8,nb,floor(v/8)
end
-- The neighbours of polygon p: f(neighbour, edge of its own).
local function polyNear(p,f)
    local _,_,o,m=polyAt(p)
    for i=o,o+m-1 do
        local a,b,e=byte(H.pa,i*3+1,i*3+3)
        local d=a+b*256
        -- Upper edge bits zero: legacy signed i16. Otherwise the high word
        -- is biased by 16; the low three bits still identify the shared edge.
        if e>=8 then d=d+(floor(e/8)-16)*65536;e=e%8
        elseif d>=32768 then d=d-65536 end
        f(p+d,e)
    end
end
H.PolyNear=polyNear
-- An exact endpoint polygon may sit on a small island ignored by the coarse
-- graph's nearest-node fallback. False only when its whole polygon component
-- was searched and cannot reach that node; a bounded search stays unknown.
function H.PolyJoinsNode(p,n)
    local goals={}
    for _,q in ipairs(H.NodePolys(n) or {}) do goals[q]=true end
    if goals[p] then return true end
    if not next(goals) then return nil end
    local seen,queue,head={[p]=true},{p},1
    while queue[head] do
        if head>H.POLYLOOK then return nil end
        if head%H.LOOK==0 then breathe() end
        local found=false
        polyNear(queue[head],function(q)
            if goals[q] then found=true end
            if not seen[q] then seen[q]=true;queue[#queue+1]=q end
        end)
        if found then return true end
        head=head+1
    end
    return false
end
-- A polygon's corners in yards from the grid's corner: {x1, y1, z1, x2, y2, z2, ...}.
function H.PolyCorners(p)
    local a,k=polyAt(p)
    local b=a+k
    local out={}
    for i=a,b-1 do
        local v=u24(H.pvi,i*3+1)
        local o=v*8+1
        out[#out+1]=u24(H.vx,o)/8;out[#out+1]=u24(H.vx,o+3)/8;out[#out+1]=(u16(H.vx,o+6)-32768)/16
    end
    return out
end
function H.PolyCentre(p)
    local c=H.PolyCorners(p)
    local x,y,z,k=0,0,0,#c/3
    for i=1,#c,3 do x,y,z=x+c[i],y+c[i+1],z+c[i+2] end
    return x/k,y/k,z/k
end
-- Is (x, y) in polygon p (convex; either winding)?
function H.PolyHas(p,x,y)
    local c=H.PolyCorners(p)
    local k=#c/3
    local sign=0
    for i=0,k-1 do
        local j=(i+1)%k
        local ax,ay,bx,by=c[i*3+1],c[i*3+2],c[j*3+1],c[j*3+2]
        local cr=(bx-ax)*(y-ay)-(by-ay)*(x-ax)
        if cr>1e-6 then if sign<0 then return false end;sign=1
        elseif cr<-1e-6 then if sign>0 then return false end;sign=-1 end
    end
    return true
end
-- Height on the polygon's corner fan, at a point already known to be inside.
function H.PolyZ(p,x,y)
    local c=H.PolyCorners(p)
    local ax,ay,az=c[1],c[2],c[3]
    for i=4,#c-5,3 do
        local bx,by,bz,cx,cy,cz=c[i],c[i+1],c[i+2],c[i+3],c[i+4],c[i+5]
        local den=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
        if abs(den)>1e-9 then
            local u=((by-cy)*(x-cx)+(cx-bx)*(y-cy))/den
            local v=((cy-ay)*(x-cx)+(ax-cx)*(y-cy))/den
            if u>=-1e-6 and v>=-1e-6 and u+v<=1+1e-6 then return u*az+v*bz+(1-u-v)*cz end
        end
    end
end
local function yardsOf(x,y)
    local g=H.geo
    return (x-g.minX)*g.width,(y-g.minY)*g.height
end
local function contOf(x,y)
    local g=H.geo
    return g.minX+x/g.width,g.minY+y/g.height
end
-- The polygon under node n holding the point (yards), else the one whose middle lies nearest.
function H.PolyAt(n,x,y,height)
    local list=H.NodePolys(n)
    if not list then return nil end
    local best,bd,contained
    local z=height or H.NodeZ(n)
    local found,dz
    local function consider(p)
        if H.PolyHas(p,x,y) then
            local pz=H.PolyZ(p,x,y)
            local d=z and pz and abs(pz-z) or 0
            if d<=H.ZNEAR and (not dz or d<dz) then found,dz=p,d end
            return true
        end
    end
    for _,p in ipairs(list) do
        if consider(p) then contained=contained or p end
        local cx,cy=H.PolyCentre(p)
        local d=(cx-x)^2+(cy-y)^2
        if not bd or d<bd then best,bd=p,d end
    end
    -- The coarse graph may anchor a tiny floor component to a nearby larger
    -- component. Start the polygon corridor on the actual floor under the
    -- endpoint, not on that distant anchor (Harick's lower shop floor).
    if H.xcell then
        local cx,cy=floor(x/H.cell),floor(y/H.cell)
        if z and cx>=0 and cy>=0 and cx<H.cols and cy<H.rows then
            local cell=cy*H.cols+cx
            local first,count=H.Extras(cell)
            local function nodePolys(node)
                for _,p in ipairs(H.NodePolys(node) or {}) do
                    consider(p)
                end
            end
            nodePolys(cell)
            for k=first,first+count-1 do nodePolys(H.NC+k) end
        end
    end
    return found or contained or best
end
-- The shared edge of p towards q: its two corners (yards) or nil.
local function portal(p,q)
    local edge
    polyNear(p,function(v,e) if v==q and not edge then edge=e end end)
    if not edge then return nil end
    local c=H.PolyCorners(p)
    local k=#c/3
    local j=(edge+1)%k
    return c[edge*3+1],c[edge*3+2],c[j*3+1],c[j*3+2]
end
-- Polygons from p to q (A* over the middles). Returns the list or nil.
-- Query-local policy: polygon geometry does not replace the cell's road,
-- slope, zone or paint costs. Resolve the actual polygon's layer, never the
-- cheapest floor at the same XY. Missing coarse coverage still uses the
-- proven polygon surface (bridges can cross gaps in cell assignments).
function H.PolyPolicy()
    local cfg=H.costCfg or Routing:Config()
    local mode=Routing:RouteMode()
    local surface={[11]=1,[9]=H.ClassCost({0,0,0,8,0},cfg,mode),[8]=H.ClassCost({0,0,0,12,0},cfg,mode)}
    local cells={}
    local function at(p,x,y)
        local area=H.parea and byte(H.parea,p+1)
        local base=H.parea and surface[area] or (not H.parea and 1)
        if not base then return nil end
        if not (H.pn and H.cc and H.geo and H.cell and H.cols and H.rows) then return base end
        local cx,cy=floor(x/H.cell),floor(y/H.cell)
        if cx<0 or cy<0 or cx>=H.cols or cy>=H.rows then return nil end
        local cell=cy*H.cols+cx
        local lookup=cells[cell]
        if not lookup then
            lookup={};cells[cell]=lookup
            local function add(n)
                local cost=H.Cost(n)
                for _,q in ipairs(H.NodePolys(n) or {}) do
                    -- Repeated ownership of one polygon must not weaken a
                    -- blocked or expensive overlay on the same floor.
                    local old=lookup[q]
                    if old==nil then lookup[q]=cost or false
                    elseif not cost then lookup[q]=false
                    elseif old then lookup[q]=max(old,cost) end
                end
            end
            add(cell)
            local first,count=H.Extras(cell)
            for k=first,first+count-1 do add(H.NC+k) end
            -- Missing polygon ownership is not missing terrain attributes.
            -- A cell with exactly one existing floor has no competing layer
            -- whose road/paint could be borrowed. Keep that floor's policy;
            -- a genuinely absent cell still falls back to the mesh surface.
            if count==0 and H.ClassOf(cell)>0 and not H.NodePolys(cell) then
                lookup.single=H.Cost(cell) or false
            end
        end
        local cost=lookup[p]
        if cost==nil then cost=lookup.single end
        if cost==false then return nil end
        if cost==nil then return base end
        return area and area~=11 and max(base,cost) or cost
    end
    -- Split at every cell boundary, so a large polygon cannot conceal a
    -- short painted strip or a road crossed between its centroid and portal.
    local function integral(ax,ay,bx,by,sample,dense)
        local dx,dy=bx-ax,by-ay
        local length=sqrt(dx*dx+dy*dy)
        if length<1e-8 then return 0 end
        local cuts={0,1}
        local cell=H.cell or 8
        local function crossings(a,b,d)
            if abs(d)<1e-8 then return end
            for k=floor(min(a,b)/cell)+1,floor(max(a,b)/cell) do
                local t=(k*cell-a)/d
                if t>0 and t<1 then cuts[#cuts+1]=t end
            end
        end
        crossings(ax,bx,dx);crossings(ay,by,dy)
        if dense then
            local n=math.ceil(length/(cell/4))
            for i=1,n-1 do cuts[#cuts+1]=i/n end
        end
        table.sort(cuts)
        local cost=0
        for i=2,#cuts do
            if i%128==0 then breathe() end
            local a,b=cuts[i-1],cuts[i]
            if b-a>1e-9 then
                local t=(a+b)/2
                local v=sample(ax+dx*t,ay+dy*t)
                if not v then return nil end
                cost=cost+length*(b-a)*v
            end
        end
        return cost
    end
    local policy={at=at,floor=min(1,H.floor or H.WAYCOST)}
    function policy.segment(p,ax,ay,bx,by)
        return integral(ax,ay,bx,by,function(x,y) return at(p,x,y) end)
    end
    function policy.path(list,pts)
        local owner=1
        local function sample(x,y)
            if not H.PolyHas(list[owner],x,y) then
                local found
                for k=owner+1,#list do if H.PolyHas(list[k],x,y) then found=k;break end end
                if not found then for k=1,owner-1 do if H.PolyHas(list[k],x,y) then found=k;break end end end
                if not found then return nil end
                owner=found
            end
            return at(list[owner],x,y)
        end
        local total=0
        for i=2,#pts do
            if i%8==0 then breathe() end
            local a,b=pts[i-1],pts[i]
            local cost=integral(a[1],a[2],b[1],b[2],sample,true)
            if not cost then return nil end
            total=total+cost
        end
        return total
    end
    return policy
end
function H.PolyPath(p,q,dryOnly)
    if p==q then
        if dryOnly and (not H.parea or byte(H.parea,p+1)~=11) then return nil end
        return {p}
    end
    -- Refinement may leave the coarse corridor. Keep the same liquid policy
    -- here; geometric distance alone silently turns bridges into canal swims.
    local policy=H.PolyPolicy()
    local areas=H.parea
    local px,py=H.PolyCentre(p)
    local qx,qy,qz=H.PolyCentre(q)
    local margin=H.CorridorClearance(px,py,qx,qy)
    local space={}
    local function cost(r)
        local area=areas and byte(areas,r+1)
        if dryOnly and area~=11 then return nil end
        local x,y=H.PolyCentre(r)
        local base=policy.at(r,x,y)
        if not base or margin<=0 then return base end
        -- The funnel can only inset the corridor A* selected. Price exposed
        -- narrow rims here as well, so a nearby wider floor can win first.
        -- Only unlinked finite boundaries count, never triangulation seams.
        -- This is a bounded preference, not a ban on the only narrow passage.
        local factor=space[r]
        if not factor then
            local x,y=H.PolyCentre(r)
            local distance=margin
            for _,w in ipairs(H.PolyBorders(r)) do
                local dx,dy=w[6]-w[4],w[7]-w[5]
                local den=dx*dx+dy*dy
                local t=den>0 and max(0,min(1,((x-w[4])*dx+(y-w[5])*dy)/den)) or 0
                distance=min(distance,sqrt((x-w[4]-t*dx)^2+(y-w[5]-t*dy)^2))
            end
            factor=2-distance/margin;space[r]=factor
        end
        return base*factor
    end
    if not cost(p) or not cost(q) then return nil end
    local mid={}
    local function centre(r)
        local m=mid[r]
        if not m then local x,y,z=H.PolyCentre(r);m={x,y,z};mid[r]=m end
        return m
    end
    local function h(r) local m=centre(r);return sqrt((m[1]-qx)^2+(m[2]-qy)^2)*policy.floor end
    local keys,vals,n={},{},0
    local dist,from,closed={[p]=0},{},{}
    n=heapPush(keys,vals,n,h(p),p)
    local count=0
    while n>0 do
        local _,u
        _,u,n=heapPop(keys,vals,n)
        if not closed[u] then
            if u==q then break end
            closed[u]=true
            count=count+1
            if count>H.POLYLOOK then return nil end
            if count%H.LOOK==0 then breathe() end
            local mu=centre(u)
            polyNear(u,function(v)
                local cv=cost(v)
                if cv and not closed[v] then
                    local mv=centre(v)
                    local ax,ay,bx,by
                    if H.vx and H.pvi then ax,ay,bx,by=portal(u,v) end
                    -- Synthetic/legacy graphs may carry no corner data;
                    -- production portals always split the two convex floors.
                    local x,y=ax and (ax+bx)/2 or (mu[1]+mv[1])/2,ay and (ay+by)/2 or (mu[2]+mv[2])/2
                    local ca=policy.segment(u,mu[1],mu[2],x,y)
                    local cb=policy.segment(v,x,y,mv[1],mv[2])
                    if ca and cb then
                        local fa,fb=space[u] or 1,space[v] or 1
                        local g=dist[u]+ca*fa+cb*fb
                        if not dist[v] or g<dist[v] then dist[v]=g;from[v]=u;n=heapPush(keys,vals,n,g+h(v),v) end
                    end
                end
            end)
        end
    end
    -- A completed search still proves the reachable part of this endpoint's
    -- floor. Let PolyEnd recover that part without another graph search.
    -- Budget exhaustion above deliberately provides no such proof.
    if not dist[q] then return nil,closed,from end
    local out={q}
    while out[1]~=p do table.insert(out,1,from[out[1]]) end
    return out
end
-- The way through a row of polygons from (ax, ay) to (bx, by), pulled tight through their shared edges (the simple
-- stupid funnel). Returns {{x, y}, ...} in yards.
-- Finite unlinked edges with their inward normals. These are both walls and
-- free mesh boundaries (cliffs/platform sides); shared triangulation edges
-- must not become artificial obstacles in otherwise open rooms.
function H.PolyBorders(p)
    local linked={}
    polyNear(p,function(_,edge) linked[edge]=true end)
    local c=H.PolyCorners(p)
    local n=#c/3
    local mx,my=H.PolyCentre(p)
    local out={}
    for i=0,n-1 do if not linked[i] then
        local j=(i+1)%n
        local x,y=c[i*3+1],c[i*3+2]
        local dx,dy=c[j*3+1]-x,c[j*3+2]-y
        local len=sqrt(dx*dx+dy*dy)
        if len>1e-6 then
            local nx,ny=-dy/len,dx/len
            if (mx-x)*nx+(my-y)*ny<0 then nx,ny=-nx,-ny end
            out[#out+1]={nx,ny,x*nx+y*ny,x,y,x+dx,y+dy}
        end
    end end
    return out
end
-- Clip a shared portal by both adjacent polygons' actual boundaries. A narrow
-- passage reduces the preferred margin locally, retaining a nonzero portal.
function H.InsetPortal(x1,y1,x2,y2,a,b,margin)
    local dx,dy=x2-x1,y2-y1
    local len=sqrt(dx*dx+dy*dy)
    if len<1e-6 or margin<=0 then return x1,y1,x2,y2 end
    local reserve=min(.5/len,.1)
    local function interval(r)
        local spans={{0,1}}
        for _,walls in ipairs({a,b}) do for _,w in ipairs(walls) do
            -- Intersection of the portal with the finite edge's capsule.
            -- Extending a short wall to an infinite line invents obstacles.
            local cutLo,cutHi
            local function add(lo,hi)
                lo,hi=max(0,lo),min(1,hi)
                if hi>lo then cutLo=min(cutLo or lo,lo);cutHi=max(cutHi or hi,hi) end
            end
            for _,k in ipairs({4,6}) do
                local ex,ey=x1-w[k],y1-w[k+1]
                local v=ex*dx+ey*dy
                local disc=v*v-len*len*(ex*ex+ey*ey-r*r)
                if disc>0 then
                    local root=sqrt(disc)
                    add((-v-root)/(len*len),(-v+root)/(len*len))
                end
            end
            local wx,wy=w[6]-w[4],w[7]-w[5]
            local wl=sqrt(wx*wx+wy*wy)
            local lo,hi=0,1
            local function slab(start,delta,low,high)
                if abs(delta)<1e-9 then return start>=low and start<=high end
                local u,v=(low-start)/delta,(high-start)/delta
                if u>v then u,v=v,u end
                lo,hi=max(lo,u),min(hi,v)
                return hi>=lo
            end
            if slab(((x1-w[4])*wx+(y1-w[5])*wy)/wl,(dx*wx+dy*wy)/wl,0,wl)
                and slab(w[1]*x1+w[2]*y1-w[3],w[1]*dx+w[2]*dy,-r,r) then add(lo,hi) end
            if cutLo then
                local kept={}
                for _,s in ipairs(spans) do
                    if cutHi<=s[1] or cutLo>=s[2] then kept[#kept+1]=s
                    else
                        if cutLo-s[1]>=reserve then kept[#kept+1]={s[1],cutLo} end
                        if s[2]-cutHi>=reserve then kept[#kept+1]={cutHi,s[2]} end
                    end
                end
                spans=kept
                if #spans==0 then return nil end
            end
        end end
        local best
        for _,s in ipairs(spans) do if not best or s[2]-s[1]>best[2]-best[1] then best=s end end
        return best and best[1],best and best[2]
    end
    local lo,hi=interval(margin)
    if not lo then
        local good,bad=0,margin
        for _=1,12 do
            local mid=(good+bad)/2
            if interval(mid) then good=mid else bad=mid end
        end
        margin=good*.9
        lo,hi=interval(margin)
    end
    if not lo then return x1,y1,x2,y2 end
    return x1+lo*dx,y1+lo*dy,x1+hi*dx,y1+hi*dy,margin
end
function H.Funnel(list,ax,ay,bx,by,margin)
    local L,R={},{}
    local borders={}
    local portals={}
    local function walls(p)
        if not borders[p] then borders[p]=H.PolyBorders(p) end
        return borders[p]
    end
    L[1],R[1]={ax,ay},{ax,ay}
    for i=2,#list do
        if i%H.LOOK==0 then breathe() end
        local x1,y1,x2,y2=portal(list[i-1],list[i])
        if not x1 then return nil end
        -- left and right as seen going from the one polygon's middle to the next's
        local px,py=H.PolyCentre(list[i-1])
        local qx,qy=H.PolyCentre(list[i])
        local cr=(qx-px)*(y1-py)-(qy-py)*(x1-px)
        portals[i]={x1,y1,x2,y2,cr=cr}
        if margin and margin>0 then
            local r
            x1,y1,x2,y2,r=H.InsetPortal(x1,y1,x2,y2,walls(list[i-1]),walls(list[i]),margin)
            portals[i].radius=r or 0
        end
        if cr>0 then L[i],R[i]={x1,y1},{x2,y2} else L[i],R[i]={x2,y2},{x1,y1} end
    end
    if margin and margin>0 then
        -- Ease the preferred margin into and out of narrow sections, rather
        -- than switching sideways between two nearby portals abruptly.
        local function ease(i,j)
            local a,b=portals[i],portals[j]
            local dx,dy=(a[1]+a[3]-b[1]-b[3])/2,(a[2]+a[4]-b[2]-b[4])/2
            a.radius=min(a.radius,b.radius+sqrt(dx*dx+dy*dy)*.25)
        end
        for i=3,#list do ease(i,i-1) end
        for i=#list-1,2,-1 do ease(i,i+1) end
        for i=2,#list do
            if i%H.LOOK==0 then breathe() end
            local p=portals[i]
            local x1,y1,x2,y2=H.InsetPortal(p[1],p[2],p[3],p[4],walls(list[i-1]),walls(list[i]),p.radius)
            if p.cr>0 then L[i],R[i]={x1,y1},{x2,y2} else L[i],R[i]={x2,y2},{x1,y1} end
        end
    end
    L[#list+1],R[#list+1]={bx,by},{bx,by}
    -- (twice the signed area, as Detour's dtTriArea2D: <= 0 when c lies left of a -> b or on it)
    local function area(a,b,c) return (c[1]-a[1])*(b[2]-a[2])-(b[1]-a[1])*(c[2]-a[2]) end
    local function same(a,b) return abs(a[1]-b[1])<1e-6 and abs(a[2]-b[2])<1e-6 end
    local out={{ax,ay}}
    local apex,left,right={ax,ay},L[1],R[1]
    local ai,li,ri=1,1,1
    local n=#L
    local i=2
    local guard=0
    while i<=n do
        guard=guard+1
        if guard>8*n+16 then return nil end
        local l,r=L[i],R[i]
        local restart=false
        -- the right side moves in
        if area(apex,right,r)<=0 then
            if same(apex,right) or area(apex,left,r)>0 then right,ri=r,i
            else
                -- over the left side: its corner is a corner of the way
                out[#out+1]={left[1],left[2]}
                apex,ai=left,li;left,right,li,ri=apex,apex,ai,ai
                i=ai+1;restart=true
            end
        end
        if not restart then
            if area(apex,left,l)>=0 then
                if same(apex,left) or area(apex,right,l)<0 then left,li=l,i
                else
                    out[#out+1]={right[1],right[2]}
                    apex,ai=right,ri;left,right,li,ri=apex,apex,ai,ai
                    i=ai+1;restart=true
                end
            end
        end
        if not restart then i=i+1 end
    end
    local last=out[#out]
    if not same(last,{bx,by}) then out[#out+1]={bx,by} end
    return out
end
function H.CorridorClearance(ax,ay,bx,by)
    local maps=Routing:Data().maps or {}
    local wanted
    for _,p in ipairs({{ax,ay},{bx,by}}) do
        local x,y=contOf(p[1],p[2])
        local zone=Routing:ZoneAt(H.cont,x,y)
        local map=zone and maps[zone]
        local value=map and tonumber(map.clearance)
        if value then wanted=min(wanted or value,value) end
    end
    return max(0,min(H.MAXCLEARANCE,wanted or H.CLEARANCE))
end
-- One end of a refined walk on the polygons: from the point (x, y) on node nodes[1] along the chain as long as its
-- nodes have polygons (and step from cell to neighbouring cell). Returns the points (continent, the end's first),
-- and the index of the chain node where the cells take over; nil where the end has no polygons. to: the other end's
-- point when the whole chain has polygons.
-- Does a row of polygons pass over itself (a spiral ramp, a turning stair: two of them, not neighbours in the row,
-- lie within STACKNEAR yd of each other across and more than STACKDZ yd apart in height)? Then the funnel, pulled
-- tight in the plane, would cut across the turns (Claude 2026-10-28, Florian in Orgrimmar, the ramp up to Doras).
H.STACKNEAR,H.STACKDZ=4,3
function H.PolysStacked(list,runs)
    local n=#list
    if n<4 then return false end
    local c={}
    for i=1,n do local x,y,z=H.PolyCentre(list[i]);c[i]={x,y,z} end
    local step=n>200 and 2 or 1
    for i=1,n-3,step do
        local a=c[i]
        for j=i+3,n,step do
            local b=c[j]
            if abs(a[3]-b[3])>H.STACKDZ and (a[1]-b[1])^2+(a[2]-b[2])^2<H.STACKNEAR*H.STACKNEAR then
                if not runs then return true end
                -- Keep the entire winding between the two floors, plus one
                -- polygon on either side to anchor its entry and exit.
                local lo,hi=max(1,i-1),min(n,j+1)
                local last=runs[#runs]
                if last and lo<=last[2]+1 then last[2]=max(last[2],hi)
                else runs[#runs+1]={lo,hi} end
            end
        end
        if runs and (i-1)%H.LOOK==0 then breathe() end
    end
    return runs and #runs>0 or false
end
-- A row of polygons drawn through the middles of their shared edges (yards), from (ax, ay) to (bx, by): each piece
-- lies inside one polygon (convex), on the mesh all the way.
function H.PolyMiddles(list,ax,ay,bx,by)
    local pts={{ax,ay}}
    for i=2,#list do
        local x1,y1,x2,y2=portal(list[i-1],list[i])
        -- (with the height between the two polygons: Navigate's loop cut and a plan anew from here use it)
        local _,_,za=H.PolyCentre(list[i-1])
        local _,_,zb=H.PolyCentre(list[i])
        local z=za and zb and (za+zb)/2 or nil
        if x1 then pts[#pts+1]={(x1+x2)/2,(y1+y2)/2,z=z} else local x,y=H.PolyCentre(list[i]);pts[#pts+1]={x,y,z=zb} end
    end
    pts[#pts+1]={bx,by}
    return pts
end
-- A corridor found from the other end is usable only when every edge also
-- exists in the walking direction. Never reverse a one-way drop or link.
function H.ReversePolys(list)
    local out={}
    for i=#list,1,-1 do
        if i>1 then
            local joined=false
            polyNear(list[i],function(q) if q==list[i-1] then joined=true end end)
            if not joined then return nil end
        end
        out[#out+1]=list[i]
    end
    return out
end
-- Walk a line through actual directed ground portals. This is a corridor
-- query, not an XY shortcut: unlinked boundaries, liquids and height gaps
-- terminate it. At a shared vertex an ambiguous exit simply keeps the old
-- corridor. A bounded local query never affects the main search budget.
function H.VisiblePolys(p,q,ax,ay,bx,by)
    if not H.PolyHas(p,ax,ay) or (H.parea and byte(H.parea,p+1)~=11) then return nil end
    local dx,dy=bx-ax,by-ay
    local at=0
    local out,seen={p},{[p]=true}
    for count=1,96 do
        if p==q and H.PolyHas(p,bx,by) then return out end
        if count%H.LOOK==0 then breathe() end
        local c=H.PolyCorners(p)
        local n=#c/3
        local nextAt,edge
        for i=0,n-1 do
            local j=(i+1)%n
            local x,y=c[i*3+1],c[i*3+2]
            local ex,ey=c[j*3+1]-x,c[j*3+2]-y
            local den=dx*ey-dy*ex
            if abs(den)>1e-9 then
                local t=((x-ax)*ey-(y-ay)*ex)/den
                local u=((x-ax)*dy-(y-ay)*dx)/den
                if t>=at-1e-7 and t<=1+1e-7 and u>=-1e-7 and u<=1+1e-7 and (not nextAt or t<nextAt) then
                    local after=min(1,t+1e-5)
                    if not H.PolyHas(p,ax+dx*after,ay+dy*after) then nextAt,edge=max(t,at),i end
                end
            end
        end
        if not nextAt then return nil end
        local x,y=ax+dx*nextAt,ay+dy*nextAt
        local after=min(1,nextAt+1e-5)
        local z=H.PolyZ(p,x,y)
        local crossing
        H.PolyNear(p,function(v,e)
            if e==edge and not seen[v] and H.PolyHas(v,ax+dx*after,ay+dy*after)
                and abs(H.PolyZ(v,x,y)-z)<.25 and (not H.parea or byte(H.parea,v+1)==11) then crossing=v end
        end)
        if not crossing then return nil end
        p,at=crossing,nextAt
        out[#out+1]=p;seen[p]=true
    end
end
-- Remove a local clearance dogleg only if its directed ground corridor is
-- unchanged and the whole replacement keeps at least the old boundary
-- distance (up to the preferred margin). Portal endpoint insets alone do
-- not guarantee that the lines BETWEEN portals keep that same distance.
function H.TrimClearance(list,pts,margin)
    if not pts or #pts<3 then return pts end
    local walls={}
    local policy=H.PolyPolicy()
    local function owner(p,at)
        for k=at or 1,#list do if H.PolyHas(list[k],p[1],p[2]) then return k end end
    end
    local function pointDistance(x,y,a,b)
        local dx,dy=b[1]-a[1],b[2]-a[2]
        local den=dx*dx+dy*dy
        local t=den>0 and max(0,min(1,((x-a[1])*dx+(y-a[2])*dy)/den)) or 0
        return sqrt((x-a[1]-t*dx)^2+(y-a[2]-t*dy)^2)
    end
    local function distance(a,b,w)
        local c,d={w[4],w[5]},{w[6],w[7]}
        local dx,dy,ex,ey=b[1]-a[1],b[2]-a[2],d[1]-c[1],d[2]-c[2]
        local den=dx*ey-dy*ex
        if abs(den)>1e-9 then
            local t=((c[1]-a[1])*ey-(c[2]-a[2])*ex)/den
            local u=((c[1]-a[1])*dy-(c[2]-a[2])*dx)/den
            if t>=0 and t<=1 and u>=0 and u<=1 then return 0 end
        end
        return min(pointDistance(a[1],a[2],c,d),pointDistance(b[1],b[2],c,d),
            pointDistance(c[1],c[2],a,b),pointDistance(d[1],d[2],a,b))
    end
    local i=1
    while i<=#pts-2 do
        breathe()
        local a=pts[i]
        local ia=owner(a)
        local chosen,gain
        if ia then for j=i+2,min(#pts,i+4) do
            local b=pts[j]
            local ib=owner(b,ia)
            if ib and ib-ia<=24 then
                local ray=H.VisiblePolys(list[ia],list[ib],a[1],a[2],b[1],b[2])
                local same=ray and #ray==ib-ia+1
                if same then for k,p in ipairs(ray) do if p~=list[ia+k-1] then same=false;break end end end
                if same then
                    local before,after=margin or H.CLEARANCE,margin or H.CLEARANCE
                    for k=ia,ib do
                        local p=list[k];walls[p]=walls[p] or H.PolyBorders(p)
                        for _,w in ipairs(walls[p]) do
                            after=min(after,distance(a,b,w))
                            for m=i+1,j do before=min(before,distance(pts[m-1],pts[m],w)) end
                        end
                    end
                    local old=0
                    for k=i+1,j do old=old+sqrt((pts[k][1]-pts[k-1][1])^2+(pts[k][2]-pts[k-1][2])^2) end
                    local saved=old-sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
                    if after+1e-6>=before and saved>.25 and (not gain or saved>gain) then
                        local oldPoints={}
                        for k=i,j do oldPoints[#oldPoints+1]=pts[k] end
                        local oldCost=policy.path(list,oldPoints)
                        local newCost=policy.path(list,{a,b})
                        if newCost and oldCost and newCost<=oldCost+1e-6 then chosen,gain=j,saved end
                    end
                end
            end
        end end
        if chosen then for _=i+1,chosen-1 do table.remove(pts,i+1) end end
        i=i+1
    end
    return pts
end
-- Centroid A* can choose the longer side of a pillar. Try local connected
-- visibility corridors, then compare the actual funnel INCLUDING clearance.
-- Rank before applying: accepting the first small win could block a better
-- overlapping replacement. Disjoint replacements are rechecked together.
function H.ClearCorridor(list,ax,ay,bx,by,margin)
    local pts=H.Funnel(list,ax,ay,bx,by,margin)
    if not pts then return list,pts end
    local base,original,candidates,tried=list,pts,{},{}
    local function length(ps)
        local d=0
        for i=2,#ps do d=d+sqrt((ps[i][1]-ps[i-1][1])^2+(ps[i][2]-ps[i-1][2])^2) end
        return d
    end
    local best=length(pts)
    local policy=H.PolyPolicy()
    local bestCost=policy.path(list,pts)
    local function owner(pt,from)
        for k=from or 1,#base do if H.PolyHas(base[k],pt[1],pt[2]) then return k end end
    end
    local function replace(source,ia,ib,ray)
        local out={}
        for k=1,ia-1 do out[#out+1]=source[k] end
        for _,v in ipairs(ray) do out[#out+1]=v end
        for k=ib+1,#source do out[#out+1]=source[k] end
        local seen={}
        for _,v in ipairs(out) do if seen[v] then return nil end;seen[v]=true end
        return out
    end
    for i=1,#original-2 do
        breathe()
        local a=original[i]
        local ia=owner(a)
        if ia then for j=min(#original,i+4),i+2,-1 do
            local b=original[j]
            local ib=owner(b,ia+1)
            if ib and ib>ia+1 and ib-ia<=24 then
                local ground=true
                for k=ia,ib do if H.parea and byte(H.parea,base[k]+1)~=11 then ground=false;break end end
                local ray=ground and H.VisiblePolys(base[ia],base[ib],a[1],a[2],b[1],b[2])
                if ray then
                    local same=#ray==ib-ia+1
                    if same then for k,v in ipairs(ray) do if v~=base[ia+k-1] then same=false;break end end end
                    local c=not same and replace(base,ia,ib,ray)
                    -- Several pairs can discover exactly the same corridor.
                    -- Its full clearance calculation is needed only once.
                    local key=c and table.concat(c,",")
                    local fresh=key and not tried[key]
                    if key then tried[key]=true end
                    local p=fresh and not H.PolysStacked(c) and H.Funnel(c,ax,ay,bx,by,margin)
                    local len=p and length(p)
                    local cost=p and policy.path(c,p)
                    if len and len<best-.25 and cost and bestCost and cost<=bestCost+1e-6 then
                        candidates[#candidates+1]={ia=ia,ib=ib,ray=ray,length=len,path=p,corridor=c}
                    end
                end
            end
        end end
    end
    table.sort(candidates,function(a,b)
        if a.length~=b.length then return a.length<b.length end
        if a.ia~=b.ia then return a.ia<b.ia end
        return a.ib<b.ib
    end)
    for _,v in ipairs(candidates) do
        local ia,ib
        for i,p in ipairs(list) do if p==base[v.ia] then ia=i end;if p==base[v.ib] then ib=i end end
        local unchanged=ia and ib and ib-ia==v.ib-v.ia
        if unchanged then for k=0,ib-ia do if list[ia+k]~=base[v.ia+k] then unchanged=false;break end end end
        if unchanged then
            local c=list==base and v.corridor or replace(list,ia,ib,v.ray)
            local p=list==base and v.path or (c and not H.PolysStacked(c) and H.Funnel(c,ax,ay,bx,by,margin))
            local len=p and length(p)
            local cost=p and policy.path(c,p)
            if len and len<best-.25 and cost and bestCost and cost<=bestCost+1e-6 then list,pts,best,bestCost=c,p,len,cost end
        end
    end
    return list,H.TrimClearance(list,pts,margin)
end
-- Protect only the winding itself. A remote spiral must not turn a whole
-- ground approach into portal-midpoint zigzags or disable its clearance.
-- Both pieces meet at an existing portal midpoint; no cross-floor shortcut.
function H.PolyRoute(list,sx,sy,ex,ey)
    local runs={}
    local stacked=H.PolysStacked(list,runs)
    local margin=H.CorridorClearance(sx,sy,ex,ey)
    if not stacked then
        local corridor,pts=H.ClearCorridor(list,sx,sy,ex,ey,margin)
        return pts,false,corridor
    end
    local middle=H.PolyMiddles(list,sx,sy,ex,ey)
    local pts,corridor={},{}
    local function piece(a,b,protected)
        if a>b then return true end
        local part={}
        for i=a,b do part[#part+1]=list[i] end
        local first,last=middle[a],middle[b+1]
        local way
        -- A shorter unsampled section may reveal another overlap in a very
        -- long corridor. Conservatively protect it as well.
        protected=protected or H.PolysStacked(part)
        if protected then
            way={}
            for i=a,b+1 do
                local p=middle[i]
                way[#way+1]={p[1],p[2],z=p.z,stack=true}
            end
        else part,way=H.ClearCorridor(part,first[1],first[2],last[1],last[2],margin) end
        if not way then return false end
        for _,p in ipairs(part) do corridor[#corridor+1]=p end
        for i,p in ipairs(way) do
            if i==1 and #pts>0 then
                if p.stack then pts[#pts].stack,pts[#pts].z=true,p.z end
            else pts[#pts+1]=p end
        end
        return true
    end
    local at=1
    for _,run in ipairs(runs) do
        if not piece(at,run[1]-1,false) or not piece(run[1],run[2],true) then return nil end
        at=run[2]+1
    end
    if not piece(at,#list,false) then return nil end
    return pts,true,corridor
end
function H.PolyWay(list,sx,sy,ex,ey,measure)
    local pts,stacked,used=H.PolyRoute(list,sx,sy,ex,ey)
    if not pts then return nil end
    local cost=measure and H.PolyPolicy().path(used or list,pts)
    local length=0
    if measure then for i=2,#pts do length=length+sqrt((pts[i][1]-pts[i-1][1])^2+(pts[i][2]-pts[i-1][2])^2) end end
    for i,pt in ipairs(pts) do
        local cx,cy=contOf(pt[1],pt[2])
        pts[i]={cx,cy,stack=pt.stack,z=pt.z,corner=(i>1 and i<#pts) or nil}
    end
    return pts,cost,length
end
-- A connected polygon path across absent cell assignments may run around
-- an outdoor road rather than represent it. Preserve the weighted coarse
-- policy at this coverage seam. Pure geometry corrections (stairs/bridges)
-- with the same average surface cost remain eligible.
function H.PolyGapPolicy(nodes,a,b,actual,length)
    if not actual or not length or length<=0 then return true end
    local budget,distance=0,0
    for i=a+1,b do
        local u,v=H.CellOf(nodes[i-1]),H.CellOf(nodes[i])
        local dx,dy=u%H.cols-v%H.cols,floor(u/H.cols)-floor(v/H.cols)
        local d=sqrt(dx*dx+dy*dy)*H.cell
        distance=distance+d;budget=budget+d*(H.Cost(nodes[i]) or 1)
    end
    if distance<=0 then return true end
    return actual<=budget+H.PULLSLACK or actual/length<=budget/distance+1e-6
end
H.POLYROUND,H.POLYROUNDYD=2,8   -- a polygon end this much longer than its cells' way is a way round (H.PolyEnd)
function H.PolyEnd(nodes,x,y,tx,ty,z,tz)
    if not H.pn then return nil end
    local k=0
    local gap
    local cols=H.cols
    for i,n in ipairs(nodes) do
        if i>1 then
            local a,b=H.CellOf(nodes[i-1]),H.CellOf(n)
            if max(abs(a%cols-b%cols),abs(floor(a/cols)-floor(b/cols)))>1 then break end
            -- (nor across a lift or teleport between neighbouring cells, the Wizard's Sanctum's portal
            -- down into the hall under the tower, is no walk on the polygons; Claude 2026-10-28)
            local js=H.jumpFrom[nodes[i-1]]
            if type(js)=="number" then js={js} end
            local jumped=false
            for _,j in ipairs(js or {}) do if H.JumpTo(j)==n and H.JumpLift(j) then jumped=true end end
            js=H.jumpFrom[n]
            if type(js)=="number" then js={js} end
            for _,j in ipairs(js or {}) do if H.JumpTo(j)==nodes[i-1] and H.JumpLift(j) then jumped=true end end
            if jumped then break end
        end
        if H.NodePolys(n) then
            k=i
            if gap then break end
        else
            gap=gap or k
        end
    end
    if k<2 then return nil end
    if gap==k then gap=nil end
    local sx,sy=yardsOf(x,y)
    local ex,ey
    if k==#nodes and tx then ex,ey=yardsOf(tx,ty)
    else local cx,cy=H.Point(nodes[k]);ex,ey=yardsOf(cx,cy) end
    local p=H.PolyAt(nodes[1],sx,sy,z)
    local q=p and H.PolyAt(nodes[k],ex,ey,k==#nodes and tz or nil)
    local list,reachable,parents
    if q then list,reachable,parents=H.PolyPath(p,q,gap~=nil) end
    if not list and gap and gap>=2 then
        -- Missing cell assignments are not walls. The extra anchor is used
        -- only with a proven dry corridor; otherwise retain the known end.
        k=gap
        local cx,cy=H.Point(nodes[k]);ex,ey=yardsOf(cx,cy)
        q=H.PolyAt(nodes[k],ex,ey)
        if q then list,reachable,parents=H.PolyPath(p,q) end
    end
    if not list and reachable then
        -- A disconnected outer floor must not discard a valid room/door
        -- corridor next to the endpoint. Reuse the completed search tree,
        -- stopping before the unresolved join; never invent a connection.
        for i=k-1,2,-1 do
            local cx,cy=H.Point(nodes[i])
            local px,py=yardsOf(cx,cy)
            local v=H.PolyAt(nodes[i],px,py)
            if v and reachable[v] then
                k,ex,ey=i,px,py
                if not H.PolyHas(v,ex,ey) then ex,ey=H.PolyCentre(v) end
                list={v}
                while list[1]~=p do table.insert(list,1,parents[list[1]]) end
                break
            end
        end
    end
    local pts,stacked
    if list then pts,stacked,list=H.PolyRoute(list,sx,sy,ex,ey) end
    if not pts then return nil end
    if gap and not stacked then
        local cost=H.PolyPolicy().path(list,pts)
        local length=0
        for i=2,#pts do length=length+sqrt((pts[i][1]-pts[i-1][1])^2+(pts[i][2]-pts[i-1][2])^2) end
        if not H.PolyGapPolicy(nodes,1,k,cost,length) then return nil end
    end
    -- (a row of polygons far round where the cells go straight - two layers of one cell a yard apart, joined on the
    -- mesh only far off: Jhag in Orgrimmar, 0 yd away, was drawn 46 yd round - is no end on the polygons; a climb on
    -- the spot is longer than its cells by nature and stays; Claude 2026-10-28)
    if not stacked then
        local function len(list2)
            local d=0
            for i=2,#list2 do d=d+sqrt((list2[i][1]-list2[i-1][1])^2+(list2[i][2]-list2[i-1][2])^2) end
            return d
        end
        -- (only where the ends lie close: a polygon way much longer than the line between them goes round)
        local line=sqrt((ex-sx)^2+(ey-sy)^2)
        local lp=len(pts)
        if line<=H.POLYROUNDYD and lp>H.POLYROUND*line+H.POLYROUNDYD then return nil end
    end
    -- (a climb on the spot marked: Navigate's loop cut leaves it, N.CutLoops)
    for i,pt in ipairs(pts) do local cx,cy=contOf(pt[1],pt[2]);pts[i]={cx,cy,stack=pt.stack,z=pt.z,corner=(i>1 and i<#pts) or nil} end
    return pts,k,list
end
-- The cells' points of a chain, pulled tight (H.Pull, H.Points), the jumps between its nodes kept.
local function cellBody(chain,ax,ay,bx,by,preserve)
    local pulled
    if preserve then
        -- At a rejected coverage bridge, only the original graph steps
        -- have a geometric witness. Keep their turns rather than cutting
        -- diagonally across an absent fine-mesh boundary.
        pulled={chain[1]}
        for i=2,#chain-1 do
            local a,b,c=H.CellOf(chain[i-1]),H.CellOf(chain[i]),H.CellOf(chain[i+1])
            local dx,dy=b%H.cols-a%H.cols,floor(b/H.cols)-floor(a/H.cols)
            local ex,ey=c%H.cols-b%H.cols,floor(c/H.cols)-floor(b/H.cols)
            if dx~=ex or dy~=ey then pulled[#pulled+1]=chain[i] end
        end
        if #chain>1 then pulled[#pulled+1]=chain[#chain] end
    else pulled=H.Pull(chain) end
    local jumps={}
    for i=2,#pulled do
        local js=H.jumpFrom[pulled[i-1]]
        if type(js)=="number" then js={js} end
        for _,j in ipairs(js or {}) do if H.JumpTo(j)==pulled[i] then jumps[i]=j end end
    end
    local pts=H.Points(pulled,jumps,ax,ay,bx,by)
    if preserve then
        local x,y=H.Point(chain[1])
        if abs(x-ax)+abs(y-ay)>1e-9 then table.insert(pts,2,{x,y}) end
        x,y=H.Point(chain[#chain])
        if abs(x-bx)+abs(y-by)>1e-9 then table.insert(pts,#pts,{x,y}) end
    end
    return pts
end
-- Is there a jump from node a to node b (a lift, a gap, a stored walk: not a step on the polygons)?
local function jumpBetween(a,b)
    local js=H.jumpFrom[a]
    if type(js)=="number" then js={js} end
    for _,j in ipairs(js or {}) do if H.JumpTo(j)==b then return true end end
    return false
end
-- Where a chain climbs on the spot (Claude 2026-10-28, Florian in Orgrimmar: the way to Doras up the tower's spiral
-- ramp was drawn as a line straight up - "als müsste ich hochfliegen"; the Wizard's Sanctum's ramp and Sentinel
-- Hill's stair the same): a spiral or a stair turning inside one or two 8-yd cells comes back to a cell it has been in
-- on another layer, and the cells' middles show only a jump up. Such a stretch (STACKBACK nodes round each return,
-- as long as its nodes have polygons and no jump lies between them) goes from polygon to polygon (H.PolyPath), drawn
-- through their middles; the rest of the chain keeps the cells. Returns {i0, i1} runs.
H.STACKBACK=6
function H.StackRuns(chain)
    if not H.pn then return {} end
    local runs={}
    local seen={}
    for i,n in ipairs(chain) do
        local c=H.CellOf(n)
        local k=seen[c]
        if k and chain[k]~=n and i-k<=H.STACKBACK*4 then
            local a,b=k,i
            -- (widened to the polygons on either side)
            while a>1 and i-a<H.STACKBACK*4 and H.NodePolys(chain[a-1]) and not jumpBetween(chain[a-1],chain[a]) do a=a-1;if k-a>=H.STACKBACK then break end end
            while b<#chain and H.NodePolys(chain[b+1]) and not jumpBetween(chain[b],chain[b+1]) and b-i<H.STACKBACK do b=b+1 end
            local ok=true
            for m=a,b do if not H.NodePolys(chain[m]) then ok=false;break end end
            for m=a+1,b do if ok and jumpBetween(chain[m-1],chain[m]) then ok=false end end
            if ok then
                local last=runs[#runs]
                if last and a<=last[2] then last[2]=math.max(last[2],b) else runs[#runs+1]={a,b} end
            end
        end
        seen[c]=i
    end
    return runs
end
-- The points of a run on the polygons: from the polygon under its first node to that under its last (their
-- middles), pulled tight; nil where the polygons do not join.
local function polyRun(chain,a,b,ax,ay,bx,by,dryOnly)
    local sx,sy
    if ax then sx,sy=yardsOf(ax,ay) else local cx,cy=H.Point(chain[a]);sx,sy=yardsOf(cx,cy) end
    local ex,ey
    if bx then ex,ey=yardsOf(bx,by) else local cx,cy=H.Point(chain[b]);ex,ey=yardsOf(cx,cy) end
    local p=H.PolyAt(chain[a],sx,sy)
    local q=p and H.PolyAt(chain[b],ex,ey)
    local list=q and H.PolyPath(p,q,dryOnly)
    if not list then return nil end
    if not ax and not H.PolyHas(p,sx,sy) then sx,sy=H.PolyCentre(p) end
    if not bx and not H.PolyHas(q,ex,ey) then ex,ey=H.PolyCentre(q) end
    -- Use the same clearance and local ramp protection as the walk's ends.
    return H.PolyWay(list,sx,sy,ex,ey,dryOnly)
end
-- The body of a refined walk: the cells, pulled tight, but where the chain climbs on the spot the polygons
-- (H.StackRuns).
function H.StackedBody(chain,ax,ay,bx,by,preserve)
    local runs=H.StackRuns(chain)
    if #runs==0 then return cellBody(chain,ax,ay,bx,by,preserve) end
    local out={}
    local function add(pts,skipFirst)
        for i,p in ipairs(pts) do if not (skipFirst and i==1) then out[#out+1]=p end end
    end
    local from,fx,fy=1,ax,ay
    for _,r in ipairs(runs) do
        local a,b=r[1],r[2]
        local first,last=a==1,b==#chain
        local pts=polyRun(chain,a,b,first and ax or nil,first and ay or nil,last and bx or nil,last and by or nil)
        if pts then
            if a>from then
                add(cellBody({unpack(chain,from,a)},fx,fy,pts[1][1],pts[1][2],preserve),#out>0)
                add(pts,true)
            else
                add(pts,#out>0)
            end
            from,fx,fy=b,pts[#pts][1],pts[#pts][2]
            H.stats.stackRuns=(H.stats.stackRuns or 0)+1
        end
    end
    if from<#chain then add(cellBody({unpack(chain,from,#chain)},fx,fy,bx,by,preserve),#out>0)
    elseif #out==0 then return cellBody(chain,ax,ay,bx,by,preserve) end
    return out
end
-- Precise geometry can resume after a gap in polygon coverage. A missing
-- endpoint must not discard a connected bridge in the middle of the walk.
-- A missing coarse-node assignment need not break the polygon graph. Try
-- the known endpoints across it; only an actual polygon path proves a join.
-- Explicit jumps still split; failed searches may bisect their span, with a
-- fixed total retry budget. Unresolved pieces retain the
-- existing layered-cell/spiral handling, never an invented polygon link.
H.BODYPOLYLOOK=8
function H.CorridorBody(chain,ax,ay,bx,by)
    if not H.pn then return H.StackedBody(chain,ax,ay,bx,by) end
    local pieces,pending,tries={},{},0
    local policyGaps={}
    local function queue(a,b)
        while a<b and not H.NodePolys(chain[a]) do a=a+1 end
        while b>a and not H.NodePolys(chain[b]) do b=b-1 end
        if a<b then pending[#pending+1]={a,b} end
    end
    local function refine(a,b)
        tries=tries+1
        -- A missing coarse assignment may hide a bridge or a shore. Prove
        -- a dry polygon connection before replacing that unknown stretch;
        -- do not introduce a new swim while repairing its geometry.
        local dryOnly
        for i=a+1,b-1 do if not H.NodePolys(chain[i]) then dryOnly=true;break end end
        local pts,cost,length=polyRun(chain,a,b,a==1 and ax or nil,a==1 and ay or nil,
            b==#chain and bx or nil,b==#chain and by or nil,dryOnly)
        if pts and dryOnly and not H.PolyGapPolicy(chain,a,b,cost,length) then
            policyGaps[#policyGaps+1]={a,b}
            H.stats.policyGaps=(H.stats.policyGaps or 0)+1
            -- Coverage itself gives the split points. Repeatedly bisecting
            -- a long outdoor gap would spend the entire retry budget before
            -- retaining the precise entrances on both sides.
            local first
            for i=a,b do
                if H.NodePolys(chain[i]) then first=first or i
                elseif first then queue(first,i-1);first=nil end
            end
            if first then queue(first,b) end
            return
        end
        if pts then pieces[#pieces+1]={a=a,b=b,pts=pts}
        elseif b-a>1 then
            local mid=floor((a+b)/2)
            queue(a,mid);queue(mid,b)
        end
    end
    local first,last
    for i,n in ipairs(chain) do
        local has=H.NodePolys(n)
        if first and jumpBetween(chain[i-1],n) then
            queue(first,last);first=nil
        end
        if has then first=first or i;last=i end
    end
    if first then queue(first,last) end
    -- Try the largest remaining stretch first: a broken hall entrance must
    -- not consume every retry before the bridge in the opposite direction.
    while #pending>0 and tries<H.BODYPOLYLOOK do
        local best=1
        for i=2,#pending do
            if pending[i][2]-pending[i][1]>pending[best][2]-pending[best][1] then best=i end
        end
        local part=table.remove(pending,best)
        refine(part[1],part[2])
    end
    H.stats.polyBodyTries=(H.stats.polyBodyTries or 0)+tries
    local function fallback(a,b,x1,y1,x2,y2)
        if #policyGaps==0 then return H.StackedBody({unpack(chain,a,b)},x1,y1,x2,y2) end
        local cuts={a,b}
        for _,r in ipairs(policyGaps) do
            if r[1]>a and r[1]<b then cuts[#cuts+1]=r[1] end
            if r[2]>a and r[2]<b then cuts[#cuts+1]=r[2] end
        end
        table.sort(cuts)
        local out={}
        for i=2,#cuts do
            local first,last=cuts[i-1],cuts[i]
            if first<last then
                local preserve
                for _,r in ipairs(policyGaps) do if first>=r[1] and last<=r[2] then preserve=true;break end end
                local ex,ey=x2,y2
                if last<b then ex,ey=H.Point(chain[last]) end
                local part=H.StackedBody({unpack(chain,first,last)},x1,y1,ex,ey,preserve)
                for k,p in ipairs(part) do if k>1 or #out==0 then out[#out+1]=p end end
                x1,y1=ex,ey
            end
        end
        return out
    end
    if #pieces==0 then return fallback(1,#chain,ax,ay,bx,by) end
    table.sort(pieces,function(a,b) return a.a<b.a end)
    local out={}
    local function add(pts)
        for i,p in ipairs(pts) do if i>1 or #out==0 then out[#out+1]=p end end
    end
    local from,fx,fy=1,ax,ay
    for _,piece in ipairs(pieces) do
        local pts=piece.pts
        if piece.a>from then
            add(fallback(from,piece.a,fx,fy,pts[1][1],pts[1][2]))
        end
        add(pts)
        from,fx,fy=piece.b,pts[#pts][1],pts[#pts][2]
    end
    if from<#chain then add(fallback(from,#chain,fx,fy,bx,by)) end
    H.stats.polyBodies=(H.stats.polyBodies or 0)+#pieces
    return out
end
function H:Refine(cont,x1,y1,x2,y2,doors,level)
    local t0=clock()
    -- (your continent made current: another plan may have used another one in between)
    self:Use(cont)
    self:Costs()
    local z1=endZ(self,doors,"from",level,cont,x1,y1)
    local z2=endZ(self,doors,"to",level,cont,x2,y2)
    local nodes,_,_,_,ex,ey,tail=H.Query(x1,y1,z1,x2,y2,z2,nil,false)
    if ex then x2,y2=ex,ey end
    local path
    if nodes then
        -- The nearby coarse anchor need not belong to the floor beneath the
        -- actual start. Never turn a proven disconnected floor into a coarse
        -- guide through walls when its precise corridor cannot be found.
        if type(z1)=="number" and H.pn then
            local px,py=yardsOf(x1,y1)
            local p=H.PolyAt(nodes[1],px,py,z1)
            local pz=p and H.PolyHas(p,px,py) and H.PolyZ(p,px,py)
            if pz and abs(pz-z1)<=H.ZNEAR and H.PolyJoinsNode(p,nodes[1])==false then
                return nil,"start floor is disconnected"
            end
        end
        -- A platform disconnected in the raw polygon graph must not become
        -- a straight climb from the coarse graph's nearby floor. Precomputed
        -- tails already provide their own qualified endpoint connection.
        if not tail and type(z2)=="number" and H.pn then
            local px,py=yardsOf(x2,y2)
            local p=H.PolyAt(nodes[#nodes],px,py,z2)
            local pz=p and H.PolyHas(p,px,py) and H.PolyZ(p,px,py)
            if pz and abs(pz-z2)<=H.ZNEAR and H.PolyJoinsNode(p,nodes[#nodes])==false then
                return nil,"target floor is disconnected"
            end
        end
        -- The ends on the polygons where the data has them; the cells between.
        local head,hk=H.PolyEnd(nodes,x1,y1,x2,y2,z1,z2)
        if head and hk==#nodes then
            path=head
            H.stats.polyEnds=(H.stats.polyEnds or 0)+2
        else
            local rev={}
            for i=#nodes,1,-1 do rev[#rev+1]=nodes[i] end
            local tail,tk,tailPolys=H.PolyEnd(rev,x2,y2,nil,nil,z2)
            -- The forward search can exhaust its budget while the existing
            -- search from the other end finds the entire corridor. Previously
            -- i1<=i0 discarded that complete result and drew coarse cell
            -- centres through stairs, walls and bridges. Reuse its polygons,
            -- checking direction and both actual endpoints before funneling.
            if tail and tk==#nodes and tailPolys then
                local list=H.ReversePolys(tailPolys)
                local sx,sy=yardsOf(x1,y1)
                local ex,ey=yardsOf(x2,y2)
                if list and H.PolyHas(list[1],sx,sy) and H.PolyHas(list[#list],ex,ey) then
                    path=H.PolyWay(list,sx,sy,ex,ey)
                    if path then H.stats.polyEnds=(H.stats.polyEnds or 0)+2 end
                end
            end
            if not path then
                local i0=head and hk or 1
                local i1=tail and (#nodes+1-tk) or #nodes
                if i1<=i0 then tail,i1=nil,#nodes end
                local mid={}
                for i=i0,i1 do mid[#mid+1]=nodes[i] end
                local ax,ay=x1,y1
                if head then ax,ay=head[#head][1],head[#head][2] end
                local bx,by=x2,y2
                if tail then bx,by=tail[#tail][1],tail[#tail][2] end
                local body=H.CorridorBody(mid,ax,ay,bx,by)
                path={}
                for i=1,(head and #head-1 or 0) do path[#path+1]=head[i] end
                for _,p in ipairs(body) do path[#path+1]=p end
                if tail then for i=#tail-1,1,-1 do path[#path+1]=tail[i] end end
                H.stats.polyEnds=(H.stats.polyEnds or 0)+(head and 1 or 0)+(tail and 1 or 0)
            end
        end
    end
    -- (the ends with their heights where known: Navigate's loop cut tells a stair walked down and back from a climb)
    if path and path[1] and type(z1)=="number" and type(path[1])=="table" and path[1].z==nil then path[1].endz=z1 end
    if path and tail then path=H.AddTail(path,tail) end
    if path and #path>1 and type(z2)=="number" and type(path[#path])=="table" and path[#path].z==nil then path[#path].endz=z2 end
    local s=H.stats
    local d=clock()-t0
    s.refined=(s.refined or 0)+1;s.refineMs=(s.refineMs or 0)+d;s.longestRefineMs=max(s.longestRefineMs or 0,d)
    return path
end
function H:Report()
    local s=H.stats
    return string.format("Planner: navmesh; %d walk(s) and %d search(es) to a town's edge on the abstract graph %.0f ms (%d layer pair(s) tried), %d refined %.0f ms (longest %.0f ms)%s.",
        s.walks or 0,s.many or 0,s.walkMs or 0,s.tries or 0,s.refined or 0,s.refineMs or 0,s.longestRefineMs or 0,
        (s.nopathKnown or 0)>0 and string.format("; %d search(es) skipped, known to find no way",s.nopathKnown) or "")
end

---------------------------------------------------------------- after login
-- The data of your continent made current and costed some seconds after login, in
-- slices (Claude 2026-10-25, Florian: the first way
-- began with one piece of 80 ms, the jump tables and the class costs built at once). H.prepared: when it was.
H.PREPAREDELAY=6
function H:Prepare()
    local G=Routing.Scheduler
    local N=Routing.Navigate
    local cont=N and N.Here and select(1,N:Here())
    local data=rawget(_G,"BVRoutingNav") or {}
    if not data[cont] then cont=next(data) end
    if not (G and G.Run and cont and not self:Missing(cont)) then return end
    G.Run(function()
        local t0=clock()
        if self:Active(cont) then
            self:Costs()
            -- which transitions of this continent are only a level's border on the same surface (N.HpaFlat), now
            -- rather than at the first way (1-2 s of searches then)
            local Nv=Routing.Navigate
            if Nv and Nv.HpaFlat and Nv.Doors then
                for i,door in ipairs(Nv:Doors()) do
                    if i%8==0 then breathe() end
                    if door[1] and door[1].cont==cont then Nv.HpaFlat(door) end
                end
            end
        end
        return clock()-t0
    end,function(ms) H.prepared={cont=cont,ms=ms} end,false)
end
-- Whether to prepare after login: Routing's "Prepare after login" (on by default) and navmesh data for a continent.
function H:PrepareActive()
    if Routing:Config().prepareAtLogin==false then return false end
    for cont in pairs(rawget(_G,"BVRoutingNav") or {}) do if not H:Missing(cont) then return true end end
    return false
end
do
    local ns=Routing.ns
    -- (the setting read only then: Routing:Config takes Gather's old settings over on its first read)
    -- One shot, the client's C_Timer.After (no handle left behind; Claude 2026-10-25, full build: a NewTimer fallback
    -- stayed pending in every runtime with Routing loaded). Asked again when it fires.
    local function login()
        local after=C_Timer and C_Timer.After
        if after and H:PrepareActive() then after(H.PREPAREDELAY,function() if H:PrepareActive() then H:Prepare() end end) end
    end
    if IsLoggedIn and IsLoggedIn() then login()
    elseif ns and ns.Events then
        local stop
        stop=ns.Events:Subscribe(H,"PLAYER_LOGIN",function()
            if stop then stop();stop=nil end
            login()
        end)
    end
end

local _,Routing=...
if not Routing.ready then return end
-- Precomputed walks between zones (Florian 2026-10-16: ways through whole
-- zones stored in advance; Crossroads to Silithus on foot took minutes).
-- Codex's offline generator walks between ground nodes (zone crossings,
-- towns, lift ends, docks) with Routing's own search and ships them as
-- Data/Transit.lua (BVRoutingTransit, link contract v1): nodes in continent
-- coordinates, directed edges per faction profile with their yards, and
-- shared geometries as delta zigzag varints in base64 (scale 1e7). A plan
-- gets the nodes and the edges' lengths; an edge's points are decoded only
-- when the way uses it. Nothing here is searched or kept beyond the data.
local ns=Routing.ns
local T={}
Routing.Transit=T
T.SCALE=1e7
local ALPHABET="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CODES={}
for i=1,#ALPHABET do CODES[ALPHABET:sub(i,i)]=i-1 end

-- Points of a geometry text, the first and last replaced by the exact nodes.
function T.Decode(text,a,b)
    local bytes,acc,bits={},0,0
    for i=1,#text do
        local v=CODES[text:sub(i,i)]
        if v then
            acc=acc*64+v;bits=bits+6
            if bits>=8 then bits=bits-8;local div=2^bits;bytes[#bytes+1]=math.floor(acc/div);acc=acc%div end
        end
    end
    local points,x,y,u,factor,axis={},0,0,0,1,1
    for _,byte in ipairs(bytes) do
        u=u+(byte%128)*factor
        if byte>=128 then factor=factor*128
        else
            local delta=u%2==0 and u/2 or -(u+1)/2
            if axis==1 then x=x+delta;axis=2 else y=y+delta;points[#points+1]={x/T.SCALE,y/T.SCALE};axis=1 end
            u,factor=0,1
        end
    end
    if #points>0 and a and b then points[1]={a.x,a.y};points[#points]={b.x,b.y} end
    return points
end
-- The other way (tests and tools): points to a geometry text.
function T.Encode(points)
    local bytes={}
    local lx,ly=0,0
    local function varint(n)
        local u=n>=0 and n*2 or -n*2-1
        while u>=128 do bytes[#bytes+1]=128+u%128;u=math.floor(u/128) end
        bytes[#bytes+1]=u
    end
    for _,p in ipairs(points) do
        local x,y=math.floor(p[1]*T.SCALE+.5),math.floor(p[2]*T.SCALE+.5)
        varint(x-lx);varint(y-ly);lx,ly=x,y
    end
    local out,acc,bits={},0,0
    for _,byte in ipairs(bytes) do
        acc=acc*256+byte;bits=bits+8
        while bits>=6 do bits=bits-6;local div=2^bits;local v=math.floor(acc/div);acc=acc%div;out[#out+1]=ALPHABET:sub(v+1,v+1) end
    end
    if bits>0 then local v=acc*2^(6-bits);out[#out+1]=ALPHABET:sub(v+1,v+1) end
    return table.concat(out)
end

-- Only when computed from exactly the data shipped here (Codex's source
-- contract: Data/Revision.lua holds the revision of the shipped inputs).
function T:Data()
    local data=rawget(_G,"BVRoutingTransit")
    if not (type(data)=="table" and (data.version==1 or data.version==2) and type(data.cont)=="table") then return nil end
    if not Routing.DATAREVISION or data.dataRevision~=Routing.DATAREVISION then return nil end
    return data
end
function T.Faction()
    local ok,faction=pcall(UnitFactionGroup,"player")
    return ok and (faction=="Horde" or faction=="Alliance") and faction or nil
end
-- Only where the settings are not stricter than the profile the walks were
-- found with (Codex's contract: harder rules need the search itself).
function T:Usable(cont)
    if not self:Data() then return false end
    local c=Routing:Config()
    if c.routeTerrain==false or c.cliffs=="never" or c.risk=="block" or c.enemy=="block" then return false end
    if cont and self:Blocked(cont) then return false end
    return true
end
-- Your own hard blocks on the ground of a continent (no-go areas, walls)
-- while your data is read (not "shipped only"): the stored walks do not
-- know them, so the way there is searched (Codex 2026-10-16). Likewise a
-- map of yours whose ground counts otherwise: walkable only where painted,
-- made your own, shipped data off, or another cell or clearance than
-- shipped. Known per data view.
T.blocked={}
function T:Blocked(cont)
    local db=Routing:Store()
    if db.source=="shipped" then return false end
    local k=cont..":"..tostring(Routing.dataVersion)
    if self.blocked[k]~=nil then return self.blocked[k] end
    local pins=ns.MapPins
    local found=false
    local function ground(e) return type(e)=="table" and (e.level or 0)==0 end
    local shipped=Routing.SHIPPED or {}
    for mapID,m in pairs(db.maps or {}) do
        if not found and type(m)=="table" and pins and pins:Continent(mapID)==cont then
            local s=type(shipped[mapID])=="table" and type(shipped[mapID].settings)=="table" and shipped[mapID].settings or {}
            if m.paintedOnly or m.own or m.shippedOff
                or (m.cell~=nil and tonumber(m.cell)~=tonumber(s.cell))
                or (m.clearance~=nil and tonumber(m.clearance)~=tonumber(s.clearance)) then found=true end
        end
    end
    for _,kind in ipairs({"areas","walls"}) do
        for mapID,list in pairs(db[kind] or {}) do
            if not found and type(list)=="table" and pins and pins:Continent(mapID)==cont then
                for _,e in ipairs(list) do
                    if ground(e) and (kind=="walls" or e.kind=="nogo") then found=true;break end
                end
            end
        end
    end
    self.blocked[k]=found
    return found
end
-- The network of a continent for your faction: {nodes={...}, edges={...}},
-- made once per data revision; nodes are plan nodes (kind "transit").
T.nets={}
T.PACE=200      -- nodes or edges built between two looks at the clock (Grid.Breathe)
function T:Net(cont)
    local data=self:Data()
    local faction=self.Faction()
    local raw=data and data.cont[cont]
    if not (raw and faction) then return nil end
    -- (Your data's view first: its version names the rides' links.)
    Routing:Data()
    local key=cont..":"..faction..":"..tostring(data.revision)..":"..tostring(Routing.dataVersion)
    local net=self.nets[key]
    if net then return net end
    local profiles={}
    for _,p in ipairs(data.profiles or {}) do if p.id then profiles[p.id]=p.faction end end
    local nodes={}
    -- Built in pieces inside a plan's coroutine (Claude 2026-10-20: the first way of a
    -- session built thousands of nodes and edges at once, a 0.2 s stall in game).
    local function pace(i)
        if i%T.PACE~=0 then return end
        local G=Routing.Grid
        if G and G.Breathe then G.Breathe() elseif coroutine.running() then coroutine.yield() end
    end
    for i,n in ipairs(raw.nodes or {}) do
        pace(i)
        -- Its own key (Codex 2026-10-16: never the rounded position; nodes
        -- may lie close to lift and bridge ends on purpose).
        -- On a level of your data too (Codex 2026-10-19: the walks Florian
        -- recorded end on the lower platforms of Thunder Bluff's lifts):
        -- only a level that is there; the plan walks on it as on its own.
        local level=(n.level or 0)~=0 and n.level or nil
        if level==nil or (Routing.Level and Routing.Level:Find(level)) then
            -- The walked transitions (bridges) it is an end of: {[link id]=side}.
            local bound
            for _,b in ipairs(type(n.bindings)=="table" and n.bindings or {}) do
                if type(b)=="table" and b.linkId and b.kind=="walk" and (b.side=="a" or b.side=="b") then bound=bound or {};bound[b.linkId]=b.side end
            end
            nodes[i]={cont=cont,x=n.x,y=n.y,kind="transit",name=n.name or ("Transit "..i),zone=n.zone,tkey="T:"..cont..":"..i..":"..tostring(data.revision),bound=bound,level=level}
        end
    end
    local edges={}
    for ei,e in ipairs(raw.edges or {}) do
        pace(ei)
        local f=e.faction or (e.profile and profiles[e.profile])
        local a,b=nodes[e.a],nodes[e.b]
        if f==faction and a and b and (e.kind=="lift" or e.kind=="transport") then
            -- A ride (version 2: typed, its seconds, no walk; Codex
            -- 2026-10-17): a transition of the plan from a to b, only
            -- while its link is in your data.
            local seconds=tonumber(e.seconds)
            if seconds and self:LinkActive(e.linkId) then
                a.pairs=a.pairs or {}
                a.pairs[#a.pairs+1]={b,seconds,{kind=e.kind,name=a.name,seconds=seconds,linkId=e.linkId,transit=true}}
            end
        elseif f==faction and a and b and tonumber(e.yards) and (a.level or 0)~=(b.level or 0) then
            -- A stored walk from the ground up onto a level (a ramp to a
            -- lift's platform): the plan never walks across levels, so it is
            -- a transition in its direction (the way back is its own edge,
            -- Codex 2026-10-19), its time from its yards, its shape kept.
            local seconds=tonumber(e.yards)/T.RUN
            -- (Its shape asked like any stored walk's: the plan's own nodes.)
            local edge={a=a,b=b,yards=e.yards,geometry=e.geometry,segs=e.segs,cont=cont,raw=e}
            a.pairs=a.pairs or {}
            a.pairs[#a.pairs+1]={b,seconds,{kind="walk",name=b.name,seconds=seconds,transit=true,transitEdge=edge,cont=cont}}
        elseif f==faction and a and b and tonumber(e.yards) then
            edges[#edges+1]={a=a,b=b,yards=e.yards,geometry=e.geometry,segs=e.segs,cont=cont,road=tonumber(e.road),
                water=tonumber(e.waterYards),swim=e.swim and true or nil,recorded=e.recorded and true or nil}
        end
    end
    local list={}
    for _,n in pairs(nodes) do list[#list+1]=n end
    table.sort(list,function(x,y) return x.name<y.name end)
    net={nodes=list,edges=edges,geometries=raw.geometries or {}}
    self.nets[key]=net
    return net
end
-- A link of your data by its id (a ride of the network uses it only
-- while it is there); none named: always.
function T:LinkActive(id)
    if id==nil then return true end
    for _,link in ipairs(Routing:Data().links or {}) do
        if type(link)=="table" and link.id==id then return true end
    end
    return false
end
-- Two nodes at the two ends of one walked transition of your data (a
-- bridge with water below, never baked into a stored walk; Codex
-- 2026-10-16): the way between them is searched normally, in the
-- transition's direction. Lifts are rides of their own, never this.
T.active={}
function T:Bound(u,b)
    if not (u.bound and b.bound) then return false end
    local k=tostring(Routing.dataVersion)
    local byID=self.active[k]
    if not byID then
        byID={}
        for _,link in ipairs(Routing:Data().links or {}) do
            if type(link)=="table" and link.id and link.kind~="lift" and link.type~="lift" then byID[link.id]=link end
        end
        self.active={[k]=byID}
    end
    for id,side in pairs(u.bound) do
        local other=b.bound[id]
        local link=byID[id]
        if link and other and other~=side and (side=="a" or not link.oneway) then return true end
    end
    return false
end
-- An edge's weight in the plan: its yards, the part on roads cheaper as
-- in the search (Routing's roadPercent; Fable 2026-10-17: the stored walks
-- were weighed by yards alone, a walk 21 yd shorter over a hill won
-- against the road beside it). Without its road share: its yards.
-- Water Florian walked on purpose (short pieces, wading or swimming;
-- Florian 2026-10-18: "lieber kurz übers Wasser als ein Mordsumweg") costs
-- more than ground, so a dry way of like length wins.
T.RUN=7         -- yards a second a stored walk between levels is timed at
T.WADE=1.5      -- each yard through shallow water counts this many
T.SWIM=3        -- each yard swum counts this many
-- Florian's own recorded ways (recorded=true, Codex 2026-10-19) count less than the older
-- derived ones: an old line a little shorter beside his walk no longer wins (Thousand Needles,
-- Shimmering Flats: 93 % on his way, the rest on an old parallel line).
T.RECORDED=0.8  -- each yard of a recorded way counts this much
-- roadCost: the road preference as a factor, when the caller has it (SeedTransit,
-- once for 15000 walks; Config() for each was time and garbage).
function T.Rank(e,roadCost)
    local yards=e.yards
    local road=tonumber(e.road)
    if road then
        road=math.max(0,math.min(1,road))
        local cost=roadCost or (tonumber(Routing:Config().roadPercent) or 60)/100
        yards=yards*(road*cost+(1-road))
    end
    local water=math.min(tonumber(e.water) or 0,e.yards)
    if water>0 then yards=yards+water*((e.swim and T.SWIM or T.WADE)-1) end
    if e.recorded then yards=yards*T.RECORDED end
    return yards
end
-- An edge's points (continent coordinates).
-- A geometry's points with their marks, decoded once per network.
local function shape(net,index)
    net.decoded=net.decoded or {}
    local known=net.decoded[index]
    if known then return known end
    local g=net.geometries[index]
    local text=type(g)=="table" and g.p or g
    if type(text)~="string" then return nil end
    local points=T.Decode(text)
    local attrs=type(g)=="table" and g.attrs
    if type(attrs)=="table" then
        for i,a in pairs(attrs) do
            local p=points[tonumber(i)]
            if p and type(a)=="table" then for k,v in pairs(a) do if k~=1 and k~=2 then p[k]=v end end end
        end
    end
    net.decoded[index]=points
    return points
end
-- Version 2 (shared pieces, Codex 2026-10-17: the same road stored once):
-- an edge is a row of pieces {geometry, first, last, reverse} (1-based
-- point indices of that geometry); pieces in a row share their joint point.
-- The first and last point become the exact nodes.
function T:PathOf(edge,net)
    local out={}
    for _,seg in ipairs(edge.segs) do
        local points=shape(net,seg[1])
        if not points then return nil end
        local first,last=seg[2] or 1,seg[3] or #points
        if first<1 or last>#points or first>last then return nil end
        local from,to,step=first,last,1
        if seg[4] then from,to,step=last,first,-1 end
        for i=from,to,step do
            local p=points[i]
            local q={p[1],p[2]}
            for k,v in pairs(p) do if k~=1 and k~=2 then q[k]=v end end
            if #out==0 or i~=from then out[#out+1]=q end
        end
    end
    if #out<2 then return nil end
    out[1][1],out[1][2]=edge.a.x,edge.a.y
    out[#out][1],out[#out][2]=edge.b.x,edge.b.y
    return out
end
function T:Path(edge,net)
    if type(edge.segs)=="table" then return self:PathOf(edge,net) end
    local g=net.geometries[edge.geometry]
    local text=type(g)=="table" and g.p or g
    if type(text)~="string" then return nil end
    local points=T.Decode(text,edge.a,edge.b)
    -- The points' marks (fixed, link, ...) by their index, as delivered
    -- (Codex 2026-10-16); never a general walkable exception.
    local attrs=type(g)=="table" and g.attrs
    if type(attrs)=="table" then
        for i,a in pairs(attrs) do
            local p=points[tonumber(i)]
            if p and type(a)=="table" then for k,v in pairs(a) do if k~=1 and k~=2 then p[k]=v end end end
        end
    end
    return points
end
-- Only for long ways (Codex 2026-10-16: short ways must not plan
-- differently just because the network's nodes are there): another
-- continent, or at least LONG yards in a line.
T.LONG=2000
-- (Tests: /bv route network always uses the network on short ways too.)
T.always=false
function T:Long(cont,x,y,goal)
    if not (goal and goal.cont) then return false end
    if self.always then return true end
    if goal.cont~=cont then return true end
    if Routing.Navigate.Yards(cont,x,y,goal.x,goal.y)>=self.LONG then return true end
    -- Short, but both ends on anchors of the network (Codex 2026-10-17:
    -- Crossroads' flight master to its inn, searched over ground that
    -- does not hold, while the proven way between them is stored).
    -- Short, from the ground up to a level the network reaches (Codex
    -- 2026-10-19: Mulgore to Thunder Bluff's lifts, the recorded ramps to
    -- their lower platforms never used): the network too.
    local here
    if Routing.Navigate.Here then local _;_,_,_,here=Routing.Navigate:Here() end
    if (goal.level or 0)~=(here or 0) and (self:Reaches(cont,goal.level) or self:Reaches(cont,here)) then return true end
    if (goal.level or 0)==0 and self:OnAnchor(cont,x,y) and self:OnAnchor(cont,goal.x,goal.y) then return true end
    -- Short, both ends within NEARNODE yards of a node of the network on their own level
    -- (Codex 2026-10-20, variant "Cnode" of 1410 cases: in Crossroads the guessed 58 yd from
    -- the inn to Devrak went through a building, the network's 278 yd hold; same plans as
    -- the variant by recorded geometry, without its index).
    -- Second value "near": only this rule turned the network on; a plan that finds no
    -- way through it plans on the ground as before (Navigate.noNear; Codex 2026-10-20:
    -- Mountaineer Grugelm, the near anchors led nowhere and the wide plan failed too).
    if Routing.Navigate.noNear then return false end
    if self:NearNode(cont,x,y,here) and self:NearNode(cont,goal.x,goal.y,goal.level) then return true,"near" end
    return false
end
T.NEARNODE=150
function T:NearNode(cont,x,y,level)
    if not (x and y and self:Usable(cont)) then return false end
    local net=self:Net(cont)
    for _,n in ipairs(net and net.nodes or {}) do
        if (n.level or 0)==(level or 0) and Routing.Navigate.Yards(cont,x,y,n.x,n.y)<=self.NEARNODE then return true end
    end
    return false
end
-- Whether the network has a node on a level of the same map as this one.
function T:Reaches(cont,level)
    if (level or 0)==0 or not self:Usable(cont) then return false end
    local _,map=Routing.Level:Find(level)
    if not map then return false end
    local net=self:Net(cont)
    for _,n in ipairs(net and net.nodes or {}) do
        if n.level then
            local _,m=Routing.Level:Find(n.level)
            if m==map then return true end
        end
    end
    return false
end
T.ONANCHOR=2
function T:OnAnchor(cont,x,y)
    if not (x and y and self:Usable(cont)) then return false end
    local net=self:Net(cont)
    for _,n in ipairs(net and net.nodes or {}) do
        if Routing.Navigate.Yards(cont,x,y,n.x,n.y)<=self.ONANCHOR then return true end
    end
    return false
end

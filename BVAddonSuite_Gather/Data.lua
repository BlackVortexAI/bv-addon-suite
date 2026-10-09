local _,G=...
if not G.ready then return end
-- Node database (account-wide SavedVariables BVGatherDB, not per profile:
-- the world is the same for all your characters). Per kind and map a list
-- of nodes {x, y, name, names, count, last, shared}; a node found again
-- within the merge distance counts up instead of adding a second pin.
-- Deduplication (Florian 2026-10-08): your position at gathering lies a few
-- yards off the plant, from whatever side you came, so a node's position
-- moves towards the mean of its finds; different herbs within the spawn
-- distance are one spawn point (Classic rotates plants on shared spawns):
-- name = the last one seen, names = every one seen there with its count.
-- GatherMate2's coordinate packing (x and y to four decimals) is used for
-- import, export and sharing, so nothing is lost on the way.
--
-- Sources (Florian 2026-10-09: databases kept apart, merged when used):
-- your own finds stay in db.nodes and always come first (the surest source:
-- their position, plant and last seen win); imports (GatherMate2, text),
-- nodes shared live by your group and guild and the known spawn points of a
-- data package (read only, never saved) each keep their own lists. The
-- nodes you see, plan and export are a merged view per kind and map, built
-- when first asked for: own nodes as they are, then the other sources in
-- order, each node joining an own (or earlier) one by the same rules as the
-- clean-up (D.Same) or standing alone. Forgetting a node of another source
-- leaves a mark in your data (db.hidden), the source itself is untouched.
local D={merged={},revision=0}
local sizes={}  -- world size per map (D.Yards)
G.Data=D
D.ORDER={"gathermate","text","import","shared","known"}
D.LABEL={own="Own finds",gathermate="GatherMate2",text="Text import",import="Earlier imports",shared="Shared",known="Known spawns"}

function D:Init()
    if type(BVGatherDB)~="table" then BVGatherDB={} end
    local db=BVGatherDB
    if type(db.nodes)~="table" then db.nodes={} end
    for _,t in ipairs(G.TYPES) do if type(db.nodes[t.id])~="table" then db.nodes[t.id]={} end end
    if type(db.sources)~="table" then db.sources={} end
    if type(db.hidden)~="table" then db.hidden={} end
    self.db=db
    -- Version 2: imported and shared nodes leave your own list for their sources.
    if (db.version or 1)<2 then
        for _,t in ipairs(G.TYPES) do
            for mapID,list in pairs(db.nodes[t.id]) do
                for i=#list,1,-1 do
                    local node=list[i]
                    local source=node.shared and "shared" or (node.last==nil and "import") or nil
                    if source then
                        table.remove(list,i)
                        node.shared=nil
                        local into=self:SourceList(source,t.id,mapID,true)
                        table.insert(into,1,node)
                    end
                end
            end
        end
        db.version=2
    end
    return db
end
-- A source's list of one kind and map (create: make it when missing).
function D:SourceList(source,kind,mapID,create)
    local db=self.db or self:Init()
    if source=="own" then
        local byMap=db.nodes[kind]
        if create and byMap and not byMap[mapID] then byMap[mapID]={} end
        return byMap and byMap[mapID]
    end
    if source=="known" then
        local known=rawget(_G,"BVGatherKnown")
        return type(known)=="table" and type(known[kind])=="table" and known[kind][mapID] or nil
    end
    local entry=db.sources[source]
    if not entry and create then entry={nodes={},time=time()};db.sources[source]=entry end
    if not entry then return nil end
    entry.nodes[kind]=entry.nodes[kind] or (create and {} or nil)
    local byMap=entry.nodes[kind]
    if not byMap then return nil end
    if create and not byMap[mapID] then byMap[mapID]={} end
    return byMap[mapID]
end
-- Whether a source joins the merged view (settings; known spawns by their own switch).
-- Every source can be switched, your own finds too (Florian 2026-10-09);
-- the choice is kept even for a source without nodes yet.
function D:SourceOn(source)
    local c=G:Config()
    if source=="own" then return c.ownFinds~=false end
    if source=="known" then return c.knownSpawns end
    if c.sourceOff[source] then return false end
    local entry=(self.db or self:Init()).sources[source]
    return entry~=nil and not entry.off
end
function D:SetSourceOn(source,on)
    local c=G:Config()
    if source=="own" then c.ownFinds=on and true or false
    elseif source=="known" then c.knownSpawns=on and true or false
    else
        c.sourceOff[source]=not on or nil
        local entry=(self.db or self:Init()).sources[source];if entry then entry.off=not on or nil end
    end
    self:Dirty()
end
function D:ForgetSource(source)
    (self.db or self:Init()).sources[source]=nil
    self:Dirty()
end
-- Something changed in a source other than your own: every merged view anew.
function D:Dirty() self.revision=self.revision+1;self.merged={} end
-- Map IDs with nodes of a kind in any source that is on.
function D:Maps(kind)
    local db=self.db or self:Init()
    local maps={}
    if self:SourceOn("own") then
        for mapID,list in pairs(db.nodes[kind] or {}) do if #list>0 then maps[mapID]=true end end
    end
    for source,entry in pairs(db.sources) do
        if self:SourceOn(source) then for mapID in pairs(entry.nodes[kind] or {}) do maps[mapID]=true end end
    end
    local known=rawget(_G,"BVGatherKnown")
    if G:Config().knownSpawns and type(known)=="table" and type(known[kind])=="table" then
        for mapID in pairs(known[kind]) do maps[mapID]=true end
    end
    return maps
end
-- Known spawn points come packed: {x1, y1, nameIndex1, x2, ...}, names in BVGatherKnown.names.
local function unpackKnown(list)
    local known=rawget(_G,"BVGatherKnown")
    local names=type(known)=="table" and known.names or {}
    local out={}
    if type(list)~="table" then return out end
    for i=1,#list-2,3 do out[#out+1]={x=list[i],y=list[i+1],name=names[list[i+2]],count=0,exact=true} end
    return out
end
local function hiddenNear(db,kind,mapID,x,y)
    local marks=db.hidden[kind] and db.hidden[kind][mapID]
    if not marks then return false end
    for _,mark in ipairs(marks) do if math.abs(mark.x-x)<.004 and math.abs(mark.y-y)<.004 then
        local yards=D.Yards(mapID,mark.x,mark.y,x,y)
        if not yards or yards<=6 then return true end
    end end
    return false
end
-- The merged view of one kind and map (see above). Without other sources it
-- is your own list itself.
function D:Merged(kind,mapID)
    local db=self.db or self:Init()
    local own=self:SourceOn("own") and db.nodes[kind] and db.nodes[kind][mapID] or nil
    local cache=self.merged[kind] and self.merged[kind][mapID]
    if cache and cache.own==own and cache.count==(own and #own or 0) and cache.revision==self.revision then return cache.list end
    local others={}
    for _,source in ipairs(self.ORDER) do
        if self:SourceOn(source) then
            local list=self:SourceList(source,kind,mapID)
            if source=="known" then list=list and unpackKnown(list) end
            if list and #list>0 then others[#others+1]={source=source,list=list} end
        end
    end
    local list,origin={},{}
    if #others==0 and not (db.hidden[kind] and db.hidden[kind][mapID]) then
        list=own or {}
    else
        -- A grid of cells as large as the merge distance: a node only meets
        -- the nodes of its own and the eight neighbouring cells.
        local c=G:Config()
        local reach=math.max(c.merge,c.spawn,1)
        D.Yards(mapID,0,0,0,0)
        local size=sizes[mapID]
        local cw=size and type(size[1])=="number" and size[1]>0 and reach/size[1] or .01
        local ch=size and type(size[2])=="number" and size[2]>0 and reach/size[2] or .01
        local grid={}
        local function cell(x,y) return math.floor(x/cw),math.floor(y/ch) end
        local function put(entry)
            local gx,gy=cell(entry.x,entry.y)
            local key=gx*100000+gy
            grid[key]=grid[key] or {};table.insert(grid[key],entry)
        end
        local function near(x,y,name,under)
            local gx,gy=cell(x,y)
            for dx=-1,1 do for dy=-1,1 do
                for _,entry in ipairs(grid[(gx+dx)*100000+gy+dy] or {}) do
                    if D.Same(mapID,entry,x,y,name,under) then return entry end
                end
            end end
        end
        for _,node in ipairs(own or {}) do list[#list+1]=node;origin[node]={own=true};put(node) end
        for _,other in ipairs(others) do
            for _,node in ipairs(other.list) do
                if not hiddenNear(db,kind,mapID,node.x,node.y) then
                    local into=near(node.x,node.y,node.name,node.under)
                    if into then origin[into][other.source]=true
                    else
                        local copy={x=node.x,y=node.y,name=node.name,names=node.names,count=node.count,last=node.last,
                            under=node.under,place=node.place,exact=node.exact,from=node}
                        list[#list+1]=copy;origin[copy]={[other.source]=true};put(copy)
                    end
                end
            end
        end
    end
    self.merged[kind]=self.merged[kind] or {}
    self.merged[kind][mapID]={list=list,origin=origin,own=own,count=own and #own or 0,revision=self.revision}
    return list
end
-- The sources a node of the merged view comes from ({own=true, known=true, ...}).
function D:Sources(kind,mapID,node)
    local cache=self.merged[kind] and self.merged[kind][mapID]
    local origin=cache and cache.origin[node]
    if origin then return origin end
    return {own=true}
end
-- A node only others gave you (shared or a text import), not seen yourself.
function D:OnlyShared(kind,mapID,node)
    local s=self:Sources(kind,mapID,node)
    return not s.own and (s.shared or s.text) and true or false
end
-- Nodes of a kind (all maps: the map IDs as keys) or of one map, merged.
function D:Nodes(kind,mapID)
    local db=self.db or self:Init()
    if not db.nodes[kind] then return nil end
    if mapID==nil then
        local out={}
        for map in pairs(self:Maps(kind)) do out[map]=self:Merged(kind,map) end
        return out
    end
    return self:Merged(kind,mapID)
end
-- Yards between two points of one map (its world size, remembered), or nil.
function D.Yards(mapID,x1,y1,x2,y2)
    local size=sizes[mapID]
    if not size then
        local w,h=G.Call("C_Map.GetMapWorldSize",mapID)
        size={w,h};if type(w)=="number" and w>0 then sizes[mapID]=size end
    end
    local width,height=size[1],size[2]
    if type(width)~="number" or width<=0 then return nil end
    local dx,dy=(x2-x1)*width,(y2-y1)*height
    return math.sqrt(dx*dx+dy*dy)
end
-- Same node: the same name within the merge distance, or any name within
-- the (smaller) spawn distance.
function D.Same(mapID,node,x,y,name,under)
    local c=G:Config()
    -- Underground and surface never merge, however close.
    if (node.under==true)~=(under==true) then return false end
    local yards=D.Yards(mapID,node.x,node.y,x,y)
    local sameName=node.name==name or not name or not node.name or (node.names and name and node.names[name])
    -- Spawn distance 0 keeps different plants apart, even on the same spot.
    if not sameName and c.spawn<=0 then return false end
    if yards then return yards<=(sameName and c.merge or c.spawn) end
    local limit=sameName and .003 or .0015
    return math.abs(node.x-x)<limit and math.abs(node.y-y)<limit
end
-- Folds a find into a node: count, names, last seen, position towards the
-- mean (weight capped, so the position settles).
function D.Fold(node,x,y,name,opts)
    opts=opts or {}
    local weight=math.min(node.count or 1,9)
    -- An exact position (from a database) stays; your offset finds do not move it.
    if not opts.import and not opts.exact and not node.exact then
        node.x=(node.x*weight+x)/(weight+1);node.y=(node.y*weight+y)/(weight+1)
    elseif opts.exact then node.x,node.y,node.exact=x,y,true end
    if not opts.import then node.count=(node.count or 1)+1;node.last=opts.time or time() end
    if name then
        node.names=node.names or (node.name and {[node.name]=1} or {})
        node.names[name]=(node.names[name] or 0)+(opts.import and 0 or 1)
        if not opts.import or not node.name then node.name=name end
    end
    -- Seen yourself: no longer only shared.
    if not opts.shared then node.shared=nil end
end
-- Adds a node to a source (opts.source; your own finds without one) or
-- counts up the same one there; returns the node, new.
function D:Add(kind,mapID,x,y,name,opts)
    if not G.TYPE[kind] or type(mapID)~="number" or type(x)~="number" or type(y)~="number" then return nil end
    opts=opts or {}
    local source=opts.source or "own"
    local list=self:SourceList(source,kind,mapID,true)
    if source~="own" then self:Dirty() end
    -- An exact position (an import from a database) wins over your offset ones.
    if opts.import and not opts.shared then opts.exact=true end
    for _,node in ipairs(list) do
        if D.Same(mapID,node,x,y,name,opts.under) then
            D.Fold(node,x,y,name,opts)
            if opts.place and not node.place then node.place=opts.place end
            return node,false
        end
    end
    local node={x=x,y=y,name=name,names=name and {[name]=opts.import and 0 or 1} or nil,count=opts.count or 1,
        last=opts.time or (not opts.import and time() or nil),exact=opts.exact or nil,
        under=opts.under or nil,place=opts.place}
    list[#list+1]=node
    return node,true
end
-- Clean-up of an existing database (also after imports): duplicates of one
-- spawn point merge; returns how many nodes went. kind and mapID narrow it.
function D:Cleanup(kind,onlyMap)
    local removed=0
    local db=self.db or self:Init()
    local stores={db.nodes}
    for _,entry in pairs(db.sources) do stores[#stores+1]=entry.nodes end
    for _,store in ipairs(stores) do
    for _,t in ipairs(G.TYPES) do
        if not kind or kind==t.id then
            for mapID,list in pairs(store[t.id] or {}) do
                if onlyMap and mapID~=onlyMap then list=nil end
                local kept={}
                for _,node in ipairs(list or {}) do
                    local into
                    for _,other in ipairs(kept) do if D.Same(mapID,other,node.x,node.y,node.name,node.under) then into=other;break end end
                    if into then
                        local a,b=into.count or 1,node.count or 1
                        if node.exact and not into.exact then into.x,into.y,into.exact=node.x,node.y,true
                        elseif not into.exact then into.x,into.y=(into.x*a+node.x*b)/(a+b),(into.y*a+node.y*b)/(a+b) end
                        into.count=a+b
                        into.names=into.names or (into.name and {[into.name]=a} or {})
                        for name,n in pairs(node.names or (node.name and {[node.name]=b} or {})) do into.names[name]=(into.names[name] or 0)+n end
                        -- The plant seen last names the spawn point.
                        if (node.last or 0)>(into.last or 0) then into.name=node.name end
                        into.last=math.max(into.last or 0,node.last or 0);if into.last==0 then into.last=nil end
                        into.shared=(into.shared and node.shared) or nil
                        removed=removed+1
                    else kept[#kept+1]=node end
                end
                if list then
                    for i=#list,1,-1 do list[i]=nil end
                    for i,node in ipairs(kept) do list[i]=node end
                end
            end
        end
    end
    end
    self:Dirty()
    return removed
end
-- Forgets a node of the merged view: your own one goes; one of another
-- source is hidden (a mark in your data), and so is everything that joined it.
function D:Remove(kind,mapID,node)
    local db=self.db or self:Init()
    local sources=self:Sources(kind,mapID,node)
    local removed=false
    local own=db.nodes[kind] and db.nodes[kind][mapID]
    for i,entry in ipairs(own or {}) do if entry==node then table.remove(own,i);removed=true;break end end
    local others=false
    for source in pairs(sources) do if source~="own" then others=true end end
    if others or not removed then
        db.hidden[kind]=db.hidden[kind] or {}
        db.hidden[kind][mapID]=db.hidden[kind][mapID] or {}
        table.insert(db.hidden[kind][mapID],{x=node.x,y=node.y})
        removed=true
    end
    self:Dirty()
    return removed
end
-- Empties your own finds and every stored source (of one kind or all); the
-- known spawns of a data package are not stored and stay.
function D:Clear(kind)
    local db=self.db or self:Init()
    for _,t in ipairs(G.TYPES) do
        if not kind or kind==t.id then
            db.nodes[t.id]={}
            for _,entry in pairs(db.sources) do entry.nodes[t.id]={} end
            if db.hidden[t.id] then db.hidden[t.id]={} end
        end
    end
    self:Dirty()
end
-- Nodes of the merged view (onlyShared: those only others gave you).
function D:Count(kind,onlyShared)
    local total=0
    for mapID,list in pairs(self:Nodes(kind) or {}) do
        for _,node in ipairs(list) do if not onlyShared or self:OnlyShared(kind,mapID,node) then total=total+1 end end
    end
    return total
end
-- Nodes stored in one source (all kinds or one).
function D:SourceCount(source,kind)
    local db=self.db or self:Init()
    local total=0
    for _,t in ipairs(G.TYPES) do
        if not kind or kind==t.id then
            local byMap
            if source=="own" then byMap=db.nodes[t.id]
            elseif source=="known" then local known=rawget(_G,"BVGatherKnown");byMap=type(known)=="table" and known[t.id] or nil
            else byMap=db.sources[source] and db.sources[source].nodes[t.id] end
            for _,list in pairs(byMap or {}) do total=total+(source=="known" and math.floor(#list/3) or #list) end
        end
    end
    return total
end
-- Names known per kind (filters, import previews).
function D:Names(kind)
    local seen,out={},{}
    for _,list in pairs(self:Nodes(kind) or {}) do
        for _,node in ipairs(list) do
            for name in pairs(node.names or (node.name and {[node.name]=1} or {})) do
                if not seen[name] then seen[name]=true;out[#out+1]=name end
            end
        end
    end
    table.sort(out)
    return out
end
-- GatherMate2's packing: x and y to four decimals, level in the last two digits.
function D.Encode(x,y) return math.floor(x*10000+.5)*1000000+math.floor(y*10000+.5)*100 end
function D.Decode(coord)
    if type(coord)~="number" then return nil end
    return math.floor(coord/1000000)/10000,math.floor(coord%1000000/100)/10000
end

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
                    if x then out[#out+1]={x=x,y=y,X=x*s.width,Y=y*s.height,kind=t.id,node=node,mapID=zone} end
                end
            end
        end
    end
    return out
end

-- Stops: nodes join a stop while every one of them stays within the radius
-- of its middle (greedy, nearest stop first).
local function yards(a,b) local dx,dy=a.X-b.X,a.Y-b.Y;return math.sqrt(dx*dx+dy*dy) end
function P.Cluster(nodes,radius)
    table.sort(nodes,function(a,b) if a.X~=b.X then return a.X<b.X end return a.Y<b.Y end)
    local stops={}
    for i,node in ipairs(nodes) do
        local best,bestDistance
        for _,stop in ipairs(stops) do
            local d=yards(stop,node)
            if d<=radius*2 and (not bestDistance or d<bestDistance) then
                local n=#stop.nodes+1
                local mid={X=(stop.X*(n-1)+node.X)/n,Y=(stop.Y*(n-1)+node.Y)/n}
                local fits=yards(mid,node)<=radius
                for _,member in ipairs(stop.nodes) do if fits and yards(mid,member)>radius then fits=false end end
                if fits then best,bestDistance=stop,d end
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
    for i=1,#order do local b=successor(order,i,loop);if b then total=total+yards(order[i],b) end end
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
                for m=i,i+k-2 do through=through+yards(at(m),at(m+1)) end
                if prev then through=through+yards(prev,at(i)) end
                if nxt then through=through+yards(at(i+k-1),nxt) end
                local shortcut=(prev and nxt) and yards(prev,nxt) or 0
                local nodes=0
                for m=i,i+k-1 do nodes=nodes+#at(m).nodes end
                local ratio=(through-shortcut)/math.max(1,nodes)
                if not bestRatio or ratio>bestRatio then best,bestRatio,bestLength=i,ratio,k end
            end
        end
        if not bestRatio or bestRatio<=limit then break end
        local cut={}
        for m=best,best+bestLength-1 do cut[#cut+1]=at(m) end
        local gone={};for _,stop in ipairs(cut) do gone[stop]=true;removed[#removed+1]=stop end
        local kept={};for _,stop in ipairs(order) do if not gone[stop] then kept[#kept+1]=stop end end
        order=kept
        if coroutine.running() then coroutine.yield() end
    end
    return order,removed
end
function P.Tour(stops,loop,start)
    local left,order={},{}
    for i,stop in ipairs(stops) do left[i]=stop end
    local current=start or stops[1]
    while #left>0 do
        local best,bestDistance=1,math.huge
        for i,stop in ipairs(left) do local d=yards(current,stop);if d<bestDistance then best,bestDistance=i,d end end
        current=table.remove(left,best);order[#order+1]=current
    end
    local n=#order
    if n<4 then return order end
    local improved,passes=true,0
    while improved and passes<30 do
        improved,passes=false,passes+1
        -- 2-opt: reverse order[i+1..j] when the two new edges are shorter.
        for i=1,n-2 do
            for j=i+2,n do
                local a,b,c,d=order[i],order[i+1],order[j],successor(order,j,loop)
                if d~=a then
                    local before=yards(a,b)+(d and yards(c,d) or 0)
                    local after=yards(a,c)+(d and yards(b,d) or 0)
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
                    local gain=yards(prev,order[first])+yards(order[last],nxt)-yards(prev,nxt)
                    for j=1,n do
                        local a,b=order[j],successor(order,j,loop)
                        if b and (j<first-1 or j>last) and b~=order[first] then
                            local cost=yards(a,order[first])+yards(order[last],b)-yards(a,b)
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
    local stops=P.Cluster(nodes,sight and (options.sight or 150) or options.radius or 30)
    local open,skipped={},0
    for _,stop in ipairs(stops) do
        stop.x,stop.y=stop.X/s.width,stop.Y/s.height
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
    local order=P.Tour(open,options.loop,start)
    local removed
    order,removed=P.Prune(order,options.loop,start,options.worth)
    local unworth=0;for _,stop in ipairs(removed) do unworth=unworth+#stop.nodes end
    local result={points={},length=0,stops=#order,nodes=#nodes,skipped=skipped,enemy=enemy,unworth=unworth,unworthStops=#removed,worth=options.worth,detours=0,unreachable=0,zones=zones,loop=options.loop,goal=sight and "sight" or "visit"}
    local function add(x,y,stop)
        local mapID,zx,zy=Grid.FromSpace(s,x,y)
        result.points[#result.points+1]={mapID=mapID,x=zx,y=zy,stop=stop and true or nil,count=stop and #stop.nodes or nil}
    end
    for i,stop in ipairs(order) do
        add(stop.x,stop.y,stop)
        local nxt=successor(order,i,options.loop)
        if nxt and #order>1 then
            local legs={{stop.x,stop.y},{nxt.x,nxt.y}}
            if not Grid.Clear(s,stop.x,stop.y,nxt.x,nxt.y) then
                local path=Grid.Search(s,stop.x,stop.y,nxt.x,nxt.y)
                if path and options.smooth then path=P.Smooth(s,path) end
                if path then
                    legs=path
                    if #path>2 then result.detours=result.detours+1 end
                    for k=2,#path-1 do add(path[k][1],path[k][2]) end
                else result.unreachable=result.unreachable+1 end
            end
            for k=2,#legs do result.length=result.length+Grid.Yards(s,legs[k-1][1],legs[k-1][2],legs[k][1],legs[k][2]) end
        end
    end
    return result
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
    for i,zone in ipairs(route.zones or {}) do copy.zones[i]=zone end
    for key,on in pairs(route.chosen or {}) do if on then copy.chosen[key]=true end end
    for i,point in ipairs(route.points) do copy.points[i]={mapID=point.mapID,x=point.x,y=point.y,stop=point.stop,count=point.count} end
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

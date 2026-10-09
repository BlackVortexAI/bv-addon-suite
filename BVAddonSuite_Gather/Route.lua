local _,G=...
if not G.ready then return end
-- Gathering route (plan phase 5): through the nodes of your current zone
-- that the filters show, starting with the one nearest to you, nearest
-- neighbour first, then 2-opt until no two legs cross. The route becomes
-- your waypoint path in the Map package (pins, lines, arrow, next one on
-- arrival) and is kept as a set; without the Map package there is no route.
local ns=G.ns
local R={}
G.Route=R
local MAX=200

-- Nodes of a map as {x, y (yards), node, kind}, filtered like the pins.
function R:Nodes(mapID)
    local width,height=G.Call("C_Map.GetMapWorldSize",mapID)
    if type(width)~="number" or width<=0 then width,height=1000,1000 end
    local out={}
    for _,point in ipairs(G.Pins:Points(mapID,false)) do
        -- Underground nodes need a cave entrance (a transition, later); until
        -- then routes leave them out unless the setting takes them.
        if not point.node.under or G:Config().routeUnderground then
            out[#out+1]={x=point.x*width,y=point.y*height,point=point}
        end
        if #out>=MAX then break end
    end
    return out,width,height
end
local function distance(a,b) local dx,dy=a.x-b.x,a.y-b.y;return math.sqrt(dx*dx+dy*dy) end
-- Order: nearest neighbour from the start, then 2-opt (reverse a stretch
-- whenever that shortens the path).
function R.Order(nodes,start)
    local left,order={},{}
    for i,node in ipairs(nodes) do left[i]=node end
    local current=start or nodes[1]
    while #left>0 do
        local best,bestDistance=1,math.huge
        for i,node in ipairs(left) do local d=distance(current,node);if d<bestDistance then best,bestDistance=i,d end end
        current=table.remove(left,best);order[#order+1]=current
    end
    local improved,passes=true,0
    while improved and passes<20 do
        improved,passes=false,passes+1
        for i=1,#order-2 do
            for j=i+2,#order do
                local a,b,c,d=order[i],order[i+1],order[j],order[j+1]
                local before=distance(a,b)+(d and distance(c,d) or 0)
                local after=distance(a,c)+(d and distance(b,d) or 0)
                if after+1e-9<before then
                    local lo,hi=i+1,j
                    while lo<hi do order[lo],order[hi]=order[hi],order[lo];lo,hi=lo+1,hi-1 end
                    improved=true
                end
            end
        end
    end
    return order
end
function R.Length(order)
    local total=0
    for i=2,#order do total=total+distance(order[i-1],order[i]) end
    return total
end
-- Builds the route of the zone you are in and hands it to the Map package.
function R:Start()
    local waypoints=ns.Map and ns.Map.Active and ns.Map:Active() and ns.Map.Waypoints
    if not waypoints then G:Print("Routes need BV Addon Suite - Map (on).");return false end
    if waypoints:TomTom() then G:Print("TomTom keeps the waypoints: routes need the Map package's own waypoints.");return false end
    local mapID,x,y=G.Record:Position()
    if not mapID then G:Print("No position here (instances hide it).");return false end
    local nodes,width,height=self:Nodes(mapID)
    if #nodes<2 then G:Print("Fewer than two nodes in this zone with the current filters.");return false end
    local order=R.Order(nodes,{x=x*width,y=y*height})
    local set={}
    for _,entry in ipairs(order) do
        local p=entry.point
        set[#set+1]={mapID=mapID,x=p.x,y=p.y,title=p.node.name or G.TYPE[p.kind].label}
    end
    local zone=G.Call("C_Map.GetMapInfo",mapID)
    local name="Route: "..(type(zone)=="table" and zone.name or ("Map "..mapID))
    ns.Map:Config().sets[name]=set
    waypoints:LoadSet(name)
    G:Print(string.format("%s: %d nodes, %d yards.",name,#set,math.floor(R.Length(order)+.5)))
    return true
end

local _,G=...
if not G.ready then return end
-- Nodes on the world map and the minimap through Core's pin layer; only the
-- nodes of the map shown (pointsFor), filtered by kind and name. Click: a
-- waypoint (with the Map package); Shift+right-click: forget the node.
local ns=G.ns
local N={}
G.Pins=N

-- "Peacebloom, Silverleaf" -> {peacebloom=true, silverleaf=true}; empty = all.
function N:Filter()
    local text=G:Config().filter
    if text==self.filterText then return self.filterSet end
    self.filterText=text
    local set
    for word in text:gmatch("[^,]+") do
        word=word:gsub("^%s+",""):gsub("%s+$",""):lower()
        if word~="" then set=set or {};set[word]=true end
    end
    self.filterSet=set
    return set
end
-- A spawn point matches the name filter when any plant seen there does.
function N.Matches(node,filter)
    if node.name and filter[node.name:lower()] then return true end
    for name in pairs(node.names or {}) do if filter[name:lower()] then return true end end
    return false
end
N.EARTH={.24,.16,.08}
-- The pins of a map are worked out once and kept until the nodes or the
-- settings change (the minimap asks often; Florian 2026-10-09: high CPU).
N.cache={}
N.revision=0
function N:Changed() self.revision=self.revision+1;self.cache={} end
function N:Points(mapID,minimap)
    local inside=minimap and G.Call("IsIndoors")==true
    local key=tostring(mapID)..(minimap and (inside and ":mi" or ":mo") or ":w")
    local lists={}
    for _,t in ipairs(G.TYPES) do lists[#lists+1]=G.Data:Nodes(t.id,mapID) or false end
    local cached=self.cache[key]
    if cached and cached.revision==self.revision and cached.dataRevision==G.Data.revision and cached.showing==G:Showing() then
        local same=true
        for i,list in ipairs(lists) do if cached.lists[i]~=list or cached.counts[i]~=(list and #list or 0) then same=false end end
        if same then return cached.points end
    end
    local points=self:Build(mapID,minimap,inside)
    local counts={};for i,list in ipairs(lists) do counts[i]=list and #list or 0 end
    self.cache[key]={points=points,lists=lists,counts=counts,revision=self.revision,dataRevision=G.Data.revision,showing=G:Showing()}
    return points
end
function N:Build(mapID,minimap,inside)
    local out={}
    if not G:Showing() or type(mapID)~="number" then return out end
    local c=G:Config()
    if minimap and not c.minimap then return out end
    if not minimap and not c.world then return out end
    local filter=self:Filter()
    for _,t in ipairs(G.TYPES) do
        if c[t.id] then
            for _,node in ipairs(G.Data:Nodes(t.id,mapID) or {}) do
                if not filter or N.Matches(node,filter) then
                    -- Known spawn points nobody has seen yet: smaller and fainter.
                    local sources=G.Data:Sources(t.id,mapID,node)
                    local unseen=not sources.own and sources.known and not (sources.gathermate or sources.text or sources.import or sources.shared)
                    out[#out+1]={mapID=mapID,x=node.x,y=node.y,symbol=t.symbol,color=G:Color(t.id),size=unseen and math.max(8,c.size-4) or c.size,
                        kind=t.id,node=node,alpha=unseen and .55 or nil,
                        disc=node.under and N.EARTH or nil,dim=minimap and ((node.under==true)~=inside) or nil}
                end
            end
        end
    end
    return out
end
function N:Register()
    if self.registered or not ns.MapPins then return end
    self.registered=true
    ns.MapPins:Register("gather:world",{pointsFor=function(mapID) return N:Points(mapID,false) end,
        onClick=function(point,button) N:Click(point,button) end,tooltip=function(point) return N:Tooltip(point) end})
    ns.MapPins:Register("gather:minimap",{pointsFor=function(mapID) return N:Points(mapID,true) end,minimap=true,world=false,
        edge=G:Config().minimapEdge,tooltip=function(point) return N:Tooltip(point) end})
end
-- Two providers so world map and minimap switch separately; the minimap one
-- is minimap only (world=false).
function N:Tooltip(point)
    local node,t=point.node,G.TYPE[point.kind]
    local rows={}
    rows[#rows+1]={"Found",(node.count or 1)==1 and "once" or (node.count.." times")}
    if node.name and G.SKILL[node.name] then rows[#rows+1]={"Skill",tostring(G.SKILL[node.name])} end
    -- Other plants seen at this spawn point.
    local others={}
    for name in pairs(node.names or {}) do if name~=node.name then others[#others+1]=name end end
    table.sort(others)
    if #others>0 then rows[#rows+1]={"Also here",table.concat(others,", ")} end
    if node.under then rows[#rows+1]={"Underground",node.place or "a cave"} end
    if node.last then rows[#rows+1]={"Last seen",date("%Y-%m-%d",node.last)} end
    -- Where it comes from: your own finds first, then the others.
    local sources=G.Data:Sources(point.kind,point.mapID,node)
    local names={}
    if sources.own then names[1]=G.Data.LABEL.own end
    for _,source in ipairs(G.Data.ORDER) do if sources[source] then names[#names+1]=G.Data.LABEL[source] end end
    rows[#rows+1]={"Source",table.concat(names,", ")}
    if not sources.own and sources.known and (node.count or 0)==0 then rows[1]={"Found","not yet (a known spawn point)"} end
    return node.name or t.label,{tag=t.label,tagColor=G:Color(point.kind),rows=rows,hint="Click: waypoint · Shift+right-click: forget"}
end
function N:Click(point,button)
    if button=="RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
        if G.Data:Remove(point.kind,point.mapID,point.node) then G:Print("Forgot "..(point.node.name or "the node")..".");self:Refresh() end
        return
    end
    local waypoints=ns.Map and ns.Map.Active and ns.Map:Active() and ns.Map.Waypoints
    if waypoints then waypoints:Add({mapID=point.mapID,x=point.x,y=point.y,title=point.node.name},false,true)
    else G:Print("Waypoints come with BV Addon Suite - Map.") end
end
function N:Refresh() self:Changed();if ns.MapPins then ns.MapPins:Refresh() end end
function N:Enable(context)
    self:Register()
    self:Refresh()
end

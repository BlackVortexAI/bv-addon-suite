local _,P=...
if not P.ready then return end
-- Travel path (Florian 2026-10-08, plan phase 2b): every queued waypoint as
-- a numbered pin on the world map and the minimap (Core's pin layer), lines
-- between them in queue order. Alt+click on the map appends a point; on a
-- pin, left-click makes it the next target, right-click removes it, dragging
-- moves it. With TomTom loaded the waypoints are TomTom's and so are its
-- pins: ours stay away.
local ns=P.ns
local T={}
P.Path=T
-- The next target green; the rest of the path and its lines in the style's
-- accent (yellow vanished on the map's parchment, Florian 2026-10-08). Both
-- can be set in the settings.
local function rgb(hex)
    local r,g,b=P.ns.UI:RGBA(hex:sub(1,6).."FF")
    return {r,g,b}
end

function T:Wanted() return P:Active() and P:Config().pathPins and not P.Waypoints:TomTom() end
function T:Points()
    if not self:Wanted() then return {} end
    local out={}
    local c=P:Config()
    local QUEUED
    if c.pathColor~="" then QUEUED=rgb(c.pathColor) else local r,g,b=P:Style():Color("accent");QUEUED={r,g,b} end
    local ACTIVE=rgb(c.nextColor)
    local queue=P.Waypoints:Queue()
    for index,point in ipairs(queue) do
        -- The first one: the leg from you to it in the next target's colour.
        out[#out+1]={mapID=point.mapID,x=point.x,y=point.y,index=index,label=tostring(index),
            symbol=point.corpse and "skull" or "map-pin",color=index==1 and ACTIVE or QUEUED,lineColor=QUEUED,size=index==1 and 22 or 18,
            lead=index==1 and c.pathLead or nil,leadColor=ACTIVE,alpha=c.pathPinAlpha/100,lineAlpha=c.pathLineAlpha/95}
    end
    -- A loop (route editor): the last point leads back to the first.
    local first=queue[1]
    if first and first.loop and #queue>2 then
        out[#out+1]={mapID=first.mapID,x=first.x,y=first.y,index=1,noPin=true,lineColor=QUEUED,lineAlpha=c.pathLineAlpha/95}
    end
    return out
end
function T:Register()
    if not ns.MapPins or self.registered then return end
    self.registered=true
    ns.MapPins:Register("map:path",{
        points=function() return T:Points() end,
        lines=true,minimap=true,arrows=true,
        onClick=function(point,button)
            if button=="RightButton" then P.Waypoints:Remove(point.index) else P.Waypoints:Choose(point.index) end
        end,
        onDrag=function(point,mapID,x,y) P.Waypoints:Place(point.index,mapID,x,y) end,
        tooltip=function(point)
            local entry=P.Waypoints:Queue()[point.index]
            if not entry then return nil end
            return P.Waypoints:Label(entry),{tag=point.index==1 and "Next" or ("#"..point.index),tagColor=point.color,
                rows={{"Where",P.Waypoints:MapName(entry.mapID).."  "..P:Format(entry.x,entry.y)}},
                hint=(point.index==1 and "" or "Click: go here next · ").."Right-click: remove · Drag: move"}
        end})
end
function T:Refresh() if ns.MapPins then ns.MapPins:Refresh() end end

-- Alt+click on the map appends a waypoint where you clicked.
function T:MapClick(button)
    if button~="LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) then return end
    if not (P:Active() and P:Config().altClick) then return end
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    if not (scroll and scroll.GetNormalizedCursorPosition and map.GetMapID) then return end
    local ok,x,y=pcall(scroll.GetNormalizedCursorPosition,scroll)
    if not ok or type(x)~="number" or x<0 or x>1 or y<0 or y>1 then return end
    P.Waypoints:Add({mapID=map:GetMapID(),x=x,y=y},true)
end
function T:Enable(context)
    self:Register()
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    if scroll and not self.hooked then
        self.hooked=true
        scroll:HookScript("OnMouseUp",function(_,button) T:MapClick(button) end)
    end
    context:Defer(function() T:Refresh() end)
    self:Refresh()
end

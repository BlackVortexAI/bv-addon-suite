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

-- BV Routing loaded and ready to plan (Map does not need it).
function T:Routing()
    local R=ns.Routing
    return R and R.ready and R.Navigate and R.Navigate.Start and R.OnContinent and R or nil
end
-- Where on the map the cursor is: map ID, x, y (0..1), or nil.
local function cursor()
    local map=P:WorldMap()
    local scroll=map and map.ScrollContainer
    if not (scroll and scroll.GetNormalizedCursorPosition and map.GetMapID) then return nil end
    local ok,x,y=pcall(scroll.GetNormalizedCursorPosition,scroll)
    if not ok or type(x)~="number" or x<0 or x>1 or y<0 or y>1 then return nil end
    return map:GetMapID(),x,y
end
-- Ctrl+Shift+click: Routing's way to the point (Florian 2026-10-16: every
-- point of the map reachable by Routing); Alt+click appends a waypoint.
function T:MapClick(button)
    if button~="LeftButton" or not P:Active() then return end
    local c=P:Config()
    if IsControlKeyDown and IsControlKeyDown() and IsShiftKeyDown and IsShiftKeyDown() then
        if not c.routeClick then return end
        local R=self:Routing()
        if not R then return end
        local mapID,x,y=cursor()
        if not mapID then return end
        return self:RouteTo(R,mapID,x,y)
    end
    if not (IsAltKeyDown and IsAltKeyDown()) or not c.altClick then return end
    local mapID,x,y=cursor()
    if not mapID then return end
    P.Waypoints:Add({mapID=mapID,x=x,y=y},true)
end
function T:RouteTo(R,mapID,x,y)
    local cont,cx,cy=R:OnContinent(mapID,x,y)
    if not cont then P:Print("Routing cannot reach that point (no continent map).");return false end
    local name=P.Waypoints:MapName(mapID).." "..P:Format(x,y)
    R.Navigate:Start({cont=cont,x=cx,y=cy,name=name,label="map point"})
    -- Blizzard sets its own waypoint on Ctrl+click, Shift held or not
    -- (Florian 2026-10-16): the one at this very point is taken away again,
    -- now and a moment later (it may come after this click).
    local function drop()
        local current=P.Call("C_Map.GetUserWaypoint")
        local position=type(current)=="table" and current.position
        local px,py
        if type(position)=="table" and position.GetXY then px,py=position:GetXY() elseif type(position)=="table" then px,py=position.x,position.y end
        if current and current.uiMapID==mapID and type(px)=="number" and math.abs(px-x)<.002 and math.abs(py-y)<.002 then
            P.Waypoints.setting=true;P.Call("C_Map.ClearUserWaypoint");P.Waypoints.setting=false
        end
    end
    drop()
    if C_Timer and C_Timer.NewTimer then C_Timer.NewTimer(.3,drop) end
    return true
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

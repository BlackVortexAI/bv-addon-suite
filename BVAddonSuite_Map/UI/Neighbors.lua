local _,P=...
if not P.ready then return end
-- Small arrows at the map's edges to the zone next to this one (Florian
-- 2026-10-16: some zones show no neighbour to click into). The zone's
-- rectangle on its continent, and just outside each edge, at three places,
-- the zone the continent has there; the one found most often wins.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local N={}
P.Neighbors=N
N.OUTSIDE=.012       -- continent units beyond the edge asked
N.ALONG={.3,.5,.7}   -- places along each edge
N.DIRS={
    {key="left",icon="arrow-left",point="LEFT",x=12,y=0},
    {key="right",icon="arrow-right",point="RIGHT",x=-12,y=0},
    {key="up",icon="arrow-up",point="TOP",x=0,y=-12},
    -- Above a coordinate bar at the bottom centre (other addons put one there).
    {key="down",icon="arrow-down",point="BOTTOM",x=0,y=36},
}
N.cache={}

-- The zone (map type 3) a map point lies in, climbing from a city or part.
local function zoneOf(info)
    local guard=0
    while type(info)=="table" and info.mapType and info.mapType>3 and info.parentMapID and guard<4 do
        info=P.Call("C_Map.GetMapInfo",info.parentMapID);guard=guard+1
    end
    return type(info)=="table" and info.mapType==3 and info.mapID or nil,type(info)=="table" and info.name or nil
end
-- The continent a zone lies on, or nil.
local function continentOf(mapID)
    local info=P.Call("C_Map.GetMapInfo",mapID)
    local guard=0
    while type(info)=="table" and info.mapType and info.mapType>2 and info.parentMapID and guard<5 do
        info=P.Call("C_Map.GetMapInfo",info.parentMapID);guard=guard+1
    end
    return type(info)=="table" and info.mapType==2 and info.mapID or nil
end
-- The neighbour in each direction: {left={mapID=,name=},...} (cached per map).
function N:Find(mapID)
    if self.cache[mapID]~=nil then return self.cache[mapID] end
    local found={}
    local info=P.Call("C_Map.GetMapInfo",mapID)
    local cont=type(info)=="table" and info.mapType==3 and continentOf(mapID)
    local left,right,top,bottom
    if cont then left,right,top,bottom=P.Call("C_Map.GetMapRectOnMap",mapID,cont) end
    if type(left)=="number" and type(right)=="number" and type(top)=="number" and type(bottom)=="number" then
        local o=self.OUTSIDE
        for _,dir in ipairs(self.DIRS) do
            local votes,names,best={}, {},nil
            for _,t in ipairs(self.ALONG) do
                local x,y
                if dir.key=="left" then x,y=left-o,top+(bottom-top)*t
                elseif dir.key=="right" then x,y=right+o,top+(bottom-top)*t
                elseif dir.key=="up" then x,y=left+(right-left)*t,top-o
                else x,y=left+(right-left)*t,bottom+o end
                if x>=0 and x<=1 and y>=0 and y<=1 then
                    local zone,name=zoneOf(P.Call("C_Map.GetMapInfoAtPosition",cont,x,y))
                    if zone and zone~=mapID then
                        votes[zone]=(votes[zone] or 0)+1;names[zone]=name
                        if not best or votes[zone]>votes[best] then best=zone end
                    end
                end
            end
            if best then found[dir.key]={mapID=best,name=names[best]} end
        end
    end
    self.cache[mapID]=found
    return found
end

function N:Build()
    local map=P:WorldMap()
    if self.frame or not map then return end
    local parent=map.ScrollContainer or map
    UI:WithStyle(P:Style(),function()
        local f=CreateFrame("Frame",nil,parent)
        f:SetAllPoints(parent);P:AbovePins(f,parent);f:EnableMouse(false)
        self.frame,self.buttons=f,{}
        for _,dir in ipairs(self.DIRS) do
            -- On the dark panel of the map's own buttons, not see-through (Florian
            -- 2026-10-20: on many maps the bare arrows were hard to make out).
            local b=UI:IconButton(f,dir.icon,function(button) N:Go(button.target) end)
            M.Size(b,28,28);M.Point(b,dir.point,f,dir.point,dir.x,dir.y)
            if b.icon then M.Size(b.icon,16,16) end
            UI:AttachTooltip(b,"To the next zone","Shows the zone next to this one in that direction.")
            self.buttons[dir.key]=b
        end
    end)
end
function N:Go(target)
    local map=P:WorldMap()
    if target and map and map.SetMapID then pcall(map.SetMapID,map,target.mapID) end
end
function N:Update()
    local map=P:WorldMap()
    local show=P:Active() and P:Config().neighbors and map and map:IsShown() and map.GetMapID
    if not show then if self.frame then self.frame:Hide() end;return end
    self:Build()
    local found=self:Find(map:GetMapID())
    for key,b in pairs(self.buttons) do
        b.target=found[key]
        b.tooltipTitle="To "..(found[key] and found[key].name or "the next zone")
        b:SetShown(found[key]~=nil)
    end
    P:AbovePins(self.frame)
    self.frame:Show()
end
function N:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() N:Update() end)
        if type(map.OnMapChanged)=="function" then hooksecurefunc(map,"OnMapChanged",function() N:Update() end) end
    end
    context:Defer(function() if N.frame then N.frame:Hide() end end)
    self:Update()
end

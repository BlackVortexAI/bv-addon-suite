local _,P=...
if not P.ready then return end
-- Own flight masters only (Florian 2026-10-08: show the flight masters of
-- your faction, not the other's). Blizzard's world map draws all of them as
-- pins; after it acquires them, ours hides those of the other faction
-- (their taxi node data says Horde or Alliance; neutral ones stay). The
-- map search leaves them out too.
local ns=P.ns
local F={}
P.Flights=F
F.TEMPLATES={"FlightPointPinTemplate","FlightMap_FlightPointPinTemplate"}

function F:On() return P:Active() and P:Config().ownFlights end
function F.Hostile(node)
    return type(node)=="table" and ns.MapOverlays and ns.MapOverlays.HostileNode(node.faction) or false
end
function F:Filter()
    self.pending=nil
    local map=P:WorldMap()
    if not (map and map.EnumeratePinsByTemplate) then return 0 end
    local hidden=0
    for _,template in ipairs(self.TEMPLATES) do
        local ok,iterator=pcall(map.EnumeratePinsByTemplate,map,template)
        if ok and iterator then
            for pin in iterator do
                local node=pin.taxiNodeData or pin.nodeData
                if self:On() and self.Hostile(node) then pin:Hide();hidden=hidden+1 end
            end
        end
    end
    return hidden
end
-- Pins come and go with every refresh: filter a moment after.
function F:Later()
    if self.pending then return end
    self.pending=C_Timer.NewTimer(0,function() F:Filter() end)
end
function F:Enable(context)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        if type(map.AcquirePin)=="function" then
            hooksecurefunc(map,"AcquirePin",function(_,template) for _,t in ipairs(F.TEMPLATES) do if t==template then F:Later() end end end)
        end
        if type(map.OnMapChanged)=="function" then hooksecurefunc(map,"OnMapChanged",function() F:Later() end) end
    end
    context:Defer(function() if F.pending then F.pending:Cancel();F.pending=nil end end)
    self:Filter()
end

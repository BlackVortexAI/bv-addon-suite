local _,G=...
if not G.ready then return end
-- Walked ways (Florian 2026-10-08: routes later from a heatmap of where
-- players really walk). Every two seconds while you move on foot or
-- mounted (not on a flight path, not flying, not in an instance) your
-- position goes into a grid of the world: per ADT tile 64 x 64 cells of
-- 8 1/3 yards (the terrain data's cells), counted, account-wide in
-- BVGatherDB.heat[instance][col * 100 + row][cell]. Cells walked often are
-- cheaper for route planning ("Prefer walked ways"); the route editor can
-- show them.
local ns=G.ns
local H={frames={}}
G.Trace=H
H.EVERY=2
H.WALKED=3

function H:Store()
    local db=G.Data.db or G.Data:Init()
    if type(db.heat)~="table" then db.heat={} end
    return db.heat
end
-- World position of a map point (X north, Y west) through Core's terrain frame.
function H:World(mapID,x,y)
    local frame=self.frames[mapID]
    if frame==nil then frame=ns.MapTerrain and ns.MapTerrain:Frame(mapID) or false;self.frames[mapID]=frame end
    if not frame then return nil end
    return frame.instance,frame.a[frame.iy]+y*frame.dy,frame.a[frame.ix]+x*frame.dx
end
function H.Cell(X,Y)
    local fc,fr=32-Y/ns.MapTerrain.ADT,32-X/ns.MapTerrain.ADT
    local col,row=math.floor(fc),math.floor(fr)
    if col<0 or col>63 or row<0 or row>63 then return nil end
    return col*100+row,math.floor((fr-row)*64)*64+math.floor((fc-col)*64)
end
function H:Add(instance,X,Y)
    local tile,cell=H.Cell(X,Y)
    if not tile then return false end
    local heat=self:Store()
    heat[instance]=heat[instance] or {}
    local cells=heat[instance][tile] or {}
    heat[instance][tile]=cells
    -- The same cell twice in a row counts once (standing about is no way).
    if self.last==instance*1000000+tile*10000+cell then return false end
    self.last=instance*1000000+tile*10000+cell
    cells[cell]=(cells[cell] or 0)+1
    return true
end
function H:Count(instance,X,Y)
    local tile,cell=H.Cell(X,Y)
    local heat=tile and self:Store()[instance]
    local cells=heat and heat[tile]
    return cells and cells[cell] or 0
end
function H:Sample()
    if not (G:Active() and G:Config().recordWays) then return false end
    if G.Call("IsPlayerMoving")~=true or G.Call("UnitOnTaxi","player")==true or G.Call("IsFlying")==true then return false end
    local inInstance=G.Call("IsInInstance")
    if inInstance==true then return false end
    local mapID,x,y=G.Record:Position()
    if not mapID then return false end
    local instance,X,Y=self:World(mapID,x,y)
    if not instance then return false end
    return self:Add(instance,X,Y)
end
function H:Forget() self:Store();G.Data.db.heat={} end
function H:Enable(context)
    self.ticker=C_Timer.NewTicker(H.EVERY,function() H:Sample() end)
    context:Defer(function() if H.ticker then H.ticker:Cancel();H.ticker=nil end end)
end

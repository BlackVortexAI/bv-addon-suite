local _,P=...
if not P.ready then return end
-- Direction and distance to a waypoint for our arrow. The target is moved
-- onto the player's map (world position in between), so the angle comes
-- from map coordinates only: x grows to the east, y to the south. Yards from
-- the map's world size. Facing: 0 is north, growing counter-clockwise.
local N={}
P.Navigation=N

-- Target on the player's current map: x, y (0..1 may be exceeded), mapID.
function N:OnPlayerMap(point,playerMap)
    if point.mapID==playerMap then return point.x,point.y end
    -- Core's pin layer converts between maps (world position, else the
    -- maps' rectangles on their continent).
    if P.ns.MapPins then return P.ns.MapPins:OnMap(point,playerMap) end
    return nil
end
-- Angle (radians, counter-clockwise from straight ahead) and yards; nil
-- inside instances or on another continent.
function N:Vector(point)
    local px,py,playerMap=P:PlayerPosition()
    if not px then return nil end
    local tx,ty=self:OnPlayerMap(point,playerMap)
    if not tx then return nil end
    local width,height=P.Call("C_Map.GetMapWorldSize",playerMap)
    if type(width)~="number" or width<=0 then return nil end
    local east,south=(tx-px)*width,(ty-py)*height
    local distance=math.sqrt(east*east+south*south)
    -- Bearing counter-clockwise from north: north is -south, west is -east.
    local bearing=math.atan2(-east,-south)
    local facing=P.Call("GetPlayerFacing")
    if type(facing)~="number" or P.Secret(facing) then return nil,distance end
    local angle=(bearing-facing)%(2*math.pi)
    return angle,distance
end
-- Arrival time from the recent approach speed (smoothed), seconds or nil.
function N:ETA(distance)
    local now=GetTime()
    if self.lastDistance and self.lastTime and now>self.lastTime then
        local speed=(self.lastDistance-distance)/(now-self.lastTime)
        self.speed=self.speed and (self.speed*.8+speed*.2) or speed
    end
    self.lastDistance,self.lastTime=distance,now
    if self.speed and self.speed>.5 then return distance/self.speed end
    return nil
end
function N:Reset() self.lastDistance,self.lastTime,self.speed=nil,nil,nil end
function N.Clock(seconds)
    seconds=math.floor(seconds+.5)
    if seconds>=3600 then return string.format("%d:%02d:%02d",math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60) end
    return string.format("%d:%02d",math.floor(seconds/60),seconds%60)
end

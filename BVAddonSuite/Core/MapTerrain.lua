local _,ns=...
-- Terrain map (Florian 2026-10-08): the client's own minimap tiles, one per
-- ADT tile of 533 1/3 yards (Core's MinimapTileData), placed by their world
-- corners on any map. Shared by Gather's route editor and the Map module.
local T={ADT=1600/3}
ns.MapTerrain=T

local function call(path,...)
    local f=_G
    for part in path:gmatch("[^%.]+") do if type(f)~="table" then return nil end;f=f[part] end
    if type(f)~="function" then return nil end
    local result={pcall(f,...)}
    if not result[1] then return nil end
    return unpack(result,2)
end
-- The line between a map and the world: the map's corners in the world.
-- The vector part that changes along the map's x is world Y (west), the
-- one along its y is world X (north).
function T:Frame(mapID)
    local vector=rawget(_G,"CreateVector2D")
    if not vector or type(mapID)~="number" then return nil end
    local function corner(x,y)
        local instance,world=call("C_Map.GetWorldPosFromMapPos",mapID,vector(x,y))
        if not (instance and type(world)=="table" and world.GetXY) then return nil end
        return instance,{world:GetXY()}
    end
    local instance,a=corner(0,0)
    local _,b=corner(1,0)
    local _,c=corner(0,1)
    if not (a and b and c) then return nil end
    local ix=math.abs(b[1]-a[1])>math.abs(b[2]-a[2]) and 1 or 2
    local iy=3-ix
    if b[ix]==a[ix] or c[iy]==a[iy] then return nil end
    return {instance=instance,a=a,ix=ix,iy=iy,dx=b[ix]-a[ix],dy=c[iy]-a[iy]}
end
-- Tile files of an instance: a function (col, row) -> texture, and the
-- source's name. (Local renders of the prototype BVAddonSuite_MapArt were
-- dropped on 2026-10-09: the client's tiles cover everything.)
function T:Source(instance)
    local client=ns.MinimapTileData and ns.MinimapTileData[instance]
    if not client then return nil end
    return function(col,row) return client.tiles[col*100+row] end,"client"
end
-- Sets a tile's texture; false (and remembered) when the client lacks the
-- file: the file list knows tiles WoW Forever does not ship, which would
-- show as green placeholders (Florian 2026-10-08).
T.missing={}
function T:Load(texture,file)
    if self.missing[file] then return false end
    local ok,loaded=pcall(texture.SetTexture,texture,file)
    if not ok or loaded==false then self.missing[file]=true;texture:SetTexture(nil);texture:Hide();return false end
    return true
end
-- A tile's rectangle on the frame's map (0..1, x0 < x1, y0 < y1).
function T.Rect(frame,col,row)
    local wy,wx=(32-col)*T.ADT,(32-row)*T.ADT
    local x0=(wy-frame.a[frame.ix])/frame.dx
    local y0=(wx-frame.a[frame.iy])/frame.dy
    local x1=(wy-T.ADT-frame.a[frame.ix])/frame.dx
    local y1=(wx-T.ADT-frame.a[frame.iy])/frame.dy
    return math.min(x0,x1),math.min(y0,y1),math.max(x0,x1),math.max(y0,y1)
end
-- Tiles under a rectangle of the map (half-open: ending on a tile edge
-- leaves the next tile out): c0, c1, r0, r1.
function T.Range(frame,x0,y0,x1,y1)
    local function col(x) return 32-(frame.a[frame.ix]+x*frame.dx)/T.ADT end
    local function row(y) return 32-(frame.a[frame.iy]+y*frame.dy)/T.ADT end
    return math.max(0,math.floor(math.min(col(x0),col(x1)))),math.min(63,math.ceil(math.max(col(x0),col(x1)))-1),
        math.max(0,math.floor(math.min(row(y0),row(y1)))),math.min(63,math.ceil(math.max(row(y0),row(y1)))-1)
end

-- Terrain data (slopes, water, holes) from the client's terrain files
-- (tools/build_terrain_data.py, local data addon BVAddonSuite_Terrain):
-- per ADT tile 64 x 64 cells of 8 1/3 yards, rows north to south, columns
-- west to east. A code is slope class (0..3) + 4 * water (0 none,
-- 1 shallow, 2 swimming, 3 magma or slime) + 16 * hole + 32 * road (a road
-- texture covers the cell). Tiles are decoded
-- when first asked for; the last DECODED stay.
local DECODED=64
T.decoded,T.order={},{}
function T:Data(instance)
    local data=rawget(_G,"BVTerrainData")
    return type(data)=="table" and type(data[instance])=="table" and data[instance] or nil
end
function T:Codes(instance,col,row)
    local key=instance*10000+col*100+row
    local codes=self.decoded[key]
    if codes~=nil then return codes end
    local data=self:Data(instance)
    local text=data and data.tiles and data.tiles[col*100+row]
    if type(text)~="string" then return false end
    local values={}
    for i=1,#data.codes do values[data.codes:sub(i,i)]=i-1 end
    codes={}
    local n,i=0,1
    while i<=#text do
        local char=text:sub(i,i)
        if char=="~" then
            local code=values[text:sub(i+1,i+1)] or 0
            local stop=text:find(".",i+2,true)
            local run=tonumber(text:sub(i+2,stop-1)) or 0
            for _=1,run do n=n+1;codes[n]=code end
            i=stop+1
        else n=n+1;codes[n]=values[char] or 0;i=i+1 end
    end
    self.decoded[key]=codes
    self.order[#self.order+1]=key
    if #self.order>DECODED then self.decoded[table.remove(self.order,1)]=nil end
    return codes
end
-- The code at a world position (X north, Y west), or nil without data.
function T:Code(instance,X,Y)
    local fc,fr=32-Y/T.ADT,32-X/T.ADT
    local col,row=math.floor(fc),math.floor(fr)
    local codes=self:Codes(instance,col,row)
    if not codes then return nil end
    local cx,cy=math.floor((fc-col)*64),math.floor((fr-row)*64)
    return codes[cy*64+cx+1]
end

-- Heights for cliffs (down yes, up no): per tile heightCells x heightCells
-- whole yards (the first value, then one delta character each, "!d;" for
-- big steps), decoded when first asked for; bilinear between cell middles.
T.heights,T.heightOrder={},{}
function T:Heights(instance,col,row)
    local key=instance*10000+col*100+row
    local grid=self.heights[key]
    if grid~=nil then return grid end
    local data=self:Data(instance)
    local text=data and data.heights and data.heights[col*100+row]
    if type(text)~="string" then return false end
    local delta={}
    for i=1,#data.delta do delta[data.delta:sub(i,i)]=i-32 end
    local colon=text:find(":",1,true)
    local value=tonumber(text:sub(1,colon-1)) or 0
    grid={value}
    local i=colon+1
    while i<=#text do
        local char=text:sub(i,i)
        if char=="!" then
            local stop=text:find(";",i+1,true)
            value=value+(tonumber(text:sub(i+1,stop-1)) or 0);i=stop+1
        else value=value+(delta[char] or 0);i=i+1 end
        grid[#grid+1]=value
    end
    self.heights[key]=grid
    self.heightOrder[#self.heightOrder+1]=key
    if #self.heightOrder>DECODED then self.heights[table.remove(self.heightOrder,1)]=nil end
    return grid
end
-- The ground height at a world position (X north, Y west), or nil.
function T:Height(instance,X,Y)
    local data=self:Data(instance)
    local n=data and data.heightCells or 32
    local fc,fr=32-Y/T.ADT,32-X/T.ADT
    local col,row=math.floor(fc),math.floor(fr)
    local grid=self:Heights(instance,col,row)
    if not grid then return nil end
    local gx=math.max(0,math.min(n-1,(fc-col)*n-.5))
    local gy=math.max(0,math.min(n-1,(fr-row)*n-.5))
    local x0,y0=math.floor(gx),math.floor(gy)
    local x1,y1=math.min(n-1,x0+1),math.min(n-1,y0+1)
    local tx,ty=gx-x0,gy-y0
    local function at(x,y) return grid[y*n+x+1] or 0 end
    return (at(x0,y0)*(1-tx)+at(x1,y0)*tx)*(1-ty)+(at(x0,y1)*(1-tx)+at(x1,y1)*tx)*ty
end

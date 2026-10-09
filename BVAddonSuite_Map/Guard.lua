local _,P=...
if not P.ready then return end
-- Coexistence (Florian 2026-10-08: never disturb existing systems). When
-- another addon already moves, scales or labels the world map, our part
-- stays out of it and the settings say so. Read from their saved settings:
-- Leatrix Maps (LeaMapsDB "On"/"Off") and the interface package's frame
-- mover and map coordinates (its name is never shown to the user).
local G={}
P.Guard=G

local function loaded(name)
    local result=P.Call("C_AddOns.IsAddOnLoaded",name)
    if result==nil then result=P.Call("IsAddOnLoaded",name) end
    return result==true or result==1
end
local function leatrix(key)
    local db=rawget(_G,"LeaMapsDB")
    return loaded("Leatrix_Maps") and type(db)=="table" and db[key]=="On"
end
local function package(fn)
    local db=rawget(_G,"EllesmereUIDB")
    if type(db)~="table" then return false end
    return fn(db)==true
end
-- Who handles a part of the map, or nil when it is free for us.
G.PARTS={
    move=function()
        if leatrix("UnlockMap") then return "Leatrix Maps" end
        if package(function(db) return db.shifterEnabled==true and type(db.shifterPositions)=="table" and db.shifterPositions.WorldMapFrame~=nil end) then return "your interface package" end
    end,
    scale=function()
        if leatrix("ScaleWorldMap") then return "Leatrix Maps" end
        if package(function(db) return db.shifterEnabled==true and type(db.shifterScales)=="table" and db.shifterScales.WorldMapFrame~=nil end) then return "your interface package" end
    end,
    reveal=function()
        if leatrix("RevealMap") then return "Leatrix Maps" end
    end,
    coords=function()
        if leatrix("ShowCoords") then return "Leatrix Maps" end
        if package(function(db) return db.mapCoords==true end) then return "your interface package" end
    end,
}
-- The other addon handling a part, whether or not ours is forced.
function G:Detected(part)
    local check=self.PARTS[part]
    if not check then return nil end
    local ok,owner=pcall(check)
    return ok and owner or nil
end
-- Ours stays out unless the user forces it ("Use ours anyway").
G.FORCE={move="forceMove",scale="forceScale",coords="forceCoords",reveal="forceReveal"}
function G:Forced(part) return P:Config()[self.FORCE[part]]==true end
function G:Owner(part)
    if self:Forced(part) then return nil end
    return self:Detected(part)
end

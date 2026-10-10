local _,G=...
if not G.ready then return end
-- Recording: a gathering cast names its node (UNIT_SPELLCAST_SENT carries
-- the target's name); when it succeeds, the node is stored where you stand
-- (you are within a few yards of it). Herbs, ore and treasure; fishing pools
-- give no name at the cast, so they come from imports for now. Not in
-- instances (no position there).
local R={}
G.Record=R
-- Gathering spells by spell ID (all ranks known to Classic) and, as a
-- fallback on other clients, by their name in the client's language.
local SPELLS={[2366]="herb",[2368]="herb",[3570]="herb",[11993]="herb",
    [2575]="ore",[2576]="ore",[3564]="ore",[10248]="ore",
    [3365]="treasure",[6247]="treasure",[6249]="treasure",[6477]="treasure",[6478]="treasure",[21651]="treasure"}
local NAMED={2366,2575,3365}
-- English names as a last resort: on WoW Forever 2366 and 2575 are called
-- "Herbalism" and "Mining" (probe 2026-10-08); "Herb Gathering" elsewhere.
local ENGLISH={["Herb Gathering"]="herb",Herbalism="herb",Mining="ore",Opening="treasure"}

function R:Kind(spellID)
    if type(spellID)~="number" or G.Secret(spellID) then return nil end
    local kind=SPELLS[spellID]
    if kind then return kind end
    -- Another rank or client: compare the spell's name with the known ones.
    local name=G.Call("C_Spell.GetSpellName",spellID) or G.Call("GetSpellInfo",spellID)
    if type(name)~="string" then return nil end
    self.names=self.names or {}
    if not self.namesBuilt then
        self.namesBuilt=true
        for _,id in ipairs(NAMED) do
            local known=G.Call("C_Spell.GetSpellName",id) or G.Call("GetSpellInfo",id)
            if type(known)=="string" then self.names[known]=SPELLS[id] end
        end
    end
    return self.names[name] or ENGLISH[name]
end
function R:Position()
    local mapID=G.Call("C_Map.GetBestMapForUnit","player")
    if type(mapID)~="number" or G.Secret(mapID) then return nil end
    local position=G.Call("C_Map.GetPlayerMapPosition",mapID,"player")
    if type(position)~="table" and type(position)~="userdata" then return nil end
    local ok,x,y=pcall(position.GetXY,position)
    if not ok or type(x)~="number" or G.Secret(x) or (x==0 and y==0) then return nil end
    return mapID,x,y
end
function R:Sent(unit,target,castGUID,spellID)
    if unit~="player" then return end
    -- For /bv map probe: the last cast's spell and whether it named a target.
    self.lastCast={spellID=spellID,target=type(target)=="string" and target~="" or nil,kind=self:Kind(spellID)}
    if not G:Recording() then return end
    local kind=self:Kind(spellID)
    if not kind or type(target)~="string" or target=="" or G.Secret(target) then self.pending=nil;return end
    local mapID,x,y=self:Position()
    if not mapID then self.pending=nil;return end
    -- Underground (Florian 2026-10-08): caves show only on the minimap, the
    -- world map keeps the zone map; indoors and the subzone tell them apart.
    local under=G.Call("IsIndoors")==true
    local place=G.Call("GetSubZoneText")
    if type(place)~="string" or place=="" or G.Secret(place) then place=nil end
    self.pending={kind=kind,name=target,guid=castGUID,mapID=mapID,x=x,y=y,under=under or nil,place=under and place or nil}
end
function R:Succeeded(unit,castGUID)
    local pending=self.pending
    if unit~="player" or not pending then return end
    if pending.guid and castGUID and not G.Secret(castGUID) and castGUID~=pending.guid then return end
    self.pending=nil
    local node,new=G.Data:Add(pending.kind,pending.mapID,pending.x,pending.y,pending.name,{under=pending.under,place=pending.place})
    if node then G.Pins:Refresh() end
    if node and new and G.Share then G.Share:Recorded(pending.kind,pending.mapID,node) end
    if G.Scanner then G.Scanner:Gathered(pending.name,pending.mapID,pending.x,pending.y) end
    return node,new
end
function R:Stopped(unit) if unit=="player" then self.pending=nil end end

function R:Enable(context)
    pcall(context.Subscribe,context,"UNIT_SPELLCAST_SENT",function(_,...) R:Sent(...) end)
    pcall(context.Subscribe,context,"UNIT_SPELLCAST_SUCCEEDED",function(_,unit,castGUID) R:Succeeded(unit,castGUID) end)
    for _,event in ipairs({"UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED"}) do
        pcall(context.Subscribe,context,event,function(_,unit) R:Stopped(unit) end)
    end
end

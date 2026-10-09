local _,P=...
if not P.ready then return end
-- Zone directory from the client's map tree (no static data): names for
-- "/way Badlands 45 67", the map search and imported waypoint lists. Built
-- once on first use; zones and cities first when two maps share a name.
local Z={}
P.Zones=Z
local ROOTS={946,947}        -- cosmic map, Azeroth (whichever the client has)
local RANK={[3]=1,[2]=2,[4]=3,[5]=4,[6]=5}   -- zone, continent, dungeon, micro, orphan

function Z:Build()
    if self.list then return self.list end
    local list,byName={},{}
    for _,root in ipairs(ROOTS) do
        local children=P.Call("C_Map.GetMapChildrenInfo",root,nil,true)
        if type(children)=="table" and #children>0 then
            for _,info in ipairs(children) do
                if type(info)=="table" and type(info.mapID)=="number" and type(info.name)=="string" and info.name~="" and not P.Secret(info.name) then
                    local rank=RANK[info.mapType] or 9
                    local entry={mapID=info.mapID,name=info.name,lower=info.name:lower(),rank=rank,parent=info.parentMapID}
                    local known=byName[entry.lower]
                    if not known or rank<known.rank then byName[entry.lower]=entry end
                    list[#list+1]=entry
                end
            end
            break
        end
    end
    table.sort(list,function(a,b) if a.rank~=b.rank then return a.rank<b.rank end return a.name<b.name end)
    -- An empty tree (asked too early) is not kept: the next call asks again.
    if #list>0 then self.list=list end
    self.byName=byName
    return list
end
-- Exact name (any case) to a map ID.
function Z:Find(name)
    if type(name)~="string" then return nil end
    self:Build()
    local entry=self.byName[name:lower():gsub("^%s+",""):gsub("%s+$","")]
    return entry and entry.mapID or nil
end
-- Names containing the text, best matches first (prefix before inside).
function Z:Search(text,limit)
    local out={}
    text=type(text)=="string" and text:lower() or ""
    if text=="" then return out end
    local seen={}
    for pass=1,2 do
        for _,entry in ipairs(self:Build()) do
            local at=entry.lower:find(text,1,true)
            if at and ((pass==1 and at==1) or (pass==2 and at>1)) and not seen[entry.lower] then
                seen[entry.lower]=true;out[#out+1]=entry
                if #out>=(limit or 8) then return out end
            end
        end
    end
    return out
end
function Z:Name(mapID)
    local info=P.Call("C_Map.GetMapInfo",mapID)
    return type(info)=="table" and type(info.name)=="string" and info.name or ("Map "..tostring(mapID))
end

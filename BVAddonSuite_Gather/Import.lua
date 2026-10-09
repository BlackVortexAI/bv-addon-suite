local _,G=...
if not G.ready then return end
-- Import and export (plan phase 4, Florian: other databases first, then
-- sharing). GatherMate2: its SavedVariables tables (GatherMate2HerbDB and
-- the others: [mapID][packed coordinate] = node ID) are read while it is
-- loaded; node IDs become names through its own tables. Shape taken from
-- GatherMate2's public source; to be confirmed with a real database.
-- Text exchange: "BVGATHER1" and one node per line "kind,mapID,coord,name",
-- for sharing through chat, forums or a friend.
local I={}
G.Import=I

local function gathermate()
    local addon=rawget(_G,"GatherMate2")
    if type(addon)=="table" then return addon end
    local libstub=rawget(_G,"LibStub")
    if type(libstub)=="table" or type(libstub)=="function" then
        local ok,ace=pcall(libstub,"AceAddon-3.0",true)
        if ok and type(ace)=="table" and ace.GetAddon then
            local found,result=pcall(ace.GetAddon,ace,"GatherMate2",true)
            if found and type(result)=="table" then return result end
        end
    end
    return nil
end
-- Node ID -> name for one of GatherMate2's kinds.
local function names(addon,gmType)
    local out={}
    if not addon then return out end
    local reverse=type(addon.reverseNodeIDs)=="table" and addon.reverseNodeIDs[gmType]
    if type(reverse)=="table" then for id,name in pairs(reverse) do out[id]=name end;return out end
    local forward=type(addon.nodeIDs)=="table" and addon.nodeIDs[gmType]
    if type(forward)=="table" then for name,id in pairs(forward) do out[id]=name end end
    return out
end
-- What GatherMate2 holds: per kind {total, new} without changing anything.
function I:GatherMate(apply)
    local addon=gathermate()
    local summary,any={},false
    for _,t in ipairs(G.TYPES) do
        local db=rawget(_G,t.db)
        local row={total=0,new=0}
        if type(db)=="table" then
            local byID=names(addon,t.gathermate)
            for mapID,coords in pairs(db) do
                if type(mapID)=="number" and type(coords)=="table" then
                    for coord,nodeID in pairs(coords) do
                        local x,y=G.Data.Decode(coord)
                        if x and x>=0 and x<=1 and y>=0 and y<=1 then
                            row.total=row.total+1;any=true
                            local name=byID[nodeID]
                            if apply then
                                local _,new=G.Data:Add(t.id,mapID,x,y,name,{import=true,source="gathermate"})
                                if new then row.new=row.new+1 end
                            elseif not self:Known(t.id,mapID,x,y,name) then row.new=row.new+1 end
                        end
                    end
                end
            end
        end
        summary[t.id]=row
    end
    return any and summary or nil
end
-- Known already: the same rule as merging (G.Data.Same), so previews and imports agree.
function I:Known(kind,mapID,x,y,name)
    for _,node in ipairs(G.Data:Nodes(kind,mapID) or {}) do
        if G.Data.Same(mapID,node,x,y,name,false) then return true end
    end
    return false
end
function I.Describe(summary)
    local parts={}
    for _,t in ipairs(G.TYPES) do
        local row=summary[t.id]
        if row and row.total>0 then parts[#parts+1]=string.format("%s: %d (%d new)",t.label,row.total,row.new) end
    end
    return table.concat(parts,", ")
end

-- Text exchange.
local HEADER="BVGATHER1"
local function clean(name)
    if type(name)~="string" then return "" end
    return (name:gsub("[%c,;|]"," "))
end
function I:Export(kind,mapID)
    local lines={HEADER}
    for _,t in ipairs(G.TYPES) do
        if not kind or kind==t.id then
            for map in pairs(G.Data:Maps(t.id)) do
                if not mapID or map==mapID then
                    -- %.0f: packed coordinates exceed 32-bit integers (%d would overflow).
                    -- Known spawns nobody saw stay out: they come with the data package.
                    for _,node in ipairs(G.Data:Nodes(t.id,map) or {}) do
                        local sources=G.Data:Sources(t.id,map,node)
                        local seen=false;for source in pairs(sources) do if source~="known" then seen=true end end
                        if seen then lines[#lines+1]=string.format("%s,%d,%.0f,%s",t.id,map,G.Data.Encode(node.x,node.y),clean(node.name)) end
                    end
                end
            end
        end
    end
    return table.concat(lines,"\n"),#lines-1
end
-- Reads a text; apply=false only counts. Imported nodes are marked shared
-- until you find them yourself.
function I:Text(text,apply)
    if type(text)~="string" or not text:find(HEADER,1,true) then return nil end
    local summary={}
    for _,t in ipairs(G.TYPES) do summary[t.id]={total=0,new=0} end
    for line in text:gmatch("[^\r\n]+") do
        local kind,mapID,coord,name=line:match("^%s*(%a+),(%d+),(%d+),(.-)%s*$")
        mapID,coord=tonumber(mapID),tonumber(coord)
        if kind and G.TYPE[kind] and mapID and coord then
            local x,y=G.Data.Decode(coord)
            if x and x>=0 and x<=1 and y>=0 and y<=1 then
                if name=="" then name=nil end
                local row=summary[kind];row.total=row.total+1
                if apply then
                    local _,new=G.Data:Add(kind,mapID,x,y,name,{import=true,source="text"})
                    if new then row.new=row.new+1 end
                elseif not self:Known(kind,mapID,x,y,name) then row.new=row.new+1 end
            end
        end
    end
    return summary
end

-- Lucide symbols (ISC/MIT, Media/Symbols/LICENSE-lucide.txt): lookup of atlas
-- cells for UI icons and Symbol media. Data only; textures are created in UI.
local _,ns=...
local S={};ns.Symbols=S
-- Further symbol sets (BV Addon Suite - Media Pack, Florian 2026-10-09: the
-- rest of Lucide as its own package) come after Core's own: same data shape
-- as ns.SymbolData (names, atlases, columns, perPage).
S.packs={}
local index,list
local function sources()
    local out={}
    if ns.SymbolData then out[1]=ns.SymbolData end
    for _,pack in ipairs(S.packs) do out[#out+1]=pack end
    return out
end
local function build()
    if index then return index end
    index,list={},{}
    for _,data in ipairs(sources()) do
        for i,name in ipairs(data.names or {}) do
            if not index[name] then index[name]={data=data,i=i};list[#list+1]=name end
        end
    end
    return index
end
function S:AddPack(data)
    if type(data)~="table" or type(data.names)~="table" or type(data.atlases)~="table" then return false end
    for _,pack in ipairs(self.packs) do if pack==data then return true end end
    self.packs[#self.packs+1]=data
    index,list=nil,nil
    return true
end
function S:Valid(name) return type(name)=="string" and build()[name]~=nil end
-- Core's symbols, then those of the packs.
function S:List() build();return list end
-- The hand-picked set comes first in the list (pickers show it without a search).
function S:Curated() return ns.SymbolData and ns.SymbolData.curated or #self:List() end
-- Lucide name for a line-drawn UI icon name, or nil.
function S:UIName(name) return ns.SymbolData and ns.SymbolData.ui[name] end
-- Atlas page and texture coordinates; the 32 px atlas for small sizes. All
-- of Lucide since 2026-10-08: pages of 16x16 cells, page 1 unchanged.
-- A name no longer in the suite (the whole library until 2026-10-09; saved
-- auras may still use one) shows as a question mark; nil only without data.
S.FALLBACK="circle-help"
function S:Coords(name,pixels)
    local entry=build()[name] or build()[S.FALLBACK];if not entry then return end
    local data,i=entry.data,entry.i
    local atlas=(pixels or 64)<=32 and data.atlases[1] or data.atlases[2]
    local per=data.perPage or math.huge
    local page,slot=math.floor((i-1)/per)+1,(i-1)%per
    local col,row=slot%data.columns,math.floor(slot/data.columns)
    local cell,side=atlas.cell,atlas.side
    local path=atlas.pages and atlas.pages[page] or atlas.path
    return path,col*cell/side,(col+1)*cell/side,row*cell/side,(row+1)*cell/side
end
-- Human label: "wand-sparkles" -> "Wand sparkles".
function S:Label(name)
    local text=tostring(name):gsub("%-"," ")
    return text:sub(1,1):upper()..text:sub(2)
end

-- Lucide symbols (ISC/MIT, Media/Symbols/LICENSE-lucide.txt): lookup of atlas
-- cells for UI icons and Symbol media. Data only; textures are created in UI.
local _,ns=...
local S={};ns.Symbols=S
local index
local function build()
    if index then return index end
    index={}
    for i,name in ipairs(ns.SymbolData and ns.SymbolData.names or {}) do index[name]=i end
    return index
end
function S:Valid(name) return type(name)=="string" and build()[name]~=nil end
function S:List() return ns.SymbolData and ns.SymbolData.names or {} end
-- Lucide name for a line-drawn UI icon name, or nil.
function S:UIName(name) return ns.SymbolData and ns.SymbolData.ui[name] end
-- Atlas path and texture coordinates; the 32 px atlas for small sizes.
function S:Coords(name,pixels)
    local i=build()[name];if not i then return end
    local data=ns.SymbolData
    local atlas=(pixels or 64)<=32 and data.atlases[1] or data.atlases[2]
    local col,row=(i-1)%data.columns,math.floor((i-1)/data.columns)
    local cell,side=atlas.cell,atlas.side
    return atlas.path,col*cell/side,(col+1)*cell/side,row*cell/side,(row+1)*cell/side
end
-- Human label: "wand-sparkles" -> "Wand sparkles".
function S:Label(name)
    local text=tostring(name):gsub("%-"," ")
    return text:sub(1,1):upper()..text:sub(2)
end

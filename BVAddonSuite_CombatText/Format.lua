local _,L=...
if not L.ready then return end
-- Number and text formatting. Readable numbers get our own short/full format;
-- secret numbers (protected by the client) can still be shown and formatted
-- through Blizzard's functions, which return displayable secret strings
-- (probe 2026-10-01: AbbreviateNumbers, BreakUpLargeNumbers, tostring and
-- concatenation work on secrets; arithmetic and comparison do not).
local F={}
L.Format=F

local function trim(text) return (text:gsub("%.0+([kKmM]?)$","%1"):gsub("(%.%d-)0+([kKmM]?)$","%1%2")) end
local function group(n)
    local s=tostring(math.floor(n+.5))
    local sign,digits=s:match("^(%-?)(%d+)$")
    if not digits then return s end
    digits=digits:reverse():gsub("(%d%d%d)","%1,"):reverse():gsub("^,","")
    return sign..digits
end
function F.Number(value,mode)
    if value==nil then return "" end
    if L.Secret(value) then
        local f=mode=="short" and AbbreviateNumbers or mode=="full" and BreakUpLargeNumbers or nil
        if f then local ok,text=pcall(f,value);if ok and text~=nil then return text end end
        local ok,text=pcall(tostring,value)
        return ok and text or ""
    end
    if type(value)~="number" then return tostring(value) end
    if mode=="short" then
        local a=math.abs(value)
        if a>=1e6 then return trim(string.format("%.1fM",value/1e6)) end
        if a>=1e4 then return trim(string.format("%.1fk",value/1e3)) end
        return tostring(math.floor(value+.5))
    elseif mode=="full" then return group(value) end
    return tostring(math.floor(value+.5))
end
-- Prefix/suffix text: at most 24 characters, no escape sequences ("|").
F.AFFIX_MAX=24
function F.CleanAffix(value,default)
    if type(value)~="string" then return default end
    value=value:gsub("|","")
    if #value>F.AFFIX_MAX then value=value:sub(1,F.AFFIX_MAX) end
    return value
end
-- Fills {school} {spell} {name} by concatenation, because a value may be a
-- secret string (displayable, but not usable as a gsub replacement).
-- A placeholder without a value drops the whole field ("{spell}: " gives
-- nothing, not ": "); unknown placeholders stay as typed.
function F.Expand(template,values,retry)
    if template=="" or not template:find("{",1,true) then return template end
    local ok,text=pcall(function()
        local out,pos="",1
        while true do
            local s,e,key=template:find("{(%a+)}",pos)
            if not s then return out..template:sub(pos) end
            local value=values[key]
            out=out..template:sub(pos,s-1)
            if key=="school" or key=="spell" or key=="name" then
                if value==nil then return "" end
                out=out..value
            else out=out..template:sub(s,e) end
            pos=e+1
        end
    end)
    if ok then return text end
    -- A value that cannot be joined is left out, the rest stays.
    if not retry then
        local plain={}
        for key,value in pairs(values) do if type(value)=="string" and not L.Secret(value) then plain[key]=value end end
        return F.Expand(template,plain,true)
    end
    return ""
end
-- core text (number or "Dodge") with the style's affixes; crits add theirs
-- outside: critPrefix..prefix..core..suffix..critSuffix.
function F.Text(style,core,values,crit)
    values=values or {}
    local before=F.Expand(style.prefix or "",values)
    local after=F.Expand(style.suffix or "",values)
    local ok,text=pcall(function()
        local t=before..core..after
        if crit then t=F.Expand(style.critPrefix or "",values)..t..F.Expand(style.critSuffix or "",values) end
        return t
    end)
    return ok and text or core
end

-- Damage school colors (lowest set bit wins for mixed schools).
F.SCHOOLS={[1]="FFFF9F",[2]="FFE680",[4]="FF8000",[8]="4DFF4D",[16]="80FFFF",[32]="8080FF",[64]="FF80FF"}
F.SCHOOL_KEYS={[1]="PHYSICAL",[2]="HOLY",[4]="FIRE",[8]="NATURE",[16]="FROST",[32]="SHADOW",[64]="ARCANE"}
F.SCHOOL_NAMES={[1]="Physical",[2]="Holy",[4]="Fire",[8]="Nature",[16]="Frost",[32]="Shadow",[64]="Arcane"}
-- Main school of a mask (lowest set bit), nil when unreadable.
function F.School(school)
    if type(school)~="number" or L.Secret(school) then return nil end
    for _,bit in ipairs({1,2,4,8,16,32,64}) do
        if school%(bit*2)>=bit then return bit end
    end
end
-- Client's localized school name (STRING_SCHOOL_*), English otherwise.
function F.SchoolName(bit)
    if not bit then return nil end
    local name=_G["STRING_SCHOOL_"..F.SCHOOL_KEYS[bit]]
    if type(name)=="string" and name~="" and not L.Secret(name) then return name end
    return F.SCHOOL_NAMES[bit]
end
function F.SchoolHex(bit)
    local colors=L:Config().schoolColors
    return colors and colors[bit] or (F.SCHOOLS[bit].."FF")
end
function F.SchoolColor(school)
    local bit=F.School(school)
    if not bit then return nil end
    local r,g,b=F.Color(F.SchoolHex(bit))
    return r,g,b
end
-- " Fire" in the school color, appended to a (possibly secret) text.
function F.Label(text,bit)
    local name=F.SchoolName(bit)
    if not name then return text end
    local ok,result=pcall(function() return text.." |cff"..F.SchoolHex(bit):sub(1,6)..name.."|r" end)
    return ok and result or text
end
function F.Color(hex)
    return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,tonumber(hex:sub(7,8),16)/255
end

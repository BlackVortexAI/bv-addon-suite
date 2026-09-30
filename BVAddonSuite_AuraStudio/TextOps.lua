-- Literal text comparison. No Lua patterns: every operation is a plain find.
local _,A=...
if A.blocked then return end
local T={maxLength=4096};A.TextOps=T
T.operations={"equals","not_equals","contains","starts_with","ends_with"}
T.labels={equals="Equals",not_equals="Not equals",contains="Contains",starts_with="Starts with",ends_with="Ends with"}
-- Case folding: ASCII A-Z plus the Latin-1 capitals À-Þ (UTF-8 C3 80-9E,
-- except × C3 97), which covers German umlauts. Other scripts stay as they are.
-- Byte ranges only: string.lower may follow the C locale and touch UTF-8 bytes.
local function ascii(c) return string.char(c:byte()+32) end
local function latin(c) if c=="\151" then return "\195\151" end return "\195"..string.char(c:byte()+32) end
function T.Fold(s)
    return (s:gsub("[A-Z]",ascii):gsub("\195([\128-\158])",latin))
end
-- Returns true/false, or nil when an operand is protected, missing or too long.
function T.Compare(a,b,operation,ignoreCase)
    if A.G.IsSecret(a) or A.G.IsSecret(b) or type(a)~="string" or type(b)~="string" then return nil end
    if #a>T.maxLength or #b>T.maxLength then return nil end
    if ignoreCase then a,b=T.Fold(a),T.Fold(b) end
    if operation=="equals" then return a==b end
    if operation=="not_equals" then return a~=b end
    if operation=="contains" then return a:find(b,1,true)~=nil end
    if operation=="starts_with" then return a:sub(1,#b)==b end
    if operation=="ends_with" then return #b==0 or a:sub(-#b)==b end
    return nil
end

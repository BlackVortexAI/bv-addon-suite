-- Backward-compatible player API over the shared unit adapter.
local _,A=...
if A.blocked then return end
local P={fields=A.UnitSource.fields};A.PlayerSource=P
function P.New(api)
    local source=A.UnitSource.New(api)
    return {Capture=function(_,requested) return source:Capture(requested,"player") end}
end

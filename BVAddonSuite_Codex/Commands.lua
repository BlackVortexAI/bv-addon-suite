local _,C=...
if not C.ready then return end
-- /bv codex [text]   the search (with text: already searching it)
-- /bv codex icons    which of the game's icons this client has for the search
-- /bv tour           the tour window
-- /bv tour go        leads through the tour; /bv tour stop ends it
-- /bv tour clear     takes every stop away
local ns=C.ns
ns.Commands:RegisterAction("codex",function(text)
    text=type(text)=="string" and text or ""
    if text=="icons" then C.Palette:IconReport();return end
    if text=="" then C.Palette:Toggle() else C.Palette:Open(text) end
end)
ns.Commands:RegisterAction("tour",function(text)
    text=type(text)=="string" and text or ""
    local T=C.Tour
    T:Ensure()
    if text=="go" then T:Navigate();return end
    if text=="stop" then T:Stop();return end
    if text=="clear" then T:Stop();T:Clear();C:Print("Tour cleared.");return end
    if text~="" then C:Print("/bv tour [go | stop | clear]");return end
    T.Window:Toggle()
end)
-- Key bindings (Bindings.xml).
_G.BINDING_NAME_BVCODEX_SEARCH="Codex: search"
_G.BINDING_NAME_BVCODEX_TOUR="Codex: tour"

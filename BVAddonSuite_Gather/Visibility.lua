local _,G=...
if not G.ready then return end
-- When a kind of node shows (Florian 2026-10-09): always, only with the
-- profession, or only while its tracking is on (the Find Herbs / Find
-- Minerals / Find Treasure aura). The kind's own switch stays the manual
-- override: off is always off.
local V={}
G.Visibility=V
-- Spells that mean you have the profession (gathering ranks and the
-- tracking spell that comes with it), and the tracking spells.
V.PROFESSION={herb={2366,2368,3570,11993,2383},ore={2575,2576,3564,10248,2580,2656},fish={7620,7731,7732,18248}}
V.TRACKING={herb={2383},ore={2580},treasure={2481}}
-- What each kind can be set to.
V.CHOICES={
    herb={"always","profession","tracking"},ore={"always","profession","tracking"},
    fish={"always","profession"},treasure={"always","tracking"},
}
V.LABEL={always="Always",profession="With the profession",tracking="With tracking on"}
function V.Options(kind)
    local out={}
    for _,value in ipairs(V.CHOICES[kind] or {"always"}) do out[#out+1]={value=value,label=V.LABEL[value]} end
    return out
end
local function known(id)
    return G.Call("IsPlayerSpell",id)==true or G.Call("IsSpellKnown",id)==true or G.Call("C_SpellBook.IsSpellKnown",id)==true
end
function V:HasProfession(kind)
    for _,id in ipairs(V.PROFESSION[kind] or {}) do if known(id) then return true end end
    return false
end
function V:Tracking(kind)
    for _,id in ipairs(V.TRACKING[kind] or {}) do
        if G.Call("C_UnitAuras.GetPlayerAuraBySpellID",id) then return true end
    end
    -- The minimap's tracking menu, where the client has it.
    local count=G.Call("C_Minimap.GetNumTrackingTypes")
    if type(count)=="number" then
        local wanted={};for _,id in ipairs(V.TRACKING[kind] or {}) do wanted[id]=true end
        for i=1,count do
            local info=G.Call("C_Minimap.GetTrackingInfo",i)
            if type(info)=="table" and info.active and wanted[info.spellID] then return true end
        end
    end
    return false
end
function V:Shown(kind)
    local c=G:Config()
    if not c[kind] then return false end
    local mode=c[kind.."When"]
    if mode=="profession" then return self:HasProfession(kind) end
    if mode=="tracking" then return self:Tracking(kind) end
    return true
end
-- Learning a profession or switching tracking: the pins follow at once.
function V:Check()
    local state={}
    for _,t in ipairs(G.TYPES) do state[#state+1]=self:Shown(t.id) and "1" or "0" end
    state=table.concat(state)
    if state~=self.state then self.state=state;if G.Pins then G.Pins:Refresh() end end
end
function V:Enable(context)
    self.state=nil
    for _,event in ipairs({"SPELLS_CHANGED","SKILL_LINES_CHANGED","LEARNED_SPELL_IN_TAB","MINIMAP_UPDATE_TRACKING"}) do
        pcall(context.Subscribe,context,event,function() V:Check() end)
    end
    pcall(context.Subscribe,context,"UNIT_AURA",function(_,unit) if unit=="player" then V:Check() end end)
end

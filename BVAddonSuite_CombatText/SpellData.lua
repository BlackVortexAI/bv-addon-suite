local _,L=...
if not L.ready then return end
-- What spells can do (0.7.1): the spell guess never names a spell for
-- something it cannot cause (Florian 2026-10-06: a Drain Life heal tick
-- showed Immolate, cast just before) and knows a spell's school, tick
-- rhythm and duration before any hit taught them. Data: SpellDB.lua,
-- generated from the client's own tables (tools/build_spell_data.py), every
-- rank of class, pet, racial and on-use item spells. Entry format
-- "school;flags;period;duration;speed":
--   school   school mask of its damage ("" when the weapon decides: wands)
--   flags    d direct damage, p periodic damage, h heals anyone, s heals
--            only the caster (drains, food), o heals periodically,
--            c channelled, n never deals damage, t travels (ticks start
--            on impact)
--   period   seconds between ticks (damage, else heal)
--   duration seconds it lasts at most
--   speed    flight speed in yards per second (0.7.3; travelling spells)
-- Not listed: unknown, the learned data decides.
local S={cache={}}
L.SpellData=S

local function parse(text)
    local school,flags,period,duration,speed=text:match("^([^;]*);([^;]*);([^;]*);([^;]*);?([^;]*)$")
    if not flags then return false end
    local function has(c) return flags:find(c,1,true)~=nil end
    return {school=tonumber(school),direct=has("d"),periodic=has("p"),heal=has("h") and "any" or has("s") and "self" or nil,
        hot=has("o"),channel=has("c"),noDamage=has("n"),travels=has("t"),period=tonumber(period),duration=tonumber(duration),speed=tonumber(speed)}
end
-- The parsed entry, else nil.
function S:Entry(id)
    if type(id)~="number" then return nil end
    local entry=self.cache[id]
    if entry==nil then
        local text=L.SpellDB and L.SpellDB[id]
        entry=type(text)=="string" and parse(text) or false
        self.cache[id]=entry
    end
    return entry or nil
end
-- true / false, or nil when unknown. onSelf: the heal landed on you (a
-- drain heals no one else).
function S:CanHeal(id,onSelf)
    local entry=self:Entry(id)
    if not entry then return nil end
    if not entry.heal then return false end
    return entry.heal=="any" or onSelf==true
end
function S:CanDamage(id)
    local entry=self:Entry(id)
    if not entry then return nil end
    return not entry.noDamage
end
-- Main school bit of its damage: only a single school counts.
local SINGLE={[1]=true,[2]=true,[4]=true,[8]=true,[16]=true,[32]=true,[64]=true}
function S:School(id)
    local entry=self:Entry(id)
    if entry and SINGLE[entry.school] then return entry.school end
end
-- Damage ticks: seconds between them (channels and DoTs).
function S:Period(id)
    local entry=self:Entry(id)
    if entry and entry.periodic then return entry.period end
end
function S:Travels(id)
    local entry=self:Entry(id)
    return entry~=nil and entry.travels
end
-- Flight speed (yards per second) of a travelling spell, else nil.
function S:Speed(id)
    local entry=self:Entry(id)
    return entry and entry.travels and entry.speed or nil
end
function S:Duration(id)
    local entry=self:Entry(id)
    return entry and entry.duration or nil
end
-- "dot" (ticks only), "direct" (hits once), "both" (Immolate), else nil.
function S:Kind(id)
    local entry=self:Entry(id)
    if not entry or entry.noDamage then return nil end
    if entry.direct and entry.periodic then return "both" end
    if entry.periodic then return "dot" end
    if entry.direct then return "direct" end
end

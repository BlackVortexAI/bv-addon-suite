local _,L=...
if not L.ready then return end
-- Buffs you give to others (category "buffgiven", off by default). The game
-- reports no "you buffed X". Evidence: your own successful cast while a
-- friendly unit other than you is your target; then whether the buff landed:
-- out of combat a buff of that spell from you on the target (aura read a
-- moment later). Heals and buffs the target refused leave no such aura and
-- show nothing. In combat auras are protected on Forever: only spells seen
-- landing as a buff before (BVCombatTextDB.givenBuffs) are shown, unchecked.
-- Buffs on you come from COMBAT_TEXT_UPDATE (Notices.lua).
local B={CHECKS={.2,.6}}
L.Given=B

local function readable(v) return v~=nil and not L.Secret(v) end
local function call(f,...) if type(f)~="function" then return nil end;local ok,v=pcall(f,...);if ok and readable(v) then return v end end
local function count(key) L.Sources.Count(key) end
local function locked() return InCombatLockdown and InCombatLockdown() end

function B:Learned()
    local db=L:DB()
    if type(db.givenBuffs)~="table" then db.givenBuffs={} end
    return db.givenBuffs
end
local function spellName(id) return call(C_Spell and C_Spell.GetSpellName,id) or call(GetSpellInfo,id) end
-- A buff from you of this spell (same id or same name) on the unit: true,
-- false (readable, none) or nil (not readable: protected or no API).
function B:HasBuff(unit,spellID)
    local api=C_UnitAuras
    if not api then return nil end
    local name=spellName(spellID)
    local direct=api.GetUnitAuraBySpellID
    if type(direct)=="function" then
        local ok,aura=pcall(direct,unit,spellID,"HELPFUL|PLAYER")
        if ok and type(aura)=="table" then return true end
    end
    local scan=api.GetAuraDataByIndex
    if type(scan)~="function" then return nil end
    local readableAny=false
    for i=1,40 do
        local ok,aura=pcall(scan,unit,i,"HELPFUL|PLAYER")
        if not ok then return nil end
        if aura==nil then break end
        if L.Secret(aura) or type(aura)~="table" then return nil end
        readableAny=true
        local id,auraName=aura.spellId,aura.name
        if readable(id) and id==spellID then return true end
        if name and readable(auraName) and auraName==name then return true end
    end
    -- An empty list in combat may just be protected.
    if not readableAny and locked() then return nil end
    return false
end

function B:Show(unit,spellID)
    local cfg=L:Config()
    local style=cfg.categories.buffgiven
    if not style.enabled then return nil end
    local name=spellName(spellID)
    if not name then count("buff given: no name");return nil end
    local entry={category="buffgiven",unit=unit,spell=spellID}
    entry.text=L.Format.Text(style,name,{spell=name})
    local ok,item=pcall(L.Display.Show,L.Display,entry)
    if not ok then count("error");L.Sources.lastError=tostring(item);return nil end
    count(item and "shown buff given" or "skip: category off")
    return item
end
-- Your cast. Friendly target other than you: check, then show.
function B:Cast(spellID)
    if not readable(spellID) or type(spellID)~="number" then count("buff given: cast unreadable");return end
    if not L:Config().categories.buffgiven.enabled then count("buff given: category off");return end
    if call(UnitExists,"target")~=true then count("buff given: no target");return end
    if call(UnitIsUnit,"target","player")==true then count("buff given: target is you");return end
    if call(UnitCanAttack,"player","target")==true then count("buff given: target hostile");return end
    local learned=self:Learned()
    self.serial=(self.serial or 0)+1
    local serial=self.serial
    local done=false
    for i,delay in ipairs(self.CHECKS) do
        C_Timer.NewTimer(delay,function()
            if done or not L:Active() then return end
            local has=self:HasBuff("target",spellID)
            if has==true then
                done=true;learned[spellID]=true;count("buff given: seen")
                self:Show("target",spellID)
            elseif has==nil then
                -- Protected (combat): a spell known as a buff is shown unchecked.
                done=true
                if learned[spellID] then count("buff given: learned");self:Show("target",spellID)
                else count("buff given: not readable") end
            elseif i==#self.CHECKS then count("buff given: no buff") end
        end)
    end
    return serial
end
function B:Enable(context)
    context:Subscribe("UNIT_SPELLCAST_SUCCEEDED",function(_,unit,_,spellID)
        if unit=="player" then local ok,err=pcall(B.Cast,B,spellID);if not ok then count("error");L.Sources.lastError=tostring(err) end end
    end)
end

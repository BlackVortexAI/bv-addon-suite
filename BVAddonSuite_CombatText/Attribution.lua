local _,L=...
if not L.ready then return end
-- Best guess which of your spells caused a hit (experimental, option
-- spellGuess), and which enemies you recently cast on. UNIT_COMBAT carries
-- neither attacker nor spell, so this only uses signals of your own: your
-- running channel, your last cast, your damage-over-time spells on the unit
-- with their tick rhythm (no aura reads: protected), your auto attack. Learned per spell:
-- damage school and tick interval. Without a unique answer there is no icon
-- rather than a wrong guess; it can still be wrong when others hit too.
local A={castWindow=4,tickWindow=7,recentWindow=10,keepWindow=30,keepSpells=6,plates={},casts={}}
L.Attribution=A
A.MELEE,A.AUTO_SHOT,A.SHOOT=6603,75,5019

local function readable(v) return v~=nil and not L.Secret(v) end
local function call(f,...) if type(f)~="function" then return nil end;local ok,v=pcall(f,...);if ok and readable(v) then return v end end

local function plateOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local ok,plate=pcall(C_NamePlate.GetNamePlateForUnit,unit)
    if ok and type(plate)=="table" then return plate end
end
-- Nameplate token of your current target (nil without one).
function A:TargetToken()
    local target=plateOf("target")
    if not target then return nil end
    for token in pairs(self.plates) do if plateOf(token)==target then return token end end
    -- A plate added before we listened: look it up once.
    for i=1,40 do
        local token="nameplate"..i
        if plateOf(token)==target then self.plates[token]=true;return token end
    end
end
function A:IsTarget(unit)
    if unit=="target" then return true end
    local target=plateOf("target")
    return target~=nil and plateOf(unit)==target
end

function A:Cast(spellID)
    if not readable(spellID) or type(spellID)~="number" then return end
    -- Mounting is a cast too, never a damage or heal source.
    if C_MountJournal and C_MountJournal.GetMountFromSpell then
        local mount=call(C_MountJournal.GetMountFromSpell,spellID)
        if mount and mount~=0 then return end
    end
    local now=GetTime()
    -- The channel itself is a candidate while it runs (see Spell).
    if spellID~=self.channel then self.lastSpell,self.lastTime=spellID,now end
    if call(UnitCanAttack,"player","target")~=true then self:Trace("cast "..spellID.." (no hostile target)");return end
    local keys={"target",self:TargetToken()}
    self:Trace("cast "..spellID.." on "..tostring(keys[2] or "target only"))
    for _,key in ipairs(keys) do
        local list=self.casts[key] or {}
        self.casts[key]=list
        for i=#list,1,-1 do if list[i].id==spellID or now-list[i].time>self.keepWindow then table.remove(list,i) end end
        table.insert(list,1,{id=spellID,time=now})
        while #list>self.keepSpells do table.remove(list) end
    end
end
-- You cast on this enemy within the last 10 seconds (counts as fighting you).
function A:Recent(unit)
    local list=self.casts[unit]
    if (not list or not list[1]) and self:IsTarget(unit) then list=self.casts.target end
    return list~=nil and list[1]~=nil and GetTime()-list[1].time<=self.recentWindow
end

local function autoAttacking()
    local current=C_Spell and C_Spell.IsCurrentSpell or IsCurrentSpell
    if call(current,A.MELEE)==true then return A.MELEE end
    if call(IsAutoRepeatSpell)==true then
        local ok,_,class=pcall(UnitClass,"player")
        return ok and readable(class) and class=="HUNTER" and A.AUTO_SHOT or A.SHOOT
    end
end
-- Your DoTs on this unit: the cast entries {id, time = applied, tick = last
-- recognised tick} still running by their rhythm. Auras on enemies are
-- protected on Forever (Florian 2026-10-02; AuraStudio reads its own auras
-- through the cooldown manager), so a DoT counts as running while its ticks
-- keep coming: an expected tick missing (1.5 intervals) means it ran out.
-- Tick jitter in Florian's trace: about +-0.08 s; 0.2 s keeps DoTs apart.
A.TOLERANCE,A.DIRECT,A.UNLEARNED=.2,1.5,6.5
-- Rhythm base: the last tick, also one that was due but not named.
local function base(cast) return math.max(cast.tick or 0,cast.seen or 0,cast.time) end
A.Base=base
local function ownDots(list,intervals,kinds,now,out)
    if not list then return end
    for _,cast in ipairs(list) do
        local interval=intervals[cast.id]
        local last=base(cast)
        if interval then
            if now-last<=interval*1.5+A.TOLERANCE then out[#out+1]=cast end
        elseif (cast.tick or kinds[cast.id]=="dot") and kinds[cast.id]~="direct" and now-last<=A.UNLEARNED then
            -- Rhythm not learned yet, but it ticked or is a known DoT: stays
            -- a candidate while it may tick. Fresh casts go via lastSpell.
            out[#out+1]=cast
        end
    end
end
-- Learned per spell, kept across sessions: main school bit and tick interval.
local function stored(key)
    local db=L:DB()
    if type(db[key])~="table" then db[key]={} end
    return db[key]
end
-- Version 2 (0.5.4): intervals are the median of the last tick gaps. Data
-- learned by earlier versions is dropped once (it could reinforce errors,
-- Florian's trace 2026-10-02: Agony learned 1.17 s instead of 2 s).
A.DATA_VERSION=2
local function current()
    local db=L:DB()
    if db.spellDataVersion~=A.DATA_VERSION then
        db.spellIntervals,db.spellGaps,db.spellKinds,db.spellDataVersion={},{},{},A.DATA_VERSION
    end
    return db
end
function A:Schools() return stored("spellSchools") end
function A:Intervals() current();return stored("spellIntervals") end
function A:Gaps() current();return stored("spellGaps") end
-- "dot": first hit well after the cast (no direct damage); "direct" otherwise.
function A:Kinds() current();return stored("spellKinds") end
function A:Forget() local db=L:DB();db.spellSchools,db.spellIntervals,db.spellGaps,db.spellKinds={},{},{},{};db.spellDataVersion=A.DATA_VERSION end
-- Diagnosis: the last decisions as short lines in BVCombatTextDB.spellTrace
-- (spell ids, schools, rhythm, unit tokens, times; no names or amounts).
A.TRACE_MAX=200
function A:Trace(text)
    local db=L:DB()
    if type(db.spellTrace)~="table" then db.spellTrace={} end
    local list=db.spellTrace
    list[#list+1]=string.format("%.2f %s",GetTime(),text)
    while #list>self.TRACE_MAX do table.remove(list,1) end
end

-- Timing: DoTs and channels tick at a fixed interval from their start, so a
-- tick is expected at base + n * interval (base: last recognised tick, else
-- the cast or channel start). "yes" within the tolerance, "no" outside,
-- "maybe" while the interval is not learned yet.
local RANK={no=0,maybe=1,yes=2}
local function rhythm(base,interval,now)
    if not interval then return "maybe" end
    local n=math.max(1,math.floor((now-base)/interval+.5))
    return math.abs(now-(base+n*interval))<=A.TOLERANCE and "yes" or "no"
end
-- After a recognised tick: keep it as the new base and learn the interval
-- as the median of the last gaps, so single wrong gaps (a missed or wrongly
-- named tick) cannot drag it away. Nothing in Classic ticks faster than 1 s.
A.GAPS=7
local function median(list)
    local sorted={}
    for i,v in ipairs(list) do sorted[i]=v end
    table.sort(sorted)
    local n=#sorted
    if n%2==1 then return sorted[(n+1)/2] end
    return (sorted[n/2]+sorted[n/2+1])/2
end
function A:Ticked(id,state,now)
    if state.first==nil then
        state.first=now-state.time
        local kinds=self:Kinds()
        if kinds[id]==nil then kinds[id]=state.first>A.DIRECT and "dot" or "direct" end
    end
    local dt=state.tick and now-state.tick
    if dt and dt>=.9 and dt<=6 then
        local gaps=self:Gaps()
        local list=gaps[id] or {}
        gaps[id]=list
        list[#list+1]=dt
        while #list>A.GAPS do table.remove(list,1) end
        self:Intervals()[id]=median(list)
    end
    state.tick=now
end
-- Spell for an outgoing hit on unit (school: the hit's main school bit), or a
-- heal on you (heal=true). Candidates: the running channel, your last direct
-- cast, your DoTs on the unit. Those of another learned school drop out, then
-- those clearly not due by their rhythm. One left: taken (and taught the
-- hit's school and rhythm). Several: the only due one, if none is unlearned;
-- otherwise nothing rather than a wrong guess.
-- Physical hits while you auto attack your target are the swing unless a
-- physical spell's rhythm fits.
function A:Spell(unit,heal,school)
    local now=GetTime()
    local recent=self.lastSpell and now-self.lastTime<=self.castWindow and self.lastSpell or nil
    if heal then return recent end
    local intervals,schools=self:Intervals(),self:Schools()
    local kinds=self:Kinds()
    local byId,list={},{}
    -- rhythm: the fit comes from a learned rhythm (a "no" then is certain).
    local function add(id,fit,state,rhythmic)
        local c=byId[id]
        if not c then c={id=id,fit=fit};byId[id]=c;list[#list+1]=c end
        if RANK[fit]>RANK[c.fit] then c.fit=fit;c.rhythmic=rhythmic end
        if state then c.state=state end
    end
    if self.channel then
        local state=self.channelState
        add(self.channel,rhythm(base(state),intervals[self.channel],now),state,intervals[self.channel]~=nil)
    end
    local casts=self.casts[unit] or (self:IsTarget(unit) and self.casts.target) or nil
    if self.lastSpell and self.lastSpell~=self.channel then
        -- The cast entry goes along, so ticks found this way teach the rhythm;
        -- a spell cast on this unit stays a candidate for its first two ticks.
        local state
        for _,cast in ipairs(casts or {}) do if cast.id==self.lastSpell then state=cast;break end end
        local age=now-self.lastTime
        -- Longer only for spells that tick: no hit yet, first hit later than
        -- a direct one (pure DoTs) or a learned rhythm. A direct-damage spell
        -- (Fireball) must not claim unrelated hits after its own.
        local ticking=state and (state.first==nil or state.first>A.DIRECT or intervals[self.lastSpell]~=nil)
        if age<=self.castWindow or (ticking and age<=self.tickWindow) then
            -- Direct hit right after the cast; a ticking spell by its rhythm
            -- ("maybe" until learned); otherwise late for a direct hit.
            local pure=kinds[self.lastSpell]=="dot"
            local direct=age<=A.DIRECT and not pure
            local fit=direct and "yes" or ticking and rhythm(base(state),intervals[self.lastSpell],now) or "no"
            add(self.lastSpell,fit,state,not direct and ticking and intervals[self.lastSpell]~=nil)
        end
    end
    local dots={}
    ownDots(casts,intervals,kinds,now,dots)
    for _,state in ipairs(dots) do add(state.id,rhythm(base(state),intervals[state.id],now),state,intervals[state.id]~=nil) end
    -- Damage type first: a learned other school cannot have caused this hit.
    local left={}
    for _,c in ipairs(list) do
        if not (school and schools[c.id] and schools[c.id]~=school) then left[#left+1]=c end
    end
    local auto=school==1 and self:IsTarget(unit) and autoAttacking() or nil
    local function note(result)
        local parts={}
        for _,c in ipairs(list) do
            local st=c.state
            parts[#parts+1]=string.format("%d:%s:s%s:i%s:b%s%s",c.id,c.fit,tostring(schools[c.id] or "?"),
                intervals[c.id] and string.format("%.2f",intervals[c.id]) or "?",
                st and string.format("%.2f",st.tick or st.time) or "-",
                (school and schools[c.id] and schools[c.id]~=school) and "(school)" or "")
        end
        self:Trace(string.format("hit %s s%s [%s] -> %s",tostring(unit),tostring(school or "?"),table.concat(parts," "),tostring(result)))
    end
    local pick
    -- One left: taken, unless its learned rhythm says it is not due.
    if #left==1 then if not (left[1].fit=="no" and left[1].rhythmic) then pick=left[1] end
    elseif #left>1 then
        -- Rhythm next: who is clearly not due drops out. One left: taken
        -- (also an unlearned one, which learns from it). Several: only a
        -- single due one counts while none is still unlearned.
        local viable,fits,maybe={},{},false
        for _,c in ipairs(left) do
            if c.fit~="no" then viable[#viable+1]=c end
            if c.fit=="yes" then fits[#fits+1]=c elseif c.fit=="maybe" then maybe=true end
        end
        if #viable==1 then pick=viable[1]
        elseif #fits==1 and not maybe then pick=fits[1] end
    end
    -- A physical hit while auto attacking is the swing, unless a known
    -- physical spell's rhythm fits; the swing never teaches a spell.
    if auto and not (pick and schools[pick.id]==1 and pick.fit=="yes") then note("auto");return auto end
    note(pick and pick.id or (#left>1 and "ambiguous" or "none"))
    if not pick then
        if #left>1 then L.Sources.Count("spell: ambiguous") end
        -- Still alive: every DoT due at this hit may have ticked.
        for _,c in ipairs(left) do if c.state and c.fit=="yes" then c.state.seen=now end end
        return nil
    end
    if school and schools[pick.id]==nil then schools[pick.id]=school end
    if pick.state then self:Ticked(pick.id,pick.state,now) end
    return pick.id
end
function A.Icon(spellID)
    if not spellID then return nil end
    local texture=call(C_Spell and C_Spell.GetSpellTexture or GetSpellTexture,spellID)
    if texture then return texture end
end

function A:Enable(context)
    self.plates,self.casts,self.lastSpell,self.lastTime,self.channel={},{},nil,nil,nil
    context:Subscribe("UNIT_SPELLCAST_SUCCEEDED",function(_,unit,_,spellID) if unit=="player" then A:Cast(spellID) end end)
    -- A channel ticks for its whole duration, not only in the 4 s after it starts.
    context:Subscribe("UNIT_SPELLCAST_CHANNEL_START",function(_,unit,_,spellID)
        if unit=="player" and readable(spellID) then A.channel,A.channelState=spellID,{time=GetTime()};A:Trace("channel start "..spellID) end
    end)
    context:Subscribe("UNIT_SPELLCAST_CHANNEL_STOP",function(_,unit) if unit=="player" then A:Trace("channel stop "..tostring(A.channel));A.channel,A.channelState=nil,nil end end)
    -- "target" holds casts on the current target without a nameplate only.
    context:Subscribe("PLAYER_TARGET_CHANGED",function() A.casts.target=nil end)
    context:Subscribe("NAME_PLATE_UNIT_ADDED",function(_,unit) if readable(unit) then A.plates[unit]=true end end)
    context:Subscribe("NAME_PLATE_UNIT_REMOVED",function(_,unit) if readable(unit) then A.plates[unit]=nil;A.casts[unit]=nil end end)
    -- Plates already shown when the module starts.
    for i=1,40 do local token="nameplate"..i;if plateOf(token) then self.plates[token]=true end end
end

local _,L=...
if not L.ready then return end
-- Best guess which of your spells caused a hit (experimental, option
-- spellGuess), and which enemies you recently cast on. UNIT_COMBAT carries
-- neither attacker nor spell, so this only uses signals of your own: your
-- running channel, your last cast, your damage-over-time spells on the unit
-- with their tick rhythm (no aura reads: protected), your auto attack. Learned per spell:
-- damage school and tick interval. Without a unique answer there is no icon
-- rather than a wrong guess; it can still be wrong when others hit too.
local A={castWindow=4,tickWindow=7,recentWindow=10,keepWindow=30,keepSpells=6,plates={},casts={},petCasts={},heals={}}
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
    local SD=L.SpellData
    if spellID~=self.channel then
        self.lastSpell,self.lastTime=spellID,now
        -- A spell that never deals damage (a curse, a buff) leaves the hit to
        -- the cast before it (a Shadow Bolt still flying).
        if SD:CanDamage(spellID)~=false then self.lastHit,self.lastHitTime=spellID,now end
    end
    -- Heals: the last one, and those over time (HoTs, drains, food) while
    -- they last.
    local entry=SD:Entry(spellID)
    if entry and entry.heal then
        self.lastHeal,self.lastHealTime=spellID,now
        if entry.hot then
            local list=self.heals
            for i=#list,1,-1 do if list[i].id==spellID or now-list[i].time>(SD:Duration(list[i].id) or self.castWindow) then table.remove(list,i) end end
            table.insert(list,1,{id=spellID,time=now})
            while #list>self.keepSpells do table.remove(list) end
        end
    end
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
-- Your running auto attack (melee, wand, auto shot) or nil; also Log.lua.
A.AutoAttacking=autoAttacking
-- Your own swing (0.7.2): PLAYER_SWING comes in the frame of your swing's
-- Combat Log line, its hit 0.45-0.55 s later (signal probe 2026-10-07,
-- spread 0.2-1.0 s); readable without the Combat Log. One swing vouches for
-- one physical hit in SWING_MIN..SWING_MAX after it.
A.SWING_MIN,A.SWING_MAX=.15,1
function A:Swing() self.swing,self.swingUsed=GetTime(),false end
-- take: the hit uses the swing up.
function A:SwingFits(take)
    if not self.swing or self.swingUsed then return false end
    local age=GetTime()-self.swing
    if age<self.SWING_MIN or age>self.SWING_MAX then return false end
    if take then self.swingUsed=true end
    return true
end
-- Your DoTs on this unit: the cast entries {id, time = applied, tick = last
-- recognised tick} still running by their rhythm. Auras on enemies are
-- protected on Forever (Florian 2026-10-02; AuraStudio reads its own auras
-- through the cooldown manager), so a DoT counts as running while its ticks
-- keep coming: an expected tick missing (1.5 intervals) means it ran out.
-- Tick jitter in Florian's trace: about +-0.08 s; 0.2 s keeps DoTs apart.
A.TOLERANCE,A.DIRECT,A.UNLEARNED=.2,1.5,6.5
-- A DoT ends after its duration (client data); a late last tick still counts.
A.EXPIRY=1
-- Rhythm base: the last tick, also one that was due but not named.
local function base(cast) return math.max(cast.tick or 0,cast.seen or 0,cast.time) end
A.Base=base
local function ownDots(list,now,out)
    if not list then return end
    for _,cast in ipairs(list) do
        local interval,kind=A:IntervalOf(cast.id),A:KindOf(cast.id)
        local duration=L.SpellData:Duration(cast.id)
        local last=base(cast)
        if duration and now-cast.time>duration+A.EXPIRY then
            -- Ran out by the duration the client's data gives it.
        elseif interval then
            if now-last<=interval*1.5+A.TOLERANCE then out[#out+1]=cast end
        elseif (cast.tick or kind=="dot") and kind~="direct" and now-last<=A.UNLEARNED then
            -- Rhythm not learned yet, but it ticked or is a known DoT: stays
            -- a candidate while it may tick. Fresh casts go via lastSpell.
            out[#out+1]=cast
        end
    end
end
-- One of your DoTs still runs on this enemy (by its duration in the client
-- data, else its ticks): evidence after the 10 s of Recent (Origin.lua).
function A:Running(unit)
    local list=self.casts[unit]
    if (not list or not list[1]) and self:IsTarget(unit) then list=self.casts.target end
    local out={}
    ownDots(list,GetTime(),out)
    return out[1]~=nil
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
-- Until a hit teaches a spell's school: the school its description names
-- ("... 100 Shadow damage", German "Schattenschaden"; idea from ForeverCrit,
-- research 2026-10-03). Only a single named school counts. Kept for the
-- session only, never stored as learned. A secret or not yet loaded
-- description is asked again later.
A.described={}
function A:DescribedSchool(id)
    local known=self.described[id]
    if known~=nil then return known or nil end
    local text=call(C_Spell and C_Spell.GetSpellDescription or GetSpellDescription,id)
    if type(text)~="string" or text=="" then return nil end
    local found=false
    for bit in pairs(L.Format.SCHOOLS) do
        local name=L.Format.SchoolName(bit)
        if name and text:find(name,1,true) then
            if found then found=false;break end
            found=bit
        end
    end
    self.described[id]=found
    return found or nil
end
-- The client's data first (SpellData.lua), then learned, then described.
function A:SchoolOf(id) return L.SpellData:School(id) or self:Schools()[id] or self:DescribedSchool(id) end
function A:Intervals() current();return stored("spellIntervals") end
function A:IntervalOf(id) return L.SpellData:Period(id) or self:Intervals()[id] end
function A:Gaps() current();return stored("spellGaps") end
-- "dot": first hit well after the cast (no direct damage); "direct" otherwise.
function A:Kinds() current();return stored("spellKinds") end
-- "dot", "direct", "both" (client data, Immolate), else learned.
function A:KindOf(id) return L.SpellData:Kind(id) or self:Kinds()[id] end
function A:Forget() local db=L:DB();db.spellSchools,db.spellIntervals,db.spellGaps,db.spellKinds={},{},{},{};db.spellDataVersion=A.DATA_VERSION;A.described={} end
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
-- hint "tick" (Log.lua: your Combat Log line came right behind the hit): a
-- DoT or channel tick, so neither a fresh direct hit nor the swing.
-- A heal (0.7.1): your running healing channel, else your heal cast of the
-- last 4 s and your heals over time on their beat, but only spells that can
-- heal there (SpellData.lua): a Drain Life tick is never the Immolate cast
-- before it. Several: none.
function A:CanHeal(id,onSelf)
    local known=L.SpellData:CanHeal(id,onSelf)
    if known~=nil then return known end
    -- Not listed: a spell seen hitting an enemy deals damage, no heal.
    if self:Schools()[id]~=nil then return false end
end
function A:Spell(unit,heal,school,hint)
    local now=GetTime()
    local recent=self.lastSpell and now-self.lastTime<=self.castWindow and self.lastSpell or nil
    if heal then
        local onSelf=unit=="player"
        local SD=L.SpellData
        local found,seen={},{}
        local function add(id) if id and not seen[id] then seen[id]=true;found[#found+1]=id end end
        -- A healing channel (Drain Life, First Aid) heals with its ticks.
        if self.channel and self:CanHeal(self.channel,onSelf) then add(self.channel)
        else
            if recent and self:CanHeal(recent,onSelf) then add(recent) end
            if self.lastHeal and now-self.lastHealTime<=self.castWindow and self:CanHeal(self.lastHeal,onSelf) then add(self.lastHeal) end
            -- Heals over time and drains on their beat while they last.
            for _,cast in ipairs(self.heals) do
                local entry=SD:Entry(cast.id)
                if entry and self:CanHeal(cast.id,onSelf) and now-cast.time<=(entry.duration or self.castWindow)+A.EXPIRY
                    and (not entry.period or rhythm(cast.time,entry.period,now)=="yes") then add(cast.id) end
            end
        end
        -- Several possible: none rather than a wrong one.
        local pick=#found==1 and found[1] or nil
        self:Trace(string.format("heal %s channel %s cast %s [%s] -> %s",tostring(unit),tostring(self.channel),tostring(recent),table.concat(found," "),tostring(pick or (#found>1 and "ambiguous" or "none"))))
        return pick
    end
    local schools=self:Schools()
    local function interval(id) return self:IntervalOf(id) end
    local function kind(id) return self:KindOf(id) end
    -- Fit by rhythm, and whether a "no" is certain: until its first tick a
    -- travelling spell (Fireball) ticks from its impact, not its cast.
    local function beat(id,state)
        local fit=rhythm(base(state),interval(id),now)
        local sure=interval(id)~=nil
        if fit=="no" and not state.tick and not state.seen and L.SpellData:Travels(id) then fit,sure="maybe",false end
        return fit,sure
    end
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
        local fit,sure=beat(self.channel,state)
        add(self.channel,fit,state,sure)
    end
    local casts=self.casts[unit] or (self:IsTarget(unit) and self.casts.target) or nil
    if self.lastHit and self.lastHit~=self.channel then
        -- The cast entry goes along, so ticks found this way teach the rhythm;
        -- a spell cast on this unit stays a candidate for its first two ticks.
        local state
        for _,cast in ipairs(casts or {}) do if cast.id==self.lastHit then state=cast;break end end
        local age=now-self.lastHitTime
        -- Longer only for spells that tick: no hit yet, first hit later than
        -- a direct one (pure DoTs) or a learned rhythm. A direct-damage spell
        -- (Fireball) must not claim unrelated hits after its own.
        local ticking=state and kind(self.lastHit)~="direct" and (state.first==nil or state.first>A.DIRECT or interval(self.lastHit)~=nil)
        if (age<=self.castWindow or (ticking and age<=self.tickWindow)) and (hint~="tick" or ticking and kind(self.lastHit)~="direct") then
            -- Direct hit right after the cast; a ticking spell by its rhythm
            -- ("maybe" until learned); otherwise late for a direct hit.
            local pure=kind(self.lastHit)=="dot"
            local direct=age<=A.DIRECT and not pure and hint~="tick"
            local fit,sure="no",false
            if direct then fit="yes" elseif ticking then fit,sure=beat(self.lastHit,state) end
            add(self.lastHit,fit,state,sure)
        end
    end
    local dots={}
    ownDots(casts,now,dots)
    for _,state in ipairs(dots) do local fit,sure=beat(state.id,state);add(state.id,fit,state,sure) end
    -- Damage type first: another school (client data, learned or described)
    -- cannot have caused this hit.
    for _,c in ipairs(list) do c.school=self:SchoolOf(c.id) end
    local left={}
    -- A spell that never deals damage (a pure heal) cannot either.
    for _,c in ipairs(list) do
        if not (school and c.school and c.school~=school) and L.SpellData:CanDamage(c.id)~=false then left[#left+1]=c end
    end
    local auto=hint~="tick" and school==1 and self:IsTarget(unit) and autoAttacking() or nil
    local function note(result)
        local parts={}
        for _,c in ipairs(list) do
            local st=c.state
            -- sx32: client data, s32: learned school, sd32: from the description.
            local data=L.SpellData:School(c.id)
            parts[#parts+1]=string.format("%d:%s:s%s:i%s:b%s%s",c.id,c.fit,data and "x"..data or schools[c.id] and tostring(schools[c.id]) or c.school and "d"..c.school or "?",
                interval(c.id) and string.format("%.2f",interval(c.id)) or "?",
                st and string.format("%.2f",st.tick or st.time) or "-",
                (school and c.school and c.school~=school) and "(school)" or "")
        end
        self:Trace(string.format("hit %s s%s%s [%s] -> %s",tostring(unit),tostring(school or "?"),hint and " "..hint or "",table.concat(parts," "),tostring(result)))
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
    if auto and not (pick and pick.school==1 and pick.fit=="yes") then note("auto");return auto end
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
-- Your pet's spells (UNIT_SPELLCAST_SUCCEEDED for "pet"): a hit within 2 s
-- whose school is the spell's (learned or named in its description) is the
-- pet's, one hit per cast. Spells without a damage school in their
-- description (Torment, ...) never match, so a swing gets no spell. The imp's
-- Firebolt lands up to about 1 s after the cast (Florian's trace 2026-10-05).
A.PET_WINDOW=2
function A:PetCast(spellID)
    if not readable(spellID) or type(spellID)~="number" then return end
    local now=GetTime()
    local list=self.petCasts
    for i=#list,1,-1 do if list[i].used or now-list[i].time>self.PET_WINDOW then table.remove(list,i) end end
    list[#list+1]={id=spellID,time=now}
    self:Trace("pet cast "..spellID)
end
-- take: the hit is given to the cast (it then names no further hit).
function A:PetSpell(school,take)
    if not school then return nil end
    local now=GetTime()
    for _,cast in ipairs(self.petCasts) do
        if not cast.used and now-cast.time<=self.PET_WINDOW and self:SchoolOf(cast.id)==school then
            if take then cast.used=true end
            return cast.id
        end
    end
end
-- Your pet's melee: a physical hit fits when there is no other pet hit in
-- the last 6 s (a first swing) or it lands on the pet's swing beat:
-- UnitAttackSpeed("pet"), else the last gap measured (voidwalker 2.0 s,
-- jitter about 0.1 s, Florian's traces 2026-10-05). Alone every such hit
-- fits; in a group the beat keeps a member's swings apart.
A.PET_TOLERANCE,A.PET_FORGET=.3,6
function A:PetExists()
    local ok,v=pcall(UnitExists,"pet")
    return ok and v==true and not L.Secret(v)
end
function A:PetMeleeFits(grouped)
    if not grouped then return true end
    local last=self.petMelee
    local now=GetTime()
    if not last or now-last>self.PET_FORGET then return true end
    local speed=call(UnitAttackSpeed,"pet")
    if type(speed)~="number" or speed<=0 then speed=self.petGap end
    if not speed then return true end
    local n=math.max(1,math.floor((now-last)/speed+.5))
    return math.abs(now-(last+n*speed))<=self.PET_TOLERANCE
end
function A:PetMelee()
    local now=GetTime()
    if self.petMelee and now-self.petMelee>=1 and now-self.petMelee<=self.PET_FORGET then self.petGap=now-self.petMelee end
    self.petMelee=now
    self:Trace("pet melee")
    return self.MELEE
end
function A.Icon(spellID)
    if not spellID then return nil end
    local texture=call(C_Spell and C_Spell.GetSpellTexture or GetSpellTexture,spellID)
    if texture then return texture end
end

function A:Enable(context)
    self.plates,self.casts,self.lastSpell,self.lastTime,self.channel,self.petCasts={},{},nil,nil,nil,{}
    self.lastHit,self.lastHitTime,self.lastHeal,self.lastHealTime,self.heals=nil,nil,nil,nil,{}
    context:Subscribe("UNIT_SPELLCAST_SUCCEEDED",function(_,unit,_,spellID)
        if unit=="player" then A:Cast(spellID) elseif unit=="pet" then A:PetCast(spellID) end
    end)
    -- A channel ticks for its whole duration, not only in the 4 s after it starts.
    context:Subscribe("UNIT_SPELLCAST_CHANNEL_START",function(_,unit,_,spellID)
        if unit=="player" and readable(spellID) then A.channel,A.channelState=spellID,{time=GetTime()};A:Trace("channel start "..spellID) end
    end)
    -- Unknown on a client without it: no swing evidence, nothing else changes.
    self.swing,self.swingUsed=nil,nil
    pcall(context.Subscribe,context,"PLAYER_SWING",function() A:Swing() end)
    context:Subscribe("UNIT_SPELLCAST_CHANNEL_STOP",function(_,unit) if unit=="player" then A:Trace("channel stop "..tostring(A.channel));A.channel,A.channelState=nil,nil end end)
    -- "target" holds casts on the current target without a nameplate only.
    context:Subscribe("PLAYER_TARGET_CHANGED",function() A.casts.target=nil end)
    context:Subscribe("NAME_PLATE_UNIT_ADDED",function(_,unit) if readable(unit) then A.plates[unit]=true end end)
    context:Subscribe("NAME_PLATE_UNIT_REMOVED",function(_,unit) if readable(unit) then A.plates[unit]=nil;A.casts[unit]=nil end end)
    -- Plates already shown when the module starts.
    for i=1,40 do local token="nameplate"..i;if plateOf(token) then self.plates[token]=true end end
end

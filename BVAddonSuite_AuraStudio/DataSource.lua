-- Narrow event-driven sources. Every field is classified before ordinary Lua
-- inspects it; absent/protected/error never becomes a false Boolean or zero.
local _,A=...
if A.blocked then return end
local G=A.G
local D={}; A.DataSource=D
D.reasons={player_state="player_state",location="location",item_count="inventory",item_equipped="inventory",spell_cooldown="cooldown",spell_proc="proc",
    spell_charges="cooldown",spell_usable="usable",spell_known="spellbook",totem="totem",
    player_xp="xp",player_money="money",currency="currency",reputation="reputation",player_talent="talents"}
function D.Key(kind,config)
    local id
    if kind=="totem" then id=config.slot
    elseif kind=="currency" then id=config.currencyID
    elseif kind=="reputation" then id=config.factionID
    elseif kind=="player_talent" then id=config.nodeID
    elseif kind=="player_xp" or kind=="player_money" then id=0
    else id=config.itemID or config.spellID end
    return kind..":"..tostring(id or 0)
end
function D.New(api)
    api=api or _G
    local self={}
    local function secret(v) return api.issecretvalue and api.issecretvalue(v) end
    local function field(v,t)
        if secret(v) then return nil,"protected" end
        if G.Accepts(t,v) then return v,"readable" end
        return nil,"unavailable"
    end
    local function read(fn,...)
        if type(fn)~="function" then return nil end
        local ok,value=pcall(fn,...); if ok then return value end
    end
    local function accessible(raw)
        return not secret(raw) and type(raw)=="table" and not getmetatable(raw)
            and (not api.canaccesstable or api.canaccesstable(raw))
    end
    -- See the pinned API notes in docs/research. Configured player/session
    -- events only; GUIDs and nested encounter-unit records are ignored. Fresh
    -- packets contain independently readable fields, never retained raw payloads.
    function self:Event(event,a,b,c,d,e)
        local packet={values={event=true},fields={}}
        local function put(key,value,t,minimum)
            -- Event metadata is scalar only. Reject inaccessible/nested tables
            -- before a generic value validator could traverse their contents.
            if secret(value) or G.IsSecret(value) then packet.fields[key]="protected";return end
            local primitive=type(value)
            if primitive~="number" and primitive~="string" and primitive~="boolean" then packet.fields[key]="unavailable";return end
            local readable,status=field(value,t)
            if readable~=nil and minimum~=nil and readable<minimum then readable=nil;status="unavailable" end
            packet.values[key],packet.fields[key]=readable,status
        end
        if event=="UNIT_SPELLCAST_SUCCEEDED" then
            local unit=field(a,"string");if unit~="player" then return end
            packet.kind="player_cast"
            packet.values.spellID,packet.fields.spellID=field(c,"integer")
            if packet.values.spellID and packet.values.spellID<1 then packet.values.spellID=nil;packet.fields.spellID="unavailable" end
        elseif event=="PLAYER_SWING" then
            packet.kind="player_swing"
            packet.values.duration,packet.fields.duration=field(a,"float")
            if packet.values.duration and (packet.values.duration<0 or packet.values.duration>86400) then packet.values.duration=nil;packet.fields.duration="unavailable" end
            local value,status=field(b,"integer");packet.fields.hand=status
            if value~=nil then
                local e=api.Enum and api.Enum.PlayerSwingType
                if e then
                    if value==e.MainHand then packet.values.hand="MAINHAND"
                    elseif value==e.OffHand then packet.values.hand="OFFHAND"
                    elseif value==e.Ranged then packet.values.hand="RANGED" end
                end
                if not packet.values.hand then packet.fields.hand="unavailable" end
            end
        elseif event=="ENCOUNTER_START" or event=="ENCOUNTER_END" then
            packet.kind="encounter_event"
            packet.values.started=event=="ENCOUNTER_START";packet.values.ended=event=="ENCOUNTER_END"
            put("encounterID",a,"integer",1);put("name",b,"string")
            put("difficulty",c,"integer",0);put("groupSize",d,"integer",0)
            packet.fields.success="unavailable"
            if packet.values.ended then
                put("success",e,"integer")
                local value=packet.values.success
                if value==0 or value==1 then packet.values.success=value==1
                elseif value~=nil then packet.values.success=nil;packet.fields.success="unavailable" end
            end
        elseif event=="READY_CHECK" or event=="READY_CHECK_FINISHED" then
            packet.kind="ready_check_event"
            packet.values.started=event=="READY_CHECK";packet.values.ended=event=="READY_CHECK_FINISHED"
            packet.fields.initiator="unavailable";packet.fields.timeLeft="unavailable";packet.fields.preempted="unavailable"
            if packet.values.started then put("initiator",a,"string");put("timeLeft",b,"float",0)
            else put("preempted",a,"boolean") end
        else return end
        return packet
    end
    function self:Observe(kind,config,event)
        local out={values={},fields={}}
        local function put(key,value,t) out.values[key],out.fields[key]=field(value,t) end
        local function transport(key,value,t)
            if secret(value) then out.values[key]=G.Capture(value,t,api.issecretvalue);out.fields[key]="protected"
            else put(key,value,t) end
        end
        local function durationObject(fn,arg)
            local raw=read(fn,arg)
            if secret(raw) or type(raw)=="table" or type(raw)=="userdata" then
                out.values.durationObject=G.CaptureObject(raw,"duration");out.fields.durationObject="protected"
            else out.fields.durationObject="unavailable" end
        end
        if kind=="player_talent" then
            local configID,status=field(read(api.C_ClassTalents and api.C_ClassTalents.GetActiveConfigID),"integer")
            local function unavailable(why)
                for _,key in ipairs({"configID","activeRank","currentRank","maxRanks","totalMaxRanks","available","active"})do out.fields[key]=why or "unavailable" end
                return out
            end
            if not configID or configID<1 then return unavailable(status=="protected" and status or "unavailable") end
            local raw=read(api.C_Traits and api.C_Traits.GetNodeInfo,configID,config.nodeID)
            if not accessible(raw) then return unavailable(secret(raw) and "protected" or "unavailable") end
            -- Do not infer a different node from a restricted/mismatched ID.
            local nodeID,nodeStatus=field(raw.ID,"integer")
            if nodeID~=config.nodeID then return unavailable(nodeStatus=="protected" and nodeStatus or "unavailable") end
            put("configID",configID,"integer")
            for _,key in ipairs({"activeRank","currentRank","maxRanks","totalMaxRanks"})do
                local value,why=field(raw[key],"integer")
                if value~=nil and value>=0 and value<=100000 then put(key,value,"integer") else out.fields[key]=why=="protected" and why or "unavailable" end
            end
            put("available",raw.isAvailable,"boolean")
            if out.values.activeRank~=nil then put("active",out.values.activeRank>0,"boolean") else out.fields.active=out.fields.activeRank end
        elseif kind=="player_xp" then
            transport("current",read(api.UnitXP,"player"),"integer")
            transport("maximum",read(api.UnitXPMax,"player"),"integer")
            transport("level",read(api.UnitLevel,"player"),"integer")
            transport("rested",read(api.GetXPExhaustion),"integer")
            transport("disabled",read(api.IsXPUserDisabled),"boolean")
            transport("capped",read(api.GameRulesUtil and api.GameRulesUtil.IsPlayerAtEffectiveMaxLevel),"boolean")
        elseif kind=="player_money" then
            transport("copper",read(api.GetMoney),"integer")
        elseif kind=="currency" then
            local raw=read(api.C_CurrencyInfo and api.C_CurrencyInfo.GetCurrencyInfo,config.currencyID)
            if accessible(raw) then
                transport("name",raw.name,"string");transport("quantity",raw.quantity,"float")
                transport("maxQuantity",raw.maxQuantity,"float");transport("icon",raw.iconFileID,"integer")
                transport("discovered",raw.discovered,"boolean")
            elseif secret(raw) then
                for _,key in ipairs({"name","quantity","maxQuantity","icon","discovered"})do out.fields[key]="protected" end
            end
        elseif kind=="reputation" then
            local rep=api.C_Reputation or {}
            local raw
            if config.factionID==0 then raw=read(rep.GetWatchedFactionData) else raw=read(rep.GetFactionDataByID,config.factionID) end
            if not accessible(raw) then
                if secret(raw) then for _,key in ipairs({"factionID","name","reaction","currentStanding","currentReactionThreshold","nextReactionThreshold","kind","current","maximum","rewardPending"})do out.fields[key]="protected" end end
                return out
            end
            for key,t in pairs({factionID="integer",name="string",reaction="integer",currentStanding="float",currentReactionThreshold="float",nextReactionThreshold="float"})do transport(key,raw[key],t)end
            local function unavailable(status)
                put("kind","UNKNOWN","string");out.fields.current=status or "unavailable";out.fields.maximum=status or "unavailable"
                return out
            end
            local function delta(value,low,high)
                if secret(low) or secret(high) then out.fields.maximum="protected"
                elseif G.Number(low) and G.Number(high) and high>=low then put("maximum",high-low,"float") end
                if secret(low) or secret(value) then out.fields.current="protected"
                elseif G.Number(low) and G.Number(value) then put("current",value-low,"float") end
            end
            if secret(raw.isHeader) or secret(raw.isHeaderWithRep) then return unavailable("protected") end
            if raw.isHeader==true then
                if raw.isHeaderWithRep==false then put("kind","HEADER","string");return out end
                if raw.isHeaderWithRep~=true then return unavailable() end
            end
            local id,status=field(raw.factionID,"integer")
            if not id or id<1 then return unavailable(status) end
            -- Detection is explicit. An absent/restricted API cannot silently
            -- turn a special reputation into an ordinary reaction bar.
            local paragon,paragonStatus=field(read(rep.IsFactionParagonForCurrentPlayer,id),"boolean")
            if paragon==nil then return unavailable(paragonStatus) end
            if paragon then
                put("kind","PARAGON","string")
                if type(rep.GetFactionParagonInfo)=="function" then
                    local ok,total,threshold,_,pending=pcall(rep.GetFactionParagonInfo,id)
                    if ok then
                        transport("maximum",threshold,"float");transport("rewardPending",pending,"boolean")
                        if secret(total) or secret(threshold) then out.fields.current="protected"
                        elseif G.Number(total) and G.Number(threshold) and threshold>0 then put("current",total%threshold,"float") end
                    end
                end
                return out
            end
            local major,majorStatus=field(read(rep.IsMajorFaction,id),"boolean")
            if major==nil then return unavailable(majorStatus) end
            if major then
                put("kind","RENOWN","string")
                local info=read(api.C_MajorFactions and api.C_MajorFactions.GetMajorFactionData,id)
                if accessible(info) then transport("current",info.renownReputationEarned,"float");transport("maximum",info.renownLevelThreshold,"float")
                elseif secret(info) then out.fields.current="protected";out.fields.maximum="protected" end
                return out
            end
            local friendship=read(api.C_GossipInfo and api.C_GossipInfo.GetFriendshipReputation,id)
            if not accessible(friendship) then return unavailable(secret(friendship) and "protected" or "unavailable") end
            local friend,friendStatus=field(friendship.friendshipFactionID,"integer")
            if friend==nil then return unavailable(friendStatus) end
            if friend>0 then
                put("kind","FRIENDSHIP","string");delta(friendship.standing,friendship.reactionThreshold,friendship.nextThreshold)
            elseif friend==0 then
                put("kind","STANDARD","string");delta(raw.currentStanding,raw.currentReactionThreshold,raw.nextReactionThreshold)
            else return unavailable() end
        elseif kind=="player_state" then
            put("mounted",read(api.IsMounted),"boolean"); put("resting",read(api.IsResting),"boolean")
            put("moving",read(api.IsPlayerMoving),"boolean")
        elseif kind=="location" then
            put("zone",read(api.GetZoneText),"string"); put("subzone",read(api.GetSubZoneText),"string")
            put("mapID",read(api.C_Map and api.C_Map.GetBestMapForUnit,"player"),"integer")
            if api.IsInInstance then
                local ok,inside,instanceType=pcall(api.IsInInstance)
                if ok then put("inInstance",inside,"boolean"); put("instanceType",instanceType,"string") end
            end
        elseif kind=="item_count" then
            put("count",read(api.C_Item and api.C_Item.GetItemCount or api.GetItemCount,config.itemID,false,false,false,false),"integer")
        elseif kind=="item_equipped" then
            put("equipped",read(api.C_Item and api.C_Item.IsEquippedItem or api.IsEquippedItem,config.itemID),"boolean")
        elseif kind=="spell_proc" then
            put("active",read(api.C_SpellActivationOverlay and api.C_SpellActivationOverlay.IsSpellOverlayed or api.IsSpellOverlayed,config.spellID),"boolean")
        elseif kind=="spell_known" then
            -- Explicit player-known semantics, including temporarily granted
            -- spells. Spellbook presence is NOT equivalent to knowing a spell.
            transport("known",read(api.C_SpellBook and api.C_SpellBook.IsSpellKnown,config.spellID),"boolean")
        elseif kind=="spell_usable" then
            local fn=api.C_Spell and api.C_Spell.IsSpellUsable
            if type(fn)=="function" then
                local ok,usable,power=pcall(fn,config.spellID)
                if ok then transport("usable",usable,"boolean");transport("insufficientPower",power,"boolean") end
            end
        elseif kind=="spell_charges" then
            local raw=read(api.C_Spell and api.C_Spell.GetSpellCharges,config.spellID)
            local keys={currentCharges="integer",maxCharges="integer",active="boolean",startTime="float",duration="float",modRate="float"}
            if secret(raw) then for key in pairs(keys) do out.fields[key]="protected" end
            elseif type(raw)=="table" and not getmetatable(raw) and (not api.canaccesstable or api.canaccesstable(raw)) then
                local fields={currentCharges="currentCharges",maxCharges="maxCharges",active="isActive",startTime="cooldownStartTime",duration="cooldownDuration",modRate="chargeModRate"}
                for key,t in pairs(keys) do transport(key,raw[fields[key]],t) end
            end
            -- A separate native object path may remain usable when the scalar
            -- charge table is restricted. Never calculate remaining time here.
            durationObject(api.C_Spell and api.C_Spell.GetSpellChargeDuration,config.spellID)
        elseif kind=="totem" then
            if not G.Number(config.slot) or config.slot~=math.floor(config.slot) or config.slot<1 or config.slot>4 then return out end
            local slots=read(api.GetNumTotemSlots)
            if not secret(slots) and G.Number(slots) and config.slot>slots then return out end
            if type(api.GetTotemInfo)=="function" then
                local ok,present,name,start,duration,icon,rate,spellID=pcall(api.GetTotemInfo,config.slot)
                if ok then
                    transport("present",present,"boolean")
                    if not secret(present) and present==false then
                        for _,key in ipairs({"name","startTime","duration","icon","modRate","spellID","durationObject"}) do out.fields[key]="absent" end
                        return out
                    end
                    transport("name",name,"string");transport("startTime",start,"float");transport("duration",duration,"float")
                    transport("icon",icon,"integer");transport("modRate",rate,"float");transport("spellID",spellID,"integer")
                end
            end
            durationObject(api.GetTotemDuration,config.slot)
        elseif kind=="spell_cooldown" then
            local raw=read(api.C_Spell and api.C_Spell.GetSpellCooldown,config.spellID)
            if secret(raw) then
                for _,key in ipairs({"active","enabled","onGCD"}) do out.fields[key]="protected" end
            elseif type(raw)=="table" and (not api.canaccesstable or api.canaccesstable(raw)) then
                put("active",raw.isActive,"boolean"); put("enabled",raw.isEnabled,"boolean")
                if event=="SPELL_UPDATE_COOLDOWN" then put("onGCD",raw.isOnGCD,"boolean") end
            end
        end
        return out
    end
    function self:Capture(requests,reason,event)
        local out,keys={},{}
        for key in pairs(requests or {}) do keys[#keys+1]=key end
        table.sort(keys);local count=0
        for _,key in ipairs(keys) do
            local request=requests[key]
            if not reason or reason=="initial" or D.reasons[request.kind]==reason then
                count=count+1
                if count<=128 then
                    local ok,observation=pcall(self.Observe,self,request.kind,request.config,event)
                    out[key]=ok and observation or {values={},fields={},status="error"}
                else out[key]={values={},fields={},status="limit"} end
            end
        end
        return out
    end
    return self
end

local _,L=...
if not L.ready then return end
-- Roll data shared by the roll bars, the results and the master loot window.
-- A roll is either "native" (Blizzard group loot, keyed by rollID) or "bv"
-- (a roll request from a master looter, keyed by a session id). Choices come
-- from whichever source the client offers: C_LootHistory (classic or modern
-- shape), chat lines (global strings) and, for BV requests, addon messages
-- plus the native /roll result in the system channel.
local ns=L.ns
local R={rolls={},order={},seq=0,sources={}}
L.Rolls=R

L.OPTIONS={
    need={label=NEED or "Need",texture="Interface\\Buttons\\UI-GroupLoot-Dice-Up",type=1,color={.35,.85,.4}},
    greed={label=GREED or "Greed",texture="Interface\\Buttons\\UI-GroupLoot-Coin-Up",type=2,color={1,.82,.2}},
    disenchant={label=ROLL_DISENCHANT or "Disenchant",texture="Interface\\Buttons\\UI-GroupLoot-DE-Up",type=3,color={.7,.5,1}},
    offspec={label="Off-spec",texture="Interface\\Buttons\\UI-GroupLoot-Dice-Up",tint={.55,.75,1},color={.55,.75,1}},
    pass={label=PASS or "Pass",texture="Interface\\Buttons\\UI-GroupLoot-Pass-Up",type=0,color={.65,.62,.62}},
    -- Master looter's own option: reason text and symbol travel with the request.
    custom={label="Custom",symbol="star",color={.85,.72,1}},
}
L.CUSTOM_SYMBOLS={"star","crown","trophy","gem","shield","swords","sword","heart","flame","sparkles","gift","target","scroll","hammer","coins","skull"}
function L.CleanCustom(label,symbol)
    label=type(label)=="string" and label:gsub("[%c\t|]",""):gsub("^%s+",""):gsub("%s+$","") or ""
    if #label>48 then label=label:sub(1,48) end
    local valid=false
    for _,s in ipairs(L.CUSTOM_SYMBOLS) do if s==symbol then valid=true end end
    return label,valid and symbol or "star"
end
-- Request options with the custom option ranked after `after` ("" = first).
-- Pass always stays last; an unknown anchor falls back to first.
function L.RankCustom(options,after)
    local out={}
    for _,option in ipairs(options) do if option~="custom" then out[#out+1]=option end end
    local at=1
    if after and after~="" then
        for index,option in ipairs(out) do if option==after and option~="pass" then at=index+1 end end
    end
    table.insert(out,at,"custom")
    return out
end
-- Rank choices for the custom option under a preset (dropdown values).
function L.RankChoices(preset)
    local out={{value="",label="Highest"}}
    for _,option in ipairs(L.PRESETS[preset] or L.PRESETS.need_greed) do
        if option~="pass" then out[#out+1]={value=option,label="After "..L.OPTIONS[option].label} end
    end
    return out
end
-- Option definition for a roll: the custom option carries the roll's own text.
function L.OptionDef(roll,option)
    local def=L.OPTIONS[option]
    if option=="custom" and roll and roll.custom then
        return {label=roll.custom.label~="" and roll.custom.label or def.label,symbol=roll.custom.symbol,color=def.color}
    end
    return def
end
L.NATIVE_ORDER={"need","greed","disenchant","pass"}
L.TYPE_OPTION={[0]="pass",[1]="need",[2]="greed",[3]="disenchant"}
L.PRESETS={need_greed={"need","greed","pass"},need_off={"need","offspec","greed","pass"},need={"need","pass"}}
L.PRESET_CHOICES={{value="need_greed",label="Need / Greed / Pass"},{value="need_off",label="Need / Off-spec / Greed / Pass"},{value="need",label="Need / Pass"}}
local function now() return GetTime() end
local function cancel(roll) if roll.timer then roll.timer:Cancel();roll.timer=nil end end

-- Model ----------------------------------------------------------------------
function R:Get(kind,id) return self.rolls[kind..":"..tostring(id)] end
function R:New(kind,id,fields)
    local key=kind..":"..tostring(id)
    if self.rolls[key] then return self.rolls[key],false end
    local roll={key=key,kind=kind,id=id,choices={},names={},started=now(),options=L.NATIVE_ORDER,enabled={},reasons={}}
    for k,v in pairs(fields or {}) do roll[k]=v end
    roll.itemID=roll.itemID or L.ItemID(roll.link)
    self.rolls[key]=roll;self.order[#self.order+1]=roll
    return roll,true
end
function R:List()
    local out={}
    for _,roll in ipairs(self.order) do out[#out+1]=roll end
    return out
end
function R:Changed(roll) L:Emit("RollUpdated",roll) end
function R:SetChoice(roll,name,choice,value,class,source)
    name=L.Short(name)
    if not roll or not name then return end
    if choice and not L.OPTIONS[choice] then return end
    local entry=roll.choices[name]
    if not entry then entry={name=name};roll.choices[name]=entry;roll.names[#roll.names+1]=name end
    if choice then entry.choice=choice end
    if value~=nil then entry.value=tonumber(value) end
    if L.Readable(class) and type(class)=="string" then entry.class=class end
    entry.class=entry.class or L.ClassOf(name)
    if source then self.sources[source]=(self.sources[source] or 0)+1 end
    if name==L.Me() and choice then roll.mine=choice end
    self:Changed(roll)
    if roll.kind=="bv" then self:CheckComplete(roll) end
    return entry
end
function R:Count(roll,choice)
    local n=0
    for _,entry in pairs(roll.choices) do if entry.choice==choice then n=n+1 end end
    return n
end
function R:Players(roll,choice)
    local out={}
    for _,name in ipairs(roll.names) do
        local entry=roll.choices[name]
        if entry.choice==choice then out[#out+1]=entry end
    end
    return out
end
-- Option order is the priority (need before greed ...); within an option the
-- higher roll wins. Passes and missing values go last.
function R:Ranking(roll)
    local priority={}
    for index,option in ipairs(roll.options) do priority[option]=index end
    priority.pass=100
    local list={}
    for _,name in ipairs(roll.names) do local entry=roll.choices[name];if entry.choice or entry.value then list[#list+1]=entry end end
    table.sort(list,function(a,b)
        local pa,pb=priority[a.choice] or 50,priority[b.choice] or 50
        if pa~=pb then return pa<pb end
        local va,vb=a.value or -1,b.value or -1
        if va~=vb then return va>vb end
        return a.name<b.name
    end)
    return list
end
function R:TimeLeft(roll)
    if roll.kind=="native" then
        local ms=L.Call("GetLootRollTimeLeft",roll.id)
        if type(ms)=="number" and not L.Secret(ms) then return math.max(0,ms/1000) end
    end
    return math.max(0,(roll.ends or now())-now())
end
function R:Visible(roll)
    if roll.done then return false end
    local keep=L:Config().rollKeep
    if roll.closed and not keep then return false end
    if roll.kind=="bv" then return roll.target==true and (roll.mine==nil or keep) end
    return true
end
function R:Finish(roll,reason)
    if not roll or roll.done then return end
    roll.done,roll.finished,roll.reason=true,now(),reason
    cancel(roll)
    if not roll.winner and reason~="cancelled" then
        local top=self:Ranking(roll)[1]
        if top and top.choice~="pass" and top.value then roll.winner=top.name end
    end
    if roll.kind=="bv" and roll.owner==L.Me() and reason~="remote" then L.Comm:Send("E",roll.id,roll.winner or "") end
    self:Changed(roll)
    L:Emit("RollFinished",roll)
    self:Prune()
end
-- Finished rolls stay a while for late chat lines, then are forgotten.
function R:Prune()
    local keep={}
    for _,roll in ipairs(self.order) do
        if roll.done and now()-roll.finished>120 then self.rolls[roll.key]=nil else keep[#keep+1]=roll end
    end
    self.order=keep
end
function R:Reset()
    for _,roll in ipairs(self.order) do cancel(roll) end
    for _,timer in pairs(self.retries or {}) do timer:Cancel() end
    self.rolls,self.order,self.retries,self.sources={},{},{},{}
    L:Emit("RollsReset")
end
function R:Expire(roll,delay)
    cancel(roll)
    roll.timer=C_Timer.NewTimer(math.max(.1,delay),function() roll.timer=nil;self:Finish(roll,"timeout") end)
end

-- Native group loot ------------------------------------------------------------
local function reason(code,skill)
    if type(code)~="number" or code==0 or L.Secret(code) then return nil end
    local text=_G["LOOT_ROLL_INELIGIBLE_REASON"..code]
    if type(text)~="string" then return nil end
    return (text:find("%%") and L.Format(text,skill or "")) or text
end
function R:StartNative(rollID,ms,attempt)
    if not L.Readable(rollID) or type(rollID)~="number" then return end
    if self:Get("native",rollID) then return end
    local texture,name,count,quality,bop,canNeed,canGreed,canDE,reasonNeed,reasonGreed,reasonDE,deSkill=L.Call("GetLootRollItemInfo",rollID)
    if not L.Readable(name) then
        -- Item not cached yet: retry a few times, then give up quietly.
        attempt=(attempt or 0)+1
        if attempt<=8 then
            self.retries=self.retries or {}
            if self.retries[rollID] then self.retries[rollID]:Cancel() end
            self.retries[rollID]=C_Timer.NewTimer(.25,function() self.retries[rollID]=nil;self:StartNative(rollID,ms,attempt) end)
        end
        return
    end
    local link=L.Call("GetLootRollItemLink",rollID)
    local duration=(type(ms)=="number" and not L.Secret(ms) and ms>0) and ms/1000 or 60
    local left=L.Call("GetLootRollTimeLeft",rollID)
    if type(left)=="number" and not L.Secret(left) and left>0 then duration=math.max(duration,left/1000) end
    local roll=self:New("native",rollID,{link=link,name=name,icon=texture,count=count,quality=quality,bop=bop==true or bop==1,
        duration=duration,ends=now()+(type(left)=="number" and not L.Secret(left) and left>0 and left/1000 or duration),options=L.NATIVE_ORDER,
        enabled={need=canNeed and true or false,greed=canGreed and true or false,disenchant=canDE and true or false,pass=true},
        reasons={need=reason(reasonNeed,deSkill),greed=reason(reasonGreed,deSkill),disenchant=reason(reasonDE,deSkill)}})
    self:Expire(roll,(roll.ends-now())+8)
    -- Chat lines that arrived before the roll was known (other addons, lag).
    if self.early then
        for _,line in ipairs(self.early) do if line.itemID==roll.itemID then self:Loot(line.text,true) end end
    end
    L:Emit("RollStarted",roll)
    self:Changed(roll)
end
-- Rolls already running when the UI loads (reload during a roll).
function R:Rediscover()
    for id=1,300 do
        local ms=L.Call("GetLootRollTimeLeft",id)
        if type(ms)=="number" and not L.Secret(ms) and ms>0 and ms<600000 then self:StartNative(id,ms) end
    end
end
function R:Choose(roll,option)
    if not roll or roll.done or roll.mine then return false end
    local def=L.OPTIONS[option]
    if not def then return false end
    if roll.kind=="native" then
        if roll.enabled[option]==false or def.type==nil then return false end
        L.Call("RollOnLoot",roll.id,def.type)
        self:SetChoice(roll,L.Me(),option,nil,nil,"self")
    else
        if not roll.target then return false end
        local allowed=false
        for _,o in ipairs(roll.options) do if o==option then allowed=true end end
        if not allowed then return false end
        L.Comm:Send("C",roll.id,option)
        self:SetChoice(roll,L.Me(),option,nil,nil,"self")
        if option~="pass" then roll.awaitingRoll=true;L.Call("RandomRoll",1,100) end
    end
    if not L:Config().rollKeep then roll.closed=true end
    self:Changed(roll)
    return true
end
function R:Cancel(rollID)
    local roll=self:Get("native",rollID)
    if roll and not roll.closed then roll.closed=true;self:Changed(roll) end
end
function R:CancelAll()
    for _,roll in ipairs(self.order) do if roll.kind=="native" and not roll.closed then roll.closed=true;self:Changed(roll) end end
end

-- Chat lines (CHAT_MSG_LOOT). Specific strings before general ones.
local SELF_SELECTED={{"LOOT_ROLL_PASSED_SELF_AUTO","pass"},{"LOOT_ROLL_NEED_SELF","need"},{"LOOT_ROLL_GREED_SELF","greed"},
    {"LOOT_ROLL_DISENCHANT_SELF","disenchant"},{"LOOT_ROLL_PASSED_SELF","pass"}}
local SELECTED={{"LOOT_ROLL_PASSED_AUTO","pass"},{"LOOT_ROLL_PASSED_AUTO_FEMALE","pass"},{"LOOT_ROLL_NEED","need"},
    {"LOOT_ROLL_GREED","greed"},{"LOOT_ROLL_DISENCHANT","disenchant"},{"LOOT_ROLL_PASSED","pass"}}
local ROLLED={{"LOOT_ROLL_ROLLED_NEED_ROLE_BONUS","need"},{"LOOT_ROLL_ROLLED_NEED","need"},{"LOOT_ROLL_ROLLED_GREED","greed"},{"LOOT_ROLL_ROLLED_DE","disenchant"}}
local function who(name)
    if name==nil or name==YOU or name==(YOU and YOU:lower()) then return L.Me() end
    return L.Short(name)
end
-- Open native roll for this item; prefers one where the player has no entry
-- for this stage yet (the same item can drop twice).
function R:FindNative(link,name,stage)
    local id=L.ItemID(link)
    if not id then return nil end
    local fallback
    for _,roll in ipairs(self.order) do
        if roll.kind=="native" and roll.itemID==id and (not roll.done or stage=="won") then
            local entry=name and roll.choices[name]
            local free=not entry or (stage=="choice" and not entry.choice) or (stage=="value" and not entry.value)
            if free and not roll.done then return roll end
            fallback=fallback or roll
        end
    end
    return fallback
end
function R:Loot(text,replay)
    if type(text)~="string" or L.Secret(text) or not text:find("|H",1,true) then return false end
    for _,row in ipairs(SELF_SELECTED) do
        local ok,a=L.Match(_G[row[1]],text)
        if ok then local roll=self:FindNative(a[1],L.Me(),"choice");if roll then self:SetChoice(roll,L.Me(),row[2],nil,nil,"chat") end;return true end
    end
    for _,row in ipairs(ROLLED) do
        local ok,a=L.Match(_G[row[1]],text)
        if ok then
            local name=who(a[3])
            local roll=self:FindNative(a[2],name,"value")
            if roll then self:SetChoice(roll,name,row[2],a[1],nil,"chat") elseif not replay then self:Early(a[2],text) end
            return true
        end
    end
    for _,row in ipairs(SELECTED) do
        local ok,a=L.Match(_G[row[1]],text)
        if ok then
            local name=who(a[1])
            local roll=self:FindNative(a[2],name,"choice")
            if roll then self:SetChoice(roll,name,row[2],nil,nil,"chat") elseif not replay then self:Early(a[2],text) end
            return true
        end
    end
    local ok,a=L.Match(LOOT_ROLL_YOU_WON,text)
    if ok then local roll=self:FindNative(a[1],nil,"won");if roll then roll.winner=L.Me();self:Finish(roll,"won") end;return true end
    ok,a=L.Match(LOOT_ROLL_WON,text)
    if ok then local roll=self:FindNative(a[2],nil,"won");if roll then roll.winner=who(a[1]);self:Finish(roll,"won") end;return true end
    ok,a=L.Match(LOOT_ROLL_ALL_PASSED,text)
    if ok then local roll=self:FindNative(a[1],nil,"won");if roll then roll.allPassed=true;self:Finish(roll,"passed") end;return true end
    return false
end
function R:Early(link,text)
    self.early=self.early or {}
    table.insert(self.early,{itemID=L.ItemID(link),text=text})
    while #self.early>40 do table.remove(self.early,1) end
end

-- C_LootHistory, classic shape (GetItem/GetPlayerInfo per item index).
function R:HistoryChanged(itemIndex,playerIndex)
    local H=C_LootHistory
    if not H or not H.GetItem or not H.GetPlayerInfo then return end
    local ok,rollID=pcall(H.GetItem,itemIndex)
    if not ok or not L.Readable(rollID) then return end
    local roll=self:Get("native",rollID)
    if not roll then return end
    local _,name,class,rollType,value,winner=pcall(H.GetPlayerInfo,itemIndex,playerIndex)
    if not L.Readable(name) then return end
    self:SetChoice(roll,name,L.TYPE_OPTION[rollType],L.Readable(value) and value or nil,class,"history")
    if winner==true then roll.winner=L.Short(name) end
end
function R:HistoryComplete()
    local H=C_LootHistory
    if not H or not H.GetItem or not H.GetNumItems then return end
    local ok,count=pcall(H.GetNumItems)
    if not ok or type(count)~="number" then return end
    for index=1,count do
        local _,rollID,_,players,done,winnerIndex=pcall(H.GetItem,index)
        local roll=L.Readable(rollID) and self:Get("native",rollID)
        if roll and done and not roll.done then
            if winnerIndex and H.GetPlayerInfo then
                local _,name=pcall(H.GetPlayerInfo,index,winnerIndex)
                if L.Readable(name) then roll.winner=L.Short(name) end
            end
            self:Finish(roll,"won")
        end
    end
end
-- C_LootHistory, modern shape (sorted info per encounter drop).
local function modernState(state)
    local e=Enum and Enum.EncounterLootDropRollState
    if not e or type(state)~="number" then return nil end
    if state==e.NeedMainSpec or state==e.NeedOffSpec then return "need" end
    if state==e.Greed or state==e.Transmog then return "greed" end
    if state==e.Pass then return "pass" end
    return nil
end
function R:HistoryDrop(encounterID,lootListID)
    local H=C_LootHistory
    if not H or not H.GetSortedInfoForDrop then return end
    local ok,info=pcall(H.GetSortedInfoForDrop,encounterID,lootListID)
    if not ok or type(info)~="table" then return end
    local roll=self:FindNative(info.itemHyperlink,nil,"won")
    if not roll then return end
    for _,row in ipairs(type(info.rollInfos)=="table" and info.rollInfos or {}) do
        if L.Readable(row.playerName) then
            self:SetChoice(roll,row.playerName,modernState(row.state),L.Readable(row.roll) and row.roll or nil,row.playerClass,"history")
            if row.isWinner then roll.winner=L.Short(row.playerName) end
        end
    end
    if info.winner or info.allPassed then
        if info.allPassed then roll.allPassed=true end
        self:Finish(roll,info.allPassed and "passed" or "won")
    end
end

-- BV roll requests ---------------------------------------------------------------
local function itemString(link)
    if type(link)~="string" then return nil end
    return link:match("|H(item:[^|]+)|h") or link:match("^(item:[%-%d:]+)$")
end
function R:BVFields(link)
    local info=L.Item(link)
    return {link=link,name=info.name,icon=info.icon,quality=info.quality,bop=info.bindType==1}
end
function R:Request(link,players,options,duration,custom)
    local item=itemString(link)
    if not item or type(players)~="table" or #players==0 then return nil,"item and players required" end
    self.seq=self.seq+1
    local sid=(L.Me():gsub("[^%w]",""):sub(1,6))..tostring(math.floor(now())%10000).."-"..self.seq
    options=options or L.PRESETS[L:Config().masterOptions]
    duration=duration or L:Config().masterRollTime
    local fields=self:BVFields(type(link)=="string" and link:find("|H",1,true) and link or item)
    fields.owner,fields.options,fields.duration,fields.ends,fields.targets,fields.targetList=L.Me(),options,duration,now()+duration,{},{}
    for _,name in ipairs(players) do
        name=L.Short(name)
        if name and not fields.targets[name] then fields.targets[name]=true;fields.targetList[#fields.targetList+1]=name end
    end
    fields.target=fields.targets[L.Me()]==true
    for _,option in ipairs(options) do
        if option=="custom" then
            local label,symbol=L.CleanCustom(custom and custom.label,custom and custom.symbol)
            fields.custom={label=label,symbol=symbol}
        end
    end
    local roll=self:New("bv",sid,fields)
    L.Comm:SendRequest(roll,item)
    self:Expire(roll,duration+2)
    L:Emit("RollStarted",roll)
    self:Changed(roll)
    return roll
end
function R:Remote(kind,sender,a,b,c,d,e,f)
    if kind=="Q" then
        if not L:Config().acceptRequests and sender~=L.Me() then return end
        local roll,new=self:New("bv",a,{owner=sender,targets={},targetList={},duration=tonumber(c) or 30})
        if not new then return end
        for k,v in pairs(self:BVFields(b)) do roll[k]=v end
        roll.itemID=L.ItemID(b)
        local options={}
        for option in tostring(d or ""):gmatch("[^,]+") do if L.OPTIONS[option] then options[#options+1]=option end end
        roll.options=#options>0 and options or L.PRESETS.need_greed
        for _,option in ipairs(roll.options) do
            if option=="custom" then local label,symbol=L.CleanCustom(f,e);roll.custom={label=label,symbol=symbol} end
        end
        roll.ends=now()+roll.duration
        self:Expire(roll,roll.duration+3)
        L:Emit("RollStarted",roll)
    elseif kind=="T" then
        local roll=self:Get("bv",a)
        if not roll or roll.owner~=sender or roll.done then return end
        for name in tostring(b or ""):gmatch("[^,]+") do
            if not roll.targets[name] then roll.targets[name]=true;roll.targetList[#roll.targetList+1]=name end
            if name==L.Me() and not roll.target then roll.target=true;L:Emit("RollTargeted",roll) end
        end
        self:Changed(roll)
    elseif kind=="C" then
        local roll=self:Get("bv",a)
        if not roll or roll.done or not roll.targets[sender] then return end
        self:SetChoice(roll,sender,b,nil,nil,"addon")
    elseif kind=="E" then
        local roll=self:Get("bv",a)
        if not roll or roll.owner~=sender or roll.done then return end
        if b and b~="" then roll.winner=b end
        self:Finish(roll,"remote")
    end
end
-- Native /roll results ("%s rolls %d (%d-%d)") answer BV requests.
function R:System(text)
    local ok,a=L.Match(RANDOM_ROLL_RESULT,text)
    if not ok then return false end
    local name,value,low,high=L.Short(a[1]),tonumber(a[2]),tonumber(a[3]),tonumber(a[4])
    if not name or not value or low~=1 or high~=100 then return true end
    for _,roll in ipairs(self.order) do
        local entry=roll.kind=="bv" and not roll.done and roll.choices[name]
        if entry and entry.choice~="pass" and entry.value==nil then self:SetChoice(roll,name,nil,value,nil,"roll");return true end
    end
    -- Targeted players without the addon may answer with a plain /roll.
    for _,roll in ipairs(self.order) do
        if roll.kind=="bv" and not roll.done and roll.targets[name] and not roll.choices[name] then
            local entry=self:SetChoice(roll,name,roll.options[1],value,nil,"roll")
            if entry then entry.manual=true end
            return true
        end
    end
    return true
end
function R:CheckComplete(roll)
    if roll.done or roll.kind~="bv" or not roll.targetList or #roll.targetList==0 then return end
    for _,name in ipairs(roll.targetList) do
        local entry=roll.choices[name]
        if not entry or (entry.choice~="pass" and entry.value==nil) then return end
    end
    if roll.owner==L.Me() or roll.owner==nil then self:Finish(roll,"complete")
    else roll.ends=math.min(roll.ends or now(),now()+3);self:Expire(roll,3) end
end

-- Addon messages ---------------------------------------------------------------------
local C={prefix="BVLoot"}
L.Comm=C
function C:Start(context)
    local chat=C_ChatInfo
    if chat and chat.RegisterAddonMessagePrefix then pcall(chat.RegisterAddonMessagePrefix,self.prefix) end
    context:Subscribe("CHAT_MSG_ADDON",function(_,prefix,text,channel,sender) self:Receive(prefix,text,channel,sender) end)
end
function C:Send(...)
    local parts={...}
    for i=1,#parts do parts[i]=tostring(parts[i]):gsub("\t"," ") end
    local text=table.concat(parts,"\t")
    if L.override.Send then return L.override.Send(text) end
    local channel=L.GroupChannel()
    local chat=C_ChatInfo
    if not channel or not chat or type(chat.SendAddonMessage)~="function" then return false end
    return pcall(chat.SendAddonMessage,self.prefix,text,channel)
end
function C:SendRequest(roll,item)
    local custom=roll.custom
    self:Send("Q",roll.id,item,roll.duration,table.concat(roll.options,","),custom and custom.symbol or "",custom and custom.label or "")
    local chunk={}
    local function flush() if #chunk>0 then self:Send("T",roll.id,table.concat(chunk,","));chunk={} end end
    local size=0
    for _,name in ipairs(roll.targetList) do
        if size+#name>200 then flush();size=0 end
        chunk[#chunk+1]=name;size=size+#name+1
    end
    flush()
end
function C:Receive(prefix,text,_,sender)
    if prefix~=self.prefix or type(text)~="string" or L.Secret(text) or #text>255 then return end
    sender=L.Short(sender)
    if not sender or not L.InGroup(sender) then return end
    -- Explicit split: "x and f() or g()" would keep only the first value.
    local fields={}
    for field in (text.."\t"):gmatch("([^\t]*)\t") do fields[#fields+1]=field end
    local kind=fields[1]
    if kind=="Q" or kind=="T" or kind=="C" or kind=="E" then R:Remote(kind,sender,fields[2],fields[3],fields[4],fields[5],fields[6],fields[7]) end
end

local _,L=...
if not L.ready then return end
-- Simulation mode: drives the real code paths with fake data. Fake roll ids
-- answer through L.override (never by replacing globals), fake players speak
-- through the same chat lines and addon messages the client would deliver,
-- and the master loot window gets a fake loot source. Nothing leaves the
-- client: addon messages loop back locally, awards are only printed.
local ns=L.ns
local R=L.Rolls
local Sim={timers={},native={},nextID=990001}
L.Sim=Sim

-- 39 fake raid members: with you a full 40-player raid.
Sim.ROSTER={{"Thalya","PRIEST"},{"Brokk","WARRIOR"},{"Mirelle","MAGE"},{"Orrin","ROGUE"},{"Kaelis","HUNTER"},{"Vexa","WARLOCK"},
    {"Doran","PALADIN"},{"Sylwen","DRUID"},{"Garrik","WARRIOR"},{"Lunara","PRIEST"},{"Tovan","SHAMAN"},{"Ysolde","MAGE"},
    {"Harn","HUNTER"},{"Ilsa","PRIEST"},{"Mordek","WARLOCK"},{"Petra","ROGUE"},{"Quill","DRUID"},{"Rhea","PALADIN"},
    {"Velyndra","PRIEST"},{"Aldric","WARRIOR"},{"Bryn","ROGUE"},{"Caelum","MAGE"},{"Dagna","SHAMAN"},{"Elowen","DRUID"},
    {"Fenrik","HUNTER"},{"Gwyn","PRIEST"},{"Hollis","WARLOCK"},{"Isolde","PALADIN"},{"Jorund","WARRIOR"},{"Kestra","MAGE"},
    {"Liora","PRIEST"},{"Maelis","ROGUE"},{"Nyx","WARLOCK"},{"Osric","PALADIN"},{"Perrin","HUNTER"},{"Runa","SHAMAN"},
    {"Seren","DRUID"},{"Talos","WARRIOR"},{"Ulla","MAGE"}}
Sim.NO_ADDON="Harn" -- answers requests with a plain /roll only
Sim.ITEMS={
    {19019,"Thunderfury, Blessed Blade of the Windseeker",5,"Interface\\Icons\\INV_Sword_39"},
    {16909,"Bloodfang Pants",4,"Interface\\Icons\\INV_Pants_06"},
    {18832,"Brutality Blade",4,"Interface\\Icons\\INV_Sword_43"},
    {16922,"Leggings of Transcendence",4,"Interface\\Icons\\INV_Pants_08"},
    {18814,"Choker of the Fire Lord",4,"Interface\\Icons\\INV_Jewelry_Necklace_17"},
    {17076,"Bonereaver's Edge",4,"Interface\\Icons\\INV_Axe_09"},
    {13446,"Major Healing Potion",1,"Interface\\Icons\\INV_Potion_54"},
    {14047,"Runecloth",1,"Interface\\Icons\\INV_Fabric_Linen_02"},
}
local HEX={[0]="9d9d9d",[1]="ffffff",[2]="1eff00",[3]="0070dd",[4]="a335ee",[5]="ff8000"}
function Sim.Link(item)
    return string.format("|cff%s|Hitem:%d::::::::60:::::|h[%s]|h|r",HEX[item[3]] or "ffffff",item[1],item[2])
end
local function pick(list,count)
    local copy,out={},{}
    for i,v in ipairs(list) do copy[i]=v end
    for _=1,math.min(count,#copy) do out[#out+1]=table.remove(copy,math.random(1,#copy)) end
    return out
end

function Sim:After(delay,callback)
    local timer
    timer=C_Timer.NewTimer(delay,function()
        for i,t in ipairs(self.timers) do if t==timer then table.remove(self.timers,i);break end end
        if self.active then ns:Call("loot/sim",callback) end
    end)
    self.timers[#self.timers+1]=timer
    return timer
end
function Sim:Install()
    if not L:Active() then L:Print("Turn the loot module on first (/bv loot on).");return false end
    if self.idle then self.idle:Cancel() end
    self.idle=C_Timer.NewTimer(240,function() self.idle=nil;Sim:Stop() end)
    if self.active then return true end
    self.active=true
    L.roster={}
    for _,row in ipairs(self.ROSTER) do L.roster[row[1]]=row[2] end
    local O=L.override
    local function real(name,...) local f=_G[name];if type(f)=="function" then return f(...) end end
    O.GetLootRollItemInfo=function(id)
        local s=Sim.native[id];if not s then return real("GetLootRollItemInfo",id) end
        return s.item[4],s.item[2],1,s.item[3],s.bop,true,true,s.de,0,0,s.de and 0 or 1,0
    end
    O.GetLootRollItemLink=function(id) local s=Sim.native[id];if s then return s.link end;return real("GetLootRollItemLink",id) end
    O.GetLootRollTimeLeft=function(id)
        local s=Sim.native[id];if not s then return real("GetLootRollTimeLeft",id) end
        return math.max(0,(s.ends-GetTime())*1000)
    end
    O.RollOnLoot=function(id,rollType)
        local s=Sim.native[id];if not s then return real("RollOnLoot",id,rollType) end
        s.mine=L.TYPE_OPTION[rollType]
        Sim:After(.2,function() R:Cancel(id) end)
    end
    -- Loopback: every addon message is "received" by this client, like the
    -- echo of a real group message, and fake players react to requests.
    O.Send=function(text)
        Sim:After(.05,function()
            L.Comm:Receive(L.Comm.prefix,text,"RAID",L.Me())
            Sim:React(text)
        end)
        return true
    end
    O.RandomRoll=function(low,high)
        local value=math.random(low or 1,high or 100)
        Sim:After(.4,function() Sim:SystemRoll(L.Me(),value) end)
    end
    return true
end
function Sim:Stop()
    if not self.active then return end
    self.active=false
    for _,timer in ipairs(self.timers) do timer:Cancel() end
    self.timers,self.native={},{}
    if self.idle then self.idle:Cancel();self.idle=nil end
    for key in pairs(L.override) do L.override[key]=nil end
    L.roster=nil
    if self.source then
        self.source=nil
        if L.Master then L.Master.items={};L.Master.selected=nil;L.Master.selection={};L.Master:Refresh() end
    end
end

-- Chat lines from global strings; direct model calls where a string is missing.
function Sim:Chat(key,fallback,...)
    local fmt=_G[key]
    if type(fmt)=="string" then R:Loot(L.Format(fmt,...)) elseif fallback then fallback() end
end
function Sim:SystemRoll(name,value)
    if type(RANDOM_ROLL_RESULT)=="string" then R:System(L.Format(RANDOM_ROLL_RESULT,name,value,1,100))
    else
        for _,roll in ipairs(R:List()) do
            local entry=roll.kind=="bv" and not roll.done and roll.choices[name]
            if entry and entry.choice~="pass" and not entry.value then R:SetChoice(roll,name,nil,value);return end
        end
    end
end

-- Native group loot: three items, fake players choose over ~10 s, the rolls
-- are announced like the client does, then the winner line.
local SELECTED={need="LOOT_ROLL_NEED",greed="LOOT_ROLL_GREED",disenchant="LOOT_ROLL_DISENCHANT",pass="LOOT_ROLL_PASSED"}
local ROLLED={need="LOOT_ROLL_ROLLED_NEED",greed="LOOT_ROLL_ROLLED_GREED",disenchant="LOOT_ROLL_ROLLED_DE"}
function Sim:NativeRolls(count)
    if not self:Install() then return end
    -- Thunderfury first: the client knows it, so its tooltip is always complete.
    local items={self.ITEMS[1]}
    for _,item in ipairs(pick({self.ITEMS[2],self.ITEMS[3],self.ITEMS[4],self.ITEMS[5],self.ITEMS[6]},(count or 3)-1)) do items[#items+1]=item end
    for index,item in ipairs(items) do
        local id=self.nextID;self.nextID=self.nextID+1
        local s={item=item,link=Sim.Link(item),bop=item[3]>=4,de=index~=2,ends=GetTime()+40,choices={}}
        self.native[id]=s
        R:StartNative(id,40000)
        for _,player in ipairs(pick(self.ROSTER,6)) do
            local name=player[1]
            local r=math.random()
            local option=r<.35 and "need" or r<.7 and "greed" or r<.8 and s.de and "disenchant" or "pass"
            s.choices[name]=option
            self:After(1+math.random()*9,function()
                local roll=R:Get("native",id)
                self:Chat(SELECTED[option],function() R:SetChoice(roll,name,option) end,name,s.link)
            end)
        end
        self:After(14+index*2,function() self:ResolveNative(id) end)
    end
    L:Print("Simulating "..(count or 3).." group loot rolls. Click an option on the bars.")
end
function Sim:ResolveNative(id)
    local s=self.native[id];if not s then return end
    local roll=R:Get("native",id)
    if s.mine then s.choices[L.Me()]=s.mine end
    local best,bestPriority,bestValue
    local priority={need=1,greed=2,disenchant=2,pass=9}
    for name,option in pairs(s.choices) do
        if option~="pass" then
            local value=math.random(1,100)
            self:Chat(ROLLED[option],function() R:SetChoice(roll,name,option,value) end,value,s.link,name)
            if not best or priority[option]<bestPriority or priority[option]==bestPriority and value>bestValue then
                best,bestPriority,bestValue=name,priority[option],value
            end
        end
    end
    self:After(.5,function()
        local current=R:Get("native",id)
        if best==L.Me() then self:Chat("LOOT_ROLL_YOU_WON",function() current.winner=best;R:Finish(current,"won") end,s.link)
        elseif best then self:Chat("LOOT_ROLL_WON",function() current.winner=best;R:Finish(current,"won") end,best,s.link)
        else self:Chat("LOOT_ROLL_ALL_PASSED",function() current.allPassed=true;R:Finish(current,"passed") end,s.link) end
        self.native[id]=nil
    end)
end

-- Loot monitor: own loot, stacks, group loot and money.
function Sim:Monitor()
    if not self:Install() then return end
    local M=L.Monitor
    local lines={
        function() return L.Format(LOOT_ITEM_SELF or "You receive loot: %s.",Sim.Link(self.ITEMS[2])) end,
        function() return L.Format(LOOT_ITEM or "%s receives loot: %s.","Thalya",Sim.Link(self.ITEMS[5])) end,
        function() return L.Format(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.",Sim.Link(self.ITEMS[8]),4) end,
        function() return L.Format(LOOT_ITEM or "%s receives loot: %s.","Brokk",Sim.Link(self.ITEMS[6])) end,
        function() return L.Format(LOOT_ITEM_SELF_MULTIPLE or "You receive loot: %sx%d.",Sim.Link(self.ITEMS[8]),2) end,
        function() return L.Format(LOOT_ITEM_SELF or "You receive loot: %s.",Sim.Link(self.ITEMS[1])) end,
    }
    for index,line in ipairs(lines) do self:After(index*.7,function() M:Loot(line()) end) end
    self:After(#lines*.7+.7,function() M:Money(L.Format(YOU_LOOT_MONEY or "You loot %s","12 Gold, 34 Silber, 56 Kupfer")) end)
    L:Print("Simulating loot for you and the group.")
end

-- Fake players answer roll requests that target them.
function Sim:React(text)
    local kind,sid,names=text:match("^(%a)\t([^\t]*)\t?([^\t]*)")
    if kind~="T" then return end
    local roll=R:Get("bv",sid)
    if not roll then return end
    for name in tostring(names):gmatch("[^,]+") do
        if name~=L.Me() and L.roster and L.roster[name] then self:Answer(roll,name) end
    end
end
function Sim:Answer(roll,name)
    local sid=roll.id
    self:After(1.5+math.random()*8,function()
        local current=R:Get("bv",sid)
        if not current or current.done then return end
        if name==self.NO_ADDON then self:SystemRoll(name,math.random(1,100));return end
        local r=math.random()
        local option=r<.2 and "pass" or current.options[math.random(1,math.max(1,#current.options-1))]
        L.Comm:Receive(L.Comm.prefix,"C\t"..sid.."\t"..option,"RAID",name)
        if option~="pass" then self:After(.4,function() self:SystemRoll(name,math.random(1,100)) end) end
    end)
end
-- A fake master looter asks you (and others) to roll.
function Sim:Request()
    if not self:Install() then return end
    local ml="Velyndra"
    local item=self.ITEMS[1]
    local sid="sim"..self.nextID;self.nextID=self.nextID+1
    local itemString=Sim.Link(item):match("|H(item:[^|]+)|h")
    local targets={L.Me()}
    for _,player in ipairs(pick(self.ROSTER,6)) do if player[1]~=ml then targets[#targets+1]=player[1] end end
    local function receive(text) L.Comm:Receive(L.Comm.prefix,text,"RAID",ml) end
    receive("Q\t"..sid.."\t"..itemString.."\t25\tcustom,need,greed,pass\tshield\tTank set")
    receive("T\t"..sid.."\t"..table.concat(targets,","))
    local roll=R:Get("bv",sid)
    if roll then for _,name in ipairs(targets) do if name~=L.Me() then self:Answer(roll,name) end end end
    self:After(26,function()
        local current=R:Get("bv",sid)
        if current and not current.done then
            local top=R:Ranking(current)[1]
            receive("E\t"..sid.."\t"..(top and top.choice~="pass" and top.value and top.name or ""))
        end
    end)
    L:Print(ml.." (simulated master looter) asks you to roll.")
end

-- Master loot window with a fake loot window and fake raid.
local Source={}
function Source:IsOpen() return true end
function Source:Slots() return self.slots end
function Source:Candidates()
    local out={{name=L.Me(),index=1,class=select(2,L.Call("UnitClass","player")) or "WARRIOR"}}
    for index,row in ipairs(Sim.ROSTER) do out[#out+1]={name=row[1],index=index+1,class=row[2]} end
    return out
end
function Source:Award(slot,index,name)
    for i,s in ipairs(self.slots) do
        if s.slot==slot then
            table.remove(self.slots,i)
            L:Print(string.format("Simulated: %s goes to %s (candidate %d). Nothing was handed out.",s.link,name,index))
            return true
        end
    end
    return false,"slot gone"
end
function Sim:Master()
    if not self:Install() then return end
    self.source=setmetatable({slots={}},{__index=Source})
    L.override.IsMasterLooter=function() return true end
    for slot,item in ipairs({self.ITEMS[1],self.ITEMS[2],self.ITEMS[4],self.ITEMS[5]}) do
        self.source.slots[#self.source.slots+1]={slot=slot,link=Sim.Link(item),name=item[2],icon=item[4],quality=item[3],count=1}
    end
    local Master=L.Master
    Master.items,Master.selected,Master.selection={},nil,{}
    Master:LootOpened()
    Master:Open()
    L:Print("Simulated master loot: pick players (e.g. all priests), request a roll, then award.")
end

function Sim:Run(what)
    what=what or ""
    if what=="stop" then self:Stop();L:Print("Simulation stopped.");return end
    if what=="" or what=="roll" or what=="rolls" then self:NativeRolls(3)
    elseif what=="monitor" or what=="loot" then self:Monitor()
    elseif what=="request" then self:Request()
    elseif what=="master" or what=="ml" then self:Master()
    elseif what=="all" then self:NativeRolls(2);self:Monitor();self:After(3,function() Sim:Request() end)
    else L:Print("/bv loot test [roll|monitor|request|master|all|stop]") end
end

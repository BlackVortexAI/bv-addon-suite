-- Graph and block sharing with a chosen player (roadmap P4). Whisper addon
-- messages carry the compressed transfer bytes in chunks. Receiving is off
-- until the player enables it; every offer needs an explicit Accept; received
-- data opens in the normal import preview and is imported only from there.
-- Protocol (tab separated): O id kind parts name | A id | R id reason |
-- C id index data (data may contain tabs) | K id (received) | F id reason.
-- Delivery is never assumed.
local _,A=...
if A.blocked then return end
local Sh={prefix="BVSHARE2",chunk=220,maxChunks=400,timeout=60,pace=.2,offerCooldown=30};A.Share=Sh
local function readable(api,v) return not (api.issecretvalue and api.issecretvalue(v)) end
local function clean(v,max) return type(v)=="string" and #v>0 and #v<=max and not v:find("[%c|]") and v or nil end
-- Same player: realm suffixes may be missing on one side.
local function sameName(a,b)
    if type(a)~="string" or type(b)~="string" then return false end
    a,b=a:lower(),b:lower()
    if a==b then return true end
    if not a:find("-",1,true) or not b:find("-",1,true) then return a:match("^[^%-]+")==b:match("^[^%-]+") end
    return false
end
Sh.SameName=sameName
local function groupUnits(api)
    local out={}
    local raid=api.IsInRaid and api.IsInRaid()
    if raid==true then for i=1,40 do out[#out+1]="raid"..i end
    else for i=1,4 do out[#out+1]="party"..i end end
    return out
end
local function unitName(api,unit)
    local name=api.GetUnitName and api.GetUnitName(unit,true)
    return readable(api,name) and clean(name,96) or nil
end
-- Friendly players in the current party/raid (excluding yourself), sorted by name.
function Sh.GroupMembers(api)
    local out,seen={},{}
    for _,unit in ipairs(groupUnits(api)) do
        local exists=api.UnitExists and api.UnitExists(unit)
        local isPlayer=api.UnitIsPlayer and api.UnitIsPlayer(unit)
        local me=api.UnitIsUnit and api.UnitIsUnit(unit,"player")
        if readable(api,exists) and exists==true and readable(api,isPlayer) and isPlayer==true and not (readable(api,me) and me==true) then
            local name=unitName(api,unit)
            if name and not seen[name:lower()] then seen[name:lower()]=true;out[#out+1]={unit=unit,name=name} end
        end
    end
    table.sort(out,function(a,b) return a.name:lower()<b.name:lower() end)
    return out
end
-- Friends, guild members and group members. Unknown or protected data never
-- counts as known.
function Sh.IsKnown(api,sender)
    for _,m in ipairs(Sh.GroupMembers(api)) do if sameName(m.name,sender) then return true end end
    local friends=api.C_FriendList
    if friends and type(friends.GetNumFriends)=="function" and type(friends.GetFriendInfoByIndex)=="function" then
        local n=friends.GetNumFriends();if readable(api,n) and type(n)=="number" then
            for i=1,math.min(n,200) do local info=friends.GetFriendInfoByIndex(i)
                if type(info)=="table" and readable(api,info.name) and sameName(info.name,sender) then return true end end
        end
    end
    local inGuild=api.IsInGuild and api.IsInGuild()
    if readable(api,inGuild) and inGuild==true and type(api.GetNumGuildMembers)=="function" and type(api.GetGuildRosterInfo)=="function" then
        local n=api.GetNumGuildMembers();if readable(api,n) and type(n)=="number" then
            for i=1,math.min(n,1000) do local name=api.GetGuildRosterInfo(i)
                if readable(api,name) and sameName(name,sender) then return true end end
        end
    end
    return false
end
-- hooks: allowReceive(sender)->true|"disabled"|"restricted", export(kind,id)->text,name,
-- pack(text)->wire, unpack(wire)->text, askAccept(sender,kind,name,parts,accept,decline),
-- review(text,sender,kind,name)->ok,message, status(message)
function Sh.New(api,events,hooks)
    local self={counter=0,lastOffer={}}
    local function now() return api.GetTime() end
    local function status(text) if hooks.status then hooks.status(text) end end
    local function send(target,...)
        local chat=api.C_ChatInfo;if not chat or type(chat.SendAddonMessage)~="function" then return false,"unsupported" end
        local ok,result=pcall(chat.SendAddonMessage,Sh.prefix,table.concat({...},"\t"),"WHISPER",target)
        if not ok or not readable(api,result) then return false,"error" end
        local enum=api.Enum and api.Enum.SendAddonMessageResult
        if enum and result==enum.Success or result==true or result==0 then return true end
        return false,result
    end
    local function stopOut(text)
        local out=self.out;self.out=nil
        if out and out.ticker then out.ticker:Cancel() end
        if out and out.timer then out.timer:Cancel() end
        if text then status(text) end
    end
    local function stopIn()
        local incoming=self.incoming;self.incoming=nil
        if incoming and incoming.timer then incoming.timer:Cancel() end
    end
    local function arm(state,seconds,onTimeout)
        if state.timer then state.timer:Cancel() end
        state.timer=api.C_Timer.NewTimer(seconds,onTimeout)
    end
    function self:Busy() return self.out~=nil end
    -- Sender ------------------------------------------------------------
    -- unit: "target" (default) or a party/raid unit token.
    function self:Send(kind,id,unit)
        unit=unit or "target"
        if self.out then return false,"A share is already in progress" end
        if api.InCombatLockdown() then return false,"Share graphs outside combat" end
        local isPlayer=api.UnitIsPlayer and api.UnitIsPlayer(unit)
        local friendly=api.UnitIsFriend and api.UnitIsFriend("player",unit)
        local me=api.UnitIsUnit and api.UnitIsUnit(unit,"player")
        if not readable(api,isPlayer) or isPlayer~=true or not readable(api,friendly) or friendly~=true or (readable(api,me) and me==true) then
            return false,unit=="target" and "Target a friendly player first" or "Choose a friendly player"
        end
        local target=unitName(api,unit)
        if not target then return false,"Player name unavailable" end
        local ok,text,name=pcall(hooks.export,kind,id)
        if not ok or type(text)~="string" then return false,"Export failed: "..tostring(text) end
        local packed,wire=pcall(hooks.pack,text)
        if not packed or type(wire)~="string" then return false,"Export failed: "..tostring(wire) end
        local parts=math.max(1,math.ceil(#wire/Sh.chunk))
        if parts>Sh.maxChunks then return false,"Too large to share ("..parts.." parts)" end
        self.counter=self.counter+1
        local token=string.format("%x%x",math.floor(now()*1000)%0x7fffffff,self.counter)
        local label=(clean(name,40) or "Shared"):gsub("\t"," ")
        local sent,why=send(target,"O",token,kind,tostring(parts),label)
        if not sent then return false,"Could not send: "..tostring(why) end
        self.out={id=token,target=target,text=wire,parts=parts,next=1,name=label,kind=kind}
        arm(self.out,Sh.timeout,function() stopOut("No answer from "..target) end)
        status("Offer sent to "..target.." – waiting for Accept")
        return true
    end
    function self:Cancel() if self.out then stopOut("Share cancelled") end end
    local function pump()
        local out=self.out;if not out then return end
        local index=out.next;local data=out.text:sub((index-1)*Sh.chunk+1,index*Sh.chunk)
        local sent=send(out.target,"C",out.id,tostring(index),data)
        if not sent then return end -- throttled: retry the same part next tick
        out.next=index+1
        if out.next>out.parts then
            out.ticker:Cancel();out.ticker=nil
            status("Sent "..out.parts.." parts to "..out.target.." – waiting for confirmation")
            arm(out,Sh.timeout,function() stopOut("No confirmation from "..out.target) end)
        end
    end
    -- Receiver ----------------------------------------------------------
    local function offer(sender,token,kind,parts,name)
        parts=tonumber(parts)
        if not clean(token,16) or (kind~="graph" and kind~="block") or not parts or parts<1 or parts>Sh.maxChunks or parts~=math.floor(parts) or not clean(name,40) then return end
        local key=sender:lower();local last=self.lastOffer[key]
        if last and now()-last<Sh.offerCooldown then return end -- silent spam protection
        self.lastOffer[key]=now()
        local allowed=hooks.allowReceive(sender)
        if allowed~=true then send(sender,"R",token,allowed=="restricted" and "restricted" or "disabled");return end
        if self.incoming or api.InCombatLockdown() then send(sender,"R",token,"busy");return end
        local state={id=token,sender=sender,parts=parts,chunks={},received=0,kind=kind,name=name}
        self.incoming=state
        arm(state,Sh.timeout,function() if self.incoming==state then stopIn();status("Share from "..sender.." timed out") end end)
        hooks.askAccept(sender,kind,name,parts,function()
            if self.incoming~=state then return end
            send(sender,"A",token);status("Receiving "..name.." from "..sender)
            arm(state,Sh.timeout,function() if self.incoming==state then stopIn();status("Share from "..sender.." timed out") end end)
        end,function()
            if self.incoming~=state then return end
            stopIn();send(sender,"R",token,"declined")
        end)
    end
    local function chunk(sender,token,index,data)
        local state=self.incoming
        if not state or state.id~=token or not sameName(sender,state.sender) then return end
        index=tonumber(index)
        if not index or index<1 or index>state.parts or index~=math.floor(index) or type(data)~="string" or #data>Sh.chunk then return end
        if not state.chunks[index] then state.chunks[index]=data;state.received=state.received+1 end
        arm(state,Sh.timeout,function() if self.incoming==state then stopIn();status("Share from "..state.sender.." timed out") end end)
        if state.received<state.parts then return end
        stopIn()
        local ok,result,message=pcall(function()
            local text=hooks.unpack(table.concat(state.chunks))
            return hooks.review(text,sender,state.kind,state.name)
        end)
        if ok and result then send(sender,"K",token);status("Received "..state.name.." from "..sender.." – review the preview to import")
        else
            local why=tostring(ok and message or result):sub(1,60):gsub("[\t%c|]"," ")
            send(sender,"F",token,why);status("Share from "..sender.." rejected: "..why)
        end
    end
    function self:Receive(prefix,text,channel,sender)
        if not readable(api,prefix) or prefix~=Sh.prefix or not readable(api,channel) or channel~="WHISPER" then return end
        if not readable(api,text) or not readable(api,sender) or type(text)~="string" or not clean(sender,96) then return end
        local kind=text:sub(1,2)
        if kind=="C\t" then
            local token,index,data=text:match("^C\t([^\t]*)\t(%d+)\t(.*)$")
            if token then chunk(sender,token,index,data) end
            return
        end
        local fields={};for part in (text.."\t"):gmatch("([^\t]*)\t") do fields[#fields+1]=part end
        kind=fields[1]
        if kind=="O" then offer(sender,fields[2],fields[3],fields[4],fields[5]) return end
        local out=self.out
        if not out or out.id~=fields[2] or not sameName(sender,out.target) then return end
        if kind=="A" and not out.ticker and out.next==1 then
            if out.timer then out.timer:Cancel();out.timer=nil end
            status("Sending "..out.name.." to "..out.target)
            out.ticker=api.C_Timer.NewTicker(Sh.pace,pump);pump()
        elseif kind=="R" then
            local why=fields[3]=="disabled" and "has receiving turned off" or fields[3]=="restricted" and "only accepts shares from friends, guild or group"
                or fields[3]=="busy" and "is busy" or "declined"
            stopOut(out.target.." "..why)
        elseif kind=="K" then stopOut(out.target.." received "..out.name.." and can import it")
        elseif kind=="F" then stopOut(out.target.." could not import: "..tostring(clean(fields[3] or "",60) or "error")) end
    end
    function self:Start()
        local chat=api.C_ChatInfo
        if not chat or type(chat.RegisterAddonMessagePrefix)~="function" then return false,"unsupported" end
        pcall(chat.RegisterAddonMessagePrefix,Sh.prefix)
        events:Release(self)
        events:Subscribe(self,"CHAT_MSG_ADDON",function(_,...) self:Receive(...) end)
        return true
    end
    function self:Stop() events:Release(self);stopOut();stopIn() end
    return self
end

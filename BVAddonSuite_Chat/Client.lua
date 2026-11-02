local _, Chat = ...
local core = Chat.core
if not core then return end

local eventSources = {
    SAY="SAY", YELL="YELL", GUILD="GUILD", OFFICER="OFFICER", PARTY="PARTY", PARTY_LEADER="PARTY",
    RAID="RAID", RAID_LEADER="RAID", RAID_WARNING="RAID", INSTANCE_CHAT="INSTANCE_CHAT",
    INSTANCE_CHAT_LEADER="INSTANCE_CHAT", WHISPER="WHISPER", WHISPER_INFORM="WHISPER",
    SYSTEM="SYSTEM", CHANNEL="WORLD",
}
-- ChatFrame:AddMessage uses ChatTypeInfo ids as its fifth argument. Keep
-- native-only output (loot, achievements, NPCs, /who results, addon prints)
-- in the mix, without also recording the formatted copy of a tracked event.
local eventTypeIDs = {}
function Chat:RefreshEventTypeIDs()
    eventTypeIDs = {}
    for kind, info in pairs(ChatTypeInfo or {}) do
        if type(kind)=="string" and type(info)=="table" and info.id and
            (eventSources[kind] or kind:match("^CHANNEL%d+$")) then
            eventTypeIDs[info.id]=true
        end
    end
end
function Chat:HasMessageEvent(typeID, event)
    if self.text(event) and event:sub(1,9)=="CHAT_MSG_" then
        return eventSources[event:sub(10)]~=nil
    end
    return typeID~=nil and eventTypeIDs[typeID]
end
local function safeCall(fn,...)
    if type(fn)~="function" then return end
    local ok, value = pcall(fn,...)
    if ok and Chat.readable(value) then return value end
end
local function unitName(unit)
    if not UnitName then return end
    local ok,name,realm = pcall(UnitName,unit)
    if not ok or not Chat.person(name) then return end
    if Chat.text(realm) then return Chat.person(name.."-"..realm) end
    return name
end

local function boundedCount(value,limit)
    return Chat.readable(value) and type(value)=="number" and value==value and math.max(0,math.min(limit,math.floor(value))) or 0
end
-- Relationship lookups during filtering/rendering only access these caches.
-- Rebuild on roster events, never for each row or each autocomplete keypress.
function Chat:RefreshFriends()
    local cache={}
    local api=C_FriendList
    local count=boundedCount(safeCall(api and api.GetNumFriends or GetNumFriends),200)
    for i=1,count do
        local info=safeCall(api and api.GetFriendInfoByIndex or GetFriendInfo,i)
        local name=Chat.person(type(info)=="table" and info.name or info)
        if name then cache[Chat:Key(name)]=name end
    end
    Chat.friend=cache
    Chat:QueueAllWindows()
end
function Chat:RefreshGuild()
    local cache={}
    -- A stale server roster after leaving a guild must not match new messages.
    if safeCall(IsInGuild)==true then
        local count=boundedCount(safeCall(GetNumGuildMembers),1000)
        for i=1,count do
            local name=Chat.person(safeCall(GetGuildRosterInfo,i))
            if name then cache[Chat:Key(name)]=name end
        end
    end
    Chat.guild=cache
    Chat:QueueAllWindows()
end

function Chat:Roster()
    self.realm = (self.text(safeCall(GetNormalizedRealmName)) or ""):lower()
    self.party, self.raid, self.unitClasses = {}, {}, {}
    local function rememberClass(unit,key)
        if not key or not UnitClass then return end
        local ok,_,token=pcall(UnitClass,unit)
        if ok then self.unitClasses[key]=self.text(token) end
    end
    local own = unitName("player")
    self.me = own and self:Key(own)
    rememberClass("player",self.me)
    local count = boundedCount(safeCall(GetNumGroupMembers),40)
    local inRaid = safeCall(IsInRaid)
    local subgroup, members = nil, {}
    for i=1,math.min(count,40) do
        local unit = (inRaid and "raid" or "party")..i
        local name = unitName(unit)
        if name then
            local key = self:Key(name)
            rememberClass(unit,key)
            if inRaid then
                local ok,_,_,group = pcall(GetRaidRosterInfo,i)
                if ok and self.readable(group) and type(group)=="number" then members[key]=group end
                self.raid[key]=name
                if key==self.me then subgroup=members[key] end
            else self.party[key]=name end
        end
    end
    if subgroup then
        for key,group in pairs(members) do if group==subgroup then self.party[key]=self.raid[key] end end
    end
    self:QueueAllWindows()
end

function Chat:Suggestions(prefix)
    local result, seen = {}, {}
    prefix=prefix:lower()
    local function offer(name)
        if #result>=8 or not Chat.person(name) then return end
        local key=Chat:Key(name)
        if key~=Chat.me and not seen[key] and key:sub(1,#prefix)==prefix then
            seen[key]=true
            result[#result+1]=name
        end
    end
    for _,name in ipairs(self:Conversations(prefix)) do offer(name) end
    for _,team in ipairs({self.party or {},self.raid or {},self.friend or {},self.guild or {}}) do
        local names={}
        for _,name in pairs(team) do names[#names+1]=name end
        table.sort(names)
        for _,name in ipairs(names) do offer(name) end
    end
    -- Public authors only after contacts and recent private conversations.
    if #result<8 then
        local rows=self:Rows(function(row) return row.author~=nil and row.source~="WHISPER" end)
        for i=#rows,1,-1 do offer(rows[i].author); if #result>=8 then break end end
    end
    return result
end

local function tradeChannel(name)
    local value=name:lower()
    return value=="trade" or value=="handel" or value:match("^trade %-") or value:match("^handel %-")
end
local knownChannels={}

-- A zone-qualified display name may vary while traveling. Strip the zone
-- only when the game confirms that the base name addresses the same slot.
local function joinedName(id,name)
    local base=name:match("^(.-) %- .+$")
    if base and GetChannelName and safeCall(GetChannelName,base)==id then return base end
    return name
end
function Chat:Joined()
    local result,seen={},{}
    local function add(id,name,disabled)
        if not self.readable(id) or type(id)~="number" or id<=0 or not self.text(name) then return end
        name=joinedName(id,name)
        local key=self.channelKey(name)
        if seen[key] then return end
        seen[key]=true
        local source=knownChannels[key] and knownChannels[key].source or (tradeChannel(name) and "TRADE" or "WORLD")
        local entry={id=id,name=name,key=key,source=source,joined=true,disabled=not self.readable(disabled) or disabled==true}
        result[#result+1]=entry
        knownChannels[key]=entry
    end
    if GetChannelList then
        local list={pcall(GetChannelList)}
        if list[1] then for i=2,#list,3 do add(list[i],list[i+1],list[i+2]) end end
    elseif GetNumDisplayChannels and GetChannelDisplayInfo then
        local count=safeCall(GetNumDisplayChannels) or 0
        for i=1,count do
            local ok,name,header,_,id,_,active=pcall(GetChannelDisplayInfo,i)
            if ok and self.readable(header) and not header then add(id,name,not self.readable(active) or not active) end
        end
    elseif GetChannelName then
        local max=Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatChannels or 20
        for slot=1,max do
            local ok,id,name=pcall(GetChannelName,slot)
            if ok then add(id,name,false) end
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end

-- The settings editor can still remove a previously selected channel after
-- leaving it. Only live memberships receive a slot or appear as send targets.
function Chat:ChannelChoices(draftSources)
    local channels=self:Joined()
    local seen,offline={},{}
    for _,entry in ipairs(channels) do seen[entry.key]=true end
    local function saved(entries)
        for key in pairs(entries or {}) do
            if type(key)=="string" and key:sub(1,1)=="#" and not seen[key] then
                seen[key]=true
                local previous=knownChannels[key]
                local name=previous and previous.name or key:sub(2)
                offline[#offline+1]={key=key,name=name,joined=false,
                    source=previous and previous.source or (tradeChannel(name) and "TRADE" or "WORLD")}
            end
        end
    end
    local cfg=self:Config()
    saved(draftSources)
    for _,view in ipairs(cfg.views) do saved(view.sources) end
    table.sort(offline,function(a,b) return a.key<b.key end)
    for _,entry in ipairs(offline) do channels[#channels+1]=entry end
    return channels
end

local channelAliases={
    SAY={"s","say"},YELL={"y","yell","sh","shout"},PARTY={"p","party"},RAID={"ra","raid"},
    GUILD={"g","guild"},OFFICER={"o","officer"},INSTANCE_CHAT={"i","instance"},
}
local function builtInAvailable(key)
    if key=="SAY" or key=="YELL" then return true end
    if key=="PARTY" or key=="RAID" then
        local member=IsInGroup
        if key=="RAID" then member=IsInRaid end
        if LE_PARTY_CATEGORY_HOME then return safeCall(member,LE_PARTY_CATEGORY_HOME)==true end
        return safeCall(member)==true
    end
    if key=="INSTANCE_CHAT" then
        return LE_PARTY_CATEGORY_INSTANCE and safeCall(IsInGroup,LE_PARTY_CATEGORY_INSTANCE)==true
    end
    if key=="OFFICER" or key=="GUILD" then
        if safeCall(IsInGuild)~=true then return false end
        if key=="OFFICER" then
            local officer=C_GuildInfo and C_GuildInfo.IsGuildOfficer or IsGuildOfficer
            return not officer or safeCall(officer)==true
        end
        local speak=C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat
        return not speak or safeCall(speak)==true
    end
    return false
end

function Chat:Targets()
    local targets={}
    for _,s in ipairs(self.sources) do
        local key=s[1]
        if builtInAvailable(key) then
            targets[#targets+1]={value=key,label=s[2]}
        end
    end
    for _,ch in ipairs(self:Joined()) do
        if not ch.disabled then targets[#targets+1]={value=ch.key,label=ch.name,number=ch.id} end
    end
    return targets
end
function Chat:AllowsTarget(target)
    for _,item in ipairs(self:Targets()) do if item.value==target then return item end end
end

function Chat:RefreshTargetLabel()
    self.targetLabel=nil
    if self.target and self.target:sub(1,1)=="#" then
        local joined=self:AllowsTarget(self.target)
        self.targetLabel=joined and (joined.number..". "..joined.label) or self.target:sub(2)
    end
end

function Chat:SelectDestination(key,body)
    if not self:HasComposer() or not self.input then return false end
    if channelAliases[key] and not builtInAvailable(key) then
        self:Notice((self.labels[key] or key).." is unavailable. Your draft is kept.")
        return false
    end
    self.input:SetText("")
    self:Switch(nil,key)
    if body~="" then self.input:SetText(body) end
    self.input:SetCursorPosition(#self.input:GetText())
    if not self.input:HasFocus() then self.input:SetFocus() end
    return true
end

-- Match the client's own localized channel commands. An incomplete token
-- stays in the BV editor until it resolves, e.g. /r -> /ra or /reload.
local aliases,prefixes
function Chat:ChannelAlias(token)
    if not aliases then
        aliases,prefixes={},{}
        local function add(name,key)
            name=name:gsub("^/",""):lower()
            aliases[name]=key
            for i=1,#name-1 do prefixes[name:sub(1,i)]=true end
        end
        for key,fallbacks in pairs(channelAliases) do
            local prefix="SLASH_"..key
            if type(_G[prefix.."1"])=="string" then
                local i=1
                while type(_G[prefix..i])=="string" do add(_G[prefix..i],key);i=i+1 end
            else
                for _,name in ipairs(fallbacks) do add(name,key) end
            end
        end
    end
    return aliases[token],prefixes[token]
end

-- Resolve numbered slots only at selection/send time. Channel numbers can
-- change after a reconnect, while the joined name identifies the destination.
function Chat:SelectNumberedChannel(slot,body)
    if not self:HasComposer() or not self.input then return false end
    for _,ch in ipairs(self:Joined()) do
        if ch.id==tonumber(slot) then
            if ch.disabled then self:Notice(ch.name.." is unavailable here."); return false end
            return self:SelectDestination(ch.key,body)
        end
    end
    self:Notice("You have not joined channel "..slot..".")
    return false
end

Chat.replyKeys={r="lastIn",reply="lastIn",rr="lastOut",raus="lastOut",lastw="lastPeer"}
function Chat:ReplyTarget(command)
    return Chat[Chat.replyKeys[command]]
end
function Chat:Submit()
    if not self:HasComposer() or not self.input or self.nativeOverrideCaption then return end
    local text=self.input:GetText()
    if not self.text(text) or not text:find("%S") then return end
    local cmd,rest=text:match("^/(%S+)%s*(.*)$")
    local recipient=self.whisperTarget
    if cmd then
        cmd=cmd:lower()
        local builtIn=self:ChannelAlias(cmd)
        if cmd:match("^%d+$") then
            if not self:SelectNumberedChannel(cmd,rest) or rest=="" then return end
            recipient=nil
            text=rest
            cmd=nil
        elseif Chat.replyKeys[cmd] then
            recipient=self:ReplyTarget(cmd)
            if not recipient then return self:Notice("No previous whisper for that shortcut.") end
            text=rest
        elseif cmd=="w" or cmd=="whisper" or cmd=="tell" then
            recipient,text=rest:match("^(%S+)%s*(.*)$")
            if not self.person(recipient) then return self:Notice("Type /w followed by a name.") end
        elseif builtIn then
            if not self:SelectDestination(builtIn,rest) or rest=="" then return end
            recipient=nil
            text=rest
            cmd=nil
        else return self:NativeCommand(text) end
        if text=="" then
            self.input:SetText("")
            self:SetAddress(recipient)
            self.input:SetFocus()
            return
        end
    end
    if #text>255 then return self:Notice("Message exceeds 255 bytes. Your draft is kept.") end
    local channel,target
    if recipient then channel,target="WHISPER",recipient
    else
        local item=self:AllowsTarget(self.target)
        if not item then return self:Notice("Choose an available destination beside the input.") end
        channel=item.number and "CHANNEL" or item.value
        target=item.number
    end
    local api=C_ChatInfo
    if api and api.InChatMessagingLockdown and safeCall(api.InChatMessagingLockdown)~=false then
        return self:Notice("Chat is restricted. Your draft is kept.")
    end
    local send=api and api.SendChatMessage or SendChatMessage
    local ok,result=pcall(send,text,channel,nil,target)
    if not ok or not self.readable(result) or result==false then return self:Notice("Could not send. Your draft is kept.") end
    self.input:SetText("")
    if not recipient then self:Config().lastDestination=self.target end
    if cmd then self:SetAddress(recipient) end
    self.input:ClearFocus()
    self:Notice("Submitted to "..(recipient or self.labels[channel] or self.target))
end

local function displayedClass(author,guid,inform)
    local key=Chat:Key(author)
    local roster=Chat.unitClasses and Chat.unitClasses[key]
    if roster then return roster end
    if not (GetPlayerInfoByGUID and Chat.text(guid) and guid:match("^Player%-")) then return end
    local ok,_,token,_,_,_,name,realm=pcall(GetPlayerInfoByGUID,guid)
    if not ok or not Chat.text(token) then return end
    -- Some clients report our own GUID on WHISPER_INFORM. The displayed
    -- name is the recipient; only apply a class for a confirmed identity.
    if Chat.person(name) and Chat.readable(realm) then
        local full=Chat.text(realm) and (name.."-"..realm) or name
        if Chat:Key(full)==key then return token end
    elseif not inform and Chat.readable(name) and not Chat.text(name) then
        return token
    end
end
local function incoming(event,body,author,_,displayName,_,_,zoneID,slot,baseName,_,_,guid)
    if not Chat.text(body) then return end
    local kind=event:sub(10)
    local source=eventSources[kind]
    local channel
    if kind=="CHANNEL" then
        channel=Chat.text(baseName)
        if not channel and Chat.readable(slot) and type(slot)=="number" then
            for _,joined in ipairs(Chat:Joined()) do if joined.id==slot then channel=joined.name;break end end
        end
        if not channel and Chat.text(displayName) then channel=displayName:gsub("^%d+%.%s*","") end
        if not channel then return end
        if Chat.readable(zoneID) and type(zoneID)=="number" and zoneID>0 then
            channel=channel:match("^(.-) %- .+$") or channel
        end
        if Chat.readable(zoneID) and zoneID==2 or tradeChannel(channel) then
            source="TRADE"
            local key=Chat.channelKey(channel)
            if not knownChannels[key] or knownChannels[key].source~=source then knownChannels[key]={name=channel,source=source} end
        end
    end
    author=Chat.person(author)
    if source=="WHISPER" and not author then return end
    local outgoing=kind=="WHISPER_INFORM" or author and Chat:Key(author)==Chat.me
    local token=author and source~="SYSTEM" and displayedClass(author,guid,kind=="WHISPER_INFORM") or nil
    local row=Chat:Add(source,author,body,outgoing,channel,zoneID,token)
    if row then
        row.kind=kind
        if kind=="CHANNEL" and Chat.readable(slot) and type(slot)=="number" and slot>=1 and slot<=20 and slot==math.floor(slot) then row.channelSlot=slot end
    end
end

local function enable(context)
    Chat:Reset()
    Chat.running=true
    context:Defer(function()
        local writer=Chat:GetComposerWindow()
        Chat.bridge:CloseWorkspace(writer)
        writer:ReleaseComposer()
        Chat.running=false
        Chat.bridge:SetActive(false)
        Chat:SyncWindows()
        Chat.nativeSource=nil
        if Chat.window then Chat.window:Hide() end
        if Chat.input then Chat.input:SetText(""); Chat.input.bvHistory={} end
        if Chat.copyBox then Chat.copyBox:SetText("") end
        Chat:Reset()
    end)
    Chat:Roster()
    Chat:RefreshFriends()
    Chat:RefreshGuild()
    for suffix in pairs(eventSources) do
        pcall(context.Subscribe,context,"CHAT_MSG_"..suffix,incoming)
    end
    context:Subscribe("GROUP_ROSTER_UPDATE",function() Chat:Roster() end)
    context:Subscribe("FRIENDLIST_UPDATE",function() Chat:RefreshFriends() end)
    context:Subscribe("GUILD_ROSTER_UPDATE",function() Chat:RefreshGuild() end)
    context:Subscribe("PLAYER_GUILD_UPDATE",function()
        Chat:RefreshGuild()
        if safeCall(IsInGuild)==true then safeCall(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster) end
    end)
    if safeCall(IsInGuild)==true then safeCall(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster) end
    pcall(context.Subscribe,context,"COMBAT_LOG_MESSAGE",function(_,body,_,_,_,order)
        local oldest=Enum and Enum.CombatLogMessageOrder and Enum.CombatLogMessageOrder.Oldest
        if not Chat.readable(order) or oldest~=nil and order==oldest then return end
        Chat.seenCombat=true
        Chat:Add("COMBAT",nil,body)
    end)
    Chat:Config().shown=nil
    local last=Chat:Config().lastDestination
    Chat.target=last or (Chat:AllowsTarget("SAY") and "SAY" or nil)
    Chat:RefreshTargetLabel()
    local function channelsChanged()
        for _,workspace in ipairs(Chat:ListWindows()) do
            if workspace.running then
                workspace:RefreshTargetLabel()
                if workspace.ruleWindow and workspace.ruleWindow:IsShown() and workspace.RefreshChannelChoices then
                    workspace:RefreshChannelChoices()
                end
                workspace:QueuePaint()
            end
        end
    end
    context:Subscribe("CHANNEL_UI_UPDATE",channelsChanged)
    context:Subscribe("CHAT_MSG_CHANNEL_NOTICE",function(_,notice)
        if Chat.readable(notice) and (notice=="YOU_JOINED" or notice=="YOU_LEFT" or notice=="YOU_CHANGED") then
            channelsChanged()
        end
    end)
    Chat:EnsureWorkspace()
    local function refreshCaptions()
        for _,workspace in ipairs(Chat:ListWindows()) do
            if workspace.running then workspace:RefreshLoadedCaptions() end
        end
    end
    refreshCaptions()
    context:Subscribe("PLAYER_ENTERING_WORLD",function()
        Chat:Roster(); Chat:RefreshFriends(); Chat:RefreshGuild(); Chat:EnsureWorkspace()
        refreshCaptions()
    end)
    pcall(context.Subscribe,context,"LOADING_SCREEN_DISABLED",refreshCaptions)
end
function Chat:EnsureWorkspace()
    if not self.running then return end
    self:Show()
    if self.window and self.window:IsShown() and not self.bridge.active then
        self.bridge:SetActive(true)
    end
    if self==Chat then Chat:SyncWindows() end
end
core.Modules:Register({id="chat",OnEnable=enable})
function Chat:Open()
    if not self.running then core.Modules:SetEnabled("chat",true) end
    self:EnsureWorkspace()
end
SLASH_BVCHAT1="/bvchat"
SlashCmdList.BVCHAT=function(args)
    local command=(Chat.text(args) or ""):lower():match("^%s*(.-)%s*$")
    if command=="test off" then Chat:SetChatPreview(false);return end
    Chat:Open()
    if command=="test" or command=="test on" then Chat:SetChatPreview(true) end
end
function Chat:Reply(outgoing)
    if not self.running then
        local api=ChatFrameUtil or {}
        local reply=outgoing and (api.ReplyTell2 or ChatFrame_ReplyTell2) or (api.ReplyTell or ChatFrame_ReplyTell)
        if self.bridge.pending and reply then reply(DEFAULT_CHAT_FRAME) end
        return
    end
    self=Chat:GetComposerWindow()
    self:EnsureWorkspace()
    if not self.input then return end
    local name
    if outgoing then name=self.lastOut else name=self.lastIn end
    if name then self:SetAddress(name); self.input:SetFocus()
    else self:Notice("No previous whisper for that shortcut.") end
end
BINDING_HEADER_BVCHAT="BV Chat"
BINDING_NAME_BVCHAT_OPEN="Open chat and type"
BINDING_NAME_BVCHAT_SLASH="Open command entry"
BINDING_NAME_BVCHAT_REPLY="Reply to last incoming whisper"
BINDING_NAME_BVCHAT_LASTOUT="Whisper last outgoing recipient"

local package, Chat = ...
local core = BVAddonSuiteCore
if not core or not core.RequireCore or not core:RequireCore(package, "0.1.18", "0.8.116", 1) then return end
Chat.core = core
core.Chat = Chat

Chat.sources = {
    {"SAY","Say"}, {"YELL","Yell"}, {"GUILD","Guild"}, {"OFFICER","Officers"},
    {"PARTY","Party"}, {"RAID","Raid"}, {"INSTANCE_CHAT","Instance"}, {"WORLD","Public channels"},
    {"TRADE","Trade"}, {"SYSTEM","System"}, {"COMBAT","Combat log"},
}
Chat.labels = {WHISPER="Whisper"}
for _, source in ipairs(Chat.sources) do Chat.labels[source[1]] = source[2] end

-- The root stays the main window's settings for existing profiles. Secondary
-- windows are keyed by stable IDs; hiding or renaming never changes anchors.
local function profile()
    local cfg=core.Settings:Module("chat")
    if not cfg.windows then
        cfg.windows={}
        if cfg.secondWindow or cfg.secondEnabled then
            local saved=cfg.secondWindow or {}
            saved.visible=cfg.secondEnabled==true
            cfg.windows[2]=saved
        end
        cfg.secondWindow,cfg.secondEnabled=nil,nil
    end
    return cfg
end
function Chat:WindowID() return self==Chat and 1 or self.id end
Chat.defaultMessageColors={time="aa9e91",channel="ead689",sender="e6ded1",message="eee7dc"}
function Chat:MessageStyle()
    local root=profile()
    if not root.messageStyle then
        local colors={}
        for role,hex in pairs(Chat.defaultMessageColors) do colors[role]=hex end
        root.messageStyle={colors=colors,timeFormat=root.times==false and "off" or "short",channelMode="full",channelModes={}}
    end
    root.messageStyle.channelModes=root.messageStyle.channelModes or {}
    root.messageStyle.sourceColors=root.messageStyle.sourceColors or {}
    if root.messageStyle.classNames==nil then root.messageStyle.classNames=true end
    return root.messageStyle
end
function Chat:SenderRules()
    local style=self:MessageStyle()
    if not style.senderRules then
        style.senderRules={}
        for _,key in ipairs({"friend","guild","party","raid"}) do
            style.senderRules[#style.senderRules+1]={key=key,enabled=false,scope="WHISPER",tint="e4bd6080",target="sender"}
        end
    end
    return style.senderRules
end
function Chat:Config()
    local root=profile()
    local cfg=self==Chat and root or assert(root.windows[self.id],"unknown chat window")
    if self~=Chat and not cfg.views then
        cfg.views={
            {name="Group",sources={PARTY=true,RAID=true,INSTANCE_CHAT=true},active=true},
            {name="Whispers",sources={},scope="all",active=true},
        }
    end
    if not cfg.views then
        if not cfg.hudHeight then cfg.hudHeight=235 end
        cfg.views = {
            {name="General", sources={SAY=true,YELL=true,GUILD=true,OFFICER=true,SYSTEM=true}, active=true},
            {name="Group", sources={PARTY=true,RAID=true,INSTANCE_CHAT=true}, active=true},
            {name="Whispers", sources={}, scope="all", active=true},
            {name="World", sources={WORLD=true}, quiet=true},
            {name="Trade", sources={TRADE=true}, quiet=true},
            {name="Combat", sources={COMBAT=true}, quiet=true},
        }
    end
    return cfg
end

-- Only the event stream, roster and methods are shared. A nil widget, draft
-- or destination in the second window must never resolve to the first one.
local shared={core=true,sources=true,labels=true,streams=true,realm=true,
    me=true,party=true,raid=true,friend=true,guild=true,lastIn=true,lastOut=true,bridge=true,seenCombat=true}
local instances={[1]=Chat}
local listedProfile,listed
local methods={__index=function(_,k)
    local v=Chat[k]
    if type(v)=="function" or shared[k] then return v end
end}
function Chat:ListWindows()
    local root=profile()
    if listedProfile~=root or not listed then
        listedProfile=root
        listed={Chat}
        for id in pairs(root.windows) do
            if type(id)=="number" and id>=2 then
                instances[id]=instances[id] or setmetatable({id=id,drafts={}},methods)
                listed[#listed+1]=instances[id]
            end
        end
        table.sort(listed,function(a,b) return a:WindowID()<b:WindowID() end)
    end
    return listed
end
function Chat:IsWindowEnabled() return self==Chat or self:Config().visible~=false end
function Chat:WindowName() return self:Config().windowName or (self==Chat and "Chat" or ("Chat "..self.id)) end
function Chat:SetWindowName(name)
    name=self.text(name)
    name=name and name:match("^%s*(.-)%s*$")
    if not name or name=="" or #name>80 or name:find("[%c|]") then return false end
    self:Config().windowName=name
    Chat:SyncLayoutWindows()
    if self.running then self:QueuePaint() end
    return true
end
function Chat:GetComposerWindow()
    local root=profile()
    local id=root.composerWindow
    if id and id~=1 and root.windows[id] and root.windows[id].visible~=false then
        if not instances[id] then Chat:ListWindows() end
        return instances[id] or Chat
    end
    return Chat
end
function Chat:HasComposer() return self==Chat:GetComposerWindow() end
function Chat:SetAsComposer()
    local prev=Chat:GetComposerWindow()
    if prev==self then return true end
    if Chat.running then
        if Chat.bridge:CloseWorkspace(prev)==false then
            prev:Notice("Finish the game command or leave combat before moving the input.")
            return false
        end
        prev:ReleaseComposer()
    end
    self:Config().visible=true
    profile().composerWindow=self:WindowID()
    if Chat.running then
        prev:ApplyLayout()
        Chat:SyncWindows()
        self:ApplyLayout()
    end
    return true
end
function Chat:CreateChatWindow()
    local root=profile()
    local id=math.max(2,tonumber(root.nextWindowID) or 2)
    while root.windows[id] do id=id+1 end
    root.windows[id]={visible=true}
    root.nextWindowID=id+1
    listed=nil
    Chat:SyncLayoutWindows()
    if Chat.running then Chat:SyncWindows() end
    return instances[id]
end
function Chat:SetWindowEnabled(on)
    if self==Chat then return end
    if not on and self:HasComposer() and not Chat:SetAsComposer() then return false end
    self:Config().visible=on==true
    if Chat.running then Chat:SyncWindows() end
    if Chat.RefreshToolbars then Chat:RefreshToolbars() end
    return true
end
function Chat:DeleteWindow()
    if self==Chat then return false end
    if not self:CanRemoveLayoutWindow() then return false end
    if not self:SetWindowEnabled(false) then return false end
    if self.ruleWindow then self.ruleWindow:Hide() end
    profile().windows[self.id]=nil
    self.drafts={}
    listed=nil
    self:RemoveLayoutWindow()
    if Chat.RefreshToolbars then Chat:RefreshToolbars() end
    return true
end
function Chat:SyncWindows()
    Chat:SyncLayoutWindows()
    for _,w in ipairs(Chat:ListWindows()) do
        if w~=Chat then
            if Chat.running and w:IsWindowEnabled() then
                if not w.running then
                    w.running=true
                    if not w.peer and not w.target then
                        w.target=w:Config().lastDestination or (w:AllowsTarget("PARTY") and "PARTY" or nil)
                    end
                    w:RefreshTargetLabel()
                    w:Show()
                end
            elseif w.running then
                Chat.bridge:CloseWorkspace(w)
                w.running=false
                if w.window then w.window:Hide() end
            end
        end
    end
end
function Chat:IsRowRead(row)
    return row.outgoing or (self==Chat and row.read) or (row.readWindows and row.readWindows[self:WindowID()])
end
function Chat:MarkRowRead(row)
    if self==Chat then row.read=true
    elseif not row.outgoing then
        row.readWindows=row.readWindows or {}
        row.readWindows[self.id]=true
    end
end
function Chat:QueueAllWindows()
    for _,w in ipairs(Chat:ListWindows()) do if w.running then w:QueuePaint() end end
end
function Chat:Reset()
    self.previewChat=nil
    self.streams,self.party,self.raid,self.friend,self.guild={},{},{},{},{}
    self.serial=0
    self.lastIn,self.lastOut,self.lastPeer=nil,nil,nil
    listed=nil
    for _,w in pairs(instances) do
        w.previewAnchor=nil
        w.whisperTarget=nil
        w.drafts={}
        w.peer,w.target,w.anchor,w.nativeSource,w.parkedRuleConfig=nil,nil,nil,nil,nil
        if w.input then w.input:SetText("");w.input.bvHistory={} end
        if w.copyBox then w.copyBox:SetText("") end
        if w.voicePanel then w.voicePanel:Hide() end
        if w~=Chat then
            w.running=false
            if w.window then w.window:Hide() end
        end
    end
end

function Chat.readable(value)
    return not (issecretvalue and issecretvalue(value))
end

function Chat.text(value)
    return Chat.readable(value) and type(value) == "string" and value ~= "" and value or nil
end

function Chat.channelKey(name)
    name=Chat.text(name)
    if name then return "#"..name:lower() end
end

function Chat.person(name)
    name = Chat.text(name)
    if name and #name <= 100 and not name:find("[%c|/:;%[%]]") then return name end
end

function Chat:Key(name)
    local short, realm = name:match("^([^%-]+)%-(.+)$")
    if short and realm:lower() == self.realm then return short:lower() end
    return name:lower()
end

-- A trade burst or a combat replay must not evict personal conversations.
function Chat:Add(source, author, body, outgoing, channel, zoneID, classToken)
    if not self.text(body) then return end
    local limit = source == "WHISPER" and 400 or source == "COMBAT" and 160 or 500
    local bucket = source == "WHISPER" and "private" or source == "COMBAT" and "combat" or "public"
    local stream = self.streams[bucket] or {count=0, head=0}
    self.streams[bucket] = stream
    self.serial = self.serial + 1
    local row = {id=self.serial, source=source, author=author, classToken=classToken, body=body, channel=channel,
        channelKey=self.channelKey(channel),zoneID=channel and self.readable(zoneID) and type(zoneID)=="number" and zoneID or nil,
        key=author and self:Key(author), outgoing=outgoing, read=outgoing or false,
        stamp=date and date("%H:%M:%S") or ""}
    stream.head = stream.head % limit + 1
    stream[stream.head] = row
    stream.count = math.min(limit, stream.count + 1)
    if source == "WHISPER" and author then
        self.lastPeer=author
        if outgoing then self.lastOut = author else self.lastIn = author end
    end
    self:QueueAllWindows()
    return row
end

function Chat:Rows(test)
    local rows = {}
    for _, stream in pairs(self.streams) do
        for i=1,stream.count do
            local row = stream[i]
            if test(row) then rows[#rows+1] = row end
        end
    end
    table.sort(rows,function(a,b) return a.id < b.id end)
    return rows
end

function Chat:Matches(view,row)
    if row.source == "WHISPER" then
        if view.scope=="all" then return true end
        if view.scope=="party" or view.scope=="raid" then return self:SocialMember(view.scope,row.key,row.previewGroups) end
        if view.scope=="selected" then
            for group,on in pairs(view.whisperGroups or {}) do
                if on and self:SocialMember(group,row.key,row.previewGroups) then return true end
            end
        end
        return false
    end
    local sources=view.sources or {}
    return sources[row.source] or sources[row.channelKey or self.channelKey(row.channel)]
end

function Chat:SocialMember(group,key,previewGroups)
    if group~="friend" and group~="guild" and group~="party" and group~="raid" then return false end
    -- Only synthetic settings rows supply this; received messages never do.
    if previewGroups then return previewGroups[group]==true end
    local cache=self[group]
    return key~=nil and cache~=nil and cache[key]~=nil or false
end

function Chat:Visible(row)
    if self.peer then return row.source=="WHISPER" and row.key==self:Key(self.peer) end
    for _, view in ipairs(self:Config().views) do
        if view.active and self:Matches(view,row) then return true end
    end
    return false
end

function Chat:Conversations(prefix)
    local people, seen = {}, {}
    local rows = self:Rows(function(row) return row.source=="WHISPER" end)
    prefix = (prefix or ""):lower()
    for i=#rows,1,-1 do
        local row = rows[i]
        if row.author and not seen[row.key] and row.key:find(prefix,1,true) then
            seen[row.key] = true
            people[#people+1] = row.author
        end
    end
    return people
end

function Chat.plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|cn[%w_]+:",""):gsub("|r",""):gsub("|H.-|h(.-)|h","%1")
        :gsub("|T.-|t",""):gsub("|A.-|a",""))
end

local function rgb(hex,offset)
    return tonumber(hex:sub(offset,offset+1),16) or 0
end
function Chat.blend(base, overlay)
    if not overlay then return base end
    local weight=rgb(overlay,7)/255
    local function channel(i)
        return math.floor(rgb(base,i)*(1-weight)+rgb(overlay,i)*weight+.5)
    end
    return string.format("%02x%02x%02x",channel(1),channel(3),channel(5))
end
function Chat:RowStyle(row)
    local tint,background
    for _,v in ipairs(self:Config().views) do
        if v.active and self:Matches(v,row) then
            if not tint and v.tint and rgb(v.tint,7)>0 then tint=v.tint end
            if not background then background=v.background end
            if tint and background then break end
        end
    end
    return tint,self:SenderBackground(row,background)
end

local function colorHex(value,length)
    return Chat.text(value) and #value==length and value:match("^%x+$") and value:lower() or nil
end
local function paletteColor(c)
    if not c then return end
    local argb=colorHex(c.colorStr,8)
    if argb then return argb:sub(3) end
    local function byte(n)
        if Chat.readable(n) and type(n)=="number" and n>=0 and n<=1 then return math.floor(n*255+.5) end
    end
    local r,g,b=byte(c.r),byte(c.g),byte(c.b)
    if r and g and b then return string.format("%02x%02x%02x",r,g,b) end
end
-- Client colors cover realm/client variations. The fallback is used during
-- startup and by clients that expose only chat type IDs.
local classicColors={SAY="ffffff",YELL="ff4040",WHISPER="ff80ff",GUILD="40ff40",OFFICER="40c040",
    PARTY="aaaaff",RAID="ff7f00",RAID_WARNING="ff4800",INSTANCE_CHAT="ff7f00",SYSTEM="ffff00",CHANNEL="ffc0c0"}
function Chat:WoWRoleColor(style,role,row)
    if (role~="channel" and role~="message") or style.colors[role]~=Chat.defaultMessageColors[role]
        or (style.fixedColors and style.fixedColors[role]) then return end
    local kind=row.kind or row.source
    if kind=="WORLD" or kind=="TRADE" or kind=="CHANNEL" then kind=row.channelSlot and ("CHANNEL"..row.channelSlot) or "CHANNEL" end
    local fallback=(kind and kind:match("^CHANNEL%d+$")) and "CHANNEL" or row.source
    if fallback=="WORLD" or fallback=="TRADE" then fallback="CHANNEL" end
    return paletteColor(ChatTypeInfo and ChatTypeInfo[kind]) or paletteColor(ChatTypeInfo and ChatTypeInfo[fallback])
        or classicColors[kind] or classicColors[fallback]
end
function Chat:SenderRule(row)
    -- WHISPER_INFORM stores the recipient in author; that is not the sender.
    local key=row.key
    if row.outgoing and row.source=="WHISPER" then key=self.me end
    local channel=row.channelKey or self.channelKey(row.channel)
    for _,rule in ipairs(self:SenderRules()) do
        if rule.enabled and rule.scope and (rule.scope=="all" or rule.scope==row.source or rule.scope==channel)
            and (colorHex(rule.tint,8) or colorHex(rule.background,8)) then
            if rule.names then
                for _,name in ipairs(rule.names) do
                    if key==self:Key(name) then return rule end
                end
            elseif self:SocialMember(rule.key,key,row.previewGroups) then return rule end
        end
    end
end
function Chat:SenderBackground(row,fallback)
    local rule=self:SenderRule(row)
    local bg=rule and colorHex(rule.background,8)
    return bg and rgb(bg,7)>0 and bg or fallback
end
function Chat:MessageColors(row,overlay,previewLayer)
    local style=self:MessageStyle()
    local sources=style.sourceColors
    local named=sources[row.channelKey or self.channelKey(row.channel)] or {}
    local source=sources[row.source] or {}
    -- Settings previews stop at a named layer without editing profile data.
    -- Runtime callers omit previewLayer and use the complete pipeline.
    local limited=previewLayer=="base" or previewLayer=="type"
    local rule=not limited and self:SenderRule(row)
    local colors={}
    for role,fallback in pairs(Chat.defaultMessageColors) do
        local base=colorHex(style.colors[role],6) or fallback
        if role=="sender" and style.classNames then base=paletteColor(row.classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.classToken]) or base end
        if previewLayer~="base" then base=colorHex(named[role],6) or colorHex(source[role],6) or self:WoWRoleColor(style,role,row) or base end
        if not limited then base=self.blend(base,overlay) end
        if rule and (rule.target=="all" or rule.target==role) then base=self.blend(base,colorHex(rule.tint,8)) end
        colors[role]=base
    end
    return colors
end

local channelSymbols={
    SAY={"S","message-circle"}, YELL={"Y","megaphone"}, WHISPER={"W","mail"},
    GUILD={"G","shield"}, OFFICER={"O","shield-check"}, PARTY={"P","users"},
    RAID={"R","flag"}, INSTANCE_CHAT={"I","castle"}, SYSTEM={"SYS","info"},
    COMBAT={"CBT","swords"}, TRADE={"TR","coins"}, WORLD={"PUB","globe"},
}
-- Server-defined channel IDs stay the same across zones and client languages.
-- Local slot numbers (such as /1) never determine a channel's identity.
local generalBadge={"G","map-pin"}
local lfgBadge={"LFG","search"}
local namedBadges={general=generalBadge,allgemein=generalBadge,
    trade=channelSymbols.TRADE,handel=channelSymbols.TRADE,
    lookingforgroup=lfgBadge,suchenachgruppe=lfgBadge,
    localdefense={"LD","shield-lock"},lokaleverteidigung={"LV","shield-lock"}}
local zoneBadges={[1]=generalBadge,[2]=channelSymbols.TRADE}

local function formatTime(stamp,mode)
    if mode=="off" or not stamp or stamp=="" then return end
    local hours,minutes,seconds=stamp:match("^(%d%d):(%d%d):?(%d*)$")
    if not hours then return stamp end
    if mode=="long" then return hours..":"..minutes..":"..(seconds~="" and seconds or "00") end
    if mode=="12h" then
        local hour=tonumber(hours)
        return string.format("%d:%s %s",(hour+11)%12+1,minutes,hour<12 and "AM" or "PM")
    end
    return hours..":"..minutes
end

local function channelBadge(row,mode,hex)
    local full=row.channel or Chat.labels[row.source] or row.source
    if mode=="full" then return "["..full.."]" end
    local named=row.channel and (zoneBadges[row.zoneID] or namedBadges[row.channel:lower()])
    local glyph=named or channelSymbols[row.source]
    if not glyph then return "["..full.."]" end
    local custom=row.channel and not named
    local short=custom and row.channel or glyph[1]
    if mode=="short" then return "["..short.."]" end
    local symbols=core.Symbols
    if mode~="icon" or not symbols or not symbols:Valid(glyph[2]) then return "["..full.."]" end
    local path,l,r,t,b=symbols:Coords(glyph[2],16)
    if not path then return "["..full.."]" end
    -- UVs come from the suite sheet. The virtual texture dimensions can use
    -- any common scale as long as the pixel bounds express the same fraction.
    local grid=core.SymbolData.atlases[1].side
    local icon=string.format("|T%s:14:14:0:0:%d:%d:%d:%d:%d:%d:%d:%d:%d|t",path,grid,grid,
        l*grid,r*grid,t*grid,b*grid,rgb(hex,1),rgb(hex,3),rgb(hex,5))
    -- Joined channels can share a glyph, so keep their identity in the mix.
    return custom and (icon.." "..short) or icon
end
function Chat:Format(row, color, overlay,previewLayer)
    local style=self:MessageStyle()
    local colors=self:MessageColors(row,overlay,previewLayer)
    local function paint(text,hex)
        return color and "|cff"..hex..text.."|r" or text
    end
    local parts = {}
    local stamp=formatTime(row.stamp,style.timeFormat)
    if stamp then parts[#parts+1]=paint(stamp,colors.time) end
    local labelColor=colors.channel
    local key=row.channelKey or self.channelKey(row.channel)
    local mode=color and (style.channelModes[key] or style.channelMode) or "full"
    parts[#parts+1]=paint(channelBadge(row,mode,labelColor),labelColor)
    if row.author then
        local name=row.author
        if row.source=="WHISPER" then name=(row.outgoing and "→ " or "← ")..name end
        parts[#parts+1]=paint(name,colors.sender)
    end
    local body=color and row.body or self.plain(row.body)
    if color then
        local messageColor=colors.message
        -- A colored item link ends with |r. Resume the message's chosen color
        -- for the words after it without changing the link or its rarity.
        if body:find("|r",1,true) then body=body:gsub("|r","|r|cff"..messageColor) end
        body=paint(body,messageColor)
    end
    parts[#parts+1]=body
    return table.concat(parts,"  ")
end

function Chat:DraftKey()
    return self.whisperTarget and "@"..self:Key(self.whisperTarget) or self.target or ""
end
function Chat:SetAddress(peer,target)
    if self.input then self.drafts[self:DraftKey()]=self.input:GetText() end
    self.whisperTarget=peer
    if not peer then self.target = target; self:RefreshTargetLabel() end
    if self.input then
        self.input:SetText(self.drafts[self:DraftKey()] or "")
        self.input.bvHistory={}
        self.input.bvLastText=self.input:GetText()
    end
    self:Paint()
end
function Chat:Switch(peer,target)
    self.nativeSource,self.peer,self.anchor=nil,peer,nil
    self:SetAddress(peer,target)
end

function Chat:Toggle(view)
    view.active = not view.active
    if self.whisperTarget and not self.peer and not self.nativeSource then
        self:Paint()
        return
    end
    local target = self.target
    if target and not self:AllowsTarget(target) then target = nil end
    self:Switch(nil,target)
end

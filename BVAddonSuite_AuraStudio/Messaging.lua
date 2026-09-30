-- Small runtime messages only. Routing topics are not authentication.
local _,A=...
if A.blocked then return end
local M={prefix="BVAURA1",maxBytes=220}; A.Messaging=M
local channels={PARTY=true,RAID=true,INSTANCE_CHAT=true,GUILD=true,WHISPER=true,LOCAL=true}
local function readable(api,v) return not (api.issecretvalue and api.issecretvalue(v)) end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
function M.Topic(v) return type(v)=="string" and #v>=1 and #v<=40 and v:match("^[%w_.%-]+$")~=nil end
local function fullName(v)
    if type(v)~="string" or #v>96 or v:find("[%c|]") or not v:match("^[^%s%-]+%-%S+$") then return end
    return v:lower()
end
function M.Senders(value)
    if type(value)~="string" or #value>3200 then return end
    local out,count={},0
    for name in value:gmatch("[^,;\r\n]+")do
        name=fullName(name:match("^%s*(.-)%s*$"));if not name then return end
        if not out[name]then count=count+1;out[name]=true end
    end
    if count<=32 then return out end
end
local communicationKinds={message_send=true,message_receive=true,chat_send=true,chat_direct=true,chat_receive=true}
function M.ResetPermissions(graph)
    -- Lua Script: imported code stays visible but off until enabled (finding 53).
    for _,node in pairs(graph.nodes or {})do if communicationKinds[node.type] or node.type=="macro_write" or node.type=="lua_script" then node.config.permission=false end end
end
local migrated=setmetatable({},{__mode="k"})
function M.MigratePermissions(graph,legacy)
    if not graph or migrated[graph]then return graph end
    local out=graph
    for id,node in pairs(graph.nodes or {})do
        if communicationKinds[node.type] and node.config.permission==nil then
            if out==graph then out=A.G.Copy(graph)end
            local c=out.nodes[id].config
            if node.type=="message_send"or node.type=="message_receive"then
                c.permission=c.channel=="LOCAL"or legacy[node.type=="message_send"and"send"or"receive"]==true and legacy.channels and legacy.channels[c.channel]==true or false
                if node.type=="message_receive"then
                    c.acceptGroup=legacy.group==true
                    local names={};for name,allowed in pairs(legacy.allowlist or {})do if allowed then names[#names+1]=name end end
                    table.sort(names);c.senders=table.concat(names,", ")
                end
            else c.permission=node.type~="chat_direct" end
        end
    end
    migrated[out]=true;return out
end
function M.Value(api,kind,value)
    if not readable(api,value) then return false end
    if kind=="boolean" then return type(value)=="boolean" end
    if kind=="number" then return finite(value) end
    return kind=="string" and type(value)=="string" and #value<=64 and not value:find("%c")
end
local function encode(value) return (value:gsub(".",function(c) return string.format("%02x",c:byte()) end)) end
local function decode(value)
    if #value%2~=0 or value:find("[^%x]") then return end
    return (value:gsub("..",function(c) return string.char(tonumber(c,16)) end))
end
function M.Pack(api,topic,kind,value,session,sequence)
    if not readable(api,topic) or not readable(api,kind) or not readable(api,session) or not readable(api,sequence)
        or not M.Topic(topic) or not M.Value(api,kind,value) or type(session)~="string"
        or not session:match("^%w+$") or #session>16 or not finite(sequence) or sequence<1 or sequence>2147483647
        or sequence~=math.floor(sequence) then return end
    local payload=kind=="boolean" and (value and "1" or "0") or kind=="number" and string.format("%.17g",value) or value
    local text=table.concat({"1",topic,kind,session,tostring(sequence),encode(payload)},"|")
    if #text>M.maxBytes then return end
    return text
end
function M.Unpack(api,text)
    if not readable(api,text) or type(text)~="string" or #text>M.maxBytes then return end
    local topic,kind,session,sequence,hex=text:match("^1|([%w_.%-]+)|(%a+)|(%w+)|(%d+)|(%x*)$")
    if not topic or not M.Topic(topic) or #session>16 or #sequence>10 then return end
    sequence=tonumber(sequence); if not sequence or sequence<1 or sequence>2147483647 then return end
    local value=decode(hex); if value==nil then return end
    if kind=="boolean" then if value=="1" then value=true elseif value=="0" then value=false else return end
    elseif kind=="number" then value=tonumber(value) end
    if not M.Value(api,kind,value) then return end
    return {topic=topic,kind=kind,value=value,session=session,sequence=sequence}
end
function M.New(api,events,receive,policy,statusChanged)
    local self={session=tostring(math.random(10000000,99999999)),sequence=0,history={},historyOrder={},rates={},rateOrder={},globalRates={}}
    local function now() return api.GetTime() end
    local function config() return policy() or {} end
    local function quota(key,limit)
        local time=now(); local global=key=="send" or key=="ingress"
        local rows=global and self.globalRates or self.rates
        local row=rows[key]
        if not row then
            if not global and #self.rateOrder>=128 then self.rates[table.remove(self.rateOrder,1)]=nil end
            row={at=time,count=0}; rows[key]=row
            if not global then self.rateOrder[#self.rateOrder+1]=key end
        end
        if time-row.at>=1 then row.at=time; row.count=0 end
        if row.count>=limit then return false end
        row.count=row.count+1; return true
    end
    local function restricted()
        local chat=api.C_ChatInfo
        if self.transitionRestricted then return true end
        if not chat or not chat.AreOutgoingAddonChatMessagesRestricted or not chat.InChatMessagingLockdown then return true end
        for _,fn in ipairs({chat.AreOutgoingAddonChatMessagesRestricted,chat.InChatMessagingLockdown}) do
            local ok,result=pcall(fn)
            if not ok or not readable(api,result) or result~=false then return true end
        end
        return false
    end
    local function localName(unit)
        if not api.UnitFullName or not api.GetNormalizedRealmName then return end
        local ok,name,realm=pcall(api.UnitFullName,unit)
        if not ok or not readable(api,name) or not readable(api,realm) or type(name)~="string" then return end
        if realm==nil or realm=="" then
            local valid,r=pcall(api.GetNormalizedRealmName); if not valid or not readable(api,r) then return end; realm=r
        end
        if type(realm)~="string" then return end
        return fullName(name.."-"..realm:gsub("%s", ""))
    end
    local function senderAllowed(sender,channel,c)
        if type(c.allowlist)=="table" and c.allowlist[sender]==true then return true end
        if c.group~=true or (channel~="PARTY" and channel~="RAID" and channel~="INSTANCE_CHAT") then return false end
        for i=1,40 do if localName("raid"..i)==sender then return true end end
        for i=1,4 do if localName("party"..i)==sender then return true end end
        return false
    end
    function self:AcceptNode(node,sender,channel)
        if node.permission==false or node.channel~=channel then return false end
        if channel=="LOCAL"then return true end
        if config().paused then return false end
        if node.permission~=true then return false end
        return senderAllowed(sender,channel,{group=node.acceptGroup==true,allowlist=M.Senders(node.senders or "")or{}})
    end
    local function allowed(sender,channel)
        local c=config();if c.paused then return false end
        if c.nodePolicies then
            for _,node in ipairs(c.receivers or {})do if self:AcceptNode(node,sender,channel)then return true end end
            return false
        end
        if not c.receive or type(c.channels)~="table"or c.channels[channel]~=true then return false end
        return senderAllowed(sender,channel,c)
    end
    function self:Receive(prefix,text,channel,sender)
        if not readable(api,prefix) or not readable(api,channel) or not readable(api,sender)
            or prefix~=M.prefix or type(channel)~="string" or not channels[channel] or channel=="LOCAL" then return false,"invalid" end
        local name=fullName(sender)
        if not name or name==localName("player") then return false,"sender" end
        if not quota("ingress",30) or not quota("sender:"..name,5) then return false,"rate limited" end
        if not allowed(name,channel) then return false,"sender" end
        local packet=M.Unpack(api,text); if not packet then return false,"invalid" end
        local key=name..":"..packet.session
        local previous=self.history[key]
        if previous and packet.sequence<=previous then return false,"duplicate" end
        if not previous then
            if #self.historyOrder>=128 then self.history[table.remove(self.historyOrder,1)]=nil end
            self.historyOrder[#self.historyOrder+1]=key
        end
        self.history[key]=packet.sequence
        packet.sender=name; packet.channel=channel; packet.origin="message"
        receive(packet) -- Controller queues bounded graph work; never evaluates recursively.
        return true,"accepted"
    end
    function self:CanSend(channel,target,node)
        if not readable(api,channel) or type(channel)~="string" or not channels[channel] then return false,"invalid channel" end
        if node and node.permission==false then return false,"disabled on node"end
        if channel=="LOCAL" then return true,"local" end
        local c=config()
        if c.paused then return false,"external addon communication paused"end
        if c.nodePolicies then
            if not node or node.permission~=true then return false,"disabled on node"end
        elseif not c.send or type(c.channels)~="table" or c.channels[channel]~=true then return false,"disabled locally" end
        if restricted() then return false,"restricted; dropped" end
        if channel=="WHISPER" and (not readable(api,target) or not fullName(target)) then return false,"full target required" end
        if not api.C_ChatInfo.SendAddonMessage then return false,"unsupported" end
        return true,"allowed; delivery unconfirmed"
    end
    function self:Send(topic,kind,value,channel,target,origin,graphID,node)
        if origin=="message" then return false,"forwarding blocked" end
        if not readable(api,channel) or type(channel)~="string" or not channels[channel] then return false,"invalid channel" end
        local can,status=self:CanSend(channel,target,node);if not can then return false,status end
        self.sequence=self.sequence+1
        local text=M.Pack(api,topic,kind,value,self.session,self.sequence); if not text then return false,"invalid payload" end
        if not quota("send",10) or not quota("graph:"..tostring(graphID),5) then return false,"rate limited" end
        if channel=="LOCAL" then
            local packet=M.Unpack(api,text); packet.sender="local"; packet.channel="LOCAL"; packet.origin="message"
            receive(packet); return true,"local queued"
        end
        local chat=api.C_ChatInfo; if not chat.SendAddonMessage then return false,"unsupported" end
        local ok,result=pcall(chat.SendAddonMessage,M.prefix,text,channel,channel=="WHISPER" and target or nil)
        if not ok or not readable(api,result) or not finite(result) then return false,"API error" end
        local enum=api.Enum and api.Enum.SendAddonMessageResult
        if enum and result==enum.Success then return true,"submitted; delivery unconfirmed" end
        return false,"send result "..tostring(result) -- Enum, never a delivery acknowledgement.
    end
    function self:Start()
        -- Reconcile subscriptions without forgetting replay history or quotas.
        events:Release(self)
        local c=config()
        if c.send then events:Subscribe(self,"ADDON_RESTRICTION_STATE_CHANGED",function(_,kind,state)
            local e=api.Enum and api.Enum.AddOnRestrictionType
            if readable(api,kind) and e and kind==e.Chat then
                local states=api.Enum.AddOnRestrictionState
                self.transitionRestricted=not (readable(api,state) and states and state==states.Inactive)
                if statusChanged then statusChanged() end
            end
        end) end
        if c.receive then
            local chat=api.C_ChatInfo; local enum=api.Enum and api.Enum.RegisterAddonMessagePrefixResult
            if not chat or not chat.RegisterAddonMessagePrefix or not enum then return false,"unsupported" end
            local ok,result=pcall(chat.RegisterAddonMessagePrefix,M.prefix)
            if not ok or not readable(api,result) or (result~=enum.Success and result~=enum.DuplicatePrefix) then return false,"registration failed" end
            events:Subscribe(self,"CHAT_MSG_ADDON",function(_,...) self:Receive(...) end)
        end
        return true,c.receive and "registered" or "local only"
    end
    function self:Stop()
        events:Release(self); self.history={}; self.historyOrder={}; self.rates={}; self.rateOrder={}; self.globalRates={}; self.transitionRestricted=nil
    end
    return self
end

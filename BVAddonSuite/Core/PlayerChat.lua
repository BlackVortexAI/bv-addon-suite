-- Bounded session chat adapter. Hardware permission is never stored or replayed.
-- Request/Confirm and explicit direct sends share native context validation.
local _,ns=...
local P={};ns.PlayerChat=P
local V=ns.GraphValues
P.receiveChannels={SAY={"CHAT_MSG_SAY"},YELL={"CHAT_MSG_YELL"},EMOTE={"CHAT_MSG_EMOTE"},WHISPER={"CHAT_MSG_WHISPER"},
 PARTY={"CHAT_MSG_PARTY","CHAT_MSG_PARTY_LEADER"},RAID={"CHAT_MSG_RAID","CHAT_MSG_RAID_LEADER"},RAID_WARNING={"CHAT_MSG_RAID_WARNING"},
 INSTANCE_CHAT={"CHAT_MSG_INSTANCE_CHAT","CHAT_MSG_INSTANCE_CHAT_LEADER"},GUILD={"CHAT_MSG_GUILD"},OFFICER={"CHAT_MSG_OFFICER"},
 CHANNEL={"CHAT_MSG_CHANNEL"},SYSTEM={"CHAT_MSG_SYSTEM"}}
P.sendChannels={SAY=true,YELL=true,EMOTE=true,WHISPER=true,PARTY=true,RAID=true,RAID_WARNING=true,INSTANCE_CHAT=true,GUILD=true,OFFICER=true,CHANNEL=true}
local modes={ANY=true,EXACT=true,CONTAINS=true,GLOB=true}
local function stringValue(v,limit,empty)
 return not V.IsSecret(v) and type(v)=="string" and #v<=limit and (empty or #v>0)
end
-- A small glob language, not Lua patterns: whole-string * / ? and backslash
-- escapes. UTF-8 characters stay intact; work is bounded even for adversarial
-- wildcard retries, independently of the outer event/token quota.
local function character(s,i)
 local first=s:byte(i);local size=first and (first>=240 and first<=244 and 4 or first>=224 and first<=239 and 3 or first>=194 and first<=223 and 2)or 1
 for j=i+1,i+size-1 do local b=s:byte(j);if not b or b<128 or b>191 then size=1;break end end
 return s:sub(i,i+size-1),i+size
end
local function globPattern(pattern)
 if not stringValue(pattern,128,false)then return end
 local tokens={};local i=1
 while i<=#pattern do
  local c,nextIndex=character(pattern,i);i=nextIndex
  if c=="\\"then if i>#pattern then return end;c,i=character(pattern,i);tokens[#tokens+1]={literal=c}
  elseif c=="*"then if tokens[#tokens]~="*"then tokens[#tokens+1]="*"end
  elseif c=="?"then tokens[#tokens+1]="?"
  else tokens[#tokens+1]={literal=c}end
 end
 return tokens
end
P.globMaxSteps=4096;P.receiveGlobMaxSteps=16384
function P.GlobMatch(value,pattern,budget)
 if not stringValue(value,1024,true)then return false end
 local tokens=globPattern(pattern);if not tokens then return false,"invalid_glob"end
 local i,j,star,retry,steps=1,1,nil,nil,0
 while i<=#value do
  steps=steps+1
  if steps>P.globMaxSteps or budget and budget.left<=0 then if budget then budget.exhausted=true end;return false,"glob_budget"end
  if budget then budget.left=budget.left-1 end
  local token=tokens[j];local c,nextIndex=character(value,i)
  if token=="*"then star=j;retry=i;j=j+1
  elseif token=="?"or type(token)=="table"and token.literal==c then i=nextIndex;j=j+1
  elseif star then local _,nextRetry=character(value,retry);retry=nextRetry;i=retry;j=star+1
  else return false end
 end
 while tokens[j]=="*"do j=j+1 end
 return j>#tokens
end
function P.ValidReceive(c)
 return V.PlainExcept(c,{}) and P.receiveChannels[c.channel]~=nil and modes[c.textMode] and modes[c.senderMode]
  and (c.permission==nil or type(c.permission)=="boolean")
  and stringValue(c.text,128,true) and stringValue(c.sender,128,true) and stringValue(c.channelName,128,true)
  and (c.textMode=="ANY" or #c.text>0) and (c.senderMode=="ANY" or #c.sender>0) and type(c.ignoreOwn)=="boolean"
  and (c.textMode~="GLOB"or globPattern(c.text)~=nil)and(c.senderMode~="GLOB"or globPattern(c.sender)~=nil)
end
function P.ValidSend(c)
 return V.PlainExcept(c,{}) and P.sendChannels[c.channel]==true and stringValue(c.target,128,true)
  and (c.permission==nil or type(c.permission)=="boolean")
  and not c.target:find("[%c|]")
end
function P.Match(packet,c,budget)
 if c.permission==false then return false end
 if not P.ValidReceive(c) or not V.PlainExcept(packet,{}) or packet.channel~=c.channel or not stringValue(packet.text,1024,false) then return false end
 if c.ignoreOwn and packet.channel~="SYSTEM" and packet.own~=false then return false end
 local function match(value,mode,needle)
  if mode=="ANY" then return true end
  if not stringValue(value,1024,true) then return false end
  if mode=="GLOB"then return P.GlobMatch(value,needle,budget)end
  return mode=="EXACT" and value==needle or mode=="CONTAINS" and value:find(needle,1,true)~=nil
 end
 return match(packet.text,c.textMode,c.text) and match(packet.sender,c.senderMode,c.sender)
  and (c.channelName=="" or packet.channel=="CHANNEL" and packet.channelName==c.channelName)
end
function P.New(api,now,timerFactory)
 api=api or _G;now=now or GetTime;timerFactory=timerFactory or C_Timer.NewTimer
 local self={pending={},listeners={},nextID=0,rules={},eventKinds={},receiveTokens=32,requestTokens=8,receiveAt=now(),requestAt=now(),dropped=0}
 local function secret(v)return V.IsSecret(v) or api.issecretvalue and api.issecretvalue(v) or false end
 local function text(v,limit,empty)return not secret(v) and stringValue(v,limit,empty) end
 local function call(fn,...)
  if type(fn)~="function" then return nil end
  local ok,a,b=pcall(fn,...);if ok then return a,b end
 end
 local function bool(fn,...)
  local v=call(fn,...);if not secret(v) and type(v)=="boolean" then return v end
 end
 local function current(row)
  local ok,value=pcall(row.isCurrent);return ok and not secret(value) and value==true
 end
 local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
 local function notify(reason)
  for owner,callback in pairs(self.listeners)do callback(owner,reason)end
 end
 local function tokens(bucket,at,capacity,rate)
  local t=now();self[bucket]=math.min(capacity,self[bucket]+math.max(0,t-self[at])*rate);self[at]=t
  if self[bucket]<1 then return false end;self[bucket]=self[bucket]-1;return true
 end
 local function arm()
  if self.timer then self.timer:Cancel();self.timer=nil end
  local soon
  for _,row in pairs(self.pending)do soon=math.min(soon or row.expiresAt,row.expiresAt)end
  if soon and not self.stopped then self.timer=timerFactory(math.max(.001,soon-now()),function()self.timer=nil;self:Expire()end)end
 end
 function self:Subscribe(owner,callback)
  assert(owner and type(callback)=="function","Invalid chat listener");self.listeners[owner]=callback
  return function()if self.listeners[owner]==callback then self.listeners[owner]=nil end end
 end
 function self:Unsubscribe(owner)self.listeners[owner]=nil end
 function self:Expire()
  local changed=false
  for id,row in pairs(self.pending)do if row.expiresAt<=now() or not current(row) then self.pending[id]=nil;changed=true end end
  arm();if changed then notify("expired")end
 end
 function self:List()
  self:Expire();local rows={}
  for _,row in pairs(self.pending)do rows[#rows+1]={id=row.id,text=row.text,channel=row.channel,target=row.target,createdAt=row.createdAt,expiresAt=row.expiresAt}end
  table.sort(rows,function(a,b)return a.id<b.id end);return rows
 end
 function self:Check(textValue,c)
  if not P.ValidSend(c) then return "unsupported" end
  if c.permission==false then return "disabled_on_node" end
  if not text(textValue,255,false) or textValue:find("[%c|]") or not textValue:find("%S") then return "invalid_text" end
  if c.channel=="WHISPER" then
   if not text(c.target,128,false) or c.target:find("[%s/\\:%[%]]") then return "invalid_target" end
  elseif c.channel=="CHANNEL" then
   if not text(c.target,128,false) or tonumber(c.target) then return "invalid_target" end
  elseif c.target~="" then return "invalid_target" end
  local chat=api.C_ChatInfo
  if not chat or type(chat.SendChatMessage)~="function" or type(chat.InChatMessagingLockdown)~="function" then return "unsupported" end
  local locked=bool(chat.InChatMessagingLockdown)
  if locked~=false then return locked==true and "restricted" or "context_unavailable" end
  local available=true;local target=c.target~="" and c.target or nil
  if c.channel=="PARTY" or c.channel=="RAID" or c.channel=="RAID_WARNING"then
   if not api.LE_PARTY_CATEGORY_HOME or secret(api.LE_PARTY_CATEGORY_HOME) then return "context_unavailable" end
   available=bool(c.channel~="PARTY" and api.IsInRaid or api.IsInGroup,api.LE_PARTY_CATEGORY_HOME)
   if c.channel=="RAID_WARNING"then
    local leader=bool(api.UnitIsGroupLeader,"player",api.LE_PARTY_CATEGORY_HOME)
    local assistant=bool(api.UnitIsGroupAssistant,"player",api.LE_PARTY_CATEGORY_HOME)
    available=available==true and (leader==true or assistant==true)
   end
  elseif c.channel=="INSTANCE_CHAT" then
   if not api.LE_PARTY_CATEGORY_INSTANCE or secret(api.LE_PARTY_CATEGORY_INSTANCE) then return "context_unavailable" end
   available=bool(api.IsInGroup,api.LE_PARTY_CATEGORY_INSTANCE)
  elseif c.channel=="GUILD"or c.channel=="OFFICER"then
   local member=bool(api.IsInGuild);local speak=bool(api.C_GuildInfo and api.C_GuildInfo.CanSpeakInGuildChat)
   available=member==true and speak==true
   if c.channel=="OFFICER"then available=available and bool(api.C_GuildInfo and api.C_GuildInfo.IsGuildOfficer)==true end
  elseif c.channel=="CHANNEL" then
   local id,name=call(api.GetChannelName,c.target)
   if secret(id) or type(id)~="number" or id<=0 or id>=math.huge or id~=math.floor(id) or not text(name,128,false) or name~=c.target then return "invalid_target" end
   target=id -- The pinned native chatbox passes the current numeric target.
  end
  if available~=true then return "context_unavailable" end
  return "ready",target
 end
 function self:Request(owner,nodeID,textValue,c,isCurrent)
  if self.stopped or not owner or type(isCurrent)~="function" then return false,"inactive" end
  local row={isCurrent=isCurrent};if not current(row)then return false,"inactive"end
  local status=self:Check(textValue,c);if status~="ready"then return false,status end
  self:Expire()
  for _,other in pairs(self.pending)do if other.owner==owner and other.nodeID==nodeID then return false,"already_pending"end end
  if count(self.pending)>=8 then return false,"queue_full"end
  if not tokens("requestTokens","requestAt",8,1)then return false,"rate_limited"end
  self.nextID=self.nextID+1;local t=now()
  row.id=self.nextID;row.owner=owner;row.nodeID=nodeID;row.text=textValue;row.channel=c.channel;row.target=c.target;row.createdAt=t;row.expiresAt=t+15
  self.pending[row.id]=row;arm();notify("requested");return true,"needs_confirmation",row.id
 end
 function self:SendDirect(owner,nodeID,textValue,c,isCurrent)
  if self.stopped or not owner or type(isCurrent)~="function" or not current({isCurrent=isCurrent})then return false,"inactive"end
  if c.permission~=true then return false,"disabled_on_node"end
  local status,target=self:Check(textValue,c);if status~="ready"then return false,status end
  if not tokens("requestTokens","requestAt",8,1)then return false,"rate_limited"end
  -- Exactly one attempt. pcall is not a hardware event or a delivery receipt.
  local ok=pcall(api.C_ChatInfo.SendChatMessage,textValue,c.channel,nil,target)
  return ok,ok and "submitted_unconfirmed"or"call_failed"
 end
 function self:Confirm(id)
  if secret(id) or type(id)~="number"then return "inactive"end
  local row=self.pending[id];if not row or self.stopped then return "inactive"end
  self.pending[id]=nil;arm() -- Consume before any callback or native side effect.
  local status,target
  if row.expiresAt<=now()then status="expired"
  elseif not current(row)then status="inactive"
  else status,target=self:Check(row.text,{channel=row.channel,target=row.target})end
  if status=="ready"then
   local ok=pcall(api.C_ChatInfo.SendChatMessage,row.text,row.channel,nil,target)
   status=ok and "submitted_unconfirmed"or"call_failed"
  end
  notify(status);return status
 end
 function self:Cancel(id)
  if secret(id) or type(id)~="number" or not self.pending[id]then return false end
  self.pending[id]=nil;arm();notify("cancelled");return true
 end
 function self:CancelOwner(owner)
  local changed=false;for id,row in pairs(self.pending)do if row.owner==owner then self.pending[id]=nil;changed=true end end
  if changed then arm();notify("cancelled")end
 end
 function self:SetReceivers(rules,dispatch)
  self.rules={};self.eventKinds={};self.dispatch=dispatch;local accepted=0
  for i=1,math.min(128,#rules)do local rule=rules[i]
   if rule.config.permission~=false and P.ValidReceive(rule.config)then
    local item={owner=rule.owner,nodeID=rule.nodeID,config=V.Copy(rule.config)};accepted=accepted+1
    for _,event in ipairs(P.receiveChannels[item.config.channel])do self.rules[event]=self.rules[event]or{};self.rules[event][#self.rules[event]+1]=item;self.eventKinds[event]=item.config.channel end
   end
  end
  return accepted,math.max(0,#rules-128)
 end
 function self:Events()local result={};for event in pairs(self.rules)do result[#result+1]=event end;table.sort(result);return result end
 function self:Receive(event,...)
  if secret(event) or type(event)~="string"then return end
  local rules=self.rules[event];if self.stopped or not rules then return end
  if not tokens("receiveTokens","receiveAt",32,16)then self.dropped=self.dropped+1;return end
  local body,sender=select(1,...),select(2,...);local channelName,guid=select(9,...),select(12,...)
  if not text(body,1024,false)then self.dropped=self.dropped+1;return end
  local packet={channel=self.eventKinds[event],text=body,sender=text(sender,128,true)and sender or nil,channelName=text(channelName,128,true)and channelName or nil}
  if packet.channel=="SYSTEM"then packet.own=false
  elseif text(guid,128,false)then local player=call(api.UnitGUID,"player");if text(player,128,false)then packet.own=guid==player end end
  local byOwner={};local globBudget={left=P.receiveGlobMaxSteps}
  for _,rule in ipairs(rules)do if P.Match(packet,rule.config,globBudget)then
   local matched=byOwner[rule.owner];if not matched then matched={kind="chat_receive",matches={},values={event=true,text=packet.text,sender=packet.sender,channel=packet.channel,channelName=packet.channelName}};byOwner[rule.owner]=matched end
   matched.matches[rule.nodeID]=true
  end end
  if globBudget.exhausted then self.dropped=self.dropped+1 end
  if self.dispatch then for owner,matched in pairs(byOwner)do self.dispatch(owner,matched)end end
 end
 function self:Stop()
  self.stopped=true;self.pending={};self.rules={};self.eventKinds={};self.dispatch=nil
  if self.timer then self.timer:Cancel();self.timer=nil end
  notify("stopped");self.listeners={}
 end
 return self
end

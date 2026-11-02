local _,Q=...
if not Q.ready then return end
local A={}
Q.AutoQuest=A

-- Only the active Blizzard quest dialog is acted on. In particular we do not
-- select gossip options, accept shared-quest confirmations or interact with an
-- NPC. Action contracts follow Blizzard QuestFrame.lua (pinned client source
-- in artifacts/research/ingame-actions-20260924); these calls can still be
-- refused by the native client. A refusal is left for the player's button.
local PANELS={QUEST_DETAIL="QuestFrameDetailPanel",QUEST_PROGRESS="QuestFrameProgressPanel",QUEST_COMPLETE="QuestFrameRewardPanel"}
local function number(value)
    return not Q.Secret(value) and type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local function yes(value) return not Q.Secret(value) and value==true end
local function shown(frame)
    if not frame or type(frame.IsShown)~="function" then return false end
    local ok,value=pcall(frame.IsShown,frame)
    return ok and yes(value)
end
local function paused()
    local combat,shift=Q.Call("InCombatLockdown"),Q.Call("IsShiftKeyDown")
    return Q.Secret(combat) or Q.Secret(shift) or combat~=false or shift~=false
end
function A:Cancel()
    if self.timer then self.timer:Cancel();self.timer=nil end
end
function A:Reset()
    self:Cancel();self.phase=nil;self.questID=nil;self.attempts={};self.manual=false
end
function A:Attempt(action,...)
    local key=self.phase..":"..self.questID
    if self.attempts[key] then return end
    local fn=_G[action]
    if type(fn)~="function" then return end
    -- Mark before calling: client events can be synchronous/reentrant.
    self.attempts[key]=true
    pcall(fn,...)
end
function A:Run()
    if not Q:Active() or self.manual then return end
    if paused() then self.manual=true;return end
    local phase,id=self.phase,self.questID
    local current=Q.Call("GetQuestID")
    if not number(current) or current~=id or not shown(QuestFrame) or not shown(_G[PANELS[phase]]) then return end
    local cfg=Q:Config()
    if phase=="QUEST_DETAIL" then
        if not cfg.autoAccept then return end
        local automatic=Q.Call("QuestGetAutoAccept")
        local pvp=Q.Call("QuestFlagsPVP")
        -- Acknowledging server auto-accepts and area/item offers is Blizzard's
        -- responsibility. Unknown/secret state is not permission to accept.
        if Q.Secret(automatic) or automatic~=false or Q.Secret(pvp) or pvp~=false then return end
        self:Attempt("AcceptQuest")
    elseif cfg.autoTurnIn then
        local cost=Q.Call("GetQuestMoneyToGet")
        if not number(cost) or cost~=0 then return end
        if phase=="QUEST_PROGRESS" then
            if yes(Q.Call("IsQuestCompletable")) then self:Attempt("CompleteQuest") end
        elseif phase=="QUEST_COMPLETE" then
            local choices=Q.Call("GetNumQuestChoices")
            if number(choices) and (choices==0 or choices==1) then self:Attempt("GetQuestReward",choices) end
        end
    end
end
function A:Schedule()
    self:Cancel()
    -- Blizzard must finish showing its panel before we inspect visibility.
    self.timer=C_Timer.NewTimer(.05,function() self.timer=nil;self:Run() end)
end
function A:Dialog(event,itemID)
    self:Cancel()
    local id=Q.Call("GetQuestID")
    if not number(id) or id<=0 or id%1~=0 then self.phase=nil;return end
    self.phase=event;self.questID=id
    if paused() then self.manual=true end
    if event=="QUEST_DETAIL" then
        if Q.Secret(itemID) or (itemID~=nil and itemID~=0)
            or yes(Q.Call("QuestIsFromAreaTrigger")) or yes(Q.Call("QuestIsFromAdventureMap")) then self.manual=true end
    end
    if not self.manual then self:Schedule() end
end
function A:Enable(context)
    self:Reset()
    for event in pairs(PANELS) do
        local name=event
        context:Subscribe(name,function(_,itemID) self:Dialog(name,itemID) end)
    end
    context:Subscribe("QUEST_ITEM_UPDATE",function() if self.phase and not self.manual then self:Schedule() end end)
    context:Subscribe("QUEST_FINISHED",function() self:Reset() end)
    -- Never confirm a group-share popup; never resume an old dialog after combat.
    for _,event in ipairs({"QUEST_ACCEPT_CONFIRM","PLAYER_REGEN_DISABLED","PLAYER_LEAVING_WORLD"}) do
        context:Subscribe(event,function() self:Cancel();self.manual=true end)
    end
    context:Defer(function() self:Reset() end)
end

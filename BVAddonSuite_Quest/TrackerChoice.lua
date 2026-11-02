local _,Q=...
if not Q.ready then return end
-- Compatibility boundary: Questie 12.1.0's own slash Toggle, never its destructive
-- Enable/Disable paths. No foreign frame access or tracker-list writes.
local ns=Q.ns
local Choice={generation=0,dismissed=setmetatable({},{__mode="k"}),views=setmetatable({},{__mode="k"})}
Q.TrackerChoice=Choice
local function combat() return InCombatLockdown and InCombatLockdown() end
local function profileName() return ns.Settings.db.activeProfile end
local function call(fn,...) if type(fn)~="function" then return false end;return pcall(fn,...) end
function Choice:Store()
    local c=Q:Config()
    if c.trackerProviderChoice~="suite" and c.trackerProviderChoice~="questie" then c.trackerProviderChoice=nil end
    if type(c.trackerProviderQuestieProfile)~="string" then c.trackerProviderQuestieProfile=nil end
    local p=c.trackerProviderPendingReload
    if type(p)~="table" or type(p.suiteProfile)~="string" or type(p.questieProfile)~="string" or type(p.requested)~="boolean" then c.trackerProviderPendingReload=nil end
    return c
end
function Choice:Inspect()
    local api=C_AddOns or {}
    local ok,loaded=call(api.IsAddOnLoaded or IsAddOnLoaded,"Questie")
    if not ok or not loaded then return {state="absent"} end
    local _,version=call(api.GetAddOnMetadata or GetAddOnMetadata,"Questie","Version")
    if version~="12.1.0" then return {state="incompatible",version=version} end
    local addon=rawget(_G,"Questie")
    if type(addon)~="table" or type(addon.IsEnabled)~="function" then return {state="incompatible"} end
    local enabledOk,enabled=call(addon.IsEnabled,addon)
    if not enabledOk or not enabled then return {state="disabled"} end
    local ready=addon.API
    if type(ready)~="table" or type(ready.RegisterOnReady)~="function" then return {state="incompatible"} end
    if ready.isReady~=true then return {state="loading",api=ready} end
    local db=addon.db;local loader=rawget(_G,"QuestieLoader")
    if type(db)~="table" or type(db.profile)~="table" or type(db.profile.trackerEnabled)~="boolean"
        or type(db.GetCurrentProfile)~="function" or type(db.RegisterCallback)~="function" or type(db.UnregisterCallback)~="function"
        or type(loader)~="table" or type(loader.ImportModule)~="function" then return {state="incompatible"} end
    local imported,tracker=call(loader.ImportModule,loader,"QuestieTracker")
    local named,name=call(db.GetCurrentProfile,db)
    if not imported or type(tracker)~="table" or type(tracker.Toggle)~="function" or type(tracker.Update)~="function"
        or not named or type(name)~="string" then return {state="incompatible"} end
    return {state="ready",db=db,api=ready,tracker=tracker,profile=db.profile,name=name,
        enabled=db.profile.trackerEnabled,started=tracker.started==true}
end
function Choice:Token(s)
    s=s or self:Inspect()
    return {generation=self.generation,suite=ns.Settings:Profile(),suiteName=profileName(),db=s.db,profile=s.profile,name=s.name,api=s.api,tracker=s.tracker}
end
function Choice:Valid(token,s)
    return self.active and token and token.generation==self.generation and token.suite==ns.Settings:Profile()
        and token.suiteName==profileName() and s.state=="ready" and token.db==s.db and token.profile==s.profile and token.name==s.name
        and token.api==s.api and token.tracker==s.tracker
end
function Choice:Notify()
    for view in pairs(self.views) do if view.Refresh then view:Refresh() end end
end
function Choice:HideDialog()
    if self.dialog then self.dialog:Hide() end
end
function Choice:Watch(s)
    if s.state=="loading" and self.readyAPI~=s.api then
        self.readyAPI=s.api
        local generation=self.generation
        -- This API is a dot function and can invoke the callback immediately.
        local ok=call(s.api.RegisterOnReady,function()
            if self.active and self.generation==generation then self:Check() end
        end)
        if not ok then self.readyAPI=nil;self.error="Questie readiness could not be registered." end
    end
    if s.state=="ready" and self.watchedDB~=s.db then
        self:Unwatch();self.watchedDB=s.db
        for _,event in ipairs({"OnProfileChanged","OnProfileCopied","OnProfileReset"}) do
            s.db.RegisterCallback(self,event,function()
                if not self.active then return end
                self.generation=self.generation+1;self.pendingAction=nil;self.pendingRepaint=nil;self.error=nil
                self:HideDialog();self:Check()
            end)
        end
    end
end
function Choice:Unwatch()
    if self.watchedDB then
        for _,event in ipairs({"OnProfileChanged","OnProfileCopied","OnProfileReset"}) do self.watchedDB.UnregisterCallback(self,event) end
        self.watchedDB=nil
    end
end
function Choice:Check()
    if not self.active then return end
    local s=self:Inspect();self:Watch(s)
    local c=self:Store();local pending=c.trackerProviderPendingReload
    -- Only an explicitly requested reload can finish this transaction. A fresh
    -- runtime owns the finalization; profile switches never toggle Questie.
    if pending and pending.requested and not self.reloadIssued and not combat() and s.state=="ready" and s.started and s.enabled
        and pending.suiteProfile==profileName() and pending.questieProfile==s.name then
        c.tracker=false;c.trackerProviderChoice="questie";c.trackerProviderQuestieProfile=s.name;c.trackerProviderPendingReload=nil
        Q.Tracker:Update()
    end
    if not combat() and s.state=="ready" and s.enabled and s.started and Q:Active() and c.tracker
        and not c.trackerProviderChoice and not c.trackerProviderPendingReload and not self.dismissed[ns.Settings:Profile()] then
        self:ShowDialog(s)
    end
    self:Notify()
end
function Choice:RepaintLater(token,s,wanted)
    if self.repaint then self.repaint:Cancel() end
    self.repaint=C_Timer.NewTimer(.15,function()
        self.repaint=nil;local current=self:Inspect()
        if self:Valid(token,current) and current.started and current.enabled==wanted and current.tracker==s.tracker then
            if combat() then self.pendingRepaint={token=token,state=s,wanted=wanted};return end
            local ok=call(current.tracker.Update,current.tracker)
            if not ok then self.error="Questie could not refresh its tracker.";self:Notify() end
        end
    end)
end
function Choice:Toggle(s,wanted,token)
    if s.enabled==wanted then return true end
    local ok=call(s.tracker.Toggle,s.tracker)
    if not ok or s.profile.trackerEnabled~=wanted then self.error="Questie did not apply the tracker choice.";return false end
    self:RepaintLater(token,s,wanted);return true
end
function Choice:Apply(wanted,token)
    if wanted~="suite" and wanted~="questie" then return false end
    local s=self:Inspect()
    if not self:Valid(token,s) then return false end
    if combat() then self.pendingAction={wanted=wanted,token=token};self.error="Choice will be applied after combat.";self:Notify();return false end
    local c=self:Store();self.error=nil
    if wanted=="questie" and not s.started then
        -- Do not change either tracker until the user explicitly requests reload.
        c.trackerProviderPendingReload={suiteProfile=profileName(),questieProfile=s.name,requested=false}
        self:HideDialog();self:Notify();return false,"needsReload"
    end
    if not self:Toggle(s,wanted=="questie",token) then self:Notify();return false end
    c.tracker=wanted=="suite";c.trackerProviderChoice=wanted;c.trackerProviderQuestieProfile=s.name;c.trackerProviderPendingReload=nil
    self.pendingAction=nil;Q.Tracker:Update();self:HideDialog();self:Notify();return true
end
function Choice:ReloadChoice(token)
    local s=self:Inspect();local c=self:Store();local p=c.trackerProviderPendingReload
    if not self:Valid(token,s) or combat() or type(ReloadUI)~="function" or not p or p.suiteProfile~=profileName() or p.questieProfile~=s.name then return false end
    if s.started then return self:Apply("questie",token) end
    if not self:Toggle(s,true,token) then self:Notify();return false end
    p.requested=true;self.reloadIssued=true;self.pendingAction=nil
    -- The only reload call: the explicitly labelled user button. BV stays on
    -- in saved settings until Questie's public Ready confirms the next session.
    local ok=call(ReloadUI)
    if not ok then self.error="Reload did not complete. Reload the UI when ready.";self:Notify() end
    return ok
end
function Choice:Status(s)
    local c=self:Store();s=s or self:Inspect()
    if self.error then return self.error end
    if s.state=="absent" then return "Questie is not loaded. No other tracker is changed." end
    if s.state=="disabled" then return "Questie is disabled." end
    if s.state=="loading" then return "Waiting for Questie to finish loading." end
    if s.state~="ready" then return "Questie tracker integration is unavailable for this version or API." end
    local pending=c.trackerProviderPendingReload
    if pending then
        if pending.suiteProfile~=profileName() or pending.questieProfile~=s.name then
            return "Pending choice belongs to another profile. Review the provider and explicitly apply it."
        end
        return "Pending: Questie needs a UI reload. The BV tracker stays unchanged until then."
    end
    local wanted=c.trackerProviderChoice
    if wanted and (c.trackerProviderQuestieProfile~=s.name or s.enabled~=(wanted=="questie") or c.tracker~=(wanted=="suite")) then
        return "Profile or tracker state changed. Review the choice and explicitly apply it."
    end
    if wanted=="questie" and not s.started then return "Questie's tracker has not started. Apply the choice to request a UI reload." end
    return wanted and (wanted=="suite" and "Using the BV tracker." or "Using the Questie tracker.") or "Choose which tracker to use. Changes require Apply."
end
function Choice:Stop()
    self.active=false;self.generation=self.generation+1;self.pendingAction=nil;self.pendingRepaint=nil;self.readyAPI=nil
    if self.repaint then self.repaint:Cancel();self.repaint=nil end
    self:Unwatch();self:HideDialog();self:Notify()
end
function Choice:Enable(context)
    self.active=true;self.generation=self.generation+1;self.error=nil
    context:Subscribe("ADDON_LOADED",function(_,name)if name=="Questie" then self:Check() end end)
    context:Subscribe("PLAYER_REGEN_ENABLED",function()
        local pending=self.pendingAction;self.pendingAction=nil
        local repaint=self.pendingRepaint;self.pendingRepaint=nil
        if pending then self:Apply(pending.wanted,pending.token)
        elseif repaint then self:RepaintLater(repaint.token,repaint.state,repaint.wanted) end
        self:Check()
    end)
    context:Defer(function()self:Stop()end)
    self:Check()
end

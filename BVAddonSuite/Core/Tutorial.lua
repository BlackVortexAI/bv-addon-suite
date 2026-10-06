local _,ns=...
-- Guides (Core 0.8.94): a package may explain what it needs, step by step, in
-- one shared window (UI/TutorialWindow.lua). Optional: packages that do not
-- register a guide, and older packages, are not affected; a package checks
-- for ns.Tutorial before it uses it, so it still runs with an older Core.
--
-- ns.Tutorial:Register{
--   id="combattext",          -- unique, lower case
--   title="Combat Text",      -- window title
--   version=1,                -- raise it to show a changed guide once more
--   module="combat_text",     -- optional: offered only while that module is on
--   steps={                   -- shown one after another
--     {title="...",text="...", -- text: string or function returning one
--      icon="Interface\\Icons\\...", -- optional texture
--      check=function() return "done"|"open"|nil, "short state text" end,
--      action={label="...",run=function() end},          -- optional button
--      secure={label="...",macro=function() return "/click ..." end}, -- optional
--      (action or secure: hideWhenDone=true hides the button once checked done)
--     },                       -- secure: a macro button, for what only a real
--   },                         -- click may do (out of combat only)
-- }
-- The guide is shown once: on login or when its module is turned on, until
-- the player finishes it ("Done"); then the next guide due follows. Closing
-- it earlier shows it again next time. /bv guide [id] and
-- ns.Tutorial:Open(id,true) show it at any time; /bv guide reset shows all
-- guides again.
--
-- Shared steps (apiVersion 2): a step several packages need (e.g. Blizzard's
-- Cooldown Manager) is registered once, ns.Tutorial:RegisterShared(id,step),
-- and guides refer to it with {shared="id"}. Once a guide with it was
-- finished, other guides skip it when offered (a guide opened by hand shows
-- it). A shared step not registered is left out.
local T={guides={},order={},shared={},apiVersion=2}
ns.Tutorial=T

local function store(key)
    local db=ns.Settings and ns.Settings.db
    if type(db)~="table" then return nil end
    key=key or "tutorials"
    if type(db[key])~="table" then db[key]={} end
    return db[key]
end
local function validate(step,i)
    assert(type(step)=="table" and type(step.title)=="string","Guide step "..i.." requires a title")
    assert(type(step.text)=="string" or type(step.text)=="function","Guide step "..i.." requires a text")
    assert(step.check==nil or type(step.check)=="function","Guide step "..i..": check must be a function")
    assert(step.action==nil or type(step.action)=="table" and type(step.action.run)=="function","Guide step "..i..": action.run required")
    assert(step.secure==nil or type(step.secure)=="table" and type(step.secure.macro)=="function","Guide step "..i..": secure.macro required")
end

function T:RegisterShared(id,step)
    assert(type(id)=="string" and id:match("^[a-z][a-z0-9_]*$"),"Shared step requires an id")
    validate(step,id)
    if not self.shared[id] then self.shared[id]=step end
    return self.shared[id]
end
function T:Register(guide)
    assert(type(guide)=="table" and type(guide.id)=="string" and guide.id:match("^[a-z][a-z0-9_]*$"),"Guide requires an id")
    assert(type(guide.title)=="string" and type(guide.steps)=="table" and #guide.steps>0,"Guide requires a title and steps")
    for i,step in ipairs(guide.steps) do
        if type(step)=="table" and step.shared~=nil then
            assert(type(step.shared)=="string","Guide step "..i..": shared must be an id")
        else validate(step,i) end
    end
    guide.version=type(guide.version)=="number" and guide.version or 1
    if not self.guides[guide.id] then self.order[#self.order+1]=guide.id end
    self.guides[guide.id]=guide
    return guide
end
function T:Get(id) return self.guides[id] end
function T:Seen(id)
    local guide,seen=self.guides[id],store()
    return guide~=nil and seen~=nil and type(seen[id])=="number" and seen[id]>=guide.version
end
function T:Finish(id)
    local guide,seen,shared=self.guides[id],store(),store("tutorialShared")
    if not (guide and seen) then return end
    seen[id]=guide.version
    for _,step in ipairs(guide.steps) do if step.shared and self.shared[step.shared] then shared[step.shared]=true end end
end
-- Finished, then the next guide due (one after another).
function T:Done(id)
    self:Finish(id)
    local next=self:NextDue()
    if next then self:Open(next) end
end
-- The steps to show: shared ones resolved; offered (all false) without
-- shared steps already finished in another guide.
function T:Steps(guide,all)
    local seen=store("tutorialShared") or {}
    local list={}
    for _,step in ipairs(guide.steps) do
        if step.shared then
            local shared=self.shared[step.shared]
            if shared and (all or not seen[step.shared]) then list[#list+1]=shared end
        else list[#list+1]=step end
    end
    return list
end
function T:Forget(id) local seen=store();if seen then seen[id]=nil end end
-- Offered: not finished, and its module (if any) is on.
function T:Due(id)
    local guide=self.guides[id]
    if not guide or self:Seen(id) then return false end
    if guide.module then
        local record=ns.Modules and ns.Modules.records[guide.module]
        if not record or (record.state~="enabled" and record.state~="enabling") then return false end
    end
    return true
end

-- One step's state, never failing: "done", "open" or nil (nothing to check).
function T:Check(step)
    if not step.check then return nil end
    local ok,state,text=pcall(step.check)
    if not ok then return "open","Could not be checked." end
    if state~="done" and state~="open" then state=nil end
    return state,type(text)=="string" and text or nil
end
function T:Text(step)
    if type(step.text)=="function" then
        local ok,text=pcall(step.text)
        return ok and type(text)=="string" and text or ""
    end
    return step.text
end

-- Opens a guide (the next one due without id); all: also shared steps seen
-- elsewhere (opened by hand). Waits for the end of combat: the window may
-- hold a secure button. A guide offered with nothing left to show is done.
function T:Open(id,all)
    id=id or self:NextDue()
    if not id or not self.guides[id] then return false end
    if InCombatLockdown and InCombatLockdown() then
        self.pending,self.pendingAll=id,all
        ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function()
            ns.Events:Release(self)
            local wanted,every=self.pending,self.pendingAll;self.pending,self.pendingAll=nil,nil
            if wanted then self:Open(wanted,every) end
        end)
        return true
    end
    local steps=self:Steps(self.guides[id],all)
    if #steps==0 then self:Done(id);return true end
    ns.UI:TutorialWindow(self.guides[id],steps)
    return true
end
function T:NextDue()
    for _,id in ipairs(self.order) do if self:Due(id) then return id end end
end
-- Shows a due guide a moment after login or after its module was turned on.
function T:Offer(id)
    if self.offering or not ((id and self:Due(id)) or self:NextDue()) then return end
    self.offering=C_Timer.NewTimer(2,function()
        self.offering=nil
        local due=id and self:Due(id) and id or self:NextDue()
        if due then self:Open(due) end
    end)
end
-- A module turned off before its guide came: nothing due, no timer left.
function T:Recheck()
    if self.offering and not self:NextDue() then self.offering:Cancel();self.offering=nil end
end

-- Shared step: Blizzard's Cooldown Manager. In combat WoW Forever protects
-- aura data; only buffs and debuffs tracked there stay readable (AuraStudio
-- reads them through CDMSource.lua). Checked with the public, read-only
-- C_CooldownViewer.GetCooldownViewerCategorySet (Environment All; research
-- 2026-09-24): spells in the categories TrackedBuff and TrackedBar.
function T.TrackedCount()
    local api=C_CooldownViewer
    local categories=Enum and Enum.CooldownViewerCategory
    if type(api)~="table" or type(api.GetCooldownViewerCategorySet)~="function" or type(categories)~="table" then return nil end
    local total,readable=0,false
    for _,name in ipairs({"TrackedBuff","TrackedBar"}) do
        local category=categories[name]
        if type(category)=="number" then
            local ok,set=pcall(api.GetCooldownViewerCategorySet,category,false)
            if ok and type(set)=="table" and not (issecretvalue and issecretvalue(set)) then
                readable=true
                local ok2,n=pcall(function() return #set end)
                if ok2 and type(n)=="number" then total=total+n end
            end
        end
    end
    return readable and total or nil
end
T:RegisterShared("cooldownmanager",{
    title="Cooldown Manager",icon="Interface\\Icons\\Spell_Holy_BorrowedTime",
    text="In combat WoW Forever hides buff and debuff data from addons. Only buffs and debuffs tracked in Blizzard's Cooldown Manager stay readable there.\n\n"
        .."So add the buffs and debuffs that BV addons should follow in combat (your procs, your damage-over-time spells, important buffs) to the Cooldown Manager's tracked buffs or tracked bars. "
        .."Out of combat everything stays readable.\n\n"
        .."Open the Cooldown Manager with /cdm (or the button below) and add the spells to \"Tracked Buffs\" or \"Tracked Bars\". This step turns green once at least one is tracked.",
    -- /cdm as a macro: a real click, in case the command opens a protected window.
    secure={label="Open the Cooldown Manager",macro=function() return "/cdm" end},
    check=function()
        local n=T.TrackedCount()
        if n==nil then return nil end
        if n>0 then return "done",n.." tracked in the Cooldown Manager" end
        return "open","Nothing tracked yet"
    end,
})

-- All guides and shared steps as never seen: offered again one after another.
function T:Reset()
    local db=ns.Settings and ns.Settings.db
    if type(db)=="table" then db.tutorials,db.tutorialShared=nil,nil end
    self:Offer()
end

ns.Commands:RegisterAction("guide",function(rest)
    if rest=="reset" then
        T:Reset()
        ns:Print("Guides reset: they are shown again for the modules that are on.")
        return
    end
    local id=rest~="" and rest or nil
    if id and not T.guides[id] then
        local names={}
        for _,key in ipairs(T.order) do names[#names+1]=key end
        ns:Print(#names>0 and "Guides: "..table.concat(names,", ").." (/bv guide <name>, /bv guide reset)" or "No guide registered.")
        return
    end
    if not T:Open(id or T:NextDue() or T.order[1],true) then ns:Print("No guide registered.") end
end)

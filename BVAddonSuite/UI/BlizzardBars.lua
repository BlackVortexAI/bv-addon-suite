local _, ns = ...
-- Central, reversible adapter: masks only known XP/rep artwork, never the whole HUD.
local Native = { requested = {}, records = {}, hooked = setmetatable({}, { __mode = "k" }),
    updateHooks = setmetatable({}, { __mode = "k" }) }
ns.NativeBars = Native

local function protected(object)
    return object.IsProtected and object:IsProtected()
end

function Native:QueueRefresh()
    if not self.active or self.queued then return end
    -- Run after all handlers: Blizzard can initialize containers later in the same event.
    self.queued = C_Timer.NewTimer(0, function()
        self.queued = nil
        if self.active then self:Refresh() end
    end)
end

function Native:WatchUpdates(owner, names, watchSize)
    if not owner then return end
    local hooks = self.updateHooks[owner]
    if not hooks then hooks = {}; self.updateHooks[owner] = hooks end
    for _, name in ipairs(names) do
        if type(owner[name]) == "function" and not hooks[name] then
            hooks[name] = true
            hooksecurefunc(owner, name, function()
                if Native.active then Native:Refresh() end
            end)
        end
    end
    if watchSize and owner.HookScript and not hooks.sizeChanged then
        hooks.sizeChanged = true
        owner:HookScript("OnSizeChanged", function() Native:QueueRefresh() end)
    end
end

function Native:Targets()
    local wanted, found = {}, {}
    local function add(object, owner, kind)
        if object then wanted[object] = owner or object; found[kind] = true end
    end
    local manager, info = StatusTrackingBarManager, StatusTrackingBarInfo
    if self.active then
        self:WatchUpdates(manager, { "UpdateBarsShown", "UpdateBarVisuals" })
    end
    if manager and info and info.BarsEnum then
        for _, container in ipairs(manager.barContainers or {}) do
            if self.active then
                self:WatchUpdates(container, { "InitializeBars", "ApplyPendingBarToShow", "UseMainMenuBarArt" }, true)
            end
            for kind, enabled in pairs(self.requested) do
                local index = info.BarsEnum[kind == "experience" and "Experience" or "Reputation"]
                if enabled and index then
                    add(container.bars and container.bars[index], container, kind)
                    -- Both templates own borders on the container, outside the bar.
                    -- Use the actual bar, not the pending one during a fade transition.
                    if container.shownBarIndex == index then
                        -- Forever build 69913 uses this Mainline region, despite being a Classic client.
                        add(container.BarFrameTexture, container, kind)
                        -- Dividers are anonymous siblings of the bar (client frame-stack evidence).
                        -- Select only these marked frames; do not mask arbitrary container children.
                        if container.GetChildren then
                            for _, child in ipairs({ container:GetChildren() }) do
                                if child.BarDividerTexture then add(child, container, kind) end
                            end
                        end
                        for _, key in ipairs({ "MainMenuBarTextures", "StandaloneTextures" }) do
                            for _, texture in ipairs(container[key] or {}) do add(texture, container, kind) end
                        end
                    end
                end
            end
        end
        for kind, enabled in pairs(self.requested) do
            local index = info.BarsEnum[kind == "experience" and "Experience" or "Reputation"]
            if enabled and index then add(manager.bars and manager.bars[index], manager, kind) end
        end
    end
    if self.requested.experience then add(MainMenuExpBar, nil, "experience") end
    if self.requested.reputation then add(ReputationWatchBar, nil, "reputation") end
    self.unavailable = false
    for kind, enabled in pairs(self.requested) do
        if enabled and not found[kind] then self.unavailable = true end
    end
    return wanted
end

function Native:Refresh()
    if not self.active and not next(self.records) then
        if self.pending then self.pending(); self.pending = nil end
        self.unavailable = false
        return
    end
    if InCombatLockdown() then
        if not self.pending then
            self.pending = ns.Events:Subscribe(self, "PLAYER_REGEN_ENABLED", function()
                self.pending(); self.pending = nil; self:Refresh()
            end)
        end
        return
    end
    if self.pending then self.pending(); self.pending = nil end
    local wanted = self:Targets()
    for frame, state in pairs(self.records) do
        if not wanted[frame] then
            self.records[frame] = nil
            -- Never undo a different addon's intervening nonzero alpha.
            if frame:GetAlpha() == 0 then frame:SetAlpha(state.alpha) end
            if state.mouse ~= nil and not frame:IsMouseEnabled() then frame:EnableMouse(state.mouse) end
        end
    end
    for frame, owner in pairs(wanted) do
        if not protected(frame) and not protected(owner) then
            if not self.records[frame] then
                local state = { alpha = frame:GetAlpha() }
                if frame.IsMouseEnabled and frame.EnableMouse then state.mouse = frame:IsMouseEnabled() end
                self.records[frame] = state
            end
            if not self.hooked[frame] then
                self.hooked[frame] = true
                hooksecurefunc(frame, "SetAlpha", function(owner, alpha)
                    local state = Native.records[owner]
                    if state and alpha ~= 0 then
                        state.alpha = alpha
                        if InCombatLockdown() then Native:Refresh() else owner:SetAlpha(0) end
                    end
                end)
            end
            frame:SetAlpha(0)
            if self.records[frame].mouse ~= nil then frame:EnableMouse(false) end
        else self.unavailable = true end
    end
end

function Native:SetHidden(kind, enabled)
    if self.requested[kind] == enabled then return end
    self.requested[kind] = enabled
    local active = false
    for _, requested in pairs(self.requested) do active = active or requested end
    self.active = active
    if active and not self.watchers then
        self.watchers = {
            ns.Events:Subscribe(self, "ADDON_LOADED", function() self:QueueRefresh() end),
            ns.Events:Subscribe(self, "PLAYER_ENTERING_WORLD", function() self:QueueRefresh() end),
        }
    elseif not active and self.watchers then
        for _, unsubscribe in ipairs(self.watchers) do unsubscribe() end
        self.watchers = nil
        if self.queued then self.queued:Cancel(); self.queued = nil end
    end
    self:Refresh()
end

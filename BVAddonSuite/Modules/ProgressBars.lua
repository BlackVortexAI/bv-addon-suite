local _, ns = ...
local Bars = { states = {}, preview = {}, definitions = {}, order = {} }
ns.ProgressBars = Bars
ns.ProgressData = {}
local Model = ns.ProgressModel

function Bars:View(kind)
    assert(self.definitions[kind],"Progress module not loaded")
    local state = self.states[kind]
    if not state then state = {}; self.states[kind] = state end
    if not state.view then
        state.view = ns.UI:ProgressBar(kind .. "_bar")
        if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(state.view) end
        ns.Layout:Refresh(true)
    end
    return state.view
end

function Bars:Render(kind)
    local state = self.states[kind]
    local preview = self.preview[kind]
    if not state or (not state.active and not preview) then return end
    local config, now = ns.ProgressOptions:Get(kind), GetTime()
    local snapshot, values
    if preview then snapshot, values = self.definitions[kind].preview()
    else
        snapshot = state.snapshot
        if snapshot then values = Model.Values(snapshot, state.session, now) end
    end
    -- Sample data controls the editor preview, never ownership of native artwork.
    local live = state.snapshot
    local inactive = not live or live.capped or live.disabled
    local liveShown = not (config.hideInactive and inactive)
    local shown = preview or liveShown
    local view = self:View(kind)
    local level=ns.Layout:Level("bv:"..kind)
    if view:GetFrameLevel()~=level then
        view:SetFrameLevel(level);view.fill:SetFrameLevel(level+1);view.border:SetFrameLevel(level+2);view.overlay:SetFrameLevel(level+3)
    end
    if not snapshot then
        snapshot = self.definitions[kind].missing or { current=0, maximum=1 }
        values = Model.Values(snapshot, nil, now)
    end
    view:Render(snapshot, values)
    local allowed=ns.Layout:IsAvailable("bv:"..kind)
    view:SetShown(shown and allowed and not view.layoutHidden)
    ns.NativeBars:SetHidden(kind, state.active and liveShown and allowed and not view.layoutHidden and config.hideBlizzard or false)
    ns.Layout:UpdateCursorTracking()
end

function Bars:NeedsClock(kind)
    local state = self.states[kind]
    local tokens=self.definitions[kind] and self.definitions[kind].clockTokens
    if not tokens or not state or not state.active or not state.view or not state.view:IsShown() or self.preview[kind] then return false end
    for _, entry in ipairs(ns.ProgressOptions:Get(kind).fields) do
        if entry.enabled then for _,token in ipairs(tokens) do if entry.template:find(token,1,true) then return true end end end
    end
    return false
end

function Bars:Clock(kind)
    local state = self.states[kind]
    if self:NeedsClock(kind) and not state.clock then
        state.clock = C_Timer.NewTicker(1, function()
            local ok = ns:Call(kind .. "/clock", self.Render, self, kind)
            if not ok then ns.Modules:Fault(ns.Modules.records[kind .. "_bar"]) end
        end)
    elseif not self:NeedsClock(kind) and state.clock then state.clock:Cancel(); state.clock = nil end
end

function Bars:Refresh(kind)
    local state = self.states[kind]
    if not state then return end
    if state.active or self.preview[kind] then
        self:View(kind):Apply(ns.ProgressOptions:Get(kind), self.preview[kind] == true)
        self:Render(kind); self:Clock(kind)
    elseif state.view then state.view:Hide() end
end

function Bars:SetPreview(kind, enabled, overlays)
    self.preview[kind] = enabled == true
    if enabled then self:View(kind).editorOverlay=overlays~=false end
    self:Refresh(kind)
end

function Bars:ClosePreviews()
    for _, kind in ipairs(self.order) do self:SetPreview(kind, false) end
end

function Bars:Update(kind)
    local state = self.states[kind]
    local definition=self.definitions[kind]
    state.snapshot=definition.snapshot()
    if state.snapshot and definition.observe then definition.observe(state.session,state.snapshot,GetTime()) end
    self:Render(kind); self:Clock(kind)
end

local function enable(kind, context)
    Bars:View(kind)
    local state = Bars.states[kind]
    state.active = true
    local definition=Bars.definitions[kind]
    state.session = definition.newSession and definition.newSession(GetTime()) or nil
    context:Defer(function()
        state.active = false
        if state.clock then state.clock:Cancel(); state.clock = nil end
        if state.pending then state.pending:Cancel(); state.pending = nil end
        if state.view then state.view:Hide() end
        Bars.preview[kind] = false
        ns.NativeBars:SetHidden(kind, false)
        ns.Layout:UpdateCursorTracking()
    end)
    local function schedule()
        if state.pending then return end
        state.pending = C_Timer.NewTimer(0, function()
            state.pending = nil
            if state.active then
                local ok = ns:Call(kind .. "/update", Bars.Update, Bars, kind)
                if not ok then ns.Modules:Fault(ns.Modules.records[kind .. "_bar"]) end
            end
        end)
    end
    context:Subscribe("PLAYER_ENTERING_WORLD", function() schedule(); ns.NativeBars:Refresh() end)
    context:Subscribe("DISPLAY_SIZE_CHANGED", function() ns.Layout:Notify() end)
    context:Subscribe("UI_SCALE_CHANGED", function() ns.Layout:Notify() end)
    for _,event in ipairs(definition.events or {}) do context:Subscribe(event,schedule) end
    state.view:Apply(ns.ProgressOptions:Get(kind), false)
    Bars:Update(kind)
    if definition.onEnable then definition.onEnable(context,state) end
end

function Bars:Register(definition)
    local id=definition.kind
    assert(type(id)=="string" and not self.definitions[id],"Duplicate progress module")
    self.definitions[id]=definition; self.order[#self.order+1]=id
    ns.Layout:Register("bv:"..id, {
        label=definition.label,
        limits={minWidth=160,maxWidth=1600,minHeight=6,maxHeight=80},
        defaults=function()
            local c=ns.ProgressOptions:Get(id)
            return {width=c.width,height=c.height,screen=c.anchor,x=c.x,y=c.y}
        end,
        apply=function(rect)
            local state=Bars.states[id]
            if state and state.view then
                state.view.config=ns.ProgressOptions:Get(id)
                state.view:Geometry(rect)
                Bars:Render(id); Bars:Clock(id)
            end
        end,
        enabled=function() return ns.Settings:Module(id.."_bar").enabled==true end,
        cursorActive=function()
            local state=Bars.states[id]
            return state and state.active and state.view and state.view:IsShown()
        end,
        preview=function(value,overlays) Bars:SetPreview(id,value,overlays) end,
    })
    local record=ns.Modules:Register({ id = id .. "_bar", OnEnable = function(context) enable(id, context) end })
    ns.Config:RegisterPage(id,{title=definition.label,description=definition.description,
        build=function(parent) return ns.BarConfig:Build(parent,id) end,
        refresh=function() ns.BarConfig:Refresh(id) end})
    for _,alias in ipairs(definition.aliases or {}) do ns.Commands:Register(alias,record.id,id) end
    if ns.ready and IsLoggedIn() and ns.Settings:Module(record.id).enabled==true then ns.Modules:Start(record) end
    if ns.LayoutEditor.active then
        ns.Layout.draft["bv:"..id]=ns.LayoutModel.Normalize(ns.Layout.elements["bv:"..id].defaults())
        ns.LayoutEditor:EnsureMovers(); ns.LayoutEditor:Refresh()
        ns.Layout.elements["bv:"..id].preview(true,ns.LayoutEditor.overlays)
    end
end

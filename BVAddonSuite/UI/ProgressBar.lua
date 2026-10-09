local _, ns = ...
local UI = ns.UI

function UI:RGBA(hex)
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- Shared renderer for XP, reputation and future bounded progress data.
-- moduleID: the bar's module (style family, Core 0.8.95). "Inherit" texture
-- and fonts follow the family; WoW and Clean add their border inside the bar.
function UI:ProgressBar(moduleID)
    local view = CreateFrame("Frame", nil, UIParent)
    view.moduleID = moduleID
    view:Hide()
    view:SetFrameStrata("MEDIUM")
    view:EnableMouse(false)
    view.background = view:CreateTexture(nil, "BACKGROUND"); view.background:SetAllPoints(view)
    view.rested = view:CreateTexture(nil, "ARTWORK")
    view.fill = CreateFrame("StatusBar", nil, view)
    view.fill:SetAllPoints(view); view.fill:SetMinMaxValues(0, 1)
    view.border = UI:GameBorder(moduleID, view)
    view.border:SetFrameLevel(view.fill:GetFrameLevel() + 1)
    view.overlay = CreateFrame("Frame", nil, view)
    view.overlay:SetAllPoints(view); view.overlay:SetFrameLevel(view.fill:GetFrameLevel() + 2)
    view.labels, view.ticks = {}, {}
    function view:Geometry(rect)
        self.layoutHidden=rect.width<=0 or rect.height<=0
        if self.layoutHidden then self:Hide(); return end
        self:SetSize(rect.width,rect.height)
        self:ClearAllPoints(); self:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
        if self.config then self:Apply(self.config,self.editing) end
    end

    function view:Apply(config, editing)
        self.config, self.editing = config, editing
        self:SetAlpha(config.opacity)
        self.background:SetColorTexture(UI:RGBA(config.background))
        local family = ns.Styles:Family(self.moduleID)
        local texture = config.texture == "inherit" and ns.Styles:BarTexture(family) or ns.Media:StatusBar(config.texture)
        self.border:RepaintSurface()
        self.fill:SetStatusBarTexture(texture); self.fill:SetStatusBarColor(UI:RGBA(config.color))
        self.rested:SetTexture(texture); self.rested:SetVertexColor(UI:RGBA(config.restedColor))
        for index = 1, config.segments - 1 do
            local tick = self.ticks[index]
            if not tick then tick = self.overlay:CreateTexture(nil, "ARTWORK"); self.ticks[index] = tick end
            tick:SetColorTexture(UI:RGBA(config.background)); tick:SetSize(1, self:GetHeight())
            tick:ClearAllPoints(); tick:SetPoint("LEFT", self, "LEFT", self:GetWidth() * index / config.segments, 0); tick:Show()
        end
        for index = config.segments, #self.ticks do self.ticks[index]:Hide() end
        for index, entry in ipairs(config.fields) do
            local label = self.labels[index]
            if not label then label = UI:Label(self.overlay, ""); self.labels[index] = label end
            -- The progress renderer owns per-field appearance; not the global label renderer.
            UI.styled[label] = nil
            if entry.font == "inherit" then ns.Styles:Font(family, label, entry.size, "regular")
            else ns.Theme:Font(label, entry.size, entry.font) end
            label:SetTextColor(UI:RGBA(entry.color)); label:SetJustifyH(entry.align); label:SetJustifyV("MIDDLE")
            label:SetWordWrap(false); label:SetSize(entry.width, entry.size * 1.8)
            label:ClearAllPoints(); label:SetPoint(entry.anchor, self, entry.relative, entry.x, entry.y)
            label:SetShown(entry.enabled and (not editing or self.editorOverlay==false))
        end
        for index = #config.fields + 1, #self.labels do self.labels[index]:Hide() end
        if self.snapshot then self:Render(self.snapshot, self.values) end
    end

    function view:Render(snapshot, values)
        self.snapshot, self.values = snapshot, values
        local config = self.config
        local fraction = snapshot.maximum > 0 and math.min(1, snapshot.current / snapshot.maximum) or 1
        self.fill:SetValue(fraction)
        local restedEnd = snapshot.maximum > 0 and math.min(1, (snapshot.current + (snapshot.rested or 0)) / snapshot.maximum) or fraction
        self.rested:SetShown(config.showRested and restedEnd > fraction)
        if restedEnd > fraction then
            self.rested:ClearAllPoints(); self.rested:SetPoint("LEFT", self, "LEFT", self:GetWidth() * fraction, 0)
            self.rested:SetSize(self:GetWidth() * (restedEnd - fraction), self:GetHeight())
        end
        for index, entry in ipairs(config.fields) do
            if entry.enabled then self.labels[index]:SetText(ns.ProgressModel.Format(entry.template, values)) end
        end
    end
    UI:Bind(view, function(self) if self.config then self:Apply(self.config, self.editing) end end)
    return view
end

local _, ns = ...
local UI = ns.UI
local D = ns.DesignSystem.Metrics

local function previewFont(region,font)
    local ok=pcall(ns.Theme.Font,ns.Theme,region,D.ToNative(15),font)
    if not ok then pcall(region.SetFont,region,"Fonts\\FRIZQT__.TTF",D.ToNative(15),"") end
end
local function label(text) return type(text)=="string" and text:gsub("|","||") or "—" end

function UI:CloseDropdown()
    if self.dropdown then self.dropdown:Hide(); self.dropdown.owner = nil end
end

local function createPopup()
    local root = CreateFrame("Frame", "BVAddonSuiteDropdown", UIParent)
    root:Hide()
    root:SetAllPoints(UIParent)
    root:SetFrameStrata("TOOLTIP")
    root:EnableMouse(true)
    root:SetScript("OnMouseDown", function() UI:CloseDropdown() end)
    root:EnableKeyboard(not InCombatLockdown())
    root:SetScript("OnShow",function(self) self:EnableKeyboard(not InCombatLockdown()); UI:SetKeyboardPropagation(self,true) end)
    root:SetScript("OnKeyDown", function(self, key)
        UI:SetKeyboardPropagation(self,key ~= "ESCAPE")
        if key == "ESCAPE" then UI:CloseDropdown() end
    end)
    root.menu = UI:Panel(root, 300, 280, "raised")
    root.menu:SetClampedToScreen(true)
    root.menu:EnableMouse(true)
    root.menu:EnableMouseWheel(true)
    root.rows = {}
    root.hint = UI:Label(root.menu, "", 12, "muted")
    D.Point(root.hint,"BOTTOM", 0, 6)
    for index = 1, 8 do
        local row = UI:Button(root.menu, "", 288, function()
            local owner, option = root.owner, root.rows[index].option
            UI:CloseDropdown()
            if owner and option then
                owner:SetValue(option.value)
                ns:Call("dropdown", owner.callback or owner.changed, option.value)
            end
        end)
        D.Height(row,30)
        D.Point(row,"TOPLEFT", 6, -6 - (index - 1) * 32)
        row.label:ClearAllPoints(); D.Point(row.label,"LEFT", 10, 0)
        row.label:SetJustifyH("LEFT"); row.label:SetJustifyV("MIDDLE"); D.Height(row.label,26)
        row.sample = row:CreateTexture(nil, "ARTWORK")
        D.Point(row.sample,"RIGHT", -8, 0); D.Size(row.sample,54, 12)
        root.rows[index] = row
    end
    function root:RefreshRows()
        local owner = self.owner
        if not owner then return end
        local count = math.min(8, #owner.options)
        local width = owner.menuWidth or D.GetWidth(owner)
        local step=owner.contextMenu and 28 or 32
        D.Size(self.menu,width,count*step+(owner.contextMenu and #owner.options<=8 and 12 or 32))
        for index, row in ipairs(self.rows) do
            local option = index <= count and owner.options[self.offset + index] or nil
            row.option = option
            row.presentationKind=owner.contextMenu and "menu" or nil
            row.danger=option and option.danger
            D.Height(row,step-2);row:ClearAllPoints();D.Point(row,"TOPLEFT",6,-6-(index-1)*step)
            row:SetShown(option ~= nil)
            if option then
                D.Width(row,width - 12)
                row:SetLabelInsets(10,option.texture and 84 or 26,"LEFT")
                row:SetLabelText(label(option.label))
                previewFont(row.label,option.font)
                row.sample:SetShown(option.texture ~= nil)
                if option.texture then local ok,ready=pcall(row.sample.SetTexture,row.sample,option.texture);row.sample:SetShown(ok and ready~=false) else row.sample:SetTexture(nil) end
                row:SetSelected(option.value == owner.value)
            end
        end
        self.hint:SetText(#owner.options > 8 and "Scroll for more" or "Click to select")
        self.hint:SetShown(not owner.contextMenu or #owner.options>8)
    end
    root.menu:SetScript("OnMouseWheel", function(_, delta)
        root.offset = math.max(0, math.min(math.max(0, #root.owner.options - 8), root.offset - delta))
        root:RefreshRows()
    end)
    UI.dropdown = root
    return root
end

function UI:OpenDropdown(host)
        if UI.dropdown and UI.dropdown:IsShown() and UI.dropdown.owner == host then UI:CloseDropdown(); return end
        if host.optionsProvider then host:SetOptions(host.optionsProvider());host:SetValue(host.value) end
        if #host.options == 0 then return end
        local popup = UI.dropdown or createPopup()
        -- Dropdowns can originate inside TOOLTIP-strata pickers. Place the
        -- pooled menu and its click shield above that owned branch on each open;
        -- a fixed UIParent-relative level would put them behind picker rows.
        local anchor = host.anchor or host
        local branch = anchor
        while branch:GetParent() and branch:GetParent() ~= UIParent
            and branch:GetParent():GetFrameStrata() == "TOOLTIP" do
            branch = branch:GetParent()
        end
        local highest = 0
        local function measure(frame)
            if not frame:IsShown() then return end
            if frame:GetFrameStrata() == "TOOLTIP" then highest = math.max(highest,frame:GetFrameLevel()) end
            for _,child in ipairs({frame:GetChildren()}) do measure(child) end
        end
        measure(branch)
        popup:SetFrameLevel(highest + 1)
        popup.owner = host
        popup.offset = math.max(0, math.min((host.index or 1) - 1, #host.options - 8))
        popup.menu:SetScale(host:GetEffectiveScale() / UIParent:GetEffectiveScale())
        popup.menu:ClearAllPoints()
        D.Point(popup.menu,"TOPLEFT", host.anchor or host, "BOTTOMLEFT", 0, -4)
        popup:RefreshRows()
        popup:Show()
end

-- Context commands use the same shield, pooled rows and dismissal as dropdowns.
-- The session is immutable, so a reused anchor cannot redirect its callback.
function UI:ContextMenu(anchor,options,callback)
    self:CloseDropdown()
    local session={anchor=anchor,options=options,callback=callback,menuWidth=260,contextMenu=true}
    function session:GetEffectiveScale() return self.anchor:GetEffectiveScale() end
    function session:SetValue() end
    if not anchor.contextMenuHooked then
        anchor.contextMenuHooked=true
        anchor:HookScript("OnHide",function()
            if UI.dropdown and UI.dropdown.owner and UI.dropdown.owner.anchor==anchor then UI:CloseDropdown() end
        end)
    end
    self:OpenDropdown(session)
end

function UI:Dropdown(parent, width, options, callback)
    local host=self:GetStyle():Dropdown(parent,width or 300,options,nil,callback)
    host.options, host.callback = options, callback
    host:SetLabelInsets(12,32,"LEFT")
    function host:SetOptionsProvider(provider) self.optionsProvider=provider end
    function host:SetOptions(items)
        self.options = items
        if UI.dropdown and UI.dropdown.owner == self then UI:CloseDropdown() end
    end
    function host:SetValue(value)
        self.value = value
        if self.sample then self.sample:Hide();self.sample:SetTexture(nil) end
        self:SetLabelInsets(12,32,"LEFT")
        for index, option in ipairs(self.options) do
            if option.value == value then
                self.index = index; self:SetLabelText(label(option.label))
                if option.texture then
                    if not self.sample then self.sample=self:CreateTexture(nil,"OVERLAY");D.Point(self.sample,"RIGHT",-29,0);D.Size(self.sample,48,10) end
                    self:SetLabelInsets(12,86,"LEFT")
                    local ok,ready=pcall(self.sample.SetTexture,self.sample,option.texture);self.sample:SetShown(ok and ready~=false)
                end
                return
            end
        end
        self.index = nil; self:SetLabelText(type(value)=="string" and "Missing: "..label(value) or "—")
    end
    host:HookScript("OnHide", function(self)
        if UI.dropdown and UI.dropdown.owner == self then UI:CloseDropdown() end
    end)
    return host
end

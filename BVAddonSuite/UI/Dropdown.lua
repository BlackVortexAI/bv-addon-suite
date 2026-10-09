local _, ns = ...
local UI = ns.UI
local D = ns.DesignSystem.Metrics

local function previewFont(region,font,style)
    -- Without a font preview the row keeps its style's font (in-game families).
    if not font and style then style:Font(region,13);return end
    local ok=pcall(ns.Theme.Font,ns.Theme,region,D.ToNative(13),font)
    if not ok then pcall(region.SetFont,region,"Fonts\\FRIZQT__.TTF",D.ToNative(13),"") end
end
local function label(text) return type(text)=="string" and text:gsub("|","||") or "—" end

function UI:CloseDropdown()
    if self.dropdown then self.dropdown:Hide(); self.dropdown.owner = nil end
end

-- One pooled popup per style: the tool style keeps its global name; lists of
-- in-game controls open in their family (UI.dropdown = the current popup).
local function createPopup(style)
    local tools = style == UI:ToolStyle()
    local root = CreateFrame("Frame", tools and "BVAddonSuiteDropdown" or nil, UIParent)
    root.style = style
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
    -- Command menus show up to 16 entries so nothing hides below a silent
    -- scroll; value dropdowns keep 8 rows plus the scroll hint.
    for index = 1, 16 do
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
        -- Current value: thin accent bar at the left edge.
        row.mark = row:CreateTexture(nil, "OVERLAY")
        D.Point(row.mark,"TOPLEFT",0,-4); D.Point(row.mark,"BOTTOMLEFT",0,4); D.Width(row.mark,2)
        row.mark:Hide()
        row.sample = row:CreateTexture(nil, "ARTWORK")
        D.Point(row.sample,"RIGHT", -8, 0); D.Size(row.sample,54, 12)
        root.rows[index] = row
    end
    function root:RefreshRows()
        local owner = self.owner
        if not owner then return end
        local visible = owner.menuRows or 8
        local count = math.min(visible, #owner.options)
        local width = owner.menuWidth or D.GetWidth(owner)
        -- Compact list (0.8.73): 26-unit rows in a 4-unit frame, no per-row borders.
        local step=26
        local overflow=#owner.options>visible
        D.Size(self.menu,width,count*step+8+(overflow and 22 or 0))
        for index, row in ipairs(self.rows) do
            local option = index <= count and owner.options[self.offset + index] or nil
            row.option = option
            row.presentationKind="menu"
            row.danger=option and option.danger
            D.Height(row,step-2);row:ClearAllPoints();D.Point(row,"TOPLEFT",4,-4-(index-1)*step)
            row:SetShown(option ~= nil)
            if option then
                D.Width(row,width - 8)
                row:SetLabelInsets(10,option.texture and 84 or 26,"LEFT")
                row:SetLabelText(label(option.label))
                previewFont(row.label,option.font,not tools and style or nil)
                row.sample:SetShown(option.texture ~= nil)
                if option.texture then local ok,ready=pcall(row.sample.SetTexture,row.sample,option.texture);row.sample:SetShown(ok and ready~=false) else row.sample:SetTexture(nil) end
                local current=not owner.contextMenu and option.value == owner.value
                row:SetSelected(current); row.mark:SetColorTexture(style:Color("accent")); row.mark:SetShown(current)
            end
        end
        self.hint:SetText("Scroll for more")
        self.hint:SetShown(overflow)
    end
    root.menu:SetScript("OnMouseWheel", function(_, delta)
        root.offset = math.max(0, math.min(math.max(0, #root.owner.options - (root.owner.menuRows or 8)), root.offset - delta))
        root:RefreshRows()
    end)
    UI.dropdowns = UI.dropdowns or {}
    UI.dropdowns[style] = root
    return root
end
local function popupFor(host)
    local style = host.bvStyle or UI:ToolStyle()
    local popup = UI.dropdowns and UI.dropdowns[style]
    if not popup then popup = UI:WithStyle(style, createPopup, style) end
    if UI.dropdown and UI.dropdown ~= popup then UI:CloseDropdown() end
    UI.dropdown = popup
    return popup
end

function UI:OpenDropdown(host)
        if UI.dropdown and UI.dropdown:IsShown() and UI.dropdown.owner == host then UI:CloseDropdown(); return end
        if host.optionsProvider then host:SetOptions(host.optionsProvider());host:SetValue(host.value) end
        if #host.options == 0 then return end
        local popup = popupFor(host)
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
        popup.offset = math.max(0, math.min((host.index or 1) - 1, #host.options - (host.menuRows or 8)))
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
    local session={anchor=anchor,options=options,callback=callback,menuWidth=260,contextMenu=true,menuRows=16}
    -- An in-game window sets anchor.bvMenuStyle: its context menu opens in that style.
    session.bvStyle=anchor.bvMenuStyle
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
                    if not self.sample then self.sample=self:CreateTexture(nil,"OVERLAY") end
                    self.sample:ClearAllPoints()
                    -- Narrow fields (node cards): a thin preview strip along the
                    -- bottom keeps the full width for long names such as
                    -- "Alu One Soft Light Bevel"; wide fields keep the swatch.
                    if D.GetWidth(self)<300 then
                        D.Point(self.sample,"BOTTOMLEFT",10,4);D.Point(self.sample,"BOTTOMRIGHT",-26,4);D.Height(self.sample,3);self:SetLabelInsets(10,24,"LEFT")
                        UI:GetStyle():Font(self.label,12);self:SetLabelText(label(option.label))
                    else
                        D.Point(self.sample,"RIGHT",-29,0);D.Size(self.sample,48,10);self:SetLabelInsets(12,86,"LEFT")
                    end
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

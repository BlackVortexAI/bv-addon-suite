local ns = BVAddonSuiteCore
local I = ns and ns.Bags and ns.Bags.Inventory
if not I then return end
local UI, M = ns.UI, ns.DesignSystem.Metrics

local function available(source)
    if not source or (InCombatLockdown and InCombatLockdown()) then return false end
    if (GetCursorInfo and GetCursorInfo()) or (CursorHasItem and CursorHasItem()) then return false end
    local read, identify = I.API("GetContainerItemInfo"), I.API("GetContainerItemID")
    if not read or not identify or identify(source.bag, source.slot) ~= source.id then return false end
    local info, count, locked, _, _, _, link = read(source.bag, source.slot)
    if type(info) == "table" then count, locked, link = info.stackCount, info.isLocked, info.hyperlink end
    return info ~= nil and not locked and count == source.count and (not source.link or source.link == link)
end

local function build()
    local style = UI:GetStyle()
    local w = UI:Window("BVInventorySplit", 292, 204, {title="Split stack", compact=true, hudIcon="layers", minWidth=292, minHeight=204})
    w:SetFrameStrata("FULLSCREEN_DIALOG")
    w:SetResizable(false)
    w.resizeGrip:Hide()
    UI:WindowReadingSurface(w, style)
    UI:ScopeDialogEscape(w)
    local content = w.content
    local function at(control, x, y)
        M.Point(control, "TOPLEFT", content, "TOPLEFT", x, -y)
        return control
    end
    local icon = at(content:CreateTexture(nil, "ARTWORK"), 12, 9)
    M.Size(icon, 29, 29)
    local name = at(UI:Label(content, "", 14, "text", true), 49, 7)
    M.Width(name, 219)
    name:SetWordWrap(false)
    name:SetJustifyH("LEFT")
    local details = at(UI:Label(content, "", 12, "muted"), 49, 25)
    at(UI:Label(content, "Quantity", 13, "text"), 12, 55)
    local amount = at(UI:Input(content, 84), 91, 49)
    amount:SetNumeric(true)
    amount:SetMaxLetters(8)
    w:TrackEscapeInput(amount)
    local preview = at(UI:Label(content, "", 12, "muted"), 12, 94)
    local function quantity()
        local n = tonumber(amount:GetText())
        if w.source and n and n == math.floor(n) and n > 0 and n < w.source.count then return n end
    end
    local function update()
        if not w.source then return end
        local n = quantity()
        preview:SetText(n and ("%d to cursor   ·   %d stay here"):format(n, w.source.count-n)
            or ("Choose an amount from 1 to %d."):format(w.source.count-1))
        if n then w.confirm:Enable() else w.confirm:Disable() end
    end
    local function change(n)
        if w.source then amount:SetText(tostring(math.max(1, math.min(w.source.count-1, n)))); update() end
    end
    local function stepButton(icon, delta, x, hint)
        local button = at(UI:IconButton(content, icon, function()
            change((tonumber(amount:GetText()) or 0) + delta)
        end, "icon-only"), x, 49)
        M.Size(button, 28, 28)
        UI:AttachTooltip(button, hint)
    end
    stepButton("arrow-down", -1, 180, "Take one fewer")
    stepButton("arrow-up", 1, 212, "Take one more")
    local function confirm()
        local source, n = w.source, quantity()
        if not n then return end
        local split = I.API("SplitContainerItem")
        if not split or not available(source) then
            w:Hide()
            ns:Print("Cannot split this stack now. Check the stack and your cursor.")
            I.full=true; I:Refresh()
            return
        end
        w:Hide()
        split(source.bag, source.slot, n)
        I.full=true; I:Refresh()
    end
    at(UI:Button(content, "Cancel", 91, function() w:Hide() end), 12, 125)
    w.confirm = at(UI:Button(content, "Split stack", 132, confirm, "primary"), 136, 125)
    amount:SetScript("OnEnterPressed", confirm)
    amount:HookScript("OnTextChanged", update)
    w:HookScript("OnHide", function() w.source=nil; amount:ClearFocus() end)
    function w:Open(source)
        self.source = {bag=source.bag, slot=source.slot, id=source.id, link=source.link, count=source.count}
        icon:SetTexture(source.icon)
        name:SetText(source.name or ("Item "..source.id))
        details:SetText(("%d in stack   ·   Bag %d, slot %d"):format(source.count, source.bag, source.slot))
        change(math.floor(source.count/2))
        self:ClearAllPoints()
        self:SetPoint("CENTER", I.window, "CENTER")
        self:Show()
        UI:FocusWindow(self)
        amount:SetFocus(); amount:HighlightText()
    end
    return w
end

function I:OpenSplit(source)
    if not self.window or not self.window:IsShown() or source.count < 2 or not available(source) then return end
    if not self.splitWindow then self.splitWindow = UI:WithStyle(UI:ToolStyle(), build) end
    self.splitWindow:Open(source)
end

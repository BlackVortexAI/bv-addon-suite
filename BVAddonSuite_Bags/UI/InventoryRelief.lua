local ns = BVAddonSuiteCore
local Bags = ns and ns.Bags
local I = Bags and Bags.Inventory
if not I then return end

local R = {}
I.Relief = R
local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function enabled()
    return ns.ready and I:Config().lootRelief ~= false
end
local function lastBag() return NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 end

-- Gather's T.Price returns one quote according to its own settings. Bags also
-- works without Gather and needs each independent quote for the comparison.
local function quote(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, price = pcall(fn, ...)
    if ok and type(price) == "number" and price > 0 and price < math.huge then return price end
end
function I:MarketQuote(source,id)
    if not id then return end
    if source=="tsm" or source=="buyout" then
        return quote(TSM_API and TSM_API.GetCustomPriceValue,source=="tsm" and "dbmarket" or "dbminbuyout","i:"..id)
    elseif source=="auction" then
        local auc=Auctionator and Auctionator.API and Auctionator.API.v1
        return quote(auc and auc.GetAuctionPriceByItemID,"BV Addon Suite",id)
    elseif source=="blackthorn" then
        return quote(BlackthornesTS_API and BlackthornesTS_API.GetPrice,id)
    end
end
function R.Prices(id, vendor)
    return {
        vendor = vendor,
        tsm = I:MarketQuote("tsm",id),
        auction = I:MarketQuote("auction",id),
        blackthorn = I:MarketQuote("blackthorn",id),
    }
end

local function full()
    local free = I.API("GetContainerNumFreeSlots")
    if not free then return false end
    for bag = 0, lastBag() do
        local count, family = free(bag)
        if type(count) ~= "number" or ((family or 0) == 0 and count > 0) then return false end
    end
    return true
end

local function snapshot(bag, slot)
    local read = I.API("GetContainerItemInfo")
    local row = read and read(bag, slot)
    if type(row) ~= "table" or row.isLocked or not row.itemID or not row.hyperlink
        or type(row.stackCount) ~= "number" or row.stackCount < 1 then return end
    if I:Config().pins[row.itemID] then return end
    local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not getInfo then return end
    local name, _, quality, _, _, _, _, _, equip, _, vendor, class, _, bind = getInfo(row.hyperlink)
    if not name or type(quality) ~= "number" or quality >= 3 or type(class) ~= "number"
        or class == 12 or bind == 4 or type(vendor) ~= "number" or vendor < 0
        or (row.isBound and equip and equip ~= "") then return end
    local quest = I.API("GetContainerItemQuestInfo")
    local questInfo = quest and quest(bag, slot)
    if questInfo and (questInfo.isQuestItem or questInfo.questID or questInfo.isActive) then return end
    local guid
    if ItemLocation and ItemLocation.CreateFromBagAndSlot and C_Item and C_Item.GetItemGUID then
        guid = C_Item.GetItemGUID(ItemLocation:CreateFromBagAndSlot(bag, slot))
    end
    return {bag=bag, slot=slot, id=row.itemID, link=row.hyperlink, count=row.stackCount,
        icon=row.iconFileID, name=name, vendor=vendor, guid=guid}
end

local function matches(item)
    if not item then return false end
    local now = snapshot(item.bag, item.slot)
    return now and now.id == item.id and now.link == item.link and now.count == item.count and now.guid == item.guid
end

function R.Candidates()
    local list, cache = {}, {}
    local count, free = I.API("GetContainerNumSlots"), I.API("GetContainerNumFreeSlots")
    if not count or not free then return list end
    for bag = 0, lastBag() do
        local _, family = free(bag)
        if (family or 0) == 0 then
            for slot = 1, count(bag) or 0 do
                local item = snapshot(bag, slot)
                if item then
                    local p = cache[item.link] or R.Prices(item.id, item.vendor)
                    cache[item.link], item.prices = p, p
                    item.value = item.count * math.max(p.vendor, p.tsm or 0, p.auction or 0, p.blackthorn or 0)
                    list[#list+1] = item
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if a.bag ~= b.bag then return a.bag < b.bag end
        return a.slot < b.slot
    end)
    for i = #list, 5, -1 do list[i] = nil end
    return list
end

local function money(value)
    if GetCoinTextureString then return GetCoinTextureString(math.floor(value), 10) end
    return tostring(math.floor(value)) .. "c"
end
local function showPrices(row)
    local item = row.item
    if not item then return end
    GameTooltip:SetOwner(row,"ANCHOR_LEFT")
    GameTooltip:SetText(item.name .. " x" .. item.count)
    GameTooltip:AddLine(("Bag %d, slot %d"):format(item.bag,item.slot))
    for _,source in ipairs({{"Sell","vendor"},{"TSM","tsm"},{"Auctionator","auction"},{"Blackthornes","blackthorn"}}) do
        local price=item.prices[source[2]]
        if price then GameTooltip:AddDoubleLine(source[1],money(price*item.count),1,1,1,1,.83,.48) end
    end
    GameTooltip:Show()
end

function R:Close()
    self.failed = false
    self.dismissed = true
    if self.window then self.window:Hide() end
end

function R:Ask(item)
    local pickup = I.API("PickupContainerItem")
    if not self.failed or not enabled() or inCombat() or not full() or not matches(item) then
        self:Refresh()
        return
    end
    if not (pickup and GetCursorInfo and ClearCursor and StaticPopup_Show) then return end
    if GetCursorInfo() or (CursorHasItem and CursorHasItem()) then return end
    if SpellIsTargeting and SpellIsTargeting() then return end

    -- Eligible candidates are non-quest items below rare quality. Forever uses
    -- DELETE_ITEM for exactly this case. Its own Yes/Cancel handlers delete or
    -- return the held stack on a separate hardware click.
    pickup(item.bag,item.slot)
    local kind,id=GetCursorInfo()
    if kind and (kind~="item" or id~=item.id) then ClearCursor();return end
    local location=C_Cursor and C_Cursor.GetCursorItem and C_Cursor.GetCursorItem()
    if location and location.GetBagAndSlot then
        local bag,slot=location:GetBagAndSlot()
        if bag~=item.bag or slot~=item.slot then ClearCursor();return end
    end
    local ok,popup=pcall(StaticPopup_Show,"DELETE_ITEM",item.link.." × "..item.count)
    if not ok or not popup then
        ClearCursor()
        ns:Print("The deletion prompt could not open. The stack was returned.")
    end
end

local function build()
    local ui, m = ns.UI, ns.DesignSystem.Metrics
    local w = ui:Dialog("BVInventoryRelief", 344, 230, nil, {escapeScope=true})
    R.window, R.rows = w, {}
    w:ClearAllPoints(); m.Point(w,"RIGHT",UIParent,"RIGHT",-24,-36)
    w.title:SetText("Bags full")
    local hint = ui:Label(w.content, "Lowest stack values first. Hover for all prices.", 12)
    m.Point(hint,"TOPLEFT", 12, -6)
    R.empty = ui:Label(w.content, "No eligible stacks. Quest items, rare items, pinned items and bound equipment are protected.", 12)
    m.Point(R.empty,"TOPLEFT",12,-40); m.Width(R.empty,310)
    for index = 1, 4 do
        local row = CreateFrame("Frame", nil, w.content)
        R.rows[index] = row
        m.Point(row,"TOPLEFT",12,-29-(index-1)*40)
        m.Point(row,"TOPRIGHT",-12,-29-(index-1)*40); m.Height(row,37)
        row.icon = row:CreateTexture(nil,"ARTWORK"); m.Size(row.icon,28,28); row.icon:SetPoint("TOPLEFT")
        row.name = ui:Label(row,"",13); m.Point(row.name,"TOPLEFT",36,0); m.Point(row.name,"TOPRIGHT",-80,0)
        row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
        row.prices = ui:Label(row,"",11); m.Point(row.prices,"TOPLEFT",36,-16)
        row:EnableMouse(true)
        row:SetScript("OnEnter",showPrices)
        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
        row.button = ui:Button(row,"Delete...",74,function() R:Ask(row.pressed or row.item); row.pressed=nil end)
        row.button:HookScript("OnMouseDown",function() row.pressed=row.item end)
        row.button:SetPoint("TOPRIGHT")
    end
    w:HookScript("OnHide",function() R.failed=false; R.dismissed=true end)
end

function R:Refresh()
    if not self.failed or self.dismissed or not enabled() or inCombat() or not full() then self:Close(); return end
    if not self.window then build() end
    local items = self.Candidates()
    for index, row in ipairs(self.rows) do
        local item = items[index]; row.item=item
        if item then
            row.name:SetText(("%s x%d"):format(item.name,item.count)); row.icon:SetTexture(item.icon)
            row.prices:SetText(money(item.value)); row:Show()
        else row:Hide() end
    end
    self.empty:SetShown(#items == 0)
    self.window:Show()
end
function R:Queue()
    if self.timer then return end
    self.timer=C_Timer.NewTimer(.12,function() self.timer=nil; self:Refresh() end)
end
local function event(e, code, message)
    if e=="LOOT_OPENED" or e=="LOOT_READY" then
        R.looting=true; R.dismissed=false
    elseif e=="LOOT_CLOSED" then
        if R.looting then R.closedAt=GetTime() end
        R.looting=false
    elseif e=="PLAYER_LEAVING_WORLD" or e=="PLAYER_REGEN_DISABLED" then
        R.looting=false; R.closedAt=nil; R:Close()
    elseif e=="UI_ERROR_MESSAGE" then
        -- Autoloot can close its window before the server rejects the pickup.
        if R.dismissed or not (R.looting or (R.closedAt and GetTime()-R.closedAt<=1)) then return end
        local invError = Enum and Enum.GameError and Enum.GameError.InvFull or LE_GAME_ERR_INV_FULL
        if ((ERR_INV_FULL and message==ERR_INV_FULL) or (invError and code==invError)) and enabled() and not inCombat() then
            R.failed=true; R:Queue()
        end
    elseif R.failed then
        if e=="BAG_UPDATE_DELAYED" or e=="GET_ITEM_INFO_RECEIVED" then R:Queue() end
    end
end
for _, e in ipairs({"LOOT_READY","LOOT_OPENED","LOOT_CLOSED","UI_ERROR_MESSAGE","BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED","PLAYER_REGEN_DISABLED","PLAYER_LEAVING_WORLD"}) do ns.Events:Subscribe(R,e,event) end
if ns.Settings.BeforeProfileChange then ns.Settings:BeforeProfileChange(R,function() R.looting=false; R:Close() end) end

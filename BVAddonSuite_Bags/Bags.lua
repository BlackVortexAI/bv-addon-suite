local package=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.89 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.8.89","0.8.89",1) then return end
local N=ns.NativeButtons

-- Blizzard's bag buttons, backpack last (it sits at the right end natively).
local fallback={"CharacterReagentBag0Slot","CharacterBag3Slot","CharacterBag2Slot","CharacterBag1Slot","CharacterBag0Slot","MainMenuBarBackpackButton"}
local function buttons()
    local list,seen={},{}
    local manager=MainMenuBarBagManager
    if manager and manager.EnumerateBagButtons then
        pcall(function() for _,button in manager:EnumerateBagButtons() do table.insert(list,1,button) end end)
    end
    if #list==0 then for _,name in ipairs(fallback) do if type(_G[name])=="table" then list[#list+1]=_G[name] end end end
    for _,button in ipairs(list) do seen[button]=true end
    if type(KeyRingButton)=="table" and not seen[KeyRingButton] then table.insert(list,1,KeyRingButton) end
    return list
end
local function entries()
    local out={}
    for _,button in ipairs(buttons()) do
        local name=button.GetName and button:GetName()
        local icon=button.icon or name and _G[name.."IconTexture"]
        local keep={}
        if icon then keep[icon]=true end
        -- Bag-open highlight and the new-item animation stay Blizzard's.
        for _,key in ipairs({"SlotHighlightTexture","AnimIcon"}) do if button[key] then keep[button[key]]=true end end
        out[#out+1]={key=name,button=button,icon=icon,art=N.Art(button,keep)}
    end
    -- Blizzard's collapse arrow would hide slots we lay out; parked while we run.
    if type(BagBarExpandToggle)=="table" then
        out[#out+1]={key="BagBarExpandToggle",button=BagBarExpandToggle,hidden=true,plain=true}
    end
    return out
end
local function freeSlots()
    local containers=C_Container
    if not containers or not containers.GetContainerNumFreeSlots then return "" end
    local free=0
    for bag=0,(NUM_BAG_SLOTS or 4) do
        local ok,count=pcall(containers.GetContainerNumFreeSlots,bag)
        if ok and type(count)=="number" then free=free+count end
    end
    return tostring(free)
end

local Bags=N:Bar({
    id="bag_bar",layout="bv:bags",label="Bag Bar",anchor="BOTTOMRIGHT",x=-8,y=48,
    defaults={enabled=false,skin="obsidian",shape="square",size=30,spacing=4,perLine=8,vertical=false,
        fade=false,fadeAlpha=.25,collapsed=false,flyout="UP",showCount=true},
    entries=entries,
    -- Blizzard's bar frame and the dividers between the bag buttons.
    decor=function()
        local list={}
        if BagsBar and BagsBar.BorderArt then list[#list+1]=BagsBar.BorderArt end
        for _,key in ipairs({"HorizontalDividersPool","VerticalDividersPool"}) do
            local pool=BagsBar and BagsBar[key]
            if pool and pool.EnumerateActive then for divider in pool:EnumerateActive() do list[#list+1]=divider end end
        end
        return list
    end,
    main={symbol="backpack",label="Bags",hint="Left-click: open or close all bags\nRight-click: keep the bag slots open\nHover: bag slots",
        text=freeSlots,
        click=function()
            if ToggleAllBags then ToggleAllBags() elseif OpenAllBags then OpenAllBags() end
        end},
    events={"BAG_UPDATE_DELAYED"},
    onEvent=function(bar) bar:UpdateText() end,
    install=function(bar)
        -- BagsBar:Layout re-anchors the buttons; lay them out again right after.
        if BagsBar and type(BagsBar.Layout)=="function" then
            hooksecurefunc(BagsBar,"Layout",function() if bar.active then bar:Arrange() end end)
        end
    end,
    restore=function()
        if BagsBar and BagsBar.Layout then BagsBar:Layout() end
    end,
})
-- A bag bar collapsed with Blizzard's arrow hides the slots. Expand it while the
-- module runs and collapse it again afterwards (cleanups run in reverse order).
local function expandNative(context)
    local toggle,slot=BagBarExpandToggle,CharacterBag0Slot
    if type(toggle)~="table" or type(slot)~="table" or slot:IsShown() or type(toggle.Click)~="function" then return end
    toggle:Click()
    context:Defer(function() if slot:IsShown() then toggle:Click() end end)
end
ns.Modules:Register({id="bag_bar",OnEnable=function(context) expandNative(context);Bags:Enable(context) end})
local page
ns.Config:RegisterPage("bags",{title="Bag Bar",description="Skinned bag slots anywhere on screen, or a single bag button.",
    build=function(parent)
        if not page then
            page=ns.UI:NativeBarPage(parent,Bags,function(p,cfg,changed)
                local g=p.grid
                p:Section("onebutton","One-button mode")
                p.collapsed=p:Row("One button",ns.UI:Switch(g,false,function(value) cfg().collapsed=value;changed() end),
                    "Click opens all bags; the bag slots appear on hover.")
                p.flyout=p:Row("Bag slots open",ns.UI:Dropdown(g,170,{{value="UP",label="Upwards"},{value="DOWN",label="Downwards"},
                    {value="LEFT",label="To the left"},{value="RIGHT",label="To the right"}},function(value) cfg().flyout=value;changed() end),
                    "Direction in which the bag slots open from the single button.")
                p.count=p:Row("Show free slots",ns.UI:Switch(g,true,function(value) cfg().showCount=value;changed() end),
                    "Number of free bag slots on the single button.")
                function p:RefreshExtra(c) self.collapsed:SetValue(c.collapsed);self.flyout:SetValue(c.flyout);self.count:SetValue(c.showCount) end
            end)
        end
        return page
    end,
    refresh=function() if page then page:Refresh() end end})
ns.Commands:Register("bags","bag_bar","bags")
ns.Bags=Bags
if ns.ready and IsLoggedIn() then ns.Modules:Reconcile() end

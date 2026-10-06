local _,L=...
if not L.ready then return end
-- Roll bars (point 1): native group loot rolls and BV roll requests share one
-- bar: item icon with item level, name over a draining quality bar, binding
-- tag and the option buttons with how many players chose each option.
-- Optional info block to the left: item kind ("Leather") and primary stats.
local ns=L.ns
local UI,Theme,D=ns.UI,ns.Theme,ns.DesignSystem.Metrics
local W,R=L.Widgets,L.Rolls
local F={bars={}}
L.RollFrame=F
local INFO=150

local function geometry(cfg)
    local h=cfg.rollHeight
    local barH=math.max(6,math.floor(h*.34+.5))
    return h,barH,h-barH-2,math.floor(h*.64+.5)
end
local function sampleRolls()
    local rolls={}
    local samples={{19019,"Thunderfury, Blessed Blade of the Windseeker",5,"Interface\\Icons\\INV_Sword_39",1,{need=4,greed=1,pass=2}},
        {16909,"Bloodfang Pants",4,"Interface\\Icons\\INV_Pants_06",1,{need=1,greed=4,pass=0}},
        {18832,"Brutality Blade",4,"Interface\\Icons\\INV_Sword_43",0,{need=0,greed=2,pass=3}}}
    for index,s in ipairs(samples) do
        local roll={key="preview:"..index,kind="native",id=-index,itemID=s[1],link="item:"..s[1],name=s[2],quality=s[3],icon=s[4],bop=s[5]==1,
            options=L.NATIVE_ORDER,enabled={need=true,greed=true,disenchant=index~=3,pass=true},reasons={},choices={},names={},
            duration=60,ends=GetTime()+60-index*12,preview=true}
        for option,count in pairs(s[6]) do
            for n=1,count do local name=option..n;roll.names[#roll.names+1]=name;roll.choices[name]={name=name,choice=option} end
        end
        rolls[#rolls+1]=roll
    end
    return rolls
end

function F:Bar(index)
    local bar=self.bars[index]
    if bar then return bar end
    bar=W.Owned(CreateFrame("Frame",nil,self.anchor.frame));bar:Hide();bar:EnableMouse(true)
    bar.bg=bar:CreateTexture(nil,"BACKGROUND");bar.bg:SetColorTexture(0,0,0,0)
    -- The whole bar (name, timer) shows the item tooltip, not only the icon;
    -- with results as "tooltip" it shows the roll overview instead (the icon
    -- keeps the item tooltip).
    bar:SetScript("OnEnter",function(owner)
        local cfg=L:Config()
        if cfg.results and cfg.resultsMode=="tooltip" and bar.roll and not bar.roll.preview then
            -- A failure says so in chat instead of showing nothing.
            local ok,err=pcall(L.Results.ShowTip,L.Results,owner,bar.roll)
            if not ok then L:Print("Roll overview failed: "..tostring(err)) end
        else F:ItemEnter(owner,bar.roll) end
    end)
    bar:SetScript("OnLeave",function(owner) W:HideTooltip(owner);L.Results:HideTip(owner) end)
    bar.item=W:ItemIcon(bar,30)
    bar.item:SetScript("OnEnter",function(owner) F:ItemEnter(owner,bar.roll) end)
    bar.item:EnableMouse(true)
    bar.item:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    bar.item:SetScript("OnClick",function()
        local link=bar.roll and bar.roll.link
        if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    bar.bvName=UI:Label(bar,"",12,false,true);bar.bvName:SetWordWrap(false)
    bar.bind=UI:Label(bar,"",11,false,true);bar.bind:SetJustifyH("RIGHT")
    bar.status=CreateFrame("StatusBar",nil,bar);bar.status:SetMinMaxValues(0,1)
    bar.statusBg=bar.status:CreateTexture(nil,"BACKGROUND");bar.statusBg:SetAllPoints(bar.status)
    bar.statusEdge=bar:CreateTexture(nil,"BORDER")
    bar.buttons={}
    for slot=1,6 do
        local b=W:OptionButton(bar,18)
        b:SetScript("OnClick",function(button) if bar.roll and not bar.roll.preview then R:Choose(bar.roll,button.option) end end)
        b:SetScript("OnEnter",function(button) F:OptionEnter(button,bar.roll) end)
        b:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
        bar.buttons[slot]=b
    end
    bar.bvKind=UI:Label(bar,"",17,false,true);bar.bvKind:SetJustifyH("RIGHT");bar.bvKind:SetWordWrap(false)
    bar.stats=UI:Label(bar,"",10,false);bar.stats:SetJustifyH("RIGHT");bar.stats:SetWordWrap(false)
    bar.bvKind:SetTextColor(1,1,1);bar.stats:SetTextColor(.85,.85,.85)
    self.bars[index]=bar
    return bar
end
function F:Layout(bar,cfg)
    local w=self.anchor:Width()
    local h,barH,nameH,button=geometry(cfg)
    D.Size(bar,w,h)
    bar.item:Resize(h);bar.item:ClearAllPoints();D.Point(bar.item,"TOPLEFT",bar,"TOPLEFT",0,0)
    -- Above the bar, which takes the mouse itself (same level: the parent wins).
    bar.item:SetFrameLevel(bar:GetFrameLevel()+3)
    local x=h+4
    bar.status:ClearAllPoints();D.Point(bar.status,"BOTTOMLEFT",bar,"BOTTOMLEFT",x,0);D.Point(bar.status,"BOTTOMRIGHT",bar,"BOTTOMRIGHT",0,0);D.Height(bar.status,barH)
    bar.statusEdge:ClearAllPoints();D.Point(bar.statusEdge,"TOPLEFT",bar.status,"TOPLEFT",-1,1);D.Point(bar.statusEdge,"BOTTOMRIGHT",bar.status,"BOTTOMRIGHT",1,-1)
    bar.statusEdge:SetColorTexture(0,0,0,.85)
    local right=0
    for slot=#bar.buttons,1,-1 do
        local b=bar.buttons[slot]
        b:Resize(button)
        if b:IsShown() then
            b:ClearAllPoints();D.Point(b,"BOTTOMRIGHT",bar,"BOTTOMRIGHT",-right,barH+2);right=right+button+3
        end
    end
    bar.bind:ClearAllPoints();D.Point(bar.bind,"BOTTOMRIGHT",bar,"BOTTOMRIGHT",-right-2,barH+3);D.Size(bar.bind,30,nameH)
    bar.bvName:ClearAllPoints();D.Point(bar.bvName,"BOTTOMLEFT",bar,"BOTTOMLEFT",x+1,barH+2)
    D.Size(bar.bvName,math.max(20,w-x-right-36),nameH)
    bar.bvKind:ClearAllPoints();D.Point(bar.bvKind,"TOPRIGHT",bar,"TOPLEFT",-6,1);D.Size(bar.bvKind,INFO,math.max(14,h*.6))
    bar.stats:ClearAllPoints();D.Point(bar.stats,"BOTTOMRIGHT",bar,"BOTTOMLEFT",-6,0);D.Size(bar.stats,INFO+60,12)
end
function F:Paint(bar,roll,cfg)
    bar.roll=roll
    local info=roll.link and L.Item(roll.link) or {}
    local r,g,b=L.QualityColor(roll.quality or info.quality or 1)
    bar.item:SetItem(roll.icon or info.icon,roll.quality or info.quality,info.level,roll.count)
    bar.bvName:SetText(roll.name or info.name or roll.link or "?");bar.bvName:SetTextColor(r,g,b)
    if roll.kind=="bv" then
        bar.bind:SetText("ML");bar.bind:SetTextColor(Theme:Color("accent"))
    elseif roll.bop then bar.bind:SetText("BoP");bar.bind:SetTextColor(1,.3,.1)
    else bar.bind:SetText("") end
    local texture=ns.Media:StatusBar(ns.Settings:Get("statusbar"))
    bar.status:SetStatusBarTexture(texture)
    if cfg.rollQualityBar then bar.status:SetStatusBarColor(r,g,b,.85);bar.statusBg:SetColorTexture(r*.2,g*.2,b*.2,.75)
    else bar.status:SetStatusBarColor(UI:RGBA(cfg.rollBarColor));bar.statusBg:SetColorTexture(0,0,0,.6) end
    bar.status:SetMinMaxValues(0,math.max(1,roll.duration or 60))
    for slot,button in ipairs(bar.buttons) do
        local option=roll.options[slot]
        if option then
            local enabled=roll.enabled[option]~=false and not roll.mine and not roll.done
            button:SetOption(option,enabled,R:Count(roll,option),roll.mine==option,L.OptionDef(roll,option))
            button:Show()
        else button.option=nil;button:Hide() end
    end
    local kind=cfg.rollKind and L.ItemKind(info) or nil
    bar.bvKind:SetText(kind or "");bar.stats:SetText(cfg.rollStats and roll.link and L.ItemStats(roll.link) or "")
    bar.bvKind:SetShown(kind~=nil);bar.stats:SetShown(cfg.rollStats)
    self:Layout(bar,cfg)
    self:Tick(bar)
end
function F:Tick(bar)
    local roll=bar.roll
    if not roll then return end
    local left=roll.preview and math.max(0,roll.ends-GetTime()) or R:TimeLeft(roll)
    bar.status:SetValue(left)
end

-- Which rolls get a bar: the oldest first, up to the configured count.
function F:Sync()
    if not self.anchor then return end
    local cfg=L:Config()
    local list={}
    if self.anchor.preview then list=self.samples or sampleRolls();self.samples=list
    elseif L:Active() and cfg.rolls then
        for _,roll in ipairs(R:List()) do if R:Visible(roll) then list[#list+1]=roll end end
    end
    local items={}
    for index=1,math.max(#self.bars,math.min(#list,cfg.rollMax)) do
        local roll=index<=cfg.rollMax and list[index]
        local bar=(roll or self.bars[index]) and self:Bar(index)
        if roll then self:Paint(bar,roll,cfg);bar:Show();items[#items+1]=bar
        elseif bar then bar.roll=nil;bar:Hide() end
        -- The overview tooltip follows its bar: another roll or no bar any more.
        if bar and L.Results.tipOwner==bar then
            if bar.roll and bar:IsShown() then L.Results:ShowTip(bar,bar.roll) else L.Results:HideTip(bar) end
        end
    end
    self.anchor:Arrange(items)
    self:Clock(#items>0)
end
-- Bars drain with a shared 0.1 s ticker that only runs while bars are shown.
function F:Clock(run)
    if run and not self.ticker then
        self.ticker=C_Timer.NewTicker(.1,function()
            for _,bar in ipairs(self.bars) do if bar:IsShown() then self:Tick(bar) end end
        end)
    elseif not run and self.ticker then self.ticker:Cancel();self.ticker=nil end
end

function F:ItemEnter(owner,roll)
    if not roll then return end
    local extra={}
    if roll.kind=="bv" then extra[1]={"Roll requested by "..(roll.owner or "?"),.9,.8,.5} end
    W:ItemTooltip(owner,{link=roll.link,itemID=roll.itemID,rollID=roll.id,native=roll.kind=="native" and not roll.preview,
        roll=roll,source="roll",extra=extra})
end
function F:OptionEnter(button,roll)
    if not roll or not button.option then return end
    local def=L.OptionDef(roll,button.option)
    local lines={}
    if roll.enabled[button.option]==false then
        lines[#lines+1]={roll.reasons[button.option] or (CANNOT_ROLL or "Can't roll"),1,.3,.3}
    end
    local players=R:Players(roll,button.option)
    if #players>0 and #lines>0 then lines[#lines+1]=" " end
    for _,entry in ipairs(players) do
        local r,g,b=L.ClassColor(entry.class)
        lines[#lines+1]={entry.name..(entry.value and ("  "..entry.value) or ""),r,g,b}
    end
    W:TextTooltip(button,def.label,lines)
end

-- Blizzard's own roll frames stay silent while this module shows bars.
local SUPPRESSED={"START_LOOT_ROLL","CANCEL_LOOT_ROLL"}
function F:Suppress(context)
    if not L:Config().hideBlizzard or not UIParent.UnregisterEvent then return end
    local restored={}
    for _,event in ipairs(SUPPRESSED) do
        local registered=not UIParent.IsEventRegistered or UIParent:IsEventRegistered(event)
        if registered then pcall(UIParent.UnregisterEvent,UIParent,event);restored[#restored+1]=event end
    end
    self.suppress=true
    for i=1,(NUM_GROUP_LOOT_FRAMES or 4) do
        local frame=_G["GroupLootFrame"..i]
        if type(frame)=="table" and frame.Hide then
            if not self.hooked and hooksecurefunc then hooksecurefunc(frame,"Show",function(f) if F.suppress then f:Hide() end end) end
            frame:Hide()
        end
    end
    self.hooked=true
    context:Defer(function()
        self.suppress=false
        for _,event in ipairs(restored) do pcall(UIParent.RegisterEvent,UIParent,event) end
    end)
end

function F:Create()
    if self.anchor then return end
    self.anchor=W:Anchor({layout="bv:lootrolls",label="Loot Rolls",screen="TOP",x=0,y=-220,
        width=function() return L:Config().rollWidth end,height=function() return L:Config().rollHeight end,
        grow=function() return L:Config().rollGrow end,spacing=function() return L:Config().rollSpacing end,
        enabled=function() return L:Config().rolls end,
        resized=function(width)
            if ns.Layout.draft then return end
            local cfg=L:Config();cfg.rollWidth=math.floor(width+.5)
        end,
        preview=function() F:Sync() end})
end
function F:Enable(context)
    self:Create()
    L:On("RollUpdated",self,function() F:Sync() end)
    L:On("RollsReset",self,function() F:Sync() end)
    self:Suppress(context)
    context:Defer(function()
        L:Off(self);self:Clock(false)
        for _,bar in ipairs(self.bars) do bar.roll=nil;bar:Hide() end
    end)
    W:Refresh()
    self:Sync()
end
-- The layout element exists from load on, so the Layout Editor knows it.
F:Create()

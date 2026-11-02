local _,L=...
if not L.ready then return end
-- Roll bars (point 1): native group loot rolls and BV roll requests share one
-- bar: item icon with item level, name over a draining quality bar, binding
-- tag and the option buttons with how many players chose each option.
-- Optional info block to the left: item kind ("Leather") and primary stats.
local ns=L.ns
local UI,Theme,D=ns.UI,ns.Theme,ns.DesignSystem.Metrics
local W,R=L.Widgets,L.Rolls
-- Stable slots (0.8.93, Florian's beta raids with 20-30 rolls at once): a
-- shown roll keeps its row until it goes; its row then stays empty until the
-- next waiting roll takes it. Nothing still shown ever moves, except when the
-- player scrolls. rows = virtual positions (roll or false), offset = how far
-- the player scrolled; slot s shows rows[offset+s].
local F={bars={},rows={},offset=0,hidden=0,above=0,below=0}
L.RollFrame=F
local INFO=150
local INTERFACE_TIMER_HEIGHT=10
local INTERFACE_MIN_HEIGHT=28

local function geometry(cfg,interface)
    local h=cfg.rollHeight
    if interface then
        -- A 10px timer, readable caption and the option count's 3px overhang
        -- cannot share a 20px row. Preserve the saved preference, size the
        -- actual row and its slot from this same minimum content footprint.
        h=math.max(INTERFACE_MIN_HEIGHT,h)
        return h,INTERFACE_TIMER_HEIGHT,h-INTERFACE_TIMER_HEIGHT-4,math.min(math.floor(cfg.rollHeight*.64+.5),h-INTERFACE_TIMER_HEIGHT-4)
    end
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
    local captured=W:Style()
    bar=captured and W:Surface(self.anchor.frame,10,10,"roll",captured) or W.Owned(CreateFrame("Frame",nil,self.anchor.frame));bar:Hide();bar:EnableMouse(true)
    local content=bar.content or bar
    -- Optional background (0.8.91) in the family's look; off by default.
    bar.back=bar.materialCarrier or UI:GamePanel(L.ID,bar,10,10,"bg",6,function() return L:Config().rollBgOpacity/100 end)
    bar.back:SetAllPoints(bar);bar.back:EnableMouse(false);bar.back:Hide()
    bar.back.bvFillOverride=function() local c=L:Config();if c.rollBgOwnColor then return UI:RGBA(c.rollBgColor) end end
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
    bar.item=W:ItemIcon(content,30,not captured,captured)
    bar.item:SetScript("OnEnter",function(owner) F:ItemEnter(owner,bar.roll) end)
    bar.item:EnableMouse(true)
    bar.item:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    bar.item:SetScript("OnClick",function()
        local link=bar.roll and bar.roll.link
        if link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(link) end
    end)
    bar.bvName=W:Label(captured,content,"",12,false,true);bar.bvName:SetWordWrap(false)
    bar.bind=W:Label(captured,content,"",11,false,true);bar.bind:SetJustifyH("RIGHT")
    bar.status=CreateFrame("StatusBar",nil,content);bar.status:SetMinMaxValues(0,1);bar.status:EnableMouse(false)
    bar.statusBg=bar.status:CreateTexture(nil,"BACKGROUND");bar.statusBg:SetAllPoints(bar.status)
    bar.statusEdge=content:CreateTexture(nil,"BORDER")
    bar.buttons={}
    for slot=1,6 do
        local b=W:OptionButton(content,18,captured)
        -- Always the roll this row shows now: bar.roll is set by Paint only.
        -- A held row (gone, kept under the cursor) takes no clicks.
        b:SetScript("OnClick",function(button) if bar.roll and not bar.roll.preview and not bar.held then R:Choose(bar.roll,button.option) end end)
        b:SetScript("OnEnter",function(button) F:OptionEnter(button,bar.roll) end)
        b:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
        bar.buttons[slot]=b
    end
    bar.bvKind=W:Label(captured,content,"",17,false,true);bar.bvKind:SetJustifyH("RIGHT");bar.bvKind:SetWordWrap(false)
    bar.stats=W:Label(captured,content,"",10,false);bar.stats:SetJustifyH("RIGHT");bar.stats:SetWordWrap(false)
    bar.bvKind:SetTextColor(1,1,1);bar.stats:SetTextColor(.85,.85,.85)
    -- The mouse wheel scrolls the rows; only on while rolls are waiting, so
    -- otherwise the wheel still zooms the camera.
    bar:SetScript("OnMouseWheel",function(_,delta) F:Wheel(delta) end)
    self.bars[index]=bar
    return bar
end
function F:Layout(bar,cfg)
    local w=self.anchor:Width()
    local h,barH,nameH,button=geometry(cfg,bar.bvStyle~=nil)
    local upperGap=bar.bvStyle and 4 or 2
    -- With the background on, everything sits inside a padding on every side.
    local p=L.RollPad(cfg)
    D.Size(bar,w,h+2*p)
    bar.back:SetShown(cfg.rollBackground);bar.back:SetFrameLevel(bar:GetFrameLevel())
    w=w-2*p
    bar.item:Resize(h);bar.item:ClearAllPoints();D.Point(bar.item,"TOPLEFT",bar,"TOPLEFT",p,-p)
    -- Above the bar, which takes the mouse itself (same level: the parent wins).
    bar.item:SetFrameLevel(bar:GetFrameLevel()+3)
    local x=h+4
    -- Right inset: the option counts stick out 4 beyond their button, so with
    -- a background the right side keeps room for them (Florian, 2026-10-07).
    local rp=p>0 and p+5 or 0
    w=w-(rp-p)
    bar.status:ClearAllPoints();D.Point(bar.status,"BOTTOMLEFT",bar,"BOTTOMLEFT",x+p,p);D.Point(bar.status,"BOTTOMRIGHT",bar,"BOTTOMRIGHT",-(bar.bvStyle and p or rp),p);D.Height(bar.status,barH)
    bar.statusEdge:SetShown(not bar.bvStyle)
    bar.statusEdge:ClearAllPoints();D.Point(bar.statusEdge,"TOPLEFT",bar.status,"TOPLEFT",-1,1);D.Point(bar.statusEdge,"BOTTOMRIGHT",bar.status,"BOTTOMRIGHT",1,-1)
    if bar.bvStyle then bar.statusEdge:SetColorTexture(bar.bvStyle:Color("controlEdge"))else bar.statusEdge:SetColorTexture(unpack(select(2,L:Family()).barEdge))end
    local right=0
    for slot=#bar.buttons,1,-1 do
        local b=bar.buttons[slot]
        b:Resize(button)
        if b:IsShown() then
            b:ClearAllPoints();D.Point(b,"BOTTOMRIGHT",bar,"BOTTOMRIGHT",-right-rp,barH+upperGap+p);right=right+button+3
        end
    end
    bar.bind:ClearAllPoints();D.Point(bar.bind,"BOTTOMRIGHT",bar,"BOTTOMRIGHT",-right-2-rp,barH+(bar.bvStyle and upperGap or 3)+p);D.Size(bar.bind,30,nameH)
    bar.bvName:ClearAllPoints();D.Point(bar.bvName,"BOTTOMLEFT",bar,"BOTTOMLEFT",x+1+p,barH+upperGap+p)
    D.Size(bar.bvName,math.max(20,w-x-right-36),nameH)
    if bar.bvStyle then W:Caption(bar.bvStyle,bar.bvName,bar.bvLootFullName or "")end
    bar.bvKind:ClearAllPoints();D.Point(bar.bvKind,"TOPRIGHT",bar,"TOPLEFT",-6,1-p);D.Size(bar.bvKind,INFO,math.max(14,h*.6))
    bar.stats:ClearAllPoints();D.Point(bar.stats,"BOTTOMRIGHT",bar,"BOTTOMLEFT",-6,p);D.Size(bar.stats,INFO+60,12)
end
function F:Paint(bar,roll,cfg)
    bar.roll=roll
    local info=roll.link and L.Item(roll.link) or {}
    local r,g,b=L.QualityColor(roll.quality or info.quality or 1)
    bar.item:SetItem(roll.icon or info.icon,roll.quality or info.quality,info.level,roll.count)
    bar.bvLootFullName=roll.name or info.name or roll.link or "?"
    bar.bvName:SetText(bar.bvLootFullName);bar.bvName:SetTextColor(r,g,b)
    local familyID,family=L:Family()
    if bar.bvStyle then familyID="bv";family=ns.Styles.families.bv end
    bar.bind.bvLootRole=bar.bvStyle and roll.kind=="bv" and "accentText" or nil
    if roll.kind=="bv" then
        bar.bind:SetText("ML");bar.bind:SetTextColor((bar.bvStyle or UI:GameStyle(L.ID)):Color(bar.bvStyle and "accentText" or "accent"))
    elseif roll.bop then bar.bind:SetText(ns.Styles:Label(familyID,"BoP"));bar.bind:SetTextColor(1,.3,.1)
    else bar.bind:SetText("") end
    local texture=ns.Styles:BarTexture(familyID)
    bar.status:SetStatusBarTexture(texture)
    if cfg.rollQualityBar then bar.status:SetStatusBarColor(r,g,b,.85);bar.statusBg:SetColorTexture(r*.2,g*.2,b*.2,.75)
    else bar.status:SetStatusBarColor(UI:RGBA(cfg.rollBarColor));bar.statusBg:SetColorTexture(0,0,0,.6) end
    bar.status:SetMinMaxValues(0,math.max(1,roll.duration or 60))
    for slot,button in ipairs(bar.buttons) do
        local option=roll.options[slot]
        if option then
            local enabled=roll.enabled[option]~=false and not roll.mine and not roll.done and not bar.held
            button:SetOption(option,enabled,R:Count(roll,option),roll.mine==option,L.OptionDef(roll,option))
            button:Show()
        else button.option=nil;button:Hide() end
    end
    local kind=cfg.rollKind and L.ItemKind(info) or nil
    bar.bvKind:SetText(ns.Styles:Label(familyID,kind) or "");bar.stats:SetText(cfg.rollStats and roll.link and L.ItemStats(roll.link) or "")
    if bar.bvStyle then bar.bvKind:SetTextColor(bar.bvStyle:Color("text"));bar.stats:SetTextColor(bar.bvStyle:Color("muted"))
    else bar.bvKind:SetTextColor(unpack(family.labelColor))end
    -- Item border, name and timer retain quality; omit the adjacent duplicate seam.
    if not bar.bvStyle then W:Quality(bar,r,g,b) end;W:RememberColors(bar.bvName,bar.bind,bar.bvKind,bar.stats)
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

-- Which rolls get a row. A roll that is no longer visible frees its row,
-- unless the cursor is over that row: then the row stays (buttons off) until
-- the mouse leaves, so a click never lands on the roll that refills it.
-- New rolls queue at the end; a free row in view takes the oldest roll out of
-- view. Positions out of view are compacted (that moves nothing shown).
function F:Assign(list,max)
    local visible,known={},{}
    for _,roll in ipairs(list) do visible[roll]=true end
    local rows,o=self.rows,self.offset
    for _,bar in ipairs(self.bars) do bar.held=nil end
    for p=1,#rows do
        local roll=rows[p]
        if roll and not visible[roll] then
            local bar=p>o and p<=o+max and self.bars[p-o]
            if bar and bar.roll==roll and bar:IsShown() and not roll.preview and bar:IsMouseOver() then bar.held=true
            else rows[p]=false end
        end
        if rows[p] then known[rows[p]]=true end
    end
    for p=#rows+1,o+max do rows[p]=false end
    for _,roll in ipairs(list) do if not known[roll] then rows[#rows+1]=roll end end
    for p=o+1,o+max do
        if not rows[p] then
            local from
            for q=o+max+1,#rows do if rows[q] then from=q;break end end
            if not from then for q=o,1,-1 do if rows[q] then from=q;break end end end
            if from then rows[p]=rows[from];rows[from]=false end
        end
    end
    local out,before,after={},0,0
    for q=1,o do if rows[q] then out[#out+1]=rows[q];before=before+1 end end
    for p=o+1,o+max do out[#out+1]=rows[p] or false end
    for q=o+max+1,#rows do if rows[q] then out[#out+1]=rows[q];after=after+1 end end
    while #out>0 and out[#out]==false do out[#out]=nil end
    self.rows,self.offset=out,(#out>0) and before or 0
    self.hidden,self.above,self.below=before+after,before,after
end
function F:Sync()
    if not self.anchor then return end
    local cfg=L:Config()
    local list={}
    if self.anchor.preview then list=self.samples or sampleRolls();self.samples=list
    elseif L:Active() and cfg.rolls then
        for _,roll in ipairs(R:List()) do if R:Visible(roll) then list[#list+1]=roll end end
    end
    local max=cfg.rollMax
    self:Assign(list,max)
    local items={}
    for index=1,math.max(#self.bars,max) do
        local roll=index<=max and self.rows[self.offset+index]
        local bar=(roll or self.bars[index]) and self:Bar(index)
        if roll then
            self:Paint(bar,roll,cfg)
            bar:Show();items[#items+1]=bar
        elseif bar then bar.roll=nil;bar.held=nil;bar:Hide() end
        if bar then bar:EnableMouseWheel(self.hidden>0) end
        -- The overview tooltip follows its bar: another roll or no bar any more.
        if bar and L.Results.tipOwner==bar then
            if bar.roll and bar:IsShown() then L.Results:ShowTip(bar,bar.roll) else L.Results:HideTip(bar) end
        end
    end
    self.anchor.items=items
    self:More(max)
    self:Place()
    self:Clock(#items>0)
end
-- Fixed row positions: slot s always sits at the same offset from the anchor,
-- whatever the other rows do. A frame is only re-anchored when its slot
-- geometry changes (height, spacing, grow, bar count), never because of rolls.
function F:Place()
    local def=self.anchor.def
    local grow,spacing,unit=def.grow(),def.spacing(),def.height()
    local function put(frame,slot)
        local offset=(slot-1)*(unit+spacing)
        local key=grow..":"..D.ToNative(offset)
        if frame.bvSlotKey==key then return end
        frame.bvSlotKey=key
        frame:ClearAllPoints()
        if grow=="DOWN" then D.Point(frame,"TOPLEFT",self.anchor.frame,"TOPLEFT",0,-offset)
        else D.Point(frame,"BOTTOMLEFT",self.anchor.frame,"BOTTOMLEFT",0,offset) end
    end
    for slot,bar in ipairs(self.bars) do put(bar,slot) end
    if self.more then put(self.more,L:Config().rollMax+1) end
end
-- "+N more" after the last row while rolls wait out of view: wheel or
-- click (left: next, right: back) scrolls.
function F:More(max)
    if self.hidden==0 and not self.more then return end
    local more=self.more
    if not more then
        more=W.Owned(CreateFrame("Button",nil,self.anchor.frame));more:Hide()
        more:EnableMouse(true);more:EnableMouseWheel(true)
        if more.RegisterForClicks then more:RegisterForClicks("LeftButtonUp","RightButtonUp") end
        more.bvStyle=W:Style();more.bvTooltipStyle=more.bvStyle
        more.text=W:Label(more.bvStyle,more,"",12,false,true);more.text:SetPoint("LEFT",more,"LEFT",2,0)
        more:SetScript("OnClick",function(_,button) F:Scroll(button=="RightButton" and -1 or 1) end)
        more:SetScript("OnMouseWheel",function(_,delta) F:Wheel(delta) end)
        more:SetScript("OnEnter",function(owner)
            W:TextTooltip(owner,string.format("%d more rolls",F.hidden),{
                {string.format("%d waiting, %d scrolled past",F.below,F.above),.85,.85,.85},
                {"Mouse wheel over the roll bars scrolls.",.85,.85,.85},{"Left-click: next, right-click: back.",.85,.85,.85}})
        end)
        more:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
        self.more=more
    end
    more.text:SetText(string.format("+%d more",self.hidden))
    if more.bvStyle then more.text:SetTextColor(more.bvStyle:Color("text"))else more.text:SetTextColor(unpack(select(2,L:Family()).labelColor))end
    W:RememberColors(more.text)
    D.Size(more,self.anchor:Width(),16)
    more:SetShown(self.hidden>0)
end
-- Only the player scrolls: one row per wheel tick or click. The wheel moves
-- along the stack: towards the later rows when it turns in the grow direction.
function F:Wheel(delta)
    local step=delta>0 and 1 or -1
    if L:Config().rollGrow=="DOWN" then step=-step end
    self:Scroll(step)
end
function F:Scroll(step)
    local max=L:Config().rollMax
    local o=math.max(0,math.min(self.offset+step,#self.rows-max))
    if o==self.offset then return end
    self.offset=o
    self:Sync()
end
-- Bars drain with a shared 0.1 s ticker that only runs while bars are shown.
function F:Clock(run)
    if run and not self.ticker then
        self.ticker=C_Timer.NewTicker(.1,function()
            local release=false
            for _,bar in ipairs(self.bars) do
                if bar:IsShown() then self:Tick(bar) end
                -- A held row frees as soon as the mouse has left it.
                if bar.held and not bar:IsMouseOver() then release=true end
            end
            if release then self:Sync() end
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
        width=function() return L:Config().rollWidth end,height=function() local c=L:Config();local style=ns.Config and ns.Config.shellStyle;local h=geometry(c,style and style.materialProfile=="interface");return h+2*L.RollPad(c) end,
        grow=function() return L:Config().rollGrow end,spacing=function() return L:Config().rollSpacing end,
        enabled=function() return L:Config().rolls end,
        resized=function(width)
            if ns.Layout.draft then return end
            local cfg=L:Config();cfg.rollWidth=math.floor(width+.5)
        end,
        preview=function() F:Sync() end})
    -- This anchor places by slot, not by packing the shown bars.
    self.anchor.Arrange=function() F:Place() end
end
function F:Enable(context)
    self:Create()
    L:On("RollUpdated",self,function() F:Sync() end)
    L:On("RollsReset",self,function() F:Sync() end)
    self:Suppress(context)
    context:Defer(function()
        L:Off(self);self:Clock(false)
        for _,bar in ipairs(self.bars) do bar.roll=nil;bar.held=nil;bar:Hide() end
        self.rows,self.offset,self.hidden,self.above,self.below={},0,0,0,0
        if self.more then self.more:Hide() end
    end)
    W:Refresh()
    self:Sync()
end
-- The layout element exists from load on, so the Layout Editor knows it.
F:Create()

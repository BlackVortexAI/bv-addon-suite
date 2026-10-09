local _,L=...
if not L.ready then return end
-- Master loot window (point 3). Lists the loot above the threshold, the
-- candidates (loot window open) or the group roster, lets the master looter
-- select players (all, one class, single players) and ask them to roll. The
-- selected players get a roll bar like a native roll; the answers and their
-- /roll results come back ranked. Awarding re-checks the candidate index.
-- Integrations add buttons (header row, candidate menu) and info tooltips.
local ns=L.ns
local UI,Theme,D=ns.UI,ns.Theme,ns.DesignSystem.Metrics
local W,R=L.Widgets,L.Rolls
local Master={items={},selection={},rows={},itemButtons={}}
L.Master=Master
-- Geometry in design units (density rules of 0.8.71-0.8.73): 26 high controls,
-- small accent headings with a rule, explanations as tooltips, no hint lines.
local WIDTH,HEIGHT,ROW,CONTROL=860,620,22,26
local CONTENT=HEIGHT-36 -- below the dialog title bar
local SIDE=250 -- item sidebar
local MAIN_X=SIDE+14
local MAIN_W=WIDTH-MAIN_X-14
local FOOTER=32
local LIST_X,LIST_Y,LIST_W=MAIN_X,138,MAIN_W
local LIST_H=CONTENT-LIST_Y-FOOTER-8
local COLUMN=math.floor((LIST_W-10)/2)
local CUSTOM_Y=CONTENT-FOOTER-162
local ITEM_PITCH=36

-- Blizzard loot window as item/candidate source.
local Real={}
Master.real=Real
function Real:IsOpen() return self.open==true end
function Real:Slots()
    local out={}
    local count=L.Call("GetNumLootItems") or 0
    local threshold=L.Call("GetLootThreshold") or 2
    for slot=1,count do
        local link=L.Call("GetLootSlotLink",slot)
        if L.Readable(link) then
            local icon,name,quantity,_,quality=L.Call("GetLootSlotInfo",slot)
            if type(quality)~="number" then quality=L.Item(link).quality or 1 end
            if quality>=threshold then out[#out+1]={slot=slot,link=link,name=name,icon=icon,quality=quality,count=quantity} end
        end
    end
    return out
end
function Real:Candidates(slot)
    local out={}
    for index=1,40 do
        local name,class,token=L.Call("GetMasterLootCandidate",slot,index)
        name=L.Short(name)
        if name then out[#out+1]={name=name,index=index,class=type(token)=="string" and token or L.ClassOf(name)} end
    end
    return out
end
function Real:Award(slot,index,name)
    local current=L.Short(L.Call("GetMasterLootCandidate",slot,index))
    if current~=name then return false,"candidate list changed" end
    L.Call("GiveMasterLoot",slot,index)
    return true
end
function Master:Source() return L.Sim and L.Sim.source or Real end

-- Group roster for requests while no loot window is open.
function Master:Roster()
    if L.Sim and L.Sim.source then return L.Sim.source:Candidates() end
    local out,seen={},{}
    local function add(name,class)
        name=L.Short(name)
        if name and not seen[name] then seen[name]=true;out[#out+1]={name=name,class=class or L.ClassOf(name)} end
    end
    if L.Call("IsInRaid") then
        -- Names with surname (WoW Forever), as chat and loot history show them.
        for i=1,40 do
            local name,_,_,_,_,token=L.Call("GetRaidRosterInfo",i)
            if name then add(L.UnitFull("raid"..i) or name,token) end
        end
    else
        add(L.Me(),select(2,L.Call("UnitClass","player")))
        for i=1,4 do
            local name=L.UnitFull("party"..i)
            if name then add(name,select(2,L.Call("UnitClass","party"..i))) end
        end
    end
    return out
end
function Master:Candidates()
    local item=self.selected
    local source=self:Source()
    if item and item.slot and source:IsOpen() then return source:Candidates(item.slot),true end
    return self:Roster(),false
end

-- Items -----------------------------------------------------------------------
function Master:AddItem(link,slot,fields)
    for _,item in ipairs(self.items) do
        if item.link==link and (item.slot==slot or item.slot==nil and not item.gone) and not item.awarded then
            item.slot=slot;return item
        end
    end
    local info=L.Item(link)
    local item={key=#self.items+1,link=link,slot=slot,name=info.name,icon=info.icon,quality=info.quality,count=1}
    for k,v in pairs(fields or {}) do item[k]=v end
    self.items[#self.items+1]=item
    while #self.items>24 do table.remove(self.items,1) end
    return item
end
function Master:LootOpened()
    local source=self:Source()
    for _,item in ipairs(self.items) do item.slot=nil end
    local slots=source:Slots()
    for _,s in ipairs(slots) do self:AddItem(s.link,s.slot,{name=s.name,icon=s.icon,quality=s.quality,count=s.count}) end
    if #slots>0 and (not self.selected or not self.selected.slot) then self.selected=self:FindItem(slots[1].link,slots[1].slot) end
    return #slots
end
function Master:FindItem(link,slot)
    for _,item in ipairs(self.items) do if item.link==link and item.slot==slot then return item end end
end
function Master:SlotCleared(slot)
    for _,item in ipairs(self.items) do if item.slot==slot then item.slot=nil;item.gone=true end end
    self:Refresh()
end
function Master:LootClosed()
    for _,item in ipairs(self.items) do item.slot=nil end
    self:Refresh()
end

-- Selection -------------------------------------------------------------------------
function Master:Select(mode)
    local list=self:Candidates()
    if mode=="none" then self.selection={}
    elseif mode=="all" then self.selection={};for _,c in ipairs(list) do self.selection[c.name]=true end
    elseif type(mode)=="string" and mode:match("^class:") then
        local class=mode:sub(7);self.selection={}
        for _,c in ipairs(list) do if c.class==class then self.selection[c.name]=true end end
    end
    self:Refresh()
end
function Master:Toggle(name) self.selection[name]=not self.selection[name] or nil;self:Refresh() end
function Master:Selected()
    local out={}
    for _,c in ipairs(self:Candidates()) do if self.selection[c.name] then out[#out+1]=c.name end end
    return out
end
function Master:ClassChoices()
    local out={{value="all",label="All"},{value="none",label="None"}}
    local seen={}
    for _,c in ipairs(self:Candidates()) do
        if c.class and not seen[c.class] then
            seen[c.class]=true
            local label=LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c.class] or c.class
            out[#out+1]={value="class:"..c.class,label="Only "..label}
        end
    end
    return out
end

-- Actions ---------------------------------------------------------------------------
function Master:Request()
    local item=self.selected
    if not item then return false,"no item" end
    local players=self:Selected()
    if #players==0 then self:Status("Select at least one player.");return false,"no players" end
    local cfg=L:Config()
    local options,custom={},nil
    for i,option in ipairs(L.PRESETS[cfg.masterOptions]) do options[i]=option end
    if cfg.customEnabled then
        if cfg.customText=="" then self:Status("Enter a reason for the custom roll or switch it off.");return false,"no reason" end
        options=L.RankCustom(options,cfg.customAfter);custom={label=cfg.customText,symbol=cfg.customSymbol}
    end
    local roll,err=R:Request(item.link,players,options,nil,custom)
    if not roll then self:Status(err);return false,err end
    item.roll=roll;item.awardTarget=nil
    L:Emit("RollRequested",roll)
    self:Status(string.format("Roll requested from %d player%s.",#players,#players==1 and "" or "s"))
    self:Refresh()
    return true
end
function Master:AwardTarget()
    local item=self.selected
    if not item then return nil end
    local picked=self:Selected()
    if #picked==1 then return picked[1] end
    if item.roll and item.roll.done and item.roll.winner then return item.roll.winner end
    return nil
end
function Master:Award(name)
    local item=self.selected
    if not item or not name then return false,"nothing to award" end
    if not item.slot or not self:Source():IsOpen() then self:Status("Open the loot window to hand out this item.");return false,"loot closed" end
    local candidate
    for _,c in ipairs(self:Source():Candidates(item.slot)) do if c.name==name then candidate=c end end
    if not candidate then self:Status(name.." cannot receive this item.");return false,"not eligible" end
    local ok,err=self:Source():Award(item.slot,candidate.index,name)
    if not ok then self:Status("Not awarded: "..tostring(err));return false,err end
    item.awarded=name
    L:Emit("ItemAwarded",{link=item.link,itemID=L.ItemID(item.link),player=name,roll=item.roll})
    if L:Config().masterAnnounce and L.GroupChannel() and SendChatMessage then
        pcall(SendChatMessage,string.format("%s -> %s",item.link,name),L.GroupChannel())
    end
    self:Status("Awarded "..(item.name or item.link).." to "..name..".")
    self:Refresh()
    return true
end
-- Award needs a second click within 4 s (no modal popup).
function Master:AwardClick()
    local target=self:AwardTarget()
    if not target then self:Status("Pick one player or finish a roll first.");return end
    if self.confirm and self.confirm.name==target and self.confirm.item==self.selected then
        self.confirm.timer:Cancel();self.confirm=nil
        self:Award(target)
    else
        if self.confirm then self.confirm.timer:Cancel() end
        self.confirm={name=target,item=self.selected,timer=C_Timer.NewTimer(4,function() Master.confirm=nil;Master:Refresh() end)}
        self:Refresh()
    end
end

-- Window ----------------------------------------------------------------------------
-- In the module's in-game style since the form kit (Loot 0.8.91):
-- built inside UI:WithStyle, so controls, the window and its lists follow the
-- style family live. Own lines: white in BV and Clean, the gold edge in WoW.
local function style() return UI:GameStyle(L.ID) end
local function color(key,alpha) return style():Color(key,alpha) end
local function line(texture,alpha)
    style():Bind(function()
        if select(2,L:Family()).border=="gold" then local r,g,b=color("edge");texture:SetColorTexture(r,g,b,.6)
        else texture:SetColorTexture(1,1,1,alpha) end
    end,texture)
    return texture
end
function Master:Status(text) self.statusText=text;if self.window then self.window.status:SetText(text or "") end end
local function heading(parent,text,x,y,width)
    local label=UI:Label(parent,text,11,"accent",true);UI:Place(label,parent,x,y)
    local rule=line(parent:CreateTexture(nil,"ARTWORK"),.08)
    UI:Place(rule,parent,x-2,y+18);D.Size(rule,width,1)
    return label,rule
end
local function control(widget,height) D.Height(widget,height or CONTROL);return widget end
function Master:Build()
    if self.window then return self.window end
    return UI:WithStyle(style(),self.BuildWindow,self)
end
function Master:BuildWindow()
    local w=W.Owned(UI:Dialog("BVLootMasterWindow",WIDTH,HEIGHT))
    w.title:SetText("Master Loot")
    self.window=w
    local c=w.content
    -- Sidebar: items on top, custom roll at the bottom.
    w.side=c:CreateTexture(nil,"BACKGROUND",nil,1);w.side:SetColorTexture(0,0,0,.18)
    D.Point(w.side,"TOPLEFT",c,"TOPLEFT",0,0);D.Point(w.side,"BOTTOMLEFT",c,"BOTTOMLEFT",0,FOOTER);D.Width(w.side,SIDE)
    w.sideRule=line(c:CreateTexture(nil,"ARTWORK"),.07)
    D.Point(w.sideRule,"TOPLEFT",c,"TOPLEFT",SIDE,0);D.Point(w.sideRule,"BOTTOMLEFT",c,"BOTTOMLEFT",SIDE,FOOTER);D.Width(w.sideRule,1)
    w.listTitle=heading(c,"ITEMS",14,10,SIDE-24)
    w.empty=UI:Label(c,"No loot yet.",12,"muted");UI:Place(w.empty,c,14,40);D.Size(w.empty,SIDE-28,18)
    UI:AttachTooltip(w.empty,"Items","Items appear when you open loot as master looter, or add one with /bv loot request <item link>.")
    heading(c,"CUSTOM ROLL",14,CUSTOM_Y,SIDE-24)
    w.customText=control(UI:GetStyle():Input(c,SIDE-24,false,L:Config().customText,function(text) L:Config().customText=L.CleanCustom(text,"star");Master:Refresh() end))
    UI:TextFieldMenu(w.customText);w.customText:SetMaxLetters(48)
    UI:AttachTooltip(w.customText,"Roll reason","Label of the custom option on the players' roll bar, e.g. \"Tank set\" or \"Transmog\".")
    UI:Place(w.customText,c,12,CUSTOM_Y+28)
    w.customIcon=c:CreateTexture(nil,"ARTWORK");UI:Place(w.customIcon,c,14,CUSTOM_Y+64);D.Size(w.customIcon,22,22)
    local symbols={}
    for _,name in ipairs(L.CUSTOM_SYMBOLS) do symbols[#symbols+1]={value=name,label=ns.Symbols:Label(name)} end
    w.customSymbol=control(UI:Dropdown(c,SIDE-58,symbols,function(value) L:Config().customSymbol=value;Master:Refresh() end))
    UI:Place(w.customSymbol,c,46,CUSTOM_Y+62)
    w.rankLabel=UI:Label(c,"Rank",12,"text");UI:Place(w.rankLabel,c,14,CUSTOM_Y+96);D.Size(w.rankLabel,40,CONTROL)
    w.customRank=control(UI:Dropdown(c,SIDE-70,L.RankChoices(L:Config().masterOptions),function(value) L:Config().customAfter=value;Master:Refresh() end))
    w.customRank:SetOptionsProvider(function() return L.RankChoices(L:Config().masterOptions) end)
    UI:Place(w.customRank,c,58,CUSTOM_Y+96)
    UI:AttachTooltip(w.customRank,"Rank","Where the custom roll counts in the result: before all options or after one of them. Pass is always last; the roll bar shows the options in this order.")
    w.customLabel=UI:Label(c,"Add to request",12,"text");UI:Place(w.customLabel,c,14,CUSTOM_Y+130);D.Size(w.customLabel,150,CONTROL)
    UI:AttachTooltip(w.customLabel,"Add to request","Offers the custom roll together with the preset options.")
    w.customSwitch=UI:Switch(c,false,function(value) L:Config().customEnabled=value;Master:Refresh() end)
    UI:Place(w.customSwitch,c,SIDE-48,CUSTOM_Y+133)
    -- Header: selected item, award (and integration buttons) on the right.
    w.header=W:ItemIcon(c,40,true);UI:Place(w.header,c,MAIN_X,12)
    w.header:SetScript("OnEnter",function(owner) local item=Master.selected;if item then W:ItemTooltip(owner,{link=item.link,itemID=L.ItemID(item.link),slot=item.slot,roll=item.roll,source="master"}) end end)
    w.header:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    w.bvName=UI:Label(c,"",15,false,true);UI:Place(w.bvName,c,MAIN_X+50,10);D.Size(w.bvName,MAIN_W-216,20);w.bvName:SetWordWrap(false)
    w.info=UI:Label(c,"",11,"muted");UI:Place(w.info,c,MAIN_X+50,31);D.Size(w.info,MAIN_W-216,15);w.info:SetWordWrap(false)
    w.rollState=UI:Label(c,"",11,"text");UI:Place(w.rollState,c,MAIN_X+50,47);D.Size(w.rollState,MAIN_W-216,15);w.rollState:SetWordWrap(false)
    w.award=control(UI:Button(c,"Award",156,function() Master:AwardClick() end))
    UI:Place(w.award,c,MAIN_X+MAIN_W-156,12)
    UI:AttachTooltip(w.award,"Award","Gives the item to the roll winner or the one selected player. Click twice to confirm; the loot window must be open.")
    w.extra={}
    w.headerRule=line(c:CreateTexture(nil,"ARTWORK"),.07)
    UI:Place(w.headerRule,c,MAIN_X,64);D.Size(w.headerRule,MAIN_W,1)
    -- Toolbar: who, which options, request.
    w.selectMenu=control(UI:Dropdown(c,170,self:ClassChoices(),function(value) Master:Select(value) end))
    w.selectMenu:SetOptionsProvider(function() return Master:ClassChoices() end)
    UI:Place(w.selectMenu,c,MAIN_X,74);w.selectMenu:SetValue("none")
    UI:AttachTooltip(w.selectMenu,"Select players","Everyone, nobody or one class. Click names in the list to add or remove single players.")
    w.preset=control(UI:Dropdown(c,236,L.PRESET_CHOICES,function(value) L:Config().masterOptions=value end))
    UI:Place(w.preset,c,MAIN_X+176,74)
    UI:AttachTooltip(w.preset,"Roll options","Options on the players' roll bar; their order is the priority.")
    w.request=control(UI:Button(c,"Request roll",140,function() Master:Request() end,true))
    UI:Place(w.request,c,MAIN_X+MAIN_W-140,74)
    UI:AttachTooltip(w.request,"Request roll","The selected players get a roll bar; answers and /roll results appear in the list.")
    -- Selection bar.
    w.selected=UI:Label(c,"",11,"muted");UI:Place(w.selected,c,MAIN_X+2,106);D.Size(w.selected,MAIN_W-232,CONTROL-2);w.selected:SetWordWrap(false)
    w.selectAll=control(UI:Button(c,"Select all",100,function() Master:Select("all") end),CONTROL-2)
    UI:Place(w.selectAll,c,MAIN_X+MAIN_W-222,106)
    w.selectNone=control(UI:Button(c,"Deselect all",116,function() Master:Select("none") end),CONTROL-2)
    UI:Place(w.selectNone,c,MAIN_X+MAIN_W-116,106)
    -- Candidates: two columns in a scroll area (40 players and more).
    w.list=CreateFrame("ScrollFrame",nil,c);UI:Place(w.list,c,LIST_X,LIST_Y);D.Size(w.list,LIST_W,LIST_H)
    w.list:SetClipsChildren(true);w.list:EnableMouseWheel(true)
    w.listChild=CreateFrame("Frame",nil,w.list);D.Size(w.listChild,LIST_W-10,LIST_H);w.list:SetScrollChild(w.listChild)
    w.list:SetScript("OnMouseWheel",function(_,delta) Master:Scroll(-delta*ROW*3) end)
    w.track=c:CreateTexture(nil,"ARTWORK");w.track:SetColorTexture(1,1,1,.05)
    D.Point(w.track,"TOPRIGHT",w.list,"TOPRIGHT",0,0);D.Size(w.track,4,LIST_H)
    w.thumb=c:CreateTexture(nil,"OVERLAY")
    -- Footer with the status line, below both columns.
    w.footer=line(c:CreateTexture(nil,"ARTWORK"),.07)
    D.Point(w.footer,"BOTTOMLEFT",c,"BOTTOMLEFT",0,FOOTER);D.Point(w.footer,"BOTTOMRIGHT",c,"BOTTOMRIGHT",0,FOOTER);D.Height(w.footer,1)
    w.status=UI:Label(c,"",11,"muted");D.Point(w.status,"BOTTOMLEFT",c,"BOTTOMLEFT",14,8);D.Size(w.status,WIDTH-150,16);w.status:SetWordWrap(false)
    w.historyButton=control(UI:Button(c,"History",100,function() L.Results:ShowHistory(10) end),22)
    D.Point(w.historyButton,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-12,5)
    UI:AttachTooltip(w.historyButton,"Roll results","The last 10 results again. /bv loot last <n> shows more.")
    w:HookScript("OnShow",function() Master:Clock(true) end)
    w:HookScript("OnHide",function() Master:Clock(false);W:HideTooltip() end)
    return w
end
function Master:ItemButton(index)
    local b=self.itemButtons[index]
    if b then return b end
    return UI:WithStyle(style(),self.NewItemButton,self,index)
end
function Master:NewItemButton(index)
    local b
    local c=self.window.content
    b=CreateFrame("Button",nil,c);D.Size(b,SIDE-24,ITEM_PITCH-2)
    b.band=b:CreateTexture(nil,"BACKGROUND");b.band:SetAllPoints(b)
    b.item=W:ItemIcon(b,28,true);UI:Place(b.item,b,3,3);b.item:EnableMouse(false)
    b.bvName=UI:Label(b,"",12,false,true);UI:Place(b.bvName,b,38,3);D.Size(b.bvName,SIDE-66,15);b.bvName:SetWordWrap(false)
    b.state=UI:Label(b,"",10,"muted");UI:Place(b.state,b,38,18);D.Size(b.state,SIDE-66,13);b.state:SetWordWrap(false)
    b:SetScript("OnClick",function() Master.selected=b.data;Master.confirm=nil;Master:Refresh() end)
    b:SetScript("OnEnter",function(owner) if b.data then W:ItemTooltip(owner,{link=b.data.link,itemID=L.ItemID(b.data.link),slot=b.data.slot,source="master"}) end end)
    b:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    self.itemButtons[index]=b
    return b
end
function Master:Row(index)
    local row=self.rows[index]
    if row then return row end
    return UI:WithStyle(style(),self.NewRow,self,index)
end
function Master:NewRow(index)
    local row=CreateFrame("Button",nil,self.window.listChild)
    row.bvMenuStyle=style();D.Size(row,COLUMN-6,ROW-2);row:RegisterForClicks("LeftButtonUp","RightButtonUp")
    row.band=row:CreateTexture(nil,"BACKGROUND");row.band:SetAllPoints(row)
    row.box=row:CreateTexture(nil,"ARTWORK");D.Size(row.box,12,12);D.Point(row.box,"LEFT",row,"LEFT",4,0)
    row.tick=row:CreateTexture(nil,"OVERLAY");D.Size(row.tick,8,8);D.Point(row.tick,"CENTER",row.box,"CENTER",0,0)
    row.bvName=UI:Label(row,"",12,false,true);D.Point(row.bvName,"LEFT",row,"LEFT",22,0);D.Size(row.bvName,COLUMN-160,ROW);row.bvName:SetWordWrap(false)
    row.choice=UI:Label(row,"",11,false);D.Point(row.choice,"RIGHT",row,"RIGHT",-38,0);D.Size(row.choice,96,ROW);row.choice:SetJustifyH("RIGHT");row.choice:SetWordWrap(false)
    row.bvValue=UI:Label(row,"",12,false,true);D.Point(row.bvValue,"RIGHT",row,"RIGHT",-4,0);D.Size(row.bvValue,30,ROW);row.bvValue:SetJustifyH("RIGHT")
    row:SetScript("OnClick",function(_,button)
        if not row.data then return end
        if button=="RightButton" then Master:CandidateMenu(row) else Master:Toggle(row.data.name) end
    end)
    row:SetScript("OnEnter",function(owner)
        if not row.data then return end
        local item=Master.selected
        local lines={}
        if LOCALIZED_CLASS_NAMES_MALE and row.data.class then lines[#lines+1]=LOCALIZED_CLASS_NAMES_MALE[row.data.class] end
        if row.entry and row.entry.manual then lines[#lines+1]="Answered with a plain /roll" end
        lines[#lines+1]={"Left-click: select · Right-click: actions",.7,.7,.7}
        W:TextTooltip(owner,L.Colored(row.data.name,row.data.class),lines)
        W:InfoTip(owner,{player=row.data.name,class=row.data.class,link=item and item.link,itemID=item and L.ItemID(item.link),roll=item and item.roll,source="candidate"})
    end)
    row:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    self.rows[index]=row
    return row
end
function Master:CandidateMenu(row)
    local options,defs={},L.Integrations:Buttons("candidate")
    options[#options+1]={value="__award",label="Award to "..row.data.name}
    options[#options+1]={value="__only",label="Select only "..row.data.name}
    for _,def in ipairs(defs) do options[#options+1]={value=def.id,label=def.label} end
    UI:ContextMenu(row,options,function(value)
        if value=="__award" then Master.selection={[row.data.name]=true};Master.confirm=nil;Master:AwardClick()
        elseif value=="__only" then Master.selection={[row.data.name]=true};Master:Refresh()
        else
            for _,def in ipairs(defs) do
                if def.id==value then
                    local item=Master.selected
                    L.Integrations:Click(def,{player=row.data.name,class=row.data.class,link=item and item.link,itemID=item and L.ItemID(item.link),roll=item and item.roll,source="candidate"})
                end
            end
        end
    end)
end
function Master:ExtraButtons()
    local w,defs=self.window,L.Integrations:Buttons("master")
    for index,def in ipairs(defs) do
        local b=w.extra[index]
        if not b then
            b=UI:Button(w.content,"",110,function(control)
                local item=Master.selected
                if control.def then L.Integrations:Click(control.def,{link=item and item.link,itemID=item and L.ItemID(item.link),slot=item and item.slot,
                    roll=item and item.roll,selected=Master:Selected(),source="master"}) end
            end)
            w.extra[index]=b
        end
        b.def=def;b:SetLabelText(def.label)
        UI:AttachTooltip(b,def.label,def.tooltip or "")
        D.Height(b,CONTROL-4);UI:Place(b,w.content,MAIN_X+MAIN_W-index*116+6,42);b:Show()
    end
    for index=#defs+1,#w.extra do w.extra[index]:Hide() end
end
function Master:Refresh()
    local w=self.window
    if not w or not w:IsShown() then return end
    local cfg=L:Config()
    -- Item list.
    local y=38
    for index=1,math.max(#self.items,#self.itemButtons) do
        local item=self.items[#self.items-index+1]
        local b=item and self:ItemButton(index) or self.itemButtons[index]
        if item and y+ITEM_PITCH<=CUSTOM_Y-6 then
            b.data=item
            local r,g,bb=L.QualityColor(item.quality or 1)
            local info=L.Item(item.link)
            b.item:SetItem(item.icon or info.icon,item.quality or info.quality,nil,item.count)
            b.bvName:SetText(item.name or info.name or item.link);b.bvName:SetTextColor(r,g,bb)
            local state=item.awarded and ("Awarded: "..item.awarded) or item.gone and "Looted" or item.roll and (item.roll.done and
                (item.roll.winner and ("Winner: "..item.roll.winner) or "Roll ended") or "Rolling…") or item.slot and "In loot window" or "Not in loot window"
            b.state:SetText(state)
            local ar,ag,ab=color("accent")
            if item==self.selected then b.band:SetColorTexture(ar,ag,ab,.16) else b.band:SetColorTexture(1,1,1,.03) end
            UI:Place(b,w.content,12,y);b:Show();y=y+ITEM_PITCH
        elseif b then b.data=nil;b:Hide() end
    end
    w.empty:SetShown(#self.items==0)
    -- Selected item.
    local item=self.selected
    if item then
        local info=L.Item(item.link)
        local r,g,b=L.QualityColor(item.quality or info.quality or 1)
        w.header:SetItem(item.icon or info.icon,item.quality or info.quality,info.level,item.count);w.header:Show()
        w.bvName:SetText(item.name or info.name or item.link);w.bvName:SetTextColor(r,g,b)
        local parts={}
        if info.level and info.level>1 then parts[#parts+1]=(ITEM_LEVEL_ABBR or "iLvl").." "..info.level end
        if L.ItemKind(info) then parts[#parts+1]=L.ItemKind(info) end
        local stats=L.ItemStats(item.link);if stats then parts[#parts+1]=stats end
        w.info:SetText(table.concat(parts,"  ·  "))
        local roll=item.roll
        if roll and not roll.done then
            w.rollState:SetText(string.format("Rolling: %d s left · %d of %d answered",math.ceil(R:TimeLeft(roll)),#roll.names,#roll.targetList))
        elseif roll then
            w.rollState:SetText(roll.winner and ("Roll ended · winner: "..L.Colored(roll.winner)) or "Roll ended without a winner")
        else w.rollState:SetText(item.awarded and ("Awarded to "..item.awarded) or "") end
    else
        w.header:Hide();w.bvName:SetText("");w.info:SetText("");w.rollState:SetText("")
    end
    self:ExtraButtons()
    w.preset:SetValue(cfg.masterOptions)
    local canRoll=item~=nil and not item.awarded
    if canRoll then w.request:Enable() else w.request:Disable() end
    local target=self:AwardTarget()
    local canAward=item~=nil and item.slot~=nil and self:Source():IsOpen() and target~=nil and not item.awarded
    if self.confirm and self.confirm.item==item then w.award:SetLabelText("Confirm: "..self.confirm.name)
    else w.award:SetLabelText(target and ("Award: "..target) or "Award") end
    if canAward then w.award:Enable() else w.award:Disable() end
    -- Candidates in two columns.
    local list,eligible=self:Candidates()
    local ranking={}
    if item and item.roll then for rank,entry in ipairs(R:Ranking(item.roll)) do ranking[entry.name]=rank end end
    table.sort(list,function(a,b)
        local ra,rb=ranking[a.name] or 99,ranking[b.name] or 99
        if ra~=rb then return ra<rb end
        return a.name<b.name
    end)
    local selected=0
    local ar,ag,ab=color("accent")
    local lines=math.ceil(#list/2)
    D.Height(w.listChild,math.max(LIST_H,lines*ROW))
    for index=1,math.max(#list,#self.rows) do
        local c=list[index]
        local row=c and self:Row(index) or self.rows[index]
        if c then
            row.data=c
            -- Row-wise: ranks 1 and 2 share the first line.
            local column,line=(index-1)%2,math.floor((index-1)/2)
            UI:Place(row,w.listChild,column*COLUMN,line*ROW)
            local on=self.selection[c.name]==true
            if on then selected=selected+1 end
            row.box:SetColorTexture(on and ar or .25,on and ag or .25,on and ab or .28,on and 1 or .9)
            row.tick:SetColorTexture(1,1,1,on and .9 or 0)
            row.bvName:SetText(L.Colored(c.name,c.class))
            local entry=item and item.roll and item.roll.choices[c.name]
            row.entry=entry
            local def=entry and entry.choice and L.OptionDef(item.roll,entry.choice)
            if entry then
                row.choice:SetText(def and def.label or "");row.choice:SetTextColor(unpack(def and def.color or {.8,.8,.8}))
                row.bvValue:SetText(entry.value and tostring(entry.value) or (entry.choice=="pass" and "" or "…"))
            elseif item and item.roll and item.roll.targets[c.name] and not item.roll.done then
                row.choice:SetText("waiting");row.choice:SetTextColor(.6,.6,.6);row.bvValue:SetText("")
            else row.choice:SetText("");row.bvValue:SetText("") end
            local winner=item and item.roll and item.roll.winner==c.name
            if winner then row.bvValue:SetTextColor(ar,ag,ab) else row.bvValue:SetTextColor(1,1,1) end
            row.band:SetColorTexture(winner and ar or 1,winner and ag or 1,winner and ab or 1,winner and .16 or (line%2==0 and .025 or 0))
            row:Show()
        elseif row then row.data=nil;row:Hide() end
    end
    self:Scroll(0)
    -- Custom roll panel.
    local cfg=L:Config()
    if w.customText:GetText()~=cfg.customText and not w.customText:HasFocus() then w.customText:SetText(cfg.customText) end
    w.customSymbol:SetValue(cfg.customSymbol);w.customSwitch:SetValue(cfg.customEnabled)
    -- Only on a preset change: SetOptions closes an open list, and Refresh runs
    -- every second while a roll is open (0.8.87: Rank closed by itself).
    local rank=L.RankChoices(cfg.masterOptions)
    if w.rankPreset~=cfg.masterOptions then w.customRank:SetOptions(rank);w.rankPreset=cfg.masterOptions end
    local valid=false
    for _,o in ipairs(rank) do if o.value==cfg.customAfter then valid=true end end
    w.customRank:SetValue(valid and cfg.customAfter or "")
    local path,l,r,t,b=ns.Symbols:Coords(cfg.customSymbol,64)
    if path then w.customIcon:SetTexture(path);w.customIcon:SetTexCoord(l,r,t,b);w.customIcon:SetVertexColor(unpack(L.OPTIONS.custom.color)) end
    w.selected:SetText(string.format("%d of %d selected · %s",selected,#list,eligible and "eligible for this loot" or "group (open the loot for eligibility)"))
    if self.statusText then w.status:SetText(self.statusText) end
end
-- Scroll the candidate list by delta (design units); 0 re-clamps.
function Master:Scroll(delta)
    local w=self.window
    if not w then return end
    local range=math.max(0,D.GetHeight(w.listChild)-LIST_H)
    self.scroll=math.max(0,math.min(range,(self.scroll or 0)+delta))
    w.list:SetVerticalScroll(D.ToNative(self.scroll))
    w.thumb:SetShown(range>0)
    if range>0 then
        local size=math.max(24,LIST_H*LIST_H/(LIST_H+range))
        w.thumb:ClearAllPoints();D.Point(w.thumb,"TOPRIGHT",w.list,"TOPRIGHT",0,-(LIST_H-size)*self.scroll/range)
        D.Size(w.thumb,4,size);w.thumb:SetColorTexture(color("accent",.7))
    end
end
function Master:Clock(run)
    if run and not self.ticker then
        self.ticker=C_Timer.NewTicker(1,function()
            local item=Master.selected
            if item and item.roll and not item.roll.done then Master:Refresh() end
        end)
    elseif not run and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function Master:Open()
    if not L:Active() then L:Print("Turn the loot module on first (/bv loot on).");return end
    self:Build():Show()
    self:Refresh()
end
function Master:ToggleWindow() if self.window and self.window:IsShown() then self.window:Hide() else self:Open() end end
function Master:Close() if self.window then self.window:Hide() end end

function Master:Enable(context)
    context:Subscribe("LOOT_OPENED",function()
        if L.Sim and L.Sim.source then return end
        Real.open=true
        local cfg=L:Config()
        if not cfg.master or not L.IsMasterLooter() then return end
        local count=Master:LootOpened()
        if count>0 and cfg.masterAutoOpen then Master:Open() else Master:Refresh() end
    end)
    context:Subscribe("LOOT_SLOT_CLEARED",function(_,slot) if not (L.Sim and L.Sim.source) then Master:SlotCleared(slot) end end)
    context:Subscribe("LOOT_CLOSED",function() if not (L.Sim and L.Sim.source) then Real.open=false;Master:LootClosed() end end)
    L:On("RollUpdated",self,function(roll)
        if Master.selected and Master.selected.roll==roll then Master:Refresh() end
    end)
    context:Defer(function()
        L:Off(self);Master:Close();Master:Clock(false)
        if Master.confirm then Master.confirm.timer:Cancel();Master.confirm=nil end
        Real.open=false
    end)
end

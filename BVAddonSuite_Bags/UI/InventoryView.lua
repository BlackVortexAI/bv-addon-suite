local ns=BVAddonSuiteCore
local B=ns and ns.Bags
local I=B and B.Inventory
if not I then return end
local UI,R=ns.UI,B.InventoryRules
local function put(f,p,x,y,w,h)
    f:ClearAllPoints();f:SetPoint("TOPLEFT",p,"TOPLEFT",x,-y);f:SetSize(w,h);f:Show()
end
local function opt(t,key,name) t[#t+1]={value=key,label=name} end
function I:SizeOptions()
    local opts={{value="default",label="Default"}}
    for _,n in ipairs(R.sizes) do opt(opts,n,n.." px") end
    return opts
end
function I:CategorySize(anchor,key)
    local options=self:SizeOptions()
    opt(options,"heading","Edit category…")
    UI:ContextMenu(anchor,options,function(size)
        if size=="heading" then self:OpenCategoryEditor(key);return end
        self:Config().categorySizes[key]=tonumber(size);self:Refresh()
    end)
end
local function tip(b,title,line)
    GameTooltip:SetOwner(b,"ANCHOR_RIGHT");GameTooltip:SetText(title)
    if line then GameTooltip:AddLine(line,1,1,1,true) end
    GameTooltip:Show()
end
local function scroller(p)
    local f=CreateFrame("ScrollFrame",nil,p)
    local child=CreateFrame("Frame",nil,f);child:SetSize(1,1);f:SetScrollChild(child)
    f:EnableMouseWheel(true);f:SetScript("OnMouseWheel",function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*48)))
    end)
    return f,child
end
local function color(hex)
    return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,1
end
local function stripe(p)
    local t=p:CreateTexture(nil,"BACKGROUND");t:SetAllPoints();return t
end
local function locked() return InCombatLockdown and InCombatLockdown() end
function I:ToggleStacks()
    if CursorHasItem and CursorHasItem() then return end
    local p=self:Config()
    if p.physical then p.physical=false;p.groupStacks=true else p.groupStacks=p.groupStacks==false end
    self:Refresh()
end
function I:TidyBags()
    if self.tidying then return end
    if locked() then ns:Print("You can clean up bags after combat.");return end
    if GetCursorInfo and GetCursorInfo() then ns:Print("Put down the item on your cursor first.");return end
    local sort=self.API("SortBags")
    if not sort then ns:Print("This client does not provide bag sorting.");return end
    local pickup,split=self.API("PickupContainerItem"),self.API("SplitContainerItem")
    local pending,retries=nil,0
    self.tidying=true
    local function finish(message)
        self.tidying=nil
        if message then ns:Print(message) else sort() end
        self.full=true;self:Refresh()
    end
    local function step()
        if locked() or (GetCursorInfo and GetCursorInfo()) then
            finish("Bag cleanup interrupted.");return
        end
        self.full=true;self:Scan()
        if pending then
            local target=self.bags[pending.bag] and self.bags[pending.bag][pending.slot]
            if not target or target.id~=pending.id then finish("Bag contents changed during cleanup.");return end
            if target.locked or target.count~=pending.count then
                retries=retries+1
                if retries>=20 then finish("The stack move was not confirmed. Try cleaning up again.");return end
                C_Timer.NewTimer(.15,step);return
            end
            pending=nil;retries=0
        end
        local partial,source,target={},nil,nil
        local busy=false
        self:Each(function(v)
            if v.locked then busy=true;return end
            if source or not v.id or v.count>=(v.maxStack or 1) then return end
            -- Stackable consumables can have different instance IDs. Keep
            -- suffixes, enchantments and the other item-link fields distinct.
            local payload=v.link and v.link:match("(item:[^|]+)") or tostring(v.id)
            payload=payload:gsub("^(item:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:)[^:]*","%1")
            local key=payload.."/"..tostring(v.bound)
            if partial[key] then source,target=v,partial[key] else partial[key]=v end
        end)
        if busy then
            retries=retries+1
            if retries>=20 then finish("Some bag slots are still locked. Try cleaning up again.");return end
            C_Timer.NewTimer(.15,step);return
        end
        if not source then finish();return end
        if source.count>target.count then source,target=target,source end
        local move=math.min(source.count,target.maxStack-target.count)
        if not pickup or not GetCursorInfo or (move<source.count and not split) then
            finish("Stack moves are unavailable on this client.");return
        end
        if move==source.count then pickup(source.bag,source.slot) else split(source.bag,source.slot,move) end
        local kind,id=GetCursorInfo()
        if kind~="item" or id~=source.id then finish("Could not pick up the stack.");return end
        pickup(target.bag,target.slot)
        if GetCursorInfo() then
            if ClearCursor then ClearCursor() end
            finish("These stacks could not be combined.");return
        end
        pending={bag=target.bag,slot=target.slot,id=target.id,count=target.count+move}
        retries=0;C_Timer.NewTimer(.15,step)
    end
    step()
end
local function bindingLabel(v)
    if v.bind==1 then return "bop" end
    if v.bound==1 then return "bound" end
    if v.bind==2 then return "boe" end
    if v.bind==3 then return "bou" end
end
local function valid(v)
    local f=I.API("GetContainerItemID");local read=I.API("GetContainerItemInfo")
    if not (v and f and read) or locked() then return false end
    local raw=read(v.bag,v.slot)
    local link=type(raw)=="table" and raw.hyperlink
    return f(v.bag,v.slot)==v.id and (raw~=nil)==v.occupied and (not v.occupied or v.id~=nil)
        and (not link or not v.link or v.link==link) and not (type(raw)=="table" and raw.isLocked)
end
function I:ItemMenu(b,v)
    if not v.id then return end
    local p=self:Config();local t={}
    opt(t,"compact",p.compact[v.id] and "Show individual slots" or "Show count only")
    opt(t,"pin",p.pins[v.id] and "Unpin from bag bar" or "Pin count to bag bar")
    opt(t,"auto","Use matching rules")
    for _,g in ipairs(self.order) do opt(t,g.key,"Assign: "..g.name) end
    UI:ContextMenu(b,t,function(k)
        if k=="compact" then p.compact[v.id]=not p.compact[v.id] or nil
        elseif k=="pin" then p.pins[v.id]=not p.pins[v.id] or nil
        else p.manual[v.id]=k~="auto" and k or nil end
        if p.compact[v.id] or p.pins[v.id] then p.names[v.id]=v.name or tostring(v.id) else p.names[v.id]=nil end
        self:Refresh()
    end)
end
function I:StockMenu(b,id)
    local p=self:Config();local opts={}
    if not (p.compact[id] and p.pins[id]) then opt(opts,"both","Count in inventory and on bag bar") end
    opt(opts,"find","Show individual slots")
    opt(opts,"pin",p.pins[id] and "Unpin from bag bar" or "Pin count to bag bar")
    opt(opts,"compact",p.compact[id] and "Stop condensing this item" or "Show count only")
    UI:ContextMenu(b,opts,function(k)
        if k=="find" then self:Open();self.search:SetText(tostring(id));return end
        if k=="both" then p.pins[id],p.compact[id]=true,true
        else
            local flags=k=="pin" and p.pins or p.compact
            flags[id]=not flags[id] or nil
        end
        if not p.pins[id] and not p.compact[id] then p.names[id]=nil
        elseif not p.names[id] then p.names[id]=(self.meta[id] or {}).name or tostring(id) end
        self:Refresh()
    end)
end
function I:ChooseStockItem(anchor,match)
    local options,seen={},{}
    self:Each(function(v)
        if v.id and not seen[v.id] and (not match or match(v)) then
            seen[v.id]=true
            opt(options,v.id,v.name or tostring(v.id))
        end
    end)
    table.sort(options,function(a,b) return a.label<b.label end)
    if #options==0 then opt(options,false,"No carried items") end
    UI:ContextMenu(anchor,options,function(id) if id then self:StockMenu(anchor,id) end end)
end
local function slotButton(parent)
    local b=CreateFrame("Button",nil,parent)
    b.back=stripe(b);b.icon=b:CreateTexture(nil,"ARTWORK");b.icon:SetPoint("TOPLEFT",1,-1);b.icon:SetPoint("BOTTOMRIGHT",-1,1);b.icon:SetTexCoord(.06,.94,.06,.94)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
    local function pickup(self)
        if self.members then I:ToggleStacks();return end
        local v=self.item;local f=I.API("PickupContainerItem");if f and valid(v) then f(v.bag,v.slot) else I.full=true;I:Refresh() end
    end
    b:RegisterForDrag("LeftButton");b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b:SetScript("OnMouseDown",function(self) self.pressedItem=self.item;self.pressedGroup=self.members~=nil end)
    b:SetScript("OnDragStart",pickup);b:SetScript("OnReceiveDrag",pickup)
    b:SetScript("OnClick",function(self,key)
        local v=self.pressedItem or self.item;self.pressedItem=nil
        if not valid(v) then I.full=true;I:Refresh();return end
        if key=="RightButton" and IsAltKeyDown() then I:ItemMenu(self,v);return end
        if v.link and HandleModifiedItemClick and HandleModifiedItemClick(v.link) then return end
        if self.members or self.pressedGroup then
            self.pressedGroup=nil
            if I:Config().groupStacks~=false then I:ToggleStacks() end
            return
        end
        local splitClick=(IsModifiedClick and IsModifiedClick("SPLITSTACK")) or (not IsModifiedClick and IsShiftKeyDown())
        if key=="LeftButton" and splitClick and v.count>1 then
            I:OpenSplit(v)
        elseif key=="LeftButton" then pickup(self)
        elseif v.id then local f=I.API("UseContainerItem");if f then f(v.bag,v.slot) end end
    end)
    b:SetScript("OnEnter",function(self)
        local v=self.item;if not v then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        if v.occupied then GameTooltip:SetBagItem(v.bag,v.slot) else GameTooltip:SetText("Empty slot") end
        GameTooltip:AddLine(("Bag %d · Slot %d"):format(v.bag,v.slot),.8,.8,.8)
        if v.occupied then
            I:AddIconPriceTooltip(self,GameTooltip)
            if self.members then GameTooltip:AddLine(("%d items in %d stacks · Click to see real slots"):format(self.totalCount,self.members),1,.83,.49,true) end
            if not self.members and v.count>1 then GameTooltip:AddLine("Use your split-stack modifier and click to choose an amount.",.8,.8,.8,true) end
            GameTooltip:AddLine((I.lookup[v.key] and I.lookup[v.key].name or "Other").." · "..(v.reason or ""),.95,.78,.47,true)
            GameTooltip:AddLine("Alt + right-click: category and counters",.8,.8,.8)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return b
end
local function groupButton(p,rail)
    local b=CreateFrame("Button",nil,p);b.bg=stripe(b)
    b.accent=b:CreateTexture(nil,"ARTWORK");b.accent:SetPoint("TOPLEFT",0,-2);b.accent:SetPoint("BOTTOMLEFT",0,2);b.accent:SetWidth(2)
    b.label=UI:Label(b,"",12);b.label:SetPoint("LEFT",6,0);b.label:SetPoint("RIGHT",-1,0);b.label:SetWordWrap(false)
    b.glyph=b:CreateTexture(nil,"OVERLAY");b.glyph:SetSize(15,15);b.glyph:SetPoint("CENTER")
    b:SetScript("OnEnter",function(s)
        tip(s,s.group.name,rail and "Click to hide or show. Right-click to style the heading." or "Left-click: size and category heading. Right-click: item icon labels.")
        if s.partner then s.partner.bg:SetAlpha(.28) end
    end)
    b:SetScript("OnLeave",function(s) GameTooltip:Hide();if s.partner then s.partner.bg:SetAlpha(.09) end end)
    b:RegisterForClicks("LeftButtonUp","RightButtonUp")
    b:SetScript("OnClick",function(s,button)
        if rail and button=="RightButton" then I:OpenCategoryEditor(s.group.key)
        elseif rail then I.hidden[s.group.key]=not I.hidden[s.group.key];I:Refresh()
        elseif button=="RightButton" and not I:Config().physical then I:OpenIconLabels(s.group.key)
        elseif not I:Config().physical then I:CategorySize(s,s.group.key) end
    end)
    return b
end
local symbols={quest="scroll-text",gear="shield",use="flask-conical",trade="layers",reagent="sparkles",misc="package"}
function I:CategorySymbol(key,heading,source)
    if heading and heading.symbol then return heading.symbol end
    local definition=self.lookup[key]
    source=source or (definition and definition.source)
    local family=source and source:match("^family:(%a+)")
    return symbols[key] or symbols[family] or "bookmark"
end
function I:ChooseHeadingSymbol(categoryName,current,choose)
    if not self.headingWindow then
        self.headingWindow=UI:WithStyle(UI:ToolStyle(),function()
            local w=UI:Window("BVInventoryCategorySymbol",394,530,{compact=true,minWidth=394,minHeight=530})
            w:SetResizable(false);w.resizeGrip:Hide()
            UI:WindowReadingSurface(w,UI:GetStyle());UI:ScopeDialogEscape(w)
            w.picker=UI:SymbolPicker(w.content,366);UI:Place(w.picker,w.content,10,8)
            w:TrackEscapeInput(w.picker.search)
            return w
        end)
    end
    local w=self.headingWindow
    w:SetTitle("Category icon · "..categoryName)
    w.picker:Open(current,function(symbol)
        w:Hide();choose(symbol)
    end)
    UI:FitWindow(w,394,530,1);w:Show();UI:FocusWindow(w)
end
local function groupArt(button,group,symbol,showGlyph)
    local r,g,b=color(group.color)
    button.bg:SetColorTexture(r,g,b,1);button.bg:SetAlpha(.09)
    button.accent:SetColorTexture(r,g,b,.88)
    button.glyph:SetShown(showGlyph)
    if showGlyph then
        local path,l,right,t,bottom=ns.Symbols:Coords(symbol,16)
        button.glyph:SetTexture(path);if path then button.glyph:SetTexCoord(l,right,t,bottom) end
        button.glyph:SetVertexColor(r,g,b)
    end
end
local badgeID="bv:bagstock"
local dockPoints={above={"BOTTOMRIGHT","TOPRIGHT",0,2},below={"TOPRIGHT","BOTTOMRIGHT",0,-2},
    left={"RIGHT","LEFT",-2,0},right={"LEFT","RIGHT",2,0}}
local function stockPreview(visible,overlays)
    local cfg=I:Config()
    local wanted=visible and overlays~=false and cfg.badgeDock=="free" and not next(cfg.pins)
    if not wanted then if I.stockPreview then I.stockPreview:Hide() end;return end
    if not I.stockPreview then
        local frame=CreateFrame("Frame",nil,UIParent)
        frame:EnableMouse(false);frame:SetSize(80,22)
        local text=UI:Label(frame,"Bag stock",12,"accentText");text:SetPoint("CENTER")
        I.stockPreview=frame
    end
    local rect=I.badgeRect
    if rect then I.stockPreview:ClearAllPoints();I.stockPreview:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y) end
    I.stockPreview:SetShown(I.badgeAllowed~=false)
end
ns.Layout:Register(badgeID,{label="Bag stock counters",sizeLocked=true,
    defaults=function() return {width=80,height=22,screen="BOTTOMRIGHT",x=-8,y=90} end,
    measure=function() if I.badge then return I.badge:GetHeight(),I.badge:GetWidth() end end,
    enabled=function() return I:Config().badgeDock=="free" end,
    preview=function(visible,overlays)
        I.previewStock=visible;I.previewOverlays=overlays
        stockPreview(visible,overlays)
    end,
    apply=function(rect,allowed)
        I.badgeRect=rect;I.badgeAllowed=allowed
        if I.previewStock then stockPreview(true,I.previewOverlays) end
        if I.badge and I:Config().badgeDock=="free" then
            I.badge:ClearAllPoints();I.badge:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
            I.badge:SetShown(allowed~=false and next(I:Config().pins)~=nil)
        end
    end})
function I:UpdateBadge()
    local p=self:Config();local ids={}
    for id in pairs(p.pins) do ids[#ids+1]=id end
    if #ids==0 then if self.badge then self.badge:Hide() end;return end
    table.sort(ids)
    if not self.badge then
        local b=CreateFrame("Button",nil,UIParent);self.badge=b
        b.bg=stripe(b);b.bg:SetColorTexture(.08,.07,.06,.88)
        b.text=UI:Label(b,"",12);b.text:SetPoint("CENTER")
        b:SetScript("OnClick",function(s)
            local t={};for _,id in ipairs(s.ids) do opt(t,id,(I:Config().names[id] or tostring(id)).." × "..s.totals[id]) end
            UI:ContextMenu(s,t,function(id) I:StockMenu(s,id) end)
        end)
    end
    local b=self.badge;local anchor=B.active and B.host or MainMenuBarBackpackButton
    if not anchor and p.badgeDock~="free" then b:Hide();return end
    local totals={};for _,id in ipairs(ids) do totals[id]=0 end
    self:Each(function(v) if v.id and totals[v.id] then totals[v.id]=totals[v.id]+v.count end end)
    local getIcon=C_Item and C_Item.GetItemIconByID or GetItemIcon
    local labels={};for i=1,math.min(3,#ids) do local id=ids[i]
        labels[i]="|T"..tostring(getIcon and getIcon(id) or 134400)..":14|t "..(self.last and tostring(totals[id]) or "…")
    end
    if #ids>3 then labels[#labels+1]="+"..(#ids-3) end
    local vertical=B.active and B:Config().vertical
    b.ids,b.totals=ids,totals;b.text:SetText(table.concat(labels,vertical and "\n" or "  "))
    b:SetSize(b.text:GetStringWidth()+10,b.text:GetStringHeight()+6);b:ClearAllPoints()
    if p.badgeDock=="free" then
        ns.Layout:Refresh()
        local rect=self.badgeRect or ns.Layout.applied[badgeID]
        if not rect or self.badgeAllowed==false then b:Hide();return end
        b:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
    else
        local d=dockPoints[p.badgeDock] or dockPoints.above
        b:SetPoint(d[1],anchor,d[2],d[3],d[4])
    end
    b:SetClampedToScreen(true);b:Show()
end
local function acceptsHeldItem(family, itemFamily)
    return not family or family == 0 or (itemFamily ~= 0 and bit.band(family, itemFamily) ~= 0)
end

local function dropButton(parent)
    local b=CreateFrame("Button",nil,parent)
    b.back=stripe(b);b.back:SetColorTexture(.8,.65,.36,.20)
    local plus=UI:Icon(b,"plus",15,"accent");plus:SetPoint("CENTER")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
    b:RegisterForClicks("LeftButtonUp")
    local function place(self)
        local slot=self.item
        local kind,id=GetCursorInfo()
        local free=I.API("GetContainerNumFreeSlots")
        local family=free and select(2,free(slot.bag))
        if not locked() and kind=="item" and id==self.cursorID and valid(slot)
            and acceptsHeldItem(family,self.itemFamily) then
            local pickup=I.API("PickupContainerItem")
            if pickup then pickup(slot.bag,slot.slot) end
        end
        I.full=true;I:Refresh()
    end
    b:SetScript("OnClick",place);b:SetScript("OnReceiveDrag",place)
    b:SetScript("OnEnter",function(self) tip(self,"Place held item","Use a free bag slot. Your category rules still apply.") end)
    b:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return b
end

function I:Draw()
    local w=self.window;if not w or not w:IsShown() then return end
    local p=self:Config();local query=self.search:GetText():lower()
    local kind,cursorID
    if GetCursorInfo and not locked() then kind,cursorID=GetCursorInfo() end
    local holding=kind=="item" and cursorID
    local getFamily=C_Item and C_Item.GetItemFamily or GetItemFamily
    local itemFamily=holding and getFamily and getFamily(cursorID) or 0
    local destination
    local phys=p.physical;local slot=p.slot or 32
    local groups,by,counts,stock={},{},{},{}
    local labelStyles={}
    local empty,total,special=0,0,0
    local function collect(key,name,hex,v)
        if not by[key] then by[key]={key=key,name=name,color=hex,items={},stacks={}};groups[#groups+1]=by[key] end
        local g=by[key]
        -- Some clients classify Soul Shards as miscellaneous. For reagents
        -- count copies of the item even if their instance links differ.
        local reagent=v.id==6265 or v.class==5 or (v.class==15 and v.subclass==1)
        if not phys and p.groupStacks~=false and query=="" and not self.reveal and v.id and (reagent or (v.maxStack or 1)>1) then
            local id=(not reagent and v.link or tostring(v.id))..":"..tostring(v.bound)
            local stack=g.stacks[id]
            if stack then stack.total=stack.total+v.count;stack.n=stack.n+1;return end
            local index=#g.items+1;stack={total=v.count,n=1};g.stacks[id]=stack;g.stacks[index]=stack
        end
        g.items[#g.items+1]=v
    end
    self:Each(function(v)
        total=total+1;if not v.occupied then
            empty=empty+1;if (self.families[v.bag] or 0)>0 then special=special+1 end
            if holding and not destination and acceptsHeldItem(self.families[v.bag],itemFamily) then destination=v end
        end
        if v.occupied then
            v.key,v.reason=R.Classify(v,p.manual,self.rules);counts[v.key]=(counts[v.key] or 0)+1
            if v.id and p.compact[v.id] then stock[v.id]=(stock[v.id] or 0)+v.count end
        end
        if query~="" and not (phys and holding and not v.occupied) and (not v.occupied or not ((v.name or ""):lower():find(query,1,true) or tostring(v.id)==query)) then return end
        if phys then collect("b"..v.bag,"Bag "..v.bag,"aeaa99",v)
        elseif v.occupied and (query~="" or (not self.hidden[v.key] and (not p.compact[v.id] or self.reveal))) then
            local g=self.lookup[v.key] or self.lookup.misc;collect(g.key,g.name,g.color,v)
        end
    end)
    if not phys then
        local ordered={}
        for _,g in ipairs(self.order) do
            if destination and (by[g.key] or (query=="" and not self.hidden[g.key])) then
                collect(g.key,g.name,g.color,destination)
                by[g.key].dropIndex=#by[g.key].items
            end
            if by[g.key] then ordered[#ordered+1]=by[g.key] end
        end
        groups=ordered
    end
    local width=math.max(1,self.scroll:GetWidth())
    if not phys then
        for _,g in ipairs(groups) do
            local setting=p.categoryHeadings[g.key]
            g.headingMode=setting and setting.mode
            if g.headingMode=="both" or g.headingMode=="label" then
                self.headingMeasure:SetText(g.name)
                g.headingWidth=math.ceil(self.headingMeasure:GetUnboundedStringWidth())+(g.headingMode=="both" and 29 or 11)
            end
        end
    end
    local depth=R.Pack(groups,width,slot,not phys and p.categorySizes or nil)
    self.body:SetSize(width,math.max(1,depth));self.scroll:SetVerticalScroll(math.min(self.scroll:GetVerticalScroll(),math.max(0,depth-self.scroll:GetHeight())))
    local used={};local h=0
    for i,g in ipairs(groups) do
        local slot=g.slot
        local head=self.heads[i] or groupButton(self.body,false);self.heads[i]=head;g.head=head
        head.group=g;head.partner=nil
        local mode=g.headingMode or (g.cols==1 and "icon" or "label")
        groupArt(head,g,self:CategorySymbol(g.key,p.categoryHeadings[g.key]),mode~="label")
        head.glyph:ClearAllPoints()
        if mode=="both" then head.glyph:SetPoint("LEFT",4,0) else head.glyph:SetPoint("CENTER") end
        head.label:ClearAllPoints();head.label:SetPoint("LEFT",mode=="both" and 22 or 6,0)
        head.label:SetPoint("RIGHT",-3,0);head.label:SetJustifyH("LEFT")
        head.label:SetText(mode=="icon" and "" or g.name);put(head,self.body,g.x,g.y,g.width-2,16)
        for j,v in ipairs(g.items) do
            local isDrop=j==g.dropIndex
            local k=isDrop and ("drop:"..g.key) or v.bag*1000+v.slot
            local b=self.slots[k]
            if isDrop then
                b=b or dropButton(self.body)
                b.cursorID=cursorID;b.itemFamily=itemFamily
            else
                b=b or slotButton(self.body)
                local qc=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[v.quality or 1]
                b.back:SetColorTexture(qc and qc.r or .4,qc and qc.g or .4,qc and qc.b or .4,v.occupied and .9 or .32)
                b.icon:SetTexture(v.icon or (v.occupied and 134400 or nil));b.icon:SetDesaturated(v.locked==true)
                local stack=g.stacks[j];b.members=stack and stack.n>1 and stack.n or nil
                b.totalCount=stack and stack.total or v.count
                self:PaintIconLabels(b,v,b.totalCount,bindingLabel(v),p,labelStyles,slot)
            end
            self.slots[k]=b;used[k]=true;b.item=v
            local index=j-1
            if g.dropIndex then index=isDrop and 0 or j end
            put(b,self.body,g.x+(index%g.cols)*(slot+4),g.y+18+math.floor(index/g.cols)*(slot+4),slot,slot)
        end
    end
    for k,b in pairs(self.slots) do if not used[k] then b:Hide() end end
    for i=#groups+1,#self.heads do self.heads[i]:Hide() end
    for _,g in ipairs(self.order) do if not phys and counts[g.key] then
        h=h+1;local b=self.rails[h] or groupButton(self.side,true);self.rails[h]=b;b.group=g
        b.partner=by[g.key] and by[g.key].head;if b.partner then b.partner.partner=b end
        groupArt(b,g,self.hidden[g.key] and "eye-off" or self:CategorySymbol(g.key,p.categoryHeadings[g.key]),true)
        b:SetAlpha(self.hidden[g.key] and .48 or 1)
        put(b,self.side,0,(h-1)*25,24,23)
    end end
    for i=h+1,#self.rails do self.rails[i]:Hide() end
    self.side:SetSize(25,math.max(1,h*25))
    self.contentDepth=math.max(depth,h*25)
    self.stock=stock
    local ids={};for id in pairs(p.compact) do ids[#ids+1]=id end;table.sort(ids)
    local labels={}
    for _,id in ipairs(ids) do labels[#labels+1]=(p.names[id] or tostring(id)).." × "..(stock[id] or 0) end
    self.stockText:SetText(table.concat(labels,"    ·    "))
    self.stockText:SetShown(#ids>0)
    self.scroll:SetPoint("BOTTOMRIGHT",w.content,"BOTTOMRIGHT",-6,#ids>0 and 53 or 31)
    self.rail:SetPoint("BOTTOMLEFT",w.content,"BOTTOMLEFT",2,#ids>0 and 53 or 31)
    self.summary:SetText(locked() and "In combat · last inventory" or (special>0 and ((empty-special).." free + "..special.." specialty") or (empty.." / "..total.." free")))
    self.mode:SetShown(not phys)
    self.physicalMode:SetShown(phys==true)
    self.stacks:SetAlpha(not phys and p.groupStacks~=false and 1 or .55)
    self.message:SetText(#groups==0 and (query~="" and "No matching items" or "No visible items") or "")
    if self.editor and self.editor:IsShown() then self.editor.preview() end
end
function I:Open()
    local p=self:Config();self:Prepare()
    if not self.window then
        local w=UI:Window("BVBagInventoryPrototype",p.width or 460,p.height or 328,{title="Inventory",minWidth=380,minHeight=220,compact=true,hudIcon="backpack",gameplaySurface=true})
        self.window=w;self.heads,self.rails,self.slots={},{},{}
        local c=w.content
        self.headingMeasure=UI:Label(c,"",12);self.headingMeasure:Hide()
        local function toggleView() local cfg=self:Config();cfg.physical=not cfg.physical;self:Refresh() end
        self.mode=UI:IconButton(c,"layout-grid",toggleView,"icon-only")
        self.mode:SetSize(24,25);self.mode:SetPoint("TOPRIGHT",-87,-3)
        self.physicalMode=UI:IconButton(c,"backpack",toggleView,"icon-only")
        self.physicalMode:SetAllPoints(self.mode);self.physicalMode:Hide()
        UI:AttachTooltip(self.mode,"Grouped inventory","Switch to individual bags and their physical slots.")
        UI:AttachTooltip(self.physicalMode,"Individual bags","Switch to category groups.")
        self.search=UI:Input(c,130);self.search:SetHeight(25);self.search:SetPoint("TOPLEFT",6,-3);self.search:SetPoint("TOPRIGHT",self.mode,"TOPLEFT",-8,0)
        local glass=UI:Icon(self.search,"search",13,"muted");glass:SetPoint("LEFT",6,0);self.search:SetTextInsets(22,4,0,0)
        local hint=UI:Label(self.search,"Find an item",12,"muted");hint:SetPoint("LEFT",23,0)
        UI:AttachTooltip(self.search,"Search carried items","Enter a name or item ID. Search includes hidden categories and condensed stock.")
        self.search:HookScript("OnTextChanged",function(box) hint:SetShown(box:GetText()=="");self.scroll:SetVerticalScroll(0);self:Refresh() end)
        local rules=UI:IconButton(c,"list-tree",function() self:OpenCategoryEditor(self.order[1] and self.order[1].key) end,"icon-only")
        rules:SetSize(24,25);rules:SetPoint("TOPRIGHT",-60,-3);UI:AttachTooltip(rules,"Edit categories","Create categories, choose conditions and preview matching items.")
        self.labelButton=UI:IconButton(c,"text",function() self:OpenIconLabels() end,"icon-only")
        self.labelButton:SetSize(24,25);self.labelButton:SetPoint("TOPRIGHT",-33,-3)
        UI:AttachTooltip(self.labelButton,"Item icon labels","Choose which labels appear, their corner, font size and color.")
        local size=UI:IconButton(c,"fit",function(b)
            local opts={{value="fit",label="Fit height to contents"},{value="category",label="Size by category…"}}
            for _,n in ipairs(R.sizes) do opt(opts,n,"Default item size · "..n.." px") end
            UI:ContextMenu(b,opts,function(n)
                if n=="fit" then
                    local target=w:GetHeight()-self.scroll:GetHeight()+(self.contentDepth or 0)+3
                    w:SetHeight(math.min(UIParent:GetHeight()*.85,math.max(ns.DesignSystem.Metrics.ToNative(220),target)))
                elseif n=="category" then
                    local groups={}
                    for _,g in ipairs(self.order) do
                        local override=self:Config().categorySizes[g.key]
                        opt(groups,g.key,g.name.." · "..(override and override.." px" or "Inherit"))
                    end
                    UI:ContextMenu(b,groups,function(key) self:CategorySize(b,key) end)
                else self:Config().slot=n;self:Refresh() end
            end)
        end,"icon-only")
        size:SetSize(24,25);size:SetPoint("TOPRIGHT",-6,-3);UI:AttachTooltip(size,"Inventory layout","Fit the window to its contents or adjust item size.")
        self.rail,self.side=scroller(c);self.rail:SetPoint("TOPLEFT",2,-34);self.rail:SetPoint("BOTTOMLEFT",2,31);self.rail:SetWidth(26)
        self.scroll,self.body=scroller(c);self.scroll:SetPoint("TOPLEFT",36,-36);self.scroll:SetPoint("BOTTOMRIGHT",-6,31)
        self.message=UI:Label(c,"",13);self.message:SetPoint("CENTER")
        self.summary=UI:Label(c,"",13);self.summary:SetPoint("BOTTOMLEFT",3,7)
        self.supply=UI:IconButton(c,"boxes",function(b)
            local opts={};opt(opts,"add","Track an item from my bags…")
            local cfg=self:Config()
            if next(cfg.compact) then opt(opts,"reveal",self.reveal and "Condense slots again" or "Temporarily reveal slots") end
            local ids={};for id in pairs(cfg.compact) do ids[#ids+1]=id end
            for id in pairs(cfg.pins) do if not cfg.compact[id] then ids[#ids+1]=id end end;table.sort(ids)
            for _,id in ipairs(ids) do
                local count=self.stock[id] or (self.badge and self.badge.totals and self.badge.totals[id]) or 0
                opt(opts,id,(cfg.names[id] or tostring(id)).." × "..count)
            end
            UI:ContextMenu(b,opts,function(k)
                if k=="add" then self:ChooseStockItem(b)
                elseif k=="reveal" then self.reveal=not self.reveal;self:Refresh()
                else self:StockMenu(b,k) end
            end)
        end,"icon-only")
        self.supply:SetSize(24,23);self.supply:SetPoint("BOTTOMRIGHT",-14,3)
        self.stacks=UI:IconButton(c,"layers",function() self:ToggleStacks() end,"icon-only")
        self.stacks:SetSize(24,23);self.stacks:SetPoint("RIGHT",self.supply,"LEFT",-4,0)
        UI:AttachTooltip(self.stacks,"Group identical stacks","Display a total or show each slot. Nothing moves. Bind a shortcut under Key Bindings → BV Addon Suite.")
        self.tidy=UI:IconButton(c,"arrow-up-down",function() self:TidyBags() end,"icon-only")
        self.tidy:SetSize(24,23);self.tidy:SetPoint("RIGHT",self.stacks,"LEFT",-4,0)
        UI:AttachTooltip(self.tidy,"Clean up bags","Physically combine partial stacks and sort carried items. Bank contents stay in place.")
        self.stockText=UI:Label(c,"",13,"accentText");self.stockText:SetPoint("BOTTOMLEFT",5,30);self.stockText:SetPoint("BOTTOMRIGHT",-7,30)
        self.stockText:SetWordWrap(false)
        UI:AttachTooltip(self.supply,"Tracked stock","Choose a carried item to count here, pin to the bag bar or reveal temporarily.")
        w:HookScript("OnSizeChanged",function() if w:IsShown() then self:Refresh() end end)
        w:HookScript("OnHide",function()
            if self.headingWindow then self.headingWindow:Hide() end
            if self.splitWindow then self.splitWindow:Hide() end
            local cfg=self:Config()
            if not w.minimized and not w.maximized then
                local m=ns.DesignSystem.Metrics;cfg.width=m.GetWidth(w);cfg.height=m.GetHeight(w);UI:SaveWindowPosition(w)
            end
            if self.editor then self.editor:Hide() end
            self.hidden={};self.reveal=false;self.search:SetText("");self.scroll:SetVerticalScroll(0)
        end)
    end
    UI:RestoreWindowPosition(self.window)
    self.full=true;self.window:Show();self:Scan();self:Draw();self:UpdateBadge()
end
function I:Toggle() if self.window and self.window:IsShown() then self.window:Hide() else self:Open() end end
-- The client's key and bag buttons can call several nested toggle functions.
-- Consume a gesture once, after Blizzard has finished choosing its bag frames.
local function hideCarriedBags()
    local last=NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for i=1,NUM_CONTAINER_FRAMES or 13 do
        local f=_G["ContainerFrame"..i]
        if f and f:IsShown() then
            local id=f.GetBagID and f:GetBagID() or f.GetID and f:GetID()
            if type(id)=="number" and id>=0 and id<=last then f:Hide() end
        end
    end
    local combined=ContainerFrameCombinedBags
    if combined and combined:IsShown() then combined:Hide() end
end
local function routeToggle()
    if not ns.ready or locked() or B:Config().replaceInventory==false then return end
    hideCarriedBags()
    if I.nativePending then return end
    I.nativePending=true
    C_Timer.NewTimer(0,function() I.nativePending=nil end)
    I:Toggle()
end
function I:InstallBagToggles()
    if not hooksecurefunc then return end
    self.bagHooks=self.bagHooks or {}
    local function hook(owner,name,callback)
        local key=(owner==_G and "global:" or "container:")..name
        if self.bagHooks[key] or not owner or type(owner[name])~="function" then return end
        if owner==_G then hooksecurefunc(name,callback) else hooksecurefunc(owner,name,callback) end
        self.bagHooks[key]=true
    end
    local function oneBag(id)
        if type(id)=="number" and id>=0 and id<=(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) then routeToggle() end
    end
    hook(_G,"ToggleAllBags",routeToggle);hook(_G,"ToggleBackpack",routeToggle);hook(_G,"ToggleBag",oneBag)
    hook(C_Container,"ToggleAllBags",routeToggle);hook(C_Container,"ToggleBackpack",routeToggle);hook(C_Container,"ToggleBag",oneBag)
end
ns.Events:Subscribe(I,"PLAYER_ENTERING_WORLD",function() I:InstallBagToggles() end)
if ns.ready then I:InstallBagToggles() end
ns.Commands:RegisterAction("inventory",function() I:Toggle() end)
BINDING_NAME_BVBAGS_INVENTORY="BV inventory"
BINDING_NAME_BVBAGS_STACKS="Group / separate inventory stacks"

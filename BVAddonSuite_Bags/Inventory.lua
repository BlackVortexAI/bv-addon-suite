local ns=BVAddonSuiteCore
local B=ns and ns.Bags
if not (B and B.InventoryRules) then return end
local R=B.InventoryRules
local I={bags={},families={},dirty={},hidden={},lookup={},order={},rules={},meta={},waiting={}}
B.Inventory=I
function I:Config()
    local c=B:Config()
    -- Seed only a new inventory. Existing sparse layouts keep their own
    -- inheritance, including categories explicitly reset to the global size.
    if not c.inventory then
        c.inventory={
            width=440, height=288, slot=32, physical=false, groupStacks=true, lootRelief=true,
            categorySizes={gear=36, trade=28, reagent=28},
            cornerLayouts={default={
                TOPLEFT={First="binding", Size=9, Color="EFE2CBFF", Mode="quality", Outline="normal"},
                TOPRIGHT={Mode="quality", Outline="normal"},
                BOTTOMLEFT={Mode="quality", Outline="normal"},
                BOTTOMRIGHT={First="quantity", Size=11, Color="FFFFFFFF", Mode="quality", Outline="normal"},
            }},
        }
    end
    local p=c.inventory
    for _,key in ipairs({"categories","manual","compact","pins","names","categorySizes","categoryLabels","categoryHeadings"}) do
        if type(p[key])~="table" then p[key]={} end
    end
    return p
end
function I:Prepare()
    local p=self:Config()
    self.lookup,self.order,self.rules={},{},{}
    local function add(g) self.lookup[g.key]=g;self.order[#self.order+1]=g end
    for _,r in ipairs(p.categories) do
        add(r)
        self.rules[#self.rules+1]={key=r.key,source=r.source,test=R.Compile(r.source)}
    end
    for _,g in ipairs(R.groups) do add(g) end
end
function I:NewKey()
    local p=self:Config()
    p.serial=(p.serial or 0)+1
    return "custom"..p.serial
end
function I:SaveRule(key,name,source,color)
    local fn,err=R.Compile(source)
    if not fn then return nil,err end
    name=name:match("^%s*(.-)%s*$")
    if name=="" or name:find("|",1,true) then return nil,"Enter a category name without |" end
    local p=self:Config()
    local rule
    for _,r in ipairs(p.categories) do
        if r.key==key then rule=r elseif r.name:lower()==name:lower() then return nil,"Name already in use" end
    end
    if not rule then
        if #p.categories>=32 then return nil,"Limit: 32 custom categories" end
        rule={key=self:NewKey()};p.categories[#p.categories+1]=rule
    end
    rule.name,rule.source,rule.color,rule.icon=name,source,color,133633
    self:Prepare();self:Refresh()
    return rule.key
end
function I:Alter(key,action)
    local p=self:Config()
    for i,r in ipairs(p.categories) do if r.key==key then
        if action=="delete" then
            table.remove(p.categories,i)
            for id,k in pairs(p.manual) do if k==key then p.manual[id]=nil end end
            self.hidden[key]=nil
            p.categorySizes[key]=nil
            p.categoryHeadings[key]=nil
            p.categoryLabels[key]=nil
            if p.cornerLayouts then p.cornerLayouts[key]=nil end
        else
            local j=math.max(1,math.min(#p.categories,i+action))
            p.categories[i],p.categories[j]=p.categories[j],r
        end
        break
    end end
    self:Prepare();self:Refresh()
end
local api=function(name) return C_Container and C_Container[name] or _G[name] end
I.API=api
local function info(id)
    if not id then return {} end
    if I.meta[id] then return I.meta[id] end
    local f=C_Item and C_Item.GetItemInfo or GetItemInfo
    if not f then return {} end
    local name,_,quality,level,required,ty,sub,maxStack,equip,icon,vendor,class,subclass,bind=f(id)
    local m={name=name,quality=quality,level=level,required=required,vendor=vendor,type=ty,subtype=sub,equip=equip,icon=icon,class=class,subclass=subclass,maxStack=maxStack,bind=bind}
    if name then I.meta[id]=m;I.waiting[id]=nil else I.waiting[id]=true end
    return m
end
function I:Scan()
    if InCombatLockdown and InCombatLockdown() then return end
    local slots,read=api("GetContainerNumSlots"),api("GetContainerItemInfo")
    if not slots or not read then return end
    local last=NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag=0,last do
        if self.full or self.dirty[bag] or not self.bags[bag] then
            local items={};self.bags[bag]=items
            local free=api("GetContainerNumFreeSlots")
            if free then self.families[bag]=select(2,free(bag)) end
            for slot=1,slots(bag) or 0 do
                local raw,n,locked,q,_,_,link,_,_,id=read(bag,slot)
                local icon=raw
                if type(raw)=="table" then
                    icon,n,locked,q,link,id=raw.iconFileID,raw.stackCount,raw.isLocked,raw.quality,raw.hyperlink,raw.itemID
                end
                if not id and link then id=tonumber(link:match("item:(%d+)")) end
                local m=info(id)
                items[slot]={bag=bag,slot=slot,id=id,link=link,count=n or 1,locked=locked,icon=icon or m.icon,
                    name=m.name,type=m.type,subtype=m.subtype,class=m.class,subclass=m.subclass,vendor=m.vendor,required=m.required,
                    bound=type(raw)=="table" and raw.isBound~=nil and (raw.isBound and 1 or 0) or nil,
                    equip=m.equip,level=m.level,quality=q or m.quality,occupied=raw~=nil,maxStack=m.maxStack,bind=m.bind}
            end
        end
    end
    self.last=last;self.full=false;self.dirty={}
end
function I:Each(fn)
    for bag=0,self.last or 0 do for _,v in ipairs(self.bags[bag] or {}) do fn(v) end end
end
function I:Refresh()
    if self.pending then return end
    self.pending=true
    C_Timer.NewTimer(.05,function()
        self.pending=false
        if not ns.ready then return end
        local open=self.window and self.window:IsShown()
        if not open and not next(self:Config().pins) then self.full=true;if self.badge then self.badge:Hide() end;return end
        self:Scan()
        if self.UpdateBadge then self:UpdateBadge() end
        if open and self.Draw then self:Draw() end
    end)
end
local function changed(e,id,ok)
    if not ns.ready then return end
    if e=="QUEST_LOG_UPDATE" or e=="PLAYER_LEVEL_UP" or e=="AUCTION_HOUSE_CLOSED" then
        if not (I.window and I.window:IsShown()) then return end
        if e=="QUEST_LOG_UPDATE" then I:Each(function(item) item.questMarker=nil end) end
        I:Refresh();return
    end
    if not (I.window and I.window:IsShown()) then
        local p=ns.Settings:Module("bag_bar").inventory
        if not (p and p.pins and next(p.pins)) then return end
    end
    if e=="BAG_UPDATE" then if id and id>=0 then I.dirty[id]=true end
    elseif e=="GET_ITEM_INFO_RECEIVED" then
        if not ok or not I.waiting[id] then return end
        I.full=true
    elseif e=="CURSOR_CHANGED" then if not (I.window and I.window:IsShown()) then return end
    elseif e~="BAG_UPDATE_DELAYED" then I.full=true end
    I:Refresh()
end
for _,e in ipairs({"PLAYER_ENTERING_WORLD","BAG_UPDATE","BAG_UPDATE_DELAYED","GET_ITEM_INFO_RECEIVED","PLAYER_REGEN_ENABLED","PLAYER_REGEN_DISABLED","CURSOR_CHANGED","QUEST_LOG_UPDATE","PLAYER_LEVEL_UP","AUCTION_HOUSE_CLOSED"}) do ns.Events:Subscribe(I,e,changed) end
if ns.Settings.BeforeProfileChange then ns.Settings:BeforeProfileChange(I,function()
    if I.headingWindow then I.headingWindow:Hide() end
    if I.window then I.window:Hide() end
end) end
if ns.Settings.AfterProfileChange then ns.Settings:AfterProfileChange(I,function()
    I.full=true
    if (I.window and I.window:IsShown()) or next(I:Config().pins) then
        I:Refresh()
    elseif I.badge then
        I.badge:Hide()
    end
end) end

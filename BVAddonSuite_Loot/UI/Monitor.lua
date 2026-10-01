local _,L=...
if not L.ready then return end
-- Loot monitor (point 2): looted items as toasts from one anchor, newest at
-- the anchor, older ones pushed along the grow direction, each fading out
-- after its hold time. Own loot and group loot have separate quality filters.
local ns=L.ns
local UI,Theme,D=ns.UI,ns.Theme,ns.DesignSystem.Metrics
local W=L.Widgets
local M={toasts={},pool={}}
L.Monitor=M
local HEIGHT=40

local SELF={{"LOOT_ITEM_SELF_MULTIPLE"},{"LOOT_ITEM_SELF"},{"LOOT_ITEM_PUSHED_SELF_MULTIPLE",true},{"LOOT_ITEM_PUSHED_SELF",true}}
local OTHER={{"LOOT_ITEM_MULTIPLE"},{"LOOT_ITEM"},{"LOOT_ITEM_PUSHED_MULTIPLE",true},{"LOOT_ITEM_PUSHED",true}}
local MONEY={"YOU_LOOT_MONEY_GUILD","YOU_LOOT_MONEY","LOOT_MONEY_SPLIT_GUILD","LOOT_MONEY_SPLIT"}

local function linkName(link)
    return type(link)=="string" and link:match("|h%[(.-)%]|h") or link
end
-- Chat line -> {looter, link, count, self} or nil.
function M.Parse(text)
    if type(text)~="string" or L.Secret(text) or not text:find("|H",1,true) then return nil end
    for _,row in ipairs(SELF) do
        local ok,a=L.Match(_G[row[1]],text)
        if ok then return {looter=L.Me(),link=a[1],count=tonumber(a[2]) or 1,self=true,pushed=row[2]} end
    end
    for _,row in ipairs(OTHER) do
        local ok,a=L.Match(_G[row[1]],text)
        if ok then return {looter=L.Short(a[1]),link=a[2],count=tonumber(a[3]) or 1,self=L.Short(a[1])==L.Me(),pushed=row[2]} end
    end
    return nil
end
function M.ParseMoney(text)
    if type(text)~="string" or L.Secret(text) then return nil end
    for _,key in ipairs(MONEY) do
        local ok,a=L.Match(_G[key],text)
        if ok then return a[1] end
    end
    return nil
end

function M:Loot(text)
    local cfg=L:Config()
    if not cfg.monitor then return end
    local data=M.Parse(text)
    if not data or not data.link then return end
    if data.self and not cfg.monitorSelf or not data.self and not cfg.monitorGroup then return end
    local info=L.Item(data.link)
    if info.quality and info.quality<(data.self and cfg.monitorSelfQuality or cfg.monitorGroupQuality) then return end
    data.kind,data.itemID,data.class="item",info.id,L.ClassOf(data.looter)
    data.key=(data.looter or "?")..":"..tostring(info.id or data.link)
    L:Emit("LootReceived",{looter=data.looter,link=data.link,itemID=data.itemID,count=data.count,self=data.self})
    self:Push(data)
end
function M:Money(text)
    local cfg=L:Config()
    if not cfg.monitor or not cfg.monitorMoney or not cfg.monitorSelf then return end
    local amount=M.ParseMoney(text)
    if amount then self:Push({kind="money",text=amount,looter=L.Me(),self=true,key="money"}) end
end

function M:Toast()
    local t=table.remove(self.pool)
    if t then return t end
    t={}
    local f=W.Owned(UI:Panel(self.anchor.frame,270,HEIGHT,"canvas"));t.frame=f;f:Hide();f:EnableMouse(true)
    t.stripe=f:CreateTexture(nil,"ARTWORK");D.Point(t.stripe,"TOPLEFT",f,"TOPLEFT",0,0);D.Point(t.stripe,"BOTTOMLEFT",f,"BOTTOMLEFT",0,0);D.Width(t.stripe,3)
    t.item=W:ItemIcon(f,32);UI:Place(t.item,f,7,4);t.item:EnableMouse(false)
    t.name=UI:Label(f,"",13,false,true);t.name:SetWordWrap(false)
    t.sub=UI:Label(f,"",11,false);t.sub:SetWordWrap(false);t.sub:SetTextColor(.82,.8,.78)
    t.fader=W:Fader(f)
    f:SetScript("OnEnter",function(owner) if t.data and t.data.link then W:ItemTooltip(owner,{link=t.data.link,itemID=t.data.itemID,source="monitor",player=t.data.looter}) end end)
    f:SetScript("OnLeave",function(owner) W:HideTooltip(owner) end)
    f:SetScript("OnMouseUp",function(_,button)
        if button=="RightButton" then M:Release(t)
        elseif t.data and t.data.link and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick then HandleModifiedItemClick(t.data.link) end
    end)
    return t
end
function M:Paint(t)
    local data,w=t.data,self.anchor:Width()
    D.Size(t.frame,w,HEIGHT)
    UI:Place(t.name,t.frame,46,5);D.Size(t.name,w-52,16)
    UI:Place(t.sub,t.frame,46,22);D.Size(t.sub,w-52,14)
    if data.kind=="money" then
        t.item:SetItem("Interface\\Icons\\INV_Misc_Coin_01",1)
        t.name:SetText(data.text);t.name:SetTextColor(1,.82,.2)
        t.sub:SetText(MONEY_LOOT or MONEY or "Money")
        t.stripe:SetColorTexture(1,.82,.2,1)
        return
    end
    local info=L.Item(data.link)
    local quality=info.quality or data.quality or 1
    local r,g,b=L.QualityColor(quality)
    t.item:SetItem(info.icon,quality,nil,data.count)
    t.name:SetText((info.name or linkName(data.link) or "?")..(data.count>1 and ("  x"..data.count) or ""));t.name:SetTextColor(r,g,b)
    t.stripe:SetColorTexture(r,g,b,1)
    local parts={}
    if not data.self then parts[#parts+1]=L.Colored(data.looter,data.class) end
    if info.level and info.level>1 and (info.classID==2 or info.classID==4) then parts[#parts+1]=(ITEM_LEVEL_ABBR or "iLvl").." "..info.level end
    local kind=L.ItemKind(info)
    if kind then parts[#parts+1]=kind end
    t.sub:SetText(table.concat(parts,"  ·  "))
end
function M:Release(t)
    if t.timer then t.timer:Cancel();t.timer=nil end
    t.fader:Stop();t.frame:Hide();t.data=nil
    for i,v in ipairs(self.toasts) do if v==t then table.remove(self.toasts,i);break end end
    self.pool[#self.pool+1]=t
    self.anchor:Arrange(self:Frames())
end
function M:Frames()
    local out={}
    for i,t in ipairs(self.toasts) do out[i]=t.frame end
    return out
end
function M:Hold(t)
    local hold=L:Config().monitorDuration
    if t.timer then t.timer:Cancel() end
    t.fader:Run(hold,.4)
    t.timer=C_Timer.NewTimer(hold+.6,function() t.timer=nil;M:Release(t) end)
end
function M:Push(data)
    if not self.anchor then return end
    for _,t in ipairs(self.toasts) do
        if t.data and t.data.key==data.key and data.kind=="item" then
            t.data.count=t.data.count+data.count
            self:Paint(t);self:Hold(t);return t
        end
    end
    local t=self:Toast()
    t.data=data
    table.insert(self.toasts,1,t)
    local max=L:Config().monitorMax
    while #self.toasts>max do self:Release(self.toasts[#self.toasts]) end
    self:Paint(t);t.frame:Show();self:Hold(t)
    self.anchor:Arrange(self:Frames())
    return t
end
-- Item info arrived from the server: repaint toasts that showed a fallback.
function M:InfoReceived()
    for _,t in ipairs(self.toasts) do if t.data then self:Paint(t) end end
end
function M:Clear() for i=#self.toasts,1,-1 do self:Release(self.toasts[i]) end end

function M:Preview(on)
    self:Clear()
    if not on then return end
    local me=L.Me()
    for _,row in ipairs({{me,19019,1,true},{"Thalya",16909,1},{me,13446,5,true},{"Brokk",18832,1}}) do
        local link="item:"..row[2]
        local t=self:Push({kind="item",link=link,looter=row[1],count=row[3],self=row[4]==true,key=row[1]..row[2],itemID=row[2],class=row[4] and nil or "PRIEST"})
        if t then t.fader:Stop();if t.timer then t.timer:Cancel();t.timer=nil end end
    end
end
function M:Create()
    if self.anchor then return end
    self.anchor=W:Anchor({layout="bv:lootmonitor",label="Loot Monitor",screen="BOTTOMRIGHT",x=-360,y=260,
        width=function() return L:Config().monitorWidth end,height=function() return HEIGHT end,
        grow=function() return L:Config().monitorGrow end,spacing=function() return 4 end,
        enabled=function() return L:Config().monitor end,
        resized=function(width)
            if ns.Layout.draft then return end
            L:Config().monitorWidth=math.floor(width+.5)
            for _,t in ipairs(M.toasts) do if t.data then M:Paint(t) end end
        end,
        preview=function(on) M:Preview(on) end})
end
function M:Enable(context)
    self:Create()
    context:Subscribe("CHAT_MSG_LOOT",function(_,text) M:Loot(text) end)
    context:Subscribe("CHAT_MSG_MONEY",function(_,text) M:Money(text) end)
    context:Defer(function() M:Clear() end)
    W:Refresh()
end
-- The layout element exists from load on, so the Layout Editor knows it.
M:Create()

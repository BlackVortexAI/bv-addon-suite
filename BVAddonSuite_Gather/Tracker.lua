local _,G=...
if not G.ready then return end
-- Gather tracker (Florian 2026-10-09): what this session brought. Start,
-- pause and stop; nodes gathered and the items looted from them (loot
-- within a few seconds after a gathering cast, so mob loot stays out unless
-- "count all loot"), their value and gold per hour. Prices: TSM
-- (TSM_API.GetCustomPriceValue "dbmarket"), Auctionator
-- (Auctionator.API.v1.GetAuctionPriceByItemID), else the vendor price; the
-- setting picks one or "auto" (TSM, then Auctionator, then vendor).
-- Stopped sessions are kept (the last 50) with their route.
local ns=G.ns
local T={}
G.Tracker=T
T.WINDOW=5      -- seconds after a gathering cast in which loot counts
T.KEEP=50

local function now() return GetTime() end
function T:Session()
    local db=G.Data.db or G.Data:Init()
    return db.session
end
function T:State()
    local s=self:Session()
    if not s then return "stopped" end
    return s.paused and "paused" or "running"
end
function T:Start()
    local s=self:Session()
    if s and s.paused then s.paused=false;s.idle=nil;s.resumed=now();s.active=now();self:Changed();return end
    if s then return end
    local follow=G.Follow and G.Follow:State()
    G.Data.db.session={started=time(),resumed=now(),active=now(),elapsed=0,nodes=0,items={},route=follow and follow.name or nil}
    self:Changed()
end
function T:Pause()
    local s=self:Session()
    if not s or s.paused then return end
    s.idle=nil
    s.elapsed=s.elapsed+(now()-s.resumed);s.paused=true
    self:Changed()
end
function T:Stop()
    local s=self:Session()
    if not s then return nil end
    if not s.paused then s.elapsed=s.elapsed+(now()-s.resumed) end
    local db=G.Data.db
    db.sessions=db.sessions or {}
    local entry={started=s.started,duration=s.elapsed,nodes=s.nodes,items=s.items,value=self:Value(s),route=s.route}
    table.insert(db.sessions,1,entry)
    while #db.sessions>T.KEEP do table.remove(db.sessions) end
    db.session=nil
    self:Changed()
    return entry
end
function T:Elapsed(s)
    s=s or self:Session()
    if not s then return 0 end
    return s.elapsed+(s.paused and 0 or (now()-s.resumed))
end

-- Prices in copper.
function T.Price(itemID)
    local source=G:Config().priceSource
    local function tsm()
        local api=rawget(_G,"TSM_API")
        if type(api)=="table" and type(api.GetCustomPriceValue)=="function" then
            local ok,value=pcall(api.GetCustomPriceValue,"dbmarket","i:"..itemID)
            if ok and type(value)=="number" and value>0 then return value end
        end
    end
    local function auctionator()
        local api=rawget(_G,"Auctionator")
        api=type(api)=="table" and type(api.API)=="table" and api.API.v1
        if type(api)=="table" and type(api.GetAuctionPriceByItemID)=="function" then
            local ok,value=pcall(api.GetAuctionPriceByItemID,"BV Addon Suite",itemID)
            if ok and type(value)=="number" and value>0 then return value end
        end
    end
    local function vendor()
        local sell=select(11,G.Call("GetItemInfo",itemID))
        return type(sell)=="number" and sell or 0
    end
    if source=="tsm" then return tsm() or 0 end
    if source=="auctionator" then return auctionator() or 0 end
    if source=="vendor" then return vendor() end
    return tsm() or auctionator() or vendor()
end
function T:Value(s)
    s=s or self:Session()
    local total=0
    for itemID,count in pairs(s and s.items or {}) do total=total+T.Price(itemID)*count end
    return total
end
function T:PerHour(s)
    local seconds=self:Elapsed(s)
    if seconds<1 then return 0 end
    return self:Value(s)/seconds*3600
end
function T.Money(copper)
    copper=math.floor(copper or 0)
    local gold,silver=math.floor(copper/10000),math.floor(copper/100)%100
    if gold>0 then return string.format("%dg %02ds",gold,silver) end
    return string.format("%ds %02dc",silver,copper%100)
end

-- Gathering casts open the loot window; loot lines count while it is open.
function T:Gathered(spellID)
    local s=self:Session()
    if not s or not G.Record:Kind(spellID) then return end
    -- Paused by itself for idling: gathering again resumes it.
    if s.paused and s.idle then self:Start() end
    if s.paused then return end
    s.nodes=s.nodes+1
    s.active=now()
    self.lootUntil=now()+T.WINDOW
    self:Changed()
end
local function pattern(format)
    if type(format)~="string" then return nil end
    local p=format:gsub("([%(%)%.%+%-%*%?%[%]%^%$])","%%%1"):gsub("%%s","(.+)"):gsub("%%d","(%%d+)")
    return "^"..p.."$"
end
function T.ParseLoot(text)
    if type(text)~="string" or G.Secret(text) then return nil end
    for _,name in ipairs({"LOOT_ITEM_SELF_MULTIPLE","LOOT_ITEM_PUSHED_SELF_MULTIPLE"}) do
        local p=pattern(rawget(_G,name) or (name=="LOOT_ITEM_SELF_MULTIPLE" and "You receive loot: %sx%d." or nil))
        local link,count
        if p then link,count=text:match(p) end
        if link then return tonumber(link:match("item:(%d+)")),tonumber(count) or 1,link:match("|h%[(.-)%]|h") end
    end
    for _,name in ipairs({"LOOT_ITEM_SELF","LOOT_ITEM_PUSHED_SELF"}) do
        local p=pattern(rawget(_G,name) or (name=="LOOT_ITEM_SELF" and "You receive loot: %s." or nil))
        local link
        if p then link=text:match(p) end
        if link then return tonumber(link:match("item:(%d+)")),1,link:match("|h%[(.-)%]|h") end
    end
    return nil
end
function T:Loot(text)
    local s=self:Session()
    if not s or s.paused then return end
    if not G:Config().trackAllLoot and not (self.lootUntil and now()<=self.lootUntil) then return end
    local itemID,count,name=T.ParseLoot(text)
    if not itemID then return end
    s.items[itemID]=(s.items[itemID] or 0)+count
    -- The loot line names the item: shown until the client has its data.
    if name then s.names=s.names or {};s.names[itemID]=name end
    self:Changed()
end
function T:Changed() if G.TrackerWindow and G.TrackerWindow.Refresh then G.TrackerWindow:Refresh() end end
-- No gathering for a while (Florian 2026-10-09): the clock pauses at the
-- last node, so gold per hour stays honest; the next node resumes it.
function T:CheckIdle()
    local s=self:Session()
    local minutes=G:Config().trackerIdle
    if not s or s.paused or minutes<=0 then return end
    local last=s.active or s.resumed
    if now()-last>=minutes*60 then
        -- Counted up to the last activity, not the time spent idling.
        s.elapsed=s.elapsed+math.max(0,last-s.resumed);s.paused=true;s.idle=true
        G:Print(string.format("Tracker paused: no gathering for %d min. The next node resumes it.",minutes))
        self:Changed()
    end
end
function T:Enable(context)
    pcall(context.Subscribe,context,"UNIT_SPELLCAST_SUCCEEDED",function(_,unit,_,spellID) if unit=="player" then T:Gathered(spellID) end end)
    pcall(context.Subscribe,context,"CHAT_MSG_LOOT",function(_,text) T:Loot(text) end)
    T.idleTicker=C_Timer.NewTicker(15,function() T:CheckIdle() end)
    context:Defer(function() if T.idleTicker then T.idleTicker:Cancel();T.idleTicker=nil end end)
    -- Item data arriving from the server: names, icons and vendor prices complete.
    pcall(context.Subscribe,context,"GET_ITEM_INFO_RECEIVED",function() T:Changed() end)
    -- A running session pauses when the module goes off (and on a reload its clock restarts there).
    local s=self:Session()
    if s and not s.paused then s.resumed=now() end
    context:Defer(function() T:Pause() end)
end

local _,L=...
if not L.ready then return end
-- Module wiring, settings page and /bv loot commands.
local ns=L.ns
local UI,D=ns.UI,ns.DesignSystem.Metrics
local R=L.Rolls

-- Optional client events: an unknown event must not fault the module.
local function optional(context,event,callback)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return false end
    return (pcall(context.Subscribe,context,event,callback))
end
function L:Changed()
    if not self:Active() then return end
    L.RollFrame:Sync();L.Results:Repaint();if L.Master.window then L.Master:Refresh() end
    L.Widgets:Refresh()
end
local refreshTimer
local function infoReceived()
    if refreshTimer then return end
    refreshTimer=C_Timer.NewTimer(.2,function()
        refreshTimer=nil
        if not L:Active() then return end
        L.RollFrame:Sync();L.Monitor:InfoReceived();L.Results:Repaint()
        if L.Master.window then L.Master:Refresh() end
    end)
end

ns.Modules:Register({id=L.ID,OnEnable=function(context)
    L.context=context
    context:Defer(function() L.context=nil end)
    L:Config()
    L.Comm:Start(context)
    context:Subscribe("START_LOOT_ROLL",function(_,rollID,ms) R:StartNative(rollID,ms) end)
    context:Subscribe("CHAT_MSG_LOOT",function(_,text) R:Loot(text) end)
    context:Subscribe("CHAT_MSG_SYSTEM",function(_,text) R:System(text) end)
    optional(context,"CANCEL_LOOT_ROLL",function(_,rollID) R:Cancel(rollID) end)
    optional(context,"CANCEL_ALL_LOOT_ROLLS",function() R:CancelAll() end)
    if C_LootHistory then
        optional(context,"LOOT_HISTORY_ROLL_CHANGED",function(_,item,player) R:HistoryChanged(item,player) end)
        optional(context,"LOOT_HISTORY_ROLL_COMPLETE",function() R:HistoryComplete() end)
        optional(context,"LOOT_ROLLS_COMPLETE",function() R:HistoryComplete() end)
        optional(context,"LOOT_HISTORY_UPDATE_DROP",function(_,encounter,list) R:HistoryDrop(encounter,list) end)
    end
    optional(context,"GET_ITEM_INFO_RECEIVED",infoReceived)
    L.RollFrame:Enable(context)
    L.Monitor:Enable(context)
    L.Results:Enable(context)
    L.Master:Enable(context)
    context:Defer(function() L.Sim:Stop();R:Reset() end)
    if L.Call("IsInGroup") then R:Rediscover() end
end})

-- Settings page --------------------------------------------------------------------
local QUALITY={}
for q=0,5 do QUALITY[#QUALITY+1]={value=q,label=_G["ITEM_QUALITY"..q.."_DESC"] or ({"Poor","Common","Uncommon","Rare","Epic","Legendary"})[q+1]} end
local GROW={{value="UP",label="Upwards"},{value="DOWN",label="Downwards"}}
local MODES={{value="toast",label="Fade out (toast)"},{value="sticky",label="Stay until closed"}}
local page
local function build(parent)
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    local function cfg() return L:Config() end
    local function set(key) return function(value) cfg()[key]=value;L:Changed() end end
    local function row(key,title,control,help,opts)
        opts=opts or {};opts.help=opts.help or help
        controls[key]=g:Row(title,control,opts)
        return controls[key]
    end
    local function switch(key,title,help) return row(key,title,UI:Switch(g,false,set(key)),help) end
    local function slider(key,title,low,high,step,format,help) return row(key,title,UI:InlineSlider(g,190,low,high,step,format,set(key)),help) end
    local function dropdown(key,title,options,help) return row(key,title,UI:Dropdown(g,190,options,set(key)),help) end
    g:Section("module","Module")
    page.enabled=g:Row("Enabled",UI:Switch(g,false,function(value)
        ns.Modules:SetEnabled(L.ID,value);ns.Layout:Refresh(true);if ns.Config then ns.Config:Refresh() end
    end),{help="Roll bars, loot monitor, results and the master loot window."})
    g:Row("Position & size",UI:Button(g,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:lootrolls") end),
        {help="Loot Rolls, Loot Monitor and Loot Results are movable elements. The width sets the bar or toast width."})
    g:Row("Simulation",UI:Button(g,"Test rolls",170,function() L.Sim:Run("roll") end),{help="Three fake group loot rolls with fake players. Nothing is sent."})
    g:Row("",UI:Button(g,"Test loot monitor",170,function() L.Sim:Run("monitor") end),{help="Fake loot for you and the group."})
    g:Row("",UI:Button(g,"Test roll request",170,function() L.Sim:Run("request") end),{help="A fake master looter asks you and others to roll."})
    g:Row("",UI:Button(g,"Test master loot",170,function() L.Sim:Run("master") end),{help="Master loot window with fake loot and a fake raid. Awards are only printed."})
    g:Section("rolls","Roll bars")
    switch("rolls","Show roll bars","Group loot rolls and roll requests as bars.")
    switch("hideBlizzard","Hide Blizzard roll frames","Takes effect when the module starts (reload or off/on).")
    switch("rollInfo","Item kind and stats","Item kind and primary stats to the left of the bar.")
    switch("rollKeep","Keep bar after choosing","Otherwise the bar closes once you chose; results follow.")
    switch("rollQualityBar","Bar in item quality color","Timer bar in the item's quality color; off uses the bar color below.")
    row("rollBarColor","Bar color",UI:ColorInput(g,150,set("rollBarColor")),"Used when the quality color is off.",{width=150})
    slider("rollHeight","Bar height",20,48,1,"%d px","Height of a roll bar including the item name; the icon and buttons scale with it.")
    slider("rollSpacing","Spacing",0,24,1,"%d px","Gap between roll bars.")
    slider("rollMax","Bars at most",1,12,1,"%d","More open rolls wait until a bar is free.")
    dropdown("rollGrow","More bars",GROW,"Direction in which further bars stack from the first one.")
    g:Section("monitor","Loot monitor")
    switch("monitor","Show loot monitor","Looted items as toasts that fade out.")
    switch("monitorSelf","Own loot","Toasts for items and money you receive.")
    dropdown("monitorSelfQuality","Own loot from",QUALITY,"Lowest item quality shown for your own loot.")
    switch("monitorGroup","Group and raid loot","Toasts for items other group or raid members receive.")
    dropdown("monitorGroupQuality","Group loot from",QUALITY,"Lowest item quality shown for other players' loot.")
    switch("monitorMoney","Money","Toast for money you loot (with own loot on).")
    slider("monitorDuration","Show for",2,30,1,"%d s","How long a toast stays before it fades out.")
    slider("monitorMax","Toasts at most",1,15,1,"%d","The oldest toast makes room when this many are shown.")
    dropdown("monitorGrow","New toasts push",GROW,"Newest toast sits at the anchor; older ones move this way.")
    g:Section("results","Roll results")
    switch("results","Show results","A ranked card per finished roll (native and requested rolls).")
    dropdown("resultsMode","Results",MODES,"Fade out after the time below, or stay until closed with X.")
    slider("resultsDuration","Show for",3,120,1,"%d s","Toast mode only. Hovering keeps a card.")
    slider("resultsMax","Cards at most",1,10,1,"%d","The oldest card makes room when this many are shown. /bv loot last shows older ones.")
    slider("resultsRows","Players per card",1,10,1,"%d","Ranked players listed on a card; the rest is counted as \"+n more\".")
    dropdown("resultsGrow","More cards",GROW,"Direction in which further cards stack from the newest one.")
    g:Section("master","Master loot")
    switch("master","Master loot window","Opens with the loot when you are master looter.")
    switch("masterAutoOpen","Open automatically","Opens the master loot window when you loot as master looter and something is above the loot threshold.")
    dropdown("masterOptions","Roll options",L.PRESET_CHOICES,"Options offered with a roll request; their order is the priority in the result.")
    slider("masterRollTime","Roll time",10,120,5,"%d s","How long players have to answer a roll request.")
    switch("masterAnnounce","Announce awards","Posts item and player to the raid or party chat.")
    switch("acceptRequests","Accept roll requests","Show roll bars when a master looter in your group asks you to roll.")
    g:Row("Window",UI:Button(g,"Open master loot",170,function() L.Master:Open() end),{help="Opens the master loot window (also /bv loot master)."})
    function page:Arrange(width)
        UI:Place(g,self,0,0)
        local height=g:Arrange(width)+8
        D.Height(self,height);return height
    end
    function page:Refresh()
        local c=L:Config()
        self.enabled:SetValue(ns.Settings:Module(L.ID).enabled==true)
        for key,control in pairs(controls) do if control.SetValue then control:SetValue(c[key]) end end
    end
    page:Arrange(880);page:Refresh()
    return page
end
ns.Config:RegisterPage("loot",{title="Loot",description="Roll bars, loot monitor, roll results and master loot with roll requests.",
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})

-- Commands -------------------------------------------------------------------------
local HELP="/bv loot [on|off] | /bv loot master | /bv loot request <item link> | /bv loot test [roll|monitor|request|master|all|stop] | /bv loot last [n] | /bv loot status | /bv loot debug"
ns.Commands:RegisterAction("loot",function(action)
    local command,rest=(action or ""):match("^(%S*)%s*(.-)$")
    if command=="" then ns.Config:OpenPage("loot")
    elseif command=="on" or command=="off" then
        ns.Modules:SetEnabled(L.ID,command=="on");ns.Layout:Refresh(true)
        ns:Print("loot: "..ns.Modules.records[L.ID].state);ns.Config:Refresh()
    elseif command=="master" or command=="ml" then L.Master:ToggleWindow()
    elseif command=="test" or command=="sim" then L.Sim:Run(rest)
    elseif command=="request" then
        local item=rest:match("(item:[%-%d:]+)")
        if not L:Active() or not item then L:Print("Usage: /bv loot request <item link> (module on).");return end
        local m=L.Master
        m.selected=m:AddItem(item,nil)
        m:Open()
    elseif command=="last" or command=="history" then
        if not L:Active() then L:Print("Turn the loot module on first (/bv loot on).");return end
        local shown=L.Results:ShowHistory(tonumber(rest) or 10)
        if shown==0 then L:Print("No roll results yet.") end
    elseif command=="debug" then
        L.debug=not L.debug;L:Print("Debug output "..(L.debug and "on (tooltips report what the client returned)." or "off."))
    elseif command=="status" then
        local parts={}
        for source,count in pairs(R.sources) do parts[#parts+1]=source.."="..count end
        L:Print(string.format("module %s · master looter %s · C_LootHistory %s · choices by source: %s",
            ns.Modules.records[L.ID].state,tostring(L.IsMasterLooter()),C_LootHistory and (C_LootHistory.GetSortedInfoForDrop and "modern" or C_LootHistory.GetPlayerInfo and "classic" or "partial") or "none",
            #parts>0 and table.concat(parts,", ") or "none yet"))
    else L:Print(HELP) end
end)
if ns.ready and IsLoggedIn() then ns.Modules:Reconcile() end

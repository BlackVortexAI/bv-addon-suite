local _,G=...
if not G.ready then return end
-- Settings page and /bv gather.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics

function G:Changed()
    -- Settings changed what shows: the next profession or tracking check compares anew.
    if self.Visibility then self.Visibility.state=nil end
    if self.Hud then self.Hud:Apply() end
    if self.Sight then self.Sight:Update() end
    if self.Scanner then self.Scanner:Update() end
    if self.Hud.ScanStatus then self.Hud:ScanStatus() end
    if self.Finds then self.Finds:Refresh() end
    if self.Pins.registered and ns.MapPins and ns.MapPins.providers["gather:minimap"] then
        ns.MapPins.providers["gather:minimap"].edge=self:Config().minimapEdge
    end
    self.Pins:Refresh()
end
local page
local function build(parent)
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    page.controls=controls
    local function cfg() return G:Config() end
    local function set(key) return function(value) cfg()[key]=value;G:Changed();if page then page:Refresh() end end end
    local function row(key,title,control,help) controls[key]=g:Row(title,control,{help=help});return controls[key] end
    local function switch(key,title,help) return row(key,title,UI:Switch(g,false,set(key)),help) end
    local function slider(key,title,low,high,step,format,help) return row(key,title,UI:InlineSlider(g,190,low,high,step,format,set(key)),help) end
    g:Section("module","Module")
    page.enabled=g:Row("Enabled",UI:Switch(g,false,function(value) ns.Modules:SetEnabled(G.ID,value);if ns.Config then ns.Config:Refresh() end end),
        {help="Herbs, ore, fishing pools and treasure you gather, on the world map and the minimap."})
    g:Row("Wiki",UI:Button(g,"Open the Gather wiki",190,function() G.Wiki:Open() end),
        {help="Every part and setting of Gather explained, each with an example. Also /bv gather wiki."})
    page.summary=g:Row("Known nodes",UI:Label(g,"",11,"muted"),{width=420,help="Per kind: all nodes, and those only shared with you so far."})
    page.other=g:Row("GatherMate2",UI:Label(g,"",11,"muted"),{width=420,help="With GatherMate2 running, ours neither records nor draws (no double pins), unless you say otherwise below."})
    switch("forceRecord","Record anyway","Record nodes although GatherMate2 records them too.")
    switch("forceShow","Show anyway","Draw our nodes although GatherMate2 draws its own.")
    g:Section("sources","Sources")
    -- The sources as a list: used or not, name, nodes (Florian 2026-10-09).
    page.sourceList=G.SourceList:Build(g,function() G:Changed();if page then page:Refresh() end end)
    g:Block(page.sourceList,(#G.SourceList.ROWS+1)*G.SourceList.ROW,function(width) return page.sourceList:Resize(width) end)
    switch("routeKnown","Known spawns in routes","Routes also visit known spawn points you have not found yourself.")
    controls.forgetGathermate=g:Row("GatherMate2 import",UI:Button(g,"Remove import",190,function() G.Data:ForgetSource("gathermate");G:Changed();if page then page:Refresh() end end),
        {help="Removes everything imported from GatherMate2 (your own finds stay). Only with an import."})
    g:Section("show","Show")
    switch("world","World map","Nodes on the world map (zone maps).")
    switch("minimap","Minimap","Nodes around you on the minimap.")
    switch("minimapEdge","Far nodes at the edge","Nodes beyond the minimap's range stay at its edge, smaller.")
    -- Per kind: the switch (manual override: off is always off) and when it
    -- shows (Florian 2026-10-09).
    for _,t in ipairs(G.TYPES) do
        switch(t.id,t.label,"Show "..t.label:lower()..". Off always hides them, whatever is chosen below.")
        local tracking={herb="Find Herbs",ore="Find Minerals",treasure="Find Treasure"}
        local help="Always; only when you have the profession; or only while "..(tracking[t.id] or "its tracking").." is on."
        if t.id=="fish" then help="Always, or only when you know Fishing." elseif t.id=="treasure" then help="Always, or only while Find Treasure is on." end
        row(t.id.."When",t.label..": show",UI:Dropdown(g,190,G.Visibility.Options(t.id),set(t.id.."When")),help)
    end
    g:Section("colours","Colours")
    for _,t in ipairs(G.TYPES) do
        local key=t.id.."Color"
        row(key,t.label,UI:ColorInput(g,190,function(hex) cfg()[key]=hex:sub(1,6):upper();G:Changed();if page then page:Refresh() end end),"Pin colour for "..t.label:lower()..".")
    end
    g:Row("Reset",UI:Button(g,"Reset colours",190,function() for _,t in ipairs(G.TYPES) do cfg()[t.id.."Color"]="" end;G:Changed();if page then page:Refresh() end end),
        {help="Each kind back to its own colour."})
    row("filter","Only these",UI:Input(g,190,function(text) cfg().filter=text;G:Changed() end),
        "Names separated by commas, for example Peacebloom, Silverleaf. Empty shows all.")
    slider("size","Pin size",8,30,1,"%d","Size of the node pins.")
    slider("respawnMinutes","Gathered: grey for",0,60,1,"%d min","A node you gathered shows grey this long, until it has likely grown back. 0: never.")
    g:Section("record","Recording")
    switch("record","Record what you gather","Herbs, ore and treasure are stored where you gathered them.")
    slider("merge","Merge distance",3,60,1,"%d yd","The same plant found again closer than this counts up instead of adding a pin; its position moves to the middle of your finds.")
    slider("spawn","Spawn distance",0,30,1,"%d yd","Different plants closer than this are one spawn point (they rotate there). 0 keeps them apart.")
    g:Row("Duplicates",UI:Button(g,"Merge duplicates",190,function()
        local removed=G.Data:Cleanup();G:Print(removed.." duplicate"..(removed==1 and "" or "s").." merged.");G:Changed();if page then page:Refresh() end
    end),{help="Merges nodes of one spawn point that your database holds twice (also runs after every import)."})
    g:Section("mode","Gather mode")
    g:Row("Gather mode",UI:Button(g,"Open the gather window",190,function() G.Mode:Show(true) end),
        {help="A small window: the gather mode switch, a route to follow, the node kinds. Also /bv gather window; /bv gather mode switches the mode."})
    g:Section("hud","HUD")
    page.hudOther=g:Row("Other addons",UI:Label(g,"",11,"muted"),{width=420,help="Another HUD addon handling the minimap; use one of them at a time."})
    g:Row("HUD",UI:Button(g,"Show or hide the HUD",190,function() G.Hud:Toggle() end),
        {help="The real minimap large and see-through in the middle of the screen (Find Herbs dots included). Also /bv gather hud."})
    slider("hudSize","HUD size",40,100,5,"%d %%","Size of the HUD as a share of the screen height.")
    slider("hudAlpha","HUD map opacity",10,100,5,"%d %%","How visible the map of the HUD is (with Blizzard's tracking dots). Route, pins and the sight circle keep their own opacity.")
    row("hudTurn","HUD turning",UI:Dropdown(g,190,{{value="turn",label="Turns with you"},{value="north",label="North up"},{value="keep",label="Like your minimap"}},set("hudTurn")),
        "Whether the HUD turns as you turn or keeps north up; your normal minimap setting comes back after.")
    switch("hudCompass","Compass at the edge","N, E, S and W at the HUD's edge, turning with it, so you see where you are heading.")
    row("hudShape","Minimap shape after",UI:Dropdown(g,190,{{value="keep",label="Leave as it is"},{value="square",label="Square"},{value="round",label="Round"}},set("hudShape")),
        "Turning the minimap can reset its shape; if your minimap is square and comes back round after the HUD, choose Square.")
    g:Section("sight","Sight circle")
    switch("sightCircle","Sight circle on the minimap","A see-through ring of the sight radius (Routes tab) around you on the minimap, while the gather mode is on.")
    row("sightColor","Colour",UI:ColorInput(g,190,function(hex) cfg().sightColor=hex:sub(1,6):upper();G:Changed();if page then page:Refresh() end end),"Colour of the ring; empty: the style's accent.")
    slider("sightAlpha","Opacity",5,100,5,"%d %%","How visible the ring is; its inside stays much fainter.")
    slider("sightWidth","Thickness",1,16,1,"%d px","How thick the ring is drawn.")
    g:Row("Reset",UI:Button(g,"Accent colour",190,function() cfg().sightColor="";G:Changed();if page then page:Refresh() end end),{help="The ring back in the style's accent."})
    g:Section("tracker","Tracker")
    g:Row("Tracker",UI:Button(g,"Open the tracker",190,function() G.TrackerWindow:Show(true) end),
        {help="What a session brings: nodes, items, value and gold per hour; start, pause and stop. Also /bv gather tracker."})
    row("priceSource","Prices",UI:Dropdown(g,190,{{value="auto",label="Auto (TSM, Auctionator, vendor)"},{value="tsm",label="TradeSkillMaster"},{value="auctionator",label="Auctionator"},{value="vendor",label="Vendor price"}},set("priceSource")),
        "Where the value of gathered items comes from.")
    switch("trackAllLoot","Count all loot","Every item you loot while a session runs, not only from gathering.")
    slider("trackerIdle","Pause when idle",0,30,1,"%d min","A running session pauses after this long without gathering (counted up to your last node); the next node resumes it. 0: never.")
    g:Section("route","Route")
    g:Row("Route editor",UI:Button(g,"Open route editor",190,function() G.Editor:Toggle() end),
        {help="Its own map: choose zones and herbs or ores, paint no-go, preferred and high-risk areas, calculate a loop, save it and follow it as waypoints. Also /bv gather editor."})
    g:Row("Quick route",UI:Button(g,"Route through this zone",190,function() G.Route:Start() end),
        {help="Through the nodes of your zone that the filters show, shortest way first; it becomes your waypoint path (needs the Map module). Also /bv gather route."})
    row("enemy","Enemy bases",UI:Dropdown(g,190,{{value="avoid",label="Avoid"},{value="block",label="Never through"},{value="ignore",label="Ignore"}},set("enemy")),
        "Towns of the other faction (around their flight masters) and their capitals: routes go round them.")
    switch("ownFlights","Own flight masters only","The route editor shows flight masters of your faction and neutral ones.")
    slider("sightRadius","Sight radius",40,230,5,"%d yd","How far the minimap's Find Herbs and Find Minerals dots reach for routes \"within sight\" (the minimap shows about 230 yards zoomed out, 150 indoors).")
    switch("routeTerrain","Use the terrain","Routes go round steep slopes and through passes (needs the terrain data).")
    row("cliffs","Down cliffs",UI:Dropdown(g,190,{{value="never",label="Never"},{value="safe",label="Short drops"},{value="always",label="Always (Slow Fall)"}},set("cliffs")),
        "Routes may drop down steep faces (never up them): short drops only, or any height with Slow Fall or Levitate.")
    switch("preferRoads","Prefer roads","Roads of the game's own terrain (from the terrain data) count as preferred ground: routes follow them where it is not much longer.")
    switch("recordWays","Record walked ways","Where you walk is counted in a map of 8-yard cells (on foot and mounted, not flying or in instances); the route editor can show it.")
    switch("preferWalked","Prefer walked ways","Cells walked three times or more count as preferred ground, like roads.")
    g:Row("Walked ways",UI:Button(g,"Forget walked ways",190,function() G.Trace:Forget();G:Print("Walked ways forgotten.") end),
        {help="Clears the recorded walked ways."})
    switch("routeSmooth","Smooth curves","The ways round obstacles as curves instead of straight pieces.")
    switch("avoidWater","Avoid water","Routes go round water you would have to swim through; off: they swim straight across.")
    slider("routeLineAlpha","Route line opacity",10,100,5,"%d %%","How visible the lines of the route you follow are, on the map and the minimap.")
    slider("routeDotAlpha","Route point opacity",10,100,5,"%d %%","How visible the small points of the route you follow are.")
    row("routeColor","Route colour",UI:ColorInput(g,190,function(hex) cfg().routeColor=hex:sub(1,6):upper();G:Changed();if page then page:Refresh() end end),"Lines and points of the route; empty: the style's accent.")
    row("routeNextColor","Next point colour",UI:ColorInput(g,190,function(hex) cfg().routeNextColor=hex:sub(1,6):upper();G:Changed();if page then page:Refresh() end end),"The next point and the line from you to it.")
    g:Row("Expert settings",UI:Button(g,"Open expert settings...",190,function() G.Expert:Open() end),
        {help="The fixed values behind route planning and following (levels, jumps, costs of slopes, water and roads, when a point counts as reached), for fine tuning. Most players never need them."})
    slider("worthLimit","Way per node",0,600,10,"%d yd","Worth the way: nodes that cost more way than this each are left out of new routes (a far group with few nodes). 0: every node. Also in the route editor.")
    slider("followRange","Joining range",100,1500,50,"%d yd","While you follow a route, only its legs this close to you are checked for joining or skipping; the rest of the route costs nothing.")
    g:Row("Following",UI:Button(g,"Stop following",190,function() G.Follow:Stop() end),{help="Ends the route you follow. Also /bv gather stop."})
    switch("routeUnderground","Underground nodes in routes","Nodes in caves and mines join routes too (the route does not know the entrance yet).")
    g:Section("share","Sharing")
    row("shareSend","Send your new nodes",UI:Dropdown(g,190,{},set("shareSend")),"Nodes you find go to your group, your guild or both, one small message each. Off by default.")
    controls.shareSend:SetOptions({{value="off",label="Off"},{value="group",label="Group"},{value="guild",label="Guild"},{value="both",label="Group and guild"}})
    switch("shareReceive","Receive nodes","Nodes your group and guild send show as shared until you find them yourself; Forget shared nodes removes them.")
    g:Section("exchange","Import and export")
    g:Row("GatherMate2",UI:Button(g,"Import from GatherMate2",190,function() G.Exchange:GatherMate() end),
        {help="Reads GatherMate2's database while it is loaded, shows what is new, and adds it after you confirm."})
    g:Row("Export",UI:Button(g,"Export nodes",190,function() G.Exchange:Open("export") end),{help="All your nodes as text to share."})
    g:Row("Import",UI:Button(g,"Import nodes",190,function() G.Exchange:Open("import") end),{help="Nodes someone shared as text; marked as shared until you find them yourself."})
    g:Row("Forget",UI:Button(g,"Forget shared nodes",190,function() G.Exchange:ForgetShared() end),{help="Removes the nodes you only got from others and never found yourself."})
    -- Minimap scanner (Florian 2026-10-10): warnings for the herbs and ores
    -- of a list when they show on the HUD's minimap.
    g:Section("scanner","Minimap scanner")
    page.scanInfo=g:Row("How it works",UI:Label(g,"",11,"muted"),{width=420,
        help="While the HUD is open and the mouse rests on its minimap, the scanner reads the names of the dots every 2 seconds. Find Herbs or Find Minerals must be on; never in combat."})
    switch("scanner","Scanner","Warns when a herb or ore of the list below shows on the minimap. Also by clicking the status text in the HUD.")
    switch("scanStage","On-screen message","A short message in the upper middle of the screen (the notification stage) besides the sound.")
    controls.scanSoundButton=g:Row("Default sound",UI:Button(g,"",190,function()
        G.WatchList:Choose(page,cfg().scanSound,function(sound) cfg().scanSound=sound;G:Changed();if page then page:Refresh() end;G.Scanner:Play({}) end)
    end),{help="The sound of every entry set to Default sound. Choose one with a preview."})
    local channels={}
    for _,name in ipairs(G.Scanner.CHANNELS) do channels[#channels+1]={value=name,label=name} end
    row("scanChannel","Sound channel",UI:Dropdown(g,190,channels,set("scanChannel")),"Master plays even when the game's sound effects are low or off.")
    g:Row("Test",UI:Button(g,"Play the default sound",190,function() G.Scanner:Play({}) end),{help="Plays the default sound on the chosen channel."})
    slider("scanRepeat","Warn again after",1,60,1,"%d min","A node warns once. Gone from the minimap this long (or gathered), it warns again when it shows: it grew back or you came back.")
    g:Row("Finds",UI:Button(g,"Open minimap finds",190,function() G.Finds:Show(true) end),
        {help="A window with the last 20 herbs and ores the scanner saw, newest first; also in the gather mode window."})
    g:Section("watch","Warn for")
    local function listChanged()
        G:Changed()
        if page then page:Refresh();page:Arrange(page.width or 880) end
        if ns.Config.window then ns.Config:Layout() end
    end
    page.watchList=G.WatchList:Build(g,listChanged)
    g:Block(page.watchList,60,function(width) return page.watchList:Resize(width) end)
    -- Tabs in the settings window header (Florian 2026-10-09: one long page
    -- was too much): which sections each one shows.
    local TABS={
        {id="general",label="General",sections={"module","sources","show","colours"}},
        {id="mode",label="Gather mode",sections={"mode","hud","sight","tracker"}},
        {id="routes",label="Routes",sections={"route"}},
        {id="record",label="Recording & sharing",sections={"record","share","exchange"}},
        {id="scanner",label="Scanner",sections={"scanner","watch"}},
    }
    local definitions={}
    for i,tab in ipairs(TABS) do definitions[i]={id=tab.id,label=tab.label,sections=tab.sections} end
    local function select(id)
        for _,tab in ipairs(TABS) do
            if tab.id==id then
                local shown={}
                for _,section in ipairs(tab.sections) do shown[section]=true end
                g:ShowSections(shown)
            end
        end
        page.navigation.selected=id
        page:Arrange(page.width or 880)
        if ns.Config.window then ns.Config:Layout() end
    end
    page.navigation={definitions=definitions,selected="general",select=select}
    function page:Arrange(width)
        self.width=width
        UI:Place(g,self,0,0)
        local height=g:Arrange(width)+8
        M.Height(self,height);return height
    end
    function page:Refresh()
        local c=G:Config()
        self.enabled:SetValue(ns.Settings:Module(G.ID).enabled==true)
        for key,control in pairs(controls) do
            if key=="routeColor" then control:SetValue((c.routeColor~="" and c.routeColor or G.Hex({G:Style():Color("accent")})).."FF")
            elseif key=="routeNextColor" then control:SetValue(c.routeNextColor.."FF")
            elseif key=="sightColor" then control:SetValue((c.sightColor~="" and c.sightColor or G.Hex({G:Style():Color("accent")})).."FF")
            elseif key:match("Color$") then control:SetValue(G.Hex(G:Color(key:gsub("Color$",""))).."FF")
            elseif key=="forgetGathermate" then
            elseif key=="scanSoundButton" then control:SetText(G.WatchList.SoundLabel(c.scanSound))
            elseif control.SetValue then control:SetValue(c[key])
            elseif control.SetText and key=="filter" then control:SetText(c.filter) end
        end
        local parts={}
        for _,t in ipairs(G.TYPES) do
            local own=G.Data:SourceCount("own",t.id)
            if own>0 then parts[#parts+1]=t.label.." "..own end
        end
        if self.summary.SetText then self.summary:SetText(#parts>0 and table.concat(parts,"  ·  ").." (own finds)" or "None of your own yet.") end
        self.sourceList:Refresh()
        self.watchList:Refresh()
        if self.scanInfo.SetText then
            local hints={}
            for _,kind in ipairs({"herb","ore"}) do local hint=G.Scanner:Hint(kind);if hint then hints[#hints+1]=hint end end
            local available=G.Scanner:Available()
            self.scanInfo:SetText(not available and "This client cannot read the minimap's dots." or
                ("Works in the HUD while the mouse rests on its minimap."..(#hints==2 and " Find Herbs and Find Minerals are both off now." or "")))
        end
        g:SetRowEnabled(controls.forgetGathermate,G.Data:SourceCount("gathermate")>0)
        local other=G.Hud:Other()
        if self.hudOther.SetText then self.hudOther:SetText(other and (other.." is loaded: use only one HUD at a time.") or "None.") end
        local gm=G:GatherMate()
        if self.other.SetText then self.other:SetText(gm and "Running: ours waits unless you turn on the switches below." or "Not running: ours records and draws.") end
        g:SetRowEnabled(controls.forceRecord,gm);g:SetRowEnabled(controls.forceShow,gm)
    end
    select("general");page:Refresh()
    return page
end
-- The Scanner tab (from the gather mode window).
function G:OpenScanner()
    ns.Config:OpenPage("gather")
    if page and page.navigation then page.navigation.select("scanner") end
end
ns.Config:RegisterPage("gather",{title="Gather",description="Herbs, ore, fishing pools and treasure on your maps; GatherMate2 import.",
    category="questmap",module=G.ID,
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})
-- Key bindings (Bindings.xml; Florian 2026-10-09): in the game's key
-- bindings under the category "BV Addon Suite" (a header attribute showed
-- as "HEADER_BVGATHER" on this client), named after the module.
_G.BINDING_NAME_BVGATHER_MODE="Gather: mode on or off"
_G.BINDING_NAME_BVGATHER_HUD="Gather: show or hide the HUD"
_G.BINDING_NAME_BVGATHER_WINDOW="Gather: window"
_G.BINDING_NAME_BVGATHER_TRACKER="Gather: tracker"
_G.BINDING_NAME_BVGATHER_EDITOR="Gather: route editor"
ns.Commands:RegisterAction("gather",function(action)
    if action=="stop" then G.Follow:Stop();return end
    if action=="mode" then if G:Active() then G.Mode:Toggle();G:Print("Gather mode "..(G:Config().mode and "on" or "off")..".") end;return end
    if action=="tracker" then if G:Active() then G.TrackerWindow:Show() end;return end
    if action=="hud" then if G:Active() then G.Hud:Toggle() end;return end
    if action=="window" then if G:Active() then G.Mode:Show() end;return end
    if action=="profile" then G.Editor:Profile();return end
    if action=="wiki" then G.Wiki:Open();return end
    if action=="editor" then if G:Active() then G.Editor:Toggle() else G:Print("The Gather module is off (/bv gather on).") end;return end
    if action=="route" then if G:Active() then G.Route:Start() else G:Print("The Gather module is off (/bv gather on).") end;return end
    if action=="on" or action=="off" then
        ns.Modules:SetEnabled(G.ID,action=="on");G:Print(ns.Modules.records[G.ID].state);if ns.Config then ns.Config:Refresh() end
    else ns.Config:OpenPage("gather") end
end)

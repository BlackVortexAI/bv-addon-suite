local _,P=...
if not P.ready then return end
-- Settings page, /bv map and /bv way.
local ns=P.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics

local DECIMALS={{value=0,label="45, 67"},{value=1,label="45.2, 67.8"},{value=2,label="45.23, 67.81"}}
local SCOPES={{value="all",label="Everything"},{value="map",label="Map only (quest log stays)"},{value="panes",label="Quest log only"}}

-- Applies every part after a change.
function P:Changed()
    if not self:Active() then return end
    self.Coords:Update();self.Fade:Apply(true);self.Window:Apply();self.Arrow:Update();self.Search:Apply()
    if self.Reveal then self.Reveal:Apply() end
    if self.Terrain then self.Terrain:Apply() end
    if self.Flights then self.Flights:Filter() end
    if self.Zoom then self.Zoom:Apply() end
    if self.Path then self.Path:Refresh() end
end
local page
local function build(parent)
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    page.controls=controls
    local function cfg() return P:Config() end
    local function set(key) return function(value) cfg()[key]=value;P:Changed();if page and page.Refresh and key:match("^force") then page:Refresh() end end end
    local function row(key,title,control,help) controls[key]=g:Row(title,control,{help=help});return controls[key] end
    local function switch(key,title,help) return row(key,title,UI:Switch(g,false,set(key)),help) end
    local function dropdown(key,title,options,help) local control=row(key,title,UI:Dropdown(g,190,{},set(key)),help);control:SetOptions(options);return control end
    local function slider(key,title,low,high,step,format,help) return row(key,title,UI:InlineSlider(g,190,low,high,step,format,set(key)),help) end
    g:Section("module","Module")
    page.enabled=g:Row("Enabled",UI:Switch(g,false,function(value) ns.Modules:SetEnabled(P.ID,value);if ns.Config then ns.Config:Refresh() end end),
        {help="Coordinates, transparency while moving, map size and waypoints. Blizzard's map stays; other map addons keep working."})
    row("styleFamily","Style family",UI:Dropdown(g,190,ns.Styles:Choices(true),function(value) cfg().styleFamily=value;ns.Styles:Changed();P:Changed() end),
        "The suite's in-game style or an own one for the coordinate strip.")
    controls.styleFamily:SetOptionsProvider(function() return ns.Styles:Choices(true) end)
    g:Section("coords","Coordinates")
    page.coordsOwner=g:Row("Other addons",UI:Label(g,"",11,"muted"),{width=420,help="When another addon already shows map coordinates, ours stays off and its settings are greyed out."})
    switch("forceCoords","Use ours anyway","Our coordinates although another addon shows them too; switch the other addon's coordinates off so only one text shows.")
    switch("coords","Show coordinates","A slim strip at the bottom of the map.")
    switch("coordsPlayer","Player","Your position on the map shown.")
    switch("coordsCursor","Cursor","The position under the mouse while it is over the map.")
    dropdown("coordsDecimals","Precision",DECIMALS,"Decimal places.")
    g:Section("fade","Transparency while moving")
    page.blizzardFade=g:Row("Blizzard's map fade",UI:Label(g,"",11,"muted"),{width=420,help="Blizzard's own map fade (game options) wins while it is on; ours waits so the two never fight."})
    switch("fade","Fade while moving","The open map fades while you walk and comes back when you stop.")
    slider("fadeOpacity","Opacity",10,100,5,"%d %%","How visible the map stays while you move.")
    dropdown("fadeScope","Fades",SCOPES,"Everything, the map without the quest log beside it, or only the quest log.")
    switch("fadeMouseover","Full on mouseover","Pointing at the map shows it fully, also while moving.")
    slider("fadeTime","Fade time",1,10,1,"%d","Tenths of a second for the fade (3 = 0.3 s).")
    g:Section("window","Map window")
    page.windowOwner=g:Row("Other addons",UI:Label(g,"",11,"muted"),{width=420,help="When another addon already moves or scales the map, that part stays with it and our settings for it are greyed out."})
    switch("forceMove","Move: use ours anyway","Our moving although another addon moves the map; switch the other addon's option off so the two never fight.")
    switch("forceScale","Scale: use ours anyway","Our scale although another addon scales the map; switch the other addon's option off so the two never fight.")
    switch("rememberZoom","Remember zoom","The map reopens on the same map, zoom and section while you are in the same zone.")
    dropdown("extraZoom","Extra zoom",{{value="off",label="Off"},{value="x2",label="2x closer"},{value="x4",label="4x closer"}},
        "Zoom in closer than Blizzard allows, on Blizzard's map and the terrain map. The map art only grows, so it gets softer: 2x is fine, 4x clearly blurred.")
    slider("scale","Scale",50,150,5,"%d %%","Size of the map in its window; maximized it stays Blizzard's. Also Ctrl+mouse wheel on the title bar.")
    switch("movable","Movable","Drag the map's title bar to move it; double-click resets the position.")
    page.resetPosition=g:Row("Position",UI:Button(g,"Reset position",170,function() P.Window:Reset() end),{help="Back to Blizzard's place."})
    g:Section("content","Map content")
    row("mapStyle","Map style",UI:Dropdown(g,190,{{value="blizzard",label="Blizzard's map"},{value="terrain",label="Terrain"}},set("mapStyle")),
        "Zone maps as Blizzard's art or as terrain (the game's own minimap tiles) with our area names. Also the layers button beside the map's search.")
    slider("terrainAlpha","Terrain opacity",20,100,5,"%d %%","How much of the terrain map covers Blizzard's map: below 100 % Blizzard's map shows through, below 70 % with its own area names instead of ours.")
    switch("ownFlights","Own flight masters only","Flight masters of the other faction are hidden on the world map and in the search; neutral ones stay.")
    switch("learnFlights","Learn flight times","Your own flights are timed; the flight master's map then shows the time to each destination you have flown to.")
    switch("unexplored","Show unexplored areas","Areas you have not discovered yet show on the world map as if explored.")
    switch("forceReveal","Unexplored: use ours anyway","Ours although another addon reveals the map; switch the other addon's option off so the two never double up.")
    switch("search","Search","A magnifier at the map's top left: zones, points of interest, flight points and your quests. Right-click a result for a waypoint.")
    -- Zone banner: the notification types "Zone" and "Subzone" switch it on and off.
    g:Section("zone","Zone banner")
    switch("zoneQuests","Quests in the zone","The zone banner counts your quests there and the ready ones (with the Quest module on).")
    switch("zoneDiscovered","Discovered","A new area shows \"Discovered\" and the exploration XP; Blizzard's line is left out.")
    g:Row("Notifications",UI:Button(g,"Open notifications",170,function() ns.Config:OpenPage("stage") end),
        {help="Zone and Subzone appear on the notification stage: switch them, set how long they stay and test them there."})
    g:Section("waypoints","Waypoints")
    page.waySource=g:Row("Waypoints go to",UI:Label(g,"",11,"muted"),{width=420,help="TomTom when it is loaded; otherwise Blizzard's own waypoint."})
    switch("arrow","Arrow","An arrow with distance and arrival time to the active waypoint (not with TomTom, whose arrow stays). Place it in the Layout Editor.")
    slider("arrival","Arrival distance",3,50,1,"%d yd","Closer than this counts as arrived; the next queued waypoint follows.")
    switch("corpse","Corpse waypoint","While you run as a ghost, a waypoint to your body (not with TomTom, which brings its own).")
    g:Row("Waypoints",UI:Button(g,"Waypoint list",170,function() P.WaypointList:Toggle() end),
        {help="Rename, reorder, sets, import of /way lines (Wowhead lists) and export. /way x y [title], /way Badlands 45 67, /way here, /way next, /way list, /way clear. Also /bv way."})
    g:Row("Arrow position",UI:Button(g,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:maparrow") end),{help="The arrow is a movable element."})
    g:Section("path","Travel path")
    switch("pathPins","Path on the map","Every queued waypoint as a numbered pin on the world map and the minimap, with lines between them. On a pin: left-click makes it next, right-click removes it, drag moves it.")
    switch("pathLead","Line to the next target","A line from you to the next waypoint in its colour, with arrows; the path's lines show the way with arrows too.")
    slider("pathPinAlpha","Path pin opacity",10,100,5,"%d %%","How visible the waypoint pins of the path are.")
    slider("pathLineAlpha","Path line opacity",10,100,5,"%d %%","How visible the lines of the path are.")
    switch("altClick","Alt+click adds","Alt+click on the world map appends a waypoint there: build your own travel path.")
    local function color(key,title,help)
        return row(key,title,UI:ColorInput(g,190,function(hex) cfg()[key]=hex:sub(1,6):upper();P:Changed();if page then page:Refresh() end end),help)
    end
    color("pathColor","Path colour","Pins and lines of the path. Reset colours goes back to your style's accent.")
    color("nextColor","Next target colour","The pin of your next waypoint.")
    g:Row("Colours",UI:Button(g,"Reset colours",170,function() cfg().pathColor="";cfg().nextColor="5FD16B";P:Changed();if page then page:Refresh() end end),
        {help="Path in the style's accent, the next target green."})
    switch("shareReceive","Receive shared paths","Paths others share with you show a preview first; nothing is added without your click.")
    local select=UI:SettingsTabs(page,g,{
        {id="general",label="General",sections={"module","coords","fade","zone"}},
        {id="map",label="Map",sections={"window","content"}},
        {id="waypoints",label="Waypoints",sections={"waypoints","path"}},
    })
    function page:Arrange(width)
        self.width=width
        UI:Place(g,self,0,0)
        local height=g:Arrange(width)+8
        M.Height(self,height);return height
    end
    function page:Refresh()
        local c=P:Config()
        self.enabled:SetValue(ns.Settings:Module(P.ID).enabled==true)
        for key,control in pairs(controls) do if control.SetValue and key~="pathColor" and key~="nextColor" then control:SetValue(c[key]) end end
        local ar,ag,ab=P:Style():Color("accent")
        controls.pathColor:SetValue((c.pathColor~="" and c.pathColor or string.format("%02X%02X%02X",ar*255,ag*255,ab*255)).."FF")
        controls.nextColor:SetValue(c.nextColor.."FF")
        local fades=P.Fade:BlizzardFades()
        if self.blizzardFade.SetText then self.blizzardFade:SetText(fades and "On: ours waits until you switch it off in the game options." or "Off: ours is in charge.") end
        local source
        if P.Waypoints:TomTom() then source="TomTom (loaded): /way, arrow and corpse marker are TomTom's; /bv way hands waypoints to it."
        elseif P.Waypoints.slash then source="Blizzard's own waypoint with its arrow; /way is ours."
        else source="Blizzard's own waypoint; /way belongs to another addon, use /bv way." end
        if self.waySource.SetText then self.waySource:SetText(source) end
        -- Parts another addon handles: a note, the settings greyed out, and
        -- "use ours anyway" (only offered when another addon is there).
        local G=P.Guard
        local function note(part,label)
            local other,forced=G:Detected(part),G:Forced(part)
            if not other then return nil,"" end
            if forced then return other,label.." also by "..other..": ours is forced on." end
            return other,label.." by "..other..": ours is off."
        end
        local coords,coordsText=note("coords","Coordinates")
        if self.coordsOwner.SetText then self.coordsOwner:SetText(coords and coordsText or "None: ours are in charge.") end
        g:SetRowEnabled(controls.forceCoords,coords~=nil)
        local coordsOff=coords~=nil and not G:Forced("coords")
        for _,key in ipairs({"coords","coordsPlayer","coordsCursor","coordsDecimals"}) do g:SetRowEnabled(controls[key],not coordsOff) end
        local move,moveText=note("move","Moving")
        local scale,scaleText=note("scale","Scaling")
        local parts={}
        if move then parts[#parts+1]=moveText end
        if scale then parts[#parts+1]=scaleText end
        if self.windowOwner.SetText then self.windowOwner:SetText(#parts>0 and table.concat(parts,"  ") or "None: ours are in charge.") end
        g:SetRowEnabled(controls.forceMove,move~=nil);g:SetRowEnabled(controls.forceScale,scale~=nil)
        local reveal,revealText=note("reveal","Unexplored areas")
        if reveal then parts[#parts+1]=revealText;if self.windowOwner.SetText then self.windowOwner:SetText(table.concat(parts,"  ")) end end
        g:SetRowEnabled(controls.forceReveal,reveal~=nil)
        g:SetRowEnabled(controls.unexplored,not (reveal and not G:Forced("reveal")))
        g:SetRowEnabled(controls.movable,not (move and not G:Forced("move")))
        g:SetRowEnabled(page.resetPosition,not (move and not G:Forced("move")))
        g:SetRowEnabled(controls.scale,not (scale and not G:Forced("scale")))
        -- Blizzard's own map fade, TomTom's arrow and corpse marker: theirs.
        for _,key in ipairs({"fade","fadeOpacity","fadeScope","fadeMouseover","fadeTime"}) do g:SetRowEnabled(controls[key],not fades) end
        local tomtom=P.Waypoints:TomTom()~=nil
        g:SetRowEnabled(controls.arrow,not tomtom);g:SetRowEnabled(controls.corpse,not tomtom);g:SetRowEnabled(controls.pathPins,not tomtom)
    end
    select("general");page:Refresh()
    return page
end
ns.Config:RegisterPage("map",{title="Map",description="Coordinates, transparency while moving, map size and waypoints.",
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})
ns.Commands:RegisterAction("map",function(action)
    if action=="probe" then return P.Probe:Open() end
    if action=="on" or action=="off" then
        ns.Modules:SetEnabled(P.ID,action=="on");P:Print(ns.Modules.records[P.ID].state);if ns.Config then ns.Config:Refresh() end
    else ns.Config:OpenPage("map") end
end)
ns.Commands:RegisterAction("way",function(text)
    if not P:Active() then P:Print("The Map module is off (/bv map on).");return end
    P.Waypoints:Command(text)
end)

local _,Q=...
if not Q.ready then return end
-- Settings page and /bv quest.
local ns=Q.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics

local ORDERS={{value="map,list,details",label="Map · List · Details"},{value="list,map,details",label="List · Map · Details"},
    {value="details,map,list",label="Details · Map · List"},{value="map,details,list",label="Map · Details · List"},
    {value="list,details,map",label="List · Details · Map"},{value="details,list,map",label="Details · List · Map"}}
local GROUPS={{value="currentzone",label="Current zone first"},{value="zone",label="By zone"},{value="status",label="By status"},{value="none",label="No groups"}}
local SORTS={{value="distance",label="Nearest objective"},{value="progress",label="Progress"},{value="ready",label="Ready first"},
    {value="level",label="Level"},{value="recent",label="Recent progress"},{value="title",label="Name"}}
local LEVELS={{value="badge",label="Badge"},{value="color",label="Name in difficulty colour"},{value="off",label="Off"}}
local PROGRESS={{value="text",label="Text (3/5)"},{value="bar",label="Thin bar"},{value="off",label="Off"}}
local DENSITY={{value="compact",label="Compact"},{value="normal",label="Normal"},{value="comfortable",label="Comfortable"}}
local TRACKER_MODES={{value="watchedzone",label="Tracked and current zone"},{value="watched",label="Tracked only"},{value="nearest",label="Nearest quests"}}
local TRACKER_LAYOUTS={{value="full",label="Full"},{value="compact",label="Compact (open objectives)"},{value="minimal",label="Minimal (names only)"}}
local TRACKER_PROGRESS={{value="bar",label="Bar"},{value="text",label="Text (7/12)"},{value="percent",label="Text and percent"},{value="off",label="Off"}}
local TRACKER_COMBAT={{value="show",label="Show"},{value="fade",label="Fade"},{value="hide",label="Hide"}}
local TRACKER_INSTANCE={{value="show",label="Show"},{value="hide",label="Hide"}}
local TRACKER_LEFT={{value="focus",label="Set as navigation target"},{value="map",label="Show in quest log"}}

function Q:Changed()
    self.Data:Sort()
    if self.Panes.frame then self.Panes:Layout() end
    if self.Tracker and self.Tracker:Shown() then self.Tracker:Layout() end
end
local page
local function build(parent)
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    local function cfg() return Q:Config() end
    local function set(key) return function(value) cfg()[key]=value;Q:Changed() end end
    local function row(key,title,control,help,opts) opts=opts or {};opts.help=help;controls[key]=g:Row(title,control,opts);return controls[key] end
    local function switch(key,title,help) return row(key,title,UI:Switch(g,false,set(key)),help) end
    -- Options follow via SetOptions right after.
    local function dropdown(key,title,help) return row(key,title,UI:Dropdown(g,190,{},set(key)),help) end
    local function slider(key,title,low,high,step,format,help) return row(key,title,UI:InlineSlider(g,190,low,high,step,format,set(key)),help) end
    g:Section("module","Module")
    page.enabled=g:Row("Enabled",UI:Switch(g,false,function(value) ns.Modules:SetEnabled(Q.ID,value);if ns.Config then ns.Config:Refresh() end end),
        {help="Quest log beside the world map: list, details of the selected quest, sorting and grouping."})
    g:Row("World map",UI:Button(g,"Open map",170,function() if ToggleWorldMap then ToggleWorldMap() end end),{help="Opens the world map with the quest log."})
    switch("hideBlizzard","Hide Blizzard's quest list","Closes Blizzard's own list beside the map while ours is shown; turning this or the module off gives it back.")
    g:Section("layout","Layout")
    dropdown("order","Order","Order of list, map and details from left to right. The map itself never moves or changes size.")
    controls.order:SetOptions(ORDERS)
    slider("listWidth","List width",200,600,10,"%d","Also by dragging the edge between list and map; double-click resets.")
    slider("detailsWidth","Details width",220,600,10,"%d","Also by dragging the edge; the details appear only for a selected quest.")
    g:Section("list","List")
    dropdown("groupBy","Groups","Current zone first, by zone, by status or no groups.")
    controls.groupBy:SetOptions(GROUPS)
    dropdown("sortBy","Sort","Within each group. Pinned quests stay on top (right-click a quest).")
    controls.sortBy:SetOptions(SORTS)
    dropdown("levelMode","Level","A badge before the name, the name in the difficulty colour, or nothing.")
    controls.levelMode:SetOptions(LEVELS)
    dropdown("progressMode","Progress","Objective counts as text, a thin bar under the row, or nothing.")
    controls.progressMode:SetOptions(PROGRESS)
    switch("showDistance","Distance","Yards to the nearest open objective (the client knows no turn-in places).")
    switch("showHeaders","Group headers","Headings between the groups.")
    switch("showTags","Tags","E elite, G group size, D dungeon.")
    switch("showFooter","Summary line","Quests in the log, ready ones and their XP.")
    switch("dungeonColor","Dungeon quests tinted","Dungeon and raid quest names in a slightly warmer colour, in the list and the tracker.")
    g:Section("look","Look")
    row("styleFamily","Style family",UI:Dropdown(g,190,ns.Styles:Choices(true),function(value) cfg().styleFamily=value;ns.Styles:Changed();Q:Changed() end),
        "The suite's in-game style or an own one for list and details.")
    controls.styleFamily:SetOptionsProvider(function() return ns.Styles:Choices(true) end)
    dropdown("density","Row height","Compact, normal or comfortable rows.")
    controls.density:SetOptions(DENSITY)
    slider("fontSize","Font size",9,18,1,"%d","Text size of the list.")
    slider("opacity","Background opacity",30,100,5,"%d %%","Background of list and details.")
    g:Section("details","Details")
    switch("detailsText","Quest text","The description, collapsible in the details.")
    switch("detailsRewards","Rewards","XP, money and items; an arrow marks an upgrade over what you wear.")
    -- Tracker on screen (Horizon Focus as the model) and the dungeon banner.
    local function trackerChanged(key) return function(value) cfg()[key]=value;Q.Tracker:Update() end end
    local function tswitch(key,title,help) return row(key,title,UI:Switch(g,false,trackerChanged(key)),help) end
    local function tdropdown(key,title,options,help) local control=row(key,title,UI:Dropdown(g,190,{},trackerChanged(key)),help);control:SetOptions(options);return control end
    local function tslider(key,title,low,high,step,format,help) return row(key,title,UI:InlineSlider(g,190,low,high,step,format,trackerChanged(key)),help) end
    g:Section("tracker","Tracker")
    tswitch("tracker","Show tracker","Quests on screen, nearest first.")
    g:Row("Position",UI:Button(g,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:questtracker") end),
        {help="Position, width and the most it grows to; taller content scrolls with the mouse wheel."})
    tswitch("trackerUnlocked","Move and resize freely","Drag the title to move it and the corner to resize it, without the Layout Editor. Off: fixed in place.")
    tdropdown("trackerMode","Quests",TRACKER_MODES,"Tracked quests and those of your current zone, only tracked ones, or the nearest ones.")
    tslider("trackerCount","Nearest quests",1,20,1,"%d","How many with \"Nearest quests\".")
    tswitch("trackerGroupDungeons","Dungeons grouped","Dungeon and raid quests in a section per dungeon instead of the zone or tracked list.")
    g:Section("trackerLook","Tracker look")
    tdropdown("trackerLayout","Layout",TRACKER_LAYOUTS,"All objectives, only open ones, or quest names only.")
    tdropdown("trackerProgress","Progress",TRACKER_PROGRESS,"Under each counted objective.")
    tswitch("trackerBackground","Background","A background behind the tracker in the style's look.")
    tslider("trackerOpacity","Background opacity",0,100,5,"%d %%","Opacity of that background.")
    g:Section("trackerBehavior","Tracker behaviour")
    tdropdown("trackerCombat","In combat",TRACKER_COMBAT,"Stays, fades or hides while you fight.")
    tdropdown("trackerInstance","In instances",TRACKER_INSTANCE,"Shown or hidden in dungeons, raids and battlegrounds.")
    tswitch("trackerMouseover","Mouseover only","Invisible until the mouse is over it.")
    tdropdown("trackerLeft","Left-click",TRACKER_LEFT,"Shift-click stops tracking; right-click opens actions.")
    tswitch("autoFocus","Auto-focus","The nearest quest becomes the navigation target; picking one yourself pauses it. Toggle with /bv quest focus (as a macro on a key).")
    tswitch("trackerHideBlizzard","Hide Blizzard's tracker","Hides Blizzard's own quest tracker while ours is on (never in combat); given back when off.")
    g:Section("banner","Dungeon banner and notifications")
    tswitch("banner","Dungeon banner","In party dungeons: time inside, XP and gold with rates per hour; hover for bosses and the next level at this pace.")
    if ns.Stage then
        g:Row("Notifications",UI:Button(g,"Open notifications",170,function() ns.Config:OpenPage("stage") end),
            {help="Quest progress and quest ready appear on the notification stage; switch them there. The zone banner belongs to the Map module."})
    end
    local select=UI:SettingsTabs(page,g,{
        {id="general",label="General",sections={"module","layout","banner"}},
        {id="log",label="Quest log",sections={"list","look","details"}},
        {id="tracker",label="Tracker",sections={"tracker","trackerLook","trackerBehavior"}},
    })
    function page:Arrange(width)
        self.width=width
        UI:Place(g,self,0,0)
        local height=g:Arrange(width)+8
        M.Height(self,height);return height
    end
    function page:Refresh()
        local c=Q:Config()
        self.enabled:SetValue(ns.Settings:Module(Q.ID).enabled==true)
        for key,control in pairs(controls) do if control.SetValue then control:SetValue(c[key]) end end
    end
    select("general");page:Refresh()
    return page
end
ns.Config:RegisterPage("quest",{title="Quest log",description="Quest log beside the world map: compact list, details, smart sorting.",
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})
ns.Commands:RegisterAction("quest",function(action)
    if action=="focus" then Q.Tracker:ToggleFocus();return end
    if action=="on" or action=="off" then
        ns.Modules:SetEnabled(Q.ID,action=="on");Q:Print(ns.Modules.records[Q.ID].state);if ns.Config then ns.Config:Refresh() end
    else ns.Config:OpenPage("quest") end
end)

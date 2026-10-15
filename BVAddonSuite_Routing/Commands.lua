local _,Routing=...
if not Routing.ready then return end
-- /bv route <what> | way | <x> <y> | stop | status | level [<name>]
--   <what>   a place by name (BV Map Data): an NPC, a title ("innkeeper"),
--            a flight master, an instance entrance, "my trainer"
--   way      to your map pin; <x> <y> to a point of the map you are on
--   stop     ends the way; status: where you are on it; level: your level
--   probe    measures while you walk, the report to copy (on / off)
--   height   your height now from the NPCs near, and the levels it fits
--   guide    left | right (of the tour window) | free | off: the guide while led;
--            preview: it with an example, without a way
--   space    where the map you are on lies for the way finding (the
--            client's rectangle, its corners carried over, the cells)
local ns=Routing.ns
local N=Routing.Navigate

-- Routing's own settings page (Florian 2026-10-15: colours of the way;
-- until now its settings sat only in Gather's Routes tab).
local page
local function build(parent)
    local UI=ns.UI
    page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    local function cfg() return Routing:Config() end
    local function redraw() if ns.MapPins then ns.MapPins:Refresh() end;if page then page:Refresh() end end
    local function row(key,title,control,help) controls[key]=g:Row(title,control,{help=help});return controls[key] end
    g:Section("colours","Way colours")
    local function color(kind,title,help)
        local key=N.COLORKEY[kind]
        return row(key,title,UI:ColorInput(g,190,function(hex) cfg()[key]=hex:sub(1,6):upper();redraw() end),help)
    end
    color("walk","Walking","The way on foot on the map and the minimap.")
    color("flight","Flights","A flight between two flight masters.")
    color("transport","Ships, zeppelins, tram","Rides on ships, zeppelins and the Deeprun Tram.")
    color("transition","Stairs, lifts, doors","Where the way changes the level in a city.")
    color("goal","Goal","The pin where the way ends.")
    g:Row("Colours",UI:Button(g,"Reset colours",170,function()
        for _,key in pairs(N.COLORKEY) do cfg()[key]="" end;redraw()
    end),{help="Back to the built-in colours."})
    g:Section("flights","Flights")
    local unknown=row("flightsUnknown","Unknown flight points",UI:Dropdown(g,190,{},function(value) cfg().flightsUnknown=value end),
        "On a continent whose flight map you have not opened: leave its flight points out (you are asked once), or count all of your side.")
    unknown:SetOptions({{value="leave",label="Leave out (asked)"},{value="all",label="Count all of yours"}})
    g:Section("guide","Guide")
    local guide=row("guide","Guide window",UI:Dropdown(g,190,{},function(value) if Routing.Guide then Routing.Guide:SetSide(value) else cfg().guide=value end end),
        "Where the guide shows while you are led: beside the tour window, where you drag it, or not at all.")
    guide:SetOptions({{value="right",label="Right of the tour"},{value="left",label="Left of the tour"},{value="free",label="Where you drag it"},{value="off",label="Off"}})
    row("guideGround","Guide background",UI:Switch(g,false,function(value) if Routing.Guide then Routing.Guide:SetBare(value~=true) else cfg().guideGround=value==true end end),
        "The guide's background panel; off it floats see-through.")
    function page:Refresh()
        local c=cfg()
        for kind,key in pairs(N.COLORKEY) do
            local hex=c[key]~="" and c[key] or N.Hex(N.COLOR[kind])
            if controls[key] and controls[key].SetValue then controls[key]:SetValue(hex.."FF") end
        end
        controls.flightsUnknown:SetValue(c.flightsUnknown);controls.guide:SetValue(c.guide);controls.guideGround:SetValue(c.guideGround)
    end
    page:Refresh()
    return page
end
ns.Config:RegisterPage("routing",{title="Routing",category="questmap",description="Ways you can really walk: colours of the way, flight points and the guide.",
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})
ns.Commands:RegisterAction("route",function(text)
    text=type(text)=="string" and text or ""
    if text=="" or text=="status" then Routing:Print(N:Status());return end
    if text=="stop" then
        if not (N.steps or N.busy) then Routing:Print("No way to end.") end
        N:Stop()
        return
    end
    if text=="probe" then Routing.Probe:Toggle();return end
    -- The log of the way, and the whole way as text for a bug report (Florian 2026-10-14).
    if text=="log" then ns.UI:DiagnosticReport("Routing log",Routing:LogText());return end
    if text=="export" then
        if not (N.goal or N.steps) then Routing:Print("No way to export: /bv route <place> first.");return end
        ns.UI:DiagnosticReport("Routing: the way",N:ExportText())
        return
    end
    local side=text:match("^guide%s*(%a*)$")
    if side then
        if side=="" then Routing:Print("The guide: "..Routing:Config().guide..". /bv route guide left | right | free | off | preview.");return end
        if side=="preview" then
            Routing:Print(Routing.Guide:Preview() and "The guide with an example (again: off)." or "The guide's example is off.")
            return
        end
        if not Routing.Guide:SetSide(side) then Routing:Print("/bv route guide left | right | free | off.");return end
        Routing:Print(side=="off" and "The guide is off." or side=="free" and "The guide stands where you drag it." or ("The guide stands "..side.." of the tour window."))
        return
    end
    -- What the way finding takes as this map's space (Florian 2026-10-12:
    -- Undercity searched as the whole Eastern Kingdoms).
    if text=="space" then
        local mapID=Routing:Position()
        if not mapID then Routing:Print("No position here.");return end
        local Grid=Routing.Grid
        local cont=ns.MapPins and ns.MapPins:Continent(mapID)
        local w,h=Routing.Call("C_Map.GetMapWorldSize",mapID)
        Routing:Print(string.format("Map %d, continent %s, its world size %s x %s yd.",mapID,tostring(cont),tostring(w),tostring(h)))
        if cont and cont~=mapID then
            local a,b,c,d=Routing.Call("C_Map.GetMapRectOnMap",mapID,cont)
            Routing:Print(string.format("The client's rectangle: %s .. %s, %s .. %s.",tostring(a),tostring(b),tostring(c),tostring(d)))
            Grid.affines={}
            local x0,y0=Grid.Convert(mapID,cont,0,0)
            local x1,y1=Grid.Convert(mapID,cont,1,1)
            Routing:Print(string.format("Its corners carried over: %s, %s .. %s, %s.",tostring(x0),tostring(y0),tostring(x1),tostring(y1)))
        end
        local s=Grid.Space({mapID})
        Routing:Print(string.format("Space of this map alone: %d x %d cells of %d yd.",s.cols,s.rows,s.cell or Grid.CELL))
        -- And what a leg of the way finding on your level searches (its own
        -- space, as Navigate:Walk builds it; the way you follow untouched).
        local _,x,y=Routing:Position()
        local c,cx,cy=Routing:OnContinent(mapID,x,y)
        if c then
            local level=Routing.Level:Current()
            local kept=N.spaces
            N.spaces=nil
            local _,note=N:Walk(c,level,cx,cy,cx,cy)
            N.spaces=kept
            Routing:Print(string.format("A leg on \"%s\" here: %s.",Routing.Level:Name(level),tostring(note)))
        end
        return
    end
    if text=="height" then
        local H=Routing.Height
        local m=H:Fresh()
        local band,mid,span=H.Text(m)
        if not band then Routing:Print("Your height: unknown, "..mid..".");return end
        local fits={}
        local mapID=Routing:Position()
        if mapID then
            for _,map in ipairs(Routing.Level.Chain(mapID)) do
                for _,level in ipairs(Routing:ReadLevels(map)) do
                    local z,from=Routing.Level:Height(level.id)
                    if H.Fits(m.set,z) then fits[#fits+1]=string.format("%s (%d%s)",level.name or "?",z,from=="learned" and ", learned" or from=="set" and ", set" or "") end
                end
            end
        end
        Routing:Print(string.format("Your height: %s yd (middle %.0f, %d NPCs, %.0f yd wide)%s.",band,mid,m.used,span,
            #fits>0 and ("; fits "..table.concat(fits,", ")) or "; fits no level of this map"))
        return
    end
    if text=="level" then
        local id=Routing.Level:Current()
        Routing:Print("You are on: "..Routing.Level:Name(id)..(id and "" or " (no level of Route Studio here)")..".")
        return
    end
    -- /bv route level <name>: you say where you are (a level of your map,
    -- or "ground"); a way being followed is planned anew from there.
    local name=text:match("^level%s+(.+)$")
    if name then
        local id,found=Routing.Level:Named(name)
        if not found then Routing:Print("No level \""..name.."\" on your map. /bv route level shows yours.");return end
        Routing.Level:Set(id)
        N.levelSet=true
        Routing:Print("You are on: "..Routing.Level:Name(id)..".")
        if N.goal and not N.busy then local goal=N.goal;N:Stop(true);N.levelSet=true;N:Start(goal) end
        return
    end
    -- How long finding the place by name took (the log of the way).
    local t0=debugprofilestop and debugprofilestop()
    local goal,err=N:Goal(text)
    N.findMs=t0 and debugprofilestop()-t0
    if not goal then Routing:Print(err);return end
    N:Start(goal)
end)

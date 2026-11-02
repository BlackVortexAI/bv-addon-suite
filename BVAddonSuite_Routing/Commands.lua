local _,Routing=...
if not Routing.ready then return end
-- /bv route <what> | way | <x> <y> | <zone> <x> <y> | stop | status | level [<name>]
--   <what>   a place by name (BV Map Data): an NPC, a title ("innkeeper"),
--            a flight master, an instance entrance, "my trainer"
--   way      to your map pin; <x> <y> to a point of the map you are on;
--            <zone> <x> <y> to a point of a zone (its name or map ID)
--   stop     ends the way; status: where you are on it; level: your level
--   probe    measures while you walk, the report to copy (on / off)
--   height   your height now from the NPCs near, and the levels it fits
--   guide    left | right (of the tour window) | free | off: the guide while led;
--            preview: it with an example, without a way
--   memory   where Routing's memory goes: while loading, and now by block;
--            memory marks on | off: exact marks while loading (from the next /reload)
--   reach    what the client tells about reaching the way's goal (soft target, name plates, ranges)
local ns=Routing.ns
local N=Routing.Navigate

-- Routing's own settings page (Florian 2026-10-15: colours of the way;
-- until now its settings sat only in Gather's Routes tab).
local page
local function build(parent)
    local UI=ns.UI
    -- Interface opt-in (2026-10-26, Config interfaceSettings): the page is built
    -- in the captured Interface context like Gather. The page host stays a plain
    -- ToolStyle container that never paints; without opt-in all is as before.
    local pageStyle=UI:GetStyle();local interface=pageStyle.materialProfile=="interface"
    if interface then
        page=UI:WithStyle(UI:ToolStyle(),function() local host=UI:Panel(parent,880,600,"surface");UI:HideSurface(host);return host end)
        page.bvStyle=pageStyle
    else page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page) end
    local g=UI:SettingsGrid(page);page.grid=g
    local controls={}
    local function cfg() return N:DisplayConfig() end
    local function redraw() if ns.MapPins then ns.MapPins:Refresh() end;if page then page:Refresh() end end
    local function row(key,title,control,help) controls[key]=g:Row(title,control,{help=help});return controls[key] end
    g:Section("lines","Route lines")
    page.lineStyles=ns.RouteLineStyles and ns.RouteLineStyles:Options(g)
    g:Section("colours","Way colours")
    local function color(kind,title,help)
        local key=N.COLORKEY[kind]
        local field=row(key,title,UI:ColorInput(g,190,function(hex) cfg()[key]=hex:sub(1,6):upper();redraw() end),help)
        -- Routing persists RGB only; "" is the built-in colour. The picker opens
        -- later from an ambient context: bind this page's context.
        if interface then field.bvColorOptions={style=pageStyle,rgb=true,default=N.Hex(N.COLOR[kind]).."FF"} end
        return field
    end
    color("walk","Walking","The way on foot on the map and the minimap.")
    color("flight","Flights","A flight between two flight masters.")
    color("transport","Ships, zeppelins, tram","Rides on ships, zeppelins and the Deeprun Tram.")
    color("transition","Stairs, lifts, doors","Where the way changes the level in a city.")
    color("goal","Goal","The pin where the way ends.")
    g:Row("Colours",UI:Button(g,"Reset colours",170,function()
        for _,key in pairs(N.COLORKEY) do cfg()[key]="" end;redraw()
    end),{help="Back to the built-in colours."})
    g:Section("ahead","Route distance fading")
    row("aheadOpacity","Opacity",UI:InlineSlider(g,190,10,100,5,"%d %%",function(value) cfg().aheadOpacity=value;redraw() end),
        "Minimum visibility of the distant route on both maps (100 %: not dimmed). Stops fade a little less; the goal pin stays clear.")
    row("aheadDistance","Fully dimmed at",UI:InlineSlider(g,190,40,300,10,"%d yd",function(value) cfg().aheadDistance=value;redraw() end),
        "The first 20 yards ahead stay bright. Beyond that the route fades evenly to this distance, measured along the way from your progress, not by corners or straight-line distance.")
    g:Section("roads","Roads")
    -- Florian 2026-10-16: a loose preference, a slider each for roads and your walked ways.
    local mode=row("routeMode","Route mode",UI:Dropdown(g,190,{},function(value) cfg().routeMode=value end),
        "How new ways start. Safe: keeps to roads much more (roads cost at most 40 %, whatever the slider below says), swims only where it saves a lot, and goes round zones above your level (unless that is set to Off); ways get longer. Normal: as set below. The shield in the guide switches the way you walk.")
    mode:SetOptions({{value="normal",label="Normal"},{value="safe",label="Safe"}})
    row("roadPercent","Road preference",UI:InlineSlider(g,190,30,100,5,"%d %%",function(value) cfg().roadPercent=value end),
        "What a yard of road costs against open ground: 100 % like any ground; 60 % (the default) a road up to about 1.7 times as long is still taken. Below 50 % ways bend far for roads. Steep slopes, walls and water stay what they are.")
    row("walkedPercent","Walked ways",UI:InlineSlider(g,190,30,100,5,"%d %%",function(value) cfg().walkedPercent=value end),
        "The same for the ways you walked often (BV Gather's walked ways), apart from roads.")
    g:Section("zones","Zones above your level")
    local zones=row("zoneLevels","Zones above your level",UI:Dropdown(g,190,{},function(value) cfg().zoneLevels=value;fresh() end),
        "A way through a zone whose lowest level is above yours: say so after planning, or also go round it where another way exists (it stays possible when there is none).")
    zones:SetOptions({{value="warn",label="Say so"},{value="avoid",label="Avoid and say so"},{value="off",label="Off"}})
    g:Section("flights","Flights")
    row("useFlights","Use flights",UI:Switch(g,true,function(value) cfg().useFlights=value==true end),
        "Off: ways are planned on foot (and by boat, zeppelin and tram) only, no flight master. Also /bv route flights on | off.")
    local unknown=row("flightsUnknown","Unknown flight points",UI:Dropdown(g,190,{},function(value) cfg().flightsUnknown=value end),
        "On a continent whose flight map you have not opened: leave its flight points out (you are asked once), or count all of your side.")
    unknown:SetOptions({{value="leave",label="Leave out (asked)"},{value="all",label="Count all of yours"}})
    g:Section("compute","Planning time")
    local budget=row("computeBudget","Time per frame",UI:Dropdown(g,190,{},function(value) cfg().computeBudget=value end),
        "How much of each frame planning a way may use. Auto: half a frame at your frame rate (at most 14 ms). Less: smoother while it plans, the way takes longer; more: the way comes sooner, the frame rate drops a little meanwhile.")
    budget:SetOptions({{value="auto",label="Auto (frame rate)"},{value="5",label="5 ms (smoothest)"},{value="10",label="10 ms"},{value="15",label="15 ms"},{value="25",label="25 ms (fastest)"}})
    row("pauseInCombat","Pause in combat",UI:Switch(g,true,function(value) cfg().pauseInCombat=value==true end),
        "While you fight, planning waits and goes on afterwards.")
    row("prepareAtLogin","Prepare after login",UI:Switch(g,true,function(value) cfg().prepareAtLogin=value==true end),
        "A few seconds after you log in, the way finding on the continent you are on is made ready in the background, so the first way is planned as fast as the next. Off: made when you first ask for a way.")
    g:Section("transports","Ships & zeppelins")
    row("transportSharing","Share observed timetables",UI:Switch(g,true,function(value) cfg().transportSharing=value==true end),
        "Exchange recent observations with other BV users of your faction through a shared channel, even without a group or guild.")
    row("transportAutoShow","Show near docks and towers",UI:Switch(g,true,function(value) cfg().transportAutoShow=value==true end),
        "Show arrival and departure times near a port, even without an active route. Close it to dismiss until you leave the port.")
    row("arrivals","Timetable",UI:Button(g,"Open timetable",190,function() Routing.Arrivals:Show() end),
        "All ports, live countdowns when a recent schedule is known, and estimates marked explicitly.")
    g:Section("guide","Guide")
    local guide=row("guide","Guide window",UI:Dropdown(g,190,{},function(value) if Routing.Guide then Routing.Guide:SetSide(value) else cfg().guide=value end end),
        "Where the guide shows while you are led: beside the tour window, where you drag it, or not at all.")
    guide:SetOptions({{value="right",label="Right of the tour"},{value="left",label="Left of the tour"},{value="free",label="Where you drag it"},{value="off",label="Off"}})
    row("guideGround","Guide background",UI:Switch(g,false,function(value) if Routing.Guide then Routing.Guide:SetBare(value~=true) else cfg().guideGround=value==true end end),
        "The guide's background panel; off it floats see-through.")
    -- Config places the page and asks it to lay its rows out (Florian
    -- 2026-10-16: without this the page stayed empty in 0.1.3).
    function page:Arrange(width)
        UI:Place(g,self,0,0)
        -- Interface pages keep the approved 10-unit scroll reserve (as Gather).
        local height=g:Arrange(interface and math.max(1,width-10) or width)+8
        ns.DesignSystem.Metrics.Height(self,height);return height
    end
    page.controls=controls
    function page:Refresh()
        if page.lineStyles then page.lineStyles:Refresh() end
        local c=cfg()
        for kind,key in pairs(N.COLORKEY) do
            -- Only a valid colour reaches the input (as N:Color reads it).
            local hex=c[key]
            hex=type(hex)=="string" and hex:match("^%x%x%x%x%x%x") and hex:sub(1,6) or N.Hex(N.COLOR[kind])
            if controls[key] and controls[key].SetValue then controls[key]:SetValue(hex.."FF") end
        end
        controls.aheadOpacity:SetValue(c.aheadOpacity);controls.aheadDistance:SetValue(c.aheadDistance)
        controls.roadPercent:SetValue(c.roadPercent);controls.walkedPercent:SetValue(c.walkedPercent);controls.zoneLevels:SetValue(c.zoneLevels)
        controls.routeMode:SetValue(c.routeMode)
        controls.transportAutoShow:SetValue(c.transportAutoShow)
        controls.transportSharing:SetValue(c.transportSharing)
        controls.computeBudget:SetValue(c.computeBudget);controls.pauseInCombat:SetValue(c.pauseInCombat);controls.prepareAtLogin:SetValue(c.prepareAtLogin)
        controls.useFlights:SetValue(c.useFlights);controls.flightsUnknown:SetValue(c.flightsUnknown);controls.guide:SetValue(c.guide);controls.guideGround:SetValue(c.guideGround)
    end
    if interface then
        -- Profile change or hide closes only this page's own menus and picker.
        local function owned(owner)
            if not owner then return false end
            for _,item in ipairs(g.items) do if item.control==owner then return true end end
            return false
        end
        local function cancelOwnedMenu()
            if UI.dropdown and owned(UI.dropdown.owner) then UI:CloseDropdown() end
            if UI.colorPopup and owned(UI.colorPopup.owner) then UI.colorPopup:Hide() end
        end
        local dispose
        local function watch() if not dispose then dispose=ns.Settings:BeforeProfileChange(page,cancelOwnedMenu) end end
        page:HookScript("OnShow",watch)
        page:HookScript("OnHide",function() cancelOwnedMenu();if dispose then dispose();dispose=nil end end)
        if page:IsVisible() then watch() end
    end
    page:Refresh()
    return page
end
ns.Config:RegisterPage("routing",{title="Routing",category="questmap",description="Ways you can really walk: colours of the way, flight points and the guide.",
    interfaceSettings=true,
    build=function(parent) return page or build(parent) end,
    refresh=function() if page then page:Refresh() end end})
ns.Commands:RegisterAction("route",function(text)
    text=type(text)=="string" and text or ""
    if text=="arrivals" or text=="timetable" then Routing.Arrivals:Show();return end
    if text=="" or text=="status" then Routing:Print(N:Status());return end
    if text=="stop" then
        if not (N.steps or N.busy) then Routing:Print("No way to end.") end
        N:Stop()
        return
    end
    if text=="probe" then Routing.Probe:Toggle();return end
    -- Flights on or off (Florian 2026-10-16: ways on foot to test).
    -- Where Routing's memory goes (Claude 2026-10-25, Florian: measure in the game, do not guess).
    --   Loading: the Lua memory at marks between the data files (Mark\*.lua). Exact only with "memory marks on"
    --   (after the next /reload each mark collects first, ~0.3 s more loading); else garbage of the moment counts too.
    --   Now: the size of each data block and cache from its tables and strings (Lua 5.1 on 64 bits: a table 56 bytes,
    --   16 per array slot, 40 per hash slot rounded up to a power of two; a string 25 bytes plus its length; each
    --   counted once per block), and all of Lua and Routing's own memory after a full collect.
    local marksArg=text:match("^memory%s+marks%s*(%a*)$")
    if marksArg then
        local db=rawget(_G,"BVAddonSuiteDB")
        if type(db)=="table" and (marksArg=="on" or marksArg=="off") then db.routingMemoryMarks=marksArg=="on" or nil end
        Routing:Print("Memory marks while loading: "..((type(db)=="table" and db.routingMemoryMarks) and "exact (collected), from the next /reload" or "fast (not collected)").." (/bv route memory marks on | off).")
        return
    end
    if text=="memory" then
        local function mb(v) return string.format("%.1f",v/1024/1024) end
        local lines={}
        local marks=Routing.memMarks or {}
        if #marks>1 then
            local t={}
            for i=1,#marks-1 do
                local d=(marks[i+1][2]-marks[i][2])*1024
                if d>=512*1024 then t[#t+1]=marks[i][1].." "..mb(d) end
            end
            lines[#lines+1]="Loading ("..(marks[1][3] and "exact" or "not collected")..", MB): "..table.concat(t,"; ").."; in all "..mb((marks[#marks][2]-marks[1][2])*1024)
        end
        local function pow2(n) local p=1;while p<n do p=p*2 end;return n>0 and p or 0 end
        local function size(roots)
            local seen,stack,bytes,tables,strings={},{},0,0,0
            local function visit(v)
                local ty=type(v)
                if (ty=="table" or ty=="string") and not seen[v] then
                    seen[v]=true
                    if ty=="string" then bytes=bytes+25+#v;strings=strings+1 else stack[#stack+1]=v end
                end
            end
            for _,r in ipairs(roots) do visit(r) end
            while #stack>0 do
                local t=stack[#stack];stack[#stack]=nil
                tables=tables+1
                local n=#t
                local h=0
                for k,v in pairs(t) do
                    if not (type(k)=="number" and k>=1 and k<=n and k%1==0) then h=h+1 end
                    visit(k);visit(v)
                end
                bytes=bytes+56+16*n+40*pow2(h)
            end
            return bytes,tables,strings
        end
        local H=Routing.Hpa or {}
        local blocks={
            {"navmesh data",{rawget(_G,"BVRoutingNav")}},
            {"navmesh in use",{H.jumps,H.jumpFrom,H.jumpTo,H.ajump,H.jcost,H.cc}},
            {"shipped maps and towns",{Routing.SHIPPED}},
            {"ground heights",{rawget(_G,"BVRoutingNavGround"),N.groundTiles}},
            {"roads",{rawget(_G,"BVRoutingRoads")}},
            {"walks searched",{N.legs}},
        }
        local t={}
        for _,b in ipairs(blocks) do
            local roots={}
            for _,r in pairs(b[2]) do roots[#roots+1]=r end
            local bytes=size(roots)
            if bytes>=256*1024 then t[#t+1]=b[1].." "..mb(bytes) end
        end
        lines[#lines+1]="Now (MB, from their tables and strings): "..table.concat(t,"; ")
        collectgarbage("collect")
        local usage=""
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            usage=", Routing "..mb((GetAddOnMemoryUsage("BVAddonSuite_Routing") or 0)*1024)
        end
        lines[#lines+1]="After a full collect: all Lua "..mb(collectgarbage("count")*1024)..usage..(H.cont and ("; navmesh in use: "..H.cont) or "")
        for _,l in ipairs(lines) do Routing:Print(l) end
        return
    end
    -- What the client tells about reaching the goal (Claude 2026-10-25, Florian: to try in the game what could tell
    -- "arrived" better than the map): the way's goal and its reach point (Hpa.ReachNodes), distance and height to
    -- you, the soft interact target, interact distances, name plates, visibility. Changes nothing; every call
    -- guarded (the client's build may lack some). One line per signal.
    if text=="reach" then
        local function try(f,...) if type(f)~="function" then return nil end;local ok,a,b,c,d=pcall(f,...);if ok then return a,b,c,d end end
        local function cvar(name)
            local api=rawget(_G,"C_CVar")
            local v=api and try(api.GetCVar,name)
            if v==nil then v=try(rawget(_G,"GetCVar"),name) end
            return v
        end
        -- (a secret value, protected in this client, is said as such: the chat drops a line holding one)
        local function s(v) if v~=nil and Routing.Secret(v) then return "(protected)" end;return v==nil and "-" or tostring(v) end
        local function creature(guid)
            if type(guid)~="string" then return nil end
            local kind,_,_,_,_,id=try(rawget(_G,"strsplit"),"-",guid)
            return (kind=="Creature" or kind=="Vehicle") and id or nil
        end
        local goal=N.goal
        local lines={}
        if not goal then lines[#lines+1]="Reach: no way active." end
        local cont,px,py=N:Here()
        local m=Routing.Height and try(Routing.Height.Now,Routing.Height)
        local span,low,high
        if m and m.set and Routing.Height.Span then span,low,high=Routing.Height.Span(m.set) end
        local myZ=span and (low+high)/2 or nil
        if goal then
            local H=Routing.Hpa
            local reach=H and H.GoalAt and goal.cont and H:Has(goal.cont) and H.cont==goal.cont and H.GoalAt(goal.x,goal.y) and H.ReachNodes(goal.x,goal.y,goal.z)
            local rx,ry
            if reach and reach[1] and px then
                local bd
                for _,r in ipairs(reach) do local d=N.Yards(goal.cont,px,py,r[2],r[3]);if not bd or d<bd then rx,ry,bd=r[2],r[3],d end end
            end
            lines[#lines+1]=string.format("Goal: %s (Map Data has no creature IDs) at %.4f %.4f z %s; reach points %s",tostring(goal.name),goal.x or 0,goal.y or 0,s(goal.z),reach and #reach or "-")
            if px and goal.cont==cont then
                local d2=N.Yards(cont,px,py,goal.x,goal.y)
                local dz=(myZ and type(goal.z)=="number") and (goal.z-myZ) or nil
                lines[#lines+1]=string.format("You: 2D %.1f yd%s, height %s (band %s), to the nearest reach point %s",d2,
                    dz and string.format(", 3D %.1f yd, goal %+.1f yd",math.sqrt(d2*d2+dz*dz),dz) or "",s(myZ and string.format("%.1f",myZ)),
                    s(span and string.format("%.0f",span)),rx and string.format("%.1f yd",N.Yards(cont,px,py,rx,ry)) or "-")
            end
        end
        local soft=try(rawget(_G,"UnitGUID"),"softinteract")
        local softName=try(rawget(_G,"UnitName"),"softinteract")
        lines[#lines+1]=string.format("Soft interact: %s (creature %s)%s; SoftTargetInteract %s, range %s",s(softName),s(creature(soft)),
            (goal and softName and softName==goal.name) and " = the goal" or "",s(cvar("SoftTargetInteract")),s(cvar("SoftTargetInteractRange")))
        for _,unit in ipairs({"softinteract","target","mouseover"}) do
            if try(rawget(_G,"UnitExists"),unit) then
                lines[#lines+1]=string.format("  %s: %s, interact range (CheckInteractDistance %d) %s, visible %s, in range %s",unit,s(try(rawget(_G,"UnitName"),unit)),
                    Routing.Navigate and Routing.Navigate.SOFTCHECK or 3,s(try(rawget(_G,"CheckInteractDistance"),unit,Routing.Navigate and Routing.Navigate.SOFTCHECK or 3)),s(try(rawget(_G,"UnitIsVisible"),unit)),s((try(rawget(_G,"UnitInRange"),unit))))
            end
        end
        local np=rawget(_G,"C_NamePlate")
        local plates=np and try(np.GetNamePlates)
        local count,mine=0,nil
        if type(plates)=="table" then
            for _,plate in ipairs(plates) do
                count=count+1
                local token=type(plate)=="table" and plate.namePlateUnitToken
                local name=token and try(rawget(_G,"UnitName"),token)
                if goal and name==goal.name then
                    local alpha=type(plate)=="table" and try(plate.GetAlpha,plate)
                    local shown=type(plate)=="table" and try(plate.IsVisible,plate)
                    mine=string.format("the goal's: alpha %s, shown %s",s(alpha and string.format("%.2f",alpha)),s(shown))
                end
            end
        end
        lines[#lines+1]=string.format("Name plates: %s%s; nameplateShowFriendlyNPCs %s",plates and count or "-",mine and (", "..mine) or "",s(cvar("nameplateShowFriendlyNPCs")))
        for _,l in ipairs(lines) do Routing:Print(l) end
        return
    end
    local fly=text:match("^flights%s*(%a*)$")
    if fly then
        local c=Routing:Config()
        if fly=="on" or fly=="off" then c.useFlights=fly=="on" end
        Routing:Print("Flights: "..(c.useFlights and "on" or "off").." (/bv route flights on | off).")
        if page then page:Refresh() end
        return
    end
    -- The log of the way, and the whole way as text for a bug report (Florian 2026-10-14).
    if text=="log" then ns.UI:DiagnosticReport("Routing log",Routing:LogText());return end
    if text=="transport status" then
        local t=Routing.Timetable
        ns.UI:DiagnosticReport("Ships and zeppelins: observer",t.Sync:Status().."\n\n"..table.concat(t.watchLog or {"No observations yet"},"\n"));return
    end
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

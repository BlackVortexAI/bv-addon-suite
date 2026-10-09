local _,P=...
if not P.ready then return end
-- Waypoints (Florian 2026-10-08: compatible with TomTom, never disturb
-- existing systems). With TomTom loaded, every waypoint goes to TomTom's own
-- API and /way stays TomTom's. Without it, /way is ours only when no other
-- addon claims it; the waypoint is Blizzard's own user waypoint (map pin,
-- navigation and distance on screen) plus our arrow, queued: on arrival the
-- next one follows. Map 0.2: list (rename, reorder, sets), import of /way
-- lines (Wowhead lists, zone names), export, /way here and next, a corpse
-- waypoint and quest objectives. /bv way always works.
local ns=P.ns
local W={}
P.Waypoints=W

function W:TomTom()
    local tomtom=rawget(_G,"TomTom")
    if type(tomtom)=="table" and type(tomtom.AddWaypoint)=="function" then return tomtom end
end
-- Another addon's /way (TomTom or any other): then ours is not registered.
function W:Claimed()
    for name,value in pairs(_G) do
        if type(name)=="string" and name:match("^SLASH_") and not name:match("^SLASH_BVMAPWAY") and type(value)=="string" and value:lower()=="/way" then return name end
    end
    return nil
end
function W:Queue() return P:Config().waypoints end
-- List window and arrow follow every change.
function W:Notify()
    if P.WaypointList and P.WaypointList.Refresh then P.WaypointList:Refresh() end
    if P.Arrow and P.Arrow.Update then P.Arrow:Update() end
    if P.Path and P.Path.Refresh then P.Path:Refresh() end
end

-- "/way [#mapID | zone name] x y [title]": percent, dot or comma decimals.
local function trim(text)
    if type(text)~="string" then return "" end
    return (text:gsub("^%s+",""):gsub("%s+$",""))
end
local function number(token)
    if type(token)~="string" then return nil end
    token=token:gsub(",$","")
    if token:match("^%d+,%d+$") then token=token:gsub(",",".") end
    if not token:match("^%d*%.?%d+$") then return nil end
    return tonumber(token)
end
function W.Parse(text)
    if type(text)~="string" then return nil end
    text=text:gsub("^%s+",""):gsub("%s+$",""):gsub("^/[%a]+%s+","")
    if text:lower():match("^way%s") then text=text:sub(5) end
    local tokens={}
    for token in text:gmatch("%S+") do tokens[#tokens+1]=token end
    local mapID,i=nil,1
    if tokens[1] and tokens[1]:match("^#%d+$") then mapID=tonumber(tokens[1]:sub(2));i=2
    elseif tokens[1] and not number(tokens[1]) then
        -- Zone name: the words before the first number.
        local words={}
        while tokens[i] and not number(tokens[i]) do words[#words+1]=tokens[i];i=i+1 end
        mapID=P.Zones:Find(table.concat(words," "))
        if not mapID then return nil,"unknown zone \""..table.concat(words," ").."\"" end
    end
    local x,y=number(tokens[i]),number(tokens[i+1])
    if not (x and y) or x<0 or x>100 or y<0 or y>100 then return nil end
    local title=table.concat(tokens," ",i+2)
    return {mapID=mapID,x=x/100,y=y/100,title=title~="" and title or nil}
end
function W:MapName(mapID) return P.Zones:Name(mapID) end
function W:Label(point) return point.title or (self:MapName(point.mapID).." "..P:Format(point.x,point.y)) end

-- Adds a waypoint: TomTom when present, else Blizzard's own (queued).
-- front: becomes the active one at once (corpse, quest objective, here).
function W:Add(point,quiet,front)
    point.mapID=point.mapID or P.Call("C_Map.GetBestMapForUnit","player")
    if type(point.mapID)~="number" then if not quiet then P:Print("No map here for a waypoint.") end;return false end
    local tomtom=self:TomTom()
    if tomtom then
        pcall(tomtom.AddWaypoint,tomtom,point.mapID,point.x,point.y,{title=self:Label(point),from="BV Addon Suite"})
        if not quiet then P:Print("Waypoint for TomTom: "..self:Label(point)) end
        return true
    end
    local list=self:Queue()
    local entry={mapID=point.mapID,x=point.x,y=point.y,title=point.title,corpse=point.corpse,loop=point.loop or nil}
    if front then table.insert(list,1,entry) else list[#list+1]=entry end
    if front or #list==1 then self:Activate(quiet)
    else
        if not quiet then P:Print("Waypoint queued ("..#list.."): "..self:Label(entry)) end
        self:Notify()
    end
    return true
end
-- The first queued waypoint becomes Blizzard's user waypoint and the navigation target.
function W:Activate(quiet)
    local point=self:Queue()[1]
    if not point then self.active=nil;self:Watch();self:Notify();return false end
    local ui=P.Call("UiMapPoint.CreateFromCoordinates",point.mapID,point.x,point.y)
    if not ui or P.Call("C_Map.CanSetUserWaypointOnMap",point.mapID)==false then
        P:Print("Waypoints are not possible on this map: "..self:Label(point));table.remove(self:Queue(),1)
        return self:Activate(quiet)
    end
    self.setting=true
    P.Call("C_Map.SetUserWaypoint",ui)
    P.Call("C_SuperTrack.SetSuperTrackedUserWaypoint",true)
    self.setting=false
    self.active,self.lastDistance=point,nil
    if P.Navigation then P.Navigation:Reset() end
    if not quiet then P:Print("Waypoint: "..self:Label(point)) end
    self:Watch();self:Notify()
    return true
end
-- Any entry of the queue becomes the active one (list window, /way next).
function W:Choose(index)
    local list=self:Queue()
    local point=list[index]
    if not point or self:TomTom() then return false end
    table.remove(list,index);table.insert(list,1,point)
    return self:Activate()
end
function W:Rename(index,title)
    local point=self:Queue()[index]
    if not point then return end
    title=trim(title)
    point.title=title~="" and title or nil
    self:Notify()
end
function W:Move(index,delta)
    local list=self:Queue()
    local to=index+delta
    if not list[index] or not list[to] then return end
    list[index],list[to]=list[to],list[index]
    if index==1 or to==1 then self:Activate(true) else self:Notify() end
end
-- A pin dragged on the map: the waypoint moves there (the active one is set again).
function W:Place(index,mapID,x,y)
    local point=self:Queue()[index]
    if not point or type(mapID)~="number" then return end
    point.mapID,point.x,point.y=mapID,x,y
    if index==1 then self:Activate(true) else self:Notify() end
end
function W:Remove(index)
    local list=self:Queue()
    if not list[index] then return end
    table.remove(list,index)
    if index==1 then
        if list[1] then self:Activate(true) else self:Stop() end
    else self:Notify() end
end
-- Clears Blizzard's waypoint we set (never one somebody else set).
function W:Stop()
    if self.active then
        self.active=nil
        self.setting=true;P.Call("C_Map.ClearUserWaypoint");self.setting=false
    end
    self:Watch();self:Notify()
end

-- Arrival: Blizzard's distance to the navigation target (yards), else ours.
function W:Distance()
    local point=self.active
    if not point then return nil end
    if P.Call("C_SuperTrack.IsSuperTrackingUserWaypoint")==true then
        local distance=P.Call("C_Navigation.GetDistance")
        if type(distance)=="number" and not P.Secret(distance) and distance>0 then return distance end
    end
    local _,distance=P.Navigation:Vector(point)
    return distance
end
function W:Check()
    if not self.active then return end
    local distance=self:Distance()
    if not distance then return end
    self.lastDistance=distance
    if distance<=P:Config().arrival then self:Arrived() end
end
function W:Arrived()
    local list=self:Queue()
    local reached=self.active
    if list[1]==reached then table.remove(list,1) end
    -- A loop (Gather's route editor): the reached point goes to the end again.
    if reached and reached.loop and #list>0 then list[#list+1]=reached end
    self.active=nil
    self.setting=true
    P.Call("C_Map.ClearUserWaypoint")
    self.setting=false
    if list[1] then self:Activate() else P:Print("Waypoint reached.");self:Watch();self:Notify() end
end
-- The event comes a moment after our own change, so the waypoint itself is
-- compared: still ours, nothing to do. Gone right next to it: arrived (the
-- next one follows). Replaced or cleared elsewhere (Ctrl+click on the map,
-- another addon): our queue lets go instead of fighting over it.
function W:Ours(current)
    local point=self.active
    if not (point and type(current)=="table") then return false end
    local position=current.position
    local x,y
    if type(position)=="table" and position.GetXY then x,y=position:GetXY() elseif type(position)=="table" then x,y=position.x,position.y end
    return current.uiMapID==point.mapID and type(x)=="number" and math.abs(x-point.x)<.0005 and math.abs(y-point.y)<.0005
end
function W:Changed()
    if self.setting or not self.active then return end
    local current=P.Call("C_Map.GetUserWaypoint")
    if self:Ours(current) then return end
    if current==nil and self.lastDistance and self.lastDistance<=P:Config().arrival*3 then return self:Arrived() end
    self.active=nil
    P:Config().waypoints={}
    self:Watch();self:Notify()
end
function W:Watch()
    if self.active and not self.ticker then self.ticker=C_Timer.NewTicker(1,function() W:Check() end)
    elseif not self.active and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
function W:Clear()
    local had=self.active~=nil or #self:Queue()>0
    P:Config().waypoints={}
    self:Stop()
    local tomtom=self:TomTom()
    P:Print(tomtom and "TomTom keeps its own waypoints (/way reset)." or (had and "Waypoints cleared." or "No waypoints."))
end
function W:List()
    local list=self:Queue()
    if #list==0 then P:Print(self:TomTom() and "Waypoints are TomTom's (its own list)." or "No waypoints.");return end
    for i,point in ipairs(list) do P:Print(i..". "..(point.title or self:MapName(point.mapID)).." "..P:Format(point.x,point.y)) end
end

-- Comfort: the spot you stand on, the closest queued waypoint.
function W:Here(title)
    local x,y,mapID=P:PlayerPosition()
    if not x then P:Print("No position here (instances hide it).");return false end
    return self:Add({mapID=mapID,x=x,y=y,title=title or "Here"})
end
function W:Closest()
    local best,bestDistance
    for index,point in ipairs(self:Queue()) do
        local _,distance=P.Navigation:Vector(point)
        if distance and (not bestDistance or distance<bestDistance) then best,bestDistance=index,distance end
    end
    if not best then P:Print("No waypoint on this continent.");return false end
    return self:Choose(best)
end
-- Corpse: a waypoint to your body while you run as a ghost (not with TomTom,
-- which brings its own); gone again once you are alive.
function W:Corpse()
    if not P:Config().corpse or self:TomTom() then return end
    local mapID=P.Call("C_Map.GetBestMapForUnit","player")
    if type(mapID)~="number" then return end
    local position=P.Call("C_DeathInfo.GetCorpseMapPosition",mapID)
    if type(position)~="table" and type(position)~="userdata" then return end
    local ok,x,y=pcall(position.GetXY,position)
    if not ok or type(x)~="number" then return end
    self:Add({mapID=mapID,x=x,y=y,title="Corpse",corpse=true},false,true)
end
function W:Alive()
    local list=self:Queue()
    local removed=false
    for i=#list,1,-1 do if list[i].corpse then table.remove(list,i);removed=removed or i==1 end end
    if removed then if list[1] then self:Activate(true) else self:Stop() end end
end
-- Quest objective (Quest package menus): Blizzard's next waypoint for the
-- quest, else its point on your current map.
function W:Quest(questID,title)
    local mapID,x,y=P.Call("C_QuestLog.GetNextWaypoint",questID)
    if type(mapID)~="number" or type(x)~="number" then
        mapID=P.Call("C_Map.GetBestMapForUnit","player")
        local list
        if type(mapID)=="number" then list=P.Call("C_QuestLog.GetQuestsOnMap",mapID) end
        x,y=nil,nil
        if type(list)=="table" then for _,entry in ipairs(list) do if entry.questID==questID then x,y=entry.x,entry.y end end end
    end
    if type(mapID)~="number" or type(x)~="number" then P:Print("No objective position for this quest here.");return false end
    return self:Add({mapID=mapID,x=x,y=y,title=title},false,true)
end

-- Import: one waypoint per line (/way lines, Wowhead lists); returns added,
-- failed lines. Export: /way lines that TomTom and we read back.
function W:Import(text)
    local added,failed=0,{}
    for line in (type(text)=="string" and text or ""):gmatch("[^\r\n]+") do
        if line:match("%S") then
            local point,why=W.Parse(line)
            if point and self:Add(point,true) then added=added+1 else failed[#failed+1]=line..(why and (" ("..why..")") or "") end
        end
    end
    if added>0 and not self:TomTom() and not self.active then self:Activate(true) end
    self:Notify()
    return added,failed
end
function W:Export()
    local lines={}
    for _,point in ipairs(self:Queue()) do
        lines[#lines+1]=string.format("/way #%d %.2f %.2f%s",point.mapID,point.x*100,point.y*100,point.title and (" "..point.title) or "")
    end
    return table.concat(lines,"\n")
end
-- Named sets: the queue saved and loaded again.
function W:SaveSet(name)
    name=trim(name)
    if name=="" or #self:Queue()==0 then return false end
    local copy={}
    for i,point in ipairs(self:Queue()) do if not point.corpse then copy[#copy+1]={mapID=point.mapID,x=point.x,y=point.y,title=point.title,loop=point.loop} end end
    P:Config().sets[name]=copy
    return true
end
function W:LoadSet(name)
    local set=P:Config().sets[name]
    if type(set)~="table" then return false end
    P:Config().waypoints={}
    if self.active then self:Stop() end
    for _,point in ipairs(set) do self:Add({mapID=point.mapID,x=point.x,y=point.y,title=point.title,loop=point.loop},true) end
    if not self:TomTom() then self:Activate() end
    return true
end
function W:DeleteSet(name) P:Config().sets[name]=nil end

-- One entry for /way and /bv way.
local USAGE="/way [#mapID | zone] x y [title]  ·  /way here  ·  /way next  ·  /way list  ·  /way clear"
function W:Command(text)
    text=type(text)=="string" and text or ""
    local word,rest=text:match("^%s*(%a+)%s*(.-)%s*$")
    word=word and word:lower()
    if word=="clear" or word=="reset" then return self:Clear() end
    if word=="list" then if P.WaypointList and not self:TomTom() then return P.WaypointList:Toggle() end return self:List() end
    if word=="here" then return self:Here(rest~="" and rest or nil) end
    if word=="next" then return self:Closest() end
    if text:match("^%s*$") then return self:Here() end
    local point,why=W.Parse(text)
    if not point then P:Print(why and ("Not found: "..why) or ("Usage: "..USAGE));return end
    return self:Add(point)
end
-- /way only when free: TomTom or any other owner keeps it.
function W:RegisterSlash()
    if self.slash or self:TomTom() or self:Claimed() then return false end
    self.slash=true
    _G.SLASH_BVMAPWAY1="/way"
    SlashCmdList=SlashCmdList or {}
    SlashCmdList.BVMAPWAY=function(text) if P:Active() then W:Command(text) else P:Print("The Map module is off (/bv map on).") end end
    return true
end

function W:Enable(context)
    self:RegisterSlash()
    pcall(context.Subscribe,context,"USER_WAYPOINT_UPDATED",function() W:Changed() end)
    pcall(context.Subscribe,context,"PLAYER_ALIVE",function() if P.Call("UnitIsGhost","player") then W:Corpse() end end)
    pcall(context.Subscribe,context,"PLAYER_UNGHOST",function() W:Alive() end)
    -- A queue from the last session continues.
    if #self:Queue()>0 and not self:TomTom() then self:Activate(true) end
    context:Defer(function() if W.ticker then W.ticker:Cancel();W.ticker=nil end;W.active=nil end)
end

local _,P=...
if not P.ready then return end
-- Zone banner on the notification stage (Horizon's zone banner as the model;
-- in the Map package since 2026-10-08, before in Quest):
-- a new zone with its PvP status and quests ("4 quests · 1 ready"), subzones,
-- and "Discovered" with the exploration XP instead of Blizzard's line. Zone and
-- subzone are stage types; while one is on, Blizzard's own zone or subzone
-- text stays hidden, switched off it comes back.
local ns=P.ns
local Z={recent={}}
P.ZoneBanner=Z
local DELAY=.3        -- the map and the exploration message settle first
local REPEAT=60       -- a subzone shown this recently is not shown again (borders)
local PVP_COLOR={sanctuary={.41,.8,.94},friendly={.1,1,.1},hostile={1,.1,.1},contested={1,.7,0},combat={1,.1,.1},arena={1,.1,.1}}
local PVP_TEXT={sanctuary="Sanctuary",contested="Contested territory",combat="Combat zone",arena="Free-for-all PvP"}

if ns.Stage then
    ns.Stage:Register({id="zone",label="Zone",priority=2,hold=4,
        description="A new zone with its PvP status and your quests there. Hides Blizzard's zone text while on. Shown while the Map module is on.",
        sample={title="Hillsbrad Foothills",subtitle="Contested territory · 4 quests · 1 ready",color=PVP_COLOR.contested}})
    ns.Stage:Register({id="subzone",label="Subzone",priority=1,hold=3,
        description="A new area within the zone, with \"Discovered\" and the exploration XP. Hides Blizzard's subzone text while on.",
        sample={title="Tarren Mill",subtitle="Discovered · +420 XP"}})
end

function Z:Ours(id)
    return P:Active() and ns.Stage~=nil and ns.Stage.types[id]~=nil and ns.Stage:TypeConfig(id).enabled==true
end
local function text(path)
    local value=P.Call(path)
    if type(value)~="string" or P.Secret(value) or value=="" then return nil end
    return value
end

-- PvP status of the zone: title colour and a short line.
function Z:PvP()
    local kind,_,faction=P.Call("GetZonePVPInfo")
    if P.Secret(kind) then return nil,nil end
    local line=PVP_TEXT[kind]
    if (kind=="friendly" or kind=="hostile") and type(faction)=="string" and not P.Secret(faction) and faction~="" then line=faction.." territory" end
    return PVP_COLOR[kind],line
end
-- "4 quests · 1 ready" for the quests with a point on the current map.
function Z:Quests()
    -- Only with the Quest module on: it reads the log (Map works without it).
    local quest=ns.Quest
    if not (P:Config().zoneQuests and quest and quest.Active and quest:Active() and quest.Data) then return nil end
    quest:Refresh()
    local count,ready=0,0
    for _,q in ipairs(quest.Data.quests or {}) do
        if q.current then count=count+1;if q.ready then ready=ready+1 end end
    end
    if count==0 then return nil end
    local line=count..(count==1 and " quest" or " quests")
    if ready>0 then line=line.." · "..ready.." ready" end
    return line
end
local function join(...)
    local parts={}
    for i=1,select("#",...) do local part=select(i,...);if part then parts[#parts+1]=part end end
    return #parts>0 and table.concat(parts," · ") or nil
end

-- Exploration: Blizzard's info line carries the area and the XP.
local function pattern(format)
    if type(format)~="string" then return nil end
    return "^"..format:gsub("[%(%)%.%+%-%*%?%[%]%^%$]","%%%0"):gsub("%%%%s","(.+)"):gsub("%%%%d","(%%d+)").."$"
end
function Z.ParseExplored(messageType,message)
    if type(message)~="string" or P.Secret(message) or P.Secret(messageType) then return nil end
    for _,name in ipairs({"ERR_ZONE_EXPLORED_XP","ERR_ZONE_EXPLORED"}) do
        local p=pattern(rawget(_G,name))
        local area,xp
        if p then area,xp=message:match(p) end
        if area then return area,tonumber(xp) end
    end
    local area,xp=message:match("^Discovered:? (.-):? (%d+) experience gained")
    if area then return area,tonumber(xp) end
    area=message:match("^Discovered: (.+)$")
    if area then return area,nil end
    return nil
end
local function discovered(xp) return xp and ("Discovered · +"..(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp).." XP") or "Discovered" end
-- Called for every UI_INFO_MESSAGE (Quest.lua); true when ours replaces it.
function Z:Explored(messageType,message)
    if not P:Config().zoneDiscovered or not (self:Ours("zone") or self:Ours("subzone")) then return false end
    local area,xp=Z.ParseExplored(messageType,message)
    if not area then return false end
    self.explored={area=area,xp=xp,time=GetTime()}
    -- Arrived after our banner: the banner on show (or waiting) gets the line.
    if not self.pending and self.lastType and self.lastTitle==area then
        self:Show(self.lastType,area,discovered(xp),self.lastColor)
    elseif not self.pending then
        self:Show(self:Ours("subzone") and "subzone" or "zone",area,discovered(xp))
    end
    return true
end
local function freshExplore(name)
    local e=Z.explored
    return e and e.area==name and GetTime()-e.time<3 and P:Config().zoneDiscovered
end

function Z:Show(id,title,subtitle,color)
    self.lastType,self.lastTitle,self.lastColor=id,title,color
    pcall(ns.Stage.Show,ns.Stage,id,{title=title,subtitle=subtitle,color=color,key="area"})
end
function Z:ZoneChanged(force)
    local zone=text("GetZoneText") or text("GetRealZoneText")
    local sub=text("GetSubZoneText")
    if not zone then return end
    local same=zone==self.zone
    self.zone,self.sub=zone,sub
    if same and not force then return self:SubzoneChanged() end
    if not self:Ours("zone") then return end
    local color,pvp=self:PvP()
    local line=join(pvp,self:Quests())
    if freshExplore(zone) then line=join(discovered(self.explored.xp),self:Quests()) end
    self:Show("zone",zone,line,color)
end
function Z:SubzoneChanged()
    local zone=text("GetZoneText") or text("GetRealZoneText")
    local sub=text("GetSubZoneText")
    if zone and zone~=self.zone then return self:ZoneChanged() end
    if not sub or sub==self.sub or sub==zone then self.sub=sub;return end
    self.sub=sub
    if not self:Ours("subzone") then return end
    local now=GetTime()
    local explored=freshExplore(sub)
    if not explored and self.recent[sub] and now-self.recent[sub]<REPEAT then return end
    self.recent[sub]=now
    self:Show("subzone",sub,explored and discovered(self.explored.xp) or zone)
end
function Z:Later(fn)
    if self.pending then self.pending:Cancel() end
    self.pending=C_Timer.NewTimer(DELAY,function() Z.pending=nil;fn() end)
end

-- Blizzard's zone and subzone text: hidden on show while our type is on.
function Z:HookBlizzard()
    self.hooked=self.hooked or {}
    for frameName,id in pairs({ZoneTextFrame="zone",SubZoneTextFrame="subzone"}) do
        local frame=rawget(_G,frameName)
        if frame and frame.HookScript and not self.hooked[frame] then
            self.hooked[frame]=true
            frame:HookScript("OnShow",function(own) if Z:Ours(id) then own:Hide() end end)
        end
    end
end

function Z:Enable(context)
    -- "Discovered" lines: through Core's shared info line (Quest filters its
    -- progress lines there too).
    if ns.InfoMessages then
        ns.InfoMessages:Filter("map",function(messageType,message) return Z:Explored(messageType,message) end)
        context:Defer(function() ns.InfoMessages:Release("map") end)
    end
    -- Where we are now is no news: no banner on enable or /reload.
    self.zone=text("GetZoneText") or text("GetRealZoneText")
    self.sub=text("GetSubZoneText")
    self:HookBlizzard()
    pcall(context.Subscribe,context,"ZONE_CHANGED_NEW_AREA",function() Z:Later(function() Z:ZoneChanged() end) end)
    for _,event in ipairs({"ZONE_CHANGED","ZONE_CHANGED_INDOORS"}) do
        pcall(context.Subscribe,context,event,function() if not Z.pending then Z:Later(function() Z:SubzoneChanged() end) end end)
    end
    -- First login and loading screens (instances) show the zone; a reload does not.
    pcall(context.Subscribe,context,"PLAYER_ENTERING_WORLD",function(_,initial,reload)
        if reload then return end
        Z:Later(function() Z:ZoneChanged(initial==true) end)
    end)
    context:Defer(function() if Z.pending then Z.pending:Cancel();Z.pending=nil end end)
end

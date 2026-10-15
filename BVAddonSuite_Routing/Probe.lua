local _,Routing=...
if not Routing.ready then return end
-- /bv route probe (Florian 2026-10-10: "measure my coordinates to the next
-- point while I walk in"; Chemist Cuely in the farthest corner of
-- Undercity as the hardest case). On: twice a second a line with where
-- you are (map, position, subzone), your level three ways (what Routing
-- follows, what the subzone says, what the plan says), the step you are on
-- and how far its end and its drawn line are; for a transition both ends,
-- the time waited and why it is not taken yet. Events (on to a step, a new
-- search, off the way) as they happen; the whole plan when a way starts.
-- Off (the same command): the report to copy. Only reads; changes nothing.
local ns=Routing.ns
local P={lines={}}
Routing.Probe=P
P.EVERY=.5
P.MAX=4000

local function num(v) return type(v)=="number" and string.format("%.1f",v) or "-" end
local function pct(v) return type(v)=="number" and string.format("%.2f",v*100) or "-" end
local function lname(id) return Routing.Level:Name(id) end
-- Your level: on a map with levels, none known is not the ground.
local function current(mapID,id)
    if id~=nil or not mapID then return lname(id) end
    for _,map in ipairs(Routing.Level.Chain(mapID)) do
        if #Routing:ReadLevels(map)>0 then return "? (Ground or unknown)" end
    end
    return lname(id)
end
local function point(p)
    if not p then return "-" end
    return string.format("%s %s,%s [%s]",tostring(p.cont),pct(p.x),pct(p.y),lname(p.level))
end
function P:Add(line)
    local lines=self.lines
    lines[#lines+1]=date("%H:%M:%S").." "..line
    if #lines>P.MAX then table.remove(lines,1) end
end
-- An event from Navigate (on to a step, a new search ...).
function P:Note(text) if self.on then self:Add(">> "..text) end end
-- The plan as it starts.
function P:Plan(goal,steps)
    if not self.on then return end
    self:Add(string.format(">> PLAN to %s at %s",tostring(goal and goal.name),point(goal)))
    for i,step in ipairs(steps or {}) do
        local apart=step.from.cont==step.to.cont and Routing.Navigate.Yards(step.from.cont,step.from.x,step.from.y,step.to.x,step.to.y) or nil
        self:Add(string.format("   %d. %s%s  %s -> %s  %s yd%s",i,step.kind,step.by and step.by.kind and ("/"..step.by.kind) or "",
            point(step.from),point(step.to),num(step.yards or apart),step.path and (", "..#step.path.." points") or ""))
    end
end
-- One reading.
function P:Sample()
    local N=Routing.Navigate
    local mapID,x,y=Routing:Position()
    local cont,cx,cy=nil,nil,nil
    if mapID then cont,cx,cy=Routing:OnContinent(mapID,x,y) end
    local sub=Routing.Call("GetSubZoneText")
    if type(sub)~="string" or Routing.Secret(sub) then sub=nil end
    local cur,cue=Routing.Level:Current(),Routing.Level:Cue()
    local parts={string.format("map %s %s,%s  sub %s  level %s / cue %s",tostring(mapID),pct(x),pct(y),sub~="" and sub or "-",current(mapID,cur),cue and lname(cue) or "-")}
    local step=N.steps and N.steps[N.current]
    if N.busy then parts[#parts+1]="  calculating"
    elseif step and cont then
        parts[#parts+1]=string.format("  step %d/%d %s plan-level %s",N.current,#N.steps,step.kind,lname(step.from.level))
        local to=step.to
        local dTo=to.cont==cont and N.Yards(cont,cx,cy,to.x,to.y) or nil
        parts[#parts+1]="  to-end "..num(dTo)
        if step.kind=="walk" then
            parts[#parts+1]="  off-line "..num(N.Nearest(cont,cx,cy,step.path)).."  off "..tostring(N.off or 0)
            local reach=to.kind=="goal" and N.ARRIVE or to.kind=="door" and N.DOOR or N.REACH
            parts[#parts+1]="  ends at "..reach
        elseif step.kind=="transition" then
            local from=step.from
            local dFrom=from.cont==cont and N.Yards(cont,cx,cy,from.x,from.y) or nil
            local apart=N.Yards(cont,from.x,from.y,to.x,to.y)
            local after,before=N.steps[N.current+1],N.steps[N.current-1]
            parts[#parts+1]=string.format("  from-start %s apart %s waited %s  next-line %s last-line %s",num(dFrom),num(apart),
                N.door and num(GetTime()-N.door) or "-",num(after and N.Nearest(cont,cx,cy,after.path)),num(before and N.Nearest(cont,cx,cy,before.path)))
        end
    elseif not step then parts[#parts+1]="  no way"
    end
    local line=table.concat(parts,"")
    self:Add(line)
    if cont then self:Heights(cont,cx,cy,mapID) end
end

-- Your height from the NPCs near (Routing.Height): each reading a "z" line
-- (the band, how many NPCs, the levels whose height fits it, the game's own
-- height if it ever gives one) and "npc" lines: those used every second
-- reading, a skipped one when its reason is new.
-- A setting's value as text (Florian 2026-10-11: GetCVar gave no value at
-- all, not even nil, and the report broke on it).
function P.CVar(name)
    local value=(Routing.Call("C_CVar.GetCVar",name))
    if value==nil then value=(Routing.Call("GetCVar",name)) end
    if value==nil or Routing.Secret(value) then return "?" end
    return tostring(value)
end
function P.Steps()
    local out={}
    for _,step in ipairs(Routing.Height:Steps()) do out[#out+1]=(step.check and "i" or "#")..step.r end
    return table.concat(out," ")
end
function P:Heights(cont,cx,cy,mapID)
    local H=Routing.Height
    local m=H:Measure(cont,cx,cy)
    local _,_,uz=Routing.Call("UnitPosition","player")
    local zs={}
    for _,p in ipairs(m.set or {}) do
        zs[#zs+1]=string.format("%s..%s",p[1]<-1e8 and "" or string.format("%.0f",p[1]),p[2]>1e8 and "" or string.format("%.0f",p[2]))
    end
    local fits={}
    if m.set then
        for _,level in ipairs(Routing:ReadLevels(mapID)) do
            local z,from=Routing.Level:Height(level.id)
            if H.Fits(m.set,z) then fits[#fits+1]=string.format("%s %d%s",level.name or "?",z,from=="learned" and " (learned)" or from=="set" and " (set)" or "") end
        end
    end
    local result=m.used==0 and "-" or #zs==0 and "none (they contradict)" or table.concat(zs," | ")
    self:Add(string.format("   z %s from %d NPCs (%d units, %d plates)%s%s",result,m.used,m.units,m.plates,
        #fits>0 and ("  levels "..table.concat(fits,", ")) or "",type(uz)=="number" and uz~=0 and string.format("  game z %.1f",uz) or ""))
    self.count=(self.count or 0)+1
    self.why=self.why or {}
    for _,e in ipairs(m.npcs) do
        local text=string.format("   npc %s [%s] %s ranges %s",tostring(e.name),e.unit,e.post and string.format("z %d h %.1f%s",e.post.z,e.h,(e.posts or 0)>1 and (" ("..e.posts.." spots)") or "") or "-",e.sig)
        if not e.why then
            if self.count%2==0 then self:Add(text..string.format("  dist %s-%s dz %.1f-%s",num(e.lo),e.hi and num(e.hi) or "?",e.a,e.b<1e8 and string.format("%.1f",e.b) or "?")) end
        elseif self.why[e.guid]~=e.why then self.why[e.guid]=e.why;self:Add(text.."  skipped: "..e.why) end
    end
    self.lastZ={set=m.set or {},used=m.used,fits=fits}
end
function P:Toggle()
    if self.on then
        self.on=false
        if self.ticker then self.ticker:Cancel();self.ticker=nil end
        local version,build=Routing.Call("GetBuildInfo")
        local head={"BV route probe "..date("%Y-%m-%d %H:%M").."  client "..tostring(version).." build "..tostring(build),
            "Positions in percent of the map named; plan points on the continent map. \">>\": events. level: what Routing follows / cue: the subzone's.",
            "z: your height from the NPCs near (Map Data z; range steps "..P.Steps()..", i interact, # item; y in range, n not, ? unknown); npc: each looked at.",
            "Name plates shown: friendly "..P.CVar("nameplateShowFriends").."  friendly NPCs "..P.CVar("nameplateShowFriendlyNPCs"),""}
        local text=table.concat(head,"\n")..table.concat(self.lines,"\n")
        self.report=text
        if ns.UI and ns.UI.DiagnosticReport then ns.UI:DiagnosticReport("Route probe",text) end
        Routing:Print("Route probe off: "..#self.lines.." lines in the report.")
        return false
    end
    self.on,self.lines=true,{}
    self.why,self.count=nil,0
    Routing.Height:Prepare()
    local N=Routing.Navigate
    if N.steps then self:Plan(N.goal,N.steps) end
    self:Sample()
    self.ticker=C_Timer.NewTicker(P.EVERY,function() P:Sample() end)
    Routing:Print("Route probe on: start or follow a way (/bv route ...); /bv route probe again shows the report.")
    return true
end

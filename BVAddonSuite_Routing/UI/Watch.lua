local _,Routing=...
if not Routing.ready then return end
-- Your level without a way being followed (Florian 2026-10-11: after a
-- reload, or after walking through a city on your own, Routing had
-- forgotten or never noticed the level). Two parts:
--  - On logout and reload (PLAYER_LOGOUT, just before the game writes the
--    saved data) your level is kept with where you stand now, so it counts
--    again after the reload (Level:Recall).
--  - While you are on a map with levels and no way is followed, once a
--    second: a transition you go through sets the level, by the same rules
--    as the way's steps (Navigate:Taken): its other end reached (ends
--    apart), or on one spot (a lift) walked off it along a street of the
--    level it leads to. The ticker runs only on such maps (zone changes
--    start and stop it).
local W={}
Routing.Watch=W
W.EVERY=1
W.EXPIRE=120     -- seconds a transition you stood at stays armed

local frame=CreateFrame("Frame")
W.frame=frame
for _,event in ipairs({"PLAYER_LOGOUT","PLAYER_ENTERING_WORLD","ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA"}) do
    pcall(frame.RegisterEvent,frame,event)
end
frame:SetScript("OnEvent",function(_,event)
    if event=="PLAYER_LOGOUT" then W:Save() else W:Check() end
end)

function W:Save()
    local L=Routing.Level
    L:Current()
    L:Remember()
end
-- On a map with levels: the ticker on; elsewhere off.
function W:Check()
    local mapID=Routing:Position()
    local has=false
    if mapID then
        for _,map in ipairs(Routing.Level.Chain(mapID)) do if #Routing:ReadLevels(map)>0 then has=true end end
    end
    if has and not self.ticker then self.ticker=C_Timer.NewTicker(W.EVERY,function() W:Tick() end)
    elseif not has and self.ticker then self.ticker:Cancel();self.ticker=nil;self.armed=nil end
    return has
end
function W:Stop()
    if self.ticker then self.ticker:Cancel();self.ticker=nil end
    self.armed=nil
end
local function onCont(p)
    local cont,x,y=Routing:OnContinent(p.mapID,p.x,p.y)
    return cont,x,y
end
function W:Tick()
    local N=Routing.Navigate
    -- Your level sure: your height (NPCs near) teaches its height.
    local L=Routing.Level
    local now=L:Current()
    if L.sure and now~=nil and Routing.Height then Routing.Height:Learn(now) end
    if N.steps or N.busy then self.armed=nil;return end
    local mapID,mx,my=Routing:Position()
    if not mapID then return end
    local cont,px,py=Routing:OnContinent(mapID,mx,my)
    if not cont then return end
    local level=now
    local armed=self.armed
    if armed and GetTime()-armed.at>W.EXPIRE then armed=nil;self.armed=nil end
    if not armed then
        -- An end on your level within reach: armed.
        for _,link in ipairs(Routing:ReadLinks()) do
            if type(link.a)=="table" and type(link.b)=="table" and (link.a.level or nil)~=(link.b.level or nil) then
                for _,side in ipairs(link.oneway and {"a"} or {"a","b"}) do
                    local p,q=link[side],link[side=="a" and "b" or "a"]
                    if (p.level or nil)==(level or nil) then
                        local c,x,y=onCont(p)
                        if c==cont and N.Yards(cont,px,py,x,y)<=N.DOOR then
                            self.armed={link=link,from=p,to=q,at=GetTime()}
                            return
                        end
                    end
                end
            end
        end
        return
    end
    local ac,ax,ay=onCont(armed.from)
    local bc,bx,by=onCont(armed.to)
    if not (ac==cont and bc==cont) then return end
    local dFrom,dTo=N.Yards(cont,px,py,ax,ay),N.Yards(cont,px,py,bx,by)
    local apart=N.Yards(cont,ax,ay,bx,by)
    local taken=false
    if apart>=N.SPOT then
        taken=dTo<=N.DOOR and dTo<dFrom
    elseif dFrom>=N.LEAVE then
        -- Off a lift: walking on a street of the level it leads to, none of
        -- the one it came from as near.
        local best,mine
        for _,cand in ipairs(N:Candidates(cont,px,py)) do
            if (cand.level or nil)==(armed.to.level or nil) then best=cand.d end
            if (cand.level or nil)==(armed.from.level or nil) then mine=cand.d end
        end
        taken=best~=nil and best<=N.UNSURE and (not mine or mine>best+N.UNSURE)
    end
    -- Walked on past it: no longer armed.
    if not taken and dFrom>N.REACH then self.armed=nil;return end
    -- Your height says you are still where it starts (Florian's probe
    -- 2026-10-11: passing a transition's end in the Trade Quarter set the
    -- entrance though the NPCs near told First Level): not taken.
    local H=Routing.Height
    -- Florian 2026-10-11: also when it fits no level known (out of
    -- Undercity: First Level taken for the entrance high above).
    if taken and H and armed.to.level~=nil and H:FitsLevel(armed.to.level,cont,px,py)==false then
        self.armed=nil
        local probe=Routing.Probe
        if probe and probe.on then probe:Note("transition to "..L:Name(armed.to.level).." not taken: your height does not fit it") end
        return
    end
    if taken then
        L:Set(armed.to.level)
        self.armed=nil
        local probe=Routing.Probe
        if probe and probe.on then probe:Note("level by a transition taken on your own: "..L:Name(armed.to.level)) end
    end
end

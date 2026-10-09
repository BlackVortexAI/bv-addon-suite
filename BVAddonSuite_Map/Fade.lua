local _,P=...
if not P.ready then return end
-- Transparency while moving: the open map fades to the chosen opacity while
-- you walk and comes back when you stop or point at it. Movement events
-- flicker in bursts (probe 2026-10-07), so both directions wait 0.25 s and
-- check again. Scope: everything, the map without the quest log beside it, or
-- only the quest log. Blizzard's own "map fade" setting wins: while it is on,
-- ours stays off. Blizzard's movement fader also sets WorldMapFrame's own alpha
-- whenever you start walking (Florian 2026-10-08: faded, then full again at
-- once), so ours never touches that frame: it fades the parts inside it.
local ns=P.ns
local F={alpha=1}
P.Fade=F
local DEBOUNCE,STEP=.25,.03

function F:BlizzardFades() return P.Call("GetCVarBool","mapFade")==true end
function F:Panes()
    local quest=ns.Quest
    return quest and quest.Panes and quest.Panes.frame or nil
end
-- The frames whose alpha the scope covers.
function F:Regions()
    local map=P:WorldMap()
    if not map then return {} end
    local scope=P:Config().fadeScope
    local panes=self:Panes()
    if scope=="panes" then return panes and {panes} or {} end
    local out={}
    for _,child in ipairs({map:GetChildren()}) do if scope=="all" or child~=panes then out[#out+1]=child end end
    for _,region in ipairs({map:GetRegions()}) do out[#out+1]=region end
    return out
end
function F:Wanted()
    local c=P:Config()
    local map=P:WorldMap()
    if not (P:Active() and c.fade and self.moving and map and map:IsShown()) or self:BlizzardFades() then return 1 end
    if c.fadeMouseover and map:IsMouseOver() then return 1 end
    return c.fadeOpacity/100
end
-- Glides to the wanted alpha in small steps (tickers only, no per-frame scripts).
function F:Apply(instant)
    local target=self:Wanted()
    if self.ticker then self.ticker:Cancel();self.ticker=nil end
    local regions=self:Regions()
    -- Regions the scope no longer covers go back to full.
    for region in pairs(self.touched or {}) do
        local still=false
        for _,r in ipairs(regions) do if r==region then still=true end end
        if not still then region:SetAlpha(1);self.touched[region]=nil end
    end
    self.touched=self.touched or {}
    local function set(value)
        F.alpha=value
        for _,region in ipairs(regions) do region:SetAlpha(value);F.touched[region]=value<1 or nil end
    end
    local steps=math.max(1,math.floor(P:Config().fadeTime/10/STEP+.5))
    if instant or math.abs(target-self.alpha)<.01 then set(target);self:Watch();return end
    local from,step=self.alpha,0
    self.ticker=C_Timer.NewTicker(STEP,function()
        step=step+1
        set(from+(target-from)*math.min(1,step/steps))
        if step>=steps then F.ticker:Cancel();F.ticker=nil;F:Watch() end
    end,steps)
end
-- While faded and "full on mouseover" is on: a light check whether the mouse
-- is over the map (ten times a second, only then).
function F:Watch()
    local watch=self.moving and P:Config().fadeMouseover and P:Config().fade and P:Active()
    local map=P:WorldMap()
    watch=watch and map and map:IsShown()
    if watch and not self.watcher then
        self.watcher=C_Timer.NewTicker(.1,function()
            local wanted=F:Wanted()
            if math.abs(wanted-F.alpha)>.01 and not F.ticker then F:Apply() end
        end)
    elseif not watch and self.watcher then self.watcher:Cancel();self.watcher=nil end
end
function F:Moving(moving)
    if self.debounce then self.debounce:Cancel() end
    self.debounce=C_Timer.NewTimer(DEBOUNCE,function()
        F.debounce=nil
        local now=P.Call("IsPlayerMoving")
        if now==nil then now=moving end
        if now==F.moving then return end
        F.moving=now==true
        F:Apply()
    end)
end
function F:Reset()
    for _,key in ipairs({"ticker","watcher","debounce"}) do if self[key] then self[key]:Cancel();self[key]=nil end end
    for region in pairs(self.touched or {}) do region:SetAlpha(1) end
    self.touched={};self.alpha=1
end

function F:Enable(context)
    self.moving=P.Call("IsPlayerMoving")==true
    pcall(context.Subscribe,context,"PLAYER_STARTED_MOVING",function() F:Moving(true) end)
    pcall(context.Subscribe,context,"PLAYER_STOPPED_MOVING",function() F:Moving(false) end)
    local map=P:WorldMap()
    if map and not self.hooked then
        self.hooked=true
        map:HookScript("OnShow",function() if P:Active() then F:Apply(true) end end)
        map:HookScript("OnHide",function() if P:Active() then F:Reset() end end)
    end
    context:Defer(function() F:Reset() end)
end

-- Timed screen notes. Deliberately outside the layout system: eight fixed
-- screen positions, never protected, safe in combat. Presentation lives in
-- UI:ToastFrame; this module owns timing, stacking and run ownership.
local _,A=...
if A.blocked then return end
local G=A.G
local Toasts={owners={},stacks={},pool={},margin=24,gap=8,width=300,limit=5};A.Toasts=Toasts
Toasts.positions={"top_left","top","top_right","right","bottom_right","bottom","bottom_left","left"}
Toasts.labels={top_left="Top left corner",top="Top edge",top_right="Top right corner",right="Right edge",
    bottom_right="Bottom right corner",bottom="Bottom edge",bottom_left="Bottom left corner",left="Left edge"}
-- point, x/y sign towards the screen interior, stacking direction (-1 down, 1 up)
local anchors={top_left={"TOPLEFT",1,-1,-1},top={"TOP",0,-1,-1},top_right={"TOPRIGHT",-1,-1,-1},right={"RIGHT",-1,0,-1},
    bottom_right={"BOTTOMRIGHT",-1,1,1},bottom={"BOTTOM",0,1,1},bottom_left={"BOTTOMLEFT",1,1,1},left={"LEFT",1,0,-1}}
function Toasts.Valid(c)
    if type(c)~="table" or not anchors[c.position] then return false,"Choose one of the eight screen positions" end
    if not G.Number(c.opacity) or c.opacity<.1 or c.opacity>1 then return false,"Opacity must be 10..100%" end
    if not G.Number(c.duration) or c.duration<.5 or c.duration>60 then return false,"Duration must be 0.5..60 seconds" end
    if type(c.fade)~="boolean" then return false,"Fade must be on or off" end
    if not G.Number(c.fadeDuration) or c.fadeDuration<.1 or c.fadeDuration>3 then return false,"Fade time must be 0.1..3 seconds" end
    if c.dismissible~=nil and type(c.dismissible)~="boolean" then return false,"Click to dismiss must be on or off" end
    if c.symbolPosition~=nil and not ({left=true,right=true,above=true,below=true})[c.symbolPosition] then return false,"Choose a symbol position" end
    if c.symbolScale~=nil and (not G.Number(c.symbolScale) or c.symbolScale<.5 or c.symbolScale>4) then return false,"Symbol size must be 0.5..4 x font size" end
    return true
end
-- Total visible time: optional fade in + hold + optional fade out.
function Toasts.Lifetime(c) local fade=c.fade and c.fadeDuration or 0;return fade+c.duration+fade end
local function layout(position)
    local stack=Toasts.stacks[position];if not stack then return end
    local a=anchors[position];local offset=0
    -- Newest sits at the screen edge; older notes move towards the interior.
    for i=#stack,1,-1 do
        local f=stack[i].frame;f:ClearAllPoints()
        f:SetPoint(a[1],UIParent,a[1],a[2]*Toasts.margin,a[3]*Toasts.margin+a[4]*offset)
        offset=offset+f:GetHeight()+Toasts.gap
    end
end
-- reason: "expired", "dismissed", "dropped" (stack limit) or "released" (run stop).
local function remove(t,reason)
    if t.removed then return end;t.removed=true
    local stack=Toasts.stacks[t.position]
    for i,entry in ipairs(stack or {}) do if entry==t then table.remove(stack,i);break end end
    local owned=Toasts.owners[t.run]
    if owned then owned[t]=nil;if not next(owned) then Toasts.owners[t.run]=nil end end
    if t.timer then t.timer:Cancel();t.timer=nil end
    local closed=t.onClose;t.onClose=nil
    t.fade:Stop();t.frame:EnableMouse(false);t.frame:Hide();t.run=nil;t.config=nil;Toasts.pool[#Toasts.pool+1]=t
    layout(t.position)
    if closed and reason~="released" then closed(reason=="dismissed") end
end
local function acquire()
    local t=table.remove(Toasts.pool);if t then return t end
    t=BVAddonSuiteCore.UI:ToastFrame(Toasts.width)
    t.frame:SetScript("OnMouseUp",function() if t.config and t.config.dismissible then remove(t,"dismissed") end end)
    return t
end
-- onClose(dismissed) runs once when the note expires, is clicked away or is
-- dropped by the stack limit; never when its run is released.
function Toasts.Show(run,config,text,icon,onClose,symbol)
    local ok,why=Toasts.Valid(config);if not ok then return false,why end
    if text==nil then return false,"unavailable" end
    local t=acquire();t.removed=nil;t.run=run;t.position=config.position;t.onClose=onClose
    local c={position=config.position,opacity=config.opacity,duration=config.duration,fade=config.fade,fadeDuration=config.fadeDuration,dismissible=config.dismissible==true}
    t.config=c
    -- Protected text reaches only the native setter; readable text is escaped.
    local glyph=symbol and {name=symbol.name,color=symbol.color,position=config.symbolPosition or "left",scale=config.symbolScale or 1}
    t:Present(G.IsSecret(text) and text or (tostring(text):gsub("|","||")),icon,glyph)
    -- Click-through unless explicitly dismissible.
    t.frame:EnableMouse(c.dismissible)
    t.frame:SetAlpha(c.opacity);t.fade:Stop()
    if c.fade then
        t.fadeIn:SetFromAlpha(0);t.fadeIn:SetToAlpha(c.opacity);t.fadeIn:SetDuration(c.fadeDuration);t.fadeIn:SetStartDelay(0)
        t.fadeOut:SetFromAlpha(c.opacity);t.fadeOut:SetToAlpha(0);t.fadeOut:SetDuration(c.fadeDuration);t.fadeOut:SetStartDelay(c.duration)
        t.frame:SetAlpha(0)
    end
    t.frame:Show();if c.fade then t.fade:Play() end
    t.timer=C_Timer.NewTimer(Toasts.Lifetime(c),function() t.timer=nil;remove(t,"expired") end)
    local stack=Toasts.stacks[c.position] or {};Toasts.stacks[c.position]=stack
    stack[#stack+1]=t
    local owned=Toasts.owners[run] or {};Toasts.owners[run]=owned;owned[t]=true
    while #stack>Toasts.limit do remove(stack[1],"dropped") end
    layout(c.position)
    return true,"shown"
end
function Toasts.Release(run)
    local owned=Toasts.owners[run];if not owned then return end
    local list={};for t in pairs(owned) do list[#list+1]=t end
    for _,t in ipairs(list) do remove(t,"released") end
    Toasts.owners[run]=nil
end

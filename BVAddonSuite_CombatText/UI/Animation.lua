local _,L=...
if not L.ready then return end
-- Keyframe animation on Blizzard AnimationGroups (no per-frame script). A text frame
-- owns SEGMENTS segments, each a Translation, Scale and Alpha with the same
-- order and the segment's smoothing; the client interpolates. Keyframes:
-- {t=0..1, x, y (fractions of the distance), s (scale), a (alpha), ease}.
-- Unused segments run with a tiny duration and no change.
local A={SEGMENTS=4,TINY=.001}
L.Animation=A

local EASE={NONE=true,IN=true,OUT=true,IN_OUT=true}
function A:Attach(frame)
    local group=frame:CreateAnimationGroup()
    group:SetLooping("NONE")
    local segments={}
    for i=1,self.SEGMENTS do
        local s={move=group:CreateAnimation("Translation"),scale=group:CreateAnimation("Scale"),alpha=group:CreateAnimation("Alpha")}
        for _,anim in pairs(s) do anim:SetOrder(i) end
        s.scale:SetOrigin("CENTER",0,0)
        segments[i]=s
    end
    frame.animGroup,frame.animSegments=group,segments
    return group
end

-- Presets. jitter: -1..1 picked per text (fountain/rain spread sideways).
A.PRESETS={
    up=function() return {
        {t=0,x=0,y=0,s=1,a=0},{t=.1,x=0,y=.1,s=1,a=1,ease="OUT"},{t=.75,x=0,y=.75,s=1,a=1},{t=1,x=0,y=1,s=1,a=0,ease="IN"}} end,
    down=function() return {
        {t=0,x=0,y=0,s=1,a=0},{t=.1,x=0,y=-.1,s=1,a=1,ease="OUT"},{t=.75,x=0,y=-.75,s=1,a=1},{t=1,x=0,y=-1,s=1,a=0,ease="IN"}} end,
    fountain=function(j) local x=(j>=0 and 1 or -1)*(.25+math.abs(j)*.35);return {
        {t=0,x=0,y=0,s=1,a=0},{t=.12,x=x*.2,y=.3,s=1,a=1,ease="OUT"},{t=.45,x=x*.55,y=.5,s=1,a=1,ease="OUT"},{t=1,x=x,y=-.15,s=1,a=0,ease="IN"}} end,
    rain=function(j) local x=j*.5;return {
        {t=0,x=x,y=.6,s=1,a=0},{t=.12,x=x,y=.5,s=1,a=1},{t=.7,x=x,y=-.1,s=1,a=1,ease="IN"},{t=1,x=x,y=-.4,s=1,a=0}} end,
    pop=function() return {
        {t=0,x=0,y=0,s=.4,a=0},{t=.1,x=0,y=0,s=1.35,a=1,ease="OUT"},{t=.25,x=0,y=0,s=1,a=1,ease="IN_OUT"},{t=1,x=0,y=.35,s=1,a=0,ease="IN"}} end,
}
-- Keyframes for a style: a preset, or custom keys (custom animations).
-- Always a copy: mirror flips x and/or y, crits start with a pop scale.
function A:Keys(style,crit,jitter,custom)
    local keys=custom
    if type(keys)~="table" or #keys<2 then keys=(self.PRESETS[style.animation] or self.PRESETS.up)(jitter or 0) end
    local mx=style.mirror=="x" or style.mirror=="xy"
    local my=style.mirror=="y" or style.mirror=="xy"
    local copy={}
    for i,k in ipairs(keys) do
        copy[i]={t=k.t,x=(k.x or 0)*(mx and -1 or 1),y=(k.y or 0)*(my and -1 or 1),s=k.s,a=k.a,ease=k.ease}
    end
    if crit and style.animation~="pop" then
        copy[1].s=(copy[1].s or 1)*1.6;copy[2].ease=copy[2].ease or "OUT"
    end
    return copy
end
-- Custom animation keys from saved data: 2..5 points, time 0 to 1 in order,
-- values in range. fallback: keys used when nothing usable is saved.
A.MAX_POINTS=5
local function clamp(v,low,high,default) if type(v)~="number" or v~=v then v=default end;return math.max(low,math.min(high,v)) end
function A.CleanKeys(keys,fallback)
    if type(keys)~="table" or #keys<2 then keys=fallback end
    local out={}
    for i=1,math.min(#keys,A.MAX_POINTS) do
        local k=type(keys[i])=="table" and keys[i] or {}
        out[i]={t=clamp(k.t,0,1,(i-1)/(#keys-1)),x=clamp(k.x,-3,3,0),y=clamp(k.y,-3,3,0),s=clamp(k.s,.1,3,1),a=clamp(k.a,0,1,1),
            ease=(i>1 and EASE[k.ease]) and k.ease or "NONE"}
    end
    out[1].t=0;out[#out].t=1
    for i=2,#out do if out[i].t<out[i-1].t then out[i].t=out[i-1].t end end
    return out
end
-- Adds or removes points; new ones split the last segment.
function A.Resize(keys,count)
    count=math.max(2,math.min(A.MAX_POINTS,count))
    while #keys<count do
        local last,before=keys[#keys],keys[#keys-1]
        table.insert(keys,#keys,{t=(before.t+last.t)/2,x=((before.x or 0)+(last.x or 0))/2,y=((before.y or 0)+(last.y or 0))/2,
            s=((before.s or 1)+(last.s or 1))/2,a=((before.a or 1)+(last.a or 1))/2,ease=last.ease})
    end
    while #keys>count do table.remove(keys,#keys-1) end
    return keys
end
-- Same easing curves as the client's smoothing, for positions moved in Lua.
local CURVES={
    NONE=function(p) return p end,
    IN=function(p) return p*p end,
    OUT=function(p) return 1-(1-p)*(1-p) end,
    IN_OUT=function(p) if p<.5 then return 2*p*p end;return 1-2*(1-p)*(1-p) end,
}
-- Position (fractions of the distance) at progress 0..1 through the keys.
function A:Offset(keys,progress)
    if progress<=0 then return keys[1].x or 0,keys[1].y or 0 end
    local last=keys[math.min(#keys,self.SEGMENTS+1)]
    if progress>=1 then return last.x or 0,last.y or 0 end
    for i=1,math.min(#keys-1,self.SEGMENTS) do
        local from,to=keys[i],keys[i+1]
        local t0,t1=from.t or 0,to.t or 1
        if progress<=t1 then
            local p=t1>t0 and (progress-t0)/(t1-t0) or 1
            p=(CURVES[to.ease] or CURVES.NONE)(math.max(0,math.min(1,p)))
            return (from.x or 0)+((to.x or 0)-(from.x or 0))*p,(from.y or 0)+((to.y or 0)-(from.y or 0))*p
        end
    end
    return last.x or 0,last.y or 0
end
-- Plays keyframes on a frame over duration seconds; distance scales x/y.
-- still: no Translation (the caller moves the frame, see Display nameplates).
function A:Play(frame,keys,duration,distance,still)
    local group,segments=frame.animGroup,frame.animSegments
    group:Stop()
    local count=math.min(#keys-1,self.SEGMENTS)
    local first=keys[1]
    frame:SetAlpha(first.a or 1)
    for i=1,self.SEGMENTS do
        local s=segments[i]
        local from,to=keys[i],keys[i+1]
        if i<=count then
            local length=math.max(self.TINY,((to.t or 1)-(from.t or 0))*duration)
            local ease=EASE[to.ease] and to.ease or "NONE"
            if still then s.move:SetOffset(0,0)
            else s.move:SetOffset(((to.x or 0)-(from.x or 0))*distance,((to.y or 0)-(from.y or 0))*distance) end
            local fs,ts=math.max(.01,from.s or 1),math.max(.01,to.s or 1)
            -- Finished scale segments stay applied, so each one scales relative to the last.
            s.scale:SetScaleFrom(i==1 and fs or 1,i==1 and fs or 1)
            s.scale:SetScaleTo(i==1 and ts or ts/fs,i==1 and ts or ts/fs)
            s.alpha:SetFromAlpha(from.a or 1);s.alpha:SetToAlpha(to.a or 1)
            for _,anim in pairs(s) do anim:SetDuration(length);anim:SetSmoothing(ease) end
        else
            local a=keys[count+1].a or 1
            s.move:SetOffset(0,0);s.scale:SetScaleFrom(1,1);s.scale:SetScaleTo(1,1)
            s.alpha:SetFromAlpha(a);s.alpha:SetToAlpha(a)
            for _,anim in pairs(s) do anim:SetDuration(self.TINY);anim:SetSmoothing("NONE") end
        end
    end
    group:Play()
end

local _,P=...
if not P.ready then return end
-- Extra zoom (Florian 2026-10-09): closer than Blizzard allows, on
-- Blizzard's map and on our terrain map alike (both are the same canvas).
-- The map builds its zoom levels for each map (CreateZoomLevels, from the
-- map's art layers); after that, levels beyond the closest one are added.
-- The art only grows, so it gets softer: 2x is fine, 4x clearly blurred.
-- A continent on the seamless map (UI/Seamless) gets its own levels down
-- to the terrain tiles' size instead. Our levels carry bv=true, so a
-- second pass never doubles them.
-- Our levels are not Blizzard's own: read by the map's code in combat they
-- block a protected call (Florian 2026-10-09: ADDON_ACTION_BLOCKED,
-- SetPassThroughButtons, opening the map in combat). So none in combat: the
-- levels go when combat starts and come back after it.
local Z={}
P.Zoom=Z
Z.STEPS={x2={1.5,2},x4={1.5,2,3,4}}
function Z:Scroll()
    local map=P:WorldMap()
    return map,map and map.ScrollContainer
end
function Z.Available()
    local _,scroll=Z:Scroll()
    return scroll and type(scroll.CreateZoomLevels)=="function" or false
end
-- Ours out of the list (Blizzard's stay untouched).
local function strip(scroll)
    local levels=scroll.zoomLevels
    if type(levels)~="table" then return end
    for i=#levels,1,-1 do if type(levels[i])=="table" and levels[i].bv then levels[i]=nil end end
    scroll.bvExtra=nil
end
-- After Blizzard built the levels: ours on top of the closest one.
function Z:Extend(scroll)
    if InCombatLockdown and InCombatLockdown() then return end
    strip(scroll)
    local steps=P:Active() and self.STEPS[P:Config().extraZoom]
    local levels=scroll.zoomLevels
    if not (P:Active() and type(levels)=="table" and #levels>0) then return end
    local last=levels[#levels]
    if type(last)~="table" or type(last.scale)~="number" then return end
    -- A continent on the seamless map: levels down to the tiles' own size.
    local seamless=P.Seamless and P.Seamless:Levels(scroll,last.scale)
    if seamless then
        scroll.bvExtra=#levels
        for _,scale in ipairs(seamless) do levels[#levels+1]={scale=scale,layerIndex=last.layerIndex,bv=true} end
        return
    end
    if not steps then return end
    scroll.bvExtra=#levels
    for _,factor in ipairs(steps) do levels[#levels+1]={scale=last.scale*factor,layerIndex=last.layerIndex,bv=true} end
end
-- Ours are there (the map's own rebuild may have gone past the hook).
function Z:Ensure(scroll)
    local levels=scroll and scroll.zoomLevels
    if type(levels)~="table" or #levels==0 then return end
    local last=levels[#levels]
    if type(last)=="table" and last.bv then return end
    self:Extend(scroll)
end
-- Combat starts: our levels out again (Blizzard's stay untouched).
function Z:Strip()
    local _,scroll=self:Scroll()
    if scroll then strip(scroll) end
end
-- Combat over: ours again on the levels the map has now.
function Z:Restore()
    local _,scroll=self:Scroll()
    if scroll and not scroll.bvExtra and type(scroll.zoomLevels)=="table" then self:Extend(scroll) end
end
-- A changed setting: the open map builds its levels again; a zoom past the
-- new limit comes back to it.
function Z:Apply()
    local map,scroll=self:Scroll()
    if not (map and self.Available()) then return end
    if not self.hooked then
        self.hooked=true
        hooksecurefunc(scroll,"CreateZoomLevels",function(container) Z:Extend(container) end)
    end
    local want=P:Active() and P:Config().extraZoom or "off"
    if P.Seamless and P.Seamless:On() then want=want..":seamless" end
    if P:Active() and (P:Config().blend or 0)>0 then want=want..":blend" end
    if want==self.applied then return end
    self.applied=want
    if InCombatLockdown and InCombatLockdown() then return end
    if not (map:IsShown() and scroll.zoomLevels) then return end
    if not pcall(scroll.CreateZoomLevels,scroll) then return end
    if scroll.GetCanvasScale and scroll.GetScaleForMaxZoom and scroll.InstantPanAndZoom then
        local ok,current=pcall(scroll.GetCanvasScale,scroll)
        local okMax,max=pcall(scroll.GetScaleForMaxZoom,scroll)
        if ok and okMax and current>max then
            local h=scroll.GetNormalizedHorizontalScroll and scroll:GetNormalizedHorizontalScroll() or .5
            local v=scroll.GetNormalizedVerticalScroll and scroll:GetNormalizedVerticalScroll() or .5
            pcall(scroll.InstantPanAndZoom,scroll,max,h,v)
        end
    end
end
function Z:Enable(context)
    self.applied=nil
    self:Apply()
    pcall(context.Subscribe,context,"PLAYER_REGEN_DISABLED",function() Z:Strip() end)
    pcall(context.Subscribe,context,"PLAYER_REGEN_ENABLED",function() Z:Restore() end)
    context:Defer(function() Z:Strip() end)
end

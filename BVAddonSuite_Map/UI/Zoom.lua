local _,P=...
if not P.ready then return end
-- Extra zoom (Florian 2026-10-09): closer than Blizzard allows, on
-- Blizzard's map and on our terrain map alike (both are the same canvas).
-- The map builds its zoom levels for each map (CreateZoomLevels, from the
-- map's art layers); after that, levels beyond the closest one are added.
-- The art only grows, so it gets softer: 2x is fine, 4x clearly blurred.
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
-- After Blizzard built the levels: ours on top of the closest one.
function Z:Extend(scroll)
    local steps=P:Active() and self.STEPS[P:Config().extraZoom]
    local levels=scroll.zoomLevels
    if not (steps and type(levels)=="table" and #levels>0) then return end
    local last=levels[#levels]
    if type(last)~="table" or type(last.scale)~="number" then return end
    for _,factor in ipairs(steps) do levels[#levels+1]={scale=last.scale*factor,layerIndex=last.layerIndex} end
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
    if want==self.applied then return end
    self.applied=want
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
end

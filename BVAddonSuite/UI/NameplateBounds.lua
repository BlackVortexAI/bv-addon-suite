-- Experimental (roadmap P2d follow-up, opt-in): include BV attachments in
-- Blizzard's nameplate stacking. One managed bounds frame per native plate
-- covers the plate plus the readable rectangles of BV views attached to it and
-- is registered with NamePlateFrame:SetStackingBoundsFrame. Recomputed only
-- when an attachment changes (coalesced to the next frame), never per frame.
-- The client offers no getter for the previous bounds frame: when the last BV
-- view leaves a plate or the option is turned off, the bounds frame shrinks
-- to the plate itself instead of restoring an unknown previous owner.
local _,ns=...
local V=ns.GraphValues
local NB={enabled=false,plates={},views={},frames={},pending={},stats={registered=0,failed=0}};ns.NameplateBounds=NB
local offsets={CENTER={0,0},TOP={0,1},BOTTOM={0,-1},LEFT={-1,0},RIGHT={1,0},TOPLEFT={-1,1},TOPRIGHT={1,1},BOTTOMLEFT={-1,-1},BOTTOMRIGHT={1,-1}}
local function number(v) return not V.IsSecret(v) and type(v)=="number" and v==v and math.abs(v)<100000 and v or nil end
local function plateSize(plate)
    local ok,w,h=pcall(function() return plate:GetWidth(),plate:GetHeight() end)
    if not ok then return end
    w,h=number(w),number(h)
    if w and h and w>0 and h>0 then return w,h end
end
-- Union of the plate and its tracked views, relative to the plate centre.
function NB.Union(w,h,geometries)
    local l,r,b,t=-w/2,w/2,-h/2,h/2
    for _,g in ipairs(geometries) do
        local o=offsets[g.point]
        if o and number(g.x) and number(g.y) and number(g.width) and number(g.height) then
            local cx,cy=o[1]*w/2+g.x,o[2]*h/2+g.y
            l=math.min(l,cx-g.width/2);r=math.max(r,cx+g.width/2);b=math.min(b,cy-g.height/2);t=math.max(t,cy+g.height/2)
        end
    end
    return (l+r)/2,(b+t)/2,r-l,t-b
end
local function apply(plate)
    NB.pending[plate]=nil
    local w,h=plateSize(plate);if not w then return end
    local geometries={}
    if NB.enabled then for view in pairs(NB.plates[plate] or {}) do
        if view.nativeAnchor==plate and view.nativeGeometry then geometries[#geometries+1]=view.nativeGeometry end
    end end
    local frame=NB.frames[plate]
    if not frame then
        if #geometries==0 then return end -- never touch plates BV has not claimed
        frame=CreateFrame("Frame",nil,plate);frame:EnableMouse(false);NB.frames[plate]=frame
    end
    local cx,cy,fw,fh=NB.Union(w,h,geometries)
    local ok=pcall(function()
        frame:ClearAllPoints();frame:SetPoint("CENTER",plate,"CENTER",cx,cy);frame:SetSize(fw,fh)
        if frame.registered~=true then
            assert(type(plate.SetStackingBoundsFrame)=="function","unsupported")
            plate:SetStackingBoundsFrame(frame);frame.registered=true
        end
    end)
    if ok then NB.stats.registered=NB.stats.registered+1 else NB.stats.failed=NB.stats.failed+1 end
end
local function schedule(plate)
    if not plate or NB.pending[plate] then return end
    NB.pending[plate]=true
    C_Timer.NewTimer(0,function() if NB.pending[plate] then apply(plate) end end)
end
-- Called by the nameplate attachment boundary after a successful anchor.
function NB:Track(view,plate)
    local old=self.views[view]
    if old==plate and not self.enabled then return end
    if old and old~=plate then self:Untrack(view) end
    self.views[view]=plate;self.plates[plate]=self.plates[plate] or {};self.plates[plate][view]=true
    if self.enabled then schedule(plate) end
end
function NB:Untrack(view)
    local plate=self.views[view];if not plate then return end
    self.views[view]=nil;if self.plates[plate] then self.plates[plate][view]=nil end
    if self.enabled or self.frames[plate] then schedule(plate) end
end
function NB:SetEnabled(value)
    value=value==true;if self.enabled==value then return end
    self.enabled=value
    for plate in pairs(self.plates) do schedule(plate) end
    for plate in pairs(self.frames) do schedule(plate) end
end

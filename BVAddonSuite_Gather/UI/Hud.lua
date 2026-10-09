local _,G=...
if not G.ready then return end
-- Gather HUD (Florian 2026-10-09, like FarmHud: the real minimap, because
-- its yellow dots of Find Herbs / Find Minerals are what matters). Blizzard's
-- minimap goes onto a screen-filling frame in the middle, larger and see-
-- through, the mouse passes through it, it turns with you and shows its
-- widest view; its other buttons (addon icons and the like) are hidden.
-- Everything it had (parent, points, size, scale, alpha, mouse, zoom,
-- rotation, the shown children) is put back exactly when the HUD closes;
-- the minimap's mask (its shape, maybe from your interface package) is
-- never touched. Our pins (nodes, route) are on the minimap and come along.
local ns=G.ns
local H={}
G.Hud=H

function H:On() return self.saved~=nil end
function H:Frame()
    if self.frame then return self.frame end
    local f=CreateFrame("Frame","BVGatherHud",UIParent)
    f:SetAllPoints(UIParent);f:SetFrameStrata("BACKGROUND");f:EnableMouse(false);f:Hide()
    -- A button ends it (Florian 2026-10-09): quiet, clearer under the mouse.
    ns.UI:WithStyle(G:Style(),function()
        f.close=ns.UI:Button(UIParent,"Close HUD",96,function() H:Hide() end,"ghost")
        f.close:SetFrameStrata("HIGH");f.close:SetAlpha(.45);f.close:Hide()
        f.close:HookScript("OnEnter",function(self) self:SetAlpha(1) end)
        f.close:HookScript("OnLeave",function(self) self:SetAlpha(.45) end)
        -- Compass letters at the edge (north a little red).
        f.compass={}
        for _,d in ipairs({{"N",0,1},{"E",1,0},{"S",0,-1},{"W",-1,0}}) do
            local l=ns.UI:Label(f,d[1],15,"text",true)
            if l.SetShadowOffset then l:SetShadowOffset(1,-1);l:SetShadowColor(0,0,0,1) end
            if d[1]=="N" then l:SetTextColor(1,.4,.35,1) end
            l.east,l.north=d[2],d[3];l:Hide()
            f.compass[#f.compass+1]=l
        end
    end)
    self.frame=f
    return f
end
-- Others (the interface package, Blizzard's minimap layout) may set the
-- minimap's place or size again: while the HUD is open it goes back.
function H:Place()
    local minimap=rawget(_G,"Minimap")
    if not (self.saved and minimap) or self.placing then return end
    self.placing=true
    local size=math.floor(UIParent:GetHeight()*G:Config().hudSize/100)
    minimap:ClearAllPoints();minimap:SetPoint("CENTER",self.frame,"CENTER",0,0)
    minimap:SetSize(size,size)
    local close=self.frame.close
    -- Fixed at the top of the screen (under the HUD it hid behind the bars).
    close:ClearAllPoints();close:SetPoint("TOP",UIParent,"TOP",0,-90);close:Show()
    self.placing=nil
end
function H:Hook(minimap)
    if self.hooked then return end
    self.hooked=true
    for _,method in ipairs({"SetPoint","SetSize","SetWidth","SetHeight","SetAllPoints"}) do
        if type(minimap[method])=="function" then
            hooksecurefunc(minimap,method,function() if H.saved and not H.placing then H:Place() end end)
        end
    end
    if type(minimap.SetAlpha)=="function" then
        hooksecurefunc(minimap,"SetAlpha",function() if H.saved and not H.placing then H:Fade() end end)
    end
end
-- The HUD's opacity. A change of zone or area resets the minimap's
-- (Florian 2026-10-09), so it is set again then; from 1 first, because the
-- client may think it still has the value.
function H:Fade()
    local minimap=rawget(_G,"Minimap")
    if not (self.saved and minimap) or self.placing then return end
    self.placing=true
    minimap:SetAlpha(1);minimap:SetAlpha(G:Config().hudAlpha/100)
    self.placing=nil
end
function H:Refade()
    if not self.saved then return end
    self:Fade()
    C_Timer.After(.5,function() H:Fade() end)
end
local function call(object,method,...)
    local fn=object and object[method]
    if type(fn)~="function" then return nil end
    local ok,a,b=pcall(fn,object,...)
    if ok then return a,b end
end
function H:Show()
    if self.saved then return true end
    local minimap=rawget(_G,"Minimap")
    if not minimap then return false end
    local c=G:Config()
    local f=self:Frame()
    local saved={parent=minimap:GetParent(),points={},width=minimap:GetWidth(),height=minimap:GetHeight(),
        scale=minimap:GetScale(),alpha=minimap:GetAlpha(),mouse=call(minimap,"IsMouseEnabled"),wheel=call(minimap,"IsMouseWheelEnabled"),
        zoom=call(minimap,"GetZoom"),rotate=G.Call("GetCVar","rotateMinimap"),strata=minimap:GetFrameStrata(),children={}}
    for i=1,(call(minimap,"GetNumPoints") or 0) do saved.points[i]={minimap:GetPoint(i)} end
    -- Other addons' buttons on the minimap: hidden while the HUD is open.
    for _,child in ipairs({minimap:GetChildren()}) do
        if not child.bvKeep and child:IsShown() then saved.children[#saved.children+1]=child;child:Hide() end
    end
    self.saved=saved
    f:Show()
    minimap:SetParent(f);minimap:SetFrameStrata("BACKGROUND")
    minimap:SetScale(1)
    self:Hook(minimap)
    self:Place()
    self:Fade()
    -- Route, pins and the sight circle stay at full strength: their layer
    -- moves to the HUD frame (the opacity is only the map's).
    if ns.MapPins and ns.MapPins.SetMinimapHost then ns.MapPins:SetMinimapHost(f) end
    call(minimap,"EnableMouse",false);call(minimap,"EnableMouseWheel",false)
    if call(minimap,"GetZoom")~=nil then call(minimap,"SetZoom",0) end
    self:Turn()
    self:Compass()
    if ns.MapPins then ns.MapPins:Refresh() end
    if G.Mode then G.Mode:Refresh() end
    return true
end
function H:Hide()
    local saved=self.saved
    if not saved then return false end
    local minimap=rawget(_G,"Minimap")
    self.saved=nil
    -- The rotation first: switching it may reset the minimap before the rest is back.
    if saved.rotate~=nil and G.Call("GetCVar","rotateMinimap")~=saved.rotate then pcall(SetCVar,"rotateMinimap",saved.rotate) end
    if minimap then
        minimap:SetParent(saved.parent);minimap:SetFrameStrata(saved.strata)
        minimap:ClearAllPoints()
        for _,point in ipairs(saved.points) do minimap:SetPoint(unpack(point)) end
        minimap:SetScale(saved.scale);minimap:SetSize(saved.width,saved.height);minimap:SetAlpha(saved.alpha)
        if saved.mouse~=nil then call(minimap,"EnableMouse",saved.mouse) end
        if saved.wheel~=nil then call(minimap,"EnableMouseWheel",saved.wheel) end
        if saved.zoom~=nil then call(minimap,"SetZoom",saved.zoom) end
        for _,child in ipairs(saved.children) do child:Show() end
        -- Turning may have reset the shape (Florian 2026-10-09: square became round).
        local shape=G:Config().hudShape
        if shape~="keep" and saved.rotated then
            call(minimap,"SetMaskTexture",shape=="square" and "Interface\\Buttons\\WHITE8X8" or "Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end
    end
    self:Compass()
    -- The pin layer back on the minimap, after its strata and level are back.
    if ns.MapPins and ns.MapPins.SetMinimapHost then ns.MapPins:SetMinimapHost(nil) end
    if self.frame then self.frame:Hide();self.frame.close:Hide() end
    if ns.MapPins then ns.MapPins:Refresh() end
    if G.Mode then G.Mode:Refresh() end
    return true
end
function H:Toggle() if self:On() then self:Hide() else self:Show() end end
-- Turning as chosen; your own setting comes back on close.
function H:Turn()
    local saved=self.saved
    if not saved then return end
    local want=G:Config().hudTurn
    local target=want=="turn" and "1" or (want=="north" and "0" or saved.rotate)
    if target and G.Call("GetCVar","rotateMinimap")~=target then pcall(SetCVar,"rotateMinimap",target);saved.rotated=true end
end
-- The compass: placed anew whenever you turn (a look 30 times a second
-- while the HUD is open, cheap when nothing turned).
function H:Compass()
    local f=self.frame
    if not f then return end
    local on=self.saved and G:Config().hudCompass
    for _,l in ipairs(f.compass) do l:SetShown(on and true or false) end
    if on and not self.compassTicker then
        self.facing=nil
        self.compassTicker=C_Timer.NewTicker(.03,function() H:PlaceCompass() end)
        self:PlaceCompass()
    elseif not on and self.compassTicker then self.compassTicker:Cancel();self.compassTicker=nil end
end
function H:PlaceCompass()
    local minimap=rawget(_G,"Minimap")
    if not (self.saved and minimap) then return end
    local facing=0
    if G.Call("GetCVar","rotateMinimap")=="1" then
        local value=G.Call("GetPlayerFacing")
        if type(value)=="number" and not (issecretvalue and issecretvalue(value)) then facing=value end
    end
    local half=minimap:GetWidth()/2
    local square=G.Call("GetMinimapShape")=="SQUARE"
    local key=string.format("%.3f:%.1f:%s",facing,half,tostring(square))
    if key==self.facing then return end
    self.facing=key
    local c,s=math.cos(facing),math.sin(facing)
    local r=half-14
    for _,l in ipairs(self.frame.compass) do
        local x=l.east*c+l.north*s
        local y=-l.east*s+l.north*c
        if square then local m=math.max(math.abs(x),math.abs(y));if m>0 then x,y=x/m,y/m end end
        l:ClearAllPoints();l:SetPoint("CENTER",minimap,"CENTER",x*r,y*r)
    end
end
-- A change of size or opacity while it is open.
function H:Apply()
    if not self.saved then return end
    self:Place()
    self:Fade()
    self:Turn()
    self:Compass()
    self.facing=nil
end
-- Another HUD addon handles the minimap already.
function H:Other()
    for _,name in ipairs({"FarmHud","HUDMap"}) do
        local loaded=G.Call("C_AddOns.IsAddOnLoaded",name)
        if loaded==nil then loaded=G.Call("IsAddOnLoaded",name) end
        if loaded==true or loaded==1 then return name end
    end
end
function H:Enable(context)
    -- Leaving the gather mode or turning the module off closes the HUD.
    context:Defer(function() H:Hide() end)
    pcall(context.Subscribe,context,"PLAYER_LOGOUT",function() H:Hide() end)
    for _,event in ipairs({"ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA","PLAYER_ENTERING_WORLD","MINIMAP_UPDATE_ZOOM"}) do
        pcall(context.Subscribe,context,event,function() H:Refade() end)
    end
end

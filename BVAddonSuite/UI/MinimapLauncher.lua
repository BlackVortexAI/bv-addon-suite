local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local Launcher={name="BVAddonSuite",controls=setmetatable({},{__mode="k"}),entries={}}
UI.MinimapLauncher=Launcher
ns.Launcher=Launcher

function Launcher:Store()
    local profile=ns.Settings:Profile()
    if type(profile.minimap)~="table" then profile.minimap={} end
    local data=profile.minimap
    if not ns.ProgressModel.Number(data.minimapPos) then data.minimapPos=225 end
    data.hide=data.hide==true; data.lock=data.lock==true
    if data.menu==nil then data.menu=true end
    return data
end
-- Left-click opens AuraStudio directly only when no other module is loaded.
function Launcher:StudioOnly()
    for id in pairs(ns.Modules.records) do if id~="aura_studio" then return false end end
    return true
end
function Launcher:Click(button)
    if button~="LeftButton" and button~="RightButton" then return end
    local studio=ns.AuraStudio
    local standalone=studio and Launcher:StudioOnly()
    if studio and (button=="RightButton" or standalone) then studio:Open()
    else ns.Config:Toggle() end
end
-- Quick menu on hover (Florian 2026-10-09: the settings, AuraStudio, the
-- route editor and the gather mode are opened often). Modules add entries:
-- {id, label, order, onClick, state = function() -> true/false/nil (a switch)}.
-- An entry that answers shown() == false is left out (its module is off).
function Launcher:AddEntry(entry)
    for i,e in ipairs(self.entries) do if e.id==entry.id then table.remove(self.entries,i) break end end
    self.entries[#self.entries+1]=entry
    table.sort(self.entries,function(a,b) return (a.order or 50)<(b.order or 50) end)
end
function Launcher:Entries()
    local out={}
    for _,entry in ipairs(self.entries) do
        local ok,shown=true,true
        if entry.shown then ok,shown=pcall(entry.shown) end
        if ok and shown then out[#out+1]=entry end
    end
    return out
end
local ROW=24
function Launcher:Menu(button)
    local menu=self.menu
    if not menu then
        menu=UI:Panel(UIParent,190,40,"surface");menu:SetFrameStrata("TOOLTIP");menu:EnableMouse(true);menu:Hide()
        menu.rows={}
        menu:SetScript("OnLeave",function() Launcher:Leave() end)
        menu:SetScript("OnEnter",function() Launcher:Stay() end)
        menu:HookScript("OnHide",function() Launcher:Stay() end)
        self.menu=menu
    end
    local entries=self:Entries()
    for i,entry in ipairs(entries) do
        local row=menu.rows[i]
        if not row then
            row=UI:Button(menu,"",182,function(own) Launcher:Choose(own.entry) end,"ghost")
            row:SetLabelInsets(10,44,"LEFT");M.Height(row,ROW)
            row.state=UI:Label(row,"",10,"muted");M.Point(row.state,"RIGHT",row,"RIGHT",-8,0);M.Size(row.state,40,ROW);row.state:SetJustifyH("RIGHT")
            row:HookScript("OnLeave",function() Launcher:Leave() end)
            row:HookScript("OnEnter",function() Launcher:Stay() end)
            menu.rows[i]=row
        end
        row.entry=entry
        row:SetLabelText(entry.label)
        local state=entry.state and entry.state()
        row.state:SetText(state==true and "On" or state==false and "Off" or "")
        row:ClearAllPoints();M.Point(row,"TOPLEFT",menu,"TOPLEFT",4,-4-(i-1)*ROW);row:Show()
    end
    for i=#entries+1,#menu.rows do menu.rows[i]:Hide() end
    if not menu.hint then
        menu.hint=UI:Label(menu,"Click: settings  ·  Right-click: AuraStudio  ·  Drag: move",9,"muted")
        M.Point(menu.hint,"BOTTOMLEFT",menu,"BOTTOMLEFT",10,4);M.Size(menu.hint,174,24);menu.hint:SetWordWrap(true)
    end
    M.Height(menu,8+#entries*ROW+26)
    -- Towards the middle of the screen, overlapping the button a little so
    -- the pointer never crosses a gap (Florian 2026-10-09: it opened off screen).
    local x,y=button:GetCenter()
    local px,py=UIParent:GetCenter()
    local right=x and px and x>px
    local top=y and py and y>py
    local point=(top and "TOP" or "BOTTOM")..(right and "RIGHT" or "LEFT")
    menu:ClearAllPoints();menu:SetPoint(point,button,"CENTER",right and 8 or -8,top and -8 or 8)
    menu:SetClampedToScreen(true)
    menu:SetShown(#entries>0)
    return menu
end
-- Leaving the button or the menu closes it after a short moment, unless
-- the pointer is over one of them by then (Florian 2026-10-09: the way from
-- the button into the menu closed it at once).
function Launcher:Leave()
    if self.closing then self.closing:Cancel() end
    self.closing=C_Timer.NewTimer(.35,function()
        Launcher.closing=nil
        local menu=Launcher.menu
        if menu and menu:IsShown() and not (menu:IsMouseOver() or (Launcher.button and Launcher.button:IsMouseOver())) then menu:Hide() end
    end)
end
function Launcher:Stay()
    if self.closing then self.closing:Cancel();self.closing=nil end
end
function Launcher:Choose(entry)
    if not entry then return end
    ns:Call("minimap menu",entry.onClick)
    if entry.state and self.menu and self.menu:IsShown() and self.button then self:Menu(self.button) else
        if self.menu then self.menu:Hide() end
    end
end
function Launcher:StopDrag()
    local button=self.library and self.library:GetMinimapButton(self.name)
    if button and button.isMouseDown then
        local stop=button:GetScript("OnDragStop"); if stop then stop(button) end
    end
end
function Launcher:Initialize()
    if self.object then self:StopDrag(); self:Refresh(); return end
    local broker=LibStub("LibDataBroker-1.1")
    self.library=LibStub("LibDBIcon-1.0")
    self.object=broker:GetDataObjectByName(self.name) or broker:NewDataObject(self.name,{type="launcher",label="BV Addon Suite"})
    self.object.icon=ns.DesignSystem.minimapLogoTexture
    self.object.iconR,self.object.iconG,self.object.iconB=1,1,1
    self.object.OnClick=function(_,button) ns:Call("minimap",function() self:Click(button) end) end
    self.object.OnEnter=function(button)
        local studio=ns.AuraStudio
        local standalone=studio and Launcher:StudioOnly()
        UI:ShowTooltip(button,"BV Addon Suite",(standalone and "Left-click: AuraStudio" or "Left-click: Addon Suite")..
            (studio and "\nRight-click: AuraStudio" or "\nRight-click: Addon Suite")..
            (self:Store().lock and "\nPosition locked (change in Settings)" or "\nDrag: move around minimap").."\n/bv minimap show | hide | reset")
        self.button=button
        -- With the quick menu the tooltip would cover it: the menu carries the hints.
        if self:Store().menu and #self:Entries()>0 then UI:HideTooltip();self:Stay();self:Menu(button) end
    end
    self.object.OnLeave=function()
        UI:HideTooltip()
        if self.menu and self.menu:IsShown() then self:Leave() end
    end
    if not self.library:IsRegistered(self.name) then self.library:Register(self.name,self.object,self:Store()) end
    local button=self.library:GetMinimapButton(self.name)
    button:HookScript("OnHide",function() self:StopDrag(); UI:HideTooltip() end)
    ns.Settings:BeforeProfileChange(self,function() self:StopDrag(); UI:HideTooltip() end)
    ns.Settings:AfterProfileChange(self,function() self:Refresh() end)
    self:Refresh()
end
function Launcher:RefreshControls()
    for panel in pairs(self.controls) do panel:Refresh() end
end
function Launcher:Refresh()
    if self.library then self.library:Refresh(self.name,self:Store()) end
    self:RefreshControls()
    if self.menu and self.menu:IsShown() and self.button then self:Menu(self.button) end
end
function Launcher:SetMenu(value) self:Store().menu=value==true;if self.menu then self.menu:Hide() end;self:RefreshControls() end
-- Core's own entries: the settings and AuraStudio.
Launcher:AddEntry({id="settings",label="Settings",order=10,onClick=function() ns.Config:Toggle() end})
Launcher:AddEntry({id="aurastudio",label="AuraStudio",order=20,shown=function() return ns.AuraStudio~=nil end,onClick=function() ns.AuraStudio:Open() end})
function Launcher:SetShown(value)
    self:StopDrag(); self:Store().hide=value~=true; self:Refresh()
end
function Launcher:SetLocked(value)
    self:StopDrag(); self:Store().lock=value==true; self:Refresh()
end
function Launcher:ResetPosition()
    self:StopDrag(); self:Store().minimapPos=225; self:Refresh()
end
ns.Commands:RegisterAction("minimap",function(action)
    if action=="show" then Launcher:SetShown(true)
    elseif action=="hide" then Launcher:SetShown(false)
    elseif action=="reset" then Launcher:ResetPosition()
    else ns:Print("/bv minimap show | hide | reset") end
end)

-- Both configuration surfaces bind to the same profile model and callbacks.
function UI:MinimapOptions(parent,width)
    local panel=CreateFrame("Frame",nil,parent); M.Size(panel,width,144)
    panel.show=UI:Switch(panel,false,function(value) Launcher:SetShown(value) end)
    panel.showLabel=UI:Label(panel,"Show minimap button",12,"text")
    panel.lock=UI:Switch(panel,false,function(value) Launcher:SetLocked(value) end)
    panel.lockLabel=UI:Label(panel,"Lock minimap position",12,"text")
    panel.menu=UI:Switch(panel,true,function(value) Launcher:SetMenu(value) end)
    panel.menuLabel=UI:Label(panel,"Quick menu on hover",12,"text")
    panel.reset=UI:Button(panel,"Reset position",150,function() Launcher:ResetPosition() end)
    UI:Place(panel.show,panel,0,4); UI:Place(panel.showLabel,panel,48,5)
    UI:Place(panel.lock,panel,0,38); UI:Place(panel.lockLabel,panel,48,39)
    UI:Place(panel.menu,panel,0,72); UI:Place(panel.menuLabel,panel,48,73)
    UI:Place(panel.reset,panel,0,108)
    UI:AttachTooltip(panel.menu,"Quick menu","Pointing at the launcher opens a small menu: settings, AuraStudio, the route editor, the gather mode.")
    UI:AttachTooltip(panel.show,"Minimap launcher","Show one shared BV launcher. Recover it anytime with /bv minimap show.")
    UI:AttachTooltip(panel.lock,"Lock minimap position","Prevent dragging the BV launcher around the minimap.")
    UI:AttachTooltip(panel.reset,"Reset position","Restore the default minimap angle without changing visibility or other settings.")
    function panel:Arrange(w)
        M.Width(self,w); M.Size(self.showLabel,math.max(1,w-48),20); M.Size(self.lockLabel,math.max(1,w-48),20); M.Size(self.menuLabel,math.max(1,w-48),20)
    end
    function panel:Refresh()
        local data=Launcher:Store(); self.show:SetValue(not data.hide); self.lock:SetValue(data.lock); self.menu:SetValue(data.menu)
    end
    panel:HookScript("OnShow",function() panel:Refresh() end)
    Launcher.controls[panel]=true; panel:Arrange(width); panel:Refresh(); return panel
end

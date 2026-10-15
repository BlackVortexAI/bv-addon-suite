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
-- {id, label, order, group, icon, onClick, state = function() -> true/false/nil
-- (a switch)}. An entry that answers shown() == false is left out (its
-- module is off). Grouped under small headings (Florian 2026-10-15: the
-- list had grown flat and long); a group with no entry shown is left out.
Launcher.GROUPS={{id="suite"},{id="gather",label="Gather"},{id="navigation",label="Navigation"},{id="tools",label="Tools"}}
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
-- The entries in their groups' order: {{group, entries}, ...}.
function Launcher:Grouped()
    local by={}
    for _,entry in ipairs(self:Entries()) do
        local g=entry.group or "suite"
        by[g]=by[g] or {};table.insert(by[g],entry)
    end
    local out,known={},{}
    for _,g in ipairs(self.GROUPS) do known[g.id]=true;if by[g.id] then out[#out+1]={group=g,entries=by[g.id]} end end
    for id,list in pairs(by) do if not known[id] then out[#out+1]={group={id=id,label=id},entries=list} end end
    return out
end
local ROW,HEAD,WIDTH=24,20,214
local function symbol(texture,name)
    if not ns.Symbols then texture:Hide();return end
    local path,l,r,t,b=ns.Symbols:Coords(name or "circle",32)
    if path then texture:SetTexture(path);texture:SetTexCoord(l,r,t,b);texture:Show() else texture:Hide() end
end
function Launcher:Menu(button)
    local menu=self.menu
    if not menu then
        menu=UI:Panel(UIParent,WIDTH,40,"surface");menu:SetFrameStrata("TOOLTIP");menu:EnableMouse(true);menu:Hide()
        -- The soft shadow of the windows (Florian 2026-10-11, finer).
        local DS=ns.DesignSystem
        if DS.Slice and DS.SHADOW then DS.Slice(menu,DS.SHADOW,DS.SHADOWCORNER*.6,"BACKGROUND",-2,DS.SHADOWEXPAND*.6) end
        menu.rows,menu.heads={},{}
        menu:SetScript("OnLeave",function() Launcher:Leave() end)
        menu:SetScript("OnEnter",function() Launcher:Stay() end)
        menu:HookScript("OnHide",function() Launcher:Stay();Launcher.held=nil end)
        self.menu=menu
    end
    local style=UI:GetStyle()
    local y,rows,heads,count=-6,0,0,0
    for _,part in ipairs(self:Grouped()) do
        if part.group.label then
            heads=heads+1
            local head=menu.heads[heads]
            if not head then
                head=CreateFrame("Frame",nil,menu);M.Size(head,WIDTH-16,HEAD)
                head.text=UI:Label(head,"",9,"muted",true);M.Point(head.text,"LEFT",head,"LEFT",4,0)
                head.rule=head:CreateTexture(nil,"ARTWORK");head.rule:SetColorTexture(style:Color("text",.08))
                M.Point(head.rule,"LEFT",head.text,"RIGHT",6,0);M.Point(head.rule,"RIGHT",head,"RIGHT",0,0);M.Height(head.rule,1)
                menu.heads[heads]=head
            end
            head.text:SetText(part.group.label:upper())
            head:ClearAllPoints();M.Point(head,"TOPLEFT",menu,"TOPLEFT",8,y);head:Show()
            y=y-HEAD
        end
        for _,entry in ipairs(part.entries) do
            rows=rows+1;count=count+1
            local row=menu.rows[rows]
            if not row then
                row=UI:Button(menu,"",WIDTH-8,function(own) Launcher:Choose(own.entry) end,"ghost")
                row:SetLabelInsets(30,48,"LEFT");M.Height(row,ROW)
                row.glyph=row:CreateTexture(nil,"OVERLAY");M.Size(row.glyph,14,14);M.Point(row.glyph,"LEFT",row,"LEFT",10,0)
                row.switch=UI:Switch(row,false);row.switch:EnableMouse(false);M.Point(row.switch,"RIGHT",row,"RIGHT",-8,0)
                row:HookScript("OnLeave",function() Launcher:Leave() end)
                row:HookScript("OnEnter",function() Launcher:Stay() end)
                menu.rows[rows]=row
            end
            row.entry=entry
            row:SetLabelText(entry.label)
            symbol(row.glyph,entry.icon)
            row.glyph:SetVertexColor(style:Color("muted"))
            local state=entry.state and entry.state()
            row.switch:SetShown(state~=nil)
            if state~=nil and row.switch.SetValue then row.switch:SetValue(state==true) end
            row:ClearAllPoints();M.Point(row,"TOPLEFT",menu,"TOPLEFT",4,y);row:Show()
            y=y-ROW
        end
    end
    for i=rows+1,#menu.rows do menu.rows[i]:Hide() end
    for i=heads+1,#menu.heads do menu.heads[i]:Hide() end
    if not menu.hint then
        menu.hint=UI:Label(menu,"Click: settings  ·  Right-click: AuraStudio  ·  Drag: move",9,"muted")
        M.Point(menu.hint,"BOTTOMLEFT",menu,"BOTTOMLEFT",10,4);M.Size(menu.hint,WIDTH-16,24);menu.hint:SetWordWrap(true)
    end
    -- The hints are the minimap button's (another button opening it: none).
    local own=self.library and self.library:GetMinimapButton(self.name)
    local hints=not own or button==own
    menu.hint:SetShown(hints)
    M.Height(menu,-y+(hints and 30 or 6))
    -- Towards the middle of the screen, overlapping the button a little so
    -- the pointer never crosses a gap (Florian 2026-10-09: it opened off screen).
    -- Held where it is after a switch in it (Florian 2026-10-15: the Gather
    -- HUD moves the minimap and its button; the menu jumped away from the
    -- pointer and closed).
    if not self.held then
        local x,yy=button:GetCenter()
        local px,py=UIParent:GetCenter()
        local right=x and px and x>px
        local top=yy and py and yy>py
        local point=(top and "TOP" or "BOTTOM")..(right and "RIGHT" or "LEFT")
        menu:ClearAllPoints();menu:SetPoint(point,button,"CENTER",right and 8 or -8,top and -8 or 8)
    end
    menu:SetClampedToScreen(true)
    menu:SetShown(count>0)
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
    local menu=self.menu
    if entry.state and menu and menu:IsShown() and menu.GetLeft and menu:GetLeft() then
        -- Pinned to the screen where it is now, before the switch moves things.
        local left,top=menu:GetLeft(),menu:GetTop()
        local scale=menu:GetEffectiveScale()/UIParent:GetEffectiveScale()
        menu:ClearAllPoints();menu:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left*scale,top*scale)
        self.held=true
    end
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
Launcher:AddEntry({id="settings",label="Settings",order=10,group="suite",icon="settings",onClick=function() ns.Config:Toggle() end})
Launcher:AddEntry({id="aurastudio",label="AuraStudio",order=80,group="tools",icon="sparkles",shown=function() return ns.AuraStudio~=nil end,onClick=function() ns.AuraStudio:Open() end})
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

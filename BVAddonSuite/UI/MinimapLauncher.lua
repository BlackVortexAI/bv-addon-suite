local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local Launcher={name="BVAddonSuite",controls=setmetatable({},{__mode="k"})}
UI.MinimapLauncher=Launcher

function Launcher:Store()
    local profile=ns.Settings:Profile()
    if type(profile.minimap)~="table" then profile.minimap={} end
    local data=profile.minimap
    if not ns.ProgressModel.Number(data.minimapPos) then data.minimapPos=225 end
    data.hide=data.hide==true; data.lock=data.lock==true
    return data
end
function Launcher:Click(button)
    if button~="LeftButton" and button~="RightButton" then return end
    local studio=ns.AuraStudio
    local standalone=studio and not ns.Modules.records.experience_bar and not ns.Modules.records.reputation_bar
    if studio and (button=="RightButton" or standalone) then studio:Open()
    else ns.Config:Toggle() end
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
        local standalone=studio and not ns.Modules.records.experience_bar and not ns.Modules.records.reputation_bar
        UI:ShowTooltip(button,"BV Addon Suite",(standalone and "Left-click: AuraStudio" or "Left-click: Addon Suite")..
            (studio and "\nRight-click: AuraStudio" or "\nRight-click: Addon Suite")..
            (self:Store().lock and "\nPosition locked (change in Settings)" or "\nDrag: move around minimap").."\n/bv minimap show | hide | reset")
    end
    self.object.OnLeave=function() UI:HideTooltip() end
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
end
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
    local panel=CreateFrame("Frame",nil,parent); M.Size(panel,width,110)
    panel.show=UI:Switch(panel,false,function(value) Launcher:SetShown(value) end)
    panel.showLabel=UI:Label(panel,"Show minimap button",12,"text")
    panel.lock=UI:Switch(panel,false,function(value) Launcher:SetLocked(value) end)
    panel.lockLabel=UI:Label(panel,"Lock minimap position",12,"text")
    panel.reset=UI:Button(panel,"Reset position",150,function() Launcher:ResetPosition() end)
    UI:Place(panel.show,panel,0,4); UI:Place(panel.showLabel,panel,48,5)
    UI:Place(panel.lock,panel,0,38); UI:Place(panel.lockLabel,panel,48,39)
    UI:Place(panel.reset,panel,0,74)
    UI:AttachTooltip(panel.show,"Minimap launcher","Show one shared BV launcher. Recover it anytime with /bv minimap show.")
    UI:AttachTooltip(panel.lock,"Lock minimap position","Prevent dragging the BV launcher around the minimap.")
    UI:AttachTooltip(panel.reset,"Reset position","Restore the default minimap angle without changing visibility or other settings.")
    function panel:Arrange(w)
        M.Width(self,w); M.Size(self.showLabel,math.max(1,w-48),20); M.Size(self.lockLabel,math.max(1,w-48),20)
    end
    function panel:Refresh()
        local data=Launcher:Store(); self.show:SetValue(not data.hide); self.lock:SetValue(data.lock)
    end
    panel:HookScript("OnShow",function() panel:Refresh() end)
    Launcher.controls[panel]=true; panel:Arrange(width); panel:Refresh(); return panel
end

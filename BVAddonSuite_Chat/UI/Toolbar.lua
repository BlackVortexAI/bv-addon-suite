local _, Chat = ...
if not Chat.core then return end
local core=Chat.core
local UI,M=core.UI,core.DesignSystem.Metrics

-- The toolbar owner is separate from the sole composer owner. These are
-- profile values; no Core window special case is needed.
function Chat:MainWindow()
    local wanted=Chat:Config().mainWindow or 1
    for _,window in ipairs(Chat:ListWindows()) do
        if window:WindowID()==wanted and window:IsWindowEnabled() then return window end
    end
    return Chat
end
function Chat:HasToolbar() return self==Chat:MainWindow() end
function Chat:ToolbarSide() return Chat:Config().toolbarSide=="left" and "left" or "right" end
function Chat:RefreshToolbars()
    for _,window in ipairs(Chat:ListWindows()) do
        if window.window then
            if not window:HasToolbar() and window.voicePanel then window.voicePanel:Hide() end
            window:ApplyLayout()
        end
    end
end
function Chat:SetAsMainWindow()
    self:Config().visible=true
    Chat:Config().mainWindow=self:WindowID()
    if Chat.running then Chat:SyncWindows() end
    Chat:RefreshToolbars()
    return true
end
function Chat:SetToolbarSide(side)
    if side~="left" and side~="right" then return false end
    Chat:Config().toolbarSide=side
    Chat:RefreshToolbars()
    return true
end

function Chat:BuildToolbar()
    local rail=CreateFrame("Frame",nil,self.window.content)
    self.toolbar=rail
    M.Width(rail,34)
    local fill=rail:CreateTexture(nil,"BACKGROUND")
    fill:SetAllPoints()
    self.style:Bind(function() fill:SetColorTexture(self.style:Color("panel",.55)) end,fill)
    rail:EnableMouse(true)
    self.toolbarEdge=rail:CreateTexture(nil,"ARTWORK")
    self.style:Bind(function() self.toolbarEdge:SetColorTexture(self.style:Color("edge",.65)) end,self.toolbarEdge)
end

function Chat:ArrangeToolbar()
    local primary=self:HasToolbar()
    local left=self:ToolbarSide()=="left"
    self.toolbar:SetShown(primary)
    self.toolbar:ClearAllPoints()
    local side=left and "LEFT" or "RIGHT"
    M.Point(self.toolbar,"TOP"..side,self.window.content,"TOP"..side,left and 2 or -2,-2)
    M.Point(self.toolbar,"BOTTOM"..side,self.window.content,"BOTTOM"..side,left and 2 or -2,2)
    self.toolbarEdge:ClearAllPoints()
    local inner=left and "RIGHT" or "LEFT"
    self.toolbarEdge:SetPoint("TOP"..inner,self.toolbar,"TOP"..inner)
    self.toolbarEdge:SetPoint("BOTTOM"..inner,self.toolbar,"BOTTOM"..inner)
    M.Width(self.toolbarEdge,1)
    local y=4
    for _,button in ipairs({self.gameAction,self.inboxAction,self.voiceAction,self.copyAction,self.latest}) do
        button:ClearAllPoints()
        M.Size(button,28,26)
        M.Point(button,"TOP",self.toolbar,"TOP",0,-y)
        if button==self.latest then button:SetShown(self.anchor~=nil and not self.nativeSource) end
        if button:IsShown() then y=y+27 end
    end
    -- A sibling drawn over a mouse-enabled rail can lose the click to it.
    -- Make the button a child of its active host, also when roles change.
    local backHost=primary and self.toolbar or self.window.content
    if self.back:GetParent()~=backHost then self.back:SetParent(backHost) end
    self.back:ClearAllPoints()
    M.Size(self.back,28,26)
    if primary then
        M.Point(self.back,"TOP",self.toolbar,"TOP",0,-y)
    else
        M.Point(self.back,"TOPLEFT",self.window.content,"TOPLEFT",5,-3)
    end
    self.back:SetShown(self.peer~=nil or self.nativeSource~=nil)
    self.settingsAction:ClearAllPoints()
    M.Size(self.settingsAction,28,26)
    M.Point(self.settingsAction,"BOTTOM",self.toolbar,"BOTTOM",0,3)
    if self.voicePanel then self:PlaceVoicePanel() end
end

function Chat:GameFeedMenu(anchor)
    self:Menu(anchor,{
        {value=1,label="Game feed"},
        {value=2,label="Combat log"},
        {value=0,label="Return to channel mix"},
    },function(id)
        if self.voicePanel then self.voicePanel:Hide() end
        if id==0 then self:Switch(nil,self.target) else self:OpenNativeFeed(id) end
    end)
end

local soundCVars={master="Sound_MasterVolume",effects="Sound_SFXVolume",music="Sound_MusicVolume"}
local function soundAPI(name)
    local fn=C_CVar and C_CVar[name]
    if type(fn)~="function" then fn=_G[name] end
    return type(fn)=="function" and fn or nil
end
function Chat:SoundState()
    local state={}
    local getter=soundAPI("GetCVar")
    if not getter or not soundAPI("SetCVar") then return state end
    -- Blizzard SettingsDefinitions_Shared/Audio.lua defines these sliders
    -- on 0..1; voice output below is a separate native 0..100 API.
    for key,cvar in pairs(soundCVars) do
        local ok,value=pcall(getter,cvar)
        if ok and self.readable(value) and (type(value)=="string" or type(value)=="number") then
            local number=tonumber(value)
            if number and number==number and number>=0 and number<=1 then state[key]=number*100 end
        end
    end
    return state
end
function Chat:SetSoundSetting(key,value)
    if not self.readable(key) or type(key)~="string" then return false end
    local cvar=soundCVars[key]
    if not cvar or not self.readable(value) or type(value)~="number"
        or value~=value or value<0 or value>100 or self:SoundState()[key]==nil then return false end
    local setter=soundAPI("SetCVar")
    if not setter then return false end
    local ok,result=pcall(setter,cvar,math.floor(value+.5)/100)
    -- APIs may return nil on success. An explicit false or unreadable result
    -- is not success, and no Sound_Enable* switch is ever changed here.
    ok=ok and self.readable(result) and result~=false
    if not ok then self:Notice("Game sound could not apply this change.") end
    self:RefreshVoicePanel()
    return ok
end

-- Blizzard's voice settings API uses 0..100, not the 0..1 sound CVars.
-- Read unavailable/secret state as unknown; never join channels or start capture.
local function voiceRead(name)
    local fn=C_VoiceChat and C_VoiceChat[name]
    if type(fn)~="function" then return nil end
    local ok,value=pcall(fn)
    if ok and Chat.readable(value) then return value end
end
local function supported(getter,setter,kind)
    if not C_VoiceChat or type(C_VoiceChat[setter])~="function" then return nil end
    local value=voiceRead(getter)
    if type(value)~=kind then return nil end
    if kind=="number" and (value~=value or value<0 or value>100) then return nil end
    return value
end
function Chat:VoiceState()
    for _,gate in ipairs({"CanAccessSettings","IsEnabled"}) do
        -- Older clients can omit a gate. A present gate must positively
        -- confirm availability; secret/nil/error is not an affirmative answer.
        if C_VoiceChat and C_VoiceChat[gate]~=nil and voiceRead(gate)~=true then return {} end
    end
    return {
        volume=supported("GetOutputVolume","SetOutputVolume","number"),
        muted=supported("IsMuted","SetMuted","boolean"),
        deafened=supported("IsDeafened","SetDeafened","boolean"),
    }
end
function Chat:SetVoiceSetting(key,value)
    local setters={volume="SetOutputVolume",muted="SetMuted",deafened="SetDeafened"}
    local setter=setters[key]
    if not setter or not self.readable(value) or self:VoiceState()[key]==nil then return false end
    if key=="volume" then
        if type(value)~="number" or value~=value or value<0 or value>100 then return false end
        value=math.floor(value+.5)
    elseif type(value)~="boolean" then return false end
    local ok=pcall(C_VoiceChat[setter],value)
    if not ok then self:Notice("Voice chat could not apply this change.") end
    self:RefreshVoicePanel()
    return ok
end
function Chat:RefreshVoicePanel()
    local panel=self.voicePanel
    if not panel then return end
    local state=self:VoiceState()
    self.refreshingVoice=true
    local sound=self:SoundState()
    for _,key in ipairs({"master","effects","music"}) do
        local slider=panel.sound[key]
        local value=sound[key]
        slider:SetValue(value or 0)
        panel.soundValues[key]:SetText(value and (math.floor(value+.5).."%") or "—")
        if value~=nil then slider:Enable() else slider:Disable() end
    end
    panel.volume:SetValue(state.volume or 0)
    panel.value:SetText(state.volume and (math.floor(state.volume+.5).."%") or "—")
    if state.volume~=nil then panel.volume:Enable() else panel.volume:Disable() end
    for _,key in ipairs({"muted","deafened"}) do
        panel[key]:SetValue(state[key]==true)
        if state[key]~=nil then panel[key]:Enable() else panel[key]:Disable() end
    end
    panel.note:SetText(state.volume==nil and state.muted==nil and state.deafened==nil
        and "Voice chat is not available in this client." or "Uses the game's voice service. Never joins a channel automatically.")
    self.refreshingVoice=nil
end
function Chat:PlaceVoicePanel()
    local panel=self.voicePanel
    if not panel then return end
    panel:ClearAllPoints()
    local left=self:ToolbarSide()=="left"
    M.Point(panel,"TOP"..(left and "LEFT" or "RIGHT"),self.toolbar,"TOP"..(left and "RIGHT" or "LEFT"),left and 5 or -5,-3)
end
function Chat:ToggleVoicePanel()
    if not self:HasToolbar() then return end
    if not self.voicePanel then self:Styled(function()
        local panel=CreateFrame("Frame",nil,self.window.content)
        self.voicePanel=panel
        self.style:Skin(panel,"bg",4,1)
        -- Some themes give bg an intrinsic alpha. A settings flyout needs
        -- an opaque text area even when the surrounding chat is translucent.
        local backing=panel:CreateTexture(nil,"BACKGROUND",nil,-8)
        M.Point(backing,"TOPLEFT",panel,"TOPLEFT",2,-2)
        M.Point(backing,"BOTTOMRIGHT",panel,"BOTTOMRIGHT",-2,2)
        self.style:Bind(function()
            local r,g,b=self.style:Color("bg")
            backing:SetColorTexture(r,g,b,1)
        end,backing)
        panel:SetFrameLevel(self.window.content:GetFrameLevel()+15)
        panel:EnableMouse(true)
        panel:SetClampedToScreen(true)
        M.Size(panel,280,334)
        Chat.at(UI:Label(panel,"Sound & voice",17,"text",true),panel,12,10)
        local close=UI:IconButton(panel,"x",function() panel:Hide() end,"icon-only")
        M.Point(close,"TOPRIGHT",panel,"TOPRIGHT",-4,-4)
        UI:AttachTooltip(close,"Close sound controls")
        Chat.at(UI:Label(panel,"Game sound",13,"text",true),panel,12,41)
        panel.sound,panel.soundValues={},{}
        for index,entry in ipairs({{"master","Master"},{"effects","Effects"},{"music","Music"}}) do
            local key,label=entry[1],entry[2]
            local y=66+(index-1)*27
            Chat.at(UI:Label(panel,label,13,"muted"),panel,12,y)
            panel.soundValues[key]=Chat.at(UI:Label(panel,"",13,"text"),panel,235,y)
            panel.sound[key]=Chat.at(self.style:Slider(panel,125,0,100,1,0,function(value)
                if not self.refreshingVoice then self:SetSoundSetting(key,value) end
            end),panel,90,y-5)
            UI:AttachTooltip(panel.sound[key],label.." volume · keeps existing mute settings")
        end
        local divider=panel:CreateTexture(nil,"ARTWORK")
        M.Point(divider,"TOPLEFT",panel,"TOPLEFT",12,-148)
        M.Size(divider,256,1)
        self.style:Bind(function() divider:SetColorTexture(self.style:Color("edge",.65)) end,divider)
        Chat.at(UI:Label(panel,"Voice chat",13,"text",true),panel,12,159)
        Chat.at(UI:Label(panel,"Volume",13,"muted"),panel,12,185)
        panel.value=Chat.at(UI:Label(panel,"",13,"text"),panel,235,185)
        panel.volume=Chat.at(self.style:Slider(panel,125,0,100,1,0,function(value)
            if not self.refreshingVoice then self:SetVoiceSetting("volume",value) end
        end),panel,90,180)
        UI:AttachTooltip(panel.volume,"Voice chat volume")
        panel.deafened=Chat.at(self.style:Check(panel,"Mute voice output",false,function(on)
            if not self.refreshingVoice then self:SetVoiceSetting("deafened",on) end
        end),panel,12,218)
        panel.muted=Chat.at(self.style:Check(panel,"Mute microphone",false,function(on)
            if not self.refreshingVoice then self:SetVoiceSetting("muted",on) end
        end),panel,12,247)
        M.Width(panel.deafened,256);M.Width(panel.muted,256)
        panel.note=Chat.at(UI:Label(panel,"",12,"muted"),panel,12,284)
        M.Width(panel.note,256);panel.note:SetWordWrap(true);panel.note:SetJustifyH("LEFT")
        -- Listen only while the flyout is visible. Optional voice events are
        -- absent on some clients; a failed registration leaves no listener.
        panel:SetScript("OnShow",function()
            core.Events:Release(panel)
            for _,event in ipairs({"VOICE_CHAT_LOGIN","VOICE_CHAT_LOGOUT",
                "VOICE_CHAT_MUTED_CHANGED","VOICE_CHAT_DEAFENED_CHANGED",
                "VOICE_CHAT_OUTPUT_DEVICES_UPDATED","VOICE_CHAT_ERROR","CVAR_UPDATE"}) do
                pcall(core.Events.Subscribe,core.Events,panel,event,function() self:RefreshVoicePanel() end)
            end
            self:RefreshVoicePanel()
        end)
        panel:SetScript("OnHide",function() core.Events:Release(panel) end)
        panel:Hide()
    end) end
    self:PlaceVoicePanel()
    self.voicePanel:SetShown(not self.voicePanel:IsShown())
    if self.voicePanel:IsShown() then
        self.peoplePanel:Hide();self.suggestions:Hide()
        self:RefreshVoicePanel()
    end
end

local _, Chat = ...
if not Chat.core then return end
local core=Chat.core
local bridge={parents={},carriers={},mouse={},editors={},hooks=setmetatable({},{__mode="k"})}
Chat.bridge=bridge

local function locked() return InCombatLockdown and InCombatLockdown() end
local function usable(frame)
    return frame and frame.GetParent and not (frame.IsForbidden and frame:IsForbidden())
end

-- Keep the real frames shown and processing messages. A separate alpha carrier
-- survives Blizzard fading the frame itself and keeps the combat tab clickable by macro.
function bridge:Park(frame)
    if not usable(frame) then return end
    local parent=frame:GetParent()
    if not parent then return end
    if self.parents[frame] and parent==self.carriers[self.parents[frame]] then return end
    local cursor=parent
    while cursor do
        if self.parents[cursor] then return end
        cursor=cursor.GetParent and cursor:GetParent()
    end
    local carrier=self.carriers[parent]
    if not carrier then
        carrier=CreateFrame("Frame",nil,parent)
        carrier:SetAllPoints(parent)
        carrier:SetAlpha(0)
        self.carriers[parent]=carrier
    end
    self.parents[frame]=parent
    frame:SetParent(carrier)
end

local function muteMouse(frame, seen)
    if not usable(frame) or seen[frame] or bridge.editors[frame] then return end
    seen[frame]=true
    local state=bridge.mouse[frame] or {}
    if frame.IsMouseWheelEnabled and frame:IsMouseWheelEnabled() then
        state.wheel=true
        frame:EnableMouseWheel(false)
    end
    if frame.IsMouseEnabled and frame:IsMouseEnabled() then
        if state.mouse==nil then
            state.mouse=true
            if frame.IsMouseClickEnabled then state.click=frame:IsMouseClickEnabled() end
            if frame.IsMouseMotionEnabled then state.motion=frame:IsMouseMotionEnabled() end
        end
        frame:EnableMouse(false)
    end
    if state.mouse or state.wheel then bridge.mouse[frame]=state end
    if frame.GetChildren then
        for _,child in ipairs({frame:GetChildren()}) do muteMouse(child,seen) end
    end
end

local function points(frame)
    local saved={}
    for i=1,frame:GetNumPoints() do saved[i]={frame:GetPoint(i)} end
    return saved
end

-- Classic's edit box owns the actual editable glyphs/caret. Its three chat
-- border textures, optional focus art, localized header, prompt and language
-- button are separate template regions. Mask only the decorations; keeping
-- their shown flags lets Blizzard continue its normal focus/command lifecycle.
local decorations={
    "Left","Mid","Right","FocusLeft","FocusMid","FocusRight","Header","HeaderSuffix",
    "Prompt","Language","LanguageHeader","NineSlice","Backdrop","Background","Border",
}
local function editorArt(box)
    local art={}
    local function track(region)
        if region and region.GetAlpha and region.SetAlpha then art[region]=region:GetAlpha() end
    end
    local name=box:GetName()
    for _,suffix in ipairs(decorations) do
        track(box[suffix])
        track(box[suffix:sub(1,1):lower()..suffix:sub(2)])
        if name then track(_G[name..suffix]) end
    end
    -- Unnamed regions belong to the native text renderer (including focus,
    -- selection and caret). A draw layer is not an identifier for frame art.
    return art
end

local function styleEditor(box)
    local state=bridge.editors[box]
    if not bridge.active or not state or not state.workspace then return end
    if locked() and box.IsProtected and box:IsProtected() then bridge.pending=true;return end
    local workspace=state.workspace
    local header=box.header or _G[(box:GetName() or "").."Header"]
    local headerText=header and header:GetText()
    local text=Chat.text(box:GetText())
    local isCommand=text and text:sub(1,1)=="/"
    -- With a hidden recipient selector, show the real game's address inside
    -- the field for native whispers and channels. Secret headers remain with
    -- Blizzard and never flow through our formatter or SavedVariables.
    local showAddress=not isCommand and (workspace:Config().hideTarget or not Chat.readable(headerText))
    local suffix=box.headerSuffix or _G[(box:GetName() or "").."HeaderSuffix"]
    for region,alpha in pairs(state.art) do
        local visible=showAddress and (region==header or region==suffix)
        local target=visible and alpha or 0
        if region:GetAlpha()~=target then region:SetAlpha(target) end
    end
    if state.insets then
        local padding=core.DesignSystem.Metrics.ToNative(10)
        local l,r,t,b=padding,padding,0,0
        if showAddress then l,r,t,b=unpack(state.nativeInsets or state.insets) end
        local oldL,oldR,oldT,oldB=box:GetTextInsets()
        if oldL~=l or oldR~=r or oldT~=t or oldB~=b then box:SetTextInsets(l,r,t,b) end
    end
    local caption=isCommand and "Command" or Chat.text(headerText) or "Game chat"
    if workspace.nativeOverrideCaption~=caption then
        workspace.nativeOverrideCaption=caption
        workspace:QueuePaint()
    end
end

local function showInputSurface(workspace)
    local surface=workspace.nativeInputSurface
    if not surface then
        surface=CreateFrame("Frame",nil,workspace.input:GetParent())
        surface:SetAllPoints(workspace.input)
        surface:EnableMouse(false)
        workspace.style:Skin(surface,"bg",4,.85)
        workspace.style:Bind(function()
            -- The native editor supplies the glyphs. Its backdrop is a Frame,
            -- so paint the panel without invoking EditBox font methods on it.
            surface:PaintSurface({workspace.style:Color("field")},{workspace.style:Color("accent")},.95)
        end,surface)
        workspace.nativeInputSurface=surface
    end
    surface:Show()
end

local function attachEditor(box)
    if not Chat.running or not bridge.active then return end
    if locked() and box.IsProtected and box:IsProtected() then bridge.pending=true;return end
    local state=bridge.editors[box]
    if not state then return end
    if state.workspace and state.input==state.workspace.input then
        styleEditor(box)
        return
    end
    if not state.points then
        local owner=Chat:GetComposerWindow()
        if not owner or not owner.input then return end
        state.workspace=owner
        state.input=owner.input
        state.points=points(box)
        state.parent=box:GetParent()
        state.ignore=box.IsIgnoringParentAlpha and box:IsIgnoringParentAlpha() or false
        state.strata=box:GetFrameStrata()
        state.art=editorArt(box)
        state.insets=box.GetTextInsets and {box:GetTextInsets()}
        state.font={box:GetFont()}
        state.altArrows=box.GetAltArrowKeyMode and box:GetAltArrowKeyMode()
        if state.altArrows~=nil then box:SetAltArrowKeyMode(false) end
    end
    local workspace=state.workspace
    local input=state.input
    if box.SetIgnoreParentAlpha then box:SetIgnoreParentAlpha(true)
    else box:SetParent(workspace.window) end
    box:SetFrameStrata("DIALOG")
    box:ClearAllPoints()
    box:SetPoint("LEFT",input,"LEFT",0,0)
    box:SetPoint("RIGHT",input,"RIGHT",0,0)
    local face,height,flags=input:GetFont()
    if face then box:SetFont(face,height,flags or "") end
    showInputSurface(workspace)
    input:Hide()
    styleEditor(box)
    -- A portrait-menu whisper finishes assigning its target after opening
    -- the native editor. Once complete, give the single visible BV edit box
    -- the real text focus and insertion point. Leave commands and opaque
    -- destinations with Blizzard.
    C_Timer.NewTimer(0,function()
        if not bridge.active or locked() or state.workspace~=workspace or workspace.input~=input
            or not box:HasFocus() or not box:IsShown() or not box.GetAttribute then return end
        if Chat.text(box:GetAttribute("chatType"))~="WHISPER" then return end
        local peer=Chat.person(box:GetAttribute("tellTarget"))
        local body=box:GetText()
        if not peer or not Chat.readable(body) or type(body)~="string" or body:sub(1,1)=="/" then return end
        local cursor=box:GetCursorPosition()
        if not Chat.readable(cursor) or type(cursor)~="number" then return end
        box:ClearFocus();box:Hide()
        workspace:SetAddress(peer)
        if body~="" then input:SetText(body) end
        input:SetFocus()
        input:SetCursorPosition(body~="" and math.min(cursor,#body) or #input:GetText())
    end)
end
local function detachEditor(box)
    local state=bridge.editors[box]
    if not state or not state.points then return end
    if locked() and box.IsProtected and box:IsProtected() then bridge.pending=true;return end
    local workspace,input=state.workspace,state.input
    state.workspace,state.input=nil,nil
    if box.SetIgnoreParentAlpha then box:SetIgnoreParentAlpha(state.ignore)
    else box:SetParent(state.parent) end
    box:SetFrameStrata(state.strata)
    box:ClearAllPoints()
    for _,p in ipairs(state.points) do box:SetPoint(unpack(p)) end
    for region,alpha in pairs(state.art) do region:SetAlpha(alpha) end
    if state.insets then box:SetTextInsets(unpack(state.nativeInsets or state.insets)) end
    if state.font[1] then box:SetFont(unpack(state.font)) end
    if state.altArrows~=nil then box:SetAltArrowKeyMode(state.altArrows) end
    state.points,state.art,state.insets,state.nativeInsets,state.font=nil,nil,nil,nil,nil
    workspace.nativeOverrideCaption=nil
    if workspace.nativeInputSurface then workspace.nativeInputSurface:Hide() end
    if workspace.input==input then input:Show() end
    workspace:QueuePaint()
end
local function registerEditor(box)
    if not usable(box) then return end
    if not bridge.editors[box] then
        bridge.editors[box]={originalIgnore=box.IsIgnoringParentAlpha and box:IsIgnoringParentAlpha() or false}
    end
    -- The edit box can be parented directly to UIParent even while anchored
    -- to a chat frame. Park it independently until the player focuses it.
    if not bridge.editors[box].points then
        bridge:Park(box)
        if box.SetIgnoreParentAlpha then box:SetIgnoreParentAlpha(false) end
    end
    if not bridge.hooks[box] then
        box:HookScript("OnShow",function(b) if b:HasFocus() then attachEditor(b) end end)
        box:HookScript("OnEditFocusGained",attachEditor)
        box:HookScript("OnHide",detachEditor)
        box:HookScript("OnEditFocusLost",detachEditor)
        box:HookScript("OnTextChanged",styleEditor)
        if hooksecurefunc then
            if box.UpdateHeader then
                hooksecurefunc(box,"UpdateHeader",function(editor)
                    local state=bridge.editors[editor]
                    if state and state.workspace and editor.GetTextInsets then state.nativeInsets={editor:GetTextInsets()} end
                    styleEditor(editor)
                end)
            end
            if box.SetFocusRegionsShown then hooksecurefunc(box,"SetFocusRegionsShown",styleEditor) end
            if box.SetFocusRegionVertexColors then hooksecurefunc(box,"SetFocusRegionVertexColors",styleEditor) end
        end
        bridge.hooks[box]=true
    end
    if box.HasFocus and box:HasFocus() then attachEditor(box)
    elseif not box:IsShown() then detachEditor(box) end
end

local function addFrame(roots,name)
    local f=_G[name]
    if usable(f) then roots[#roots+1]=f end
end
local function mirror(workspace,index,text,r,g,b)
    if workspace and workspace.nativeSource==index and workspace.window and workspace.window:IsShown() then
        local feed=workspace.nativeFeed
        pcall(feed.AddMessage,feed,text,r,g,b)
    end
end
function bridge:Scan()
    if not self.active then return end
    if locked() then self.pending=true;return end
    Chat:RefreshEventTypeIDs()
    local roots={}
    local names={}
    for i=1,(NUM_CHAT_WINDOWS or 10) do names["ChatFrame"..i]=true end
    for _,name in ipairs(CHAT_FRAMES or {}) do if type(name)=="string" then names[name]=true end end
    for name in pairs(names) do
        local frame=_G[name]
        if usable(frame) then
            registerEditor(frame.editBox or _G[name.."EditBox"])
            if (name=="ChatFrame1" or name=="ChatFrame2") and type(frame.AddMessage)=="function" and hooksecurefunc and not self.hooks[frame] then
                local index=name=="ChatFrame1" and 1 or 2
                hooksecurefunc(frame,"AddMessage",function(_,text,r,g,b,typeID,accessID,lineID,event)
                    if not Chat.running then return end
                    for _,workspace in ipairs(Chat:ListWindows()) do
                        mirror(workspace,index,text,r,g,b)
                    end
                    if index==1 and Chat.readable(typeID) and Chat.text(text) then
                        -- /played, /help and usage errors use SYSTEM's colour id
                        -- directly, without a native message event or history ids.
                        local system=ChatTypeInfo and ChatTypeInfo.SYSTEM
                        local direct=system and typeID==system.id and Chat.readable(event) and not event and
                            Chat.readable(accessID) and not accessID and Chat.readable(lineID) and not lineID
                        if direct or not Chat:HasMessageEvent(typeID,event) then Chat:Add("SYSTEM",nil,text) end
                    end
                end)
                self.hooks[frame]=true
            end
            for _,suffix in ipairs({"","Tab","ButtonFrame","Dock","ResizeButton","ChannelButton","QuickJoinToastButton"}) do
                addFrame(roots,name..suffix)
            end
        end
    end
    for _,name in ipairs({"GeneralDockManager","ChatFrameMenuButton","ChatFrameChannelButton","ChatFrameToggleVoiceDeafenButton","ChatFrameToggleVoiceMuteButton","ChatFrameToggleVoiceChatButton","QuickJoinToastButton","ChatAlertFrame"}) do addFrame(roots,name) end
    local seen={}
    for _,frame in ipairs(roots) do self:Park(frame); muteMouse(frame,seen) end
end
function bridge:Bindings()
    if locked() then self.pending=true;return end
    if self.updatingBindings or not self.owner or not ClearOverrideBindings then return end
    self.updatingBindings=true
    ClearOverrideBindings(self.owner)
    if self.active and SetOverrideBinding and GetBindingKey then
        for action,target in pairs({OPENCHAT="BVCHAT_OPEN",OPENCHATSLASH="BVCHAT_SLASH",REPLY="BVCHAT_REPLY",REPLY2="BVCHAT_LASTOUT"}) do
            for _,key in ipairs({GetBindingKey(action)}) do SetOverrideBinding(self.owner,false,key,target) end
        end
    end
    self.updatingBindings=nil
end
function bridge:Restore()
    if locked() then self.pending=true;return end
    for box,state in pairs(self.editors) do
        detachEditor(box)
        if box.SetIgnoreParentAlpha then box:SetIgnoreParentAlpha(state.originalIgnore) end
    end
    for frame,parent in pairs(self.parents) do
        if frame:GetParent()==self.carriers[parent] then frame:SetParent(parent) end
    end
    for frame,state in pairs(self.mouse) do
        if state.mouse then frame:EnableMouse(true) end
        if state.click~=nil and frame.SetMouseClickEnabled then frame:SetMouseClickEnabled(state.click) end
        if state.motion~=nil and frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(state.motion) end
        if state.wheel then frame:EnableMouseWheel(true) end
    end
    if Chat.logStart and Chat.logStart:IsShown() then Chat.logStart:Hide() end
    self.parents,self.mouse,self.editors={},{},{}
    self:Bindings()
end
function bridge:Sync()
    self.pending=nil
    if self.active then self:Scan();self:Bindings() else self:Restore() end
    if not self.active and not self.pending and self.listening then
        core.Events:Release(self);self.listening=nil
    end
end
function bridge:RegisterWorkspace(workspace)
    local input=workspace.input
    if not input then return end
    if not self.hooks[input] then
        self.hooks[input]=true
        -- The same edit box moves between trays. Its first owning window must
        -- never be captured by a per-keystroke hook.
        input:HookScript("OnTextChanged",function(box,userInput)
            if not userInput or not Chat.running or not self.active then return end
            local owner=Chat:GetComposerWindow()
            if owner and owner.input==box then owner:RouteCommand(box:GetText()) end
        end)
    end
    if self.registeredOwner~=workspace then
        self.registeredOwner=workspace
        -- A saved secondary composer may be built after the native chat was
        -- first scanned. Adopt any editor that was already focused at login.
        if self.active then
            for box in pairs(self.editors) do
                if box:HasFocus() then attachEditor(box) end
            end
        end
    end
end

function bridge:CloseWorkspace(workspace)
    for box,state in pairs(self.editors) do
        if state.workspace==workspace then
            if locked() and box.IsProtected and box:IsProtected() then
                return false
            else
                box:ClearFocus()
                detachEditor(box)
            end
        end
    end
    return true
end

-- The bag caller uses InsertLink's return value to decide whether a Shift
-- click should split a stack. A post-hook cannot report that we handled it.
local function routeItemLinks(api,key)
    local previous=api and api[key]
    if type(previous)~="function" then return end
    api[key]=function(link,...)
        if bridge.active and Chat.running and Chat.text(link) and link:find("|Hitem:",1,true) then
            local writer=Chat:GetComposerWindow()
            local input=writer.input
            if input and input:IsVisible() and input:HasFocus() and not writer.nativeOverrideCaption then
                input:Insert(link)
                return true
            end
        end
        return previous(link,...)
    end
end
local function queueScan()
    if bridge.active and not bridge.queued then
        bridge.queued=C_Timer.NewTimer(0,function() bridge.queued=nil;bridge:Scan() end)
    end
end
function bridge:SetActive(active)
    self.active=active
    for _,carrier in pairs(self.carriers) do carrier:SetAlpha(active and 0 or 1) end
    if active and not self.owner then
        routeItemLinks(ChatFrameUtil,"InsertLink")
        routeItemLinks(_G,"ChatEdit_InsertLink")
        self.owner=CreateFrame("Frame",nil,UIParent)
        self:RegisterWorkspace(Chat:GetComposerWindow())
        if hooksecurefunc then for _,fn in ipairs({"FCF_OpenTemporaryWindow","FCF_OpenNewWindow","FCF_DockFrame"}) do
            if type(_G[fn])=="function" then hooksecurefunc(fn,queueScan) end
        end end
    end
    if active and not self.listening then
        self.listening=true
        core.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function() if self.pending then self:Sync() end end)
        core.Events:Subscribe(self,"UPDATE_BINDINGS",function() if self.active then self:Bindings() end end)
        for _,event in ipairs({"PLAYER_ENTERING_WORLD","UPDATE_CHAT_WINDOWS","UPDATE_FLOATING_CHAT_WINDOWS"}) do
            pcall(core.Events.Subscribe,core.Events,self,event,queueScan)
        end
    elseif not active and self.queued then
        self.queued:Cancel();self.queued=nil
    end
    self:Sync()
end

-- Hand client commands to the native editor at the same location. Only the
-- player's next Enter executes the command, using the normal chat parser.
function Chat:NativeCommand(text)
    self=Chat:GetComposerWindow()
    if not self or not self.input then return end
    local open=ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    if not open then return self:Notice("Blizzard command entry is unavailable.") end
    self.input:ClearFocus()
    local ok=pcall(open,text,DEFAULT_CHAT_FRAME)
    if ok then self.input:SetText("") else self.input:SetFocus();self:Notice("Command could not be opened.") end
end

-- Switch as soon as the first word cannot be a BV whisper shortcut. From
-- then on the keystrokes (including Enter) belong to Blizzard's real editor.
local shortcuts={"w","whisper","tell","r","reply","rr","raus","lastw"}
function Chat:RouteCommand(text)
    if not self.text(text) then return end
    local token,space=text:match("^/(%S+)(%s*)")
    if not token then return end
    token=token:lower()
    if space~="" and Chat.replyKeys[token] then
        local name=self:ReplyTarget(token)
        if name then
            local body=text:match("^/%S+%s+(.*)$") or ""
            self.input:SetText("")
            self:SetAddress(name)
            if body~="" then self.input:SetText(body) end
            self.input:SetCursorPosition(#self.input:GetText())
        else self:Notice("No previous whisper for that shortcut.") end
        return
    end
    if token:match("^%d+$") then
        local slot,body=text:match("^/(%d+)%s+(.*)$")
        if slot then self:SelectNumberedChannel(slot,body) end
        return
    end
    for _,name in ipairs(shortcuts) do
        if token==name then return end
        if space=="" and name:sub(1,#token)==token then return end
    end
    local channel,prefix=self:ChannelAlias(token)
    if channel or (space=="" and prefix) then
        if channel and space~="" then self:SelectDestination(channel,text:match("^/%S+%s+(.*)$") or "") end
        return
    end
    if (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat then self:NativeCommand(text) end
end

function Chat:FocusComposer(slash)
    if not self.running then
        local open=ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
        if bridge.pending and open then open(slash and "/" or "",DEFAULT_CHAT_FRAME) end
        return
    end
    local workspace=Chat:GetComposerWindow()
    if not workspace then return end
    workspace:EnsureWorkspace()
    if not workspace.input then return end
    if workspace.nativeOverrideCaption then return end
    if slash and workspace.input:GetText()=="" then workspace.input:SetText("/") end
    workspace.input:SetFocus()
end

function Chat:BuildNativeFeed(parent)
    local f=CreateFrame("ScrollingMessageFrame",nil,parent)
    f:SetAllPoints(self.feed)
    -- ScrollingMessageFrameSecureMixin:SetFont discards the success result.
    -- Resolve/validate the theme on a FontString, then copy its font verbatim.
    -- Passing the message frame itself to Theme:Font would select FRIZQT.
    local font=f:CreateFontString(nil,"OVERLAY")
    font:Hide()
    self.style:Bind(function()
        self.style:Font(font,14)
        local file,height,flags=font:GetFont()
        if file then f:SetFont(file,height,flags or "") end
    end,f)
    f:SetJustifyH("LEFT")
    if f.SetFading then f:SetFading(false); f:SetMaxLines(500) end
    if f.SetHyperlinksEnabled then
        f:SetHyperlinksEnabled(true)
        f:SetScript("OnHyperlinkClick",function(_,link,text,button)
            if Chat.text(link) and SetItemRef then SetItemRef(link,text,button) end
        end)
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel",function(box,delta) if delta>0 then box:ScrollUp() else box:ScrollDown() end end)
    f:Hide()
    self.nativeFeed=f
end
function Chat:ReadNative(accept)
    local source=_G["ChatFrame"..self.nativeSource]
    if not usable(source) or not source.GetNumMessages then return end
    local count=source:GetNumMessages()
    if not self.readable(count) then return end
    for i=math.max(1,count-499),count do
        local ok,text,r,g,b=pcall(source.GetMessageInfo,source,i)
        if ok then accept(text,r,g,b) end
    end
end
function Chat:OpenNativeFeed(index)
    self.nativeSource=index
    self.peoplePanel:Hide()
    self.nativeFeed:Clear()
    self:ReadNative(function(text,r,g,b) pcall(self.nativeFeed.AddMessage,self.nativeFeed,text,r,g,b) end)
    self:Paint()
    if index==2 and not self.seenCombat then self:OfferCombatStart() end
end
function Chat:OfferCombatStart()
    if locked() then return self:Notice("Open the combat log outside combat once to start the game’s filter.") end
    if not ChatFrame2Tab then return end
    if not Chat.logStart then
        local UI,M=core.UI,core.DesignSystem.Metrics
        self:Styled(function()
            local panel=UI:Dialog("BVChatStartCombatLog",332,136)
            Chat.logStart=panel
            panel.title:SetText("Combat log")
            local text=UI:Label(panel,"Start Blizzard’s combat filter for this session.",14,"text")
            M.Point(text,"TOPLEFT",panel,"TOPLEFT",16,-36)
            local face=UI:Button(panel,"Start combat log",168,nil,true)
            M.Point(face,"BOTTOM",panel,"BOTTOM",0,14)
            local action=CreateFrame("Button",nil,face,"SecureActionButtonTemplate")
            action:SetAllPoints(face)
            action:SetFrameLevel(face:GetFrameLevel()+2)
            action:RegisterForClicks("AnyUp","AnyDown")
            action:SetAttribute("type","macro")
            action:SetAttribute("macrotext","/click ChatFrame1Tab\n/click ChatFrame2Tab\n/click ChatFrame1Tab")
            action:SetScript("PostClick",function(_,_,down)
                if not down and not locked() then panel:Hide() end
            end)
            core.Events:Subscribe(panel,"PLAYER_REGEN_DISABLED",function() if panel:IsShown() then panel:Hide() end end)
        end)
    end
    Chat.logStart:Show()
end

local _, Chat = ...
if not Chat.core then return end
local core=Chat.core
local UI,M=core.UI,core.DesignSystem.Metrics
local COMPOSER_HEIGHT=32
local function at(frame,parent,x,y)
    M.Point(frame,"TOPLEFT",parent,"TOPLEFT",x,-y)
    return frame
end
Chat.at=at
local function frameName(workspace,prefix)
    local id=workspace:WindowID()
    return id==1 and prefix or prefix..id
end

local function focusIfWriter(workspace)
    if workspace.input and workspace:HasComposer() and workspace.input:IsVisible() then workspace.input:SetFocus() end
end

local function showConversation(workspace,name,write)
    if write then
        local writer=workspace:GetComposerWindow()
        if not writer then return end
        if not writer.input or not writer.input:IsVisible() then
            return workspace:Notice("Finish or cancel the current game entry before whispering.")
        end
        writer:SetAddress(name)
        focusIfWriter(writer)
    else
        workspace:Switch(name)
        focusIfWriter(workspace)
    end
end
function Chat:Styled(create)
    return UI:WithStyle(self.style or UI:InterfaceStyle(),create)
end
function Chat:Menu(anchor,items,choose)
    anchor.bvMenuStyle=self.style
    if #items>0 then UI:ContextMenu(anchor,items,choose) end
end
function Chat:ToggleInbox()
    if self.voicePanel then self.voicePanel:Hide() end
    local pane=self.peoplePanel
    pane:SetShown(not pane:IsShown())
    if pane:IsShown() then
        self.suggestions:Hide()
        self.peopleSearch:SetText("")
        self.peopleSearch:SetFocus()
    end
    self:Paint()
end
function Chat:ChooseTarget(anchor)
    if not self:HasComposer() then return end
    local targets=self:Targets()
    if #targets==0 then return self:Notice("Enable a writable channel or use /w Name.") end
    self:Menu(anchor,targets,function(key) self:Switch(nil,key); focusIfWriter(self) end)
end
function Chat:OpenActions(anchor)
    self.peoplePanel:Hide()
    local items={}
    if self.peer or self.nativeSource then items[#items+1]={value="back",label="Return to channel mix"} end
    if self.anchor then items[#items+1]={value="latest",label="Jump to latest message"} end
    items[#items+1]={value="inbox",label="Whisper inbox"}
    if self:HasComposer() and self:Config().hideTarget then items[#items+1]={value="target",label="Choose sending destination"} end
    if self.peer and not self:HasComposer() then items[#items+1]={value="write",label="Whisper "..self.peer} end
    for _,entry in ipairs({
        {value="rules",label="Chat settings"},
        {value="copy",label="Copy current view"},
        {value="game",label="Game feed"},
        {value="combat",label="Combat log"},
        {value="new",label="New chat window"},
    }) do items[#items+1]=entry end
    self:Menu(anchor,items,function(action)
        if action=="rules" then self:EditRules()
        elseif action=="copy" then self:Copy()
        elseif action=="back" then self:Switch(nil,self.target)
        elseif action=="latest" then self.anchor=nil;self:Paint()
        elseif action=="inbox" then self:ToggleInbox()
        elseif action=="target" then self:ChooseTarget(anchor)
        elseif action=="new" then self:CreateChatWindow()
        elseif action=="write" then showConversation(self,self.peer,true)
        else self:OpenNativeFeed(action=="combat" and 2 or 1) end
    end)
end
function Chat:Notice(message)
    if not self.feedback then return end
    if self.feedbackTimer then self.feedbackTimer:Cancel() end
    if message:match("^Submitted to ") then self.feedback:Hide();return end
    self.status:SetText(message)
    self.feedback:Show()
    self.feedbackTimer=C_Timer.NewTimer(5,function()
        self.feedbackTimer=nil
        self.feedback:Hide()
    end)
end
function Chat:QueuePaint()
    if self.queued or not self.window or not self.window:IsShown() then return end
    self.queued=C_Timer.NewTimer(.12,function()
        self.queued=nil
        if self.running and self.window:IsShown() then self:Paint() end
    end)
end
function Chat:RefreshLoadedCaptions()
    if self.captionTimer then self.captionTimer:Cancel(); self.captionTimer=nil end
    self.refreshCaptions=true
    self:QueuePaint()
end
-- Local screenshot fixture: never dispatch chat events or write sample
-- identities to history, reply targets, unread state or SavedVariables.
local examples={
    {"COMBAT",nil,nil,"Your Frostbolt hits the training dummy for 318 Frost damage."},
    {"SAY","Tova","HUNTER","The airship is coming in."},
    {"WORLD","Neris","SHAMAN","The next zeppelin leaves from the east tower.","General"},
    {"TRADE","Varek","WARRIOR","Looking for a smith to make a shield.","Trade"},
    {"RAID","Tova","HUNTER","Group two, meet us at the bridge."},
    {"GUILD","Kaela","DRUID","I have the herbs. Who needs potions?"},
    {"PARTY","Neris","SHAMAN","I marked the entrance on the map."},
    {"WHISPER","Liora","PRIEST","Saved you a spot. Ready when you are!"},
    {"PARTY","Mira","MAGE","Portal is up by the fountain."},
    {"YELL","Varek","WARRIOR","Last call for the airship!"},
}
function Chat:SetChatPreview(on)
    if (Chat.previewChat~=nil)==on then return end
    if on then
        local rows={}
        for i,data in ipairs(examples) do
            rows[i]={source=data[1],author=data[2],key=data[2] and self:Key(data[2]),classToken=data[3],body=data[4],channel=data[5],
                id=i,stamp=string.format("18:%02d:%02d",40+math.floor(i/3),i*5),previewGroups={friend=data[1]=="WHISPER",guild=data[1]=="GUILD",party=data[1]=="PARTY"}}
        end
        Chat.previewChat=rows
    else Chat.previewChat=nil end
    for _,workspace in ipairs(Chat:ListWindows()) do
        if on then workspace.previewAnchor=workspace.anchor;workspace.anchor=nil
        else workspace.anchor=workspace.previewAnchor;workspace.previewAnchor=nil end
        workspace:Paint()
    end
end
function Chat:FeedRows()
    if Chat.previewChat then
        local rows={}
        for _,row in ipairs(Chat.previewChat) do
            if self.nativeSource==1 or (self.nativeSource==2 and row.source=="COMBAT")
                or (not self.nativeSource and (self.peer and row.source=="WHISPER" or self:Visible(row))) then
                rows[#rows+1]=row
            end
        end
        return rows
    end
    return self.nativeSource and {} or self:Rows(function(row)return self:Visible(row)end)
end
function Chat:Copy(row)
    if not self.copyWindow then self:Styled(function()
        local w=UI:Window(frameName(self,"BVChatCopy"),510,306,{title="Copy chat",minWidth=510,minHeight=306})
        self.copyWindow=w
        self.copyBox=at(UI:TransferText(w.content,480,185,0),w.content,12,8)
        at(UI:Label(w.content,"Select a passage or press Ctrl+A, then Ctrl+C.",13,"muted"),w.content,12,205)
    end) end
    local lines={}
    if row then lines[1]=self:Format(row,false)
    elseif self.nativeSource and not Chat.previewChat then
        self:ReadNative(function(text) if self.text(text) then lines[#lines+1]=self.plain(text) end end)
    else for _,r in ipairs(self:FeedRows()) do lines[#lines+1]=self:Format(r,false) end end
    self.copyWindow:Show()
    self.copyBox:SetText(table.concat(lines,"\n"))
    self.copyBox.input:SetFocus()
    self.copyBox.input:HighlightText()
end

local function rowMenu(self,button)
    local row=button.message
    if not row then return end
    local menu={{value="copy",label="Copy this line"}}
    if row.author then menu[#menu+1]={value="person",label="Whisper "..row.author} end
    for link,label in row.body:gmatch("|H(.-)|h(.-)|h") do
        if link:match("^item:") or link:match("^spell:") or link:match("^quest:") then
            menu[#menu+1]={value=link,label=self.plain(label)}
        end
    end
    self:Menu(button,menu,function(action)
        if action=="copy" then self:Copy(row)
        elseif action=="person" then showConversation(self,row.author,true)
        elseif SetItemRef then SetItemRef(action,"|H"..action.."|h[Link]|h","LeftButton") end
    end)
end
function Chat:Scroll(delta)
    local list=self.visibleRows or {}
    if #list==0 then return end
    local index=#list
    if self.anchor then
        while index>1 and list[index].id>self.anchor do index=index-1 end
    end
    if delta>0 and self.oldestVisible==list[1].id then return end
    index=math.max(1,math.min(#list,index-delta*3))
    self.anchor=index<#list and list[index].id or nil
    self:Paint()
end

local function paintCaption(button,label,startRefresh,refreshing)
    if startRefresh then button.loadingCaption=label end
    if not refreshing or label~=button.loadingCaption then button.loadingCaption=nil end
    button:SetText(button.loadingCaption and label.." " or label)
end

function Chat:Paint()
    local w=self.window
    if not self.running or not w or not w:IsShown() or not w.content:IsVisible() then return end
    local cfg=self:Config()
    self.pageTint:SetColorTexture(UI:RGBA(cfg.backgroundTint or "64829c0c"))
    local rows=self:FeedRows()
    self.visibleRows=rows
    local bottom=#rows
    while self.anchor and bottom>1 and rows[bottom].id>self.anchor do bottom=bottom-1 end
    local height=self.feed:GetHeight()
    local width=math.max(1,self.feed:GetWidth()-8)
    local used=0
    local canRead=not (Chat.previewChat or self.nativeSource or self.peoplePanel:IsShown() or self.suggestions:IsShown() or self.voicePanel and self.voicePanel:IsShown()
        or self.ruleWindow and self.ruleWindow:IsShown() or self.copyWindow and self.copyWindow:IsShown())
    self.oldestVisible=nil
    for index,button in ipairs(self.lines) do
        local row=rows[bottom-index+1]
        button:Hide()
        if row and used<height then
            button.caption:SetWidth(width)
            local tint,background=self:RowStyle(row)
            button.caption:SetText(self:Format(row,true,tint))
            if background then
                local r,g,b,a=UI:RGBA(background)
                button.tint:SetColorTexture(r,g,b,a)
                button.tint:SetShown(a>0)
            else
                button.tint:Hide()
            end
            local natural=math.max(M.ToNative(18),button.caption:GetStringHeight()+M.ToNative(4))
            local h=math.min(natural,height)
            if used+h<=height+.1 then
                button:ClearAllPoints()
                button:SetPoint("BOTTOMLEFT",self.feed,"BOTTOMLEFT",2,used)
                button:SetSize(width,h)
                button.message=row
                button:Show()
                used=used+h
                self.oldestVisible=row.id
                if canRead then self:MarkRowRead(row) end
            else used=height end
        end
    end
    self.empty:SetShown(#rows==0 and not self.nativeSource)
    local combat=false
    for _,v in ipairs(cfg.views) do if v.active and v.sources.COMBAT then combat=true end end
    self.empty:SetText(self.peer and "Your conversation starts here." or combat and "Open the combat log to view the game’s filter." or "New messages appear here.")
    local unread={}
    for _,stream in pairs(self.streams) do for i=1,stream.count do
        local row=stream[i]
        if not self:IsRowRead(row) then for _,v in ipairs(cfg.views) do
            if not v.quiet and (not v.active or self.peer or self.nativeSource) and self:Matches(v,row) then unread[v]=(unread[v] or 0)+1 end
        end end
    end end
    local pageSize=self.channelPageSize
    -- At login a native FontString may have the right text and width but no
    -- visible glyphs. Keep a distinct string across frames, even if chat
    -- traffic requests another paint, then restore the current labels.
    local startRefresh=self.refreshCaptions and not self.captionTimer
    if startRefresh then
        self.captionTimer=C_Timer.NewTimer(.2,function()
            self.captionTimer=nil
            self.refreshCaptions=nil
            self:QueuePaint()
        end)
    end
    local pages=math.ceil(#cfg.views/pageSize)
    self.tabPage=math.min(self.tabPage or 1,math.max(1,pages))
    for i,chip in ipairs(self.chips) do
        local v=i<=pageSize and cfg.views[(self.tabPage-1)*pageSize+i] or nil
        chip.view=v
        chip:SetShown(v~=nil and not self.peer and not self.nativeSource)
        if v then
            local selected=v.active and not self.peer and not self.nativeSource
            paintCaption(chip,v.name..(unread[v] and " · "..math.min(unread[v],99) or ""),startRefresh,self.refreshCaptions)
            chip:SetRole((selected or unread[v]) and "accentText" or "muted")
            chip.mark:SetShown(selected and true or false)
        end
    end
    local moreUnread=false
    for i,v in ipairs(cfg.views) do
        if math.ceil(i/pageSize)~=self.tabPage and unread[v] then moreUnread=true end
    end
    paintCaption(self.more,moreUnread and "•••" or "…",startRefresh,self.refreshCaptions)
    self.more:SetShown(pages>1 and not self.peer and not self.nativeSource)
    self.contextLabel:SetShown(self.peer~=nil or self.nativeSource~=nil)
    self.contextLabel:SetText((self.nativeSource==2 and "Combat log" or self.nativeSource and "Game feed") or (Chat.previewChat and self.peer and "Liora") or self.peer or "")
    local destination=self.nativeOverrideCaption or self.whisperTarget or self.labels[self.target] or self.targetLabel
    if self.nativeOverrideCaption then
        self.sendButton:Disable(); self.targetButton:Disable()
    else
        self.sendButton:Enable(); self.targetButton:Enable()
    end
    paintCaption(self.targetButton,destination or "Choose…",startRefresh,self.refreshCaptions)
    self.targetMeasure:SetText(destination or "Choose…")
    if self.placeholder then
        self.placeholder:SetText(cfg.hideTarget and destination and ("Write to "..destination.."…") or "Write a message…")
    end
    local canGoBack=self.peer~=nil or self.nativeSource~=nil
    local readerBack=canGoBack and not self:HasToolbar()
    if self.readerBackLayout~=readerBack or self.contextLayout~=canGoBack then
        self.readerBackLayout=readerBack
        self.contextLayout=canGoBack
        self:ApplyLayout()
        return
    end
    self.back:SetShown(canGoBack)
    self:ArrangeComposer(cfg,canGoBack)
    self.nativeFeed:SetShown(self.nativeSource~=nil and not Chat.previewChat)
    self.feed:SetShown(self.nativeSource==nil or Chat.previewChat~=nil)
    self.latest:SetShown(self.anchor~=nil and not self.nativeSource)
    self:ArrangeToolbar()
    if self.peoplePanel:IsShown() then self:ListPeople() end
end

function Chat:ListPeople()
    self.people=self:Conversations(self.peopleSearch:GetText())
    local pages=math.max(1, math.ceil(#self.people/#self.personButtons))
    self.peoplePage=math.min(self.peoplePage or 1,pages)
    local onPage=math.min(#self.personButtons,#self.people-(self.peoplePage-1)*#self.personButtons)
    M.Height(self.peoplePanel,72+37*math.max(1,onPage))
    for i,b in ipairs(self.personButtons) do
        local name=self.people[(self.peoplePage-1)*#self.personButtons+i]
        b.person=name
        if name then
            local key=self:Key(name)
            local unread,last=0,nil
            local stream=self.streams.private
            if stream then for j=1,stream.count do
                local row=stream[j]
                if row.key==key then
                    if not last or row.id>last.id then last=row end
                    if not self:IsRowRead(row) then unread=unread+1 end
                end
            end end
            b:SetText(name)
            b:SetRole(unread>0 and "accentText" or "text")
            b.detail:SetText(last and ((last.outgoing and "→ " or "← ")..self.plain(last.body)) or "")
            b.badge:SetText(unread>0 and tostring(math.min(unread,99)) or "")
        end
        b:SetShown(name~=nil)
    end
    self.peopleNext:SetText(self.peoplePage.." / "..pages.."  ›")
    self.peopleNext:SetShown(pages>1)
    self.peopleEmpty:SetShown(#self.people==0)
end

function Chat:Suggest()
    if not self.input then return end
    local prefix=self.input:GetText():match("^/[wW]%s+([^%s]+)$")
    local names=prefix and self:Suggestions(prefix) or {}
    M.Height(self.suggestions,33+25*#names)
    self.suggestions:SetShown(#names>0)
    for i,b in ipairs(self.picks) do
        b.person=names[i]
        b:SetShown(b.person~=nil)
        if b.person then b:SetText(b.person) end
    end
end
function Chat:Pick(name)
    if not name or not self.input then return end
    self.input:SetText("")
    self:SetAddress(name)
    focusIfWriter(self)
    self:Notice("Private to "..name.." · Enter sends")
end
local function rule(parent,style,role,alpha)
    local line=parent:CreateTexture(nil,"ARTWORK")
    style:Bind(function() line:SetColorTexture(style:Color(role,alpha)) end,line)
    return line
end

-- Chat chrome uses text on a shared surface. A quiet ink wash follows the
-- pointer, while the underline and counters keep their own persistent meaning.
local function textAction(parent,style,width,height,role,callback)
    local b=CreateFrame("Button",nil,parent)
    M.Size(b,width,height)
    b.wash=rule(b,style,"accent",.10)
    b.wash:SetAllPoints()
    b.wash:Hide()
    -- The caption has a full-height text rectangle even before the first
    -- paint. Only the button owns its color across palette/font refreshes.
    b.caption=style:Label(b,"",14,false,"bold")
    M.Point(b.caption,"TOPLEFT",b,"TOPLEFT",8,-1)
    M.Point(b.caption,"BOTTOMRIGHT",b,"BOTTOMRIGHT",-8,1)
    b.caption:SetJustifyH("LEFT")
    b.caption:SetWordWrap(false)
    b.textRole=role
    function b:SetText(value) self.caption:SetText(value) end
    function b:SetRole(value)
        self.textRole=value
        self.caption:SetTextColor(style:Color(self.over and "text" or value,1))
    end
    style:Bind(function() b:SetRole(b.textRole) end,b)
    b:SetScript("OnEnter",function() b.over=true;b.wash:Show();b:SetRole(b.textRole) end)
    b:SetScript("OnLeave",function() b.over=false;b.wash:Hide();b:SetRole(b.textRole) end)
    b:SetScript("OnHide",function() b.over=false;b.wash:Hide() end)
    b:SetScript("OnClick",callback)
    return b
end

local function inlineInput(parent,style,width)
    local input=style:Input(parent,width,false,nil,nil,true)
    UI:TextFieldMenu(input)
    return input
end

-- The actual message editor follows the selected window. Search boxes and
-- copy dialogs keep their own input fields and never become chat destinations.
local messageInput, messageHint, inputOwner

local function createMessageInput(workspace)
    local box=workspace.style:Input(workspace.composer,280,false)
    UI:TextFieldMenu(box)
    box:SetMaxLetters(380)
    if box.SetAltArrowKeyMode then box:SetAltArrowKeyMode(false) end
    local hint=UI:Label(box,"Write a message…",14,"muted")
    M.Point(hint,"LEFT",box,"LEFT",10,0)
    local function paintHint() hint:SetShown(box:GetText()=="" and not box:HasFocus()) end
    box:SetScript("OnEnterPressed",function() if inputOwner then inputOwner:Submit() end end)
    box:SetScript("OnEscapePressed",function()
        if inputOwner then inputOwner.suggestions:Hide() end
        box:ClearFocus()
    end)
    box:SetScript("OnTabPressed",function()
        if inputOwner and inputOwner.suggestions:IsShown() then inputOwner:Pick(inputOwner.picks[1].person) end
    end)
    box:HookScript("OnEditFocusGained",paintHint)
    box:HookScript("OnEditFocusLost",function()
        paintHint()
        if inputOwner then inputOwner:QueuePaint() end
    end)
    box:HookScript("OnTextChanged",function()
        paintHint()
        if inputOwner then inputOwner:Suggest() end
    end)
    return box,hint
end

function Chat:ReleaseComposer()
    if inputOwner~=self or not self.input then return end
    self.drafts[self:DraftKey()]=messageInput:GetText()
    messageInput:ClearFocus()
    messageInput:Hide()
    inputOwner=nil
    self.suggestions:Hide()
    self.input,self.placeholder,self.composerLayout=nil,nil,nil
    self.composer:Hide()
end

function Chat:AcquireComposer()
    if inputOwner==self then return end
    if inputOwner then inputOwner:ReleaseComposer() end
    if not messageInput then
        self:Styled(function() messageInput,messageHint=createMessageInput(self) end)
    end
    messageInput:SetParent(self.composer)
    messageInput:ClearAllPoints()
    inputOwner=self
    self.input,self.placeholder=messageInput,messageHint
    self.composerLayout=nil
    messageInput.bvHistory={}
    messageInput:SetText(self.drafts[self:DraftKey()] or "")
    messageInput.bvLastText=messageInput:GetText()
    messageInput:Show()
    self.bridge:RegisterWorkspace(self)
end

function Chat:ArrangeComposer(cfg,canGoBack)
    if not self.input then return end
    local back=false -- Return lives in the toolbar or beside the reader tabs.
    local leftInset=3
    local rightInset=cfg.hideSend and 3 or 35
    -- Measure an unconstrained copy: a clipped label must not shrink itself
    -- on the next paint. Leave most of a small window for the message.
    local available=M.GetWidth(self.window.content)-(self:HasToolbar() and 36 or 0)-4
    local targetWidth=math.max(48,math.min(120,available*.28,M.ToDesign(self.targetMeasure:GetStringWidth())+28))
    local layoutKey=leftInset.."/"..rightInset.."/"..tostring(cfg.hideTarget).."/"..targetWidth
    if self.composerLayout==layoutKey then return end
    self.composerLayout=layoutKey
    self.compactBack:SetShown(back)
    self.targetButton:ClearAllPoints()
    M.Width(self.targetButton,targetWidth)
    M.Point(self.targetButton,"LEFT",self.composer,"LEFT",leftInset,0)
    self.input:ClearAllPoints()
    M.Height(self.input,28)
    if cfg.hideTarget then
        M.Point(self.input,"LEFT",self.composer,"LEFT",leftInset,0)
    else M.Point(self.input,"LEFT",self.targetSplit,"RIGHT",2,0) end
    M.Point(self.input,"RIGHT",self.composer,"RIGHT",-rightInset,0)
end

function Chat:ApplyLayout()
    local w=self.window
    if not w or not self.suggestions then return end
    local cfg=self:Config()
    if w.hudSurface then w.hudSurface:Refresh() end
    local c,rail,tray=self.window.content,self.tabBar,self.composer
    local writer=self:HasComposer()
    if writer then self:AcquireComposer() else self:ReleaseComposer() end
    tray:SetShown(writer)
    local primary=self:HasToolbar()
    local leftInset=primary and self:ToolbarSide()=="left" and 36 or 0
    local rightInset=primary and self:ToolbarSide()=="right" and 36 or 0
    local context=self.peer~=nil or self.nativeSource~=nil
    local readerBack=context and not primary
    self.readerBackLayout=readerBack
    self.contextLayout=context
    local headerHeight=3
    self.tabBar:SetShown(not cfg.hideTabs or context)
    self.sendButton:SetShown(not cfg.hideSend)
    self.targetButton:SetShown(not cfg.hideTarget)
    self.targetSplit:SetShown(not cfg.hideTarget)

    rail:ClearAllPoints()
    M.Point(rail,"TOPLEFT",c,"TOPLEFT",leftInset+(readerBack and 30 or 0),-headerHeight)
    M.Point(rail,"TOPRIGHT",c,"TOPRIGHT",-rightInset,-headerHeight)
    local belowNavigation=headerHeight+((not cfg.hideTabs or context) and 26 or 0)
    if self.arrangeTabs then self.arrangeTabs() end
    tray:ClearAllPoints()
    if cfg.composerTop then
        M.Point(tray,"TOPLEFT",c,"TOPLEFT",leftInset+2,-belowNavigation)
        M.Point(tray,"TOPRIGHT",c,"TOPRIGHT",-rightInset-2,-belowNavigation)
    else
        M.Point(tray,"BOTTOMLEFT",c,"BOTTOMLEFT",leftInset+2,2)
        M.Point(tray,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-rightInset-2,2)
    end
    self:ArrangeComposer(cfg,self.peer~=nil or self.nativeSource~=nil)

    self.composerLine:ClearAllPoints()
    local edge=cfg.composerTop and "BOTTOM" or "TOP"
    self.composerLine:SetPoint(edge.."LEFT",tray,edge.."LEFT")
    self.composerLine:SetPoint(edge.."RIGHT",tray,edge.."RIGHT")
    self.feed:ClearAllPoints()
    M.Point(self.feed,"TOPLEFT",c,"TOPLEFT",leftInset+12,-(belowNavigation+(writer and cfg.composerTop and COMPOSER_HEIGHT+5 or 5)))
    M.Point(self.feed,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-rightInset-12,writer and not cfg.composerTop and COMPOSER_HEIGHT+9 or 9)
    self.suggestions:ClearAllPoints()
    self.feedback:ClearAllPoints()
    local out=cfg.composerTop and "TOP" or "BOTTOM"
    local inset=cfg.composerTop and -3 or 3
    if writer then
        M.Point(self.suggestions,out.."LEFT",self.input,edge.."LEFT",0,inset)
        M.Point(self.feedback,out.."LEFT",tray,edge.."LEFT",8,inset)
        M.Point(self.feedback,out.."RIGHT",tray,edge.."RIGHT",-8,inset)
    else
        self.suggestions:Hide()
        M.Point(self.feedback,"BOTTOMLEFT",c,"BOTTOMLEFT",8,4)
        M.Point(self.feedback,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-8,4)
    end
    self.peoplePanel:ClearAllPoints()
    if primary and self:ToolbarSide()=="left" then
        M.Point(self.peoplePanel,"TOPLEFT",c,"TOPLEFT",leftInset+5,-headerHeight)
    else M.Point(self.peoplePanel,"TOPRIGHT",c,"TOPRIGHT",-rightInset-8,-headerHeight) end
    self:ArrangeToolbar()
    self:Paint()
end

function Chat:Build()
    local w=CreateFrame("Frame",frameName(self,"BVChatWorkspace"),UIParent)
    w:Hide()
    w:SetFrameStrata("LOW")
    M.Size(w,535,265)
    if core.ExternalFrames then core.ExternalFrames:MarkOwned(w) end
    self.style:Skin(w,"bg",4,.89)
    core.InterfaceSurfaces:AttachHUD(self.style,w,function()return self:Config().hideTexture and 0 or 1 end)
    self.window=w
    w.content=CreateFrame("Frame",nil,w)
    local c=w.content
    c:SetAllPoints()
    self:BuildToolbar()
    local rail=CreateFrame("Frame",nil,c)
    self.tabBar=rail
    M.Height(rail,26)
    self.contextLabel=UI:Label(rail,"",14,"accentText",true)
    M.Point(self.contextLabel,"LEFT",rail,"LEFT",12,0)
    M.Point(self.contextLabel,"RIGHT",rail,"RIGHT",-12,0)
    self.contextLabel:SetJustifyH("LEFT");self.contextLabel:SetWordWrap(false)
    self.contextLabel:Hide()
    local hair=rule(rail,self.style,"edge",.65)
    M.Point(hair,"BOTTOMLEFT",rail,"BOTTOMLEFT",12,0)
    M.Point(hair,"BOTTOMRIGHT",rail,"BOTTOMRIGHT",-12,0)
    M.Height(hair,1)
    self.chips={}
    for i=1,6 do
        local b=textAction(rail,self.style,76,25,"muted",function(button,which)
            if which=="RightButton" then self:OpenActions(button)
            else self:Toggle(button.view) end
        end)
        b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        b.caption:SetJustifyH("CENTER")
        b.mark=rule(b,self.style,"accent",.90)
        M.Point(b.mark,"BOTTOMLEFT",b,"BOTTOMLEFT",8,0)
        M.Point(b.mark,"BOTTOMRIGHT",b,"BOTTOMRIGHT",-8,0)
        M.Height(b.mark,2)
        b:HookScript("OnEnter",function(button) if button.view then
            local hint=button.view.active and "Remove from channel mix" or "Add to channel mix"
            UI:ShowTooltip(button,button.view.name,hint.."\nRight-click: chat actions")
        end end)
        b:HookScript("OnLeave",function() UI:HideTooltip() end)
        self.chips[i]=b
    end
    self.more=textAction(rail,self.style,26,25,"muted",function()
        local pages=math.max(1,math.ceil(#self:Config().views/self.channelPageSize))
        self.tabPage=self.tabPage%pages+1
        self:Paint()
    end)
    self.more.caption:SetJustifyH("CENTER")
    M.Point(self.more,"TOPRIGHT",rail,"TOPRIGHT",-7,0)
    UI:AttachTooltip(self.more,"Next channel page")
    local function arrangeTabs()
        local available=math.max(200,M.GetWidth(w)-42-(self:HasToolbar() and 36 or 0)-(self.readerBackLayout and 30 or 0))
        self.channelPageSize=math.max(4,math.min(#self.chips,math.floor(available/76)))
        local cell=math.min(110,available/self.channelPageSize)
        for i,tab in ipairs(self.chips) do
            tab:ClearAllPoints()
            M.Width(tab,cell)
            M.Point(tab,"TOPLEFT",rail,"TOPLEFT",8+(i-1)*cell,0)
        end
    end
    self.arrangeTabs=arrangeTabs
    arrangeTabs()
    local function icon(symbol,x,hint,fn)
        local b=UI:IconButton(self.toolbar,symbol,fn,"icon-only")
        UI:AttachTooltip(b,hint)
        return b
    end
    self.back=icon("arrow-left",-74,"Return to channel mix",function() self:Switch(nil,self.target) end)
    self.inboxAction=icon("mail",-40,"Whisper inbox",function() self:ToggleInbox() end)
    local settings=icon("sliders-horizontal",-6,"Chat settings",function() self:EditRules() end)
    self.settingsAction=settings
    self.gameAction=icon("swords",0,"Game feed and combat log",function(b) self:GameFeedMenu(b) end)
    self.voiceAction=icon("volume-2",0,"Sound & voice",function() self:ToggleVoicePanel() end)
    self.copyAction=icon("copy",0,"Copy current view",function() self:Copy() end)
    settings:RegisterForClicks("LeftButtonUp","RightButtonUp")
    local openSettings=settings:GetScript("OnClick")
    settings:SetScript("OnClick",function(b,which)
        if which=="RightButton" then self:OpenActions(b) else openSettings(b,which) end
    end)
    UI:AttachTooltip(settings,"Chat settings","Click to configure this window. Right-click for chat actions.")
    self.feed=CreateFrame("Frame",nil,c)
    self.pageTint=c:CreateTexture(nil,"BACKGROUND")
    self.pageTint:SetAllPoints(self.feed)
    self:BuildNativeFeed(c)
    self.feed:EnableMouseWheel(true)
    self.feed:SetScript("OnMouseWheel",function(_,delta) self:Scroll(delta) end)
    self.lines={}
    for i=1,60 do
        local b=CreateFrame("Button",nil,self.feed)
        b.tint=b:CreateTexture(nil,"BACKGROUND")
        b.tint:SetAllPoints()
        b.caption=UI:Label(b,"",14,"text")
        b.caption:SetPoint("LEFT",b,"LEFT",0,0)
        b.caption:SetJustifyH("LEFT")
        b.caption:SetWordWrap(true)
        if b.SetHyperlinksEnabled then
            b:SetHyperlinksEnabled(true)
            b:SetScript("OnHyperlinkClick",function(_,link,text,button)
                if Chat.text(link) and SetItemRef then SetItemRef(link,text,button) end
            end)
        end
        b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        b:SetScript("OnClick",function(button,which)
            if Chat.previewChat then return end
            if which=="RightButton" then rowMenu(self,button)
            elseif button.message.author then showConversation(self,button.message.author,false)
            else rowMenu(self,button) end
        end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel",self.feed:GetScript("OnMouseWheel"))
        self.lines[i]=b
    end
    self.empty=UI:Label(self.feed,"",14,"muted")
    self.empty:SetPoint("CENTER");self.empty:SetWidth(M.ToNative(380));self.empty:SetJustifyH("CENTER")
    self.latest=icon("arrow-down-to-line",-108,"Jump to latest message",function() self.anchor=nil;self:Paint() end)
    local tray=CreateFrame("Frame",nil,c)
    self.composer=tray
    M.Height(tray,COMPOSER_HEIGHT)
    local trayFill=rule(tray,self.style,"panel",.66)
    trayFill:SetAllPoints()
    self.composerLine=rule(tray,self.style,"edge",.6)
    M.Height(self.composerLine,1)
    self.compactBack=UI:IconButton(tray,"arrow-left",function()
        self:Switch(nil,self.target)
    end,"icon-only")
    M.Point(self.compactBack,"LEFT",tray,"LEFT",3,0)
    UI:AttachTooltip(self.compactBack,"Return to channel mix")
    self.targetButton=textAction(tray,self.style,72,28,"accentText",function(b) self:ChooseTarget(b) end)
    M.Point(self.targetButton,"LEFT",tray,"LEFT",4,0)
    self.targetMeasure=UI:Label(tray,"",14,"accentText",true)
    self.targetMeasure:Hide()
    self.targetButton.caption:ClearAllPoints()
    M.Point(self.targetButton.caption,"LEFT",self.targetButton,"LEFT",5,0)
    M.Point(self.targetButton.caption,"RIGHT",self.targetButton,"RIGHT",-20,0)
    self.targetButton:HookScript("OnEnter",function(b)UI:ShowTooltip(b,"Send to: "..(self.targetMeasure:GetText() or "Choose…"),"Choose where your next message goes.")end)
    self.targetButton:HookScript("OnLeave",function()UI:HideTooltip()end)
    local caret=UI:Icon(self.targetButton,"chevron-down",12,"muted")
    M.Point(caret,"RIGHT",self.targetButton,"RIGHT",-4,0)
    local split=rule(tray,self.style,"edge",.55)
    self.targetSplit=split
    M.Point(split,"LEFT",self.targetButton,"RIGHT",1,0)
    M.Size(split,1,18)
    local send=UI:IconButton(tray,"send",function() self:Submit() end,"icon-only")
    self.sendButton=send
    M.Size(send,28,28)
    M.Point(send,"RIGHT",tray,"RIGHT",-3,0)
    UI:AttachTooltip(send,"Send message")
    self.feedback=CreateFrame("Frame",nil,c)
    self.feedback:SetFrameLevel(c:GetFrameLevel()+5)
    self.style:Skin(self.feedback,"bg",3,.98)
    M.Point(self.feedback,"BOTTOMLEFT",tray,"TOPLEFT",8,2)
    M.Point(self.feedback,"BOTTOMRIGHT",tray,"TOPRIGHT",-8,2)
    M.Height(self.feedback,28)
    self.status=UI:Label(self.feedback,"",13,"text")
    M.Point(self.status,"LEFT",self.feedback,"LEFT",8,0)
    M.Point(self.status,"RIGHT",self.feedback,"RIGHT",-8,0)
    self.status:SetJustifyH("LEFT"); self.status:SetWordWrap(false)
    self.feedback:Hide()
    local pane=CreateFrame("Frame",nil,c)
    self.peoplePanel=pane
    self.style:Skin(pane,"bg",4,1)
    pane:SetFrameLevel(c:GetFrameLevel()+12)
    pane:EnableMouse(true)
    M.Size(pane,264,257)
    pane:SetClampedToScreen(true)
    M.Point(pane,"TOPRIGHT",c,"TOPRIGHT",-8,-37)
    local inboxLabel=UI:Label(pane,"Whispers",17,"text",true)
    M.Point(inboxLabel,"TOPLEFT",pane,"TOPLEFT",12,-8)
    local closeInbox=UI:IconButton(pane,"x",function()
        pane:Hide(); focusIfWriter(self)
    end,"icon-only")
    M.Point(closeInbox,"TOPRIGHT",pane,"TOPRIGHT",-5,-2)
    UI:AttachTooltip(closeInbox,"Back to chat")
    local lens=UI:Icon(pane,"search",13,"muted")
    M.Point(lens,"TOPLEFT",pane,"TOPLEFT",13,-43)
    self.peopleSearch=at(inlineInput(pane,self.style,155),pane,25,33)
    local queryHint=UI:Label(self.peopleSearch,"Find a conversation",13,"muted")
    M.Point(queryHint,"LEFT",self.peopleSearch,"LEFT",10,0)
    self.peopleSearch:HookScript("OnTextChanged",function(box) queryHint:SetShown(box:GetText()=="") end)
    self.peopleSearch:SetScript("OnEscapePressed",function() pane:Hide();focusIfWriter(self) end)
    self.peopleSearch:HookScript("OnTextChanged",function() self.peoplePage=1; self:ListPeople() end)
    self.peopleNext=at(textAction(pane,self.style,71,28,"muted",function()
        self.peoplePage=self.peoplePage%math.max(1,math.ceil(#self.people/5))+1;self:ListPeople()
    end),pane,185,35)
    local divider=rule(pane,self.style,"edge",.55)
    M.Point(divider,"TOPLEFT",pane,"TOPLEFT",10,-65)
    M.Point(divider,"TOPRIGHT",pane,"TOPRIGHT",-10,-65)
    M.Height(divider,1)
    self.personButtons={}
    for i=1,5 do
        local b=textAction(pane,self.style,248,37,"text",function(button)
            pane:Hide(); showConversation(self,button.person,false)
        end)
        b.caption:ClearAllPoints()
        M.Point(b.caption,"TOPLEFT",b,"TOPLEFT",5,-2);M.Width(b.caption,203)
        b.detail=UI:Label(b,"",12,"muted")
        M.Point(b.detail,"BOTTOMLEFT",b,"BOTTOMLEFT",5,3);M.Width(b.detail,221)
        b.detail:SetJustifyH("LEFT");b.detail:SetWordWrap(false)
        b.badge=UI:Label(b,"",12,"accentText",true)
        M.Point(b.badge,"TOPRIGHT",b,"TOPRIGHT",-8,-4)
        self.personButtons[i]=at(b,pane,8,68+(i-1)*37)
    end
    self.peopleEmpty=at(UI:Label(pane,"No matching conversations",13,"muted"),pane,13,76)
    pane:HookScript("OnHide",function() self.peopleSearch:ClearFocus() end)
    pane:Hide()
    local popup=CreateFrame("Frame",nil,c)
    self.suggestions=popup
    self.style:Skin(popup,"bg",4,.99)
    popup:SetFrameLevel(c:GetFrameLevel()+14)
    M.Size(popup,246,170)
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    at(UI:Label(popup,"WHISPER TO",11,"accentText",true),popup,12,9)
    local keyHint=UI:Label(popup,"Tab selects first",11,"muted")
    M.Point(keyHint,"TOPRIGHT",popup,"TOPRIGHT",-12,-9)
    self.picks={}
    for i=1,8 do
        local b=textAction(popup,self.style,236,25,i==1 and "accentText" or "text",function(button) self:Pick(button.person) end)
        self.picks[i]=at(b,popup,5,28+(i-1)*25)
    end
    popup:Hide()
    -- The frame edge remains available when the tabs are hidden.
    -- It is outside the transcript, so it never intercepts links or text selection.
    local rim=CreateFrame("Button",nil,c)
    self.actionEdge=rim
    M.Point(rim,"TOPLEFT",c,"TOPLEFT",0,-3)
    M.Point(rim,"BOTTOMLEFT",c,"BOTTOMLEFT",0,3)
    M.Width(rim,8)
    rim:SetFrameLevel(c:GetFrameLevel()+3)
    rim:RegisterForClicks("RightButtonUp")
    rim:SetScript("OnClick",function() self:OpenActions(rim) end)
    UI:AttachTooltip(rim,"Chat actions","Right-click for settings and views.")
    w:HookScript("OnShow",function() self:QueuePaint() end)
    w:HookScript("OnHide",function() pane:Hide();popup:Hide();self.feedback:Hide()
        for _,key in ipairs({"queued","captionTimer","feedbackTimer"}) do
            if self[key] then self[key]:Cancel();self[key]=nil end
        end
        if self.voicePanel then self.voicePanel:Hide() end
        if self.ruleWindow then self.ruleWindow:Hide() end
        if self.copyWindow then self.copyWindow:Hide() end
    end)
    w:HookScript("OnSizeChanged",function() arrangeTabs();self:QueuePaint() end)
    self:PlaceLayoutWindow()
end
function Chat:Show()
    self.style=UI:InterfaceStyle()
    if not self.style then return end
    if not self.window then self:Styled(function() self:Build() end) end
    self.window:Show()
    self:ApplyLayout()
end

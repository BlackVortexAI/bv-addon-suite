local _, Chat = ...
if not Chat.core then return end
local core=Chat.core
local UI,at,M=core.UI,Chat.at,core.DesignSystem.Metrics
local page, openRules
local layoutOptions={
    {"composerTop","Put the input above messages"},
    {"hideTabs","Chat tabs"},
    {"hideSend","Send button"},
    {"hideTarget","Sending destination"},
    {"hideTexture","Show window texture"},
}
local function selector(parent,x,y,width,choices,choose)
    local control=at(UI:Dropdown(parent,width,{},choose),parent,x,y)
    control:SetOptionsProvider(choices)
    return control
end

local function useSelection(control,items,key)
    control:SetOptions(items)
    control:SetValue(key)
end

function Chat:TabChoices()
    local list={}
    for i,tab in ipairs(self:Config().views) do list[#list+1]={value=i,label=tab.name} end
    return list
end

function Chat:LoadRule(index)
    local cfg=self:Config()
    local tab=cfg.views[index]
    self.editIndex=index
    self.rule=tab or {sources={},name="",active=true}
    self.ruleName:SetText(self.rule.name)
    useSelection(self.selector,self:TabChoices(),index)
    if not tab then self.selector:SetLabelText("New tab") end
    self.nameAction:SetText(tab and "Rename" or "Create tab")
    if tab and #cfg.views>1 then self.removeTab:Enable() else self.removeTab:Disable() end
    for key,control in pairs(self.sourceButtons) do control:SetValue(self.rule.sources[key]==true) end
    self.channelPage=1
    self:UpdateNamedSources()
    self:RefreshWhisperOptions()
    self.notifyButton:SetValue(not self.rule.quiet)
    self:RefreshFormatFields()
    self:RefreshTabStyle()
    self.bgTint:SetValue(cfg.backgroundTint or "64829c0c")
    self.ruleHint:SetText(tab and "Changes apply immediately." or "Name this tab and choose its messages.")
    self.renameActive=not tab
    if self.arrangeSettings then self.arrangeSettings() end
end

function Chat:CommitTabName()
    local cfg=self:Config()
    local name=self.ruleName:GetText():match("^%s*(.-)%s*$")
    if name=="" or name:find("[%c|]") then return self.ruleHint:SetText("Enter a tab name.") end
    for i,tab in ipairs(cfg.views) do
        if i~=self.editIndex and tab.name:lower()==name:lower() then return self.ruleHint:SetText("That tab name is already in use.") end
    end
    local whispers=self.rule.scope=="all" or self.rule.scope=="party" or self.rule.scope=="raid" or
        (self.rule.scope=="selected" and next(self.rule.whisperGroups or {})~=nil)
    if not cfg.views[self.editIndex] and not (next(self.rule.sources) or whispers) then
        return self.ruleHint:SetText("Select a channel, message type or whisper group first.")
    end
    self.rule.name=name
    cfg.views[self.editIndex]=self.rule
    self.ruleName:ClearFocus()
    self:LoadRule(self.editIndex)
    self:Paint()
end

function Chat:RuleChanged()
    self:UpdateChatSample()
    if self:Config().views[self.editIndex]~=self.rule then return end
    if self.target and not self.whisperTarget and not self:AllowsTarget(self.target) then self:Switch(nil,nil) else self:Paint() end
end

function Chat:SetNamedSource(channel,on)
    local sources=self.rule.sources
    if not on and sources[channel.source] then
        -- Freeze only this group to today's members. Keep the other group,
        -- exact offline choices and non-channel message types intact.
        sources[channel.source]=nil
        for _,entry in ipairs(self:ChannelChoices(sources)) do
            if entry.joined and entry.source==channel.source then sources[entry.key]=true end
        end
        if self.sourceButtons[channel.source] then self.sourceButtons[channel.source]:SetValue(false) end
        self.ruleHint:SetText("Using individual channels now. New channels can be added here.")
    end
    sources[channel.key]=on or nil
    self:UpdateNamedSources()
    self:RuleChanged()
end

local CHANNELS_PER_PAGE=4
function Chat:UpdateNamedSources()
    local choices=self:ChannelChoices(self.rule.sources)
    local pages=math.max(1,math.ceil(#choices/CHANNELS_PER_PAGE))
    self.channelPage=math.max(1,math.min(self.channelPage or 1,pages))
    self.channelsPrevious:SetShown(pages>1)
    self.channelsNext:SetShown(pages>1)
    if self.channelPage>1 then self.channelsPrevious:Enable() else self.channelsPrevious:Disable() end
    if self.channelPage<pages then self.channelsNext:Enable() else self.channelsNext:Disable() end
    self.channelsPage:SetText(pages>1 and (self.channelPage.." / "..pages) or "")
    self.noChannels:SetShown(#choices==0)
    for i,control in ipairs(self.joinedChecks) do
        local ch=choices[(self.channelPage-1)*CHANNELS_PER_PAGE+i]
        control.channel=ch
        if ch then
            local name=ch.id and (ch.id..". "..ch.name) or (ch.name.." · not joined")
            local inherited=self.rule.sources[ch.source]==true
            control.label:SetText(name)
            control:SetValue(inherited or self.rule.sources[ch.key]==true)
            UI:AttachTooltip(control,name,inherited and "Uncheck to switch this group to individual channels. Other joined channels in this group stay selected." or "Show this channel in the selected tab.")
        end
        control:SetShown(ch~=nil)
    end
end

local relationshipNames={friend="Friends",guild="Guild members",party="Party members",raid="Raid members"}
local function senderRuleName(rule)
    return relationshipNames[rule.key] or (rule.names and rule.names[1]) or "Player names"
end
local function senderChoices(rules)
    local items={}
    for i,rule in ipairs(rules) do items[i]={value=rule.key,label=i..". "..senderRuleName(rule)} end
    return items
end
local formatRoles={
    {key="time",label="Time"},
    {key="channel",label="Channel"},
    {key="sender",label="Sender"},
    {key="message",label="Message"},
}
local timeFormats={{value="short",label="24-hour · 18:42"},{value="long",label="24-hour with seconds · 18:42:07"},
    {value="12h",label="12-hour · 6:42 PM"},{value="off",label="Hide the time"}}
local channelModes={{value="full",label="Full name · Party"},{value="short",label="Abbreviation · P"},
    {value="icon",label="Channel icon"}}
local namedModes={{value="inherit",label="Use shared default"},{value="full",label="Full name"},
    {value="short",label="Abbreviation"},{value="icon",label="Channel icon"}}

function Chat:LabelScopeChoices()
    local items={{value="all",label="All channels · default"}}
    local overrides=self:MessageStyle().channelModes or {}
    self.scopeEntries={}
    for _,ch in ipairs(self:ChannelChoices(overrides)) do
        if ch.joined or overrides[ch.key] then
            items[#items+1]={value=ch.key,label=ch.id and (ch.id..". "..ch.name) or (ch.name.." · not joined")}
            self.scopeEntries[ch.key]=ch
        end
    end
    return items
end

function Chat:RefreshLabelScope()
    local style=self:MessageStyle()
    local items=self:LabelScopeChoices()
    if not self.scopeEntries[self.labelScope] then self.labelScope="all" end
    useSelection(self.channelScope,items,self.labelScope)
    local mode=self.labelScope=="all" and style.channelMode or (style.channelModes or {})[self.labelScope] or "inherit"
    useSelection(self.channelMode,self.labelScope=="all" and channelModes or namedModes,mode)
end

function Chat:RefreshChannelChoices()
    if self.rule and self.ruleWindow and self.ruleWindow:IsShown() then
        self:UpdateNamedSources()
        self:RefreshLabelScope()
        self:RefreshTypeFields()
        self:UpdateChatSample()
    end
end

function Chat:RefreshFormatFields()
    local style=self:MessageStyle()
    self.classNames:SetValue(style.classNames)
    for _,role in ipairs(formatRoles) do
        self.formatColors[role.key]:SetValue(style.colors[role.key].."ff")
    end
    useSelection(self.timeFormat,timeFormats,style.timeFormat)
    self:RefreshLabelScope()
end

function Chat:UpdateChatSample()
    if not self.tabSample or not self.rule then return end
    local function rowFor(source,groups,body,author)
        local entry=self.typeEntries and self.typeEntries[source]
        return {stamp="18:42:07",source=entry and entry.source or source,body=body or "Ready when you are.",author=author or "Mira",
            classToken=author=="Liora" and "PRIEST" or author=="Enyo" and "WARRIOR" or "MAGE",
            previewGroups=groups or {},channel=entry and entry.key:sub(1,1)=="#" and entry.name or nil,
            channelKey=entry and entry.key:sub(1,1)=="#" and entry.key or nil}
    end
    local function paint(host,row,tint,background,layer)
        if not host then return end
        host.fill:SetColorTexture(UI:RGBA(self:Config().backgroundTint or "64829c0c"))
        if row and not layer then
            row.key=row.author and self:Key(row.author)
            background=self:SenderBackground(row,background)
        end
        host.row:SetColorTexture(UI:RGBA(background or "00000000"))
        host.text:SetText(row and self:Format(row,true,tint,layer) or "No messages selected.")
        host.tooltipTitle=row and (row.channel or self.labels[row.source] or row.source) or "Tab preview"
    end
    local sample=rowFor("PARTY")
    local named=self.scopeEntries and self.scopeEntries[self.labelScope]
    local shared=named and {stamp="18:42:07",source=named.source,author="Mira",classToken="MAGE",body="Ready when you are.",
        channel=named.name,channelKey=named.key,previewGroups={}} or sample
    paint(self.sharedSample,shared,nil,nil,"base")
    if self.sharedSamples then
        paint(self.sharedSamples[2],rowFor("WHISPER",nil,"Do you have a moment?","Liora"),nil,nil,"base")
        paint(self.sharedSamples[3],rowFor("GUILD",nil,"Meet at the flight master.","Enyo"),nil,nil,"base")
    end
    paint(self.tabBaseline,sample)
    paint(self.tabSample,sample,self.rule.tint,self.rule.background)
    local source=self.editType or "WHISPER"
    paint(self.typeBase,rowFor(source),nil,nil,"base")
    paint(self.typeSample,rowFor(source),nil,nil,"type")
    if self.typeSamples then
        paint(self.typeSamples[2],rowFor(source,nil,"The boat is arriving.","Enyo"),nil,nil,"type")
        paint(self.typeSamples[3],rowFor(source,nil,"On my way.","Liora"),nil,nil,"type")
    end
    local matches={}
    local candidates={"WHISPER","PARTY","GUILD","SAY","YELL","RAID","OFFICER","INSTANCE_CHAT","SYSTEM","WORLD","TRADE","COMBAT"}
    for _,entry in ipairs(self:ChannelChoices(self.rule.sources)) do candidates[#candidates+1]=entry.key end
    for _,key in ipairs(candidates) do
        local candidate=rowFor(key,{friend=true,guild=true,party=true,raid=true})
        if self:Matches(self.rule,candidate) then matches[#matches+1]=candidate end
    end
    local bodies={"Ready when you are.","Meet at the flight master.","On my way."}
    for i,host in ipairs(self.sourceSamples or {self.sourceSample})do
        local row=matches[i] or matches[1]
        if row then
            local copy={};for key,value in pairs(row)do copy[key]=value end
            copy.body=bodies[i] or bodies[1];copy.author=({"Mira","Enyo","Liora"})[i]or"Mira";row=copy
        end
        paint(host,row,self.rule.tint,self.rule.background)
        host:SetShown(i==1 or row~=nil)
    end
    if self.unreadSample then
        self.unreadSample:SetText((self.rule.name~="" and self.rule.name or "New tab")..(self.rule.quiet and "   ·   No unread highlight" or "   • 3 new messages"))
    end
    if self.senderSamples then
        local rule=self.editSender
        if self.senderRuleStatus then self.senderRuleStatus:SetText(rule and rule.enabled and "First active matching rule wins." or "Selected rule is disabled.") end
        local source=rule and rule.scope~="all" and rule.scope or "WHISPER"
        for _,host in ipairs(self.senderSamples) do
            local groups=host.groups or {[self.senderKey or "friend"]=true}
            local row=rowFor(source,groups,nil,not host.groups and rule and rule.names and rule.names[1])
            paint(host,row)
            local winner=self.SenderRule and self:SenderRule(row)
            local match=winner and senderRuleName(winner) or "No match"
            if not host.groups then host.legend:SetText("Selected example · "..match) end
            UI:AttachTooltip(host,host.tooltipTitle,"Matching rule: "..match)
        end
    end
end

function Chat:RefreshTabStyle()
    local tint=self.rule.tint or "91aee500"
    self.ruleTint:SetValue(tint:sub(1,6).."ff")
    local strength=math.floor((tonumber(tint:sub(7,8),16) or 0)*100/255+.5)
    self.settingTintSlider=true
    self.tintStrength:SetValue(strength)
    self.settingTintSlider=nil
    self.tintValue:SetText(strength.."%")
    self.tabBackground:SetValue(self.rule.background or "00000000")
    self:UpdateChatSample()
end

local function preview(parent,x,y,caption)
    local host=at(CreateFrame("Frame",nil,parent),parent,x,y)
    host.fill=host:CreateTexture(nil,"BACKGROUND");host.fill:SetAllPoints()
    host.row=host:CreateTexture(nil,"ARTWORK")
    host.text=UI:Label(host,"",14,"text");host.text:SetJustifyH("LEFT")
    if caption then
        host.legend=UI:Label(host,caption,11,"muted",true);host.legend:SetJustifyH("LEFT")
    end
    function host:Arrange(width,compact)
        M.Size(self,width,compact and 26 or 58)
        self.text:ClearAllPoints();self.row:ClearAllPoints()
        if compact and self.legend then
            self.legend:ClearAllPoints();M.Point(self.legend,"LEFT",self,"LEFT",0,0);M.Width(self.legend,112)
            M.Point(self.text,"LEFT",self,"LEFT",116,0);M.Point(self.text,"RIGHT",self,"RIGHT",-3,0)
            M.Point(self.row,"TOPLEFT",self,"TOPLEFT",114,-1);M.Point(self.row,"BOTTOMRIGHT",self,"BOTTOMRIGHT",0,1)
            self.text:SetWordWrap(false)
        else
            if self.legend then
                self.legend:ClearAllPoints();M.Point(self.legend,"TOPLEFT",self,"TOPLEFT",0,0);M.Width(self.legend,width)
            end
            M.Point(self.text,"TOPLEFT",self,"TOPLEFT",4,self.legend and -19 or -5);M.Point(self.text,"TOPRIGHT",self,"TOPRIGHT",-4,self.legend and -19 or -5)
            M.Height(self.text,self.legend and 36 or 48);self.text:SetWordWrap(true)
            M.Point(self.row,"TOPLEFT",self,"TOPLEFT",0,self.legend and -17 or 0);M.Point(self.row,"BOTTOMRIGHT",self,"BOTTOMRIGHT",0,0)
        end
    end
    host:Arrange(330,false)
    host:EnableMouse(true);UI:AttachTooltip(host,"Party","Channel used by this example.")
    return host
end

local function sharedChanged(owner)
    owner:UpdateChatSample()
    owner:QueueAllWindows()
end

function Chat:RefreshLayoutOptions()
    if not self.editingWindow then return end
    local config=self:Config()
    useSelection(self.editingWindow,self.windowChoices(),self:WindowID())
    self.layoutInfo:SetText(self:HasComposer() and "This window owns the input. Enter starts typing here." or
        "Reading window. Move the shared input here when you want to type in this window.")
    for key,control in pairs(self.layoutChecks) do
        if key=="composerTop" then control:SetValue(config[key]==true) else control:SetValue(not config[key]) end
        local needsInput=key=="composerTop" or key=="hideSend" or key=="hideTarget"
        if not needsInput or self:HasComposer() then control:Enable() else control:Disable() end
    end
    if self.restoreLayout then
        if config.previousChatLayout then self.restoreLayout:Enable() else self.restoreLayout:Disable() end
    end
    if self.mainInfo then
        local main=Chat:MainWindow()
        self.mainInfo:SetText("Main window: "..main:WindowName())
        if main==self then self.makeMain:Disable() else self.makeMain:Enable() end
        self.makeMain:SetText(main==self and "This is the main window" or "Make this the main window")
        useSelection(self.toolbarSide,{{value="left",label="Toolbar on the left"},{value="right",label="Toolbar on the right"}},self:ToolbarSide())
    end
    if self.moveComposer then
        self.moveComposer:SetText(self:HasComposer() and "Input is here" or "Move input here")
        if self:HasComposer() then self.moveComposer:Disable() else self.moveComposer:Enable() end
    end
end

function Chat:SetLayoutPreset(minimal)
    local config=self:Config()
    if minimal then
        local previous={}
        for _,option in ipairs(layoutOptions) do previous[option[1]]=config[option[1]]==true end
        config.previousChatLayout=config.previousChatLayout or previous
        for _,option in ipairs(layoutOptions) do
            local key=option[1]
            if key~="composerTop" then config[key]=key~="hideTabs" end
        end
    elseif config.previousChatLayout then
        for _,option in ipairs(layoutOptions) do
            local key=option[1]
            config[key]=config.previousChatLayout[key] or nil
        end
        config.previousChatLayout=nil
    end
    self:RefreshLayoutOptions()
    self:ApplyLayout()
end

local settingsPages={
    {key="types",title="Chat types",description="Choose a message type. Unchanged colors follow the shared format.",search="color colour text whisper say yell party raid guild officer instance system channel general trade /w /s /y /p /g /raid"},
    {key="senders",title="Sender rules",description="Highlight messages by player name or relationship.",search="friend friends guild relationship member sender tint priority order whisper player names background opacity"},
    {key="appearance",title="Shared format",description="The base text colors and labels for all windows in this profile.",search="timestamp time seconds clock 12 hour abbreviation label icon symbol name text format role sender message color colour class player Klassenfarbe"},
    {key="channels",title="Tabs & sources",description="Choose the messages in your tab, then its appearance and unread hints.",search="source channel filter whisper group tab appearance background opacity alpha transparency tint unread alert notification trade general selected none all /w"},
    {key="layout",title="Windows & input",description="One input. Independent reading windows. Tools stay on the main window.",search="window input composer toolbar left right main move size resize layout position send destination texture material motif Textur"},
}
local whisperModes={{value="none",label="None"},{value="all",label="All"},{value="selected",label="Selected groups"}}
local senderTargets={{value="sender",label="Sender name"},{value="message",label="Message text"},{value="all",label="Whole line"}}
local function selectedWhisperMode(rule)
    if rule.scope=="party" or rule.scope=="raid" then return "selected" end
    return rule.scope or "none"
end
function Chat:RefreshWhisperOptions()
    local mode=selectedWhisperMode(self.rule)
    useSelection(self.scopeButton,whisperModes,mode)
    for key,control in pairs(self.whisperChecks or {}) do
        control:SetShown(mode=="selected")
        control:SetValue((self.rule.whisperGroups and self.rule.whisperGroups[key])==true or self.rule.scope==key)
    end
    self.whisperHint:SetText(mode=="all" and "Include whispers from anyone." or mode=="none" and "No whispers are included in this tab." or
        "Include a sender who matches at least one selected group.")
    if self.arrangeSettings then self.arrangeSettings() end
end
function Chat:TypeChoices()
    local items={}
    self.typeEntries={}
    local choices=self.AppearanceSources and self:AppearanceSources() or {}
    if #choices==0 then
        choices={{key="WHISPER",name="Whisper",source="WHISPER"}}
        for _,source in ipairs(self.sources) do choices[#choices+1]={key=source[1],name=source[2],source=source[1]} end
    end
    for _,entry in ipairs(choices) do
        if entry.key~="COMBAT" then
            items[#items+1]={value=entry.key,label=entry.name}
            self.typeEntries[entry.key]=entry
        end
    end
    for _,entry in ipairs(self:ChannelChoices(self:MessageStyle().sourceColors or {})) do
        if not self.typeEntries[entry.key] then
            items[#items+1]={value=entry.key,label=entry.name..(entry.joined and "" or " · not joined")}
            self.typeEntries[entry.key]=entry
        end
    end
    return items
end
function Chat:RefreshTypeFields()
    if not self.typeSelector then return end
    local choices=self:TypeChoices()
    self.editType=self.typeEntries[self.editType] and self.editType or "WHISPER"
    useSelection(self.typeSelector,choices,self.editType)
    local style=self:MessageStyle()
    local own=(style.sourceColors or {})[self.editType] or {}
    local entry=self.typeEntries[self.editType]
    local inherited=entry and entry.source~=self.editType and (style.sourceColors or {})[entry.source] or {}
    inherited=inherited or {}
    for _,role in ipairs(formatRoles) do
        local native=self:WoWRoleColor(style,role.key,{source=entry and entry.source or self.editType})
        self.typeColors[role.key]:SetValue((own[role.key] or inherited[role.key] or native or style.colors[role.key]).."ff")
        self.typeOrigin[role.key]:SetText(own[role.key] and "Own color" or inherited[role.key] and ("From "..(self.labels[entry.source] or entry.source)) or native and "WoW chat color" or "Shared default")
        self.typeReset[role.key]:SetShown(own[role.key]~=nil)
    end
end
function Chat:RefreshSenderFields()
    if not self.senderSelector then return end
    local rules=self:SenderRules()
    local choices=senderChoices(rules)
    self.editSender=nil
    for i,rule in ipairs(rules) do if rule.key==self.senderKey then self.editSender=rule;self.senderIndex=i end end
    if not self.editSender then self.editSender=rules[1];self.senderIndex=1;self.senderKey=rules[1].key end
    local rule=self.editSender
    if not rule then return end
    useSelection(self.senderSelector,choices,self.senderKey)
    self.senderEnabled:SetValue(rule.enabled==true)
    local scopes={{value="all",label="All message types"}}
    for _,entry in ipairs(self:TypeChoices()) do scopes[#scopes+1]=entry end
    useSelection(self.senderScope,scopes,rule.scope or "all")
    useSelection(self.senderTarget,senderTargets,rule.target or "sender")
    local tint=rule.tint or "91aee500"
    self.senderTint:SetValue(tint:sub(1,6).."ff")
    self.settingSenderSlider=true
    local amount=math.floor((tonumber(tint:sub(7,8),16) or 0)*100/255+.5)
    self.senderStrength:SetValue(amount)
    self.settingSenderSlider=nil
    self.senderAmount:SetText(amount.."%")
    self.senderBackground:SetValue(rule.background or "7062a800")
    if rule.background then self.senderBackgroundReset:Enable() else self.senderBackgroundReset:Disable() end
    self.senderNames:SetText(rule.names and table.concat(rule.names,", ") or "")
    if self.senderIndex>1 then self.senderUp:Enable() else self.senderUp:Disable() end
    if self.senderIndex<#rules then self.senderDown:Enable() else self.senderDown:Disable() end
end

function Chat:BuildRules()
    local style=UI:ToolStyle()
    local w=UI:Window("BVChatChannels"..self:WindowID(),1000,560,{title="Chat settings",minWidth=850,minHeight=550})
    self.ruleWindow=w
    self.settingsStyle=style
    local root=w.content
    local baseLevel=root:GetFrameLevel()
    root:SetFrameLevel(baseLevel+2)
    UI:WindowReadingSurface(w,style)
    core.ShellMaterials:AttachEditorFrame(style,w)
    w.editorSurface=core.InterfaceSurfaces:AttachEditor(style,w,192,baseLevel+1)
    local function place(widget,parent,x,y,width,height)
        at(widget,parent,x,y)
        if width then M.Width(widget,math.max(1,width)) end
        if height then M.Height(widget,math.max(1,height)) end
        return widget
    end
    local function label(parent,text,size,role)
        local widget=UI:Label(parent,text,size or 13,role or "muted",role=="accentText")
        widget:SetJustifyH("LEFT");widget:SetWordWrap(true)
        return widget
    end
    local function card(title)
        local host=CreateFrame("Frame",nil,root)
        host:SetFrameLevel(baseLevel+3)
        local surface=style:Panel(w,100,100,"panel",3)
        surface:SetFrameLevel(baseLevel);surface:EnableMouse(false)
        M.Point(surface,"TOPLEFT",host,"TOPLEFT");M.Point(surface,"BOTTOMRIGHT",host,"BOTTOMRIGHT")
        host.surface=surface
        core.InterfaceSurfaces:AttachHeader(style,surface,30)
        local mark=surface:CreateTexture(nil,"ARTWORK")
        M.Size(mark,2,12);M.Point(mark,"TOPLEFT",3,-9)
        local band=surface:CreateTexture(nil,"ARTWORK")
        M.Point(band,"TOPLEFT",2,-2);M.Point(band,"TOPRIGHT",-2,-2);M.Height(band,27)
        local rule=style:Rule(surface);M.Point(rule,"TOPLEFT",1,-30);M.Point(rule,"TOPRIGHT",-1,-30)
        style:Bind(function()mark:SetColorTexture(style:Color("accent",.78));band:SetColorTexture(style:Color("accent",.065))end,surface)
        host.heading=place(label(host,title,13,"accentText"),host,10,8,300)
        host.body=CreateFrame("Frame",nil,host)
        host.body:SetClipsChildren(true)
        M.Point(host.body,"TOPLEFT",host,"TOPLEFT",12,-40);M.Point(host.body,"BOTTOMRIGHT",host,"BOTTOMRIGHT",-12,10)
        function host:Arrange(x,y,width,height)
            place(self,root,x,y,width,height)
            M.Width(self.heading,math.max(1,width-24))
        end
        function host:Visible(on)self:SetShown(on);self.surface:SetShown(on)end
        host:HookScript("OnHide",function()surface:Hide()end)
        host:HookScript("OnShow",function()surface:Show()end)
        return host
    end
    local function swatch(parent,changed,rgb)
        local control
        control=UI:Button(parent,"",30,function()control:OpenPicker()end,"ghost")
        M.Size(control,30,30)
        control.callback=changed
        control.swatch=control
        control.sample=control:CreateTexture(nil,"OVERLAY")
        M.Point(control.sample,"TOPLEFT",5,-5);M.Point(control.sample,"BOTTOMRIGHT",-5,5)
        function control:SetValue(value)
            self.value=value
            self.sample:SetColorTexture(UI:RGBA(value or "ffffffff"))
        end
        function control:OpenPicker()
            UI:OpenColorPicker(self,nil,{rgb=rgb~=false,style=style})
        end
        function control:SetLocked(on)
            self.locked=on==true
            if on then self:Disable() else self:Enable() end
        end
        control:HookScript("OnHide",function()
            if UI.colorPopup and UI.colorPopup.owner==control then UI.colorPopup:Hide() end
        end)
        UI:AttachTooltip(control,"Choose color","Open the color spectrum. Exact hex values are available in the picker.")
        return control
    end
    local function button(parent,text,width,callback)
        return UI:Button(parent,text,width,callback,"ghost")
    end
    local function check(parent,text,changed)
        return style:Check(parent,text,false,changed)
    end
    local function dropdown(parent,provider,changed)
        return selector(parent,0,0,200,provider,changed)
    end
    local navCard=card("CHAT SETTINGS")
    self.settingsSearch=UI:Input(navCard,150)
    self.searchStatus=label(navCard,"Find a setting",11)
    self.navMessageTitle=label(navCard,"MESSAGE DESIGN",10,"accentText")
    self.navWindowTitle=label(navCard,"WORKSPACE",10,"accentText")
    self.navButtons={}
    local icons={types="message-circle",senders="users",appearance="sliders-horizontal",channels="layers",layout="layout-grid"}
    for _,item in ipairs(settingsPages) do
        self.navButtons[item.key]=UI:NavButton(navCard,item.title,150,function()
            local target=item.key
            local term=(self.settingsSearch:GetText() or ""):lower()
            if target=="channels" then
                for _,word in ipairs({"background","opacity","alpha","transparency","tint","appearance","style","color","colour"}) do
                    if term:find(word,1,true) then target="tabStyle";break end
                end
                for _,word in ipairs({"unread","alert","notification"}) do
                    if term:find(word,1,true) then target="unread";break end
                end
            end
            self.selectSettingsSection(target)
        end,nil,icons[item.key])
    end
    self.settingsTitle=label(root,"",22,"text")
    self.settingsLead=label(root,"",13)
    self.sharedCaption=label(root,"PROFILE · ALL CHAT WINDOWS",10,"accentText")
    self.windowCaption=label(root,"Window",11)
    self.tabCaption=label(root,"Tab",11)
    self.windowChoices=function()
        local list={}
        for _,workspace in ipairs(Chat:ListWindows()) do list[#list+1]={value=workspace:WindowID(),label=workspace:WindowName()} end
        return list
    end
    self.editingWindow=dropdown(root,self.windowChoices,function(id)
        for _,workspace in ipairs(Chat:ListWindows()) do if workspace:WindowID()==id then workspace:EditRules(self.settingsSection);return end end
    end)
    self.manageWindows=button(root,"Manage windows",130,function()Chat:OpenWindowManager(self)end)
    self.selector=dropdown(root,function()return self:TabChoices()end,function(index)self:LoadRule(index)end)
    self.styleTab=self.selector
    local addTab=UI:IconButton(root,"plus",function()
        self:LoadRule(#self:Config().views+1);self.selectSettingsSection("channels");self.ruleName:SetFocus()
    end,"icon-only")
    UI:AttachTooltip(addTab,"Create a tab","Add a personal selection of messages.")
    local renameTab=UI:IconButton(root,"pencil",function()
        self.renameActive=not self.renameActive;self.arrangeSettings();if self.renameActive then self.ruleName:SetFocus() end
    end,"icon-only")
    UI:AttachTooltip(renameTab,"Rename this tab")
    self.removeTab=UI:IconButton(root,"trash-2",function(anchor)
        local cfg,index=self:Config(),self.editIndex
        if #cfg.views<=1 or not cfg.views[index] then return end
        self:Menu(anchor,{{value="remove",label="Remove "..cfg.views[index].name}},function()
            table.remove(cfg.views,index);self:LoadRule(math.min(index,#cfg.views));self:RuleChanged()
        end)
    end,"icon-only")
    UI:AttachTooltip(self.removeTab,"Remove this tab")
    self.ruleName=UI:Input(root,200);self.ruleName:SetMaxLetters(24)
    self.nameAction=button(root,"Rename",100,function()self:CommitTabName()end)
    self.ruleName:SetScript("OnEnterPressed",function()self:CommitTabName()end)
    self.ruleName:SetScript("OnEscapePressed",function()self.renameActive=false;self.ruleName:ClearFocus();self.arrangeSettings()end)
    self.ruleHint=label(root,"",11)
    local subtabs=UI:Tabs(root,{{id="channels",label="Messages"},{id="tabStyle",label="Appearance"},{id="unread",label="Unread"}},
        function(key)self.selectSettingsSection(key)end)
    self.settingsForms,self.settingsCards,self.settingsPreviewExpanded={},{},{}
    local pages,editors,previews={},{},{}
    local titles={
        types={"Message type colors","Live preview"},senders={"Sender rules","Same message · different senders"},
        appearance={"Shared text format","Shared defaults · live examples"},channels={"Messages in this tab","Your tab · live preview"},
        tabStyle={"Appearance of this tab","Before & after"},unread={"Unread messages","While another tab is active"},
        layout={"Window roles & input","Layout & window surface"},
    }
    local function newPage(key)
        local left,right=card(titles[key][1]),card(titles[key][2])
        local form=UI:Form(left,350,350,left)
        form:SetClipsChildren(true)
        local data={left=left,right=right,form=form,contentHeight=300,previewHeight=260}
        if key~="layout" then
            data.previewToggle=button(right,"Show",54,function()
                self.settingsPreviewExpanded[key]=not self.settingsPreviewExpanded[key];self.arrangeSettings()
            end)
        end
        pages[key]=data;editors[key]=form.content;previews[key]=right.body
        self.settingsForms[key]={form=form,height=300,top=0}
        self.settingsCards[key]={editor=left,preview=right}
        return form.content,right.body
    end
    local typePane,typePreview=newPage("types")
    local senderPane,senderPreview=newPage("senders")
    local sharedPane,sharedPreview=newPage("appearance")
    local sourcePane,sourcePreview=newPage("channels")
    local stylePane,stylePreview=newPage("tabStyle")
    local unreadPane,unreadPreview=newPage("unread")
    local layoutPane,layoutPreview=newPage("layout")
    local function resizePreview(list,parent,width,compact,offset)
        local y=offset or 0
        for _,sample in ipairs(list) do
            local height=compact and 26 or 58
            place(sample,parent,0,y,width,height)
            sample:Arrange(width,compact)
            y=y+height+(compact and 3 or 6)
        end
        return y
    end

    self.typeColors,self.typeReset,self.typeOrigin={}, {},{}
    self.typeSelector=dropdown(typePane,function()return self:TypeChoices()end,function(key)
        self.editType=key;self:RefreshTypeFields();self:UpdateChatSample()
    end)
    local typeLabels={}
    for _,role in ipairs(formatRoles) do
        local key=role.key
        typeLabels[key]=label(typePane,role.label,14,"text")
        self.typeOrigin[key]=label(typePane,"",11)
        self.typeColors[key]=swatch(typePane,function(hex)
            local colors=self:MessageStyle().sourceColors;colors[self.editType]=colors[self.editType] or {};colors[self.editType][key]=hex:sub(1,6)
            self:RefreshTypeFields();sharedChanged(self)
        end)
        self.typeReset[key]=UI:IconButton(typePane,"undo-2",function()
            local colors=self:MessageStyle().sourceColors;local own=colors[self.editType]
            if own then own[key]=nil;if not next(own) then colors[self.editType]=nil end end
            self:RefreshTypeFields();sharedChanged(self)
        end,"icon-only")
        UI:AttachTooltip(self.typeReset[key],"Use inherited color","Remove this override and follow the shared format or channel group.")
    end
    local editDefaults=button(typePane,"Edit shared defaults",190,function()self.selectSettingsSection("appearance")end)
    local typeNote=label(typePane,"Unchanged roles keep following their inherited colors.",12)
    self.typeBase=preview(typePreview,0,0,"Shared default")
    self.typeSamples={preview(typePreview,0,0,"Selected chat type"),preview(typePreview,0,0,"Another message"),preview(typePreview,0,0,"A reply")}
    self.typeSample=self.typeSamples[1]
    pages.types.arrange=function(width,previewWidth,compact)
        place(self.typeSelector,typePane,0,0,width)
        for i,role in ipairs(formatRoles) do
            local y=47+(i-1)*44;local key=role.key
            place(typeLabels[key],typePane,0,y,width-80)
            place(self.typeOrigin[key],typePane,0,y+19,width-80)
            place(self.typeReset[key],typePane,width-64,y+5,26,26)
            place(self.typeColors[key],typePane,width-30,y+3,30,30)
        end
        place(editDefaults,typePane,0,239,math.min(190,width));place(typeNote,typePane,0,280,width)
        pages.types.contentHeight=316
        local h=resizePreview({self.typeBase,self.typeSamples[1],self.typeSamples[2],self.typeSamples[3]},typePreview,previewWidth,compact)
        pages.types.previewHeight=h+48
    end

    self.formatColors={}
    local sharedLabels={}
    for _,role in ipairs(formatRoles) do
        local key=role.key
        sharedLabels[key]=label(sharedPane,role.label,14,"text")
        self.formatColors[key]=swatch(sharedPane,function(hex)
            local fmt=self:MessageStyle();fmt.colors[key]=hex:sub(1,6)
            fmt.fixedColors=fmt.fixedColors or {};fmt.fixedColors[key]=true
            self:RefreshTypeFields();sharedChanged(self)
        end)
    end
    self.classNames=check(sharedPane,"Use class colors for player names",function(on)
        self:MessageStyle().classNames=on;sharedChanged(self)
    end)
    UI:AttachTooltip(self.classNames,"Player names","Unknown classes use the Sender color. Chat type overrides and tints still apply.")
    local timeLabel=label(sharedPane,"Time",13,"text")
    self.timeFormat=dropdown(sharedPane,function()return timeFormats end,function(value)self:MessageStyle().timeFormat=value;sharedChanged(self)end)
    local channelLabel=label(sharedPane,"Channel label",13,"text")
    self.channelScope=dropdown(sharedPane,function()return self:LabelScopeChoices()end,function(key)self.labelScope=key;self:RefreshLabelScope();self:UpdateChatSample()end)
    self.channelMode=dropdown(sharedPane,function()return self.labelScope=="all" and channelModes or namedModes end,function(value)
        local config=self:MessageStyle()
        if self.labelScope=="all" then config.channelMode=value else config.channelModes[self.labelScope]=value~="inherit" and value or nil end
        sharedChanged(self)
    end)
    local resetShared=button(sharedPane,"Restore base colors",180,function()
        self:MessageStyle().fixedColors=nil
        for role,hex in pairs(Chat.defaultMessageColors) do self:MessageStyle().colors[role]=hex end
        self:RefreshFormatFields();self:RefreshTypeFields();sharedChanged(self)
    end)
    self.sharedSamples={preview(sharedPreview,0,0,"Party"),preview(sharedPreview,0,0,"Whisper"),preview(sharedPreview,0,0,"Guild")}
    self.sharedSample=self.sharedSamples[1]
    local sharedNote=label(sharedPreview,"These examples use only the shared colors. Chat types and tints can override them.",12)
    pages.appearance.arrange=function(width,previewWidth,compact)
        for i,role in ipairs(formatRoles) do
            local y=(i-1)*42;place(sharedLabels[role.key],sharedPane,0,y+8,width-42)
            place(self.formatColors[role.key],sharedPane,width-30,y,30,30)
        end
        place(self.classNames,sharedPane,0,166,width)
        place(timeLabel,sharedPane,0,221,94);place(self.timeFormat,sharedPane,100,212,width-100)
        place(channelLabel,sharedPane,0,263,94);place(self.channelScope,sharedPane,100,254,width-100)
        place(self.channelMode,sharedPane,100,294,width-100)
        place(resetShared,sharedPane,0,348,math.min(180,width));pages.appearance.contentHeight=387
        local y=resizePreview(self.sharedSamples,sharedPreview,previewWidth,compact)
        place(sharedNote,sharedPreview,0,y+5,previewWidth);sharedNote:SetShown(not compact);pages.appearance.previewHeight=y+(compact and 48 or 92)
    end

    self.senderSelector=dropdown(senderPane,function()
        return senderChoices(self:SenderRules())
    end,function(key)self.senderKey=key;self:RefreshSenderFields();self:UpdateChatSample();self.arrangeSettings()end)
    local function refreshRules()
        for _,window in ipairs(self:ListWindows()) do
            if window.ruleWindow and window.ruleWindow:IsShown() and window.settingsSection=="senders" then
                window:RefreshSenderFields();window:UpdateChatSample();window.arrangeSettings()
            end
        end
        self:QueueAllWindows()
    end
    local function reorder(delta)
        local rules=self:SenderRules();local i=self.senderIndex;local j=i+delta
        if rules[j]then rules[i],rules[j]=rules[j],rules[i];refreshRules()end
    end
    self.senderUp=UI:IconButton(senderPane,"arrow-up",function()reorder(-1)end,"icon-only")
    self.senderDown=UI:IconButton(senderPane,"arrow-down",function()reorder(1)end,"icon-only")
    UI:AttachTooltip(self.senderUp,"Higher priority");UI:AttachTooltip(self.senderDown,"Lower priority")
    self.senderEnabled=check(senderPane,"Enable this rule",function(on)if self.editSender then self.editSender.enabled=on;sharedChanged(self)end end)
    local scopeLabel=label(senderPane,"Apply to",13,"text")
    local targetLabel=label(senderPane,"Text part",13,"text")
    local senderColorLabel=label(senderPane,"Tint color",13,"text")
    local senderStrengthLabel=label(senderPane,"Strength",13,"text")
    self.senderScope=dropdown(senderPane,function()
        local list={{value="all",label="All message types"}};for _,entry in ipairs(self:TypeChoices())do list[#list+1]=entry end;return list
    end,function(value)self.editSender.scope=value;sharedChanged(self)end)
    self.senderTarget=dropdown(senderPane,function()return senderTargets end,function(value)self.editSender.target=value;sharedChanged(self)end)
    self.senderTint=swatch(senderPane,function(hex)self.editSender.tint=hex:sub(1,6)..(self.editSender.tint or "00000000"):sub(7,8);sharedChanged(self)end)
    self.senderStrength=style:Slider(senderPane,200,0,100,1,0,function(value)
        if self.settingSenderSlider or not self.editSender then return end
        value=math.floor(value+.5);self.editSender.tint=(self.editSender.tint or "91aee500"):sub(1,6)..string.format("%02x",math.floor(value*255/100+.5))
        self.senderAmount:SetText(value.."%");sharedChanged(self)
    end)
    self.senderAmount=label(senderPane,"",13,"text")
    local backgroundLabel=label(senderPane,"Row background",13,"text")
    self.senderBackground=swatch(senderPane,function(hex)
        self.editSender.background=hex
        self.senderBackgroundReset:Enable()
        sharedChanged(self)
    end,false)
    UI:AttachTooltip(self.senderBackground,"Row background","Choose a color and opacity for matching lines. Zero opacity uses the tab color.")
    self.senderBackgroundReset=button(senderPane,"Inherit",115,function()
        self.editSender.background=nil;self:RefreshSenderFields();sharedChanged(self)
    end)
    self.addSenderRule=button(senderPane,"+ Name rule",120,function()
        local rules=self:SenderRules()
        local used={}
        for _,rule in ipairs(rules) do used[rule.key]=true end
        local n=1
        while used["names"..n] do n=n+1 end
        self.senderKey="names"..n
        table.insert(rules,1,{key=self.senderKey,names={},scope="WHISPER",enabled=true,target="sender",tint="e4bd6000",background="7062a830"})
        refreshRules();self.senderNames:SetFocus()
    end)
    self.deleteSenderRule=button(senderPane,"Delete rule",110,function()
        if self.editSender.names then table.remove(self:SenderRules(),self.senderIndex);self.senderKey=nil;refreshRules() end
    end)
    local namesLabel=label(senderPane,"Player names · separate with commas",12)
    self.senderNames=UI:Input(senderPane,180)
    self.senderNames:SetMaxLetters(512)
    local function saveNames()
        local names,seen={},{}
        for input in self.senderNames:GetText():gmatch("[^,]+") do
            local name=input:match("^%s*(.-)%s*$")
            if name~="" then
                if not self.person(name) then namesLabel:SetText("Invalid name. Use Name or Name-Realm.");return end
                local key=name:lower()
                if not seen[key] then names[#names+1]=name;seen[key]=true end
            end
        end
        self.editSender.names=names;self.senderNames:ClearFocus()
        namesLabel:SetText("Player names · separate with commas");refreshRules()
    end
    self.senderNames:SetScript("OnEnterPressed",saveNames)
    local applyNames=button(senderPane,"Apply",62,saveNames)
    local priorityNote=label(senderPane,"The first active matching rule wins. Use the arrows to change priority.",12)
    self.senderRuleStatus=label(senderPreview,"",12,"accentText")
    self.senderSamples={}
    for _,entry in ipairs({{"No relation",{}},{"Friend",{friend=true}},{"Guild",{guild=true}},{"Friend + guild",{friend=true,guild=true}},{"Selected group",false}})do
        local sample=preview(senderPreview,0,0,entry[1]);sample.groups=entry[2];self.senderSamples[#self.senderSamples+1]=sample
    end
    pages.senders.arrange=function(width,previewWidth,compact)
        place(self.senderSelector,senderPane,0,0,width-68)
        place(self.senderUp,senderPane,width-60,2,26,26);place(self.senderDown,senderPane,width-28,2,26,26)
        place(self.addSenderRule,senderPane,0,42,120);place(self.deleteSenderRule,senderPane,127,42,110)
        local custom=self.editSender and self.editSender.names~=nil
        for _,widget in ipairs({self.deleteSenderRule,namesLabel,self.senderNames,applyNames}) do widget:SetShown(custom) end
        place(namesLabel,senderPane,0,86,width);place(self.senderNames,senderPane,0,103,width-70);place(applyNames,senderPane,width-64,103,64)
        local y=custom and 150 or 86
        place(self.senderEnabled,senderPane,0,y,width)
        place(scopeLabel,senderPane,0,y+45,87);place(self.senderScope,senderPane,94,y+36,width-94)
        place(backgroundLabel,senderPane,0,y+88,width-164);place(self.senderBackgroundReset,senderPane,width-157,y+78,120);place(self.senderBackground,senderPane,width-30,y+78,30,30)
        place(targetLabel,senderPane,0,y+130,87);place(self.senderTarget,senderPane,94,y+121,width-94)
        place(senderColorLabel,senderPane,0,y+172,width-42);place(self.senderTint,senderPane,width-30,y+163,30,30)
        place(senderStrengthLabel,senderPane,0,y+214,88);place(self.senderStrength,senderPane,94,y+204,width-137)
        place(self.senderAmount,senderPane,width-35,y+214,35)
        local noteY=y+258
        place(priorityNote,senderPane,0,noteY,width);pages.senders.contentHeight=noteY+50
        local rows={};for i,sample in ipairs(self.senderSamples)do
            local shown=i<5 or custom or self.senderKey=="party" or self.senderKey=="raid";sample:SetShown(shown)
            if shown then rows[#rows+1]=sample end
        end
        place(self.senderRuleStatus,senderPreview,0,0,previewWidth)
        pages.senders.previewHeight=resizePreview(rows,senderPreview,previewWidth,compact,compact and 28 or 36)+48
    end

    local whisperLabel=label(sourcePane,"Whispers",14,"text")
    local whisperModesProvider=function()return whisperModes end
    self.scopeButton=dropdown(sourcePane,whisperModesProvider,function(key)
        if self.rule.scope=="party" or self.rule.scope=="raid" then self.rule.whisperGroups=self.rule.whisperGroups or {};self.rule.whisperGroups[self.rule.scope]=true end
        self.rule.scope=key~="none" and key or nil;self:RefreshWhisperOptions();self:RuleChanged()
    end)
    self.whisperHint=label(sourcePane,"",12)
    self.whisperChecks={}
    for _,key in ipairs({"friend","guild","party","raid"})do
        self.whisperChecks[key]=check(sourcePane,({friend="Friends",guild="Guild",party="Party",raid="Raid"})[key],function(on)
            self.rule.whisperGroups=self.rule.whisperGroups or {};self.rule.whisperGroups[key]=on or nil;self:RuleChanged()
        end)
    end
    local conversationsLabel=label(sourcePane,"CONVERSATIONS & GAME",11,"accentText")
    self.sourceButtons={}
    local sourceOrder={}
    for _,source in ipairs(self.sources)do
        local key=source[1]
        if key~="WORLD" and key~="TRADE" then
            sourceOrder[#sourceOrder+1]=key
            self.sourceButtons[key]=check(sourcePane,source[2],function(on)self.rule.sources[key]=on or nil;self:RuleChanged()end)
            if key=="COMBAT"then UI:AttachTooltip(self.sourceButtons[key],"Combat log","Uses Blizzard's native feed. BV text colors do not change it.")end
        end
    end
    local publicLabel=label(sourcePane,"JOINED PUBLIC CHANNELS",11,"accentText")
    self.channelsPrevious=UI:IconButton(sourcePane,"arrow-left",function()self.channelPage=self.channelPage-1;self:UpdateNamedSources()end,"icon-only")
    self.channelsNext=UI:IconButton(sourcePane,"arrow-right",function()self.channelPage=self.channelPage+1;self:UpdateNamedSources()end,"icon-only")
    self.channelsPage=label(sourcePane,"",11)
    self.joinedChecks={}
    for i=1,CHANNELS_PER_PAGE do
        local control
        control=check(sourcePane,"",function(on)if control.channel then self:SetNamedSource(control.channel,on)end end)
        self.joinedChecks[i]=control
    end
    self.noChannels=label(sourcePane,"Join a WoW channel to add it here.",12)
    for _,key in ipairs({"WORLD","TRADE"})do
        self.sourceButtons[key]=check(sourcePane,key=="WORLD" and "Include future public channels" or "Include future trade channels",function(on)
            self.rule.sources[key]=on or nil;self:UpdateNamedSources();self:RuleChanged()
        end)
    end
    local publicHint=label(sourcePane,"Uncheck a channel to keep an individual selection.",11)
    self.sourceSamples={preview(sourcePreview,0,0),preview(sourcePreview,0,0),preview(sourcePreview,0,0)}
    self.sourceSample=self.sourceSamples[1]
    local sourcesNote=label(sourcePreview,"A merged tab shows each matching message once.",12)
    pages.channels.arrange=function(width,previewWidth,compact)
        place(whisperLabel,sourcePane,0,8,80);place(self.scopeButton,sourcePane,86,0,width-86)
        place(self.whisperHint,sourcePane,0,40,width)
        local selected=self.rule and selectedWhisperMode(self.rule)=="selected"
        for i,key in ipairs({"friend","guild","party","raid"})do
            place(self.whisperChecks[key],sourcePane,(i-1)%2*(width/2),75+math.floor((i-1)/2)*30,width/2-8)
            self.whisperChecks[key]:SetShown(selected)
        end
        local y=selected and 145 or 82
        place(conversationsLabel,sourcePane,0,y,width);y=y+26
        for i,key in ipairs(sourceOrder)do
            place(self.sourceButtons[key],sourcePane,(i-1)%2*(width/2),y+math.floor((i-1)/2)*30,width/2-8)
        end
        y=y+math.ceil(#sourceOrder/2)*30+18
        place(publicLabel,sourcePane,0,y,width-88)
        place(self.channelsPrevious,sourcePane,width-83,y-5,24,24);place(self.channelsPage,sourcePane,width-52,y+2,31)
        place(self.channelsNext,sourcePane,width-23,y-5,24,24);y=y+28
        for i,control in ipairs(self.joinedChecks)do place(control,sourcePane,0,y+(i-1)*28,width)end
        place(self.noChannels,sourcePane,0,y+3,width);y=y+CHANNELS_PER_PAGE*28+8
        place(self.sourceButtons.WORLD,sourcePane,0,y,width);place(self.sourceButtons.TRADE,sourcePane,0,y+29,width)
        place(publicHint,sourcePane,0,y+62,width);pages.channels.contentHeight=y+94
        local h=resizePreview(self.sourceSamples,sourcePreview,previewWidth,compact)
        place(sourcesNote,sourcePreview,0,h+6,previewWidth);sourcesNote:SetShown(not compact);pages.channels.previewHeight=h+(compact and 48 or 85)
    end

    local tintLabel=label(stylePane,"Text tint",14,"text")
    local tintHelp=label(stylePane,"Tint text in this tab. Sender tints still apply afterwards.",12)
    self.ruleTint=swatch(stylePane,function(hex)
        local tint=self.rule.tint or "91aee500";self.rule.tint=hex:sub(1,6)..tint:sub(7,8);self:RefreshTabStyle();self:RuleChanged()
    end)
    self.tintStrength=style:Slider(stylePane,180,0,100,1,0,function(value)
        if self.settingTintSlider or not self.rule then return end
        local percent=math.floor(value+.5)
        self.rule.tint=(self.rule.tint or "91aee500"):sub(1,6)..string.format("%02x",math.floor(percent*255/100+.5))
        self.tintValue:SetText(percent.."%");self:UpdateChatSample();self:RuleChanged()
    end)
    self.tintValue=label(stylePane,"",13,"text")
    local backgroundLabel=label(stylePane,"Message background",14,"text")
    local backgroundHelp=label(stylePane,"Choose the color and opacity behind each message.",12)
    self.tabBackground=swatch(stylePane,function(hex)self.rule.background=hex;self:UpdateChatSample();self:RuleChanged()end,false)
    local backgroundPicker=button(stylePane,"Color & opacity…",165,function()self.tabBackground:OpenPicker()end)
    local clearTab=button(stylePane,"Clear tab style",150,function()self.rule.tint,self.rule.background=nil,nil;self:RefreshTabStyle();self:RuleChanged()end)
    local sharedTab=button(stylePane,"Shared defaults",150,function()self.selectSettingsSection("appearance")end)
    self.tabBaseline=preview(stylePreview,0,0,"Without tab tint")
    self.tabSample=preview(stylePreview,0,0,"In this tab")
    local tabStyleNote=label(stylePreview,"Sender tints are applied after the tab tint. Background affects only this tab's matching lines.",12)
    pages.tabStyle.arrange=function(width,previewWidth,compact)
        place(tintLabel,stylePane,0,0,width);place(tintHelp,stylePane,0,25,width)
        place(self.ruleTint,stylePane,0,69,30,30);place(self.tintStrength,stylePane,48,70,width-91);place(self.tintValue,stylePane,width-35,80,35)
        place(backgroundLabel,stylePane,0,132,width);place(backgroundHelp,stylePane,0,157,width)
        place(self.tabBackground,stylePane,0,201,30,30);place(backgroundPicker,stylePane,46,201,math.min(165,width-46))
        place(clearTab,stylePane,0,264,math.min(150,width));place(sharedTab,stylePane,math.max(160,width-150),264,math.min(150,width-160))
        pages.tabStyle.contentHeight=310
        local h=resizePreview({self.tabBaseline,self.tabSample},stylePreview,previewWidth,compact)
        place(tabStyleNote,stylePreview,0,h+8,previewWidth);tabStyleNote:SetShown(not compact);pages.tabStyle.previewHeight=h+(compact and 48 or 98)
    end

    local unreadLead=label(unreadPane,"When you are reading another tab:",13,"text")
    self.notifyButton=check(unreadPane,"Highlight this tab and show its unread count",function(on)self.rule.quiet=not on;self:RuleChanged()end)
    local unreadHelp=label(unreadPane,"Disable this for busy channels such as Trade. Messages still remain in history.",13)
    self.unreadSample=label(unreadPreview,"",18,"accentText")
    local unreadNote=label(unreadPreview,"Example: three messages arrive while a different tab is active.",12)
    pages.unread.arrange=function(width,previewWidth)
        place(unreadLead,unreadPane,0,0,width);place(self.notifyButton,unreadPane,0,38,width)
        place(unreadHelp,unreadPane,0,84,width);pages.unread.contentHeight=156
        place(self.unreadSample,unreadPreview,0,8,previewWidth);place(unreadNote,unreadPreview,0,51,previewWidth);pages.unread.previewHeight=154
    end

    self.mainInfo=label(layoutPane,"",14,"text")
    self.makeMain=button(layoutPane,"Make this the main window",246,function()self:SetAsMainWindow();self:RefreshLayoutOptions()end)
    self.toolbarSide=dropdown(layoutPane,function()return {{value="left",label="Toolbar on the left"},{value="right",label="Toolbar on the right"}}end,
        function(value)self:SetToolbarSide(value);self:RefreshLayoutOptions()end)
    self.layoutInfo=label(layoutPane,"",13)
    self.moveComposer=button(layoutPane,"Move input here",182,function()self:SetAsComposer();self:RefreshLayoutOptions()end)
    self.layoutChecks={}
    for _,option in ipairs(layoutOptions)do
        local key=option[1]
        self.layoutChecks[key]=check(layoutPane,option[2],function(on)
            if key=="composerTop"then self:Config()[key]=on or nil else self:Config()[key]=not on or nil end
            self:ApplyLayout();self:RefreshLayoutOptions()
        end)
    end
    self.openLayoutButton=button(layoutPreview,"Open Layout Editor",220,function()
        local profile=core.Settings.db.activeProfile
        local opened=self:OpenLayoutEditor(function()
            if core.Settings.db.activeProfile~=profile then return false end
            for _,workspace in ipairs(Chat:ListWindows())do if workspace==self then self:EditRules("layout");return true end end
            return false
        end)
        if opened then self.parkedRuleConfig=self:Config();self.ruleWindow:Hide()end
    end)
    local layoutHelp=label(layoutPreview,"Whisper shortcuts: /r replies to the last sender, /rr to the last recipient, /lastw to your latest contact.",13)
    local surfaceLabel=label(layoutPreview,"Window surface tint",14,"text")
    self.bgTint=swatch(layoutPreview,function(hex)self:Config().backgroundTint=hex;self:UpdateChatSample();self:Paint()end,false)
    local surfaceHelp=label(layoutPreview,"Window material is independent of message backgrounds.",12)
    self.restoreLayout=button(layoutPane,"Restore previous layout",200,function()self:SetLayoutPreset(false)end);self.restoreLayout:Hide()
    self.minimalLayout=button(layoutPane,"Apply minimal",160,function()self:SetLayoutPreset(true)end);self.minimalLayout:Hide()
    pages.layout.arrange=function(width,previewWidth)
        place(self.mainInfo,layoutPane,0,0,width)
        place(self.makeMain,layoutPane,0,32,math.min(246,width));place(self.toolbarSide,layoutPane,0,74,width)
        place(self.layoutInfo,layoutPane,0,119,width);place(self.moveComposer,layoutPane,0,172,math.min(182,width))
        for i,option in ipairs(layoutOptions)do place(self.layoutChecks[option[1]],layoutPane,0,222+(i-1)*31,width)end
        pages.layout.contentHeight=222+#layoutOptions*31+12
        place(self.openLayoutButton,layoutPreview,0,0,math.min(220,previewWidth))
        place(layoutHelp,layoutPreview,0,46,previewWidth)
        place(surfaceLabel,layoutPreview,0,115,previewWidth-42);place(self.bgTint,layoutPreview,previewWidth-30,106,30,30)
        place(surfaceHelp,layoutPreview,0,155,previewWidth);pages.layout.previewHeight=242
    end

    local arranging=false
    self.arrangeSettings=function()
        if arranging then return end
        arranging=true
        local width,height=M.GetWidth(root),M.GetHeight(root)
        local bodyX,bodyWidth=202,math.max(400,width-214)
        local term=(self.settingsSearch:GetText()or""):lower():match("^%s*(.-)%s*$")
        navCard:Arrange(6,6,180,math.max(380,height-12))
        place(self.settingsSearch,navCard,10,40,160)
        place(self.searchStatus,navCard,10,76,160)
        local count,y=0,108
        for i,item in ipairs(settingsPages)do
            local haystack=item.title.." "..item.search
            if item.key=="types"or item.key=="channels"then
                for _,channel in ipairs(self:ChannelChoices(self.rule and self.rule.sources or {}))do haystack=haystack.." "..channel.name end
            end
            local found=term==""or haystack:lower():find(term,1,true)~=nil
            if term==""and i==1 then place(self.navMessageTitle,navCard,12,y,156);y=y+22 end
            if term==""and i==4 then y=y+18;place(self.navWindowTitle,navCard,12,y,156);y=y+22 end
            self.navButtons[item.key]:SetShown(found)
            if found then place(self.navButtons[item.key],navCard,5,y,170,34);y=y+37;count=count+1 end
        end
        self.navMessageTitle:SetShown(term=="");self.navWindowTitle:SetShown(term=="")
        self.searchStatus:SetText(term==""and"Find a setting"or count==0 and"No matching setting"or count.." matching topics")
        place(self.settingsTitle,root,bodyX,9,bodyWidth)
        place(self.settingsLead,root,bodyX,37,bodyWidth)
        local key=self.settingsSection or "types"
        local tabPage=key=="channels"or key=="tabStyle"or key=="unread"
        local windowPage=tabPage or key=="layout"
        self.windowCaption:SetShown(windowPage);self.editingWindow:SetShown(windowPage);self.manageWindows:SetShown(windowPage)
        self.sharedCaption:SetShown(not windowPage)
        place(self.sharedCaption,root,bodyX,64,bodyWidth)
        local top=85
        if windowPage then
            local pickWidth=tabPage and math.max(130,(bodyWidth-250)/2)or math.min(330,bodyWidth-150)
            place(self.windowCaption,root,bodyX,69,pickWidth)
            place(self.editingWindow,root,bodyX,86,pickWidth)
            place(self.manageWindows,root,bodyX+bodyWidth-130,86,130)
            top=130
            if tabPage then
                local tx=bodyX+pickWidth+12
                place(self.tabCaption,root,tx,69,pickWidth)
                place(self.selector,root,tx,86,pickWidth)
                place(addTab,root,tx+pickWidth+6,89,24,24)
                place(renameTab,root,tx+pickWidth+33,89,24,24)
                place(self.removeTab,root,tx+pickWidth+60,89,24,24)
                if self.renameActive then
                    place(self.ruleName,root,bodyX,125,math.min(280,bodyWidth-124))
                    place(self.nameAction,root,bodyX+math.min(280,bodyWidth-124)+10,125,110)
                    top=169
                end
                place(subtabs,root,bodyX,top,math.min(bodyWidth,440));subtabs:Arrange(math.min(bodyWidth,440))
                place(self.ruleHint,root,bodyX+math.min(bodyWidth,440)+10,top+9,math.max(1,bodyWidth-450))
                self.ruleHint:SetShown(bodyWidth>720 and not self.renameActive)
                top=top+42
            end
        end
        for _,widget in ipairs({self.tabCaption,self.selector,addTab,renameTab,self.removeTab,subtabs})do widget:SetShown(tabPage)end
        self.ruleName:SetShown(tabPage and self.renameActive==true);self.nameAction:SetShown(tabPage and self.renameActive==true)
        if not tabPage then self.ruleHint:Hide()end
        local available=math.max(230,height-top-12)
        local narrow=bodyWidth<730
        self.settingsNarrow=narrow
        for id,data in pairs(pages)do
            local active=id==key
            local stacked=narrow and id~="layout"
            local leftWidth=stacked and bodyWidth or math.floor((bodyWidth-12)*.53)
            local rightWidth=stacked and bodyWidth or bodyWidth-leftWidth-12
            local editWidth=leftWidth-46
            local previewWidth=rightWidth-24
            data.arrange(editWidth,previewWidth,stacked)
            local previewExpanded=not narrow or id=="layout"or self.settingsPreviewExpanded[id]
            local previewHeight=previewExpanded and data.previewHeight or 32
            local leftHeight=math.min(available,data.contentHeight+54)
            if stacked then
                previewHeight=math.min(previewHeight,math.max(32,available-160))
                data.right:Arrange(bodyX,top,bodyWidth,previewHeight)
                leftHeight=math.max(140,available-previewHeight-10)
                data.left:Arrange(bodyX,top+previewHeight+10,bodyWidth,leftHeight)
            else
                data.left:Arrange(bodyX,top,leftWidth,leftHeight)
                data.right:Arrange(bodyX+leftWidth+12,top,rightWidth,math.min(available,previewHeight))
            end
            if data.previewToggle then
                place(data.previewToggle,data.right,rightWidth-66,3,56,24)
                data.previewToggle:SetText(previewExpanded and"Hide"or"Show")
                data.previewToggle:SetShown(narrow)
                M.Width(data.right.heading,rightWidth-(narrow and 85 or 24))
            end
            data.right.body:SetShown(previewExpanded)
            place(data.form,data.left,12,40,leftWidth-46,math.max(100,leftHeight-52))
            M.Width(data.form.content,leftWidth-46);M.Height(data.form.slider,math.max(100,leftHeight-52))
            data.form:SetContentHeight(data.contentHeight)
            self.settingsForms[id].height=data.contentHeight;self.settingsForms[id].top=top
            data.left:Visible(active);data.right:Visible(active)
            data.form.slider:SetShown(active and(data.form.maximum or 0)>0)
        end
        arranging=false
    end
    self.selectSettingsSection=function(key)
        if key=="tabs"then key="channels"end
        if not pages[key]then key="types"end
        self.settingsSection=key
        local main=(key=="tabStyle"or key=="unread")and"channels"or key
        for _,item in ipairs(settingsPages)do
            self.navButtons[item.key]:SetSelected(item.key==main)
            if item.key==main then self.settingsTitle:SetText(item.title);self.settingsLead:SetText(item.description)end
        end
        subtabs:SetValue(main=="channels"and key or"channels")
        if key=="types"then self:RefreshTypeFields()end
        if key=="senders"then self:RefreshSenderFields()end
        if key=="appearance"then self:RefreshFormatFields()end
        if key=="layout"then self:RefreshLayoutOptions()end
        self:UpdateChatSample();self.arrangeSettings()
    end
    self.settingsSearch:SetScript("OnTextChanged",function()self.arrangeSettings()end)
    self.settingsSearch:SetScript("OnEscapePressed",function(input)input:SetText("");input:ClearFocus()end)
    w:HookScript("OnSizeChanged",self.arrangeSettings)
    self:RefreshTypeFields();self:RefreshSenderFields();self.selectSettingsSection("types")
    if UI.FitWindow then UI:FitWindow(w,1000,560,1)end
end

function Chat:EditRules(section)
    local other=openRules
    if other and other~=self and other.ruleWindow and other.ruleWindow:IsShown() then
        other.parkedRuleConfig=other:Config()
        other.ruleWindow:Hide()
    end
    openRules=self
    if not rawget(self,"ruleWindow") then UI:WithStyle(UI:ToolStyle(),function()self:BuildRules()end) end
    local config=self:Config()
    if config~=self.parkedRuleConfig then
        local index=self.editIndex or 1
        self:LoadRule(config.views[index] and index or 1)
    end
    self.parkedRuleConfig=nil
    self:RefreshLayoutOptions()
    self.selectSettingsSection(section or self.settingsSection or "channels")
    if self.ruleWindow.minimized then self.ruleWindow:Restore() end
    if UI.FitWindow then UI:FitWindow(self.ruleWindow,1000,560,1) end
    self.ruleWindow:Show()
    if self.ruleWindow.Raise then self.ruleWindow:Raise() end
end

local PER_PAGE=5
local function setEnabled(button,enabled)
    if enabled then button:Enable() else button:Disable() end
end

local function buildManager(parent)
    if page then return page end
    page=CreateFrame("Frame",nil,parent)
    page.batch,page.selected,page.rows=1,Chat,{}
    local style=UI:GetStyle()
    page.title=at(UI:Label(page,"Your chat windows",20,"text",true),page,8,8)
    page.status=at(UI:Label(page,"",12,"muted"),page,8,38)

    function page:SelectWindow(workspace)
        self.selected=workspace
        self.name:ClearFocus()
        self.name:SetText(workspace:WindowName())
        self.feedback:SetText("")
        for i,item in ipairs(Chat:ListWindows()) do
            if workspace==item then self.batch=math.ceil(i/PER_PAGE);break end
        end
        self:Refresh()
    end

    page.create=UI:Button(page,"+ New window",146,function()
        local workspace=Chat:CreateChatWindow()
        if workspace then page:SelectWindow(workspace) end
    end,true)
    M.Point(page.create,"TOPRIGHT",page,"TOPRIGHT",-8,-8)
    for i=1,PER_PAGE do
        local row
        row=UI:NavButton(page,"",240,function()
            if row.workspace then page:SelectWindow(row.workspace) end
        end)
        at(row,page,8,66+(i-1)*32)
        M.Height(row,30)
        row.state=UI:Label(row,"",12,"muted")
        M.Point(row.state,"RIGHT",row,"RIGHT",-12,0)
        row:SetLabelInsets(12,123,"LEFT")
        page.rows[i]=row
    end
    page.previous=UI:Button(page,"‹",46,function() page.batch=page.batch-1;page:Refresh() end,"ghost")
    page.next=UI:Button(page,"›",46,function() page.batch=page.batch+1;page:Refresh() end,"ghost")
    page.counter=UI:Label(page,"",12,"muted")
    page.detail=UI:Label(page,"",16,"text",true)
    page.name=UI:Input(page,193)
    page.name:SetMaxLetters(32)
    local function rename()
        local name=page.name:GetText():match("^%s*(.-)%s*$")
        if name=="" or name:find("[%c|]") then
            page.feedback:SetText("Enter a window name.");return
        end
        if page.selected:SetWindowName(name)==false then
            page.feedback:SetText("This name could not be used.");return
        end
        page.name:ClearFocus()
        page:SelectWindow(page.selected)
    end
    page.name:SetScript("OnEnterPressed",rename)
    page.rename=UI:Button(page,"Rename",90,rename,"ghost")
    page.edit=UI:Button(page,"Customize window",164,function() page.selected:EditRules() end,true)
    page.visibility=UI:Button(page,"Show window",140,function()
        local owner=page.selected
        owner:SetWindowEnabled(not owner:IsWindowEnabled())
        page:Refresh()
    end)
    page.composer=UI:Button(page,"Move input here",154,function()
        page.selected:SetAsComposer()
        page:Refresh()
    end)
    page.remove=UI:Button(page,"Remove…",106,function(button)
        local owner=page.selected
        if owner==Chat then return end
        button.bvMenuStyle=style
        UI:ContextMenu(button,{{value="delete",label="Delete "..owner:WindowName()}},function()
            if owner:DeleteWindow()~=false then page:SelectWindow(Chat) end
        end)
    end,"ghost")
    page.feedback=UI:Label(page,"",12,"muted")
    page.help=UI:Label(page,"",13,"muted")
    page.help:SetJustifyH("LEFT")
    page.help:SetWordWrap(true)
    page.separator=page:CreateTexture(nil,"ARTWORK")
    style:Bind(function() page.separator:SetColorTexture(style:Color("edge",.6)) end,page.separator)

    function page:Arrange(width)
        local list=Chat:ListWindows()
        local count=math.min(#list,PER_PAGE)
        for _,row in ipairs(self.rows) do M.Width(row,math.max(1,width-16)) end
        local y=69+count*32
        local paged=#list>PER_PAGE
        for _,widget in ipairs({self.previous,self.next,self.counter}) do widget:SetShown(paged) end
        if paged then
            at(self.previous,self,8,y);at(self.next,self,60,y);at(self.counter,self,119,y+8)
            y=y+38
        end
        self.separator:ClearAllPoints()
        M.Point(self.separator,"TOPLEFT",self,"TOPLEFT",8,-y)
        M.Point(self.separator,"TOPRIGHT",self,"TOPRIGHT",-8,-y)
        M.Height(self.separator,1)
        at(self.detail,self,8,y+14);M.Width(self.detail,math.max(1,width-16))
        at(self.name,self,8,y+45);at(self.rename,self,205,y+45)
        at(self.edit,self,8,y+91);at(self.visibility,self,180,y+91)
        local tight=width<512
        at(self.composer,self,tight and 8 or 328,y+(tight and 132 or 91))
        local bottom=y+(tight and 180 or 139)
        at(self.help,self,8,bottom);M.Size(self.help,math.max(1,width-16),42)
        at(self.remove,self,8,bottom+48);at(self.feedback,self,124,bottom+58)
        return bottom+92
    end
    function page:Refresh()
        local list=Chat:ListWindows()
        local found=false
        for _,workspace in ipairs(list) do if workspace==self.selected then found=true;break end end
        if not found then self.selected=Chat end
        local last=math.max(1,math.ceil(#list/PER_PAGE))
        self.batch=math.min(math.max(1,self.batch),last)
        for i,row in ipairs(self.rows) do
            local workspace=list[(self.batch-1)*PER_PAGE+i]
            row.workspace=workspace
            row:SetShown(workspace~=nil)
            if workspace then
                row:SetLabelText(workspace:WindowName())
                row.state:SetText(workspace:HasComposer() and "Input window" or (workspace:IsWindowEnabled() and "Visible" or "Hidden"))
                row:SetSelected(workspace==self.selected)
            end
        end
        self.counter:SetText(self.batch.." / "..last)
        setEnabled(self.previous,self.batch>1);setEnabled(self.next,self.batch<last)
        local owner=self.selected
        self.status:SetText(Chat.running and "Chat enabled" or "Chat disabled")
        self.detail:SetText(owner:WindowName())
        if not self.name:HasFocus() then self.name:SetText(owner:WindowName()) end
        self.visibility:SetText(owner:IsWindowEnabled() and "Hide window" or "Show window")
        self.composer:SetText(owner:HasComposer() and "Input is here" or "Move input here")
        setEnabled(self.visibility,owner~=Chat and owner~=Chat:MainWindow())
        setEnabled(self.remove,owner~=Chat)
        setEnabled(self.composer,not owner:HasComposer())
        self.help:SetText(not Chat.running and "Enable Chat in the sidebar to display these windows in game." or
            owner==Chat:MainWindow() and "The main window stays visible. Use Customize window to edit its tabs, colors and layout." or
            "Hidden windows keep their channels and layout. Moving the input here makes this window visible.")
        if core.Config.page=="chat" then core.Config:Layout() end
    end
    page:Refresh()
    return page
end
function Chat:OpenWindowManager(workspace)
    core.Config:OpenPage("chat")
    if core.Config.page~="chat" or not core.Config.window or not core.Config.window:IsShown() then return end
    if openRules and openRules.ruleWindow then openRules.ruleWindow:Hide() end
    if page then page:SelectWindow(workspace or Chat) end
end
core.Config:RegisterPage("chat",{title="Chat windows",category="interface",module="chat",icon="message-circle",
    description="Chat windows, shared text format, message type colors, sender tints, personal tabs, whispers and layout.",
    interfaceSettings=true,build=buildManager, refresh=function() if page then page:Refresh() end end})
core.Commands:RegisterAction("chatsettings",function() Chat:OpenWindowManager() end)
core.Commands:RegisterAction("inbox",function() Chat:Open() end)
local function firstVisit()
    if core.Settings.db and Chat:Config().enabled==nil then core.Modules:SetEnabled("chat",true) end
end
core.Events:Subscribe(Chat,"PLAYER_ENTERING_WORLD",firstVisit)
if core.ready and IsLoggedIn() then firstVisit() end
if core.ready and IsLoggedIn() then core.Modules:Reconcile() end

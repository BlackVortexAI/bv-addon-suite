local _, ns = ...
local UI = { styled = setmetatable({}, { __mode = "k" }) }
ns.UI = UI
local Theme = ns.Theme

-- One stacking policy for all BV windows. Keep complete child trees in separate
-- level bands; strata still define dialogs versus transient tools/overlays.
local windows,stack={},{}
local mouseOwner={}
local mouseSubscribed=false
local function restack()
    local levels={}
    for _,window in ipairs(stack) do
        local strata=window:GetFrameStrata(); local base=levels[strata] or 50
        local old=window:GetFrameLevel(); local tree={}; local span=0
        local function collect(frame)
            local offset=frame:GetFrameLevel()-old
            tree[#tree+1]={frame=frame,offset=offset}; span=math.max(span,offset)
            for _,child in ipairs({frame:GetChildren()}) do collect(child) end
        end
        collect(window)
        for _,entry in ipairs(tree) do entry.frame:SetFrameLevel(base+entry.offset) end
        levels[strata]=base+math.max(128,span+16)
    end
end
function UI:FocusWindow(window)
    if not windows[window] or not window:IsShown() then return end
    local index
    for i,item in ipairs(stack) do if item==window then index=i; break end end
    if index==#stack then return end
    if index then table.remove(stack,index) end
    stack[#stack+1]=window
    self:HideTooltip(); if self.CloseDropdown then self:CloseDropdown() end
    restack()
end
local function mouseWindow()
    local foci=GetMouseFoci and GetMouseFoci() or (GetMouseFocus and {GetMouseFocus()} or {})
    if issecretvalue and issecretvalue(foci) then return end
    if canaccesstable and not canaccesstable(foci) then return end
    for _,focus in ipairs(foci) do
        for _=1,64 do
            if issecretvalue and issecretvalue(focus) then break end
            if not focus then break end
            if windows[focus] then return focus end
            if not focus.GetParent or (focus.IsForbidden and focus:IsForbidden()) then break end
            focus=focus:GetParent()
        end
    end
end
local function watchWindows()
    -- A single visible window needs no click-to-front listener.
    local needed=#stack>1
    if needed==mouseSubscribed then return end
    if needed then
        ns.Events:Subscribe(mouseOwner,"GLOBAL_MOUSE_DOWN",function()
            local ok,window=pcall(mouseWindow)
            if ok and window then UI:FocusWindow(window) end
        end)
    else ns.Events:Release(mouseOwner) end
    mouseSubscribed=needed
end
function UI:ManageWindow(window)
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(window)end
    if windows[window] then return window end
    windows[window]=true
    window:HookScript("OnShow",function(self) UI:FocusWindow(self); watchWindows() end)
    window:HookScript("OnHide",function(self)
        for i=#stack,1,-1 do if stack[i]==self then table.remove(stack,i) end end
        watchWindows()
    end)
    if window:IsShown() then self:FocusWindow(window); watchWindows() end
    return window
end

local DS = ns.DesignSystem
local M = DS.Metrics

local function invoke(scope,callback,...)
    if callback then return ns:Call("UI/"..scope,callback,...) end
end

function UI:Bind(widget,render)
    self.styled[widget]=render; render(widget); return widget
end

-- Shared lifecycle services carry no palette, material or constructor state.
-- Interface and gameplay factories share only their owner and weak registry.
function UI:GetStyle()
    if self.styleOverride then return self.styleOverride end
    return self:ToolStyle()
end
function UI:InterfaceStyle()
    return ns.Config and ns.Config:EnsureShellStyle() or nil
end
function UI:ToolStyle()
    return assert(self:InterfaceStyle(),"Interface context is not ready; initialize Settings before building tool widgets")
end
function UI:ContextServices()
    if self.contextServices then return self.contextServices end
    local owner={}
    function owner:ShowTooltip(control,title,body) UI:ShowTooltip(control,title,body) end
    function owner:HideTooltip() UI:HideTooltip() end
    function owner:ShowDropdown(control) UI:OpenDropdown(control) end
    local services={owner=owner}
    services.fontResolver=function(region,size,weight)
        Theme:Font(region,size,(weight=="bold" or weight=="display") and Theme:BoldFont() or nil)
    end
    -- Keep production painters in the existing weak widget registry. A context
    -- must not permanently retain closed/rebuilt module controls in paints/edits.
    services.registerPaint=function(widget,paint)
        widget.bvPaints=widget.bvPaints or {}
        widget.bvPaints[#widget.bvPaints+1]=paint
        UI.styled[widget]=function(current) for _,fn in ipairs(current.bvPaints) do fn() end end
        paint()
    end
    self.contextServices=services
    return services
end

function UI:Refresh()
    -- Snapshot first: a render may register new widgets (a progress bar adds
    -- labels), and adding keys while pairs() runs can skip entries at random.
    local widgets={}
    for widget in pairs(self.styled) do widgets[#widgets+1]=widget end
    for _,widget in ipairs(widgets) do local render=self.styled[widget]; if render then render(widget) end end
    if ns.Styles then ns.Styles:Notify() end
    if ns.Config then ns.Config:Refresh() end
end

-- Inert hosts have ownership and geometry, never a painted material to hide.
function UI:Container(parent,width,height,style)
    style=style or self:GetStyle()
    local host=CreateFrame("Frame",nil,parent)
    M.Size(host,width,height);host.bvStyle=style;host.bvTooltipStyle=style;host.surfaceHidden=true
    return host
end

-- Compatibility facade for callers controlling entire surfaces. Never replace
-- native texture methods: a facade delegates to the actual nine-slice regions.
local function facade(regions)
    local proxy={}
    for _,method in ipairs({"SetAlpha","SetShown","Show","Hide"}) do
        proxy[method]=function(_,...) for _,region in ipairs(regions) do region[method](region,...) end end
    end
    function proxy:SetColorTexture(...) for _,region in ipairs(regions) do region:SetVertexColor(...) end end
    function proxy:SetVertexColor(...) self:SetColorTexture(...) end
    function proxy:IsShown() return regions[1]:IsShown() end
    return proxy
end
local function compatibility(frame)
    frame.fill=facade(frame.fills or {})
    frame.edges={facade(frame.borders or {})}
    return frame
end
function UI:Compatible(frame) return compatibility(frame) end
function UI:HideSurface(frame)
    frame.surfaceHidden=true
    if frame.headerSurface then frame.headerSurface:Hide() end
    if frame.hudSurface then frame.hudSurface:Hide() end
    if frame.fill then frame.fill:Hide() end
    for _,edge in ipairs(frame.edges or {}) do edge:Hide() end
    if frame.sheen then frame.sheen:Hide() end
end
function UI:Panel(parent,width,height,fill,corner,alpha)
    return compatibility(self:GetStyle():Panel(parent,width,height,fill or "panel",corner,alpha))
end
function UI:Label(parent,text,size,color,bold)
    return self:GetStyle():Label(parent,text,size,color,bold and "bold" or "regular")
end
function UI:Button(parent,text,width,callback,primary)
    local kind=type(primary)=="string" and primary or primary and "primary" or "secondary"
    local button=self:GetStyle():Button(parent,text,width,function(control) invoke("button",callback,control) end,kind)
    button.primary=primary==true
    return compatibility(button)
end
function UI:Icon(parent,name,size,color) return self:GetStyle():Icon(parent,name,size,color) end
function UI:Logo(parent,size) return self:GetStyle():Logo(parent,size) end
function UI:ResizeGrip(parent) return compatibility(self:GetStyle():ResizeGrip(parent)) end
function UI:FitCaption(label,text,width) return self:GetStyle():FitCaption(label,text,width) end
function UI:IconButton(parent,name,callback,kind)
    return compatibility(self:GetStyle():IconButton(parent,name,function(control) invoke("icon",callback,control) end,kind))
end
function UI:Switch(parent,initial,callback)
    local control=compatibility(self:GetStyle():Switch(parent,initial,function(value) invoke("switch",callback,value) end))
    control.isSwitch=true
    self:GetStyle():Tooltip(control)
    return control
end
-- Right-click menu for text fields (finding 48). WoW gives addons no
-- clipboard access: copy/cut/paste stay on Ctrl+C / Ctrl+X / Ctrl+V.
function UI:TextFieldMenu(input,changed)
    if input.bvTextMenu then return end
    input.bvMenuStyle=input.bvMenuStyle or self:GetStyle()
    input.bvTextMenu=true;input.bvHistory={}
    input:HookScript("OnTextChanged",function(self,user)
        if user and not self.bvUndoing then
            local h=self.bvHistory;h[#h+1]=self.bvLastText or "";if #h>20 then table.remove(h,1) end
        end
        self.bvLastText=self:GetText()
    end)
    input:HookScript("OnMouseDown",function(self,button)
        if button~="RightButton" then return end
        local options={{value="all",label="Select all"},{value="clear",label="Clear"}}
        if #self.bvHistory>0 then options[#options+1]={value="undo",label="Undo last change"} end
        options[#options+1]={value="hint",label="Copy Ctrl+C / Cut Ctrl+X / Paste Ctrl+V"}
        UI:ContextMenu(self,options,function(command)
            if command=="all" then self:SetFocus();self:HighlightText()
            elseif command=="clear" then
                local h=self.bvHistory;h[#h+1]=self:GetText();self:SetText("");self:SetFocus()
                if changed then changed() end
            elseif command=="undo" then
                local previous=table.remove(self.bvHistory)
                if previous then self.bvUndoing=true;self:SetText(previous);self.bvUndoing=nil;self:SetFocus();if changed then changed() end end
            end
        end)
    end)
end
function UI:Input(parent,width,onSubmit)
    local input=compatibility(self:GetStyle():Input(parent,width))
    self:TextFieldMenu(input)
    input:SetMaxLetters(48)
    input:SetScript("OnEnterPressed",function(self) invoke("input",onSubmit,self:GetText()); self:ClearFocus() end)
    self:GetStyle():Tooltip(input)
    return input
end
function UI:Tabs(parent,definitions,callback)
    local style=self:GetStyle()
    local host=CreateFrame("Frame",nil,parent); host.buttons={}; host.pool={}
    M.Size(host,math.max(1,#definitions)*130,38)
    -- host.bvHeight: compact callers (settings window) use 30.
    function host:Arrange(width)
        M.Width(self,width)
        local count=#(self.definitions or {})
        if count==0 then return end
        local gap=style.shellPresentation=="clean" and 0 or 8; local cell=math.min(132,math.max(1,(width-gap*(count-1))/count))
        local x=0
        local height=self.bvHeight or 38
        M.Height(self,height)
        for index,definition in ipairs(self.definitions) do
            local button=self.buttons[definition.id]
            button:ClearAllPoints(); M.Point(button,"TOPLEFT",x,0)
            local bw=cell
            if style.shellPresentation=="clean" then
                local label=button.label;label:SetText(button.fullLabel or definition.label)
                bw=math.min(cell,math.max(48,math.ceil(M.ToDesign(label:GetUnboundedStringWidth()))+26))
            end
            M.Size(button,bw,height);x=x+bw+gap
            if style.shellPresentation=="clean" then button:SetLabelText(definition.label)end
        end
    end
    function host:SetDefinitions(items)
        self.definitions=items or {}; self.buttons={}
        for index,definition in ipairs(self.definitions) do
            local button=self.pool[index]
            if not button then
                button=UI:WithStyle(style,function()return UI:Button(self,"",120,function(control) invoke("tab",callback,control.tabID) end,"tab")end)
                if style.shellPresentation=="clean" then style:Font(button.label,12);button:SetLabelInsets(12,12,"CENTER")end
                self.pool[index]=button
            end
            button.tabID=definition.id; button:SetLabelText(definition.label); button:Show()
            self.buttons[definition.id]=button
        end
        for index=#self.definitions+1,#self.pool do self.pool[index]:Hide() end
        self:Arrange(M.GetWidth(self))
    end
    function host:SetValue(id)
        self.value=id
        for key,button in pairs(self.buttons) do button:SetSelected(key==id) end
    end
    host:SetDefinitions(definitions)
    return host
end
function UI:AttachTooltip(widget,title,text)
    widget.tooltipTitle,widget.tooltipText,widget.tooltipBody=title,text,text
    self:GetStyle():Tooltip(widget,title,text)
end
-- Tooltip (Core 0.8.96, Florian 2026-10-08: less bulky, less prototype):
-- as wide as its content (150..240), tight padding, a dark translucent
-- ground with a hairline edge, the title in the text colour. text may be a
-- string (explanations, as before) or a table: {tag=, tagColor={r,g,b},
-- rows={{label,value},...}, text=, hint=} for values and a separate, muted
-- line of mouse actions under a hairline.
local TIP={MIN=150,MAX=240,PADX=10,TOP=7,BOTTOM=8,TITLE=13,BODY=12,SMALL=11}
local function tipRegion(parent,size,role,bold)
    local label=parent.bvTooltipStyle:Label(parent,"",size,role,bold and "bold" or "regular")
    label:SetJustifyV("TOP");label:SetWordWrap(true)
    return label
end
function UI:TooltipFrame(style)
    if not style and self.tooltip then return self.tooltip end
    style=style or self:ToolStyle()
    self.tooltips=self.tooltips or {}
    if self.tooltips[style] then return self.tooltips[style] end
    local tooltip=CreateFrame("Frame",nil,UIParent)
    tooltip.bvTooltipStyle=style
    tooltip:SetFrameStrata("TOOLTIP");tooltip:SetClampedToScreen(true);tooltip:EnableMouse(false);tooltip:Hide()
    tooltip.ground=tooltip:CreateTexture(nil,"BACKGROUND");tooltip.ground:SetAllPoints(tooltip)
    tooltip.edges={}
    for i=1,4 do tooltip.edges[i]=tooltip:CreateTexture(nil,"BORDER") end
    tooltip.edges[1]:SetPoint("TOPLEFT");tooltip.edges[1]:SetPoint("TOPRIGHT");tooltip.edges[1]:SetHeight(1)
    tooltip.edges[2]:SetPoint("BOTTOMLEFT");tooltip.edges[2]:SetPoint("BOTTOMRIGHT");tooltip.edges[2]:SetHeight(1)
    tooltip.edges[3]:SetPoint("TOPLEFT");tooltip.edges[3]:SetPoint("BOTTOMLEFT");tooltip.edges[3]:SetWidth(1)
    tooltip.edges[4]:SetPoint("TOPRIGHT");tooltip.edges[4]:SetPoint("BOTTOMRIGHT");tooltip.edges[4]:SetWidth(1)
    -- Rounded and crisp like the windows, with their soft shadow (Florian
    -- 2026-10-11, finer); the square ground and edges stay as the fallback.
    if style.materialProfile=="interface" then
        style:Skin(tooltip,"tooltip",6,1)
        tooltip.ground:Hide()
        for _,edge in ipairs(tooltip.edges) do edge:Hide() end
    elseif DS.Slice and DS.SHADOW then
        local lab="Interface\\AddOns\\BVAddonSuite\\Media\\DesignLab\\"
        tooltip.fills=DS.Slice(tooltip,lab.."surface.tga",8,"BACKGROUND",0)
        tooltip.lines=DS.Slice(tooltip,lab.."border.tga",8,"BORDER",0)
        tooltip.shade=DS.Slice(tooltip,DS.SHADOW,DS.SHADOWCORNER*.6,"BACKGROUND",-2,DS.SHADOWEXPAND*.6)
        tooltip.ground:Hide()
        for _,edge in ipairs(tooltip.edges) do edge:Hide() end
    end
    tooltip.title=tipRegion(tooltip,TIP.TITLE,"text",true);tooltip.title:SetWordWrap(false)
    tooltip.tag=tipRegion(tooltip,TIP.SMALL,false);tooltip.tag:SetWordWrap(false);tooltip.tag:SetJustifyH("RIGHT")
    tooltip.body=tipRegion(tooltip,TIP.BODY,"text")
    tooltip.rule=tooltip:CreateTexture(nil,"ARTWORK")
    tooltip.hint=tipRegion(tooltip,TIP.SMALL,"muted")
    tooltip.labels,tooltip.values={},{}
    function tooltip:PaintContent()
        local br,bg,bb=style:Color("bg")
        if style.materialProfile~="interface" then
            self.ground:SetColorTexture(br*.6,bg*.6,bb*.6,.95)
            for _,edge in ipairs(self.edges) do edge:SetColorTexture(1,1,1,.1) end
            for _,t in ipairs(self.fills or {}) do t:SetVertexColor(br*.6,bg*.6,bb*.6,.96) end
            for _,t in ipairs(self.lines or {}) do t:SetVertexColor(1,1,1,.12) end
        end
        if style.materialProfile=="interface" then self.rule:SetColorTexture(style:Color("edge",.35))
        else self.rule:SetColorTexture(1,1,1,.08) end
        self.title:SetTextColor(style:Color("text"))
        local color=self.content and self.content.tagColor
        if color then self.tag:SetTextColor(color[1],color[2],color[3]) else self.tag:SetTextColor(style:Color("muted")) end
    end
    style:Bind(function()tooltip:PaintContent()end,tooltip)
    -- Older callers may still set these fields on the frame.
    self.tooltips[style]=tooltip
    return tooltip
end
-- Width of a text at a size (the client measures; a fallback estimate where it cannot).
local function textWidth(region,value,size)
    region:SetWidth(2000);region:SetText(value)
    local width=region.GetStringWidth and region:GetStringWidth()
    if type(width)=="number" and width>0 then return M.ToDesign(width) end
    return #value*size*.52
end
local function textHeight(region,value,size,width)
    M.Width(region,width);region:SetHeight(0);region:SetText(value)
    local _,breaks=value:gsub("\n","")
    local measured=region.GetStringHeight and region:GetStringHeight()
    return math.max((breaks+1)*size*1.3,type(measured)=="number" and M.ToDesign(measured) or 0)
end
function UI:ShowTooltip(owner,title,text)
    title=title or owner.tooltipTitle
    if not title or not ns.Settings:Get("tooltips") then return end
    -- The owner determines appearance, never the ambient factory at hover time.
    local style=owner.bvTooltipStyle or owner.bvStyle
    local parent=owner.GetParent and owner:GetParent()
    while not style and parent do
        style=parent.bvTooltipStyle or parent.bvStyle
        parent=parent.GetParent and parent:GetParent()
    end
    style=style or self:ToolStyle()
    local tooltip=self:TooltipFrame(style)
    if self.tooltip and self.tooltip~=tooltip then self:HideTooltip() end
    self.tooltip=tooltip
    tooltip.owner=owner
    -- Its owner's scale; a pin on a zoomed map: the map's, not the zoom
    -- (Florian 2026-10-14: zoomed in, the tooltip grew with it).
    local ref=owner.tooltipScaleFrame or owner
    tooltip:SetScale(ref:GetEffectiveScale()/UIParent:GetEffectiveScale())
    local content=text or owner.tooltipText or ""
    if type(content)~="table" then content={text=content} end
    local rows=type(content.rows)=="table" and content.rows or {}
    local body=type(content.text)=="string" and content.text or ""
    local hint=type(content.hint)=="string" and content.hint or ""
    local tag=type(content.tag)=="string" and content.tag or ""
    tooltip.content=content
    tooltip:PaintContent()
    -- Width: as much as the content needs, within MIN..MAX.
    local need=textWidth(tooltip.title,title,TIP.TITLE)+(tag~="" and textWidth(tooltip.tag,tag,TIP.SMALL)+12 or 0)
    local labelWidth,valueWidth=0,0
    for i,row in ipairs(rows) do
        tooltip.labels[i]=tooltip.labels[i] or tipRegion(tooltip,TIP.BODY,"muted")
        tooltip.values[i]=tooltip.values[i] or tipRegion(tooltip,TIP.BODY,"text")
        tooltip.labels[i]:SetWordWrap(false);tooltip.values[i]:SetWordWrap(false);tooltip.values[i]:SetJustifyH("RIGHT")
        labelWidth=math.max(labelWidth,textWidth(tooltip.labels[i],tostring(row[1] or ""),TIP.BODY))
        valueWidth=math.max(valueWidth,textWidth(tooltip.values[i],tostring(row[2] or ""),TIP.BODY))
    end
    if #rows>0 then need=math.max(need,labelWidth+14+valueWidth) end
    if body~="" then for line in body:gmatch("[^\n]+") do need=math.max(need,textWidth(tooltip.body,line,TIP.BODY)) end end
    if hint~="" then for line in hint:gmatch("[^\n]+") do need=math.max(need,textWidth(tooltip.hint,line,TIP.SMALL)) end end
    local inner=math.max(TIP.MIN,math.min(TIP.MAX,math.ceil(need)+1+2*TIP.PADX))-2*TIP.PADX
    local y=TIP.TOP
    tooltip.title:ClearAllPoints();M.Point(tooltip.title,"TOPLEFT",tooltip,"TOPLEFT",TIP.PADX,-y)
    M.Size(tooltip.title,inner-(tag~="" and math.min(80,textWidth(tooltip.tag,tag,TIP.SMALL))+12 or 0),TIP.TITLE*1.3);tooltip.title:SetText(title)
    tooltip.tag:ClearAllPoints();M.Point(tooltip.tag,"TOPRIGHT",tooltip,"TOPRIGHT",-TIP.PADX,-y-1);M.Size(tooltip.tag,80,TIP.SMALL*1.3)
    tooltip.tag:SetText(tag);tooltip.tag:SetShown(tag~="")
    y=y+TIP.TITLE*1.3+3
    for i,row in ipairs(rows) do
        local label,value=tooltip.labels[i],tooltip.values[i]
        label:ClearAllPoints();M.Point(label,"TOPLEFT",tooltip,"TOPLEFT",TIP.PADX,-y);M.Size(label,inner*.5,TIP.BODY*1.3);label:SetText(tostring(row[1] or ""))
        value:ClearAllPoints();M.Point(value,"TOPRIGHT",tooltip,"TOPRIGHT",-TIP.PADX,-y);M.Size(value,inner-math.min(labelWidth,inner*.5)-8,TIP.BODY*1.3);value:SetText(tostring(row[2] or ""))
        label:SetTextColor(style:Color("muted"));value:SetTextColor(style:Color("text"))
        label:Show();value:Show()
        y=y+TIP.BODY*1.3
    end
    for i=#rows+1,#tooltip.labels do tooltip.labels[i]:Hide();tooltip.values[i]:Hide() end
    if body~="" then
        if #rows>0 then y=y+3 end
        local height=textHeight(tooltip.body,body,TIP.BODY,inner)
        tooltip.body:ClearAllPoints();M.Point(tooltip.body,"TOPLEFT",tooltip,"TOPLEFT",TIP.PADX,-y);M.Height(tooltip.body,height)
        tooltip.body:SetTextColor(style:Color("text"));tooltip.body:Show()
        y=y+height
    else tooltip.body:Hide() end
    if hint~="" then
        y=y+5
        tooltip.rule:ClearAllPoints();M.Point(tooltip.rule,"TOPLEFT",tooltip,"TOPLEFT",TIP.PADX,-y);M.Size(tooltip.rule,inner,1);tooltip.rule:Show()
        y=y+5
        local height=textHeight(tooltip.hint,hint,TIP.SMALL,inner)
        tooltip.hint:ClearAllPoints();M.Point(tooltip.hint,"TOPLEFT",tooltip,"TOPLEFT",TIP.PADX,-y);M.Height(tooltip.hint,height)
        tooltip.hint:SetTextColor(style:Color("muted"));tooltip.hint:Show()
        y=y+height
    else tooltip.rule:Hide();tooltip.hint:Hide() end
    M.Size(tooltip,inner+2*TIP.PADX,y+TIP.BOTTOM)
    tooltip:ClearAllPoints();M.Point(tooltip,"TOPLEFT",owner,"BOTTOMLEFT",0,-6);tooltip:Show()
end
function UI:HideTooltip(owner)
    if self.tooltip and (not owner or self.tooltip.owner==owner) then self.tooltip:Hide(); self.tooltip.owner=nil end
end
-- Loading indicators may opt into their captured Interface context. Omission
-- preserves the global material preview and callers with their own bar colours.
function UI:StatusBar(parent,width,height,style)
    local captured=style and style.materialProfile=="interface" and style or nil
    local bar=CreateFrame("StatusBar",nil,parent); M.Size(bar,width,height); bar:SetMinMaxValues(0,1); bar:SetValue(.72)
    bar.bvStyle=captured
    return self:Bind(bar,function(self)
        local texture = ns.Media:StatusBar(ns.Settings:Get("statusbar"))
        self:SetStatusBarTexture(texture); self:SetStatusBarColor((captured or Theme):Color("accent"))
    end)
end

-- Stateless window chrome shared by production and isolated design contexts.
-- Callers retain their own geometry, lifecycle and maximize/minimize state.
function UI:WindowChrome(window,style,options)
    options=options or {}; style=style or self:GetStyle()
    local shell=window.shellMetrics or ns.ShellMetrics.Window(options.shellMetrics)
    window.shellMetrics=shell
    style:Skin(window,"bg",8,function() return style.opacity end,true); compatibility(window)
    local chrome={}
    local bar=CreateFrame("Frame",nil,window); chrome.titlebar=bar
    M.Point(bar,"TOPLEFT"); M.Point(bar,"TOPRIGHT"); M.Height(bar,shell.titlebarHeight)
    bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    local rule=style:Rule(bar); chrome.rule=rule; M.Point(rule,"BOTTOMLEFT"); M.Point(rule,"BOTTOMRIGHT")
    local hud=options.hudIcon and style.materialProfile=="interface"
    chrome.brand=hud and style:Icon(bar,options.hudIcon,16,"accentText") or style:Logo(bar,24)
    M.Point(chrome.brand,"LEFT",hud and 10 or 14,0)
    chrome.title=style:Label(bar,options.title or "Addon Suite",options.titleSize or (hud and 13 or 14),"text","bold")
    M.Point(chrome.title,"LEFT",hud and 33 or 46,0); M.Height(chrome.title,shell.titlebarHeight); chrome.title:SetWordWrap(false)
    chrome.caption=style:Label(bar,options.caption or "",12,"muted")
    M.Point(chrome.caption,"LEFT",136,0); M.Size(chrome.caption,130,shell.titlebarHeight)
    chrome.caption:SetShown(options.caption~=nil)
    local function action(name,callback)
        if hud and name=="close" then
            local close=style:IconButton(bar,name,function() invoke("window/close",callback) end,"icon-only")
            M.Size(close,30,30)
            return close
        end
        local button=style:IconButton(bar,name,function() invoke("window/"..name,callback) end,"window")
        -- Shared shell contexts also create standalone windows. Their caption
        -- renderer needs the same action/owner identity as the Config shell.
        if style.materialProfile=="interface" then
            button.shellAction=name;button.shellWindow=window
            if style.shellPresentation=="clean" then ns.ShellMaterials:PaintButton(style,button,"window") end
        end
        return button
    end
    chrome.close=action("close",options.onClose or function() window:Hide() end)
    chrome.maximize=action("max",options.onMaximize)
    chrome.minimize=action("minus",options.onMinimize)
    local grouped=style.materialProfile=="interface" and not ns.ShellMetrics.IsWoW(style.interfaceThemeKey)
    if grouped and not hud then
        for _,button in ipairs({chrome.close,chrome.maximize,chrome.minimize}) do M.Size(button,32,30) end
    end
    M.Point(chrome.close,"RIGHT",hud and -4 or -10,0)
    if grouped then
        -- Overlap the one-unit rims so every key also has a complete outline
        -- when a neighbouring action is hidden or its width changes.
        M.Point(chrome.maximize,"RIGHT",chrome.close,"LEFT",1,0)
        M.Point(chrome.minimize,"RIGHT",chrome.maximize,"LEFT",1,0)
    else
        M.Point(chrome.maximize,"RIGHT",-46,0); M.Point(chrome.minimize,"RIGHT",-82,0)
    end
    chrome.maximize.restoreIcon=style:Icon(chrome.maximize,"restore",16,"text")
    M.Point(chrome.maximize.restoreIcon,"CENTER"); chrome.maximize.restoreIcon:Hide()
    style:Tooltip(chrome.close,"Close","Close this window.")
    style:Tooltip(chrome.maximize,"Maximize","Maximize or restore this window.")
    style:Tooltip(chrome.minimize,"Minimize","Collapse or restore this window.")
    local grip=CreateFrame("Button",nil,window); chrome.grip=grip
    M.Size(grip,18,18); M.Point(grip,"BOTTOMRIGHT"); grip:EnableMouse(true)
    for i=1,3 do
        local line=grip:CreateLine(nil,"OVERLAY"); M.Thickness(line,1)
        M.LineStart(line,"BOTTOMRIGHT",grip,-3-i*4,3); M.LineEnd(line,"BOTTOMRIGHT",grip,-3,3+i*4)
        style:Bind(function() line:SetColorTexture(style:Color("muted",.7)) end,line)
    end
    bar:SetScript("OnDragStart",function() invoke("window/drag",options.onDragStart or function() window:StartMoving() end) end)
    bar:SetScript("OnDragStop",function() invoke("window/dragstop",options.onDragStop or function() window:StopMovingOrSizing() end) end)
    grip:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then invoke("window/resize",options.onResizeStart or function() window:StartSizing("BOTTOMRIGHT") end) end end)
    grip:SetScript("OnMouseUp",function() invoke("window/resizestop",options.onResizeStop or function() window:StopMovingOrSizing() end) end)
    function chrome:SetMaximized(value)
        self.maximize.icon:SetShown(not value); self.maximize.restoreIcon:SetShown(value)
        if self.presentation then self.presentation:Chrome()
        elseif style.materialProfile=="interface" and style.shellPresentation=="clean" then ns.ShellMaterials:PaintButton(style,self.maximize,"window") end
    end
    if options.compact then chrome.maximize:Hide(); chrome.minimize:Hide() end
    local function titleGeometry() M.Width(chrome.title,math.max(1,M.GetWidth(window)-(hud and 72 or options.compact and 98 or 174))) end
    window:HookScript("OnSizeChanged",titleGeometry); titleGeometry()
    window.chrome=chrome
    return chrome
end

function UI:Window(name,width,height,options)
    options=options or {}
    local shell=ns.ShellMetrics.Window(options.shellMetrics)
    if options.hudIcon and self:GetStyle().materialProfile=="interface" then
        shell.titlebarHeight,shell.contentTop=32,32
    end
    ns.ShellMetrics.ContentSize(width,height,shell)
    ns.ShellMetrics.ContentSize(options.minWidth or 480,options.minHeight or 420,shell)
    local style=self:GetStyle()
    local window=CreateFrame("Frame",name,UIParent); window:Hide();window.shellMetrics=shell
    M.Size(window,width,height); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true); window:SetMovable(true); window:SetResizable(true); window:EnableMouse(true)
    M.ResizeBounds(window,options.minWidth or 480,options.minHeight or 420)
    window.content=CreateFrame("Frame",nil,window)
    M.Point(window.content,"TOPLEFT",window,"TOPLEFT",shell.contentLeft,-shell.contentTop); M.Point(window.content,"BOTTOMRIGHT",window,"BOTTOMRIGHT",-shell.contentRight,shell.contentBottom)
    function window:SetTitle(text) self.title:SetText(text or "") end
    local function snapshot()
        return {width=M.GetWidth(window),height=M.GetHeight(window),point={window:GetPoint(1)}}
    end
    local function geometry(saved)
        window:ClearAllPoints(); window:SetPoint(unpack(saved.point)); M.Size(window,saved.width,saved.height)
    end
    function window:Restore()
        if self.minimized then
            self.minimized=false; M.ResizeBounds(self,options.minWidth or 480,options.minHeight or 420)
            geometry(self.beforeMinimize); self.content:Show(); self.resizeGrip:Show()
        elseif self.maximized then self.maximized=false; geometry(self.beforeMaximize) end
        self.chrome:SetMaximized(self.maximized); self.resizeGrip:SetShown(not self.maximized)
        if self.shellPresentation then self.shellPresentation:Chrome()end
    end
    function window:Minimize()
        if self.minimized then self:Restore(); return end
        self.beforeMinimize=snapshot(); self.minimized=true
        self.content:Hide(); self.resizeGrip:Hide(); UI:HideTooltip(); if UI.CloseDropdown then UI:CloseDropdown() end
        M.ResizeBounds(self,shell.collapsedMinWidth,shell.collapsedHeight); M.Size(self,math.min(shell.collapsedMaxWidth,self.beforeMinimize.width),shell.collapsedHeight)
        if self.shellPresentation then self.shellPresentation:Chrome()end
    end
    function window:ToggleMaximize()
        if self.minimized then self:Restore() end
        if self.maximized then self:Restore(); return end
        self.beforeMaximize=snapshot(); self.maximized=true
        local ratio=UIParent:GetEffectiveScale()/self:GetEffectiveScale()
        self:ClearAllPoints(); self:SetPoint("CENTER",UIParent,"CENTER")
        self:SetSize(UIParent:GetWidth()*ratio*.94,UIParent:GetHeight()*ratio*.90)
        self.chrome:SetMaximized(true); self.resizeGrip:Hide()
    end
    local chrome=self:WindowChrome(window,style,{
        title=options.title or "Addon Suite",
        compact=options.compact,
        hudIcon=options.hudIcon,
        onClose=function() window:Hide() end,
        onMaximize=function() window:ToggleMaximize() end,
        onMinimize=function() window:Minimize() end,
        onDragStart=function() if not window.maximized then window:StartMoving() end end,
        onResizeStart=function() if not window.minimized and not window.maximized then window:StartSizing("BOTTOMRIGHT") end end,
    })
    window.drag,window.title=chrome.titlebar,chrome.title
    window.close,window.maximize,window.minimize=chrome.close,chrome.maximize,chrome.minimize
    window.resizeGrip=chrome.grip
    -- Persistent gameplay windows share the HUD motif without decorating
    -- nested panels or the separate, already textured authoring shell.
    if options.gameplaySurface then ns.InterfaceSurfaces:AttachHUD(style,window) end
    window:HookScript("OnHide",function(self)
        self:StopMovingOrSizing(); UI:HideTooltip(); if UI.CloseDropdown then UI:CloseDropdown() end
    end)
    self:ManageWindow(window)
    if name then UISpecialFrames[#UISpecialFrames+1]=name end
    return window
end
-- Snapshot only the addon-owned managed stack; consumers never enumerate game UI.
function UI:VisibleWindows()
    local out={}
    for _,window in ipairs(stack)do if window:IsShown()then out[#out+1]=window end end
    return out
end
-- Movable windows (in-game round 4): drag by the handle, clamped to the
-- screen; the position is remembered account-wide per window (key), a
-- double-click on the handle resets it to the centre.
local function positionStore()
    local db=ns.Settings and ns.Settings.db
    if type(db)~="table" then return end
    if type(db.windowPositions)~="table" then db.windowPositions={} end
    return db.windowPositions
end
local function positionKey(frame)
    if frame.positionKey then return frame.positionKey end
    local name=frame.GetName and frame:GetName()
    if name then return name end
    local title=frame.title and frame.title.GetText and frame.title:GetText()
    return type(title)=="string" and title~="" and "dialog:"..title or nil
end
function UI:SaveWindowPosition(frame)
    local store,key=positionStore(),positionKey(frame);if not store or not key then return end
    local point,_,relPoint,x,y=frame:GetPoint(1)
    if type(point)=="string" and type(x)=="number" and type(y)=="number" then store[key]={point,relPoint or point,x,y} end
end
function UI:RestoreWindowPosition(frame)
    local store,key=positionStore(),positionKey(frame)
    local saved=store and key and store[key]
    if type(saved)~="table" or type(saved[3])~="number" or type(saved[4])~="number" then return false end
    frame:ClearAllPoints();frame:SetPoint(saved[1],UIParent,saved[2],saved[3],saved[4]);return true
end
function UI:ResetWindowPosition(frame)
    local store,key=positionStore(),positionKey(frame)
    if store and key then store[key]=nil end
    frame:ClearAllPoints();frame:SetPoint("CENTER",UIParent,"CENTER",0,0)
end
function UI:MakeMovable(frame,handle,key)
    frame.positionKey=key or frame.positionKey
    frame:SetMovable(true);frame:SetClampedToScreen(true)
    handle:EnableMouse(true);handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart",function() frame:StartMoving() end)
    handle:SetScript("OnDragStop",function() frame:StopMovingOrSizing();UI:SaveWindowPosition(frame) end)
    if handle.RegisterForClicks then handle:RegisterForClicks("LeftButtonUp") end
    handle:SetScript("OnDoubleClick",function() UI:ResetWindowPosition(frame) end)
    frame:HookScript("OnShow",function() UI:RestoreWindowPosition(frame) end)
    frame:HookScript("OnHide",function() frame:StopMovingOrSizing() end)
    return handle
end
-- Opt-in modal Escape routing for owned dialogs; the existing window stack stays authoritative.
local strataOrder={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
local function dialogHasPriority(dialog)
    if not dialog:IsVisible() then return false end
    for _,popup in pairs({UI.dropdown,UI.colorPopup})do
        if popup~=dialog and popup:IsVisible() then return false end
    end
    local rank=strataOrder[dialog:GetFrameStrata()] or 0
    for _,other in ipairs(stack)do
        if other~=dialog and other:IsVisible() then
            local otherRank=strataOrder[other:GetFrameStrata()] or 0
            if otherRank>rank or (otherRank==rank and other:GetFrameLevel()>dialog:GetFrameLevel())then return false end
        end
    end
    return true
end
local function dialogOwnsFocus(dialog,focus)
    for _=1,64 do
        if not focus or (issecretvalue and issecretvalue(focus))then return false end
        if focus==dialog then return true end
        if not focus.GetParent or (focus.IsForbidden and focus:IsForbidden())then return false end
        focus=focus:GetParent()
    end
    return false
end
function UI:ScopeDialogEscape(dialog)
    if dialog.escapeController then return dialog.escapeController end
    local controller={};dialog.escapeController=controller
    local function clearFocusKey()
        if controller.focusTimer then controller.focusTimer:Cancel();controller.focusTimer=nil end
        controller.focusKey=nil
    end
    local function focusKey()
        clearFocusKey();controller.focusKey=true
        -- EditBox may consume key-up. Keep only a single dispatch-turn guard, never an idle poll.
        controller.focusTimer=C_Timer.NewTimer(0,function()controller.focusTimer=nil;controller.focusKey=nil end)
    end
    function dialog:TrackEscapeInput(input)
        input:HookScript("OnEscapePressed",function()if dialog:IsVisible()then focusKey()end end)
        input:HookScript("OnKeyUp",function(_,key)if key=="ESCAPE"then clearFocusKey()end end)
    end
    dialog:SetScript("OnKeyDown",function(self,key)
        if InCombatLockdown()then return end
        if not dialogHasPriority(self)then UI:SetKeyboardPropagation(self,true);return end
        local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and not dialogOwnsFocus(self,focus)then UI:SetKeyboardPropagation(self,true);return end
        if key~="ESCAPE"then UI:SetKeyboardPropagation(self,not focus);return end
        UI:SetKeyboardPropagation(self,false)
        if controller.focusKey then return end
        if focus then focusKey();focus:ClearFocus();return end
        self:Hide()
    end)
    dialog:SetScript("OnKeyUp",function(_,key)if key=="ESCAPE"then clearFocusKey()end end)
    local function shown()
        clearFocusKey();dialog:EnableKeyboard(not InCombatLockdown());UI:SetKeyboardPropagation(dialog,true)
        ns.Events:Subscribe(controller,"PLAYER_REGEN_DISABLED",function()dialog:EnableKeyboard(false);clearFocusKey()end)
        ns.Events:Subscribe(controller,"PLAYER_REGEN_ENABLED",function()UI:SetKeyboardPropagation(dialog,true);dialog:EnableKeyboard(true)end)
    end
    dialog:HookScript("OnShow",shown)
    dialog:HookScript("OnHide",function()clearFocusKey();ns.Events:Release(controller);dialog:EnableKeyboard(false)end)
    if dialog:IsVisible()then shown()end
    return controller
end

function UI:Dialog(name,width,height,owner,options)
    local dialog=self:GetStyle():Dialog(UIParent,width,height,name)
    dialog:SetPoint("CENTER"); dialog:SetFrameStrata("FULLSCREEN_DIALOG"); dialog:SetClampedToScreen(true)
    -- Title bar drag handle (leaves the close button free).
    dialog.dragHandle=CreateFrame("Button",nil,dialog)
    dialog.dragHandle:SetPoint("TOPLEFT",dialog,"TOPLEFT",0,0);dialog.dragHandle:SetPoint("TOPRIGHT",dialog,"TOPRIGHT",-M.ToNative(48),0)
    dialog.dragHandle:SetHeight(M.ToNative(36));dialog.dragHandle:SetFrameLevel(dialog:GetFrameLevel()+2)
    self:AttachTooltip(dialog.dragHandle,"Move window","Drag to move. Double-click to reset the position.")
    self:MakeMovable(dialog,dialog.dragHandle)
    function dialog:FitContent(w,h)
        M.Size(self,w,h); UI:FitWindow(self,w,h,ns.Settings:Get("scale"))
    end
    self:ManageWindow(dialog)
    if options and options.escapeScope then self:ScopeDialogEscape(dialog)end
    if name then UISpecialFrames[#UISpecialFrames+1]=name end
    if owner then owner:HookScript("OnHide",function() dialog:Hide() end) end
    dialog:HookScript("OnHide",function() UI:HideTooltip(); if UI.CloseDropdown then UI:CloseDropdown() end end)
    return dialog
end

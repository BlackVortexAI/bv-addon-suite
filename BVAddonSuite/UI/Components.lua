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

function UI:GetStyle()
    if self.styleContext then return self.styleContext end
    local owner={}
    function owner:ShowTooltip(control,title,body) UI:ShowTooltip(control,title,body) end
    function owner:HideTooltip() UI:HideTooltip() end
    function owner:ShowDropdown(control) UI:OpenDropdown(control) end
    local style=DS:New(owner)
    style.theme=ns.Settings:Get("themeKey") or "violet"
    style.colorResolver=function(key,alpha) return Theme:Color(key,alpha) end
    style.fontResolver=function(region,size,weight)
        Theme:Font(region,size,(weight=="bold" or weight=="display") and Theme:BoldFont() or nil)
    end
    -- Keep production painters in the existing weak widget registry. A context
    -- must not permanently retain closed/rebuilt module controls in paints/edits.
    style.registerPaint=function(widget,paint)
        widget.bvPaints=widget.bvPaints or {}
        widget.bvPaints[#widget.bvPaints+1]=paint
        UI.styled[widget]=function(current) for _,fn in ipairs(current.bvPaints) do fn() end end
        paint()
    end
    self.styleContext=style
    return style
end

function UI:Refresh()
    if self.styleContext then self.styleContext.theme=ns.Settings:Get("themeKey"); self.styleContext:Refresh() end
    for widget,render in pairs(self.styled) do render(widget) end
    if ns.Config then ns.Config:Refresh() end
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
function UI:HideSurface(frame)
    frame.surfaceHidden=true
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
    self:GetStyle():Tooltip(control)
    return control
end
function UI:Input(parent,width,onSubmit)
    local input=compatibility(self:GetStyle():Input(parent,width))
    input:SetMaxLetters(48)
    input:SetScript("OnEnterPressed",function(self) invoke("input",onSubmit,self:GetText()); self:ClearFocus() end)
    self:GetStyle():Tooltip(input)
    return input
end
function UI:Tabs(parent,definitions,callback)
    local host=CreateFrame("Frame",nil,parent); host.buttons={}; host.pool={}
    M.Size(host,math.max(1,#definitions)*130,38)
    function host:Arrange(width)
        M.Width(self,width)
        local count=#(self.definitions or {})
        if count==0 then return end
        local gap=8; local cell=math.min(132,math.max(1,(width-gap*(count-1))/count))
        for index,definition in ipairs(self.definitions) do
            local button=self.buttons[definition.id]
            button:ClearAllPoints(); M.Point(button,"TOPLEFT",(index-1)*(cell+gap),0); M.Size(button,cell,38)
        end
    end
    function host:SetDefinitions(items)
        self.definitions=items or {}; self.buttons={}
        for index,definition in ipairs(self.definitions) do
            local button=self.pool[index]
            if not button then
                button=UI:Button(self,"",120,function(control) invoke("tab",callback,control.tabID) end,"tab")
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
function UI:ShowTooltip(owner,title,text)
    title=title or owner.tooltipTitle
    if not title or not ns.Settings:Get("tooltips") then return end
    if not self.tooltip then
        local tooltip=self:Panel(UIParent,280,40,"raised")
        tooltip:SetFrameStrata("TOOLTIP"); tooltip:SetClampedToScreen(true)
        tooltip:EnableMouse(false)
        tooltip.title=self:Label(tooltip,"",14,"accent","bold")
        tooltip.body=self:Label(tooltip,"",12,"text")
        tooltip.title:SetJustifyV("TOP"); tooltip.body:SetJustifyV("TOP")
        tooltip.title:SetWordWrap(true); tooltip.body:SetWordWrap(true)
        self.tooltip=tooltip
    end
    local tooltip=self.tooltip; tooltip.owner=owner
    tooltip:SetScale(owner:GetEffectiveScale()/UIParent:GetEffectiveScale())
    local copy=text or owner.tooltipText or ""
    local function measure(region,value,size)
        M.Width(region,256); region:SetHeight(0); region:SetText(value)
        local _,breaks=value:gsub("\n","")
        -- Give cold FontStrings a real drawable rectangle; do not depend on a
        -- later configuration refresh to resolve their initial auto-height.
        return math.max((breaks+1)*size*1.2,M.ToDesign(region:GetStringHeight()))
    end
    local titleHeight=measure(tooltip.title,title,14)
    local bodyHeight=copy~="" and measure(tooltip.body,copy,12) or 0
    tooltip.title:ClearAllPoints(); M.Point(tooltip.title,"TOPLEFT",12,-10); M.Height(tooltip.title,titleHeight)
    tooltip.body:ClearAllPoints(); M.Point(tooltip.body,"TOPLEFT",12,-(16+titleHeight))
    tooltip.body:SetText(copy); tooltip.body:SetShown(copy~=""); M.Height(tooltip.body,bodyHeight)
    M.Height(tooltip,20+titleHeight+(copy~="" and 6+bodyHeight or 0))
    tooltip:ClearAllPoints(); M.Point(tooltip,"TOPLEFT",owner,"BOTTOMLEFT",0,-6); tooltip:Show()
end
function UI:HideTooltip(owner)
    if self.tooltip and (not owner or self.tooltip.owner==owner) then self.tooltip:Hide(); self.tooltip.owner=nil end
end
function UI:StatusBar(parent,width,height)
    local bar=CreateFrame("StatusBar",nil,parent); M.Size(bar,width,height); bar:SetMinMaxValues(0,1); bar:SetValue(.72)
    return self:Bind(bar,function(self)
        local texture = ns.Media:StatusBar(ns.Settings:Get("statusbar"))
        self:SetStatusBarTexture(texture); self:SetStatusBarColor(Theme:Color("accent"))
    end)
end

-- Stateless window chrome shared by production and isolated design contexts.
-- Callers retain their own geometry, lifecycle and maximize/minimize state.
function UI:WindowChrome(window,style,options)
    options=options or {}; style=style or self:GetStyle()
    style:Skin(window,"bg",8,function() return style.opacity end,true); compatibility(window)
    local chrome={}
    local bar=CreateFrame("Frame",nil,window); chrome.titlebar=bar
    M.Point(bar,"TOPLEFT"); M.Point(bar,"TOPRIGHT"); M.Height(bar,44)
    bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    style:Gradient(bar,"HORIZONTAL","accent",.055,"accent",0,1)
    local rule=style:Rule(bar); M.Point(rule,"BOTTOMLEFT"); M.Point(rule,"BOTTOMRIGHT")
    chrome.brand=style:Logo(bar,24)
    M.Point(chrome.brand,"LEFT",14,0)
    chrome.title=style:Label(bar,options.title or "Addon Suite",options.titleSize or 14,"text","bold")
    M.Point(chrome.title,"LEFT",46,0); M.Height(chrome.title,44); chrome.title:SetWordWrap(false)
    chrome.caption=style:Label(bar,options.caption or "",12,"muted")
    M.Point(chrome.caption,"LEFT",136,0); M.Size(chrome.caption,130,44)
    chrome.caption:SetShown(options.caption~=nil)
    local function action(name,callback)
        return style:IconButton(bar,name,function() invoke("window/"..name,callback) end,"window")
    end
    chrome.close=action("close",options.onClose or function() window:Hide() end)
    chrome.maximize=action("max",options.onMaximize)
    chrome.minimize=action("minus",options.onMinimize)
    M.Point(chrome.close,"RIGHT",-10,0); M.Point(chrome.maximize,"RIGHT",-46,0); M.Point(chrome.minimize,"RIGHT",-82,0)
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
    end
    if options.compact then chrome.maximize:Hide(); chrome.minimize:Hide() end
    local function titleGeometry() M.Width(chrome.title,math.max(1,M.GetWidth(window)-(options.compact and 98 or 174))) end
    window:HookScript("OnSizeChanged",titleGeometry); titleGeometry()
    window.chrome=chrome
    return chrome
end

function UI:Window(name,width,height,options)
    options=options or {}
    local style=self:GetStyle()
    local window=CreateFrame("Frame",name,UIParent); window:Hide()
    M.Size(window,width,height); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true); window:SetMovable(true); window:SetResizable(true); window:EnableMouse(true)
    M.ResizeBounds(window,options.minWidth or 480,options.minHeight or 420)
    window.content=CreateFrame("Frame",nil,window)
    M.Point(window.content,"TOPLEFT",window,"TOPLEFT",0,-44); M.Point(window.content,"BOTTOMRIGHT",window,"BOTTOMRIGHT",0,0)
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
    end
    function window:Minimize()
        if self.minimized then self:Restore(); return end
        self.beforeMinimize=snapshot(); self.minimized=true
        self.content:Hide(); self.resizeGrip:Hide(); UI:HideTooltip(); if UI.CloseDropdown then UI:CloseDropdown() end
        M.ResizeBounds(self,280,44); M.Size(self,math.min(360,self.beforeMinimize.width),44)
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
        onClose=function() window:Hide() end,
        onMaximize=function() window:ToggleMaximize() end,
        onMinimize=function() window:Minimize() end,
        onDragStart=function() if not window.maximized then window:StartMoving() end end,
        onResizeStart=function() if not window.minimized and not window.maximized then window:StartSizing("BOTTOMRIGHT") end end,
    })
    window.drag,window.title=chrome.titlebar,chrome.title
    window.close,window.maximize,window.minimize=chrome.close,chrome.maximize,chrome.minimize
    window.resizeGrip=chrome.grip
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
function UI:Dialog(name,width,height,owner)
    local dialog=self:GetStyle():Dialog(UIParent,width,height,name)
    dialog:SetPoint("CENTER"); dialog:SetFrameStrata("FULLSCREEN_DIALOG"); dialog:SetClampedToScreen(true)
    function dialog:FitContent(w,h)
        M.Size(self,w,h); UI:FitWindow(self,w,h,ns.Settings:Get("scale"))
    end
    self:ManageWindow(dialog)
    if name then UISpecialFrames[#UISpecialFrames+1]=name end
    if owner then owner:HookScript("OnHide",function() dialog:Hide() end) end
    dialog:HookScript("OnHide",function() UI:HideTooltip(); if UI.CloseDropdown then UI:CloseDropdown() end end)
    return dialog
end

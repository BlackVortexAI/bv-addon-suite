-- Compact settings layout shared by every settings page (0.8.71, density pass).
-- Rows are "label left, control right", 32 design units high, in two columns
-- once the page is wide enough. Sections are a small heading and a rule instead
-- of cards. Explanations live in tooltips, not in extra lines.
local _,ns=...
local UI,Theme=ns.UI,ns.Theme
local D=ns.DesignSystem.Metrics
local G={ROW=32,HEADING=30,GAP=10,COLUMN_GAP=28,TWO_COLUMNS=620,CONTROL=26,TOOLTIP_DELAY=.5}
UI.SettingsMetrics=G

-- The mouse wheel on a slider (Florian 2026-10-09: scrolling a settings
-- page, the pointer slid over a slider and changed it): it only turns the
-- slider after a click on it, until the pointer leaves; otherwise the wheel
-- goes on to the page that scrolls.
function UI:SliderWheel(slider,apply)
    slider:EnableMouseWheel(true)
    slider:HookScript("OnMouseDown",function(self) self.wheelArmed=true end)
    slider:HookScript("OnLeave",function(self) self.wheelArmed=nil end)
    slider:SetScript("OnMouseWheel",function(self,delta)
        if self.wheelArmed then return apply(delta) end
        local parent=self:GetParent()
        while parent do
            local handler=parent.GetScript and parent:GetScript("OnMouseWheel")
            local enabled=not parent.IsMouseWheelEnabled or parent:IsMouseWheelEnabled()
            if handler and enabled then return handler(parent,delta) end
            parent=parent.GetParent and parent:GetParent()
        end
    end)
end
-- Tabs of a settings page (Florian 2026-10-09: pages in tabs, not one long
-- list): tabs={{id,label,sections={...}}}; each shows its sections. The
-- settings search opens the tab that holds a hit's section.
function UI:SettingsTabs(page,grid,tabs,selected)
    local definitions={}
    for i,tab in ipairs(tabs) do definitions[i]={id=tab.id,label=tab.label,sections=tab.sections} end
    local function select(id)
        for _,tab in ipairs(tabs) do
            if tab.id==id then
                local shown={}
                for _,section in ipairs(tab.sections) do shown[section]=true end
                grid:ShowSections(shown)
            end
        end
        page.navigation.selected=id
        if page.Arrange then page:Arrange(page.width or 880) end
        if ns.Config and ns.Config.window then ns.Config:Layout() end
    end
    page.navigation={definitions=definitions,selected=selected or tabs[1].id,select=select}
    return select
end

-- Slider with its value to the right, on one line. Commits on release or wheel.
function UI:InlineSlider(parent,width,low,high,step,format,callback)
    local host=CreateFrame("Frame",nil,parent);D.Size(host,width,G.CONTROL)
    local slider=self:GetStyle():Slider(host,width-46,low,high,step,low);host.slider=slider
    D.Point(slider,"LEFT",0,0)
    host.label=self:Label(host,"",11,"text");D.Point(host.label,"RIGHT",0,0);D.Size(host.label,40,16)
    host.label:SetJustifyH("RIGHT")
    local function show(value) host.value=value;host.label:SetText(string.format(format,value)) end
    slider:SetScript("OnValueChanged",function(_,value) show(math.floor(value/step+.5)*step) end)
    local function commit() if host.value~=nil then ns:Call("slider",callback,host.value) end end
    slider:SetScript("OnMouseUp",commit)
    UI:SliderWheel(slider,function(delta)
        if slider:IsEnabled()==false then return end
        slider:SetValue(math.max(low,math.min(high,slider:GetValue()+delta*step)));commit()
    end)
    function host:SetValue(value) slider:SetValue(value);show(value) end
    function host:Enable() slider:Enable() end
    function host:Disable() slider:Disable() end
    function host:Resize(w) D.Width(self,w);D.Width(slider,w-46) end
    return host
end

-- Every grid built for a settings page is known to the settings search
-- (Core 0.8.96): Config sets buildingPage while a page builds.
UI.settingsGrids=UI.settingsGrids or {}
function UI:SettingsGrid(parent)
    local grid=CreateFrame("Frame",nil,parent);D.Size(grid,880,1)
    grid.items={};grid.hiddenSections={}
    grid.pageID=ns.Config and ns.Config.buildingPage
    UI.settingsGrids[#UI.settingsGrids+1]=grid
    local section
    -- id: filter key for page tabs; title: small heading.
    function grid:Section(id,title)
        section={id=id,kind="section",text=title,
            title=UI:Label(self,string.upper(title),11,"accent",true),
            rule=UI:Rule(self,1,"edge")}
        section.title:SetWordWrap(false)
        self.items[#self.items+1]=section
        return section
    end
    -- A setting. opts: help (tooltip), width (control width), wide (full row).
    function grid:Row(title,control,opts)
        opts=opts or {}
        local row={kind="row",section=section,control=control,wide=opts.wide,width=opts.width,
            height=opts.height or G.ROW,help=opts.help,fixedHeight=opts.fixedHeight,title=title}
        row.band=self:CreateTexture(nil,"BACKGROUND")
        row.band:SetColorTexture(1,1,1,.025)
        if title then
            row.label=UI:Label(self,title,12,"text");row.label:SetWordWrap(false)
            if opts.help then
                -- Hit area over the label so the explanation is reachable there too.
                row.hit=CreateFrame("Frame",nil,self);row.hit:EnableMouse(true)
                row.hit.tooltipDelay=G.TOOLTIP_DELAY
                UI:AttachTooltip(row.hit,title,opts.help)
            end
        end
        if opts.help and control and control.HookScript and not control.tooltipTitle then
            control.tooltipDelay=G.TOOLTIP_DELAY
            UI:AttachTooltip(control,title,opts.help)
        end
        local kind=control and control.GetObjectType and control:GetObjectType()
        if not opts.fixedHeight and (kind=="Button" and not control.isSwitch or kind=="EditBox" and not control.multiline) then
            D.Height(control,G.CONTROL)
        end
        if control then control.bvGridRow=row end
        self.items[#self.items+1]=row
        return control
    end
    -- Greys a row out and blocks its control (a feature another addon handles,
    -- Map 0.1.0); the label keeps its tooltip so the reason stays readable.
    function grid:SetRowEnabled(control,enabled)
        if not control then return end
        enabled=enabled~=false
        local alpha=enabled and 1 or .4
        control:SetAlpha(alpha)
        local row=control.bvGridRow
        if row and row.label then row.label:SetAlpha(alpha) end
        if enabled then if control.Enable then control:Enable() end elseif control.Disable then control:Disable() end
        control.bvRowDisabled=not enabled or nil
    end
    -- A search hit: the row's band lights up in the accent colour for a moment.
    function grid:Flash(item)
        if not (item and item.band) then return end
        local r,g,b=ns.Theme:Color("accent")
        item.band:SetColorTexture(r,g,b,.28)
        if item.flash then item.flash:Cancel() end
        item.flash=C_Timer.NewTimer(1.6,function() item.flash=nil;item.band:SetColorTexture(1,1,1,.025) end)
    end
    -- Arbitrary content (preview, list). Always full width.
    function grid:Block(frame,height,resize)
        local row={kind="row",section=section,control=frame,wide=true,height=height,block=true,resize=resize}
        self.items[#self.items+1]=row
        return frame
    end
    function grid:ShowSections(ids)
        self.visibleSections=ids
    end
    local function visible(item)
        local s=item.kind=="section" and item or item.section
        if not s or not grid.visibleSections then return true end
        return grid.visibleSections[s.id]==true
    end
    function grid:Arrange(width)
        D.Width(self,width)
        local two=width>=G.TWO_COLUMNS
        local column=two and (width-G.COLUMN_GAP)/2 or width
        local y,col,lineHeight=0,0,0
        local function newline() if col>0 then y=y+lineHeight;col=0;lineHeight=0 end end
        for index,item in ipairs(self.items) do
            local show=visible(item)
            if item.kind=="section" then
                item.title:SetShown(show);item.rule:SetShown(show)
                if show then
                    newline()
                    if y>0 then y=y+G.GAP end
                    UI:Place(item.title,self,2,y+8);D.Size(item.title,width-4,16)
                    UI:Place(item.rule,self,0,y+G.HEADING-3);D.Width(item.rule,width)
                    y=y+G.HEADING
                end
            else
                local c=item.control
                -- Not ipairs: label/band/hit can be nil and would stop the loop
                -- before the control (0.8.74, previews stayed visible on tab change).
                for _,key in ipairs({"label","band","hit","control"}) do
                    local r=item[key]; if r then r:SetShown(show) end
                end
                if show then
                    local wide=item.wide or not two
                    if wide then newline() end
                    local x=wide and 0 or col*(column+G.COLUMN_GAP)
                    local w=wide and width or column
                    local h=item.height
                    if item.block then
                        UI:Place(c,self,x,y+4)
                        if item.resize then h=item.resize(w) or h else D.Width(c,w) end
                        h=h+8
                    else
                        item.y=y
                        UI:Place(item.band,self,x,y+1);D.Size(item.band,w,h-2)
                        local cw=item.width or D.GetWidth(c)
                        cw=math.min(cw,math.max(40,w-110))
                        if c.Resize then c:Resize(cw) elseif not c.isSwitch then D.Width(c,cw) end
                        local ch=D.GetHeight(c)
                        UI:Place(c,self,x+w-cw-8,y+(h-ch)/2)
                        if item.label then
                            UI:Place(item.label,self,x+8,y+(h-16)/2);D.Size(item.label,math.max(20,w-cw-28),16)
                            if item.hit then UI:Place(item.hit,self,x+8,y+2);D.Size(item.hit,math.max(20,w-cw-28),h-4) end
                        end
                    end
                    lineHeight=math.max(lineHeight,h)
                    if wide then y=y+lineHeight;col=0;lineHeight=0
                    else col=col+1;if col>=2 then newline() end end
                end
            end
        end
        newline()
        D.Height(self,math.max(1,y));return y
    end
    return grid
end

-- Compact settings layout shared by every settings page (0.8.71, density pass).
-- Rows are "label left, control right", 32 design units high, in two columns
-- once the page is wide enough. Sections are a small heading and a rule instead
-- of cards. Explanations live in tooltips, not in extra lines.
local _,ns=...
local UI,Theme=ns.UI,ns.Theme
local D=ns.DesignSystem.Metrics
local G={ROW=32,HEADING=30,GAP=10,COLUMN_GAP=28,TWO_COLUMNS=620,CONTROL=26,TOOLTIP_DELAY=.5}
UI.SettingsMetrics=G
-- R9 Clean card rhythm; product sections keep their actual content and tabs.
-- Separate breakpoint: a whole card needs 420 units, unlike legacy half-rows.
local C={ROW=38,HEADER=31.84375,PAD=14,GAP=14,COLUMN_GAP=16,MIN_CARD=420,CONTROL=28}
UI.InterfaceSettingsMetrics=C
local function flat(region)
    if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false)end
    if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0)end
    return region
end

-- Tooltip hit frames also receive input over the otherwise empty label area.
-- Forward only to the nearest wheel-enabled ancestor: nested forms keep their
-- own scroll owner, while sliders and open dropdowns retain their own handlers.
local function parentWheel(self,delta)
    local parent=self:GetParent()
    while parent do
        local handler=parent.GetScript and parent:GetScript("OnMouseWheel")
        local enabled=not parent.IsMouseWheelEnabled or parent:IsMouseWheelEnabled()
        if handler and enabled then return handler(parent,delta) end
        parent=parent.GetParent and parent:GetParent()
    end
end

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
        return parentWheel(self,delta)
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
    local style=self:GetStyle();local interface=style.materialProfile=="interface"
    local host=CreateFrame("Frame",nil,parent);D.Size(host,width,interface and C.CONTROL or G.CONTROL)
    local unit=interface and (format:match("^%%[%d%.]*[df]%s*(.*)$")or ""):gsub("%%%%","%%")or ""
    if unit~="" then host.unit=style:Label(host,unit,12,"muted")end
    local function unitSize()return host.unit and math.max(10,math.ceil(D.ToDesign(host.unit:GetUnboundedStringWidth()))+2)or 0 end
    local unitWidth=unitSize()
    local trailing=interface and (46+5+(unitWidth>0 and unitWidth+5 or 0))or 46
    local slider=style:Slider(host,width-trailing,low,high,step,low);host.slider=slider
    D.Point(slider,"LEFT",0,0)
    if not interface then
        host.label=self:Label(host,"",11,"text");D.Point(host.label,"RIGHT",0,0);D.Size(host.label,40,16)
        host.label:SetJustifyH("RIGHT")
    end
    local function show(value)
        host.value=value
        if host.number then host.number:SetValue(value)
        elseif host.label then host.label:SetText(string.format(format,value))end
    end
    local function quantize(value)
        if interface then return math.max(low,math.min(high,low+math.floor((value-low)/step+.5)*step))end
        return math.floor(value/step+.5)*step
    end
    slider:SetScript("OnValueChanged",function(_,value)show(quantize(value))end)
    local function commit() if host.value~=nil then ns:Call("slider",callback,host.value) end end
    if interface then
        host.number=self:NumberInput(host,46,low,high,function(value)
            if not host:IsVisible() or not host.number:IsEnabled() then host.number:SetValue(host.value or low);return end
            value=quantize(value)
            local previous=host.value;slider:SetValue(value);show(value)
            if value~=previous then commit()end
        end)
        host.label=host.number;host.number.interfaceOpacity=1;D.Height(host.number,26);host.number:SetJustifyH("CENTER")
        D.TextInsets(host.number,4,4,2,2);style:Bind(function()style:Font(host.number,13)end,host.number)
        D.Point(host.number,"RIGHT",-(unitWidth>0 and unitWidth+5 or 0),0)
        if host.unit then D.Size(host.unit,unitWidth,16);D.Point(host.unit,"RIGHT",0,0)end
        local function cancelDraft()host.number:SetText(tostring(host.value or low));host.number:ClearFocus()end
        host.number:SetScript("OnEscapePressed",cancelDraft)
        host:HookScript("OnHide",cancelDraft)
    end
    slider:SetScript("OnMouseUp",commit)
    UI:SliderWheel(slider,function(delta)
        if slider:IsEnabled()==false then return end
        slider:SetValue(math.max(low,math.min(high,slider:GetValue()+delta*step)));commit()
    end)
    function host:SetValue(value) slider:SetValue(value);show(value) end
    function host:Enable() slider:Enable();if self.number then self.number:Enable()end end
    function host:Disable()
        if self.number then self.number:SetText(tostring(self.value or low));self.number:ClearFocus();self.number:Disable()end
        slider:Disable()
    end
    function host:Resize(w)
        if self.unit then
            -- Measure the selected font, including font refresh; byte count is not glyph width.
            unitWidth=unitSize();trailing=46+5+unitWidth+5
            D.Size(self.unit,unitWidth,16);self.number:ClearAllPoints();D.Point(self.number,"RIGHT",-(unitWidth+5),0)
        end
        D.Width(self,w);D.Width(slider,interface and math.max(1,w-trailing)or w-46)
    end
    if host.unit then host.unit.bvAfterFont=function()host:Resize(D.GetWidth(host))end end
    return host
end

-- Every grid built for a settings page is known to the settings search
-- (Core 0.8.96): Config sets buildingPage while a page builds.
UI.settingsGrids=UI.settingsGrids or {}
function UI:SettingsGrid(parent,options)
    assert(options==nil or type(options)=="table","SettingsGrid options must be a table")
    assert(not options or options.compact==nil or type(options.compact)=="boolean","SettingsGrid compact must be boolean")
    local grid=CreateFrame("Frame",nil,parent);D.Size(grid,880,1)
    grid.items={};grid.hiddenSections={}
    grid.bvStyle=UI:GetStyle();grid.compact=options and options.compact==true or false
    grid.interfaceCards=grid.bvStyle.materialProfile=="interface" and not grid.compact
    function grid:WithStyle(fn)return UI:WithStyle(self.bvStyle,fn)end
    grid.pageID=ns.Config and ns.Config.buildingPage
    UI.settingsGrids[#UI.settingsGrids+1]=grid
    local section
    -- id: filter key for page tabs; title: small heading.
    function grid:Section(id,title,opts)
        if self.interfaceCards then
            local card=CreateFrame("Frame",nil,self);D.Size(card,400,40);card.interfaceRadius=3
            self.bvStyle:Skin(card,"panel",3)
            section={id=id,kind="section",text=title,card=card,rows={},wide=opts and opts.wide,
                title=self.bvStyle:Label(card,string.upper(title),11,"accentText","bold")}
            section.title:SetWordWrap(false)
            ns.InterfaceSurfaces:AttachHeader(self.bvStyle,card,C.HEADER)
            self.items[#self.items+1]=section;return section
        end
        section={id=id,kind="section",text=title,
            -- Quiet headings, a neutral hairline (Florian 2026-10-11: finer;
            -- the accent kept for what is active).
            title=UI:Label(self,string.upper(title),11,"muted",true),
            rule=UI:Rule(self,1)}
        section.title:SetWordWrap(false)
        self.items[#self.items+1]=section
        return section
    end
    -- A setting. opts: help (tooltip), width (control width), wide (full row).
    function grid:Row(title,control,opts)
        opts=opts or {}
        local row={kind="row",section=section,control=control,wide=opts.wide,width=opts.width,
            height=opts.height or G.ROW,help=opts.help,fixedHeight=opts.fixedHeight,title=title}
        local rowParent=self.interfaceCards and section and section.card or self
        if self.interfaceCards then
            assert(section,"Interface settings rows need an explicit section")
            section.rows[#section.rows+1]=row
            row.height=opts.height or C.ROW
            if control then control:SetParent(rowParent)end
            row.line=flat(rowParent:CreateTexture(nil,"BORDER"))
            self.bvStyle:Bind(function()row.line:SetColorTexture(self.bvStyle:Color("edge"))end,row.line)
        end
        row.band=rowParent:CreateTexture(nil,"BACKGROUND")
        row.band:SetColorTexture(1,1,1,self.interfaceCards and 0 or .025)
        if title then
            row.label=self.interfaceCards and self.bvStyle:Label(rowParent,title,14,"text") or UI:Label(self,title,12,"text");row.label:SetWordWrap(false)
            if opts.help then
                -- Hit area over the label so the explanation is reachable there too.
                row.hit=CreateFrame("Frame",nil,rowParent);row.hit:EnableMouse(true)
                row.hit:EnableMouseWheel(true);row.hit:SetScript("OnMouseWheel",parentWheel)
                row.hit.tooltipDelay=G.TOOLTIP_DELAY
                self:WithStyle(function()UI:AttachTooltip(row.hit,title,opts.help)end)
            end
        end
        if opts.help and control and control.HookScript and not control.tooltipTitle then
            control.tooltipDelay=G.TOOLTIP_DELAY
            self:WithStyle(function()UI:AttachTooltip(control,title,opts.help)end)
        end
        local kind=control and control.GetObjectType and control:GetObjectType()
        if not opts.fixedHeight and (kind=="Button" and not control.isSwitch or kind=="EditBox" and not control.multiline) then
            D.Height(control,self.interfaceCards and C.CONTROL or G.CONTROL)
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
        control.bvRowDisabled=not enabled or nil
        local alpha=enabled and 1 or .4
        control:SetAlpha(alpha)
        local row=control.bvGridRow
        if row and row.label then row.label:SetAlpha(alpha) end
        if enabled then if control.Enable then control:Enable() end elseif control.Disable then control:Disable() end
    end
    -- A search hit: the row's band lights up in the accent colour for a moment.
    function grid:Flash(item)
        if not (item and item.band) then return end
        local r,g,b
        if self.bvStyle.materialProfile=="interface" then r,g,b=self.bvStyle:Color("accent")else r,g,b=ns.Theme:Color("accent")end
        item.band:SetColorTexture(r,g,b,.28)
        if item.flash then item.flash:Cancel() end
        item.flash=C_Timer.NewTimer(1.6,function() item.flash=nil;item.band:SetColorTexture(1,1,1,self.interfaceCards and 0 or .025) end)
    end
    -- Arbitrary content (preview, list). Always full width.
    function grid:Block(frame,height,resize)
        local row={kind="row",section=section,control=frame,wide=true,height=height,block=true,resize=resize}
        if self.interfaceCards then
            assert(section,"Interface settings blocks need an explicit section")
            section.rows[#section.rows+1]=row;section.wide=true
            frame:SetParent(section.card)
        end
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

    -- A section is one card. Pair only cards that fit; blocks and deliberately
    -- long sections occupy the full row. item.y remains grid-relative for search.
    function grid:ArrangeCards(width)
        D.Width(self,width)
        local two=width>=2*C.MIN_CARD+C.COLUMN_GAP
        local column=two and (width-C.COLUMN_GAP)/2 or width
        local visibleCards={}
        for _,item in ipairs(self.items)do
            if item.kind=="section" then
                local shown=visible(item);item.card:SetShown(shown)
                if shown then visibleCards[#visibleCards+1]=item end
            end
        end
        local y,pending,pendingHeight=0,false,0
        local function flush()
            if pending then y=y+pendingHeight+C.GAP;pending=false;pendingHeight=0 end
        end
        for _,s in ipairs(visibleCards)do
            local wide=not two or s.wide
            for _,row in ipairs(s.rows)do
                if row.block or row.wide or (row.width and row.width+2*C.PAD+12+110>column)then wide=true end
            end
            if wide then flush()end
            local x=wide and 0 or pending and column+C.COLUMN_GAP or 0
            local w=wide and width or column
            local cursor=1+C.HEADER
            UI:Place(s.title,s.card,C.PAD,10);D.Size(s.title,math.max(1,w-2*C.PAD),16)
            for index,row in ipairs(s.rows)do
                local control=row.control;local h=row.height
                if row.block then
                    local bodyWidth=math.max(1,w-2*C.PAD)
                    local bodyHeight
                    if row.resize then bodyHeight=self:WithStyle(function()return row.resize(bodyWidth)end)or h
                    else bodyHeight=h;D.Width(control,bodyWidth)end
                    h=bodyHeight+10+(index>1 and 1 or 0)
                    UI:Place(control,s.card,C.PAD,cursor+5)
                else
                    local cw=row.width or D.GetWidth(control)
                    cw=math.min(cw,math.max(40,w-2*C.PAD-(row.label and 122 or 0)))
                    if control.Resize then self:WithStyle(function()control:Resize(cw)end)
                    elseif not control.isSwitch then D.Width(control,cw)end
                    local ch=D.GetHeight(control)
                    h=math.max(h,ch+10)+(index>1 and 1 or 0)
                    UI:Place(control,s.card,w-C.PAD-cw,cursor+(h-ch)/2)
                    UI:Place(row.band,s.card,1,cursor);D.Size(row.band,w-2,h)
                    UI:Place(row.line,s.card,1,cursor);D.Size(row.line,w-2,1)
                    if row.label then
                        UI:Place(row.label,s.card,C.PAD,cursor+(h-18)/2)
                        D.Size(row.label,math.max(1,w-2*C.PAD-cw-12),18)
                        if row.hit then UI:Place(row.hit,s.card,C.PAD,cursor);D.Size(row.hit,math.max(1,w-2*C.PAD-cw-12),h)end
                    end
                end
                row.y=y+cursor;row.cardX=x;row.layoutHeight=h;cursor=cursor+h
            end
            local height=cursor+1;s.layoutX=x;s.layoutY=y;s.layoutWidth=w;s.layoutHeight=height
            UI:Place(s.card,self,x,y);D.Size(s.card,w,height)
            if wide then y=y+height+C.GAP
            elseif pending then y=y+math.max(pendingHeight,height)+C.GAP;pending=false;pendingHeight=0
            else pending=true;pendingHeight=height end
        end
        flush();local height=math.max(1,y>0 and y-C.GAP or 0)
        D.Height(self,height);return height
    end

    function grid:Arrange(width)
        if self.interfaceCards then return self:ArrangeCards(width)end
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

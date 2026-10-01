-- Compact settings layout shared by every settings page (0.8.71, density pass).
-- Rows are "label left, control right", 32 design units high, in two columns
-- once the page is wide enough. Sections are a small heading and a rule instead
-- of cards. Explanations live in tooltips, not in extra lines.
local _,ns=...
local UI,Theme=ns.UI,ns.Theme
local D=ns.DesignSystem.Metrics
local G={ROW=32,HEADING=30,GAP=10,COLUMN_GAP=28,TWO_COLUMNS=620,CONTROL=26,TOOLTIP_DELAY=.5}
UI.SettingsMetrics=G

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
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel",function(_,delta)
        slider:SetValue(math.max(low,math.min(high,slider:GetValue()+delta*step)));commit()
    end)
    function host:SetValue(value) slider:SetValue(value);show(value) end
    function host:Enable() slider:Enable() end
    function host:Disable() slider:Disable() end
    function host:Resize(w) D.Width(self,w);D.Width(slider,w-46) end
    return host
end

function UI:SettingsGrid(parent)
    local grid=CreateFrame("Frame",nil,parent);D.Size(grid,880,1)
    grid.items={};grid.hiddenSections={}
    local section
    -- id: filter key for page tabs; title: small heading.
    function grid:Section(id,title)
        section={id=id,kind="section",
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
            height=opts.height or G.ROW,help=opts.help,fixedHeight=opts.fixedHeight}
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

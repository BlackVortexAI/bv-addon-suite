-- Options page for a NativeButtons bar (bag bar, micro menu) on the compact
-- SettingsGrid. Packages add their own sections and rows through extra(page).
local _,ns=...
local UI,N,D=ns.UI,ns.NativeButtons,ns.DesignSystem.Metrics
function UI:NativeBarPage(parent,bar,extra)
    local def=bar.def
    local page=UI:Panel(parent,880,600,"surface");UI:HideSurface(page)
    local grid=UI:SettingsGrid(page);page.grid=grid
    local function changed() bar:Changed() end
    local function cfg() return bar:Config() end
    -- Package-facing helpers: note becomes the tooltip.
    function page:Section(id,title) return grid:Section(id,title) end
    function page:Row(title,control,note,opts)
        opts=opts or {};opts.help=opts.help or note
        return grid:Row(title,control,opts)
    end
    page:Section("module","Module")
    page.enabled=page:Row("Enabled",UI:Switch(grid,false,function(value)
        ns.Modules:SetEnabled(def.id,value);ns.Layout:Refresh(true);if ns.Config then ns.Config:Refresh() end
    end),"Takes over the Blizzard buttons. Turning it off gives them back.")
    page.editor=page:Row("Position & size",UI:Button(grid,"Open Layout Editor",170,function() ns.LayoutEditor:Open(def.layout) end),
        "Drag to move; in the editor the width sets the button size.")
    page:Section("look","Look")
    page.skin=page:Row("Skin",UI:Dropdown(grid,170,N.SkinChoices(),function(value) cfg().skin=value;changed() end),
        "Frame style of the buttons, shared with the suite's icon skins.")
    page.shape=page:Row("Shape",UI:Dropdown(grid,170,N.ShapeChoices("none"),function(value) cfg().shape=value;changed() end),
        "Available shapes depend on the skin.")
    page.shape:SetOptionsProvider(function() return N.ShapeChoices(cfg().skin) end)
    page.size=page:Row("Button size",UI:InlineSlider(grid,190,16,64,1,"%d px",function(value) cfg().size=value;changed() end),
        "Width and height of each button. In the Layout Editor, dragging the width changes it too.")
    page.background=page:Row("Background",UI:Switch(grid,true,function(value) cfg().background=value;changed() end),
        "Dark plate behind each button. With Blizzard pictures: Blizzard's button background.")
    page.border=page:Row("Border",UI:Switch(grid,true,function(value) cfg().border=value;changed() end),
        "Skin frame around each button. Hover and pressed highlights stay.")
    page.barBackground=page:Row("Bar background",UI:Switch(grid,false,function(value) cfg().barBackground=value;changed() end),
        "Solid background behind the whole bar, instead of Blizzard's bar art.")
    page.barColor=page:Row("Bar background color",UI:ColorInput(grid,150,function(value) cfg().barColor=value;changed() end),
        "Color and opacity of the bar background.",{width=150})
    page.blizzardFrame=page:Row("Show Blizzard bar frame",UI:Switch(grid,false,function(value) cfg().blizzardFrame=value;changed() end),
        "Blizzard's frame and dividers of the original bar. Hidden while this module runs unless switched on.")
    page.spacing=page:Row("Spacing",UI:InlineSlider(grid,190,0,12,1,"%d px",function(value) cfg().spacing=value;changed() end),
        "Gap between the buttons.")
    page:Section("arrange","Arrangement")
    page.perLine=page:Row("Buttons per row",UI:InlineSlider(grid,190,1,24,1,"%d",function(value) cfg().perLine=value;changed() end),
        "In vertical mode: buttons per column.")
    page.vertical=page:Row("Vertical",UI:Switch(grid,false,function(value) cfg().vertical=value;changed() end),
        "Arranges the buttons in columns instead of rows.")
    page.fade=page:Row("Show on mouseover",UI:Switch(grid,false,function(value) cfg().fade=value;changed() end),
        "Fades the bar until the mouse is over it.")
    page.fadeAlpha=page:Row("Faded opacity",UI:InlineSlider(grid,190,0,1,.05,"%.2f",function(value) cfg().fadeAlpha=value;changed() end),
        "Opacity of the bar while the mouse is elsewhere (with \"Show on mouseover\"). 0 hides it completely.")
    if extra then extra(page,cfg,changed) end
    function page:Arrange(width)
        UI:Place(grid,self,0,0)
        local height=grid:Arrange(width)+8
        D.Height(self,height);return height
    end
    function page:Refresh()
        local c=cfg()
        self.enabled:SetValue(ns.Settings:Module(def.id).enabled==true)
        self.skin:SetValue(c.skin);self.shape:SetValue(c.shape)
        self.size:SetValue(c.size);self.spacing:SetValue(c.spacing);self.perLine:SetValue(c.perLine)
        self.vertical:SetValue(c.vertical);self.fade:SetValue(c.fade);self.fadeAlpha:SetValue(c.fadeAlpha)
        self.background:SetValue(c.background);self.border:SetValue(c.border);self.blizzardFrame:SetValue(c.blizzardFrame)
        self.barBackground:SetValue(c.barBackground);self.barColor:SetValue(c.barColor)
        if self.RefreshExtra then self:RefreshExtra(c) end
    end
    page:Arrange(880);page:Refresh()
    return page
end

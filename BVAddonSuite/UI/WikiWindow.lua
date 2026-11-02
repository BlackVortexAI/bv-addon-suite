-- BV wiki window (in-game round 4): the standard movable/resizable window
-- with navigation on the left (search + page list) and the page on the right
-- (Markdown with tables). Content comes from a provider:
-- {entries()->{{group=true,title}|{id,title}}, page(id,node)->markdown, limit}.
local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
local NAV=290
function UI:WikiWindow(provider,options)
    local style=options and options.style or UI:GetStyle()
    return UI:WithStyle(style,function()
    local w=UI:Window("BVAddonSuiteWiki",1000,700,{title="Wiki",minWidth=720,minHeight=480})
    local body=w.content
    if style.materialProfile=="interface" then
        -- Only this reader's content is opaque. Preserve the shared titlebar,
        -- theme/HUD opacity and material silhouette at the lower corners.
        local reading=CreateFrame("Frame",nil,body);w.readingSurface=reading
        reading:SetFrameLevel(body:GetFrameLevel());reading:EnableMouse(false)
        D.Point(reading,"TOPLEFT",body,"TOPLEFT",1,0);D.Point(reading,"BOTTOMRIGHT",body,"BOTTOMRIGHT",-1,1)
        style:Skin(reading,"bg",4,1);reading.surfacePaintOwned=true
        local function paintReading()
            local c=style.interfaceColors.bg
            reading:PaintSurface({c[1],c[2],c[3],1},{0,0,0,0},1)
            for _,edge in ipairs(reading.borders) do edge:Hide() end
        end
        style:Bind(paintReading,reading);reading:HookScript("OnSizeChanged",paintReading)
        -- Only the Wiki title reading strip is opaque; shared shell/HUD opacity stays unchanged.
        local titlebar=CreateFrame("Frame",nil,w);w.titleReadingSurface=titlebar
        titlebar:SetFrameLevel(w:GetFrameLevel());titlebar:EnableMouse(false)
        local inset=ns.ShellMetrics.IsWoW(style.interfaceThemeKey) and 6 or 1
        D.Point(titlebar,"TOPLEFT",w.chrome.titlebar,"TOPLEFT",inset,-inset)
        D.Point(titlebar,"BOTTOMRIGHT",w.chrome.titlebar,"BOTTOMRIGHT",-inset,0)
        style:Skin(titlebar,"bg",4,1);titlebar.surfacePaintOwned=true
        local function paintTitle()
            local c=style.interfaceColors.bg
            titlebar:PaintSurface({c[1],c[2],c[3],1},{0,0,0,0},1)
            for _,edge in ipairs(titlebar.borders) do edge:Hide() end
        end
        style:Bind(paintTitle,titlebar);titlebar:HookScript("OnSizeChanged",paintTitle)
        UI:ScopeDialogEscape(w)
    end
    w.provider=provider;w.bvStyle=style
    w.search=UI:Input(body,NAV-24);UI:Place(w.search,body,12,10);w.search:SetMaxLetters(60)
    if w.escapeController then w:TrackEscapeInput(w.search) end
    UI:AttachTooltip(w.search,"Search","Filter pages by title.")
    w.searchHint=UI:Label(w.search,"Search pages…",11,"muted");w.searchHint:SetWordWrap(false)
    D.Point(w.searchHint,"LEFT",10,0);D.Point(w.searchHint,"RIGHT",-10,0)
    local function searchHint() w.searchHint:SetShown(w.search:GetText()=="" and not w.search:HasFocus()) end
    w.search:HookScript("OnEditFocusGained",searchHint);w.search:HookScript("OnEditFocusLost",searchHint)
    searchHint()
    w.nav=UI:Form(body,NAV,500,body);UI:Place(w.nav,body,12,50);w.nav:SetClipsChildren(true)
    w.page=UI:Form(body,600,500,body);UI:Place(w.page,body,NAV+24,10);w.page:SetClipsChildren(true)
    -- Roomier text than canvas notes (in-game finding 40).
    w.view=UI:MarkdownView(w.page.content,560,{body=13,spacing=4,gap=10,rowPad=7});UI:Place(w.view,w.page.content,0,0)
    -- Node pages: open the detailed per-output reference tables.
    w.reference=UI:Button(body,"Detailed reference...",240,function()
        if w.provider.reference and w.current then w.referenceDialog=UI:WithStyle(style,w.provider.reference,w,w.current,w.node) end
    end,"ghost")
    UI:AttachTooltip(w.reference,"Detailed reference","Per-output tables: availability in and out of combat, secret behaviour.")
    w.rows={}
    local function row(i)
        local r=w.rows[i];if r then return r end
        r=UI:WithStyle(style,function() return UI:Button(w.nav.content,"",NAV-24,function(self) if self.entryId then w:Open(self.entryId) end end,"nav") end)
        r:SetLabelInsets(10,6,"LEFT")
        r.header=style:Label(w.nav.content,"",11,"accent","bold");r:Hide();r.header:Hide()
        w.rows[i]=r;return r
    end
    function w:Layout()
        if self.minimized then return end
        local width,height=ns.ShellMetrics.ContentSize(D.GetWidth(self),D.GetHeight(self),self.shellMetrics)
        -- Form sizes exclude their scroll bar (drawn 6 + 12 units to the right).
        local navH=math.max(100,height-60);D.Size(self.nav,NAV-22,navH);D.Height(self.nav.slider,navH)
        -- Page form incl. its scroll bar ends 14 units inside the window edge.
        local pageWidth=math.max(300,width-NAV-60)
        local isNode=self.current and self.current:match("^node:")~=nil and self.provider.reference~=nil
        self.reference:SetShown(isNode)
        self.reference:ClearAllPoints();D.Point(self.reference,"TOPRIGHT",self.content,"TOPRIGHT",-16,-10)
        local pageH=math.max(100,height-(isNode and 60 or 20));D.Size(self.page,pageWidth,pageH);D.Height(self.page.slider,pageH)
        UI:Place(self.page,self.content,NAV+24,isNode and 50 or 10)
        D.Width(self.view,pageWidth-20);self.view.width=pageWidth-20
        if self.current then self:Render() end
    end
    function w:RefreshNav()
        local query=(self.search:GetText() or ""):lower()
        local y,i=0,0
        for _,r in ipairs(self.rows) do r:Hide();r.header:Hide() end
        for _,e in ipairs(self.provider.entries()) do
            if e.group then
                if query=="" then
                    i=i+1;local r=row(i);r:Hide();r.entryId=nil;r.header:SetText(e.title:upper());UI:Place(r.header,self.nav.content,6,y+8);r.header:Show();y=y+28
                end
            elseif query=="" or e.title:lower():find(query,1,true) then
                i=i+1;local r=row(i);r.entryId=e.id;r:SetLabelText(e.title);r:SetSelected(e.id==self.current)
                UI:Place(r,self.nav.content,0,y);r:Show();y=y+32
            end
        end
        self.nav:SetContentHeight(math.max(1,y))
    end
    function w:Render()
        local ok,text=pcall(self.provider.page,self.current,self.node)
        if not ok then text="# Page unavailable\n\n"..tostring(text) end
        local h=self.view:SetMarkdown(text,self.provider.limit or 60000)
        self.page:SetContentHeight(math.max(1,h+20));self.page.slider:SetValue(0)
    end
    -- id: "page:<name>" or "node:<type>"; node: optional graph node for its settings.
    function w:Open(id,node)
        self.current=id;self.node=node
        if style.materialProfile=="interface" and not self.minimized and not self.maximized then UI:FitWindow(self,D.GetWidth(self),D.GetHeight(self),ns.Settings:Get("scale")) end
        self:Show();self:Layout();self:RefreshNav();self:Render()
        UI:FocusWindow(self)
        return self
    end
    w.search:SetScript("OnTextChanged",function() searchHint();w:RefreshNav() end)
    w:HookScript("OnSizeChanged",function() if w:IsShown() then w:Layout() end end)
    if style.materialProfile=="interface" then
        style:Bind(function()
            if w:IsShown() and not w.minimized then
                local nav,page=w.nav.slider:GetValue(),w.page.slider:GetValue()
                w:Layout();w:RefreshNav();w.nav.slider:SetValue(math.min(nav,w.nav.maximum or 0));w.page.slider:SetValue(math.min(page,w.page.maximum or 0))
            end
        end,w)
    end
    return w
    end)
end

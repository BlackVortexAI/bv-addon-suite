-- BV wiki window (in-game round 4): the standard movable/resizable window
-- with navigation on the left (search + page list) and the page on the right
-- (Markdown with tables). Content comes from a provider:
-- {entries()->{{group=true,title}|{id,title}}, page(id,node)->markdown, limit}.
local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
local NAV=290
function UI:WikiWindow(provider)
    local w=UI:Window("BVAddonSuiteWiki",1000,700,{title="Wiki",minWidth=720,minHeight=480})
    local body=w.content
    w.provider=provider
    w.search=UI:Input(body,NAV-24);UI:Place(w.search,body,12,10);w.search:SetMaxLetters(60)
    UI:AttachTooltip(w.search,"Search","Filter pages by title.")
    w.nav=UI:Form(body,NAV,500,body);UI:Place(w.nav,body,12,50);w.nav:SetClipsChildren(true)
    w.page=UI:Form(body,600,500,body);UI:Place(w.page,body,NAV+24,10);w.page:SetClipsChildren(true)
    -- Roomier text than canvas notes (in-game finding 40).
    w.view=UI:MarkdownView(w.page.content,560,{body=13,spacing=4,gap=10,rowPad=7});UI:Place(w.view,w.page.content,0,0)
    -- Node pages: open the detailed per-output reference tables.
    w.reference=UI:Button(body,"Detailed reference...",240,function()
        if w.provider.reference and w.current then w.referenceDialog=w.provider.reference(w,w.current,w.node) end
    end,"ghost")
    UI:AttachTooltip(w.reference,"Detailed reference","Per-output tables: availability in and out of combat, secret behaviour.")
    w.rows={}
    local function row(i)
        local r=w.rows[i];if r then return r end
        r=UI:Button(w.nav.content,"",NAV-24,function(self) if self.entryId then w:Open(self.entryId) end end,"nav")
        r:SetLabelInsets(10,6,"LEFT")
        r.header=UI:Label(w.nav.content,"",11,"accent",true);r:Hide();r.header:Hide()
        w.rows[i]=r;return r
    end
    function w:Layout()
        local width,height=D.GetWidth(self),D.GetHeight(self)-44
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
        self:Show();self:Layout();self:RefreshNav();self:Render()
        UI:FocusWindow(self)
        return self
    end
    w.search:SetScript("OnTextChanged",function() w:RefreshNav() end)
    w:HookScript("OnSizeChanged",function() if w:IsShown() then w:Layout() end end)
    return w
end

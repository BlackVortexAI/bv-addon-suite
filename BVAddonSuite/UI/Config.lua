local _,ns=...
local UI,Settings=ns.UI,ns.Settings
local D=ns.DesignSystem.Metrics
local Config={page="appearance",modulePages={},moduleOrder={}}
ns.Config=Config
local function at(w,p,x,y) return UI:Place(w,p,x,y) end
local NAV,HEADING=30,22
-- Sidebar categories (0.8.75): collapsible groups. Modules pick one with
-- definition.category (id) and categoryLabel; default is UI Enhancements.
local categoryOrder={"design","core","enhancements"}
local categoryLabels={design="Design & Layout",core="Core Services",enhancements="UI Enhancements"}
local pageCategory={layout="design",appearance="core",profiles="core",core="core"}
local titles={appearance="Global Settings",profiles="Profiles",core="Core Status"}
local icons={appearance="spark",profiles="grid",core="info",aurastudio="tree",experience="plus",reputation="check",bags="folder",micromenu="grid",loot="spark"}
local descriptions={appearance="Shared typography, surfaces and preferences for every BV module.",profiles="Independent configurations for your characters and activities.",core="Client and module diagnostics, captured on demand."}
function Config:RegisterPage(id,definition)
    assert(not titles[id],"Duplicate configuration page")
    self.modulePages[id]=definition; self.moduleOrder[#self.moduleOrder+1]=id
    titles[id],descriptions[id]=definition.title,definition.description
    local category=type(definition.category)=="string" and definition.category:match("^[a-z][a-z0-9_]*$") and definition.category or "enhancements"
    if not categoryLabels[category] then
        categoryLabels[category]=type(definition.categoryLabel)=="string" and definition.categoryLabel or category
        categoryOrder[#categoryOrder+1]=category
    end
    pageCategory[id]=category
    if self.window then self:ModuleNavigation(); self:Layout() end
end
function Config:ModuleNavigation()
    for _,id in ipairs(self.moduleOrder) do
        local key=id
        if not self.nav[id] then self.nav[id]=self.navButton(titles[id],function() self:SelectPage(key) end,icons[id] or "grid",0) end
    end
    for _,category in ipairs(categoryOrder) do self:CategoryHeading(category) end
end
function Config:CategoryOf(id) return pageCategory[id] or "enhancements" end
-- Collapsed categories are remembered per profile.
function Config:CollapsedCategories()
    local profile=Settings:Profile()
    if type(profile.configNav)~="table" then profile.configNav={} end
    if type(profile.configNav.collapsed)~="table" then profile.configNav.collapsed={} end
    return profile.configNav.collapsed
end
function Config:ToggleCategory(category)
    local collapsed=self:CollapsedCategories()
    collapsed[category]=not collapsed[category] or nil
    self:Layout()
end
function Config:CategoryHeading(category)
    self.categoryHeadings=self.categoryHeadings or {}
    if self.categoryHeadings[category] then return self.categoryHeadings[category] end
    local h=CreateFrame("Button",nil,self.navContent); D.Size(h,160,HEADING-2)
    h.label=UI:Label(h,string.upper(categoryLabels[category]),10,"muted"); D.Point(h.label,"LEFT",22,0); D.Size(h.label,130,14)
    h.label:SetWordWrap(false)
    h.open=UI:Icon(h,"chevron",12,"muted"); D.Point(h.open,"LEFT",6,0)
    h.closed=UI:Icon(h,"right",12,"muted"); D.Point(h.closed,"LEFT",6,0)
    h:SetScript("OnClick",function() self:ToggleCategory(category) end)
    h:SetScript("OnEnter",function() h.label:SetTextColor(ns.Theme:Color("text")) end)
    h:SetScript("OnLeave",function() h.label:SetTextColor(ns.Theme:Color("muted")) end)
    UI:AttachTooltip(h,categoryLabels[category],"Click to expand or collapse this category.")
    self.categoryHeadings[category]=h; self.navHeadings[#self.navHeadings+1]=h.label
    return h
end
-- Lays out headings and page buttons top to bottom; returns the content height.
function Config:ArrangeNavigation(side,compact)
    local collapsed=self:CollapsedCategories()
    local y=0
    self.emptyModules:Hide()
    local buttons={layout=self.layoutButton}
    for id,button in pairs(self.nav) do buttons[id]=button end
    for _,category in ipairs(categoryOrder) do
        local items={}
        if category=="design" then items[1]="layout" end
        if category=="core" then items={"appearance","profiles","core"} end
        for _,id in ipairs(self.moduleOrder) do if pageCategory[id]==category then items[#items+1]=id end end
        local heading=self:CategoryHeading(category)
        local empty=category=="enhancements" and #items==0
        local visible=#items>0 or empty
        heading:SetShown(visible and not compact)
        local open=compact or not collapsed[category]
        if visible and not compact then
            at(heading,self.navContent,0,y); D.Width(heading,side-16)
            heading.open:SetShown(open); heading.closed:SetShown(not open)
            y=y+HEADING
        end
        for _,id in ipairs(items) do
            local button=buttons[id]
            if button then
                button:SetShown(open)
                if open then at(button,self.navContent,0,y); y=y+NAV end
            end
        end
        if empty then
            self.emptyModules:SetShown(open and not compact)
            if open and not compact then at(self.emptyModules,self.navContent,8,y+4); y=y+24 end
        end
        if visible then y=y+8 end
    end
    return y
end
function Config:OpenPage(id)
    if ns.LayoutEditor.active then ns:Print("Finish layout editing before opening module settings."); return end
    if InCombatLockdown() then ns:Print("Open configuration after combat."); return end
    self:Build(); self:SelectPage(id); self.window:Show()
end
function Config:SelectPage(id)
    if not titles[id] then ns:Print("This module is not loaded."); return end
    local module=self.modulePages[id]
    if module then self.pages[id]=module.build(self.pageContent) end
    self.page=id; self.pageScroll:SetValue(0); self.heading:SetText(titles[id]); self.description:SetText(descriptions[id])
    local category=self:CategoryOf(id)
    self.category:SetText("CONFIGURATION / "..string.upper(categoryLabels[category]))
    -- Opening a page (also by command) expands its category.
    self:CollapsedCategories()[category]=nil
    for key,page in pairs(self.pages) do page:SetShown(key==id) end
    for key,button in pairs(self.nav) do button:SetSelected(key==id) end
    self:UpdateNavigation(); self:Layout(); self:Refresh()
end
function Config:SelectSection(id)
    local page=self.pages[self.page]; local navigation=page and page.navigation
    if not navigation then return end
    navigation.select(id)
    self.pageScroll:SetValue(0)
    self:UpdateNavigation(); self:Layout()
end
function Config:UpdateNavigation()
    local page=self.pages[self.page]; local navigation=page and page.navigation
    local definitions=navigation and navigation.definitions or {}
    self.tabs:SetDefinitions(definitions); self.tabs:SetValue(navigation and navigation.selected)
    self.tabs:SetShown(#definitions>1)
    self.sectionTree:SetDefinitions(definitions); self.sectionTree:SetValue(navigation and navigation.selected)
end
function Config:Refresh()
    if not self.window then return end
    UI:FitWindow(self.window,1040,680,Settings:Get("scale"))
    for _,key in ipairs({"font","themeKey","scale","statusbar","tooltips"}) do self[key]:SetValue(Settings:Get(key)) end
    self.profile:SetOptions(Settings:ListProfiles()); self.profile:SetValue(Settings.db.activeProfile)
    self.profileLabel:SetText("PROFILE  /  "..Settings.db.activeProfile)
    if self.page=="core" and self.window:IsShown() then self:UpdateDiagnostics() end
    for _,id in ipairs(self.moduleOrder) do self.modulePages[id].refresh() end
    self:UpdateNavigation(); self:Layout()
end
function Config:UpdateDiagnostics()
    local events,subscriptions=ns.Events:Count(); local enabled,failed=0,0
    for _,record in ipairs(ns.Modules.order) do
        if record.state=="enabled" then enabled=enabled+1 end
        if record.state=="faulted" then failed=failed+1 end
    end
    local version,build,_,interface=GetBuildInfo()
    self.diagnostics:SetText(string.format("CLIENT\n%s  /  build %s  /  interface %s\n\nMODULES\n%d registered  /  %d enabled  /  %d faulted\n\nEVENTS\n%d events  /  %d subscriptions\n\nERRORS\n%d retained\n\nCPU and memory profiling are not running.",tostring(version),tostring(build),tostring(interface),#ns.Modules.order,enabled,failed,events,subscriptions,#ns.errors))
end
-- Compact shell (0.8.71): slim header with the tabs right below, 30-unit
-- navigation rows, settings pages on the shared SettingsGrid.
function Config:Layout()
    if not self.grids or self.arranging or self.window.minimized then return end
    self.arranging=true
    local w,h=D.GetWidth(self.window),D.GetHeight(self.window)-44
    local compact=w<860; local side=compact and 52 or 176
    local footer=40
    at(self.sidebar,self.window.content,0,0); D.Size(self.sidebar,side,h-footer)
    self.profileLabel:SetShown(not compact); self.profileRule:SetShown(not compact)
    at(self.navScroll,self.sidebar,8,12); D.Size(self.navScroll,side-16,math.max(80,h-footer-12-54))
    -- Page sections are the tabs; the sidebar only lists pages.
    self.sectionTree:Hide(); self.sectionHeading:Hide()
    local navHeight=self:ArrangeNavigation(side,compact)
    D.Size(self.navContent,side-16,navHeight)
    self.navMax=math.max(0,navHeight-D.GetHeight(self.navScroll)); self.navOffset=math.min(self.navOffset or 0,self.navMax); self.navScroll:SetVerticalScroll(D.ToNative(self.navOffset))
    local buttons={self.layoutButton}; for _,button in pairs(self.nav) do buttons[#buttons+1]=button end
    for _,button in ipairs(buttons) do D.Width(button,side-16); button.label:SetShown(not compact) end
    local inner=w-side-40; local stacked=inner<560; local headerHeight=stacked and 94 or 62
    at(self.header,self.window.content,side,0); D.Size(self.header,w-side,headerHeight)
    local titleWidth=stacked and inner or inner-264
    at(self.heading,self.header,20,10); D.Size(self.heading,titleWidth,26)
    at(self.description,self.header,20,38); D.Size(self.description,titleWidth,16)
    at(self.themeGroup,self.header,stacked and 20 or w-side-20-254,stacked and 62 or 18); D.Size(self.themeGroup,254,26)
    at(self.themeCaption,self.themeGroup,0,5); D.Size(self.themeCaption,80,16)
    at(self.themeKey,self.themeGroup,84,0); D.Size(self.themeKey,170,26)
    at(self.tabs,self.window.content,side+20,headerHeight+6); self.tabs:Arrange(inner)
    local top=headerHeight+(self.tabs:IsShown() and 42 or 12); local viewHeight=math.max(80,h-top-footer-8)
    at(self.viewport,self.window.content,side+20,top); D.Size(self.viewport,inner,viewHeight)
    at(self.pageScroll,self.window.content,w-12,top); D.Size(self.pageScroll,8,viewHeight)
    D.Width(self.pageContent,inner)
    local page=self.pages[self.page]; if not page then self.arranging=false; return end
    at(page,self.pageContent,0,0); D.Width(page,inner)
    local module=self.modulePages[self.page]
    local height
    if module then
        if page.Arrange then height=page:Arrange(inner) or D.GetHeight(page) else height=D.GetHeight(page) end
    else
        local grid=self.grids[self.page]
        local selected=page.navigation.selected
        grid:ShowSections(selected~="overview" and {[selected]=true} or nil)
        at(grid,page,0,0); height=grid:Arrange(inner)+8
    end
    D.Height(page,height); D.Height(self.pageContent,height)
    self.pageMaximum=math.max(0,height-viewHeight); self.pageScroll:SetMinMaxValues(0,self.pageMaximum); self.pageScroll:SetShown(self.pageMaximum>0)
    self.pageScroll:SetValue(math.min(self.pageScroll:GetValue(),self.pageMaximum)); self.footerLabel:SetShown(w>=860)
    self.arranging=false
end
function Config:Build()
    if self.window then return end
    local window=UI:Window("BVAddonSuiteConfig",1040,680,{minWidth=720,minHeight=480}); self.window=window
    window:SetTitle("Addon Suite")
    local body=window.content
    local sidebar=CreateFrame("Frame",nil,body); self.sidebar=sidebar
    local shade=sidebar:CreateTexture(nil,"BACKGROUND"); shade:SetAllPoints(); shade:SetColorTexture(0,0,0,.08)
    self.sideRule=UI:Rule(sidebar,1); D.Point(self.sideRule,"TOPRIGHT"); D.Point(self.sideRule,"BOTTOMRIGHT")
    self.navScroll=CreateFrame("ScrollFrame",nil,sidebar); self.navScroll:SetClipsChildren(true); self.navScroll:EnableMouseWheel(true)
    self.navContent=CreateFrame("Frame",nil,self.navScroll); D.Size(self.navContent,160,420); self.navScroll:SetScrollChild(self.navContent)
    self.navScroll:SetScript("OnMouseWheel",function(_,delta)
        self.navOffset=math.max(0,math.min(self.navMax or 0,(self.navOffset or 0)-delta*NAV)); self.navScroll:SetVerticalScroll(D.ToNative(self.navOffset))
    end)
    self.nav={}; self.navHeadings={}
    local function navButton(text,callback,icon,y)
        local b=at(UI:NavButton(self.navContent,text,160,callback,false,icon),self.navContent,0,y); D.Height(b,NAV-2)
        if b.mark then D.Height(b.mark,NAV-2) end
        return b
    end
    -- Positions come from ArrangeNavigation; headings are created per category.
    self.layoutButton=navButton("Layout Editor",function() ns.LayoutEditor:Open() end,"grid",0)
    local function nav(id) self.nav[id]=navButton(titles[id],function() self:SelectPage(id) end,icons[id],0) end
    nav("appearance"); nav("profiles"); nav("core")
    self.emptyModules=UI:Label(self.navContent,"No feature addons loaded.",11,"muted")
    self.navButton=navButton
    self:ModuleNavigation()
    self.sectionHeading=UI:Label(self.navContent,"PAGE SECTIONS",10,"muted")
    self.sectionTree=UI:TreeMenu(self.navContent,{},function(id) self:SelectSection(id) end)
    self.profileLabel=UI:Label(sidebar,"",11,"muted"); D.Point(self.profileLabel,"BOTTOMLEFT",14,12); D.Size(self.profileLabel,150,28)
    self.profileRule=UI:Rule(sidebar,156); D.Point(self.profileRule,"BOTTOMLEFT",10,46)
    self.header=CreateFrame("Frame",nil,body)
    UI:GetStyle():Gradient(self.header,"HORIZONTAL","accent",.055,"secondary",.035,1)
    -- Kept for callers; the compact header shows only title and description.
    self.category=at(UI:Label(self.header,"",10,"accent"),self.header,20,0); self.category:Hide()
    self.heading=at(UI:Label(self.header,"",20,"text",true),self.header,20,10)
    self.heading:SetWordWrap(false)
    self.description=at(UI:Label(self.header,"",11,"muted"),self.header,20,38)
    self.description:SetWordWrap(false)
    self.headerRule=UI:Rule(self.header,1,"accent"); D.Point(self.headerRule,"BOTTOMLEFT"); D.Point(self.headerRule,"BOTTOMRIGHT")
    self.themeGroup=CreateFrame("Frame",nil,self.header)
    self.themeCaption=UI:Label(self.themeGroup,"Material",11,"muted")
    self.themeKey=UI:AppearanceChoice(self.themeGroup,"themeKey",170)
    self.tabs=UI:Tabs(body,{},function(id) self:SelectSection(id) end); self.tabs.bvHeight=30
    self.viewport=CreateFrame("ScrollFrame",nil,body); self.viewport:SetClipsChildren(true); self.viewport:EnableMouseWheel(true)
    self.pageContent=CreateFrame("Frame",nil,self.viewport); D.Size(self.pageContent,880,600); self.viewport:SetScrollChild(self.pageContent)
    self.pageScroll=UI:GetStyle():Slider(body,8,0,0,1,0,function(value) self.viewport:SetVerticalScroll(D.ToNative(value)) end)
    self.pageScroll:SetOrientation("VERTICAL"); self.pageScroll.track:ClearAllPoints(); D.Point(self.pageScroll.track,"TOP"); D.Point(self.pageScroll.track,"BOTTOM"); D.Width(self.pageScroll.track,3); D.Size(self.pageScroll:GetThumbTexture(),6,36)
    self.viewport:SetScript("OnMouseWheel",function(_,delta) self.pageScroll:SetValue(math.max(0,math.min(self.pageMaximum or 0,self.pageScroll:GetValue()-delta*42))) end)
    self.pages={}; self.grids={}
    for _,id in ipairs({"appearance","profiles","core"}) do
        self.pages[id]=UI:Panel(self.pageContent,880,600,"surface"); UI:HideSurface(self.pages[id])
        self.grids[id]=UI:SettingsGrid(self.pages[id])
    end
    local g=self.grids.appearance
    g:Section("typography","Typography")
    self.font=g:Row("Font family",UI:AppearanceChoice(g,"font",220),{help="Used by every BV window, bar and text element that inherits the suite font."})
    self.typePreview=g:Row("Preview",UI:Label(g,"A clearer view of your adventures.",14,"text",true),{width=240})
    g:Section("materials","Surfaces & accent")
    self.statusbar=g:Row("Statusbar texture",UI:Dropdown(g,220,ns.Media:BarOptions(),function(v) Settings:Set("statusbar",v) end),
        {help="Default texture for BV bars. Change the suite palette with Material in the header."})
    self.statusbar:SetOptionsProvider(function()return ns.Media:BarOptions()end)
    self.barPreview=g:Row("Preview",UI:StatusBar(g,220,10),{width=220})
    g:Section("interaction","Window & interaction")
    self.tooltips=g:Row("Contextual help",UI:Switch(g,true,function(v) Settings:Set("tooltips",v) end),{help="Show tooltips on BV controls."})
    UI:AttachTooltip(self.tooltips,"Control tooltips","Show contextual help for BV controls.")
    self.resetAppearance=g:Row("Reset appearance",UI:Button(g,"Reset",110,function() Settings:ResetAppearance() end),
        {help="Font, material, statusbar texture and window scale back to their defaults."})
    g:Section("minimap","Minimap launcher")
    -- Same controls contract as UI:MinimapOptions, laid out as grid rows.
    local launcher=UI.MinimapLauncher
    local minimap={}
    minimap.show=g:Row("Show minimap button",UI:Switch(g,false,function(value) launcher:SetShown(value) end),
        {help="Show one shared BV launcher. Recover it anytime with /bv minimap show."})
    minimap.lock=g:Row("Lock minimap position",UI:Switch(g,false,function(value) launcher:SetLocked(value) end),
        {help="Prevent dragging the BV launcher around the minimap."})
    minimap.reset=g:Row("Minimap position",UI:Button(g,"Reset",110,function() launcher:ResetPosition() end),
        {help="Restore the default minimap angle without changing visibility or other settings."})
    function minimap:Refresh() local data=launcher:Store(); self.show:SetValue(not data.hide); self.lock:SetValue(data.lock) end
    launcher.controls[minimap]=true; minimap:Refresh(); self.minimapOptions=minimap
    g=self.grids.profiles
    g:Section("active","Active profile")
    self.profile=g:Row("Select profile",UI:Dropdown(g,220,{},function(v) Settings:SelectProfile(v) end),
        {help="Profiles are shared across characters on this account."})
    g:Section("create","Create a profile")
    local function newProfile()
        local ok,name=pcall(Settings.CreateProfile,Settings,self.profileName:GetText())
        if ok then Settings:SelectProfile(name); self.profileName:SetText(""); self.profileMessage:SetText("Profile created.")
        else self.profileMessage:SetText("Use a unique name (1-48 bytes, no control characters or |).") end
    end
    self.profileName=g:Row("Profile name",UI:Input(g,220,newProfile),{help="Starts with a copy of the current configuration and layout."})
    self.createProfile=g:Row(nil,UI:Button(g,"Create & select",150,newProfile,true))
    self.profileMessage=g:Block(UI:Label(g,"",12,"accent"),16)
    g=self.grids.core
    g:Section("overview","Runtime snapshot")
    self.diagnostics=g:Block(UI:Label(g,"",12),200,function(width)
        D.Width(self.diagnostics,width); return math.max(40,D.ToDesign(self.diagnostics:GetStringHeight()))
    end)
    g:Row(nil,UI:Button(g,"Refresh snapshot",150,function() self:UpdateDiagnostics() end))
    self.footer=CreateFrame("Frame",nil,body); D.Point(self.footer,"BOTTOMLEFT"); D.Point(self.footer,"BOTTOMRIGHT"); D.Height(self.footer,40)
    local footerRule=UI:Rule(self.footer,1); D.Point(footerRule,"TOPLEFT"); D.Point(footerRule,"TOPRIGHT")
    self.scale=UI:ScaleSlider(self.footer,230,function(v) Settings:Set("scale",v) end); D.Point(self.scale,"RIGHT",-130,0)
    self.done=UI:Button(self.footer,"Done",100,function() window:Hide() end,true); D.Height(self.done,28); D.Point(self.done,"RIGHT",-14,0)
    self.footerLabel=UI:Label(self.footer,"BV / "..ns.version,11,"muted"); D.Point(self.footerLabel,"LEFT",16,0)
    self.cards={}
    local function navigation(page,definitions)
        page.navigation={definitions=definitions,selected="overview",select=function(id) page.navigation.selected=id end}
    end
    navigation(self.pages.appearance,{{id="overview",label="Overview"},{id="typography",label="Typography"},{id="materials",label="Materials"},{id="interaction",label="Interaction"},{id="minimap",label="Minimap"}})
    navigation(self.pages.profiles,{{id="overview",label="Overview"},{id="active",label="Active profile"},{id="create",label="Create profile"}})
    navigation(self.pages.core,{{id="overview",label="Snapshot"}})
    window:HookScript("OnSizeChanged",function() if self.grids then self:Layout() end end)
    window:HookScript("OnShow",function()
        self:Refresh()
        ns.Events:Subscribe(self,"DISPLAY_SIZE_CHANGED",function() self:Refresh() end)
        ns.Events:Subscribe(self,"UI_SCALE_CHANGED",function() self:Refresh() end)
    end)
    window:HookScript("OnHide",function()
        ns.Events:Release(self); ns.ProgressBars:ClosePreviews(); UI:CloseDropdown()
        if UI.colorPopup then UI.colorPopup:Hide() end
    end)
    self:SelectPage(self.page)
end
function Config:Toggle()
    if not ns.ready then ns:Print("The core could not initialize. Check the error handler."); return end
    if ns.LayoutEditor.active then ns.LayoutEditor:RequestClose(); return end
    if self.window and self.window:IsShown() then self.window:Hide(); return end
    if InCombatLockdown() then ns:Print("Open configuration after combat."); return end
    self:Build(); self.window:Show()
end

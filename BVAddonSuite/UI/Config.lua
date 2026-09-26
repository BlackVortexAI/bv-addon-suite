local _,ns=...
local UI,Settings=ns.UI,ns.Settings
local D=ns.DesignSystem.Metrics
local Config={page="appearance",modulePages={},moduleOrder={}}
ns.Config=Config
local function at(w,p,x,y) return UI:Place(w,p,x,y) end
local titles={appearance="Global Settings",profiles="Profiles",core="Core Status"}
local icons={appearance="spark",profiles="grid",core="info",aurastudio="tree",experience="plus",reputation="check"}
local descriptions={appearance="Shared typography, surfaces and preferences for every BV module.",profiles="Independent configurations for your characters and activities.",core="Client and module diagnostics, captured on demand."}
function Config:RegisterPage(id,definition)
    assert(not titles[id],"Duplicate configuration page")
    self.modulePages[id]=definition; self.moduleOrder[#self.moduleOrder+1]=id
    titles[id],descriptions[id]=definition.title,definition.description
    if self.window then self:ModuleNavigation(); self:Layout() end
end
function Config:ModuleNavigation()
    for index,id in ipairs(self.moduleOrder) do
        local key=id
        if not self.nav[id] then self.nav[id]=at(UI:NavButton(self.navContent,titles[id],180,function() self:SelectPage(key) end,false,icons[id] or "grid"),self.navContent,0,240+(index-1)*38) end
    end
    self.emptyModules:SetShown(#self.moduleOrder==0)
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
    self.category:SetText(module and "CONFIGURATION / UI ENHANCEMENTS" or "CONFIGURATION / CORE")
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
    self.tabs:SetShown(#definitions>0)
    self.sectionTree:SetDefinitions(definitions); self.sectionTree:SetValue(navigation and navigation.selected)
end
function Config:Refresh()
    if not self.window then return end
    UI:FitWindow(self.window,1160,760,Settings:Get("scale"))
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
local function sizeCard(card,width,height)
    UI:ResizeSection(card,width,height)
end
function Config:Layout()
    if not self.cards or self.arranging or self.window.minimized then return end
    self.arranging=true
    local w,h=D.GetWidth(self.window),D.GetHeight(self.window)-44
    local compact=w<860; local side=compact and 58 or 200
    at(self.sidebar,self.window.content,0,0); D.Size(self.sidebar,side,h-48)
    self.profileLabel:SetShown(not compact); self.profileRule:SetShown(not compact); self.emptyModules:SetShown(not compact and #self.moduleOrder==0)
    at(self.navScroll,self.sidebar,10,20); D.Size(self.navScroll,side-20,math.max(80,h-132))
    local count=#self.moduleOrder; local sectionTop=272+count*38
    at(self.sectionHeading,self.navContent,8,sectionTop); at(self.sectionTree,self.navContent,0,sectionTop+25)
    self.sectionTree:Arrange(side-20); self.sectionTree:SetShown(not compact); self.sectionHeading:SetShown(not compact)
    local navHeight=compact and 260+count*38 or sectionTop+35+D.GetHeight(self.sectionTree)
    D.Size(self.navContent,side-20,navHeight)
    self.navMax=math.max(0,navHeight-D.GetHeight(self.navScroll)); self.navOffset=math.min(self.navOffset or 0,self.navMax); self.navScroll:SetVerticalScroll(D.ToNative(self.navOffset))
    for _,label in ipairs(self.navHeadings) do label:SetShown(not compact) end
    local buttons={self.layoutButton}; for _,button in pairs(self.nav) do buttons[#buttons+1]=button end
    for index,button in ipairs(buttons) do
        D.Width(button,side-20); button.label:SetShown(not compact)
    end
    local inner=w-side-48; local stacked=inner<680; local headerHeight=stacked and 154 or 116
    at(self.header,self.window.content,side,0); D.Size(self.header,w-side,headerHeight)
    local titleWidth=stacked and inner or inner-194
    D.Size(self.category,titleWidth,16); D.Size(self.heading,titleWidth,34); D.Size(self.description,inner,30)
    at(self.themeGroup,self.header,stacked and 24 or w-side-194,stacked and 110 or 22)
    D.Size(self.themeGroup,stacked and inner or 170,stacked and 32 or 58)
    at(self.themeCaption,self.themeGroup,0,stacked and 8 or 0); D.Size(self.themeCaption,stacked and 138 or 170,18)
    at(self.themeKey,self.themeGroup,stacked and 144 or 0,stacked and 0 or 22); D.Width(self.themeKey,170)
    local module=self.modulePages[self.page]
    at(self.tabs,self.window.content,side+24,headerHeight); self.tabs:Arrange(inner)
    local top=headerHeight+54; local viewHeight=math.max(80,h-top-64)
    at(self.viewport,self.window.content,side+24,top); D.Size(self.viewport,inner,viewHeight)
    at(self.pageScroll,self.window.content,w-14,top); D.Size(self.pageScroll,8,viewHeight)
    D.Width(self.pageContent,inner)
    local page=self.pages[self.page]; if not page then self.arranging=false; return end
    at(page,self.pageContent,0,0); D.Width(page,inner)
    local height=448
    if module then
        if page.Arrange then height=page:Arrange(inner) or D.GetHeight(page) else height=D.GetHeight(page) end
    elseif self.page=="appearance" then
        local current=page.navigation.selected
        local overview=current=="overview"
        local two=overview and inner>=800; local column=two and (inner-20)/2 or inner
        local a,b,c,d=self.cards.typeCard,self.cards.surf,self.cards.prefs,self.cards.minimap
        a:SetShown(overview or current=="typography"); b:SetShown(overview or current=="materials"); c:SetShown(overview or current=="interaction")
        d:SetShown(overview or current=="minimap")
        at(a,page,0,0); sizeCard(a,column,225)
        at(b,page,two and column+20 or 0,two and 0 or overview and 245 or 0); sizeCard(b,column,225)
        local y=overview and (two and 245 or 490) or 0; at(c,page,0,y); sizeCard(c,inner,inner>=800 and 157 or 207)
        D.Size(self.typePreview,column-32,28); D.Size(self.typeHint,column-32,32); D.Width(self.barPreview,column-32); D.Size(self.materialHint,column-32,44)
        local helpX=inner>=800 and 252 or math.floor(inner/2)
        at(self.helpTitle,c,helpX,64); at(self.helpHint,c,helpX,91)
        D.Size(self.helpTitle,inner-helpX-68,24); D.Size(self.helpHint,inner-helpX-32,36)
        at(self.tooltips,c,inner>=800 and 502 or inner-52,65)
        at(self.resetAppearance,c,inner>=800 and inner-180 or 16,inner>=800 and 77 or 145)
        local minimapY=overview and y+D.GetHeight(c)+20 or 0
        at(d,page,0,minimapY); sizeCard(d,inner,184); self.minimapOptions:Arrange(inner-32)
        height=overview and minimapY+202 or current=="minimap" and 202 or current=="interaction" and D.GetHeight(c)+18 or 243
    elseif self.page=="profiles" then
        local overview=page.navigation.selected=="overview"
        self.cards.profileCard:SetShown(overview or page.navigation.selected=="active")
        self.cards.create:SetShown(overview or page.navigation.selected=="create")
        at(self.cards.profileCard,page,0,0); sizeCard(self.cards.profileCard,inner,175)
        local narrow=inner<660
        at(self.cards.create,page,0,overview and 195 or 0); sizeCard(self.cards.create,inner,narrow and 247 or 205)
        at(self.createProfile,self.cards.create,narrow and 16 or 466,narrow and 158 or 112)
        at(self.profileMessage,self.cards.create,16,narrow and 205 or 166); D.Size(self.profileMessage,inner-32,30)
        D.Size(self.profileHint,inner-32,30); D.Size(self.createHint,inner-32,30)
        height=overview and (narrow and 460 or 416) or page.navigation.selected=="active" and 193 or (narrow and 265 or 223)
    else sizeCard(self.cards.coreCard,inner,440); D.Width(self.diagnostics,inner-32); height=458 end
    -- Fixed-width legacy labels are bounded to the available page; interactive
    -- fields adapt via their common field contract below.
    for _,card in pairs(self.cards) do
        if card:GetParent()==page then
            for _,field in ipairs(card.fields or {}) do
                local available=math.max(40,D.GetWidth(card)-field.x-16)
                D.Width(field.control,math.min(field.width,available)); D.Width(field.label,math.min(field.width,available))
            end
        end
    end
    D.Height(page,height); D.Height(self.pageContent,height)
    self.pageMaximum=math.max(0,height-viewHeight); self.pageScroll:SetMinMaxValues(0,self.pageMaximum); self.pageScroll:SetShown(self.pageMaximum>0)
    self.pageScroll:SetValue(math.min(self.pageScroll:GetValue(),self.pageMaximum)); self.footerLabel:SetShown(w>=860)
    self.arranging=false
end
function Config:Build()
    if self.window then return end
    local window=UI:Window("BVAddonSuiteConfig",1160,760,{minWidth=720,minHeight=480}); self.window=window
    window:SetTitle("Addon Suite")
    local body=window.content
    local sidebar=CreateFrame("Frame",nil,body); self.sidebar=sidebar
    local shade=sidebar:CreateTexture(nil,"BACKGROUND"); shade:SetAllPoints(); shade:SetColorTexture(0,0,0,.08)
    self.sideRule=UI:Rule(sidebar,1); D.Point(self.sideRule,"TOPRIGHT"); D.Point(self.sideRule,"BOTTOMRIGHT")
    self.navScroll=CreateFrame("ScrollFrame",nil,sidebar); self.navScroll:SetClipsChildren(true); self.navScroll:EnableMouseWheel(true)
    self.navContent=CreateFrame("Frame",nil,self.navScroll); D.Size(self.navContent,180,420); self.navScroll:SetScrollChild(self.navContent)
    self.navScroll:SetScript("OnMouseWheel",function(_,delta)
        self.navOffset=math.max(0,math.min(self.navMax or 0,(self.navOffset or 0)-delta*36)); self.navScroll:SetVerticalScroll(D.ToNative(self.navOffset))
    end)
    self.nav={}; self.navHeadings={}
    self.navHeadings[1]=at(UI:Label(self.navContent,"DESIGN & LAYOUT",10,"muted"),self.navContent,8,0)
    self.layoutButton=at(UI:NavButton(self.navContent,"Layout Editor",180,function() ns.LayoutEditor:Open() end,false,"grid"),self.navContent,0,22)
    self.navHeadings[2]=at(UI:Label(self.navContent,"CORE SERVICES",10,"muted"),self.navContent,8,74)
    local function nav(id,y) self.nav[id]=at(UI:NavButton(self.navContent,titles[id],180,function() self:SelectPage(id) end,false,icons[id]),self.navContent,0,y) end
    nav("appearance",96); nav("profiles",134); nav("core",172)
    self.navHeadings[3]=at(UI:Label(self.navContent,"UI ENHANCEMENTS",10,"muted"),self.navContent,8,216)
    self.emptyModules=at(UI:Label(self.navContent,"No feature addons loaded.",11,"muted"),self.navContent,8,244)
    self:ModuleNavigation()
    self.sectionHeading=UI:Label(self.navContent,"PAGE SECTIONS",10,"muted")
    self.sectionTree=UI:TreeMenu(self.navContent,{},function(id) self:SelectSection(id) end)
    self.profileLabel=UI:Label(sidebar,"",11,"muted"); D.Point(self.profileLabel,"BOTTOMLEFT",18,16); D.Size(self.profileLabel,170,30)
    self.profileRule=UI:Rule(sidebar,180); D.Point(self.profileRule,"BOTTOMLEFT",10,56)
    self.header=CreateFrame("Frame",nil,body)
    UI:GetStyle():Gradient(self.header,"HORIZONTAL","accent",.055,"secondary",.035,1)
    self.category=at(UI:Label(self.header,"",10,"accent"),self.header,24,16)
    self.heading=at(UI:Label(self.header,"",26,"text",true),self.header,24,38)
    self.description=at(UI:Label(self.header,"",13,"muted"),self.header,24,76)
    self.headerRule=UI:Rule(self.header,1,"accent"); D.Point(self.headerRule,"BOTTOMLEFT"); D.Point(self.headerRule,"BOTTOMRIGHT")
    self.themeGroup=CreateFrame("Frame",nil,self.header)
    self.themeCaption=UI:Label(self.themeGroup,"Material & color",12,"muted")
    self.themeKey=UI:AppearanceChoice(self.themeGroup,"themeKey",170)
    self.tabs=UI:Tabs(body,{},function(id) self:SelectSection(id) end)
    self.viewport=CreateFrame("ScrollFrame",nil,body); self.viewport:SetClipsChildren(true); self.viewport:EnableMouseWheel(true)
    self.pageContent=CreateFrame("Frame",nil,self.viewport); D.Size(self.pageContent,880,600); self.viewport:SetScrollChild(self.pageContent)
    self.pageScroll=UI:GetStyle():Slider(body,8,0,0,1,0,function(value) self.viewport:SetVerticalScroll(D.ToNative(value)) end)
    self.pageScroll:SetOrientation("VERTICAL"); self.pageScroll.track:ClearAllPoints(); D.Point(self.pageScroll.track,"TOP"); D.Point(self.pageScroll.track,"BOTTOM"); D.Width(self.pageScroll.track,3); D.Size(self.pageScroll:GetThumbTexture(),6,36)
    self.viewport:SetScript("OnMouseWheel",function(_,delta) self.pageScroll:SetValue(math.max(0,math.min(self.pageMaximum or 0,self.pageScroll:GetValue()-delta*42))) end)
    self.pages={}
    for _,id in ipairs({"appearance","profiles","core"}) do
        self.pages[id]=UI:Panel(self.pageContent,880,600,"surface"); UI:HideSurface(self.pages[id])
    end
    local appearance=self.pages.appearance
    local typeCard=at(UI:Section(appearance,"Typography",430,225,"info"),appearance,0,0)
    self.font=UI:Field(typeCard,"Font family",UI:AppearanceChoice(typeCard,"font",398),16,58)
    self.typePreview=at(UI:Label(typeCard,"A clearer view of your adventures.",19,"text",true),typeCard,16,133)
    self.typeHint=at(UI:Label(typeCard,"Regular for values. Bold for hierarchy.",12,"muted"),typeCard,16,166)
    local surf=at(UI:Section(appearance,"Surfaces & accent",430,225,"spark"),appearance,450,0)
    self.statusbar=UI:Field(surf,"Statusbar texture",UI:Dropdown(surf,398,ns.Media:BarOptions(),function(v) Settings:Set("statusbar",v) end),16,58)
    self.statusbar:SetOptionsProvider(function()return ns.Media:BarOptions()end)
    self.barPreview=at(UI:StatusBar(surf,398,12),surf,16,126)
    self.materialHint=at(UI:Label(surf,"Change the suite palette using Material & color in the header.",12,"muted"),surf,16,156)
    local prefs=at(UI:Section(appearance,"Window & interaction",880,157,"grid"),appearance,0,245)
    at(UI:Label(prefs,"Window scale",13,"text",true),prefs,16,64)
    local scaleHint=at(UI:Label(prefs,"Adjust using the footer slider.",12,"muted"),prefs,16,91); D.Size(scaleHint,220,36)
    self.helpTitle=at(UI:Label(prefs,"Contextual help",13,"text",true),prefs,252,64)
    self.helpHint=at(UI:Label(prefs,"Show tooltips on BV controls.",12,"muted"),prefs,252,91)
    self.tooltips=at(UI:Switch(prefs,true,function(v) Settings:Set("tooltips",v) end),prefs,502,65)
    UI:AttachTooltip(self.tooltips,"Control tooltips","Show contextual help for BV controls.")
    self.resetAppearance=at(UI:Button(prefs,"Reset appearance",164,function() Settings:ResetAppearance() end),prefs,698,77)
    local minimap=at(UI:Section(appearance,"Minimap launcher",880,184,"spark"),appearance,0,420)
    self.minimapOptions=at(UI:MinimapOptions(minimap,848),minimap,16,58)
    local profiles=self.pages.profiles
    local profileCard=at(UI:Section(profiles,"Active profile",880,175,"check"),profiles,0,0)
    self.profile=UI:Field(profileCard,"Select profile",UI:Dropdown(profileCard,430,{},function(v) Settings:SelectProfile(v) end),16,59)
    self.profileHint=at(UI:Label(profileCard,"Profiles are shared across characters on this account.",12,"muted"),profileCard,16,132)
    local create=at(UI:Section(profiles,"Create a profile",880,205,"plus"),profiles,0,195)
    self.createHint=at(UI:Label(create,"Start with a copy of the current configuration and layout.",12,"muted"),create,16,58)
    local function newProfile()
        local ok,name=pcall(Settings.CreateProfile,Settings,self.profileName:GetText())
        if ok then Settings:SelectProfile(name); self.profileName:SetText(""); self.profileMessage:SetText("Profile created.")
        else self.profileMessage:SetText("Use a unique name (1-48 bytes, no control characters or |).") end
    end
    self.profileName=UI:Field(create,"Profile name",UI:Input(create,430,newProfile),16,91)
    self.createProfile=at(UI:Button(create,"Create & select",158,newProfile,true),create,466,112)
    self.profileMessage=at(UI:Label(create,"",12,"accent"),create,16,166)
    local core=self.pages.core
    local coreCard=at(UI:Section(core,"Runtime snapshot",880,440,"info"),core,0,0)
    self.diagnostics=at(UI:Label(coreCard,"",13),coreCard,16,58); D.Width(self.diagnostics,820)
    at(UI:Button(coreCard,"Refresh snapshot",160,function() self:UpdateDiagnostics() end),coreCard,16,390)
    self.footer=CreateFrame("Frame",nil,body); D.Point(self.footer,"BOTTOMLEFT"); D.Point(self.footer,"BOTTOMRIGHT"); D.Height(self.footer,48)
    local footerRule=UI:Rule(self.footer,1); D.Point(footerRule,"TOPLEFT"); D.Point(footerRule,"TOPRIGHT")
    self.scale=UI:ScaleSlider(self.footer,150,function(v) Settings:Set("scale",v) end); D.Point(self.scale,"RIGHT",-144,0)
    self.done=UI:Button(self.footer,"Done",112,function() window:Hide() end,true); D.Point(self.done,"RIGHT",-18,0)
    self.footerLabel=UI:Label(self.footer,"BV / "..ns.version,11,"muted"); D.Point(self.footerLabel,"LEFT",20,0)
    self.cards={typeCard=typeCard,surf=surf,prefs=prefs,minimap=minimap,profileCard=profileCard,create=create,coreCard=coreCard}
    local function navigation(page,definitions)
        page.navigation={definitions=definitions,selected="overview",select=function(id) page.navigation.selected=id end}
    end
    navigation(appearance,{{id="overview",label="Overview"},{id="typography",label="Typography"},{id="materials",label="Materials"},{id="interaction",label="Interaction"},{id="minimap",label="Minimap"}})
    navigation(profiles,{{id="overview",label="Overview"},{id="active",label="Active profile"},{id="create",label="Create profile"}})
    navigation(core,{{id="overview",label="Snapshot"}})
    -- Capture the original layouts once. Half-width cards never shrink below
    -- their design width; full-width forms stack fields at narrow sizes.
    window:HookScript("OnSizeChanged",function() if self.cards then self:Layout() end end)
    window:HookScript("OnShow",function()
        self:Refresh()
        ns.Events:Subscribe(self,"DISPLAY_SIZE_CHANGED",function() self:Refresh() end)
        ns.Events:Subscribe(self,"UI_SCALE_CHANGED",function() self:Refresh() end)
    end)
    window:HookScript("OnHide",function()
        ns.Events:Release(self); ns.ProgressBars:ClosePreviews(); UI:CloseDropdown()
        if UI.colorEditor then UI.colorEditor:Hide() end
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

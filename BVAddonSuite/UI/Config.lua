local _,ns=...
local UI,Settings=ns.UI,ns.Settings
local D=ns.DesignSystem.Metrics
local Shell=ns.ShellMetrics
local FOOTER_LABEL_WIDTH=860
local bvShellThemes=ns.ThemeTokens.themes
local Config={page="appearance",modulePages={},moduleOrder={}}
ns.Config=Config
-- The loaded family is fixed for the session; the saved target may differ.
-- This creates only a Factory (no frames), before any migrated editor can capture it.
function Config:EnsureShellStyle()
    if self.interfaceInitialized then return self.shellStyle end
    if not Settings.db then return nil end
    self.shellMode=self.shellMode or Settings:Get("interfaceTheme") or "clean"
    if not bvShellThemes[self.shellMode] then self.shellMode="clean" end
    if bvShellThemes[self.shellMode] then
        local tools=UI:ContextServices()
        local accent=Settings:Get("interfaceAccent");if accent=="" then accent=nil end
        local style=ns.DesignSystem:New(tools.owner,{materialProfile="interface",themeKey=self.shellMode,accent=accent})
        style.fontResolver,style.registerPaint=tools.fontResolver,tools.registerPaint
        style.shellPresentation="clean";self.shellStyle=style
        style.interfaceSurface={key=Settings:Get("interfaceSurface"),area=Settings:Get("interfaceSurfaceArea"),strength=Settings:Get("interfaceSurfaceStrength")}
    end
    self.interfaceInitialized=true
    return self.shellStyle
end
function Config:SyncInterfaceSettings()
    self:EnsureShellStyle()
    local target=Settings:Get("interfaceTheme")
    self.interfaceReloadRequired=target~=self.shellMode
    if self.shellStyle and not self.interfaceReloadRequired then
        local accent=Settings:Get("interfaceAccent");if accent=="" then accent=nil end
        if self.shellStyle.interfaceAccent~=accent then self.shellStyle:SetInterfaceTheme(self.shellMode,accent)end
        local surface=self.shellStyle.interfaceSurface
        surface.key,surface.area,surface.strength=Settings:Get("interfaceSurface"),Settings:Get("interfaceSurfaceArea"),Settings:Get("interfaceSurfaceStrength")
        if self.shellPresentation and self.shellPresentation.surface then self.shellPresentation.surface:Refresh()end
    end
end
function Config:SetShellPresentation(mode)
    if not bvShellThemes[mode] then return false,"Use "..table.concat(ns.ThemeTokens.order,", ").."."end
    if self.window or self.shellStyle then return false,"Shell context already captured; reload before choosing a different shell."end
    self.shellMode=mode;self.interfaceInitialized=nil;self:EnsureShellStyle();return true
end
function Config:WithPageStyle(fn,pageID)
    return self:WithShellStyle(fn)
end
-- The page ID is explicit: search can build several pages, including failures.
-- buildingPage is only search metadata, never a sticky style selector.
function Config:BuildModulePage(id)
    local previous=self.buildingPage;self.buildingPage=id
    local ok,page=pcall(function()
        return self:WithPageStyle(function()return self.modulePages[id].build(self.pageContent)end,id)
    end)
    self.buildingPage=previous
    if not ok then error(page,0)end
    return page
end
function Config:WithShellStyle(fn)
    local style=self:EnsureShellStyle()
    assert(style and style.materialProfile=="interface","Configuration requires a ready Interface context")
    return UI:WithStyle(style,fn)
end
local function at(w,p,x,y) return UI:Place(w,p,x,y) end
local NAV,HEADING,ROW=30,24,26
-- Sidebar (Florian 2026-10-08, after EllesmereUI's): the suite's own pages
-- pinned on top with distinct symbols; modules as compact text rows in real
-- categories, each with a power switch. Modules pick a category with
-- definition.category (id) and categoryLabel; the known pages are listed
-- here so published packages need no new version. Unknown ones go to Other.
local categoryOrder={"pinned","interface","combat","questmap","loot"}
local categoryLabels={pinned="Suite",interface="Interface",combat="Combat",questmap="Quest and map",loot="Loot",enhancements="Other"}
local pageCategory={layout="pinned",appearance="pinned",profiles="pinned",core="pinned"}
local pinnedOrder={"layout","appearance","profiles","stage","core"}
local KNOWN={experience={"interface","experience_bar"},reputation={"interface","reputation_bar"},bags={"interface","bag_bar"},
    micromenu={"interface","micro_menu"},aurastudio={"combat","aura_studio"},combattext={"combat","combat_text"},
    quest={"questmap","quest"},map={"questmap","map"},loot={"loot","loot"},stage={"pinned"}}
local pageModule={}
local titles={appearance="Global Settings",profiles="Profiles",core="Core Status"}
local icons={layout="layout-dashboard",appearance="settings",profiles="layers",stage="bell",core="activity"}
-- Compact navigation keeps module identity separate from the power action.
local moduleIcons={experience="gauge",reputation="award",bags="shopping-bag",micromenu="list-tree",
    aurastudio="sparkles",combattext="swords",quest="scroll-text",map="map",routing="route",questnav="navigation",
    gather="leaf",loot="gem"}
local moduleArt={experience="BVAddonSuite_Experience",reputation="BVAddonSuite_Reputation",
    bags="BVAddonSuite_Bags",micromenu="BVAddonSuite_MicroMenu",aurastudio="BVAddonSuite_AuraStudio",
    combattext="BVAddonSuite_CombatText",quest="BVAddonSuite_Quest",map="BVAddonSuite_Map",
    routing="BVAddonSuite_Routing",questnav="BVAddonSuite_QuestNavigation",gather="BVAddonSuite_Gather",loot="BVAddonSuite_Loot"}
-- Package identity has authored colors. Keep semantic symbols (power, search,
-- third-party pages) in the palette and preserve the existing navigation layout.
local function moduleArtwork(button,id)
    local package=moduleArt[id];if not package then return end
    if button.navIcon then button.navIcon:Hide() end
    button.icon=nil
    local texture=button:CreateTexture(nil,"ARTWORK")
    texture:SetTexture("Interface\\AddOns\\"..package.."\\Media\\Brand\\module-icon.tga")
    texture:SetVertexColor(1,1,1,1);D.Size(texture,16,16);D.Point(texture,"LEFT",10,0)
    button.navIcon=texture;button.moduleArtwork=true
end
local descriptions={appearance="Shared typography, surfaces and preferences for every BV module.",profiles="Independent configurations for your characters and activities.",core="Client and module diagnostics, captured on demand."}
function Config:RegisterPage(id,definition)
    assert(not titles[id],"Duplicate configuration page")
    self.modulePages[id]=definition; self.moduleOrder[#self.moduleOrder+1]=id
    titles[id],descriptions[id]=definition.title,definition.description
    if not icons[id] then
        local requested=definition.icon
        icons[id]=ns.Symbols and ns.Symbols:Valid(requested) and requested or moduleIcons[id] or "layout-grid"
    end
    local known=KNOWN[id] or {}
    local category=type(definition.category)=="string" and definition.category:match("^[a-z][a-z0-9_]*$") and definition.category or known[1] or "enhancements"
    -- Old ids from before the sidebar rework: Core's own pages are pinned.
    if category=="core" or category=="design" then category="pinned" end
    pageModule[id]=type(definition.module)=="string" and definition.module or known[2]
    if category=="enhancements" then
        if not self.otherAdded then self.otherAdded=true;categoryOrder[#categoryOrder+1]=category end
    elseif not categoryLabels[category] then
        categoryLabels[category]=type(definition.categoryLabel)=="string" and definition.categoryLabel or category
        categoryOrder[#categoryOrder+1]=category
    end
    pageCategory[id]=category
    if self.window then self:ModuleNavigation(); self:Layout() end
end
function Config:ModuleNavigation()
    for _,id in ipairs(self.moduleOrder) do
        local key=id
        if not self.nav[id] then
            if pageCategory[id]=="pinned" then self.nav[id]=self.navButton(titles[id],function() self:SelectPage(key) end,icons[id] or "layout-grid",0)
            else self.nav[id]=self:ModuleRow(id) end
        end
    end
    for _,category in ipairs(categoryOrder) do if category~="pinned" then self:CategoryHeading(category) end end
end
-- A module's row: its name (opens the page) and a power switch on the right.
function Config:ModuleRow(id)
    local row=self:WithShellStyle(function()return UI:NavButton(self.navContent,titles[id],160,function() self:SelectPage(id) end,false,icons[id])end)
    moduleArtwork(row,id)
    D.Height(row,ROW-2);if row.mark then D.Height(row.mark,ROW-2) end
    row:SetLabelInsets(14,34,"LEFT");row.isModuleRow=true
    if row.navIcon then row.navIcon:Hide() end
    if self.shellStyle then self.shellStyle:Font(row.label,14)end
    local module=pageModule[id]
    if module then
        row.power=CreateFrame("Button",nil,row);D.Size(row.power,22,22);D.Point(row.power,"RIGHT",row,"RIGHT",-4,0)
        row.power:SetFrameLevel(row:GetFrameLevel()+3)
        row.power.icon=self:WithShellStyle(function()return UI:Icon(row.power,"power",Shell.IsWoW(self.shellStyle.interfaceThemeKey) and 13 or 15,"muted")end);D.Point(row.power.icon,"CENTER")
        row.powerIconSize=D.GetWidth(row.power.icon)
        local function showPowerTooltip(owner)
            local record=ns.Modules.records[module]
            local state=record and record.state or "missing"
            UI:ShowTooltip(owner,titles[id],state=="enabled" and "On. Click to switch it off." or state=="faulted" and "Stopped after an error. Click to try again."
                or "Off. Click to switch it on.")
        end
        row.power:SetScript("OnEnter",showPowerTooltip)
        row.power:SetScript("OnClick",function(owner)
            self:TogglePower(id)
            -- Read the resulting state, including a failed enable or combat block.
            -- Never open a tooltip on click or take one from a different owner.
            local tip=UI.tooltip
            if tip and tip.owner==owner and tip:IsShown() and owner:IsVisible() then showPowerTooltip(owner)end
        end)
        row.power:SetScript("OnLeave",function(owner) UI:HideTooltip(owner) end)
    end
    row.moduleID=module
    return row
end
function Config:TogglePower(id)
    local module=pageModule[id]
    local record=module and ns.Modules.records[module]
    if not record then return end
    if InCombatLockdown and InCombatLockdown() then ns:Print("Switch modules after combat.");return end
    ns.Modules:SetEnabled(module,record.state~="enabled")
    if ns.Layout and ns.Layout.Refresh then ns.Layout:Refresh(true) end
    self:Refresh()
end
-- Compact rows have two disjoint hit rectangles. The power child sits beside,
-- not over, the page button; neither controller needs a new dispatch path.
function Config:LayoutNavigationButton(button,width,compact)
    local separate=compact and button.isModuleRow and button.power
    D.Width(button,separate and width-18 or width);button.label:SetShown(not compact)
    if button.navIcon then
        button.navIcon:ClearAllPoints()
        -- Keep the identity column fixed even when a row has no power action.
        -- Its full hit width is independent from the shared 26-unit icon lane.
        if compact then D.Point(button.navIcon,"CENTER",button,"LEFT",(width-18)/2,0)
        else D.Point(button.navIcon,"LEFT",10,0)end
        button.navIcon:SetShown(compact or not button.isModuleRow)
    end
    if button.power then
        button.power:ClearAllPoints()
        if compact then
            D.Size(button.power,16,20);D.Point(button.power,"LEFT",button,"RIGHT",2,0)
            D.Size(button.power.icon,12,12)
        else
            D.Size(button.power,22,22);D.Point(button.power,"RIGHT",button,"RIGHT",-4,0)
            D.Size(button.power.icon,button.powerIconSize,button.powerIconSize)
        end
    end
end
-- Power symbols and row colours follow the module states.
function Config:PaintPower()
    for id,row in pairs(self.nav) do
        if row.power then
            local record=ns.Modules.records[row.moduleID]
            local state=record and record.state
            local role=state=="enabled" and "success" or state=="faulted" and "danger" or "muted"
            row.power.icon.colorRole=role;row.power.icon:SetColor(self.shellStyle:Color(role))
            if row.label then row.label:SetAlpha(state=="enabled" and 1 or .6) end
        end
    end
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
    h.label=self:WithShellStyle(function()return UI:Label(h,string.upper(categoryLabels[category]),10,"accentText",true)end); D.Point(h.label,"LEFT",10,0); D.Size(h.label,120,16)
    h.label:SetWordWrap(false)
    h.open=self:WithShellStyle(function()return UI:Icon(h,"chevron",12,"muted")end); D.Point(h.open,"RIGHT",-6,0)
    h.closed=self:WithShellStyle(function()return UI:Icon(h,"right",12,"muted")end); D.Point(h.closed,"RIGHT",-6,0)
    h:SetScript("OnClick",function() self:ToggleCategory(category) end)
    h:SetScript("OnEnter",function() h.label:SetTextColor(self.shellStyle:Color("text")) end)
    h:SetScript("OnLeave",function() h.label:SetTextColor(self.shellStyle:Color("accentText")) end)
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
    -- The suite's own pages, always open, no heading.
    for _,id in ipairs(pinnedOrder) do
        local button=buttons[id]
        if button then button:Show();at(button,self.navContent,0,y);y=y+NAV end
    end
    y=y+8
    -- Settings search (Core 0.8.96): results take the module list's place.
    self.searchBox:SetShown(not compact);self.searchHint:SetShown(not compact and self.searchBox:GetText()=="" and not self.searchBox:HasFocus())
    if not compact and self.shellStyle and Shell.IsWoW(self.shellStyle.interfaceThemeKey) then
        at(self.searchBox,self.header,218,7);D.Size(self.searchBox,math.min(320,math.max(80,D.GetWidth(self.window)-260)),26)
        at(self.searchHint,self.searchBox,10,6);D.Width(self.searchHint,math.max(1,D.GetWidth(self.searchBox)-20))
    elseif not compact then
        at(self.searchBox,self.navContent,0,y);D.Width(self.searchBox,side-28)
        at(self.searchHint,self.searchBox,10,6);D.Width(self.searchHint,side-48)
        y=y+34
    end
    local searching=not compact and self.searchResults~=nil
    for _,row in ipairs(self.searchRows) do row:Hide() end
    self.searchEmpty:Hide()
    if searching then
        for _,heading in pairs(self.categoryHeadings or {}) do heading:Hide() end
        for id,button in pairs(self.nav) do if pageCategory[id]~="pinned" then button:Hide() end end
        self.emptyModules:Hide()
        for index,result in ipairs(self.searchResults) do
            local row=self:SearchRow(index)
            row.result=result
            row.title:SetText(result.title)
            local where=titles[result.page] or ""
            if result.section and result.section~="" then where=where.."  ·  "..result.section end
            if result.kind=="page" then where="Page" end
            row.where:SetText(where)
            at(row,self.navContent,0,y);D.Width(row,side-28);D.Width(row.title,side-40);D.Width(row.where,side-40)
            row:Show();y=y+40
        end
        if #self.searchResults==0 then at(self.searchEmpty,self.navContent,10,y);self.searchEmpty:Show();y=y+24 end
        return y
    end
    local modules=0
    for _,category in ipairs(categoryOrder) do
        if category~="pinned" then
            local items={}
            for _,id in ipairs(self.moduleOrder) do if pageCategory[id]==category then items[#items+1]=id end end
            local heading=self:CategoryHeading(category)
            local visible=#items>0
            modules=modules+#items
            heading:SetShown(visible and not compact)
            local open=compact or not collapsed[category]
            if visible and not compact then
                at(heading,self.navContent,0,y); D.Width(heading,side-28)
                heading.open:SetShown(open); heading.closed:SetShown(not open)
                y=y+HEADING
            end
            for _,id in ipairs(items) do
                local button=buttons[id]
                if button then
                    button:SetShown(open)
                    if open then at(button,self.navContent,0,y); y=y+(button.power and ROW or NAV) end
                end
            end
            if visible then y=y+14 end
        end
    end
    self.emptyModules:SetShown(modules==0 and not compact)
    if modules==0 and not compact then at(self.emptyModules,self.navContent,8,y+4); y=y+24 end
    return y
end
-- Settings search (Core 0.8.96, Florian's second step after the sidebar):
-- page titles and every settings row (title, tooltip text, section) of all
-- pages; building every module page once is the price of the first search.
local SEARCH_MAX=12
function Config:BuildAllPages()
    for _,id in ipairs(self.moduleOrder) do
        if not self.pages[id] then
            local ok,page=pcall(function()return self:BuildModulePage(id)end)
            if ok and page then self.pages[id]=page;if id~=self.page then page:Hide() end end
        end
    end
end
function Config:SearchIndex()
    self:BuildAllPages()
    local out={}
    for id,title in pairs(titles) do out[#out+1]={kind="page",page=id,title=title,help=descriptions[id]} end
    for _,grid in ipairs(UI.settingsGrids or {}) do
        if grid.pageID and titles[grid.pageID] then
            for _,item in ipairs(grid.items) do
                if item.kind=="row" and type(item.title)=="string" and item.title~="" then
                    out[#out+1]={kind="setting",page=grid.pageID,title=item.title,help=item.help,
                        section=item.section and item.section.text,grid=grid,item=item}
                end
            end
        end
    end
    return out
end
-- Best first: name starts with the text, name contains it, its section or
-- page does, its explanation does.
function Config:Search(text)
    text=type(text)=="string" and text or ""
    text=text:lower():gsub("^%s+",""):gsub("%s+$","")
    if #text<2 then return nil end
    local order={}
    for i,id in ipairs(pinnedOrder) do order[id]=i end
    for i,id in ipairs(self.moduleOrder) do order[id]=order[id] or 100+i end
    local hits={}
    for _,entry in ipairs(self:SearchIndex()) do
        local title=entry.title:lower()
        local rank
        if title:sub(1,#text)==text then rank=1
        elseif title:find(text,1,true) then rank=2
        elseif ((entry.section or ""):lower()):find(text,1,true) or ((titles[entry.page] or ""):lower()):find(text,1,true) then rank=3
        elseif type(entry.help)=="string" and entry.help:lower():find(text,1,true) then rank=4 end
        if rank then entry.rank=rank;hits[#hits+1]=entry end
    end
    table.sort(hits,function(a,b)
        if a.rank~=b.rank then return a.rank<b.rank end
        if a.kind~=b.kind then return a.kind=="page" end
        local oa,ob=order[a.page] or 999,order[b.page] or 999
        if oa~=ob then return oa<ob end
        return a.title<b.title
    end)
    while #hits>SEARCH_MAX do table.remove(hits) end
    return hits
end
function Config:UpdateSearch()
    self.searchResults=self:Search(self.searchBox:GetText())
    self:Layout()
end
function Config:ClearSearch()
    self.searchBox:SetText("");self.searchBox:ClearFocus()
    self.searchResults=nil
    self:Layout()
end
function Config:SearchRow(index)
    local row=self.searchRows[index]
    if row then return row end
    row=CreateFrame("Button",nil,self.navContent);D.Size(row,160,38)
    row.band=row:CreateTexture(nil,"BACKGROUND");row.band:SetAllPoints(row);row.band:SetColorTexture(1,1,1,0)
    row.title=self:WithShellStyle(function()return UI:Label(row,"",12,"text")end);D.Point(row.title,"TOPLEFT",10,-4);row.title:SetWordWrap(false)
    row.where=self:WithShellStyle(function()return UI:Label(row,"",10,"muted")end);D.Point(row.where,"TOPLEFT",10,-21);row.where:SetWordWrap(false)
    row:SetScript("OnEnter",function() row.band:SetColorTexture(1,1,1,.06) end)
    row:SetScript("OnLeave",function() row.band:SetColorTexture(1,1,1,0) end)
    row:SetScript("OnClick",function() if row.result then Config:Go(row.result) end end)
    self.searchRows[index]=row
    return row
end
-- Opens the hit: its page, its tab or section, scrolled to the row, which
-- lights up for a moment.
function Config:Go(result)
    self.searchBox:SetText("");self.searchBox:ClearFocus();self.searchResults=nil
    self:SelectPage(result.page)
    if result.kind~="setting" then return end
    local page=self.pages[result.page];local navigation=page and page.navigation
    local section=result.grid.navigationID or (result.item.section and result.item.section.id)
    if navigation and section then
        for _,definition in ipairs(navigation.definitions or {}) do
            local holds=definition.id==section
            for _,id in ipairs(definition.sections or {}) do if id==section then holds=true end end
            if holds then self:SelectSection(definition.id);break end
        end
    end
    self:Layout()
    local y=result.item.y or 0
    local gridTop,contentTop=result.grid:GetTop(),self.pageContent:GetTop()
    if type(gridTop)=="number" and type(contentTop)=="number" then y=y+D.ToDesign(contentTop-gridTop) end
    self.pageScroll:SetValue(math.max(0,math.min(self.pageMaximum or 0,y-24)))
    result.grid:Flash(result.item)
end
function Config:OpenPage(id)
    if ns.LayoutEditor.active then ns:Print("Finish layout editing before opening module settings."); return end
    if InCombatLockdown() then ns:Print("Open configuration after combat."); return end
    if not self:Build() then return false end
    self:SelectPage(id); self.window:Show()
end
function Config:SelectPage(id)
    if not titles[id] then ns:Print("This module is not loaded."); return end
    local module=self.modulePages[id]
    if module then self.pages[id]=self:BuildModulePage(id)end
    if self.shellStyle then self.navReveal=true end
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
function Config:RefreshInterfaceControls()
    if not self.interfaceControls then return end
    local c=self.interfaceControls;local target=Settings:Get("interfaceTheme")
    if c.target and c.target~=target and UI.colorPopup and UI.colorPopup.owner==c.accent then UI.colorPopup:Hide()end
    c.target=target
    local family=ns.ThemeTokens.themes[target];local enabled=family~=nil
    c.theme:SetValue(target);c.surface:SetValue(Settings:Get("interfaceSurface"));c.area:SetValue(Settings:Get("interfaceSurfaceArea"))
    c.strength:SetValue(Settings:Get("interfaceSurfaceStrength"))
    local accent=Settings:Get("interfaceAccent");local default=family and family.accent or "d9b35c"
    c.accent.bvColorOptions={style=self.shellStyle,rgb=true,default=default}
    c.accent:SetValue((accent=="" and default or accent).."ff")
    if accent=="" then c.accent:SetLabelText("Family default")end
    local function enable(control,value)if value then control:Enable()else control:Disable()end end
    enable(c.accent,enabled);enable(c.surface,enabled)
    local textured=enabled and Settings:Get("interfaceSurface")~="none"
    enable(c.area,textured);if textured then c.strength:Enable()else c.strength:Disable()end
    local pending=target~=self.shellMode
    self.interfaceReloadRequired=pending
    c.status:SetText(pending and "Saved. Reload the UI to change the interface family." or enabled and "Accent and background changes apply immediately." or "Existing interface. Choose a family, then reload the UI.")
    enable(c.reload,pending and not (InCombatLockdown and InCombatLockdown()) and not (ns.Layout and ns.Layout.draft))
end
function Config:BuildInterfaceControls(g)
    local choices={}
    for _,key in ipairs(ns.ThemeTokens.order)do choices[#choices+1]={value=key,label=ns.ThemeTokens.themes[key].name}end
    local c={};self.interfaceControls=c
    g:Section("interface","Interface design")
    c.theme=g:Row("Theme family",UI:Dropdown(g,220,choices,function(v)Settings:Set("interfaceTheme",v)end),{help="Changes the complete interface family after a UI reload. Existing settings and gameplay styles are preserved."})
    c.accent=g:Row("Accent colour",UI:ColorInput(g,220,function(v)Settings:Set("interfaceAccent",v=="" and "" or v:sub(1,6))end),{help="RGB accent for this interface. Default follows the selected family."})
    c.surface=g:Row("Background motif",UI:Dropdown(g,220,{{value="none",label="Quiet"},{value="atlas",label="Atlas"},{value="relief",label="Relief"},{value="mist",label="Mist"},{value="patina",label="Patina"},{value="horde",label="Horde"},{value="alliance",label="Alliance"}},function(v)Settings:Set("interfaceSurface",v)end),{help="Choose a subtle motif for windows, the route guide, nearby arrivals and quest HUDs. Quiet removes the motif without changing the selected area or strength."})
    c.area=g:Row("Background area",UI:Dropdown(g,220,{{value="casing",label="Header and sidebar"},{value="full",label="Whole window"}},function(v)Settings:Set("interfaceSurfaceArea",v)end),{help="Apply the motif to the header and sidebar, or across the whole interface window. This does not change HUD or popup transparency."})
    c.strength=g:Row("Texture strength",UI:InlineSlider(g,220,0,50,5,"%d%%",function(v)Settings:Set("interfaceSurfaceStrength",v)end),{help="Shared by interface windows and gameplay panels: routing, quests, Gather, Codex and loot. From 0% (hidden) to 50%; default 15%. Text and icons keep their own opacity. Choose a motif first; Quiet preserves the selected area and strength."})
    c.status=g:Block(UI:Label(g,"",12,"muted"),32)
    c.reload=g:Row(nil,UI:Button(g,"Reload UI",120,function()
        if Settings:Get("interfaceTheme")==self.shellMode or (InCombatLockdown and InCombatLockdown()) or (ns.Layout and ns.Layout.draft)then return end
        ReloadUI()
    end),{help="Reload deliberately to apply the saved family. Unavailable in combat or during a layout draft."})
    self:RefreshInterfaceControls()
end
function Config:RefreshProfileCopy()
    if not self.profileSource then return end
    if self.profileCopyTarget~=Settings.db.activeProfile then self.profileCopyMessage:SetText("") end
    self.profileCopyTarget=Settings.db.activeProfile
    local options,selected={},nil
    for _,option in ipairs(Settings:ListProfiles()) do
        if option.value~=Settings.db.activeProfile then
            options[#options+1]=option
            if option.value==self.profileSource.value then selected=option.value end
        end
    end
    self.profileSource:SetOptions(options);self.profileSource:SetValue(selected)
    if not selected then self.profileSource:SetLabelText(#options>0 and "Choose a profile..." or "No other profiles") end
    if selected then self.copyProfile:Enable() else self.copyProfile:Disable() end
    self.profileCopyNotice:SetText('Replaces settings and layout in "'..Settings.db.activeProfile..'". The source profile stays unchanged.')
end
function Config:Refresh()
    if not self.window then return end
    self:RefreshInterfaceControls()
    local sizes=self.shellConfig
    UI:FitWindow(self.window,sizes.width,sizes.height,Settings:Get("scale"))
    ns.Styles:SuiteFamily()
    for _,key in ipairs({"font","themeKey","scale","statusbar","tooltips","gameFamily"}) do self[key]:SetValue(Settings:Get(key)) end
    self.profile:SetOptions(Settings:ListProfiles()); self.profile:SetValue(Settings.db.activeProfile)
    self:RefreshProfileCopy()
    self.profileLabel:SetText("PROFILE  /  "..Settings.db.activeProfile)
    if self.shellPresentation then self.shellPresentation:SetMetadata(Settings.db.activeProfile)end
    if self.page=="core" and self.window:IsShown() then self:UpdateDiagnostics() end
    for _,id in ipairs(self.moduleOrder) do self.modulePages[id].refresh() end
    self:PaintPower()
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
    local w,h=Shell.ContentSize(D.GetWidth(self.window),D.GetHeight(self.window),self.window.shellMetrics)
    local native=Shell.IsWoW(self.shellStyle.interfaceThemeKey)
    local target=(native and Shell.WoWLayout or Shell.BVDarkLayout)(D.GetWidth(self.window),D.GetHeight(self.window),self.tabs:IsShown(),self.shellStyle.interfaceThemeKey)
    local compact,side,footer=target.compact,target.side,target.footer
    local navInset=compact and 4 or native and 7 or 14;local navTop=native and 8 or target.brand+8
    local navWidth=side-navInset*2-(compact and 4 or 0)
    at(self.sidebar,self.window.content,native and 14 or 0,native and 114 or 0);D.Size(self.sidebar,side,native and h-168 or h-footer)
    self.profileLabel:SetShown(not compact);self.profileRule:SetShown(not compact)
    at(self.navScroll,self.sidebar,navInset,navTop);D.Size(self.navScroll,navWidth,math.max(80,(native and h-168 or h-footer)-navTop-54))
    self.sectionTree:Hide();self.sectionHeading:Hide()
    local navHeight=self:ArrangeNavigation(side,compact)
    D.Size(self.navContent,navWidth,navHeight)
    local navViewHeight=D.GetHeight(self.navScroll)
    self.navMax=math.max(0,navHeight-navViewHeight)
    self.navOffset=math.max(0,math.min(self.navOffset or 0,self.navMax))
    if self.shellStyle then
        -- Selection and real viewport changes reveal the active row once; ordinary
        -- paints/layouts retain the user's chosen scroll position.
        if not self.navViewWidth or math.abs(self.navViewWidth-navWidth)>.01 or math.abs(self.navViewHeight-navViewHeight)>.01 then
            self.navReveal=true;self.navViewWidth,self.navViewHeight=navWidth,navViewHeight
        end
        if self.navReveal and not self.searchResults then
            local active=self.nav[self.page]
            if active and active:IsShown() then
                local _,_,_,_,y=active:GetPoint(1)
                local top=-D.ToDesign(y);local bottom=top+D.GetHeight(active)
                if top<self.navOffset then self.navOffset=top
                elseif bottom>self.navOffset+navViewHeight then self.navOffset=bottom-navViewHeight end
                self.navOffset=math.max(0,math.min(self.navOffset,self.navMax))
            end
            self.navReveal=nil
        end
    end
    self.navScroll:SetVerticalScroll(D.ToNative(self.navOffset))
    local buttons={self.layoutButton};for _,button in pairs(self.nav)do buttons[#buttons+1]=button end
    for _,button in ipairs(buttons)do self:LayoutNavigationButton(button,native and navWidth-14 or navWidth,compact)end
    local inner=target.inner
    local headerHeight=target.header
    at(self.header,self.window.content,native and 14 or side,native and 64 or 0);D.Size(self.header,native and w-28 or w-side,headerHeight)
    if native then
        self.description:Hide()
        at(self.tabs,self.window.content,240,h-87);self.tabs:Arrange(math.max(1,w-280));D.Height(self.footer,footer)
        self.footer:ClearAllPoints();at(self.footer,self.window.content,14,h-54);D.Width(self.footer,w-28)
        self.shellPresentation:Layout(target)
    else
        at(self.heading,self.header,20,14);D.Size(self.heading,math.max(1,w-side-150),30)
        at(self.description,self.header,20,48);D.Size(self.description,math.max(1,w-side-44),18)
        at(self.tabs,self.window.content,side+22,headerHeight+9);self.tabs:Arrange(inner)
        D.Height(self.footer,footer)
        self.shellPresentation:Layout(target)
    end
    -- Keep the existing footer group, reserving the full resize hit width at its right.
    local gripReserve=D.GetWidth(self.window.resizeGrip)
    self.done:ClearAllPoints();D.Point(self.done,"RIGHT",-14-gripReserve,0)
    self.scale:ClearAllPoints();D.Point(self.scale,"RIGHT",-130-gripReserve,0)
    local top=target.top
    local viewHeight=target.viewHeight
    at(self.viewport,self.window.content,native and 254 or side+22,top);D.Size(self.viewport,inner,viewHeight)
    at(self.pageScroll,self.window.content,w-(native and 38 or 12),top);D.Size(self.pageScroll,8,viewHeight)
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
        at(grid,page,0,0); height=grid:Arrange(math.max(1,inner-10))+8
    end
    D.Height(page,height); D.Height(self.pageContent,height)
    self.pageMaximum=math.max(0,height-viewHeight); self.pageScroll:SetMinMaxValues(0,self.pageMaximum); self.pageScroll:SetShown(self.pageMaximum>0)
    self.pageScroll:SetValue(math.min(self.pageScroll:GetValue(),self.pageMaximum)); self.footerLabel:SetShown(w>=FOOTER_LABEL_WIDTH)
    self.arranging=false
    self:UpdateShellScroll()
end
function Config:UpdateShellScroll()
    if self.shellPresentation and self.navContent then
        self.shellPresentation:Scroll(self.navOffset or 0,self.navMax or 0,D.GetHeight(self.navScroll),D.GetHeight(self.navContent),self.pageScroll:GetValue(),self.pageMaximum or 0)
    end
end
function Config:Build()
    if self.window then return true end
    if not self:EnsureShellStyle() then return false end
    self.shellConfig={width=1200,height=Shell.IsWoW(self.shellMode) and 730 or 740,minWidth=720,minHeight=480}
    local sizes=self.shellConfig
    local window=self:WithShellStyle(function()return UI:Window("BVAddonSuiteConfig",sizes.width,sizes.height,{minWidth=sizes.minWidth,minHeight=sizes.minHeight,shellMetrics=Shell.IsWoW(self.shellStyle.interfaceThemeKey) and Shell.WoWWindow() or Shell.BVDarkWindow(self.shellStyle.interfaceThemeKey)})end);self.window=window
    window:SetTitle("Addon Suite")
    local body=window.content
    self:WithShellStyle(function()
    local sidebar=CreateFrame("Frame",nil,body); self.sidebar=sidebar
    self.sideRule=UI:Rule(sidebar,1); D.Point(self.sideRule,"TOPRIGHT"); D.Point(self.sideRule,"BOTTOMRIGHT")
    self.navScroll=CreateFrame("ScrollFrame",nil,sidebar); self.navScroll:SetClipsChildren(true); self.navScroll:EnableMouseWheel(true)
    self.navContent=CreateFrame("Frame",nil,self.navScroll); D.Size(self.navContent,160,420); self.navScroll:SetScrollChild(self.navContent)
    self.navScroll:SetScript("OnMouseWheel",function(_,delta)
        self.navOffset=math.max(0,math.min(self.navMax or 0,(self.navOffset or 0)-delta*NAV)); self.navScroll:SetVerticalScroll(D.ToNative(self.navOffset))
    end)
    self.nav={}; self.navHeadings={}
    local function navButton(text,callback,icon,y)
        local b=self:WithShellStyle(function()return at(UI:NavButton(self.navContent,text,160,callback,false,icon),self.navContent,0,y)end);
        if self.shellStyle then self.shellStyle:Font(b.label,14,"bold");b:SetLabelInsets(34,8,"LEFT")end D.Height(b,NAV-2)
        if b.mark then D.Height(b.mark,NAV-2) end
        return b
    end
    -- Positions come from ArrangeNavigation; headings are created per category.
    self.layoutButton=navButton("Layout Editor",function() ns.LayoutEditor:Open() end,icons.layout,0)
    local function nav(id) self.nav[id]=navButton(titles[id],function() self:SelectPage(id) end,icons[id],0);moduleArtwork(self.nav[id],id) end
    nav("appearance"); nav("profiles"); nav("core")
    self.emptyModules=UI:Label(self.navContent,"No feature addons loaded.",11,"muted")
    self.searchRows={}
    self.searchBox=UI:Input(self.navContent,150,function()
        local first=self.searchResults and self.searchResults[1]
        if first then self:Go(first) end
    end)
    self.searchBox:SetMaxLetters(40);D.Height(self.searchBox,28)
    self.searchBox:HookScript("OnTextChanged",function() self:UpdateSearch() end)
    self.searchBox:HookScript("OnEscapePressed",function() self:ClearSearch() end)
    self.searchBox:HookScript("OnEditFocusGained",function() self.searchHint:Hide() end)
    self.searchBox:HookScript("OnEditFocusLost",function() self.searchHint:SetShown(self.searchBox:GetText()=="") end)
    UI:AttachTooltip(self.searchBox,"Search settings","Every page and setting of the suite and its modules. Enter opens the first hit, Escape clears.")
    self.searchHint=UI:Label(self.searchBox,"Search settings…",11,"muted");self.searchHint:SetWordWrap(false)
    self.searchEmpty=UI:Label(self.navContent,"No settings found.",11,"muted")
    self.navButton=navButton
    self:ModuleNavigation()
    self.sectionHeading=UI:Label(self.navContent,"PAGE SECTIONS",10,"muted")
    self.sectionTree=UI:TreeMenu(self.navContent,{},function(id) self:SelectSection(id) end)
    self.profileLabel=UI:Label(sidebar,"",11,"muted"); D.Point(self.profileLabel,"BOTTOMLEFT",14,12); D.Size(self.profileLabel,150,28)
    self.profileRule=UI:Rule(sidebar,156); D.Point(self.profileRule,"BOTTOMLEFT",10,46)
    self.header=CreateFrame("Frame",nil,body)
    -- Kept for callers; the compact header shows only title and description.
    self.category=at(UI:Label(self.header,"",10,"accent"),self.header,20,0); self.category:Hide()
    self.heading=at(UI:Label(self.header,"",20,"text",true),self.header,20,10)
    self.heading:SetWordWrap(false)
    self.description=at(UI:Label(self.header,"",11,"muted"),self.header,20,38)
    self.description:SetWordWrap(false)
    self.tabs=UI:Tabs(body,{},function(id) self:SelectSection(id) end); self.tabs.bvHeight=30
    self.viewport=CreateFrame("ScrollFrame",nil,body); self.viewport:SetClipsChildren(true); self.viewport:EnableMouseWheel(true)
    self.pageContent=CreateFrame("Frame",nil,self.viewport); D.Size(self.pageContent,880,600); self.viewport:SetScrollChild(self.pageContent)
    self.pageScroll=UI:GetStyle():Slider(body,8,0,0,1,0,function(value) self.viewport:SetVerticalScroll(D.ToNative(value)) end)
    self.pageScroll:SetOrientation("VERTICAL"); self.pageScroll.track:ClearAllPoints(); D.Point(self.pageScroll.track,"TOP"); D.Point(self.pageScroll.track,"BOTTOM"); D.Width(self.pageScroll.track,3); D.Size(self.pageScroll:GetThumbTexture(),6,36)
    self.viewport:SetScript("OnMouseWheel",function(_,delta) self.pageScroll:SetValue(math.max(0,math.min(self.pageMaximum or 0,self.pageScroll:GetValue()-delta*42))) end)
    end)
    self.pages={}; self.grids={}
    self:WithShellStyle(function()
    for _,id in ipairs({"appearance","profiles","core"}) do
        -- Inert hosts must not gain a material repaint that makes them opaque.
        self.pages[id]=UI:Container(self.pageContent,880,600)
        self.grids[id]=UI:SettingsGrid(self.pages[id]);self.grids[id].pageID=id
    end
    local g=self.grids.appearance
    self:BuildInterfaceControls(g)
    g:Section("typography","Typography")
    self.font=g:Row("Font family",UI:AppearanceChoice(g,"font",220),{help="Used by every BV window, bar and text element that inherits the suite font."})
    self.typePreview=g:Row("Preview",UI:Label(g,"A clearer view of your adventures.",14,"text",true),{width=240,help="Sample text in the selected font."})
    g:Section("materials","Surfaces & accent")
    self.themeKey=g:Row("BV gameplay palette",UI:AppearanceChoice(g,"themeKey",220),{help="Colours for in-game elements using the BV style. Interface windows use their selected theme and accent."})
    self.statusbar=g:Row("Statusbar texture",UI:Dropdown(g,220,ns.Media:BarOptions(),function(v) Settings:Set("statusbar",v) end),
        {help="Default texture for BV bars. Individual bars can choose their own texture."})
    self.statusbar:SetOptionsProvider(function()return ns.Media:BarOptions()end)
    self.barPreview=g:Row("Preview",UI:StatusBar(g,220,10),{width=220,help="Sample bar with the selected texture."})
    -- In-game style family: gameplay elements; Interface windows keep their selected theme and accent.
    g:Section("gamestyle","In-game style")
    self.gameFamily=g:Row("Style family",UI:Dropdown(g,220,ns.Styles:Choices(false),function(v) Settings:Set("gameFamily",v) end),
        {help="Look of bars, roll bars, toasts and other elements you see while playing. Interface windows keep their selected theme and accent. A module can choose its own family on its page. \"Clean (match my UI)\" takes border, background and accent colours from a supported interface package."})
    self.gameFamily:SetOptionsProvider(function() return ns.Styles:Choices(false) end)
    g:Section("interaction","Window & interaction")
    self.tooltips=g:Row("Contextual help",UI:Switch(g,true,function(v) Settings:Set("tooltips",v) end),{help="Show tooltips on BV controls."})
    UI:AttachTooltip(self.tooltips,"Control tooltips","Show contextual help for BV controls.")
    self.resetAppearance=g:Row("Reset appearance",UI:Button(g,"Reset",110,function() Settings:ResetAppearance() end),
        {help="Font, material, statusbar texture, window scale and interface design back to their defaults. An interface family change requires a UI reload."})
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
    self.profileMessage=g:Block(UI:Label(g,"",12,"accentText"),16)
    g:Section("copy","Copy from profile")
    self.profileSource=g:Row("Source profile",UI:Dropdown(g,220,{},function(v)
        self.profileSource:SetValue(v);self.profileCopyMessage:SetText("");self:RefreshProfileCopy()
    end),{help="Copies configuration, module settings and layout into the active profile. Its name stays the same."})
    self.profileCopyNotice=g:Block(UI:Label(g,"",12,"muted"),34,function(width)
        D.Width(self.profileCopyNotice,width);return math.max(30,D.ToDesign(self.profileCopyNotice:GetStringHeight()))
    end)
    self.copyProfile=g:Row(nil,UI:Button(g,"Copy settings",150,function()
        local source=self.profileSource.value
        local ok,err=pcall(Settings.CopyFromProfile,Settings,source)
        if ok then self:Refresh();self.profileCopyMessage:SetText('Copied from "'..source..'".')
        else self.profileCopyMessage:SetText(tostring(err):gsub("^.-:%d+: ","")) end
        self:Layout()
    end,true))
    self.profileCopyMessage=g:Block(UI:Label(g,"",12,"accentText"),32,function(width)
        D.Width(self.profileCopyMessage,width);return math.max(16,D.ToDesign(self.profileCopyMessage:GetStringHeight()))
    end)
    g=self.grids.core
    g:Section("overview","Runtime snapshot")
    self.diagnostics=g:Block(UI:Label(g,"",12),200,function(width)
        D.Width(self.diagnostics,width); return math.max(40,D.ToDesign(self.diagnostics:GetStringHeight()))
    end)
    g:Row(nil,UI:Button(g,"Refresh snapshot",150,function() self:UpdateDiagnostics() end))
    end)
    self:WithShellStyle(function()
    self.footer=CreateFrame("Frame",nil,body); D.Point(self.footer,"BOTTOMLEFT"); D.Point(self.footer,"BOTTOMRIGHT"); D.Height(self.footer,Shell.IsWoW(self.shellMode) and 42 or 49)
    local footerRule=UI:Rule(self.footer,1); D.Point(footerRule,"TOPLEFT"); D.Point(footerRule,"TOPRIGHT")
    self.scale=UI:ScaleSlider(self.footer,230,function(v) Settings:Set("scale",v) end); D.Point(self.scale,"RIGHT",-130,0)
    self.done=UI:Button(self.footer,"Done",100,function() window:Hide() end,true); D.Height(self.done,28); D.Point(self.done,"RIGHT",-14,0)
    self.footerLabel=UI:Label(self.footer,"BV / "..ns.version,11,"muted"); D.Point(self.footerLabel,"LEFT",16,0)
    end)
    self.shellPresentation=ns.ShellMaterials:Attach(self.shellStyle,window,{sidebar=self.sidebar,header=self.header,footer=self.footer,config=self})
    self.shellStyle:Font(self.heading,Shell.IsWoW(self.shellMode) and 17 or 24,"bold");self.shellStyle:Font(self.description,13)
    self.tabs.bvHeight=33
    self.pageScroll:HookScript("OnValueChanged",function()self:UpdateShellScroll()end)
    self.navScroll:HookScript("OnMouseWheel",function()self:UpdateShellScroll()end)
    self.cards={}
    local function navigation(page,definitions)
        page.navigation={definitions=definitions,selected="overview",select=function(id) page.navigation.selected=id end}
    end
    navigation(self.pages.appearance,{{id="overview",label="Overview"},{id="interface",label="Interface design"},{id="typography",label="Typography"},{id="materials",label="Materials"},{id="interaction",label="Interaction"},{id="minimap",label="Minimap"}})
    navigation(self.pages.profiles,{{id="overview",label="Overview"},{id="active",label="Active profile"},{id="create",label="Create profile"},{id="copy",label="Copy from profile"}})
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
    return true
end
function Config:Toggle()
    if not ns.ready then ns:Print("The core could not initialize. Check the error handler."); return end
    if ns.LayoutEditor.active then ns.LayoutEditor:RequestClose(); return end
    if self.window and self.window:IsShown() then self.window:Hide(); return end
    if InCombatLockdown() then ns:Print("Open configuration after combat."); return end
    if not self:Build() then return false end
    self.window:Show()
end

ns.Commands:RegisterAction("uishell",function(arg)
    if arg=="status"then ns:Print("Shell: "..(Config.shellMode or "not initialized")..(Config.window and " (built)" or " (before build)"));return end
    local ok,why=Config:SetShellPresentation(arg=="" and "clean" or arg)
    ns:Print(ok and ("Shell "..Config.shellMode.." selected for the first configuration build. Settings contents keep their existing style.")or why)
end)

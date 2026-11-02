local ns = BVAddonSuiteCore
local I = ns and ns.Bags and ns.Bags.Inventory
if not I then return end
local UI, M = ns.UI, ns.DesignSystem.Metrics
local corners={"TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT"}
local cornerTitles={TOPLEFT="Top left",TOPRIGHT="Top right",BOTTOMLEFT="Bottom left",BOTTOMRIGHT="Bottom right"}
local bindings={boe="BoE",bop="BoP",bou="BoU",bound="Bound"}
local defaults={Shown=true,Size=10,Color="FFFFFFFF",Mode="custom",Font="inherit",Outline="none",StrokeColor="000000FF",
    Shadow=true,ShadowColor="00000080",ShadowX=1,ShadowY=-1,X=0,Y=0,First="none",Second="none",Third="none",PriceBasis="unit"}
local function legacyLayout(config,overrides)
    local function old(source,field)
        local values=overrides and overrides[source]
        if values and values[field]~=nil then return values[field] end
        return config[source..field]
    end
    local layout={}
    for _,point in ipairs(corners) do layout[point]={} end
    -- One binding style now covers BoE, BoP, BoU and Bound. Import BoE as its representative.
    local function import(source,content,defaultPoint)
        local point=old(source,"Point") or defaultPoint
        local dst=layout[point] or layout[defaultPoint]
        if dst.First then dst.Second=content;return end
        dst.First=content
        for field in pairs(defaults) do
            local value=old(source,field)
            if value~=nil then dst[field]=value end
        end
        if source=="count" then dst.Size=dst.Size or 11
        else
            dst.Color=dst.Color or "8CE4BCFF"
            if dst.Shown==nil then dst.Shown=config.bindLabels~=false end
        end
    end
    import("count","quantity","BOTTOMRIGHT")
    import("boe","binding","TOPLEFT")
    return layout
end
local function layouts(config)
    if config.cornerLayouts then return config.cornerLayouts end
    local shared=legacyLayout(config)
    local result={default=shared}
    for scope,old in pairs(config.categoryLabels or {}) do
        local group={}
        local migrated=legacyLayout(config,old)
        for _,point in ipairs(corners) do
            local patch={}
            for field,fallback in pairs(defaults) do
                local value=migrated[point][field]
                if value==nil then value=fallback end
                local parent=shared[point][field]
                if parent==nil then parent=fallback end
                if value~=parent then patch[field]=value end
            end
            if next(patch) then group[point]=patch end
        end
        if next(group) then result[scope]=group end
    end
    config.cornerLayouts=result
    return result
end
local function resolve(config,scope,point)
    local all=layouts(config)
    local shared=all.default[point] or {}
    local override=all[scope] and all[scope][point]
    local style={Point=point}
    for field,fallback in pairs(defaults) do
        local value=override and override[field]
        if value==nil then value=shared[field] end
        if value==nil then value=fallback end
        style[field]=value
    end
    return style
end
local directions={{-1,0},{1,0},{0,1},{0,-1}}
local function fixedStroke(region,style,path,height)
    local copies=region.bvStroke
    if style.Outline~="fixed" then
        if copies then for _,copy in ipairs(copies) do copy:Hide() end end
        return
    end
    local parent=region:GetParent()
    local pixel=1/(ns.DesignSystem.PerPixel(parent) or 1)
    if not copies then copies={};region.bvStroke=copies end
    for i,d in ipairs(directions) do
        local copy=copies[i]
        if not copy then copy=parent:CreateFontString(nil,"OVERLAY");copy:SetDrawLayer("OVERLAY",-1);copies[i]=copy end
        copy:SetFont(path,height,"");copy:ClearAllPoints()
        copy:SetPoint("CENTER",region,"CENTER",pixel*d[1],pixel*d[2])
        copy:SetTextColor(UI:RGBA(style.StrokeColor));copy:SetText(region:GetText());copy:Show()
    end
end
local function applyFont(region)
    local style=region.bvIconStyle
    if not style then return end
    local current,height,currentFlags=region:GetFont()
    local path=current
    if style.Font~="inherit" then path=ns.Media:Font(style.Font) end
    if not path then return end
    local flags=style.Outline=="normal" and "OUTLINE" or style.Outline=="thick" and "THICKOUTLINE" or ""
    if path~=current or (currentFlags or "")~=flags then region:SetFont(path,height,flags) end
    if style.Shadow then
        region:SetShadowColor(UI:RGBA(style.ShadowColor))
        region:SetShadowOffset(M.ToNative(style.ShadowX),M.ToNative(style.ShadowY))
    else region:SetShadowOffset(0,0);region:SetShadowColor(0,0,0,0) end
    fixedStroke(region,style,path,height)
end
local function paint(region,text,style,quality,categoryColor)
    if not text or not style or not style.Shown then
        region:SetText("");region.bvIconStyle=nil
        if region.bvStroke then for _,copy in ipairs(region.bvStroke) do copy:Hide() end end
        return
    end
    region.bvIconStyle=style
    if not region.bvAfterFont then region.bvAfterFont=function() applyFont(region) end end
    -- Resolve the suite font again when switching back from a custom face.
    if region.bvIconFace~=style.Font or region.bvFontSize~=style.Size then
        UI:GetStyle():Font(region,style.Size);region.bvIconFace=style.Font
    end
    local point=style.Point
    local x=(point:find("LEFT",1,true) and 1 or -1)+M.ToNative(style.X)
    local y=(point:find("TOP",1,true) and -1 or 1)+M.ToNative(style.Y)
    region:ClearAllPoints();region:SetPoint(point,region:GetParent(),point,x,y)
    local rgba=quality~=nil and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if style.Mode=="quality" and rgba then region:SetTextColor(rgba.r,rgba.g,rgba.b,1)
    elseif style.Mode=="category" and categoryColor then region:SetTextColor(UI:RGBA(categoryColor.."FF"))
    else region:SetTextColor(UI:RGBA(style.Color)) end
    region:SetText(text);applyFont(region)
    return point
end
local priceNames={vendor="Vendor sell",tsm="TSM market",buyout="TSM min buyout",auction="Auctionator",blackthorn="Blackthornes"}
local function compactMoney(copper)
    if copper<100 then return math.floor(copper).."c" end
    if copper<10000 then return math.floor(copper/100).."s" end
    local gold=copper/10000
    if gold>=1000 then return ("%.1f"):format(gold/1000):gsub("%.0$","").."kg" end
    return ("%.1f"):format(gold):gsub("%.0$","").."g"
end
local function unitPrice(source,item,cache)
    if item.samplePrices then return item.samplePrices[source] end
    if source=="vendor" then return item.vendor end
    if not item.id then return end
    cache.prices=cache.prices or {}
    local prices=cache.prices[item.id]
    if not prices then prices={};cache.prices[item.id]=prices end
    if prices[source]==nil then prices[source]=I:MarketQuote(source,item.id) or false end
    return prices[source]
end
local priority={"First","Second","Third"}
local function fitPriceRow(left,right,width)
    if not ((left and left.price) or (right and right.price)) then return end
    local function extent(region)
        if not region or not region.bvIconStyle then return 0 end
        return region:GetStringWidth()+math.abs(M.ToNative(region.bvIconStyle.X))
    end
    local used=extent(left)+extent(right)
    local ratio=(width-4)/math.max(1,used)
    if ratio>=1 then return end
    local function fit(region)
        if not region or not region.bvIconStyle then return end
        local size=math.max(6,math.floor(region.bvIconStyle.Size*ratio))
        if size<region.bvFontSize then UI:GetStyle():Font(region,size);applyFont(region) end
    end
    fit(left);fit(right)
end
local function content(source,item,quantity,binding,members,style,cache)
    if source=="binding" then return bindings[binding] end
    if source=="quantity" and quantity and quantity>1 then return tostring(quantity) end
    if source=="level" and (item.class==2 or item.class==4) and item.level and item.level>0 then return tostring(item.level) end
    if source=="stacks" and members and members>1 then return tostring(members) end
    if source=="junk" and item.quality==0 then return "Junk" end
    if source=="quest" then
        if item.class==12 then return "Quest" end
        if item.questMarker==nil and item.bag~=nil then
            local questInfo=I.API("GetContainerItemQuestInfo")
            local data=questInfo and questInfo(item.bag,item.slot)
            item.questMarker=type(data)=="table" and (data.isQuestItem or data.questID or data.isActive) or false
        end
        if item.questMarker then return "Quest" end
    end
    if source=="required" and item.required and item.required>0 then
        if cache.playerLevel==nil then cache.playerLevel=UnitLevel and UnitLevel("player") or 0 end
        if cache.playerLevel>0 and item.required>cache.playerLevel then return "Lv"..item.required end
    end
    if priceNames[source] then
        local cost=unitPrice(source,item,cache)
        if cost and cost>0 then
            local total=cost*(style.PriceBasis=="stack" and (quantity or 1) or 1)
            return compactMoney(total),total
        end
    end
end
function I:PaintIconLabels(button,item,quantity,binding,config,cache,iconSize)
    local scope=item.key or "default"
    cache=cache or {}
    iconSize=iconSize or config.slot or 32
    local cacheKey=scope.."/"..iconSize
    local styles=cache[cacheKey]
    if not styles then
        styles={};cache[cacheKey]=styles
        for _,point in ipairs(corners) do
            local style=resolve(config,scope,point)
            style.Size=math.max(6,math.floor(style.Size*iconSize/32+.5))
            styles[point]=style
        end
    end
    button.cornerText=button.cornerText or {}
    local group=self.lookup[scope] or self.lookup.misc
    for _,point in ipairs(corners) do
        local style=styles[point]
        local text,value,source
        if item.occupied and style.Shown then
            for _,field in ipairs(priority) do
                source=style[field]
                text,value=content(source,item,quantity,binding,button.members,style,cache)
                if text then break end
            end
        end
        local region=button.cornerText[point]
        if text and not region then
            region=UI:Label(button,"",style.Size,false);button.cornerText[point]=region
        end
        if region then
            region.price=value;region.priceSource=value and (priceNames[source].." / "..style.PriceBasis) or nil
            paint(region,text,style,item.quality,group and group.color)
        end
    end
    fitPriceRow(button.cornerText.TOPLEFT,button.cornerText.TOPRIGHT,iconSize)
    fitPriceRow(button.cornerText.BOTTOMLEFT,button.cornerText.BOTTOMRIGHT,iconSize)
end
function I:AddIconPriceTooltip(button,tooltip)
    for _,point in ipairs(corners) do
        local region=button.cornerText and button.cornerText[point]
        if region and region.price then
            tooltip:AddDoubleLine(region.priceSource,GetCoinTextureString and GetCoinTextureString(region.price) or region.price.."c")
        end
    end
end
local function options(...)
    local values={...};local result={}
    for i=1,#values,2 do result[#result+1]={value=values[i],label=values[i+1]} end
    return result
end
local sources=options("none","Empty","binding","Binding status","quantity","Quantity",
    "level","Item level","stacks","Stack count","quest","Quest item","required","Level needed","junk","Junk",
    "vendor","Vendor sell","tsm","TSM market","buyout","TSM min buyout","auction","Auctionator","blackthorn","Blackthornes")
local modes=options("custom","Custom color","quality","Item quality","category","Category accent")
local outlines=options("none","None","normal","Normal","thick","Thick","fixed","Fixed (1 pixel)")
local sourceLabel={}
for _,entry in ipairs(sources) do sourceLabel[entry.value]=entry.label end
local recipes={
    value={"tsm","auction","vendor"}, supplies={"quantity","stacks","none"},
    equipment={"binding","required","level"}, blackthorn={"blackthorn","auction","vendor"},
}
local function build()
    local w=UI:Window("BVInventoryIconLabels",740,470,{title="Inventory  /  Icon labels",compact=true,minWidth=740,minHeight=440})
    w:SetResizable(false);w.resizeGrip:Hide()
    UI:ScopeDialogEscape(w)
    local content=w.content
    local scope,key,tab="default","TOPLEFT","content"
    local rows={}
    local function caption(text,x,y,size,color)
        local s=UI:Label(content,text,size or 12,color or "muted");M.Point(s,"TOPLEFT",x,-y);return s
    end
    local function overrides()
        local group=layouts(I:Config())[scope]
        return scope~="default" and group and group[key] or nil
    end
    local function write(field,value)
        local groups=layouts(I:Config())
        groups[scope]=groups[scope] or {}
        local values=groups[scope][key] or {}
        groups[scope][key]=values;values[field]=value
        if not next(values) then groups[scope][key]=nil end
        if scope~="default" and not next(groups[scope]) then groups[scope]=nil end
    end
    local function set(field,value) write(field,value);w:Sync();I:Refresh() end
    local theme=UI:GetStyle()
    local function rule(parent,x,y,width,height,role,alpha)
        local line=parent:CreateTexture(nil,"BORDER")
        M.Point(line,"TOPLEFT",x,-y);M.Size(line,width,height)
        theme:Bind(function() line:SetColorTexture(theme:Color(role,alpha)) end,line)
        return line
    end
    local card=I:SettingsCards(w,284)
    card(content,6,3,267,71,25)
    card(content,6,79,267,140,26)
    card(content,6,232,267,173,31)
    card(content,294,3,431,97)
    local fields=card(content,294,105,431,214,29)
    M.Point(UI:Icon(content,"layout-grid",13,"accentText"),"TOPLEFT",16,-8)
    caption("INVENTORY LAYOUT",36,10,11,"accentText")
    w.scope=UI:Dropdown(content,247,{},function(value) scope=value;w:Sync() end)
    M.Point(w.scope,"TOPLEFT",16,-31)
    caption("Choose a corner",16,84,16,"text")
    w.cornerButtons={}
    for i,point in ipairs(corners) do
        local button=CreateFrame("Button",nil,content)
        w.cornerButtons[point]=button
        M.Size(button,121,48);M.Point(button,"TOPLEFT",16+((i-1)%2)*126,-108-math.floor((i-1)/2)*53)
        button.bg=button:CreateTexture(nil,"BACKGROUND");button.bg:SetAllPoints()
        button.name=UI:Label(button,cornerTitles[point],13,"text",true)
        M.Point(button.name,"TOPLEFT",10,-5)
        button.value=UI:Label(button,"",11,"muted");M.Point(button.value,"TOPLEFT",10,-25)
        button.mark=UI:Icon(button,"check",12,"accent");M.Point(button.mark,"TOPRIGHT",-6,-5)
        M.Width(button.value,105);button.value:SetWordWrap(false)
        local right=point:find("RIGHT",1,true);local bottom=point:find("BOTTOM",1,true)
        rule(button,right and 106 or 0,bottom and 46 or 0,15,2,"accent",1)
        rule(button,right and 119 or 0,bottom and 33 or 0,2,15,"accent",1)
        function button:Paint()
            self.bg:SetColorTexture(theme:Color(self.selected and "accent" or "muted",self.selected and .23 or self.hover and .14 or .075))
        end
        theme:Bind(function() button:Paint() end,button)
        button:SetScript("OnEnter",function() button.hover=true;button:Paint() end)
        button:SetScript("OnLeave",function() button.hover=false;button:Paint() end)
        button:SetScript("OnClick",function() key=point;w:Sync() end)
    end
    M.Point(UI:Icon(content,"eye",13,"accentText"),"TOPLEFT",16,-243)
    caption("LIVE SAMPLES",36,245,11,"accentText")
    local previewNote=caption("",16,350,12,"muted");M.Width(previewNote,246);previewNote:SetWordWrap(true)
    local heading=caption("",305,9,22,"text")
    local state=caption("",305,42,12,"muted")
    local preset=UI:Button(content,"Presets",100,function(anchor)
        UI:ContextMenu(anchor,options("value","Market / vendor fallback","blackthorn","Blackthornes first",
            "equipment","Equipment details","supplies","Stack quantities"),function(name)
            for i,field in ipairs(priority) do write(field,recipes[name][i]) end
            write("Shown",true);tab="content";w:Sync();I:Refresh()
        end)
    end)
    M.Point(preset,"TOPRIGHT",-15,-9)
    w.preset=preset
    local function makeTab(title,id,x,width)
        local t=UI:NavButton(content,title,width,function() tab=id;w:Sync() end,true)
        M.Height(t,30);M.Point(t,"TOPLEFT",x,-70)
        return t
    end
    local contentTab=makeTab("Contents","content",305,102)
    local mainTab=makeTab("Lettering","type",411,102)
    local effectsTab=makeTab("Effects","effects",517,90)
    w.effectsTab,w.typeTab,w.contentTab=effectsTab,mainTab,contentTab
    local section=caption("",305,114,11,"accentText")
    local function row(field,title,control,index,page,visible)
        local y=139+(index-1)*35
        M.Point(control,"TOPLEFT",474,-y)
        local reset=UI:IconButton(content,"undo-2",function() set(field,nil) end,"icon-only")
        M.Size(reset,23,24);M.Point(reset,"TOPLEFT",688,-y-2)
        UI:AttachTooltip(reset,"Inherit "..title:lower(),"Use the corresponding setting from All categories.")
        rows[#rows+1]={field=field,title=caption(title,305,y+6,13,"text"),control=control,reset=reset,page=page,visible=visible}
        return control
    end
    local function drop(field,title,items,index,page,visible)
        return row(field,title,UI:Dropdown(content,194,items,function(value) set(field,value) end),index,page,visible)
    end
    local function slider(field,title,min,max,index,page,visible)
        return row(field,title,UI:InlineSlider(content,193,min,max,1,"%d px",function(value) set(field,value) end),index,page,visible)
    end
    local function picker(field,title,index,page,visible)
        local input=UI:ColorInput(content,194,function(value) set(field,value) end)
        input.bvColorOptions={style=UI:GetStyle()}
        return row(field,title,input,index,page,visible)
    end
    w.showLabel=row("Shown","Show this corner",UI:Switch(content,true,function(value) set("Shown",value) end),1,"content")
    w.first=drop("First","First choice",sources,2,"content")
    w.second=drop("Second","If empty, try",sources,3,"content")
    w.third=drop("Third","Then try",sources,4,"content")
    local function usesPrice(s) return priceNames[s.First] or priceNames[s.Second] or priceNames[s.Third] end
    w.priceBasis=drop("PriceBasis","Value shown",options("unit","Per item","stack","Displayed stack"),5,"content",usesPrice)
    local hint=caption("",305,320)
    M.Width(hint,392);hint:SetWordWrap(true)
    local font=drop("Font","Font",ns.Media:FontOptions(true),2,"type")
    font:SetOptionsProvider(function() return ns.Media:FontOptions(true) end)
    w.size=slider("Size","Size at 32 px",7,22,3,"type")
    w.mode=drop("Mode","Text color",modes,5,"type")
    w.color=picker("Color","Custom color",6,"type",function(s) return s.Mode=="custom" end)
    w.outline=drop("Outline","Outline",outlines,1,"effects")
    picker("StrokeColor","Outline color",2,"effects",function(s) return s.Outline=="fixed" end)
    w.shadow=row("Shadow","Drop shadow",UI:Switch(content,true,function(value) set("Shadow",value) end),3,"effects")
    local function shadowOn(s) return s.Shadow end
    picker("ShadowColor","Shadow color",4,"effects",shadowOn)
    slider("ShadowX","Shadow X",-5,5,5,"effects",shadowOn)
    slider("ShadowY","Shadow Y",-5,5,6,"effects",shadowOn)
    slider("X","Text offset X",-12,12,7,"effects")
    slider("Y","Text offset Y",-12,12,8,"effects")
    local samples={}
    for i,name in ipairs({"Stack","Equipment","No quote"}) do
        local frame=CreateFrame("Frame",nil,content)
        local holder=UI:Panel(content,72,66,"raised",3,.6)
        M.Point(holder,"TOPLEFT",16+(i-1)*85,-268)
        frame:SetParent(holder);frame:SetPoint("CENTER")
        local icon=frame:CreateTexture(nil,"ARTWORK");icon:SetAllPoints();icon:SetTexCoord(.08,.92,.08,.92);frame.icon=icon
        local label=caption(name,16+(i-1)*85,337,11,"muted");M.Width(label,72);label:SetJustifyH("CENTER")
        samples[i]=frame
    end
    w.samples=samples
    w.reset=UI:Button(content,"Use defaults for corner",162,function()
        local groups=layouts(I:Config());local group=groups[scope]
        if group then group[key]=nil;if not next(group) then groups[scope]=nil end end
        w:Sync();I:Refresh()
    end)
    M.Point(w.reset,"BOTTOMRIGHT",-12,6)
    function w:Sync()
        local config=I:Config()
        if scope~="default" and not I.lookup[scope] then scope="default" end
        local scopes=options("default","All categories")
        for _,group in ipairs(I.order) do scopes[#scopes+1]={value=group.key,label=group.name} end
        self.scope:SetOptions(scopes);self.scope:SetValue(scope)
        for point,button in pairs(self.cornerButtons) do
            local current=resolve(config,scope,point)
            button.selected=point==key;button.mark:SetShown(button.selected);button:Paint()
            local first=current.First~="none" and current.First or current.Second~="none" and current.Second or current.Third
            button.value:SetText(current.Shown and sourceLabel[first] or "Hidden")
        end
        local value=resolve(config,scope,key)
        local own=overrides()
        local count,line=0,0
        for _,r in ipairs(rows) do
            local changed=own and own[r.field]~=nil
            if changed then count=count+1 end
            local visible=r.page==tab and (not r.visible or r.visible(value))
            r.title:SetShown(visible);r.control:SetShown(visible);r.reset:SetShown(visible and changed or false)
            if visible then
                local y=139+line*35;line=line+1
                r.title:ClearAllPoints();M.Point(r.title,"TOPLEFT",305,-y-6)
                r.control:ClearAllPoints();M.Point(r.control,"TOPLEFT",474,-y)
                r.reset:ClearAllPoints();M.Point(r.reset,"TOPLEFT",688,-y-2)
                r.control:SetValue(value[r.field])
            end
        end
        heading:SetText(cornerTitles[key]);section:SetText(tab=="content" and "FIRST AVAILABLE VALUE" or tab=="type" and "TEXT APPEARANCE" or "OUTLINE AND SHADOW")
        hint:SetShown(tab=="content")
        hint:ClearAllPoints();M.Point(hint,"TOPLEFT",305,-(146+35*line))
        hint:SetText(usesPrice(value) and "Missing quotes fall through. Hover an item in your bag for the exact price and source." or
            "The first matching value fills this corner. Quantity skips single items. Choose a preset to start a new order.")
        contentTab:SetSelected(tab=="content");mainTab:SetSelected(tab=="type");effectsTab:SetSelected(tab=="effects")
        M.Height(fields,38+line*35+(tab=="content" and 42 or 5))
        M.Height(self,math.max(456,207+line*35))
        state:SetText(scope=="default" and "Default for all categories" or count==0 and "Following all-category defaults" or count.." local settings / other values inherited")
        self.reset:SetShown(count>0)
        local group=I.lookup[scope]
        local textures={132889,135147,134400}
        local iconSize=config.categorySizes[scope] or config.slot or 32
        local qualities={1,3,4}
        previewNote:ClearAllPoints();M.Point(previewNote,"TOPLEFT",16,-360)
        previewNote:SetText(("At %d px icons, this corner uses %d px type. Prices shown are examples."):format(iconSize,math.max(6,math.floor(value.Size*iconSize/32+.5))))
        for i,frame in ipairs(samples) do
            frame:SetSize(iconSize,iconSize);frame.icon:SetTexture(textures[i])
            local item={occupied=true,key=scope,quality=qualities[i],class=i==1 and 7 or 4,level=i==1 and 1 or 54,
                samplePrices=i==3 and {} or {tsm=12345,auction=18100,buyout=23300,blackthorn=14500,vendor=75}}
            frame.members=i==1 and 10 or nil
            I:PaintIconLabels(frame,item,i==1 and 2000 or 1,({"","boe","bound"})[i],config,nil,iconSize)
        end
    end
    function w:OpenScope(category)
        scope=category or "default";tab="content";self:Sync()
        self:Show();UI:FocusWindow(self)
    end
    return w
end
function I:OpenIconLabels(category)
    self:Prepare()
    self.labelsWindow=self.labelsWindow or UI:WithStyle(UI:ToolStyle(),build)
    self.labelsWindow:OpenScope(category)
end
if ns.Settings.BeforeProfileChange then ns.Settings:BeforeProfileChange(corners,function()
    if I.labelsWindow then I.labelsWindow:Hide() end
end) end

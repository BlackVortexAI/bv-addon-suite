local ns=BVAddonSuiteCore
local I=ns and ns.Bags and ns.Bags.Inventory
if not I then return end
local UI,R,M=ns.UI,ns.Bags.InventoryRules,ns.DesignSystem.Metrics

-- Shared by the two Bags editors. Use the SettingsGrid card material and its
-- theme-controlled header artwork. Keep the cards behind the form controls.
function I:SettingsCards(window,sidebarWidth)
    local style=UI:GetStyle()
    local level=window.content:GetFrameLevel()
    window.content:SetFrameLevel(level+2)
    UI:WindowReadingSurface(window,style)
    ns.ShellMaterials:AttachEditorFrame(style,window)
    window.editorSurface=ns.InterfaceSurfaces:AttachEditor(style,window,sidebarWidth,level+1)
    return function(anchor,x,y,width,height,headerHeight)
        local card=style:Panel(window,width,height,"panel",3)
        card:SetFrameLevel(level);card:EnableMouse(false)
        M.Point(card,"TOPLEFT",anchor,"TOPLEFT",x,-y)
        if headerHeight then
            ns.InterfaceSurfaces:AttachHeader(style,card,headerHeight)
            local band=card:CreateTexture(nil,"ARTWORK")
            M.Point(band,"TOPLEFT",2,-2);M.Point(band,"TOPRIGHT",-2,-2);M.Height(band,headerHeight-2)
            local mark=card:CreateTexture(nil,"ARTWORK")
            M.Size(mark,2,12);M.Point(mark,"TOPLEFT",2,-(headerHeight-12)/2)
            style:Bind(function()
                band:SetColorTexture(style:Color("accent",.065))
                mark:SetColorTexture(style:Color("accent",.78))
            end,card)
            local rule=style:Rule(card)
            M.Point(rule,"TOPLEFT",1,-headerHeight);M.Point(rule,"TOPRIGHT",-1,-headerHeight)
        end
        return card
    end
end

local function choices(pairsList)
    local list={}
    for _,pair in ipairs(pairsList) do list[#list+1]={value=pair[1],label=pair[2]} end
    return list
end
local colors=choices({{"eab95a","Gold"},{"80a8df","Sky"},{"84c28b","Mint"},{"bd98d9","Violet"},{"e99285","Coral"},{"8ccccb","Ice"}})
local families={}
for _,group in ipairs(R.groups) do families[#families+1]={value=group.key,label=group.name} end
local fields={
    {"family","Category","gear",families},{"quality","Quality","2",choices({{"0","Poor"},{"1","Common"},{"2","Uncommon"},{"3","Rare"},{"4","Epic"},{"5","Legendary"},{"6","Artifact"},{"7","Heirloom"}})},
    {"name","Item name",""},{"count","Stack size","5"},{"bound","Binding","1",choices({{"1","Bound"},{"0","Unbound"}})},
    {"id","Item ID",""},{"level","Item level","1"},{"bag","Bag number","0"},
    {"type","Item type",""},{"subtype","Item subtype",""},{"equip","Equip slot",""},{"class","Class ID","0"},{"subclass","Subclass ID","0"}
}
local fieldByKey,fieldChoices={},{}
for _,f in ipairs(fields) do fieldByKey[f[1]]=f;fieldChoices[#fieldChoices+1]={value=f[1],label=f[2]} end
local textFields={name=true,type=true,subtype=true,equip=true}
local numeric=choices({{"=","is"},{">=","at least"},{"<=","at most"},{">","above"},{"<","below"},{"!=","is not"}})
local simple=choices({{":","is"},{"!:","is not"}})
local textOps=choices({{":","matches"},{"!:","excludes"}})
local examples={
    {label="Valuable equipment",source="family:gear; quality>=2",color="eab95a",icon="shield"},
    {label="Small material stacks",source="family:trade; count<5",color="84c28b",icon="layers"},
    {label="Spell supplies",source="id:6265 | id:17031 | id:17032",color="bd98d9",icon="spark"},
    {label="Potions by name",source="name:*potion* | name:*trank*",color="e99285",icon="search"}
}
local function ops(field)
    if field=="family" or field=="bound" then return simple end
    return textFields[field] and textOps or numeric
end
local function term(field)
    return {field=field,op=ops(field)[1].value,value=fieldByKey[field][3]}
end
local function decode(source)
    if not R.Compile(source) then return end
    local groups={}
    for part in (source.."|"):gmatch("(.-)|") do
        local group={}
        for s in (part..";"):gmatch("(.-);") do
            local neg,field,op,value=s:match("^%s*(!?)%s*(%a+)%s*([:<>!=]+)%s*(.-)%s*$")
            field=field:lower()
            if neg=="!" then op="!"..op end
            if not textFields[field] and field~="family" and field~="bound" and op==":" then op="=" end
            group[#group+1]={field=field,op=op,value=value}
        end
        groups[#groups+1]=group
    end
    return groups
end
local function encode(groups)
    local clauses={}
    for _,group in ipairs(groups) do
        local terms={}
        for _,t in ipairs(group) do
            if t.value=="" then return nil,"Choose a value for "..fieldByKey[t.field][2].."." end
            if t.value:find("[;|]") then return nil,"Use an alternative group for a second value." end
            local neg=t.op~="!=" and t.op:sub(1,1)=="!"
            terms[#terms+1]=(neg and "!" or "")..t.field..(neg and t.op:sub(2) or t.op)..t.value
        end
        clauses[#clauses+1]=table.concat(terms,"; ")
    end
    return table.concat(clauses," | ")
end
local function place(f,x,y,w,h)
    f:ClearAllPoints();M.Point(f,"TOPLEFT",x,-y)
    if w and h then M.Size(f,w,h) end
    return f
end
local function label(p,text,x,y,size,role,bold)
    return place(UI:Label(p,text,size,role,bold),x,y)
end
local function button(p,title,x,y,width,fn,primary)
    return place(UI:Button(p,title,width,fn,primary),x,y,width,28)
end
local function enable(control,on)
    if on then control:Enable() else control:Disable() end
end
local function line(p,x,y,w,h)
    local tex=p:CreateTexture(nil,"BACKGROUND");place(tex,x,y,w,h)
    local style=UI:GetStyle()
    style:Bind(function() tex:SetColorTexture(style:Color("muted",.28)) end,tex)
    return tex
end
local function scrolling(p,x,y,width,height)
    local view=place(CreateFrame("ScrollFrame",nil,p),x,y,width,height)
    local body=CreateFrame("Frame",nil,view);M.Size(body,width,1);view:SetScrollChild(body)
    view:EnableMouseWheel(true);view:SetScript("OnMouseWheel",function(f,d)
        f:SetVerticalScroll(math.max(0,math.min(f:GetVerticalScrollRange(),f:GetVerticalScroll()-d*32)))
    end)
    return view,body
end
local function libraryButton(parent)
    local b=CreateFrame("Button",nil,parent)
    local style=UI:GetStyle()
    b.line=b:CreateTexture(nil,"BACKGROUND");b.line:SetAllPoints()
    style:Bind(function() b.line:SetColorTexture(style:Color("accent",.23)) end,b)
    b.title=UI:Label(b,"",13);M.Point(b.title,"LEFT",7,0);M.Point(b.title,"RIGHT",-3,0);b.title:SetWordWrap(false)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
    b:SetScript("OnClick",function(s) s.pick() end)
    return b
end
local function build()
    local style=UI:GetStyle()
    local available=UIParent:GetHeight()
    local height=available>0 and math.min(698,math.max(544,M.ToDesign(available)*.88)) or 698
    local w=UI:Window("BVBagRuleEditor",790,height,{title="Inventory categories",minWidth=760,minHeight=544})
    w.minimize:Hide()
    UI:ScopeDialogEscape(w)
    local p=w.content
    local lower=CreateFrame("Frame",nil,p)
    M.Point(lower,"TOPLEFT",p,"BOTTOMLEFT",0,462)
    M.Point(lower,"BOTTOMRIGHT",p,"BOTTOMRIGHT",0,0)
    local card=I:SettingsCards(w,192)
    local libraryCard=card(p,5,4,181,124,25)
    local recipeCard=card(p,5,140,181,155,25)
    local properties=card(p,198,4,500,105,25)
    M.Point(properties,"TOPRIGHT",p,"TOPRIGHT",-9,-4)
    local conditions=card(p,198,118,500,260,38)
    M.Point(conditions,"BOTTOMRIGHT",lower,"TOPRIGHT",-9,-322)
    local matches=card(lower,198,330,500,76,29)
    M.Point(matches,"TOPRIGHT",lower,"TOPRIGHT",-9,-330)
    local left=14
    local x=207
    place(UI:Icon(p,"folder",13,"accentText"),left,11)
    label(p,"CATEGORIES",left+20,13,12,"accentText",true)
    w.create=button(p,"+ New category",left,37,162,function() w.switch(nil) end)
    local library,items=scrolling(p,left,73,162,160)
    local savedButtons={}
    local recipeIcon=UI:Icon(p,"sparkles",13,"accentText")
    local recipeTitle=label(p,"START FROM A RECIPE",left+20,249,12,"accentText",true)
    local recipeButtons={}
    for index,recipe in ipairs(examples) do
        local b=libraryButton(p);b.line:Hide();place(b,left,274+(index-1)*29,166,27)
        local glyph=UI:Icon(b,recipe.icon,15,"accentText");M.Point(glyph,"LEFT",3,0)
        b.title:ClearAllPoints();M.Point(b.title,"LEFT",26,0);M.Point(b.title,"RIGHT",-1,0)
        b.title:SetText(recipe.label);b.pick=function() w.switch(nil,recipe) end
        recipeButtons[index]=b
    end
    w.empty=label(items,"Saved categories appear here.",4,4,12,"muted")
    w.empty:SetWordWrap(true);M.Width(w.empty,144)
    label(p,"CATEGORY NAME",x,13,12,"accentText",true)
    w.nameBox=place(UI:Input(p,188),x,34,188,29)
    label(p,"ITEM SIZE",406,13,12,"accentText",true)
    w.size=place(UI:Dropdown(p,120,I:SizeOptions(),function(value)
        w.slotSize=value;w.preview()
    end),406,34,120,29)
    label(p,"ACCENT",540,13,12,"accentText",true)
    w.palette=place(UI:ColorPalette(p,colors,function(v) w.color=v;w.preview() end),540,36)
    w.builtinAccent=p:CreateTexture(nil,"ARTWORK");place(w.builtinAccent,540,41,18,18)
    w.iconButton=button(p,"Choose icon…",x,72,150,function()
        I:ChooseHeadingSymbol(w.nameBox:GetText()~="" and w.nameBox:GetText() or "New category",w.visibleSymbol,function(symbol)
            w.symbol=symbol;w.preview()
        end)
    end)
    w.iconButton:SetLabelInsets(32,6,"LEFT")
    w.iconPreview=w.iconButton:CreateTexture(nil,"OVERLAY")
    M.Size(w.iconPreview,18,18);M.Point(w.iconPreview,"LEFT",8,0)
    w.resetIcon=place(UI:IconButton(p,"rotate-ccw",function() w.symbol=nil;w.preview() end,"icon-only"),x+154,73,25,25)
    UI:AttachTooltip(w.resetIcon,"Use default category icon")
    label(p,"Heading",x+197,80,13,"muted")
    w.display=place(UI:Dropdown(p,160,choices({{"auto","Automatic"},{"both","Icon and label"},{"icon","Icon only"},{"label","Label only"}}),function(mode)
        w.displayMode=mode;w.preview()
    end),x+260,72,160,28)
    w.heading=label(p,"Match items",x,129,19,"text",true)
    w.mode=button(p,"Expression",581,124,108,function()
        if w.advanced then
            local groups=decode(w.rule:GetText())
            if not groups then w.preview();return end
            w.groups=groups
        else
            local source,err=encode(w.groups)
            if not source then w.result:SetText(err);return end
            w.rule:SetText(source)
        end
        w.advanced=not w.advanced;w.rebuild()
    end)
    w.hint=label(p,"Every condition in a group must match.",x,158,13,"muted")
    w.view,w.body=scrolling(p,x,183,485,133)
    w.rule=place(UI:Input(p,476),x,189,476,32);w.rule:SetMaxLetters(240)
    w.guide=label(p,"Use ; for AND, | for OR and * in names.",x,232,14,"muted")
    w.add=button(lower,"+ Condition",x,285,125,function()
        local group=w.groups[w.active];group[#group+1]=term("quality");w.rebuild(true)
    end)
    w.alternative=button(lower,"+ Alternative",x+134,285,140,function()
        w.groups[#w.groups+1]={term("family")};w.active=#w.groups;w.rebuild(true)
    end)
    label(lower,"IN YOUR BAGS",x,342,12,"accentText",true)
    w.result=label(lower,"",x,361,16,"text",true)
    w.track=button(lower,"Track item…",557,331,132,function(anchor)
        if w.previewMatch then I:ChooseStockItem(anchor,w.previewMatch) end
    end)
    w.hits=label(lower,"",x,384,13,"muted");M.Width(w.hits,473);w.hits:SetWordWrap(false)
    local samples={}
    for i=1,3 do
        local icon=lower:CreateTexture(nil,"ARTWORK")
        place(icon,x+(i-1)*23,383,19,19);icon:SetTexCoord(.07,.93,.07,.93);icon:Hide()
        samples[i]=icon
    end
    local footerRule=line(lower,8,410,678,1)
    M.Point(footerRule,"TOPRIGHT",lower,"TOPRIGHT",-9,-410)
    w.more=button(lower,"Manage",left,421,105,function(b)
        UI:ContextMenu(b,choices({{"up","Higher priority"},{"down","Lower priority"},{"delete","Delete category…"}}),function(k)
            if k=="delete" then
                UI:ContextMenu(b,choices({{"yes","Delete category and its assignments"}}),function() I:Alter(w.key,"delete");I:Edit() end)
            else I:Alter(w.key,k=="up" and -1 or 1);w.refreshLibrary();w.preview() end
        end)
    end)
    w.save=button(lower,"Save category",557,420,132,function()
        local source,err=w.source()
        if not source then w.result:SetText(err);return end
        local key,why=w.key
        if not w.builtin then key,why=I:SaveRule(key,w.nameBox:GetText(),source,w.color) end
        if not key then w.result:SetText(why);return end
        local cfg=I:Config()
        cfg.categorySizes[key]=tonumber(w.slotSize)
        local heading={symbol=w.symbol}
        if w.displayMode~="auto" then heading.mode=w.displayMode end
        cfg.categoryHeadings[key]=next(heading) and heading or nil
        I:Refresh();I:Edit(key)
    end,true)
    w.state=label(lower,"",x,428,13,"muted")
    function w.source()
        if w.advanced then return w.rule:GetText() end
        return encode(w.groups)
    end
    function w.preview()
        if w.loading then return end
        local source,err=w.source()
        local match
        if source then match,err=R.Compile(source) end
        local manual=I:Config().manual
        if w.builtin then match=function(item) return R.Classify(item,manual,I.rules)==w.key end end
        w.previewMatch=match
        w.visibleSymbol=I:CategorySymbol(w.key,{symbol=w.symbol},source)
        local path,l,r,t,b=ns.Symbols:Coords(w.visibleSymbol,16)
        w.iconPreview:SetTexture(path);if path then w.iconPreview:SetTexCoord(l,r,t,b) end
        w.iconPreview:SetVertexColor(UI:RGBA(w.color.."FF"))
        w.resetIcon:SetShown(w.symbol~=nil)
        w.track:Hide()
        local valid=match and w.nameBox:GetText():match("%S")
        enable(w.save,valid)
        w.dirty=w.nameBox:GetText()~=w.initialName or source~=w.initialSource or w.color~=w.initialColor or w.slotSize~=w.initialSize
            or w.symbol~=w.initialSymbol or w.displayMode~=w.initialDisplayMode
        w.state:SetText(w.dirty and "Unsaved changes" or w.key and "Saved category" or "Draft category")
        for _,icon in ipairs(samples) do icon:Hide() end
        if not match then w.result:SetText(err or "Choose a condition.");w.hits:SetText("");return end
        local count,wins,names,seen,sampleCount=0,0,{},{},0
        I:Each(function(item)
            if not item.occupied or not match(item) then return end
            count=count+1
            local claimed=manual[item.id]
            if not w.builtin then
                for _,r in ipairs(I.rules) do
                    if r.key==w.key then break end
                    if r.test and r.test(item) then claimed=true;break end
                end
            end
            if w.builtin or not claimed then wins=wins+1 end
            if item.name and not seen[item.name] and #names<4 then
                seen[item.name]=true;names[#names+1]=item.name
                if item.icon and sampleCount<#samples then
                    sampleCount=sampleCount+1;samples[sampleCount]:SetTexture(item.icon);samples[sampleCount]:Show()
                end
            end
        end)
        local result=count==0 and "No matching slots" or count.." matching "..(count==1 and "slot" or "slots")
        if count>wins then result=result.."  ·  "..(count-wins).." assigned elsewhere" end
        w.result:SetText(result)
        w.track:SetShown(count>0)
        place(w.hits,x+sampleCount*23,385);M.Width(w.hits,473-sampleCount*23)
        w.hits:SetText(#names>0 and table.concat(names,"  ·  ") or "The preview uses the items you are carrying.")
    end
    w.rows={};w.headers={}
    local function makeRow()
        local row=CreateFrame("Frame",nil,w.body)
        row.field=place(UI:Dropdown(row,131,fieldChoices,function(k)
            w.groups[row.g][row.i]=term(k);w.active=row.g;w.rebuild()
        end),0,0,132,26)
        row.operator=place(UI:Dropdown(row,127,{},function(v) row.term.op=v;w.active=row.g;w.preview() end),138,0,127,26)
        row.choice=place(UI:Dropdown(row,156,{},function(v) row.term.value=v;w.active=row.g;w.preview() end),271,0,156,26)
        row.input=place(UI:Input(row,156),271,0,156,26)
        row.pickItem=place(UI:IconButton(row,"search",function(anchor)
            local options,seen={},{}
            I:Each(function(item)
                if item.id and not seen[item.id] then
                    seen[item.id]=true
                    options[#options+1]={value=tostring(item.id),label=item.name or tostring(item.id),texture=item.icon,squarePreview=true}
                end
            end)
            table.sort(options,function(a,b) return a.label<b.label end)
            if #options>0 then UI:ContextMenu(anchor,options,function(id)
                row.term.value=id;row.input:SetText(id);w.preview()
            end) end
        end,"icon-only"),400,0,26,26)
        UI:AttachTooltip(row.pickItem,"Choose from your bags","Pick the item by name.")
        row.input:HookScript("OnTextChanged",function(b) if not w.rendering then row.term.value=b:GetText();w.active=row.g;w.preview() end end)
        row.remove=place(UI:IconButton(row,"close",function()
            local group=w.groups[row.g];table.remove(group,row.i)
            if #group==0 then table.remove(w.groups,row.g) end
            if #w.groups==0 then w.groups={{term("family")}} end
            w.active=math.min(#w.groups,row.g);w.rebuild()
        end),439,1,23,23)
        UI:AttachTooltip(row.remove,"Remove condition")
        return row
    end
    function w.rebuild(bottom)
        w.rendering=true
        local extra=math.max(0,M.GetWidth(w)-734)
        local visibleHeight=math.max(133,M.GetHeight(w)-411)
        M.Size(w.view,485+extra,visibleHeight)
        M.Width(w.body,485+extra)
        place(w.save,557+extra,420,132,28)
        place(w.mode,581+extra,124,108,28)
        M.Width(w.rule,476+extra)
        w.rule:SetShown(w.advanced);w.guide:SetShown(w.advanced);w.view:SetShown(not w.advanced)
        w.add:SetShown(not w.advanced);w.alternative:SetShown(not w.advanced)
        w.mode:SetText(w.advanced and "Visual editor" or "Expression")
        w.hint:SetText(w.advanced and "Edit the expression directly, then return to the visual editor." or "Match all conditions in any one group.")
        local y,idx,total=0,0,0
        for g,group in ipairs(w.groups) do
            local header=w.headers[g] or UI:WithStyle(style,libraryButton,w.body);w.headers[g]=header
            header.title:SetText(#w.groups==1 and "ALL CONDITIONS" or (g==1 and "GROUP 1" or "OR   ·   GROUP "..g))
            header.line:SetShown(w.active==g);header.pick=function() w.active=g;w.rebuild() end
            place(header,0,y,467+extra,19);header:Show();y=y+22
            for i,t in ipairs(group) do
                idx=idx+1;total=total+1
                local row=w.rows[idx] or UI:WithStyle(style,makeRow);w.rows[idx]=row
                row.g,row.i,row.term=g,i,t
                place(row,0,y,468+extra,27);row:Show();y=y+31
                row.field:SetValue(t.field)
                local opChoices={};local found=false
                for _,o in ipairs(ops(t.field)) do opChoices[#opChoices+1]=o;if o.value==t.op then found=true end end
                if not found then opChoices[#opChoices+1]={value=t.op,label="Custom ("..t.op..")"} end
                row.operator:SetOptions(opChoices);row.operator:SetValue(t.op)
                local options=fieldByKey[t.field][4]
                if options then
                    local list={};found=false
                    for _,o in ipairs(options) do list[#list+1]=o;if o.value==t.value then found=true end end
                    if not found then list[#list+1]={value=t.value,label=t.value} end
                    row.choice:SetOptions(list);row.choice:SetValue(t.value)
                else row.input:SetText(t.value) end
                row.choice:SetShown(options~=nil);row.input:SetShown(options==nil)
                row.pickItem:SetShown(t.field=="id");M.Width(row.input,(t.field=="id" and 124 or 156)+extra)
                M.Width(row.choice,156+extra)
                place(row.remove,439+extra,1,23,23)
                place(row.pickItem,400+extra,0,26,26)
                UI:AttachTooltip(row.input,fieldByKey[t.field][2],textFields[t.field] and "Enter a word or a pattern such as *potion*." or "Enter a whole number.")
            end
        end
        for i=idx+1,#w.rows do w.rows[i]:Hide() end
        for i=#w.groups+1,#w.headers do w.headers[i]:Hide() end
        M.Height(w.body,math.max(y,1));enable(w.add,total<16);enable(w.alternative,total<16)
        local top=math.max(0,M.ToNative(y-visibleHeight))
        w.up:SetShown(not w.advanced and top>0);w.down:SetShown(not w.advanced and top>0)
        w.view:SetVerticalScroll(bottom and top or math.min(w.view:GetVerticalScroll(),top))
        w.mode:SetShown(not w.builtin)
        w.heading:SetText(w.builtin and "Built-in category" or "Match items")
        if w.builtin then
            w.view:Hide();w.rule:Hide();w.guide:Hide();w.add:Hide();w.alternative:Hide();w.up:Hide();w.down:Hide()
            w.hint:SetText("Items are assigned automatically. Customize the category heading above.")
        end
        w.rendering=false;w.preview()
    end
    local function scrollBy(direction)
        local limit=math.max(0,w.body:GetHeight()-w.view:GetHeight())
        w.view:SetVerticalScroll(math.max(0,math.min(limit,w.view:GetVerticalScroll()+direction*75)))
    end
    w.up=button(lower,"Up",564,285,54,function() scrollBy(-1) end)
    w.down=button(lower,"Down",621,285,68,function() scrollBy(1) end)
    w:HookScript("OnSizeChanged",function() if w.groups and not w.rendering then w.rebuild() end end)
    function w.refreshLibrary()
        local categories=I.order
        w.empty:Hide();w.more:SetShown(w.key~=nil and not w.builtin)
        for i,r in ipairs(categories) do
            local b=savedButtons[i] or UI:WithStyle(style,libraryButton,items);savedButtons[i]=b
            place(b,0,(i-1)*27,159,26);b:Show();b.title:SetText(r.name)
            b.line:SetShown(r.key==w.key);b.pick=function() w.switch(r.key) end
        end
        for i=#categories+1,#savedButtons do savedButtons[i]:Hide() end
        M.Height(items,math.max(42,#categories*27))
        local visible=math.max(40,math.min(160,#categories*27))
        M.Height(library,visible)
        M.Height(libraryCard,74+visible)
        recipeCard:ClearAllPoints();M.Point(recipeCard,"TOPLEFT",p,"TOPLEFT",5,-(84+visible))
        M.Height(recipeCard,36+#recipeButtons*29)
        place(recipeIcon,left,91+visible)
        place(recipeTitle,left+20,93+visible)
        for i,b in ipairs(recipeButtons) do place(b,left,118+visible+(i-1)*29,166,27) end
    end
    function w.switch(key,recipe)
        if w.dirty then
            UI:ContextMenu(w.nameBox,choices({{"discard","Discard changes and continue"},{"keep","Keep editing"}}),function(k)
                if k=="discard" then I:Edit(key,recipe) end
            end)
        else I:Edit(key,recipe) end
    end
    w.rule:HookScript("OnTextChanged",function() if w.advanced then w.preview() end end)
    w.nameBox:HookScript("OnTextChanged",function() if w.groups then w.preview() end end)
    w:HookScript("OnHide",function() if I.headingWindow then I.headingWindow:Hide() end end)
    return w
end
function I:Edit(key,recipe)
    if #self.order==0 then self:Prepare() end
    if not self.editor then self.editor=UI:WithStyle(UI:ToolStyle(),build) end
    local w=self.editor;local r=recipe or (key and self.lookup[key])
    if self.headingWindow then self.headingWindow:Hide() end
    w.loading=true
    w.builtin=key~=nil and r~=nil and not r.source
    local saved=key and self:Config().categoryHeadings[key]
    w.symbol=saved and saved.symbol
    w.displayMode=saved and saved.mode or "auto"
    w.initialSymbol,w.initialDisplayMode=w.symbol,w.displayMode
    w.display:SetValue(w.displayMode)
    enable(w.nameBox,not w.builtin)
    w.palette:SetShown(not w.builtin)
    w.key=key;w.color=r and r.color or colors[1].value
    w.builtinAccent:SetShown(w.builtin)
    if w.builtin then w.builtinAccent:SetColorTexture(UI:RGBA(w.color.."FF")) end
    local source=r and r.source or "family:gear"
    -- The original equipment recipe expressed the same family as two alternatives.
    if source== "class:2; quality>=2 | class:4; quality>=2" then source="family:gear; quality>=2" end
    w.groups=decode(source);w.advanced=not w.groups;w.groups=w.groups or {{term("family")}}
    w.slotSize=key and self:Config().categorySizes[key] or "default";w.initialSize=w.slotSize;w.size:SetValue(w.slotSize)
    w.active=1;w.view:SetVerticalScroll(0)
    w.palette:SetValue(w.color);w.nameBox:SetText(r and (r.name or r.label) or "")
    w.rule:SetText(source)
    w.initialName,w.initialColor,w.initialSource=w.nameBox:GetText(),w.color,w.source()
    w.loading=false;w.refreshLibrary();w.rebuild();w:Show();UI:FocusWindow(w)
end
function I:OpenCategoryEditor(key)
    if self.editor and self.editor:IsShown() then self.editor.switch(key) else self:Edit(key) end
end

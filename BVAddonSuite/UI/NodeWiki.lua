-- Shared read-only reference tables. Providers supply prepared, plain English pages.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local WIDTH,HEIGHT,PAGE_SIZE=900,600,12
local nextWindowID=0
local function at(w,p,x,y)w:ClearAllPoints();M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y);return w end
local function literal(value)return type(value)=="string" and value:gsub("|","||") or "" end
local function fallback()
    return {title="Node wiki",selectedTopic="overview",topics={{value="overview",label="Overview"}},tables={{title="Reference",columns={{key="item",label="Item",width=.25},{key="meaning",label="Meaning",width=.75}},rows={{item="Node help",meaning="A reference for this node is not available yet."}}}}}
end
local function valid(page)
    if type(page)~="table" or getmetatable(page) or type(page.title)~="string" or type(page.topics)~="table" or #page.topics==0 or type(page.tables)~="table" or #page.tables==0 then return false end
    for _,topic in ipairs(page.topics)do if type(topic)~="table" or type(topic.value)~="string" or type(topic.label)~="string" then return false end end
    for _,t in ipairs(page.tables)do
        if type(t)~="table" or type(t.title)~="string" or type(t.columns)~="table" or #t.columns<1 or #t.columns>6 or type(t.rows)~="table" then return false end
        for _,c in ipairs(t.columns)do if type(c)~="table" or type(c.key)~="string" or type(c.label)~="string" then return false end end
        for _,row in ipairs(t.rows)do
            if type(row)~="table" then return false end
            for _,c in ipairs(t.columns)do if row[c.key]~=nil and type(row[c.key])~="string" then return false end end
        end
    end
    return true
end
local function clearView(view)
    view.title:Hide();view.title:SetText("");view.header:Hide()
    for _,label in ipairs(view.headers)do label:Hide();label:SetText("")end
    for _,row in ipairs(view.rows)do row.frame:Hide();for _,cell in ipairs(row.cells)do cell:Hide();cell:SetText("")end end
end
local function measure(label,text,width,size,bold)
    label:SetText(literal(text));label:SetJustifyV("TOP");label:SetWordWrap(true)
    ns.Theme:Font(label,M.ToNative(size),bold and ns.Theme:BoldFont() or nil)
    M.Width(label,width);M.Height(label,0)
    -- Keep all prepared text, including UTF-8. The estimate also protects mock and
    -- first-layout measurements before the native font renderer has settled.
    local lines=0
    for line in ((label:GetText() or "").."\n"):gmatch("(.-)\n")do
        local _,characters=line:gsub("[^\128-\191]","")
        lines=lines+math.max(1,math.ceil(characters/math.max(1,math.floor(width/(size*.55)))))
    end
    local height=math.max(size*1.3*lines,M.ToDesign(label:GetStringHeight()))
    M.Height(label,height);label:Show();return height
end
function UI:NodeWiki(owner,provider)
    local dialog=owner and owner.nodeWiki
    if not dialog then
        nextWindowID=nextWindowID+1
        dialog=self:Dialog("BVAddonSuiteNodeWiki"..nextWindowID,WIDTH,HEIGHT,owner)
        if owner then owner.nodeWiki=dialog end
        dialog.tableViews={};dialog.pageNumber=1;dialog.pageCount=1
        local p=dialog.content
        dialog.subtitle=at(self:Label(p,"",13,"muted"),p,20,10);dialog.subtitle:SetJustifyV("TOP")
        dialog.topicLabel=at(self:Label(p,"Topic",12,"muted"),p,20,48)
        dialog.topic=at(self:Dropdown(p,340,{},function(value)dialog:LoadTopic(value)end),p,20,68)
        dialog.filterLabel=at(self:Label(p,"Filter rows",12,"muted"),p,380,48)
        dialog.filter=at(self:Input(p,WIDTH-400,function()end),p,380,68);dialog.filter:SetMaxLetters(80)
        dialog.form=at(self:Form(p,WIDTH-40,HEIGHT-220,p),p,20,116);dialog.form:SetClipsChildren(true)
        dialog.previous=self:Button(p,"Previous",100,function()dialog:SetPage(dialog.pageNumber-1)end,"ghost")
        dialog.next=self:Button(p,"Next",100,function()dialog:SetPage(dialog.pageNumber+1)end,"ghost")
        dialog.pageLabel=self:Label(p,"",12,"muted");dialog.pageLabel:SetJustifyH("CENTER")
        dialog.notice=self:Label(p,"",12,"muted")
        function dialog:Layout()
            if not self.page then return end
            local width,height=M.GetWidth(self),M.GetHeight(self)
            M.Size(self.subtitle,width-40,34)
            local topicWidth=math.min(340,(width-60)*.45)
            M.Width(self.topic,topicWidth);at(self.filterLabel,p,40+topicWidth,48);at(self.filter,p,40+topicWidth,68);M.Width(self.filter,width-topicWidth-60)
            M.Size(self.form,width-62,height-220);M.Width(self.form.content,width-64);M.Height(self.form.slider,height-220)
            at(self.previous,p,20,height-94);at(self.next,p,width-120,height-94);M.Height(self.previous,28);M.Height(self.next,28)
            at(self.pageLabel,p,130,height-88);M.Size(self.pageLabel,width-260,20)
            at(self.notice,p,20,height-60);M.Size(self.notice,width-40,16);self.notice:SetText(literal(self.page.notice))
            local filtered={};local search=(self.filter:GetText() or ""):lower()
            for tableIndex,t in ipairs(self.page.tables)do
                for _,row in ipairs(t.rows)do
                    local matches=search==""
                    if not matches then for _,c in ipairs(t.columns)do if (row[c.key] or ""):lower():find(search,1,true)then matches=true;break end end end
                    if matches then filtered[#filtered+1]={tableIndex=tableIndex,row=row}end
                end
                if #t.rows==0 and search=="" then filtered[#filtered+1]={tableIndex=tableIndex,empty=t.emptyText or "No outputs are enabled. Choose a topic above for more information."}end
            end
            if #filtered==0 then filtered[1]={tableIndex=1,empty="No matching rows."}end
            self.filteredCount=#filtered;self.pageCount=math.max(1,math.ceil(#filtered/PAGE_SIZE));self.pageNumber=math.max(1,math.min(self.pageNumber or 1,self.pageCount))
            local first,last=(self.pageNumber-1)*PAGE_SIZE+1,math.min(#filtered,self.pageNumber*PAGE_SIZE)
            self.pageLabel:SetText("Page "..self.pageNumber.." / "..self.pageCount.."   ·   Rows "..first.."–"..last.." of "..#filtered)
            if self.pageNumber>1 then self.previous:Enable()else self.previous:Disable()end
            if self.pageNumber<self.pageCount then self.next:Enable()else self.next:Disable()end
            for _,view in ipairs(self.tableViews)do clearView(view)end
            local y,viewIndex,currentTable,rowIndex=0,0,nil,0
            local tableWidth=width-66;local view,columnWidths
            for index=first,last do
                local item=filtered[index];local t=self.page.tables[item.tableIndex]
                if currentTable~=item.tableIndex then
                    currentTable=item.tableIndex;viewIndex=viewIndex+1;rowIndex=0;view=self.tableViews[viewIndex]
                    if not view then
                        view={title=UI:Label(self.form.content,"",14,"accent",true),header=UI:Panel(self.form.content,tableWidth,36,"raised",nil,.65),headers={},rows={}}
                        self.tableViews[viewIndex]=view
                    end
                    at(view.title,self.form.content,0,y);y=y+measure(view.title,t.title,tableWidth,14,true)+8
                    columnWidths={};local total=0
                    for _,c in ipairs(t.columns)do local weight=type(c.width)=="number" and c.width>0 and c.width<math.huge and c.width or 1/#t.columns;columnWidths[#columnWidths+1]=weight;total=total+weight end
                    local x,headerHeight=0,32
                    for i,c in ipairs(t.columns)do
                        columnWidths[i]=tableWidth*columnWidths[i]/total
                        local label=view.headers[i] or UI:Label(view.header,"",12,"muted",true);view.headers[i]=label
                        at(label,view.header,x+10,8);headerHeight=math.max(headerHeight,measure(label,c.label,columnWidths[i]-20,12,true)+16);x=x+columnWidths[i]
                    end
                    at(view.header,self.form.content,0,y);M.Size(view.header,tableWidth,headerHeight);view.header:Show();y=y+headerHeight
                end
                rowIndex=rowIndex+1;local row=view.rows[rowIndex]
                if not row then
                    row={frame=UI:Panel(self.form.content,tableWidth,40,rowIndex%2==0 and "raised" or "panel",nil,.3),cells={}}
                    row.rule=UI:Rule(row.frame,tableWidth);view.rows[rowIndex]=row
                end
                at(row.frame,self.form.content,0,y);local x,rowHeight=0,40
                for i,c in ipairs(t.columns)do
                    local cell=row.cells[i] or UI:Label(row.frame,"",13,"text");row.cells[i]=cell
                    if item.empty and i>1 then cell:SetText("");cell:Hide()
                    else
                        local text=item.empty or item.row[c.key] or ""
                        at(cell,row.frame,x+10,8);rowHeight=math.max(rowHeight,measure(cell,text,(item.empty and tableWidth or columnWidths[i])-20,13)+16)
                    end
                    x=x+columnWidths[i]
                end
                M.Size(row.frame,tableWidth,rowHeight);row.frame:Show();at(row.rule,row.frame,0,rowHeight-1);M.Width(row.rule,tableWidth);y=y+rowHeight
                if index==last or filtered[index+1].tableIndex~=currentTable then y=y+18 end
            end
            self.form:SetContentHeight(y)
        end
        function dialog:SetPage(number)
            self.pageNumber=number;self:Layout();self.form.slider:SetValue(0)
        end
        function dialog:LoadTopic(topic)
            if not self.provider then return end
            local ok,page=pcall(self.provider,topic or "overview")
            if ok and page==nil then self:Hide();return end
            if not ok or not valid(page)then page=fallback()end
            self.page=page;self.title:SetText(literal(page.title));self.subtitle:SetText(literal(page.subtitle))
            local choices={};for _,item in ipairs(page.topics)do choices[#choices+1]={value=item.value,label=literal(item.label)}end
            self.topic:SetOptions(choices);self.topic:SetValue(page.selectedTopic or "overview")
            self.resetting=true;self.filter:SetText("");self.resetting=nil;self.pageNumber=1
            self:Layout();self.form.slider:SetValue(0)
        end
        dialog.filter:HookScript("OnTextChanged",function()if not dialog.resetting then dialog:SetPage(1)end end)
        function dialog:Open(nextProvider)
            self.provider=type(nextProvider)=="function" and nextProvider or fallback
            self:FitContent(WIDTH,HEIGHT);self:ClearAllPoints();M.Point(self,"CENTER",owner or UIParent,"CENTER",0,0)
            self:Show();self:LoadTopic("overview")
        end
        dialog:HookScript("OnHide",function()
            dialog.provider=nil;dialog.page=nil;dialog.pageNumber=1;dialog.pageCount=1;dialog.filteredCount=0
            dialog.title:SetText("");dialog.subtitle:SetText("");dialog.notice:SetText("");dialog.pageLabel:SetText("")
            dialog.topic:SetOptions({});dialog.topic:SetValue(nil);dialog.filter:ClearFocus();dialog.filter:SetText("")
            for _,view in ipairs(dialog.tableViews)do clearView(view)end
            dialog.form:SetContentHeight(0);dialog.form.slider:SetValue(0)
        end)
        dialog:HookScript("OnSizeChanged",function()dialog:Layout()end)
        self:Bind(dialog,function()if dialog:IsShown()then dialog:Layout()end end)
    end
    dialog:Open(provider);return dialog
end


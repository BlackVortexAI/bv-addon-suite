local _, ns = ...
local M = ns.DesignSystem.Metrics
local Lab = { state={theme="violet",scale=1,opacity=.96,page="components",zoom=1}, controls={} }
ns.UI.DesignLab = Lab
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,value)) end
local function at(frame,parent,x,y,width,height)
    frame:ClearAllPoints(); M.Point(frame,"TOPLEFT",parent,"TOPLEFT",x,-y)
    if width then M.Width(frame,width) end
    if height then M.Height(frame,height) end
end
local function geometry(frame)
    return {width=M.GetWidth(frame),height=M.GetHeight(frame),point={frame:GetPoint(1)}}
end
local function restoreGeometry(frame,value)
    if not value then return end
    frame:ClearAllPoints(); frame:SetPoint(unpack(value.point)); M.Size(frame,value.width,value.height)
end
function Lab:Status(text) if self.status then self.status:SetText(text) end end
function Lab:CloseTransient()
    if self.popup then self.popup:Hide() end
    if self.modal then self.modal:Hide() end
    self:HideTooltip()
    if self.factory then for _,edit in ipairs(self.factory.edits) do edit:ClearFocus() end end
end
function Lab:HideTooltip() if self.tooltip then self.tooltip:Hide() end end
function Lab:ShowTooltip(owner,title,body)
    if not self.tooltip then
        local tip=self.factory:Panel(self.window,280,84,"raised",6)
        tip:SetFrameStrata("TOOLTIP"); tip:SetClampedToScreen(true); tip:EnableMouse(false)
        tip.title=self.factory:Label(tip,"",15,"accent","bold"); at(tip.title,tip,12,10,256,20)
        tip.body=self.factory:Label(tip,"",13,"muted"); at(tip.body,tip,12,34,256,42); tip.body:SetJustifyV("TOP")
        self.tooltip=tip
    end
    local tip=self.tooltip; tip.title:SetText(title); tip.body:SetText(body)
    -- Measure the complete wrapped copy before fixing the text region heights.
    -- A long menu label must remain readable in its tooltip after truncation.
    tip.title:SetHeight(0); tip.body:SetHeight(0)
    local titleHeight=math.max(20,M.ToDesign(tip.title:GetStringHeight()))
    local bodyHeight=math.max(18,M.ToDesign(tip.body:GetStringHeight()))
    at(tip.title,tip,12,10,256,titleHeight)
    at(tip.body,tip,12,18+titleHeight,256,bodyHeight)
    M.Height(tip,30+titleHeight+bodyHeight); tip:ClearAllPoints(); M.Point(tip,"TOPLEFT",owner,"BOTTOMLEFT",0,-6); tip:Show()
end
function Lab:ShowDropdown(owner)
    self:HideTooltip()
    if self.popup and self.popup:IsShown() and self.popup.owner==owner then self.popup:Hide(); return end
    if not self.popup then
        local popup=CreateFrame("Frame",nil,self.window); popup:SetAllPoints(self.window); popup:SetFrameStrata("TOOLTIP")
        popup:EnableMouse(true); popup:SetScript("OnMouseDown",function() popup:Hide() end)
        popup.menu=self.factory:Panel(popup,200,120,"raised",6); popup.menu:SetClampedToScreen(true); popup.menu:EnableMouse(true)
        popup.rows={}; popup:Hide(); self.popup=popup
        popup:EnableKeyboard(true); popup:SetScript("OnKeyDown",function(_,key) popup:SetPropagateKeyboardInput(key~="ESCAPE"); if key=="ESCAPE" then popup:Hide() end end)
        popup:SetScript("OnShow",function()
            ns.Events:Subscribe(popup,"GLOBAL_MOUSE_DOWN",function()
                local foci=GetMouseFoci and GetMouseFoci() or {}
                if issecretvalue and issecretvalue(foci) then popup:Hide(); return end
                if canaccesstable and not canaccesstable(foci) then popup:Hide(); return end
                for _,focus in ipairs(foci) do
                    for _=1,64 do
                        if not focus or (issecretvalue and issecretvalue(focus)) then break end
                        if focus==self.window then return end
                        if not focus.GetParent or (focus.IsForbidden and focus:IsForbidden()) then break end
                        focus=focus:GetParent()
                    end
                end
                popup:Hide()
            end)
        end)
        popup:SetScript("OnHide",function() ns.Events:Release(popup) end)
    end
    local popup=self.popup; popup.owner=owner
    M.Size(popup.menu,math.max(180,M.GetWidth(owner)),#owner.options*34+12)
    popup.menu:ClearAllPoints(); M.Point(popup.menu,"TOPLEFT",owner,"BOTTOMLEFT",0,-4)
    for index,option in ipairs(owner.options) do
        local row=popup.rows[index]
        if not row then
            row=self.factory:Button(popup.menu,"",180,function(button)
                local target,choice=popup.owner,button.option
                popup:Hide(); target:SetValue(choice.value); if target.changed then target.changed(choice.value) end
            end)
            row.label:SetJustifyH("LEFT"); popup.rows[index]=row
        end
        row.option=option; row:SetLabelText(option.label); at(row,popup.menu,6,6+(index-1)*34,M.GetWidth(popup.menu)-12,32)
        row:SetSelected(owner.value==option.value); row:Show()
    end
    for i=#owner.options+1,#popup.rows do popup.rows[i]:Hide() end
    popup:Show()
end
function Lab:ShowDialog(title,body,action,callback)
    self:CloseTransient()
    if not self.modal then
        local overlay=CreateFrame("Frame",nil,self.window); overlay:SetAllPoints(self.window); overlay:SetFrameLevel(self.window:GetFrameLevel()+80)
        overlay:EnableMouse(true)
        overlay.dim=overlay:CreateTexture(nil,"BACKGROUND"); overlay.dim:SetAllPoints(); overlay.dim:SetColorTexture(.01,.01,.025,.65)
        overlay.panel=self.factory:Dialog(overlay,400,220); M.Point(overlay.panel,"CENTER"); overlay.panel:Show()
        overlay.panel.close:SetScript("OnClick",function() overlay:Hide() end)
        overlay.title=overlay.panel.title
        overlay.body=self.factory:Label(overlay.panel,"",14,"muted"); at(overlay.body,overlay.panel,20,66,360,80); overlay.body:SetJustifyV("TOP")
        overlay.cancel=self.factory:Button(overlay.panel,"Cancel",100,function() overlay:Hide() end); M.Point(overlay.cancel,"BOTTOMRIGHT",-136,18)
        overlay.confirm=self.factory:Button(overlay.panel,"Confirm",108,function() local fn=overlay.callback; overlay:Hide(); if fn then fn() end end,"primary"); M.Point(overlay.confirm,"BOTTOMRIGHT",-20,18)
        overlay:EnableKeyboard(true); overlay:SetScript("OnKeyDown",function(_,key) overlay:SetPropagateKeyboardInput(key~="ESCAPE"); if key=="ESCAPE" then overlay:Hide() end end)
        overlay:Hide(); self.modal=overlay
    end
    self.modal.callback=callback; self.modal.title:SetText(title); self.modal.body:SetText(body); self.modal.confirm:SetLabelText(action or "Understood")
    self.modal:Show()
end
function Lab:Section(parent,title,height)
    local f=self.factory
    local panel=f:Panel(parent,380,height,"panel",6,.66)
    panel.icon=f:Icon(panel,(title=="Inputs" and "text") or (title=="Switches & selection" and "sliders") or "spark",16,"accent"); at(panel.icon,panel,14,15)
    panel.title=f:Label(panel,title,17,"text","bold"); at(panel.title,panel,40,10,306,24)
    panel.rule=f:Rule(panel); M.Point(panel.rule,"TOPLEFT",1,-44); M.Point(panel.rule,"TOPRIGHT",-1,-44)
    panel.body=CreateFrame("Frame",nil,panel); M.Point(panel.body,"TOPLEFT",14,-54); M.Point(panel.body,"BOTTOMRIGHT",-14,14)
    return panel
end
function Lab:SetTheme(name)
    if not ns.DesignSystem.palettes[name] then return false end
    self.state.theme=name
    if self.factory then self.factory.theme=name; self.factory:Refresh(); self.controls.theme:SetValue(name) end
    self:Status("Theme: "..ns.DesignSystem.palettes[name].name); return true
end
function Lab:SetOpacity(value)
    self.state.opacity=clamp(tonumber(value) or .96,.80,1)
    if self.factory then self.factory.opacity=self.state.opacity; self.factory:Refresh(); self.controls.opacity:SetValue(self.state.opacity*100) end
end
function Lab:SetScale(value)
    self.state.scale=clamp(tonumber(value) or 1,.70,1.25)
    if not self.window then return end
    self:CloseTransient(); self.window:SetScale(self.state.scale)
    self.controls.scale:SetValue(self.state.scale*100); self.scaleValue:SetText(math.floor(self.state.scale*100+.5).."%")
    self:Fit(); self:Layout()
end
function Lab:Fit()
    if not self.window then return end
    local w=self.window
    local maxWidth=math.max(480,M.GetWidth(UIParent)/self.state.scale-32)
    local maxHeight=math.max(360,M.GetHeight(UIParent)/self.state.scale-32)
    if self.maximized and not self.minimized then
        w:ClearAllPoints(); M.Point(w,"CENTER"); M.Size(w,maxWidth,maxHeight)
    elseif not self.minimized then M.Size(w,math.min(M.GetWidth(w),maxWidth),math.min(M.GetHeight(w),maxHeight)) end
end
function Lab:SetPage(page)
    if page~="components" and page~="materials" and page~="nodes" then return end
    self.state.page=page; self.scrollOffset=0; self:CloseTransient()
    if self.window then
        for id,frame in pairs(self.pages) do frame:SetShown(id==page) end
        for id,button in pairs(self.tabs) do button:SetSelected(id==page); self.navigation[id]:SetSelected(id==page) end
        self.pageTitle:SetText(page=="components" and "The details make the difference." or page=="materials" and "Material with restraint." or "Connect your ideas.")
        self.pageEyebrow:SetText("BV DESIGN STUDIO / "..(page=="components" and "01" or page=="materials" and "02" or "03"))
        self.pageSubtitle:SetText(page=="components" and "One shared look. From the smallest switch to the entire window." or page=="materials" and "Tinted glass, soft gradients and just the right amount of light." or "The same design language. More room for your reactive graphs.")
        self:Layout()
    end
end
function Lab:ScrollTo(value)
    self.scrollOffset=clamp(value or 0,0,math.max(0,(self.contentHeight or 0)-M.GetHeight(self.scroll)))
    self.scroll:SetVerticalScroll(M.ToNative(self.scrollOffset))
    if not self.scrollUpdating then self.scrollUpdating=true; self.scrollbar:SetValue(self.scrollOffset); self.scrollUpdating=false end
    if self.popup then self.popup:Hide() end
    self:HideTooltip()
end
function Lab:SetZoom(value)
    self.state.zoom=clamp(tonumber(value) or 1,.6,1.4)
    if self.world then self.world:SetScale(self.state.zoom); self.controls.nodeZoomLabel:SetText(math.floor(self.state.zoom*100+.5).."%"); self:LayoutNodes() end
end
function Lab:LayoutNodes()
    if not self.world then return end
    M.Size(self.world,650,260)
    local area=self.canvas
    self.nodeScrollMax=math.max(0,260*self.state.zoom-M.GetHeight(area))
    self.nodeScroll=clamp(self.nodeScroll or 0,0,self.nodeScrollMax); area:SetVerticalScroll(M.ToNative(self.nodeScroll))
    self.nodeHorizontalMax=math.max(0,650*self.state.zoom-M.GetWidth(area))
    self.nodeHorizontal=clamp(self.nodeHorizontal or 0,0,self.nodeHorizontalMax); area:SetHorizontalScroll(M.ToNative(self.nodeHorizontal))
end
function Lab:CreateComponents()
    local f,c=self.factory,self.controls
    local page=self.pages.components
    local actions=self:Section(page,"Actions & states",194)
    c.primary=f:Button(actions.body,"Apply",108,function() self:Status("Preview applied - memory only") end,"primary")
    c.secondary=f:Button(actions.body,"Preview",108,function() self:Status("Preview ready") end)
    c.tooltip=f:IconButton(actions.body,"info",function() self:ShowDialog("A shared design language","Colors, materials and control geometry belong to one isolated UI study.","Understood") end)
    f:Tooltip(c.tooltip,"Useful details","Tooltips follow the current theme and global scale.")
    c.destructive=f:Button(actions.body,"Remove",108,function() self:ShowDialog("Remove the example?","This removes only a temporary example state. Your suite configuration stays untouched.","Remove",function() self:Status("Example removed") end) end,"danger")
    c.disabled=f:Button(actions.body,"Disabled",108); c.disabled:Disable()
    actions.caption=f:Label(actions.body,"Hover and pressed states use native input.",12,"muted")
    function actions:Arrange(width)
        at(c.primary,self.body,0,0,100); at(c.secondary,self.body,108,0,100); at(c.tooltip,self.body,216,0)
        at(c.destructive,self.body,0,44,100); at(c.disabled,self.body,108,44,100); at(self.caption,self.body,0,92,width-28,32)
    end
    local inputs=self:Section(page,"Inputs",388)
    local labels={}
    for i,text in ipairs({"Profile name","Trigger","Duration (seconds)","Description","Spell ID - validation example"}) do labels[i]=f:Label(inputs.body,text,13,"muted") end
    c.profileName=f:Input(inputs.body,300,false,"My adventure",function() self:Status("Unsaved example changes") end)
    c.trigger=f:Dropdown(inputs.body,160,{{value="aura",label="Aura active"},{value="health",label="Health below threshold"},{value="combat",label="In combat"}},"aura")
    c.duration= f:Input(inputs.body,64,false,"8",function(text,box) box:SetInvalid(not tonumber(text)) end)
    c.durationMinus=f:IconButton(inputs.body,"minus",function() c.duration:SetText(math.max(1,(tonumber(c.duration:GetText()) or 8)-1)) end)
    c.durationPlus=f:IconButton(inputs.body,"plus",function() c.duration:SetText(math.min(120,(tonumber(c.duration:GetText()) or 8)+1)) end)
    inputs.multiViewport=CreateFrame("ScrollFrame",nil,inputs.body); M.Size(inputs.multiViewport,300,72); inputs.multiViewport:SetClipsChildren(true)
    f:Skin(inputs.multiViewport,"bg",4,.85)
    c.multiline=f:Input(inputs.multiViewport,300,true,"Quiet hints. Clear, even in the middle of an adventure.",nil,true)
    M.Height(c.multiline,160); inputs.multiViewport:SetScrollChild(c.multiline)
    inputs.multiOffset=0; inputs.multiViewport:EnableMouseWheel(true)
    inputs.multiViewport:SetScript("OnMouseWheel",function(_,delta) inputs.multiOffset=clamp(inputs.multiOffset-delta*20,0,88); inputs.multiViewport:SetVerticalScroll(M.ToNative(inputs.multiOffset)) end)
    c.multiline:SetScript("OnCursorChanged",function(_,_,y,_,height)
        local pos=M.ToDesign(-y); height=M.ToDesign(height)
        if pos<inputs.multiOffset then inputs.multiOffset=pos elseif pos+height>inputs.multiOffset+72 then inputs.multiOffset=pos+height-72 end
        inputs.multiOffset=clamp(inputs.multiOffset,0,math.max(88,pos)); inputs.multiViewport:SetVerticalScroll(M.ToNative(inputs.multiOffset))
    end)
    c.spell=f:Input(inputs.body,300,false,"Aura",function(text,box) local number=tonumber(text); box:SetInvalid(not number or number<1 or number%1~=0) end); c.spell:SetInvalid(true)
    inputs.error=f:Label(inputs.body,"Enter a positive whole number.",12,"danger")
    function inputs:Arrange(width)
        local inner=width-28
        at(labels[1],self.body,0,0,inner,18); at(c.profileName,self.body,0,22,inner)
        at(labels[2],self.body,0,66,inner-142,18); at(c.trigger,self.body,0,88,inner-142)
        at(labels[3],self.body,inner-132,66,132,18); at(c.durationMinus,self.body,inner-132,88)
        at(c.duration,self.body,inner-98,88,64); at(c.durationPlus,self.body,inner-32,88)
        at(labels[4],self.body,0,132,inner,18); at(self.multiViewport,self.body,0,154,inner,72); M.Width(c.multiline,inner)
        at(labels[5],self.body,0,238,inner,18); at(c.spell,self.body,0,260,inner); at(self.error,self.body,0,298,inner,18)
    end
    local choices=self:Section(page,"Switches & selection",290)
    choices.label=f:Label(choices.body,"Enable module",14,"text"); choices.description=f:Label(choices.body,"A local visual example; no feature is activated.",12,"muted")
    c.switch=f:Switch(choices.body,true,function(v) self:Status(v and "Example enabled" or "Example disabled") end)
    c.checkbox=f:Check(choices.body,"Tooltips",true)
    c.gridCheck=f:Check(choices.body,"Snap to grid",false)
    c.radioLeft=f:Check(choices.body,"Left",true,function() c.radioCenter:SetValue(false) end,true)
    c.radioCenter=f:Check(choices.body,"Centered",false,function() c.radioLeft:SetValue(false) end,true)
    choices.strengthLabel=f:Label(choices.body,"Effect strength",13,"muted"); choices.strengthValue=f:Label(choices.body,"35%",13,"accent")
    c.strength=f:Slider(choices.body,260,0,100,1,35,function(v) choices.strengthValue:SetText(math.floor(v+.5).."%") end)
    function choices:Arrange(width)
        local inner=width-28
        at(self.label,self.body,0,0,inner-50,22); at(c.switch,self.body,inner-36,2)
        at(self.description,self.body,0,26,inner,32)
        at(c.checkbox,self.body,0,70,inner/2); at(c.gridCheck,self.body,inner/2,70,inner/2)
        at(c.radioLeft,self.body,0,108,inner/2); at(c.radioCenter,self.body,inner/2,108,inner/2)
        at(self.strengthLabel,self.body,0,150,inner-40,20); at(self.strengthValue,self.body,inner-38,150,38,20)
        at(c.strength,self.body,0,178,inner)
    end
    local feedback=self:Section(page,"Modules & feedback",352)
    c.search=f:Input(feedback.body,300,false,"")
    feedback.rows={}
    for i,item in ipairs({{"AuraStudio","Reactive graphs"},{"Experience Bar","Progress & rested experience"},{"Reputation Bar","The next standing"}}) do
        local row=CreateFrame("Frame",nil,feedback.body); M.Size(row,300,46)
        row.name=f:Label(row,item[1],14,"text"); at(row.name,row,0,0,210,21)
        row.detail=f:Label(row,item[2],12,"muted"); at(row.detail,row,0,23,230,18)
        row.state=f:Label(row,i==3 and "Inactive" or "Active",12,i==3 and "muted" or "success"); M.Point(row.state,"RIGHT"); row.state:SetJustifyH("RIGHT")
        feedback.rows[#feedback.rows+1]=row
    end
    c.search:SetScript("OnTextChanged",function()
        local query=c.search:GetText():lower()
        for _,row in ipairs(feedback.rows) do row:SetShown(query=="" or row.name:GetText():lower():find(query,1,true)~=nil) end
    end)
    feedback.progressLabel=f:Label(feedback.body,"Progress - 64%",13,"muted")
    c.progress=CreateFrame("Frame",nil,feedback.body); M.Size(c.progress,300,6)
    c.progress.track=c.progress:CreateTexture(nil,"BACKGROUND"); c.progress.track:SetAllPoints()
    c.progress.fill=c.progress:CreateTexture(nil,"ARTWORK"); M.Point(c.progress.fill,"TOPLEFT"); M.Point(c.progress.fill,"BOTTOMLEFT"); c.progress.value=.64
    f:Bind(function() c.progress.track:SetColorTexture(f:Color("edge",.3)); c.progress.fill:SetColorTexture(f:Color("accent")) end)
    c.dialog=f:Button(feedback.body,"Open dialog",120,function() self:ShowDialog("A place for clear decisions.","Native controls, a shared material and a clear primary action. No changes are saved.","Understood") end)
    function feedback:Arrange(width)
        local inner=width-28; at(c.search,self.body,0,0,inner)
        for i,row in ipairs(self.rows) do at(row,self.body,0,44+(i-1)*50,inner,46) end
        at(self.progressLabel,self.body,0,204,inner,20); at(c.progress,self.body,0,232,inner,6); M.Width(c.progress.fill,inner*.64)
        at(c.dialog,self.body,0,252,120)
    end
    local advanced=self:Section(page,"Sections & empty states",182)
    c.accordion=f:Button(advanced.body,"Advanced settings",180,function() self.advancedOpen=not self.advancedOpen; advanced.copy:SetShown(self.advancedOpen); self:Status(self.advancedOpen and "Section expanded" or "Section collapsed") end)
    advanced.copy=f:Label(advanced.body,"A quiet empty state. Create a collection when you need one.",14,"muted")
    self.advancedOpen=true
    function advanced:Arrange(width) at(c.accordion,self.body,0,0,width-28); at(self.copy,self.body,0,48,width-28,58) end
    self.componentSections={actions,inputs,choices,feedback,advanced}
end
function Lab:CreateMaterials()
    local f,c=self.factory,self.controls
    local page=self.pages.materials
    local panel=self:Section(page,"Material & atmosphere",330)
    panel.copy=f:Label(panel.body,"Tinted surfaces let the world show through. Text stays opaque; this study does not simulate a live backdrop blur.",14,"muted")
    panel.opacityLabel=f:Label(panel.body,"Window opacity",14,"text"); panel.opacityValue=f:Label(panel.body,"94%",13,"accent")
    c.opacity=f:Slider(panel.body,300,80,100,1,94,function(v)
        panel.opacityValue:SetText(math.floor(v+.5).."%")
        if math.abs(self.state.opacity-v/100)>.001 then self:SetOpacity(v/100) end
    end)
    panel.swatches={}
    for _,token in ipairs({"bg","panel","raised","accent","secondary"}) do
        local swatch=f:Panel(panel.body,60,60,token,5); swatch.caption=f:Label(swatch,token,12,"muted"); M.Point(swatch.caption,"TOP",swatch,"BOTTOM",0,-8)
        panel.swatches[#panel.swatches+1]=swatch
    end
    function panel:Arrange(width)
        local inner=width-28; at(self.copy,self.body,0,0,inner,60)
        at(self.opacityLabel,self.body,0,76,inner-45,22); at(self.opacityValue,self.body,inner-40,76,40,22)
        at(c.opacity,self.body,0,108,inner)
        local sw=(inner-32)/5
        for i,t in ipairs(self.swatches) do at(t,self.body,(i-1)*(sw+8),156,sw,60) end
    end
    -- In-game style families (Core 0.8.95): each family fixed, side by side.
    local styles=self:Section(page,"In-game styles",300)
    styles.copy=f:Label(styles.body,"Bars, roll bars, toasts and other elements you see while playing. Choose the suite's family under Appearance; a module can pick its own.",14,"muted")
    styles.samples={}
    for _,id in ipairs(ns.Styles.order) do
        local s=ns.Styles:Preview(id,self)
        local sample=s:Panel(styles.body,160,170,"bg",6)
        sample.style=s
        sample.title=s:Label(sample,ns.Styles.families[id].label,15,"text","bold")
        sample.text=s:Label(sample,ns.Styles:LevelText(id,80),12,"muted")
        sample.button=s:Button(sample,"Award",120,function() self:Status(ns.Styles.families[id].label..": button") end)
        sample.bar=CreateFrame("StatusBar",nil,sample);sample.bar:SetMinMaxValues(0,1);sample.bar:SetValue(.62)
        sample.bar:SetStatusBarTexture(ns.Styles:BarTexture(id));sample.bar:SetStatusBarColor(s:Color("accent"))
        sample.barBack=sample.bar:CreateTexture(nil,"BACKGROUND");sample.barBack:SetAllPoints(sample.bar);sample.barBack:SetColorTexture(0,0,0,.45)
        sample.barBorder=ns.Styles:Border(s,sample.bar)
        styles.samples[#styles.samples+1]=sample
    end
    function styles:Arrange(width)
        local inner=width-28; at(self.copy,self.body,0,0,inner,44)
        local count=#self.samples
        local sw=(inner-(count-1)*10)/count
        for i,sample in ipairs(self.samples) do
            at(sample,self.body,(i-1)*(sw+10),56,sw,170)
            at(sample.title,sample,12,10,sw-24,22)
            at(sample.text,sample,12,36,sw-24,18)
            at(sample.button,sample,12,64,math.min(120,sw-24),30)
            at(sample.bar,sample,12,110,sw-24,14)
        end
    end
    self.materialSections={panel,styles}
end
function Lab:CreateNodes()
    local f,c=self.factory,self.controls; local page=self.pages.nodes
    c.nodeAdd=f:Button(page,"Add node",120,function() self:ShowDialog("Node library","This isolated study contains two representative nodes. The production AuraStudio remains unchanged.","Understood") end,"primary")
    c.nodeTest=f:Button(page,"Test signal",112,function() self.nodeStatus:SetText("Output - test signal received"); self:Status("Local example: Your aura is active.") end)
    c.nodeZoomOut=f:IconButton(page,"minus",function() self:SetZoom(self.state.zoom-.1) end)
    c.nodeZoomIn=f:IconButton(page,"plus",function() self:SetZoom(self.state.zoom+.1) end)
    c.nodeZoomLabel=f:Label(page,"100%",13,"accent"); c.nodeZoomLabel:SetJustifyH("CENTER")
    self.canvas=CreateFrame("ScrollFrame",nil,page); M.Size(self.canvas,650,290); self.canvas:SetClipsChildren(true); f:Skin(self.canvas,"bg",6,.75)
    self.world=CreateFrame("Frame",nil,self.canvas); M.Size(self.world,650,260); self.canvas:SetScrollChild(self.world)
    self.canvas:EnableMouseWheel(true)
    self.canvas:SetScript("OnMouseWheel",function(_,delta)
        if IsControlKeyDown() then self:SetZoom(self.state.zoom+delta*.1)
        elseif IsShiftKeyDown() then self.nodeHorizontal=clamp((self.nodeHorizontal or 0)-delta*32,0,self.nodeHorizontalMax or 0); self.canvas:SetHorizontalScroll(M.ToNative(self.nodeHorizontal))
        else self.nodeScroll=clamp((self.nodeScroll or 0)-delta*28,0,self.nodeScrollMax or 0); self.canvas:SetVerticalScroll(M.ToNative(self.nodeScroll)) end
    end)
    self.nodeA=f:Panel(self.world,220,174,"panel",6); at(self.nodeA,self.world,22,24,220,174)
    self.nodeB=f:Panel(self.world,220,156,"panel",6); at(self.nodeB,self.world,356,76,220,156)
    local a=f:Label(self.nodeA,"Player Aura",16,"text","bold"); at(a,self.nodeA,14,10,190,28)
    local b=f:Label(self.nodeB,"Notification",16,"text","bold"); at(b,self.nodeB,14,10,190,28)
    local desc=f:Label(self.nodeA,"Aura / Spell",13,"muted"); at(desc,self.nodeA,14,68,190,20)
    c.nodeAura=f:Dropdown(self.nodeA,192,{{value="sample",label="Example aura"},{value="second",label="Another aura"}},"sample"); at(c.nodeAura,self.nodeA,14,94,192)
    local source=f:Label(self.nodeA,"Source - waiting for test signal",12,"muted"); at(source,self.nodeA,14,138,192,24)
    c.nodeMessage=f:Input(self.nodeB,192,false,"Your aura is active."); at(c.nodeMessage,self.nodeB,14,62,192)
    self.nodeStatus=f:Label(self.nodeB,"Output - local preview",12,"muted"); at(self.nodeStatus,self.nodeB,14,108,192,28)
    self.portA=f:GraphPort(self.nodeA); M.Point(self.portA,"CENTER",self.nodeA,"TOPRIGHT",0,-56)
    self.portB=f:GraphPort(self.nodeB); M.Point(self.portB,"CENTER",self.nodeB,"TOPLEFT",0,-48)
    self.portA:SetConnected(true); self.portB:SetConnected(true)
    self.graphWire=f:GraphWire(self.world)
    self.graphWire:SetEndpoints(242,80,356,124)
    self.wires=self.graphWire.segments
    self.nodeHint=f:Label(page,"Independent node zoom: Ctrl + wheel. Scroll vertically with wheel, horizontally with Shift + wheel.",13,"muted")
end
function Lab:Layout()
    if not self.window or self.layingOut then return end
    self.layingOut=true
    local w,h=M.GetWidth(self.window),M.GetHeight(self.window)
    M.Width(self.windowTitle,80); self.titleCaption:SetShown(w>=480)
    if self.minimized then self.layingOut=false; return end
    local compact=w<688; local side=compact and 58 or 200
    local stacked=w-side<650; local headerHeight=stacked and 174 or 116
    M.Width(self.sidebar,side); self.brand:SetShown(not compact); self.brandTagline:SetShown(not compact)
    self.profile:SetShown(not compact); self.navHeading:SetShown(not compact); self.treeHeading:SetShown(not compact)
    at(self.emblem,self.sidebar,compact and 13 or 12,20,compact and 32 or 44,compact and 32 or 44)
    for id,button in pairs(self.navigation) do
        M.Width(button,side-20); button.label:SetShown(not compact); button.navCount:SetShown(not compact)
        button.navIcon:ClearAllPoints(); M.Point(button.navIcon,"LEFT",compact and 11 or 9,0)
    end
    self.tree:SetShown(not compact and h>=594); self.treeHeading:SetShown(not compact and h>=594)
    self.header:ClearAllPoints(); M.Point(self.header,"TOPLEFT",self.window,"TOPLEFT",side,-44); M.Point(self.header,"TOPRIGHT",self.window,"TOPRIGHT",0,-44); M.Height(self.header,headerHeight)
    local mainWidth=w-side; local titleWidth=mainWidth-(stacked and 44 or 224)
    at(self.pageEyebrow,self.header,22,14,titleWidth,16)
    at(self.pageTitle,self.header,22,34,titleWidth,stacked and 60 or 38)
    at(self.pageSubtitle,self.header,22,stacked and 96 or 76,titleWidth,stacked and 30 or 26)
    if stacked then
        at(self.themeCaption,self.header,22,134,106,28); at(self.controls.theme,self.header,134,132,mainWidth-156,32)
    else
        at(self.themeCaption,self.header,mainWidth-192,29,170,18); at(self.controls.theme,self.header,mainWidth-192,51,170,32)
    end
    local tabTop=44+headerHeight
    self.tabRule:ClearAllPoints(); M.Point(self.tabRule,"TOPLEFT",self.window,"TOPLEFT",side,-tabTop-40); M.Point(self.tabRule,"TOPRIGHT",self.window,"TOPRIGHT",0,-tabTop-40)
    for i,id in ipairs({"components","materials","nodes"}) do at(self.tabs[id],self.window,side+22+(i-1)*106,tabTop,94,40) end
    local contentTop=tabTop+58
    self.scroll:ClearAllPoints(); M.Point(self.scroll,"TOPLEFT",self.window,"TOPLEFT",side+20,-contentTop); M.Point(self.scroll,"BOTTOMRIGHT",self.window,"BOTTOMRIGHT",-28,62)
    local inner=math.max(270,w-side-48)
    M.Width(self.content,inner)
    local contentHeight=1
    for id,page in pairs(self.pages) do M.Width(page,inner); M.Point(page,"TOPLEFT",self.content,"TOPLEFT",0,0) end
    if self.state.page=="components" or self.state.page=="materials" then
        local sections=self.state.page=="components" and self.componentSections or self.materialSections
        local two=self.state.page=="components" and inner>=720
        local columnWidth=two and (inner-16)/2 or inner
        local positions={0,0}
        for index,panel in ipairs(sections) do
            local col=two and ((index-1)%2+1) or 1
            at(panel,self.pages[self.state.page],(col-1)*(columnWidth+16),positions[col],columnWidth)
            M.Width(panel.title,columnWidth-54); panel:Arrange(columnWidth)
            positions[col]=positions[col]+M.GetHeight(panel)+16
        end
        contentHeight=math.max(positions[1],positions[2])
    else
        local c=self.controls
        at(c.nodeAdd,self.pages.nodes,0,0,120); at(c.nodeTest,self.pages.nodes,128,0,112)
        local zoomY=inner<430 and 42 or 0
        at(c.nodeZoomOut,self.pages.nodes,inner-132,zoomY); at(c.nodeZoomLabel,self.pages.nodes,inner-94,zoomY,56,32); at(c.nodeZoomIn,self.pages.nodes,inner-32,zoomY)
        at(self.canvas,self.pages.nodes,0,48+zoomY,inner,300)
        -- Horizontal graph overflow is deliberately scrollable, never rearranged.
        at(self.nodeHint,self.pages.nodes,0,364+zoomY,inner,48)
        self:LayoutNodes(); contentHeight=430+zoomY
    end
    self.contentHeight=contentHeight; M.Height(self.content,contentHeight)
    M.Height(self.pages[self.state.page],contentHeight)
    local viewport=math.max(1,h-contentTop-62)
    M.Size(self.scroll,inner,viewport)
    self.scrollbar:SetMinMaxValues(0,math.max(0,contentHeight-viewport)); self.scrollbar:SetShown(contentHeight>viewport)
    self:ScrollTo(self.scrollOffset or 0)
    M.Width(self.status,math.max(40,w-440)); self.scaleCaption:SetShown(w>=740)
    self.layingOut=false
end
function Lab:Build()
    local f=ns.DesignSystem:New(self); self.factory=f
    f.theme=self.state.theme; f.opacity=self.state.opacity
    local win=CreateFrame("Frame","BVAddonSuiteDesignLab",UIParent); self.window=win; win:Hide()
    M.Size(win,1120,760); M.Point(win,"CENTER"); win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:SetResizable(true); M.ResizeBounds(win,480,420); win:SetClampedToScreen(true); win:EnableMouse(true)
    local chrome=ns.UI:WindowChrome(win,f,{
        title="Addon Suite",caption="|   Design Studio",
        onClose=function() self:Close() end,
        onMaximize=function() self:Maximize() end,
        onMinimize=function() self:Minimize() end,
        onDragStart=function() if not self.maximized then self:CloseTransient(); win:StartMoving() end end,
        onResizeStart=function() if not self.maximized then self:CloseTransient(); win:StartSizing("BOTTOMRIGHT") end end,
        onResizeStop=function() win:StopMovingOrSizing(); self:Layout() end,
    })
    self.titlebar,self.windowTitle,self.titleCaption=chrome.titlebar,chrome.title,chrome.caption
    self.controls.close,self.controls.maximize,self.controls.minimize=chrome.close,chrome.maximize,chrome.minimize
    self.grip=chrome.grip
    self.body=CreateFrame("Frame",nil,win); self.body:SetAllPoints(win)
    self.sidebar=CreateFrame("Frame",nil,self.body); M.Width(self.sidebar,200); M.Point(self.sidebar,"TOPLEFT",0,-44); M.Point(self.sidebar,"BOTTOMLEFT",0,48)
    local sideTint=self.sidebar:CreateTexture(nil,"BACKGROUND"); sideTint:SetAllPoints(); sideTint:SetColorTexture(0,0,0,.08)
    local sideRule=f:Rule(self.sidebar); M.Width(sideRule,1); M.Point(sideRule,"TOPRIGHT"); M.Point(sideRule,"BOTTOMRIGHT")
    self.emblem=f:Logo(self.sidebar,44)
    self.brand=f:Label(self.sidebar,"Addon Suite",18,"text","display"); at(self.brand,self.sidebar,66,16,120,26)
    self.brandTagline=f:Label(self.sidebar,"YOUR WORLD.\nYOUR UI.",10,"muted"); at(self.brandTagline,self.sidebar,66,42,120,36)
    self.navHeading=f:Label(self.sidebar,"DESIGN SYSTEM",10,"muted"); at(self.navHeading,self.sidebar,18,94,166,16)
    self.profile=f:Label(self.sidebar,"Local preview\nNo saved configuration",12,"muted"); M.Point(self.profile,"BOTTOMLEFT",48,14); M.Width(self.profile,138); M.Height(self.profile,36)
    local profileRule=f:Rule(self.sidebar); M.Point(profileRule,"BOTTOMLEFT",10,62); M.Point(profileRule,"BOTTOMRIGHT",-10,62)
    self.avatar=f:Logo(self.sidebar,28); M.Point(self.avatar,"BOTTOMLEFT",15,19)
    self.navigation={}; self.tabs={}
    for i,def in ipairs({{"components","Components","grid"},{"materials","Appearance","spark"},{"nodes","AuraStudio","tree"}}) do
        local id=def[1]
        local nav=f:Button(self.sidebar,def[2],180,function() self:SetPage(id) end,"nav"); at(nav,self.sidebar,10,114+(i-1)*40,180,36)
        nav:SetLabelInsets(34,26,"LEFT")
        nav.navIcon=f:Icon(nav,def[3],16); M.Point(nav.navIcon,"LEFT",9,0)
        nav.navCount=f:Label(nav,"0"..i,10,"muted"); M.Point(nav.navCount,"RIGHT",-7,0)
        self.navigation[id]=nav; f:Tooltip(nav,def[2],"Open this design study page.")
        self.tabs[id]=f:Button(self.body,id=="materials" and "Materials" or id=="nodes" and "Node editor" or def[2],94,function() self:SetPage(id) end,"tab")
    end
    self.treeHeading=f:Label(self.sidebar,"COMPONENT TREE",10,"muted"); at(self.treeHeading,self.sidebar,18,254,164,18)
    self.tree=CreateFrame("Frame",nil,self.sidebar); at(self.tree,self.sidebar,18,278,164,142)
    self.controls.treeToggle=f:Button(self.tree,"Controls",164,function() self.treeExpanded=not self.treeExpanded; self.treeChildren:SetShown(self.treeExpanded) end,"ghost"); at(self.controls.treeToggle,self.tree,0,0,164,30)
    self.controls.treeToggle:SetLabelInsets(8,8,"LEFT"); f:Font(self.controls.treeToggle.label,13)
    self.treeChildren=CreateFrame("Frame",nil,self.tree); at(self.treeChildren,self.tree,10,34,154,104)
    local branch=f:Rule(self.treeChildren); M.Width(branch,1); M.Point(branch,"TOPLEFT"); M.Point(branch,"BOTTOMLEFT")
    local function jumpTo(section)
        self:SetPage("components")
        local offset=0
        for _,panel in ipairs(self.componentSections) do
            if panel==section then local _,_,_,_,y=panel:GetPoint(1); offset=M.ToDesign(-(y or 0)); break end
        end
        self:ScrollTo(offset)
    end
    local jump0=f:Button(self.treeChildren,"Buttons & states",148,function() jumpTo(self.componentSections[1]) end,"ghost"); at(jump0,self.treeChildren,6,0,148,30); jump0:SetLabelInsets(8,8,"LEFT"); f:Font(jump0.label,12)
    local jump=f:Button(self.treeChildren,"Inputs & selection",148,function() jumpTo(self.componentSections[2]) end,"ghost"); at(jump,self.treeChildren,6,32,148,30); jump:SetLabelInsets(8,8,"LEFT"); f:Font(jump.label,12)
    local jump2=f:Button(self.treeChildren,"Lists & feedback",148,function() jumpTo(self.componentSections[4]) end,"ghost"); at(jump2,self.treeChildren,6,64,148,30); jump2:SetLabelInsets(8,8,"LEFT"); f:Font(jump2.label,12)
    self.treeExpanded=true
    self.header=CreateFrame("Frame",nil,self.body)
    f:Gradient(self.header,"HORIZONTAL","accent",.055,"secondary",.035,1)
    local headerRule=f:Gradient(self.header,"HORIZONTAL","accent",.5,"secondary",.10,0)
    headerRule:ClearAllPoints(); M.Point(headerRule,"BOTTOMLEFT"); M.Point(headerRule,"BOTTOMRIGHT"); M.Height(headerRule,1)
    self.pageEyebrow=f:Label(self.header,"BV DESIGN STUDIO / 01",10,"accent")
    self.pageTitle=f:Label(self.header,"The details make the difference.",25,"text","display")
    self.pageSubtitle=f:Label(self.header,"One shared look. From the smallest switch to the entire window.",14,"muted")
    self.themeCaption=f:Label(self.header,"Material & color",12,"muted")
    self.controls.theme=f:Dropdown(self.header,170,{{value="violet",label="Arcane Violet"},{value="ember",label="Ember Atelier"},{value="tide",label="Moonlit Tide"}},"violet",function(value) self:SetTheme(value) end)
    self.tabRule=f:Rule(self.body)
    self.scroll=CreateFrame("ScrollFrame",nil,self.body); self.scroll:SetClipsChildren(true)
    self.content=CreateFrame("Frame",nil,self.scroll); M.Size(self.content,900,1200); self.scroll:SetScrollChild(self.content)
    self.scroll:EnableMouseWheel(true); self.scroll:SetScript("OnMouseWheel",function(_,delta) self:ScrollTo((self.scrollOffset or 0)-delta*48) end)
    self.scrollbar=f:Slider(self.body,8,0,100,1,0,function(value) if not self.scrollUpdating then self:ScrollTo(value) end end)
    self.scrollbar:SetOrientation("VERTICAL"); M.Point(self.scrollbar,"TOPRIGHT",self.scroll,"TOPRIGHT",14,0); M.Point(self.scrollbar,"BOTTOMRIGHT",self.scroll,"BOTTOMRIGHT",14,0); M.Width(self.scrollbar,8)
    self.scrollbar.track:ClearAllPoints(); M.Point(self.scrollbar.track,"TOP",0,0); M.Point(self.scrollbar.track,"BOTTOM",0,0); M.Width(self.scrollbar.track,3)
    M.Size(self.scrollbar:GetThumbTexture(),6,36)
    self.pages={}
    for _,id in ipairs({"components","materials","nodes"}) do self.pages[id]=CreateFrame("Frame",nil,self.content); M.Size(self.pages[id],900,1000); self.pages[id]:Hide() end
    self:CreateComponents(); self:CreateMaterials(); self:CreateNodes()
    self.footer=CreateFrame("Frame",nil,self.body); M.Point(self.footer,"BOTTOMLEFT"); M.Point(self.footer,"BOTTOMRIGHT"); M.Height(self.footer,48)
    local footerRule=f:Rule(self.footer); M.Point(footerRule,"TOPLEFT"); M.Point(footerRule,"TOPRIGHT")
    self.status=f:Label(self.footer,"Native design study - memory only",12,"muted"); M.Point(self.status,"LEFT",18,0); M.Height(self.status,30)
    self.controls.scale=f:Slider(self.footer,120,70,125,5,100,function(value) self.scaleValue:SetText(math.floor(value+.5).."%") end)
    M.Point(self.controls.scale,"RIGHT",-82,0)
    self.controls.scale:SetScript("OnMouseUp",function() self:SetScale(self.controls.scale:GetValue()/100) end)
    self.scaleValue=f:Label(self.footer,"100%",13,"accent"); M.Point(self.scaleValue,"RIGHT",-24,0); M.Width(self.scaleValue,48); self.scaleValue:SetJustifyH("RIGHT")
    self.scaleCaption=f:Label(self.footer,"UI scale",12,"muted"); M.Point(self.scaleCaption,"RIGHT",self.controls.scale,"LEFT",-10,0)
    win:HookScript("OnSizeChanged",function() self:Layout() end)
    win:SetScript("OnShow",function()
        ns.Events:Subscribe(self,"PLAYER_REGEN_DISABLED",function() self:Close(); ns:Print("Design Studio closed for combat. Reopen with /bvdesign afterward.") end)
        ns.Events:Subscribe(self,"DISPLAY_SIZE_CHANGED",function() self:Fit(); self:Layout() end)
        ns.Events:Subscribe(self,"UI_SCALE_CHANGED",function() self:Fit(); self:Layout() end)
    end)
    win:SetScript("OnHide",function() win:StopMovingOrSizing(); self:CloseTransient(); ns.Events:Release(self) end)
    ns.UI:ManageWindow(win); UISpecialFrames[#UISpecialFrames+1]="BVAddonSuiteDesignLab"
    self:SetTheme(self.state.theme); self:SetPage(self.state.page); self:SetScale(self.state.scale); self:SetZoom(self.state.zoom)
end
function Lab:Minimize()
    if self.minimized then
        self.minimized=false; M.ResizeBounds(self.window,480,420); restoreGeometry(self.window,self.beforeMinimize); self.body:Show(); self.grip:SetShown(not self.maximized); self:Fit(); self:Layout(); return
    end
    self:CloseTransient(); self.beforeMinimize=geometry(self.window); self.minimized=true
    self.body:Hide(); self.grip:Hide(); M.ResizeBounds(self.window,320,44); M.Size(self.window,352,44)
end
function Lab:Maximize()
    if self.minimized then self:Minimize() end
    self:CloseTransient(); M.ResizeBounds(self.window,480,420)
    if self.maximized then self.maximized=false; restoreGeometry(self.window,self.beforeMaximize)
    else self.beforeMaximize=geometry(self.window); self.maximized=true end
    self.grip:SetShown(not self.maximized); self:Fit(); self:Layout()
    self.controls.maximize.icon:SetShown(not self.maximized); self.controls.maximize.restoreIcon:SetShown(self.maximized)
end
function Lab:Open()
    if InCombatLockdown() then ns:Print("Design Studio cannot open during combat. Try /bvdesign afterward."); return false end
    if not self.window then self:Build() end
    if self.minimized then self:Minimize() end
    M.ResizeBounds(self.window,480,420); self:Fit(); self.window:Show(); ns.UI:FocusWindow(self.window); self:Layout()
    return true
end
function Lab:Close() if self.window then self.window:Hide() end end

SLASH_BVADDONSUITEDESIGN1="/bvdesign"
SlashCmdList.BVADDONSUITEDESIGN=function() ns:Call("DesignLab",function() Lab:Open() end) end

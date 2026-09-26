local _,ns=...
local UI=ns.UI
local D=ns.DesignSystem.Metrics
local Editor={pages={}}
ns.BarConfig=Editor
local function at(w,p,x,y) return UI:Place(w,p,x,y) end
local function choices(values)
    local out={}; for _,v in ipairs(values) do out[#out+1]={value=v,label=v} end; return out
end
function Editor:Refresh(kind)
    local p=self.pages[kind]; if not p then return end
    local cfg=ns.ProgressOptions:Get(kind); p.fieldIndex=math.min(p.fieldIndex,#cfg.fields)
    p.enabled:SetValue(cfg.enabled==true)
    local texture=ns.Media:StatusBar(cfg.texture=="inherit" and ns.Settings:Get("statusbar") or cfg.texture)
    p.barSample:SetStatusBarTexture(texture)
    p.barSample:SetStatusBarColor(UI:RGBA(cfg.color)); p.barSample:SetAlpha(cfg.opacity)
    for _,c in ipairs(p.controls) do c.widget:SetValue((c.field and cfg.fields[p.fieldIndex] or cfg)[c.key]) end
    for index,b in ipairs(p.fieldButtons) do
        local f=cfg.fields[index]; b:SetShown(f~=nil)
        if f then b:SetLabelText(index.."  "..f.template); b:SetSelected(index==p.fieldIndex) end
    end
    local sample={level="34",nextLevel="35",current="42000",max="65000",remaining="23000",percent="64.6",rested="12000",rate="38000",eta="36m",levelTime="1h 12m",sessionXP="24000",faction="Example faction",standing="Honored",status=""}
    p.sample:SetText("Example: "..ns.ProgressModel.Format(cfg.fields[p.fieldIndex].template,sample))
end
function Editor:Build(parent,kind)
    if self.pages[kind] then return self.pages[kind] end
    local p=at(UI:Panel(parent,880,497,"surface"),parent,0,0)
    UI:HideSurface(p)
    self.pages[kind]=p; p.fieldIndex=1; p.controls={}; p.fieldButtons={}; p.inputs={bar={},field={}}; p.selectedTab="appearance"
    local function changed()
        ns.ProgressBars:Refresh(kind); self:Refresh(kind)
        if ns.Config.window then ns.Config:Layout() end
    end
    at(UI:Label(p,"Module enabled",12,"muted"),p,0,4)
    p.enabled=at(UI:Switch(p,false,function(value) ns.Modules:SetEnabled(kind.."_bar",value); changed() end),p,113,2)
    local layoutButton=at(UI:Button(p,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:"..kind) end),p,710,-4)
    local pages={}
    for _,id in ipairs({"appearance","text","behavior"}) do
        local frame=at(UI:Panel(p,880,397,"surface"),p,0,48)
        UI:HideSurface(frame)
        pages[id]=frame; frame:SetShown(id=="appearance")
    end
    local definitions={{id="appearance",label="Appearance"},{id="text",label="Text fields"},{id="behavior",label="Behavior"}}
    local tabs
    local function select(id)
        for key,frame in pairs(pages) do frame:SetShown(key==id) end
        p.selectedTab=id; p.navigation.selected=id; tabs:SetValue(id)
        if ns.Config.window then ns.Config:Layout() end
    end
    -- Retain the host as an internal selection facade for existing consumers;
    -- visible navigation is rendered once by the configuration shell.
    tabs=UI:Tabs(p,definitions,select); tabs:Hide(); p.tabs=tabs
    p.navigation={definitions=definitions,selected="appearance",select=select}; tabs:SetValue("appearance")
    local function field(parent,title,key,isField,mode,x,y,width,options,maximum)
        local function set(value)
            local cfg=ns.ProgressOptions:Get(kind); local dest=isField and cfg.fields[p.fieldIndex] or cfg
            dest[key]=value; changed()
        end
        local control
        if mode=="number" then control=UI:NumberInput(parent,width,options,maximum,set)
        elseif mode=="choice" then control=UI:Dropdown(parent,width,options,set)
        elseif mode=="toggle" then control=UI:Switch(parent,false,set)
        elseif mode=="color" then control=UI:ColorInput(parent,width,set)
        else
            control=UI:Input(parent,width,set); control:SetMaxLetters(160)
            function control:SetValue(v) self:SetText(v) end
            control:SetScript("OnEditFocusLost",function(input) ns:Call("text field",set,input:GetText()) end)
        end
        if mode=="choice" and key=="font" then control:SetOptionsProvider(function()return ns.Media:FontOptions(true)end)
        elseif mode=="choice" and key=="texture" then control:SetOptionsProvider(function()return ns.Media:BarOptions(true)end) end
        p.controls[#p.controls+1]={widget=control,key=key,field=isField}
        p.inputs[isField and "field" or "bar"][key]=control
        return UI:Field(parent,title,control,x,y)
    end
    local appearance=pages.appearance
    local surface=at(UI:Section(appearance,"Surface",430,244),appearance,0,0)
    field(surface,"Texture","texture",false,"choice",16,57,398,ns.Media:BarOptions(true))
    field(surface,"Fill","color",false,"color",16,123,190)
    field(surface,"Background / dividers","background",false,"color",224,123,190)
    p.barSample=at(UI:StatusBar(surface,398,14),surface,16,205)
    UI.styled[p.barSample]=nil
    local shape=at(UI:Section(appearance,"Segmentation & opacity",430,244),appearance,450,0)
    field(shape,"Segments (1 = continuous)","segments",false,"number",16,57,190,1,40)
    field(shape,"Opacity (0.1 - 1)","opacity",false,"number",224,57,190,.1,1)
    if ns.ProgressBars.definitions[kind].supportsRested then
        field(shape,"Show rested XP","showRested",false,"toggle",16,137,36)
        field(shape,"Rested color","restedColor",false,"color",224,137,190)
    end
    local hint=at(UI:Section(appearance,"Position & size",880,106),appearance,0,264)
    local hintText=at(UI:Label(hint,"Arrange, resize and link elements together in the shared Layout Editor.",13,"muted"),hint,16,57)
    local behavior=at(UI:Section(pages.behavior,"Visibility",880,230),pages.behavior,0,0)
    field(behavior,"Hide when inactive / at maximum","hideInactive",false,"toggle",16,63,36)
    field(behavior,"Hide native Blizzard artwork","hideBlizzard",false,"toggle",450,63,36)
    local note=at(UI:Label(behavior,"Native XP hiding is not working reliably on the current test client. A fix is pending.",12,"muted"),behavior,16,153)
    D.Width(note,820)
    local text=pages.text
    local list=at(UI:Section(text,"Fields",210,397),text,0,0)
    for index=1,12 do
        local i=index
        local b=at(UI:NavButton(list,"",190,function()
            if UI.colorEditor then UI.colorEditor:Hide() end
            p.fieldIndex=i; self:Refresh(kind)
        end),list,10,45+(i-1)*25)
        D.Height(b,25); D.Height(b.mark,25); D.Height(b.label,23); p.fieldButtons[i]=b
    end
    local addField=at(UI:Button(list,"+ Add",88,function()
        local cfg=ns.ProgressOptions:Get(kind); if #cfg.fields>=12 then return end
        cfg.fields[#cfg.fields+1]={template="{percent}%"}; p.fieldIndex=#cfg.fields; changed()
    end),list,12,357)
    local removeField=at(UI:Button(list,"Remove",88,function()
        local cfg=ns.ProgressOptions:Get(kind); if #cfg.fields<=1 then return end
        table.remove(cfg.fields,p.fieldIndex); p.fieldIndex=1; changed()
    end),list,110,357)
    local inspect=at(UI:Section(text,"Selected text field",650,397),text,230,0)
    local template=field(inspect,"Text / variables","template",true,"text",16,49,618)
    UI:AttachTooltip(template,"Available variables","{level} {nextLevel} {current} {max} {remaining} {percent} {rested} {rate} {eta} {levelTime} {sessionXP} {faction} {standing} {status}")
    template:SetScript("OnEnter",function(input) UI:ShowTooltip(input) end)
    template:SetScript("OnLeave",function(input) UI:HideTooltip(input) end)
    field(inspect,"Font","font",true,"choice",16,110,300,ns.Media:FontOptions(true))
    field(inspect,"Size","size",true,"number",332,110,92,8,40)
    field(inspect,"Color","color",true,"color",440,110,194)
    field(inspect,"Text anchor","anchor",true,"choice",16,171,194,choices(ns.ProgressOptions.points))
    field(inspect,"Anchor on bar","relative",true,"choice",228,171,194,choices(ns.ProgressOptions.points))
    field(inspect,"Alignment","align",true,"choice",440,171,194,choices({"LEFT","CENTER","RIGHT"}))
    field(inspect,"Offset X","x",true,"number",16,232,140,-2000,2000)
    field(inspect,"Offset Y","y",true,"number",172,232,140,-2000,2000)
    field(inspect,"Text width","width",true,"number",328,232,140,20,1400)
    field(inspect,"Visible","enabled",true,"toggle",494,232,36)
    p.sample=at(UI:Label(inspect,"",14,"accent"),inspect,16,308); D.Size(p.sample,618,68)
    local function card(frame,x,y,width,height)
        at(frame,frame:GetParent(),x,y); UI:ResizeSection(frame,width,height)
    end
    local function place(control,x,y,width,labelWidth)
        local parent=control:GetParent()
        at(control.fieldLabel,parent,x,y); D.Size(control.fieldLabel,labelWidth or width,18)
        at(control,parent,x,y+21); D.Width(control,width)
    end
    function p:Arrange(width)
        self.layoutWidth=width
        at(layoutButton,self,width-170,-4); tabs:Arrange(width)
        for _,frame in pairs(pages) do D.Width(frame,width) end
        local two=width>=860; local column=two and (width-20)/2 or width
        local split=column>=400; local inner=column-32; local half=(inner-16)/2
        local surfaceHeight=split and 244 or 310
        card(surface,0,0,column,surfaceHeight)
        place(self.inputs.bar.texture,16,57,inner)
        place(self.inputs.bar.color,16,123,split and half or inner)
        place(self.inputs.bar.background,split and 32+half or 16,split and 123 or 189,split and half or inner)
        at(self.barSample,surface,16,surfaceHeight-39); D.Width(self.barSample,inner)
        local shapeY=two and 0 or surfaceHeight+20
        local shapeHeight=split and 244 or 350
        card(shape,two and column+20 or 0,shapeY,column,shapeHeight)
        place(self.inputs.bar.segments,16,57,split and half or inner)
        place(self.inputs.bar.opacity,split and 32+half or 16,split and 57 or 123,split and half or inner)
        if self.inputs.bar.showRested then
            place(self.inputs.bar.showRested,16,split and 137 or 189,36,split and half or inner)
            place(self.inputs.bar.restedColor,split and 32+half or 16,split and 137 or 255,split and half or inner)
        end
        local hintY=two and math.max(surfaceHeight,shapeHeight)+20 or shapeY+shapeHeight+20
        card(hint,0,hintY,width,118); D.Size(hintText,width-32,48)
        local appearanceHeight=hintY+118
        D.Height(appearance,appearanceHeight)

        local behaviorSplit=width>=720; local behaviorWidth=behaviorSplit and (width-48)/2 or width-32
        card(behavior,0,0,width,behaviorSplit and 244 or 310)
        place(self.inputs.bar.hideInactive,16,63,36,behaviorWidth)
        place(self.inputs.bar.hideBlizzard,behaviorSplit and width/2+8 or 16,behaviorSplit and 63 or 129,36,behaviorWidth)
        at(note,behavior,16,behaviorSplit and 153 or 219); D.Size(note,width-32,60)
        local behaviorHeight=D.GetHeight(behavior); D.Height(pages.behavior,behaviorHeight)

        local beside=width>=880; local listWidth=beside and 210 or width
        local listColumns=not beside and width>=500 and 2 or 1
        local count=#ns.ProgressOptions:Get(kind).fields
        local listRows=math.ceil(count/listColumns); local listHeight=45+listRows*28+56
        card(list,0,0,listWidth,listHeight)
        local buttonWidth=(listWidth-20-(listColumns-1)*10)/listColumns
        for index,button in ipairs(self.fieldButtons) do
            local col=(index-1)%listColumns; local row=math.floor((index-1)/listColumns)
            at(button,list,10+col*(buttonWidth+10),45+row*28); D.Width(button,buttonWidth)
        end
        at(addField,list,12,listHeight-40); at(removeField,list,110,listHeight-40)
        local inspectWidth=beside and width-230 or width
        local inspectY=beside and 0 or listHeight+20
        local fieldWidth=inspectWidth-32; local gap=16
        local columns=fieldWidth>=580 and 3 or 2
        local cell=(fieldWidth-(columns-1)*gap)/columns
        local f=self.inputs.field
        place(f.template,16,49,fieldWidth)
        local y=115
        if columns==3 then
            place(f.font,16,y,cell); place(f.size,32+cell,y,cell); place(f.color,48+2*cell,y,cell)
            y=y+66
        else
            place(f.font,16,y,fieldWidth); y=y+66
            place(f.size,16,y,cell); place(f.color,32+cell,y,cell); y=y+66
        end
        local keys={"anchor","relative","align","x","y","width","enabled"}
        for index,key in ipairs(keys) do
            local col=(index-1)%columns; local row=math.floor((index-1)/columns)
            place(f[key],16+col*(cell+gap),y+row*66,key=="enabled" and 36 or cell,cell)
        end
        local sampleY=y+math.ceil(#keys/columns)*66+4
        at(self.sample,inspect,16,sampleY); D.Size(self.sample,fieldWidth,68)
        local inspectHeight=sampleY+84
        card(inspect,beside and 230 or 0,inspectY,inspectWidth,inspectHeight)
        local textHeight=math.max(listHeight,inspectY+inspectHeight); D.Height(text,textHeight)
        local selectedHeight=self.selectedTab=="appearance" and appearanceHeight or self.selectedTab=="text" and textHeight or behaviorHeight
        D.Size(self,width,48+selectedHeight)
        return 48+selectedHeight
    end
    self:Refresh(kind); p:Arrange(880); return p
end

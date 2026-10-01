local _,ns=...
-- Explanations per setting key; {bar, text field} where a key exists in both.
local HELP={
    texture="Status bar texture of the fill. \"Inherit\" uses the texture from Global Settings.",
    color={"Color of the filled part of the bar.","Text color of this field."},
    background="Color of the empty part and of the dividers between segments.",
    showRested="Shows rested experience as a lighter section after the fill.",
    restedColor="Color of the rested section.",
    hideInactive="Hides the bar when there is nothing to show, for example at the level cap or without a watched faction.",
    template="Text of this field. Variables in braces are replaced; hover for the list.",
    font="Font of this field. \"Inherit\" uses the font from Global Settings.",
    size="Font size of this field.",
    enabled="Shows or hides this text field.",
    anchor="Point of the text that is attached to the bar.",
    relative="Point on the bar the text is attached to.",
    align="Alignment of the text inside its width.",
    width="Width available for the text; longer text is cut off.",
    x="Horizontal shift from the anchor point.",
    y="Vertical shift from the anchor point.",
}
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
-- Compact module page (0.8.71): a one-line module strip, then the selected tab
-- as SettingsGrid rows. The text tab keeps its field list beside the grid.
function Editor:Build(parent,kind)
    if self.pages[kind] then return self.pages[kind] end
    local p=at(UI:Panel(parent,880,497,"surface"),parent,0,0)
    UI:HideSurface(p)
    self.pages[kind]=p; p.fieldIndex=1; p.controls={}; p.fieldButtons={}; p.inputs={bar={},field={}}; p.selectedTab="appearance"
    local function changed()
        ns.ProgressBars:Refresh(kind); self:Refresh(kind)
        if ns.Config.window then ns.Config:Layout() end
    end
    local head=UI:SettingsGrid(p); p.head=head
    p.enabled=head:Row("Module enabled",UI:Switch(head,false,function(value) ns.Modules:SetEnabled(kind.."_bar",value); changed() end),
        {help="Shows this bar. Turning it off hides the bar and gives the area back to Blizzard's own bar."})
    local layoutButton=head:Row("Position & size",UI:Button(head,"Open Layout Editor",170,function() ns.LayoutEditor:Open("bv:"..kind) end),
        {help="Arrange, resize and link elements together in the shared Layout Editor."})
    local pages={}
    for _,id in ipairs({"appearance","text","behavior"}) do
        local frame=UI:Panel(p,880,397,"surface")
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
    local function field(grid,title,key,isField,mode,width,options,maximum,help)
        local function set(value)
            local cfg=ns.ProgressOptions:Get(kind); local dest=isField and cfg.fields[p.fieldIndex] or cfg
            dest[key]=value; changed()
        end
        local control
        if mode=="number" then control=UI:NumberInput(grid,width,options,maximum,set)
        elseif mode=="choice" then control=UI:Dropdown(grid,width,options,set)
        elseif mode=="toggle" then control=UI:Switch(grid,false,set)
        elseif mode=="color" then control=UI:ColorInput(grid,width,set)
        else
            control=UI:Input(grid,width,set); control:SetMaxLetters(160)
            function control:SetValue(v) self:SetText(v) end
            control:SetScript("OnEditFocusLost",function(input) ns:Call("text field",set,input:GetText()) end)
        end
        if mode=="choice" and key=="font" then control:SetOptionsProvider(function()return ns.Media:FontOptions(true)end)
        elseif mode=="choice" and key=="texture" then control:SetOptionsProvider(function()return ns.Media:BarOptions(true)end) end
        p.controls[#p.controls+1]={widget=control,key=key,field=isField}
        p.inputs[isField and "field" or "bar"][key]=control
        local text=HELP[key]
        if type(text)=="table" then text=text[isField and 2 or 1] end
        return grid:Row(title,control,{help=help or text,width=width,wide=mode=="text" or nil})
    end
    local a=UI:SettingsGrid(pages.appearance); p.appearanceGrid=a
    a:Section("surface","Surface")
    field(a,"Texture","texture",false,"choice",220,ns.Media:BarOptions(true))
    field(a,"Fill","color",false,"color",150)
    field(a,"Background / dividers","background",false,"color",150)
    p.barSample=a:Row("Preview",UI:StatusBar(a,220,12),{width=220,help="How the bar looks with the current texture and colors."})
    UI.styled[p.barSample]=nil
    a:Section("shape","Segmentation & opacity")
    field(a,"Segments","segments",false,"number",90,1,40,"1 = continuous bar.")
    field(a,"Opacity","opacity",false,"number",90,.1,1,"0.1 - 1")
    if ns.ProgressBars.definitions[kind].supportsRested then
        field(a,"Show rested XP","showRested",false,"toggle")
        field(a,"Rested color","restedColor",false,"color",150)
    end
    local b=UI:SettingsGrid(pages.behavior); p.behaviorGrid=b
    b:Section("visibility","Visibility")
    field(b,"Hide when inactive / at maximum","hideInactive",false,"toggle")
    field(b,"Hide native Blizzard artwork","hideBlizzard",false,"toggle",nil,nil,nil,
        "Native XP hiding is not working reliably on the current test client. A fix is pending.")
    local text=pages.text
    local list=UI:Panel(text,190,397,"panel",6,.5); p.fieldList=list
    local listTitle=at(UI:Label(list,"FIELDS",11,"accent",true),list,10,8)
    for index=1,12 do
        local i=index
        local button=at(UI:NavButton(list,"",170,function()
            if UI.colorPopup then UI.colorPopup:Hide() end
            p.fieldIndex=i; self:Refresh(kind)
        end),list,6,28+(i-1)*24)
        D.Height(button,22); D.Height(button.mark,22); D.Height(button.label,20); p.fieldButtons[i]=button
    end
    local addField=UI:Button(list,"+ Add",80,function()
        local cfg=ns.ProgressOptions:Get(kind); if #cfg.fields>=12 then return end
        cfg.fields[#cfg.fields+1]={template="{percent}%"}; p.fieldIndex=#cfg.fields; changed()
    end); D.Height(addField,24)
    local removeField=UI:Button(list,"Remove",80,function()
        local cfg=ns.ProgressOptions:Get(kind); if #cfg.fields<=1 then return end
        table.remove(cfg.fields,p.fieldIndex); p.fieldIndex=1; changed()
    end); D.Height(removeField,24)
    local t=UI:SettingsGrid(text); p.textGrid=t
    t:Section("field","Selected text field")
    local template=field(t,"Text / variables","template",true,"text",420)
    UI:AttachTooltip(template,"Available variables","{level} {nextLevel} {current} {max} {remaining} {percent} {rested} {rate} {eta} {levelTime} {sessionXP} {faction} {standing} {status}")
    template:SetScript("OnEnter",function(input) UI:ShowTooltip(input) end)
    template:SetScript("OnLeave",function(input) UI:HideTooltip(input) end)
    field(t,"Font","font",true,"choice",170,ns.Media:FontOptions(true))
    field(t,"Size","size",true,"number",70,8,40)
    field(t,"Color","color",true,"color",150)
    field(t,"Visible","enabled",true,"toggle")
    field(t,"Text anchor","anchor",true,"choice",130,choices(ns.ProgressOptions.points))
    field(t,"Anchor on bar","relative",true,"choice",130,choices(ns.ProgressOptions.points))
    field(t,"Alignment","align",true,"choice",130,choices({"LEFT","CENTER","RIGHT"}))
    field(t,"Text width","width",true,"number",80,20,1400)
    field(t,"Offset X","x",true,"number",80,-2000,2000)
    field(t,"Offset Y","y",true,"number",80,-2000,2000)
    p.sample=t:Block(UI:Label(t,"",13,"accent"),34)
    function p:Arrange(width)
        self.layoutWidth=width
        at(head,self,0,0); local headHeight=head:Arrange(width)
        for _,frame in pairs(pages) do at(frame,self,0,headHeight+10); D.Width(frame,width) end
        local appearanceHeight=a:Arrange(width); at(a,pages.appearance,0,0); D.Height(pages.appearance,appearanceHeight)
        local behaviorHeight=b:Arrange(width); at(b,pages.behavior,0,0); D.Height(pages.behavior,behaviorHeight)
        -- Text tab: field list beside the grid when there is room, above it otherwise.
        local beside=width>=700; local listWidth=beside and 190 or width
        local listColumns=not beside and width>=460 and 2 or 1
        local count=#ns.ProgressOptions:Get(kind).fields
        local listRows=math.ceil(count/listColumns); local listHeight=28+listRows*24+40
        at(list,text,0,0); D.Size(list,listWidth,listHeight)
        local buttonWidth=(listWidth-12-(listColumns-1)*8)/listColumns
        for index,button in ipairs(self.fieldButtons) do
            local col=(index-1)%listColumns; local row=math.floor((index-1)/listColumns)
            at(button,list,6+col*(buttonWidth+8),28+row*24); D.Width(button,buttonWidth)
        end
        at(addField,list,8,listHeight-32); at(removeField,list,96,listHeight-32)
        D.Width(listTitle,listWidth-20)
        local gridX=beside and 206 or 0; local gridY=beside and 0 or listHeight+10
        at(t,text,gridX,gridY)
        local textGridHeight=t:Arrange(width-gridX)
        local textHeight=math.max(listHeight,gridY+textGridHeight); D.Height(text,textHeight)
        local selectedHeight=self.selectedTab=="appearance" and appearanceHeight or self.selectedTab=="text" and textHeight or behaviorHeight
        local total=headHeight+10+selectedHeight
        D.Size(self,width,total)
        return total
    end
    self:Refresh(kind); p:Arrange(880); return p
end

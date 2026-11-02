local _,ns=...
local UI,L,D=ns.UI,ns.Layout,ns.DesignSystem.Metrics
local A,G=ns.LayoutEditorMaterials,ns.LayoutPlacement
local Presentation={}
ns.LayoutEditorPresentation=Presentation
local function finite(v)return type(v)=="number"and v==v and math.abs(v)<math.huge end
local function ratio(frame)return frame:GetEffectiveScale()/UIParent:GetEffectiveScale()end
local function place(frame,x,y)
    local scale=ratio(frame)
    frame:ClearAllPoints();frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",x/scale,-y/scale)
    frame.layoutOrigin=frame.layoutOrigin or {};frame.layoutOrigin.x=x;frame.layoutOrigin.y=y
end
local function box(frame)
    local left,bottom,w,h=frame:GetLeft(),frame:GetBottom(),frame:GetWidth(),frame:GetHeight();local scale=ratio(frame)
    if not finite(left)or not finite(bottom)then
        local origin=frame.layoutOrigin
        if origin then return {x=origin.x,y=origin.y,w=w*scale,h=h*scale}end
        return nil
    end
    return {x=left*scale,y=UIParent:GetHeight()-(bottom+h)*scale,w=w*scale,h=h*scale}
end
local function clamp(x,y,w,h)
    return math.max(8,math.min(math.max(8,UIParent:GetWidth()-w-8),x)),
        math.max(8,math.min(math.max(8,UIParent:GetHeight()-h-8),y))
end
local function raise(frame,level)
    frame:SetFrameLevel(level)
    for _,child in ipairs({frame:GetChildren()})do raise(child,level+1)end
end
function Presentation:Modal()
    local e=self.editor
    return e.confirm:IsShown()or e.deleteDialog:IsShown()or(e.cleanupDialog and e.cleanupDialog:IsShown())
end
function Presentation:UpdateModal()
    local e=self.editor;local top
    for _,dialog in ipairs({e.confirm,e.deleteDialog,e.cleanupDialog})do if dialog and dialog:IsShown()then top=dialog end end
    self.modalShield:SetShown(top~=nil)
    if top then self.modalShield:SetFrameLevel(top:GetFrameLevel()-1)end
end
function Presentation:PlaceToolbar(restore)
    local toolbar=self.console
    local previous=not restore and box(toolbar)
    UI:FitWindow(toolbar,910,44,ns.Settings:Get("scale"))
    local scale=ratio(toolbar);local w,h=toolbar:GetWidth()*scale,toolbar:GetHeight()*scale
    local x,y
    if restore then
        local saved=ns.Settings:Profile().layoutToolbar
        if saved and finite(saved.x)and finite(saved.y)then
            x=UIParent:GetWidth()/2+saved.x-w/2;y=UIParent:GetHeight()/2-saved.y-h/2
        else x=(UIParent:GetWidth()-w)/2;y=14 end
    elseif previous then x=previous.x+(previous.w-w)/2;y=previous.y+(previous.h-h)/2
    else x=(UIParent:GetWidth()-w)/2;y=14 end
    x,y=clamp(x,y,w,h);place(toolbar,x,y)
end
function Presentation:SaveToolbar()
    self.console:StopMovingOrSizing();self:PlaceToolbar(false)
    local b=box(self.console)
    ns.Settings:Profile().layoutToolbar={x=b.x+b.w/2-UIParent:GetWidth()/2,y=UIParent:GetHeight()/2-b.y-b.h/2}
    self:Refresh()
end
function Presentation:Open()
    self.expanded=false;self.tray:Hide();self.solveSignature=nil;self.manualInspector=nil;self.inspectorAnchor=nil
    self:PlaceToolbar(true)
end
function Presentation:CloseTools()
    if not self.tray:IsShown()then return false end
    self.tray:Hide();self.editor:Refresh();return true
end
function Presentation:PaintControls()
    local gold={self.style:Color("accentText")};local muted={self.style:Color("muted")}
    self.pigment:SetVertexColor(self.style:Color("accent"))
    for _,state in ipairs(self.states)do
        local b=state.button;local active=state.active()
        b.value:SetText(state.value())
        if b.glyph.SetColor then b.glyph.colorRole=active and "accentText"or "muted";b.glyph:SetColor(unpack(active and gold or muted))
        else b.glyph:SetVertexColor(unpack(active and gold or muted))end
        A.Rect(b,"active",30,38,b:GetWidth()-38,2,{gold[1],gold[2],gold[3],active and .85 or 0})
        A.Rect(b,"state",1,1,b:GetWidth()-2,38,{gold[1],gold[2],gold[3],b.pressed and .23 or b.hovered and .11 or 0},"BACKGROUND")
    end
end
function Presentation:Caption(id)
    local cap=self.chips[id]
    if cap then return cap end
    cap=CreateFrame("Frame",nil,self.root);cap:SetSize(210,23);cap.bvTooltipStyle=self.style
    local label=self.style:Label(cap,"",12,false,true);label:SetPoint("TOPLEFT",cap,"TOPLEFT",7,-3)
    label:SetHeight(18);label:SetWordWrap(false);cap.label=label;cap.lines={}
    for i=1,2 do local line=self.root:CreateLine(nil,"ARTWORK");line:SetThickness(1);cap.lines[i]=line end
    A.Rect(cap,"fill",0,0,210,23,A.Tint(self.style,"bg",{.045,.04,.03},.96),"BACKGROUND")
    A.Rect(cap,"rule",0,22,210,1,A.Accent(self.style,{.83,.66,.32},.3),"BORDER")
    label.bvAfterFont=function()
        label:SetTextColor(self.style:Color(id==self.editor.selected and "accentText" or "text"))
        if cap.fullText then self.style:FitCaption(label,cap.fullText,math.max(1,cap:GetWidth()-14))end
        self.solveSignature=nil
        if self.lastRects then self:Refresh(self.lastRects)end
    end
    UI:AttachTooltip(cap,"","Linked to the indicated element.")
    self.chips[id]=cap;return cap
end
-- Inspector anchoring is deliberately separate from collision-free caption placement.
-- Keep one side and attachment edge for both modes; other movers may be covered.
function Presentation:AnchorInspector(owner,pw,ph,reserveW,reserveH,gap,w,h)
    local margin=8
    local left=math.max(0,owner.x-margin)
    local right=math.max(0,w-margin-owner.x-owner.w)
    local old=self.inspectorAnchor
    local moved=not old or old.id~=owner.id or old.x~=owner.x or old.y~=owner.y
        or old.w~=owner.w or old.h~=owner.h or old.viewportW~=w or old.viewportH~=h
    local side=old and old.id==owner.id and old.side or nil
    if side=='right' and right<reserveW then side=nil end
    if side=='left' and left<reserveW then side=nil end
    if (side=='top' or side=='bottom') and (left>=reserveW or right>=reserveW) then side=nil end
    if not side then
        if right>=reserveW then side='right'
        elseif left>=reserveW then side='left'
        elseif owner.y+owner.h+gap+reserveH<=h-margin then side='bottom'
        else side='top' end
    end
    local y
    if side=='left' or side=='right' then y=owner.y
    elseif side=='bottom' then y=owner.y+owner.h+gap
    else y=owner.y-gap-reserveH end
    local _,top=clamp(0,y,reserveW,reserveH)
    -- Growing content may lift the shared top, but collapsing never moves it down.
    if not moved and old.side==side then top=math.min(top,old.top) end
    local x
    if side=='right' then x=owner.x+owner.w+math.min(gap,math.max(0,right-reserveW))
    elseif side=='left' then x=owner.x-math.min(gap,math.max(0,left-reserveW))-pw
    else x=owner.x end
    local maxHeight
    local toolbar=box(self.console)
    local unionX=side=='left' and x+pw-reserveW or x
    if toolbar and unionX<toolbar.x+toolbar.w+8 and unionX+reserveW>toolbar.x-8
        and top<toolbar.y+toolbar.h+8 and top+reserveH>toolbar.y-8 then
        local below=h-toolbar.y-toolbar.h-16
        local above=toolbar.y-16
        if below>=above then top=toolbar.y+toolbar.h+8;maxHeight=below
        else top=8;maxHeight=above end
        -- Only the full scroll viewport is shortened; no title or controls hidden.
        maxHeight=math.max(1,maxHeight);reserveH=math.min(reserveH,maxHeight)
    end
    maxHeight=math.min(maxHeight or h-8-top,h-8-top)
    x,y=clamp(x,top,pw,math.min(ph,maxHeight))
    self.inspectorAnchor={id=owner.id,side=side,top=y,x=owner.x,y=owner.y,w=owner.w,h=owner.h,viewportW=w,viewportH=h}
    return {x=x,y=y,w=pw,h=math.min(ph,maxHeight or ph),side=side,maxHeight=maxHeight}
end
function Presentation:Refresh(rects)
    local e=self.editor
    if self.refreshing or not e.active or e.suspended or e.inspectHidden then return end
    self.refreshing=true
    local w,h=UIParent:GetWidth(),UIParent:GetHeight()
    local chrome=e.toolbar:GetFrameLevel()
    e.toolbar:Hide()
    if self.chromeLevel~=chrome then
        raise(self.root,chrome+1);raise(self.tray,chrome+10);raise(self.compact,chrome+4);raise(e.inspector,chrome+3)
        self.chromeLevel=chrome
    end
    self:PlaceToolbar(false)
    UI:FitWindow(self.tray,414,294,ns.Settings:Get("scale"))
    local trayScale=ratio(self.tray);local tx,ty=clamp(w-750,80,414*trayScale,294*trayScale);place(self.tray,tx,ty)
    self:PaintControls();A.Surface(self.console,self.style);A.Surface(self.tray,self.style)
    for _,x in ipairs({64,181,294,420,556,714})do A.Rect(self.console,"group"..x,x,10,1,24,A.Accent(self.style,{.62,.53,.33},.28))end
    A.Rect(self.tray,"headerRule",18,38,378,1,A.Accent(self.style,{.65,.53,.31},.28))
    A.Grid(e)
    for _,cap in pairs(self.chips)do cap:Hide();for _,line in ipairs(cap.lines)do line:Hide()end end
    rects=rects or L:Resolve()
    local items,byId={},{}
    for _,id in ipairs(L.order)do
        local r,mover=rects[id],e.movers[id]
        if r and mover and mover:IsShown()then
            mover.title:Hide()
            local cap=self:Caption(id);cap.fullText=L.elements[id].label
            cap.label:SetText(cap.fullText)
            local wanted=math.max(70,math.min(250,cap.label:GetUnboundedStringWidth()+17))
            -- Use the actual editor handle (min16 / anchors32), not a zero-size
            -- saved layout footprint. Native world-space rectangles stay intact.
            local b=box(mover)
            if not b then
                local scale=ratio(mover);local mw,mh=mover:GetWidth()*scale,mover:GetHeight()*scale
                b={x=w/2+r.x-mw/2,y=h/2-r.y-mh/2,w=mw,h=mh}
            end
            local item={id=id,x=b.x,y=b.y,w=b.w,h=b.h,labelW=wanted,labelH=23,selected=id==e.selected}
            items[#items+1]=item;byId[id]=item
        end
    end
    local owner=byId[e.selected]
    self.compact:SetShown(owner~=nil and not self.expanded)
    e.inspector:SetShown(owner~=nil and self.expanded==true)
    local obstacles={box(self.console)}
    if self.tray:IsShown()then obstacles[#obstacles+1]=box(self.tray)end
    local panel=self.expanded and e.inspector or self.compact
    if self.manualInspector and self.manualInspector.id~=e.selected then self.manualInspector=nil end
    if owner then
        local r=rects[e.selected];local node=L:Get(e.selected)
        e.titleHandle.tooltipTitle="Move element inspector"
        e.titleHandle.tooltipBody=L.elements[e.selected].label.."\nDrag to move. Right-click the title to reset beside the selected element."
        e.titleHandle.tooltipText=e.titleHandle.tooltipBody
        self.style:FitCaption(self.compactTitle,L.elements[e.selected].label,245)
        self.coords:SetText(string.format("X  %.2f  |  Y  %.2f  px",r.x,r.y))
        self.links:SetText(string.format("%.0f x %.0f px   |   ",r.width,r.height)..(node.widthTarget and "W matched"or "Free width").." / "..(node.link and "Anchored"or "Free position"))
        local contentHeight=(e.stackOpen or e.preferencesOpen)and 306 or e.inspectorGridHeight
        local reserveHeight=math.max(e.inspectorGridHeight or 0,306)+88
        local full=e.inspector
        full:SetSize(D.ToNative(342),math.min(h<800 and 300 or h-115,D.ToNative(contentHeight+88)))
        UI:FitWindow(full,342,D.ToDesign(full:GetHeight()),ns.Settings:Get("scale"))
        UI:FitWindow(self.compact,D.ToDesign(304),D.ToDesign(150),ns.Settings:Get("scale"))
        if self.expanded then
            self.scroll:SetHeight(math.max(1,full:GetHeight()-D.ToNative(88)))
            self.scroll.slider:SetHeight(self.scroll:GetHeight())
            D.Height(e.inspectorContent,contentHeight);self.scroll:SetContentHeight(contentHeight)
            e.inspectorContent:ClearAllPoints();D.Point(e.inspectorContent,"TOPLEFT",self.scroll.content,"TOPLEFT",0,0)
            e.title:SetWidth(D.ToNative(265));self.style:FitCaption(e.title,L.elements[e.selected].label,D.ToNative(265))
        end
        local scale=ratio(panel);local pw,ph=panel:GetWidth()*scale,panel:GetHeight()*scale
        local selectedGap=ns.Settings:Get("inspectorGap")/UIParent:GetEffectiveScale()
        local manual=self.inspectorDragging and box(panel)or self.manualInspector
        local compactScale,fullScale=ratio(self.compact),ratio(full)
        -- FitWindow may scale a short Preferences panel wider than the long Layout
        -- panel. Reserve the largest possible width across both, not today's tab.
        local fullWidth=D.ToNative(342)
        local minHeight=math.min(h<800 and 300 or h-115,D.ToNative(math.min(e.inspectorGridHeight or 306,306)+88))
        local maxHeight=math.min(h<800 and 300 or h-115,D.ToNative(reserveHeight))
        local parentScale=fullScale/full:GetScale()
        local desired=ns.Settings:Get("scale")
        local maxScale=math.max(.1,math.min(desired,w*.94/fullWidth,h*.90/minHeight))*parentScale
        local heightScale=math.max(.1,math.min(desired,w*.94/fullWidth,h*.90/maxHeight))*parentScale
        local reserveW=math.max(self.compact:GetWidth()*compactScale,fullWidth*maxScale)
        local reserveH=math.min(h-16,math.max(self.compact:GetHeight()*compactScale,maxHeight*heightScale))
        local signature={w,h,e.selected,tostring(self.expanded),pw,ph,reserveW,reserveH,selectedGap,manual and manual.x or "",manual and manual.y or ""}
        for _,item in ipairs(items)do signature[#signature+1]=table.concat({item.id,item.x,item.y,item.w,item.h,item.labelW},",")end
        for _,item in ipairs(obstacles)do signature[#signature+1]=table.concat({item.x,item.y,item.w,item.h},",")end
        signature=table.concat(signature,";")
        if signature~=self.solveSignature then
            local blocks={};for _,b in ipairs(obstacles)do blocks[#blocks+1]=b end
            for _,b in ipairs(items)do
                if b.id==e.selected then
                    local extra=math.max(0,selectedGap-8)
                    blocks[#blocks+1]={x=b.x-extra,y=b.y-extra,w=b.w+extra*2,h=b.h+extra*2}
                else blocks[#blocks+1]=b end
            end
            self.panelObstacles=blocks;self.selectedGap=selectedGap
            if manual then
                local x,y=clamp(manual.x,manual.y,pw,ph)
                self.panelPlacement={x=x,y=y,w=pw,h=ph}
            else
                self.panelPlacement=self:AnchorInspector(owner,pw,ph,reserveW,reserveH,selectedGap,w,h)
            end
            if self.inspectorDragging then self.panelPlacement=box(panel)end
            obstacles[#obstacles+1]=self.panelPlacement
            self.placements=G.placeCaptions(items,obstacles,{w=w,h=h},{gap=7,margin=10})
            self.solveSignature=signature;self.solveCount=(self.solveCount or 0)+1
        else obstacles[#obstacles+1]=self.panelPlacement end
        if self.panelPlacement.maxHeight then
            local compactHeight=self.compact:GetHeight()*ratio(self.compact)
            if compactHeight>self.panelPlacement.maxHeight then
                self.compact:SetScale(self.compact:GetScale()*self.panelPlacement.maxHeight/compactHeight)
                if panel==self.compact then
                    local width=self.compact:GetWidth()*ratio(self.compact)
                    if self.panelPlacement.side=='left' then
                        self.panelPlacement.x=self.panelPlacement.x+self.panelPlacement.w-width
                    end
                    self.panelPlacement.w=width
                    self.panelPlacement.h=self.compact:GetHeight()*ratio(self.compact)
                end
            end
            local maxHeight=self.panelPlacement.maxHeight/fullScale
            if full:GetHeight()>maxHeight then
                full:SetHeight(maxHeight)
                self.scroll:SetHeight(math.max(1,maxHeight-D.ToNative(88)))
                self.scroll.slider:SetHeight(self.scroll:GetHeight())
                self.scroll:SetContentHeight(contentHeight)
            end
        end
        if not self.inspectorDragging then place(panel,self.panelPlacement.x,self.panelPlacement.y)end
        A.Surface(panel,self.style)
    else
        self.solveSignature=nil;self.panelPlacement=nil
        self.placements=G.placeCaptions(items,obstacles,{w=w,h=h},{gap=7,margin=10})
    end
    local gold={self.style:Color("accentText")}
    for id,pos in pairs(self.placements or {})do
        local cap=self.chips[id];cap:SetSize(pos.w,pos.h);place(cap,pos.x,pos.y)
        cap.label:SetWidth(math.max(1,pos.w-14));self.style:FitCaption(cap.label,cap.fullText,math.max(1,pos.w-14))
        cap.label:SetTextColor(self.style:Color(id==e.selected and "accentText"or "text"))
        A.Rect(cap,"fill",0,0,pos.w,pos.h,A.Tint(self.style,"bg",{.045,.04,.03},.96),"BACKGROUND")
        A.Rect(cap,"rule",0,22,pos.w,1,A.Accent(self.style,{.83,.66,.32},.3),"BORDER")
        cap:SetShown(e.overlays);cap:SetAlpha(e.focus and id~=e.selected and .35 or 1)
        cap.tooltipTitle=cap.fullText;cap.tooltipBody=pos.clear and "Linked to the indicated element."or "Dense layout: label clearance is limited."
        for i,line in ipairs(cap.lines)do
            local segment=pos.leader.segments[i]
            line:SetShown(e.overlays and segment~=nil)
            if segment then
                line:SetStartPoint("TOPLEFT",UIParent,segment.x1,-segment.y1);line:SetEndPoint("TOPLEFT",UIParent,segment.x2,-segment.y2)
                line:SetColorTexture(gold[1],gold[2],gold[3],id==e.selected and .65 or .32)
                line:SetAlpha(e.focus and id~=e.selected and .35 or 1)
            end
        end
    end
    self.lastRects=rects;self.placementItems=items;self.placementObstacles=obstacles
    self:UpdateModal();self.refreshing=false
end
function Presentation.Build(editor)
    local self=setmetatable({editor=editor,style=editor.style,controls={},states={},chips={}},{__index=Presentation})
    local style=self.style
    local function frame(parent,w,h,x,y)
        local f=CreateFrame("Frame",nil,parent);f:SetSize(w,h);f:SetPoint("TOPLEFT",parent,"TOPLEFT",x or 0,-(y or 0));f.bvTooltipStyle=style;return f
    end
    local function label(parent,value,x,y,w,size,role)
        local t=style:Label(parent,value,size,role or "text",true);t:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
        t:SetSize(w,18);t:SetWordWrap(false);return t
    end
    local function action(parent,key,x,y,w,fn,primary)
        local b=UI:Button(parent,key,D.ToDesign(w),function()if not self:Modal()then fn()end end,primary)
        b:SetSize(w,28);b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y);self.controls[key]=b;return b
    end
    local function mini(parent,key,glyph,x,y,w,value,active,fn)
        local b=CreateFrame("Button",nil,parent);b:SetSize(w,40);b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y);b.bvTooltipStyle=style
        label(b,key,29,2,w-31,11,"muted");b.value=label(b,value(),29,17,w-31,13,"accentText")
        if glyph=="eye"then b.glyph=style:Icon(b,"eye",D.ToDesign(21),"muted")
        else b.glyph=b:CreateTexture(nil,"OVERLAY");b.glyph:SetTexture(style.materialMediaRoot.."LayoutEditor\\glyph-"..glyph..".tga")end
        b.glyph:SetSize(21,21);b.glyph:SetPoint("LEFT",b,"LEFT",3,0)
        b:SetScript("OnClick",function()if not self:Modal()then fn();editor:Refresh()end end)
        UI:AttachTooltip(b,key,"Layout editor: "..key..".")
        b:HookScript("OnEnter",function()b.hovered=true;self:PaintControls()end)
        b:HookScript("OnLeave",function()b.hovered=false;b.pressed=false;self:PaintControls()end)
        b:HookScript("OnMouseDown",function()b.pressed=true;self:PaintControls()end)
        b:HookScript("OnMouseUp",function()b.pressed=false;self:PaintControls()end)
        b:HookScript("OnHide",function()b.hovered=false;b.pressed=false;self:PaintControls()end)
        self.controls[key]=b;self.states[#self.states+1]={button=b,value=value,active=active};return b
    end
    self.root=frame(editor.root,1,1);self.root:SetAllPoints(editor.root)
    self.console=frame(self.root,910,44);self.console:EnableMouse(true);self.console:SetMovable(true);self.console:SetClampedToScreen(true);self.console:RegisterForDrag("LeftButton")
    self.console:SetScript("OnDragStart",function(f)if not self:Modal()then f:StartMoving()end end)
    self.console:SetScript("OnDragStop",function()self:SaveToolbar()end)
    self.console:SetScript("OnMouseUp",function(_,button)if button=="RightButton"and not self:Modal()then ns.Settings:Profile().layoutToolbar=nil;self:PlaceToolbar(true);self:Refresh()end end)
    self.console:SetScript("OnHide",function(f)f:StopMovingOrSizing()end)
    local logo=frame(self.console,44,44)
    logo:ClearAllPoints();logo:SetPoint("LEFT",self.console,"LEFT",12,0)
    local neutral=logo:CreateTexture(nil,"ARTWORK");neutral:SetTexture(style.materialMediaRoot.."Brand\\LogoNeutral.tga");neutral:SetAllPoints(logo);neutral:SetDesaturated(true)
    self.pigment=logo:CreateTexture(nil,"OVERLAY");self.pigment:SetTexture(style.materialMediaRoot.."Brand\\LogoPigment.tga");self.pigment:SetAllPoints(logo)
    self.tray=frame(self.root,414,294);self.tray:EnableMouse(true);self.tray:Hide()
    mini(self.console,"GRID SNAP","grid",74,1,112,function()return editor.snap and "On / "..editor.gridSize.." px"or "Off"end,function()return editor.snap end,function()editor.snapToggle:Click()end)
    mini(self.console,"ALIGN","align",188,1,112,function()return editor.elementSnap and "Enabled"or "Free"end,function()return editor.elementSnap end,function()editor.elementSnapToggle:Click()end)
    mini(self.console,"OVERLAYS","layers",300,1,122,function()return editor.overlays and "Visible"or "Hidden"end,function()return editor.overlays end,function()editor.overlayToggle:Click()end)
    mini(self.console,"FOCUS","focus",426,1,132,function()return editor.focus and "Selected"or "All elements"end,function()return editor.focus end,function()editor.focusToggle:Click()end)
    mini(self.console,"TOOLS","tools",562,1,140,function()return "More options"end,function()return self.tray:IsShown()end,function()self.tray:SetShown(not self.tray:IsShown())end)
    action(self.console,"Save & exit",726,8,116,function()editor:Close(true)end,true)
    action(self.console,"Exit",847,8,54,function()editor:RequestClose()end)
    label(self.tray,"LAYOUT TOOLS",18,13,300,13,"accentText")
    action(self.tray,"Close",345,7,55,function()self:CloseTools()end)
    local function move(control,x,y,width)
        control:SetParent(self.tray);control:ClearAllPoints();control:SetPoint("TOPLEFT",self.tray,"TOPLEFT",x,-y);D.Width(control,width);control:Show()
    end
    label(self.tray,"Selected element",18,52,150,13,"muted");move(editor.elementSelect,174,45,220)
    label(self.tray,"Grid spacing",18,94,150,13,"muted");move(editor.gridSelect,174,86,100)
    label(self.tray,"View",18,134,150,13,"muted");move(editor.viewSelect,174,126,220)
    label(self.tray,"Inspector gap",18,174,150,13,"muted");move(editor.inspectorGap,174,166,100)
    mini(self.tray,"HIDDEN","eye",18,208,152,function()return editor.showHidden and "Shown"or "Normal"end,function()return editor.showHidden end,function()editor.hiddenToggle:Click()end)
    move(editor.newAnchor,174,208,105);move(editor.cleanupButton,287,208,105)
    editor.cleanupButton:SetLabelInsets(4,4)
    action(self.tray,"Discard",80,248,80,function()editor:Close(false)end)
    self.compact=frame(self.root,304,150)
    label(self.compact,"SELECTED ELEMENT",15,8,175,11,"muted")
    self.compactTitle=label(self.compact,"",15,30,245,14,"accentText")
    label(self.compact,"POSITION",15,52,120,10,"muted");self.coords=label(self.compact,"",15,71,274,13)
    label(self.compact,"SIZE / LINKS",15,95,220,10,"muted");self.links=label(self.compact,"",15,113,274,12,"muted")
    for _,y in ipairs({48,92})do A.Rect(self.compact,"separator"..y,15,y,274,1,A.Accent(style,{.65,.53,.31},.24))end
    self.detailsButton=action(self.compact,"Settings",196,6,96,function()self.expanded=true;editor:Refresh()end);self.detailsButton:SetHeight(23);self.detailsButton:SetLabelInsets(24,4)
    self.settingsGlyph=style:Icon(self.detailsButton,"gear",14,"text")
    self.settingsGlyph:SetPoint("LEFT",self.detailsButton,"LEFT",6,0)
    UI:AttachTooltip(self.detailsButton,"Element settings","Edit size, position, links and element preferences.")
    UI:HideSurface(editor.inspector);D.Width(editor.inspector,342)
    self.collapse=action(editor.inspector,"-",D.ToNative(310),7,20,function()self.expanded=false;editor:Refresh()end)
    self.collapse:SetLabelInsets(2,2)
    UI:AttachTooltip(self.collapse,"Compact inspector","Return to the compact element inspector.")
    editor.titleHandle:SetWidth(D.ToNative(290))
    self.compactHandle=CreateFrame("Button",nil,self.compact)
    self.compactHandle:SetSize(178,44);self.compactHandle:SetPoint("TOPLEFT",self.compact,"TOPLEFT",12,-2)
    self.compact:SetMovable(true);self.compact:SetClampedToScreen(true)
    self.compactHandle:EnableMouse(true);self.compactHandle:RegisterForDrag("LeftButton")
    self.compactHandle:SetScript("OnDragStart",function()self.compact:StartMoving()end)
    self.compactHandle:SetScript("OnDragStop",function()self.compact:StopMovingOrSizing()end)
    for _,pair in ipairs({{self.compactHandle,self.compact},{editor.titleHandle,editor.inspector}})do
        local handle,panel=pair[1],pair[2]
        handle.bvTooltipStyle=style
        UI:AttachTooltip(handle,"Move element inspector","Drag to move. Right-click the title to reset beside the selected element.")
        handle:HookScript("OnDragStart",function()self.inspectorDragging=true end)
        handle:HookScript("OnDragStop",function()
            self.inspectorDragging=false;local b=box(panel)
            if b then self.manualInspector={id=editor.selected,x=b.x,y=b.y}end
            self.solveSignature=nil;editor:Refresh()
        end)
        handle:HookScript("OnMouseUp",function(_,button)
            if button=="RightButton"then self.manualInspector=nil;self.inspectorAnchor=nil;self.solveSignature=nil;editor:Refresh()end
        end)
        panel:HookScript("OnHide",function()panel:StopMovingOrSizing();self.inspectorDragging=false end)
    end
    self.scroll=UI:Form(editor.inspector,342,460,editor.inspector)
    D.Point(self.scroll,"TOPLEFT",editor.inspector,"TOPLEFT",0,-76);self.scroll:SetClipsChildren(true)
    editor.inspectorContent:SetParent(self.scroll.content)
    self.modalShield=frame(editor.root,1,1);self.modalShield:SetAllPoints(editor.root);self.modalShield:EnableMouse(true);self.modalShield:Hide()
    for _,dialog in ipairs({editor.confirm,editor.deleteDialog,editor.cleanupDialog})do
        if dialog then dialog:HookScript("OnShow",function()self:UpdateModal()end);dialog:HookScript("OnHide",function()self:UpdateModal()end)end
    end
    UI:AttachTooltip(self.controls["GRID SNAP"],"Snap to grid","On snaps movement to the chosen spacing. Overlays separately controls grid visibility. Shift allows free dragging.")
    UI:AttachTooltip(self.controls.OVERLAYS,"Editor overlays","Show or hide grid, shading and labels. This does not switch Grid snap off.")
    editor.presentation=self
    self:PlaceToolbar(true)
    return self
end

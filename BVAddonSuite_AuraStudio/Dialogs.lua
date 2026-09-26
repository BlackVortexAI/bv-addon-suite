local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local UI,D=ns.UI,ns.DesignSystem.Metrics
local Dialogs={owners={},pool={}};A.Dialogs=Dialogs
local function acquire()
    local slot=table.remove(Dialogs.pool)
    if slot then return slot end
    slot={};local w=UI:Panel(UIParent,340,140,"canvas");slot.frame=w
    w:SetFrameStrata("DIALOG");w:EnableMouse(true);w:SetClampedToScreen(true)
    slot.heading=UI:Label(w,"",16,"text",true)
    slot.form=UI:Form(w,308,20)
    slot.body=UI:Label(slot.form.content,"",12,"text")
    slot.input=UI:Input(w,308);slot.input:SetMaxLetters(1024);slot.input:SetAutoFocus(false)
    slot.cancelButton=UI:Button(w,"Cancel",146,function()if slot.complete then slot.complete(false)end end)
    slot.okButton=UI:Button(w,"OK",146,function()if slot.complete then slot.complete(true)end end,true)
    slot.input:SetScript("OnEnterPressed",function()if slot.complete then slot.complete(true)end end)
    slot.input:SetScript("OnEscapePressed",function()if slot.complete then slot.complete(false)end end)
    return slot
end
local function measure(label,text,width,minimum)
    label:SetText(text:gsub("|","||"));D.Width(label,width);label:SetHeight(0)
    label:SetWordWrap(true);label:SetJustifyV("TOP")
    local h=math.max(minimum,D.ToDesign(label:GetStringHeight()))
    D.Height(label,h);return h
end
local function configure(slot,title,message,hasInput,width)
    width=math.max(260,math.min(640,width or 340))
    local inner=width-32
    local heading=measure(slot.heading,title,inner,22)
    UI:Place(slot.heading,slot.frame,16,16)
    local bodyHeight=measure(slot.body,message,inner-24,18)
    local bodyVisible=math.min(300,bodyHeight)
    local y=16+heading+18
    UI:Place(slot.form,slot.frame,16,y);D.Size(slot.form,inner-22,bodyVisible)
    D.Width(slot.form.content,inner-24);D.Height(slot.form.slider,bodyVisible)
    UI:Place(slot.body,slot.form.content,0,0);slot.form:SetContentHeight(bodyHeight)
    y=y+bodyVisible+20
    slot.input:SetShown(hasInput)
    if hasInput then UI:Place(slot.input,slot.frame,16,y);D.Width(slot.input,inner);y=y+D.GetHeight(slot.input)+16 end
    UI:Place(slot.cancelButton,slot.frame,16,y);UI:Place(slot.okButton,slot.frame,16+(inner+16)/2,y)
    D.Width(slot.cancelButton,(inner-16)/2);D.Width(slot.okButton,(inner-16)/2)
    local height=y+D.GetHeight(slot.okButton)+16
    D.Size(slot.frame,width,height)
    UI:FitWindow(slot.frame,width,height,ns.Settings:Get("scale"))
    return height
end
local function position(slot,rect)
    local w=slot.frame;local ratio=w:GetEffectiveScale()/UIParent:GetEffectiveScale()
    w:ClearAllPoints();w:SetPoint("CENTER",UIParent,"CENTER",rect and rect.x/ratio or 0,rect and rect.y/ratio or 0)
end
local function recycle(slot)
    slot.input:ClearFocus();slot.frame:Hide();slot.complete=nil
    Dialogs.pool[#Dialogs.pool+1]=slot
end
-- The shared layout owns position/width; content height is a transient footprint.
function Dialogs.Prepare(node,name,saved)
    local c=node.config;local id=c.layoutId
    if c.position==nil then c.position=c.anchor and c.anchor~="" and "layout" or "center" end
    local initial=saved and A.G.Copy(saved) or {displayAnchor=1,width=D.ToNative(340),height=D.ToNative(140),x=0,y=0,screen="CENTER"}
    if c.anchor and c.anchor~="" then
        c.position="layout";initial.link={target=c.anchor,side="CENTER",align="CENTER",gap=0,offset=0}
        c.anchor=""
    end
    local preview
    local function live()
        for _,owned in pairs(Dialogs.owners) do for _,entry in pairs(owned) do if entry.layoutId==id then return entry end end end
    end
    local function previewSlot()
        if not preview then preview=acquire();preview.input:SetText("");preview.frame:EnableMouse(false);preview.input:EnableMouse(false);preview.cancelButton:Disable();preview.okButton:Disable() end
        return preview
    end
    local p={enabled=c.position=="layout"}
    function p.active()return live()~=nil end
    function p.measure(rect)
        local entry=live()
        if not entry and (not p.enabled or not ns.DisplayAnchors.records[id].preview) then return end
        local editing=ns.DisplayAnchors.records[id].preview
        local slot=not editing and entry and entry.slot or previewSlot()
        local values=node.values or {}
        local scale=ns.Settings:Get("scale") or 1
        configure(slot,entry and entry.title or values.title or "AuraStudio",entry and entry.message or values.message or "Confirm?",node.type=="input_dialog",D.ToDesign(rect.width/scale))
        if editing then slot.input:SetText(entry and entry.slot.input:GetText() or values.text or "") end
        local ratio=slot.frame:GetEffectiveScale()/UIParent:GetEffectiveScale()
        return slot.frame:GetHeight()*ratio,slot.frame:GetWidth()*ratio
    end
    function p.paint(rect,showPreview)
        local entry=live()
        if entry then position(entry.slot,rect);entry.frame:SetShown(not showPreview and ns.Layout:IsAvailable(id)) end
        if showPreview and p.enabled and rect then
            local slot=previewSlot();p.measure(rect);position(slot,rect);slot.frame:Show()
        elseif preview then preview.frame:Hide() end
    end
    function p.release()if preview then recycle(preview);preview=nil end end
    ns.DisplayAnchors:Ensure(id,name,134400,initial,p)
end
function Dialogs.Open(run,id,config,title,message,text,payload,finish)
    if InCombatLockdown() and not config.allowCombat then finish(false,text);return end
    local owned=Dialogs.owners[run] or {};Dialogs.owners[run]=owned
    if owned[id] then return end
    local slot=acquire();local w=slot.frame
    w:EnableMouse(true);slot.input:EnableMouse(true);slot.cancelButton:Enable();slot.okButton:Enable();slot.form.slider:SetValue(0)
    configure(slot,title,message,text~=nil)
    local input
    if text~=nil then input=slot.input;input:SetText(text);input:ClearFocus() end
    local done=false
    local function complete(accepted)
        if done then return end;done=true
        local result=input and input:GetText() or nil
        ns.Events:Release(w);owned[id]=nil;recycle(slot)
        if not next(owned) then Dialogs.owners[run]=nil end
        ns.Layout:Refresh();finish(accepted,result)
    end
    slot.complete=complete
    local layoutId=config.position=="layout" and config.layoutId or nil
    owned[id]={frame=w,slot=slot,layoutId=layoutId,title=title,message=message,cancel=function()complete(false)end}
    ns.Events:Subscribe(w,"PLAYER_REGEN_DISABLED",function()
        if not config.allowCombat then complete(false) elseif input then input:ClearFocus() end
    end)
    w:Show()
    if layoutId and ns.Layout.elements[layoutId] then
        ns.Layout:Refresh();position(slot,ns.Layout.rects[layoutId]);w:SetShown(ns.Layout:IsAvailable(layoutId))
    else position(slot,nil) end
end
function Dialogs.Release(run)
    local owned=Dialogs.owners[run];if not owned then return end
    local list={};for _,entry in pairs(owned) do list[#list+1]=entry end
    for _,entry in ipairs(list) do entry.cancel() end
    Dialogs.owners[run]=nil
end

-- Own protected lifecycle; never borrow pooled ordinary display frames.
local _,ns=...
local V,UI=ns.GraphValues,ns.UI
local Actions=ns.Actions
local Q={pending={},pool={secure={},ooc={},["local"]={}},macros={}};ns.SecureActionMedia=Q
function Q:ValidLayout(id)
    local all=ns.Layout:Nodes();local visiting,done={},{}
    local function static(key)
        if type(key)~="string" then return false end
        if done[key] then return true end
        local raw=all[key]
        if not raw or raw.templateId or visiting[key] or key:match("^builtin:") or key:match("^frame:") then return false end
        visiting[key]=true
        for _,target in pairs({raw.link and raw.link.target,raw.widthTarget,raw.heightTarget}) do
            if not static(target) then return false end
        end
        visiting[key]=nil;done[key]=true;return true
    end
    return static(id)
end
local attributes={"*type1","type","spell","item","unit","macro","macrotext","action","marker"}
local function clear(s)
    for _,key in ipairs(attributes) do s.button:SetAttribute(key,nil) end
    for key in pairs(s.attrs or {}) do s.button:SetAttribute(key,nil) end
    s.clickAction=nil;s.clickBindings=nil
end
local function property(region,method,...) return UI:DisplayProperty(region,method,...) end
local function text(region,value)
    if V.IsSecret(value) then region.actionText=nil;return UI:SetMediaText(region,value) end
    if region.actionText==value then return true end
    local ok=UI:SetMediaText(region,value);region.actionText=ok and value or nil;return ok
end
local function asset(region,method,value)
    local opaque=V.IsSecret(value)
    local old=region.actionAsset
    if not opaque and old and old.method==method and old.value==value then return end
    region.actionAsset=nil
    local result
    if method=="SetAtlas" then result=region[method](region,value,false) else result=region[method](region,value) end
    if not V.IsSecret(result) and result==false then error("Media asset unavailable") end
    if not opaque then region.actionAsset={method=method,value=value} end
end
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function unitValid(unit)
    if V.IsSecret(unit) or type(unit)~="string" then return false end
    if unit=="player" or unit=="target" or unit=="targettarget" or unit=="focus" or unit=="focustarget" then return true end
    local party=unit:match("^party([1-4])$");local raid=unit:match("^raid([1-9][0-9]?)$")
    return party~=nil or raid~=nil and tonumber(raid)<=40
end
Q.ValidUnit=unitValid
local function create(mode)
    assert(mode=="local" or not InCombatLockdown(),"Prepare action media outside combat")
    local root=CreateFrame("Frame",nil,UIParent,mode~="local" and "SecureHandlerStateTemplate" or nil)
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(root) end
    root:Hide();root:SetFrameStrata("MEDIUM");root:EnableMouse(false)
    local template=mode~="local" and (mode=="ooc" and "InsecureActionButtonTemplate" or "SecureActionButtonTemplate") or nil
    local b=CreateFrame("Button",nil,root,template)
    b:SetAllPoints(root);b:EnableMouse(true);b:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp","Button4Up","Button5Up")
    b:SetAttribute("useOnKeyDown",false)
    local s={root=root,button=b,mode=mode}
    local function clicked(_,button)
        local key=Actions.HardwareKey(button);local action=key and s.clickBindings and s.clickBindings[key]
        if not action or (action.kind~="click" and action.kind~="ui" and action.kind~="group") then return end
        local ok,why=Actions.ExecuteClick(action,s.owner,button)
        if s.record then s.record.actionStatus=why end
        text(s.caption,ok and "" or why)
    end
    if mode=="local" then b:SetScript("OnClick",clicked) else b:HookScript("PostClick",clicked) end
    local function refresh()
        if s.record and s.record.actionRequest then
            local r=s.record.actionRequest;local e=r.entry
            local compatible=e and r.visible and not s.record.macroPending and s.owner==e.owner and Actions.BindingSame(s.action,e.action) and s.mode==e.mode
            Q:Cosmetics(s.record,r.media,e,compatible)
        end
    end
    b:HookScript("OnEnter",function()s.hover=true;refresh()end)
    b:HookScript("OnLeave",function()s.hover=nil;s.down={};refresh()end)
    b:HookScript("OnMouseDown",function(_,key)if Actions.HardwareKey(key)then s.down=s.down or {};s.down[key]=true;refresh()end end)
    b:HookScript("OnMouseUp",function(_,key)if s.down then s.down[key]=nil end;refresh()end)
    s.buttonSkin=UI:ButtonSkin(b)
    s.background=b:CreateTexture(nil,"BACKGROUND");s.background:SetAllPoints(b)
    s.image=b:CreateTexture(nil,"ARTWORK");s.image:SetAllPoints(b)
    s.iconSkin=UI:IconSkin(b,s.image,mode~="local",s.buttonSkin)
    -- Numeric and timer bars are distinct: a native timer cannot overwrite a
    -- later numeric value. All regions already exist before combat starts.
    for _,key in ipairs({"bar","timer"}) do
        local bar=CreateFrame("StatusBar",nil,b);bar:SetAllPoints(b);bar:EnableMouse(false)
        s[key]=bar
    end
    s.front=CreateFrame("Frame",nil,b);s.front:SetAllPoints(b);s.front:EnableMouse(false)
    s.text=s.front:CreateFontString(nil,"OVERLAY");s.text:SetAllPoints(s.front)
    UI:ApplyMediaFont(s.text,"Fonts\\FRIZQT__.TTF",12,"")
    s.placeholder=s.front:CreateFontString(nil,"OVERLAY");s.placeholder:SetAllPoints(s.front)
    UI:ApplyMediaFont(s.placeholder,"Fonts\\FRIZQT__.TTF",12,"OUTLINE")
    s.placeholder:SetTextColor(1,.85,.45,1);s.placeholder:SetJustifyH("CENTER");s.placeholder:SetWordWrap(true)
    s.cue=s.front:CreateTexture(nil,"OVERLAY");s.cue:SetAllPoints(s.front);s.cue:SetColorTexture(1,.78,.15,.3)
    s.edges={};for i=1,4 do s.edges[i]=s.front:CreateTexture(nil,"OVERLAY") end
    s.caption=s.front:CreateFontString(nil,"OVERLAY");s.caption:SetPoint("TOP",b,"BOTTOM",0,-3)
    UI:ApplyMediaFont(s.caption,"Fonts\\FRIZQT__.TTF",10,"OUTLINE")
    s.caption:SetTextColor(1,.85,.45,1)
    s.front.caption=s.text;s.glow=UI:DisplayGlow(s.front);s.decorations=UI:DisplayDecorations(s.front)
    -- Independent, mouse-transparent visual: protected bindings retain their
    -- original hitbox while the shared renderer can update any cosmetic in combat.
    s.visual=UI:DisplayIcon()
    local function hideVisual()s.visual:Present(nil,false);s.hover=nil;s.down={} end
    root:HookScript("OnHide",hideVisual);b:HookScript("OnHide",hideVisual)
    root:HookScript("OnShow",refresh);b:HookScript("OnShow",refresh)
    return s
end
local function wanted(rec,rect,entry,visible)
    return entry and type(entry.owner)=="table" and not entry.owner.test and not rec.preview and visible==true
        and Actions.Valid(entry.action)
        and (entry.mode=="secure" or entry.mode=="ooc" or entry.mode=="local") and rect and V.PlainExcept(rect,{})
        and finite(rect.x) and finite(rect.y) and finite(rect.width) and finite(rect.height)
        and rect.width>=1 and rect.height>=1 and rect.width<=5000 and rect.height<=2000
end
local function sameRect(a,b)
    return a and b and a.x==b.x and a.y==b.y and a.width==b.width and a.height==b.height
end
function Q:Supported(media)
    if not ns.DisplayModel.Valid(media) then return false,"media unavailable" end
    if media.kind~="icon" and media.kind~="graphic" and media.kind~="text" and media.kind~="bar" then return false,"unsupported media kind" end
    if media.nativeBinding then return false,"native binding unavailable" end
    return true,"ready"
end
local function shape(media)
    if not media then return "",12,"",0 end
    if media.kind=="text" then
        return ns.Media:Font(media.font),media.fontSize,media.fontFlags and media.fontFlags~="NONE" and media.fontFlags or "",0
    end
    return "",12,"",media.kind=="bar" and media.borderWidth or 0
end
local function prepareStyle(s,media)
    local path,size,flags,border=shape(media)
    -- Fonts and edge rectangles are prepared outside combat. Changes retain
    -- the last prepared style until regen; content and colors can still update.
    if path~="" then UI:ApplyMediaFont(s.text,path,size,flags) end
    local w,h=s.rect.width,s.rect.height;local t=math.min(border,w/2,h/2)
    local edges={{0,(h-t)/2,w,t},{0,-(h-t)/2,w,t},{-(w-t)/2,0,t,h-2*t},{(w-t)/2,0,t,h-2*t}}
    for i,r in ipairs(edges) do
        UI:PlaceDisplayRegion(s.edges[i],"CENTER",s.front,"CENTER",r[1],r[2],math.max(.01,r[3]),math.max(.01,r[4]))
    end
    local buttonStyle=media and media.buttonStyle
    local buttonBorder=buttonStyle and buttonStyle~="wow" and (media.surface and media.surface.borderWidth or 1) or 0
    s.buttonSkin:Prepare(buttonStyle,media and media.surface,w,h)
    s.iconSkin:Prepare(media and media.iconSkin,s.rect,media and media.iconShape)
    s.style={path=path,size=size,flags=flags,border=border,buttonStyle=buttonStyle,buttonBorder=buttonBorder,iconSkin=media and media.iconSkin,iconShape=media and media.iconShape}
end
local function styleSame(s,media)
    local path,size,flags,border=shape(media);local old=s.style
    local buttonStyle=media and media.buttonStyle
    local buttonBorder=buttonStyle and buttonStyle~="wow" and (media.surface and media.surface.borderWidth or 1) or 0
    return old and old.path==path and old.size==size and old.flags==flags and old.border==border and old.buttonStyle==buttonStyle and old.buttonBorder==buttonBorder and old.iconSkin==(media and media.iconSkin) and old.iconShape==(media and media.iconShape)
end
local function alpha(region,value) property(region,"SetAlpha",value) end
local function sharedVisual(media,entry)
    return media and (#(media.ops or {})>0 or media.cooldown or media.overlay or (media.glow and media.glow>0) or media.surface or media.textOutline or media.textShadow or media.iconBorder or media.iconSkin or media.buttonStyle or media.duration or entry and (entry.hoverMedia or entry.pressedMedia))
end
function Q:Cosmetics(rec,media,entry,compatible)
    local s=rec.actionSurface;if not s then return end
    if entry then
        local alternate=s.down and next(s.down) and entry.pressedMedia or s.hover and entry.hoverMedia
        if alternate then media=alternate end
    end
    local supported,status=self:Supported(media)
    if not compatible then supported=false;status="pending action change" end
    if s.bindingWhy then supported=false;status=s.bindingWhy end
    rec.actionStatus=supported and media.alpha==0 and "transparent media; action prepared" or status
    local function render()
        local opacity=supported and media.alpha or 1
        local shared=supported and sharedVisual(media,entry)
        if not supported then
            text(s.placeholder,(s.unit or s.label).." / "..(s.bindingWhy or "pending"))
        elseif media.kind=="icon" or media.kind=="graphic" then
            local mode=media.atlas and "atlas" or "texture"
            if s.imageMode~=mode then s.image.displayProperties=nil;s.image.actionAsset=nil;s.imageMode=mode end
            if media.atlas then asset(s.image,"SetAtlas",media.atlas)
            else asset(s.image,"SetTexture",V.Native(media.texture));UI:ApplyMediaCrop(s.image,media) end
            property(s.image,"SetVertexColor",unpack(media.color))
            property(s.image,"SetBlendMode",media.blendMode or "BLEND")
        elseif media.kind=="text" then
            assert(text(s.text,media.text),"Text unavailable")
            property(s.text,"SetTextColor",unpack(media.color));property(s.text,"SetJustifyH",media.align)
            property(s.text,"SetJustifyV","MIDDLE");property(s.text,"SetWordWrap",media.wrap)
        else
            local bar=media.duration and s.timer or s.bar
            local texture=ns.Media:StatusBar(media.texture);asset(bar,"SetStatusBarTexture",texture)
            property(bar,"SetStatusBarColor",unpack(media.color))
            property(bar,"SetOrientation",(media.direction=="UP" or media.direction=="DOWN") and "VERTICAL" or "HORIZONTAL")
            property(bar,"SetReverseFill",media.direction=="LEFT" or media.direction=="DOWN")
            if media.duration then bar:SetTimerDuration(V.Object(media.duration,"duration"))
            else property(bar,"SetMinMaxValues",0,V.Native(media.maximum));property(bar,"SetValue",V.Native(media.value)) end
            property(s.background,"SetColorTexture",unpack(media.background))
            if s.style.border>0 then for _,edge in ipairs(s.edges) do property(edge,"SetColorTexture",unpack(media.borderColor)) end end
        end
        local kind=supported and media.kind or "placeholder"
        s.buttonSkin:Paint(supported and media or nil,opacity)
        alpha(s.image,(kind=="icon" or kind=="graphic") and opacity or 0)
        alpha(s.text,kind=="text" and opacity or 0)
        alpha(s.placeholder,kind=="placeholder" and 1 or 0)
        alpha(s.background,kind=="bar" and opacity or 0)
        alpha(s.bar,kind=="bar" and not media.duration and opacity or 0)
        alpha(s.timer,kind=="bar" and media.duration and opacity or 0)
        for _,edge in ipairs(s.edges) do alpha(edge,kind=="bar" and s.style.border>0 and opacity or 0) end
        local skinStatus=s.iconSkin:Paint(not shared and media or nil,supported and not shared)
        if skinStatus~="ready" then rec.actionStatus=skinStatus end
        local decorated=supported and V.RuntimeCopy(media) or nil
        if decorated and decorated.buttonStyle then decorated.surface=nil end
        s.glow:Present(supported and not shared and media or nil,0)
        s.decorations:Present(not shared and decorated or nil,0)
        if shared then
            s.glow:Stop();s.decorations:Stop();s.buttonSkin:Paint(nil);s.iconSkin:Paint(nil,false)
            for _,region in ipairs({s.image,s.text,s.background,s.bar,s.timer,unpack(s.edges)}) do alpha(region,0) end
            local cosmetic=V.RuntimeCopy(media);cosmetic.interaction=nil
            s.visual:Geometry(s.rect);s.visual:SetDisplayLevel(s.front:GetFrameLevel());s.visual:SetInputHandler(nil)
            s.visual:Present(cosmetic,true)
            assert(not s.visual.assetUnavailable and not s.visual.cropUnavailable,"Cosmetic asset unavailable")
            local status=s.visual.renderStatus
            if status and status~="ready" and status~="bound" then rec.actionStatus=status end
            if s.visual.buttonSkin and s.visual.buttonSkin.art then
                local art=s.visual.buttonSkin.art;art.hover=s.hover;art.down=s.down or {};art:Refresh()
            end
            if not s.root:IsVisible() or not s.button:IsVisible() then s.visual:Hide() end
        else s.visual:Present(nil,false) end
    end
    local ok=pcall(render)
    if not ok then
        s.visual:Present(nil,false)
        s.glow:Stop();s.decorations:Stop()
        s.buttonSkin:Paint(nil)
        s.iconSkin:Paint(nil,false)
        rec.actionStatus="native media unavailable"
        alpha(s.image,0);alpha(s.bar,0);alpha(s.timer,0);alpha(s.background,0)
        for _,edge in ipairs(s.edges) do alpha(edge,0) end
        text(s.placeholder,(s.unit or s.label).." / unavailable");alpha(s.placeholder,1);alpha(s.text,0)
    end
    alpha(s.cue,compatible and entry and not V.IsSecret(entry.hint) and entry.hint==true and 1 or 0)
    local suffix=rec.actionPending and " / pending after combat" or rec.actionStatus~="ready" and " / "..rec.actionStatus or ""
    property(s.caption,"SetText",suffix~="" and s.label..suffix or "")
end
function Q:MacroWatch(rec,enabled)
    self.macros[rec]=enabled and true or nil
    if next(self.macros) and not self.macroUnsubscribe then
        Actions.macroCache=nil
        self.macroUnsubscribe=ns.Events:Subscribe(self.macros,"UPDATE_MACROS",function()
            Actions.macroCache=nil
            local records={};for r in pairs(self.macros) do records[#records+1]=r end
            for _,r in ipairs(records) do
                if InCombatLockdown() then r.macroPending=true end
                local request=r.actionRequest;if request then self:Paint(r,request.rect,request.media,request.entry,request.visible) end
            end
        end)
    elseif not next(self.macros) and self.macroUnsubscribe then
        self.macroUnsubscribe();self.macroUnsubscribe=nil;Actions.macroCache=nil
    end
end
function Q:Watch()
    if self.watching then return end
    self.watching=true
    ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function()
        if InCombatLockdown() then return end
        ns.Events:Release(self);self.watching=nil
        local pending=self.pending;self.pending={}
        for rec in pairs(pending) do
            local r=rec.actionRequest
            if r then self:Paint(rec,r.rect,r.media,r.entry,r.visible) end
        end
    end)
end
function Q:Retire(rec)
    local s=rec.actionSurface;if not s then return end
    assert(s.mode=="local" or not InCombatLockdown(),"Retire action media outside combat")
    if s.watched then UnregisterUnitWatch(s.button);s.watched=nil end
    if s.driver then UnregisterStateDriver(s.root,"visibility");s.driver=nil end
    s.root:Hide();s.button:Hide();clear(s);self:MacroWatch(rec,false)
    s.iconSkin:Release();s.glow:Stop();s.decorations:Stop();s.visual:Present(nil,false);s.style=nil;s.hover=nil;s.down={}
    s.owner=nil;s.spellID=nil;s.unit=nil;s.action=nil;s.attrs=nil;s.record=nil;rec.actionSurface=nil
    self.pool[s.mode][#self.pool[s.mode]+1]=s
end
function Q:Paint(rec,rect,media,entry,visible)
    if entry then
        local a=entry.action or {kind="spell",spellID=entry.spellID,unit=entry.unit}
        entry={owner=entry.owner,action=a,mode=Actions.Mode(a)=="local" and "local" or entry.mode,hint=entry.hint,cropBorder=entry.cropBorder,hoverMedia=entry.hoverMedia,pressedMedia=entry.pressedMedia}
    end
    rec.actionRequest={rect=rect,media=media,entry=entry,visible=visible}
    local want=wanted(rec,rect,entry,visible);local s=rec.actionSurface
    local compatible=s and want and not rec.macroPending and s.owner==entry.owner and Actions.BindingSame(s.action,entry.action) and s.mode==entry.mode
    local supported=self:Supported(media);local styled=supported and media or nil
    if InCombatLockdown() and (s and s.mode~="local" or want and entry.mode~="local") then
        rec.actionPending=(s~=nil or want) and not (compatible and sameRect(s.rect,rect) and (sharedVisual(styled,entry) or styleSame(s,styled))) or nil
        if rec.actionPending then self.pending[rec]=true;self:Watch() else self.pending[rec]=nil end
        if compatible then s.clickBindings=V.RuntimeCopy(Actions.BindingMap(entry.action)) end
        self:Cosmetics(rec,media,entry,compatible)
        return
    end
    rec.actionPending=nil;rec.macroPending=nil;self.pending[rec]=nil
    if not want then self:Retire(rec);rec.actionStatus=nil;rec.actionRequest=nil;return end
    if s and s.mode~=entry.mode then self:Retire(rec);s=nil end
    s=s or table.remove(self.pool[entry.mode]) or create(entry.mode);rec.actionSurface=s
    self:MacroWatch(rec,Actions.HasMacro(entry.action))
    local attrs,why=Actions.Prepare(entry.action)
    if s.owner~=entry.owner or not Actions.Same(s.action,entry.action) or not Actions.Same(s.attrs,attrs) then
        if s.watched then UnregisterUnitWatch(s.button);s.watched=nil end;s.root:Hide()
        clear(s)
        if attrs then for key,value in pairs(attrs) do s.button:SetAttribute(key,value) end end
        s.owner=entry.owner;s.spellID=entry.action.spellID;s.unit=entry.action.unit;s.action=V.RuntimeCopy(entry.action);s.attrs=attrs
    end
    s.clickBindings=V.RuntimeCopy(Actions.BindingMap(entry.action))
    s.bindingWhy=why;s.label=Actions.Label(entry.action);s.record=rec
    local moved=not sameRect(s.rect,rect)
    if moved then
        s.root:ClearAllPoints();s.root:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y);s.root:SetSize(rect.width,rect.height)
        s.rect={x=rect.x,y=rect.y,width=rect.width,height=rect.height}
    end
    if moved or not styleSame(s,styled) then prepareStyle(s,styled) end
    local level=rec.level or 5
    if s.root:GetFrameLevel()~=level then
        s.root:SetFrameLevel(level);s.button:SetFrameLevel(level+1);s.bar:SetFrameLevel(level+2);s.timer:SetFrameLevel(level+2);s.front:SetFrameLevel(level+3)
    end
    self:Cosmetics(rec,media,entry,true)
    -- Existence owns only the child; OOC combat visibility owns only its parent.
    if s.unit and s.unit~="none" and attrs then
        if not s.watched then RegisterUnitWatch(s.button);s.watched=true end
    else s.button:Show() end
    if s.mode=="ooc" and not s.driver then RegisterStateDriver(s.root,"visibility","[combat] hide; show");s.driver=true end
    if not s.root:IsShown() then s.root:Show() end
end
function Q:Release(rec)
    self:Paint(rec,nil,nil,nil,false)
end

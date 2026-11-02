local _, ns = ...
local UI = ns.UI
local D = ns.DesignSystem.Metrics

-- Owned color editor: preview changes are local until Apply. No game UI is patched.
local function colorHex(value)
    if ns.GraphValues.IsSecret(value) or type(value)~="string" then return end
    local c=ns.DisplayModel.GlowColor(value)
    if not c then return end
    return string.format("%02X%02X%02X%02X",math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5),math.floor(c[4]*255+.5)),c
end
-- HSV helpers for the colour spectrum (h,s,v in 0..1).
local function hsvToRgb(h,s,v)
    local i=math.floor(h*6)%6;local f=h*6-math.floor(h*6)
    local p,q,t=v*(1-s),v*(1-f*s),v*(1-(1-f)*s)
    if i==0 then return v,t,p elseif i==1 then return q,v,p elseif i==2 then return p,v,t
    elseif i==3 then return p,q,v elseif i==4 then return t,p,v end
    return v,p,q
end
local function rgbToHsv(r,g,b)
    local max,min=math.max(r,g,b),math.min(r,g,b);local d=max-min;local h=0
    if d>0 then
        if max==r then h=((g-b)/d)%6 elseif max==g then h=(b-r)/d+2 else h=(r-g)/d+4 end
        h=h/6
    end
    return h,max>0 and d/max or 0,max
end
UI.HsvToRgb,UI.RgbToHsv=hsvToRgb,rgbToHsv
-- Cursor position inside a frame, 0..1 on both axes (0,0 = top left).
local function cursorIn(frame)
    local x,y=GetCursorPosition();local scale=frame:GetEffectiveScale()
    local left,top,w,h=frame:GetLeft(),frame:GetTop(),frame:GetWidth(),frame:GetHeight()
    if not left or not top or not w or not h or w<=0 or h<=0 then return end
    return math.max(0,math.min(1,(x/scale-left)/w)),math.max(0,math.min(1,(top-y/scale)/h))
end
-- Interactive spectrum: saturation/brightness field and hue bar built from
-- gradient textures. Dragging polls with a short C_Timer ticker while the
-- button is held; no per-frame scripts.
local function buildSpectrum(popup,width)
    local api=popup.panel.CreateTexture and CreateColor
    local field=CreateFrame("Button",nil,popup.panel);D.Size(field,width,120);UI:Place(field,popup.panel,16,80)
    field.hue=field:CreateTexture(nil,"BACKGROUND");field.hue:SetAllPoints(field)
    field.white=field:CreateTexture(nil,"BORDER");field.white:SetAllPoints(field);field.white:SetColorTexture(1,1,1,1)
    field.black=field:CreateTexture(nil,"ARTWORK");field.black:SetAllPoints(field);field.black:SetColorTexture(0,0,0,1)
    if field.white.SetGradient and api then
        field.white:SetGradient("HORIZONTAL",CreateColor(1,1,1,1),CreateColor(1,1,1,0))
        field.black:SetGradient("VERTICAL",CreateColor(0,0,0,1),CreateColor(0,0,0,0))
    end
    field.marker=field:CreateTexture(nil,"OVERLAY");D.Size(field.marker,8,8);field.marker:SetColorTexture(1,1,1,1)
    local bar=CreateFrame("Button",nil,popup.panel);D.Size(bar,width,14);UI:Place(bar,popup.panel,16,206)
    bar.parts={}
    for i=1,6 do
        local t=bar:CreateTexture(nil,"ARTWORK");bar.parts[i]=t
        D.Point(t,"TOPLEFT",bar,"TOPLEFT",(i-1)*width/6,0);D.Size(t,width/6,14)
        local r1,g1,b1=hsvToRgb((i-1)/6,1,1);local r2,g2,b2=hsvToRgb((i%6)/6,1,1)
        t:SetColorTexture(1,1,1,1)
        if t.SetGradient and api then t:SetGradient("HORIZONTAL",CreateColor(r1,g1,b1,1),CreateColor(r2,g2,b2,1)) else t:SetColorTexture(r1,g1,b1,1) end
    end
    bar.marker=bar:CreateTexture(nil,"OVERLAY");D.Size(bar.marker,3,18);bar.marker:SetColorTexture(1,1,1,1)
    popup.field,popup.hueBar=field,bar
    function popup:ShowHsv()
        local h,s,v=self.hsv[1],self.hsv[2],self.hsv[3]
        local r,g,b=hsvToRgb(h,1,1);field.hue:SetColorTexture(r,g,b,1)
        field.marker:ClearAllPoints();D.Point(field.marker,"CENTER",field,"TOPLEFT",s*width,-(1-v)*120)
        bar.marker:ClearAllPoints();D.Point(bar.marker,"CENTER",bar,"LEFT",h*width,0)
    end
    local function apply(which)
        local fx,fy=cursorIn(which);if not fx then return end
        local h,s,v=popup.hsv[1],popup.hsv[2],popup.hsv[3]
        if which==bar then h=math.min(fx,.9999) else s,v=fx,1-fy end
        popup.hsv={h,s,v};local r,g,b=hsvToRgb(h,s,v)
        popup.keepHsv=true;popup:SetColor({r,g,b,popup.color[4]});popup.keepHsv=nil;popup:ShowHsv()
    end
    for _,frame in ipairs({field,bar}) do
        local target=frame
        frame:SetScript("OnMouseDown",function()
            if not popup.owner then return end
            apply(target)
            if popup.dragTicker then popup.dragTicker:Cancel() end
            popup.dragTicker=C_Timer.NewTicker(.03,function()
                if not IsMouseButtonDown or not IsMouseButtonDown("LeftButton") or not popup.owner then
                    if popup.dragTicker then popup.dragTicker:Cancel();popup.dragTicker=nil end;return
                end
                apply(target)
            end)
        end)
        frame:SetScript("OnMouseUp",function() if popup.dragTicker then popup.dragTicker:Cancel();popup.dragTicker=nil end end)
    end
end
-- Shared spectrum colour picker (0.8.73). Any owner with value, SetValue,
-- callback and IsVisible can use it; ColorField and ColorInput both do.
local colorPopups={}
local function openPicker(self,options)
    options=options or self.bvColorOptions or {}
    if self.locked or not self:IsVisible() then return end
    UI:CloseDropdown()
    if UI.colorPopup then UI.colorPopup:Hide() end
    local style=options.style or UI:GetStyle()
    local popup=colorPopups[style]
    if not popup then
      UI:WithStyle(style,function()
        popup=UI:DismissiblePopup(UIParent,320,440,style.materialProfile=="interface" and "dialog" or nil)
        D.Point(popup.panel,"CENTER",UIParent,"CENTER",0,0);popup.panel:SetClampedToScreen(true)
        UI:Place(UI:Label(popup.panel,"Color",16,"text"),popup.panel,16,12)
        popup.sample=popup.panel:CreateTexture(nil,"ARTWORK");D.Point(popup.sample,"TOPRIGHT",-16,-16);D.Size(popup.sample,48,30)
        popup.hex=UI:Input(popup.panel,176,function(text)
            local hex,c=colorHex(text)
            if hex then popup:SetColor(c) else popup.hex:SetText(popup.rgb and (popup.value or ""):sub(1,6) or (popup.value or "")) end
        end);popup.hex:SetMaxLetters(9);UI:Place(popup.hex,popup.panel,16,43)
        popup.sliders={};popup.labels={}
        function popup:SetColor(c)
            c={c[1],c[2],c[3],self.rgb and 1 or c[4]}
            self.updating=true;self.color={unpack(c)}
            for i,slider in ipairs(self.sliders)do slider:SetValue(math.floor(c[i]*255+.5));self.labels[i]:SetText(({"R","G","B","A"})[i].."  "..math.floor(c[i]*255+.5))end
            self.value=colorHex(string.format("%02X%02X%02X%02X",math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5),math.floor(c[4]*255+.5)))
            self.hex:SetText(self.rgb and self.value:sub(1,6) or self.value);self.sample:SetColorTexture(unpack(c));self.updating=false
            if not self.keepHsv then
                local h,s,v=rgbToHsv(c[1],c[2],c[3])
                -- Grey keeps the last hue so the bar does not jump to red.
                if s==0 and self.hsv then h=self.hsv[1] end
                self.hsv={h,s,v}
            end
            if self.ShowHsv then self:ShowHsv() end
        end
        buildSpectrum(popup,288)
        for i=1,4 do
            local index=i
            popup.labels[i]=UI:Place(UI:Label(popup.panel,"",12,"muted"),popup.panel,16,240+(i-1)*32)
            local slider=UI:GetStyle():Slider(popup.panel,210,0,255,1,255);popup.sliders[i]=slider
            UI:Place(slider,popup.panel,90,238+(i-1)*32)
            slider:SetScript("OnValueChanged",function(_,v)
                if popup.updating or not popup.owner or (popup.rgb and index==4) then return end
                local c={unpack(popup.color)};c[index]=math.floor(v+.5)/255;popup:SetColor(c)
            end)
        end
        popup.cancel=UI:Place(UI:Button(popup.panel,"Cancel",130,function()popup:Hide()end),popup.panel,16,388)
        popup.apply=UI:Place(UI:Button(popup.panel,"Apply",130,function()
            local owner,value=popup.owner,colorHex(popup.hex:GetText())
            if not value then popup.hex:SetText(popup.rgb and (popup.value or ""):sub(1,6) or (popup.value or ""));return end
            if popup.rgb then value=value:sub(1,6).."FF" end
            popup:Hide()
            if owner and owner:IsVisible() and not owner.locked then owner:SetValue(value);ns:Call("color picker",owner.callback,value)end
        end),popup.panel,174,388)
        popup.default=UI:Place(UI:Button(popup.panel,"Default",288,function()
            local owner,value=popup.owner,popup.defaultValue
            if not value then return end
            popup:Hide()
            if owner and owner:IsVisible() and not owner.locked then owner:SetValue(value);ns:Call("color default",owner.callback,"")end
        end),popup.panel,16,334)
        popup:HookScript("OnHide",function(self)self.owner=nil;self.hex:ClearFocus();if self.dragTicker then self.dragTicker:Cancel();self.dragTicker=nil end end)
      end)
      colorPopups[style]=popup
    end
    UI.colorPopup=popup;popup.owner=self;popup.rgb=options.rgb==true
    popup.defaultValue=options.default and colorHex(options.default) or nil
    popup.default:SetShown(popup.rgb and popup.defaultValue~=nil)
    popup.labels[4]:SetShown(not popup.rgb);popup.sliders[4]:SetShown(not popup.rgb)
    popup.sliders[4]:EnableMouse(not popup.rgb);popup.hex:SetMaxLetters(popup.rgb and 7 or 9)
    popup.panel:SetScale(self:GetEffectiveScale()/UIParent:GetEffectiveScale())
    popup:SetColor(select(2,colorHex(self.value or "")) or {1,1,1,1});popup:Open()
end
function UI:OpenColorPicker(owner,callback,options)
    if callback then owner.callback=callback end
    openPicker(owner,options)
end
ns.Settings:BeforeProfileChange(colorPopups,function()if UI.colorPopup then UI.colorPopup:Hide()end end)
-- Compact preset rail with a shape cue for the selection and a full RGB picker.
function UI:ColorPalette(parent,choices,changed)
    local host=CreateFrame("Frame",nil,parent)
    D.Size(host,(#choices+1)*24,24)
    host.chips={}
    function host:SetValue(hex)
        self.value=hex:sub(1,6):lower()
        for _,chip in ipairs(self.chips) do chip.mark:SetShown(chip.hex==self.value) end
        self.custom.value=self.value.."FF"
        self.custom.sample:SetColorTexture(UI:RGBA(self.custom.value))
    end
    local function choose(hex)
        host:SetValue(hex)
        changed(host.value)
    end
    for i,choice in ipairs(choices) do
        local chip=CreateFrame("Button",nil,host)
        chip.hex=choice.value:lower()
        D.Size(chip,23,24);D.Point(chip,"LEFT",(i-1)*24,0)
        local fill=chip:CreateTexture(nil,"ARTWORK")
        D.Size(fill,16,14);D.Point(fill,"CENTER",0,2)
        fill:SetColorTexture(UI:RGBA(chip.hex.."FF"))
        chip.mark=chip:CreateTexture(nil,"OVERLAY")
        D.Size(chip.mark,12,2);D.Point(chip.mark,"BOTTOM",0,1)
        chip.mark:SetColorTexture(UI:GetStyle():Color("text"))
        chip:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square","ADD")
        UI:AttachTooltip(chip,choice.label)
        chip:SetScript("OnClick",function() choose(chip.hex) end)
        host.chips[i]=chip
    end
    host.bvStyle=UI:GetStyle()
    host.custom=UI:IconButton(host,"plus",function(b) UI:OpenColorPicker(b,choose,{rgb=true,style=host.bvStyle}) end)
    function host.custom:SetValue(hex) host:SetValue(hex) end
    host:HookScript("OnHide",function() if UI.colorPopup and UI.colorPopup.owner==host.custom then UI.colorPopup:Hide() end end)
    D.Point(host.custom,"LEFT",#choices*24,0);D.Size(host.custom,22,22)
    host.custom.sample=host.custom:CreateTexture(nil,"OVERLAY")
    D.Point(host.custom.sample,"BOTTOMLEFT",2,1);D.Point(host.custom.sample,"BOTTOMRIGHT",-2,1);D.Height(host.custom.sample,2)
    UI:AttachTooltip(host.custom,"Custom color","Choose any color from the spectrum.")
    host:SetValue(choices[1].value)
    return host
end
function UI:ColorField(parent,width,callback)
    local host=CreateFrame("Frame",nil,parent);D.Size(host,width,30);host.callback=callback
    host.input=self:Input(host,width-36,function(value)
        if host.locked then return end
        local hex=colorHex(value)
        if hex then host:SetValue(hex);ns:Call("color input",callback,hex) else host.input:SetText(host.value or "") end
    end)
    host.input:SetMaxLetters(9)
    host.swatch=self:Button(host,"",30,function()host:OpenPicker()end)
    host.sample=host.swatch:CreateTexture(nil,"OVERLAY");D.Point(host.sample,"TOPLEFT",4,-4);D.Point(host.sample,"BOTTOMRIGHT",-4,4)
    function host:Layout(w)D.Size(self,w,30);D.Point(self.input,"TOPLEFT",0,0);D.Width(self.input,math.max(30,w-36));D.Point(self.swatch,"TOPRIGHT",0,0)end
    function host:SetValue(value)
        self.value=value;self.input:SetText(value or "")
        local _,c=colorHex(value or "");self.sample:SetColorTexture(unpack(c or {0,0,0,0}))
    end
    function host:SetLocked(locked)
        self.locked=locked==true;self.input:EnableMouse(not self.locked)
        self.input:SetAlpha(self.locked and .4 or 1)
        if self.locked then self.swatch:Disable() else self.swatch:Enable() end
        if self.locked and UI.colorPopup and UI.colorPopup.owner==self then UI.colorPopup:Hide() end
    end
    host.OpenPicker=openPicker
    host:HookScript("OnHide",function(self)
        self.input:ClearFocus()
        if UI.colorPopup and UI.colorPopup.owner==self then UI.colorPopup:Hide() end
    end)
    host:Layout(width);host:SetValue("FFFFFFFF");return host
end

-- Commit after release: resizing the owning window during a drag moves the track.
function UI:AppearanceChoice(parent,key,width)
    local choices=key=="themeKey" and {{value="violet",label="Arcane Violet"},{value="ember",label="Ember Atelier"},{value="tide",label="Moonlit Tide"}} or ns.Media:FontOptions()
    assert(key=="themeKey" or key=="font","Unknown appearance choice")
    local dropdown=self:Dropdown(parent,width,choices,function(value) ns.Settings:Set(key,value) end)
    if key=="font" then dropdown:SetOptionsProvider(function()return ns.Media:FontOptions()end) end
    return dropdown
end
function UI:ScaleSlider(parent, width, callback)
    -- One line (0.8.71 density pass): caption, slider, value.
    local host=CreateFrame("Frame",nil,parent); D.Size(host,width,24)
    local label=self:Label(host,"Window scale",11,"muted"); D.Point(label,"LEFT"); D.Size(label,78,16)
    host.label=self:Label(host,"100%",11,"text"); D.Point(host.label,"RIGHT"); D.Size(host.label,40,16); host.label:SetJustifyH("RIGHT")
    local slider=self:GetStyle():Slider(host,width-126,50,130,1,100); host.slider=slider
    D.Size(slider,math.max(40,width-126),20); D.Point(slider,"LEFT",82,0)
    function host:Resize(value)
        D.Width(self,value)
        D.Width(self.slider,math.max(40,value-126))
    end
    host:HookScript("OnSizeChanged",function()D.Width(slider,math.max(40,D.GetWidth(host)-126))end)
    slider:SetScript("OnValueChanged",function(_,value)
        host.value=math.floor(value+0.5)/100; host.label:SetText(string.format("%.0f%%",host.value*100))
    end)
    local function commit() ns:Call("window scale",callback,host.value) end
    slider:SetScript("OnMouseUp",commit)
    self:SliderWheel(slider,function(delta)
        slider:SetValue(math.max(50,math.min(130,slider:GetValue()+delta*5))); commit()
    end)
    function host:SetValue(value) slider:SetValue(value*100) end
    self:AttachTooltip(slider,"Window scale","50–130%. Release to apply; after a click the mouse wheel adjusts by 5%.")
    host:SetValue(1); return host
end

function UI:NumberInput(parent, width, minimum, maximum, callback, options)
    -- Optional presentation only: never round the authoritative numeric value.
    if options and options.displayDecimals ~= nil then
        local decimals = options.displayDecimals
        assert(type(decimals) == "number" and decimals % 1 == 0 and decimals >= 0 and decimals <= 6, "Invalid number display precision")
        local input, rendered, editing
        local function show(full)
            local value = input.value or minimum
            local text = string.format(full and "%.17g" or ("%." .. decimals .. "f"), value)
            if not full and decimals > 0 then text = text:gsub("0+$", ""):gsub("%.$", "") end
            if not full and text == "-0" then text = "0" end
            rendered = text
            input:SetText(text)
            input:SetCursorPosition(0)
        end
        local function commit(text)
            editing = false
            -- Also avoids parsing a rounded display or a no-op Enter/Blur twice.
            if text ~= rendered then
                local value = tonumber(text)
                if ns.ProgressModel.Number(value) then
                    value = math.max(minimum, math.min(maximum, value))
                    if value ~= input.value then input.value = value; callback(value) end
                end
            end
            show(false)
        end
        input = self:Input(parent, width, commit)
        function input:SetValue(value) self.value = value; show(editing) end
        input:HookScript("OnEditFocusGained", function() editing = true; show(true) end)
        input:HookScript("OnEditFocusLost", function(self) ns:Call("number input", commit, self:GetText()) end)
        input:SetScript("OnEscapePressed", function(self)
            -- Edits are pending text only; the current value (including external updates) is intact.
            editing = false; show(false); self:ClearFocus()
        end)
        return input
    end
    local input
    local function commit(text)
        local value = tonumber(text)
        if not ns.ProgressModel.Number(value) then input:SetText(tostring(input.value or minimum)); return end
        value = math.max(minimum, math.min(maximum, value))
        if value ~= input.value then input.value = value; callback(value) end
        input:SetText(tostring(input.value))
    end
    input = self:Input(parent, width, commit)
    function input:SetValue(value) self.value = value; self:SetText(tostring(value)) end
    input:SetScript("OnEditFocusLost", function(self) ns:Call("number input", commit, self:GetText()) end)
    return input
end

function UI:Form(parent, width, height, scrollbarParent)
    local form = CreateFrame("ScrollFrame", nil, parent)
    D.Size(form,width - 22, height)
    form:EnableMouseWheel(true)
    form.content = CreateFrame("Frame", nil, form)
    D.Size(form.content,width - 24, 1)
    form:SetScrollChild(form.content)
    -- Clipped consumers can keep the scrollbar outside their viewport.
    form.slider = self:GetStyle():Slider(scrollbarParent or form,12,0,0,1,0)
    D.Point(form.slider,"TOPLEFT", form, "TOPRIGHT", 6, 0)
    D.Size(form.slider,12, height)
    form.slider:SetOrientation("VERTICAL"); form.slider:SetMinMaxValues(0, 0); form.slider:SetValueStep(1)
    form.slider.track:ClearAllPoints(); D.Point(form.slider.track,"TOP"); D.Point(form.slider.track,"BOTTOM"); D.Width(form.slider.track,3)
    local thumb = form.slider.AsScrollbar and form.slider:AsScrollbar() or form.slider:GetThumbTexture()
    D.Size(thumb,4, 32)
    form.slider:SetScript("OnValueChanged", function(_, value) form:SetVerticalScroll(D.ToNative(value)) end)
    form.slider:SetValue(0)
    form:SetScript("OnMouseWheel", function(_, delta)
        form.slider:SetValue(math.max(0, math.min(form.maximum or 0, form.slider:GetValue() - delta * 42)))
    end)
    form.rows = 0
    function form:SetContentHeight(value)
        self.rows=value; D.Height(self.content,math.max(1,value))
        self.maximum=math.max(0,value-D.GetHeight(self))
        self.slider:SetMinMaxValues(0,self.maximum)
        self.slider:SetValue(math.min(self.slider:GetValue(),self.maximum))
        self.slider:SetShown(self.maximum>0)
    end
    function form:Row(label, control, rowHeight)
        local y = self.rows
        local title = UI:Label(self.content, label, 14)
        D.Point(title,"TOPLEFT", 8, -y - 10); D.Width(title,300)
        D.Point(control,"TOPRIGHT", self.content, "TOPRIGHT", -8, -y)
        self.rows = y + (rowHeight or 46)
        D.Height(self.content,self.rows)
        self.maximum = math.max(0, self.rows - height)
        self.slider:SetMinMaxValues(0, self.maximum)
        self.slider:SetShown(self.maximum > 0)
        return control
    end
    return form
end

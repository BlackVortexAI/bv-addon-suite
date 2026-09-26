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
    function host:OpenPicker()
        if self.locked or not self:IsVisible() then return end
        UI:CloseDropdown()
        local popup=UI.colorPopup
        if not popup then
            popup=UI:DismissiblePopup(UIParent,320,286);UI.colorPopup=popup
            D.Point(popup.panel,"CENTER",UIParent,"CENTER",0,0);popup.panel:SetClampedToScreen(true)
            UI:Place(UI:Label(popup.panel,"Color",16,"text"),popup.panel,16,12)
            popup.sample=popup.panel:CreateTexture(nil,"ARTWORK");D.Point(popup.sample,"TOPRIGHT",-16,-16);D.Size(popup.sample,48,30)
            popup.hex=UI:Input(popup.panel,176,function(text)
                local hex,c=colorHex(text)
                if hex then popup:SetColor(c) else popup.hex:SetText(popup.value or "") end
            end);popup.hex:SetMaxLetters(9);UI:Place(popup.hex,popup.panel,16,43)
            popup.sliders={};popup.labels={}
            function popup:SetColor(c)
                self.updating=true;self.color={unpack(c)}
                for i,slider in ipairs(self.sliders)do slider:SetValue(math.floor(c[i]*255+.5));self.labels[i]:SetText(({"R","G","B","A"})[i].."  "..math.floor(c[i]*255+.5))end
                self.value=colorHex(string.format("%02X%02X%02X%02X",math.floor(c[1]*255+.5),math.floor(c[2]*255+.5),math.floor(c[3]*255+.5),math.floor(c[4]*255+.5)))
                self.hex:SetText(self.value);self.sample:SetColorTexture(unpack(c));self.updating=false
            end
            for i=1,4 do
                local index=i
                popup.labels[i]=UI:Place(UI:Label(popup.panel,"",12,"muted"),popup.panel,16,88+(i-1)*32)
                local slider=UI:GetStyle():Slider(popup.panel,210,0,255,1,255);popup.sliders[i]=slider
                UI:Place(slider,popup.panel,90,86+(i-1)*32)
                slider:SetScript("OnValueChanged",function(_,v)
                    if popup.updating or not popup.owner then return end
                    local c={unpack(popup.color)};c[index]=math.floor(v+.5)/255;popup:SetColor(c)
                end)
            end
            popup.cancel=UI:Place(UI:Button(popup.panel,"Cancel",130,function()popup:Hide()end),popup.panel,16,238)
            popup.apply=UI:Place(UI:Button(popup.panel,"Apply",130,function()
                local owner,value=popup.owner,colorHex(popup.hex:GetText())
                if not value then popup.hex:SetText(popup.value or "");return end
                popup:Hide()
                if owner and owner:IsVisible() and not owner.locked then owner:SetValue(value);ns:Call("color picker",owner.callback,value)end
            end),popup.panel,174,238)
            popup:HookScript("OnHide",function(self)self.owner=nil;self.hex:ClearFocus()end)
        end
        popup:Hide();popup.owner=self
        popup.panel:SetScale(self:GetEffectiveScale()/UIParent:GetEffectiveScale())
        popup:SetColor(select(2,colorHex(self.value or "")) or {1,1,1,1});popup:Open()
    end
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
    local host=CreateFrame("Frame",nil,parent); D.Size(host,width,44)
    local label=self:Label(host,"Window scale",11,"muted"); D.Point(label,"TOPLEFT")
    host.label=self:Label(host,"100%",11,"text"); D.Point(host.label,"TOPRIGHT")
    local slider=self:GetStyle():Slider(host,width,50,130,1,100); host.slider=slider
    D.Size(slider,width,20); D.Point(slider,"BOTTOMLEFT")
    slider:SetScript("OnValueChanged",function(_,value)
        host.value=math.floor(value+0.5)/100; host.label:SetText(string.format("%.0f%%",host.value*100))
    end)
    local function commit() ns:Call("window scale",callback,host.value) end
    slider:SetScript("OnMouseUp",commit)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel",function(_,delta)
        slider:SetValue(math.max(50,math.min(130,slider:GetValue()+delta*5))); commit()
    end)
    function host:SetValue(value) slider:SetValue(value*100) end
    self:AttachTooltip(slider,"Window scale","50–130%. Release to apply; mouse wheel adjusts by 5%.")
    host:SetValue(1); return host
end

function UI:NumberInput(parent, width, minimum, maximum, callback)
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
    local thumb = form.slider:GetThumbTexture()
    D.Size(thumb,6, 32)
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

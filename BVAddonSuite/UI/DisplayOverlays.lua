-- Central media additions. Native values live only in the source-to-widget call.
local _,ns=...
function ns.UI:DisplayOverlays(parent)
    local effect={parent=parent,borders={},borderSets={}}
    function effect:BindTexture(bar,path)
        local prior=bar.mediaTexture
        if prior and prior.path==path then return prior.ready,prior.status end
        local function apply(value)
            local ok,result=pcall(bar.SetStatusBarTexture,bar,value)
            return ok and not ns.GraphValues.IsSecret(result) and result~=false
        end
        local ready=apply(path);local status=ready and "ready" or "texture failed; bundled fallback"
        if not ready then local fallback=ns.Media:StatusBar("flat");ready=apply(fallback) end
        if not ready then status="texture unavailable" end
        bar.mediaTexture={path=path,ready=ready,status=status}
        return ready,status
    end
    function effect:Stop()
        self.mode=nil
        self.fontStatus=nil;self.textureStatus=nil
        if self.durationBound and self.durationBar then
            -- Use an addon-owned zero duration to release the previous native
            -- timer. Never mutate an object supplied by a Unit API.
            pcall(function()
                self.emptyDuration=self.emptyDuration or C_DurationUtil.CreateDuration()
                self.durationBar:SetTimerDuration(self.emptyDuration)
            end)
            self.durationBound=nil
        end
        for _,bar in pairs({self.valueBar,self.durationBar}) do
            pcall(function()bar:SetMinMaxValues(0,1);bar:SetValue(0)end);bar:Hide()
        end
        if self.background then self.background:Hide() end
        if self.cooldown then self.cooldown:Clear(); self.cooldown:Hide() end
        if self.label then self.label:SetText(""); self.label:Hide() end
        for _,set in pairs(self.borderSets) do for _,edge in ipairs(set) do edge:Hide() end end
        self.nativeStatus=nil
    end
    function effect:Present(media,source,fontScale)
        if not media then self:Stop();return end
        local mode=media.kind..(media.duration and "/duration" or media.nativeBinding and "/native" or "/value")
            ..(media.cooldown and "/cooldown" or "")..(media.overlay and "/overlay" or "")
        if self.mode~=mode then self:Stop();self.mode=mode end
        if media.kind=="bar" then
            if not self.background then self.background=parent:CreateTexture(nil,"BACKGROUND"); self.background:SetAllPoints(parent) end
            local key=media.duration and "durationBar" or "valueBar"
            if not self[key] then
                self[key]=CreateFrame("StatusBar",nil,parent); self[key]:EnableMouse(false); self[key]:SetAllPoints(parent)
                self[key]:SetFrameLevel(parent:GetFrameLevel()+1);self.borderSets[key]={}
            end
            -- Timer-driven and numeric bars are independently pooled: an old
            -- timer can never overwrite a subsequent numeric bar value.
            self.bar=self[key];self.borders=self.borderSets[key]
            ns.UI:DisplayProperty(self.background,"SetColorTexture",unpack(media.background)); self.background:Show()
            local texture,status=ns.Media:StatusBar(media.texture)
            local textureReady,textureStatus=self:BindTexture(self.bar,texture)
            self.textureStatus=textureStatus~="ready" and textureStatus or status
            ns.UI:DisplayProperty(self.bar,"SetStatusBarColor",media.color[1],media.color[2],media.color[3],media.color[4] or 1)
            ns.UI:DisplayProperty(self.bar,"SetOrientation",(media.direction=="UP" or media.direction=="DOWN") and "VERTICAL" or "HORIZONTAL")
            ns.UI:DisplayProperty(self.bar,"SetReverseFill",media.direction=="LEFT" or media.direction=="DOWN")
            local bound=true
            if media.duration then
                local ok=pcall(function() self.bar:SetTimerDuration(ns.GraphValues.Object(media.duration,"duration")) end)
                self.durationBound=ok or self.durationBound;bound=ok;self.nativeStatus=ok and "bound" or "error"
            elseif media.nativeBinding then
                bound=false; self.nativeStatus="unavailable"
                if source then bound,self.nativeStatus=source:BindHealth(self.bar) end
            else
                -- Never compare/clamp opaque values in Lua; the native bar owns
                -- range handling. The same setters handle HP, power or numbers.
                local opaque=ns.GraphValues.IsSecret(media.value) or ns.GraphValues.IsSecret(media.maximum)
                local value=opaque and media.value or math.min(media.value,media.maximum)
                local ok=pcall(function()
                    self.bar:SetMinMaxValues(0,ns.GraphValues.Native(media.maximum))
                    self.bar:SetValue(ns.GraphValues.Native(value))
                end)
                bound=ok; self.nativeStatus=ok and "bound" or "error"
            end
            if not textureReady then bound=false;self.nativeStatus="texture unavailable" end
            if not bound then local status,textureStatus=self.nativeStatus,self.textureStatus;self:Stop();self.nativeStatus=status;self.textureStatus=textureStatus end
            self.bar:SetShown(bound==true)
            self.background:SetShown(bound==true)
            local w,h=parent:GetWidth(),parent:GetHeight()
            local t=math.min(media.borderWidth,w/2,h/2)
            if t>0 then
                local edges={{0,(h-t)/2,w,t},{0,-(h-t)/2,w,t},{-(w-t)/2,0,t,h-2*t},{(w-t)/2,0,t,h-2*t}}
                for i,r in ipairs(edges) do
                    if not self.borders[i] then self.borders[i]=self.bar:CreateTexture(nil,"OVERLAY") end
                    local edge=self.borders[i]
                    if r[3]>0 and r[4]>0 then
                        ns.UI:PlaceDisplayRegion(edge,"CENTER",parent,"CENTER",r[1],r[2],r[3],r[4])
                        ns.UI:DisplayProperty(edge,"SetColorTexture",unpack(media.borderColor)); edge:Show()
                    else edge:Hide() end
                end
            else for _,edge in ipairs(self.borders) do edge:Hide() end end
        end
        if media.cooldown or (media.duration and media.kind=="icon") then
            if not self.cooldown then
                self.cooldown=CreateFrame("Cooldown",nil,parent); self.cooldown:SetAllPoints(parent)
                self.cooldown:EnableMouse(false); self.cooldown:SetFrameLevel(parent:GetFrameLevel()+2)
            end
            ns.UI:DisplayProperty(self.cooldown,"SetHideCountdownNumbers",media.cooldown and not media.cooldown.showNumbers or false)
            ns.UI:ShapeCooldown(self.cooldown,media)
            local bound=false; self.nativeStatus="unavailable"
            if media.duration then
                bound=pcall(function() self.cooldown:SetCooldownFromDurationObject(ns.GraphValues.Object(media.duration,"duration")) end)
                self.nativeStatus=bound and "bound" or "error"
            elseif source then bound,self.nativeStatus=source:BindCooldown(self.cooldown,media.cooldown.spellID) end
            if not bound then self.cooldown:Clear() end
            self.cooldown:SetShown(bound==true)
        end
        if media.overlay then
            if not self.label then
                self.labelHost=CreateFrame("Frame",nil,parent); self.labelHost:SetAllPoints(parent)
                self.labelHost:EnableMouse(false); self.labelHost:SetFrameLevel(parent:GetFrameLevel()+3)
                self.label=self.labelHost:CreateFontString(nil,"OVERLAY")
            end
            local o=media.overlay; local label=self.label
            ns.UI:PlaceDisplayRegion(label,o.point,parent,o.point,o.offsetX,o.offsetY,parent:GetWidth(),parent:GetHeight())
            local size=math.max(1,math.min(512,o.fontSize*(fontScale or 1)))
            local path,availability=ns.Media:Font(o.font)
            local fontOK,status=ns.UI:ApplyMediaFont(label,path,size,o.outline=="NONE" and "" or o.outline)
            self.fontStatus=availability~="ready" and availability or status
            assert(fontOK,"Overlay font unavailable (including game fallback)")
            local textOK=fontOK and ns.UI:SetMediaText(label,o.text)
            ns.UI:DisplayProperty(label,"SetTextColor",unpack(o.color)); ns.UI:DisplayProperty(label,"SetWordWrap",false)
            ns.UI:DisplayProperty(label,"SetJustifyH",o.point:find("LEFT") and "LEFT" or o.point:find("RIGHT") and "RIGHT" or "CENTER")
            ns.UI:DisplayProperty(label,"SetJustifyV",o.point:find("TOP") and "TOP" or o.point:find("BOTTOM") and "BOTTOM" or "MIDDLE")
            label:SetShown(textOK)
        end
    end
    return effect
end

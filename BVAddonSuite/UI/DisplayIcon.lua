-- Shared pooled media renderer. Local mouse feedback has no update timer.
local _,ns=...
local M=ns.DisplayModel
-- Crop artwork only; atlas regions and custom graphic UVs keep their own bounds.
function ns.UI:ApplyIconCrop(image,enabled)
    local inset=enabled~=false and .08 or 0
    self:DisplayProperty(image,"SetTexCoord",inset,1-inset,inset,1-inset)
end
-- Normalized artwork coordinates work for icons, file textures and atlas regions.
-- Atlas metadata is classified before it is used in arithmetic.
function ns.UI:AtlasCoordinates(info)
    local V=ns.GraphValues
    if V.IsSecret(info) or type(info)~="table" or (canaccesstable and not canaccesstable(info)) then return end
    for _,key in ipairs({"tilesHorizontally","tilesVertically","sliceData"}) do if V.IsSecret(info[key]) then return end end
    if info.tilesHorizontally or info.tilesVertically or info.sliceData then return end
    local out={info.leftTexCoord,info.rightTexCoord,info.topTexCoord,info.bottomTexCoord}
    for i=1,4 do if not ns.GraphModel.Number(out[i]) or out[i]<0 or out[i]>1 then return end end
    if out[1]>=out[2] or out[3]>=out[4] then return end
    return out
end
function ns.UI:ApplyMediaCrop(image,media,atlasUV)
    local crop=media and (media.crop or (media.kind=="graphic" and media.texcoords))
    if not crop then local inset=media and media.atlas and 0 or media and media.cropBorder==false and 0 or .08;crop={inset,1-inset,inset,1-inset} end
    local l,r,t,b=unpack(crop)
    if media and media.flipX then l,r=r,l end
    if media and media.flipY then t,b=b,t end
    if media and media.atlas then
        if not atlasUV then return l==0 and r==1 and t==0 and b==1 end
        l,r=atlasUV[1]+(atlasUV[2]-atlasUV[1])*l,atlasUV[1]+(atlasUV[2]-atlasUV[1])*r
        t,b=atlasUV[3]+(atlasUV[4]-atlasUV[3])*t,atlasUV[3]+(atlasUV[4]-atlasUV[3])*b
    end
    self:DisplayProperty(image,"SetTexCoord",l,r,t,b)
    return true
end
-- Owned display properties only. Opaque native values bypass this cache.
function ns.UI:DisplayProperty(region,method,...)
    local count=select('#',...);local cache=region.displayProperties
    local old=cache and cache[method];local same=old and old.count==count
    for i=1,count do
        local value=select(i,...)
        if ns.GraphValues.IsSecret(value) then
            if cache then cache[method]=nil end
            return region[method](region,...)
        end
        if not old or old[i]~=value then same=false end
    end
    if same then return end
    region[method](region,...)
    cache=cache or {};region.displayProperties=cache
    cache[method]={count=count,...}
end
function ns.UI:PlaceDisplayRegion(region,point,parent,relative,x,y,width,height)
    local old=region.displayPlacement
    if not old or old.point~=point or old.parent~=parent or old.relative~=relative or old.x~=x or old.y~=y then
        region:ClearAllPoints();region:SetPoint(point,parent,relative,x,y)
    end
    if not old or old.width~=width or old.height~=height then region:SetSize(width,height) end
    if not old or old.point~=point or old.parent~=parent or old.relative~=relative or old.x~=x or old.y~=y or old.width~=width or old.height~=height then
        region.displayPlacement={point=point,parent=parent,relative=relative,x=x,y=y,width=width,height=height}
    end
end
-- Native text setter is the only consumer of protected text. Do not read text
-- back from FontStrings: effects reuse the original runtime handle instead.
function ns.UI:SetMediaText(region,value)
    local V=ns.GraphValues
    local ok=pcall(function()
        if V.IsSecret(value) then
            assert(V.Accepts("string",value),"Invalid secret text")
            region:SetText(V.Native(value))
        else region:SetText(value:gsub("|","||")) end
    end)
    if not ok then pcall(region.SetText,region,"") end
    return ok
end
local function fontReady(region,path,size,flags)
    if type(path)~="string" or path=="" then return false end
    local ok,result=pcall(region.SetFont,region,path,size,flags or "")
    if not ok then return false end
    if result==true then return true end
    -- Some clients do not return a success Boolean. Confirm the actual font,
    -- rather than accepting nil blindly or retaining an unrelated pooled font.
    if region.GetFont then
        local read,current,height=pcall(region.GetFont,region)
        if read and type(current)=="string" and type(height)=="number" then
            local function normalized(p) return p:gsub("/","\\"):lower() end
            return normalized(current)==normalized(path) and math.abs(height-size)<0.51
        end
    end
    return false
end
function ns.UI:ApplyMediaFont(region,path,size,flags)
    flags=flags or ""
    local old=region.displayFont
    if old and old.path==path and old.size==size and old.flags==flags then return true,old.status end
    local ready=fontReady(region,path,size,flags);local status=ready and "ready" or "font failed; game fallback"
    if not ready then ready=fontReady(region,"Fonts\\FRIZQT__.TTF",size,flags) end
    region.displayFont=ready and {path=path,size=size,flags=flags,status=status} or nil
    return ready,ready and status or "font unavailable"
end
function ns.UI:DisplayIcon()
    local view=CreateFrame("Button",nil,UIParent)
    view:SetFrameStrata("MEDIUM"); view:EnableMouse(false); view:Hide()
    view.image=view:CreateTexture(nil,"ARTWORK"); view.image:SetAllPoints(view)
    view.caption=view:CreateFontString(nil,"OVERLAY"); view.caption:SetAllPoints(view); view.caption:Hide()
    view:RegisterForClicks("LeftButtonUp","RightButtonUp","MiddleButtonUp")
    function view:SetDisplayLevel(level)
        self.displayLevel=level
        level=level+(self.nativeLevelBase or 0)
        if self:GetFrameLevel()==level then return end
        self:SetFrameLevel(level)
        local overlays=self.overlays
        if overlays then
            for key,offset in pairs({valueBar=1,durationBar=1,cooldown=2,labelHost=3})do
                if overlays[key] then overlays[key]:SetFrameLevel(level+offset) end
            end
        end
        if self.feedbackLayer then self.feedbackLayer:SetFrameLevel(level+4) end
    end
    local function supportedButton(button)
        return not ns.GraphValues.IsSecret(button) and (button=="LeftButton" or button=="RightButton" or button=="MiddleButton")
    end
    view:SetScript("OnMouseDown",function(self,button)
        ns:RecordDisplayInput("down")
        if supportedButton(button) and self:FeedbackLive() and self:IsMouseEnabled() then
            self.feedbackHover=true;self.feedbackDown=self.feedbackDown or {};self.feedbackDown[button]=true;self:RefreshFeedback()
        end
    end)
    view:SetScript("OnMouseUp",function(self,button)
        ns:RecordDisplayInput("up")
        if supportedButton(button) and self.feedbackDown then self.feedbackDown[button]=nil;self:RefreshFeedback() end
    end)
    view:SetScript("OnClick",function(self,button)
        ns:RecordDisplayInput("click")
        if not self:IsVisible() or not self:IsMouseEnabled() or not self.inputHandler or not self.interaction or not self.interaction.enabled then return end
        if issecretvalue and issecretvalue(button) then return end
        if button~="LeftButton" and button~="RightButton" and button~="MiddleButton" then return end
        local event={key=self.interaction.key,button=button,payload=self.interaction.payload}
        for key,fn in pairs({shift=IsShiftKeyDown,control=IsControlKeyDown,alt=IsAltKeyDown}) do
            local value=fn and fn()
            if issecretvalue and issecretvalue(value) then return end
            event[key]=value==true
        end
        self.inputHandler(event)
    end)
    view:SetScript("OnEnter",function(self)
        if self:FeedbackLive() and self:IsMouseEnabled() then self.feedbackHover=true;self:RefreshFeedback() end
        if self.interaction and self.inputHandler and self.interaction.enabled and self.interaction.tooltip~="" then
            ns.UI:ShowTooltip(self,"AuraStudio",self.interaction.tooltip:gsub("|","||"))
        end
    end)
    view:SetScript("OnLeave",function(self) self:ResetFeedback();self:RefreshFeedback();ns.UI:HideTooltip(self) end)
    view:SetScript("OnHide",function(self)
        if self.buttonSkin then self.buttonSkin:Paint(nil) end
        ns.Media:Unsubscribe(self);self.mediaWatching=nil
        self.visible=false; if self.glowView then self.glowView:Stop() end
        if self.decorations then self.decorations:Stop() end
        if self.overlays then self.overlays:Stop() end
        self:ResetFeedback()
        ns.UI:HideTooltip(self)
    end)
    view:SetScript("OnShow",function(self)
        -- UIParent can be hidden/restored independently of graph evaluation.
        if not self.visible and self.lastValue then self:Present(self.lastValue,true) end
        self:WatchMedia(self.lastValue)
    end)
    function view:WatchMedia(media)
        local needed=self:IsVisible() and type(media)=="table" and (media.kind=="text" or media.kind=="bar" or media.overlay)
        if not needed then ns.Media:Unsubscribe(self);self.mediaWatching=nil;return end
        if self.mediaWatching then return end
        self.mediaWatching=true
        ns.Media:Subscribe(self,function(owner,kind,key)
            local m=owner.lastValue;if type(m)~="table" or not owner:IsVisible() then return end
            local ref="lsm:"..key
            local used=kind=="font" and ((m.kind=="text" and m.font==ref) or (m.overlay and m.overlay.font==ref))
                or kind=="statusbar" and m.kind=="bar" and m.texture==ref
            if used then owner.mediaDirty=true;owner:Present(m,true) end
        end)
    end
    function view:Geometry(rect)
        if (self.feedbackHover or self.feedbackDown) and not M.Equal(self.rect,rect) then self:ResetFeedback() end
        self.rect=ns.LayoutModel.Copy(rect)
    end
    function view:SetNativeSource(source)
        if self.nativeSource~=source then self:ResetFeedback() end
        self.nativeSource=source
    end
    function view:SetInputHandler(handler,identity,instance)
        if self.inputHandler==handler and self.inputIdentity==identity and self.inputInstance==instance then return end
        self:ResetFeedback()
        self.inputHandler=handler;self.inputIdentity=identity;self.inputInstance=instance
        self:RefreshInput(self.lastValue)
    end
    function view:ResetFeedback()
        self.feedbackHover=nil;self.feedbackDown=nil;self.feedbackState=nil
        if self.feedbackLayer then self.feedbackLayer:Hide() end
    end
    function view:FeedbackLive()
        return self.feedbackShown==true and self:IsVisible() and self.inputHandler~=nil
            and self.interaction~=nil and self.interaction.feedback==true
    end
    function view:RefreshFeedback()
        if not self:FeedbackLive() then self:ResetFeedback();return end
        local state
        if not self.interaction.enabled then state="disabled"
        elseif self.feedbackDown and next(self.feedbackDown) then state="pressed"
        elseif self.feedbackHover then state="hover" end
        self.feedbackState=state
        if not state then if self.feedbackLayer then self.feedbackLayer:Hide() end;return end
        if not self.feedbackLayer then
            local layer=CreateFrame("Frame",nil,self);layer:SetAllPoints(self);layer:EnableMouse(false)
            self.feedbackLayer=layer;self.feedbackTexture=layer:CreateTexture(nil,"OVERLAY");self.feedbackTexture:SetAllPoints(layer)
        end
        -- Native bars/cooldowns/labels use parent levels +1/+2/+3. This owned,
        -- non-interactive layer stays above them without changing their style.
        local level=self:GetFrameLevel()+4
        if self.feedbackLayer:GetFrameLevel()~=level then self.feedbackLayer:SetFrameLevel(level) end
        local white=state=="hover" and 1 or 0
        ns.UI:DisplayProperty(self.feedbackTexture,"SetColorTexture",white,white,white,state=="hover" and .12 or state=="pressed" and .22 or .45)
        local m=self.lastValue
        local maskPath=m and m.kind=="icon" and ns.IconSkins.Mask(m.iconSkin,m.iconShape,true) or nil
        if maskPath and m.iconShape and m.iconShape~="square" then
            local size=math.min(self:GetWidth(),self:GetHeight())
            ns.UI:PlaceDisplayRegion(self.feedbackTexture,"CENTER",self.feedbackLayer,"CENTER",0,0,size,size)
        elseif self.feedbackMaskPath then self.feedbackTexture:ClearAllPoints();self.feedbackTexture:SetAllPoints(self.feedbackLayer);self.feedbackTexture.displayPlacement=nil end
        if maskPath~=self.feedbackMaskPath then
            if self.feedbackMaskPath then self.feedbackTexture:RemoveMaskTexture(self.feedbackMask) end
            if maskPath then
                self.feedbackMask=self.feedbackMask or self.feedbackLayer:CreateMaskTexture()
                self.feedbackMask:SetAllPoints(self.feedbackTexture)
                self.feedbackMask:SetTexture(maskPath,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
                self.feedbackTexture:AddMaskTexture(self.feedbackMask)
            end
            self.feedbackMaskPath=maskPath
        end
        self.feedbackLayer:Show()
    end
    function view:RefreshInput(media)
        media=type(media)=="table" and media or nil
        local shown=media and media.alpha>0 and not self.assetUnavailable and not self.cropUnavailable
        if media and media.kind=="bar" then shown=shown and self.overlays and self.overlays.nativeStatus=="bound" end
        self.feedbackShown=shown==true
        local enabled=shown==true and self.inputHandler~=nil and self.interaction~=nil and self.interaction.enabled==true
        if self:IsMouseEnabled()~=enabled then self:EnableMouse(enabled) end
        if not self:IsMouseEnabled() then self:ResetFeedback();ns.UI:HideTooltip(self) end
        self:RefreshFeedback()
    end
    function view:Present(value,visible)
        local media=type(value)=="table" and value or nil
        local rect=self.rect
        if not visible or not rect then
            if self.iconSkin then self.iconSkin:Release() end
            if self.glowView then self.glowView:Stop() end
            if self.overlays then self.overlays:Stop() end
            pcall(self.caption.SetText,self.caption,"");pcall(self.image.SetTexture,self.image,nil)
            self:Hide(); self.visible=false; self.lastValue=nil; self.nativeSource=nil; self.assetUnavailable=nil; self.texture=nil; self.atlas=nil
            self.interaction=nil; self.inputHandler=nil;self.inputIdentity=nil;self.inputInstance=nil;self.feedbackShown=nil;self.feedbackGeometry=nil;self.cropUnavailable=nil
            self:ResetFeedback();self.mediaText=nil; self:EnableMouse(false); return
        end
        local interaction=media and media.interaction or nil
        local lastMedia=type(self.lastValue)=="table" and self.lastValue or nil
        local prior=lastMedia and lastMedia.interaction or nil
        if (interaction and interaction.feedback) or (prior and prior.feedback) then
            if not prior or not interaction or prior.key~=interaction.key or prior.enabled~=interaction.enabled or prior.feedback~=interaction.feedback
                or not M.Equal(lastMedia and lastMedia.nativeBinding,media and media.nativeBinding)
                or (lastMedia and lastMedia.kind)~=(media and media.kind) then self:ResetFeedback() end
        end
        if not prior or not interaction or prior.key~=interaction.key or prior.tooltip~=interaction.tooltip or prior.enabled~=interaction.enabled then ns.UI:HideTooltip(self) end
        self.interaction=interaction
        self:RefreshInput(media)
        if self.visible and not self.mediaDirty and not (media and (media.nativeBinding or media.cooldown or media.duration)) and M.SameVisual(self.lastValue,value) and M.Equal(self.lastRect,rect) then
            self.lastValue=ns.GraphValues.RuntimeCopy(value);return
        end
        local visual=M.Transform(rect,media,"visual")
        if interaction and interaction.feedback then
            if not M.Equal(self.feedbackGeometry,visual) then self:ResetFeedback();self.feedbackGeometry=ns.LayoutModel.Copy(visual) end
        else self.feedbackGeometry=nil end
        if visual.width<=0 or visual.height<=0 then if self.glowView then self.glowView:Stop() end; self:EnableMouse(false); self:Hide(); self.visible=false; return end
        -- Attached media keeps its native anchor while its content changes.
        -- The attachment helper applies geometry after presentation.
        if not self.nativeAnchor then
            ns.UI:PlaceDisplayRegion(self,"CENTER",UIParent,"CENTER",visual.x,visual.y,visual.width,visual.height)
        elseif not self.nativeGeometry or self.nativeGeometry.width~=visual.width or self.nativeGeometry.height~=visual.height then
            -- Effects below use owned dimensions immediately; the attachment
            -- boundary will then apply the corresponding native anchor.
            self:SetSize(visual.width,visual.height)
        end
        self:SetAlpha(media and media.alpha or 1)
        if media and media.buttonStyle and not self.buttonSkin then self.buttonSkin=ns.UI:ButtonSkin(self) end
        if self.buttonSkin then
            self.buttonSkin:Prepare(media and media.buttonStyle,media and media.surface,visual.width,visual.height)
            self.buttonSkin:Paint(media)
        end
        if media and media.iconSkin and not self.iconSkin then self.iconSkin=ns.UI:IconSkin(self,self.image,false,self.buttonSkin) end
        if self.iconSkin then self.iconSkin:Prepare(media and media.iconSkin,visual,media and media.iconShape) end
        local isText=media and media.kind=="text"
        local isBar=media and media.kind=="bar"
        if isText or isBar then self.assetUnavailable=nil; self.texture=nil;self.cropUnavailable=nil end
        local region=isText and self.caption or self.image
        self.image:SetShown(not isText and not isBar); self.caption:SetShown(isText==true)
        local color=media and media.color or {1,1,1}
        if isText then
            local layout=M.Transform({x=0,y=0,width=1,height=1},media,"layout")
            local size=math.max(1,math.min(512,media.fontSize*visual.fontScale*layout.fontScale))
            local path,availability=ns.Media:Font(media.font)
            local fontOK,fontStatus=ns.UI:ApplyMediaFont(self.caption,path,size,media.fontFlags and media.fontFlags~="NONE" and media.fontFlags or "")
            self.fontStatus=availability~="ready" and availability or fontStatus
            assert(fontOK,"Text font unavailable (including game fallback): "..tostring(path).." / "..tostring(size))
            self.mediaText=media.text
            local textOK=fontOK and ns.UI:SetMediaText(self.caption,media.text)
            self.assetUnavailable=not textOK; self.caption:SetShown(textOK)
            self.renderStatus=textOK and self.fontStatus or "text unavailable"
            ns.UI:DisplayProperty(self.caption,"SetTextColor",color[1],color[2],color[3],color[4] or 1)
            ns.UI:DisplayProperty(self.caption,"SetJustifyH",media.align); ns.UI:DisplayProperty(self.caption,"SetJustifyV","MIDDLE"); ns.UI:DisplayProperty(self.caption,"SetWordWrap",media.wrap)
            self.texture=nil
        elseif not isBar then
            local texture=media and media.texture or value
            local atlas=media and media.atlas
            if self.texture~=texture or self.atlas~=atlas then
                local ok,loaded
                if atlas then
                    ok,loaded=pcall(function()
                        if not C_Texture or not C_Texture.GetAtlasInfo then return false end
                        local info=C_Texture.GetAtlasInfo(atlas)
                        if ns.GraphValues.IsSecret(info) or type(info)~="table" then return false end
                        self.atlasUV=ns.UI:AtlasCoordinates(info)
                        local loaded=self.image:SetAtlas(atlas,false);self.image.displayProperties=nil
                        return ns.GraphValues.IsSecret(loaded) or loaded~=false
                    end)
                else ok,loaded=pcall(self.image.SetTexture,self.image,ns.GraphValues.Native(texture)) end
                self.texture=texture;self.atlas=atlas
                self.assetUnavailable=not ok or (not ns.GraphValues.IsSecret(loaded) and loaded==false)
            end
            self.image:SetShown(not self.assetUnavailable)
            self.renderStatus=self.assetUnavailable and "asset unavailable" or "ready"
            if not atlas and self.image.displayWasAtlas then self.image.displayProperties=nil end
            local cropOK=ns.UI:ApplyMediaCrop(self.image,media,atlas and self.atlasUV)
            self.cropUnavailable=not cropOK
            if not cropOK then self.image:Hide();self.renderStatus="atlas crop unavailable" end
            ns.UI:DisplayProperty(self.image,"SetBlendMode",media and media.blendMode or "BLEND")
            self.image.displayWasAtlas=atlas~=nil
            ns.UI:DisplayProperty(self.image,"SetVertexColor",color[1],color[2],color[3],color[4] or 1)
        end
        local angle=math.rad(visual.angle%360)
        assert(not (isBar or (media and (media.cooldown or media.duration or media.overlay))) or angle==0,
            "Rotation of bars and media overlays is not supported")
        if region.SetRotation then ns.UI:DisplayProperty(region,"SetRotation",angle)
        else assert(angle==0,"Rotation is unavailable for this media type on this client") end
        if media and (media.textOutline or media.textShadow or media.iconBorder or media.surface) and not self.decorations then self.decorations=ns.UI:DisplayDecorations(self) end
        if self.decorations then
            local decorated=media
            if media and media.buttonStyle then decorated=ns.GraphValues.RuntimeCopy(media);decorated.surface=nil end
            self.decorations:Present(not self.assetUnavailable and not self.cropUnavailable and decorated or nil,angle)
        end
        if media and media.glow>0 and not self.glowView then self.glowView=ns.UI:DisplayGlow(self) end
        if self.glowView then self.glowView:Present(not self.assetUnavailable and not self.cropUnavailable and media or nil,angle) end
        if media and (isBar or media.cooldown or media.duration or media.overlay) and not self.overlays then self.overlays=ns.UI:DisplayOverlays(self) end
        if self.overlays then
            local layout=M.Transform({x=0,y=0,width=1,height=1},media,"layout")
            self.overlays:Present(media,self.nativeSource,visual.fontScale*layout.fontScale)
            if isBar then self.renderStatus=self.overlays.textureStatus or self.overlays.nativeStatus end
            if self.overlays.fontStatus and self.overlays.fontStatus~="ready" then self.renderStatus=self.overlays.fontStatus end
        end
        self:RefreshInput(media)
        self.lastValue=ns.GraphValues.RuntimeCopy(value); self.lastRect=ns.LayoutModel.Copy(rect)
        self.visible=true; self:Show()
        if self.iconSkin then
            local status=self.iconSkin:Paint(media,not self.assetUnavailable)
            if status~="ready" then self.renderStatus=status end
        end
        self.mediaDirty=nil;self:WatchMedia(media)
        self:RefreshFeedback()
    end
    return view
end

-- Masque receives an artwork host, never our protected action button.
-- Secure hosts are UIParent siblings with absolute geometry and no secure anchors.
local _,ns=...
local UI,K,V=ns.UI,ns.IconSkins,ns.GraphValues
function UI:ShapeCooldown(cooldown,media)
    local path=K.Mask(media.iconSkin,media.iconShape,true)
    if path and media.iconShape and media.iconShape~="square" then
        local parent=cooldown:GetParent();local size=math.min(parent:GetWidth(),parent:GetHeight())
        self:PlaceDisplayRegion(cooldown,"CENTER",parent,"CENTER",0,0,size,size)
    elseif cooldown.bvShapeMask then cooldown:ClearAllPoints();cooldown:SetAllPoints(cooldown:GetParent());cooldown.displayPlacement=nil end
    if cooldown.bvShapeMask==path then return end
    if path then
        if not cooldown.bvShapeDefaults then cooldown.bvShapeDefaults={edge=cooldown:GetDrawEdge(),bling=cooldown:GetDrawBling()} end
        cooldown:SetSwipeTexture(path);cooldown:SetDrawEdge(false);cooldown:SetDrawBling(false)
    elseif cooldown.bvShapeDefaults then
        cooldown:SetSwipeTexture("",0,0,0,.8)
        cooldown:SetDrawEdge(cooldown.bvShapeDefaults.edge);cooldown:SetDrawBling(cooldown.bvShapeDefaults.bling)
        cooldown.bvShapeDefaults=nil
    end
    cooldown.bvShapeMask=path
end
function UI:IconSkin(button,image,secure,fallback)
    local skin={button=button,image=image,secure=secure,fallback=fallback}
    skin.rim=button:CreateTexture(nil,"OVERLAY",nil,2);skin.rim:SetAllPoints(button);skin.rim:SetAlpha(0)
    skin.pushed=button:CreateTexture(nil,"OVERLAY",nil,3);skin.pushed:SetAllPoints(button);skin.pushed:SetAlpha(0)
    skin.highlight=button:CreateTexture(nil,"HIGHLIGHT");skin.highlight:SetAllPoints(button);skin.highlight:SetAlpha(0)
    local function visibility(shown)
        if skin.host then skin.host:SetShown(shown and skin.style=="masque" and skin.contentVisible==true and skin.registered==true) end
    end
    button:HookScript("OnHide",function()visibility(false)end)
    button:HookScript("OnShow",function()visibility(true)end)
    function skin:Detach()
        if self.registered then
            pcall(self.group.RemoveButton,self.group,self.host)
            self.registered=nil
        end
        if self.host then self.host:Hide() end
    end
    function skin:ClearMask()
        if self.maskAttached then image:RemoveMaskTexture(self.mask);self.maskAttached=nil end
        self.maskReady=true
    end
    function skin:Prepare(id,rect,shape)
        id=id or "none"
        shape=shape or "square"
        local same=self.style==id and self.shape==shape and self.rect and self.rect.x==rect.x and self.rect.y==rect.y and self.rect.width==rect.width and self.rect.height==rect.height
        if same and (id~="masque" or self.registered) then return end
        if self.secure then assert(not InCombatLockdown(),"Prepare icon skin outside combat") end
        if self.style~=id then self:Detach() end
        self:ClearMask()
        self.style=id;self.shape=shape;self.rect={x=rect.x,y=rect.y,width=rect.width,height=rect.height};self.status="ready"
        image:ClearAllPoints()
        if id~="none" and id~="masque" then
            local scale=id=="echo" and 1 or .75
            local width,height=rect.width,rect.height
            if shape~="square" then width=math.min(width,height);height=width end
            image:SetPoint("CENTER",button,"CENTER",0,0);image:SetSize(width*scale,height*scale)
            for _,texture in ipairs({self.rim,self.pushed,self.highlight}) do
                texture:ClearAllPoints();texture:SetPoint("CENTER",button,"CENTER",0,0);texture:SetSize(width,height)
            end
            local path=K.Path(id,shape)
            self.rim:SetTexture(path);self.rim:SetTexCoord(0,.5,0,.5)
            self.pushed:SetTexture(path);self.pushed:SetTexCoord(.5,1,0,.5)
            self.highlight:SetTexture(path);self.highlight:SetTexCoord(0,.5,.5,1);self.highlight:SetBlendMode("ADD")
            button:SetPushedTexture(self.pushed);button:SetHighlightTexture(self.highlight)
            local maskPath=K.Mask(id,shape)
            if maskPath then
                if button.CreateMaskTexture and image.AddMaskTexture and image.RemoveMaskTexture then
                    self.mask=self.mask or button:CreateMaskTexture()
                    self.mask:ClearAllPoints();self.mask:SetAllPoints(image)
                    self.mask:SetTexture(maskPath,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
                    image:AddMaskTexture(self.mask);self.maskAttached=true
                else self.maskReady=false;self.status="icon mask unavailable" end
            end
        else
            image:SetAllPoints(button)
            local states=self.fallback or button.buttonSkin
            if states then button:SetPushedTexture(states.pushed);button:SetHighlightTexture(states.highlight) end
        end
        image:SetAlpha(1);image.displayProperties=nil
        if id~="masque" then return end
        local api=K:Masque()
        if not api then self.status="Masque unavailable; original icon";return end
        if not self.host then
            self.host=CreateFrame("Frame",nil,secure and UIParent or button)
            self.host:EnableMouse(false);self.host:Hide()
            if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(self.host) end
            self.art=self.host:CreateTexture(nil,"ARTWORK");self.art:SetAllPoints(self.host)
            self.normal=self.host:CreateTexture(nil,"OVERLAY");self.normal:SetAllPoints(self.host)
        end
        if secure then
            self.host:ClearAllPoints();self.host:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y);self.host:SetSize(rect.width,rect.height)
            self.host:SetFrameStrata("MEDIUM");self.host:SetFrameLevel(button:GetFrameLevel()+1)
        else self.host:SetAllPoints(button);self.host:SetFrameLevel(button:GetFrameLevel()+1) end
        self.group=self.group or api:Group("BV Addon Suite","Icons","bv-icons")
        local ok
        if self.registered then ok=pcall(self.group.ReSkin,self.group,self.host)
        else
            ok=pcall(self.group.AddButton,self.group,self.host,{Icon=self.art,Normal=self.normal,Cooldown=false,Count=false,Duration=false,DebuffBorder=false},"Aura",true)
        end
        self.registered=ok==true
        if not ok then pcall(self.group.RemoveButton,self.group,self.host);self.status="Masque skin failed; original icon";self.host:Hide() end
    end
    function skin:Paint(media,visible)
        local active=visible and media and media.kind=="icon" and self.maskReady~=false
        if self.maskReady==false then UI:DisplayProperty(image,"SetAlpha",0) end
        local opacity=active and media.alpha or 0
        local own=active and self.style~="none" and self.style~="masque"
        self.rim:SetAlpha(own and opacity or 0);self.pushed:SetAlpha(own and opacity or 0);self.highlight:SetAlpha(own and opacity or 0)
        self.contentVisible=active==true
        if active and self.style=="masque" and self.registered then
            if media.atlas then
                if self.atlas~=media.atlas then self.art:SetAtlas(media.atlas,false);pcall(self.group.ReSkin,self.group,self.host) end
            else self.art:SetTexture(V.Native(media.texture)) end
            self.atlas=media.atlas
            -- Masque owns UVs and region geometry; BV owns the actual spell artwork.
            self.art:SetVertexColor(unpack(media.color));self.host:SetAlpha(opacity)
            if secure then self.host:SetFrameLevel(button:GetFrameLevel()+1) end
            UI:DisplayProperty(image,"SetAlpha",0);visibility(button:IsVisible())
        else visibility(false) end
        return self.status or "ready"
    end
    function skin:Release()
        self:Detach();self:ClearMask();self.contentVisible=nil;self.style=nil;self.shape=nil;self.rect=nil
        self.rim:SetAlpha(0);self.pushed:SetAlpha(0);self.highlight:SetAlpha(0)
    end
    return skin
end

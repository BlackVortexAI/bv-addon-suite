-- Native glyph/flipbook effects plus bounded LibCustomGlow adapters.
-- Sprite layouts are documented in docs/glow-research.md. No ActionBar manager.
local _,ns=...
local M=ns.DisplayModel
local PROC="UI-HUD-ActionBar-Proc-Loop-Flipbook"
local CLASSIC="Interface\\SpellActivationOverlay\\IconAlert"
local ANTS="Interface\\SpellActivationOverlay\\IconAlertAnts"
local function atlasAvailable()
    if not C_Texture or not C_Texture.GetAtlasInfo then return false end
    local ok,info=pcall(C_Texture.GetAtlasInfo,PROC); return ok and type(info)=="table"
end
local function flipbook(texture,rows,columns,frames,pixels)
    local group,animation
    local ok=pcall(function()
        group=texture:CreateAnimationGroup(); group:SetLooping("REPEAT")
        animation=group:CreateAnimation("FlipBook")
        animation:SetOrder(1); animation:SetDuration(1)
        animation:SetFlipBookRows(rows); animation:SetFlipBookColumns(columns); animation:SetFlipBookFrames(frames)
        animation:SetFlipBookFrameWidth(pixels); animation:SetFlipBookFrameHeight(pixels)
    end)
    if not ok then if group then pcall(group.Stop,group) end; return end
    return group,animation
end
local function texture(parent)
    local t=parent:CreateTexture(nil,"OVERLAY"); t:Hide(); t:SetBlendMode("ADD"); return t
end
function ns.UI:DisplayGlow(parent)
    local effect={parent=parent,glyphs={},loops={},pulses={}}
    function effect:Pulse(region,options,maximum)
        local pulse=self.pulses[region]
        if not options.pulse or options.minimum==1 then
            if pulse and pulse.group then pulse.group:Stop() end
            region:SetAlpha(maximum); return
        end
        if pulse==nil then
            pulse={}; self.pulses[region]=pulse
            local group
            local ok=pcall(function()
                group=region:CreateAnimationGroup(); group:SetLooping("REPEAT")
                pulse.down=group:CreateAnimation("Alpha"); pulse.up=group:CreateAnimation("Alpha")
                for i,a in ipairs({pulse.down,pulse.up}) do
                    a:SetOrder(i); a:SetDuration(.8); a:SetFromAlpha(1); a:SetToAlpha(0)
                    if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
                end
            end)
            if ok then pulse.group=group else if group then pcall(group.Stop,group) end; pulse.failed=true end
        end
        if pulse.failed then self.pulseUnavailable=true; region:SetAlpha(maximum); return end
        if pulse.period~=options.period or pulse.minimum~=options.minimum or pulse.maximum~=maximum then
            pulse.group:Stop()
            pulse.down:SetDuration(options.period/2); pulse.up:SetDuration(options.period/2)
            pulse.down:SetFromAlpha(maximum); pulse.down:SetToAlpha(maximum*options.minimum)
            pulse.up:SetFromAlpha(maximum*options.minimum); pulse.up:SetToAlpha(maximum)
            pulse.period,pulse.minimum,pulse.maximum=options.period,options.minimum,maximum
        end
        if not pulse.group:IsPlaying() then pulse.group:Play() end
    end
    function effect:Loop(style,rows,columns,frames,pixels)
        local cached=self.loops[style]
        if cached==nil then
            local group,animation=flipbook(self.sprite,rows,columns,frames,pixels)
            cached=group and {group,animation} or false; self.loops[style]=cached
        end
        if cached then return cached[1],cached[2] end
    end
    function effect:Stop()
        if self.libHost then
            local lib=LibStub and LibStub("LibCustomGlow-1.0",true)
            if lib then
                if lib.PixelGlow_Stop then pcall(lib.PixelGlow_Stop,self.libHost,"BV") end
                if lib.AutoCastGlow_Stop then pcall(lib.AutoCastGlow_Stop,self.libHost,"BV") end
            end
            self.libHost:Hide();self.libRequest=nil
        end
        for _,pulse in pairs(self.pulses) do if pulse.group then pulse.group:Stop() end end
        if self.loop and self.loop:IsPlaying() then self.loop:Stop() end
        if self.base then self.base:Hide(); self.sprite:Hide() end
        for _,label in ipairs(self.glyphs) do label:SetText("");label:Hide() end
        self.visible=false
    end
    function effect:Library(style,options,strength,angle)
        local lib=LibStub and LibStub("LibCustomGlow-1.0",true)
        if not lib or options.speed==0 or angle~=0 then return false end
        local start=style=="pixel" and lib.PixelGlow_Start or lib.AutoCastGlow_Start
        if type(start)~="function" then return false end
        if not self.libHost then
            -- This adapter owns an unprotected display; creation is cosmetic.
            self.libHost=CreateFrame("Frame",nil,parent);self.libHost:EnableMouse(false)
        end
        if self.style~=style then self:Stop();self.style=style end
        local width,height=parent:GetWidth(),parent:GetHeight()
        local request={style=style,options=options,strength=strength,width=width,height=height}
        if not M.Equal(request,self.libRequest) then
            local ok=pcall(function()
                ns.UI:PlaceDisplayRegion(self.libHost,"CENTER",parent,"CENTER",options.offsetX,options.offsetY,width*options.scaleX,height*options.scaleY)
                self.libHost:SetFrameLevel(parent:GetFrameLevel()+4)
                local color={options.color[1],options.color[2],options.color[3],strength*options.color[4]}
                if style=="pixel" then start(self.libHost,color,8,.25*options.speed,nil,math.max(1,options.size/2),options.size,options.size,false,"BV")
                else start(self.libHost,color,4,.25*options.speed,math.max(.25,options.size/3),options.size,options.size,"BV") end
            end)
            if not ok then self:Stop();self.style=nil;return false end
            self.libRequest=ns.GraphValues.RuntimeCopy(request)
        end
        self.libHost:Show();self:Pulse(self.libHost,options,1)
        self.actualStyle=style.." (LibCustomGlow)";self.visible=true;return true
    end
    function effect:Icon(options,strength,angle)
        local style=options.iconStyle
        if style=="auto" or style=="proc" then style=(not self.procUnavailable and atlasAvailable()) and "proc" or "button" end
        if not self.base then self.base=texture(parent); self.sprite=texture(parent) end
        if self.style~=style then
            self:Stop(); self.style=style; self.loop,self.animation=nil,nil; self.duration=nil
            self.sprite:SetTexCoord(0,1,0,1)
            if style=="proc" then
                local ok,result=pcall(self.sprite.SetAtlas,self.sprite,PROC)
                if ok and result~=false then self.loop,self.animation=self:Loop("proc",6,5,30,0) end
                -- A static sprite sheet would display all frames. Fall back.
                if not self.loop then self.procUnavailable=true; style="button"; self.style=style end
            end
            if style=="button" then
                self.base:SetTexture(CLASSIC)
                self.base:SetTexCoord(.0078125,.5078125,.27734375,.52734375)
                self.sprite:SetTexture(ANTS)
                self.loop,self.animation=self:Loop("button",5,5,22,48)
                self.sprite:SetTexCoord(0,48/256,0,48/256)
            end
        end
        local color=options.color
        local w,h=parent:GetWidth(),parent:GetHeight()
        for _,region in ipairs({self.base,self.sprite}) do
            local x,y=M.Rotate(options.offsetX,options.offsetY,math.deg(angle))
            ns.UI:PlaceDisplayRegion(region,"CENTER",parent,"CENTER",x,y,(w*1.4+options.size*2)*options.scaleX,(h*1.4+options.size*2)*options.scaleY)
            if region.SetDesaturated then ns.UI:DisplayProperty(region,"SetDesaturated",true) end
            ns.UI:DisplayProperty(region,"SetVertexColor",color[1],color[2],color[3],1)
            region:SetAlpha(strength*color[4]); if region.SetRotation then ns.UI:DisplayProperty(region,"SetRotation",angle) end
        end
        self.base:SetShown(style=="button")
        self.sprite:SetShown(style=="proc" or self.loop~=nil)
        for _,region in ipairs({self.base,self.sprite}) do
            self:Pulse(region,region:IsShown() and options or {pulse=false},strength*color[4])
        end
        if self.loop then
            if options.speed>0 then
                -- Color/size changes do not replay the entrance or reset phase.
                local duration=(style=="button" and .3 or 1)/options.speed
                if self.duration~=duration then self.animation:SetDuration(duration); self.duration=duration end
                if not self.loop:IsPlaying() then
                    if style=="proc" then self.sprite:SetAtlas(PROC) else self.sprite:SetTexCoord(0,1,0,1) end
                    self.loop:Play()
                end
            else
                self.loop:Stop()
                if style=="proc" then self.sprite:SetTexCoord(0,1/5,0,1/6)
                else self.sprite:SetTexCoord(0,48/256,0,48/256) end
            end
        end
        self.actualStyle=style..(self.loop and "" or " (static fallback)"); self.visible=true
    end
    function effect:Text(options,strength,angle)
        if self.style~="text" then self:Stop(); self.style="text" end
        local caption=parent.caption
        local path,size=caption:GetFont()
        local count=options.textStyle=="outline" and 8 or options.textStyle=="shadow" and 8 or 16
        local color=options.color
        for i=1,count do
            local label=self.glyphs[i]
            if not label then label=parent:CreateFontString(nil,"BACKGROUND"); self.glyphs[i]=label end
            assert(ns.UI:ApplyMediaFont(label,path,size),"Glow font unavailable")
            local ring=i>8 and 2 or 1; local radians=(i-1)%8*math.pi/4
            local radius=options.size*(ring==1 and .5 or 1)
            if options.textStyle=="outline" then radius=options.size end
            if options.textStyle=="neon" then radius=options.size*(ring==1 and .25 or .7) end
            local x,y=M.Rotate(math.cos(radians)*radius+options.offsetX,math.sin(radians)*radius+options.offsetY,math.deg(angle))
            if options.textStyle=="shadow" then x,y=M.Rotate(math.cos(radians)*radius*.5+options.offsetX+options.size,math.sin(radians)*radius*.5+options.offsetY-options.size,math.deg(angle)) end
            ns.UI:PlaceDisplayRegion(label,"CENTER",parent,"CENTER",x,y,parent:GetWidth(),parent:GetHeight())
            ns.UI:DisplayProperty(label,"SetJustifyH",caption:GetJustifyH()); ns.UI:DisplayProperty(label,"SetJustifyV","MIDDLE"); ns.UI:DisplayProperty(label,"SetWordWrap",self.wrap)
            local textOK=ns.UI:SetMediaText(label,self.text)
            local weight=options.textStyle=="outline" and 1 or (ring==1 and .28 or .09)
            if options.textStyle=="neon" then weight=ring==1 and .55 or .12 end
            ns.UI:DisplayProperty(label,"SetTextColor",color[1],color[2],color[3],strength*color[4]*weight)
            if label.SetRotation then ns.UI:DisplayProperty(label,"SetRotation",angle) end
            self:Pulse(label,options,1)
            label:SetShown(textOK)
        end
        for i=count+1,#self.glyphs do self:Pulse(self.glyphs[i],{pulse=false},1); self.glyphs[i]:Hide() end
        self.actualStyle="text "..options.textStyle; self.visible=true
    end
    function effect:Present(media,angle)
        if not media or media.glow<=0 or media.alpha<=0 then self:Stop(); return end
        local options=M.GlowOptions(media)
        if options.color[4]<=0 then self:Stop(); return end
        local style=media.kind=="text" and options.textStyle or options.iconStyle
        if style=="pixel" or style=="autocast" then
            if self:Library(style,options,media.glow,angle) then return end
            options.iconStyle="button";options.speed=0;options.textStyle="soft"
            if media.kind=="text" then self.wrap=media.wrap;self.text=media.text;self:Text(options,media.glow,angle) else self:Icon(options,media.glow,angle) end
            self.actualStyle=style.." (static fallback)";return
        end
        if media.kind=="text" then self.wrap=media.wrap; self.text=media.text; self:Text(options,media.glow,angle)
        else self:Icon(options,media.glow,angle) end
    end
    return effect
end

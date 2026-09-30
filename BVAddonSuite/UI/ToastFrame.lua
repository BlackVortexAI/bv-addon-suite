-- Presentation of one timed toast note. Timing, stacking and ownership belong
-- to the caller; this frame is never protected and click-through by default.
local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
local ICON=28
function UI:ToastFrame(width)
    local t={width=width}
    local f=UI:Panel(UIParent,width,48,"canvas");t.frame=f
    f:SetFrameStrata("DIALOG");f:EnableMouse(false);f:SetClampedToScreen(true);f:Hide()
    t.icon=f:CreateTexture(nil,"ARTWORK");D.Size(t.icon,ICON,ICON);UI:Place(t.icon,f,12,10);t.icon:Hide()
    t.text=UI:Label(f,"",13,"text");t.text:SetWordWrap(true);t.text:SetJustifyH("LEFT");t.text:SetJustifyV("TOP")
    -- Native alpha animation: order 1 fades in, order 2 fades out after the hold.
    t.fade=f:CreateAnimationGroup();t.fade:SetToFinalAlpha(true)
    t.fadeIn=t.fade:CreateAnimation("Alpha");t.fadeIn:SetOrder(1)
    t.fadeOut=t.fade:CreateAnimation("Alpha");t.fadeOut:SetOrder(2)
    t.glyph=f:CreateTexture(nil,"ARTWORK");t.glyph:Hide()
    -- text: already escaped or protected; icon: texture reference or nil;
    -- symbol: {name,color,position,scale} shown next to the text (size = 13 x scale).
    function t:Present(text,icon,symbol)
        local x=14
        if icon~=nil then self.icon:SetTexture(icon);self.icon:Show();x=12+ICON+10 else self.icon:SetTexture(nil);self.icon:Hide() end
        local size,gap,top=0,6,12
        local path,l,r,tt,b
        if symbol then path,l,r,tt,b=ns.Symbols:Coords(symbol.name,13*symbol.scale*2) end
        if path then size=math.floor(13*symbol.scale+.5) end
        local textX,textW=x,self.width-x-14
        if size>0 and symbol.position=="left" then textX=x+size+gap;textW=textW-size-gap
        elseif size>0 and symbol.position=="right" then textW=textW-size-gap
        elseif size>0 and symbol.position=="above" then top=12+size+gap end
        UI:Place(self.text,self.frame,textX,top);D.Width(self.text,textW)
        self.text:SetText(text);self.text:SetHeight(0)
        local h=math.max(20,math.min(240,D.ToDesign(self.text:GetStringHeight())))
        D.Height(self.text,h)
        local body=h+(size>0 and (symbol.position=="above" or symbol.position=="below") and size+gap or 0)
        if size>0 then
            self.glyph:SetTexture(path);self.glyph:SetTexCoord(l,r,tt,b);self.glyph:SetVertexColor(unpack(symbol.color));D.Size(self.glyph,size,size)
            local gx,gy=x,12
            if symbol.position=="right" then gx=x+textW+gap elseif symbol.position=="below" then gy=12+h+gap end
            UI:Place(self.glyph,self.frame,gx,gy);self.glyph:Show()
        else self.glyph:Hide() end
        D.Height(self.frame,math.max(body,icon~=nil and ICON-4 or 0)+24)
    end
    return t
end

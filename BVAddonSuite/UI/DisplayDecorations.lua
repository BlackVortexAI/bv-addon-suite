-- Independent text and icon decorations; no layout mutation or Lua animation loop.
local _,ns=...
local M=ns.DisplayModel
-- Native Button owns hover/pressed state. Never replace its click scripts.
-- Secure callers allocate and prepare geometry outside combat; Paint is cosmetic.
function ns.UI:ButtonSkin(button)
    local skin={edges={},ornaments={},art=ns.UI:ButtonArtwork(button)}
    for _,key in ipairs({"normal","pushed","highlight"}) do
        local texture=button:CreateTexture(nil,key=="highlight" and "HIGHLIGHT" or "BACKGROUND")
        texture:SetAllPoints(button);skin[key]=texture
    end
    button:SetNormalTexture(skin.normal);button:SetPushedTexture(skin.pushed);button:SetHighlightTexture(skin.highlight)
    for i=1,4 do skin.edges[i]=button:CreateTexture(nil,"BORDER") end
    function skin:Prepare(style,surface,w,h)
        self.style=style;self.border=style~="wow" and (surface and surface.borderWidth or 1) or 0
        if self.art:Prepare(style,w,h) then self.border=0;self.ornamentCount=0;return end
        local t=math.min(self.border,w/2,h/2)
        local edges={{0,(h-t)/2,w,t},{0,-(h-t)/2,w,t},{-(w-t)/2,0,t,h-2*t},{(w-t)/2,0,t,h-2*t}}
        for i,r in ipairs(edges) do ns.UI:PlaceDisplayRegion(self.edges[i],"CENTER",button,"CENTER",r[1],r[2],math.max(.01,r[3]),math.max(.01,r[4])) end
        self.ornamentCount=0
        local function line(x1,y1,x2,y2,thickness)
            self.ornamentCount=self.ornamentCount+1
            local i=self.ornamentCount
            local l=self.ornaments[i] or button:CreateLine(nil,"BORDER",nil,1);self.ornaments[i]=l
            l:ClearAllPoints();l:SetStartPoint("CENTER",button,x1,y1);l:SetEndPoint("CENTER",button,x2,y2);l:SetThickness(thickness or 1)
        end
        local x,y=w/2,h/2
        local s=math.max(2,math.min(8,h/5,w/12))
        if M.buttonPalettes[style] then
            for _,v in ipairs({-1,1}) do
                if style=="arcane" or style=="frost" then
                    local cx=v*(x-s*1.5)
                    line(cx-s/2,0,cx,s);line(cx,s,cx+s/2,0);line(cx+s/2,0,cx,-s);line(cx,-s,cx-s/2,0)
                    for _,q in ipairs({-1,1}) do line(v*(x-3*s),q*(y-3),v*s,q*(y-3)) end
                    if style=="frost" then line(cx-s,0,cx+s,0);line(cx,-s*1.5,cx,s*1.5) end
                elseif style=="runic" then
                    for _,q in ipairs({-1,1}) do
                        line(v*(x-3),q*(y-s*2),v*(x-3),q*(y-3),2)
                        line(v*(x-3),q*(y-3),v*(x-s*2),q*(y-3),2)
                        line(v*(x-s),q*(y-3),v*(x-s),q*(y-s))
                        line(v*(x-s),q*(y-s),v*(x-3),q*(y-s))
                    end
                elseif style=="ember" then
                    line(v*(x-s*2),y-3,v*(x-3),0,2);line(v*(x-3),0,v*(x-s*2),-y+3,2)
                    line(v*(x-s*3),y-3,v*(x-s),0);line(v*(x-s),0,v*(x-s*3),-y+3)
                else
                    line(v*(x-3),v*(y-3),v*(x-s*3),v*(y-3),2)
                    line(v*(x-3),v*(y-3),v*(x-3),-v*(y-s),2)
                    for i=1,3 do line(v*(x-s*i),-v*(y-3),v*(x-s*i+s/2),-v*(y-3),2) end
                end
            end
            if style=="arcane" then
                line(-s,y-3,0,y-s);line(0,y-s,s,y-3)
                line(-s,-y+3,0,-y+s);line(0,-y+s,s,-y+3)
            end
        end
        for key,suffix in pairs({normal="Up",pushed="Down",highlight="Highlight"}) do
            local texture=self[key]
            texture.displayProperties=nil
            if style=="wow" then
                texture:SetTexture("Interface\\Buttons\\UI-Panel-Button-"..suffix)
                texture:SetTexCoord(0,.625,0,.6875)
                texture:SetGradient("VERTICAL",CreateColor(1,1,1,1),CreateColor(1,1,1,1))
            else texture:SetTexture(nil);texture:SetTexCoord(0,1,0,1) end
            texture:SetBlendMode(key=="highlight" and "ADD" or "BLEND")
        end
    end
    function skin:Paint(media,alpha)
        local active=media and media.buttonStyle and self.style==media.buttonStyle
        local opacity=active and (alpha or 1) or 0
        self.art:Paint(media,alpha)
        if self.art.active then
            for _,key in ipairs({"normal","pushed","highlight"}) do ns.UI:DisplayProperty(self[key],"SetAlpha",0) end
            for _,edge in ipairs(self.edges) do ns.UI:DisplayProperty(edge,"SetAlpha",0) end
            for _,line in ipairs(self.ornaments) do ns.UI:DisplayProperty(line,"SetAlpha",0) end
            return
        end
        if active and self.style~="wow" then
            local palette=M.buttonPalettes[self.style]
            local c=media.surface and media.surface.background or palette and palette.base or {.12,.14,.20,1}
            local border=media.surface and media.surface.borderColor or palette and palette.edge or {.35,.43,.60,1}
            ns.UI:DisplayProperty(self.normal,"SetColorTexture",unpack(c))
            -- Gradient resets even when switching a pooled surface to Modern.
            local top=not media.surface and palette and palette.top or c
            self.normal:SetGradient("VERTICAL",CreateColor(unpack(c)),CreateColor(unpack(top)))
            ns.UI:DisplayProperty(self.pushed,"SetColorTexture",c[1]*.55,c[2]*.55,c[3]*.55,c[4] or 1)
            local a=palette and palette.accent or {.25,.35,.55,1}
            ns.UI:DisplayProperty(self.highlight,"SetColorTexture",a[1],a[2],a[3],palette and .18 or .35)
            for _,edge in ipairs(self.edges) do ns.UI:DisplayProperty(edge,"SetColorTexture",unpack(border)) end
            for _,l in ipairs(self.ornaments) do ns.UI:DisplayProperty(l,"SetColorTexture",unpack(a)) end
        end
        for _,key in ipairs({"normal","pushed","highlight"}) do ns.UI:DisplayProperty(self[key],"SetAlpha",opacity) end
        for _,edge in ipairs(self.edges) do ns.UI:DisplayProperty(edge,"SetAlpha",active and self.border>0 and opacity or 0) end
        for i,l in ipairs(self.ornaments) do ns.UI:DisplayProperty(l,"SetAlpha",active and i<=(self.ornamentCount or 0) and opacity or 0) end
    end
    skin:Paint(nil)
    return skin
end
function ns.UI:DisplayDecorations(parent)
    local effect={outline={},border={}}
    local function glyph(label,x,y,angle,color)
        local caption=parent.caption; local path,size=caption:GetFont()
        assert(ns.UI:ApplyMediaFont(label,path,size),"Decoration font unavailable")
        x,y=M.Rotate(x,y,math.deg(angle))
        ns.UI:PlaceDisplayRegion(label,"CENTER",parent,"CENTER",x,y,parent:GetWidth(),parent:GetHeight())
        ns.UI:DisplayProperty(label,"SetJustifyH",caption:GetJustifyH()); ns.UI:DisplayProperty(label,"SetJustifyV","MIDDLE")
        ns.UI:DisplayProperty(label,"SetWordWrap",effect.wrap)
        local textOK=ns.UI:SetMediaText(label,effect.text)
        ns.UI:DisplayProperty(label,"SetTextColor",color[1],color[2],color[3],color[4]); label:SetAlpha(1)
        if label.SetRotation then ns.UI:DisplayProperty(label,"SetRotation",angle) end
        label:SetShown(textOK)
    end
    function effect:Stop()
        if self.surfaceBackground then self.surfaceBackground:Hide() end
        if self.shadow then self.shadow:SetText("");self.shadow:Hide() end
        for _,region in ipairs(self.outline) do region:SetText("");region:Hide() end
        for _,region in ipairs(self.border) do region:Hide() end
    end
    function effect:Present(media,angle)
        if not media or media.alpha<=0 then self:Stop();self.kind=nil;return end
        if self.kind~=media.kind then self:Stop();self.kind=media.kind end
        local surface=media.surface
        if surface and surface.background[4]>0 then
            self.surfaceBackground=self.surfaceBackground or parent:CreateTexture(nil,"BACKGROUND",nil,-8)
            self.surfaceBackground:SetAllPoints(parent)
            ns.UI:DisplayProperty(self.surfaceBackground,"SetColorTexture",unpack(surface.background))
            if self.surfaceBackground.SetRotation then ns.UI:DisplayProperty(self.surfaceBackground,"SetRotation",angle) end
            self.surfaceBackground:Show()
        elseif self.surfaceBackground then self.surfaceBackground:Hide() end
        if media.kind=="text" then
            self.wrap=media.wrap; self.text=media.text
            local shadow=media.textShadow
            if shadow and shadow.color[4]>0 then
                self.shadow=self.shadow or parent:CreateFontString(nil,"BACKGROUND")
                glyph(self.shadow,shadow.x,shadow.y,angle,shadow.color)
            elseif self.shadow then self.shadow:SetText("");self.shadow:Hide()
            end
            local outline=media.textOutline
            if outline and outline.width>0 and outline.color[4]>0 then
                for i=1,8 do
                    self.outline[i]=self.outline[i] or parent:CreateFontString(nil,"ARTWORK")
                    local a=(i-1)*math.pi/4
                    glyph(self.outline[i],math.cos(a)*outline.width,math.sin(a)*outline.width,angle,outline.color)
                end
            else for _,label in ipairs(self.outline) do label:SetText("");label:Hide() end
            end
        end
        local e=media.iconBorder or (surface and {width=surface.borderWidth,color=surface.borderColor})
        if e and e.width>0 and e.color[4]>0 then
            local w,h=parent:GetWidth(),parent:GetHeight()
            local t=math.min(e.width,w/2,h/2) -- Inside the graphic, never negative dimensions.
            local edges={{0,(h-t)/2,w,t},{0,-(h-t)/2,w,t},{-(w-t)/2,0,t,h-2*t},{(w-t)/2,0,t,h-2*t}}
            if e.style=="corners" then
                edges={};local length=math.min(w,h)*.28
                for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do
                    edges[#edges+1]={sx*(w-length)/2,sy*(h-t)/2,length,t}
                    edges[#edges+1]={sx*(w-t)/2,sy*(h-length)/2,t,length}
                end end
            elseif e.style=="double" and w>6*t and h>6*t then
                edges[#edges+1]={0,(h-5*t)/2,w-4*t,t};edges[#edges+1]={0,-(h-5*t)/2,w-4*t,t}
                edges[#edges+1]={-(w-5*t)/2,0,t,h-6*t};edges[#edges+1]={(w-5*t)/2,0,t,h-6*t}
            end
            for i,r in ipairs(edges) do
                local region=self.border[i]
                if not region then region=parent:CreateTexture(nil,"OVERLAY"); self.border[i]=region end
                if r[3]>0 and r[4]>0 then
                    local x,y=M.Rotate(r[1],r[2],math.deg(angle))
                    ns.UI:PlaceDisplayRegion(region,"CENTER",parent,"CENTER",x,y,r[3],r[4])
                    ns.UI:DisplayProperty(region,"SetColorTexture",unpack(e.color)); if region.SetRotation then ns.UI:DisplayProperty(region,"SetRotation",angle) end
                    region:Show()
                else region:Hide() end
            end
            for i=#edges+1,#self.border do self.border[i]:Hide() end
        else for _,region in ipairs(self.border) do region:Hide() end
        end
    end
    return effect
end

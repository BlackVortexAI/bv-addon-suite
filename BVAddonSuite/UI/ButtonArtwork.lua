-- Approved bitmap skins. Nine slices keep corners stable at different sizes.
-- Mouse hooks only switch preallocated textures; no secure geometry mutation.
local _,ns=...
local styles={modern=true,arcane=true,runic=true,ember=true,frost=true,tech=true}
function ns.UI:ButtonArtwork(button)
    local art={regions={},down={}}
    for _,state in ipairs({'normal','hover','pressed'}) do
        art.regions[state]={}
        for i=1,9 do
            local t=button:CreateTexture(nil,'BACKGROUND',nil,-1)
            t:SetBlendMode('BLEND');t:SetAlpha(0);art.regions[state][i]=t
        end
    end
    function art:Refresh()
        local state=next(self.down) and 'pressed' or self.hover and 'hover' or 'normal'
        self.state=state
        for name,regions in pairs(self.regions) do for _,t in ipairs(regions) do
            ns.UI:DisplayProperty(t,'SetAlpha',self.active and name==state and self.alpha or 0)
        end end
    end
    function art:Prepare(style,w,h)
        self.style=styles[style] and style or nil
        if not self.style then self.active=false;self:Refresh();return false end
        local side=math.min(h*.28,w/2);local edge=math.min(h*.16,h/2)
        local xs={0,side,w-side,w};local ys={0,edge,h-edge,h}
        local us={0,.07,.93,1};local vs={0,.16,.84,1}
        for state,regions in pairs(self.regions) do
            for row=1,3 do for col=1,3 do
                local t=regions[(row-1)*3+col]
                ns.UI:DisplayProperty(t,'SetTexture','Interface\\AddOns\\BVAddonSuite\\Media\\Buttons\\'..style..'-'..state..'.tga')
                ns.UI:DisplayProperty(t,'SetTexCoord',us[col],us[col+1],vs[row],vs[row+1])
                ns.UI:PlaceDisplayRegion(t,'TOPLEFT',button,'TOPLEFT',xs[col],-ys[row],math.max(.01,xs[col+1]-xs[col]),math.max(.01,ys[row+1]-ys[row]))
            end end
        end
        return true
    end
    function art:Paint(media,alpha)
        self.active=media and self.style and media.buttonStyle==self.style or false
        self.alpha=alpha or 1
        local palette=ns.DisplayModel.buttonPalettes[self.style]
        local color=media and media.surface and media.surface.borderColor or palette and palette.accent or {1,1,1,1}
        for _,regions in pairs(self.regions) do for _,t in ipairs(regions) do
            ns.UI:DisplayProperty(t,'SetVertexColor',color[1],color[2],color[3],color[4] or 1)
        end end
        if not self.active then self.hover=nil;self.down={} end
        self:Refresh()
    end
    button:HookScript('OnEnter',function()art.hover=true;art:Refresh()end)
    button:HookScript('OnLeave',function()art.hover=nil;art.down={};art:Refresh()end)
    button:HookScript('OnMouseDown',function(_,key)if key=='LeftButton' or key=='RightButton' or key=='MiddleButton' then art.down[key]=true;art:Refresh()end end)
    button:HookScript('OnMouseUp',function(_,key)art.down[key]=nil;art:Refresh()end)
    button:HookScript('OnHide',function()art.hover=nil;art.down={};art:Refresh()end)
    return art
end

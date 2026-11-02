local _,ns=...
-- Presentation only. Providers own points, colours, progress and future-leg
-- alpha; this renderer never edits a provider's geometry or cached points.
local S={}
ns.RouteLineStyles=S
local WHITE="Interface\\Buttons\\WHITE8X8"
local DISC="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local VALID={contour=true,compass=true,ribbon=true,dots=true,glow=true}
S.CHOICES={{value="contour",label="Kontur"},{value="compass",label="Kompass"},
    {value="ribbon",label="Pfeilband"},{value="dots",label="Punktspur"},{value="glow",label="Leuchtspur"}}
local function number(v,default,lo,hi)
    if type(v)~="number" or v~=v then return default end
    return math.max(lo,math.min(hi,v))
end
function S:Config()
    -- Providers may register/paint while addons load, before ADDON_LOADED
    -- has initialized the profile store. Use detached defaults until then.
    if not (ns.Settings and ns.Settings.db) then
        return {style="contour",width=3,opacity=100,arrows=true}
    end
    local c=ns.Settings:Module("routeLines")
    if not VALID[c.style] then c.style="contour" end
    c.width=number(c.width,3,1,6)
    c.opacity=number(c.opacity,100,0,100)
    if type(c.arrows)~="boolean" then c.arrows=true end
    return c
end
-- One profile setting, offered on all three pages. The callbacks resolve
-- the current profile at commit time, just like the surrounding controls.
function S:Options(grid)
    local UI=ns.UI
    local controls={}
    local function change(key,value)
        S:Config()[key]=value
        if ns.MapPins then ns.MapPins:Refresh() end
        if ns.Config then ns.Config:Refresh() end
    end
    local help="Shared by Map, Gather and Routing, on the world map and minimap. Colours and later-leg dimming stay as set below."
    controls.style=grid:Row("Route line style",UI:Dropdown(grid,190,self.CHOICES,function(v) change("style",v) end),{help=help})
    controls.width=grid:Row("Line width",UI:InlineSlider(grid,190,1,6,.5,"%.1f px",function(v) change("width",v) end),{help="Width at normal UI scale; stays readable when the map zooms."})
    controls.opacity=grid:Row("Line visibility",UI:InlineSlider(grid,190,0,100,5,"%d %%",function(v) change("opacity",v) end),{help="Scales lines, arrows and soft underlays together. 0 hides lines; pins and gather rings stay visible."})
    controls.arrows=grid:Row("Direction arrows",UI:Switch(grid,true,function(v) change("arrows",v==true) end),{help="Show direction arrows on paths that support them. Shared by Map, Gather and Routing."})
    function controls:Refresh()
        local c=S:Config()
        self.style:SetValue(c.style);self.width:SetValue(c.width);self.opacity:SetValue(c.opacity);self.arrows:SetValue(c.arrows)
    end
    controls:Refresh()
    return controls
end
local function position(line,anchor,point,x1,y1,x2,y2)
    line:SetStartPoint(point,anchor,x1,y1);line:SetEndPoint(point,anchor,x2,y2)
end
local function stroke(line,anchor,point,x1,y1,x2,y2,r,g,b,a,width)
    line:SetTexture(WHITE);line:SetVertexColor(r,g,b,a);line:SetThickness(width)
    position(line,anchor,point,x1,y1,x2,y2);line:Show()
end
local function part(owner,kind,index)
    local key=kind=="underlay" and "styleUnderlays" or (kind=="dot" and "styleDots" or "styleLines")
    local pool=owner[key]
    if not pool then pool={};owner[key]=pool end
    local item=pool[index]
    local parent=owner:GetParent()
    if not item then
        if kind=="dot" then item=parent:CreateTexture(nil,"OVERLAY",nil,3);item:SetTexture(DISC)
        elseif kind=="underlay" then
            item=parent:CreateTexture(nil,"OVERLAY",nil,0);item:SetTexture(WHITE)
            item:SetSnapToPixelGrid(false);item:SetTexelSnappingBias(0)
        else item=parent:CreateLine(nil,"OVERLAY",nil,3);item:SetTexture(WHITE) end
        pool[index]=item
    elseif item:GetParent()~=parent then item:SetParent(parent) end
    return item
end
function S:HideParts(line,lines,dots,underlays)
    for i=(lines or 0)+1,#(line.styleLines or {}) do line.styleLines[i]:Hide() end
    for i=(dots or 0)+1,#(line.styleDots or {}) do line.styleDots[i]:Hide() end
    for i=(underlays or 0)+1,#(line.styleUnderlays or {}) do line.styleUnderlays[i]:Hide() end
    if not underlays and line.routeBand then line.routeBand.active=false end
end
-- Native texture vertices share an identical edge at each join. Independent
-- thick Lines overlap inside a turn and leave a hole outside it; changing
-- opacity or adding round discs would only hide one of those two defects.
local function bandQuad(t,b)
    local s,e,lo,hi=t.bandStart,t.bandEnd,t.bandLow,t.bandHigh
    local sx,sy,ex,ey=-b.uy,b.ux,-b.uy,b.ux
    if s==0 then sx,sy=b.sx,b.sy end
    if e==b.length then ex,ey=b.ex,b.ey end
    local ax,ay=b.x+b.ux*s,b.y+b.uy*s
    local bx,by=b.x+b.ux*e,b.y+b.uy*e
    local x1,y1,x2,y2=ax+sx*hi,ay+sy*hi,ax+sx*lo,ay+sy*lo
    local x3,y3,x4,y4=bx+ex*hi,by+ey*hi,bx+ex*lo,by+ey*lo
    local left,top=math.min(x1,x2,x3,x4),math.max(y1,y2,y3,y4)
    local width=math.max(1,math.max(x1,x2,x3,x4)-left)
    local height=math.max(1,top-math.min(y1,y2,y3,y4))
    t:ClearAllPoints();t:SetPoint("TOPLEFT",b.anchor,b.point,left,top);t:SetSize(width,height)
    t:SetVertexOffset(1,x1-left,y1-top);t:SetVertexOffset(2,x2-left,y2-top+height)
    t:SetVertexOffset(3,x3-left-width,y3-top);t:SetVertexOffset(4,x4-left-width,y4-top+height)
end
function S:Join(previous,line)
    local a,b=previous and previous.routeBand,line.routeBand
    if not (a and b and a.active and b.active) or a.anchor~=b.anchor or a.point~=b.point
        or math.abs(a.x+a.ux*a.length-b.x)>.001 or math.abs(a.y+a.uy*a.length-b.y)>.001
        or a.width~=b.width then return end
    local divisor=1+a.ux*b.ux+a.uy*b.uy
    if divisor<.01 then return end -- reversal: no unbounded spike
    local nx,ny=(-a.uy-b.uy)/divisor,(a.ux+b.ux)/divisor
    local magnitude=math.sqrt(nx*nx+ny*ny)
    if magnitude>4 then nx,ny=nx*4/magnitude,ny*4/magnitude end
    a.ex,a.ey,b.sx,b.sy=nx,ny,nx,ny
    for _,t in ipairs(previous.styleUnderlays or {}) do if t:IsShown() then bandQuad(t,a) end end
    for _,t in ipairs(line.styleUnderlays or {}) do if t:IsShown() then bandQuad(t,b) end end
end
-- phase is measured in screen units along a provider's polyline. Keeping it
-- between pieces prevents dots/dashes from turning solid at dense waypoints.
-- startGap/endGap only clear the inside of hollow Gather stop markers.
function S:Paint(line,cfg,anchor,point,x1,y1,x2,y2,color,alpha,unit,phase,startGap,endGap)
    local dx,dy=x2-x1,y2-y1
    local length=math.sqrt(dx*dx+dy*dy)
    local nextPhase=(phase or 0)+length
    -- Map's existing provider uses percent / 95; preserve its 100 % setting.
    local a=number(alpha,1,0,1/.95)*cfg.opacity/100
    local w=cfg.width*unit
    local r,g,b=color[1],color[2],color[3]
    local style=cfg.style
    local used,dots=0,0
    line:SetVertexColor(r,g,b,0);line.shadow:SetVertexColor(r,g,b,0)
    position(line,anchor,point,x1,y1,x2,y2)
    position(line.shadow,anchor,point,x1,y1,x2,y2)
    line:Show()
    if length<.01 or a==0 then self:HideParts(line);return nextPhase end
    local ux,uy=dx/length,dy/length
    local from,to=math.max(0,startGap or 0),length-math.max(0,endGap or 0)
    if from>=to then self:HideParts(line);return nextPhase end
    local ax,ay,bx,by=x1+ux*from,y1+uy*from,x1+ux*to,y1+uy*to
    local geometry=line.routeBand or {};line.routeBand=geometry
    geometry.x,geometry.y,geometry.ux,geometry.uy,geometry.length=x1,y1,ux,uy,length
    geometry.sx,geometry.sy,geometry.ex,geometry.ey=-uy,ux,-uy,ux
    geometry.anchor,geometry.point,geometry.width,geometry.active=anchor,point,w,true
    -- The broad band flows beside hollow stop rings. Only the small resource
    -- centre is cut out; applying the foreground's full gap to the band would
    -- break it into separate rectangles. Side strips preserve a clear central
    -- square (and thus its inscribed circle) without opaque masks or assets.
    local underlays=0
    local head=(startGap or 0)>0 and math.min(startGap,3*unit) or 0
    local tail=(endGap or 0)>0 and math.min(endGap,3*unit) or 0
    local function bandPiece(ca,cw,s,e,offset)
        if e<=s or cw<=0 then return end
        underlays=underlays+1
        local t=part(line,"underlay",underlays)
        t.bandStart,t.bandEnd,t.bandLow,t.bandHigh=s,e,(offset or 0)-cw/2,(offset or 0)+cw/2
        bandQuad(t,geometry);t:SetVertexColor(r,g,b,ca*a);t:Show()
    end
    local function band(ca,cw)
        local hole=math.max(head,tail)
        if hole==0 then bandPiece(ca,cw,0,length);return end
        -- Longitudinal strips also work at a bent stop. Short end patches
        -- would fold when their shared miter edge reaches past the patch.
        local strip=cw/2-hole;local offset=hole+strip/2
        bandPiece(ca,strip,0,length,offset);bandPiece(ca,strip,0,length,-offset)
        bandPiece(ca,2*hole,head,length-tail)
    end
    band(.055,w+19*unit);band(.09,w+15*unit);band(.22,w+11*unit)
    local function extra(cr,cg,cb,ca,cw,s,e)
        used=used+1
        local l=part(line,"line",used)
        stroke(l,anchor,point,x1+ux*s,y1+uy*s,x1+ux*e,y1+uy*e,cr,cg,cb,ca,cw)
    end
    if style=="contour" then
        stroke(line.shadow,anchor,point,ax,ay,bx,by,0,0,0,.55*a,w+1.5*unit)
        stroke(line,anchor,point,ax,ay,bx,by,r,g,b,.95*a,w)
    elseif style=="ribbon" then
        stroke(line.shadow,anchor,point,ax,ay,bx,by,0,0,0,.5*a,w+3*unit)
        stroke(line,anchor,point,ax,ay,bx,by,r,g,b,.95*a,w+1.5*unit)
    elseif style=="glow" then
        -- Soft coloured layers, never a wide black outside contour.
        stroke(line.shadow,anchor,point,ax,ay,bx,by,r,g,b,.07*a,w+9*unit)
        stroke(line,anchor,point,ax,ay,bx,by,r,g,b,.16*a,w+5*unit)
        extra(r,g,b,.9*a,w+unit,from,to)
        extra(1,1,1,.8*a,math.max(.7*unit,w*.35),from,to)
    elseif style=="compass" then
        stroke(line.shadow,anchor,point,ax,ay,bx,by,r,g,b,.04*a,w+10*unit)
        stroke(line,anchor,point,ax,ay,bx,by,r,g,b,.09*a,w+7*unit)
        local on,period=5*unit,11*unit
        local start=math.floor(((phase or 0)+from)/period)*period-(phase or 0)
        while start<to do
            local s,e=math.max(from,start),math.min(to,start+on)
            if e>s then extra(0,0,0,.4*a,w+unit,s,e);extra(r,g,b,.95*a,w,s,e) end
            start=start+period
        end
    else -- dots
        local period=math.max(7*unit,w*3.5)
        if (startGap or 0)>0 then from=from+w/2 end
        if (endGap or 0)>0 then to=to-w/2 end
        local start=math.ceil(((phase or 0)+from)/period)*period-(phase or 0)
        while start<to do
            -- Keep centres on the clipped segment. Adjacent short pieces
            -- must not each discard the dot nearest their shared endpoint.
            if start>=from and start<to then
                dots=dots+1
                local dot=part(line,"dot",dots)
                dot:ClearAllPoints();dot:SetPoint("CENTER",anchor,point,x1+ux*start,y1+uy*start)
                dot:SetSize(w,w);dot:SetVertexColor(r,g,b,.95*a);dot:Show()
            end
            start=start+period
        end
    end
    self:HideParts(line,used,dots,underlays)
    return nextPhase
end

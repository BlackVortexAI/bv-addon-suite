local _,ns=...
local S={};ns.ShellMaterials=S
local M=ns.DesignSystem.Metrics
local families={
 ['bv-graphite']={frame='FrameGraphite',radius=9,inset=1,fill='ShellRound9Fill'},
 ['bv-steel']={frame='FrameSteel',radius=6,inset=3,fill='Round6Fill'},
 ['bv-forge']={frame='FrameForge',radius=3,inset=3,fill='Round3Fill'},
}
local WHITE="Interface\\Buttons\\WHITE8X8"
local function sample(t)
 if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)end
 if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)end
 return t
end
local function tex(parent,layer)local t=parent:CreateTexture(nil,layer or 'BACKGROUND');t:SetTexture(WHITE);return t end
local function at(t,p,x,y,w,h)t:ClearAllPoints();M.Point(t,'TOPLEFT',p,'TOPLEFT',x,-y);if w and h then M.Size(t,w,h)end end
local function rgba(c,a)return {c[1],c[2],c[3],a or c[4] or 1}end
local function gradient(t,c,a,b)
 t:SetVertexColor(1,1,1,1)
 if t.SetGradient and CreateColor then t:SetGradient('HORIZONTAL',CreateColor(c[1],c[2],c[3],a),CreateColor(c[1],c[2],c[3],b))
 else t:SetColorTexture(c[1],c[2],c[3],(a+b)/2)end
end
local paths={minus={{2,7,12,7}},max={{3,3,11,3},{11,3,11,11},{11,11,3,11},{3,11,3,3}},
 close={{3,3,11,11},{3,11,11,3}},restore={{2,5,9,5},{9,5,9,12},{9,12,2,12},{2,12,2,5},{5,2,12,2},{12,2,12,9}}}
local function glyph(button,name,color,weight)
 button.shellGlyphs=button.shellGlyphs or {}
 for _,t in ipairs(button.shellGlyphs)do t:Hide()end
 for i,p in ipairs(paths[name])do
  local t=button.shellGlyphs[i];if not t then t=sample(tex(button,'OVERLAY'));button.shellGlyphs[i]=t end
  local dx,dy=p[3]-p[1],p[4]-p[2]
  t:Show();t:ClearAllPoints();M.Point(t,'CENTER',(p[1]+p[3])/2-7,7-(p[2]+p[4])/2)
  M.Size(t,math.sqrt(dx*dx+dy*dy),weight or 1);t:SetRotation(-math.atan2(dy,dx));t:SetVertexColor(unpack(color))
 end
end
function S:PaintButton(style,b,kind)
 if ns.ShellMetrics.IsWoW(style.interfaceThemeKey)then return ns.ShellWoWMaterials:PaintButton(style,b,kind,glyph)end
 local c=style.interfaceColors;local enabled=b:IsEnabled();local selected=enabled and b.selected
 local state={enabled=enabled,focused=b.keyboardFocused,pressed=b.pressed,hovered=b.hovered}
 state.danger=b.shellAction=='close' and b.hovered and enabled
 b.interfaceRadius=kind=='window' and (style.interfaceThemeKey=='bv-graphite' and 5 or style.interfaceThemeKey=='bv-forge' and 2 or 3) or nil
 b.interfaceOverride=nil
 ns.ControlMaterials:Paint(style,b,'button',state)
 local color=enabled and (selected or b.hovered) and c.text or c.muted
 if kind=='window' then
  color=not enabled and c.muted or b.hovered and (b.shellAction=='close' and c.danger or c.accentText) or c.text
  if b.icon then b.icon:Hide()end;if b.restoreIcon then b.restoreIcon:Hide()end
  if b.shellAction then glyph(b,b.shellAction=='max' and b.shellWindow.maximized and 'restore' or b.shellAction,color,1.5)end
 else
  for key,t in pairs(b.interfaceTextures or {})do if not key:find('focus',1,true)then t:Hide()end end
  if not b.shellBand then b.shellBand=tex(b);b.shellBand:SetAllPoints()end
  if families[style.interfaceThemeKey] and kind=='nav' and selected then gradient(b.shellBand,c.selection,1,1)
  else gradient(b.shellBand,c.accent,kind=='nav' and (selected and .14 or enabled and b.hovered and .07 or 0) or 0,0)end
  if b.selection then sample(b.selection);b.selection:SetColorTexture(unpack(c.accent));b.selection:SetShown(selected==true)end
  if b.icon then
   b.icon.colorRole=selected and 'accentText' or enabled and b.hovered and 'text' or 'muted'
   b.icon:SetColor(style:Color(b.icon.colorRole))
  end
 end
 b.label:SetTextColor(unpack(color));b.interfaceTextColor=color
end
local function divider(style,parent,left,right,peak,spread)
 local holder=CreateFrame('Frame',nil,parent);holder:SetAllPoints();holder:SetFrameLevel(parent:GetFrameLevel()+3);holder:EnableMouse(false)
 local rows={}
 for dy=-spread,spread do rows[#rows+1]={dy=dy,parts={sample(tex(holder,'OVERLAY')),sample(tex(holder,'OVERLAY'))}}end
 local function paint()
  local width=math.max(1,M.GetWidth(parent)-left-(right=='30%' and M.GetWidth(parent)*.3 or right))
  local split=math.max(1,width*peak);local c=style.interfaceColors.accent
  for _,row in ipairs(rows)do
   local alpha=row.dy==0 and .9 or .13*math.exp(-math.abs(row.dy)*.55)
   local a,b=row.parts[1],row.parts[2]
   a:ClearAllPoints();M.Point(a,'BOTTOMLEFT',parent,'BOTTOMLEFT',left,row.dy);M.Size(a,split,1)
   b:ClearAllPoints();M.Point(b,'BOTTOMLEFT',a,'BOTTOMRIGHT');M.Size(b,math.max(1,width-split),1)
   gradient(a,c,peak==0 and alpha or 0,alpha);gradient(b,c,alpha,0)
  end
 end
 style:Bind(paint,holder);parent:HookScript('OnSizeChanged',paint)
 holder.rows=rows;return holder
end
-- Insets are one design unit inside the window's radius-8 silhouette. Crop
-- that outer pixel from the existing corner alpha rather than stretching a mask.
local function insetFill(style,parent,rounded)
 local surface={parts={}}
 for i=1,9 do surface.parts[i]=tex(parent)end
 function surface:Paint(color,width,height)
  local w,h=width or M.GetWidth(parent),height or M.GetHeight(parent)
  if w<=0 or h<=0 then for _,t in ipairs(self.parts)do t:Hide()end;return end
  local cap=math.min(8,w/2,h/2)
  local xs,ys={0,cap,w-cap,w},{0,cap,h-cap,h}
  for y=1,3 do for x=1,3 do
   local i=(y-1)*3+x;local t=self.parts[i];local pw,ph=xs[x+1]-xs[x],ys[y+1]-ys[y]
   t:SetShown(pw>0 and ph>0);at(t,parent,xs[x],ys[y],math.max(.1,pw),math.max(.1,ph))
   if rounded[i] then
    t:SetTexture(style.materialMediaRoot..'Shapes\\Round8Fill')
    t:SetTexCoord(x==1 and 1/64 or 55/64,x==1 and 9/64 or 63/64,y==1 and 1/64 or 55/64,y==1 and 9/64 or 63/64)
   else t:SetTexture(WHITE);t:SetTexCoord(0,1,0,1)end
   t:SetVertexColor(unpack(color))
  end end
 end
 return surface
end

-- Original R9 1200x740/POT2048x1024 frame artwork. Fixed caps preserve rim
-- thickness and corner radii during resize/maximize/minimize; only straight spans stretch.
local function materialRim(style,parent)
 local parts={}
 for i=1,9 do if i~=5 then parts[i]=tex(parent,'OVERLAY')end end
 return {parts=parts,Paint=function(self,family)
  local w,h=M.GetWidth(parent),M.GetHeight(parent);local cap=math.min(10,w/2,h/2)
  local xs,ys={0,cap,w-cap,w},{0,cap,h-cap,h}
  local us,vs={0,10/2048,1190/2048,1200/2048},{0,10/1024,730/1024,740/1024}
  for y=1,3 do for x=1,3 do local t=parts[(y-1)*3+x];if t then
   at(t,parent,xs[x],ys[y],math.max(.1,xs[x+1]-xs[x]),math.max(.1,ys[y+1]-ys[y]))
   t:SetTexture(style.materialMediaRoot..'Materials\\'..family.frame)
   t:SetTexCoord(us[x],us[x+1],vs[y],vs[y+1]);t:SetVertexColor(1,1,1,1);t:Show()
  end end end
 end}
end
local function familyFill(style,parent,rounded,inset)
 local parts={};for i=1,9 do parts[i]=tex(parent)end
 return {parts=parts,Paint=function(self,color,width,height)
  local family=assert(families[style.interfaceThemeKey]);local edge=inset or 0
  local sourceCap=family.radius+1;local cap=math.max(1,sourceCap-edge)
  local w,h=width or M.GetWidth(parent),height or M.GetHeight(parent)
  cap=math.min(cap,w/2,h/2);local xs,ys={0,cap,w-cap,w},{0,cap,h-cap,h}
  for y=1,3 do for x=1,3 do local i=(y-1)*3+x;local t=parts[i]
   at(t,parent,xs[x],ys[y],math.max(.1,xs[x+1]-xs[x]),math.max(.1,ys[y+1]-ys[y]))
   if rounded[i]then
    t:SetTexture(style.materialMediaRoot..'Shapes\\'..family.fill)
    t:SetTexCoord(x==1 and edge/64 or (64-sourceCap)/64,x==1 and sourceCap/64 or (64-edge)/64,y==1 and edge/64 or (64-sourceCap)/64,y==1 and sourceCap/64 or (64-edge)/64)
   else t:SetTexture(WHITE);t:SetTexCoord(0,1,0,1)end
   t:SetVertexColor(unpack(color));t:Show()
  end end
 end}
end
local function headerWash(parent,cornerInset)
 -- Stay inside the straight top span: no rectangular wash may refill a rounded corner.
 local t=tex(parent,'BORDER');M.Point(t,'TOPLEFT',parent,'TOPLEFT',cornerInset,0);M.Point(t,'TOPRIGHT',parent,'TOPRIGHT',-cornerInset,0)
 return {texture=t,Paint=function(self,strong)
  M.Height(t,M.GetHeight(parent)*.75);t:SetVertexColor(1,1,1,1)
  local alpha=strong and 10/255 or 5/255
  if t.SetGradient and CreateColor then t:SetGradient('VERTICAL',CreateColor(1,1,1,0),CreateColor(1,1,1,alpha))else t:SetColorTexture(1,1,1,alpha/2)end
 end}
end


-- Only BV Dark: CSS outer accent rim, soft shadow, glow and inner top light.
-- Masks have a transparent original window interior; shadow offset is baked in.
local function cleanEffects(style,window,outline)
 local root=style.materialMediaRoot..'Shapes\\'
 local function slices(parent,name,size,pad,cap,layer,sublevel,topCap,bottomCap)
  topCap,bottomCap=topCap or cap,bottomCap or cap
  local parts={};local uv={0,cap/size,(size-cap)/size,1};local v={0,topCap/size,(size-bottomCap)/size,1}
  for i=1,9 do local t=parent:CreateTexture(nil,layer,nil,sublevel);t:SetDrawLayer(layer,sublevel);sample(t);t:SetTexture(root..name);parts[i]=t end
  return function(color,opacity)
   local w,h=M.GetWidth(window),M.GetHeight(window)
   local bottom=math.min(bottomCap-pad,h);local top=math.min(topCap-pad,math.max(0,h-bottom))
   local xs,ys={-pad,cap-pad,w+pad-cap,w+pad},{-pad,top,h-bottom,h+pad}
   for y=1,3 do for x=1,3 do local t=parts[(y-1)*3+x]
    local width,height=xs[x+1]-xs[x],ys[y+1]-ys[y]
    t:ClearAllPoints();M.Point(t,'TOPLEFT',window,'TOPLEFT',xs[x],-ys[y]);M.Size(t,math.max(.01,width),math.max(.01,height))
    t:SetTexCoord(uv[x],uv[x+1],v[y],v[y+1]);t:SetVertexColor(color[1],color[2],color[3],opacity);t:SetShown(width>0 and height>0)
   end end
  end,parts
 end
 local shadow,shadowParts=slices(window,'CleanShadow80',512,192,200,'BACKGROUND',-7,230,200)
 local glow,glowParts=slices(window,'CleanGlow60',512,192,200,'BACKGROUND',-6)
 local rim,rimParts=slices(outline,'CleanAccentRim',64,1,10,'BORDER',1)
 local light=outline:CreateTexture(nil,'ARTWORK');light:SetTexture('Interface\\Buttons\\WHITE8X8');sample(light)
 local result={shadow=shadowParts,glow=glowParts,rim=rimParts,light=light}
 function result:Paint()
  shadow({0,0,0},.65);glow(style.interfaceColors.accent,.10);rim(style.interfaceColors.accent,.18)
  light:ClearAllPoints();M.Point(light,'TOPLEFT',window,'TOPLEFT',9,-1);M.Size(light,math.max(1,M.GetWidth(window)-18),1);light:SetVertexColor(1,1,1,.07)
 end
 return result
end

-- Use the same casing assets on a standalone settings window without creating
-- Config's page navigation, search field, brand sidebar or scroll controller.
function S:AttachEditorFrame(style,window)
 if ns.ShellMetrics.IsWoW(style.interfaceThemeKey) then
  return ns.ShellWoWMaterials:AttachEditorFrame(style,window)
 end
 local outline=CreateFrame('Frame',nil,window)
 outline:SetAllPoints(window);outline:EnableMouse(false)
 outline:SetFrameLevel(window.content:GetFrameLevel()+1)
 local family=families[style.interfaceThemeKey]
 local rim=family and materialRim(style,outline) or cleanEffects(style,window,outline)
 local function paint() rim:Paint(family) end
 style:Bind(paint,outline);window:HookScript('OnSizeChanged',paint)
 return outline
end
function S:Attach(style,window,regions)
 if ns.ShellMetrics.IsWoW(style.interfaceThemeKey)then return ns.ShellWoWMaterials:Attach(style,window,regions)end
 assert(style.shellPresentation=='clean' and not window.shellPresentation)
 local family=families[style.interfaceThemeKey]
 local p={style=style,window=window,regions=regions,family=family};window.shellPresentation=p;window.chrome.presentation=p
 local chrome=window.chrome
 chrome.rule:Hide();chrome.brand:Hide();chrome.title:Hide();chrome.caption:Hide()
 window.interfaceRadius=8
 p.brand=CreateFrame('Frame',nil,regions.sidebar);p.brand:SetSize(1,1)
 p.logo=CreateFrame('Frame',nil,p.brand);M.Size(p.logo,34,34);M.Point(p.logo,'LEFT',14,0)
 p.logoNeutral=tex(p.logo,'ARTWORK');p.logoNeutral:SetTexture(style.materialMediaRoot..'Brand\\LogoNeutral');p.logoNeutral:SetAllPoints();p.logoNeutral:SetDesaturated(true)
 p.logoPigment=tex(p.logo,'OVERLAY');p.logoPigment:SetTexture(style.materialMediaRoot..'Brand\\LogoPigment');p.logoPigment:SetAllPoints()
 p.brandName=style:Label(p.brand,'BV Suite',16,'text','bold');at(p.brandName,p.brand,58,14,145,20)
 p.brandSub=style:Label(p.brand,'',11,'muted');at(p.brandSub,p.brand,58,36,143,30);p.brandSub:SetWordWrap(true)
 p.headerGlow=divider(style,regions.header,22,0,.6,5);p.brandGlow=divider(style,p.brand,16,'30%',0,4)
 p.sideFill=family and familyFill(style,regions.sidebar,{[1]=true},family.inset) or insetFill(style,regions.sidebar,{[1]=true})
 p.footerFill=family and familyFill(style,regions.footer,{[7]=true,[9]=true},family.inset) or insetFill(style,regions.footer,{[7]=true,[9]=true})
 if family then
  p.background=familyFill(style,window,{[1]=true,[3]=true,[7]=true,[9]=true},0)
  local cornerInset=family.radius+1-family.inset
  p.headerWash=headerWash(regions.header,cornerInset);p.brandWash=headerWash(p.brand,cornerInset)
 end
 -- Child surfaces otherwise draw over the parent's BORDER layer. Keep the
 -- outline independent and mouse-passive; the existing resize controller stays.
 p.outline=CreateFrame('Frame',nil,window);p.outline:SetPoint('TOPLEFT',window,'TOPLEFT');p.outline:EnableMouse(false);p.outline.interfaceRadius=8
 p.outline:SetFrameLevel(math.max(regions.sidebar:GetFrameLevel(),regions.footer:GetFrameLevel(),regions.header:GetFrameLevel())+5)
 chrome.grip:SetFrameLevel(p.outline:GetFrameLevel()+1)
 if family then p.materialRim=materialRim(style,p.outline)end
 if ns.ThemeTokens.MaterialFamily(style.interfaceThemeKey)=='clean' then p.cleanEffects=cleanEffects(style,window,p.outline)end
 p.cue=CreateFrame('Frame',nil,window.content);p.cueFill=tex(p.cue);p.cueFill:SetAllPoints()
 p.cueLabel=style:Label(p.cue,'More settings below',11,'muted');p.cueLabel:SetPoint('CENTER')
 p.navTrack=CreateFrame('Frame',nil,regions.sidebar);p.navTrack:EnableMouse(false)
 p.navRail=sample(tex(p.navTrack));p.navRail:SetAllPoints()
 p.navThumb=sample(tex(p.navTrack,'ARTWORK'))
 for name,b in pairs({close=chrome.close,max=chrome.maximize,minus=chrome.minimize})do b.shellAction=name;b.shellWindow=window;M.Size(b,32,30)end
 local function paint()
  local c=style.interfaceColors
  window:PaintSurface(family and {0,0,0,0} or rgba(c.bg,.97),{0,0,0,0},1)
  if family then p.background:Paint(rgba(c.bg,.99));p.headerWash:Paint(style.interfaceThemeKey=='bv-steel');p.brandWash:Paint(false)end
  p.outline:SetSize(window:GetWidth(),window:GetHeight())
  p.outline.interfaceOverride={background={0,0,0,0},edge=c.controlEdge,opacity=1}
  if family then p.materialRim:Paint(family)else ns.ControlMaterials:Paint(style,p.outline,'panel')end
  if p.cleanEffects then p.cleanEffects:Paint()end
  p.sideFill:Paint(rgba(c.bg2,1));p.footerFill:Paint(rgba(c.bg2,1),p.metrics and p.metrics.width,p.metrics and p.metrics.footer)
  p.cueFill:SetColorTexture(unpack(rgba(c.field,1)));p.navRail:SetColorTexture(unpack(rgba(c.text,.05)));p.navThumb:SetColorTexture(unpack(rgba(c.muted,.7)))
  p.logoNeutral:SetVertexColor(1,1,1,1);p.logoPigment:SetVertexColor(unpack(c.accent))
  p:Chrome()
 end
 function p:Chrome()
  local compact=window.minimized;local bar=chrome.titlebar;local width=M.GetWidth(window);local l=self.metrics
  if not l then return end
  bar:ClearAllPoints()
  local inset=family and family.inset or 1
  at(bar,window,compact and inset or l.side+inset,inset,compact and width-inset*2 or width-l.side-inset*2,compact and (44-inset*2) or l.header)
  chrome.title:SetShown(compact==true);chrome.caption:Hide();chrome.brand:Hide()
  if compact then chrome.title:SetText('BV Suite');at(chrome.title,bar,14,0,math.max(1,width-138),44-inset*2)end
  for i,b in ipairs({chrome.close,chrome.maximize,chrome.minimize})do
   local right,step,top=compact and 14 or 13,31,compact and 7 or 16
   b:ClearAllPoints();M.Point(b,'TOPRIGHT',window,'TOPRIGHT',-right-(i-1)*step,-top)
   S:PaintButton(style,b,'window')
  end
 end
 function p:Layout(metrics)
  self.metrics=metrics;local c=self.regions
  at(self.brand,c.sidebar,0,0,metrics.side,metrics.brand);self.brandName:SetShown(not metrics.compact);self.brandSub:SetShown(not metrics.compact);M.Size(self.logo,metrics.compact and 24 or 34,metrics.compact and 24 or 34)
  at(self.cue,window.content,metrics.side,metrics.height-metrics.footer-metrics.cue,metrics.width-metrics.side,metrics.cue)
  at(self.navTrack,c.sidebar,metrics.side-6,metrics.brand+10,3,math.max(1,metrics.height-metrics.footer-metrics.brand-64))
  paint();if self.surface then self.surface:Refresh()end
 end
 function p:SetMetadata(profile)
  self.brandSub:SetText(ns.version..' · Profile '..profile)
 end
 function p:Scroll(navOffset,navMaximum,viewHeight,contentHeight,pageOffset,pageMaximum)
  self.navTrack:SetShown(navMaximum>0)
  local track=M.GetHeight(self.navTrack);local size=math.min(track,math.max(18,track*math.min(1,viewHeight/math.max(1,contentHeight))))
  at(self.navThumb,self.navTrack,0,(track-size)*(navMaximum>0 and navOffset/navMaximum or 0),3,size)
  self.cueLabel:SetText(pageMaximum>0 and (pageOffset<pageMaximum-.5 and 'More settings below' or 'End of settings') or '')
 end
 p.surface=ns.InterfaceSurfaces:Attach(style,window,regions,p)
 style:Bind(paint,window)
 window:HookScript('OnSizeChanged',paint)
 return p
end

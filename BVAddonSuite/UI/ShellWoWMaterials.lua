local _,ns=...
local S={};ns.ShellWoWMaterials=S
local M=ns.DesignSystem.Metrics
local WHITE='Interface\\Buttons\\WHITE8X8'
local A={
 frameClassicBl={ path = "Frames\\frame-classic-bl", width = 14, height = 14, textureWidth = 16, textureHeight = 16, u = 0.875, v = 0.875, uv = {0,0.875,0,0.875} },
 frameClassicBottom={ path = "Frames\\frame-classic-bottom", width = 256, height = 9, textureWidth = 256, textureHeight = 16, u = 1, v = 0.5625, uv = {0,1,0,0.5625} },
 frameClassicBr={ path = "Frames\\frame-classic-br", width = 11, height = 11, textureWidth = 16, textureHeight = 16, u = 0.6875, v = 0.6875, uv = {0,0.6875,0,0.6875} },
 frameClassicLeft={ path = "Frames\\frame-classic-left", width = 16, height = 256, textureWidth = 16, textureHeight = 256, u = 1, v = 1, uv = {0,1,0,1} },
 frameClassicRight={ path = "Frames\\frame-classic-right", width = 10, height = 256, textureWidth = 16, textureHeight = 256, u = 0.625, v = 1, uv = {0,0.625,0,1} },
 frameClassicTop={ path = "Frames\\frame-classic-top", width = 256, height = 28, textureWidth = 256, textureHeight = 32, u = 1, v = 0.875, uv = {0,1,0,0.875} },
 frameClassicTr={ path = "Frames\\frame-classic-tr", width = 33, height = 33, textureWidth = 64, textureHeight = 64, u = 0.515625, v = 0.515625, uv = {0,0.515625,0,0.515625} },
 frameModernBl={ path = "Frames\\frame-modern-bl", width = 45, height = 49, textureWidth = 64, textureHeight = 64, u = 0.703125, v = 0.765625, uv = {0,0.703125,0,0.765625} },
 frameModernBottom={ path = "Frames\\frame-modern-bottom", width = 512, height = 16, textureWidth = 512, textureHeight = 16, u = 1, v = 1, uv = {0,1,0,1} },
 frameModernBr={ path = "Frames\\frame-modern-br", width = 47, height = 49, textureWidth = 64, textureHeight = 64, u = 0.734375, v = 0.765625, uv = {0,0.734375,0,0.765625} },
 frameModernLeft={ path = "Frames\\frame-modern-left", width = 16, height = 512, textureWidth = 16, textureHeight = 512, u = 1, v = 1, uv = {0,1,0,1} },
 frameModernRight={ path = "Frames\\frame-modern-right", width = 17, height = 512, textureWidth = 32, textureHeight = 512, u = 0.53125, v = 1, uv = {0,0.53125,0,1} },
 frameModernTop={ path = "Frames\\frame-modern-top", width = 30, height = 70, textureWidth = 32, textureHeight = 128, u = 0.9375, v = 0.546875, uv = {0,0.9375,0,0.546875} },
 frameModernTr={ path = "Frames\\frame-modern-tr", width = 158, height = 138, textureWidth = 256, textureHeight = 256, u = 0.6171875, v = 0.5390625, uv = {0,0.6171875,0,0.5390625} },
 classicMarble={ path = "Controls\\classicMarble", width = 256, height = 256, textureWidth = 256, textureHeight = 256, u = 1, v = 1, uv = {0,1,0,1} },
 tabClassicOn={ path = "Controls\\tabClassicOn", width = 118, height = 37, textureWidth = 128, textureHeight = 64, u = 0.921875, v = 0.578125, uv = {0,0.921875,0,0.578125} },
 tabClassicOff={ path = "Controls\\tabClassicOff", width = 112, height = 30, textureWidth = 128, textureHeight = 32, u = 0.875, v = 0.9375, uv = {0,0.875,0,0.9375} },
 frameNavUp={ path = "Controls\\frameNavUp", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 frameNavDown={ path = "Controls\\frameNavDown", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 frameNavDisabled={ path = "Controls\\frameNavDisabled", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
}
S.assets=A
local function at(t,p,x,y,w,h)t:ClearAllPoints();M.Point(t,'TOPLEFT',p,'TOPLEFT',x,-y);if w and h then M.Size(t,w,h)end end
local function flat(t)if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)end;if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)end;return t end
local function texture(parent,key,layer)parent.wowParts=parent.wowParts or {};local t=parent.wowParts[key];if not t then t=parent:CreateTexture(nil,layer or 'BACKGROUND');parent.wowParts[key]=t end;t:Show();return t end
local function mix(a,b,f)return {a[1]*(1-f)+b[1]*f,a[2]*(1-f)+b[2]*f,a[3]*(1-f)+b[3]*f,1}end
local function gradient(t,top,bottom)t:SetTexture(WHITE);t:SetVertexColor(1,1,1,1);if t.SetGradient and CreateColor then t:SetGradient('VERTICAL',CreateColor(unpack(bottom)),CreateColor(unpack(top)))else t:SetColorTexture(unpack(mix(top,bottom,.5)))end end
local function slices(style,parent,key,a,cx,cy,layer,center,tint)
 local width,height=M.GetWidth(parent),M.GetHeight(parent);local dx,dy=math.min(cx,width/2),math.min(cy,height/2)
 local xs,ys={0,dx,width-dx,width},{0,dy,height-dy,height}
 local us,vs={0,cx/a.textureWidth,(a.width-cx)/a.textureWidth,a.u},{0,cy/a.textureHeight,(a.height-cy)/a.textureHeight,a.v}
 for y=1,3 do for x=1,3 do local i=(y-1)*3+x;if center or i~=5 then
  local t=texture(parent,key..i,layer);t:SetTexture(style.materialMediaRoot..a.path);t:SetTexCoord(us[x],us[x+1],vs[y],vs[y+1]);at(t,parent,xs[x],ys[y],math.max(.1,xs[x+1]-xs[x]),math.max(.1,ys[y+1]-ys[y]));t:SetVertexColor(unpack(tint or {1,1,1,1}))
 end end end
end
local function clearButton(b)for _,t in pairs(b.interfaceTextures or {})do t:Hide()end;for _,t in pairs(b.wowParts or {})do t:Hide()end;if b.selection then b.selection:Hide()end;if b.shellBand then b.shellBand:Hide()end end

local function buildChrome(style,window)
 local holder=CreateFrame("Frame",nil,window);holder:SetAllPoints();holder:SetFrameLevel(window:GetFrameLevel()+3);holder:EnableMouse(false)
 local pools={Top={},Tr={},Left={},Right={},Bottom={},Bl={},Br={}}
 local function region(name,index,a,x,y,width,height,u0,u1,v0,v1)
  local pool=pools[name];local t=pool[index]
  if not t then t=holder:CreateTexture(nil,"OVERLAY");pool[index]=t end
  t:ClearAllPoints();t:SetTexture(style.materialMediaRoot..a.path);t:SetTexCoord(u0,u1,v0,v1);M.Point(t,"TOPLEFT",window,"TOPLEFT",x,-y);M.Size(t,width,height);t:Show();return t
 end
 local function hideAfter(name,count) for i=count+1,#pools[name] do pools[name][i]:Hide() end end
 local function repeated(name,a,x,y,width,height,tileWidth,tileHeight,vertical)
  local length=vertical and height or width;local step=vertical and tileHeight or tileWidth;local count=math.ceil(length/step)
  for i=1,count do local offset=(i-1)*step;local span=math.min(step,length-offset)
   region(name,i,a,x+(vertical and 0 or offset),y+(vertical and offset or 0),vertical and width or span,vertical and span or height,0,a.u*(vertical and 1 or span/tileWidth),0,a.v*(vertical and span/tileHeight or 1))
  end;hideAfter(name,count)
 end
 local function paint()
  local classic=style.interfaceThemeKey=="classic";local native=classic or style.interfaceThemeKey=="modern";holder:SetShown(native);if not native then return end
  local prefix=classic and "frameClassic" or "frameModern";local function asset(name) return A[prefix..name] end
  local width,height=M.GetWidth(window),M.GetHeight(window);local topY=classic and 2 or 6.4;local topX,topWidth=54,width-62
  -- Final CSS border-image: fixed 6px metal caps, flexible 40px centre.
  -- Horizontal 'round' repeats the source instead of stretching its grain.
  local a=asset("Top");local sourceCap=classic and 6 or 15;local count=math.max(1,math.floor(topWidth/(a.width*6/sourceCap)+.5));local tileWidth=topWidth/count
  local sourceY={0,sourceCap,a.height-sourceCap,a.height};local targetY={0,6,46,52};local index=0
  for row=1,3 do for col=1,count do index=index+1;region("Top",index,a,topX+(col-1)*tileWidth,topY+targetY[row],tileWidth,targetY[row+1]-targetY[row],0,a.u,sourceY[row]/a.textureHeight,sourceY[row+1]/a.textureHeight) end end;hideAfter("Top",index)
  -- Only the outer corner edge survives; the obsolete close-button socket is excluded.
  a=asset("Tr");local cap=classic and 8 or 20;local left=(a.width-cap)/a.textureWidth
  region("Tr",1,a,width-8,topY,8,8,left,a.u,0,cap/a.textureHeight)
  hideAfter("Tr",1) -- The lower TR source contains the obsolete socket lip; never render it.
  local bottomHeight=classic and 9 or 6.4;local bottomLeft=classic and 14 or 19.2;local bottomRight=classic and 11 or 18.8;local cornerHeight=classic and 11 or 19.6
  a=asset("Left");repeated("Left",a,0,32,classic and 16 or 8,height-32-(classic and 14 or 19.6),classic and 16 or 8,256,true)
  a=asset("Right");local rightWidth=classic and 10 or 6.8;repeated("Right",a,width-rightWidth,topY+8,rightWidth,height-(topY+8)-cornerHeight,rightWidth,classic and 256 or 204.8,true)
  a=asset("Bottom");repeated("Bottom",a,bottomLeft,height-bottomHeight,width-bottomLeft-bottomRight,bottomHeight,classic and 256 or 204.8,bottomHeight,false)
  a=asset("Bl");region("Bl",1,a,classic and 0 or 1.2,height-(classic and 14 or 19.6),classic and 14 or 18,classic and 14 or 19.6,0,a.u,0,a.v);hideAfter("Bl",1)
  a=asset("Br");region("Br",1,a,width-bottomRight,height-cornerHeight,bottomRight,cornerHeight,0,a.u,0,a.v);hideAfter("Br",1)
 end
 style:Bind(paint,holder);window:HookScript("OnSizeChanged",paint);return holder,pools
end


function S:PaintButton(style,b,kind,glyph)
 local c=style.interfaceColors;local enabled=b:IsEnabled();local hover=enabled and b.hovered;local selected=enabled and b.selected
 -- Reuse Factory focus treatment, then replace only its material layers.
 ns.ControlMaterials:Paint(style,b,'button',{enabled=enabled,focused=b.keyboardFocused})
 for k,t in pairs(b.interfaceTextures or {})do if not k:find('focus',1,true)then t:Hide()end end
 for _,t in pairs(b.wowParts or {})do t:Hide()end;if b.selection then b.selection:Hide()end
 local text=enabled and (selected and c.accentText or c.text) or c.muted
 if kind=='window' then
  local classic=style.interfaceThemeKey=='classic';local pressed=enabled and b.pressed
  local assets=ns.ControlMaterials.assets
  local a=classic and assets[not enabled and 'classicDisabled' or pressed and 'classicDownMetal' or 'classicUpMetal'] or A[not enabled and 'frameNavDisabled' or pressed and 'frameNavDown' or 'frameNavUp']
  local tint=classic and {hover and 1 or .88,hover and 1 or .88,hover and 1 or .88,1} or b.shellAction=='close' and mix({.8,.8,.8},c.danger,.3) or hover and {1,1,1,1} or {.86,.89,.94,1}
  slices(style,b,'caption',a,8,5,'BACKGROUND',true,tint)
  if classic and enabled then
   local pigment=b.shellAction=='close' and c.danger or c.pigment;local amount=b.shellAction=='close' and .42 or hover and .3 or .12
   slices(style,b,'pigment',assets[pressed and 'classicDownPigment' or 'classicUpPigment'],8,5,'ARTWORK',true,{pigment[1]*amount,pigment[2]*amount,pigment[3]*amount,1})
   for k,t in pairs(b.wowParts)do if k:find('pigment',1,true)then t:SetBlendMode('ADD')end end
  end
  if b.icon then b.icon:Hide()end;if b.restoreIcon then b.restoreIcon:Hide()end
  if b.shellAction then glyph(b,b.shellAction=='max' and b.shellWindow.maximized and 'restore' or b.shellAction,hover and (b.shellAction=='close' and c.danger or c.text) or c.muted)end
 elseif kind=='tab' then
  local a=A[selected and 'tabClassicOn' or 'tabClassicOff'];local height=selected and 33 or 29;local cap=18;local width=M.GetWidth(b);local dx=math.min(cap,width/2)
  for i=1,3 do
   local t=texture(b,'tab'..i,'BACKGROUND');t:SetTexture(style.materialMediaRoot..a.path);t:SetVertexColor(1,1,1,enabled and 1 or .4)
   local xs={0,dx,width-dx,width};local us={0,cap/a.textureWidth,(a.width-cap)/a.textureWidth,a.u}
   at(t,b,xs[i],M.GetHeight(b)-height,math.max(.1,xs[i+1]-xs[i]),height);t:SetTexCoord(us[i],us[i+1],0,a.v)
  end
 else
  local top=selected and mix(c.bg,c.pigment,.25) or mix(c.field,c.text,.20)
  local bottom=selected and mix(c.bg,c.pigment,.10) or mix(c.field,c.text,.08)
  local face=texture(b,'navFace');face:SetAllPoints();gradient(face,top,bottom)
  local edge=selected and c.accent or hover and c.accentText or c.edge
  local width,height=M.GetWidth(b),M.GetHeight(b)
  for i,box in ipairs({{0,0,width,1},{0,height-1,width,1},{0,0,1,height},{width-1,0,1,height}})do local t=flat(texture(b,'navEdge'..i,'BORDER'));t:SetColorTexture(unpack(edge));at(t,b,unpack(box))end
  local t=flat(texture(b,'navShine','BORDER'));at(t,b,1,1,math.max(1,width-2),1);t:SetColorTexture(1,1,1,.14)
  if b.icon then b.icon.colorRole=selected and 'accentText' or 'muted';b.icon:SetColor(style:Color(b.icon.colorRole))end
 end
 b.label:SetTextColor(unpack(text));b.interfaceTextColor=text
end

function S:AttachEditorFrame(style,window)
 return buildChrome(style,window)
end
function S:Attach(style,window,regions)
 local c=assert(regions.config,'native shell requires its existing Config owner')
 local p={style=style,window=window,regions=regions,config=c};window.shellPresentation=p;window.chrome.presentation=p
 local classic=style.interfaceThemeKey=='classic';local chrome=window.chrome
 p.frame,p.framePools=buildChrome(style,window);p.outline=p.frame
 chrome.titlebar:SetFrameLevel(window:GetFrameLevel()+6)
 chrome.title:Hide();chrome.caption:Hide();chrome.brand:Hide();chrome.rule:Hide();c.sideRule:Hide()
 p.logo=CreateFrame('Frame',nil,window);p.logo:SetFrameLevel(window:GetFrameLevel()+8);at(p.logo,window,-8,-8,72,72);p.logo:EnableMouse(false)
 p.logoNeutral=texture(p.logo,'neutral','ARTWORK');p.logoNeutral:SetTexture(style.materialMediaRoot..'Brand\\LogoNeutral');p.logoNeutral:SetAllPoints();p.logoNeutral:SetDesaturated(true)
 p.logoPigment=texture(p.logo,'pigment','OVERLAY');p.logoPigment:SetTexture(style.materialMediaRoot..'Brand\\LogoPigment');p.logoPigment:SetAllPoints()
 p.plate=CreateFrame('Frame',nil,window);p.plate:SetFrameLevel(window:GetFrameLevel()+5);p.plate:EnableMouse(false)
 c.heading:SetParent(p.plate);c.heading:SetJustifyH('CENTER');c.description:Hide()
 p.plateBrand=style:Label(p.plate,'BV SUITE',11,'muted','bold')
 c.searchBox:SetParent(regions.header);c.searchHint:SetParent(c.searchBox)
 p.bodyInset=CreateFrame('Frame',nil,window.content);p.bodyInset:EnableMouse(false);p.bodyInset:SetFrameLevel(window.content:GetFrameLevel())
 p.pageFill=texture(p.bodyInset,'page');p.pageFill:SetAllPoints()
 p.sideFill=texture(regions.sidebar,'side');p.sideFill:SetAllPoints()
 p.footerFill=texture(regions.footer,'footer');p.footerFill:SetAllPoints()
 p.base=texture(window,'base');p.base:SetAllPoints();p.base:SetDrawLayer('BACKGROUND',1)
 p.marble={}
 p.navTrack=CreateFrame('Frame',nil,regions.sidebar);p.navTrack:EnableMouse(false)
 p.navRail=flat(texture(p.navTrack,'rail'));p.navRail:SetAllPoints();p.navThumb=flat(texture(p.navTrack,'thumb','ARTWORK'))
 p.cue=CreateFrame('Frame',nil,window.content);p.cue:SetFrameLevel(window:GetFrameLevel()+15);p.cue:EnableMouse(false)
 p.cueFill=texture(p.cue,'fill');p.cueFill:SetAllPoints();p.cueLabel=style:Label(p.cue,'',11,'muted');p.cueLabel:SetPoint('CENTER')
 for name,b in pairs({close=chrome.close,max=chrome.maximize,minus=chrome.minimize})do b.shellAction=name;b.shellWindow=window;M.Size(b,34,28)end
 local function paint()
  local colors=style.interfaceColors
  window:PaintSurface({0,0,0,0},{0,0,0,0},1)
  for _,t in pairs(window.interfaceTextures or {})do t:Hide()end
  p.base:SetColorTexture(colors.bg[1],colors.bg[2],colors.bg[3],classic and .7 or .99)
  if classic then
   local width,height=M.GetWidth(window),M.GetHeight(window);local index=0;local a=A.classicMarble
   for y=0,height-1,256 do for x=0,width-1,256 do index=index+1;local t=p.marble[index]
    -- Adjacent opaque tiles retain their fractional geometry; disable independent texel snapping.
    if not t then t=flat(window:CreateTexture(nil,'BACKGROUND',nil,0));p.marble[index]=t end
    local w,h=math.min(256,width-x),math.min(256,height-y);at(t,window,x,y,w,h);t:SetTexture(style.materialMediaRoot..a.path);t:SetTexCoord(0,w/256,0,h/256);t:Show()
   end end
   for i=index+1,#p.marble do p.marble[i]:Hide()end
  end
  p.pageFill:SetColorTexture(colors.field[1],colors.field[2],colors.field[3],.76)
  p.sideFill:SetColorTexture(colors.bg2[1],colors.bg2[2],colors.bg2[3],classic and .74 or 1)
  p.footerFill:SetColorTexture(colors.bg2[1],colors.bg2[2],colors.bg2[3],1)
  p.cueFill:SetColorTexture(colors.field[1],colors.field[2],colors.field[3],1)
  p.navRail:SetColorTexture(colors.text[1],colors.text[2],colors.text[3],.05);p.navThumb:SetColorTexture(colors.muted[1],colors.muted[2],colors.muted[3],.7)
  p.logoNeutral:SetVertexColor(1,1,1,1);p.logoPigment:SetVertexColor(unpack(colors.accent))
  local inset=ns.ControlMaterials.assets.frameInset
  slices(style,regions.sidebar,'inset',inset,6,6,'BORDER',false)
  slices(style,p.bodyInset,'inset',inset,6,6,'BORDER',false)
  p:Chrome()
 end
 function p:Chrome()
  local width=M.GetWidth(window);local compact=window.minimized
  at(chrome.titlebar,window,64,classic and 2 or 6.4,math.max(1,width-72),52)
  chrome.title:Hide();chrome.caption:Hide();chrome.brand:Hide()
  at(self.plate,window,classic and 88 or 100,classic and 9 or 13,math.max(1,width-(classic and 228 or 240)),30)
  local textWidth=math.max(1,math.min(math.max(1,M.GetWidth(self.plate)-110),math.ceil(M.ToDesign(c.heading:GetUnboundedStringWidth()))+2))
  M.Size(c.heading,textWidth,30);c.heading:ClearAllPoints();M.Point(c.heading,'CENTER',self.plate,'CENTER',28,0)
  c.heading:SetTextColor(unpack(classic and style.interfaceColors.accentText or style.interfaceColors.text))
  self.plateBrand:ClearAllPoints();M.Point(self.plateBrand,'RIGHT',c.heading,'LEFT',-14,0);M.Size(self.plateBrand,64,20)
  for i,b in ipairs({chrome.minimize,chrome.maximize,chrome.close})do
   at(b,window,width-126+(i-1)*40,classic and 10 or 14,34,28)
   ns.ShellMaterials:PaintButton(style,b,'window')
  end
  chrome.grip:ClearAllPoints();M.Point(chrome.grip,'BOTTOMRIGHT',window,'BOTTOMRIGHT',classic and -14 or -22,classic and 14 or 22)
  chrome.grip:SetFrameLevel(window:GetFrameLevel()+20)
 end
 function p:Layout(metrics)
  self.metrics=metrics
  at(self.bodyInset,window.content,232,114,math.max(1,metrics.width-246),math.max(1,metrics.height-201))
  at(self.cue,window.content,238,metrics.height-117,math.max(1,metrics.width-268),24)
  at(self.navTrack,regions.sidebar,199,8,3,math.max(1,M.GetHeight(regions.sidebar)-62))
  local count=#(c.tabs.definitions or {});local available=math.max(1,metrics.width-280);local x=0
  for _,definition in ipairs(c.tabs.definitions or {})do
   local b=c.tabs.buttons[definition.id];local full=b.fullLabel or definition.label;b.label:SetText(full)
   local bw=math.min(math.max(1,(available-math.max(0,count-1)*4)/math.max(1,count)),math.max(85,math.ceil(M.ToDesign(b.label:GetUnboundedStringWidth()))+26))
   at(b,c.tabs,x,0,bw,33);b:SetLabelText(full);x=x+bw+4;ns.ShellMaterials:PaintButton(style,b,'tab')
  end
  paint();if self.surface then self.surface:Refresh()end
 end
 function p:SetMetadata(profile)self.profile=profile end
 function p:Scroll(offset,maximum,viewHeight,contentHeight,pageOffset,pageMaximum)
  self.navTrack:SetShown(maximum>0)
  local track=M.GetHeight(self.navTrack);local size=math.min(track,math.max(18,track*math.min(1,viewHeight/math.max(1,contentHeight))))
  at(self.navThumb,self.navTrack,0,(track-size)*(maximum>0 and offset/maximum or 0),3,size)
  self.cueLabel:SetText(pageMaximum>0 and (pageOffset<pageMaximum-.5 and 'More settings below' or 'End of settings') or '')
 end
 p.surface=ns.InterfaceSurfaces:Attach(style,window,regions,p)
 style:Bind(paint,window);window:HookScript('OnSizeChanged',paint)
 return p
end

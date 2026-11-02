local _,ns=...
local R={};ns.ControlMaterials=R
local WHITE="Interface\\Buttons\\WHITE8X8"
local ALU="Interface\\AddOns\\BVAddonSuite\\Media\\StatusBars\\alu-one-soft-light-bevel.tga"
local assets={
 classicCheckbox= { path = "Controls\\classicCheckbox", width = 32, height = 32, textureWidth = 32, textureHeight = 32, u = 1, v = 1, uv = {0,1,0,1} },
 classicCheckboxDown= { path = "Controls\\classicCheckboxDown", width = 32, height = 32, textureWidth = 32, textureHeight = 32, u = 1, v = 1, uv = {0,1,0,1} },
 classicCheckboxHover= { path = "Controls\\classicCheckboxHover", width = 32, height = 32, textureWidth = 32, textureHeight = 32, u = 1, v = 1, uv = {0,1,0,1} },
 classicCheck= { path = "Controls\\classicCheck", width = 32, height = 32, textureWidth = 32, textureHeight = 32, u = 1, v = 1, uv = {0,1,0,1} },
 modernCheck= { path = "Controls\\modernCheck", width = 15, height = 14, textureWidth = 16, textureHeight = 16, u = 0.9375, v = 0.875, uv = {0,0.9375,0,0.875} },
 classicDisabled={ path = "Buttons\\ClassicDisabled", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 classicDownMetal={ path = "Buttons\\ClassicDownMetal", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 classicDownPigment={ path = "Buttons\\ClassicDownPigment", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 classicUpMetal={ path = "Buttons\\ClassicUpMetal", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 classicUpPigment={ path = "Buttons\\ClassicUpPigment", width = 80, height = 22, textureWidth = 128, textureHeight = 32, u = 0.625, v = 0.6875, uv = {0,0.625,0,0.6875} },
 frameInset={ path = "Frames\\frame-inset", width = 30, height = 30, textureWidth = 32, textureHeight = 32, u = 0.9375, v = 0.9375, uv = {0,0.9375,0,0.9375} },
 classicSliderThumb={ path = "Controls\\classicSliderThumb", width = 32, height = 32, textureWidth = 32, textureHeight = 32, u = 1, v = 1, uv = {0,1,0,1} },
 classicSliderTrack={ path = "Controls\\classicSliderTrack", width = 8, height = 8, textureWidth = 8, textureHeight = 8, u = 1, v = 1, uv = {0,1,0,1} },
 classicInput={ path = "Controls\\classicInput", width = 128, height = 20, textureWidth = 128, textureHeight = 32, u = 1, v = 0.625, uv = {0,1,0,0.625} },
 circleMask={ path = "Controls\\CircleMask", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1} },
 sliderSteelThumb={ path = "Controls\\SliderSteelThumb", width = 12, height = 19, textureWidth = 16, textureHeight = 32, u = 0.75, v = 0.59375, uv = {0,0.75,0,0.59375} },
 sliderForgeThumb={ path = "Controls\\SliderForgeThumb", width = 12, height = 20, textureWidth = 16, textureHeight = 32, u = 0.75, v = 0.625, uv = {0,0.75,0,0.625} },
 round2Fill={ path = "Shapes\\Round2Fill", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 2, cap = 3 },
 round2Edge={ path = "Shapes\\Round2Edge", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 2, cap = 3 },
 round3Fill={ path = "Shapes\\Round3Fill", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 3, cap = 4 },
 round3Edge={ path = "Shapes\\Round3Edge", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 3, cap = 4 },
 round4Fill={ path = "Shapes\\Round4Fill", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 4, cap = 5 },
 round4Edge={ path = "Shapes\\Round4Edge", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 4, cap = 5 },
 round5Fill={ path = "Shapes\\Round5Fill", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 5, cap = 6 },
 round5Edge={ path = "Shapes\\Round5Edge", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 5, cap = 6 },
 round6Fill={ path = "Shapes\\Round6Fill", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 6, cap = 7 },
 round6Edge={ path = "Shapes\\Round6Edge", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 6, cap = 7 },
 round8Fill={ path = "Shapes\\Round8Fill", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 8, cap = 9 },
 round8Edge={ path = "Shapes\\Round8Edge", width = 64, height = 64, textureWidth = 64, textureHeight = 64, u = 1, v = 1, uv = {0,1,0,1}, radius = 8, cap = 9 },
}
R.assets=assets
for _,phase in ipairs({'Normal','Hover','Pressed','Disabled'})do
 for _,layer in ipairs({'Fill','Edge'})do
  local name='Brushed'..phase..layer
  assets[name]={path='Buttons\\'..name,width=200,height=56,textureWidth=256,textureHeight=64,u=200/256,v=56/64,sourceScale=2}
 end
end

local function mix(a,b,t)return {a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t,a[3]*(1-t)+b[3]*t,(a[4] or 1)*(1-t)+(b[4] or 1)*t}end
local function unit(v)return ns.DesignSystem.Metrics.ToNative(v)end
local function sampling(t)if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)end;if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)end end
local function texture(frame,key,layer)
 frame.interfaceTextures=frame.interfaceTextures or {};local t=frame.interfaceTextures[key]
 if not t then t=frame:CreateTexture(nil,layer or 'BACKGROUND');frame.interfaceTextures[key]=t end;t:Show();return t
end
local function solid(t,c)t:SetVertexColor(c[1],c[2],c[3],c[4] or 1)end
local function gradient(t,a,b)
 t:SetVertexColor(1,1,1,1)
 if t.SetGradient and CreateColor then t:SetGradient('VERTICAL',CreateColor(b[1],b[2],b[3],b[4] or 1),CreateColor(a[1],a[2],a[3],a[4] or 1))else solid(t,mix(a,b,.5))end
end
local function slice(style,frame,key,assetKey,cx,cy,top,bottom,layer,inset,middle,alu,square)
 local a=assert(assets[assetKey],assetKey);inset=inset or 0
 local width,height=math.max(.1,frame:GetWidth()-inset*2),math.max(.1,frame:GetHeight()-inset*2)
 local dx,dy=math.min(unit(cx),width/2),math.min(unit(cy),height/2)
 local xs={0,dx,width-dx,width};local ys={0,dy,height-dy,height}
 local scale=a.sourceScale or 1
 local us={0,cx*scale/a.textureWidth,(a.width-cx*scale)/a.textureWidth,a.u};local vs={0,cy*scale/a.textureHeight,(a.height-cy*scale)/a.textureHeight,a.v}
 -- Preserve the chosen source's density across ordinary button widths. Wider
 -- than 256 design units uses the full source, stretched once, never tiled.
 local span=alu and math.min(1,width/unit(1)*2/512);local start=span and (1-span)/2
 for y=cy==0 and 2 or 1,cy==0 and 2 or 3 do for x=1,3 do
  local t=texture(frame,key..((y-1)*3+x),layer);t:SetTexture(style.materialMediaRoot..a.path);t:SetTexCoord(us[x],us[x+1],vs[y],vs[y+1]);t:ClearAllPoints();t:SetPoint('TOPLEFT',frame,'TOPLEFT',inset+xs[x],-inset-ys[y]);t:SetSize(math.max(.1,xs[x+1]-xs[x]),math.max(.1,ys[y+1]-ys[y]))
  if alu and not square then
   local mask=t.interfaceFillMask
   if not mask then mask=frame:CreateMaskTexture();sampling(mask);mask:SetAllPoints(t);t.interfaceFillMask=mask end
   mask:SetTexture(style.materialMediaRoot..a.path);mask:SetTexCoord(us[x],us[x+1],vs[y],vs[y+1]);mask:Show()
   if not t.interfaceFillMaskBound then t:AddMaskTexture(mask);t.interfaceFillMaskBound=true end
  elseif t.interfaceFillMaskBound then
   t:RemoveMaskTexture(t.interfaceFillMask);t.interfaceFillMask:Hide();t.interfaceFillMaskBound=nil
  end
  if alu then t:SetTexture(ALU);t:SetTexCoord(start+span*xs[x]/width,start+span*xs[x+1]/width,ys[y]/height,ys[y+1]/height)
  elseif square then t:SetTexture(WHITE);t:SetTexCoord(0,1,0,1)end
  local function at(f)if middle then return f<.48 and mix(top,middle,f/.48) or mix(middle,bottom,(f-.48)/.52)end;return mix(top,bottom,f)end
  local f1=ys[y]/height;local f2=ys[y+1]/height;gradient(t,at(f1),at(f2))
 end end
end
-- Square controls reuse straight strips of the selected material, with disjoint
-- corners. Colors are explicit paint inputs; no texture-state readback is needed.
local function squareEdge(style,frame,key,assetKey,cap,top,bottom,inset,light,dark)
 local a=assets[assetKey];inset=inset or 0
 local w,h=math.max(.1,frame:GetWidth()-2*inset),math.max(.1,frame:GetHeight()-2*inset)
 local scale=a.sourceScale or 1;local pixels=scale==2 and 4 or 1
 local thick=math.min(unit(pixels/scale),w/2,h/2)
 local cut=math.min(unit(cap),h/2)/h
 local upper,lower=mix(top,bottom,cut),mix(top,bottom,1-cut)
 local boxes={
  {0,0,w,thick,{a.width/2/a.textureWidth,(a.width/2+1)/a.textureWidth,0,pixels/a.textureHeight},light or top,light and top or upper},
  {0,h-thick,w,thick,{a.width/2/a.textureWidth,(a.width/2+1)/a.textureWidth,(a.height-pixels)/a.textureHeight,a.v},dark and bottom or lower,dark or bottom},
  {0,thick,thick,h-2*thick,{0,pixels/a.textureWidth,a.height/2/a.textureHeight,(a.height/2+1)/a.textureHeight},upper,lower},
  {w-thick,thick,thick,h-2*thick,{(a.width-pixels)/a.textureWidth,a.u,a.height/2/a.textureHeight,(a.height/2+1)/a.textureHeight},upper,lower}}
 for i,b in ipairs(boxes)do
  if b[3]>0 and b[4]>0 then
   local t=texture(frame,'square'..key..i,'BORDER');t:SetTexture(style.materialMediaRoot..a.path);t:SetTexCoord(unpack(b[5]))
   t:ClearAllPoints();t:SetPoint('TOPLEFT',frame,'TOPLEFT',inset+b[1],-inset-b[2]);t:SetSize(b[3],b[4]);gradient(t,b[6],b[7])
  end
 end
end
local function hide(frame)for _,t in pairs(frame.interfaceTextures or {})do t:Hide()end end

-- Menu rows deliberately have no individual control face or decorative rim.
-- All states share the popup's motif, while semantics remain on the real Button.
function R:Menu(style,frame,state)
 local c=style.interfaceColors;local enabled=state.enabled~=false
 local ink=not enabled and c.muted or state.danger and c.danger or state.selected and c.accentText or c.text
 local pigment=state.danger and c.danger or c.accent
 local alpha=enabled and (state.pressed and .24 or state.hovered and .16 or state.selected and .12 or 0) or 0
 local function rect(key,x,y,w,h,color,a,layer)
  local t=texture(frame,key,layer);sampling(t);t:SetTexture(WHITE);t:ClearAllPoints();t:SetPoint('TOPLEFT',frame,'TOPLEFT',x,-y);t:SetSize(math.max(.1,w),math.max(.1,h));t:SetVertexColor(color[1],color[2],color[3],a);return t
 end
 local w,h=frame:GetWidth(),frame:GetHeight()
 if alpha>0 then rect('menuBand',0,0,w,h,pigment,alpha,'BACKGROUND')end
 if state.selected then rect('menuMark',unit(2),unit(4),unit(2),h-unit(8),enabled and c.accentText or c.muted,enabled and 1 or .5,'ARTWORK')end
 if state.focused and enabled then
  local i,b=unit(2),unit(1)
  rect('menuFocus1',i,i,w-i*2,b,c.text,.8,'OVERLAY');rect('menuFocus2',i,h-i-b,w-i*2,b,c.text,.8,'OVERLAY')
  rect('menuFocus3',i,i,b,h-i*2,c.text,.8,'OVERLAY');rect('menuFocus4',w-i-b,i,b,h-i*2,c.text,.8,'OVERLAY')
 end
 frame.interfaceTextColor=ink;frame.fills={};frame.borders={}
 if frame.interfaceTextures.menuBand and frame.interfaceTextures.menuBand:IsShown()then frame.fills[1]=frame.interfaceTextures.menuBand end
 if frame.label then frame.label:SetTextColor(ink[1],ink[2],ink[3],enabled and (ink[4] or 1) or .7)end
 if frame.selection then frame.selection:Hide()end
 frame:SetAlpha(frame.bvRowDisabled and .4 or 1)
end
function R:Paint(style,frame,kind,state)
 state=state or {};frame.interfaceKind=kind;frame.interfaceState=state;hide(frame)
 -- HideSurface suppresses only this panel material, including later size/theme paints.
 if kind=='panel' and frame.surfaceHidden then return end
 if kind=='menu' then self:Menu(style,frame,state);return end
 local c=style.interfaceColors;local theme=ns.ThemeTokens.MaterialFamily(style.interfaceThemeKey);local enabled=state.enabled~=false
 local primary=enabled and (state.primary or state.selected);local face=c.field;local edge=c.controlEdge;local text=c.text
 if kind=='panel' then
  face=c[state.fill or 'panel'] or c.panel;edge=c.edge
  -- Standalone reading surfaces keep theme RGB without underlying UI text bleeding through.
  if state.fill=='dialog' then face={face[1],face[2],face[3],1}
  elseif state.fill=='tooltip' then face={c.bg[1],c.bg[2],c.bg[3],1} end
 end
 if primary then face=state.primary and c.action or c.selectedFace;text=state.primary and c.onAccent or c.selectedText end
 if state.selected and enabled then text=c.selectedText;if theme=='clean' then edge=c.accent end end
 if state.danger and enabled then face=mix(c.field,c.danger,.18);edge=c.danger;text=c.danger end
 if state.hovered and enabled then edge=c.accent end
 if kind=='input' and state.focused then edge=c.accent end;if state.invalid then edge=c.danger end
 if not enabled then face=c.field;edge=c.edge;text=c.muted end
 local top,bottom=face,face
 local own=theme=='bv-steel' or theme=='bv-forge' or theme=='bv-graphite'
 local role=frame.presentationKind or frame.kind
 local specialized=role=='dropdown' or role=='window' or role=='nav' or role=='tab' or role=='ghost' or role=='resize' or role=='icon-only'
 local caption=role=='window' and frame.shellAction~=nil
 local brushed=kind=='button' and (own or theme=='clean') and (caption or not specialized)
 local square=brushed or (kind=='input' or frame.interfaceInputSurface or kind=='button' and (role=='dropdown' or role=='window' or role=='ghost')) and (own or theme=='clean')
 local materialButton=kind=='button' and (own or theme=='modern') and not brushed;local middle
 -- Atlas engraving uses a dark, restrained action surface. The accent carries
 -- emphasis rather than flooding the label background; native WoW skins stay intact.
 if brushed then
  local pigment=state.danger and c.danger or c.accent
  face=mix(c.field,c.text,.065)
  if primary then face=mix(c.field,pigment,state.primary and .42 or .24) end
  if state.danger and enabled then face=mix(c.field,pigment,.18) end
  if not enabled then face=c.field end
  top=mix(face,c.text,enabled and .065 or .025);bottom=mix(face,c.bg2,.22)
  if enabled and state.hovered then top=mix(top,c.text,.035) end
  if enabled and state.pressed then top=mix(face,c.bg2,.3);bottom=face end
  text=not enabled and c.muted or state.danger and c.danger or c.text
  edge=not enabled and c.edge or state.hovered and pigment or mix(c.controlEdge,pigment,primary and .7 or .25)
 end
 if materialButton and enabled then
  local steel,forge=theme=='bv-steel',theme=='bv-forge'
  face=state.primary and mix(c.action,c.bg,steel and .05 or forge and .14 or 0) or mix(c.field,c.text,steel and .13 or forge and .10 or .08)
  top=state.primary and mix(face,{1,1,1,1},steel and .17 or forge and .08 or .025) or mix(face,c.text,steel and .09 or forge and .07 or .025)
  bottom=state.primary and mix(face,c.bg,steel and .13 or forge and .10 or .025) or mix(face,c.bg2,.35)
  if theme=='modern' then top=state.primary and mix(c.action,{1,1,1,1},.22) or {57/255,59/255,64/255,1};bottom=state.primary and c.action or {36/255,38/255,43/255,1};face=mix(top,bottom,.48)end
  if state.selected then face=c.selectedFace;top=mix(face,c.text,.07);bottom=mix(face,c.bg2,.2)end
  if state.danger then face=mix(c.field,c.danger,.18);top=face;bottom=face end
  middle=face;edge=state.danger and c.danger or state.primary and c.action or c.controlEdge
 end
 local override=frame.interfaceOverride
 if override then middle=nil;face=override.background or face;edge=override.edge or edge;top=override.top or override.background or top;bottom=override.bottom or override.background or bottom end
 local opacity=override and override.opacity;if opacity==nil then opacity=frame.interfaceOpacity end;if type(opacity)=='function' then opacity=opacity()end;opacity=opacity==nil and 1 or opacity
 top={top[1],top[2],top[3],(top[4] or 1)*opacity};bottom={bottom[1],bottom[2],bottom[3],(bottom[4] or 1)*opacity}
 if middle then middle={middle[1],middle[2],middle[3],(middle[4] or 1)*opacity}end
 -- A floating menu owns an opaque reading base; its art/state bands stay translucent.
 -- Do not change shared theme alpha, ordinary panels, or the popup Frame alpha.
 if kind=='panel' and frame.menuSurface then
  top[4]=1;bottom[4]=1;if middle then middle[4]=1 end
 end
 local radius=frame.interfaceRadius or (theme=='bv-steel' and 3 or theme=='bv-forge' and 2 or theme=='bv-graphite' and 5 or theme=='modern' and 4 or kind=='button' and 6 or 4)
 if brushed then
  local phase=not enabled and 'Disabled' or state.pressed and 'Pressed' or state.hovered and 'Hover' or 'Normal'
  slice(style,frame,'face','Brushed'..phase..'Fill',6,5,top,bottom,'BACKGROUND',nil,nil,true,true)
  squareEdge(style,frame,'edge','round2Edge',3,edge,edge,0,mix(edge,c.text,.12),mix(edge,c.bg2,.35))
  -- One static crop from the bundled 1024x683 Atlas image (1024x1024 POT).
  -- Crop at a stable density and preserve aspect; never sample padded rows.
  local width,height=math.max(.1,frame:GetWidth()-unit(2)),math.max(.1,frame:GetHeight()-unit(2))
  local scale=math.min(1/unit(240),.9/width,.5/height)
  local u,v=width*scale,height*scale
  local art=texture(frame,'faceAtlas','BACKGROUND');sampling(art);art:SetDrawLayer('BACKGROUND',1)
  art:SetTexture(style.materialMediaRoot..'Backgrounds\\Atlas');art:SetTexCoord(.96-u,.96,.1,.1+v)
  art:ClearAllPoints();art:SetPoint('TOPLEFT',frame,'TOPLEFT',unit(1),-unit(1));art:SetSize(width,height)
  art:SetVertexColor(1,1,1,(not enabled and .09 or state.pressed and .16 or state.hovered and .31 or .25)*opacity)
  if not caption then
   local mark=texture(frame,'atlasAccent','BORDER');sampling(mark);mark:SetTexture(WHITE)
   mark:ClearAllPoints();local inset=math.min(unit(8),frame:GetHeight()/3)
   mark:SetPoint('TOPLEFT',frame,'TOPLEFT',unit(2),-inset);mark:SetSize(unit(2),math.max(.1,frame:GetHeight()-inset*2))
   local pigment=not enabled and c.muted or state.danger and c.danger or primary and c.accentText or c.accent
   mark:SetVertexColor(pigment[1],pigment[2],pigment[3],(not enabled and .32 or primary and 1 or .75)*opacity)
  end
 elseif theme=='classic' and kind=='button' then
  local suffix=state.pressed and enabled and 'Down' or 'Up';local base=enabled and ('classic'..suffix..'Metal') or 'classicDisabled'
  slice(style,frame,'metal',base,12,0,{1,1,1,1},{1,1,1,1},'BACKGROUND')
  if enabled then local pigment=state.danger and c.danger or c.pigment;local strength=state.danger and .5 or primary and .85 or .18;if state.hovered then strength=strength+.12 end;local tint={pigment[1]*strength,pigment[2]*strength,pigment[3]*strength,1};slice(style,frame,'pigment','classic'..suffix..'Pigment',12,0,tint,tint,'BORDER');for k,t in pairs(frame.interfaceTextures)do if k:find('pigment',1,true)then t:SetBlendMode('ADD')end end end
  text=enabled and (state.danger and c.danger or state.selected and c.selectedText or c.text) or c.muted
 elseif theme=='classic' and kind=='input' then
  local fill=texture(frame,'plain','BACKGROUND');fill:SetTexture(WHITE);fill:SetAllPoints();gradient(fill,top,bottom)
  slice(style,frame,'input','classicInput',8,0,edge,edge,'BORDER')
 else
  local borderWidth=(theme=='bv-steel' or theme=='bv-forge') and kind=='button' and 2 or 1
  slice(style,frame,'face','round'..radius..'Fill',radius+1,radius+1,top,bottom,'BACKGROUND',0,middle,nil,square)
  if square then
   local shade=materialButton and enabled and not override
   squareEdge(style,frame,'edge','round'..radius..'Edge',radius+1,edge,edge,0,shade and mix(edge,c.text,.28),shade and mix(edge,c.bg2,.6))
   if borderWidth==2 then squareEdge(style,frame,'bevel','round'..radius..'Edge',radius+1,mix(edge,c.text,.28),mix(edge,c.bg2,.6),unit(1))end
  else
  slice(style,frame,'edge','round'..radius..'Edge',radius+1,radius+1,edge,edge,'BORDER')
  if borderWidth==2 then slice(style,frame,'bevel','round'..radius..'Edge',radius+1,radius+1,mix(edge,c.text,.28),mix(edge,c.bg2,.6),'BORDER',unit(1))end
  if materialButton and enabled and not override then for i=1,9 do local t=frame.interfaceTextures['edge'..i];local row=math.floor((i-1)/3)+1;gradient(t,row==1 and mix(edge,c.text,.28) or edge,row==3 and mix(edge,c.bg2,.6) or edge)end end
  end
  if theme=='classic' or theme=='modern' and kind=='panel' then slice(style,frame,'inset','frameInset',6,6,{1,1,1,1},{1,1,1,1},'BORDER');local center=frame.interfaceTextures.inset5;if center then center:Hide()end end
 end
 frame.fills={};frame.borders={};for key,t in pairs(frame.interfaceTextures or {})do if t:IsShown()then local list=(key:find("face",1,true) or key=="plain" or key:find("metal",1,true) or key:find("pigment",1,true)) and frame.fills or frame.borders;list[#list+1]=t end end
 if kind=='button' and state.focused and enabled then
  local inset=unit(4);local width,height=math.max(.1,frame:GetWidth()-2*inset),math.max(.1,frame:GetHeight()-2*inset)
  local boxes={{inset,-inset,width,unit(1)},{inset,-frame:GetHeight()+inset,width,unit(1)},{inset,-inset,unit(1),height},{frame:GetWidth()-inset,-inset,unit(1),height}}
  for i,b in ipairs(boxes)do local t=texture(frame,'focus'..i,'OVERLAY');sampling(t);t:SetTexture(WHITE);t:ClearAllPoints();t:SetPoint('TOPLEFT',frame,'TOPLEFT',b[1],b[2]);t:SetSize(b[3],b[4]);solid(t,c.text)end
 end
 frame.interfaceTextColor=text
 if frame.label then frame.label:SetTextColor(unpack(text))end
 if kind=='input' then frame:SetTextColor(unpack(text))end
 if frame.selection then frame.selection:Hide()end
 frame:SetAlpha(frame.bvRowDisabled and .4 or 1)
end
function R:Skin(style,frame,fill,alpha)
 frame.fills={};frame.borders={};frame.interfaceFill=fill;frame.interfaceOpacity=alpha
 function frame:PaintSurface(background,edge,opacity,top,bottom)
  self.interfaceOverride={background=background,edge=edge,opacity=opacity,top=top,bottom=bottom}
  R:Paint(style,self,self.interfaceKind or 'panel',self.interfaceState or {fill=fill})
 end
 style:Bind(function()if not frame.surfacePaintOwned then R:Paint(style,frame,frame.interfaceKind or 'panel',frame.interfaceState or {fill=fill})end end,frame)
 frame:HookScript('OnSizeChanged',function()R:Paint(style,frame,frame.interfaceKind or 'panel',frame.interfaceState or {fill=fill})end)
 return frame
end
function R:Slider(style,slider,thumb)
 local previousWidth,previousHeight=thumb:GetWidth(),thumb:GetHeight()
 local c=style.interfaceColors;local key=ns.ThemeTokens.MaterialFamily(style.interfaceThemeKey);local enabled=slider:IsEnabled();local muted=not enabled
 slider.track:SetTexture(WHITE);slider.track:SetColorTexture(unpack(c.controlEdge));slider.fill:SetColorTexture(unpack(muted and c.muted or c.accent));sampling(slider.track);sampling(slider.fill)
 if slider.scrollbar then thumb:SetTexture(WHITE);thumb:SetVertexColor(unpack(c.muted));slider.fill:Hide();return end
 slider.fill:Show();local assetKey=key=='classic' and 'classicSliderThumb' or key=='bv-steel' and 'sliderSteelThumb' or key=='bv-forge' and 'sliderForgeThumb' or nil
 if assetKey then local a=assets[assetKey];thumb:SetTexture(style.materialMediaRoot..a.path);thumb:SetTexCoord(0,a.u,0,a.v);thumb:SetVertexColor(1,1,1,muted and .4 or 1);thumb:SetSize(unit(key=='classic' and 40 or 12),unit(key=='classic' and 40 or key=='bv-forge' and 20 or 19))
 else thumb:SetTexture(key=='modern' and WHITE or style.materialMediaRoot..assets.circleMask.path);thumb:SetTexCoord(0,1,0,1);thumb:SetVertexColor(unpack(muted and c.muted or key=='modern' and c.accentText or c.text));thumb:SetSize(unit(key=='modern' and 12 or 16),unit(key=='modern' and 18 or 16));sampling(thumb)end
 if key=='classic' then local a=assets.classicSliderTrack;slider.track:SetTexture(style.materialMediaRoot..a.path);slider.track:SetTexCoord(0,a.u,0,a.v);slider.track:SetVertexColor(1,1,1,muted and .4 or 1);slider.track:SetHeight(unit(16))else slider.track:SetHeight(unit(4))end
 slider.fill:SetHeight(unit(4))
 -- The native Slider caches thumb travel after a size-only material change.
 -- Expanding (never clamping) and restoring its range invalidates that cache,
 -- also while hidden, without writing its value or touching layout anchors.
 if thumb:GetWidth()~=previousWidth or thumb:GetHeight()~=previousHeight then
  local low,high=slider:GetMinMaxValues()
  local expanded=high+math.max(1,math.abs(high)*.000001)
  if expanded>high and expanded<math.huge then
   slider:SetMinMaxValues(low,expanded)
   slider:SetMinMaxValues(low,high)
  end
 end
end

-- Selection controls share the Factory's value/callback/lifecycle contract.
-- R9 defines Switch shapes. Check/Radio are semantic extensions of those
-- materials, not additional standalone widget implementations.
local function choiceAsset(style,mark,key,name,layer)
 local a=assets[name];local t=texture(mark,key,layer or 'ARTWORK')
 t:SetTexture(style.materialMediaRoot..a.path);t:SetTexCoord(0,a.u,0,a.v)
 t:ClearAllPoints();t:SetAllPoints(mark);t:SetVertexColor(1,1,1,1);return t
end
local function choiceCircle(style,mark,key,width,height,x,y,color,layer,sublevel)
 local t=texture(mark,key,layer or 'ARTWORK');sampling(t)
 if sublevel~=nil then t:SetDrawLayer(layer or 'ARTWORK',sublevel)end
 t:SetTexture(WHITE);solid(t,color);t:ClearAllPoints()
 t:SetPoint('TOPLEFT',mark,'TOPLEFT',x,-y);t:SetSize(width,height)
 if not t.choiceMask then
  t.choiceMask=mark:CreateMaskTexture();sampling(t.choiceMask)
  t.choiceMask:SetAllPoints(t);t:AddMaskTexture(t.choiceMask)
 end
 t.choiceMask:SetTexture(style.materialMediaRoot..assets.circleMask.path)
 return t
end
local function choiceCapsule(style,mark,key,inset,color)
 local w,h=mark:GetWidth()-2*inset,mark:GetHeight()-2*inset
 -- R9: inset surfaces must cover all outer cap textures, including masked parts.
 local sublevel=inset>0 and 1 or 0
 choiceCircle(style,mark,key..'Left',h,h,inset,inset,color,'ARTWORK',sublevel)
 choiceCircle(style,mark,key..'Right',h,h,inset+w-h,inset,color,'ARTWORK',sublevel)
 local mid=texture(mark,key..'Middle','ARTWORK');mid:SetDrawLayer('ARTWORK',sublevel);sampling(mid);mid:SetTexture(WHITE);solid(mid,color)
 mid:ClearAllPoints();mid:SetPoint('TOPLEFT',mark,'TOPLEFT',inset+h/2,-inset);mid:SetSize(w-h,h)
end
function R:Selection(style,control,kind)
 local c,key=style.interfaceColors,ns.ThemeTokens.MaterialFamily(style.interfaceThemeKey)
 local enabled,on=control:IsEnabled(),control.value==true
 local hovered,pressed,focused=enabled and control.hovered,enabled and control.pressed,enabled and control.keyboardFocused
 local native=key=='modern' or key=='classic';local square=key=='bv-steel' or key=='bv-forge'
 local switch=kind=='switch';local radio=kind=='radio'
 local size=native and (key=='classic' and 30 or 24) or 20
 local w,h=switch and not native and 40 or size,switch and not native and 22 or size
 local mark=control.mark;hide(mark);hide(control.choiceThumb)
 mark:SetSize(unit(w),unit(h));control.choiceThumb:Hide()
 if switch then control:SetSize(unit(w),unit(h))
 else
  control:SetHeight(unit(math.max(28,h)));control.label:ClearAllPoints()
  control.label:SetPoint('LEFT',control,'LEFT',unit(w+8),0);control.label:SetPoint('RIGHT',control,'RIGHT',-unit(2),0)
  control.label:SetHeight(unit(math.max(28,h)));control.label:SetTextColor(unpack(enabled and c.text or c.muted))
 end
 local active=key=='clean' and mix(c.field,c.accent,.30) or c.selection
 local face=on and active or c.field;local edge=on and c.accent or (switch and not native and not square and c.edge or c.controlEdge)
 local ink=on and c.accent or c.muted
 if key=='modern' then edge=c.controlEdge end
 if hovered then edge=c.accentText end
 if pressed then face=mix(face,c.bg,.22);edge=c.accentText end
 -- Keep selection legible while disabled, but remove active pigment/emphasis.
 if not enabled then face=on and mix(c.field,c.muted,.12) or c.field;edge=c.edge;ink=c.muted end
 control.interfaceKind=kind;control.interfaceState={enabled=enabled,selected=on,hovered=not not hovered,pressed=not not pressed,focused=not not focused}
 control.interfaceFace=face;control.interfaceEdge=edge
 control:SetAlpha(control.bvRowDisabled and .4 or 1);mark:SetAlpha(enabled and 1 or .55)
 control.tick:Hide();control.thumb:Hide()
 if radio then
  -- Radio stays circular for recognisable exclusive-choice semantics.
  local rim=key=='classic' and mix(c.controlEdge,c.text,.3) or edge
  choiceCircle(style,mark,'radioRim',unit(w),unit(h),0,0,rim)
  choiceCircle(style,mark,'radioFace',unit(w-2),unit(h-2),unit(1),unit(1),face)
  if key=='classic' then
   choiceCircle(style,mark,'radioInset',unit(w-6),unit(h-6),unit(3),unit(3),edge)
   choiceCircle(style,mark,'radioWell',unit(w-8),unit(h-8),unit(4),unit(4),face)
  end
  if on then
   local dot=native and (key=='classic' and 10 or 9) or 8
   local t=choiceCircle(style,mark,'radioDot',unit(dot),unit(dot),unit((w-dot)/2),unit((h-dot)/2),enabled and c.accentText or c.muted,'OVERLAY');control.tick=t
  end
 elseif native and key=='classic' then
  local frame=choiceAsset(style,mark,'classicFrame',pressed and 'classicCheckboxDown' or 'classicCheckbox')
  if hovered then local t=choiceAsset(style,mark,'classicHover','classicCheckboxHover','OVERLAY');t:SetBlendMode('ADD');t:SetDrawLayer('OVERLAY',0)end
  if on then local t=choiceAsset(style,mark,'classicTick','classicCheck','OVERLAY');t:SetDrawLayer('OVERLAY',1);solid(t,enabled and c.accentText or c.muted);control.tick=t end
 elseif switch and not native and not square then
  choiceCapsule(style,mark,'capsuleOuter',0,edge);choiceCapsule(style,mark,'capsuleInner',unit(1),face)
  local t=choiceCircle(style,mark,'capsuleThumb',unit(16),unit(16),unit(on and 21 or 3),unit(3),ink,'OVERLAY');control.thumb=t
 else
  local radius=switch and square and (key=='bv-steel' and 5 or 2) or key=='bv-forge' and 2 or key=='bv-steel' and 3 or key=='modern' and 3 or 4
  -- Modern checkbox uses an un-tinted field; the selected tick carries accent.
  if key=='modern' and enabled and not pressed then face=c.field;control.interfaceFace=face end
  slice(style,mark,'choiceFace','round'..radius..'Fill',radius+1,radius+1,face,face,'BACKGROUND')
  slice(style,mark,'choiceEdge','round'..radius..'Edge',radius+1,radius+1,edge,edge,'BORDER')
  if switch and square then
   local thumb=control.choiceThumb;thumb:Show();thumb:ClearAllPoints();thumb:SetSize(unit(16),unit(16))
   thumb:SetPoint(on and 'RIGHT' or 'LEFT',mark,on and 'RIGHT' or 'LEFT',unit(on and -3 or 3),0)
   local r=key=='bv-steel' and 3 or 2
   slice(style,thumb,'thumbFace','round'..r..'Fill',r+1,r+1,ink,ink,'ARTWORK')
  elseif on then
   local t=choiceAsset(style,mark,'modernTick','modernCheck','OVERLAY');t:ClearAllPoints();t:SetPoint('CENTER',mark,'CENTER',0,0);t:SetSize(unit(15),unit(14));solid(t,enabled and c.accentText or c.muted);control.tick=t
  end
 end
 if focused then
  -- Interior focus indication is independent from persistent selection.
  if radio or switch and not native and not square then
   local t=texture(mark,'focusLine','OVERLAY');sampling(t);t:SetTexture(WHITE);solid(t,c.text)
   t:ClearAllPoints();t:SetPoint('BOTTOM',mark,'BOTTOM',0,unit(2));t:SetSize(unit(radio and 6 or 10),unit(1))
  else
   local r=2;slice(style,mark,'choiceFocus','round2Edge',3,3,c.text,c.text,'OVERLAY',unit(3))
  end
 end
 -- Expose the existing UI facade's surface collections without separate painters.
 control.fills=control.fills or {};control.borders=control.borders or {}
 for i=#control.fills,1,-1 do control.fills[i]=nil end;for i=#control.borders,1,-1 do control.borders[i]=nil end
 for name,t in pairs(mark.interfaceTextures or {})do
  if t:IsShown()then local list=(name:find('Edge') or name:find('Outer') or name:find('Rim') or name:find('Focus') or name=='focusLine') and control.borders or control.fills;list[#list+1]=t end
 end
end

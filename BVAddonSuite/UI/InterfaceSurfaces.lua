local _,ns=...
local S={};ns.InterfaceSurfaces=S
local M=ns.DesignSystem.Metrics
S.assets={relief='Relief',atlas='Atlas',mist='Mist',patina='Patina',horde='Horde',alliance='Alliance'}
-- Texture strength: percent0..50, step5; 30 means16.5% window art.
-- All six original images contain1024x683 pixels in a1024x1024 POT texture.
function S.Crop(width,height,key)
 local scale=math.max(width/1024,height/683)
 local visibleW,visibleH=width/scale,height/scale
 local focalY=key=='horde' and .2 or key=='alliance' and .4 or .5
 local left=(1024-visibleW)*.5;local top=(683-visibleH)*focalY
 return left/1024,(left+visibleW)/1024,top/1024,(top+visibleH)/1024
end
local function sampling(t)
 if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false)end
 if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0)end
end
local function layer(parent,corners,radius,root)
 local item={parent=parent,parts={},corners=corners or {},radius=radius or 0}
 for i=1,9 do
  local t=parent:CreateTexture(nil,'BORDER',nil,-6);sampling(t);item.parts[i]=t
  if item.corners[i] then
   local mask=parent:CreateMaskTexture(nil,'BORDER');mask:SetTexture(root..'Shapes\\'..(radius==9 and 'ShellRound9Fill' or 'Round'..radius..'Fill'),'CLAMPTOBLACKADDITIVE','CLAMPTOBLACKADDITIVE')
   mask:SetAllPoints(t);t:AddMaskTexture(mask);sampling(mask)
   local x,y=(i-1)%3,math.floor((i-1)/3);local cap=radius+1
   mask:SetTexCoord(x==0 and 0 or (64-cap)/64,x==0 and cap/64 or 1,y==0 and 0 or (64-cap)/64,y==0 and cap/64 or 1)
   item.masks=item.masks or {};item.masks[i]=mask
  end
 end
 function item:Hide()for _,t in ipairs(self.parts)do t:Hide()end end
 function item:Paint(path,alpha,x,y,w,h,originX,originY,windowWidth,windowHeight,uv)
  local cap=math.min(self.radius+1,w/2,h/2);local xs,ys={0,cap,w-cap,w},{0,cap,h-cap,h}
  for iy=1,3 do for ix=1,3 do local t=self.parts[(iy-1)*3+ix]
   local pw,ph=xs[ix+1]-xs[ix],ys[iy+1]-ys[iy]
   t:ClearAllPoints();M.Point(t,'TOPLEFT',self.parent,'TOPLEFT',x+xs[ix],-y-ys[iy]);M.Size(t,math.max(.01,pw),math.max(.01,ph))
   local l,r=(originX+xs[ix])/windowWidth,(originX+xs[ix+1])/windowWidth
   local top,bottom=(originY+ys[iy])/windowHeight,(originY+ys[iy+1])/windowHeight
   t:SetTexture(path);t:SetTexCoord(uv[1]+(uv[2]-uv[1])*l,uv[1]+(uv[2]-uv[1])*r,uv[3]+(uv[4]-uv[3])*top,uv[3]+(uv[4]-uv[3])*bottom)
   t:SetVertexColor(1,1,1,alpha);t:SetShown(pw>0 and ph>0)
  end end
 end
 return item
end
local function motif(style,width,height)
 local option=style.interfaceSurface
 local asset=option and S.assets[option.key]
 if not asset or width<=0 or height<=0 then return end
 return style.materialMediaRoot..'Backgrounds\\'..asset,{S.Crop(width,height,option.key)},option.strength/100*.55
end

-- Standalone settings editors share the Config motif and its window-space crop.
-- The small editor has a title bar and a left column rather than Config's
-- navigation, search and scroll controllers. Use its actual region geometry.
function S:AttachEditor(style,window,sidebarWidth,artLevel)
 local body=CreateFrame('Frame',nil,window)
 body:SetAllPoints(window.content);body:SetFrameLevel(artLevel);body:EnableMouse(false)
 local head=layer(window.chrome.titlebar,{},0,style.materialMediaRoot)
 local page=layer(body,{},0,style.materialMediaRoot)
 local function refresh()
  local w,h=M.GetWidth(window),M.GetHeight(window)
  local path,uv,alpha=motif(style,w,h)
  if not path or alpha<=0 or not window:IsShown() or window.minimized then head:Hide();page:Hide();return end
  local inset=ns.ShellMetrics.IsWoW(style.interfaceThemeKey) and 6 or 3
  local top=window.shellMetrics.contentTop
  local bodyWidth,bodyHeight=ns.ShellMetrics.ContentSize(w,h,window.shellMetrics)
  local width=style.interfaceSurface.area=='full' and bodyWidth or math.min(sidebarWidth,bodyWidth)
  head:Paint(path,alpha,inset,inset,w-2*inset,top-inset,inset,inset,w,h,uv)
  page:Paint(path,alpha,inset,0,math.max(1,width-2*inset),math.max(1,bodyHeight-inset),
    window.shellMetrics.contentLeft+inset,top,w,h,uv)
 end
 style:Bind(refresh,body);window:HookScript('OnShow',refresh);window:HookScript('OnSizeChanged',refresh)
 body:HookScript('OnSizeChanged',refresh)
 return {header=head,body=page}
end
function S:Attach(style,window,regions,presentation)
 local wow=ns.ShellMetrics.IsWoW(style.interfaceThemeKey)
 local radius=wow and 0 or style.interfaceThemeKey=='bv-graphite' and 9 or style.interfaceThemeKey=='bv-steel' and 6 or style.interfaceThemeKey=='bv-forge' and 3 or 8
 local root=style.materialMediaRoot
 local result={style=style,window=window,regions=regions,presentation=presentation,layers={}}
 local layers=result.layers
 layers.full=layer(window,{},0,root)
 layers.side=layer(regions.sidebar,wow and {} or {[1]=true},radius,root)
 layers.header=layer(regions.header,wow and {} or {[3]=true},radius,root)
 layers.footer=layer(regions.footer,wow and {} or {[7]=true,[9]=true},radius,root)
 if wow then layers.title=layer(presentation.frame,{},0,root);layers.body=layer(presentation.bodyInset,{},0,root);layers.tabs=layer(window,{},0,root)end
 function result:Refresh()
  local option=style.interfaceSurface;local metrics=presentation.metrics
  for _,v in pairs(layers)do v:Hide()end
  if not metrics or not option or not S.assets[option.key] or window.minimized then return end
  local w,h=M.GetWidth(window),M.GetHeight(window)
  local path,uv,alpha=motif(style,w,h);if not path then return end
  self.crop,self.alpha=uv,alpha
  local function paint(item,x,y,rw,rh,ox,oy)item:Paint(path,alpha,x,y,rw,rh,ox,oy,w,h,uv)end
  local full=option.area=='full'
  if wow then
   if full then
    paint(layers.body,6,6,M.GetWidth(presentation.bodyInset)-12,M.GetHeight(presentation.bodyInset)-12,238,120)
    -- The separate tabs band is below the inset body. Keep the art on the
    -- window background, below all existing tab controls and their labels.
    paint(layers.tabs,232,h-87,math.max(1,w-246),33,232,h-87)
   end
   paint(layers.side,6,6,M.GetWidth(regions.sidebar)-12,M.GetHeight(regions.sidebar)-12,20,120)
   paint(layers.header,0,0,M.GetWidth(regions.header),M.GetHeight(regions.header),14,64)
   local top=style.interfaceThemeKey=='classic' and 2 or 6.4
   -- Chrome holder is below the separate caption plate and window buttons.
   paint(layers.title,64,top+6,math.max(1,w-72),40,64,top+6)
  else
   local inset=(style.interfaceThemeKey=='bv-steel' or style.interfaceThemeKey=='bv-forge')and 3 or 1
   -- Disjoint regions sample one global image: no double alpha below child fills.
   if full then paint(layers.full,inset+metrics.side,inset+metrics.header,metrics.width-metrics.side,metrics.height-metrics.header-metrics.footer,inset+metrics.side,inset+metrics.header)end
   paint(layers.side,0,0,M.GetWidth(regions.sidebar),M.GetHeight(regions.sidebar),inset,inset)
   paint(layers.header,0,0,M.GetWidth(regions.header),M.GetHeight(regions.header),inset+metrics.side,inset)
  end
  if full then paint(layers.footer,0,0,M.GetWidth(regions.footer),M.GetHeight(regions.footer),wow and 14 or (w-metrics.width)/2,h-metrics.footer-(wow and 12 or (h-metrics.height)/2))end
 end
 window:HookScript('OnSizeChanged',function()result:Refresh()end)
 style:Bind(function()result:Refresh()end,window)
 return result
end

-- Local, restrained card-header decoration; casing remains outer chrome only.
function S:AttachHeader(style,card,headerHeight)
 if style.materialProfile~='interface' then return end
 if card.headerSurface then return card.headerSurface end
 local result={style=style,card=card,height=headerHeight};card.headerSurface=result
 function result:Hide()
  if self.art then self.art:Hide();self.veil:Hide() end
  self.signature=nil
 end
 function result:Refresh()
  local option=style.interfaceSurface
  if card.surfaceHidden or not card:IsVisible() or not option or option.area~='full' or not S.assets[option.key] then self:Hide();return end
  local wow=ns.ShellMetrics.IsWoW(style.interfaceThemeKey)
  local inset=wow and 6 or math.max(4,(card.interfaceRadius or 3)+1)
  local top=wow and 6 or 1
  local width=M.GetWidth(card)-inset*2
  local height=math.min(self.height+1,M.GetHeight(card))-top
  if width<=0 or height<=0 then self:Hide();return end
  local bg=style.interfaceColors.bg
  local strength=tonumber(option.strength) or 0
  local alpha=math.max(0,math.min(.20,strength/100*.36))
  local signature=table.concat({option.key,strength,style.interfaceThemeKey,style.materialMediaRoot,tostring(style.interfaceColors),bg[1],bg[2],bg[3],width,height,inset,top},':')
  if self.signature==signature then return end
  if not self.art then
   self.art=card:CreateTexture(nil,'BACKGROUND');self.art:SetDrawLayer('BACKGROUND',1);sampling(self.art)
   self.veil=card:CreateTexture(nil,'BACKGROUND');self.veil:SetDrawLayer('BACKGROUND',2);sampling(self.veil)
  end
  local art,veil=self.art,self.veil
  art:ClearAllPoints();M.Point(art,'TOPLEFT',card,'TOPLEFT',inset,-top);M.Size(art,width,height)
  art:SetTexture(style.materialMediaRoot..'Backgrounds\\'..S.assets[option.key])
  art:SetTexCoord(S.Crop(width,height,option.key));art:SetVertexColor(1,1,1,alpha);art:Show()
  veil:SetAllPoints(art);veil:SetTexture('Interface\\Buttons\\WHITE8X8');veil:SetVertexColor(1,1,1,1)
  veil:SetGradient('HORIZONTAL',CreateColor(bg[1],bg[2],bg[3],.92),CreateColor(bg[1],bg[2],bg[3],.12));veil:Show()
  self.signature=signature
 end
 local function paint()result:Refresh()end
 style:Bind(paint,card);card:HookScript('OnSizeChanged',paint);card:HookScript('OnShow',paint)
 card:HookScript('OnHide',function()result:Hide()end)
 return result
end

-- Menu art uses the approved lower-left source at one texel per design unit.
-- Large popups expose quiet background beyond the source, never repeat/stretch it.
function S.MenuCrop(width,height)
 local w,h=math.min(1024,math.max(0,width)),math.min(683,math.max(0,height))
 return w,h,0,w/1024,(683-h)/1024,683/1024
end
function S:AttachMenu(style,menu)
 if style.materialProfile~='interface' then return end
 if menu.menuSurface then return menu.menuSurface end
 local result={style=style,menu=menu};menu.menuSurface=result
 -- Repaint the existing skin now, before first Show, with the menu-only reading contract.
 ns.ControlMaterials:Paint(style,menu,'panel',menu.interfaceState or {fill=menu.interfaceFill})
 function result:Hide()
  if self.art then self.art:Hide()end
  self.signature=nil
 end
 function result:Refresh()
  local option=style.interfaceSurface
  if menu.surfaceHidden or not menu:IsVisible() or not option or option.area~='full' or not S.assets[option.key] then self:Hide();return end
  local inset=ns.ShellMetrics.IsWoW(style.interfaceThemeKey) and 6 or 5
  local width,height=M.GetWidth(menu)-inset*2,M.GetHeight(menu)-inset*2
  if width<=0 or height<=0 then self:Hide();return end
  local w,h,u1,u2,v1,v2=S.MenuCrop(width,height)
  local alpha=math.max(0,math.min(1,(tonumber(option.strength) or 0)/100*.55))
  local signature=table.concat({option.key,alpha,style.materialMediaRoot,width,height,inset},':')
  if self.signature==signature then return end
  if not self.art then self.art=menu:CreateTexture(nil,'BACKGROUND',nil,1);sampling(self.art)end
  local art=self.art;art:ClearAllPoints();M.Point(art,'BOTTOMLEFT',menu,'BOTTOMLEFT',inset,inset);M.Size(art,w,h)
  art:SetTexture(style.materialMediaRoot..'Backgrounds\\'..S.assets[option.key]);art:SetTexCoord(u1,u2,v1,v2);art:SetVertexColor(1,1,1,alpha);art:Show()
  self.signature=signature
 end
 local function paint()result:Refresh()end
 style:Bind(paint,menu);menu:HookScript('OnSizeChanged',paint);menu:HookScript('OnShow',paint)
 menu:HookScript('OnHide',function()result:Hide()end)
 return result
end

-- Opt-in decoration for small, transparent gameplay HUDs. A single image lives
-- above the material fill, below borders and text. Never attach this to every
-- Panel: nested reading surfaces must not accumulate the same texture.
function S.HUDCrop(width,height)
 -- Keep the decorated lower-left corner at its source density on small HUDs.
 -- Only large surfaces scale the source; never repeat or expose POT padding.
 local scale=math.max(1,width/1024,height/683)
 return 0,width/scale/1024,(683-height/scale)/1024,683/1024
end
function S:AttachHUD(style,frame,opacity)
 if style.materialProfile~='interface' then return end
 if frame.hudSurface then return frame.hudSurface end
 local result={style=style,frame=frame};frame.hudSurface=result
 function result:Hide()
  if self.art then self.art:Hide()end
  self.signature=nil
 end
 function result:Refresh()
  local option=style.interfaceSurface
  local strength=option and tonumber(option.strength) or 0
  if frame.surfaceHidden or not frame:IsVisible() or not option or not S.assets[option.key] or strength<=0 then self:Hide();return end
  -- Keep the square image clear of rounded/native borders. HUD decoration uses
  -- the chosen motif independently of the large window's Full/Casing layout.
  local inset=ns.ShellMetrics.IsWoW(style.interfaceThemeKey) and 6 or math.max(5,(frame.interfaceRadius or 3)+1)
  local width,height=M.GetWidth(frame)-inset*2,M.GetHeight(frame)-inset*2
  if width<=0 or height<=0 then self:Hide();return end
  -- The source itself is dark. 30% means 24% art, not the nearly invisible
  -- 7.2% used previously. This affects neither the fill nor content opacity.
  local alpha=math.min(50,strength)/100*.8*(opacity and opacity() or 1)
  local signature=table.concat({option.key,alpha,style.materialMediaRoot,width,height,inset},':')
  if self.signature==signature then return end
  if not self.art then self.art=frame:CreateTexture(nil,'BACKGROUND');self.art:SetDrawLayer('BACKGROUND',1);sampling(self.art)end
  local art=self.art;art:ClearAllPoints();M.Point(art,'TOPLEFT',frame,'TOPLEFT',inset,-inset);M.Size(art,width,height)
  art:SetTexture(style.materialMediaRoot..'Backgrounds\\'..S.assets[option.key])
  art:SetTexCoord(S.HUDCrop(width,height));art:SetVertexColor(1,1,1,alpha);art:Show()
  self.signature=signature
 end
 local function paint()result:Refresh()end
 style:Bind(paint,frame);frame:HookScript('OnSizeChanged',paint);frame:HookScript('OnShow',paint)
 frame:HookScript('OnHide',function()result:Hide()end)
 return result
end

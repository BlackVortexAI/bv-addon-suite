local _,ns=...
local UI,L,M=ns.UI,ns.Layout,ns.LayoutModel
local D=ns.DesignSystem.Metrics
local Editor={movers={},connectors={},controls={},snap=true,overlays=true,gridSize=16}
ns.LayoutEditor=Editor
local function at(w,p,x,y) return UI:Place(w,p,x,y) end
local function opts(values) local out={}; for _,v in ipairs(values) do out[#out+1]={value=v,label=v} end; return out end
local INSPECTOR_TOP,INSPECTOR_HEIGHT=76,680
function Editor:Message(text) self.message:SetText(text or "") end
function Editor:SetGridSize(value)
    self:StopDrag(); ns.Settings:Set("gridSize",value); self.gridSize=value; self:Grid()
end
function Editor:SetShowHidden(value)
    self:StopDrag();self.showHidden=value==true;if self.hiddenToggle then self.hiddenToggle:SetValue(self.showHidden) end
    if self.selected and not self:InView(self.selected) then self.selected=nil end
    for _,id in ipairs(L.order) do L.elements[id].preview(self:InView(id),self.overlays) end;self:Refresh()
end
function Editor:SetOverlays(value)
    self.overlays=value==true; self.overlayToggle:SetValue(self.overlays)
    self.dim:SetShown(self.overlays)
    for i,line in ipairs(self.grid) do line:SetShown(self.overlays and i<=(self.gridCount or 0)) end
    if self.active and not self.suspended then
        for _,id in ipairs(L.order) do L.elements[id].preview(self:InView(id),self.overlays) end
    end
    self:Refresh()
end
function Editor:InView(id)
    local def=L.elements[id]
    if def and def.listed and not def.listed() then return false end
    -- Node option: kept out of the editor unless "Show hidden" is on; links
    -- still move it together with its anchor target.
    if def and def.editorHidden and not self.showHidden then return false end
    local seen={};local key=id
    while key and not seen[key] do
        if key==L.NAMEPLATE_TARGET then return self.viewMode=="nameplates" end
        seen[key]=true;local node=L:Nodes()[key];key=node and node.link and node.link.target
    end
    return self.viewMode~="nameplates"
end
function Editor:SetView(mode)
    self:StopDrag();self.picking=nil;self.viewMode=mode
    if self.selected and not self:InView(self.selected) then self.selected=nil end
    self.inspectorSelection=nil;for _,id in ipairs(L.order) do L.elements[id].preview(self:InView(id),self.overlays) end;self:Refresh()
end
function Editor:PositionInspector(rects)
    local drag=self.drag and self.drag.id==self.selected and self.drag
    if self.inspectorSelection==self.selected and not drag then return end
    self.inspectorSelection=self.selected
    local x,y=GetCursorPosition();local scale=UIParent:GetEffectiveScale()
    x,y=x/scale,y/scale
    rects=rects or L:Resolve();local r=rects[self.selected]
    local right=not r or r.x<=0
    -- Resolve the side and outside edge from the current element on every drag
    -- tick, including resize; the initial grab point is not a horizontal anchor.
    if r then x=UIParent:GetWidth()/2+r.x+(right and r.width/2 or -r.width/2) end
    if drag and r then
        y=drag.inspector.y+r.y-drag.rect.y
    end
    local panel=self.inspector;local ratio=panel:GetEffectiveScale()/scale
    local width,height=panel:GetWidth()*ratio,panel:GetHeight()*ratio
    local gap=ns.Settings:Get("inspectorGap")/scale
    local left=right and x+gap or x-gap-width
    left=math.max(8,math.min(UIParent:GetWidth()-width-8,left))
    local top=math.max(height+8,math.min(UIParent:GetHeight()-8,y+40))
    panel:ClearAllPoints();panel:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left/ratio,top/ratio)
end
function Editor:CanEdit(id)
    return self.active and not self.suspended and not self.inspectHidden and L.elements[id] and self:InView(id) and (not self.focus or id==self.selected)
end
function Editor:SetInspectionHidden(hidden,suppressRestore)
    self.inspectHidden=hidden==true
    if not self.active then return end
    self:StopDrag();UI:CloseDropdown()
    if hidden then
        self.root:Hide()
        for _,id in ipairs(L.order)do L.elements[id].preview(false)end
    elseif not suppressRestore and not self.suspended and not InCombatLockdown()then
        for _,id in ipairs(L.order)do L.elements[id].preview(self:InView(id),self.overlays)end
        self.root:Show();self:Refresh()
    end
end
function Editor:SetFocus(value)
    self:StopDrag(); self.picking=nil; self.focus=value==true
    if self.focusToggle then self.focusToggle:SetValue(self.focus) end
    self:Refresh()
end
-- Entire hit target uses native layout units, independent of toolbar UI density.
function Editor:PlaceGrip(mover,rect)
    local size,gap,margin=14,3,4
    local halfW,halfH=UIParent:GetWidth()/2,UIParent:GetHeight()/2
    local rw,rh=mover:GetWidth()/2,mover:GetHeight()/2
    local sx,sy=1,-1
    local drag=self.drag
    if drag and drag.resize and self.movers[drag.id]==mover then sx,sy=drag.sx,drag.sy
    else
        if rect.x+rw+gap+size+margin>halfW then sx=-1 end
        if rect.y-rh-gap-size-margin < -halfH then sy=1 end
    end
    local x,y=rect.x+sx*(rw+gap+size/2),rect.y+sy*(rh+gap+size/2)
    -- Oversized elements may leave no exterior space; keep the handle reachable.
    x=math.max(-halfW+margin+size/2,math.min(halfW-margin-size/2,x))
    y=math.max(-halfH+margin+size/2,math.min(halfH-margin-size/2,y))
    local grip=mover.grip
    grip.corner=(sy==1 and "TOP" or "BOTTOM")..(sx==1 and "RIGHT" or "LEFT")
    grip.sx,grip.sy=sx,sy; grip.bounds={left=x-size/2,right=x+size/2,bottom=y-size/2,top=y+size/2}
    grip:SetDirection(sx,sy)
    grip:ClearAllPoints(); grip:SetPoint("CENTER",UIParent,"CENTER",x,y)
end
function Editor:Change(patch)
    if not self:CanEdit(self.selected) then return end
    local ok,why=L:Change(self.selected,patch); if not ok then self:Message(why) else self:Message("") end
end
function Editor:PlaceCaption(mover,text)
    local b=mover.grip.bounds;local gap,margin=6,4
    local halfW,halfH=UIParent:GetWidth()/2,UIParent:GetHeight()/2
    local label=mover.title;label:SetText((text:gsub("[\r\n\t]+"," ")))
    local wanted=math.min(320,label:GetUnboundedStringWidth())
    local left=math.max(0,b.left-gap+halfW-margin)
    local right=math.max(0,halfW-margin-b.right-gap)
    local onRight=left<wanted and right>left
    local width=math.min(wanted,onRight and right or left)
    local _,size=label:GetFont();local height=(size or 12)*1.4
    local y=math.max(-halfH+margin+height/2,math.min(halfH-margin-height/2,(b.bottom+b.top)/2))
    label:ClearAllPoints();label:SetHeight(height);label:SetJustifyV("MIDDLE")
    label:SetJustifyH(onRight and "LEFT" or "RIGHT")
    local x=onRight and b.right+gap or b.left-gap
    label:SetPoint(onRight and "LEFT" or "RIGHT",UIParent,"CENTER",x,y)
    UI:FitCaption(label,text,width)
    UI:AttachTooltip(mover.grip,text,"Drag to resize. Drag the element itself to move it.")
end
function Editor:Targets(axis)
    local out={}
    if L:TargetAllowed(self.selected,axis,"none") then out[#out+1]={value="none",label="Independent"}end
    if axis=="position" then
        if L:TargetAllowed(self.selected,axis,L.CURSOR_TARGET)then out[#out+1]={value=L.CURSOR_TARGET,label="Mouse cursor"}end
        if L:TargetAllowed(self.selected,axis,L.NAMEPLATE_TARGET)then out[#out+1]={value=L.NAMEPLATE_TARGET,label="Nameplate"}end
    end
    for _,id in ipairs(L.order) do if L:TargetAllowed(self.selected,axis,id) then out[#out+1]={value=id,label=L.elements[id].label} end end
    if ns.ExternalFrames then
        for _,option in ipairs(ns.ExternalFrames:Targets(L:Nodes()))do if L:TargetAllowed(self.selected,axis,option.value)then out[#out+1]=option end end
        if L:TargetAllowed(self.selected,axis,"frame:TradeFrame")then out[#out+1]={value="library:frame",label="Frame library..."}end
    end
    return out
end
function Editor:ChooseTarget(axis,id)
    if id=="library:frame" then
        local selected,draft,profile=self.selected,L.draft,ns.Settings:Profile()
        UI:OpenFrameLibrary({choose=function(reference)
            if not self.active or self.suspended or self.selected~=selected or L.draft~=draft or ns.Settings:Profile()~=profile then return end
            if not ns.ExternalFrames:CanReference(reference,L:Nodes())then self:Message("External frame reference limit reached (32).");return end
            self:ChooseTarget(axis,"frame:"..reference)
        end});return
    end
    self.picking=nil
    if not L:TargetAllowed(self.selected,axis,id)then self:Message("Choose a target allowed for this template slot.");return end
    if id=="none" then L:Unlink(self.selected,axis)
    elseif id==self.selected then self:Message("Choose another element.")
    elseif axis=="position" then
        local special=id==L.CURSOR_TARGET or id==L.NAMEPLATE_TARGET
        local old=L:Get(self.selected).link or {side=special and "CENTER" or "BOTTOM",align="CENTER",gap=special and 0 or 6,offset=0}
        local link=M.Copy(old); link.target=id; self:Change({link=link})
    else self:Change({[axis.."Target"]=id}) end
    self:Refresh()
end
function Editor:ChangeStack(key,value)
    local n=L:Get(self.selected)
    if n.anchorPoint~=1 then return end
    if key=="enabled"then self:Change({stack=value and M.NormalizeStack(n.stack) or false});return end
    local stack=M.NormalizeStack(n.stack);stack[key]=value;self:Change({stack=stack})
end
function Editor:Select(id)
    self:CancelAnchorDelete()
    if self.picking then self:ChooseTarget(self.picking,id); return true end
    if not self:CommitAnchorName() then return false end
    self:StopDrag(); self.selected=id; self:Message(""); self:Refresh(); return true
end
function Editor:CancelAnchorDelete()
    self.deleteTarget=nil
    if self.deleteDialog then self.deleteDialog:Hide() end
end
function Editor:RefreshAnchorDelete()
    local target=self.deleteTarget
    if not target then return end
    local raw=L:Nodes()[target.id]
    if target.profile~=ns.Settings:Profile() or not raw then self:CancelAnchorDelete(); return end
    local refs=ns.DisplayAnchors:AnchorReferences(target.id)
    self.deleteRefs=refs
    local pages=math.max(1,math.ceil(#refs/4)); self.deletePage=math.max(1,math.min(pages,self.deletePage or 1))
    self.deleteTitle:SetText(#refs>0 and "Anchor is still in use" or "Delete anchor?")
    self.deleteInfo:SetText(#refs>0 and "Unlink these references first. Save changed graph layouts,\nthen reopen this dialog. Nothing will be deleted." or "Delete "..raw.label.."?\nThis is a draft change until Save & exit. Discard restores it.")
    local lines={}; for i=(self.deletePage-1)*4+1,math.min(self.deletePage*4,#refs) do lines[#lines+1]=refs[i] end
    self.deleteList:SetText(table.concat(lines,"\n\n"))
    self.deletePageLabel:SetText(#refs.." references  /  "..self.deletePage.." / "..pages)
    self.deletePrev:SetShown(pages>1); self.deleteNext:SetShown(pages>1); self.deletePageLabel:SetShown(#refs>0)
    self.deleteAccept:SetShown(#refs==0)
end
function Editor:RequestAnchorDelete()
    if not self.active or self.suspended or not L.elements[self.selected] or not L.elements[self.selected].anchorPoint then return end
    if not self:CommitAnchorName() then return end
    self:StopDrag(); self.picking=nil; UI:CloseDropdown(); self.confirm:Hide()
    self.deleteTarget={id=self.selected,profile=ns.Settings:Profile()}; self.deletePage=1
    self:RefreshAnchorDelete(); self.deleteDialog:Show()
end
function Editor:ConfirmAnchorDelete()
    local target=self.deleteTarget
    if not target or not self.active or self.suspended or target.profile~=ns.Settings:Profile() then return end
    local ok,why=ns.DisplayAnchors:DeleteAnchor(target.id) -- recheck, never trust the opened dialog
    if not ok then self:RefreshAnchorDelete(); self:Message(why); return end
    self:CancelAnchorDelete(); self:Refresh(); self:Message("Anchor removed from draft. Save & exit to keep; Discard to restore.")
end
function Editor:CommitAnchorName()
    local input=self.anchorName
    if not input or not input.anchorID or not self.active or self.suspended then return true end
    local id=input.anchorID; local name=input:GetText():match("^%s*(.-)%s*$")
    if not L:Nodes()[id] or name==L:Get(id).label then return true end
    local ok,why=L:Change(id,{label=name})
    if not ok then self:Message(why); return false end
    return true
end
function Editor:StopDrag()
    if self.dragTimer then self.dragTimer:Cancel(); self.dragTimer=nil end
    local wasResize=self.drag and self.drag.resize
    self.drag=nil; self.press=nil
    if wasResize and self.active and not self.suspended then self:Refresh() end
    if self.guides then self.guides:Hide() end
end
function Editor:EndDrag()
    if self.drag then ns:Call("layout/drag",self.DragStep,self) end
    self:StopDrag()
end
local function cursor()
    local x,y=GetCursorPosition(); local scale=UIParent:GetEffectiveScale(); return x/scale,y/scale
end
function Editor:Press(id,button)
    if not self.active or self.suspended then return end
    local picking=self.picking~=nil
    if not picking and not self:CanEdit(id) then return end
    self:StopDrag(); if not self:Select(id) then return end
    if picking or button~="LeftButton" then return end
    local x,y=cursor(); local rect=L:Resolve()
    self.press={id=id,x=x,y=y,rect=M.Copy(rect[id]),node=L:Get(id)}
end
function Editor:BeginDrag(id,resize)
    if resize and L.elements[id] and L.elements[id].sizeLocked then self:Message("Size is locked on its node.");return end
    if not self:CanEdit(id) or self.picking then return end
    local press=not resize and self.press and self.press.id==id and self.press or nil
    if not self:Select(id) then return end; self:StopDrag()
    local x,y=cursor(); local rect=L:Resolve(); rect=rect[id]
    if press then x,y,rect=press.x,press.y,press.rect end
    local grip=self.movers[id].grip
    self.drag={id=id,x=x,y=y,rect=M.Copy(rect),node=press and press.node or L:Get(id),resize=resize,
        corner=grip.corner,sx=grip.sx or 1,sy=grip.sy or -1,started={},snapped={},hits={},direction={},pointer={},
        inspector={y=y}}
    -- Include movement during WoW's drag threshold instead of shifting the grab point.
    if press then self:DragStep() else self:PositionInspector() end
    self.dragTimer=C_Timer.NewTicker(0.02,function()
        local ok=ns:Call("layout/drag",self.DragStep,self)
        if not ok then self:StopDrag() end
    end)
end
function Editor:DragStep()
    local d=self.drag; if not d or self.suspended then return end
    local x,y=cursor(); local dx,dy=x-d.x,y-d.y
    local step=self.gridSize
    local snapping=self.snap and not IsShiftKeyDown()
    local function snap(value,start,key)
        if not d.started[key] and math.abs(value-start)*UIParent:GetEffectiveScale()<3 then return start end
        d.started[key]=true
        if not snapping then d.snapped[key]=nil; return value end
        local previous=d.snapped[key]
        -- Small hysteresis prevents chatter around a grid-cell midpoint.
        if previous and math.abs(value-previous)<=step*.60 then return previous end
        local result=math.floor(value/step+.5)*step; d.snapped[key]=result; return result
    end
    if d.resize then
        local patch={}; local rules=L.elements[d.id].limits or {}
        local sx,sy=d.sx,d.sy
        local fixedX,fixedY=d.rect.x-sx*d.rect.width/2,d.rect.y-sy*d.rect.height/2
        local edgeX,edgeY=d.rect.x+sx*d.rect.width/2,d.rect.y+sy*d.rect.height/2
        local width=sx*(snap(edgeX+dx,edgeX,"width")-fixedX)
        local height=sy*(snap(edgeY+dy,edgeY,"height")-fixedY)
        local maxWidth=math.max(1,UIParent:GetWidth()/2-sx*fixedX)
        local maxHeight=math.max(1,UIParent:GetHeight()/2-sy*fixedY)
        if not d.node.widthTarget then patch.width=math.max(rules.minWidth or 1,math.min(rules.maxWidth or 5000,maxWidth,width)) end
        if not d.node.heightTarget and not L.elements[d.id].autoHeight then patch.height=math.max(rules.minHeight or 1,math.min(rules.maxHeight or 2000,maxHeight,height)) end
        if (patch.width or d.rect.width)==(d.lastWidth or d.rect.width) and (patch.height or d.rect.height)==(d.lastHeight or d.rect.height) then return end
        local dw,dh=(patch.width or d.rect.width)-d.rect.width,(patch.height or d.rect.height)-d.rect.height
        local nx,ny=d.rect.x+sx*dw/2,d.rect.y+sy*dh/2
        if not d.node.link then patch.screen="CENTER"; patch.x=nx; patch.y=ny
        else
            -- Resolve the candidate before adjusting its link: the target may itself
            -- match this element's size. Derivatives of the source alone miss that.
            local nodes,unbounded={},{}
            local stored=L:Nodes()
            for _,id in ipairs(L.order) do
                nodes[id]=stored[id]
                if stored[id].templateId and stored[id].templateRoot~=id then unbounded[id]=true end
            end
            nodes[d.id]=M.Copy(d.node)
            if patch.width then nodes[d.id].width=patch.width end
            if patch.height then nodes[d.id].height=patch.height end
            local predicted,_,constrained=M.Resolve(nodes,L.externalRects or {},UIParent:GetWidth(),UIParent:GetHeight(),nil,nil,{unboundedNodes=unbounded})
            local r=constrained[d.id] or predicted[d.id]
            local predictedX,predictedY=r.x,r.y
            local a=M.Copy(d.node.link)
            local ox,oy=nx-predictedX,ny-predictedY
            if a.side=="CENTER" then a.offset=a.offset+ox; a.gap=a.gap+oy
            elseif a.side=="TOP" or a.side=="BOTTOM" then a.offset=a.offset+ox; a.gap=a.gap+oy*(a.side=="TOP" and 1 or -1)
            else a.offset=a.offset+oy; a.gap=a.gap+ox*(a.side=="RIGHT" and 1 or -1) end
            patch.link=a
        end
        d.lastWidth,d.lastHeight=patch.width,patch.height; self:Change(patch)
    else
        local rects=L:Resolve()
        local order={};for _,id in ipairs(L.order) do if self:InView(id) then order[#order+1]=id end end
        local targets=ns.SnapModel.Targets(d.id,L:Nodes(),rects,order)
        local bypass=IsShiftKeyDown()
        local function moveAxis(axis,delta,extent)
            local start=d.rect[axis]; local raw=start+delta
            local travel=raw-(d.pointer[axis] or start)
            if math.abs(travel)>.001 then d.direction[axis]=travel>0 and 1 or -1 end
            d.pointer[axis]=raw
            local options={grid=self.snap and not bypass,elements=self.elementSnap and not bypass,step=step,scale=UIParent:GetEffectiveScale()}
            if not d.started[axis] and math.abs(delta)*options.scale<3 then
                options.grid=false
                local value,hit=ns.SnapModel.Axis(start,extent,axis,targets,options,nil,d.direction[axis] or 0)
                d.hits[axis]=math.abs(value-start)<.00001 and hit or nil
                return start
            end
            d.started[axis]=true
            local value,hit=ns.SnapModel.Axis(raw,extent,axis,targets,options,d.hits[axis],d.direction[axis] or 0)
            d.hits[axis]=hit; return value
        end
        local nx,ny=moveAxis("x",dx,d.rect.width),moveAxis("y",dy,d.rect.height)
        if nx~=(d.lastX or d.rect.x) or ny~=(d.lastY or d.rect.y) then
            d.lastX,d.lastY=nx,ny; L:Move(d.id,nx,ny)
        end
        rects=L:Resolve()
        for _,axis in ipairs({"x","y"}) do
            if math.abs(rects[d.id][axis]-(axis=="x" and nx or ny))>.00001 then d.hits[axis]=nil end
            local hit=d.hits[axis]
            self.guides:Draw(axis,hit,rects[d.id],hit and rects[hit.target])
        end
        self:PositionInspector(rects)
    end
end
function Editor:Refresh()
    if not self.active or not self.root or self.inspectHidden then return end
    local rects,warnings=L:Resolve()
    self:EnsureMovers()
    -- Movers follow draw order while editor chrome and dialogs remain above all.
    local chrome=self.root:GetFrameLevel()+20+((L.drawCount or 0)+2)*4
    for key,offset in pairs({toolbar=0,inspector=1,confirm=30,deleteDialog=40,cleanupShield=49,cleanupDialog=50})do
        if self[key] then self[key]:SetFrameLevel(chrome+offset) end
    end
    if not L.elements[self.selected] or not self:InView(self.selected) then self.selected=nil;for _,id in ipairs(L.order) do if self:InView(id) then self.selected=id;break end end end
    if not self.selected and not self.showHidden then
        for _,id in ipairs(L.order) do if L.elements[id].editorHidden then self:Message("Some elements are hidden by their node. Turn on Show hidden to edit them.");break end end
    end
    for _,id in ipairs(L.order) do
        local mover=self.movers[id]; local r=rects[id]
        mover:SetShown(self:InView(id))
        local minimum=L.elements[id].anchorPoint and 32 or 16
        mover:ClearAllPoints(); mover:SetPoint("CENTER",UIParent,"CENTER",r.x,r.y); mover:SetSize(math.max(minimum,r.width),math.max(minimum,r.height))
        for _,line in ipairs(mover.edges) do line:SetColorTexture(ns.Theme:Color(id==self.selected and "accent" or "edge")) end
        mover.title:SetText(L.elements[id].label..(L.elements[id].enabled() and "" or "  /  disabled preview"))
        mover.fill:SetShown(self.overlays)
        -- Display captions follow the selected grip; ordinary bars keep centered labels.
        local display=L.elements[id].displayAnchor
        mover.title:ClearAllPoints()
        mover.title:SetPoint(display and "TOP" or "CENTER",mover,display and "BOTTOM" or "CENTER",0,display and -5 or 0)
        mover.title:SetShown(self.overlays and (not display or id==self.selected))
        -- A locked overlapping mover must never cover the focused move surface.
        -- Picking reverses that rule: the source stops intercepting target clicks.
        local rank=L.drawRanks and L.drawRanks[id] or 1
        local focused=self.focus and id==self.selected and not self.picking
        mover:SetFrameLevel(self.root:GetFrameLevel()+5+(focused and (L.drawCount or 0)+1 or rank)*4)
        mover:EnableMouse(not (self.picking and id==self.selected))
        mover.grip:SetFrameLevel(mover:GetFrameLevel()+2)
        mover:SetAlpha(self.focus and id~=self.selected and .35 or 1)
        self:PlaceGrip(mover,r)
        if display and id==self.selected then self:PlaceCaption(mover,mover.title:GetText()) end
        mover.grip:SetShown(id==self.selected and not self.picking and not self.suspended and not L.elements[id].sizeLocked)
        for _,edge in ipairs(mover.edges) do edge:SetAlpha((self.overlays or id==self.selected) and 1 or .35) end
    end
    for _,connector in pairs(self.connectors) do connector:Hide() end
    for _,id in ipairs(L.order) do
        local link=L:Get(id).link
        local target=link and (rects[link.target] or L.externalRects and L.externalRects[link.target])
        if target and not warnings[id] and self:InView(id) and (not L.elements[link.target] or self:InView(link.target)) then
            local connector=self.connectors[id]
            if not connector then
                connector=UI:AnchorConnector(self.root); connector:SetFrameLevel(self.root:GetFrameLevel()+6)
                self.connectors[id]=connector
            end
            connector:SetGeometry(rects[id],target,link.side,id==self.selected or link.target==self.selected)
        end
    end
    if not L.elements[self.selected] or not self:InView(self.selected) then self.selected=nil;for _,id in ipairs(L.order) do if self:InView(id) then self.selected=id;break end end end
    self.inspector:SetShown(self.selected~=nil)
    local elements={}
    for _,id in ipairs(L.order) do if self:InView(id) then elements[#elements+1]={value=id,label=L.elements[id].label} end end
    self.elementSelect:SetOptions(elements); self.elementSelect:SetValue(self.selected)
    if not self.selected then return end
    local n=L:Get(self.selected); local rect=rects[self.selected]
    local fullTitle=L.elements[self.selected].label
    UI:FitCaption(self.title,fullTitle,D.ToNative(288))
    self.titleHandle.tooltipTitle="Layout element";self.titleHandle.tooltipBody=fullTitle;self.titleHandle.tooltipText=fullTitle
    self.controls.zIndex:SetValue(n.zIndex)
    local anchor=L.elements[self.selected].anchorPoint
    self.controls.zIndex:SetShown(not anchor);self.controls.zIndex.fieldLabel:SetShown(not anchor);self.zHint:SetShown(not anchor)
    self.controls.zIndex.fieldLabel:SetText(n.templateId and n.templateRoot==self.selected and "Stack Z index" or n.templateId and "Slot Z index" or "Z index")
    self.zHint:SetText(n.templateId and n.templateRoot~=self.selected and "Higher = above slots in this stack. Root slot = 0."
        or "Higher = in front. A stack stays together.")
    for _,axis in ipairs({"position","width","height"}) do
        local c=self.controls[axis.."Target"]; c:SetOptions(self:Targets(axis))
        c:SetValue(axis=="position" and (n.link and n.link.target or "none") or n[axis.."Target"] or "none")
    end
    self.controls.width:SetValue(rect.width); self.controls.height:SetValue(rect.height)
    local autoHeight=L.elements[self.selected].autoHeight
    self.controls.height.fieldLabel:SetText(autoHeight and "Height (content)" or "Height")
    if autoHeight then self.controls.height:Disable();self.controls.heightTarget:Disable()
    else self.controls.height:Enable();self.controls.heightTarget:Enable() end
    -- Locked size: no manual width/height; size links stay available.
    if L.elements[self.selected].sizeLocked then self.controls.width:Disable();self.controls.height:Disable()
    else self.controls.width:Enable();if not autoHeight then self.controls.height:Enable() end end
    self.controls.width:SetAlpha(n.widthTarget and .4 or 1); self.controls.height:SetAlpha(n.heightTarget and .4 or 1)
    self.controls.x:SetValue(rect.x); self.controls.y:SetValue(rect.y)
    local isAnchor=L.elements[self.selected].anchorPoint==true
    local dynamic=L.elements[self.selected].active~=nil
    local stackMode=self.stackOpen and isAnchor
    local preferences=stackMode or self.preferencesOpen and (isAnchor or dynamic)
    self.preferencesButton:SetShown(isAnchor or dynamic)
    self.preferencesButton:SetLabelText(isAnchor and "Options" or "Preferences")
    self.stackButton:SetShown(isAnchor)
    self.layoutButton:SetSelected(not preferences)
    self.preferencesButton:SetSelected(preferences and not stackMode)
    self.stackButton:SetSelected(stackMode==true)
    for _,key in ipairs({"width","height","x","y","zIndex"}) do
        self.controls[key]:SetShown(not preferences and (key~="zIndex" or not anchor))
        self.controls[key].fieldLabel:SetShown(not preferences and (key~="zIndex" or not anchor))
    end
    self.zHint:SetShown(not preferences and not anchor);self.linkHint:SetShown(not preferences)
    if isAnchor then
        D.Width(self.layoutButton,90);D.Width(self.preferencesButton,90);at(self.preferencesButton,self.inspector,115,40)
    else D.Width(self.layoutButton,136);D.Width(self.preferencesButton,136);at(self.preferencesButton,self.inspector,168,40)end
    for _,key in ipairs({"widthTarget","heightTarget","positionTarget","side","align","gap","offset"}) do
        self.controls[key]:SetShown(not preferences); self.controls[key].fieldLabel:SetShown(not preferences)
    end
    for _,button in ipairs(self.targetButtons) do button:SetShown(not preferences) end
    if autoHeight then self.targetButtons[2]:Disable() else self.targetButtons[2]:Enable() end
    self.preferencesPanel:SetShown(preferences)
    at(self.preferencesPanel,self.preferencesPanel:GetParent(),16,0); self.inspectorGrid:SetShown(not preferences)
    self.anchorName:SetShown(isAnchor and not stackMode); self.anchorName.fieldLabel:SetShown(isAnchor and not stackMode); self.renameAnchor:SetShown(isAnchor and not stackMode)
    self.deleteAnchor:SetShown(isAnchor and not stackMode)
    if isAnchor and preferences and not stackMode then
        if self.anchorName.anchorID~=self.selected or not self.anchorName.focused then self.anchorName:SetText(n.label) end
        self.anchorName.anchorID=self.selected
    else self.anchorName.anchorID=nil end
    for key,toggle in pairs(self.collapseControls) do
        toggle:SetValue(n[key]==true); toggle:SetShown(dynamic and not stackMode and not n.templateId); toggle.caption:SetShown(dynamic and not stackMode and not n.templateId)
    end
    self.stackPanel:SetShown(stackMode)
    local stack=M.NormalizeStack(n.stack);self.stackEnabled:SetValue(n.stack~=nil)
    for key,control in pairs(self.stackControls)do
        control:SetValue(stack[key]);if n.stack and (key~="descending"or stack.sort~="APPEARANCE")then control:Enable()else control:Disable()end
    end
    self.preferencesHint:SetShown(not stackMode)
    self.preferencesHint:SetText(isAnchor and "Neutral layout anchor. Its ID stays stable when renamed. Use Layout to attach it to any other element. New points have a zero-sized footprint; the editor handle is only a marker."
        or "When inactive, use a zero-sized footprint on the selected axes. At a direction change, children use the former entry edge. Collapse spacing closes positive gaps; negative overlaps stay. Normal sizes remain saved and visible while editing.")
    local a=n.link or {side="BOTTOM",align="CENTER",gap=6,offset=0}
    self.controls.gap.fieldLabel:SetText(a.side=="CENTER" and "Offset Y" or "Gap")
    self.controls.offset.fieldLabel:SetText(a.side=="CENTER" and "Offset X" or "Along-side offset")
    self.controls.align:SetAlpha(a.side=="CENTER" and .4 or 1)
    if a.side=="CENTER" then self.controls.align:Disable() else self.controls.align:Enable() end
    for _,key in ipairs({"side","align","gap","offset"}) do self.controls[key]:SetValue(a[key]) end
    self.linkHint:SetText((n.widthTarget and "Width follows target. " or "")..(n.heightTarget and "Height follows target. " or "")..(n.link and "Dragging changes relative offsets." or "Free position."))
    if n.link and n.link.target==L.CURSOR_TARGET then self.linkHint:SetText("Cursor fixed while editing. Follows your mouse after exit. Drag to adjust offsets.") end
    if n.link and n.link.target==L.NAMEPLATE_TARGET then self.linkHint:SetText("Nameplate preview uses the screen center. At runtime each entry follows its own nameplate.") end
    if L.constrained[self.selected] then
        self.linkHint:SetText(L.constrained[self.selected].oversized and "Larger than screen: centered. Size links retained."
            or "Screen edge reached. Saved anchor links retained.")
    end
    if warnings[self.selected] then self:Message(warnings[self.selected]) end
    D.Height(self.inspector,self.inspectorHeight); UI:FitWindow(self.inspector,320,self.inspectorHeight,ns.Settings:Get("scale"))
    UI:FitWindow(self.toolbar,1180,70,ns.Settings:Get("scale"))
    UI:FitWindow(self.confirm,420,130,ns.Settings:Get("scale"))
    UI:FitWindow(self.deleteDialog,520,350,ns.Settings:Get("scale"))
    self:PositionInspector(rects)
end
function Editor:Build()
    if self.root then return end
    local root=CreateFrame("Frame","BVAddonSuiteLayoutEditor",UIParent); root:Hide(); root:SetAllPoints(UIParent)
    root:SetFrameStrata("FULLSCREEN_DIALOG"); root:EnableMouse(true); root:EnableKeyboard(true)
    root:SetScript("OnKeyDown",function(self,key)
        self:SetPropagateKeyboardInput(key~="ESCAPE")
        if key=="ESCAPE" then
            if Editor.cleanupTarget then Editor:CancelCleanup()
            elseif Editor.deleteTarget then Editor:CancelAnchorDelete()
            elseif UI.dropdown and UI.dropdown:IsShown() then UI:CloseDropdown()
            elseif Editor.picking then Editor.picking=nil; Editor:Message(""); Editor:Refresh()
            else Editor:RequestClose() end
        end
    end)
    root:SetScript("OnMouseUp",function() self:EndDrag() end)
    root:SetScript("OnHide",function() self:StopDrag(); UI:CloseDropdown() end)
    UI:ManageWindow(root)
    local dim=root:CreateTexture(nil,"BACKGROUND"); dim:SetAllPoints(root); dim:SetColorTexture(.02,.02,.025,.28)
    self.dim=dim
    self.root=root; self.grid={}
    self.guides=UI:SnapGuides(root); self.guides:SetFrameLevel(root:GetFrameLevel()+7)
    -- Geometry redraws on editor entry / display events, never while idle in gameplay.
    function self:Grid()
        for _,line in ipairs(self.grid) do line:Hide() end
        local count=0
        for axis=1,2 do
            local length=axis==1 and UIParent:GetWidth() or UIParent:GetHeight()
            for pos=-math.floor(length/2/self.gridSize)*self.gridSize,length/2,self.gridSize do
                count=count+1; local line=self.grid[count]
                if not line then line=root:CreateTexture(nil,"BACKGROUND"); self.grid[count]=line end
                line:ClearAllPoints(); line:SetColorTexture(.4,.8,.65,pos==0 and .32 or .10)
                if axis==1 then line:SetSize(1,UIParent:GetHeight()); line:SetPoint("CENTER",root,"CENTER",pos,0)
                else line:SetSize(UIParent:GetWidth(),1); line:SetPoint("CENTER",root,"CENTER",0,pos) end
                line:SetShown(self.overlays)
            end
        end
        self.gridCount=count
    end
    local toolbar=UI:Panel(root,1180,70,"canvas"); D.Point(toolbar,"TOP",0,-16); self.toolbar=toolbar
    toolbar:EnableMouse(true); toolbar:SetFrameLevel(root:GetFrameLevel()+30)
    toolbar:SetMovable(true);toolbar:SetClampedToScreen(true)
    local drag=CreateFrame("Button",nil,toolbar);D.Size(drag,196,32);at(drag,toolbar,10,5)
    drag:EnableMouse(true);drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart",function()toolbar:StartMoving()end)
    drag:SetScript("OnDragStop",function()
        toolbar:StopMovingOrSizing();local x,y=toolbar:GetCenter();local px,py=UIParent:GetCenter()
        local scale=toolbar:GetScale();ns.Settings:Profile().layoutToolbar={x=x*scale-px,y=y*scale-py}
    end)
    UI:AttachTooltip(drag,"Move toolbar","Drag this heading. Right-click to reset its position.")
    drag:RegisterForClicks("RightButtonUp")
    drag:SetScript("OnClick",function()ns.Settings:Profile().layoutToolbar=nil;toolbar:ClearAllPoints();D.Point(toolbar,"TOP",root,"TOP",0,-16)end)
    local saved=ns.Settings:Profile().layoutToolbar
    if saved then toolbar:ClearAllPoints();toolbar:SetPoint("CENTER",UIParent,"CENTER",saved.x/toolbar:GetScale(),saved.y/toolbar:GetScale())end
    self.brand=at(UI:Logo(toolbar,24),toolbar,16,10)
    self.brandTitle=at(UI:Label(toolbar,"LAYOUT EDITOR",13,"accent",true),toolbar,58,15)
    self.elementSelect=at(UI:Dropdown(toolbar,220,{},function(id) self:Select(id) end),toolbar,216,8)
    self.newAnchor=at(UI:Button(toolbar,"New anchor",190,function()
        if self.suspended or not self:CommitAnchorName() then return end
        self:StopDrag()
        local ok,id=pcall(ns.DisplayAnchors.NewAnchor,ns.DisplayAnchors)
        if not ok then self:Message(tostring(id)); return end
        L.elements[id].preview(true); self:Select(id)
    end),toolbar,16,38)
    at(UI:Label(toolbar,"Focus",12,"muted"),toolbar,216,46)
    self.focusToggle=at(UI:Switch(toolbar,false,function(v) self:SetFocus(v) end),toolbar,268,43)
    UI:AttachTooltip(self.focusToggle,"Focus selected element","Only the selected element can be moved or resized. Change focus with the element list; Pick can still choose any permitted anchor target.")
    self.cleanupButton=at(UI:Button(toolbar,"Clean up...",116,function() self:RequestCleanup() end),toolbar,320,38)
    at(UI:Label(toolbar,"Grid snap",12,"muted"),toolbar,448,16)
    self.snapToggle=at(UI:Switch(toolbar,true,function(v) self:StopDrag(); self.snap=v; ns.Settings:Set("snapToGrid",v) end),toolbar,515,13)
    UI:AttachTooltip(self.snapToggle,"Snap to grid","Snap to the visible grid. Hold Shift while dragging for free movement.")
    at(UI:Label(toolbar,"Grid",12,"muted"),toolbar,559,16)
    local sizes={}; for _,size in ipairs({8,16,24,32,48,64}) do sizes[#sizes+1]={value=size,label=tostring(size)} end
    self.gridSelect=at(UI:Dropdown(toolbar,76,sizes,function(v) self:SetGridSize(v) end),toolbar,592,8)
    UI:AttachTooltip(self.gridSelect,"Grid size","Spacing in UI units. Movement snaps edges and centers; free resizing snaps the dragged edge. Saved per profile.")
    at(UI:Label(toolbar,"Element snap",12,"muted"),toolbar,448,46)
    self.elementSnapToggle=at(UI:Switch(toolbar,true,function(v) self:StopDrag(); self.elementSnap=v; ns.Settings:Set("snapToElements",v) end),toolbar,541,43)
    UI:AttachTooltip(self.elementSnapToggle,"Align to elements","Snap edges and centers to other BV elements. Captures within 6 screen pixels, releases beyond 10. Takes priority over grid snapping; does not create anchors.")
    self.viewSelect=at(UI:Dropdown(toolbar,174,{{value="normal",label="Normal anchors"},{value="nameplates",label="Nameplates"}},function(v)self:SetView(v)end),toolbar,592,38)
    self.viewSelect:SetValue(self.viewMode or "normal")
    at(UI:Label(toolbar,"Inspector gap (px)",11,"muted"),toolbar,790,46)
    self.inspectorGap=at(UI:NumberInput(toolbar,90,20,400,function(v)ns.Settings:Set("inspectorGap",v);self.inspectorSelection=nil;self:Refresh()end),toolbar,930,38)
    self.inspectorGap:SetValue(ns.Settings:Get("inspectorGap"))
    at(UI:Label(toolbar,"Overlays",12,"muted"),toolbar,685,16)
    self.overlayToggle=at(UI:Switch(toolbar,true,function(v) self:SetOverlays(v) end),toolbar,752,13)
    at(UI:Label(toolbar,"Show hidden",12,"muted"),toolbar,1034,46)
    self.hiddenToggle=at(UI:Switch(toolbar,false,function(v) self:SetShowHidden(v) end),toolbar,1124,43)
    UI:AttachTooltip(self.hiddenToggle,"Show hidden elements","Temporarily show elements whose node has Hide in Layout Editor enabled. Resets when the editor closes.")
    UI:AttachTooltip(self.overlayToggle,"Editor overlays","Temporarily hide the grid, shading and labels to see the elements underneath. Outlines and arrows remain; arrows point to the anchor target.")
    at(UI:Button(toolbar,"Discard",94,function() self:Close(false) end),toolbar,836,8)
    at(UI:Button(toolbar,"Save & exit",124,function() self:Close(true) end,true),toolbar,940,8)
    at(UI:Button(toolbar,"Exit",86,function() self:RequestClose() end),toolbar,1074,8)
    -- Compact toolbar (0.8.72): 26-unit controls in two rows.
    for _,child in ipairs({toolbar:GetChildren()}) do
        local kind=child.GetObjectType and child:GetObjectType()
        if (kind=="Button" and not child.isSwitch and child~=drag) or kind=="EditBox" then D.Height(child,26) end
    end
    -- Compact inspector (0.8.72): tabs under a slim title, then SettingsGrid rows
    -- (label left, control right); explanations are tooltips.
    local panel=UI:Panel(root,320,INSPECTOR_HEIGHT,"canvas"); self.inspector=panel
    D.Point(panel,"TOPRIGHT",UIParent,"TOPRIGHT",-24,-116); panel:EnableMouse(true)
    panel:SetFrameLevel(root:GetFrameLevel()+30); panel:SetMovable(true); panel:SetClampedToScreen(true)
    local handle=CreateFrame("Button",nil,panel); D.Size(handle,300,36); D.Point(handle,"TOPLEFT",10,-2)
    self.titleHandle=handle;UI:AttachTooltip(handle,"Layout element","")
    handle:EnableMouse(true); handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart",function() panel:StartMoving() end)
    handle:SetScript("OnDragStop",function() panel:StopMovingOrSizing() end)
    panel:SetScript("OnHide",function() panel:StopMovingOrSizing() end)
    self.title=at(UI:Label(panel,"",15,"text",true),panel,16,11); D.Size(self.title,288,22);self.title:SetWordWrap(false)
    at(UI:Rule(panel,288),panel,16,36)
    local content=CreateFrame("Frame",nil,panel);D.Point(content,"TOPLEFT",0,-INSPECTOR_TOP);D.Size(content,320,INSPECTOR_HEIGHT-INSPECTOR_TOP)
    self.inspectorContent=content
    local grid=UI:SettingsGrid(content); self.inspectorGrid=grid
    local function row(key,label,control,help,width)
        self.controls[key]=grid:Row(label,control,{help=help,width=width})
        self.controls[key].fieldLabel=self.controls[key].bvGridRow.label
        return self.controls[key]
    end
    local function number(key,label,low,high,callback,help)
        return row(key,label,UI:NumberInput(grid,90,low,high,callback),help,90)
    end
    grid:Section("geometry","Size & position")
    number("width","Width",0,5000,function(v)
        if L:Get(self.selected).widthTarget then self:Message("Unlink width before resizing."); self:Refresh(); return end
        self:Change({width=v})
    end)
    number("height","Height",0,2000,function(v)
        if L:Get(self.selected).heightTarget then self:Message("Unlink height before resizing."); self:Refresh(); return end
        self:Change({height=v})
    end)
    number("x","Position X",-10000,10000,function(v) local r=L:Resolve(); L:Move(self.selected,v,r[self.selected].y) end)
    number("y","Position Y",-10000,10000,function(v) local r=L:Resolve(); L:Move(self.selected,r[self.selected].x,v) end)
    grid:Section("links","Links")
    self.targetButtons={}
    for index,axis in ipairs({"width","height","position"}) do
        local a=axis
        local label=axis=="position" and "Anchor to" or "Match "..axis
        -- Dropdown and Pick share one row; the dropdown stays the control.
        local host=UI:Panel(grid,170,26,"surface"); UI:HideSurface(host)
        local dropdown=at(UI:Dropdown(host,140,{},function(id) self:ChooseTarget(a,id) end),host,0,0); D.Height(dropdown,26)
        local pick=UI:IconButton(host,"fit",function() self:StopDrag(); self.picking=a; self:Message("Click the target element. Escape cancels."); self:Refresh() end)
        self.targetButtons[index]=at(pick,host,144,0); D.Size(pick,26,26)
        UI:AttachTooltip(pick,"Pick target","Click the target element on screen. Escape cancels.")
        grid:Row(label,host,{width=170,fixedHeight=true,help=axis=="position" and "Attach this element to another one. Pick: click the target on screen." or "Follow the "..axis.." of another element. Pick: click the target on screen."})
        self.controls[axis.."Target"]=dropdown; dropdown.fieldLabel=host.bvGridRow.label; dropdown.bvHost=host
    end
    local function link(key,value)
        local a=L:Get(self.selected).link
        if not a then self:Message("Choose an anchor target first."); self:Refresh(); return end
        if key=="side" and (value=="CENTER" or a.side=="CENTER") and a.side~=value then a.gap=0; a.offset=0 end
        a[key]=value; self:Change({link=a})
    end
    row("side","Side",UI:Dropdown(grid,120,opts({"TOP","BOTTOM","LEFT","RIGHT","CENTER"}),function(v) link("side",v) end),"Edge of the target this element attaches to.",120)
    row("align","Alignment",UI:Dropdown(grid,120,opts({"START","CENTER","END"}),function(v) link("align",v) end),"Alignment along the chosen side.",120)
    number("gap","Gap",-10000,10000,function(v) link("gap",v) end,"Distance from the target's edge.")
    number("offset","Along-side offset",-10000,10000,function(v) link("offset",v) end,"Shift along the chosen side.")
    self.linkHint=grid:Block(UI:Label(grid,"",11,"muted"),30)
    grid:Section("order","Draw order")
    number("zIndex","Z index",-1000,1000,function(v)self:Change({zIndex=math.floor(v)})end)
    UI:AttachTooltip(self.controls.zIndex,"Draw order","Higher values appear in front. A template root orders the entire stack; child slots order only inside it. Equal values use stable layout IDs. Position anchors do not change.")
    self.zHint=grid:Block(UI:Label(grid,"",11,"muted"),16)
    self.message=grid:Block(UI:Label(grid,"",12,"accent"),30)
    UI:Place(grid,content,16,0); self.inspectorGridHeight=grid:Arrange(288)
    self.preferencesPanel=at(UI:Panel(content,288,306,"surface"),content,16,0); UI:HideSurface(self.preferencesPanel)
    local gp=self.preferencesPanel
    self.anchorName=UI:Field(gp,"Anchor name",UI:Input(gp,288,function() self:CommitAnchorName() end),0,0)
    self.anchorName:SetMaxLetters(80)
    self.anchorName:SetScript("OnEditFocusGained",function(input) input.focused=true end)
    self.anchorName:SetScript("OnEditFocusLost",function(input) input.focused=false; self:CommitAnchorName() end)
    self.renameAnchor=at(UI:Button(gp,"Save name",150,function() self:CommitAnchorName(); self.anchorName:ClearFocus() end),gp,0,60)
    self.deleteAnchor=at(UI:Button(gp,"Delete anchor",150,function() self:RequestAnchorDelete() end),gp,0,104)
    UI:AttachTooltip(self.deleteAnchor,"Delete anchor","Checks position, size and saved graph references. Only unused neutral anchors can be deleted; Save & exit commits the change.")
    self.collapseControls={}
    for index,entry in ipairs({{"collapseWidth","Inactive width = 0"},{"collapseHeight","Inactive height = 0"},{"collapseGap","Collapse chain spacing"}}) do
        local key=entry[1]; local y=(index-1)*36
        local toggle=at(UI:Switch(gp,false,function(value) self:Change({[key]=value}) end),gp,0,y)
        toggle.caption=at(UI:Label(gp,entry[2],12,"text"),gp,52,y+3); self.collapseControls[key]=toggle
    end
    self.preferencesHint=at(UI:Label(gp,"",11,"muted"),gp,0,130); D.Size(self.preferencesHint,288,120)
    gp:Hide()
    self.layoutButton=at(UI:Button(panel,"Layout",136,function()
        if not self:CommitAnchorName() then return end
        self.preferencesOpen=false;self.stackOpen=false; self:Refresh()
    end,"tab"),panel,16,40)
    self.preferencesButton=at(UI:Button(panel,"Preferences",136,function() self.preferencesOpen=true;self.stackOpen=false; self:Refresh() end,"tab"),panel,168,40)
    self.stackButton=at(UI:Button(panel,"Stack",90,function()if not self:CommitAnchorName()then return end;self.stackOpen=true;self.preferencesOpen=false;self:Refresh()end,"tab"),panel,214,40)
    for _,b in ipairs({self.layoutButton,self.preferencesButton,self.stackButton}) do D.Height(b,28) end
    self.stackPanel=at(UI:Panel(gp,288,306,"surface"),gp,0,0);UI:HideSurface(self.stackPanel)
    local sp=self.stackPanel;self.stackControls={}
    self.stackEnabled=at(UI:Switch(sp,false,function(v)self:ChangeStack("enabled",v)end),sp,0,0)
    at(UI:Label(sp,"Stack layout",12,"text"),sp,52,3)
    local function stackField(key,label,control,x,y)self.stackControls[key]=UI:Field(sp,label,control,x,y)end
    stackField("direction","Direction",UI:Dropdown(sp,136,{{value="UP",label="Up"},{value="DOWN",label="Down"},{value="LEFT",label="Left"},{value="RIGHT",label="Right"}},function(v)self:ChangeStack("direction",v)end),0,36)
    stackField("align","Alignment",UI:Dropdown(sp,136,{{value="START",label="Start"},{value="CENTER",label="Center"},{value="END",label="End"}},function(v)self:ChangeStack("align",v)end),152,36)
    stackField("gap","Entry gap",UI:NumberInput(sp,136,0,1000,function(v)self:ChangeStack("gap",v)end),0,90)
    stackField("maxEntries","Max entries",UI:NumberInput(sp,136,1,40,function(v)self:ChangeStack("maxEntries",v)end),152,90)
    stackField("sort","Sort by",UI:Dropdown(sp,288,{{value="APPEARANCE",label="Appearance"},{value="NUMERIC",label="Numeric"},{value="ALPHABETICAL",label="Alphabetical"}},function(v)self:ChangeStack("sort",v)end),0,144)
    for _,key in ipairs({"direction","align","gap","maxEntries","sort"}) do D.Height(self.stackControls[key],26) end
    self.stackControls.descending=at(UI:Switch(sp,false,function(v)self:ChangeStack("descending",v)end),sp,0,200)
    at(UI:Label(sp,"Descending",12,"text"),sp,52,203)
    UI:AttachTooltip(self.stackControls.sort,"Stack order","Secret or unusable sort values retain their appearance order after readable values.")
    local hint=at(UI:Label(sp,"For attached Display Stack templates only. Missing media keeps its layout slot.",11,"muted"),sp,0,232);D.Size(hint,288,40)
    self.stackPanel:Hide()
    self.inspectorHeight=INSPECTOR_TOP+math.max(self.inspectorGridHeight,306)+12
    D.Height(panel,self.inspectorHeight); D.Height(content,self.inspectorHeight-INSPECTOR_TOP)
    local confirm=UI:Panel(root,420,130,"raised"); confirm:SetPoint("CENTER"); confirm:SetFrameLevel(root:GetFrameLevel()+60); confirm:EnableMouse(true); confirm:Hide()
    self.confirm=confirm
    at(UI:Label(confirm,"Keep your layout changes?",18,"text",true),confirm,18,18)
    at(UI:Button(confirm,"Keep editing",116,function() confirm:Hide() end),confirm,18,76)
    at(UI:Button(confirm,"Discard",116,function() self:Close(false) end),confirm,150,76)
    at(UI:Button(confirm,"Save & exit",116,function() self:Close(true) end,true),confirm,282,76)
    local dialog=UI:Panel(root,520,350,"raised"); dialog:SetPoint("CENTER"); dialog:SetFrameLevel(root:GetFrameLevel()+70); dialog:EnableMouse(true); dialog:Hide()
    self.deleteDialog=dialog
    self.deleteTitle=at(UI:Label(dialog,"",18,"text",true),dialog,18,16); D.Size(self.deleteTitle,484,26)
    self.deleteInfo=at(UI:Label(dialog,"",12,"muted"),dialog,18,50); D.Size(self.deleteInfo,484,48)
    self.deleteList=at(UI:Label(dialog,"",12,"text"),dialog,18,104); D.Size(self.deleteList,484,138)
    self.deletePrev=at(UI:Button(dialog,"Previous",100,function() self.deletePage=self.deletePage-1; self:RefreshAnchorDelete() end),dialog,18,246)
    self.deletePageLabel=at(UI:Label(dialog,"",11,"muted"),dialog,134,255); D.Size(self.deletePageLabel,244,20)
    self.deleteNext=at(UI:Button(dialog,"Next",100,function() self.deletePage=self.deletePage+1; self:RefreshAnchorDelete() end),dialog,402,246)
    at(UI:Button(dialog,"Cancel",140,function() self:CancelAnchorDelete() end),dialog,18,298)
    self.deleteAccept=at(UI:Button(dialog,"Delete anchor",160,function() self:ConfirmAnchorDelete() end),dialog,342,298)
    self:BuildCleanup()
end
-- World-space movers, snap distances and saved layout coordinates intentionally
-- remain in native UIParent units; only the editor controls use design metrics.
function Editor:EnsureMovers()
    for id,mover in pairs(self.movers) do if not L.elements[id] then mover:Hide() end end
    for _,id in ipairs(L.order) do
        if not self.movers[id] then
            local key=id
            local mover=UI:Panel(self.root,100,24,"canvas"); mover.fill:SetAlpha(.92)
            mover:SetFrameLevel(self.root:GetFrameLevel()+5); mover:EnableMouse(true); mover:RegisterForDrag("LeftButton")
            mover.title=UI:Label(mover,"",12,"accent",true); mover.title:SetPoint("CENTER")
            mover:SetScript("OnMouseDown",function(_,button) self:Press(key,button) end)
            mover:SetScript("OnDragStart",function()
                if self.press and self.press.id==key then self:BeginDrag(key,false) end
            end)
            mover:SetScript("OnDragStop",function() self:EndDrag() end)
            mover:SetScript("OnMouseUp",function() self:EndDrag() end)
            local grip=UI:ResizeGrip(mover); grip:SetFrameLevel(mover:GetFrameLevel()+2)
            mover.grip=grip
            UI:AttachTooltip(grip,"Resize","Drag the diagonal handle to resize. Drag the element itself to move it.")
            grip:SetScript("OnMouseDown",function(_,button) if button=="LeftButton" then self:BeginDrag(key,true) end end)
            grip:SetScript("OnMouseUp",function() self:EndDrag() end)
            self.movers[key]=mover
        end
        self.movers[id]:Show()
    end
end
function Editor:Open(id,returnTo)
    L:Store() -- Restore persistent anchors before deciding whether the editor is empty.
    if InCombatLockdown() then ns:Print("Open the Layout Editor after combat."); return end
    if self.active then if id then self:Select(id) end; return end
    self.returnTo=returnTo
    self:Build()
    if ns.Config.window then ns.Config.window:Hide() end
    ns.DisplayAnchors:BeginPreview()
    L:Begin()
    if #L.order==0 then ns.DisplayAnchors:NewAnchor() end -- Draft-only starting handle; Discard removes it.
    self:CancelCleanup(); self.focus=false; self.focusToggle:SetValue(false)
    self.active=true; self.suspended=false; self.preferencesOpen=false;self.stackOpen=false; self.selected=id or L.order[1]
    self.gridSize=ns.Settings:Get("gridSize"); self.snap=ns.Settings:Get("snapToGrid")
    self.elementSnap=ns.Settings:Get("snapToElements"); self.elementSnapToggle:SetValue(self.elementSnap)
    self.gridSelect:SetValue(self.gridSize); self.snapToggle:SetValue(self.snap)
    self.showHidden=false; self.hiddenToggle:SetValue(false)
    self.overlays=true; self:EnsureMovers(); self:Grid(); self:SetOverlays(true)
    self.root:Show(); self.confirm:Hide(); self:CancelAnchorDelete(); self:Message(""); self:Refresh()
    ns.Events:Subscribe(self,"PLAYER_REGEN_DISABLED",function()
        self:StopDrag(); self:CancelCleanup(); self:CancelAnchorDelete(); self.picking=nil; self.focus=false; self.focusToggle:SetValue(false); self.suspended=true; UI:CloseDropdown(); self.root:Hide()
        L:FreezeCursor(false)
        for _,key in ipairs(L.order) do L.elements[key].preview(false) end
        L:Refresh(true)
    end)
    ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function()
        self.suspended=false
        L:FreezeCursor(true)
        for _,key in ipairs(L.order) do L.elements[key].preview(not self.inspectHidden and self:InView(key),self.overlays) end
        if not self.inspectHidden then self.root:Show()end; L:Refresh(true)
    end)
    for _,event in ipairs({"UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
        ns.Events:Subscribe(self,event,function() self:StopDrag(); if not self.suspended then L:FreezeCursor(true) end; self:Grid(); L:Refresh(true) end)
    end
end
function Editor:RequestClose()
    self:CancelCleanup(); self:CancelAnchorDelete()
    self:StopDrag()
    if self.suspended then ns:Print("Finish layout editing after combat."); return end
    if L.dirty then self.confirm:Show() else self:Close(false) end
end
function Editor:Close(save)
    if not self.active or self.suspended then return end
    if save and not self:CommitAnchorName() then return end
    if self.anchorName then self.anchorName.anchorID=nil; self.anchorName:ClearFocus() end
    self:StopDrag(); self:CancelCleanup(); self:CancelAnchorDelete(); self.focus=false; self.focusToggle:SetValue(false); self.active=false; self.picking=nil; ns.Events:Release(self)
    UI:CloseDropdown(); self.root:Hide(); self.confirm:Hide(); L:Finish(save)
    for _,id in ipairs(L.order) do L.elements[id].preview(false) end
    ns.DisplayAnchors.previewItems=nil
    -- Consume before invoking: a later session must never inherit this caller.
    local returnTo=self.returnTo; self.returnTo=nil
    if returnTo then
        local ok,handled=ns:Call("layout/return",returnTo)
        if ok and handled~=false then return end
    end
    ns.Config:Build(); ns.Config.window:Show()
end

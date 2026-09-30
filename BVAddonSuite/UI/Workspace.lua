local _,ns=...
local UI,Theme=ns.UI,ns.Theme
local D=ns.DesignSystem.Metrics

function UI:Place(widget,parent,x,y)
    widget:ClearAllPoints(); D.Point(widget,"TOPLEFT",parent,"TOPLEFT",x,-y); return widget
end
-- Layout helpers (in-game round 4): measured content and button rows instead
-- of hand-placed coordinates.
-- Lowest bottom edge (design units) of the shown children and regions of
-- parent that are anchored at its top left.
function UI:ContentBottom(parent)
    local bottom=0
    local function visit(region)
        if not region.IsShown or not region:IsShown() or not region.GetPoint then return end
        local ok,point,rel,_,x,y=pcall(region.GetPoint,region,1)
        if not ok or point~="TOPLEFT" or (rel and rel~=parent) or type(y)~="number" then return end
        local h=region.GetHeight and region:GetHeight() or 0
        bottom=math.max(bottom,D.ToDesign(-y+h))
    end
    for _,child in ipairs({parent:GetChildren()}) do visit(child) end
    if parent.GetRegions then for _,region in ipairs({parent:GetRegions()}) do visit(region) end end
    return bottom
end
-- Places buttons left to right at (x,y) with widths fitted to their labels;
-- wraps to a new line at maxWidth. Returns the used height (0 when empty).
function UI:ButtonRow(parent,buttons,x,y,maxWidth,gap)
    gap=gap or 10;if #buttons==0 then return 0 end
    local cx,cy,rowH=x,y,0
    for _,b in ipairs(buttons) do
        local text=b.label and b.label.GetText and b.label:GetText() or ""
        local textWidth=b.label and b.label.GetUnboundedStringWidth and D.ToDesign(b.label:GetUnboundedStringWidth()) or #text*8
        local width=math.max(100,math.floor(textWidth+36))
        if cx>x and cx+width>x+maxWidth then cx=x;cy=cy+rowH+8;rowH=0 end
        D.Width(b,width);b:ClearAllPoints();D.Point(b,"TOPLEFT",parent,"TOPLEFT",cx,-cy)
        local h=D.GetHeight(b);rowH=math.max(rowH,h>0 and h or 34)
        cx=cx+width+gap
    end
    return cy-y+rowH
end
function UI:Rule(parent,width,color)
    local line=self:GetStyle():Rule(parent,color); D.Width(line,width)
    return line
end
function UI:FitWindow(frame,width,height,desired,heightFraction)
    -- Window geometry already contains the native base density. The preference
    -- is the actual root multiplier; clamp only when needed to fit the screen.
    local nativeWidth=frame:GetWidth()>0 and frame:GetWidth() or D.ToNative(width)
    local nativeHeight=frame:GetHeight()>0 and frame:GetHeight() or D.ToNative(height)
    frame:SetScale(math.max(.1,math.min(desired or 1,UIParent:GetWidth()*.94/nativeWidth,UIParent:GetHeight()*.90/nativeHeight)))
end
function UI:NavButton(parent,text,width,callback,tab,icon)
    local b=self:GetStyle():Button(parent,text,width,function() ns:Call("navigation",callback) end,tab and "tab" or "nav")
    D.Height(b,tab and 38 or 34); b.mark=b.selection
    b:SetLabelInsets(tab and 2 or icon and 34 or 12,8,tab and "CENTER" or "LEFT")
    if icon then b.navIcon=self:Icon(b,icon,16,"accent"); D.Point(b.navIcon,"LEFT",10,0) end
    self:AttachTooltip(b,text,"Open this page.")
    return b
end

-- Editor-only position relationship. Route outside the bars so short gaps still
-- have a readable arrow; coordinates use the common UIParent coordinate space.
function UI:AnchorConnector(parent)
    local host=CreateFrame("Frame",nil,parent); host:SetAllPoints(parent); host:EnableMouse(false)
    host.lines={}
    for i=1,5 do
        local line=host:CreateLine(nil,"ARTWORK"); line:SetThickness(1.5); host.lines[i]=line
    end
    host.badge=UI:Panel(host,24,24,"canvas"); host.badge:SetSize(22,22)
    host.badge:EnableMouse(false); host.badge:SetFrameLevel(host:GetFrameLevel()+1)
    host.sideLabel=UI:Label(host.badge,"",13,"accent",true); host.sideLabel:SetPoint("CENTER")
    function host:SetGeometry(source,target,side,selected)
        local points,tip,wingA,wingB
        if side=="TOP" or side=="BOTTOM" then
            local sx,tx=source.x+source.width/2,target.x+target.width/2
            local gutter=math.max(sx,tx)+24
            points={{sx,source.y},{gutter,source.y},{gutter,target.y},{tx,target.y}}
            tip=points[4]; wingA={tx+7,target.y+4}; wingB={tx+7,target.y-4}
        else
            local sy,ty=source.y+source.height/2,target.y+target.height/2
            local gutter=math.max(sy,ty)+24
            points={{source.x,sy},{source.x,gutter},{target.x,gutter},{target.x,ty}}
            tip=points[4]; wingA={target.x-4,ty+7}; wingB={target.x+4,ty+7}
        end
        local segments={{points[1],points[2]},{points[2],points[3]},{points[3],tip},{wingA,tip},{wingB,tip}}
        for i,pair in ipairs(segments) do
            local line=self.lines[i]
            line:SetStartPoint("CENTER",UIParent,pair[1][1],pair[1][2])
            line:SetEndPoint("CENTER",UIParent,pair[2][1],pair[2][2])
            line:SetColorTexture(Theme:Color(selected and "accent" or "muted"))
            line:SetAlpha(selected and 1 or .65)
            line:SetShown(pair[1][1]~=pair[2][1] or pair[1][2]~=pair[2][2])
        end
        -- Half the routed path length, not the straight source/target midpoint.
        local lengths,total={},0
        for i=1,3 do local p,q=points[i],points[i+1]; lengths[i]=math.abs(q[1]-p[1])+math.abs(q[2]-p[2]); total=total+lengths[i] end
        local remaining=total/2; local bx,by=points[1][1],points[1][2]
        for i=1,3 do
            if remaining<=lengths[i] and lengths[i]>0 then
                local t=remaining/lengths[i]; local p,q=points[i],points[i+1]
                bx,by=p[1]+(q[1]-p[1])*t,p[2]+(q[2]-p[2])*t; break
            end
            remaining=remaining-lengths[i]
        end
        self.badge:ClearAllPoints(); self.badge:SetPoint("CENTER",UIParent,"CENTER",bx,by)
        self.badge:SetFrameLevel(self:GetFrameLevel()+1)
        self.sideLabel:SetText(({RIGHT="R",LEFT="L",TOP="T",BOTTOM="B",CENTER="C"})[side] or "?")
        self.sideLabel:SetTextColor(Theme:Color(selected and "accent" or "muted"))
        self:Show()
    end
    host:Hide(); return host
end

function UI:SnapGuides(parent)
    local host=CreateFrame("Frame",nil,parent); host:SetAllPoints(parent); host:EnableMouse(false)
    host.lines={}
    for _,axis in ipairs({"x","y"}) do
        local line=host:CreateLine(nil,"OVERLAY"); line:SetThickness(1.5); line:Hide(); host.lines[axis]=line
    end
    function host:Draw(axis,hit,source,target)
        local line=self.lines[axis]
        if not hit then line:Hide(); return end
        target=target or source
        if axis=="x" then
            line:SetStartPoint("CENTER",UIParent,hit.coordinate,math.min(source.y-source.height/2,target.y-target.height/2)-12)
            line:SetEndPoint("CENTER",UIParent,hit.coordinate,math.max(source.y+source.height/2,target.y+target.height/2)+12)
        else
            line:SetStartPoint("CENTER",UIParent,math.min(source.x-source.width/2,target.x-target.width/2)-12,hit.coordinate)
            line:SetEndPoint("CENTER",UIParent,math.max(source.x+source.width/2,target.x+target.width/2)+12,hit.coordinate)
        end
        line:SetColorTexture(Theme:Color("accent")); line:SetAlpha(hit.kind=="element" and 1 or .45)
        line:Show(); self:Show()
    end
    host:Hide(); return host
end
function UI:ResizeSection(card,width,height)
    D.Size(card,width,height); D.Size(card.title,math.max(1,width-60),24); D.Width(card.rule,width-2)
end
function UI:Section(parent,title,width,height,icon)
    local card=self:Panel(parent,width,height,"panel",6,.66)
    card.icon=self:Icon(card,icon or "grid",16,"accent"); self:Place(card.icon,card,16,15)
    card.title=self:Place(self:Label(card,title,17,"text",true),card,44,10)
    card.title:SetWordWrap(false)
    card.rule=self:Place(self:Rule(card,width-2),card,1,44)
    self:ResizeSection(card,width,height)
    return card
end

-- Contextual navigation owns only presentation. Each item selects an actual
-- section provided by the page; the menu never invents feature actions.
function UI:TreeMenu(parent,definitions,callback)
    local tree=CreateFrame("Frame",nil,parent); D.Size(tree,180,1)
    tree.items={}; tree.pool={}
    tree.branch=self:Rule(tree,1,"edge"); D.Point(tree.branch,"TOPLEFT",9,-8); D.Point(tree.branch,"BOTTOMLEFT",9,8)
    function tree:Arrange(width)
        D.Width(self,width); D.Height(self,math.max(1,#self.definitions*30))
        for index,definition in ipairs(self.definitions) do
            local button=self.items[definition.id]
            UI:Place(button,self,18,(index-1)*30); D.Size(button,math.max(1,width-18),28)
        end
    end
    function tree:SetDefinitions(items)
        self.definitions=items or {}; self.items={}
        for index,definition in ipairs(self.definitions) do
            local button=self.pool[index]
            if not button then
                button=UI:Button(self,"",148,function(control) ns:Call("section",callback,control.sectionID) end,"nav")
                button:SetLabelInsets(8,6,"LEFT"); UI:GetStyle():Font(button.label,12)
                self.pool[index]=button
            end
            button.sectionID=definition.id; button:SetLabelText(definition.label); button:Show()
            self.items[definition.id]=button
        end
        for index=#self.definitions+1,#self.pool do self.pool[index]:Hide() end
        self:Arrange(D.GetWidth(self))
    end
    function tree:SetValue(id) for key,button in pairs(self.items) do button:SetSelected(key==id) end end
    tree:SetDefinitions(definitions)
    return tree
end

function UI:ActionButton(parent,label,icon,width,callback,primary)
    local button=self:Button(parent,label,width,callback,primary)
    button:SetLabelInsets(32,10,"LEFT")
    button.icon=self:Icon(button,icon,16,primary and "bg" or "text"); D.Point(button.icon,"LEFT",10,0)
    return button
end

-- Command menus share the dropdown's input shield, bounded rows and lifecycle.
function UI:TextMenu(parent,label,width,options,callback)
    local button=self:Button(parent,label,width,function(host) UI:OpenDropdown(host) end,"nav")
    button:SetLabelInsets(8,8,"CENTER")
    button.options=options; button.callback=callback; button.menuWidth=246; button.menuRows=16
    function button:SetValue() end -- Commands do not replace the menu heading.
    function button:SetOptions(items) self.options=items end
    button:HookScript("OnHide",function(self) if UI.dropdown and UI.dropdown.owner==self then UI:CloseDropdown() end end)
    return button
end

function UI:InlineEdit(parent,commit)
    local input=self:Input(parent,180); input:SetMaxLetters(80); input:Hide()
    function input:Cancel() self.editing=nil; self:ClearFocus(); self:Hide() end
    function input:Begin(value,width)
        self.editing=true; D.Width(self,width); self:SetText(value or ""); self:Show(); self:SetFocus(); self:HighlightText()
    end
    input:SetScript("OnEnterPressed",function(self)
        if not self.editing then return end
        local text=self:GetText(); self:Cancel(); commit(text)
    end)
    input:SetScript("OnEscapePressed",function(self) self:Cancel() end)
    input:HookScript("OnEditFocusLost",function(self) self:Cancel() end)
    input:HookScript("OnHide",function(self) self:Cancel() end)
    return input
end

-- Reusable rich object selector. Providers return plain presentation data and
-- a cancellable bounded request; pooled bindings never accept stale callbacks.
function UI:ObjectButton(parent,width,callback)
    local button=self:Button(parent,"",width,callback)
    button.preview=button:CreateTexture(nil,"ARTWORK"); D.Size(button.preview,24,24); D.Point(button.preview,"LEFT",6,0)
    button.identity=self:Label(button,"",10,"muted"); D.Point(button.identity,"RIGHT",-8,0); button.identity:SetWordWrap(false)
    function button:StopRequest()
        self.generation=(self.generation or 0)+1
        if self.cancelRequest then self.cancelRequest(); self.cancelRequest=nil end
    end
    function button:PaintObject(row)
        self.objectRow=row
        local identity=row.value and ("["..row.value.."]") or ""
        self.identity:SetText(identity); self.identity:SetShown(row.value~=nil)
        local identityWidth=row.value and D.ToDesign(self.identity:GetUnboundedStringWidth()) or 0
        D.Size(self.identity,math.max(1,identityWidth),20)
        self:SetLabelInsets(row.icon and 38 or 10,identityWidth+14,"LEFT")
        self.preview:SetTexture(row.icon); self.preview:SetShown(row.icon~=nil)
        if row.coords then self.preview:SetTexCoord(unpack(row.coords)) else self.preview:SetTexCoord(0,1,0,1) end
        self:SetLabelText(row.value and (((row.unverified and "Metadata unavailable" or row.name or "Spell")..(row.rank and " - "..row.rank or "")):gsub("|","||")) or row.label or "Select...")
        UI:AttachTooltip(self,row.label,row.origin or "Select an object.")
    end
    button.identity.bvAfterFont=function() if button.objectRow then button:PaintObject(button.objectRow) end end
    function button:SetObject(key,row,request)
        self.objectSpec={key=key,row=row,request=request}
        self:PaintObject(row)
        if not self:IsVisible() then self:StopRequest(); self.objectKey=nil; return end
        if self.objectKey==key then return end
        self:StopRequest(); self.objectKey=key
        if request then
            local generation=self.generation
            self.cancelRequest=request(function(result)
                if self.generation==generation and self.objectKey==key and self:IsVisible() then self:PaintObject(result) end
            end)
        end
    end
    button:HookScript("OnHide",function(self) self:StopRequest(); self.objectKey=nil end)
    button:HookScript("OnShow",function(self) local spec=self.objectSpec; if spec then self:SetObject(spec.key,spec.row,spec.request) end end)
    return button
end

function UI:PointerWithin(frame)
    local foci=GetMouseFoci and GetMouseFoci() or GetMouseFocus and {GetMouseFocus()} or {}
    if issecretvalue and issecretvalue(foci) or canaccesstable and not canaccesstable(foci) then return false end
    -- Only the topmost hit owns the pointer; overlapping windows block canvas.
    local focus=foci[1]
    if issecretvalue and issecretvalue(focus) then return false end
    for _=1,40 do
        if issecretvalue and issecretvalue(focus) then return false end
        if not focus then return false end
        if focus==frame then return true end
        if type(focus.GetParent)~="function" then return false end
        focus=focus:GetParent()
    end
    return false
end
function UI:TextInputFocused()
    local focus=GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if issecretvalue and issecretvalue(focus) then return true end
    return focus~=nil and focus~=false
end
function UI:SetKeyboardPropagation(frame,value)
    if InCombatLockdown and InCombatLockdown() then return false end
    frame:SetPropagateKeyboardInput(value); return true
end
function UI:CategoryGlyph(parent)
    local host=CreateFrame("Frame",nil,parent); D.Size(host,20,20); host.icons={}; host:EnableMouse(true)
    for key,info in pairs(ns.DesignSystem.categories) do
        host.icons[key]=self:Icon(host,info.icon,16,"accent"); D.Point(host.icons[key],"CENTER"); host.icons[key]:Hide()
    end
    function host:SetCategory(key)
        for name,icon in pairs(self.icons) do icon:SetShown(name==key) end
        local info=ns.DesignSystem.categories[key]; UI:AttachTooltip(self,info.label,"Node category: "..info.label)
    end
    return host
end
function UI:ResultList(parent,width,choose)
    local host=CreateFrame("Frame",nil,parent); D.Size(host,width,264); host.buttons={}; host.offset=0
    host.slider=self:GetStyle():Slider(host,12,0,0,1,0)
    host.slider:SetOrientation("VERTICAL"); host.slider:SetValueStep(1)
    host.slider.track:ClearAllPoints(); D.Point(host.slider.track,"TOP"); D.Point(host.slider.track,"BOTTOM"); D.Width(host.slider.track,3)
    D.Size(host.slider:GetThumbTexture(),6,24)
    D.Point(host.slider,"TOPRIGHT",0,0)
    host.empty=self:Place(self:Label(host,"No matching nodes",12,"muted"),host,8,8)
    for i=1,8 do
        local button=self:Place(self:Button(host,"",width-22,function()
            local b=host.buttons[i]; if b.entry then choose(b.index) end
        end,"nav"),host,0,(i-1)*33)
        button:SetLabelInsets(30,8,"LEFT"); button.glyph=self:CategoryGlyph(button); D.Point(button.glyph,"LEFT",5,0)
        button.glyph:EnableMouse(false)
        host.buttons[i]=button
    end
    function host:Paint()
        for i,button in ipairs(self.buttons) do
            local index=self.offset+i; local entry=i<=self.rows and self.entries[index]
            button.entry=entry; button.index=index; button:SetShown(entry~=nil and entry~=false)
            if entry then button:SetLabelText(entry.label); button:SetSelected(index==self.selected); button.glyph:SetCategory(entry.category); UI:AttachTooltip(button,entry.label,"Category: "..ns.DesignSystem.categories[entry.category].label) end
        end
    end
    function host:SetEntries(entries,rows,selected,ensure)
        self.entries=entries; self.rows=rows; self.selected=selected
        self.maximum=math.max(0,#entries-rows); self.offset=math.min(self.offset,self.maximum)
        if ensure then self.offset=math.max(0,math.min(self.maximum,selected<=self.offset and selected-1 or selected>self.offset+rows and selected-rows or self.offset)) end
        D.Height(self,rows*33); D.Height(self.slider,rows*33)
        self.slider:SetMinMaxValues(0,self.maximum); self.slider:SetValue(self.offset); self.slider:SetShown(self.maximum>0)
        self.empty:SetShown(#entries==0); self:Paint()
    end
    host.slider:SetScript("OnValueChanged",function(_,value) host.offset=math.floor(value+.5); if host.entries then host:Paint() end end)
    host:EnableMouseWheel(true); host:SetScript("OnMouseWheel",function(_,delta)
        host.slider:SetValue(math.max(0,math.min(host.maximum or 0,host.offset-delta)))
    end)
    return host
end

-- Transient popup with a transparent screen-wide click shield. The dismissing
-- press/release belongs to the shield, never to an editor control behind it.
-- Parent ownership also closes it on window hide/minimize without idle polling.
function UI:DismissiblePopup(parent,width,height)
    local root=CreateFrame("Frame",nil,parent); root:Hide()
    root:SetAllPoints(UIParent); root:SetFrameStrata("TOOLTIP")
    root:SetFrameLevel(parent:GetFrameLevel()+50); root:EnableMouse(true)
    root:EnableMouseWheel(true); root:SetScript("OnMouseWheel",function() end)
    root:EnableKeyboard(not InCombatLockdown()); UI:SetKeyboardPropagation(root,true)
    root.panel=self:Panel(root,width,height,"raised",6,.9); root.panel:EnableMouse(true)
    -- Movable by its top strip; position remembered per popup key.
    root.dragHandle=CreateFrame("Button",nil,root.panel)
    root.dragHandle:SetPoint("TOPLEFT",root.panel,"TOPLEFT",0,0);root.dragHandle:SetPoint("TOPRIGHT",root.panel,"TOPRIGHT",-D.ToNative(72),0)
    root.dragHandle:SetHeight(D.ToNative(36))
    UI:MakeMovable(root.panel,root.dragHandle,"popup:"..width.."x"..height)
    local function release(button)
        if root.dismissButton and root.dismissButton==button then root:Hide() end
    end
    root:SetScript("OnMouseDown",function(_,button) root.dismissButton=button end)
    root:SetScript("OnMouseUp",function(_,button) release(button) end)
    root:SetScript("OnKeyDown",function(self,key)
        UI:SetKeyboardPropagation(self,key~="ESCAPE")
        if key=="ESCAPE" then self:Hide() end
    end)
    root:SetScript("OnShow",function(self)
        self.dismissButton=nil; self:EnableKeyboard(not InCombatLockdown()); UI:SetKeyboardPropagation(self,true)
        ns.Events:Subscribe(self,"GLOBAL_MOUSE_UP",function(_,button) release(button) end)
        ns.Events:Subscribe(self,"PLAYER_REGEN_DISABLED",function() self:EnableKeyboard(false) end)
        ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function() UI:SetKeyboardPropagation(self,true); self:EnableKeyboard(true) end)
    end)
    root:SetScript("OnHide",function(self)
        ns.Events:Release(self); self.dismissButton=nil; self.panel:Hide()
    end)
    root.panel:HookScript("OnHide",function() if root:IsShown() then root:Hide() end end)
    function root:Open() self:Show(); self.panel:Show() end
    return root
end

-- Data-driven, scrollable hierarchy. Selection, expansion and activation have
-- separate hit targets. The consumer owns persistence and execution semantics.
function UI:LibraryTree(parent,onSelect,onToggle,onRename,onMove,options)
    options=options or {}
    local tree=CreateFrame("Frame",nil,parent); tree.pool={}; tree.items={}; tree.collapsed={}; tree.definitions={}
    tree.viewport=self:Form(tree,220,200,tree); tree.viewport:SetClipsChildren(true)
    self:Place(tree.viewport,tree,0,0)
    function tree:CancelDrag()
        self.dragID=nil; self.dropID=nil; ns.Events:Release(self); self:EnableKeyboard(false)
        if self.dragTimer then self.dragTimer:Cancel(); self.dragTimer=nil end
        if self.ghost then self.ghost:Hide(); self.marker:Hide() end
        for _,row in ipairs(self.pool) do if row.item then row:SetSelected(self.value==row.item.id) end end
        self.suppressRelease=self.dragRow; self.dragRow=nil
        if self.suppressRelease then self.suppressRelease.suppressClick=nil end
    end
    function tree:DragStep()
        if not self.dragID then return end
        local x,y=GetCursorPosition(); local scale=self:GetEffectiveScale()
        self.ghost:ClearAllPoints(); self.ghost:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",x/scale+14,y/scale+8)
        self.destination=nil; self.marker:Hide()
        for _,row in ipairs(self.pool) do if row:IsVisible() and UI:PointerWithin(row) and row.item.id~=self.dragID then
            local item=row.item; local after=y/scale<(row:GetTop()-row:GetHeight()/2)
            self.destination={groupId=item.children and (item.kind=="group" and item.id or nil) or item.parentId,targetId=not item.children and item.id or nil,after=after}
            self.marker:ClearAllPoints(); self.marker:SetParent(row); D.Point(self.marker,after and "BOTTOMLEFT" or "TOPLEFT",0,0); D.Width(self.marker,D.GetWidth(row)); self.marker:Show()
            break
        end end
    end
    function tree:FinishDrag()
        if not self.dragID then return end
        self:DragStep(); local id,target,context=self.dragID,self.destination,self.dragContext
        self:CancelDrag()
        if target and onMove then onMove(id,target.groupId,target.targetId,target.after,context) end
    end
    function tree:Rename(item)
        local row=self.items[item.id]; if not row or item.kind=="folder" or not onRename then return end
        self:CancelDrag(); self.renameItem={kind=item.kind,id=item.id}
        row.rename:Begin(item.label,math.max(60,D.GetWidth(row)-48))
    end
    tree:SetScript("OnKeyDown",function(self,key)
        UI:SetKeyboardPropagation(self,key~="ESCAPE"); if key=="ESCAPE" then self:CancelDrag() end
    end)
    tree:HookScript("OnHide",function(self) self:CancelDrag() end)
    function tree:Arrange(width,height)
        D.Size(self,width,height); D.Size(self.viewport,width-20,height)
        D.Size(self.viewport.slider,12,height); D.Width(self.viewport.content,width-22)
        self:Rebuild()
    end
    function tree:Rebuild()
        self.items={}; local visible={}
        local function visit(items,depth)
            for _,item in ipairs(items) do
                visible[#visible+1]={item=item,depth=depth}
                if item.children and not self.collapsed[item.id] then visit(item.children,depth+1) end
            end
        end
        visit(self.definitions,0)
        local width=D.GetWidth(self.viewport.content)
        for index,entry in ipairs(visible) do
            local row=self.pool[index]
            if not row then
                local function select(control)
                    if control.suppressClick then control.suppressClick=nil; return end
                    local item=control.item
                    if onRename and control.lastClick and control.lastID==item.id and GetTime()-control.lastClick<.3 and item.kind~="folder" then
                        control.lastClick=nil; self:Rename(item)
                    else control.lastClick=GetTime(); control.lastID=item.id; onSelect(item) end
                end
                row=UI:Button(self.viewport.content,"",width,select,"nav")
                if options.onContext and not options.readOnly then
                    row:RegisterForClicks("LeftButtonUp","RightButtonUp")
                    row:SetScript("OnClick",function(control,button)
                        if button=="RightButton" then
                            self:CancelDrag(); control.lastClick=nil
                            if control.item.kind=="graph" or control.item.kind=="group" then options.onContext(control.item,control) end
                        else select(control) end
                    end)
                end
                D.Height(row,28); UI:GetStyle():Font(row.label,12)
                row.rename=UI:InlineEdit(row,function(text)
                    local target=self.renameItem; self.renameItem=nil; if target and onRename then onRename(target,text) end
                end); UI:Place(row.rename,row,20,1); row.rename:SetFrameLevel(row:GetFrameLevel()+5)
                if onMove then row:RegisterForDrag("LeftButton") end
                row:HookScript("OnMouseDown",function() row.suppressClick=nil end)
                row:SetScript("OnDragStart",function()
                    if row.item.kind~="graph" or not onMove or InCombatLockdown() then return end
                    self:CancelDrag(); self.dragID=row.item.id; self.dragRow=row; row.suppressClick=true
                    self.dragContext=options.context and options.context()
                    if not self.ghost then
                        self.ghost=UI:Panel(UIParent,190,34,"raised"); self.ghost:SetFrameStrata("TOOLTIP"); self.ghost:EnableMouse(false); self.ghost:SetAlpha(.78)
                        self.ghost.icon=UI:Icon(self.ghost,"spark",16,"accent"); D.Point(self.ghost.icon,"LEFT",10,0)
                        self.ghost.label=UI:Label(self.ghost,"",12,"text",true); D.Point(self.ghost.label,"LEFT",34,0); D.Size(self.ghost.label,144,24); self.ghost.label:SetWordWrap(false)
                        self.marker=UI:Rule(self,190,"accent"); D.Height(self.marker,2)
                    end
                    self.ghost:SetScale(self:GetEffectiveScale()/UIParent:GetEffectiveScale()); self.ghost.label:SetText(row.item.label); self.ghost:Show()
                    self:DragStep(); self.dragTimer=C_Timer.NewTicker(.025,function() self:DragStep() end)
                    self:EnableKeyboard(true); UI:SetKeyboardPropagation(self,true)
                    ns.Events:Subscribe(self,"GLOBAL_MOUSE_UP",function(_,button) if button=="LeftButton" then self:FinishDrag() end end)
                    ns.Events:Subscribe(self,"PLAYER_REGEN_DISABLED",function() self:CancelDrag() end)
                end)
                row:SetScript("OnDragStop",function() self:FinishDrag() end)
                row:HookScript("OnEnter",function()
                    if self.dragID and row.item.children then self.dropID=row.item.id; row:SetSelected(true); UI:ShowTooltip(row,"Move graph",row.item.label) end
                end)
                row:HookScript("OnLeave",function()
                    if self.dragID then self.dropID=nil; row:SetSelected(self.value==row.item.id) end
                end)
                row.expand=UI:IconButton(row,"chevron",function()
                    self.collapsed[row.item.id]=not self.collapsed[row.item.id]; self:Rebuild()
                end,"nav"); D.Size(row.expand,22,24)
                row.closed=UI:Icon(row.expand,"right",16,"text"); D.Point(row.closed,"CENTER")
                row.toggle=UI:Switch(row,false,function(value) if not InCombatLockdown() then onToggle(row.item,value) end end)
                row.status=UI:Icon(row,"spark",12,"accent")
                row.changed=UI:Label(row,"*",18,"accent",true);D.Point(row.changed,"LEFT",6,0)
                self.pool[index]=row
            end
            local item=entry.item
            if row.item and (row.item.id~=item.id or row.item.kind~=item.kind) then
                row.rename:Cancel(); row.lastClick=nil
                if UI.dropdown and UI.dropdown.owner and UI.dropdown.owner.anchor==row then UI:CloseDropdown() end
            end
            row.item=item; self.items[item.id]=row
            UI:Place(row,self.viewport.content,0,(index-1)*30); D.Width(row,width)
            local indent=entry.depth*14
            row:SetLabelInsets(indent+26,44,"LEFT")
            row:SetLabelText(item.label); row:SetSelected(self.value==item.id); row:Show()
            UI:Place(row.expand,row,indent,2); row.expand:SetShown(item.children~=nil)
            row.expand.icon:SetShown(not self.collapsed[item.id]); row.closed:SetShown(self.collapsed[item.id]==true)
            UI:Place(row.status,row,indent+6,8); row.status:SetShown(not item.children)
            row.status:SetAlpha(item.running and 1 or .25)
            row.status:SetShown(not item.children and not item.changed);row.changed:SetShown(item.changed==true)
            row.changed:ClearAllPoints();D.Point(row.changed,"LEFT",indent+6,0)
            row.toggle:ClearAllPoints(); D.Point(row.toggle,"RIGHT",-4,0)
            row.toggle:SetShown(item.enabled~=nil); row.toggle:SetValue(item.enabled==true)
            if InCombatLockdown() then row.toggle:Disable() else row.toggle:Enable() end
            UI:AttachTooltip(row,item.label,item.children and (#item.children.." visible graphs. Use the arrow to expand or collapse.") or options.readOnly and "Quick-Access: activation only. Open Studio to edit this graph." or (item.changed and "Unsaved changes. " or "").."Select to edit. The switch changes activation, not selection.")
            UI:AttachTooltip(row.toggle,item.label,InCombatLockdown() and "Change activation after combat." or item.toggleHelp or item.children and "Enable or pause this group. Individual switches are preserved." or
                item.blocked and "Enabled, but paused by its group or module." or "Enable or disable this applied graph. Draft changes are not applied.")
        end
        for i=#visible+1,#self.pool do self.pool[i]:Hide() end
        local form=self.viewport; D.Height(form.content,math.max(1,#visible*30))
        form.maximum=math.max(0,#visible*30-D.GetHeight(form))
        form.slider:SetMinMaxValues(0,form.maximum); form.slider:SetValue(math.min(form.slider:GetValue(),form.maximum))
        form.slider:SetShown(form.maximum>0)
    end
    function tree:SetDefinitions(items) self.definitions=items; self:Rebuild() end
    function tree:SetValue(id) self.value=id; for key,row in pairs(self.items) do row:SetSelected(key==id) end end
    tree:Arrange(220,200); return tree
end
-- Same hierarchy and controller as Studio, without authoring gestures.
function UI:QuickAccess(controller)
    local window=self:Window("BVAddonSuiteAuraQuick",280,360,{title="Quick-Access",minWidth=230,minHeight=180,compact=true})
    for i=#UISpecialFrames,1,-1 do if UISpecialFrames[i]=="BVAddonSuiteAuraQuick" then table.remove(UISpecialFrames,i) end end
    local tree
    tree=self:LibraryTree(window.content,function(item)
        if item.children then tree.collapsed[item.id]=not tree.collapsed[item.id]; tree:Rebuild() end
    end,function(item,value)
        if item.kind=="group" then controller:SetGroupEnabled(item.id,value) else controller:SetGraphEnabled(value,item.id) end
    end,nil,nil,{readOnly=true})
    window.tree=tree
    window.openStudio=self:Button(window.content,"Open Studio",120,function() controller:Open() end,"ghost")
    D.Height(window.openStudio,24)
    window.close:SetScript("OnClick",function() controller:SetQuickShown(false) end)
    function window:Arrange()
        local width,height=D.GetWidth(self),D.GetHeight(self)
        UI:Place(tree,self.content,8,8); tree:Arrange(width-16,math.max(50,height-96))
        UI:Place(self.openStudio,self.content,width-132,height-80)
        if not self.loading then local saved=controller:Store().quick; saved.width=width; saved.height=height end
    end
    function window:Refresh()
        self.loading=true; local store=controller:Store(); local data=store.quick
        if self.store~=store or self.savedGeometry~=data then
            D.Size(self,data.width or 280,data.height or 360)
            UI:FitWindow(self,D.GetWidth(self),D.GetHeight(self),ns.Settings:Get("scale"))
            self:ClearAllPoints(); self:SetPoint("CENTER",UIParent,"CENTER",(data.x or 0)/self:GetScale(),(data.y or 0)/self:GetScale())
            self.store=store; self.savedGeometry=data
        end
        UI:FitWindow(self,D.GetWidth(self),D.GetHeight(self),ns.Settings:Get("scale"))
        tree.collapsed=data.collapsed; tree:SetDefinitions(controller:Library(true)); self:Arrange(); self.loading=nil
    end
    window:HookScript("OnSizeChanged",function() window:Arrange() end)
    window.drag:HookScript("OnDragStop",function()
        local x,y=window:GetCenter(); local px,py=UIParent:GetCenter(); local scale=window:GetScale(); local saved=controller:Store().quick
        saved.x=x*scale-px; saved.y=y*scale-py
    end)
    window:HookScript("OnShow",function()
        ns.Events:Subscribe(window,"PLAYER_REGEN_DISABLED",function() tree:Rebuild() end)
        ns.Events:Subscribe(window,"PLAYER_REGEN_ENABLED",function() tree:Rebuild() end)
    end)
    window:HookScript("OnHide",function() ns.Events:Release(window) end)
    window.loading=true; window:Arrange(); window.loading=nil; return window
end
function UI:Field(parent,title,control,x,y)
    local label=self:Place(self:Label(parent,title,12,"muted"),parent,x,y)
    D.Width(label,D.GetWidth(control)); D.Height(label,18); label:SetWordWrap(false)
    self:Place(control,parent,x,y+21)
    control.fieldLabel=label
    parent.fields=parent.fields or {}; parent.fields[#parent.fields+1]={label=label,control=control,x=x,y=y,width=D.GetWidth(control)}
    return control
end
function UI:ColorInput(parent,width,callback)
    -- Swatch button with hex label; opens the shared spectrum picker (0.8.73).
    local host=self:Button(parent,"",width or 160,function(button) UI:OpenColorPicker(button,callback) end)
    host.callback=callback
    host.sample=host:CreateTexture(nil,"ARTWORK"); D.Size(host.sample,20,16); D.Point(host.sample,"LEFT",8,0)
    host:SetLabelInsets(37,6,"LEFT")
    function host:SetValue(hex)
        self.value=hex; self.sample:SetColorTexture(UI:RGBA(hex)); self:SetLabelText("#"..hex:sub(1,6))
    end
    host:HookScript("OnHide",function(self) if UI.colorPopup and UI.colorPopup.owner==self then UI.colorPopup:Hide() end end)
    return host
end
-- Former RGBA-only editor; kept as an entry point for callers.
function UI:OpenColorEditor(owner,callback)
    self:OpenColorPicker(owner,callback)
end

-- Shared presentation only: the optional module supplies catalog, data and actions.
local _,ns=...
local UI,G=ns.UI,ns.GraphModel
local M=ns.DesignSystem.Metrics
local NODE_WIDTH,PORT_SIZE,PORT_START,PORT_STEP=260,18,48,24
local function definition(catalog,node)
    local raw=catalog[node.type]
    if raw then return G.Definition(raw,node) or raw end
    return {label=node.type or "Unknown node",inputs={},outputs={},fields={},help="Unknown node type; inspect its available reference."}
end
local function at(w,p,x,y) w:ClearAllPoints(); M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y); return w end
local function sorted(nodes) local ids={}; for id in pairs(nodes) do ids[#ids+1]=id end; table.sort(ids); return ids end
local function windowSize(window,width,height)
    M.Size(window,width,height)
    UI:FitWindow(window,width,height,ns.Settings:Get("scale"))
end
local function clearDebugCard(card)
    card.debugSelection=nil;card.debugStamp=nil;card.debugText=nil;card.debugOptions=nil;card.debugExpanded=nil;card.debugSignal=nil
    if card.debugPreview then card.debugPreview:SetText("No observation");card.debugLabel:SetText("Graph");card.debugContext:SetOptions({}) end
end

function UI:GraphEditor(controller)
    local E={s=controller,cards={},freeCards={},lines={},selected={},zoom=1,panX=30,panY=35}
    local s=controller
    local w=UI:Window("BVAddonSuiteAuraStudio",1220,760,{title="AuraStudio",minWidth=860,minHeight=510}); E.window=w
    local body=w.content
    local style=UI:GetStyle()
    local function action(fn) return function(...) local ok,why=pcall(fn,...); if not ok then s.message=tostring(why); s:Diagnostic("editor","action",tostring(why)); E:Refresh() end end end
    local function group(width)
        local frame=CreateFrame("Frame",nil,body); M.Size(frame,width,38); frame.designWidth=width; return frame
    end
    E.sidebar=UI:Panel(body,238,660,"canvas",2,1)
    at(UI:Label(E.sidebar,"AURAS",12,"accent",true),E.sidebar,12,14)
    E.new=at(UI:ActionButton(E.sidebar,"New","plus",78,action(function() E:Cancel(); s:New(false); E:LoadView() end)),E.sidebar,12,43)
    E.newGroup=at(UI:IconButton(E.sidebar,"folder",action(function()
        E:Cancel(); local id=s:NewGroup(); E.libraryTarget={kind="group",id=id}; E:Refresh(); E:Details("library")
    end)),E.sidebar,98,43)
    UI:AttachTooltip(E.newGroup,"New group","Create an aura group. Its switch pauses members without changing their own switches.")
    E.library=UI:LibraryTree(E.sidebar,action(function(item)
        if item.kind=="folder" then E.library.collapsed[item.id]=not E.library.collapsed[item.id]; E.library:Rebuild(); return end
        E:Cancel(); E.libraryTarget={kind=item.kind,id=item.id}
        if item.kind=="graph" then s:Select(item.id); E:LoadView() else E:Refresh() end
    end),action(function(item,value)
        if item.kind=="group" then s:SetGroupEnabled(item.id,value) else s:SetGraphEnabled(value,item.id) end
    end),action(function(item,name) s:Rename(item.kind,item.id,name) end),action(function(id,groupId,targetId,after,context) s:MoveGraph(id,groupId,targetId,after,context) end),{
        context=function() return s:Store() end,
        onContext=action(function(item,row)
            local store=s:Store(); local kind,id=item.kind,item.id
            local record=(kind=="group" and store.groups or store.graphs)[id]
            if not record then return end
            local include=record.quickInclude~=true
            local choices={{value="quick",label=(include and "" or "✓ ").."Include in Quick-Access"},{value="export",label="Export "..kind.."..."}}
            if kind=="graph" then
                table.insert(choices,1,{value="copyGraph",label="Copy Graph"})
                if s.graphClipboard then table.insert(choices,2,{value="pasteAbove",label="Paste Above"});table.insert(choices,3,{value="pasteBelow",label="Paste Below"}) end
            else choices[#choices+1]={value="properties",label="Group options..."} end
            choices[#choices+1]={value="deleteGraph",label="Delete "..kind.."...",danger=true}
            UI:ContextMenu(row,choices,action(function(command)
                local current=s:Store()
                if current~=store or (kind=="group" and current.groups or current.graphs)[id]~=record
                    or not w:IsShown() or not row:IsVisible() or row.item.id~=id or row.item.kind~=kind then return end
                if command=="copyGraph" then s:CopyGraph(id)
                elseif command=="pasteAbove" or command=="pasteBelow" then E:Cancel();s:PasteGraph(id,command=="pasteBelow");E:LoadView()
                elseif command=="deleteGraph" then E.libraryTarget={kind=kind,id=id};if kind=="graph" then s:Select(id) end;E:DeleteSelected()
                elseif command=="quick" then s:SetQuickIncluded(kind,id,include)
                elseif command=="export" then
                    E:Cancel(); E.transfer=E.transfer or UI:TransferDialog(w,s); E.transfer:Open("export",kind,id)
                elseif command=="properties" then
                    E:Cancel()
                    if kind=="graph" then s:Select(id); E:LoadView() end
                    E.libraryTarget={kind=kind,id=id}; E:Details("library")
                end
            end))
        end),
    })
    at(E.library,E.sidebar,8,88)
    E.delete=at(UI:IconButton(E.sidebar,"close",action(function() E:DeleteSelected() end)),E.sidebar,140,43)
    UI:AttachTooltip(E.delete,"Delete selected...","Confirm deletion of the selected graph or group.")
    E.libraryFooter=CreateFrame("Frame",nil,E.sidebar);M.Size(E.libraryFooter,238,74)
    M.Point(E.libraryFooter,"BOTTOMLEFT",E.sidebar,"BOTTOMLEFT",0,0)
    E.libraryFooterRule=at(UI:Rule(E.libraryFooter,214),E.libraryFooter,12,0)
    E.libraryHint=at(UI:Label(E.libraryFooter,"Right-click options / drag to reorder",10,"muted"),E.libraryFooter,12,46);M.Size(E.libraryHint,214,18)
    E.quickAccess=at(UI:Switch(E.libraryFooter,false,action(function(value) s:SetQuickShown(value) end)),E.libraryFooter,12,14)
    E.quickAccessLabel=at(UI:Label(E.libraryFooter,"Show Quick-Access",12,"text"),E.libraryFooter,60,14);M.Size(E.quickAccessLabel,166,20)
    UI:AttachTooltip(E.quickAccess,"Show Quick-Access","Show the compact activation window. Right-click a graph or group to choose its inclusion.")
    E.graphTitle=at(UI:Label(body,"",19,"text",true),body,258,10); E.graphTitle:SetWordWrap(false)
    E.graphState=UI:Label(body,"",11,"muted"); E.graphState:SetJustifyH("RIGHT")
    local liveGroup,viewGroup,budgetGroup=group(126),group(350),group(230)
    E.apply=UI:ActionButton(body,"Save","save",96,action(function() s:Apply() end),true)
    UI:AttachTooltip(E.apply,"Save","Save changes and update the active aura.")
    E.resetTests=UI:Button(body,"Return all to Live",164,action(function()s:EndTest();E:Refresh()end),"ghost")
    E.module=at(UI:Switch(liveGroup,false,action(function(value) ns.Modules:SetEnabled("aura_studio",value); if not value then E:Open() end; E:Refresh() end)),liveGroup,0,10)
    at(UI:Label(liveGroup,"Module",11,"muted"),liveGroup,44,12)
    UI:AttachTooltip(E.module,"AuraStudio module","Master switch for all live graphs. Tests remain available when disabled.")
    E.applied=at(UI:Switch(viewGroup,false,action(function(value) E:Cancel(); s.inspectApplied=value; E:Refresh() end)),viewGroup,0,10)
    E.appliedLabel=at(UI:Label(viewGroup,"Applied view",11,"muted"),viewGroup,44,12)
    UI:AttachTooltip(E.applied,"Applied view","Inspect the applied snapshot. Connections and values are read-only until this switch is disabled.")
    E.freeze=at(UI:Switch(viewGroup,false,function(value)
        E.frozen=value
        if value then local trace=s:Trace(); E.frozenTrace=G.Copy(trace); E.frozenGraph=s:Graph().id; E.frozenRevision=s:Graph().revision end
        E:Debug()
    end),viewGroup,172,10)
    at(UI:Label(viewGroup,"Freeze debug",11,"muted"),viewGroup,216,12)
    at(UI:Label(budgetGroup,"Budget",11,"muted"),budgetGroup,0,12)
    E.budget=at(UI:Input(budgetGroup,52,action(function(text)
        local n=tonumber(text); assert(G.Number(n) and n>=.25 and n<=8,"Budget must be 0.25..8 ms")
        s:Store().budget=n; E:Refresh()
    end)),budgetGroup,44,3)
    E.budget:HookScript("OnEditFocusGained",function() E.textFocus=true end)
    E.budget:HookScript("OnEditFocusLost",function() E.textFocus=false end)
    at(UI:Label(budgetGroup,"ms / slice",11,"muted"),budgetGroup,104,12)
    E.reset=at(UI:IconButton(budgetGroup,"undo",function() s:Store().budget=1; E:Refresh() end),budgetGroup,180,3)
    UI:AttachTooltip(E.reset,"Reset budget","Restore the default execution budget of 1 ms per slice.")
    -- Keep stateful controls in the shared debug dialog; commands compose a
    -- Compact menu strip with Save; testing lives on individual source nodes.
    viewGroup:Hide(); budgetGroup:Hide(); liveGroup:Hide()
    E.menus={}
    local commands={
        Graph={{"new","New graph"},{"apply","Save"},{"discard","Discard Changes"},{"import","Import..."},{"export","Export graph..."},{"exportGroup","Export selected group..."},{"delete","Delete selected..."}},
        Edit={{"add","Add node..."},{"undo","Undo"},{"redo","Redo"},{"copy","Copy nodes"},{"paste","Paste nodes"},{"select","Select all nodes"},{"remove","Delete selected nodes"}},
        View={{"fit","Fit graph"},{"applied","Toggle applied snapshot"},{"freeze","Freeze / resume debug"},{"errors","Diagnostics..."}},
        Tools={{"layout","Layout editor"},{"frames","Frame library..."},{"inspectFrames","Inspect frames"},{"debug","Debug & budget..."},{"module","Enable / disable module"},{"settings","Studio settings..."},{"communication","Addon message permissions..."},{"quick","Show Quick-Access"}},
    }
    local function command(id)
        UI:CloseDropdown()
        if s.inspectApplied and ({undo=true,redo=true,paste=true,remove=true})[id] then s.message="Applied view is read-only"; E:Debug(); return end
        if id=="new" then E:Cancel(); s:New(false); E:LoadView()
        elseif id=="apply" then s:Apply()
        elseif id=="discard" then E:Cancel(); s:Discard()
        elseif id=="import" or id=="export" or id=="exportGroup" then
            E:Cancel(); E.transfer=E.transfer or UI:TransferDialog(w,s)
            local target=E.libraryTarget
            E.transfer:Open(id=="import" and "import" or "export",id=="exportGroup" and "group" or "graph",
                id=="exportGroup" and target and target.kind=="group" and target.id or id~="exportGroup" and s:Graph() and s:Graph().id or nil)
        elseif id=="properties" then E:Details("library")
        elseif id=="delete" then E:DeleteSelected()
        elseif id=="add" then E:Search(80,30)
        elseif id=="undo" or id=="redo" then E:Cancel(); s:Undo(id=="redo")
        elseif id=="copy" then E.clipboard=G.Fragment(s:Draft(),E.selected)
        elseif id=="paste" and E.clipboard then E:Cancel(); E.placing={fragment=E.clipboard}; E.ghostLabel:SetText("Paste node group"); E:Track()
        elseif id=="select" then for node in pairs(E:Graph().nodes) do E.selected[node]=true end; E:Render()
        elseif id=="remove" and not s.inspectApplied then s:Edit(function(g) G.Remove(g,E.selected) end); E.selected={}
        elseif id=="fit" then E:Fit()
        elseif id=="applied" then E:Cancel(); s.inspectApplied=not s.inspectApplied; E:Refresh()
        elseif id=="freeze" then E.frozen=not E.frozen; E.freeze:SetValue(E.frozen); if E.frozen then E.frozenTrace=G.Copy(s:Trace()); E.frozenGraph=s:Graph().id; E.frozenRevision=s:Graph().revision end; E:Debug()
        elseif id=="errors" then E:Details("errors")
        elseif id=="layout" then s:OpenLayout()
        elseif id=="frames" then E:Cancel();UI:OpenFrameLibrary()
        elseif id=="inspectFrames" then E:Cancel();UI.frameInspector:Start()
        elseif id=="debug" then E:Details("debug")
        elseif id=="settings" then E:Details("settings")
        elseif id=="communication" then E:Details("communication")
        elseif id=="quick" then s:SetQuickShown(not s:Store().quick.shown)
        elseif id=="module" then ns.Modules:SetEnabled("aura_studio",not s.active); if not s.active then E:Open() end; E:Refresh() end
    end
    for _,name in ipairs({"Graph","Edit","View","Tools"}) do
        local options={}; for _,entry in ipairs(commands[name]) do options[#options+1]={value=entry[1],label=entry[2]} end
        local menu=UI:TextMenu(body,name,name=="Graph" and 72 or 64,options,action(command))
        menu:HookScript("OnMouseDown",function() menu:SetOptions(options) end)
        E.menus[#E.menus+1]=menu
    end
    E.debugGroups={viewGroup,budgetGroup,liveGroup}
    E.canvas=at(UI:Panel(body,1184,595,"canvas"),body,18,86)
    E.canvas:EnableMouse(true); E.canvas:EnableMouseWheel(true); E.canvas:SetClipsChildren(true)
    E.grid=style:CanvasGrid(E.canvas)
    E.legend=style:GraphLegend(body)
    E.content=CreateFrame("Frame",nil,E.canvas); E.content:SetAllPoints(E.canvas)
    E.status=UI:Label(body,"",11,"muted"); M.Point(E.status,"BOTTOMLEFT",18,12); M.Width(E.status,1000)
    E.selectionBox=UI:Panel(E.canvas,1,1,"hover"); E.selectionBox:SetAlpha(.35); E.selectionBox:Hide()
    E.ghost=UI:Panel(E.canvas,NODE_WIDTH,95,"raised"); E.ghost:SetAlpha(.6); E.ghost:Hide()
    E.ghostLabel=at(UI:Label(E.ghost,"",14,"accent",true),E.ghost,12,12)
    E.pendingLine=style:GraphWire(E.canvas,"accent"); E.pendingLine:SetFrameLevel(E.content:GetFrameLevel()+1); E.pendingLine:Hide()
    E.caption=UI:Label(body,"",11,"muted"); M.Point(E.caption,"BOTTOMRIGHT",-36,12); E.caption:SetJustifyH("RIGHT"); M.Width(E.caption,330)
    function E:Layout()
        local width,height=M.GetWidth(w),M.GetHeight(w)
        self.canvasLeft=258
        at(self.sidebar,body,0,0); M.Size(self.sidebar,238,height-44)
        self.library:Arrange(210,math.max(100,M.GetHeight(self.sidebar)-88-74-8))
        M.Width(self.graphTitle,math.max(180,width-self.canvasLeft-250))
        at(self.graphState,body,width-246,5); M.Size(self.graphState,228,18)
        local menuX=self.canvasLeft
        for _,menu in ipairs(self.menus) do at(menu,body,menuX,30); menuX=menuX+M.GetWidth(menu)+2 end
        at(self.apply,body,width-114,30);at(self.resetTests,body,width-286,30);self.resetTests:SetShown(s.test and s.test.nodeOverrides~=nil or false)
        self.canvasTop=70
        at(self.canvas,body,self.canvasLeft,self.canvasTop)
        local canvasWidth=math.max(300,width-self.canvasLeft-18)
        local legendWidth=578
        self.legend:Arrange(legendWidth,false)
        local canvasHeight=math.max(120,height-44-self.canvasTop-38)
        M.Size(self.canvas,canvasWidth,canvasHeight)
        self.legend:ClearAllPoints(); M.Point(self.legend,"BOTTOMRIGHT",body,"BOTTOMRIGHT",-18,6)
        M.Width(self.status,math.max(180,width-legendWidth-54)); self.status:SetWordWrap(false)
        self.caption:Hide()
        if s:Store() and not w.minimized and not w.maximized then
            s:Store().window.width=width; s:Store().window.height=height
        end
        self:Render()
    end
    w:HookScript("OnSizeChanged",function() if E.canvas and not w.minimized then E:Layout() end end)
    w.drag:HookScript("OnDragStop",function()
        local x,y=w:GetCenter(); local px,py=UIParent:GetCenter(); local scale=w:GetScale()
        s:Store().window.x=x*scale-px; s:Store().window.y=y*scale-py
    end)
    function E:Coordinates()
        local x,y=GetCursorPosition(); local scale=self.canvas:GetEffectiveScale()
        return M.ToDesign(x/scale-self.canvas:GetLeft()), M.ToDesign(self.canvas:GetTop()-y/scale)
    end
    function E:Graph() return self.working or (s.inspectApplied and s:Graph().applied) or s:Draft() end
    function E:LoadView()
        if self.wiki then self.wiki:Hide() end
        if self.details then self.details:Hide() end
        self.libraryTarget={kind="graph",id=s:Graph().id}
        self.library.collapsed[s:Graph().groupId or "ungrouped"]=nil
        local v=s:Draft().view or {}; self.zoom=v.zoom or 1; self.panX=v.x or 30; self.panY=v.y or 35
        self.frozen=false; self.frozenTrace=nil; self.freeze:SetValue(false)
        for _,card in pairs(self.cards) do clearDebugCard(card) end
        self.selected={}; self:Refresh()
    end
    function E:SaveView()
        local g=s:Draft(); g.view={zoom=self.zoom,x=self.panX,y=self.panY}
    end
    function E:Fit()
        local graph=self:Graph(); local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
        for id,n in pairs(graph.nodes) do
            minX=math.min(minX,n.x); minY=math.min(minY,n.y)
            maxX=math.max(maxX,n.x+NODE_WIDTH); maxY=math.max(maxY,n.y+(self.cards[id] and M.GetHeight(self.cards[id]) or 240))
        end
        if minX==math.huge then minX,minY,maxX,maxY=0,0,1,1 end
        self.zoom=math.max(.35,math.min(1,(M.GetWidth(self.canvas)-50)/math.max(1,maxX-minX),(M.GetHeight(self.canvas)-50)/math.max(1,maxY-minY)))
        self.panX,self.panY=25-minX*self.zoom,25-minY*self.zoom; self:SaveView(); self:Render()
    end
    function E:Cancel()
        self.space=false
        if self.library then self.library:CancelDrag() end
        if self.pointerTimer then self.pointerTimer:Cancel(); self.pointerTimer=nil end
        self.pointer=nil; self.working=nil; self.wire=nil; self.wirePress=nil; self.placing=nil
        self.ghost:Hide(); self.pendingLine:Hide(); self.selectionBox:Hide()
        if self.search then self.search:Hide() end
        self:Render()
    end
    function E:Track()
        if not self.pointerTimer then self.pointerTimer=C_Timer.NewTicker(.025,function() E:PointerStep() end) end
    end
    function E:PointerStep(final)
        if not w:IsShown() then self:Cancel(); return end
        local x,y=self:Coordinates()
        if self.placing then at(self.ghost,self.canvas,x,y); self.ghost:Show(); return end
        if self.wire then
            local p=self:PortPosition(self.wire.from,self.wire.output,false)
            if p then self.pendingLine:SetEndpoints(p.x,p.y,x,y,1); self.pendingLine:Show() end
            return
        end
        local p=self.pointer; if not p then return end
        if p.spacePan and (UI:TextInputFocused() or (IsKeyDown and not IsKeyDown("SPACE",true))) then self:Cancel(); return end
        if not final and IsMouseButtonDown and not IsMouseButtonDown(p.button) then self:Release(p.button); return end
        local dx,dy=x-p.x,y-p.y
        if math.abs(dx)+math.abs(dy)>3 then p.moved=true end
        if p.kind=="pan" then self.panX=p.panX+dx; self.panY=p.panY+dy; self:Render()
        elseif p.kind=="move" and p.moved then
            for id in pairs(self.selected) do
                local n=self.working.nodes[id]; local old=p.original.nodes[id]
                if n and old then n.x=old.x+dx/self.zoom; n.y=old.y+dy/self.zoom end
            end; self:Render()
        elseif p.kind=="select" and p.moved then
            local left,top=math.min(x,p.x),math.min(y,p.y)
            at(self.selectionBox,self.canvas,left,top); M.Size(self.selectionBox,math.max(1,math.abs(dx)),math.max(1,math.abs(dy))); self.selectionBox:Show()
        end
    end
    function E:Release(button)
        local p=self.pointer; if not p or (button and button~=p.button) then return end
        self:PointerStep(true)
        if not self.pointer then return end
        local x,y=self:Coordinates(); local graph=self.working
        self.pointer=nil; self.working=nil; self.space=false
        if self.pointerTimer then self.pointerTimer:Cancel(); self.pointerTimer=nil end
        self.selectionBox:Hide()
        if p.kind=="move" and p.moved then s:Commit(graph)
        elseif p.kind=="pan" then self:SaveView()
        elseif p.kind=="select" and p.moved then
            if not p.add then self.selected={} end
            for id,card in pairs(self.cards) do if card:IsShown() then
                local n=self:Graph().nodes[id]; local nx,ny=self.panX+n.x*self.zoom,self.panY+n.y*self.zoom
                if nx+NODE_WIDTH*self.zoom>=math.min(x,p.x) and nx<=math.max(x,p.x) and ny+M.GetHeight(card)*self.zoom>=math.min(y,p.y) and ny<=math.max(y,p.y) then self.selected[id]=true end
            end end
        elseif p.kind=="select" and not p.add then self.selected={} end
        self:Render()
    end
    function E:Place(x,y)
        local placing=self.placing; if not placing then return end
        local gx,gy=(x-self.panX)/self.zoom,(y-self.panY)/self.zoom
        self:Cancel()
        s:Edit(function(g)
            if placing.kind then local id=G.Add(g,placing.kind,s.catalog,gx,gy); self.selected={[id]=true}
            else self.selected=G.Paste(g,placing.fragment,s.catalog,gx,gy) end
        end)
    end
    function E:EmptyDown(button)
        local x,y=self:Coordinates()
        if button=="LeftButton" and self.placing then self:Place(x,y); return end
        if button=="LeftButton" and self.wire then
            local wire=self.wire; self:Cancel()
            if wire.original then s:Edit(function(g) local _,i=G.Binding(g,wire.original.to,wire.original.input); if i then table.remove(g.edges,i) end end) end
            return
        end
        self.space=self.space and UI:PointerWithin(self.canvas) and not UI:TextInputFocused() and (not IsKeyDown or IsKeyDown("SPACE",true))
        local kind=(button=="MiddleButton" or (button=="LeftButton" and self.space)) and "pan" or "select"
        if button~="LeftButton" and button~="MiddleButton" then return end
        if kind=="select" and self.lastClick and GetTime()-self.lastClick.time<.3 and math.abs(x-self.lastClick.x)+math.abs(y-self.lastClick.y)<8 then
            self:Cancel(); self.lastClick=nil; self:Search(x,y); return
        end
        self.lastClick=kind=="select" and {time=GetTime(),x=x,y=y} or nil
        self.pointer={kind=kind,button=button,spacePan=button=="LeftButton" and self.space,x=x,y=y,panX=self.panX,panY=self.panY,add=IsShiftKeyDown()}; self:Track()
    end
    E.canvas:SetScript("OnMouseDown",action(function(_,button) E:EmptyDown(button) end))
    E.canvas:SetScript("OnMouseUp",action(function(_,button) E:Release(button) end))
    E.canvas:HookScript("OnLeave",function() if not E.pointer then E.space=false end end)
    E.canvas:SetScript("OnMouseWheel",function(_,delta)
        local x,y=E:Coordinates(); local old=E.zoom
        E.zoom=math.max(.35,math.min(1.6,old*(delta>0 and 1.1 or 1/1.1)))
        E.panX=x-(x-E.panX)*E.zoom/old; E.panY=y-(y-E.panY)*E.zoom/old
        E:SaveView(); E:Render()
    end)
    function E:PortPosition(id,key,input)
        local card=self.cards[id]; local node=self:Graph().nodes[id]
        if node and node.collapsed and card then
            return {x=self.panX+(node.x+(input and 0 or NODE_WIDTH))*self.zoom,y=self.panY+(node.y+(node.title and 28 or 21))*self.zoom}
        end
        local button=card and (input and card.inPorts[key] or card.outPorts[key])
        if not node or not button or not button:IsShown() then return end
        return {x=self.panX+(node.x+(input and 0 or NODE_WIDTH))*self.zoom,y=self.panY+(node.y+button.rowY+PORT_SIZE/2)*self.zoom}
    end
    function E:Port(id,key,input)
        if s.inspectApplied then s.message="Applied view is read-only. Disable Applied view to edit connections."; self:Debug(); return end
        if not input then self:Cancel(); self.wire={from=id,output=key}; self:Track(); self:Render(); return end
        if self.wire then
            local wire=self.wire; local g=G.Copy(s:Draft())
            if wire.original then local _,i=G.Binding(g,wire.original.to,wire.original.input); if i then table.remove(g.edges,i) end end
            local result,why=G.Connect(g,s.catalog,wire.from,wire.output,id,key)
            if result then self:Cancel(); s:Commit(result) else s.message=why; self:Refresh() end
        else
            local edge=G.Binding(s:Draft(),id,key)
            if edge then self:Cancel(); self.wire={from=edge.from,output=edge.output,original=G.Copy(edge)}; self:Track(); self:Render() end
        end
    end
    function E:Disconnect(id,key)
        if s.inspectApplied then s.message="Applied view is read-only. Disable Applied view to edit connections."; self:Debug(); return end
        local edge=G.Binding(s:Draft(),id,key); if not edge then return end
        self:Cancel()
        s:Edit(function(g) local _,index=G.Binding(g,id,key); if index then table.remove(g.edges,index) end end)
        s.message="Connection removed."; self:Debug()
    end
    function E:PortDown(port,button)
        local binding=port.graphPort
        port.handledPress=true
        if button=="RightButton" then
            if binding.input then self:Disconnect(binding.card.nodeId,binding.key) else self:Cancel() end
            return
        end
        if button~="LeftButton" then return end
        local x,y=self:Coordinates()
        local completing=binding.input and self.wire~=nil
        self:Port(binding.card.nodeId,binding.key,binding.input)
        if self.wire and not completing then self.wirePress={port=port,x=x,y=y} end
    end
    function E:WireDropTarget()
        local foci=GetMouseFoci and GetMouseFoci() or (GetMouseFocus and {GetMouseFocus()} or {})
        if issecretvalue and issecretvalue(foci) then return "other" end
        if canaccesstable and not canaccesstable(foci) then return "other" end
        local focus=foci[1]
        for _=1,64 do
            if not focus then break end
            if issecretvalue and issecretvalue(focus) then break end
            if focus.IsForbidden and focus:IsForbidden() then break end
            if focus.graphPort and focus.graphPort.editor==self then return "port",focus.graphPort end
            if focus.graphCardEditor==self then return "node" end
            if focus==self.canvas or focus==self.content then return "canvas" end
            if focus==w or not focus.GetParent then break end
            focus=focus:GetParent()
        end
        return "other"
    end
    function E:ReleaseWire(button)
        if button~="LeftButton" or not self.wirePress then return end
        local press=self.wirePress; self.wirePress=nil
        local x,y=self:Coordinates()
        if math.abs(x-press.x)+math.abs(y-press.y)<=3 then return end
        if not self.wire then return end
        local kind,target=self:WireDropTarget()
        if kind=="port" and target.input then
            self:Port(target.card.nodeId,target.key,true)
            -- As with click-to-connect, an incompatible target keeps the
            -- original edge and preview available for retry or Escape.
        elseif kind=="canvas" and self.wire.original then
            local original=self.wire.original; self:Disconnect(original.to,original.input)
        else self:Cancel() end
    end
    function E:SelectNode(id)
        if IsShiftKeyDown() then self.selected[id]=not self.selected[id] or nil
        elseif not self.selected[id] then self.selected={[id]=true} end
        self.focusNode=id
        if self.details and self.details:IsShown() and self.detailMode=="node" then self:Details("node",id) end
    end
    function E:NodeDown(id,button)
        if button~="LeftButton" then return end
        if self.placing or self.wire then return end
        self:SelectNode(id); self:Render()
        if s.inspectApplied then return end
        local x,y=self:Coordinates(); self.working=G.Copy(s:Draft())
        self.pointer={kind="move",button=button,x=x,y=y,original=G.Copy(s:Draft())}; self:Track()
    end
    function E:Field(parent,slot)
        parent.fields=parent.fields or {}; if parent.fields[slot] then return parent.fields[slot] end
        local row={}; parent.fields[slot]=row
        row.label=UI:Label(parent,"",11,"muted"); row.input=UI:Input(parent,125,function(text) E:SubmitField(row,text) end)
        row.input:SetMaxLetters(1024)
        row.input:HookScript("OnEditFocusGained",function() E.textFocus=true; row.focused=true end)
        row.input:HookScript("OnEditFocusLost",function()
            E.textFocus=false; row.focused=false
            if not E.refreshing and row.input:GetText()~=row.original then E:SubmitField(row,row.input:GetText()) end
        end)
        row.color=UI:ColorField(parent,140,function(v) E:SubmitField(row,v) end)
        row.color.input:HookScript("OnEditFocusGained",function()E.textFocus=true end)
        row.color.input:HookScript("OnEditFocusLost",function()E.textFocus=false end)
        row.toggle=UI:Switch(parent,false,function(v) E:SubmitField(row,v) end)
        row.dropdown=UI:Dropdown(parent,140,{},function(v) E:SubmitField(row,v) end)
        row.picker=UI:ObjectButton(parent,125,action(function()
            if row.binding.picker=="sound" then
                local binding=G.Copy(row.binding);local rec=s:Graph();local node=rec.draft.nodes[binding.id]
                if E.soundPicker then E.soundPicker:Hide()end
                E.soundPicker=UI:SoundPicker(E.window,node.config,function(value)
                    if s:Graph()==rec and rec.draft.nodes[binding.id]==node and not s.inspectApplied then E:SubmitField(row,value)end
                end);return
            end
            if row.binding.picker=="macro" then
                E.macroEditor=E.macroEditor or UI:MacroActionEditor(E.window,s)
                E.macroEditor:Open(row.binding.id);return
            end
            E.pickerBinding=G.Copy(row.binding); E.pickerGraph=s:Graph().id
            E:Details(row.binding.picker=="icon" and "iconpicker" or "picker",row.binding.id)
        end))
        row.preview=row.picker.preview
        row.itemBrowse=UI:Button(parent,"...",28,action(function()
            E.pickerBinding=G.Copy(row.binding);E.pickerGraph=s:Graph().id
            E:Details("itempicker",row.binding.id)
        end))
        UI:AttachTooltip(row.itemBrowse,"Choose carried item","Browse your equipped items and bags. The numeric Item ID remains editable.")
        return row
    end
    function E:SubmitField(row,value)
        if self.refreshing or not row.binding then return end
        local b=row.binding
        if b.title then s:SetNodeTitle(b.id,value); return end
        if b.stackElement then s:StackElement(b.id,b.stackAction or "rename",b.stackElement==true and value or b.stackElement,value);return end
        if b.clickPayload then s:ClickPayload(b.id,b.payloadAction or "rename",b.clickPayload,value);return end
        if b.type=="float" or b.type=="integer" then value=tonumber(value) end
        s:SetValue(b.id,b.key,value,b.config)
    end
    function E:ShowField(row,parent,b,value,x,y,width,locked,stacked)
        local preserve=row.focused and row.binding and row.binding.id==b.id and row.binding.key==b.key and row.binding.config==b.config
        row.used=true; row.binding=b; row.label:Show(); row.label:SetText(b.label)
        local controlX,controlY=x+95,y
        if stacked then
            at(row.label,parent,x,y); M.Size(row.label,width,16); controlX,controlY=x,y+19
            if b.type=="boolean" then at(row.label,parent,x,y+7); M.Width(row.label,width-48); controlX,controlY=x+width-36,y+3 end
        else at(row.label,parent,x,y+7); M.Size(row.label,90,18) end
        row.label:SetWordWrap(false)
        if not preserve then row.input:Hide() end
        row.toggle:Hide(); row.dropdown:Hide(); row.color:Hide();row.itemBrowse:Hide(); if not b.picker or b.picker=="color" or b.picker=="item" then row.picker:Hide() end
        if b.picker=="item" then
            local inputWidth=(width or 125)-34
            at(row.input,parent,controlX,controlY);M.Width(row.input,inputWidth)
            if not preserve then row.original=tostring(value==nil and "" or value);row.input:SetText(row.original)end
            row.input:EnableMouse(not locked);row.input:SetAlpha(locked and .4 or 1);row.input:Show()
            at(row.itemBrowse,parent,controlX+inputWidth+6,controlY);row.itemBrowse:Show()
            if locked then row.itemBrowse:Disable()else row.itemBrowse:Enable()end
        elseif b.picker=="color" then
            at(row.color,parent,controlX,controlY);row.color:Layout(width or 125);row.color:SetValue(value);row.color:SetLocked(locked);row.color:Show()
        elseif b.picker then
            at(row.picker,parent,controlX,controlY); M.Width(row.picker,width or 125)
            local texture=b.picker=="icon" and ns.IconCatalog:Reference(value)
            row.picker:Show()
            if b.picker=="sound" then
                row.picker:SetObject(tostring(value),{label=tostring(value).." / Browse sounds...",origin="Search and listen before selecting."})
            elseif b.picker=="macro" then
                row.picker:SetObject(tostring(value),{label=value~="" and value or "Select / edit macro...",origin="Saved game macro; choose by name and scope."})
            elseif b.picker=="aura" then
                local node=self:Graph().nodes[b.id]
                local key=table.concat({self.profile or "",s:Graph().id,b.id,tostring(value),tostring(node.config.spellIcon),tostring(s.inspectApplied)},":")
                row.picker:SetObject(key,s:ObjectSummary(node),function(callback) return s:WatchObject(node,callback) end)
            else row.picker:SetObject(tostring(value),{icon=texture or nil,label=texture and "Change icon..." or "Select icon...",origin="Choose an icon from the shared catalog."}) end
            if locked then row.picker:Disable() else row.picker:Enable() end
        elseif b.choices or b.options=="fonts" or b.options=="statusbars" or b.options=="sounds" or b.options=="anchors" or b.options=="frameLibrary" then
            local options={}; for _,v in ipairs(b.choices or {}) do options[#options+1]={value=v,label=b.choiceLabels and b.choiceLabels[v] or v} end
            row.dropdown:SetOptionsProvider(nil)
            if b.options=="fonts" then options=ns.Media:FontOptions();row.dropdown:SetOptionsProvider(function()return ns.Media:FontOptions()end)
            elseif b.options=="statusbars" then options=ns.Media:BarOptions();row.dropdown:SetOptionsProvider(function()return ns.Media:BarOptions()end)
            elseif b.options=="sounds" then options=ns.Media:SoundOptions();row.dropdown:SetOptionsProvider(function()return ns.Media:SoundOptions()end)
            elseif b.options=="anchors" then
                options={{value="",label="Screen center"}}
                for _,id in ipairs(ns.Layout.order)do local entry=ns.Layout.elements[id];if entry.anchorPoint then options[#options+1]={value=id,label=entry.label}end end
            elseif b.options=="frameLibrary" then
                local function frameOptions()
                    local entries={{value="",label="Select frame..."}}
                    for _,entry in ipairs(ns.FrameLibrary and ns.FrameLibrary:Options() or {}) do entries[#entries+1]=entry end
                    return entries
                end
                options=frameOptions();row.dropdown:SetOptionsProvider(frameOptions)
            end
            at(row.dropdown,parent,controlX,controlY); M.Width(row.dropdown,width or 125)
            row.dropdown:SetOptions(options); row.dropdown:SetValue(value); row.dropdown:Show()
            if locked then row.dropdown:Disable() else row.dropdown:Enable() end
        elseif b.type=="boolean" then
            at(row.toggle,parent,controlX,controlY+3); row.toggle:SetValue(value==true); row.toggle:Show(); if locked then row.toggle:Disable() else row.toggle:Enable() end
        else
            at(row.input,parent,controlX,controlY); M.Width(row.input,width or 125)
            if not preserve then row.original=tostring(value==nil and "" or value); row.input:SetText(row.original) end
            row.input:EnableMouse(not locked); row.input:SetAlpha(locked and .4 or 1); row.input:Show()
        end
    end
    local function hideFields(parent)
        for _,row in pairs(parent.fields or {}) do
            row.used=false
            if not row.focused then row.binding=nil; row.label:Hide(); row.input:Hide() end
            row.toggle:Hide(); row.dropdown:Hide(); row.color:Hide();row.itemBrowse:Hide()
        end
    end
    local function finishFields(parent)
        for _,row in pairs(parent.fields or {}) do
            if not row.used then
                row.input:ClearFocus(); row.binding=nil; row.label:Hide(); row.input:Hide(); row.picker:Hide(); row.color:Hide();row.itemBrowse:Hide()
            end
        end
    end
    -- Catalog-owned selection metadata keeps optional source ports generic.
    -- The edit transaction rechecks edges even if a stale/disabled UI callback
    -- is invoked after another draft change.
    function E:SetOutputSelected(id,key,selected)
        return s:Edit(function(graph)
            local node=assert(graph.nodes[id],"Node no longer exists")
            local def=G.Definition(s.catalog[node.type],node) or s.catalog[node.type]
            assert(def.selectableOutputs and def.selectableOutputs[key] and type(def.outputSelectionKey)=="string","Output is not selectable")
            assert(not selected or not def.selectableOutputs[key].disabled,"This output is available only for Player")
            if not selected then
                for _,edge in ipairs(graph.edges) do
                    assert(edge.from~=id or edge.output~=key,"Disconnect this output before hiding it")
                end
            end
            local selection=node.config[def.outputSelectionKey] or {}
            node.config[def.outputSelectionKey]=selection
            selection[key]=selected and true or nil
        end)
    end
    function E:Card(id)
        if self.cards[id] then return self.cards[id] end
        if #self.freeCards>0 then
            local card=table.remove(self.freeCards);card.nodeId=id;clearDebugCard(card)
            self.cards[id]=card;return card
        end
        local c=UI:Panel(self.content,NODE_WIDTH,170,"surface"); self.cards[id]=c
        c.nodeId=id; c.graphCardEditor=self
        c.inPorts={}; c.outPorts={}; c:EnableMouse(true)
        c.header=UI:Button(c,"",NODE_WIDTH-4,nil,"ghost"); at(c.header,c,2,2); M.Height(c.header,36)
        c.header:SetLabelInsets(32,44,"LEFT")
        c.header:SetFrameLevel(c:GetFrameLevel())
        style:Gradient(c.header,"HORIZONTAL","secondary",.04,"accent",.07,0)
        c.headerRule=at(UI:Rule(c,NODE_WIDTH-2),c,1,39)
        c.category=at(UI:CategoryGlyph(c),c,9,10)
        c.title=c.header.label; style:Font(c.title,13,"bold")
        c.typeTitle=at(UI:Label(c,"",10,"muted"),c,34,28); M.Size(c.typeTitle,NODE_WIDTH-80,16); c.typeTitle:SetWordWrap(false)
        c.rename=at(UI:InlineEdit(c,action(function(value) s:SetNodeTitle(c.nodeId,value) end)),c,32,7)
        c.rename:SetFrameLevel(c:GetFrameLevel()+5)
        c.header:EnableMouse(true)
        c.header:SetScript("OnMouseDown",action(function(_,button)
            if button~="LeftButton" then return end
            if not s.inspectApplied and c.lastTitleClick and GetTime()-c.lastTitleClick<.3 then
                E:Cancel(); c.lastTitleClick=nil; c.rename:Begin(E:Graph().nodes[c.nodeId].title,NODE_WIDTH-80)
            else c.lastTitleClick=GetTime(); E:NodeDown(c.nodeId,button) end
        end))
        c.header:SetScript("OnMouseUp",function(_,button) E:Release(button) end)
        c.gear=at(UI:Button(c,"...",32,action(function() E.focusNode=c.nodeId; E:Details("node",c.nodeId) end)),c,NODE_WIDTH-42,7); M.Height(c.gear,26)
        UI:AttachTooltip(c.gear,"Node details","Inspect values, expose advanced ports and configure this node.")
        c.freezeNode=UI:Button(c,"Freeze",100,action(function()s.nodeTesting.Freeze(s,c.nodeId);E:Refresh()end),"ghost")
        c.testNode=UI:Button(c,"Test Mode",112,action(function()s.nodeTesting.Dialog(E,s,c.nodeId)end),"ghost")
        c.state=UI:Label(c,"",10,"muted"); M.Point(c.state,"BOTTOMLEFT",12,8); M.Size(c.state,NODE_WIDTH-56,14); c.state:SetWordWrap(false)
        c.info=UI:IconButton(c,"info",action(function()
            E:Cancel()
            local id=c.nodeId;local record=s:Graph()
            if not record then return end
            local graph=E:Graph();local node=graph and graph.nodes[id]
            if not node or not c:IsVisible() then return end
            E.wikiBinding={store=s:Store(),graph=record,id=id,kind=node.type,applied=s.inspectApplied}
            E.wiki=UI:NodeWiki(w,function(topic)
                local binding=E.wikiBinding
                if not binding or binding.store~=s:Store() or binding.graph~=s:Graph() or binding.applied~=s.inspectApplied then return nil end
                local current=E:Graph()
                if not current or not current.nodes[binding.id] or current.nodes[binding.id].type~=binding.kind then return nil end
                if type(s.Wiki)=="function" then return s:Wiki(binding.id,topic) end
                return {title="Node wiki: "..binding.kind,selectedTopic="overview",topics={{value="overview",label="Overview"}},tables={{title="Reference",columns={{key="meaning",label="Meaning"}},rows={{meaning="A reference for this node is not available yet."}}}}}
            end)
            if not E.wiki.editorBindingCleanup then
                E.wiki.editorBindingCleanup=true;E.wiki:HookScript("OnHide",function()E.wikiBinding=nil end)
            end
            if not E.wiki:IsShown() then E.wikiBinding=nil end
        end),"ghost")
        M.Size(c.info,24,24);M.Point(c.info,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-8,4);c.info:SetFrameLevel(c:GetFrameLevel()+5)
        c.info:SetScript("OnMouseDown",function()end);c.info:SetScript("OnMouseUp",function()end)
        if c.info.SetPropagateMouseClicks then c.info:SetPropagateMouseClicks(false) end
        UI:AttachTooltip(c.info,"Node wiki","Explore this node's outputs and how to use them.")
        c:SetScript("OnMouseDown",action(function(_,button) E:NodeDown(c.nodeId,button) end)); c:SetScript("OnMouseUp",action(function(_,button) E:Release(button) end))
        return c
    end
    function E:PortButton(card,id,key,p,input,y)
        local ports=input and card.inPorts or card.outPorts
        if not ports[key] then
            local button=style:GraphPort(card)
            button.graphPort={editor=self,card=card,key=key,input=input}
            button:SetScript("OnMouseDown",action(function(_,mouseButton) E:PortDown(button,mouseButton) end))
            button:SetScript("OnMouseUp",action(function(_,mouseButton) E:ReleaseWire(mouseButton) end))
            button:SetScript("OnClick",action(function(_,mouseButton)
                -- Native clicks follow the already handled press. Keep direct
                -- Button activation usable without starting a second operation.
                if button.handledPress then button.handledPress=nil; return end
                if mouseButton=="RightButton" then
                    if input then E:Disconnect(card.nodeId,key) end
                else E:Port(card.nodeId,key,input) end
            end))
            button.portLabel=UI:Label(card,"",10,"muted"); M.Size(button.portLabel,NODE_WIDTH/2-28,16); button.portLabel:SetWordWrap(false); if not input then button.portLabel:SetJustifyH("RIGHT") end
            ports[key]=button
        end
        local b=ports[key]; b.used=true; b.rowY=y; b:Show(); b.portLabel:Show(); b.portLabel:SetText(p.label or key)
        at(b,card,input and -PORT_SIZE/2 or NODE_WIDTH-PORT_SIZE/2,y)
        at(b.portLabel,card,input and 14 or NODE_WIDTH/2+14,y+3)
        local connected=input and G.Binding(self:Graph(),card.nodeId,key)~=nil or false
        if not input then for _,edge in ipairs(self:Graph().edges) do if edge.from==card.nodeId and edge.output==key then connected=true; break end end end
        b:SetConnected(connected); b:SetSelected(false); b:SetCompatible(nil)
        if self.wire and input then
            local source=self:Graph().nodes[self.wire.from]
            local sourceDef=source and (G.Definition(s.catalog[source.type],source) or s.catalog[source.type])
            local output=sourceDef and sourceDef.outputs[self.wire.output]
            local compatible=output and G.Compatible(G.OutputType(self:Graph(),s.catalog,self.wire.from,self.wire.output),p.type) or false
            if compatible then
                local graph=self:Graph()
                if not self.connectionChecks or self.connectionChecks.graph~=graph then self.connectionChecks={graph=graph,results={}} end
                local identity=table.concat({self.wire.from,self.wire.output,card.nodeId,key},":")
                local result=self.connectionChecks.results[identity]
                if result==nil then result=G.Connect(graph,s.catalog,self.wire.from,self.wire.output,card.nodeId,key)~=nil;self.connectionChecks.results[identity]=result end
                compatible=result
            end
            b:SetCompatible(compatible)
        end
        local help=s.inspectApplied and "Applied view is read-only. Disable Applied view to edit connections."
            or input and "Drag a connected input to another input to rewire; drop on empty canvas or right-click to disconnect. Escape cancels."
            or "Drag to an input, or click this output then click an input. Escape cancels."
        UI:AttachTooltip(b,p.label or key,p.type..(p.wire and (p.required==false and " / optional connection" or " / connection required") or "")..(p.control and " / control" or "").."\n"..help..(p.maySecret and "\nThis source can be secret depending on the client and situation." or ""))
        b.tooltipEnter=function()
            local trace=s:Trace(); local rec=s:Graph(); local message=b.tooltipText
            local signal=E:PortSignal(card.nodeId,key,input)
            local info=ns.DesignSystem.signals[signal] or ns.DesignSystem.signals.unavailable
            message=message.."\nStatus: "..info.label.."\n"..info.help
            if E.frozen then message=message.."\nFrozen debug snapshot, not current gameplay."; trace=E.frozenTrace or {} end
            local node=E:Graph().nodes[card.nodeId]
            if node and s.catalog[node.type].debugPreview then
                message=message.."\n"..(card.debugLabel and card.debugLabel:GetText() or "Graph").."\n"..(card.debugText or "No observation")
            elseif input then
                local edge=G.Binding(E:Graph(),card.nodeId,key)
                if edge then
                    local observed=trace[edge.from]; local value=observed and observed.values and observed.values[edge.output]
                    if (s.inspectApplied or rec.draftRevision==rec.appliedDraftRevision) and value~=nil then message=message.."\nObserved: "..ns.DisplayModel.Summary(value) end
                end
            else
                local observed=trace[card.nodeId]; local value=observed and observed.values and observed.values[key]
                if (s.inspectApplied or rec.draftRevision==rec.appliedDraftRevision) and value~=nil then message=message.."\nObserved: "..ns.DisplayModel.Summary(value) end
                if (s.inspectApplied or rec.draftRevision==rec.appliedDraftRevision) and observed and observed.fields and observed.fields[key] then message=message.."\nData: "..observed.fields[key] end
            end
            local previous=b.tooltipText; b.tooltipText=message; UI:ShowTooltip(b); b.tooltipText=previous
        end
        if not b.graphTooltipHooked then
            b.graphTooltipHooked=true
            b:HookScript("OnEnter",function() if b.tooltipEnter then b.tooltipEnter() end end)
            b:HookScript("OnLeave",function() UI:HideTooltip(b) end)
        end
    end
    function E:PortSignal(id,key,input)
        local graph=self:Graph(); local n=graph.nodes[id]; if not n then return "pending" end
        local cached=self.portDefinitions and self.portDefinitions[id]
        local def=cached and cached.def or definition(s.catalog,n)
        local p=input and (cached and cached.inputs or G.Ports(def))[key] or def.outputs[key]
        local trace=s:Trace(); local rec=s:Graph()
        local matches=s.test and s.test.draftRevision==rec.draftRevision or s.inspectApplied or (rec.applied and rec.draftRevision==rec.appliedDraftRevision)
        if self.frozen then
            trace=self.frozenTrace or {}; matches=matches and self.frozenGraph==rec.id and self.frozenRevision==rec.revision
        end
        if def.debugPreview and key=="value" then
            local card=self.cards[id]
            if self.frozen then return matches and card and card.debugSignal or "pending" end
            local _,run=s:Trace()
            local observation=matches and ns.GraphDebug.Observe(run,id,card and card.debugSelection)
            return observation and observation.observed and observation.signal or "pending"
        end
        if input then
            local e=G.Binding(graph,id,key)
            if e then return self:PortSignal(e.from,e.output,false) end
            local value=n.values[key]; if value==nil and p then value=p.default end
            return value~=nil and "readable" or "unavailable"
        end
        local observed=matches and trace[id]
        return observed and observed.signals and observed.signals[key] or p and p.maySecret and "conditional" or "pending"
    end
    function E:Render()
        if not s:Graph() or not self.canvas then if self.wiki then self.wiki:Hide();self.wikiBinding=nil end;return end
        self.grid:Update(M.GetWidth(self.canvas),M.GetHeight(self.canvas),self.panX,self.panY,self.zoom)
        self.refreshing=true
        local graph=self:Graph(); local plan=G.Compile(graph,s.catalog,true)
        local binding=self.wikiBinding
        if self.wiki and self.wiki:IsShown() and binding and (binding.store~=s:Store() or binding.graph~=s:Graph() or binding.applied~=s.inspectApplied or not graph.nodes[binding.id] or graph.nodes[binding.id].type~=binding.kind) then self.wiki:Hide();self.wikiBinding=nil end
        self.portDefinitions={}
        for id,c in pairs(self.cards) do
            if not graph.nodes[id] then c:Hide();clearDebugCard(c); self.cards[id]=nil; c.nodeId=nil; self.freeCards[#self.freeCards+1]=c end
        end
        for _,id in ipairs(sorted(graph.nodes)) do
            local n=graph.nodes[id]; local def=definition(s.catalog,n); local c=self:Card(id)
            c:Show(); c:SetScale(self.zoom); at(c,self.content,(self.panX/self.zoom)+n.x,(self.panY/self.zoom)+n.y)
            c.header:SetLabelText(n.title or def.label); c.typeTitle:SetText(def.label); c.typeTitle:SetShown(n.title~=nil)
            c.category:SetCategory(ns.DesignSystem.NodeCategory(n.type,def))
            c.category:SetScript("OnMouseDown",action(function(_,button) if button=="LeftButton" then self:Cancel(); s:ToggleCollapsed(c.nodeId) end end))
            UI:AttachTooltip(c.category,n.collapsed and "Expand node" or "Collapse node","Presentation only; connections and execution are unchanged.")
            M.Height(c.header,n.title and 50 or 36); at(c.headerRule,c,1,n.title and 54 or 39)
            at(c.title,c.header,32,7); M.Size(c.title,NODE_WIDTH-80,20)
            UI:AttachTooltip(c.header,n.title or def.label,def.label.." / "..id.."\nDouble-click the heading to set a custom title.")
            c:SetAlpha((not plan or plan.active[id]) and 1 or .55)
            c.gear.tooltipText=def.help or "Inspect values, expose advanced ports and configure this node."
            for _,edge in ipairs(c.edges) do edge:SetColorTexture(ns.Theme:Color(self.selected[id] and "accent" or "edge")) end
            -- Do not hide active hit targets during a redraw: WoW can cancel
            -- mouse capture when a pressed Button is hidden, even briefly.
            for _,ports in ipairs({c.inPorts,c.outPorts}) do for _,b in pairs(ports) do b.used=false end end
            hideFields(c)
            local inputs=G.Ports(def); local rows=0; local portStart=PORT_START+(n.title and 16 or 0)
            self.portDefinitions[id]={def=def,inputs=inputs}
            if not n.collapsed then
            local slot=0
            for _,f in ipairs(def.fields or {}) do if f.primary and not f.advanced then
                slot=slot+1;self:ShowField(self:Field(c,slot),c,{id=id,key=f.key,label=f.label,type=f.type,choices=f.choices,choiceLabels=f.choiceLabels,config=true},n.config[f.key]==nil and f.default or n.config[f.key],12,portStart,NODE_WIDTH-24,s.inspectApplied,true)
                portStart=portStart+58
            end end
            for _,key in ipairs(G.Ordered(inputs)) do local p=inputs[key]
                if not p.advanced or n.exposed[key] or G.Binding(graph,id,key) then self:PortButton(c,id,key,p,true,portStart+rows*PORT_STEP); rows=rows+1 end
            end
            local outputs=0
            for _,key in ipairs(G.Ordered(def.outputs)) do self:PortButton(c,id,key,def.outputs[key],false,portStart+outputs*PORT_STEP); outputs=outputs+1 end
            for _,ports in ipairs({c.inPorts,c.outPorts}) do for _,b in pairs(ports) do if not b.used then b:Hide(); b.portLabel:Hide() end end end
            local y=portStart+math.max(rows,outputs)*PORT_STEP+10
            for _,key in ipairs(G.Ordered(inputs)) do local p=inputs[key]
                if not p.control and not p.wire and (not p.advanced or n.exposed[key]) then
                    slot=slot+1; local v=n.values[key]; if v==nil then v=p.default end
                    self:ShowField(self:Field(c,slot),c,{id=id,key=key,label=p.label,type=p.type,picker=p.picker},v,12,y,NODE_WIDTH-24,G.Binding(graph,id,key)~=nil or s.inspectApplied,true); y=y+(p.type=="boolean" and 38 or 58)
                end
            end
            for _,f in ipairs(def.fields or {}) do
                if not f.advanced and not f.primary then
                slot=slot+1; self:ShowField(self:Field(c,slot),c,{id=id,key=f.key,label=f.label,type=f.type,choices=f.choices,choiceLabels=f.choiceLabels,picker=f.picker,options=f.options,config=true},n.config[f.key]==nil and f.default or n.config[f.key],12,y,NODE_WIDTH-24,s.inspectApplied,true); y=y+(f.type=="boolean" and 38 or 58)
                end
            end
            if c.debugPreview then c.debugPreview:Hide();c.debugContext:Hide();c.debugDetails:Hide();c.debugLabel:Hide() end
            if def.debugPreview then
                if not c.debugPreview then
                    c.debugLabel=UI:Label(c,"Graph",10,"muted");c.debugLabel:SetWordWrap(false)
                    c.debugPreview=UI:Label(c,"No observation",11,"text");c.debugPreview:SetJustifyV("TOP")
                    c.debugContext=UI:Dropdown(c,NODE_WIDTH-24,{},action(function(token)
                        local _,run=s:Trace();c.debugSelection=ns.GraphDebug.Select(run,token);c.debugStamp=nil;self:Debug()
                    end))
                    c.debugDetails=UI:Button(c,"Expand value",NODE_WIDTH-24,action(function()
                        c.debugExpanded=not c.debugExpanded;c.debugStamp=nil;self:Render()
                    end))
                end
                at(c.debugLabel,c,12,y);M.Size(c.debugLabel,NODE_WIDTH-24,18);c.debugLabel:Show();y=y+20
                at(c.debugContext,c,12,y);c.debugContext:Show();y=y+34
                at(c.debugPreview,c,12,y);M.Size(c.debugPreview,NODE_WIDTH-24,c.debugExpanded and 124 or 50);c.debugPreview:Show();y=y+(c.debugExpanded and 130 or 56)
                at(c.debugDetails,c,12,y);c.debugDetails:SetLabelText(c.debugExpanded and "Collapse value" or "Expand value");c.debugDetails:Show();y=y+32
            end
            local capable=s.nodeTesting and #s.nodeTesting.Ports(def)>0 and not s.inspectApplied
            c.freezeNode:SetShown(capable);c.testNode:SetShown(capable)
            if capable then
                local override=s.test and s.test.nodeOverrides and s.test.nodeOverrides[id]
                c.freezeNode:SetLabelText(override and "Live" or "Freeze")
                at(c.freezeNode,c,12,y);at(c.testNode,c,124,y);y=y+36
            end
            finishFields(c); M.Height(c,y+30)
            else
                if c.debugPreview then c.debugPreview:Hide();c.debugContext:Hide();c.debugDetails:Hide();c.debugLabel:Hide() end
                for _,ports in ipairs({c.inPorts,c.outPorts}) do for _,b in pairs(ports) do b:Hide(); b.portLabel:Hide() end end
                c.freezeNode:Hide();c.testNode:Hide();finishFields(c); M.Height(c,n.title and 90 or 76)
            end
            c.headerRule:Show(); c.state:Show();c.info:Show()
        end
        for _,line in ipairs(self.lines) do line:Hide() end
        for index,edge in ipairs(graph.edges) do
            local a,b=self:PortPosition(edge.from,edge.output,false),self:PortPosition(edge.to,edge.input,true)
            if a and b and not (self.wire and self.wire.original and self.wire.original.to==edge.to and self.wire.original.input==edge.input) then
                local line=self.lines[index]
                if not line then line=style:GraphWire(self.content,"accent"); self.lines[index]=line end
                line:SetEndpoints(a.x,a.y,b.x,b.y,1); line:Show()
            end
        end
        self.refreshing=false; self:Debug()
    end
    function E:Debug()
        local trace,run=s:Trace(); if self.frozen then trace=self.frozenTrace or {} end
        local rec=s:Graph(); if not rec then return end
        local matches=s.test and s.test.draftRevision==rec.draftRevision or s.inspectApplied or (rec.applied and rec.draftRevision==rec.appliedDraftRevision)
        if self.frozen and (self.frozenGraph~=rec.id or self.frozenRevision~=rec.revision) then matches=false end
        for id,card in pairs(self.cards) do if card:IsShown() then
            for _,entry in ipairs({{card.inPorts,true},{card.outPorts,false}}) do
                for key,port in pairs(entry[1]) do if port.used then port:SetSignal(self:PortSignal(id,key,entry[2])) end end
            end
            local t=matches and trace[id]; local v=s.validation
            local node=self:Graph().nodes[id];local def=node and s.catalog[node.type]
            if def and def.debugPreview and card.debugPreview and card.debugPreview:IsVisible() and w:IsShown() and not self.frozen
                and (not card.debugStamp or GetTime()-card.debugStamp>=.2) then
                card.debugStamp=GetTime()
                local observation=matches and ns.GraphDebug.Observe(run,id,card.debugSelection) or {context="Draft / no matching live trace",observed=false}
                local text=ns.GraphDebug.Format(observation.value,observation.signal,observation.observed,card.debugExpanded)
                card.debugSignal=observation.observed and observation.signal or "pending"
                if text~=card.debugText then card.debugText=text;card.debugPreview:SetText(text) end
                card.debugLabel:SetText(observation.context)
                local repeated=matches and run and run.repeated and run.repeated[id]
                card.debugContext:SetShown(repeated==true)
                if repeated then
                    local options=ns.GraphDebug.Contexts(run);local signature=""
                    for _,option in ipairs(options) do signature=signature..option.label..";" end
                    if signature~=card.debugOptions then card.debugOptions=signature;card.debugContext:SetOptions(options) end
                    card.debugContext:SetValue(card.debugSelection and card.debugSelection.token or "")
                end
            end
            local observed=""
            if t and t.values and not (def and def.debugPreview) then
                local node=self:Graph().nodes[id]; local def=G.Definition(s.catalog[node.type],node) or s.catalog[node.type]
                for _,key in ipairs(G.Ordered(def.outputs)) do
                    if t.values[key]~=nil then observed=" / "..ns.DisplayModel.Summary(t.values[key]):sub(1,48); break end
                end
            end
            card.state:SetText(v and v.node==id and ("! "..v.message) or (def and def.debugPreview and (self.frozen and "Frozen preview" or "Session preview / 5 Hz")) or (t and (ns.GraphValues.StatusLabel(t.status)..observed) or (not matches and "Draft / no matching live trace" or "No observation")))
            local color=v and v.node==id and "danger" or (self.selected[id] or (t and GetTime()-t.at<.4)) and "accent" or "edge"
            for _,edge in ipairs(card.edges) do edge:SetColorTexture(ns.Theme:Color(color)) end
        end end
        local state=(run and run.test and "TEST" or s.runs[rec.id] and "LIVE" or "IDLE").." / r"..rec.revision..(self.frozen and " / frozen" or "")..(matches and "" or " / draft differs")
        self.status:SetText((run and run.test and "TEST" or s.runs[rec.id] and "LIVE" or "IDLE").." r"..rec.revision.." / "..math.floor(self.zoom*100).."%"..(s.inspectApplied and " / read-only" or "")..(#s.errors>0 and " / !"..#s.errors or ""))
        UI:AttachTooltip(self.canvas,"Graph status",state.."\n"..(s.message or "Ready").."\nPending: "..#s.queue.." / diagnostics: "..#s.errors)
        self.menus[3].options[2].label=s.inspectApplied and "Edit draft" or "Applied snapshot"
        self.menus[3].options[3].label=self.frozen and "Resume debug" or "Freeze debug"
        self.menus[4].options[3].label=s.active and "Disable module" or "Enable module"
        self.menus[4].options[5].label=s:Store().quick.shown and "Hide Quick-Access" or "Show Quick-Access"
        if self.details and self.details:IsShown() and self.detailMode=="node" then
            local n=self:Graph().nodes[self.focusNode]; local t=matches and trace[self.focusNode]
            if n and s.catalog[n.type].source and t then
                local fields=t.fields or {}
                self.detailText:SetText("Observation: "..ns.GraphValues.StatusLabel(t.status).."\n"..(fields.stacks and ("Stacks: "..ns.GraphValues.StatusLabel(fields.stacks).."; duration: "..ns.GraphValues.StatusLabel(fields.duration or "unavailable")) or "Changes remain in the draft until Save."))
            end
        end
    end
    function E:Refresh()
        self.quickAccess:SetValue(s:Store().quick.shown==true)
        if self.quickShown then self.quickShown:SetValue(s:Store().quick.shown==true) end
        if not s:Graph() then return end
        local rec=s:Graph(); local target=self.libraryTarget
        if not target or not (target.kind=="group" and s:Store().groups[target.id] or target.kind=="graph" and s:Store().graphs[target.id]) then
            self.libraryTarget={kind="graph",id=rec.id}
        elseif target.kind=="graph" then target.id=rec.id end
        self.library:SetDefinitions(s:Library()); self.library:SetValue(self.libraryTarget.id)
        self.resetTests:SetShown(s.test and s.test.nodeOverrides~=nil or false)
        self.graphTitle:SetText(rec.name..(s:Unsaved(rec) and " *" or ""))
        self.graphState:SetText(not rec.applied and "Draft only" or not rec.enabled and "Disabled" or not s:GroupAllows(rec) and "Paused by group" or not s.active and "Module disabled" or "Live enabled")
        self.module:SetValue(s.active==true); self.applied:SetValue(s.inspectApplied==true)
        self.appliedLabel:SetText(s.inspectApplied and "Applied (read-only)" or "Applied view")
        self.budget:SetText(tostring(s:Store().budget)); self:Render()
        if self.details and self.details:IsShown() and self.detailMode=="node" then self:Details("node",self.focusNode) end
    end
    function E:Search(x,y)
        if s.inspectApplied then s.message="Leave applied view to add nodes"; self:Debug(); return end
        self:Cancel(); self.searchX,self.searchY=x,y
        if not self.search then
            self.searchPopup=UI:DismissiblePopup(body,340,320)
            self.search=self.searchPopup.panel
            self.search:SetClampedToScreen(true)
            self.searchInput=at(UI:Input(self.search,280),self.search,12,12)
            self.searchClose=at(UI:IconButton(self.search,"close",function() E.search:Hide() end,"ghost"),self.search,300,12)
            M.Size(self.searchClose,28,32)
            UI:AttachTooltip(self.searchClose,"Close node search","Escape or click outside to cancel without adding a node.")
            self.searchInput:SetScript("OnTextChanged",function() E:SearchResults() end)
            self.searchInput:SetScript("OnEscapePressed",function() E.search:Hide() end)
            self.searchInput:SetScript("OnEnterPressed",function() E:ChooseSearch() end)
            self.searchInput:SetScript("OnKeyDown",function(_,key)
                if key=="DOWN" then E.searchIndex=math.min(#E.matches,(E.searchIndex or 1)+1); E:SearchResults(true)
                elseif key=="UP" then E.searchIndex=math.max(1,(E.searchIndex or 1)-1); E:SearchResults(true) end
            end)
            self.search:HookScript("OnHide",function() E.searchInput:ClearFocus(); E.lastClick=nil end)
            self.searchMode=at(UI:Dropdown(self.search,316,{{value="alphabetical",label="Alphabetical"},{value="categories",label="Categories"}},function(value)
                s:Store().nodePalette.mode=value; E:SearchResults()
            end),self.search,12,49)
            self.searchList=at(UI:ResultList(self.search,316,function(index) E.searchIndex=index; E:ChooseSearch() end),self.search,12,87)
            self.searchButtons=self.searchList.buttons
        end
        -- The content viewport is the window minus its 44-unit chrome.
        at(self.search,body,math.max(8,math.min(M.GetWidth(w)-348,(self.canvasLeft or 18)+x)),math.max(0,math.min(M.GetHeight(w)-44-M.GetHeight(self.search)-8,(self.canvasTop or 86)+y)))
        self.searchPopup:Open(); self.searchInput:SetText(""); self:SearchResults(); self.searchInput:SetFocus()
    end
    function E:SearchResults(keep)
        local q=self.searchInput:GetText():lower():match("^%s*(.-)%s*$"); self.matches={}
        local store=s:Store(); store.nodePalette=store.nodePalette or {mode="categories",collapsed={}}
        local prefs=store.nodePalette; prefs.collapsed=prefs.collapsed or {}
        self.searchMode:SetValue(prefs.mode)
        local ranks={}
        for _,kind in ipairs(s.catalogOrder) do
            local label=s.catalog[kind].label:lower(); local p=label:find(q,1,true)
            if p or kind:find(q,1,true) then self.matches[#self.matches+1]=kind; ranks[kind]=label==q and 1 or p==1 and 2 or 3 end
        end
        table.sort(self.matches,function(a,b)
            if ranks[a]~=ranks[b] then return ranks[a]<ranks[b] end
            local x,y=s.catalog[a].label:lower(),s.catalog[b].label:lower(); return x==y and a<b or x<y
        end)
        local entries={}
        if prefs.mode=="categories" then
            local groups={};for _,kind in ipairs(self.matches) do
                local category=ns.DesignSystem.NodeCategory(kind,s.catalog[kind]);groups[category]=groups[category] or {};groups[category][#groups[category]+1]=kind
            end
            self.matches={}
            for _,category in ipairs(ns.DesignSystem.categoryOrder) do
                local group=groups[category]
                if group then
                    local expanded=q~="" or not prefs.collapsed[category]
                    self.matches[#self.matches+1]={category=category}
                    entries[#entries+1]={label=(expanded and "[-] " or "[+] ")..ns.DesignSystem.categories[category].label.." ("..#group..")",category=category}
                    if expanded then for _,kind in ipairs(group) do self.matches[#self.matches+1]=kind;entries[#entries+1]={label="    "..s.catalog[kind].label,category=category} end end
                end
            end
        else
            for _,kind in ipairs(self.matches) do entries[#entries+1]={label=s.catalog[kind].label,category=ns.DesignSystem.NodeCategory(kind,s.catalog[kind])} end
        end
        if not keep then
            self.searchIndex=1; self.searchList.offset=0
            if q~="" then for i,kind in ipairs(self.matches) do if type(kind)=="string" then self.searchIndex=i;break end end end
        end
        self.searchIndex=math.max(1,math.min(#self.matches,self.searchIndex or 1))
        local available=math.min(M.GetHeight(w)-44,M.ToDesign(UIParent:GetHeight()/self.search:GetEffectiveScale()))-106
        local rows=math.max(1,math.min(8,#self.matches,math.floor(available/33)))
        self.searchList:SetEntries(entries,rows,self.searchIndex,true); M.Height(self.search,95+rows*33)
        at(self.search,body,math.max(8,math.min(M.GetWidth(w)-348,self.canvasLeft+self.searchX)),math.max(0,math.min(M.GetHeight(w)-44-M.GetHeight(self.search)-8,self.canvasTop+self.searchY)))
    end
    function E:ChooseSearch()
        local kind=self.matches[self.searchIndex or 1]; if not kind then return end
        if type(kind)=="table" then
            local prefs=s:Store().nodePalette;prefs.collapsed[kind.category]=not prefs.collapsed[kind.category];self:SearchResults();return
        end
        self.search:Hide(); self.placing={kind=kind}; self.ghostLabel:SetText(s.catalog[kind].label); M.Size(self.ghost,NODE_WIDTH*self.zoom,95*self.zoom); self:Track(); self:PointerStep()
    end
    function E:PickerResults(reset)
        if not self.pickerView or self.detailMode~="picker" then return end
        self.pickerView.page=self.pickerPage or 1; self.pickerView:Refresh(reset)
        self.pickerMatches=self.pickerView.matches; self.pickerPage=self.pickerView.page
    end
    function E:DeleteSelected()
        local target=self.libraryTarget or {kind="graph",id=s:Graph().id}
        local record=target.kind=="group" and s:Store().groups[target.id] or s:Store().graphs[target.id]
        if not record then return end
        self.deleteTarget={id=target.id,kind=target.kind,record=record}; self:Details(target.kind=="group" and "deleteGroup" or "deleteGraph")
    end
    function E:Details(mode,id)
        ns.Sound:Release(self)
        local nextNode=id or self.focusNode
        local resetScroll=mode~=self.detailMode or (mode=="node" and nextNode~=self.focusNode)
        self.detailMode=mode; self.focusNode=id or self.focusNode
        if not self.details then
            self.details=UI:Dialog("BVAddonSuiteAuraDetails",460,320,w)
            self.details:HookScript("OnHide",function()
                ns.Sound:Release(E)
                if E.iconView then E.iconView:Hide(); E.iconView:Close() end
                if E.pickerView then E.pickerView:Hide(); E.pickerView:Close() end
                if E.itemView then E.itemView:Hide();E.itemView:Close()end
                if E.pickerInput then E.pickerInput:ClearFocus() end
                E.pickerSearch=nil
            end)
            self.detailTitle=self.details.title
            self.detailText=at(UI:Label(self.details.content,"",11,"muted"),self.details.content,18,9); M.Size(self.detailText,410,38)
            self.detailRows=UI:Panel(self.details.content,424,510,"surface"); at(self.detailRows,self.details.content,18,56)
            self.detailForm=UI:Form(self.details.content,424,510,self.details.content); at(self.detailForm,self.details.content,18,56)
            self.detailForm:SetClipsChildren(true); self.detailForm:Hide(); self.detailForm.slider:Hide()
            self.detailButtons={}; self.expose={}; self.outputChoices={}
        end
        self.refreshing=true; hideFields(self.detailRows)
        for _,b in pairs(self.detailButtons) do b:Hide() end
        for _,b in pairs(self.expose) do b:Hide(); b.caption:Hide() end
        for _,b in pairs(self.outputChoices) do UI:HideTooltip(b); b:Hide(); b.caption:Hide() end
        if self.outputChoiceTitle then self.outputChoiceTitle:Hide() end
        if self.outputFilter and (mode~="node" or resetScroll) then
            self.outputFilter:ClearFocus(); self.outputFilter:Hide(); self.outputFilterLabel:Hide(); self.outputFilterContext=nil
        end
        for _,widget in ipairs(self.pickerWidgets or {}) do widget:Hide() end
        if self.pickerView then self.pickerView:Hide() end
        if self.itemView then self.itemView:Hide()end
        if self.iconView then self.iconView:Hide() end
        for _,widget in ipairs(self.libraryWidgets or {}) do widget:Hide() end
        if self.settingsPanel then self.settingsPanel:Hide() end
        if self.communicationPanel then self.communicationPanel:Hide() end
        for _,frame in ipairs(self.debugGroups) do frame:Hide() end
        if mode~="picker" then self.pickerSearch=nil; if self.pickerInput then self.pickerInput:ClearFocus() end end
        local p=self.detailRows
        self.detailForm:SetShown(mode=="node"); self.detailForm.slider:Hide()
        p:SetParent(mode=="node" and self.detailForm.content or self.details.content)
        if mode=="node" then at(p,self.detailForm.content,0,0); M.Size(p,400,510)
        else at(p,self.details.content,18,56); M.Size(p,424,510) end
        if resetScroll then self.detailForm.slider:SetValue(0) end
        local function button(key,label,x,y,callback)
            if not self.detailButtons[key] then self.detailButtons[key]=UI:Button(p,label,140,function() local b=self.detailButtons[key]; b.callback() end) end
            local b=self.detailButtons[key]; b.callback=action(callback); at(b,p,x,y); b:Show(); return b
        end
        if mode=="debug" then
            self.detailTitle:SetText("Debug & execution budget")
            self.detailText:SetText("Inspect the applied snapshot, freeze observations and tune the shared slice budget.")
            for i,frame in ipairs(self.debugGroups) do frame:SetParent(p); frame:SetFrameLevel(p:GetFrameLevel()+1); at(frame,p,12,12+(i-1)*60); frame:Show() end
        elseif mode=="communication" then
            self.detailTitle:SetText("Addon message permissions")
            self.detailText:SetText("Local profile settings, saved immediately. External delivery requires native testing; API success is not a receipt.")
            if not self.communicationPanel then self.communicationPanel=at(UI:MessageOptions(p,s,424),p,0,0) end
            self.communicationPanel:Refresh(); self.communicationPanel:Show()
        elseif mode=="settings" then
            self.detailTitle:SetText("Studio settings")
            self.detailText:SetText("Appearance is shared by all BV windows. Quick-Access choices are saved with this profile.")
            if not self.settingsPanel then
                self.settingsPanel=at(UI:Panel(p,424,438,"surface"),p,0,0); UI:HideSurface(self.settingsPanel)
                local panel=self.settingsPanel
                self.quickShown=at(UI:Switch(panel,false,function(value) s:SetQuickShown(value) end),panel,12,18)
                at(UI:Label(panel,"Show Quick-Access",13,"text"),panel,62,19)
                local note=at(UI:Label(panel,"Choose included graphs and group switches in the graph context menu. New items are hidden by default.",11,"muted"),panel,12,54); M.Size(note,398,36)
                self.settingsTheme=UI:Field(panel,"Theme",UI:AppearanceChoice(panel,"themeKey",398),12,106)
                self.settingsFont=UI:Field(panel,"Font family",UI:AppearanceChoice(panel,"font",398),12,178)
                self.settingsScale=at(UI:ScaleSlider(panel,398,function(value)
                    ns.Settings:Set("scale",value); windowSize(w,M.GetWidth(w),M.GetHeight(w)); E:Details("settings")
                    if s.quick and s.quick:IsShown() then s.quick:Refresh() end
                end),panel,12,257)
                self.minimapOptions=at(UI:MinimapOptions(panel,398),panel,12,316)
            end
            self.settingsPanel:Show(); self.quickShown:SetValue(s:Store().quick.shown)
            self.settingsTheme:SetValue(ns.Settings:Get("themeKey")); self.settingsFont:SetValue(ns.Settings:Get("font")); self.settingsScale:SetValue(ns.Settings:Get("scale"))
        elseif mode=="library" then
            local target=self.libraryTarget or {kind="graph",id=s:Graph().id}
            self.libraryEditing={kind=target.kind,id=target.id}
            local item=target.kind=="group" and s:Store().groups[target.id] or s:Store().graphs[target.id]
            assert(item,"Library item no longer exists")
            self.detailTitle:SetText(target.kind=="group" and "Aura group" or "Aura properties")
            self.detailText:SetText("Names and membership are saved immediately.\nMoving a live graph into a disabled group pauses it.")
            if not self.libraryWidgets then
                self.libraryWidgets={}
                local function keep(widget) self.libraryWidgets[#self.libraryWidgets+1]=widget; return widget end
                keep(at(UI:Label(p,"Name",12,"muted"),p,12,16))
                local function rename()
                    local t=E.libraryEditing; s:Rename(t.kind,t.id,E.libraryName:GetText()); E:Details("library")
                end
                self.libraryName=keep(at(UI:Input(p,398,action(rename)),p,12,42)); self.libraryName:SetMaxLetters(80)
                self.libraryName:HookScript("OnEditFocusGained",function() E.textFocus=true end)
                self.libraryName:HookScript("OnEditFocusLost",function() E.textFocus=false end)
                keep(at(UI:ActionButton(p,"Save name","check",140,action(rename),true),p,12,86))
                self.membershipLabel=keep(at(UI:Label(p,"Group",12,"muted"),p,12,144))
                self.membership=keep(at(UI:Dropdown(p,398,{},action(function(id)
                    s:MoveGraph(E.libraryEditing.id,id~="ungrouped" and id or nil); E:Details("library")
                end)),p,12,170))
                self.quickIncluded=keep(at(UI:Switch(p,false,function(value)
                    local target=E.libraryEditing; s:SetQuickIncluded(target.kind,target.id,value)
                end),p,12,228))
                self.quickIncludedLabel=keep(at(UI:Label(p,"Include in Quick-Access",12,"text"),p,62,230))
                self.libraryNote=keep(at(UI:Label(p,"",12,"muted"),p,12,278)); M.Size(self.libraryNote,398,96)
            end
            for _,widget in ipairs(self.libraryWidgets) do widget:Show() end
            self.libraryName:SetText(item.name)
            self.quickIncluded:SetValue(item.quickInclude==true)
            UI:AttachTooltip(self.quickIncluded,"Quick-Access inclusion",target.kind=="group" and "Show this group's switch. It affects ALL members, even hidden graphs; child inclusion is independent." or "Show this graph in Quick-Access. This does not enable or apply it.")
            self.membership:SetShown(target.kind=="graph"); self.membershipLabel:SetShown(target.kind=="graph")
            if target.kind=="graph" then
                local options={{value="ungrouped",label="Ungrouped"}}
                for _,folder in ipairs(s:Library()) do if folder.kind=="group" then options[#options+1]={value=folder.id,label=folder.label} end end
                self.membership:SetOptions(options); self.membership:SetValue(item.groupId or "ungrouped")
                self.libraryNote:SetText("The switch in the tree controls this graph. A disabled group pauses execution without changing that switch.\n\nOnly applied snapshots run. Selecting or renaming a graph never applies its draft.")
                local remove=button("deleteGraph","Delete graph...",12,390,function()
                    E.deleteTarget={id=target.id,record=item}; E:Details("deleteGraph")
                end)
                M.Width(remove,190); remove:SetLabelText("Delete graph...")
            else
                self.libraryNote:SetText("Use the group switch in the tree to pause or resume its enabled graphs together.\n\nDrag a graph onto a group, or use the graph context menu to assign its group.")
            end
        elseif mode=="deleteGroup" then
            local target=self.deleteTarget
            assert(target and s:Store().groups[target.id]==target.record,"Group changed; reopen deletion")
            self.detailTitle:SetText("Delete group?"); self.detailText:SetText(target.record.name)
            if not self.deleteNote then self.deleteNote=at(UI:Label(p,"",13,"text"),p,12,16); M.Size(self.deleteNote,398,200) end
            self.deleteNote:SetText("Move this group's graphs to Ungrouped. Graphs, snapshots and history are preserved. Enabled graphs may resume running.\n\nDeleting the group cannot be undone."); M.Height(self.deleteNote,142); self.deleteNote:Show()
            local remove=button("confirmDeleteGroup","Delete group",12,178,function()
                if E.detailMode=="deleteGroup" and E.deleteTarget==target and s:DeleteGroup(target.id,target.record) then E.details:Hide() end
            end); M.Width(remove,190); remove:SetLabelText("Delete group")
            button("cancelDeleteGroup","Cancel",216,178,function() E.details:Hide() end)
        elseif mode=="deleteGraph" then
            local target=self.deleteTarget
            assert(target and s:Store().graphs[target.id]==target.record,"Graph changed; reopen its properties")
            self.detailTitle:SetText("Delete graph?")
            self.detailText:SetText(target.record.name)
            if not self.deleteNote then
                self.deleteNote=at(UI:Label(p,"",13,"text"),p,12,16); M.Size(self.deleteNote,398,200)
            end
            self.deleteNote:SetText("Delete this graph, its draft, applied snapshot and history. Its live output and test stop.\n\nOther graphs and shared layout anchors are preserved. This cannot be undone."); M.Height(self.deleteNote,142)
            self.deleteNote:Show()
            local remove=button("confirmDelete","Delete graph",12,178,function()
                if E.detailMode=="deleteGraph" and E.deleteTarget==target then s:DeleteGraph(target.id,target.record) end
            end)
            M.Width(remove,190); remove:SetLabelText("Delete graph")
            button("cancelDelete","Cancel",216,178,function() E:Details("library") end)
        elseif mode=="node" then
            local n=self:Graph().nodes[self.focusNode]
            if not n then self.details:Hide(); self.refreshing=false; return end
            local def=G.Definition(s.catalog[n.type],n) or s.catalog[n.type]; self.detailTitle:SetText(def.label.." / "..n.id)
            self.detailText:SetText("Changes remain in the draft until Save. Connected values are read-only.")
            if n.type=="glow" then self.detailText:SetText("Hex: RRGGBB[AA]. Scale/speed: icons. Pulse: both media.\nScroll for offsets, pulse and styles. Changes need Save.") end
            if def.logic then self.detailText:SetText("Unavailable is not false. Details help: hover the node's ...\nType/count changes keep existing connections or are rejected.") end
            local slot,y=0,10
            local inputs=G.Ports(def)
            for _,field in ipairs(def.fields or {}) do if field.primary then
                slot=slot+1;self:ShowField(self:Field(p,slot),p,{id=n.id,key=field.key,label=field.label,type=field.type,choices=field.choices,choiceLabels=field.choiceLabels,config=true},n.config[field.key]==nil and field.default or n.config[field.key],10,y,230,s.inspectApplied);y=y+36
            end end
            for _,key in ipairs(G.Ordered(inputs)) do local field=inputs[key]
                if not field.wire then
                    slot=slot+1; local value=n.values[key]; if value==nil then value=field.default end
                    self:ShowField(self:Field(p,slot),p,{id=n.id,key=key,label=field.label,type=field.type,picker=field.picker},value,10,y,230,G.Binding(self:Graph(),n.id,key)~=nil or s.inspectApplied)
                    y=y+36
                    if field.advanced then
                        local k=key; local b=self.expose[key]
                        if not b then b=UI:Switch(p,false,function(v)
                            s:Edit(function(g) local node=g.nodes[E.focusNode]; assert(not G.Binding(g,node.id,k),"Connected ports must remain visible"); node.exposed[k]=v end)
                        end); b.caption=UI:Label(p,"Show on node",11,"muted"); self.expose[key]=b end
                        at(b,p,106,y); at(b.caption,p,150,y+2); b:SetValue(n.exposed[key]==true); b:Show(); b.caption:Show()
                        if G.Binding(self:Graph(),n.id,key) or s.inspectApplied then b:Disable() else b:Enable() end; y=y+28
                    end
                end
            end
            for _,field in ipairs(def.fields or {}) do if not field.primary then slot=slot+1
                self:ShowField(self:Field(p,slot),p,{id=n.id,key=field.key,label=field.label,type=field.type,choices=field.choices,choiceLabels=field.choiceLabels,picker=field.picker,options=field.options,config=true},n.config[field.key]==nil and field.default or n.config[field.key],10,y,230,s.inspectApplied); y=y+36
            end end
            if def.selectableOutputs and type(def.outputSelectionKey)=="string" then
                if not self.outputChoiceTitle then self.outputChoiceTitle=UI:Label(p,"Visible outputs",12,"text") end
                if not self.outputFilter then
                    self.outputFilterLabel=UI:Label(p,"Find outputs",11,"muted")
                    self.outputFilter=UI:Input(p,280); self.outputFilter:SetMaxLetters(80)
                    self.outputFilter:SetScript("OnTextChanged",function()
                        if E.refreshing then return end
                        E.detailForm.slider:SetValue(0); E:Details("node",E.focusNode)
                    end)
                    self.outputFilter:HookScript("OnEditFocusGained",function() E.textFocus=true end)
                    self.outputFilter:HookScript("OnEditFocusLost",function() E.textFocus=false end)
                    UI:AttachTooltip(self.outputFilter,"Find outputs","Filter by label or output key. Hidden matches keep their selections and connections.")
                end
                local context=table.concat({ns.Settings.db.activeProfile,s:Graph().id,n.id},":")
                if self.outputFilterContext~=context then self.outputFilter:SetText(""); self.outputFilterContext=context end
                at(self.outputChoiceTitle,p,10,y+2); M.Size(self.outputChoiceTitle,380,20); self.outputChoiceTitle:Show(); y=y+28
                at(self.outputFilterLabel,p,10,y+7); M.Size(self.outputFilterLabel,90,18); self.outputFilterLabel:Show()
                at(self.outputFilter,p,106,y); self.outputFilter:Show(); y=y+36
                local query=self.outputFilter:GetText():lower():match("^%s*(.-)%s*$")
                local matched,total=0,0
                local connected={}
                for _,edge in ipairs(self:Graph().edges) do if edge.from==n.id then connected[edge.output]=true end end
                local selected=n.config[def.outputSelectionKey] or {}
                for _,key in ipairs(G.Ordered(def.selectableOutputs)) do
                    local port=def.selectableOutputs[key]; total=total+1
                    if query=="" or key:lower():find(query,1,true) or (port.label or key):lower():find(query,1,true) then
                    matched=matched+1; local choice=self.outputChoices[key]
                    if not choice then
                        choice=UI:Switch(p,false,action(function(value)
                            local binding=E.outputChoices[key]
                            if binding.nodeId then E:SetOutputSelected(binding.nodeId,key,value) end
                        end))
                        choice.caption=UI:Label(p,"",11,"text"); choice.caption:SetWordWrap(false)
                        self.outputChoices[key]=choice
                    end
                    choice.nodeId=n.id; at(choice,p,10,y); at(choice.caption,p,58,y+3); M.Size(choice.caption,330,18)
                    choice.caption:SetText(port.label or key); choice:SetValue(selected[key]==true or connected[key]==true)
                    local locked=s.inspectApplied or connected[key]==true or (port.disabled and not selected[key])
                    if locked then choice:Disable() else choice:Enable() end
                    local reason=s.inspectApplied and "Applied view is read-only. Leave Applied view to change outputs."
                        or connected[key] and "Connected output. Disconnect its wires before hiding it."
                        or port.disabled and "Available only when Unit is Player. Existing selected outputs can be removed."
                        or "Show or hide this output on the node. Changes remain in the draft until Save."
                    UI:AttachTooltip(choice,port.label or key,reason.."\nType: "..(port.type or "value")..(port.maySecret and "\nAvailability is checked per field; secret values are not inferred." or ""))
                    choice:Show(); choice.caption:Show(); y=y+26
                    end
                end
                self.outputChoiceTitle:SetText("Visible outputs ("..matched.." / "..total..")")
            elseif self.outputFilter then
                self.outputFilter:ClearFocus(); self.outputFilter:Hide(); self.outputFilterLabel:Hide(); self.outputFilterContext=nil
            end
            slot=slot+1; self:ShowField(self:Field(p,slot),p,{id=n.id,key="title",label="Node title",type="string",title=true},n.title or "",10,y,230,s.inspectApplied); y=y+36
            if def.interactionProducer then
                for index,field in ipairs(n.config.payload or {}) do
                    local fieldId=field.id
                    slot=slot+1;self:ShowField(self:Field(p,slot),p,{id=n.id,key=fieldId,label="Payload "..index,type="string",clickPayload=fieldId},field.label,10,y,230,s.inspectApplied);y=y+36
                    slot=slot+1;self:ShowField(self:Field(p,slot),p,{id=n.id,key=fieldId.."Type",label="Value type",choices={"string","float","integer","boolean"},choiceLabels={string="String",float="Number",integer="Integer",boolean="Boolean"},clickPayload=fieldId,payloadAction="type"},field.type,10,y,230,s.inspectApplied);y=y+36
                    local remove=button("payloadRemove"..fieldId,"Remove value",10,y,function()s:ClickPayload(n.id,"remove",fieldId)end)
                    if s.inspectApplied then remove:Disable() else remove:Enable() end;y=y+40
                end
                local add=button("payloadAdd","+ Payload value",10,y,function()s:ClickPayload(n.id,"add")end)
                if s.inspectApplied or #(n.config.payload or {})>=8 then add:Disable() else add:Enable() end;y=y+42
                UI:AttachTooltip(add,"Click payload","Values are captured from the clicked element. Matching Media event nodes receive these fields automatically. Disconnect fields before changing their type or removing them.")
            end
            if def.displayStack then
                local choices,labels={},{}
                for _,element in ipairs(n.config.elements) do choices[#choices+1]=element.id;labels[element.id]=element.label end
                slot=slot+1;self:ShowField(self:Field(p,slot),p,{id=n.id,key="rootElement",label="Root element",choices=choices,choiceLabels=labels,stackElement=true,stackAction="root"},n.config.rootElement,10,y,230,s.inspectApplied);y=y+36
                for index,element in ipairs(n.config.elements) do
                    local elementId=element.id
                    slot=slot+1;self:ShowField(self:Field(p,slot),p,{id=n.id,key=elementId,label="Media "..index,type="string",stackElement=elementId},element.label,10,y,170,s.inspectApplied);y=y+32
                    local up=button("stackUp"..elementId,"Up",10,y,function()s:StackElement(n.id,"move",elementId,-1)end)
                    local down=button("stackDown"..elementId,"Down",110,y,function()s:StackElement(n.id,"move",elementId,1)end)
                    local remove=button("stackRemove"..elementId,"Remove",210,y,function()s:StackElement(n.id,"remove",elementId)end)
                    M.Width(up,90);M.Width(down,90);M.Width(remove,110)
                    if s.inspectApplied or index==1 then up:Disable() else up:Enable() end
                    if s.inspectApplied or index==#n.config.elements then down:Disable() else down:Enable() end
                    if s.inspectApplied or elementId==n.config.rootElement then remove:Disable() else remove:Enable() end
                    y=y+36
                end
                local add=button("stackAdd","+ Media input",10,y,function()s:StackElement(n.id,"add")end)
                if s.inspectApplied or #n.config.elements>=8 then add:Disable() else add:Enable() end
                y=y+42
            end
            if def.source then button("test","Test signals",10,y+8,function() E:Details("test") end) end
            if def.display or (def.layoutOwner and n.config.position=="layout") then
                local layoutButton=button("layoutIcon","Position / size",10,y+8,function() s:LayoutIcon(n.id) end)
                M.Width(layoutButton,210); layoutButton:SetLabelText("Position / size")
                UI:AttachTooltip(layoutButton,"Position / anchors","Open the shared Layout Editor. Anchor this icon to any element, chain icons, and configure its inactive footprint under Preferences. Save & exit persists the layout with its graph.")
                if n.type=="icon" and not s.inspectApplied then
                    button("convertMedia","Convert to media",10,y+46,function() s:ConvertIcon(n.id); E:Details("node",n.id) end)
                end
            end
            if def.count and (def.maxCount or def.count>1) then
                local add=button("addLogicInput","+ Input",10,y+8,function() s:SetValue(n.id,"count",math.min(16,def.count+1),true) end)
                local remove=button("removeLogicInput","- Last input",164,y+8,function() s:SetValue(n.id,"count",math.max(def.minCount or 2,def.count-1),true) end)
                if s.inspectApplied or def.count>=16 then add:Disable() else add:Enable() end
                if s.inspectApplied or def.count<=(def.minCount or 2) then remove:Disable() else remove:Enable() end
                y=y+52
            end
            if def.soundSink then
                self.detailText:SetText(n.config.source=="sharedmedia" and "SharedMedia files use the selected channel's game volume. Preview plays the draft locally." or "Volume applies to this SoundKit playback. Preview plays the draft locally.")
                local graph=s:Graph()
                button("soundPreview","Preview sound",10,y+8,function()
                    if E.detailMode~="node" or E.focusNode~=n.id or s:Graph()~=graph then return end
                    local current=E:Graph().nodes[n.id]
                    if not current or current.type~="play_sound" then return end
                    local ok,status=ns.Sound:Play(E,"preview",current.config)
                    E.detailText:SetText((ok and "Preview: " or "Preview unavailable: ")..status)
                end)
                button("soundStop","Stop preview",164,y+8,function() ns.Sound:Release(E);E.detailText:SetText("Preview stopped.") end)
                y=y+52
            end
            local height=math.max(100,y+((def.display or def.layoutOwner) and 94 or def.source and 52 or 10))
            self.nodeContentHeight=math.min(420,height); M.Height(self.detailForm,self.nodeContentHeight); M.Height(self.detailForm.slider,self.nodeContentHeight)
            M.Height(p,height); self.detailForm:SetContentHeight(height)
        elseif mode=="picker" then
            local binding=self.pickerBinding
            assert(binding and self.pickerGraph==s:Graph().id and not s.inspectApplied,"Selector context changed")
            local selected=s:Draft().nodes[binding.id]
            self.detailTitle:SetText(selected and s.catalog[selected.type].secureAction and "Choose self-cast spell" or "Choose player aura")
            self.detailText:SetText("Search names or partial Spell IDs. Best matches appear first.\nIcons, rank and game text load automatically for visible results.")
            if not self.pickerView then
                self.pickerView=at(UI:LookupPicker(p,398),p,10,10)
                self.pickerInput=self.pickerView.input; self.pickerButtons=self.pickerView.buttons
                self.pickerNote=self.pickerView.note; self.pickerPages=self.pickerView.pages
                self.pickerWidgets={self.pickerView}
                self.pickerInput:HookScript("OnEditFocusGained",function() E.textFocus=true end)
                self.pickerInput:HookScript("OnEditFocusLost",function() E.textFocus=false end)
            end
            self.pickerSearch=s:Picker(binding.id,binding.key); self.pickerPage=1
            local pickerSession=self.pickerSearch
            self.pickerView:Open(self.pickerSearch,action(function(entry)
                local b=E.pickerBinding
                if E.pickerSearch~=pickerSession or not pickerSession:Valid() or E.pickerGraph~=s:Graph().id or E.detailMode~="picker" then return end
                if s:Pick(b.id,b.key,entry) then E:Details("node",b.id) end
            end),function() E:Details("node",binding.id) end)
            self:PickerResults(true)
            button("refreshPicker","Refresh auras",10,462,function() E:Details("picker",binding.id) end)
            button("backPicker","Back",165,462,function() E:Details("node",binding.id) end)
        elseif mode=="itempicker" then
            local binding=self.pickerBinding
            assert(binding and self.pickerGraph==s:Graph().id and not s.inspectApplied,"Selector context changed")
            self.detailTitle:SetText("Choose carried item")
            self.detailText:SetText("Search items in bags 0–4 and equipment. No bank or global item scan.\nUse the node's numeric Item ID for items outside this snapshot.")
            if not self.itemView then
                self.itemView=at(UI:ItemPicker(p,398),p,10,10)
                self.itemView.input:HookScript("OnEditFocusGained",function()E.textFocus=true end)
                self.itemView.input:HookScript("OnEditFocusLost",function()E.textFocus=false end)
            end
            local session=s:ItemPicker(binding.id,binding.key)
            self.itemView:Open(session,action(function(entry)
                if E.detailMode=="itempicker" and E.itemView.session==session and session:Choose(entry)then E:Details("node",binding.id)end
            end),function()E:Details("node",binding.id)end)
            button("refreshItems","Refresh items",10,462,function()E:Details("itempicker",binding.id)end)
            button("backItems","Back",165,462,function()E:Details("node",binding.id)end)
        elseif mode=="iconpicker" then
            local binding=self.pickerBinding
            assert(binding and self.pickerGraph==s:Graph().id and not s.inspectApplied,"Selector context changed")
            self.detailTitle:SetText("Icon catalog")
            self.detailText:SetText("Choose the icon for this node.\nChanges stay in the draft until Save.")
            if not self.iconView then
                self.iconView=at(UI:IconPicker(p,398),p,10,0)
                for _,input in ipairs({self.iconView.input,self.iconView.reference}) do
                    input:HookScript("OnEditFocusGained",function() E.textFocus=true end)
                    input:HookScript("OnEditFocusLost",function() E.textFocus=false end)
                end
                self.iconView:HookScript("OnShow",function()
                    -- Minimizing releases the session via OnHide. Restore lazily.
                    if E.detailMode=="iconpicker" and not E.iconView.session then
                        local b=E.pickerBinding
                        E.iconView:Open(s:IconPicker(b and b.id,b and b.key),function() E.details:Hide() end,
                            b and function() E.details:Hide() end or nil)
                    end
                end)
            end
            self.iconView:Open(s:IconPicker(binding and binding.id,binding and binding.key),function() E.details:Hide() end,
                binding and function() E.details:Hide() end or nil)
            button("closeIcons","Close",10,474,function() if binding then E:Details("node",binding.id) else E.details:Hide() end end)
        elseif mode=="errors" then
            self.detailTitle:SetText("Graph diagnostics")
            self.detailText:SetText("Bounded log; repeated faults are counted. Retry does not replay lost events.")
            if not self.logText then self.logText=at(UI:Label(p,"",11,"text"),p,10,10); M.Width(self.logText,400); M.Height(self.logText,400) end
            self.logText:SetText(s:ErrorsText()); self.logText:Show()
            button("retry","Retry faults",10,450,function() s:Retry(); E:Details("errors") end)
        end
        if mode~="test" then
            for _,f in pairs(self.testFields or {}) do f.label:Hide(); f.input:Hide() end
            if self.contextSelect then self.contextSelect:Hide(); self.contextLabel:Hide() end
            if self.auraSelect then self.auraSelect:Hide(); self.auraLabel:Hide(); self.auraTestNote:Hide() end
            if self.secretHP then self.secretHP:Hide(); self.secretHPLabel:Hide(); self.secretAura:Hide(); self.secretAuraLabel:Hide() end
        end
        if mode~="errors" and self.logText then self.logText:Hide() end
        if mode~="deleteGraph" and mode~="deleteGroup" and self.deleteNote then self.deleteNote:Hide() end
        finishFields(self.detailRows); self.refreshing=false
        local contentHeight=mode=="node" and self.nodeContentHeight or ({deleteGraph=218,deleteGroup=218,debug=182,test=424,library=434,settings=446,communication=480,picker=504,itempicker=504,iconpicker=516,errors=492})[mode] or 300
        if mode~="node" then M.Height(p,contentHeight) end
        self.details:FitContent(460,44+56+contentHeight+18)
        self.details:Show()
        UI:FocusWindow(self.details)
        if mode=="picker" and self.pickerSearch:Status().ready then self.pickerInput:SetFocus() end
    end
    function E:Key(key)
        if w.minimized and key~="ESCAPE" then return false end
        if key=="ESCAPE" and self.search and self.search:IsShown() then self.search:Hide(); return true end
        if self.textFocus or UI:TextInputFocused() or (self.search and self.search:IsShown()) or (UI.dropdown and UI.dropdown:IsShown()) then self.space=false; return false end
        if key=="SPACE" then
            self.space=UI:PointerWithin(self.canvas) and not (self.details and self.details:IsShown()) and not InCombatLockdown()
            return self.space
        end
        if key=="ESCAPE" then
            if self.placing or self.wire or self.pointer then self:Cancel()
            elseif self.details and self.details:IsShown() then self.details:Hide() else self:Close() end
            return true
        end
        if s.inspectApplied then return false end
        if key=="DELETE" then s:Edit(function(g) G.Remove(g,self.selected) end); self.selected={}; return true end
        if IsControlKeyDown() then
            if key=="Z" then s:Undo(IsShiftKeyDown()); return true end
            if key=="Y" then s:Undo(true); return true end
            if key=="C" then self.clipboard=G.Fragment(s:Draft(),self.selected); return true end
            if key=="V" and self.clipboard then self:Cancel(); self.placing={fragment=self.clipboard}; self.ghostLabel:SetText("Paste node group"); self:Track(); return true end
            if key=="A" then for id in pairs(s:Draft().nodes) do self.selected[id]=true end; self:Render(); return true end
        end
        return false
    end
    w:EnableKeyboard(not InCombatLockdown()); UI:SetKeyboardPropagation(w,true)
    w:SetScript("OnKeyDown",action(function(_,key) if not InCombatLockdown() then UI:SetKeyboardPropagation(w,not E:Key(key)) end end))
    w:SetScript("OnKeyUp",function(_,key)
        if key=="SPACE" then if E.pointer and E.pointer.spacePan then E:Release(E.pointer.button) end; E.space=false end
        UI:SetKeyboardPropagation(w,true)
    end)
    function E:Open()
        local data=G.Copy(s:Store().window)
        while w.minimized or w.maximized do w:Restore() end
        windowSize(w,data.width or 1220,data.height or 760)
        if data.x and data.y then w:ClearAllPoints(); w:SetPoint("CENTER",UIParent,"CENTER",data.x/w:GetScale(),data.y/w:GetScale()) end
        self.profile=ns.Settings.db.activeProfile; self:LoadView(); self:Layout(); w:Show()
        w:EnableKeyboard(not InCombatLockdown()); UI:SetKeyboardPropagation(w,true)
        UI:FocusWindow(w)
        ns.Events:Release(self)
        ns.Events:Subscribe(self,"GLOBAL_MOUSE_UP",function(_,button) E:ReleaseWire(button); E:Release(button) end)
        ns.Events:Subscribe(self,"GLOBAL_MOUSE_DOWN",function() if not UI:PointerWithin(E.canvas) or UI:TextInputFocused() then E.space=false end end)
        ns.Events:Subscribe(self,"PLAYER_REGEN_DISABLED",function() E:Cancel(); UI:CloseDropdown(); w:EnableKeyboard(false); s.message="Combat: editing/debug available; Save disabled"; E:Debug() end)
        ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function() UI:SetKeyboardPropagation(w,true); w:EnableKeyboard(true); s.message="Combat ended: Save available (not automatic)"; E:Debug() end)
        if not self.debugTimer then self.debugTimer=C_Timer.NewTicker(.2,function()
            if E.profile~=ns.Settings.db.activeProfile then E:Close(); return end
            E.dirtyDebug=false; E:Debug()
        end) end
    end
    function E:Close() w:Hide() end
    local function watchMedia()
        if ns.Media.Subscribe then ns.Media:Subscribe(E,function()
            if body:IsVisible() and not E.textFocus then E:Refresh() end
        end) end
    end
    body:HookScript("OnShow",watchMedia)
    w:HookScript("OnShow",watchMedia)
    body:HookScript("OnHide",function()
        if ns.Media.Unsubscribe then ns.Media:Unsubscribe(E) end
        if w.minimized then
            E:Cancel(); E.space=false; E.textFocus=false
            E.budget:ClearFocus()
            if E.details then E.details:Hide() end
            if E.wiki then E.wiki:Hide();E.wikiBinding=nil end
            UI:CloseDropdown()
        end
    end)
    w:HookScript("OnHide",function()
        if ns.Media.Unsubscribe then ns.Media:Unsubscribe(E) end
        E:Cancel(); E.space=false; E.textFocus=false; ns.Events:Release(E)
        for _,card in pairs(E.cards) do clearDebugCard(card) end
        if E.debugTimer then E.debugTimer:Cancel(); E.debugTimer=nil end
        if E.details then E.details:Hide() end
        if E.wiki then E.wiki:Hide();E.wikiBinding=nil end
        s:EndTest()
    end)
    return E
end

function UI:AuraStudioPage(parent,s)
    if s.page then return s.page end
    local page=UI:Panel(parent,880,390,"surface"); at(page,parent,0,0); UI:HideSurface(page); s.page=page
    local overview=CreateFrame("Frame",nil,page); at(overview,page,0,0)
    local helpPage=CreateFrame("Frame",nil,page); at(helpPage,page,0,0); helpPage:Hide()
    local workspace=UI:Section(overview,"Graph workspace",430,210,"tree")
    local intro=at(UI:Label(workspace,"Build reactive graphs from sources, conditions and actions.",13,"muted"),workspace,16,58)
    local graphSummary=at(UI:Label(workspace,"",12,"muted"),workspace,16,110)
    at(UI:Button(workspace,"Open AuraStudio",190,function() s:Open() end,true),workspace,16,148)
    local execution=UI:Section(overview,"Execution",430,210,"play")
    at(UI:Label(execution,"Enable module",14,"text"),execution,16,64)
    page.enabled=UI:Switch(execution,false,function(v) ns.Modules:SetEnabled("aura_studio",v); page:Refresh() end)
    local executionHelp=at(UI:Label(execution,"Live execution is enabled separately for each graph. You can edit graphs and send test signals while the module is disabled.",13,"muted"),execution,16,110)
    local workflow=UI:Section(overview,"Workflow",880,160,"grid")
    local workflowText=at(UI:Label(workflow,"1. Build your graph and configure its sources.\n2. Use Freeze or Test Mode on supported nodes, then Save.\n3. Enable the module and the graph in the tree. Its group must be enabled too.",13,"muted"),workflow,16,58)
    local editing=UI:Section(helpPage,"Connections & editing",880,300,"tree")
    local editingText=at(UI:Label(editing,"CONNECT\nDrag from an output point to an input point, or click the two points.\n\nREWIRE & REMOVE\nDrag a connected input to another input. Drop on empty canvas or right-click the connected input to remove its connection. Escape cancels.\n\nAPPLIED VIEW\nThis shows the applied snapshot. Turn Applied view off to edit the draft.",13,"muted"),editing,16,56)
    local testing=UI:Section(helpPage,"Apply & test",880,160,"play")
    local testingText=at(UI:Label(testing,"Draft edits do not change a running graph until you Apply. Test signals are local samples and do not require live execution.\n\n/bv aura opens the editor directly.",13,"muted"),testing,16,56)
    page.navigation={definitions={{id="overview",label="Overview",icon="grid"},{id="help",label="Usage",icon="info"}},selected="overview"}
    page.navigation.select=function(id)
        if id~="overview" and id~="help" then return end
        page.navigation.selected=id; overview:SetShown(id=="overview"); helpPage:SetShown(id=="help")
        if ns.Config.window then ns.Config.pageScroll:SetValue(0); ns.Config:Layout() end
    end
    local function card(frame,x,y,width,height)
        at(frame,frame:GetParent(),x,y); UI:ResizeSection(frame,width,height)
    end
    function page:Arrange(width)
        local two=width>=760; local column=two and (width-16)/2 or width
        card(workspace,0,0,column,210); card(execution,two and column+16 or 0,two and 0 or 226,column,210)
        local workflowY=two and 226 or 452; card(workflow,0,workflowY,width,160)
        M.Size(intro,column-32,44); M.Size(graphSummary,column-32,24)
        at(self.enabled,execution,column-52,65); M.Size(executionHelp,column-32,80)
        M.Size(workflowText,width-32,88); M.Size(overview,width,workflowY+160)
        card(editing,0,0,width,340); M.Size(editingText,width-32,260)
        card(testing,0,356,width,180); M.Size(testingText,width-32,108); M.Size(helpPage,width,536)
        local height=self.navigation.selected=="help" and 536 or workflowY+160
        M.Size(self,width,height); return height
    end
    function page:Refresh()
        self.enabled:SetValue(s.active==true)
        local count=0; for _ in pairs(s:Store().graphs) do count=count+1 end
        graphSummary:SetText(count..(count==1 and " graph in this profile" or " graphs in this profile"))
        if s.editor and s.editor.profile~=ns.Settings.db.activeProfile then s.editor:Close() end
    end
    page:Arrange(880); page:Refresh(); return page
end

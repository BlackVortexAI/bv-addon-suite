local _, A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local G,R=A.G,A.Runtime
local S={nodeTesting=A.NodeTesting,catalog=A.catalog,catalogOrder=A.order,runs={},queue={},errors={},histories={},budget=1,maxQueue=128,maxInteractions=16,source=A.AuraSource.New()}
ns.AuraStudio=S
local function displayElements(node)
    if A.catalog[node.type] and A.catalog[node.type].displayStack then return node.config.elements or {} end
    return {{id=node.id,layoutId=node.config.layoutId}}
end
function S:UnitReference(token)
    self.unitRefs=self.unitRefs or {};self.unitGenerations=self.unitGenerations or {}
    local old=self.unitRefs[token];local generation=self.unitGenerations[token] or 0
    if not old or G.Object(old,"unitref").generation~=generation then
        self.unitSerial=(self.unitSerial or 0)+1
        old=G.CaptureObject({unit=token,generation=generation,id=token..":"..generation,appearance=self.unitSerial},"unitref")
        self.unitRefs[token]=old
    end
    return old
end
function S:RefreshBindings(run)
    run.bindings=run.bindings or {}
    if not run.collection then return end
    local tokens={};for token in pairs(run.collectionTokens or {}) do tokens[#tokens+1]=token end;table.sort(tokens)
    for index,token in ipairs(tokens) do
        local plate=token:match("^nameplate%d+$")~=nil
        local present=run.test and tonumber(token:match("%d+$"))<=3 or self.visibleNameplates and self.visibleNameplates[token]==true
        local absent=plate and self.nameplateAbsent and self.nameplateAbsent[token]
        if not run.test and plate and not present and not absent and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
            local ok,frame=pcall(C_NamePlate.GetNamePlateForUnit,token);present=ok and not G.IsSecret(frame) and frame~=nil
        end
        if not run.test and not present and not absent and type(UnitExists)=="function" then
            local ok,value=pcall(UnitExists,token);present=ok and not G.IsSecret(value) and value==true
        end
        if present then
            if run.test then
                if not run.bindings[token] then
                    local ref=G.CaptureObject({unit=token,generation=0,id="test:"..token,appearance=index},"unitref")
                    run.bindings[token]={reference=ref,unit=token,generation=0,id="test:"..token,appearance=index}
                end
            else
                local ref=self:UnitReference(token);local data=G.Object(ref,"unitref")
                run.bindings[token]={reference=ref,unit=token,generation=data.generation,id=data.id,appearance=data.appearance}
            end
        else
            run.bindings[token]=nil
            if R.InvalidateInstance then R.InvalidateInstance(run,token) end
        end
    end
end

-- Documentation reads the selected graph without Store's profile migrations.
function S:Wiki(nodeId,topic)
    if G.IsSecret(nodeId) or type(nodeId)~="string" then return A.NodeWiki.Page(nil,topic) end
    local db=ns.Settings.db
    local profile=db and db.profiles and db.profiles[db.activeProfile]
    local store=profile and profile.modules and profile.modules.aura_studio
    local record=store and store.graphs and store.graphs[store.selected]
    local graph=record and (self.inspectApplied and record.applied or record.draft)
    return A.NodeWiki.Page(graph and graph.nodes and graph.nodes[nodeId],topic,graph)
end

function S:Store()
    local data=ns.Settings:Module("aura_studio")
    assert(not data.version or data.version==1,"Unsupported AuraStudio data version")
    data.version=1; data.graphs=data.graphs or {}; data.nextId=data.nextId or 1
    if type(data.nodePalette)~="table" then data.nodePalette={} end
    local palette=data.nodePalette
    if palette.mode~="alphabetical" and palette.mode~="categories" then palette.mode="categories" end
    if type(palette.collapsed)~="table" then palette.collapsed={} end
    for key,value in pairs(palette.collapsed) do if not ns.DesignSystem.categories[key] or value~=true then palette.collapsed[key]=nil end end
    for _,rec in pairs(data.graphs)do
        if rec.draft then rec.draft=A.MigrateGraph(A.Messaging.MigratePermissions(rec.draft,data.communication or {})) end
        if rec.applied then rec.applied=A.MigrateGraph(A.Messaging.MigratePermissions(rec.applied,data.communication or {})) end
    end
    -- Additive profile migration: existing graphs stay ungrouped and untouched.
    data.groups=data.groups or {}; data.nextGroupId=data.nextGroupId or 1
    data.budget=G.Number(data.budget) and math.max(.25,math.min(8,data.budget)) or 1
    data.window=data.window or {width=1220,height=760}
    local order,seen,missing={},{},{}
    for _,id in ipairs(data.graphOrder or {}) do if data.graphs[id] and not seen[id] then order[#order+1]=id; seen[id]=true end end
    for id,rec in pairs(data.graphs) do if not seen[id] then missing[#missing+1]={id=id,name=rec.name} end end
    table.sort(missing,function(a,b) local x,y=a.name:lower(),b.name:lower(); return x==y and a.id<b.id or x<y end)
    for _,rec in ipairs(missing) do order[#order+1]=rec.id end
    data.graphOrder=order
    data.quick=data.quick or {shown=false,width=280,height=360,collapsed={}}
    data.quick.collapsed=data.quick.collapsed or {}
    data.communication=data.communication or {send=false,receive=false,group=true,channels={PARTY=true,RAID=true,INSTANCE_CHAT=true},allowlist={}}
    return data
end
function S:Communication() return self:Store().communication end
function S:CommunicationPolicy()
    local receivers={}
    for _,run in pairs(self.runs)do
        if not run.stopped and not run.test then for id in pairs(run.plan.active)do
            local n=run.plan.graph.nodes[id]
            if n.type=="message_receive"and n.config.permission==true and n.config.channel~="LOCAL"then receivers[#receivers+1]=n.config end
        end end
    end
    local paused=self:Communication().paused==true
    return {nodePolicies=true,paused=paused,send=true,receive=not paused and #receivers>0,receivers=receivers}
end
function S:Interaction(owner,packet)
    if not self.active or not owner or owner.test or owner.stopped or self.runs[owner.graphId]~=owner or type(packet)~="table" then return false end
    for _,key in ipairs({"key","button","shift","control","alt"}) do if issecretvalue and issecretvalue(packet[key]) then return false end end
    if type(packet.key)~="string" or #packet.key<1 or #packet.key>40 or not packet.key:match("^[%w_.%-]+$")
        or not ({LeftButton=true,RightButton=true,MiddleButton=true,Button4=true,Button5=true})[packet.button]
        or type(packet.shift)~="boolean" or type(packet.control)~="boolean" or type(packet.alt)~="boolean" then return false end
    if not owner.interactionKeys or not owner.interactionKeys[packet.key] then return false end
    if packet.instance then
        local binding=G.Object(packet.instance,"unitref");local current=binding and owner.bindings and owner.bindings[binding.unit]
        if not current or current.reference~=packet.instance then return false end
    end
    if packet.payload~=nil and not ns.GraphValues.Accepts("click",packet.payload) then return false end
    return self:Schedule(owner,{interaction={key=packet.key,button=packet.button,shift=packet.shift,control=packet.control,alt=packet.alt,instance=packet.instance,payload=packet.payload}},"interaction")==true
end
function S:InvalidateMessages()
    -- Permission revocation also covers messages already accepted by transport.
    -- Clear pending work for externally influenced receiver graphs before a
    -- neutral observation removes old values/timer controls from those paths.
    for _,run in pairs(self.runs) do
        local external=false
        for id in pairs(run.plan.active) do
            local n=run.plan.graph.nodes[id]
            if n.type=="message_receive" and n.config.channel~="LOCAL" then external=true end
        end
        if external then
            for i=#self.queue,1,-1 do if self.queue[i].run==run then table.remove(self.queue,i) end end
            self:Schedule(run,{},"message_reset")
        end
    end
end
function S:RefreshMessaging()
    if not self.active then return end
    -- Rebuild node permissions on lifecycle/apply/pause changes, not per packet.
    -- Current group membership is still checked at reception.
    self.messagePolicy=self:CommunicationPolicy()
    if not self.messaging then
        self.messaging=A.Messaging.New(_G,ns.Events,function(packet)
            local key=packet.topic..":"..packet.kind..":"..packet.channel
            for _,run in pairs(self.runs) do if run.messageTopics and run.messageTopics[key] then self:Schedule(run,{message=packet},"message") end end
        end,function() return self.messagePolicy end,function()
            for _,run in pairs(self.runs) do if run.needs.message_send then self:Schedule(run,{},"message_policy") end end
        end)
    end
    local ok,status=self.messaging:Start()
    if not ok then self:Diagnostic("communication","registration",status) end
    for _,run in pairs(self.runs) do if run.needs.message_send then self:Schedule(run,{},"message_policy") end end
end
function S:SetCommunication(key,value)
    assert(key=="paused","Unknown communication setting")
    if InCombatLockdown() then self.message="Change communication settings after combat";self:Changed();return false end
    self:Communication()[key]=value==true;self:InvalidateMessages();self:RefreshMessaging();self:Changed();return true
end
function S:Graph()
    local store=self:Store(); return store.graphs[store.selected]
end
function S:Draft() local record=self:Graph(); return record and record.draft end
function S:List()
    local out={}; for id,g in pairs(self:Store().graphs) do out[#out+1]={value=id,label=g.name} end
    table.sort(out,function(a,b)return a.value<b.value end); return out
end
function S:GroupAllows(rec)
    local group=rec.groupId and self:Store().groups[rec.groupId]
    return not group or group.enabled~=false
end
function S:Unsaved(rec)
    rec=rec or self:Graph()
    if not rec then return false end
    local draft,applied=G.Copy(rec.draft),G.Copy(rec.applied or G.New())
    draft.view=nil;applied.view=nil
    return not ns.DisplayModel.Equal(draft,applied)
end
function S:CopyGraph(id)
    local rec=assert(self:Store().graphs[id],"Unknown graph")
    self.graphClipboard={name=rec.name,graph=G.Copy(rec.draft),layout=G.Copy(rec.displayLayout)}
end
function S:PasteGraph(targetID,after)
    assert(self.graphClipboard,"Copy a graph first")
    local data=self:Store();local target=assert(data.graphs[targetID],"Unknown target")
    local copy=G.Copy(self.graphClipboard)
    local id=self:New(false);local rec=data.graphs[id]
    rec.name=(copy.name:sub(1,70).." copy");rec.draft=copy.graph;rec.displayLayout=copy.layout
    local original=G.Copy(rec.draft)
    self:PrepareDisplays(rec.draft,rec)
    local remap={}
    for nodeID,node in pairs(rec.draft.nodes) do
        if A.catalog[node.type] and (A.catalog[node.type].display or A.catalog[node.type].layoutOwner) then
            local before=displayElements(original.nodes[nodeID])
            for index,element in ipairs(displayElements(node)) do
                if before[index].layoutId then remap[before[index].layoutId]=element.layoutId end
            end
        end
    end
    local stored=ns.Layout:Store()
    for _,id in pairs(remap) do
        local raw=stored[id]
        if raw then
            if raw.link and remap[raw.link.target] then raw.link.target=remap[raw.link.target] end
            for _,key in ipairs({"widthTarget","heightTarget","templateId","templateRoot"}) do if remap[raw[key]] then raw[key]=remap[raw[key]] end end
        end
    end
    ns.DisplayAnchors:Sync();self:CaptureLayouts()
    self:MoveGraph(id,target.groupId,targetID,after,data)
    self:Select(id);return id
end
function S:Library(quick)
    local data=self:Store(); local roots,byID={},{}
    for id,group in pairs(data.groups) do
        local item={id=id,label=group.name,kind="group",children={}}
        if not quick or group.quickInclude==true then item.enabled=group.enabled~=false end
        item.toggleHelp="Enable or pause ALL members, including graphs hidden from Quick-Access. Individual switches are preserved."
        roots[#roots+1]=item; byID[id]=item
    end
    local function order(a,b) local x,y=a.label:lower(),b.label:lower(); return x==y and a.id<b.id or x<y end
    table.sort(roots,order)
    local loose={id="ungrouped",label="Ungrouped",kind="folder",children={}}
    roots[#roots+1]=loose
    for _,id in ipairs(data.graphOrder) do
        local rec=data.graphs[id]
        if not quick or rec.quickInclude==true then
        local parent=byID[rec.groupId] or loose
        parent.children[#parent.children+1]={id=id,parentId=rec.groupId,label=rec.name,kind="graph",changed=not quick and self:Unsaved(rec),enabled=rec.enabled==true,
            blocked=rec.enabled and (not self.active or not self:GroupAllows(rec)),running=self.runs[id]~=nil}
        end
    end
    if quick then for i=#roots,1,-1 do if roots[i].enabled==nil and #roots[i].children==0 then table.remove(roots,i) end end end
    return roots
end
local function libraryName(name)
    assert(type(name)=="string","Enter a name")
    name=name:match("^%s*(.-)%s*$")
    assert(#name>0 and #name<=80 and not name:find("[%c|]"),"Use 1..80 characters without control codes or |")
    return name
end
function S:NewGroup()
    local data=self:Store(); local count=0; for _ in pairs(data.groups) do count=count+1 end
    assert(count<32,"Group limit reached (32 per profile)")
    local id,name
    repeat
        id="folder"..data.nextGroupId; name="Group "..data.nextGroupId; data.nextGroupId=data.nextGroupId+1
        local duplicate=false; for _,g in pairs(data.groups) do if g.name:lower()==name:lower() then duplicate=true end end
        if not data.groups[id] and not duplicate then break end
    until false
    data.groups[id]={id=id,name=name,enabled=true}; self:Changed(); return id
end
function S:Rename(kind,id,name)
    name=libraryName(name)
    local collection=kind=="group" and self:Store().groups or self:Store().graphs
    local rec=assert(collection[id],"Unknown library item")
    for key,other in pairs(collection) do assert(key==id or other.name:lower()~=name:lower(),"That name is already in use") end
    rec.name=name; self:Changed(); return true
end
-- One activation transaction for a graph, group or membership change. Existing
-- runs keep gate state; only newly effective members get an initial observation.
function S:ChangeActivation(change)
    if InCombatLockdown() then self.message="Change graph activation after combat"; self:Changed(); return false end
    local data=self:Store(); local before,groupBefore={},{}
    for id,rec in pairs(data.graphs) do before[id]={enabled=rec.enabled,groupId=rec.groupId} end
    for id,group in pairs(data.groups) do groupBefore[id]={enabled=group.enabled} end
    local old=self.runs; local nextRuns,created={},{}; local sample
    local ok,why=pcall(function()
        change()
        for id,rec in pairs(data.graphs) do
            if self.active and rec.enabled and rec.applied and self:GroupAllows(rec) then
                if old[id] and not old[id].stopped then nextRuns[id]=old[id]
                else
                    local plan,err=G.Compile(rec.applied,A.catalog); assert(plan,err and err.message)
                    local run=self:MakeRun(rec,plan,false); nextRuns[id]=run; created[#created+1]=run
                end
            end
        end
        self.runs=nextRuns; self:Subscriptions()
        if #created>0 then sample=self:Sample() end
    end)
    if not ok then
        for id,values in pairs(before) do data.graphs[id].enabled=values.enabled; data.graphs[id].groupId=values.groupId end
        for id,values in pairs(groupBefore) do data.groups[id].enabled=values.enabled end
        self.runs=old; for _,run in ipairs(created) do self:DropRun(run) end
        pcall(self.Subscriptions,self); self.message="Activation unchanged: "..ns.GraphValues.Error(why); self:Changed(); return false
    end
    for id,run in pairs(old) do if nextRuns[id]~=run then self:DropRun(run) end end
    for _,run in ipairs(created) do self:Schedule(run,sample,"initial") end
    self.message="Activation updated"; self:Changed(); return true
end
function S:SetGroupEnabled(id,enabled)
    local group=assert(self:Store().groups[id],"Unknown group")
    return self:ChangeActivation(function() group.enabled=enabled==true end)
end
function S:MoveGraph(id,groupId,targetId,after,expectedStore)
    local data=self:Store(); local rec=assert(data.graphs[id],"Unknown graph")
    if expectedStore and data~=expectedStore then self.message="Library changed; drag again"; return false end
    assert(not groupId or data.groups[groupId],"Unknown group")
    if targetId then
        local target=data.graphs[targetId]
        if not target or targetId==id or target.groupId~=groupId then return false end
    end
    local order={}; for _,key in ipairs(data.graphOrder) do if key~=id then order[#order+1]=key end end
    local position=#order+1
    for i,key in ipairs(order) do
        if targetId and key==targetId then position=i+(after and 1 or 0); break
        elseif not targetId and data.graphs[key].groupId==groupId then position=i+1 end
    end
    if not self:ChangeActivation(function() rec.groupId=groupId end) then return false end
    table.insert(order,position,id); data.graphOrder=order; self:Changed(); return true
end
function S:SetQuickIncluded(kind,id,value)
    local data=self:Store(); local collection=kind=="group" and data.groups or data.graphs
    assert(collection[id],"Unknown library item").quickInclude=value==true
    self:Changed()
end
function S:SetQuickShown(value)
    self:Store().quick.shown=value==true; self:RefreshQuick(); self:Changed()
end
function S:RefreshQuick()
    if self:Store().quick.shown then
        self.quick=self.quick or ns.UI:QuickAccess(self); self.quick:Refresh(); self.quick:Show()
    elseif self.quick then self.quick:Hide() end
end
function S:ToggleCollapsed(id)
    local rec=self:Graph(); local graph=rec and (self.inspectApplied and rec.applied or rec.draft)
    local node=graph and graph.nodes[id]; if not node then return end
    local value=not node.collapsed or nil
    local function set(graph)
        if graph and graph.graph then graph=graph.graph end
        if graph and graph.nodes[id] then graph.nodes[id].collapsed=value end
    end
    set(rec.draft); set(rec.applied)
    local history=self.histories[ns.Settings.db.activeProfile..":"..rec.id]
    if history then for _,stack in pairs({history.undo,history.redo}) do for _,graph in ipairs(stack or {}) do set(graph) end end end
    self:Changed()
end
function S:DeleteGroup(id,expected)
    local data=self:Store(); local group=data.groups[id]
    if not group or group~=expected then self.message="Group changed; reopen deletion"; self:Changed(); return false end
    local ok=self:ChangeActivation(function()
        for _,record in pairs(data.graphs) do if record.groupId==id then record.groupId=nil end end
    end)
    if not ok then return false end
    data.groups[id]=nil; self.message="Deleted group "..group.name.."; graphs moved to Ungrouped"; self:Changed(); return true
end
function S:New(example)
    local data=self:Store(); local count=0; for _ in pairs(data.graphs) do count=count+1 end
    assert(count<32,"Graph limit reached (32 per profile)")
    self:EndTest(); self.inspectApplied=false
    while data.graphs["g"..data.nextId] do data.nextId=data.nextId+1 end
    local id="g"..data.nextId; data.nextId=data.nextId+1
    local effects=example=="text_effects" or example=="icon_effects"
    local logic=example=="logic_values" or example=="logic_branch"
    local time=example=="timer" or example=="remaining_estimate" or example=="interval"
    local draft=example=="cast_button" and A.CastButtonExample() or (example=="action_stack" or example=="ooc_stack") and A.ActionStackExample(example=="ooc_stack") or example=="self_buff" and A.SelfBuffExample() or time and A.TimeExample(example) or logic and A.LogicExample(example=="logic_branch") or effects and A.EffectsExample(example=="text_effects") or example=="orbit" and A.OrbitExample() or (example=="media" or example=="text") and A.MediaExample(example=="text") or example=="icon" and A.IconExample() or example=="aura" and A.AuraExample() or (example and A.Example() or G.New())
    draft=A.MigrateGraph(draft)
    data.graphs[id]={id=id,name=(example=="orbit" and "Orbit example " or example=="text" and "Text example " or example=="media" and "Media example " or example=="icon" and "Icon example " or example=="aura" and "Aura example " or example and "HP example " or "Aura ")..id,draft=draft,enabled=false,revision=0,draftRevision=0}
    if effects then data.graphs[id].name=(example=="text_effects" and "Text effects " or "Icon effects ")..id end
    if logic then data.graphs[id].name=(example=="logic_values" and "Logic values " or "Logic branches ")..id end
    if example=="cast_button" then data.graphs[id].name="Cast button / Unending Breath "..id end
    if example=="self_buff" then data.graphs[id].name="Self buff / Unending Breath "..id end
    if example=="action_stack" or example=="ooc_stack" then data.graphs[id].name=(example=="ooc_stack" and "OOC" or "Secure").." stack / Unending Breath "..id end
    if time then data.graphs[id].name=A.catalog[example].label.." "..id end
    self:PrepareDisplays(draft,data.graphs[id])
    if example=="cast_button" then ns.Layout:Change(draft.nodes.n3.config.layoutId,{width=180,height=36}) end
    if example=="action_stack" or example=="ooc_stack" then
        for _,node in pairs(draft.nodes) do if A.catalog[node.type].actionStack then
            for _,element in ipairs(node.config.elements) do ns.Layout:Change(element.layoutId,{width=element.id=="media1" and 40 or 220,height=element.id=="media1" and 40 or 32}) end
        end end
    end
    if time then for _,node in pairs(draft.nodes) do if node.type=="display" then ns.Layout:Change(node.config.layoutId,{width=240,height=48}) end end end
    if example=="text" or example=="text_effects" then ns.Layout:Change(draft.nodes.n2.config.layoutId,{width=240,height=48}) end
    if example=="logic_values" then ns.Layout:Change(draft.nodes.n5.config.layoutId,{width=240,height=48}) end
    if example=="orbit" then
        local anchor=ns.DisplayAnchors:NewAnchor()
        for _,node in pairs(draft.nodes) do if node.type=="display" then
            ns.Layout:Change(node.config.layoutId,{link={target=anchor,side="CENTER",gap=0,offset=0}})
        end end
    end
    self:CaptureLayouts()
    data.selected=id; self.selection={}; self.validation=nil; self.message="New draft"; self:Changed(); return id
end
function S:Select(id)
    assert(self:Store().graphs[id],"Unknown graph"); self:EndTest(); self:Store().selected=id
    self.selection={}; self.inspectApplied=false; self.validation=nil; self.message="Draft loaded"; self:Changed()
end
function S:DeleteGraph(id,expected)
    local data=self:Store(); local rec=data.graphs[id]
    if not rec or (expected and rec~=expected) then self.message="Graph changed; reopen its properties"; self:Changed(); return false end
    if InCombatLockdown() then self.message="Delete graphs after combat"; self:Changed(); return false end
    -- Register remaining sources before changing saved data or stopping any run.
    local old=self.runs; local remaining={}
    for key,run in pairs(old) do if key~=id then remaining[key]=run end end
    self.runs=remaining
    local ok,why=pcall(self.Subscriptions,self)
    if not ok then
        self.runs=old; pcall(self.Subscriptions,self)
        self.message="Delete cancelled: "..ns.GraphValues.Error(why); self:Changed(); return false
    end
    local selected=data.selected==id; local nextID
    if selected then for _,item in ipairs(self:List()) do if item.value~=id then nextID=item.value; break end end end
    if self.test and self.test.graphId==id then self:EndTest() end
    self:DropRun(old[id])
    if selected and self.editor then
        self.editor:Cancel(); if self.editor.details then self.editor.details:Hide() end
        if not nextID then self.editor:Close() end
    end
    data.graphs[id]=nil
    self.histories[ns.Settings.db.activeProfile..":"..id]=nil
    -- Layout anchors are shared resources, not graph-owned disposable objects.
    if selected then
        data.selected=nextID; self.selection={}; self.inspectApplied=false; self.validation=nil
        if nextID and self.editor then self.editor:LoadView() end
    end
    self.message="Deleted "..rec.name..". Layout anchors retained."; self:Changed(); return true
end
function S:History()
    local id=ns.Settings.db.activeProfile..":"..self:Store().selected
    self.histories[id]=self.histories[id] or {undo={},redo={}}
    return self.histories[id]
end
function S:HistorySnapshot(graph)
    local layouts={};local stored=ns.Layout:Store()
    for _,node in pairs(graph.nodes) do if A.catalog[node.type] and (A.catalog[node.type].display or A.catalog[node.type].layoutOwner) then
        for _,element in ipairs(displayElements(node)) do if element.layoutId and stored[element.layoutId] then layouts[element.layoutId]=G.Copy(stored[element.layoutId]) end end
    end end
    return {graph=G.Copy(graph),layouts=layouts}
end
function S:Commit(graph)
    if self.test and self.test.nodeOverrides then self:EndTest() end
    -- Receivers adopt their graph-local producer schema; edits stay one undo step.
    local schemas={}
    for _,node in pairs(graph.nodes) do if A.catalog[node.type] and A.catalog[node.type].interactionProducer and type(node.config.key)=="string" then
        local key=node.config.key;local payload=node.config.payload or {}
        if not schemas[key] then schemas[key]=payload end
    end end
    for _,node in pairs(graph.nodes) do if node.type=="media_event" and schemas[node.config.key] then node.config.payload=G.Copy(schemas[node.config.key]) end end
    local plan,err=G.Compile(graph,A.catalog,true); if not plan then self.message=err.message; self:Changed(); return false end
    local before=self:HistorySnapshot(self:Draft())
    self:PrepareDisplays(graph,self:Graph())
    local rec=self:Graph(); local h=self:History(); h.undo[#h.undo+1]=before
    if #h.undo>40 then table.remove(h.undo,1) end; h.redo={}
    rec.draft=graph; rec.draftRevision=rec.draftRevision+1; self:CaptureLayouts(); self.message="Draft saved"; self:Changed(); return true
end
function S:Edit(callback)
    if self.inspectApplied then self.message="Leave applied view to edit"; self:Changed(); return false end
    local g=G.Copy(self:Draft()); local ok,why=pcall(callback,g)
    if not ok then self.message=ns.GraphValues.Error(why); self:Changed(); return false end
    return self:Commit(g)
end
function S:Undo(redo)
    if self.inspectApplied then return end
    local h=self:History(); local from,to=redo and h.redo or h.undo,redo and h.undo or h.redo
    if #from==0 then return end
    to[#to+1]=self:HistorySnapshot(self:Draft());local snapshot=table.remove(from)
    local rec=self:Graph();rec.draft=snapshot.graph or snapshot;rec.draftRevision=rec.draftRevision+1
    local stored=ns.Layout:Store();for id,raw in pairs(snapshot.layouts or {}) do stored[id]=G.Copy(raw) end
    self:PrepareDisplays(rec.draft,rec)
    self:CaptureLayouts()
    self.selection={}; self:Changed()
end
function S:Connect(from,output,to,input)
    if self.inspectApplied then return end
    local graph,why=G.Connect(self:Draft(),A.catalog,from,output,to,input)
    if graph then return self:Commit(graph) end
    self.message=why; self:Changed(); return false
end
function S:SetValue(id,key,value,config)
    return self:Edit(function(g)
        local n=assert(g.nodes[id]); local def=assert(G.Definition(A.catalog[n.type],n)); local p
        if not config then p=G.Ports(def)[key] end
        if p then assert(not G.Binding(g,id,key),"Disconnect this input before editing its local value"); assert(G.Accepts(p.type,value),"Invalid "..key) end
        if config and n.type=="media_graphic" and key=="source" then
            local paths=n.config.pathsBySource or {};n.config.pathsBySource=paths
            paths[n.config.source or "file"]=n.config.path
            if value=="file" then n.config.path=paths.file or "Interface\\AddOns\\BVAddonSuite\\Media\\Brand\\bv-logo-small.tga"
            elseif value=="game" then n.config.path=paths.game or "Interface\\Buttons\\WHITE8X8" end
            n.config.atlas=n.config.atlas or "UI-LFG-RoleIcon-Tank";n.config.fileID=n.config.fileID or 134400
        end
        if config then n.config[key]=value; if key=="spellID" then n.config.spellIcon=nil end else n.values[key]=value end
        if config and n.type=="icon_appearance" and key=="skin" and not ns.IconSkins.Supports(value,n.config.shape or "square") then n.config.shape="square" end
        if config and def.memoryOperation=="set" and key=="valueType" then
            local nextDef,why=G.Definition(A.catalog[n.type],n);assert(nextDef,why)
            local input=nextDef.inputs.value
            if not G.Accepts(input.type,n.values.value) then n.values.value=input.default end
        end
        if config and n.type=="unit_record" and key=="schema" then
            local choices={};for field in pairs(A.UnitDataCatalog.schemas[value] or {}) do choices[#choices+1]=field end;table.sort(choices)
            assert(#choices>0,"Unknown record schema");n.config.field=choices[1]
        end
        if config and def.logic then
            local nextDef,why=G.Definition(A.catalog[n.type],n); assert(nextDef,why)
            if key=="count" then
                for input in pairs(G.Ports(def)) do
                    if not G.Ports(nextDef)[input] then assert(not G.Binding(g,id,input),"Disconnect "..input.." before removing it") end
                end
            elseif key=="payloadType" then
                for input,port in pairs(G.Ports(nextDef)) do
                    if not port.control and input~="condition" then
                        local localValue=n.values[input]
                        if localValue~=nil and not G.Accepts(port.type,localValue) then n.values[input]=port.default end
                    end
                end
            end
        end
    end)
end
function S:SetNodeTitle(id,value)
    return self:Edit(function(graph) assert(graph.nodes[id],"Node no longer exists").title=G.NodeTitle(value) end)
end
function S:Metadata()
    if not self.metadata or self.metadata.api~=self.source.api or self.metadata.index~=ns.SpellIndex then self.metadata=ns.SpellMetadataModel.New(self.source.api,ns.SpellIndex) end
    return self.metadata
end
-- Exact configured IDs only; the existing index/cache owns safety and storage.
-- This never opens/builds the index and never queries a native API from the view.
function S:ObjectSummary(node,enrich)
    local id=node and node.config and node.config.spellID
    if not G.Number(id) or id<1 then return {label="Select aura...",origin="Choose a player aura."} end
    local metadata=self:Metadata(); local entry=ns.SpellIndex:Lookup(id) or {value=id,name="Spell "..id,unverified=true}
    if enrich then metadata:Load(entry,true) end
    local row=metadata:Row(entry)
    row.icon=row.icon or metadata:Number(node.config.spellIcon,true)
    return row
end
function S:WatchObject(node,changed)
    local id=node.config.spellID
    if not G.Number(id) or id<1 then return function() end end
    local profile=ns.Settings.db.activeProfile; local key=profile..":"..id
    self.objectBuckets=self.objectBuckets or {}
    if not self.objectOwner then
        self.objectOwner={}
        local function refresh(_,spellID)
            if self:Metadata():Secret(spellID) then return end
            for _,bucket in pairs(self.objectBuckets) do
                if spellID==nil or spellID==bucket.id then
                    self:Metadata().attempts[bucket.id]=nil; bucket.attempts=0; bucket.due=GetTime()
                end
            end
            self:QueueObjects()
        end
        ns.Events:Subscribe(self.objectOwner,"SPELL_DATA_LOAD_RESULT",refresh)
        ns.Events:Subscribe(self.objectOwner,"PLAYER_REGEN_ENABLED",function() refresh() end)
        self.objectUnwatch=ns.SpellIndex:WatchReady(self.objectOwner,function() refresh() end)
    end
    local bucket=self.objectBuckets[key]
    if not bucket then bucket={id=id,profile=profile,watchers={},attempts=0,due=GetTime()}; self.objectBuckets[key]=bucket end
    local owner={node=G.Copy(node),changed=changed}; bucket.watchers[owner]=true
    self:QueueObjects()
    return function()
        bucket.watchers[owner]=nil
        if not next(bucket.watchers) and self.objectBuckets[key]==bucket then self.objectBuckets[key]=nil end
        if not next(self.objectBuckets) then
            if self.objectTimer then self.objectTimer:Cancel(); self.objectTimer=nil end
            if self.objectOwner then ns.Events:Release(self.objectOwner); self.objectOwner=nil end
            if self.objectUnwatch then self.objectUnwatch(); self.objectUnwatch=nil end
        end
    end
end
function S:QueueObjects()
    if self.objectTimer then return end
    local due
    for _,bucket in pairs(self.objectBuckets or {}) do if bucket.due then due=math.min(due or bucket.due,bucket.due) end end
    if not due then return end
    self.objectTimer=C_Timer.NewTimer(math.max(.05,due-GetTime()),function()
        self.objectTimer=nil
        local keys={}; for key,bucket in pairs(self.objectBuckets) do if bucket.due and bucket.due<=GetTime() then keys[#keys+1]=key end end; table.sort(keys)
        -- Four configured IDs per slice, shared by every card, live graph and
        -- isolated test. No index scan and no timer when this queue is empty.
        for i=1,math.min(4,#keys) do
            local bucket=self.objectBuckets[keys[i]]
            if bucket then
                bucket.due=nil
                if bucket.profile==ns.Settings.db.activeProfile then
                    local first=next(bucket.watchers)
                    if first then
                        bucket.attempts=bucket.attempts+1
                        local row=self:ObjectSummary(first.node,true)
                        for watcher in pairs(bucket.watchers) do watcher.changed(self:ObjectSummary(watcher.node)) end
                        if not row.icon and bucket.attempts<3 and not self:Metadata():Paused() then bucket.due=GetTime()+.5 end
                    end
                end
            end
        end
        self:QueueObjects()
    end)
end
function S:ItemPicker(id,key)
    local node=self:Draft().nodes[id]
    assert(node and (node.type=="item_count" or node.type=="item_equipped" or node.type=="item_action") and key=="itemID","Unsupported item selector")
    local store,graph,kind,selected=self:Store(),self:Graph(),node.type,node.config.itemID
    local session=ns.ItemCatalog:Open(function()
        local current=graph.draft.nodes[id]
        return self:Store()==store and self:Graph()==graph and not self.inspectApplied
            and current and current.type==kind and current.config.itemID==selected
    end)
    function session:Choose(entry)
        if not self:Valid() or ns.GraphValues.IsSecret(entry) or type(entry)~="table" or not self:Contains(entry.value) then return false end
        return S:SetValue(id,key,entry.value,true)
    end
    return session
end
function S:Picker(id,key)
    local node=self:Draft().nodes[id]
    assert(node and (node.type=="aura" or A.catalog[node.type].auraSource or (A.catalog[node.type].secureAction or A.catalog[node.type].actionStack or A.catalog[node.type].actionSource)) and key=="spellID","Unsupported selector")
    local selectedKind=node.type
    local selectedUnit=(node.type=="aura" or A.catalog[node.type].secureAction or A.catalog[node.type].actionStack or A.catalog[node.type].actionSource) and "player" or A.UnitSource.Token(node.type,node.config)
    local index=ns.SpellIndex; local session={}; local scan=selectedUnit and self.source:Browse(selectedUnit) or {items={}}; local filter=node.config.filter
    local store,graph,selectedID=self:Store(),self:Graph(),node.config.spellID; local studio=self
    function session:Valid()
        return not self.closed and studio:Store()==store and studio:Graph()==graph and not studio.inspectApplied
            and graph.draft.nodes[id] and graph.draft.nodes[id].type==selectedKind
            and graph.draft.nodes[id].config.spellID==selectedID and graph.draft.nodes[id].config.filter==filter
    end
    local metadata=self:Metadata()
    local source=self.source
    local active={}
    for _,item in ipairs(scan.items) do if item.filter==filter and not active[item.spellID] then active[item.spellID]=item end end
    index:Open(session)
    function session:Enrich(entry,consent)
        if not self:Valid() then return entry end
        metadata:Observe(scan.items)
        metadata:Load(entry,consent)
        return metadata:Row(entry,active[entry.value])
    end
    function session:EnrichmentPaused() return metadata:Paused() end
    function session:Tooltip(entry,consent)
        if not self:Valid() then return entry end
        if not metadata:Allowed(entry,consent) then return metadata:Row(entry,active[entry.value]) end
        local current=source:Inspect(active[entry.value])
        metadata:LoadText(entry,consent,current)
        return metadata:Row(entry,current)
    end
    function session:Status() return index:Status() end
    function session:Retry() index:Retry() end
    function session:Close() self.closed=true; index:Close(self) end
    function session:Search(query)
        if not self:Valid() then return {},"Selector context changed" end
        if not index:Status().ready then return {},"Index not ready" end
        metadata:Observe(scan.items)
        local matches,truncated=index:Search(query); local rows={}
        -- Empty search retains convenient active-aura browsing, after the build gate.
        if query:match("^%s*$") and next(active) then
            matches={}; truncated=false
            for spellID,item in pairs(active) do matches[#matches+1]={value=spellID,name=item.name or "Active aura"} end
            table.sort(matches,function(a,b)return a.value<b.value end)
        end
        for _,entry in ipairs(matches) do
            rows[#rows+1]=metadata:Row(entry,active[entry.value])
        end
        return rows,truncated and "Best 200 matches; refine the name or ID fragment." or "Best matches first. Search name / partial Spell ID."
    end
    return session
end
function S:IconPicker(id,key)
    local catalog=ns.IconCatalog; local store=self:Store(); local session={}; local graphId=self:Graph().id
    if id then local kind=self:Draft().nodes[id].type; assert((kind=="icon" or kind=="media_icon") and key=="texture","Unsupported icon selector") end
    catalog:Open(session)
    function session:Status() return catalog:Status() end
    function session:Search(query) return catalog:Search(query) end
    function session:Close() self.closed=true; catalog:Close(self) end
    function session:Selected()
        local value=store.iconSelection
        if id then
            local rec=store.graphs[graphId]; local node=rec and rec.draft.nodes[id]
            value=node and {kind="icon",texture=node.config.texture}
        end
        if type(value)~="table" or value.kind~="icon" then return end
        local texture,key=catalog:Reference(value.texture)
        if texture then return {kind="icon",texture=texture,key=key} end
    end
    function session:Choose(entry)
        if self.closed or not catalog:Status().ready or type(entry)~="table" or entry.kind~="icon" then return false end
        local found=catalog:Find(entry.texture); if not found then return false end
        if id then
            if S:Graph().id~=graphId or S.inspectApplied then return false end
            local changed=S:Edit(function(g)
                local node=assert(g.nodes[id]); assert(node.type=="icon" or node.type=="media_icon","Node changed")
                node.config.texture=tostring(found.texture)
            end)
            if not changed then return false end
        end
        -- Library preference only. Never writes a spell ID, node or live graph.
        store.iconSelection={kind="icon",texture=found.texture}; return true
    end
    return session
end
-- Canonical shared anchors remain in Layout. Each graph carries its own geometry
-- and a dependency snapshot for future export, never a second editable anchor.
function S:CaptureLayouts()
    local stored=(ns.Settings:Profile().layout or {}).elements or {}
    for _,rec in pairs(self:Store().graphs) do
        local snapshot={version=1,elements={},dependencies={},anchorRefs={}}
        for _,graph in pairs({rec.draft,rec.applied}) do
            for _,node in pairs(graph.nodes) do
                if A.catalog[node.type] and (A.catalog[node.type].display or A.catalog[node.type].layoutOwner) then for _,element in ipairs(displayElements(node)) do
                    local id=element.layoutId
                    local raw=stored[id] or (rec.displayLayout and rec.displayLayout.elements[id])
                    if raw then snapshot.elements[id]=G.Copy(raw) end
                end end
            end
        end
        local visited={}
        local function visit(raw)
            for _,id in pairs({raw.widthTarget,raw.heightTarget,raw.link and raw.link.target}) do
                local external=type(id)=="string" and id:match("^frame:(.*)$")
                local externalReference=external and ns.ExternalFrames and ns.FrameLibrary:ValidateReference(external)
                if id~=ns.Layout.CURSOR_TARGET and id~=ns.Layout.NAMEPLATE_TARGET and not externalReference and not visited[id] then
                    visited[id]=true
                    local dependency=stored[id] or (rec.displayLayout and rec.displayLayout.dependencies and rec.displayLayout.dependencies[id])
                    if not snapshot.elements[id] then
                        snapshot.anchorRefs[#snapshot.anchorRefs+1]=id
                        if dependency then snapshot.dependencies[id]=G.Copy(dependency) end
                    end
                    if dependency then visit(dependency) end
                end
            end
        end
        for _,raw in pairs(snapshot.elements) do visit(raw) end
        table.sort(snapshot.anchorRefs); rec.displayLayout=snapshot
    end
end
function S:PrepareDisplays(graph,rec)
    local used={}
    for _,other in pairs(self:Store().graphs) do
        if other.id~=rec.id then
            for _,g in pairs({other.draft,other.applied}) do
                for _,node in pairs(g.nodes) do for _,element in ipairs(displayElements(node)) do if element.layoutId then used[element.layoutId]=true end end end
            end
        end
    end
    for _,node in pairs(graph.nodes) do
        if A.catalog[node.type] and (A.catalog[node.type].display or A.catalog[node.type].layoutOwner) then
            local elements=displayElements(node)
            local remap={}
            for _,element in ipairs(elements) do
            local id=element.layoutId
            if type(id)~="string" or not id:match("^bv_aura:%x+$") or #id~=40 or used[id] then local old=id;id=ns.DisplayAnchors:NewID();element.layoutId=id;if old then remap[old]=id end end
            used[id]=true
            -- Invalid drafts remain editable; the compiler rejects their texture on Apply.
            local texture=ns.IconCatalog:Reference(node.config.texture) or 134400
            local saved=rec.displayLayout and rec.displayLayout.elements[id] or self.retiredDisplayLayouts and self.retiredDisplayLayouts[id]
            if not saved and rec.displayLayout then for old,new in pairs(remap)do if new==id then saved=G.Copy(rec.displayLayout.elements[old]);break end end end
            if A.catalog[node.type].layoutOwner then
                node.config.layoutId=id
                A.Dialogs.Prepare(node,rec.name.." / "..node.id,saved)
            else
            ns.DisplayAnchors:Ensure(id,rec.name.." / "..node.id..(A.catalog[node.type].displayStack and " / "..element.label or ""),texture,saved)
            end
            end
            if A.catalog[node.type].displayStack then
                local root
                for _,element in ipairs(elements) do if element.id==node.config.rootElement then root=element.layoutId end end
                root=root or elements[1].layoutId;node.config.layoutId=root
                local stored=ns.Layout:Store()
                for _,element in ipairs(elements) do
                    local raw=stored[element.layoutId];raw.templateId=root;raw.templateRoot=root
                    if raw.link and remap[raw.link.target] then raw.link.target=remap[raw.link.target] end
                    if element.layoutId~=root and not raw.link then raw.link={target=root,side="RIGHT",align="CENTER",gap=6,offset=0} end
                end
            else node.config.layoutId=elements[1].layoutId end
        end
    end
    ns.DisplayAnchors:Sync()
end
function S:ClickPayload(id,action,fieldId,value)
    return self:Edit(function(graph)
        local node=assert(graph.nodes[id],"Node no longer exists")
        assert(A.catalog[node.type] and A.catalog[node.type].interactionProducer,"Edit payload fields on a click producer")
        local fields=G.Copy(node.config.payload or {});local index
        for i,field in ipairs(fields) do if field.id==fieldId then index=i end end
        local nextId=node.config.nextPayloadId or 1
        if action=="add" then
            assert(#fields<8,"Payload field limit reached (8)")
            local used={};for _,field in ipairs(fields) do used[field.id]=true end
            while used["value"..nextId] do nextId=nextId+1 end
            fields[#fields+1]={id="value"..nextId,label="Value "..nextId,type="string"};nextId=nextId+1
        elseif action=="remove" then assert(index,"Unknown payload field");table.remove(fields,index)
        elseif action=="rename" then assert(index,"Unknown payload field");fields[index].label=value
        elseif action=="type" then assert(index,"Unknown payload field");fields[index].type=value
        else error("Unknown payload action") end
        assert(ns.GraphValues.ClickSchema(fields),"Use up to eight named String, Number, Integer or Boolean fields")
        -- All producers sharing a key publish the same contract. Compile rejects
        -- any removal/type change that would break an existing connection.
        for _,other in pairs(graph.nodes) do
            if A.catalog[other.type] and A.catalog[other.type].interactionProducer and other.config.key==node.config.key then
                other.config.payload=G.Copy(fields);other.config.nextPayloadId=nextId
                if action=="remove" then other.values[fieldId]=nil;other.exposed[fieldId]=nil end
            end
        end
    end)
end
function S:StackElement(id,action,elementId,value)
    local changes={}
    local removed
    local edited=self:Edit(function(graph)
        local node=assert(graph.nodes[id]);assert(A.catalog[node.type].displayStack,"Select a Display Stack")
        local elements=node.config.elements;local index
        for i,element in ipairs(elements) do if element.id==elementId then index=i end end
        if action=="add" then
            assert(#elements<8,"Element limit reached (8)")
            local nextId=node.config.nextElementId or 1;local used={};for _,e in ipairs(elements) do used[e.id]=true end
            while used["media"..nextId] do nextId=nextId+1 end
            elements[#elements+1]={id="media"..nextId,label="Element "..nextId};node.config.nextElementId=nextId+1
        elseif action=="rename" then
            assert(index,"Unknown element");assert(type(value)=="string" and #value>0 and #value<=48 and not value:find("[%c|]"),"Use 1..48 plain characters")
            elements[index].label=value
        elseif action=="remove" then
            assert(index and #elements>1,"Keep at least one element")
            assert(elementId~=node.config.rootElement,"Choose another root before removing this element")
            assert(not G.Binding(graph,id,elementId),"Disconnect this media input before removing it")
            local layoutId=elements[index].layoutId
            for _,raw in pairs(ns.Layout:Store()) do assert(not (raw.link and raw.link.target==layoutId) and raw.widthTarget~=layoutId and raw.heightTarget~=layoutId,"Detach dependent layout elements first") end
            removed=layoutId
            table.remove(elements,index);node.values[elementId]=nil;node.exposed[elementId]=nil
        elseif action=="move" then
            assert(index,"Unknown element");local target=index+value
            if target>=1 and target<=#elements then elements[index],elements[target]=elements[target],elements[index] end
        elseif action=="root" then
            assert(index,"Unknown root");local old=node.config.layoutId;local new=elements[index].layoutId
            if old~=new then
                local stored=ns.Layout:Store();local records={};for _,e in ipairs(elements) do records[e.layoutId]=stored[e.layoutId] end
                local template=assert(ns.LayoutModel.ResolveTemplate(records,old));local offset=template.rects[new]
                for _,e in ipairs(elements) do
                    local raw=G.Copy(stored[e.layoutId]);raw.templateId=new;raw.templateRoot=new
                    if e.layoutId==new then raw.link=G.Copy(stored[old].link);raw.screen=stored[old].screen;raw.x=stored[old].x;raw.y=stored[old].y
                    else local r=template.rects[e.layoutId];raw.link={target=new,side="CENTER",align="CENTER",offset=r.x-offset.x,gap=r.y-offset.y} end
                    changes[e.layoutId]=raw
                end
                node.config.rootElement=elementId;node.config.layoutId=new
            end
        end
    end)
    if edited and next(changes) then
        local stored=ns.Layout:Store();for key,raw in pairs(changes) do stored[key]=raw end
        ns.DisplayAnchors:Sync();ns.Layout:Refresh(true);self:CaptureLayouts()
    end
    if edited and removed then
        local stored=ns.Layout:Store();local raw=stored[removed]
        self.retiredDisplayLayouts=self.retiredDisplayLayouts or {};self.retiredDisplayLayouts[removed]=G.Copy(raw)
        local applied=false
        for _,record in pairs(self:Store().graphs) do for _,node in pairs(record.applied and record.applied.nodes or {}) do
            for _,element in ipairs(displayElements(node)) do if element.layoutId==removed then applied=true end end
        end end
        if applied then raw.templateId=nil;raw.templateRoot=nil else stored[removed]=nil end
        ns.DisplayAnchors:Sync();ns.Layout:Refresh(true);self:CaptureLayouts()
    end
    return edited
end
function S:ConvertIcon(id)
    return self:Edit(function(graph)
        local n=assert(graph.nodes[id]); assert(n.type=="icon","Select a legacy icon output")
        local media=G.Add(graph,"media_icon",A.catalog,n.x-310,n.y)
        graph.nodes[media].config.texture=n.config.texture
        graph.nodes[media].config.cropBorder=n.config.cropBorder~=false
        n.type="display"; n.config={layoutId=n.config.layoutId}
        graph.edges[#graph.edges+1]={from=media,output="media",to=id,input="media"}
    end)
end
function S:LayoutIcon(id)
    if InCombatLockdown() then self.message="Open the Layout Editor after combat"; self:Changed(); return end
    local graph=self.inspectApplied and self:Graph().applied or self:Draft()
    local node=graph and graph.nodes[id]; assert(node and (A.catalog[node.type].display or A.catalog[node.type].layoutOwner),"Select a display node")
    self:PrepareDisplays(graph,self:Graph())
    local anchor=node.config.layoutId
    self:EnterLayout(anchor)
end
function S:EnterLayout(anchor)
    local profile=ns.Settings.db.activeProfile
    local graphID=self:Store().selected
    local selection=self.editor and G.Copy(self.editor.selected) or {}
    if self.editor then self.editor:Close() end
    ns.LayoutEditor:Open(anchor,function()
        -- Layout normally blocks profile switches. Still reject a stale caller
        -- if a graph/profile disappeared through another entry point.
        if ns.Settings.db.activeProfile~=profile or not self:Store().graphs[graphID] then return false end
        self:Store().selected=graphID; self:Open()
        local displayed=self.editor:Graph()
        for id in pairs(selection) do if not displayed or not displayed.nodes[id] then selection[id]=nil end end
        self.editor.selected=selection; self.editor:Render()
        return true
    end)
end
function S:OpenLayout()
    if InCombatLockdown() then self.message="Open the Layout Editor after combat"; self:Changed(); return end
    self:RestoreLayouts()
    local rec=self:Graph(); local graph=rec and (self.inspectApplied and rec.applied or rec.draft)
    local ids={}
    for id,node in pairs(graph and graph.nodes or {}) do if A.catalog[node.type] and (A.catalog[node.type].display or A.catalog[node.type].layoutOwner) then ids[#ids+1]=id end end
    table.sort(ids)
    local selected=self.editor and self.editor.selected or {}
    local nodeID=ids[1]
    for _,id in ipairs(ids) do if selected[id] then nodeID=id; break end end
    self:EnterLayout(nodeID and graph.nodes[nodeID].config.layoutId)
end
function S:Pick(id,key,entry)
    if not ns.SpellIndex:Status().ready then return false end
    return self:Edit(function(graph)
        local node=assert(graph.nodes[id]); assert((node.type=="aura" or A.catalog[node.type].auraSource or (A.catalog[node.type].secureAction or A.catalog[node.type].actionStack or A.catalog[node.type].actionSource)) and key=="spellID","Unsupported selector")
        node.config.spellID=entry.value
        node.config.spellIcon=entry.icon -- Reference metadata, never an image or live trigger value.
    end)
end
function S:Discard()
    local rec=self:Graph(); if not rec.applied then return self:Commit(G.New()) end
    self:Commit(G.Copy(rec.applied)); rec.draftRevision=rec.appliedDraftRevision or 0; self:Changed()
end
function S:Diagnostic(graph,node,message)
    message=ns.GraphValues.Error(message)
    local key=tostring(graph)..":"..tostring(node)..":"..message
    local last
    for _,e in ipairs(self.errors) do if e.key==key then last=e; break end end
    if last then last.count=last.count+1; last.at=GetTime()
    else
        if #self.errors>=40 then table.remove(self.errors,1) end
        self.errors[#self.errors+1]={key=key,graph=graph,node=node,message=message,count=1,at=GetTime()}
    end
    self:Changed(false)
end
function S:ErrorsText()
    local lines={}
    for i=#self.errors,math.max(1,#self.errors-11),-1 do local e=self.errors[i]; lines[#lines+1]=string.format("%s / %s  x%d\n%s",e.graph,e.node,e.count,e.message) end
    return #lines>0 and table.concat(lines,"\n\n") or "No graph errors."
end
-- Binding generations are local lifecycle counters, never native identities.
local function collectionOnlyToken(run,token)
    if not run.instanceRuntime or not run.collection or not (run.collectionTokens and run.collectionTokens[token]) then return false end
    local nodes=run.unitNodes and run.unitNodes[token]
    if not nodes or not next(nodes) then return false end
    for id in pairs(nodes) do
        local def=run.plan.definitions[id]
        if not def or not def.collectionSource then return false end
    end
    return true
end
local function discardRecycledObservation(item,token)
    -- Started jobs retain their frozen snapshot: InstanceRuntime rejects stale
    -- tasks by reference/generation and lets the unaffected contexts finish.
    if item.job then return end
    local sample=item.sample
    for _,key in ipairs({"units","unitRefs"}) do if sample[key] then sample[key][token]=nil end end
    for _,key in ipairs({"unitQueries","auras"}) do
        for id in pairs(sample[key] or {}) do
            if id==token or id:sub(1,#token+1)==token..":" then sample[key][id]=nil end
        end
    end
    -- Keep a tombstone so an old queued job cannot initialise the replacement
    -- plate with data from the previous occupant of this native token.
    sample.unitGenerations=sample.unitGenerations or {}
    sample.unitGenerations[token]=item.bindings[token]
end
function S:InvalidateUnits(tokens)
    if tokens.player then self:CancelCDMAuraRefresh("player") end
    if tokens.target then
        self:CancelCDMAuraRefresh("target")
        if self.source then self.source.cdmTargetEpoch=(self.source.cdmTargetEpoch or 0)+1 end
    end
    self.unitGenerations=self.unitGenerations or {}
    for token in pairs(tokens) do
        self.unitGenerations[token]=(self.unitGenerations[token] or 0)+1
        for key,query in pairs(self.unitQueries or {}) do if query.unit==token then query.sample=nil end end
        for key,request in pairs(self.unitAuraRequests or {}) do if request.unit==token and self.unitAuraSamples then self.unitAuraSamples[key]=nil end end
    end
    for _,run in pairs(self.runs) do
        for token in pairs(tokens) do
            if run.bindings then run.bindings[token]=nil end
            if R.InvalidateInstance then R.InvalidateInstance(run,token) end
        end
        local affected={}
        local onlyCollection=run.collection==true
        for token in pairs(tokens) do
            if run.unitNodes and run.unitNodes[token] and not collectionOnlyToken(run,token) then onlyCollection=false end
        end
        local function visit(id)
            if affected[id] then return end;affected[id]=true
            for child in pairs(run.plan.dependents[id] or {}) do visit(child) end
        end
        for token in pairs(tokens) do for id in pairs(run.unitNodes and run.unitNodes[token] or {}) do visit(id) end end
        if next(affected) then
            for i=#self.queue,1,-1 do
                local item=self.queue[i]
                if item.run==run then
                    local packet=item.reason=="interaction" and item.sample.interaction
                    local binding=packet and packet.instance and G.Object(packet.instance,"unitref")
                    -- A different plate disappearing cannot revoke this click.
                    -- Noncollection dependencies and the clicked generation still do.
                    local keep=onlyCollection and (not packet or binding and not tokens[binding.unit]) and self:BindingsCurrent(item)
                    if keep and not item.job and item.instanceTokens then
                        for token in pairs(tokens) do item.instanceTokens[token]=nil end
                        keep=next(item.instanceTokens)~=nil
                    end
                    if not keep then
                        if packet then ns:RecordDisplayInput("cancelled") end
                        table.remove(self.queue,i)
                    end
                end
            end
            if not onlyCollection and R.InvalidateNodes then R.InvalidateNodes(run,affected) end
            for id in pairs(onlyCollection and {} or affected) do
                run.values[id]=nil;run.signals[id]=nil;run.trace[id]=nil
                -- Preserve gate latches/deadlines and fault backoff. An unknown
                -- binding must never manufacture a new false-to-true edge.
                local state=run.state[id];if state then state.time=nil;state.auraEstimate=nil end
                if run.plan.definitions[id].actionStack then ns.ActionStacks:Clear(run,id)
                elseif run.plan.definitions[id].secureAction then ns.DisplayAnchors:SetSecureHint(run,id,nil)
                elseif run.plan.definitions[id].displayStack then ns.DisplayAnchors:ClearStack(run,id)
                elseif run.plan.definitions[id].display then ns.DisplayAnchors:Set(run,id,false) end
            end
        end
    end
    self:RefreshClock()
end
function S:CancelCDMAuraRefresh(unit)
    for _,token in ipairs({"player","target"}) do
        if not unit or token==unit then
            local key=token=="player" and "cdmAuraRefresh" or "cdmTargetAuraRefresh"
            local pending=self[key];self[key]=nil
            if pending and pending.timer then pending.timer:Cancel() end
        end
    end
end
function S:QueueCDMAuraRefresh(unit)
    unit=unit or "player"
    if unit~="player" and unit~="target" then return end
    local pendingKey=unit=="player" and "cdmAuraRefresh" or "cdmTargetAuraRefresh"
    if not self.active or self[pendingKey] or not A.CDMSource or not self.source then return end
    local source=self.source;local api=source.api
    if not api or source:Secret(api.C_CooldownViewer) or type(api.C_CooldownViewer)~="table" then return end
    local info=api.C_CooldownViewer.GetCooldownViewerCooldownInfo
    if source:Secret(info) or type(info)~="function" then return end
    local icon,bar=api.BuffIconCooldownViewer,api.BuffBarCooldownViewer
    local function viewer(value)return not source:Secret(value) and (type(value)=="table" or type(value)=="userdata")end
    if not viewer(icon) and not viewer(bar) then return end
    local requests,legacy={},{}
    for key,request in pairs(self.unitAuraRequests or {}) do
        if request.unit==unit then requests[key]=G.Copy(request) end
    end
    for key,request in pairs(self.auraRequests or {}) do
        if unit=="player" and (request.unit==nil or request.unit=="player") then legacy[key]=G.Copy(request) end
    end
    if not next(requests) and not next(legacy) then return end
    local pending={source=source,generation=self.unitGenerations and self.unitGenerations[unit] or 0}
    self[pendingKey]=pending
    -- Blizzard can update its existing viewer after UNIT_AURA dispatch. One
    -- coalesced follow-up observes that update; it never arms another timer.
    pending.timer=C_Timer.NewTimer(.05,function()
        if self[pendingKey]~=pending or not self.active or self.source~=source or (self.unitGenerations and self.unitGenerations[unit] or 0)~=pending.generation then return end
        local ok,why=pcall(function()
            local observed=next(requests) and source:Capture(requests) or {}
            local old=next(legacy) and source:Capture(legacy) or {}
            if self[pendingKey]~=pending or not self.active or self.source~=source or (self.unitGenerations and self.unitGenerations[unit] or 0)~=pending.generation then return end
            self.unitAuraSamples=self.unitAuraSamples or {}
            for key,value in pairs(observed) do self.unitAuraSamples[key]=G.RuntimeCopy(value) end
            if A.infoDiagnostics.active then
                for key,value in pairs(observed) do A.infoCollector:PublishObservation("aura",key,value) end
                for key,value in pairs(old) do A.infoCollector:PublishObservation("aura",key,value) end
            end
            for _,run in pairs(self.runs) do
                if not run.stopped and not run.test then
                    local auras={}
                    if run.needs.aura then for key,value in pairs(old) do auras[key]=value end end
                    for key,request in pairs(run.unitAuras or {}) do
                        if request.unit==unit and observed[key] then auras[key]=observed[key] end
                    end
                    if next(auras) then self:Schedule(run,{auras=auras,unitGenerations={[unit]=pending.generation}},"aura") end
                end
            end
        end)
        if self[pendingKey]==pending then self[pendingKey]=nil end
        if not ok then self:Diagnostic("sources","CDM deferred aura refresh",ns.GraphValues.Error(why)) end
    end)
end
function S:CaptureUnits(tokens,dynamic,keys,deferred,skipAuras)
    local perfStarted=ns.Performance.active and ns.Performance:Begin()
    local sample={units={},unitQueries={},unitGenerations={}}
    self.unitSource=self.unitSource or A.UnitSource.New(_G)
    self.unitGenerations=self.unitGenerations or {};self.unitPresence=self.unitPresence or {}
    local ordered={};for key in pairs(self.unitQueries or {}) do ordered[#ordered+1]=key end;table.sort(ordered)
    local captured=0;local started=debugprofilestop and debugprofilestop() or 0
    for _,key in ipairs(ordered) do
        local query=self.unitQueries[key];local token=query.unit
        if (not tokens or tokens[token]) and (not keys or keys[key]) then
            local fields=query.fields
            if dynamic then fields={};for field in pairs(query.fields) do if A.UnitDataCatalog.dynamic[field] then fields[field]=true end end end
            if not dynamic or next(fields) then
                if captured>=2 or (captured>0 and debugprofilestop and debugprofilestop()-started>=2) then
                    self.pendingUnitQueries=self.pendingUnitQueries or {};self.pendingUnitQueries[key]=true
                    if not skipAuras and not dynamic then self.pendingAuraQueries=self.pendingAuraQueries or {};self.pendingAuraQueries[key]=true end
                else
                captured=captured+1
                local observation
                if self.nameplateAbsent and self.nameplateAbsent[token] then
                    local knownAbsent=self.nameplateAbsent[token]==true
                    observation={values={},fields={},status=knownAbsent and "absent" or "protected"}
                    if knownAbsent then observation.values.exists=false end
                    for field in pairs(fields) do observation.fields[field]=knownAbsent and (field=="exists" and "readable" or "absent") or "protected" end
                else observation=self.unitSource:Capture(fields,token,A.UnitSource.Options(query.options)) end
                local old=self.unitPresence[token]
                if old and old~=observation.status then self:InvalidateUnits({[token]=true}) end
                self.unitPresence[token]=observation.status
                if dynamic and query.sample and observation.status=="present" then
                    local merged=G.RuntimeCopy(query.sample)
                    for field in pairs(fields) do merged.values[field]=observation.values[field];merged.fields[field]=observation.fields[field] end
                    observation=merged
                end
                query.sample=G.RuntimeCopy(observation)
                if A.infoDiagnostics.active then A.infoCollector:PublishObservation("unit",key,observation) end
                sample.unitQueries[key]=observation
                sample.units[token]=sample.units[token] or observation
                sample.unitGenerations[token]=self.unitGenerations[token] or 0
                if key==token then sample.units[token]=observation end
                end
            end
        end
    end
    if self.pendingUnitQueries and next(self.pendingUnitQueries) and not self.sourceTimer then
        self.sourceTimer=C_Timer.NewTimer(.016,function()
            self.sourceTimer=nil;local pending=self.pendingUnitQueries;self.pendingUnitQueries={}
            local withAuras=next(self.pendingAuraQueries or {});self.pendingAuraQueries={}
            local result=self:CaptureUnits(nil,false,pending,true,not withAuras)
            for _,run in pairs(self.runs) do self:Schedule(run,result,"unit") end
        end)
    end
    local auraRequests={}
    for key,request in pairs(self.unitAuraRequests or {}) do if not skipAuras and not dynamic and sample.units[request.unit] then auraRequests[key]=request end end
    if next(auraRequests) then
        sample.auras=self.source:Capture(auraRequests);self.unitAuraSamples=self.unitAuraSamples or {}
        for key,value in pairs(sample.auras) do
            self.unitAuraSamples[key]=G.RuntimeCopy(value)
            if A.infoDiagnostics.active then A.infoCollector:PublishObservation("aura",key,value) end
        end
    end
    if ns.Performance.active then ns.Performance:Finish("capture_units_ms",perfStarted) end
    return sample
end
function S:ObserveUnits(tokens,rebind,skipAuras)
    local requested={}
    for token in pairs(self.unitRequests or {}) do if not tokens or tokens[token] then requested[token]=true end end
    if not next(requested) then return end
    if rebind then self:InvalidateUnits(requested) end
    local sample=self:CaptureUnits(requested,nil,nil,nil,skipAuras)
    for _,run in pairs(self.runs) do self:Schedule(run,sample,"unit") end
end
function S:BindingsCurrent(item)
    local packet=item.reason=="interaction" and item.sample.interaction
    local clicked=packet and packet.instance and G.Object(packet.instance,"unitref")
    if clicked then
        local binding=item.run.bindings and item.run.bindings[clicked.unit]
        if not binding or binding.reference~=packet.instance then return false end
    end
    for token,generation in pairs(item.bindings or {}) do
        if (self.unitGenerations and self.unitGenerations[token] or 0)~=generation then
            if collectionOnlyToken(item.run,token) and (not clicked or token~=clicked.unit) then
                discardRecycledObservation(item,token)
            else return false end
        end
    end
    return true
end
function S:Sample(reason,event)
    local sample={}
    if not reason or reason=="initial" then sample=self:CaptureUnits() end
    if reason and reason~="initial" and ({hp=true,power=true,player_state=true,context=true})[reason] and self.unitRequests and self.unitRequests.player then sample=self:CaptureUnits({player=true},nil,nil,nil,true) end
    local requested={}
    if not reason or ({initial=true,hp=true,power=true,player_state=true,context=true})[reason] then
        for key in pairs(self.playerRequests or {}) do requested[key]=true end
    end
    -- Preserve the existing HP sampling API while sharing its native reads with
    -- the new Player snapshot. Old graph/node IDs and saved profiles are intact.
    if reason~="aura" then
        for key in pairs(self.legacyPlayerFields or {}) do requested[key]=true end
        if not self.active or not next(self.runs) then requested.health=true;requested.healthMax=true;requested.combat=true end
    end
    self.playerSource=self.playerSource or A.PlayerSource.New(_G)
    sample.player=sample.unitQueries and sample.unitQueries.player or self.playerSource:Capture(requested)
    if A.infoDiagnostics.active then A.infoCollector:PublishObservation("unit","player",sample.player) end
    sample.combat=sample.player.values.combat
    sample.current=sample.player.values.health;sample.maximum=sample.player.values.healthMax
    sample.hpFields={current=sample.player.fields.health,maximum=sample.player.fields.healthMax}
    if not reason or reason=="initial" or reason=="aura" then
        sample.auras=sample.auras or {}
        for key,value in pairs(self.source:Capture(self.auraRequests or {})) do
            sample.auras[key]=value
            if A.infoDiagnostics.active then A.infoCollector:PublishObservation("aura",key,value) end
        end
    end
    if self.dataSource then sample.sources=self.dataSource:Capture(self.dataRequests,reason,event) end
    return sample
end
function S:EnsurePlayerChat()
    if not self.playerChat or self.playerChat.stopped then
        self.playerChat=ns.PlayerChat.New(_G,GetTime,C_Timer.NewTimer)
        if ns.UI.BindPlayerChat then ns.UI:BindPlayerChat(self.playerChat) end
    end
    return self.playerChat
end
function S:RefreshMouseover(rebind)
    if not (self.unitRequests and self.unitRequests.mouseover) then self.mouseoverPresence=nil;return end
    local ok,value=pcall(function()return UnitExists and UnitExists("mouseover")end)
    local status=not ok and "unavailable" or G.IsSecret(value) and "protected" or value==true and "present" or value==false and "absent" or "unavailable"
    if rebind or status~=self.mouseoverPresence then
        self.mouseoverPresence=status
        self:ObserveUnits({mouseover=true},true)
    end
end
function S:MakeRun(rec,plan,test)
    local run
    run=R.New(plan,function(text,nodeID,prefix)
        if run.stopped then return end
        if not test and self.runs[rec.id]~=run then return end
        if test and self.test~=run then return end
        -- Local output only. Escape markup supplied by a graph.
        ns:Print((test and "[Test] " or "")..text:gsub("|","||"),prefix)
    end,function(node,message) self:Diagnostic(rec.id,node,message) end,function(node,visible,media,stack,instance)
        if run.stopped then return end
        if test and self.test~=run then return end
        if not test and self.runs[rec.id]~=run then return end
        if plan.definitions[node].actionDisplay then ns.DisplayAnchors:SetAction(run,node,visible,media,stack and stack.action,nil,stack)
        elseif plan.definitions[node].actionStack then ns.ActionStacks:Set(run,node,visible,stack,instance)
        elseif plan.definitions[node].secureAction then
            ns.DisplayAnchors:SetSecureHint(run,node,stack and stack.highlight)
            ns.DisplayAnchors:Set(run,node,visible)
        elseif plan.definitions[node].displayStack then ns.DisplayAnchors:SetStack(run,node,visible,stack,instance)
        else ns.DisplayAnchors:Set(run,node,visible,media) end
    end)
    run.graphId=rec.id; run.test=test; run.appliedRevision=rec.revision
    run.dialogResume=function(id) self:Schedule(run,{},"dialog:"..id) end
    run.requestChat=function(nodeID,text,config)
        if test or run.stopped or self.runs[rec.id]~=run then return false,"inactive" end
        local revision=run.appliedRevision
        local profile=ns.Settings.db.activeProfile
        return self:EnsurePlayerChat():Request(run,nodeID,text,config,function()
            return not run.stopped and self.runs[rec.id]==run and run.appliedRevision==revision and ns.Settings.db.activeProfile==profile
        end)
    end
    run.sendChat=function(nodeID,text,config)
        return self:EnsurePlayerChat():SendDirect(run,nodeID,text,config,function()
            return not test and not run.stopped and self.runs[rec.id]==run
        end)
    end
    run.send=function(config,value)
        if test or run.stopped or self.runs[rec.id]~=run then return false,"inactive" end
        if not self.messaging then return false,"message service unavailable" end
        return self.messaging:Send(config.topic,config.payloadType,value,config.channel,config.target,run.messageDriven and "message" or "local",rec.id,config)
    end
    run.messageStatus=function(config)
        if test or run.stopped or self.runs[rec.id]~=run or not self.messaging then return false,"inactive" end
        return self.messaging:CanSend(config.channel,config.target,config)
    end
    run.messageAccept=function(config,packet)
        return self.messaging and self.messaging:AcceptNode(config,packet.sender,packet.channel) or false
    end
    run.needs={};run.messageTopics={};run.interactionKeys={};run.playerFields={};run.unitFields={};run.unitNodes={};run.queryFields={};run.frameReferences={}
    for _,id in ipairs(plan.order) do
        local node=plan.graph.nodes[id]; run.needs[node.type]=true
        if node.type=="macro_exists" and not plan.incoming[id].event then run.needs.macros=true end
        if node.type=="media_bar" and node.config.source=="player_health" then run.needs.hp=true end
        if plan.definitions[id].unitSource or plan.definitions[id].auraSource then
            local tokens={}
            if plan.definitions[id].collectionSource then
                run.collection=true;tokens=A.CollectionTokens(plan.definitions[id],node.config)
                run.collectionTokens=run.collectionTokens or {};for _,token in ipairs(tokens) do run.collectionTokens[token]=true end
            else tokens[1]=A.UnitSource.Token(node.type,node.config) end
            for _,token in ipairs(tokens) do
            run.unitFields[token]=run.unitFields[token] or {};run.unitNodes[token]=run.unitNodes[token] or {};run.unitNodes[token][id]=true
            local key=A.UnitSource.Key(token,node.config)
            run.queryFields[key]=run.queryFields[key] or {unit=token,options=A.UnitSource.Options(node.config),fields={}}
            run.queryFields[key].fields.exists=true
            if plan.definitions[id].auraSource then
                run.unitAuras=run.unitAuras or {}
                run.unitAuras[A.AuraSource.Key(node.config.spellID,node.config.filter,token)]={spellID=node.config.spellID,filter=node.config.filter,unit=token,transport=true}
            end
            end
        end
        if A.catalog[node.type].dataSource then run.needs[A.DataSource.reasons[node.type]]=true end
        if node.type=="message_receive" then run.messageTopics[node.config.topic..":"..node.config.payloadType..":"..node.config.channel]=true end
        if node.type=="media_event" then run.interactionKeys[node.config.key]=true end
        if node.type=="frame_state" and node.config.reference~="" then run.frameReferences[node.config.reference]=true end
    end
    for _,edge in ipairs(plan.graph.edges) do
        if plan.active[edge.from] and plan.active[edge.to] then
            local node=plan.graph.nodes[edge.from]
            if node.type=="player" then run.playerFields[edge.output]=true end
            if plan.definitions[edge.from].auraSource and edge.output=="realTime" then
                local tokens=plan.definitions[edge.from].collectionSource and A.CollectionTokens(plan.definitions[edge.from],node.config)
                    or {A.UnitSource.Token(node.type,node.config)}
                for _,token in ipairs(tokens) do run.unitAuras[A.AuraSource.Key(node.config.spellID,node.config.filter,token)].realTime=true end
            end
            if plan.definitions[edge.from].unitSource then
                local tokens={}
                if plan.definitions[edge.from].collectionSource then tokens=A.CollectionTokens(plan.definitions[edge.from],node.config)
                else tokens[1]=A.UnitSource.Token(node.type,node.config) end
                for _,token in ipairs(tokens) do
                run.unitFields[token][edge.output]=true
                if A.UnitDataCatalog.fields[edge.output] or A.UnitSource.presentationFields[edge.output] or A.UnitSource.playerFields[edge.output] then run.queryFields[A.UnitSource.Key(token,node.config)].fields[edge.output]=true end
                if A.UnitDataCatalog.dynamic[edge.output] then run.unitDynamic=true end
                end
            end
        end
    end
    -- Validate the complete display set before opening any runtime resources.
    -- Action Display can resolve static layout links into a screen rectangle;
    -- its protected surface already freezes that rectangle during combat.
    for _,id in ipairs(plan.order) do
        local node=plan.graph.nodes[id];local def=plan.definitions[id]
        if def.display then
            local saved=rec.displayLayout and rec.displayLayout.elements[node.config.layoutId]
            ns.DisplayAnchors:Ensure(node.config.layoutId,rec.name.." / "..id,node.config.texture or 134400,saved)
        end
    end
    for _,id in ipairs(plan.order) do
        local node=plan.graph.nodes[id];local def=plan.definitions[id]
        if def.secureAction then assert(ns.SecureSpells:ValidLayout(node.config.layoutId),"Secure spell buttons require a free screen position (no anchor or size links)")
        elseif def.actionDisplay then assert(ns.SecureActionMedia:ValidLayout(node.config.layoutId),"Action Display requires screen-based layout links (no cursor, nameplate, external frame or template)") end
    end
    local items={}
    for _,id in ipairs(plan.order) do
        local node=plan.graph.nodes[id]
        if A.catalog[node.type].actionStack then
            ns.ActionStacks:Open(run,id,node.config,A.catalog[node.type].actionMode)
        elseif A.catalog[node.type].displayStack then
            ns.DisplayAnchors:OpenStack(run,id,node.config,test and 1 or 0)
        elseif A.catalog[node.type].display then
            items[#items+1]={key=id,anchor=node.config.layoutId,texture=node.config.spellIcon or node.config.texture or 134400,
                actionDisplay=not test and A.catalog[node.type].actionDisplay or nil,cropBorder=node.config.cropBorder,secureSpell=not test and A.catalog[node.type].secureAction and node.config.spellID or nil}
        end
    end
    if #items>0 then
        local ok,why=pcall(ns.DisplayAnchors.Open,ns.DisplayAnchors,run,items,test and 1 or 0)
        if not ok then pcall(ns.DisplayAnchors.Close,ns.DisplayAnchors,run); error(why) end
    end
    run.objectIcons={}; run.objectRequests={}
    local ready,why=pcall(function()
        local iconDemand={}
        for _,edge in ipairs(plan.graph.edges) do
            if edge.output=="icon" and plan.active[edge.to] then iconDemand[edge.from]=true end
        end
        for _,id in ipairs(plan.order) do
            local node=plan.graph.nodes[id]
            if (node.type=="aura" or plan.definitions[id].auraSource and iconDemand[id]) and not run.objectRequests[node.config.spellID] then
                local spellID=node.config.spellID
                run.objectIcons[spellID]=self:ObjectSummary(node).icon
                run.objectRequests[spellID]=self:WatchObject(node,function(row)
                    if run.stopped or (run.test and self.test~=run) or (not run.test and self.runs[run.graphId]~=run) then return end
                    if row.icon~=run.objectIcons[spellID] then run.objectIcons[spellID]=row.icon; self:Schedule(run,{},"metadata") end
                end)
            end
        end
    end)
    if not ready then self:DropRun(run); error(why) end
    return run
end
local function needsCachedUnit(run,token)
    if not (run.collectionTokens and run.collectionTokens[token]) or run.bindings[token] then return true end
    local nodes=run.unitNodes and run.unitNodes[token]
    if not nodes then return true end -- Unknown demand: preserve the full cache.
    for id in pairs(nodes) do
        local def=run.plan.definitions[id]
        if not def or not def.collectionSource then return true end
    end
    return false
end
local function ignoresReason(run,reason,queue)
    if (reason=="hp" and not run.needs.hp and not run.needs.player)
        or (reason=="context" and not run.needs.context and not run.needs.player)
        or (reason=="aura" and not run.needs.aura and not run.unitAuras)
        or (reason=="cooldown" and not run.needs.icon_cooldown and not run.needs.cooldown)
        or (reason=="power" and not run.needs.player)
        or (reason=="frame_state" and not run.needs.frame_state)
        or (reason=="macros" and not run.needs.macros)
        or (reason=="player_state" and not run.needs.player_state and not run.needs.player)
        or (({location=true,inventory=true,proc=true,usable=true,spellbook=true,totem=true,xp=true,money=true,currency=true,reputation=true,talents=true})[reason] and not run.needs[reason]) then return true end
    if reason=="clock" then
        if not R.NeedsClock(run) then return true end
        for _,item in ipairs(queue) do if item.run==run then return true end end
    end
    return false
end
local function collectionUpdates(run,sample,reason)
    if reason~="unit" or not run.instanceRuntime then return end
    local tokens={}
    if sample.unitQueries then
        for key in pairs(sample.unitQueries) do
            local query=run.queryFields and run.queryFields[key]
            if query then
                if not collectionOnlyToken(run,query.unit) then return end
                tokens[query.unit]=true
            end
        end
    else
        for token in pairs(sample.units or {}) do if run.unitFields and run.unitFields[token] then
            if not collectionOnlyToken(run,token) then return end
            tokens[token]=true
        end end
    end
    if next(tokens) then return tokens end
end
function S:Schedule(run,sample,reason)
    if not run or run.stopped then return end
    if not run.test and self.test and self.test.nodeOverrides and self.test.graphId==run.graphId then
        self:Schedule(self.test,sample,reason)
    end
    local prepareStarted=ns.Performance.active and ns.Performance:Begin()
    self:RefreshBindings(run)
    if ignoresReason(run,reason,self.queue) then
        if ns.Performance.active then ns.Performance:Finish("schedule_prepare_ms",prepareStarted) end
        return
    end
    -- Initial contexts need the last observation of every demanded query. Event
    -- deltas alone would mix fresh plate values with missing static ancestors.
    -- Capture actual event demand before adding cached observations used to
    -- initialise new contexts. Cache membership is not a change notification.
    local instanceTokens=collectionUpdates(run,sample,reason)
    sample=G.RuntimeCopy(sample)
    if reason=="initial" and not run.test and next(run.frameReferences or {}) then
        sample.sources=sample.sources or {}
        for reference in pairs(run.frameReferences) do
            local observation=ns.ExternalFrames:Snapshot(reference)
            sample.sources["frame_state:"..reference]={state=observation and observation.state or "pending",binding=observation and observation.binding}
        end
    end
    sample.unitRefs={}
    for token in pairs(run.unitFields or {}) do sample.unitRefs[token]=self:UnitReference(token) end
    if run.test and not run.nodeOverrides then
        sample.units=sample.units or {};sample.unitQueries=sample.unitQueries or {}
        for key,query in pairs(run.queryFields or {}) do
            local observation=G.RuntimeCopy(sample.player or {values={},fields={}})
            observation.values.exists=true;observation.values.name="Example "..query.unit
            sample.unitQueries[key]=observation;sample.units[query.unit]=observation
        end
    end
    if run.collection and reason~="interaction" then
        sample.units=sample.units or {};sample.unitQueries=sample.unitQueries or {}
        -- Unbound collection-only tokens have no context to initialize. Keep
        -- explicit unit dependencies and incoming absence deltas unchanged.
        for key,query in pairs(self.unitQueries or {}) do if query.sample and run.queryFields[key] and needsCachedUnit(run,query.unit) then
            sample.unitQueries[key]=sample.unitQueries[key] or G.RuntimeCopy(query.sample)
            sample.units[query.unit]=sample.units[query.unit] or G.RuntimeCopy(query.sample)
        end end
    end
    if run.unitAuras and (reason=="initial" or reason=="unit" or reason=="aura" or reason=="test") and not run.test then
        sample.auras=sample.auras or {}
        for key in pairs(run.unitAuras) do if self.unitAuraSamples and self.unitAuraSamples[key] then sample.auras[key]=G.RuntimeCopy(self.unitAuraSamples[key]) end end
    end
    if ns.Performance.active then ns.Performance:Finish("schedule_prepare_ms",prepareStarted) end
    if reason=="unit" then
        local match=false
        if sample.unitQueries then for key in pairs(run.queryFields or {}) do if sample.unitQueries[key] then match=true;break end end
        else for token in pairs(run.unitFields or {}) do if sample.units and sample.units[token] then match=true;break end end end
        if not match then return end
    end
    local interaction=reason=="interaction";local inputs=0
    if interaction then for _,item in ipairs(self.queue) do if item.reason=="interaction" then inputs=inputs+1 end end end
    local full=interaction and (inputs>=self.maxInteractions or #self.queue>=self.maxQueue+self.maxInteractions)
        or not interaction and #self.queue>=self.maxQueue
    if full then
        if reason=="interaction" then ns:RecordDisplayInput("full") end
        self:Diagnostic(run.graphId,"scheduler","Queue full; newest observation dropped"); return false
    end
    local bindings={}
    if not run.test then for token in pairs(run.unitFields or {}) do
        bindings[token]=sample.unitGenerations and sample.unitGenerations[token] or self.unitGenerations and self.unitGenerations[token] or 0
    end end
    -- Preparation already owns this snapshot: caller data and added cache
    -- observations were copied above; unit references are opaque handles.
    -- Transfer that ownership to the queue without cloning the whole tree again.
    local item={run=run,sample=sample,reason=reason,now=GetTime(),bindings=bindings,instanceTokens=instanceTokens}
    if ns.Performance.active then ns.Performance:Queued(item);ns.Performance:Count("graph_enqueued") end
    if interaction then
        -- Keep the active job at the head. Pump can serve the next input at a
        -- committed context boundary without moving/replaying the suspended job.
        local index=self.queue[1] and self.queue[1].job and 2 or 1
        while self.queue[index] and self.queue[index].reason=="interaction" do index=index+1 end
        table.insert(self.queue,index,item)
    else self.queue[#self.queue+1]=item end
    if reason=="interaction" then ns:RecordDisplayInput("queued") end
    if not self.timer then self.timer=C_Timer.NewTimer(.001,function() self.timer=nil; self:Pump() end) end
    return true
end
local function pumpItem(self)
    local first,input=self.queue[1],self.queue[2]
    if not first.job or first.reason=="interaction" or not input or input.reason~="interaction" then return first,1 end
    -- A started input stays active across frame slices; all new inputs remain
    -- behind it in the queue. The suspended observation keeps its original age.
    if input.job then return input,2 end
    if not R.InputBoundary(first.job) or first.job.inputServed then return first,1 end
    if input.run.stopped or not self:BindingsCurrent(input) then return input,2 end
    if input.run~=first.run or R.PrioritizeInput(first.job,input.sample) then
        input.suspendedJob=input.run==first.run and first.job or nil
        first.job.inputServed=true -- At most one input before another context progresses.
        if ns.Performance.active then ns.Performance:Count("graph_input_interrupts") end
        return input,2
    end
    return first,1
end
function S:Pump()
    local perfStarted=ns.Performance.active and ns.Performance:Begin()
    local start=debugprofilestop and debugprofilestop() or 0
    local storeStarted=ns.Performance.active and ns.Performance:Begin()
    local steps=0; local budget=self:Store().budget
    if ns.Performance.active then ns.Performance:Finish("graph_store_ms",storeStarted) end
    while #self.queue>0 do
        local item,queueIndex=pumpItem(self)
        local bindingsStarted=ns.Performance.active and ns.Performance:Begin()
        local current=not item.run.stopped and self:BindingsCurrent(item)
        if ns.Performance.active then ns.Performance:Finish("graph_bindings_ms",bindingsStarted) end
        if not current then
            if item.reason=="interaction" then ns:RecordDisplayInput("cancelled") end
            table.remove(self.queue,queueIndex)
        else
            if not item.job and ns.Performance.active then
                ns.Performance:Wait(item,"graph_wait_ms")
                if item.reason=="interaction" then ns.Performance:Wait(item,"click_wait_ms") end
            end
            if not item.job then
                local beginStarted=ns.Performance.active and ns.Performance:Begin()
                item.job=R.Begin(item.run,item.sample,item.reason=="clock" and GetTime() or item.now,item.reason,true,budget,item.suspendedJob,item.instanceTokens)
                if ns.Performance.active then ns.Performance:Finish("graph_begin_ms",beginStarted) end
            end
            local stepStarted=ns.Performance.active and ns.Performance:Begin()
            local ok,done=pcall(R.Step,item.job)
            if ns.Performance.active then ns.Performance:Finish("graph_step_ms",stepStarted) end
            if not ok then self:Diagnostic(item.run.graphId,"runtime",ns.GraphValues.Error(done)); self:DropRun(item.run); done=true end
            steps=steps+1
            if ns.Performance.active then ns.Performance:Count("graph_steps") end
            if done then
                -- Lifecycle callbacks can remove the suspended item while input
                -- runs. Locate this exact item rather than trusting its old slot.
                for index,queued in ipairs(self.queue) do if queued==item then
                    if ok and item.reason=="interaction" and ns.Performance.active then ns.Performance:Wait(item,"click_complete_ms") end
                    if ok and item.reason=="interaction" then ns:RecordDisplayInput("processed") end
                    table.remove(self.queue,index);break
                end end
            end
        end
        if steps>=64 or (debugprofilestop and debugprofilestop()-start>=budget) then break end
    end
    if #self.queue>0 then self.timer=C_Timer.NewTimer(.016,function() self.timer=nil; self:Pump() end) end
    local clockStarted=ns.Performance.active and ns.Performance:Begin()
    self:RefreshClock()
    if ns.Performance.active then ns.Performance:Finish("graph_clock_ms",clockStarted) end
    local notifyStarted=ns.Performance.active and ns.Performance:Begin()
    self:Changed(false)
    if ns.Performance.active then ns.Performance:Finish("graph_notify_ms",notifyStarted) end
    if ns.Performance.active then ns.Performance:Finish("graph_slice_ms",perfStarted) end
end
function S:RefreshClock()
    local needed=R.NeedsClock(self.test)
    for _,run in pairs(self.runs) do needed=needed or R.NeedsClock(run) or run.unitDynamic or (run.unitFields and run.unitFields.mouseover) end
    if not needed then
        if self.clockTimer then self.clockTimer:Cancel(); self.clockTimer=nil end
    elseif not self.clockTimer then
        self.clockTimer=C_Timer.NewTicker(.1,function()
            -- One presence-only check while demanded. The mouseover event can
            -- announce entry without a matching leave event on some clients.
            self:RefreshMouseover(false)
            -- At most two demanded dynamic bindings per shared tick; no broad
            -- per-frame polling. Static fields come from the latest event snapshot.
            local dynamic={}
            for key,query in pairs(self.unitQueries or {}) do
                for field in pairs(query.fields) do if A.UnitDataCatalog.dynamic[field] then dynamic[#dynamic+1]=key;break end end
            end
            table.sort(dynamic)
            if #dynamic>0 then
                local keys={};for _=1,math.min(2,#dynamic) do self.dynamicIndex=(self.dynamicIndex or 0)%#dynamic+1;keys[dynamic[self.dynamicIndex]]=true end
                local sample=self:CaptureUnits(nil,true,keys);for _,run in pairs(self.runs) do self:Schedule(run,sample,"unit") end
            end
            for _,run in pairs(self.runs) do self:Schedule(run,{},"clock") end
            self:Schedule(self.test,{},"clock")
            self:RefreshClock()
        end)
    end
end
function S:DropRun(run)
    if run then
        run.stopped=true;A.Dialogs.Release(run)
        if run.baseRun then run.baseRun.stopped=true;A.Dialogs.Release(run.baseRun)end
        for _,child in pairs(run.children or {})do child.stopped=true;A.Dialogs.Release(child)end
    end
    if not run then return end; run.stopped=true
    ns.Sound:Release(run)
    if A.Memory then A.Memory.Release(run) end
    if self.playerChat then self.playerChat:CancelOwner(run) end
    if R.InvalidateInstances then R.InvalidateInstances(run) end
    for _,cancel in pairs(run.objectRequests or {}) do cancel() end; run.objectRequests={}
    ns.DisplayAnchors:Close(run)
    ns.DisplayAnchors:CloseStacks(run)
    ns.ActionStacks:Close(run)
    for token in pairs(run.children or {}) do if R.InvalidateInstance then R.InvalidateInstance(run,token) end end
    for i=#self.queue,1,-1 do if self.queue[i].run==run then table.remove(self.queue,i) end end
    run.values={};run.auras={};run.state={};run.signals={}
    if #self.queue==0 and self.timer then self.timer:Cancel(); self.timer=nil end
    self:RefreshClock()
end
function S:RefreshFrameWatches()
    local references={}
    for _,run in pairs(self.runs) do if not run.stopped then
        for reference in pairs(run.frameReferences or {}) do references[reference]=true end
    end end
    if not next(references) then ns.ExternalFrames:Unwatch(self);return end
    ns.ExternalFrames:Watch(self,references,function(reference,observation,previous)
        local status=observation and observation.state or "pending"
        if previous and previous.state==status and previous.binding==(observation and observation.binding) then return end -- Geometry does not change this source.
        for _,run in pairs(self.runs) do
            if not run.stopped and run.frameReferences and run.frameReferences[reference] then
                self:Schedule(run,{sources={["frame_state:"..reference]={state=status,binding=observation and observation.binding}}},"frame_state")
            end
        end
    end)
end
function S:Subscriptions()
    self:CancelCDMAuraRefresh()
    if self.source and self.source.ResetTargetEstimates then self.source:ResetTargetEstimates() end
    if self.sourceTimer then self.sourceTimer:Cancel();self.sourceTimer=nil end;self.pendingUnitQueries={};self.pendingAuraQueries={}
    ns.Events:Release(self)
    if self.restrictionTimer then self.restrictionTimer:Cancel(); self.restrictionTimer=nil end
    local needsHP,needsContext,needsAura,needsCooldown=false,false,false,false
    local needsMacros=false
    local chatRules={}
    self.auraRequests={};self.unitAuraRequests={};self.unitAuraSamples={}; self.dataRequests={};self.playerRequests={};self.legacyPlayerFields={};self.unitRequests={};self.unitQueries={};local needsPlayer=false;local needsPower=false; local dataNeeds={};local nativeEvents={}
    for _,run in pairs(self.runs) do
        needsMacros=needsMacros or not run.test and run.needs.macros
        if run.unitAuras then
            needsAura=true
            for key,request in pairs(run.unitAuras) do
                local shared=self.unitAuraRequests[key]
                if not shared then self.unitAuraRequests[key]=G.Copy(request)
                elseif request.realTime then shared.realTime=true end
            end
        end
        for key,query in pairs(run.queryFields or {}) do
            local shared=self.unitQueries[key]
            if not shared then shared={unit=query.unit,options=query.options,fields={}};self.unitQueries[key]=shared end
            for field in pairs(query.fields) do shared.fields[field]=true end
        end
        for token,fields in pairs(run.unitFields or {}) do
            self.unitRequests[token]=self.unitRequests[token] or {}
            for key in pairs(fields) do self.unitRequests[token][key]=true end
        end
        if run.needs.player then
            needsPlayer=true
            for key in pairs(run.playerFields or {}) do self.playerRequests[key]=true end
        end
        for _,id in ipairs(run.plan.order) do local kind=run.plan.graph.nodes[id].type
            needsHP=needsHP or kind=="hp" or (kind=="media_bar" and run.plan.graph.nodes[id].config.source=="player_health")
            needsContext=needsContext or kind=="context"; needsCooldown=needsCooldown or kind=="icon_cooldown"
            if kind=="hp" then self.legacyPlayerFields.health=true;self.legacyPlayerFields.healthMax=true end
            if kind=="context" then self.legacyPlayerFields.combat=true end
            if A.catalog[kind].dataSource then
                local config=run.plan.graph.nodes[id].config
                self.dataRequests[A.DataSource.Key(kind,config)]={kind=kind,config=config}
                dataNeeds[A.DataSource.reasons[kind]]=true
                needsCooldown=needsCooldown or kind=="spell_cooldown" or kind=="spell_charges"
            end
            if A.catalog[kind].nativeEvent then nativeEvents[kind]=true end
            if kind=="chat_receive" then chatRules[#chatRules+1]={owner=run,nodeID=id,config=run.plan.graph.nodes[id].config} end
            if A.catalog[kind].sourceFamily=="cast" then nativeEvents.unit_cast=true end
            if kind=="aura" then
                needsAura=true; local c=run.plan.graph.nodes[id].config
                self.auraRequests[A.AuraSource.Key(c.spellID,c.filter)]={spellID=c.spellID,filter=c.filter}
            end
        end
    end
    self:RefreshMessaging()
    self:RefreshFrameWatches()
    if needsMacros then ns.Events:Subscribe(self,"UPDATE_MACROS",function()
        for _,run in pairs(self.runs) do
            if not run.test and run.needs.macros then self:Schedule(run,{},"macros") end
        end
        -- All dynamic definitions share the same removal contract, including
        -- operation changes such as Logic AND -> NOT, not only count edits.
        if config then
            local nextDef,why=G.Definition(A.catalog[n.type],n);assert(nextDef,why)
            local nextPorts=G.Ports(nextDef)
            for input in pairs(G.Ports(def)) do if not nextPorts[input] then
                assert(not G.Binding(g,id,input),"Disconnect "..input.." before removing it")
                n.values[input]=nil;n.exposed[input]=nil
            end end
        end
    end) end
    local chat=self:EnsurePlayerChat()
    local _,excess=chat:SetReceivers(chatRules,function(owner,packet)
        if not owner.stopped and self.runs[owner.graphId]==owner then self:Schedule(owner,{sourceEvent=packet},"source_event") end
    end)
    if excess>0 then self:Diagnostic("chat","receivers","Chat receiver limit reached (128); excess rules are inactive") end
    for _,event in ipairs(chat:Events())do
        local eventName=event
        ns.Events:Subscribe(self,eventName,function(_,...)chat:Receive(eventName,...)end)
    end
    if self.unitQueries.player then for field in pairs(self.legacyPlayerFields) do self.unitQueries.player.fields[field]=true end end
    for key in pairs(self.playerRequests) do
        if key=="health" or key=="healthMax" or key=="healthPercent" then needsHP=true
        elseif key=="mounted" or key=="resting" or key=="moving" then dataNeeds.player_state=true
        elseif key=="combat" then needsContext=true
        else needsPower=true end
    end
    local function listen(event,reason)
        ns.Events:Subscribe(self,event,function(_,unit)
            if reason=="talents" and (event=="TRAIT_NODE_CHANGED" or event=="TRAIT_NODE_CHANGED_PARTIAL") and G.Number(unit) then
                local requested=false
                for _,query in pairs(self.dataRequests)do if query.kind=="player_talent" and query.config.nodeID==unit then requested=true;break end end
                if not requested then return end
            end
            if reason=="hp" or reason=="aura" or reason=="power" or (reason=="xp" and (event=="PLAYER_XP_UPDATE" or event=="UNIT_LEVEL")) then
                if issecretvalue and issecretvalue(unit) then return end
                if unit and unit~="player" then return end
            end
            local ok,why=pcall(function()
                if (event=="PLAYER_REGEN_ENABLED" or event=="PLAYER_ENTERING_WORLD") and self.source and self.source.ResetTargetEstimates then self.source:ResetTargetEstimates() end
                local sample=self:Sample(reason,event); for _,run in pairs(self.runs) do self:Schedule(run,sample,reason) end
                if event=="UNIT_AURA" and unit=="player" then self:QueueCDMAuraRefresh() end
            end)
            if not ok then self:Diagnostic("sources",event,ns.GraphValues.Error(why)) end
        end)
    end
    if next(self.unitRequests) or needsPlayer then
        local function subscribe(event,fn)
            ns.Events:Subscribe(self,event,function(_,unit)
                local ok,why=pcall(fn,unit,event)
                if not ok then self:Diagnostic("units",event,ns.GraphValues.Error(why)) end
            end)
        end
        local function refresh(unit,event)
            -- Aliases may refer to the same entity without a readable identity.
            -- Reacquire compound targets on unit events; never compare GUIDs.
            if G.IsSecret(unit) then self:ObserveUnits(nil,true);return end
            local sharedHP=needsHP and (event=="UNIT_HEALTH" or event=="UNIT_MAXHEALTH")
            local sharedPower=needsPower and (event=="UNIT_POWER_UPDATE" or event=="UNIT_MAXPOWER" or event=="UNIT_DISPLAYPOWER")
            local tokens={target=true,focus=true,targettarget=true,focustarget=true}
            if type(unit)=="string" and not (unit=="player" and (sharedHP or sharedPower)) then tokens[unit]=true end
            self:ObserveUnits(tokens,false,event~="UNIT_AURA")
            if event=="UNIT_AURA" and unit=="target" then self:QueueCDMAuraRefresh("target") end
        end
        for _,event in ipairs({"UNIT_HEALTH","UNIT_MAXHEALTH","UNIT_POWER_UPDATE","UNIT_MAXPOWER","UNIT_DISPLAYPOWER","UNIT_FLAGS","UNIT_NAME_UPDATE","UNIT_LEVEL","UNIT_CLASSIFICATION_CHANGED","UNIT_FACTION","UNIT_CONNECTION","UNIT_THREAT_LIST_UPDATE","UNIT_THREAT_SITUATION_UPDATE","UNIT_AURA","UNIT_ABSORB_AMOUNT_CHANGED","UNIT_HEAL_ABSORB_AMOUNT_CHANGED","UNIT_HEAL_PREDICTION","UNIT_SPELLCAST_START","UNIT_SPELLCAST_STOP","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_DELAYED","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_CHANNEL_UPDATE","UNIT_SPELLCAST_CHANNEL_STOP","UNIT_SPELLCAST_EMPOWER_START","UNIT_SPELLCAST_EMPOWER_UPDATE","UNIT_SPELLCAST_EMPOWER_STOP","UNIT_SPELLCAST_INTERRUPTIBLE","UNIT_SPELLCAST_NOT_INTERRUPTIBLE","LOSS_OF_CONTROL_ADDED","LOSS_OF_CONTROL_UPDATE"}) do subscribe(event,refresh) end
        subscribe("UNIT_PET",function(unit)
            if G.IsSecret(unit) or unit=="player" then self:ObserveUnits({pet=true},true) end
        end)
        subscribe("NAME_PLATE_UNIT_ADDED",function(unit)
            if not G.IsSecret(unit) and A.UnitSource.ValidToken(unit) and unit:match("^nameplate") then
                self.visibleNameplates=self.visibleNameplates or {};self.visibleNameplates[unit]=true
                if self.nameplateAbsent then self.nameplateAbsent[unit]=nil end;self:ObserveUnits({[unit]=true},true)
            end
        end)
        subscribe("NAME_PLATE_UNIT_REMOVED",function(unit)
            if G.IsSecret(unit) then
                self.visibleNameplates={}
                local tokens={};self.nameplateAbsent=self.nameplateAbsent or {}
                for token in pairs(self.unitRequests) do if token:match("^nameplate") then tokens[token]=true;self.nameplateAbsent[token]="unknown" end end
                self:InvalidateUnits(tokens);return
            end
            if not self.unitRequests[unit] then return end
            if self.visibleNameplates then self.visibleNameplates[unit]=nil end
            self.nameplateAbsent=self.nameplateAbsent or {};self.nameplateAbsent[unit]=true
            self:InvalidateUnits({[unit]=true});self.unitPresence[unit]="absent"
            local observation={values={exists=false},fields={},status="absent"}
            for key in pairs(self.unitRequests[unit]) do observation.fields[key]=key=="exists" and "readable" or "absent" end
            local sample={units={[unit]=observation},unitQueries={},unitGenerations={[unit]=self.unitGenerations[unit]}}
            for key,query in pairs(self.unitQueries or {}) do if query.unit==unit then query.sample=G.RuntimeCopy(observation);sample.unitQueries[key]=observation end end
            for _,run in pairs(self.runs) do self:Schedule(run,sample,"unit") end
        end)
        subscribe("RAID_TARGET_UPDATE",function()self:ObserveUnits()end)
        local playerFields=self.unitRequests.player or {}
        if playerFields.moneyCopper then subscribe("PLAYER_MONEY",function()self:ObserveUnits({player=true},false,true)end) end
        local needsXP=false
        for field in pairs(playerFields) do if A.UnitSource.playerFields[field] and A.UnitSource.playerFields[field].kind=="player_xp" then needsXP=true end end
        if needsXP then for _,event in ipairs({"PLAYER_XP_UPDATE","PLAYER_LEVEL_UP","PLAYER_MAX_LEVEL_UPDATE","UPDATE_EXPANSION_LEVEL","UPDATE_EXHAUSTION","ENABLE_XP_GAIN","DISABLE_XP_GAIN"}) do
            subscribe(event,function()self:ObserveUnits({player=true},false,true)end)
        end end
        local function refreshRoles()
            local tokens={}
            for token,fields in pairs(self.unitRequests) do if fields.roleIcon or fields.groupRolesAssigned or fields.groupRolesAssignedEnum then tokens[token]=true end end
            if next(tokens) then self:ObserveUnits(tokens,false) end
        end
        subscribe("PLAYER_ROLES_ASSIGNED",refreshRoles)
        subscribe("ROLE_CHANGED_INFORM",refreshRoles)
        subscribe("PLAYER_TARGET_CHANGED",function()
            self:ObserveUnits({target=true,targettarget=true},true)
            self:QueueCDMAuraRefresh("target")
        end)
        subscribe("PLAYER_FOCUS_CHANGED",function() self:ObserveUnits({focus=true,focustarget=true},true) end)
        if self.unitRequests.mouseover then subscribe("UPDATE_MOUSEOVER_UNIT",function()self:RefreshMouseover(true)end) end
        subscribe("UNIT_TARGET",function()
            -- Parent aliases are not identity-safe to compare. Both compound
            -- bindings are bounded and must discard their old entity epochs.
            self:ObserveUnits({targettarget=true,focustarget=true},true)
        end)
        subscribe("GROUP_ROSTER_UPDATE",function()
            local tokens={};for token in pairs(self.unitRequests) do if token:match("^party") or token:match("^raid") then tokens[token]=true end end
            self:ObserveUnits(tokens,true)
        end)
        subscribe("PLAYER_ENTERING_WORLD",function() self.visibleNameplates={};self.nameplateAbsent={};self:InvalidateUnits(self.unitRequests) end)
    end
    if needsHP then listen("UNIT_HEALTH","hp"); listen("UNIT_MAXHEALTH","hp") end
    if needsPower then
        listen("UNIT_POWER_UPDATE","power");listen("UNIT_MAXPOWER","power");listen("UNIT_DISPLAYPOWER","power")
    end
    if needsAura then listen("UNIT_AURA","aura") end
    if needsCooldown then listen("SPELL_UPDATE_COOLDOWN","cooldown"); listen("SPELL_UPDATE_CHARGES","cooldown") end
    if dataNeeds.player_state then
        for _,event in ipairs({"PLAYER_MOUNT_DISPLAY_CHANGED","PLAYER_UPDATE_RESTING","PLAYER_STARTED_MOVING","PLAYER_STOPPED_MOVING"}) do listen(event,"player_state") end
    end
    if dataNeeds.location then
        for _,event in ipairs({"ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA"}) do listen(event,"location") end
    end
    if dataNeeds.inventory then listen("BAG_UPDATE_DELAYED","inventory"); listen("PLAYER_EQUIPMENT_CHANGED","inventory") end
    if dataNeeds.proc then listen("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW","proc"); listen("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE","proc") end
    if dataNeeds.usable then listen("SPELL_UPDATE_USABLE","usable") end
    if dataNeeds.totem then listen("PLAYER_TOTEM_UPDATE","totem") end
    if dataNeeds.talents then
        for _,event in ipairs({"TRAIT_CONFIG_UPDATED","TRAIT_NODE_CHANGED","TRAIT_NODE_CHANGED_PARTIAL","ACTIVE_PLAYER_SPECIALIZATION_CHANGED","ACTIVE_TALENT_GROUP_CHANGED","PLAYER_TALENT_UPDATE","PLAYER_ENTERING_WORLD"})do listen(event,"talents")end
    end
    if dataNeeds.xp then for _,event in ipairs({"PLAYER_XP_UPDATE","UNIT_LEVEL","PLAYER_LEVEL_UP","PLAYER_MAX_LEVEL_UPDATE","UPDATE_EXPANSION_LEVEL","UPDATE_EXHAUSTION","ENABLE_XP_GAIN","DISABLE_XP_GAIN"})do listen(event,"xp")end end
    if dataNeeds.money then listen("PLAYER_MONEY","money") end
    if dataNeeds.currency then listen("CURRENCY_DISPLAY_UPDATE","currency") end
    if dataNeeds.reputation then for _,event in ipairs({"UPDATE_FACTION","FACTION_STANDING_CHANGED","MAJOR_FACTION_RENOWN_LEVEL_CHANGED"})do listen(event,"reputation")end end
    for _,reason in ipairs({"spellbook","usable","cooldown"}) do
        if dataNeeds[reason] then listen("SPELLS_CHANGED",reason) end
    end
    for kind,event in pairs({player_cast="UNIT_SPELLCAST_SUCCEEDED",player_swing="PLAYER_SWING"}) do
        if nativeEvents[kind] and not (kind=="player_cast" and nativeEvents.unit_cast) then ns.Events:Subscribe(self,event,function(_,a,b,c)
            local packet=self.dataSource:Event(event,a,b,c)
            if packet then for _,run in pairs(self.runs) do if run.needs[packet.kind] then self:Schedule(run,{sourceEvent=packet},"source_event") end end end
        end) end
    end
    for kind,events in pairs({encounter_event={"ENCOUNTER_START","ENCOUNTER_END"},ready_check_event={"READY_CHECK","READY_CHECK_FINISHED"}}) do
        if nativeEvents[kind] then for _,event in ipairs(events) do ns.Events:Subscribe(self,event,function(_,a,b,c,d,e)
            local packet=self.dataSource:Event(event,a,b,c,d,e)
            if packet then for _,run in pairs(self.runs) do if run.needs[packet.kind] then self:Schedule(run,{sourceEvent=packet},"source_event") end end end
        end) end end
    end
    if nativeEvents.unit_cast then ns.Events:Subscribe(self,"UNIT_SPELLCAST_SUCCEEDED",function(_,unit,castID,spellID)
        if G.IsSecret(unit) or not A.UnitSource.ValidToken(unit) then return end
        local value
        if G.IsSecret(spellID) then value=G.Capture(spellID,"integer")
        elseif G.Number(spellID) and spellID>0 and spellID==math.floor(spellID) then value=spellID end
        local sample=self:CaptureUnits({[unit]=true});sample.sourceEvent={kind="unit_cast",unit=unit,spellID=value}
        for _,run in pairs(self.runs) do if run.needs.unit_cast or run.needs.nameplates_cast then self:Schedule(run,sample,"source_event") end end
        if nativeEvents.player_cast then
            local legacy=self.dataSource:Event("UNIT_SPELLCAST_SUCCEEDED",unit,castID,spellID)
            if legacy then for _,run in pairs(self.runs) do if run.needs.player_cast then self:Schedule(run,{sourceEvent=legacy},"source_event") end end end
        end
    end) end
    if needsHP or needsContext or needsAura or needsCooldown or needsPlayer or next(self.unitRequests) or next(dataNeeds) or next(nativeEvents) then
        listen("PLAYER_REGEN_DISABLED",(needsAura or needsHP or needsCooldown or next(self.unitRequests) or next(dataNeeds)) and "initial" or "context")
        listen("PLAYER_REGEN_ENABLED",(needsAura or needsHP or needsCooldown or next(self.unitRequests) or next(dataNeeds)) and "initial" or "context")
    end
    if needsHP or needsContext or needsAura or needsCooldown or needsPlayer or next(self.unitRequests) or next(dataNeeds) or next(nativeEvents) then
        listen("PLAYER_ENTERING_WORLD","initial")
        ns.Events:Subscribe(self,"ADDON_RESTRICTION_STATE_CHANGED",function()
            self:InvalidateUnits(self.unitRequests or {})
            -- Activating fires before enforcement. Discard queued snapshots and
            -- stale observations now; reacquire after this native event dispatch.
            for _,run in pairs(self.runs) do
                run.values={}; run.signals={}; run.trace={}; run.auras={}
                for id in pairs(run.plan.active) do
                    local def=run.plan.definitions[id]
                    -- This event can precede lockdown. A prepared action is not
                    -- an observation: hiding it here strands it through combat.
                    -- Clear only its stale suggestion; preserve action visibility.
                    if def.actionStack then ns.ActionStacks:Clear(run,id)
                    elseif def.secureAction then ns.DisplayAnchors:SetSecureHint(run,id,nil)
                    elseif def.display then ns.DisplayAnchors:Set(run,id,false) end
                end
            end
            for i=#self.queue,1,-1 do if not self.queue[i].run.test then table.remove(self.queue,i) end end
            if self.restrictionTimer then self.restrictionTimer:Cancel() end
            self.restrictionTimer=C_Timer.NewTimer(.001,function()
                self.restrictionTimer=nil
                local sample=self:Sample(); for _,run in pairs(self.runs) do self:Schedule(run,sample,"initial") end
            end)
        end)
    end
end
function S:Apply()
    if InCombatLockdown() then self.message="Save is unavailable in combat"; self:Changed(); return false end
    local rec=self:Graph(); local ok,plan,err=pcall(G.Compile,rec.draft,A.catalog)
    if not ok or not plan then self.validation=ok and err or {message=ns.GraphValues.Error(plan)}; self.message=self.validation.message; self:Changed(); return false end
    for _,id in ipairs(plan.order) do
        local def=plan.definitions[id];local layout=plan.graph.nodes[id].config.layoutId
        if def.secureAction and not ns.SecureSpells:ValidLayout(layout) then
            self.message="Secure spell buttons require a free screen position (no anchor or size links)";self:Changed();return false
        elseif def.actionDisplay and not ns.SecureActionMedia:ValidLayout(layout) then
            self.message="Action Display requires screen-based layout links (no cursor, nameplate, external frame or template)";self:Changed();return false
        end
    end
    for _,id in ipairs(plan.order) do if plan.definitions[id].displayStack then
        local config=plan.graph.nodes[id].config;local records={};local stored=ns.Layout:Store()
        if plan.definitions[id].actionStack then
            local valid,why=ns.ActionStacks:ValidLayout(config)
            if not valid then self.message=why;self:Changed();return false end
        end
        for _,element in ipairs(config.elements) do records[element.layoutId]=stored[element.layoutId] end
        local rects=ns.Layout:Resolve()
        local template,why=ns.LayoutModel.ResolveTemplate(records,config.layoutId,rects[config.layoutId])
        if not template then self.message=why;self:Changed();return false end
    end end
    local old=self.runs[rec.id]; local candidate
    if self.active and rec.enabled and self:GroupAllows(rec) then
        local made,value=pcall(self.MakeRun,self,rec,plan,false)
        if not made then self.message="Save unchanged: "..ns.GraphValues.Error(value); self:Changed(); return false end
        candidate=value
    end
    self.runs[rec.id]=candidate
    local registered,why=pcall(self.Subscriptions,self)
    if not registered then self.runs[rec.id]=old; if candidate then self:DropRun(candidate) end; pcall(self.Subscriptions,self); self.message="Source setup failed: "..ns.GraphValues.Error(why); self:Changed(); return false end
    self:EndTest(); self:DropRun(old)
    rec.applied=G.Copy(rec.draft); rec.revision=rec.revision+1; rec.appliedDraftRevision=rec.draftRevision
    self:CaptureLayouts()
    if candidate then candidate.appliedRevision=rec.revision; self:Schedule(candidate,self:Sample(),"initial") end
    self.validation=nil; self.message="Saved revision "..rec.revision..(candidate and " (live)" or " (live disabled)"); self:Changed(); return true
end
function S:SetGraphEnabled(enabled,id)
    if InCombatLockdown() then self.message="Change graph activation after combat"; self:Changed(); return false end
    local rec
    if id then rec=assert(self:Store().graphs[id],"Unknown graph") else rec=assert(self:Graph(),"Unknown graph") end
    if enabled and not rec.applied then self.message="Save a valid graph first"; self:Changed(); return false end
    if enabled and not self.active then self.message="Enable the AuraStudio module first"; self:Changed(); return false end
    return self:ChangeActivation(function() rec.enabled=enabled==true end)
end
function S:TestSample(before,current,maximum,combat,auraPresent,auraSeconds,protectedHP,protectedAura)
    if not G.Number(before) or not G.Number(current) or not G.Number(maximum) or maximum<=0 or before<0 or current<0 or before>maximum or current>maximum then self.message="Use HP values between 0 and a positive maximum"; self:Changed(); return false end
    local rec=self:Graph(); if not rec.applied then self.message="Apply a valid snapshot before testing"; self:Changed(); return false end
    auraSeconds=auraSeconds or 0
    if not G.Number(auraSeconds) or auraSeconds<0 or auraSeconds>86400 then self.message="Aura test duration must be 0..86400 seconds"; self:Changed(); return false end
    local function simulated(hp,present)
        local result={current=hp,maximum=maximum,combat=combat,auras={}}
        if protectedHP then result.current=nil; result.hpFields={current="protected",maximum="readable"} end
        if result.combat==nil then result.combat=false end
        result.player={values={health=result.current,healthMax=maximum,combat=result.combat},
            fields={health=protectedHP and "protected" or "readable",healthMax="readable",combat="readable",
                healthPercent=protectedHP and "protected" or "readable"}}
        if not protectedHP then result.player.values.healthPercent=100*hp/maximum end
        -- Resource values require explicit synthetic observations; the HP test
        -- controls never query or impersonate live mana/energy/other power.
        for _,node in pairs(rec.applied.nodes) do
            if node.type=="aura" or A.catalog[node.type].auraSource then
                local values=present and {present=true,stacks=1,duration=auraSeconds,hasExpiration=auraSeconds>0} or {present=false}
                local observation={values=values,observedAt=GetTime(),status=present and "test present" or "test absent",
                    fields={remaining=present and auraSeconds==0 and "permanent" or not present and "absent" or "readable"}}
                if present then observation.expirationTime=auraSeconds>0 and GetTime()+auraSeconds or 0 end
                if protectedAura and present then
                    values.duration=nil; values.hasExpiration=nil; observation.expirationTime=nil
                    observation.fields={duration="protected",remaining="protected",hasExpiration="protected"}
                end
                if A.catalog[node.type].collectionSource then
                    for i,token in ipairs(A.CollectionTokens(A.catalog[node.type],node.config)) do if i<=3 then result.auras[A.AuraSource.Key(node.config.spellID,node.config.filter,token)]=G.RuntimeCopy(observation) end end
                else result.auras[A.AuraSource.Key(node.config.spellID,node.config.filter,node.type~="aura" and A.UnitSource.Token(node.type,node.config) or nil)]=observation end
            end
        end
        return result
    end
    if not self.test then
        local plan,err=G.Compile(rec.applied,A.catalog); if not plan then self.message=err.message; self:Changed(); return false end
        self.test=self:MakeRun(rec,plan,true)
        self:Schedule(self.test,simulated(before,false),"initial")
    end
    self:Schedule(self.test,simulated(current,auraPresent==true),"test")
    self.message="Test signal queued (applied revision "..rec.revision..")"; self:Changed(); return true
end
function S:EndTest() self:DropRun(self.test); self.test=nil end
function S:Retry()
    for _,run in pairs(self.runs) do for _,s in pairs(run.state) do s.failures=0; s.retryAt=nil; s.paused=nil end end
    if self.test then for _,s in pairs(self.test.state) do s.failures=0; s.retryAt=nil; s.paused=nil end end
    self.message="Fault backoff cleared; next observation may retry"; self:Changed()
end
function S:Trace()
    local rec=self:Graph(); local run=self.test or (rec and self.runs[rec.id]); return run and run.trace or {},run
end
function S:Changed(full)
    if self.editor and self.editor.window:IsShown() then
        if full~=false then self.editor:Refresh() else self.editor.dirtyDebug=true end
    end
    if self.quick and self.quick:IsShown() then self.quick:Refresh() end
end
function S:Stop()
    self:CancelCDMAuraRefresh()
    if self.source and self.source.ResetTargetEstimates then self.source:ResetTargetEstimates() end
    if A.infoDiagnostics then A.infoDiagnostics:Stop() end
    ns.ExternalFrames:Unwatch(self)
    ns.Events:Release(self); self:EndTest()
    if self.playerChat then self.playerChat:Stop();self.playerChat=nil end
    self.unitRefs={};self.visibleNameplates={};self.unitAuraRequests={};self.unitAuraSamples={}
    if self.messaging then self.messaging:Stop();self.messaging=nil end
    if self.restrictionTimer then self.restrictionTimer:Cancel(); self.restrictionTimer=nil end
    for _,run in pairs(self.runs) do self:DropRun(run) end; self.runs={}; self.queue={}
    if self.clockTimer then self.clockTimer:Cancel();self.clockTimer=nil end
    self.mouseoverPresence=nil
    if self.timer then self.timer:Cancel(); self.timer=nil end
    self.auraRequests={}; self.dataRequests={};self.playerRequests={};self.legacyPlayerFields={};self.playerSource=nil;self.unitSource=nil;if self.sourceTimer then self.sourceTimer:Cancel();self.sourceTimer=nil end;self.pendingUnitQueries={};self.pendingAuraQueries={};self.unitRequests={};self.unitQueries={};self.unitPresence={};self.unitGenerations={};self.dynamicIndex=nil;self.nameplateAbsent={}; self.active=false; ns.DisplayAnchors.nativeSource=nil;ns.DisplayAnchors.inputHandler=nil; if self.editor then self.editor:Close() end
    if self.quick then self.quick:Hide() end
end
function S:Start(ctx)
    self.active=true; ctx:Defer(function() self:Stop() end)
    ns.DisplayAnchors.nativeSource=A.NativeSource.New(_G)
    ns.DisplayAnchors.inputHandler=function(owner,packet) self:Interaction(owner,packet) end
    self.dataSource=A.DataSource.New(_G)
    self.playerSource=A.PlayerSource.New(_G)
    self:RefreshMessaging()
    self:RestoreLayouts()
    for _,rec in pairs(self:Store().graphs) do
        if rec.enabled and rec.applied and self:GroupAllows(rec) then
            local ok,plan,err=pcall(G.Compile,rec.applied,A.catalog)
            if ok and plan then
                local made,run=pcall(self.MakeRun,self,rec,plan,false)
                if made then self.runs[rec.id]=run else self:Diagnostic(rec.id,"load",ns.GraphValues.Error(run)) end
            else self:Diagnostic(rec.id,"load",ok and err.message or ns.GraphValues.Error(plan)) end
        end
    end
    local ok,why=pcall(self.Subscriptions,self)
    if not ok then ns.Events:Release(self); self:Diagnostic("sources","registration",ns.GraphValues.Error(why)); for _,r in pairs(self.runs) do self:DropRun(r) end; self.runs={} end
    local sample=self:Sample(); for _,run in pairs(self.runs) do self:Schedule(run,sample,"initial") end
    self:RefreshQuick()
end
function S:Open()
    self:RestoreLayouts()
    if not self:Graph() then self:New(false) end
    self.editor=self.editor or ns.UI:GraphEditor(self)
    self.editor:Open()
end
-- The shared editor can preview disabled drafts without enabling their graphs.
ns.DisplayAnchors.diagnose=function(layoutID,message)
    for _,rec in pairs(S:Store().graphs) do
        for _,graph in pairs({rec.draft,rec.applied}) do
            for id,node in pairs(graph.nodes) do
                if node.config.layoutId==layoutID then S:Diagnostic(rec.id,id,message); return end
            end
        end
    end
end
ns.DisplayAnchors.previewProvider=function()
    local out={}
    for _,rec in pairs(S:Store().graphs) do
        for _,node in pairs(rec.draft.nodes) do if (node.type=="icon" or A.catalog[node.type].secureAction) and node.config.layoutId then
            out[node.config.layoutId]={texture=node.config.spellIcon or node.config.texture,cropBorder=node.config.cropBorder}
        end end
        local plan=G.Compile(rec.draft,A.catalog,true)
        if plan then
            local run=R.New(plan,function() end,function() end)
            R.Run(run,{},0,"initial") -- Pure preview: no native observations or side effects.
            for id,node in pairs(rec.draft.nodes) do if (node.type=="display" or A.catalog[node.type].actionDisplay) and node.config.layoutId then
                local e=plan.incoming[id].media; local value=e and run.values[e.from]
                if value and value[e.output] then out[node.config.layoutId]={media=value[e.output]} end
            end end
        end
    end
    return out
end
function S:RestoreLayouts()
    ns.Layout:Store() -- Migrate legacy groups before capturing canonical geometry.
    for _,rec in pairs(self:Store().graphs) do
        if rec.applied then self:PrepareDisplays(rec.applied,rec) end
        self:PrepareDisplays(rec.draft,rec)
    end
    self:CaptureLayouts()
end
ns.Layout:AfterSave(S,function() S:CaptureLayouts() end)
ns.Modules:Register({id="aura_studio",OnEnable=function(ctx) S:Start(ctx) end,OnDisable=function() S:Stop() end})
ns.Config:RegisterPage("aurastudio",{title="AuraStudio",description="Build and test reactive graphs in game.",
    build=function(parent) return ns.UI:AuraStudioPage(parent,S) end,
    refresh=function() if S.page then S.page:Refresh() end end})
ns.Commands:Register("aura","aura_studio","aurastudio",function() S:Open() end)
ns.Commands:Register("aurastudio","aura_studio","aurastudio",function() S:Open() end)
ns.Settings:BeforeProfileChange(S,function() S:Stop(); S.histories={}; S.errors={}; S.inspectApplied=false end)
ns.Settings:AfterProfileChange(S,function() S:RefreshQuick() end)
local quickLogin={}
if ns.ready and IsLoggedIn() then S:RefreshQuick()
else ns.Events:Subscribe(quickLogin,"PLAYER_LOGIN",function() ns.Events:Release(quickLogin); S:RefreshQuick() end) end
if ns.ready and IsLoggedIn() then ns.Modules:Reconcile() end

ns.Commands:RegisterAction("info",function(action)
    local ok,why=A.infoDiagnostics:Command(action or "report");if not ok then ns:Print(why) end
end)

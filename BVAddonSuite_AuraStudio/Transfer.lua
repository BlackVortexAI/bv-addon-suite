-- AuraStudio transfer contract. No frames, native observations or executable data.
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local S,G,C=ns.AuraStudio,A.G,ns.TransferCodec
local T={}; A.Transfer=T
local function fields(t,list)
    assert(type(t)=="table","Expected transfer object")
    local allowed={}; for key in list:gmatch("%S+") do allowed[key]=true end
    for k in pairs(t) do assert(allowed[k],"Unsupported transfer field: "..tostring(k)) end
end
local function name(v) assert(type(v)=="string" and #v>0 and #v<=80 and v:find("%S") and not v:find("[%c|]"),"Invalid transfer name"); return v end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function array(t,max) assert(type(t)=="table" and #t<=max,"Transfer array limit"); for k in pairs(t) do assert(type(k)=="number" and k>=1 and k<=#t and k==math.floor(k),"Invalid transfer array") end end
local function bounded(v,lo,hi) assert(G.Number(v) and v>=lo and v<=hi,"Invalid transfer number"); return v end
local function flag(v) assert(v==nil or type(v)=="boolean","Invalid transfer flag") end
local function identity(id) return type(id)=="string" and #id==40 and id:match("^bv_aura:%x+$") end
local function refs(raw) return {raw.widthTarget,raw.heightTarget,raw.link and raw.link.target,raw.templateId,raw.templateRoot} end
local function builtin(id) return id==ns.Layout.CURSOR_TARGET or id=="builtin:nameplate" end
local function external(id)
    local name=type(id)=="string" and id:match("^frame:(.+)$")
    return name and ns.FrameLibrary:ValidateReference(name) or false
end
local function endpoint(id)return builtin(id) or external(id)end
local function frameReferences(packet)
    local wanted={}
    for _,raw in pairs(packet.layouts or {}) do
        for _,id in pairs(refs(raw)) do local ref=type(id)=="string" and id:match("^frame:(.+)$");if ref then wanted[ref]=true end end
    end
    for _,rec in ipairs(packet.graphs or {}) do
        for _,node in pairs(rec.graph.nodes) do
            if node.type=="frame_state" and node.config.reference~="" then wanted[node.config.reference]=true end
        end
    end
    return wanted
end
local function frameEntries(packet)
    if packet.frames then return packet.frames end
    local out={}
    for ref in pairs(frameReferences(packet)) do out[ref]={reference=ref,label=ref:sub(1,96)} end
    return out
end
local function libraryStamp()
    local store,why=ns.FrameLibrary:Store();assert(store,why);return C.Serialize(store)
end
local function displayIDs(node)
    local out={};local def=A.catalog[node.type]
    if def and def.displayStack then for _,element in ipairs(node.config.elements or {})do out[#out+1]=element.layoutId end
    elseif def and (def.display or def.layoutOwner) then out[1]=node.config.layoutId end
    return out
end
local function same(a,b) return C.Serialize(a)==C.Serialize(b) end
local function geometry(raw)
    local out=G.Copy(raw); out.label=nil; out.previewTexture=nil; out.fallback=nil
    return ns.LayoutModel.Normalize(out)
end
local layoutFields="anchorPoint displayAnchor label previewTexture width height x y screen zIndex link widthTarget heightTarget collapseWidth collapseHeight collapseGap fallback templateId templateRoot stack"
local function validateLayout(id,raw)
    assert(identity(id),"Invalid layout identity"); fields(raw,layoutFields)
    assert((raw.anchorPoint==1 and raw.displayAnchor==nil) or (raw.displayAnchor==1 and raw.anchorPoint==nil),"Unsupported layout element")
    if raw.anchorPoint==1 then name(raw.label)
    else assert(type(raw.label)=="string" and #raw.label<=160 and not raw.label:find("[%c|]"),"Invalid display label") end
    bounded(raw.width,0,5000); bounded(raw.height,0,2000); bounded(raw.x,-10000,10000); bounded(raw.y,-10000,10000)
    if raw.zIndex~=nil then bounded(raw.zIndex,-1000,1000);assert(raw.zIndex==math.floor(raw.zIndex),"Invalid Z index") end
    assert(({CENTER=true,LEFT=true,RIGHT=true,TOP=true,BOTTOM=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true})[raw.screen],"Invalid screen anchor")
    flag(raw.collapseWidth); flag(raw.collapseHeight); flag(raw.collapseGap)
    if raw.previewTexture~=nil then assert(ns.IconCatalog:Reference(raw.previewTexture),"Invalid preview texture") end
    assert(not builtin(raw.widthTarget) and not builtin(raw.heightTarget),"Built-in position anchors cannot be size targets")
    for _,id2 in pairs(refs(raw)) do assert(identity(id2) or endpoint(id2),"Unsupported external anchor reference") end
    if raw.link then
        fields(raw.link,"target side align gap offset")
        assert(({LEFT=true,RIGHT=true,TOP=true,BOTTOM=true,CENTER=true})[raw.link.side],"Invalid anchor side")
        assert(raw.link.align==nil or ({START=true,CENTER=true,END=true})[raw.link.align],"Invalid anchor alignment")
        bounded(raw.link.gap,-10000,10000); bounded(raw.link.offset,-10000,10000)
    end
    if raw.fallback then fields(raw.fallback,"x y width height"); bounded(raw.fallback.x,-10000,10000); bounded(raw.fallback.y,-10000,10000); bounded(raw.fallback.width,0,5000); bounded(raw.fallback.height,0,2000) end
    if raw.templateId~=nil or raw.templateRoot~=nil then
        assert(raw.displayAnchor==1 and identity(raw.templateId) and raw.templateId==raw.templateRoot,"Invalid display template identity")
    end
    if raw.stack then
        assert(raw.anchorPoint==1,"Stack settings belong to a neutral anchor")
        fields(raw.stack,"direction gap sort descending align maxEntries")
        assert(({DOWN=true,UP=true,LEFT=true,RIGHT=true})[raw.stack.direction],"Invalid stack direction")
        bounded(raw.stack.gap,0,1000);assert(({APPEARANCE=true,NUMERIC=true,ALPHABETICAL=true})[raw.stack.sort],"Invalid stack sort")
        flag(raw.stack.descending);assert(({START=true,CENTER=true,END=true})[raw.stack.align],"Invalid stack alignment")
        bounded(raw.stack.maxEntries,1,40);assert(raw.stack.maxEntries==math.floor(raw.stack.maxEntries),"Invalid stack entry limit")
    end
end
-- block=true: a building block without layout ownership (displays get new
-- layout elements when the block is inserted).
local function validateInner(graph,owned,block,ctx)
    fields(graph,"version nextId nodes edges view sections")
    local sectionError=A.Sections.Check(graph.sections);assert(not sectionError,sectionError)
    bounded(graph.nextId,1,1000000); assert(graph.nextId==math.floor(graph.nextId),"Invalid next node ID")
    fields(graph.view,"x y zoom"); bounded(graph.view.x,-1000000,1000000); bounded(graph.view.y,-1000000,1000000); bounded(graph.view.zoom,.1,4)
    assert(type(graph.nodes)=="table" and count(graph.nodes)<=G.maxNodes,"Node limit exceeded")
    for id,node in pairs(graph.nodes) do
        ctx.node=id
        assert(type(id)=="string" and #id<=32,"Invalid node identity")
        fields(node,"id type version revision x y values config exposed title collapsed")
        flag(node.collapsed); bounded(node.x,-1000000,1000000); bounded(node.y,-1000000,1000000)
        local def=assert(A.catalog[node.type],"Unknown node type: "..tostring(node.type))
        local allowed={}; for k in pairs(def.defaults or {}) do allowed[k]=true end
        for _,field in ipairs(def.fields or {}) do allowed[field.key]=true end
        if def.display or def.layoutOwner then allowed.layoutId=true end
        -- Aura selection caches only its icon reference, never live aura data.
        if node.type=="aura" or def.auraSource then allowed.texture=true end
        if node.type=="aura" or def.auraSource or def.secureAction or def.actionSource then allowed.spellIcon=true end
        assert(type(node.config)=="table","Invalid node configuration")
        for k,v in pairs(node.config) do
            assert(allowed[k],"Unsupported node setting: "..tostring(k))
            if type(v)=="table" then
                if def.displayStack and k=="elements"then
                    array(v,8);for _,element in ipairs(v)do fields(element,"id label layoutId")end
                elseif (def.interactionProducer or def.interactionConsumer) and k=="payload" then
                    assert(ns.GraphValues.ClickSchema(v),"Invalid click payload schema")
                else
                    assert(def.selectableOutputs and k==def.outputSelectionKey,"Nested node configuration is not supported")
                    for output,selected in pairs(v) do assert(def.selectableOutputs[output] and selected==true,"Invalid output selection")end
                end
            end
        end
        if (node.type=="aura" or def.auraSource) and node.config.texture~=nil then assert(ns.IconCatalog:Reference(node.config.texture),"Invalid aura icon") end
        if node.config.spellIcon~=nil then assert(ns.IconCatalog:Reference(node.config.spellIcon),"Invalid spell icon") end
        local resolved,why=G.Definition(def,node); assert(resolved,why)
        -- Block displays have no layout element yet; they are validated after insertion.
        if resolved.validate and not (block and (def.display or def.layoutOwner)) then local ok,err=resolved.validate(node.config); assert(ok,err) end
        local ports=G.Ports(resolved)
        assert(type(node.values)=="table" and type(node.exposed)=="table","Invalid node inputs")
        for k,v in pairs(node.values) do assert(ports[k] and not ports[k].wire and G.Accepts(ports[k].type,v),"Invalid stored input: "..tostring(k)) end
        for k,v in pairs(node.exposed) do assert(ports[k] and type(v)=="boolean","Invalid exposed port") end
        if block then assert(node.config.layoutId==nil,"Blocks carry no layout ownership")
        elseif def.display or (def.layoutOwner and node.config.layoutId) then
            if def.displayStack then
                local root
                for _,element in ipairs(node.config.elements)do if element.id==node.config.rootElement then root=element.layoutId end end
                assert(identity(root) and node.config.layoutId==root,"Invalid stack root alias")
                for _,element in ipairs(node.config.elements)do
                    local key=element.layoutId;assert(identity(key) and not owned[key],"Repeated or missing display anchor");owned[key]={root=root}
                end
            else
                local key=node.config.layoutId; assert(identity(key) and not owned[key],"Repeated or missing display anchor"); owned[key]=true
            end
        end
    end
    ctx.node=nil
    array(graph.edges,G.maxEdges); for _,e in ipairs(graph.edges) do fields(e,"from output to input") end
    local plan,why=G.Compile(graph,A.catalog,true)
    if not plan then ctx.node=why and why.node;error(why and why.message or "Invalid graph",0) end
end
-- Errors name the node (title, type, id) without the Lua file/line prefix.
local function validateGraph(graph,owned,block)
    local ctx={}
    local ok,err=pcall(validateInner,graph,owned,block,ctx)
    if ok then return end
    local message=ns.GraphValues.UserError(err)
    if ctx.node and type(graph)=="table" and type(graph.nodes)=="table" and graph.nodes[ctx.node] then
        message=G.DescribeError(graph,A.catalog,{node=ctx.node,message=message})
    end
    error(message,0)
end
T.ValidateGraph=validateGraph
function T.Validate(packet)
    -- This also bounds calls made without the text decoder (tests/internal callers).
    C.Serialize(packet)
    fields(packet,"version kind group graphs layouts frames")
    assert(packet.version==1 and (packet.kind=="graph" or packet.kind=="group"),"Unsupported transfer schema")
    if packet.kind=="group" then fields(packet.group,"name quickInclude"); name(packet.group.name); flag(packet.group.quickInclude)
    else assert(packet.group==nil,"Unexpected transfer group") end
    array(packet.graphs,32); assert(#packet.graphs>0,"Nothing to import")
    local owned={}
    for _,rec in ipairs(packet.graphs) do
        fields(rec,"name graph inGroup quickInclude"); name(rec.name); flag(rec.inGroup); flag(rec.quickInclude)
        assert(not rec.inGroup or packet.kind=="group","Missing transfer group")
        local ok,err=pcall(validateGraph,rec.graph,owned)
        if not ok then error("Graph '"..tostring(rec.name):gsub("|","||").."': "..ns.GraphValues.UserError(err),0) end
    end
    assert(type(packet.layouts)=="table" and count(packet.layouts)<=1024,"Layout transfer limit exceeded")
    local anchors=0
    for id,raw in pairs(packet.layouts) do
        validateLayout(id,raw)
        if raw.anchorPoint==1 then anchors=anchors+1 else assert(owned[id],"Unowned display dependency") end
        for _,target in pairs(refs(raw)) do assert(endpoint(target) or packet.layouts[target],"Missing layout dependency") end
    end
    assert(anchors<=32,"Anchor limit exceeded")
    for id in pairs(owned) do assert(packet.layouts[id] and packet.layouts[id].displayAnchor==1,"Missing display layout") end
    for id,owner in pairs(owned)do
        local raw=packet.layouts[id]
        if type(owner)=="table"then
            assert(raw.templateId==owner.root and raw.templateRoot==owner.root,"Missing or mismatched stack template")
            if id==owner.root then
                assert(not raw.link or endpoint(raw.link.target) or packet.layouts[raw.link.target].anchorPoint==1,"Stack root requires a neutral or built-in anchor")
            else
                local seen={};local key=id
                while key~=owner.root do
                    assert(not seen[key],"Cyclic stack template");seen[key]=true
                    local item=packet.layouts[key]
                    assert(item and item.templateId==owner.root and item.link,"Stack element must reach its own root")
                    key=item.link.target
                end
                for _,target in pairs({raw.widthTarget,raw.heightTarget})do assert(packet.layouts[target] and packet.layouts[target].templateId==owner.root,"Cross-template size target")end
            end
        else assert(raw.templateId==nil and raw.templateRoot==nil,"Template metadata needs Display Stack ownership")end
    end
    local ok,why=ns.LayoutModel.Validate(packet.layouts); assert(ok,why)
    -- Reject unused hidden payloads, not merely unknown field names.
    local reachable={}
    local function visit(id) if endpoint(id) or reachable[id] then return end; reachable[id]=true; for _,target in pairs(refs(packet.layouts[id])) do visit(target) end end
    for id in pairs(owned) do visit(id) end
    for id in pairs(packet.layouts) do assert(reachable[id],"Unused layout payload") end
    local required=frameReferences(packet)
    local frameCount=0;for ref in pairs(required) do frameCount=frameCount+1;assert(ns.FrameLibrary:ValidateReference(ref),"Invalid frame reference") end
    assert(frameCount<=128,"Frame reference limit exceeded")
    if packet.frames~=nil then
        assert(type(packet.frames)=="table" and count(packet.frames)<=128,"Invalid frame description list")
        for ref,entry in pairs(packet.frames) do
            assert(required[ref] and ns.FrameLibrary:ValidEntry(entry) and entry.reference==ref,"Unused or invalid frame description")
        end
        for ref in pairs(required) do assert(packet.frames[ref],"Missing frame description") end
    end
    return packet
end
function T.Export(store,layout,kind,id)
    local packet={version=1,kind=kind,graphs={},layouts={}}
    local selected,owners={},{}
    for gid,rec in pairs(store.graphs) do
        for _,node in pairs(rec.draft.nodes) do for _,key in ipairs(displayIDs(node))do owners[key]=gid end end
    end
    if kind=="group" then
        local group=assert(store.groups[id],"Select a group to export")
        packet.group={name=group.name,quickInclude=group.quickInclude}
        for gid,rec in pairs(store.graphs) do if rec.groupId==id then selected[gid]=true end end
    else assert(kind=="graph" and store.graphs[id],"Select a graph to export"); selected[id]=true end
    local visited={}; local includeGraph,includeLayout
    includeLayout=function(key)
        if endpoint(key) or packet.layouts[key] then return end
        local raw=assert(layout[key],"Missing layout dependency: "..tostring(key))
        packet.layouts[key]=G.Copy(raw)
        if raw.displayAnchor==1 then includeGraph(assert(owners[key],"Dependency belongs to an unavailable draft; apply/discard it before export")) end
        for _,target in pairs(refs(raw)) do includeLayout(target) end
    end
    includeGraph=function(gid)
        if visited[gid] then return end; visited[gid]=true; selected[gid]=true
        for _,node in pairs(store.graphs[gid].draft.nodes) do for _,key in ipairs(displayIDs(node))do includeLayout(key)end end
    end
    local initial={}; for gid in pairs(selected) do initial[#initial+1]=gid end
    for _,gid in ipairs(initial) do includeGraph(gid) end
    for _,gid in ipairs(store.graphOrder) do if selected[gid] then
        local rec=store.graphs[gid]; packet.graphs[#packet.graphs+1]={name=rec.name,graph=G.Copy(rec.draft),quickInclude=rec.quickInclude,inGroup=kind=="group" and rec.groupId==id or nil}
    end end
    local entries={}
    for ref in pairs(frameReferences(packet)) do entries[ref]=ns.FrameLibrary:Lookup(ref) or {reference=ref,label=ref:sub(1,96)} end
    if next(entries) then packet.frames=entries end
    for _,rec in ipairs(packet.graphs)do A.Messaging.ResetPermissions(rec.graph)end
    T.Validate(packet); return packet
end
local function uniqueName(base,collection)
    local names={}; for _,rec in pairs(collection) do names[rec.name:lower()]=true end
    if not names[base:lower()] then return base end
    local last=math.min(#base+1,61)
    while last>1 and base:byte(last) and base:byte(last)>=128 and base:byte(last)<192 do last=last-1 end
    local index=2; local stem=G.NodeTitle(base:sub(1,last-1)) or "Imported"
    while names[(stem.." ("..index..")"):lower()] do index=index+1 end
    return stem.." ("..index..")"
end
local function relevant(layout,packet)
    local out={}; for id in pairs(packet.layouts) do out[id]=layout[id] or false end; return C.Serialize(out)
end
local function conflicts(packet,layout)
    local out={}
    for id,raw in pairs(packet.layouts) do if raw.anchorPoint==1 and layout[id] then
        if layout[id].anchorPoint~=1 or not same(geometry(raw),geometry(layout[id])) then out[#out+1]=raw.label end
        -- Reusing an anchor linked to a display would bind the imported copy to
        -- the original display. Treat this as an explicit topology decision.
        if layout[id].anchorPoint==1 then for _,target in pairs(refs(raw)) do if not endpoint(target) and packet.layouts[target].displayAnchor==1 then out[#out+1]=raw.label.." (display link)"; break end end end
    end end
    table.sort(out); return out
end
function S:ExportTransfer(kind,id)
    if kind=="block" then local packet=T.ExportBlock(self:Store(),id);return C.Encode(packet),packet end
    if kind=="blocks" then local packet=T.ExportBlocks(self:Store());return C.Encode(packet),packet end
    assert(not ns.Layout.draft,"Save or exit the Layout Editor before exporting")
    local packet=T.Export(self:Store(),ns.Layout:Store(),kind,id)
    return C.Encode(packet),packet
end
local pending
function S:PreviewTransfer(text)
    pending=nil
    assert(not InCombatLockdown() and not ns.Layout.draft,"Import outside combat and close the Layout Editor first")
    local decoded=C.Decode(text)
    if type(decoded)=="table" and decoded.kind=="block" then
        local packet=T.ValidateBlock(decoded);local n=count(packet.block.graph.nodes)
        local token={conflicts={},graphs=0,anchors=0,names={packet.block.name},frames=0,block=true,
            summary="Building block: "..packet.block.name.."\n"..n.." node(s). Saved as a new block in your library; insert it from Edit > Blocks."}
        pending={token=token,packet=packet,store=self:Store(),profile=ns.Settings:Profile(),block=true}
        return token
    end
    if type(decoded)=="table" and decoded.kind=="blocks" then
        local packet=T.ValidateBlocks(decoded);local names={}
        for _,b in ipairs(packet.blocks) do names[#names+1]=b.name end
        local token={conflicts={},graphs=0,anchors=0,names=names,frames=0,block=true,
            summary="Block library: "..#names.." block(s)\n"..table.concat(names,", ").."\nSaved as new blocks in your library; insert them from Edit > Blocks."}
        pending={token=token,packet=packet,store=self:Store(),profile=ns.Settings:Profile(),block=true}
        return token
    end
    local packet=T.Validate(decoded); local data=self:Store(); local layout=ns.Layout:Store()
    assert(count(data.graphs)+#packet.graphs<=32,"Graph limit reached (32 per profile)")
    if packet.group then assert(count(data.groups)<32,"Group limit reached (32 per profile)") end
    local prepared,why=ns.FrameLibrary:Prepare(frameEntries(packet));assert(prepared,why)
    local token={conflicts=conflicts(packet,layout),graphs=#packet.graphs,anchors=0,names={},frames=count(frameEntries(packet))}
    for _,rec in ipairs(packet.graphs) do token.names[#token.names+1]=rec.name end
    for _,raw in pairs(packet.layouts) do if raw.anchorPoint==1 then token.anchors=token.anchors+1 end end
    token.summary=(packet.group and "Group: "..packet.group.name.."\n" or "")..#packet.graphs.." graph(s), "..token.anchors.." anchor(s).\n"..table.concat(token.names,", ").."\nNew copies; imported graphs remain disabled. Review the graph before Apply and enable."
    token.summary=token.summary.."\n"..token.frames.." portable frame reference(s); existing library names are retained."
    if #token.conflicts>0 then token.summary=token.summary.."\nAnchor conflicts: "..table.concat(token.conflicts,", ") end
    pending={token=token,packet=packet,store=data,profile=ns.Settings:Profile(),layout=relevant(layout,packet),library=libraryStamp()}
    return token
end
function S:CancelTransfer() pending=nil end
function S:ImportTransfer(token,policy)
    local p=pending; assert(p and p.token==token,"Preview the import first")
    if p.block then
        assert(self:Store()==p.store and ns.Settings:Profile()==p.profile,"Import preview expired; preview again")
        if p.packet.kind=="blocks" then
            local names=A.Blocks.AddAll(p.store,p.packet);pending=nil
            self.message=#names.." block(s) imported";self:Changed();return names
        end
        local id,name=A.Blocks.Add(p.store,p.packet);pending=nil
        self.message="Block imported: "..name;self:Changed();return id
    end
    assert(not InCombatLockdown() and not ns.Layout.draft,"Import outside combat and close the Layout Editor first")
    local data=self:Store(); local layout=ns.Layout:Store(); local packet=p.packet
    assert(data==p.store and ns.Settings:Profile()==p.profile and relevant(layout,packet)==p.layout and libraryStamp()==p.library,"Import preview expired; preview again")
    local clashes=conflicts(packet,layout)
    assert(policy==nil or policy=="existing" or policy=="copy","Unknown anchor policy")
    assert(#clashes==0 or policy,"Choose how to handle conflicting anchors")
    assert(count(data.graphs)+#packet.graphs<=32,"Graph limit reached (32 per profile)")
    if packet.group then assert(count(data.groups)<32,"Group limit reached (32 per profile)") end
    local preparedFrames,frameWhy=ns.FrameLibrary:Prepare(frameEntries(packet));assert(preparedFrames,frameWhy)
    local graphs,groups,order,layouts={},{},G.Copy(data.graphOrder),{}
    for id,rec in pairs(data.graphs) do graphs[id]=rec end
    for id,rec in pairs(data.groups) do groups[id]=rec end
    for id,raw in pairs(layout) do layouts[id]=raw end
    local map,newIDs={},{}
    local function fresh()
        for _=1,32 do
            local id=ns.DisplayAnchors:NewID()
            if not layouts[id] and not newIDs[id] and not packet.layouts[id] then newIDs[id]=true; return id end
        end
        error("Could not allocate a unique import identity")
    end
    local labels={}; local anchors=0
    for _,raw in pairs(layouts) do if raw.anchorPoint==1 then anchors=anchors+1; labels[#labels+1]={name=raw.label} end end
    for id,raw in pairs(packet.layouts) do
        if raw.displayAnchor==1 or policy=="copy" then map[id]=fresh()
        else
            assert(not layouts[id] or layouts[id].anchorPoint==1,"Layout identity collision; choose separate anchors")
            map[id]=id
        end
    end
    for id,raw in pairs(packet.layouts) do if not layouts[map[id]] then
        local copy=G.Copy(raw)
        if copy.link and not endpoint(copy.link.target) then copy.link.target=map[copy.link.target] end
        if copy.widthTarget and not external(copy.widthTarget) then copy.widthTarget=map[copy.widthTarget] end
        if copy.heightTarget and not external(copy.heightTarget) then copy.heightTarget=map[copy.heightTarget] end
        if copy.templateId then copy.templateId=map[copy.templateId]end
        if copy.templateRoot then copy.templateRoot=map[copy.templateRoot]end
        if copy.anchorPoint==1 then anchors=anchors+1; copy.label=uniqueName(copy.label,labels); labels[#labels+1]={name=copy.label} end
        layouts[map[id]]=copy
    end end
    assert(anchors<=32,"Anchor limit reached (32 per profile)")
    local valid,why=ns.LayoutModel.Validate(layouts); assert(valid,why)
    local nextGroup=data.nextGroupId; local groupID
    if packet.group then
        repeat groupID="folder"..nextGroup; nextGroup=nextGroup+1 until not groups[groupID]
        groups[groupID]={id=groupID,name=uniqueName(packet.group.name,groups),enabled=false,quickInclude=packet.group.quickInclude}
    end
    local nextGraph=data.nextId; local imported={}
    for _,source in ipairs(packet.graphs) do
        local id; repeat id="g"..nextGraph; nextGraph=nextGraph+1 until not graphs[id]
        local draft=A.MigrateGraph(G.Copy(source.graph)); local label=uniqueName(source.name,graphs)
        A.Messaging.ResetPermissions(draft)
        for _,node in pairs(draft.nodes) do if A.catalog[node.type].display or (A.catalog[node.type].layoutOwner and node.config.layoutId) then
            node.config.layoutId=map[node.config.layoutId]; layouts[node.config.layoutId].label=label.." / "..(node.title or node.id)
            if A.catalog[node.type].displayStack then for _,element in ipairs(node.config.elements)do
                element.layoutId=map[element.layoutId];layouts[element.layoutId].label=label.." / "..(node.title or node.id).." / "..element.label
            end end
        end end
        graphs[id]={id=id,name=label,draft=draft,enabled=false,revision=0,draftRevision=0,quickInclude=source.quickInclude,groupId=source.inGroup and groupID or nil}
        local snapshot={version=1,elements={},dependencies={},anchorRefs={}}
        for _,node in pairs(draft.nodes) do for _,key in ipairs(displayIDs(node))do snapshot.elements[key]=G.Copy(layouts[key])end end
        local seen={}
        local function dependency(key)
            if endpoint(key) or seen[key] then return end; seen[key]=true
            if not snapshot.elements[key] then snapshot.dependencies[key]=G.Copy(layouts[key]); snapshot.anchorRefs[#snapshot.anchorRefs+1]=key end
            if layouts[key] then for _,target in pairs(refs(layouts[key])) do dependency(target) end end
        end
        for key in pairs(snapshot.elements) do dependency(key) end
        table.sort(snapshot.anchorRefs); graphs[id].displayLayout=snapshot
        order[#order+1]=id; imported[#imported+1]=id
    end
    -- No existing record is changed and no runtime is started. All allocation,
    -- remapping and validation above must finish before these assignments.
    local before={data.graphs,data.groups,data.graphOrder,data.nextId,data.nextGroupId,layout,ns.Settings.db.frameLibrary}
    data.graphs,data.groups,data.graphOrder,data.nextId,data.nextGroupId=graphs,groups,order,nextGraph,nextGroup
    p.profile.layout.elements=layouts;ns.Settings.db.frameLibrary=preparedFrames
    local ok,err=pcall(function()
        ns.DisplayAnchors:Sync()
        for _,id in ipairs(imported) do self:PrepareDisplays(graphs[id].draft,graphs[id]) end
    end)
    if not ok then
        data.graphs,data.groups,data.graphOrder,data.nextId,data.nextGroupId=unpack(before,1,5); p.profile.layout.elements=before[6];ns.Settings.db.frameLibrary=before[7]
        pcall(ns.DisplayAnchors.Sync,ns.DisplayAnchors); error(err)
    end
    pending=nil; self:EndTest(); data.selected=imported[1]; self.inspectApplied=false
    self.message="Imported "..#imported.." disabled graph(s). Review, Apply, then enable."
    ns.Layout:Refresh(); self:Changed(); return imported
end
ns.Settings:BeforeProfileChange(T,function() pending=nil end)

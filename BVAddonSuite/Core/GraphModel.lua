local _, ns = ...
local G = { maxNodes = 128, maxEdges = 1024 }
ns.GraphModel = G
local V=ns.GraphValues
G.Copy=V.Copy; G.RuntimeCopy=V.RuntimeCopy; G.TraceCopy=V.TraceCopy
G.IsSecret=V.IsSecret; G.Capture=V.Capture
G.CaptureObject=V.CaptureObject; G.Object=V.Object
function G.Number(v) return not V.IsSecret(v) and type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end
-- Declarative user configuration; never a trigger or a runtime cast request.
function G.Action(v)
    if ns.Actions then return ns.Actions.Valid(v) end
    if not V.PlainExcept(v,{}) or type(v)~="table" then return false end
    for k in pairs(v) do if k~="kind" and k~="spellID" and k~="unit" then return false end end
    return v.kind=="spell" and G.Number(v.spellID) and v.spellID>0 and v.spellID<=2147483647
        and v.spellID==math.floor(v.spellID) and ({player=true,target=true,targettarget=true,focus=true,focustarget=true})[v.unit]==true
end
function G.Accepts(t,v)
    if V.Contains(v) then return false end
    if t=="nil" then return v==nil end
    if t=="any" then
        return type(v)=="boolean" or G.Number(v) or (type(v)=="string" and #v<=1024) or ns.DisplayModel.Valid(v) or ns.DisplayModel.Font(v) or ns.DisplayModel.Style(v) or G.Action(v)
    end
    if t=="media" then return ns.DisplayModel.Valid(v) end
    if t=="font" then return ns.DisplayModel.Font(v) end
    if t=="style" then return ns.DisplayModel.Style(v) end
    if t=="action" then return G.Action(v) end
    if t=="symbol" then return ns.DisplayModel.Symbol(v) end
    if t=="float" then return G.Number(v) end
    if t=="integer" then return G.Number(v) and v==math.floor(v) end
    if t=="boolean" then return type(v)=="boolean" end
    if t=="string" then return type(v)=="string" and #v<=1024 end
    return false
end
function G.RuntimeAccepts(t,v)
    if V.IsSecret(v) then return V.Accepts(t,v) end
    if t=="action" then return G.Action(v) end
    if t=="media" then return ns.DisplayModel.Valid(v) end
    if t=="any" and type(v)=="table" then return ns.DisplayModel.Valid(v) or ns.DisplayModel.Font(v) or ns.DisplayModel.Style(v) or G.Action(v) end
    return G.Accepts(t,v)
end
local valueTypes={action=true,boolean=true,integer=true,float=true,string=true,media=true,event=true,data=true,duration=true,calculator=true,unitref=true,font=true,style=true,symbol=true}
function G.Compatible(from,to)
    -- Nil is an explicit missing value, never a wildcard carrying arbitrary data.
    -- "any" is an inspection input only; ordinary value ports remain typed.
    if from=="nil" then return valueTypes[to]==true or to=="any" or to=="nil" end
    if to=="any" then return from=="any" or valueTypes[from]==true end
    return from==to or (from=="integer" and to=="float")
end
-- Plain status metadata travels beside values; it never contains client data.
local signalStates={readable=true,protected=true,unavailable=true,["nil"]=true,muted=true,faulted=true,absent=true,permanent=true,inactive=true}
function G.SignalStatus(value,status)
    if V.IsSecret(value) then return "protected" end
    if value~=nil then return "readable" end
    if signalStates[status] and status~="readable" then return status end
    if type(status)=="string" and status:find("protected",1,true) then return "protected" end
    return "unavailable"
end
function G.SignalMerge(a,b)
    local rank={protected=9,faulted=8,unavailable=7,muted=6,inactive=5,absent=4,permanent=3,["nil"]=2,readable=1}
    return (rank[b] or 0)>(rank[a] or 0) and b or a
end
function G.SignalSecret(status)
    if status=="protected" then return true end
    if status and status~="unavailable" then return false end
    return nil
end
function G.New() return {version=1,nextId=1,nodes={},edges={},view={x=30,y=35,zoom=1}} end
function G.NodeTitle(value)
    if type(value)~="string" then return nil end
    value=value:gsub("[%c|]",""):match("^%s*(.-)%s*$")
    -- Bound bytes without cutting a UTF-8 code point.
    if #value>80 then
        local last=81
        while last>1 and value:byte(last)>=128 and value:byte(last)<192 do last=last-1 end
        value=value:sub(1,last-1)
    end
    return value~="" and value or nil
end
-- One specialization path for editor, compiler and runtime. Catalog definitions
-- remain immutable; only bounded configuration determines the concrete ports.
function G.Definition(def,node)
    if not def.resolve then return def end
    local ok,result,why=pcall(def.resolve,node and node.config or def.defaults)
    if not ok then return nil,tostring(result) end
    return result,why
end
function G.Ports(def)
    if def.resolve then def=assert(G.Definition(def)) end
    local inputs={}; for k,v in pairs(def.inputs or {}) do inputs[k]=v end
    if not def.source and not def.annotation then inputs.mute={type="boolean",default=false,label="Mute",control=true} end
    if def.bypass then inputs.bypass={type="boolean",default=false,label="Bypass",control=true} end
    return inputs
end
function G.Ordered(ports)
    local ids={}; for id in pairs(ports or {}) do ids[#ids+1]=id end
    table.sort(ids,function(a,b)
        local x,y=ports[a],ports[b]
        if (x.order or 100)~=(y.order or 100) then return (x.order or 100)<(y.order or 100) end
        return a<b
    end); return ids
end
function G.Add(graph, kind, catalog, x,y)
    assert(catalog[kind],"Unknown node type")
    local count=0; for _ in pairs(graph.nodes) do count=count+1 end
    assert(count<G.maxNodes,"Node limit reached (128)")
    assert(G.Number(graph.nextId) and graph.nextId>=1 and graph.nextId==math.floor(graph.nextId),"Invalid node identity counter")
    while graph.nodes["n"..graph.nextId] do graph.nextId=graph.nextId+1 end
    local id="n"..graph.nextId; graph.nextId=graph.nextId+1
    local values={}; for key,p in pairs(G.Ports(assert(G.Definition(catalog[kind])))) do values[key]=p.default end
    local config=G.Copy(catalog[kind].defaults or {})
    if catalog[kind].interactionProducer then
        -- New producers must not invalidate an existing interaction contract.
        -- Reserve receiver keys too; existing nodes and schemas remain untouched.
        local reserved,conflict={},false
        local signature=V.ClickSignature(config.payload)
        for _,node in pairs(graph.nodes) do
            local def=catalog[node.type];local other=node.config
            if def and (def.interactionProducer or def.interactionConsumer) and type(other)=="table" and type(other.key)=="string" then
                reserved[other.key]=true
                if other.key==config.key and V.ClickSignature(other.payload)~=signature then conflict=true end
            end
        end
        if conflict then
            local base=config.key;local suffix=2
            while reserved[base.."."..suffix] do suffix=suffix+1 end
            config.key=base.."."..suffix
        end
    end
    graph.nodes[id]={id=id,type=kind,version=1,revision=catalog[kind].revision or 1,x=x or 0,y=y or 0,values=values,
        config=config,exposed={}}
    return id
end
function G.Binding(graph,id,port)
    for i,e in ipairs(graph.edges) do if e.to==id and e.input==port then return e,i end end
end
-- Inspection outputs retain their wired source type; Any never grants a
-- wildcard connection to an ordinary typed consumer.
function G.OutputType(graph,catalog,id,key,seen)
    local node=graph.nodes[id]; local def=node and G.Definition(catalog[node.type],node)
    local output=def and def.outputs[key]; if not output then return nil end
    if not def.transparentInput or output.type~="any" then return output.type end
    seen=seen or {}; if seen[id] then return nil end; seen[id]=true
    local edge
    for _,candidate in ipairs(graph.edges) do
        if type(candidate)=="table" and candidate.to==id and candidate.input==def.transparentInput then edge=candidate; break end
    end
    return edge and G.OutputType(graph,catalog,edge.from,edge.output,seen) or "any"
end
-- tolerant=true (editor drafts only): a node whose settings no longer resolve
-- is recorded in plan.invalid instead of rejecting the whole graph, so one
-- outdated node never blocks editing. Apply, export and runtime stay strict.
function G.Compile(graph,catalog,structureOnly,tolerant)
    local function fail(message,node,port) return nil,{message=message,node=node,port=port} end
    local invalid={}
    if V.Contains(graph) then return fail("Secret or opaque values cannot enter graph storage") end
    if type(graph)~="table" or graph.version~=1 or type(graph.nodes)~="table" or type(graph.edges)~="table" then return fail("Unsupported graph schema") end
    local count=0; local incoming,dependents,definitions={},{},{}
    for id,n in pairs(graph.nodes) do
        count=count+1
        if type(id)~="string" or type(n)~="table" or n.id~=id or not catalog[n.type] or n.version~=1 then return fail("Invalid or unsupported node",id) end
        -- Node revision (per type): newer than this client means a newer addon made it.
        if n.revision~=nil and (not G.Number(n.revision) or n.revision<1 or n.revision~=math.floor(n.revision)) then return fail("Invalid node revision",id) end
        if (n.revision or 1)>(catalog[n.type].revision or 1) then
            if not tolerant then return fail("This node was made with a newer BV Addon Suite version; update the addon",id) end
            invalid[id]="This node was made with a newer BV Addon Suite version; update the addon"
        end
        if not G.Number(n.x) or not G.Number(n.y) or type(n.values)~="table" or type(n.config)~="table" or type(n.exposed)~="table" then return fail("Invalid node data",id) end
        if n.title~=nil and G.NodeTitle(n.title)~=n.title then return fail("Invalid node title",id) end
        local def,why=G.Definition(catalog[n.type],n)
        if not def then
            if not tolerant then return fail(why or "Invalid port configuration",id) end
            invalid[id]=why or "Invalid port configuration"
            def=G.Definition(catalog[n.type]) or {inputs={},outputs={}}
        end
        definitions[id]=def
        incoming[id]={}; dependents[id]={}
    end
    local schemas={}
    for id,def in pairs(definitions) do if def.interactionProducer or def.interactionConsumer then
        local config=graph.nodes[id].config
        local signature=V.ClickSignature(config.payload)
        if schemas[config.key] and schemas[config.key]~=signature then return fail("Matching interaction keys need the same payload fields",id) end
        if type(config.key)~="string" then return fail("Invalid interaction key",id) end
        schemas[config.key]=signature
    end end
    if count>G.maxNodes or #graph.edges>G.maxEdges then return fail("Graph resource limit exceeded") end
    for id,def in pairs(definitions) do if def.transparentInput then
        def=G.Copy(def); definitions[id]=def
        for key,p in pairs(def.outputs) do p.type=G.OutputType(graph,catalog,id,key) or "any" end
    end end
    for _,e in ipairs(graph.edges) do
        if type(e)~="table" or not graph.nodes[e.from] or not graph.nodes[e.to] then return fail("Connection references a missing node") end
        local output=definitions[e.from].outputs[e.output]
        local input=G.Ports(definitions[e.to])[e.input]
        local lenient=invalid[e.from] or invalid[e.to]
        if not lenient and (not output or not input or not G.Compatible(output.type,input.type)) then return fail("Incompatible ports",e.to,e.input) end
        if incoming[e.to][e.input] then return fail("Input already connected",e.to,e.input) end
        incoming[e.to][e.input]=e; dependents[e.from][e.to]=true
    end
    local visiting,visited,order={},{},{}
    local function visit(id)
        if visiting[id] then return false end
        if visited[id] then return true end
        visiting[id]=true
        for _,key in ipairs(G.Ordered(incoming[id])) do if not visit(incoming[id][key].from) then return false end end
        visiting[id]=nil; visited[id]=true; order[#order+1]=id; return true
    end
    local ids={}; for id in pairs(graph.nodes) do ids[#ids+1]=id end; table.sort(ids)
    for _,id in ipairs(ids) do if not visit(id) then return fail("Connection would create a cycle",id) end end
    local active={}
    local function reach(id)
        if active[id] then return end; active[id]=true
        for _,key in ipairs(G.Ordered(incoming[id])) do reach(incoming[id][key].from) end
    end
    for _,id in ipairs(ids) do if catalog[graph.nodes[id].type].sink then reach(id) end end
    local execution={}
    for _,id in ipairs(order) do
        if active[id] then
            local n=graph.nodes[id]; local def=definitions[id]
            if not structureOnly then
                for key,p in pairs(G.Ports(def)) do
                    if not incoming[id][key] then
                        local v=n.values[key]; if v==nil then v=p.default end
                        if (p.wire and p.required~=false) or (p.required and v==nil) or (v~=nil and not G.Accepts(p.type,v)) then return fail("Missing or invalid "..(p.label or key),id,key) end
                    end
                end
                if def.validate then local ok,why=def.validate(n.config); if not ok then return fail(why,id) end end
            end
            execution[#execution+1]=id
        end
    end
    local repeated={}
    for _,id in ipairs(execution) do
        if definitions[id].collectionSource then repeated[id]=true end
        for _,edge in pairs(incoming[id]) do if repeated[edge.from] then repeated[id]=true end end
        if repeated[id] and definitions[id].sink and not definitions[id].displayStack and not definitions[id].debugPreview and not definitions[id].memoryOperation then
            return fail("Repeated units require a Display Stack output",id)
        end
    end
    return {graph=G.Copy(graph),order=execution,incoming=incoming,active=active,dependents=dependents,definitions=definitions,repeated=repeated,invalid=invalid}
end
-- User-facing type name: internal "array:string" reads "Dictionary (string)".
local typeLabels={boolean="On/off",integer="Whole number",float="Number",string="Text",event="Event",media="Media",font="Font",style="Style",
    symbol="Symbol",timestamp="Timestamp",duration="Duration",unitref="Unit",action="Action",data="Data",any="Any value",calculator="Calculator",click="Click",["nil"]="Nothing"}
function G.TypeLabel(t)
    if type(t)~="string" then return tostring(t) end
    local inner=t:match("^array:(.+)$")
    if inner then return "Dictionary ("..(typeLabels[inner] or inner)..")" end
    return typeLabels[t] or t
end
-- Names the node an error belongs to: "Node 'Title' (Type, n5): message".
function G.DescribeError(graph,catalog,err)
    local message=V.UserError(type(err)=="table" and err.message or err)
    local id=type(err)=="table" and err.node
    local n=id and type(graph)=="table" and type(graph.nodes)=="table" and graph.nodes[id]
    if not n then return message end
    local def=catalog and catalog[n.type]
    local label=def and def.label or tostring(n.type)
    local name=type(n.title)=="string" and n.title~="" and n.title or label
    return "Node '"..name.."' ("..(name~=label and label..", " or "")..id.."): "..message
end
function G.FirstInvalid(plan)
    local ids={};for id in pairs(plan and plan.invalid or {}) do ids[#ids+1]=id end;table.sort(ids)
    if ids[1] then return {node=ids[1],message=plan.invalid[ids[1]]} end
end
function G.Connect(graph,catalog,from,output,to,input)
    local nextGraph=G.Copy(graph)
    local _,index=G.Binding(nextGraph,to,input); if index then table.remove(nextGraph.edges,index) end
    nextGraph.edges[#nextGraph.edges+1]={from=from,output=output,to=to,input=input}
    local plan,err=G.Compile(nextGraph,catalog,true,true)
    if not plan then return nil,G.DescribeError(nextGraph,catalog,err) end
    return nextGraph
end
function G.Remove(graph,selection)
    for id in pairs(selection) do graph.nodes[id]=nil end
    for i=#graph.edges,1,-1 do local e=graph.edges[i]; if selection[e.from] or selection[e.to] then table.remove(graph.edges,i) end end
end
function G.Fragment(graph,selection)
    local out={nodes={},edges={}}; local x,y=math.huge,math.huge
    for id in pairs(selection) do local n=graph.nodes[id]; if n then out.nodes[id]=G.Copy(n); x=math.min(x,n.x); y=math.min(y,n.y) end end
    for _,n in pairs(out.nodes) do n.x=n.x-x; n.y=n.y-y end
    for _,e in ipairs(graph.edges) do if out.nodes[e.from] and out.nodes[e.to] then out.edges[#out.edges+1]=G.Copy(e) end end
    return out
end
function G.Paste(graph,fragment,catalog,x,y)
    local map,selection={},{}
    local ids={}; for id in pairs(fragment.nodes) do ids[#ids+1]=id end; table.sort(ids)
    for _,old in ipairs(ids) do
        local n=fragment.nodes[old]; local id=G.Add(graph,n.type,catalog,x+n.x,y+n.y)
        local copy=G.Copy(n); copy.id=id; copy.x=x+n.x; copy.y=y+n.y; graph.nodes[id]=copy
        if catalog[n.type].display then
            copy.config.layoutId=nil
            for _,element in ipairs(copy.config.elements or {}) do element.layoutId=nil end
        end
        map[old]=id; selection[id]=true
    end
    for _,e in ipairs(fragment.edges) do graph.edges[#graph.edges+1]={from=map[e.from],output=e.output,to=map[e.to],input=e.input} end
    return selection
end

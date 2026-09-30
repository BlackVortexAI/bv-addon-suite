-- Building blocks (roadmap P3): saved node groups, inserted as independent
-- copies. Relay nodes mark a block's inputs and outputs. Blocks live in the
-- profile and travel as "block" transfer packets (text or P4 sharing).
local _,A=...
if A.blocked then return end
local ns=BVAddonSuiteCore
local S,G,T,C=ns.AuraStudio,A.G,A.Transfer,ns.TransferCodec
local B={max=64};A.Blocks=B
local function blockName(v) return type(v)=="string" and #v>0 and #v<=40 and v:find("%S") and not v:find("[%c|]") end
function S:Blocks()
    local data=self:Store()
    if type(data.blocks)~="table" then data.blocks={} end
    return data.blocks
end
-- Fragment without layout ownership: inserted displays get fresh elements.
local function clean(fragment)
    for _,n in pairs(fragment.nodes) do
        n.config.layoutId=nil
        for _,element in ipairs(n.config.elements or {}) do element.layoutId=nil end
    end
    return fragment
end
local function asGraph(fragment)
    local graph={version=1,nextId=1,nodes=G.Copy(fragment.nodes),edges=G.Copy(fragment.edges),view={x=0,y=0,zoom=1}}
    local n=0;for id in pairs(graph.nodes) do local num=tonumber(tostring(id):match("(%d+)$"));if num and num>=n then n=num end end
    graph.nextId=n+1;return graph
end
function S:SaveBlock(name,selection)
    if not blockName(name) then self.message="Block names have 1-40 characters";self:Changed();return false end
    local draft=self:Draft();if not draft then return false end
    local fragment=clean(G.Fragment(draft,selection or {}))
    if not next(fragment.nodes) then self.message="Select the nodes for the block first";self:Changed();return false end
    local blocks=self:Blocks();local count=0;for _ in pairs(blocks) do count=count+1 end
    if count>=B.max then self.message="Block limit reached ("..B.max..")";self:Changed();return false end
    local ok,why=pcall(T.ValidateGraph,asGraph(fragment),{},true)
    if not ok then self.message="Block not saved: "..ns.GraphValues.Error(why);self:Changed();return false end
    local i=1;while blocks["b"..i] do i=i+1 end
    blocks["b"..i]={name=name,fragment=fragment};self.message="Block saved";self:Changed()
    return "b"..i
end
-- Insert copy: nodes saved by older versions are upgraded first.
function S:BlockFragment(id)
    local block=self:Blocks()[id];if not block then return end
    local g=A.UpgradeNodes({nodes=G.Copy(block.fragment.nodes),edges=G.Copy(block.fragment.edges)})
    return {nodes=g.nodes,edges=g.edges},block.name
end
function S:DeleteBlock(id)
    local blocks=self:Blocks();if not blocks[id] then return false end
    blocks[id]=nil;self:Changed();return true
end
function S:BlockList()
    local out={}
    for id,b in pairs(self:Blocks()) do local n=0;for _ in pairs(b.fragment.nodes) do n=n+1 end;out[#out+1]={id=id,name=b.name,nodes=n} end
    table.sort(out,function(a,b) return a.name:lower()<b.name:lower() or a.name:lower()==b.name:lower() and a.id<b.id end)
    return out
end
-- Transfer packets ------------------------------------------------------
function T.ExportBlock(store,id)
    local block=assert(store.blocks and store.blocks[id],"Select a block to export")
    local graph=asGraph(block.fragment);A.Messaging.ResetPermissions(graph)
    local packet={version=1,kind="block",block={name=block.name,graph=graph}}
    T.ValidateBlock(packet);return packet
end
function T.ValidateBlock(packet)
    C.Serialize(packet)
    assert(type(packet)=="table" and packet.version==1 and packet.kind=="block" and type(packet.block)=="table","Unsupported block transfer")
    for k in pairs(packet) do assert(k=="version" or k=="kind" or k=="block","Unsupported transfer field: "..tostring(k)) end
    for k in pairs(packet.block) do assert(k=="name" or k=="graph","Unsupported block field: "..tostring(k)) end
    assert(blockName(packet.block.name),"Invalid block name")
    T.ValidateGraph(packet.block.graph,{},true)
    return packet
end
-- Whole library in one packet (kind "blocks").
function T.ExportBlocks(store)
    local list={}
    for _,b in ipairs(S.BlockList(S)) do list[#list+1]=T.ExportBlock(store,b.id).block end
    assert(#list>0,"The block library is empty")
    local packet={version=1,kind="blocks",blocks=list}
    T.ValidateBlocks(packet);return packet
end
function T.ValidateBlocks(packet)
    C.Serialize(packet)
    assert(type(packet)=="table" and packet.version==1 and packet.kind=="blocks" and type(packet.blocks)=="table","Unsupported block library transfer")
    for k in pairs(packet) do assert(k=="version" or k=="kind" or k=="blocks","Unsupported transfer field: "..tostring(k)) end
    local n=0;for k in pairs(packet.blocks) do n=n+1;assert(type(k)=="number" and k>=1 and k==math.floor(k),"Invalid block list") end
    assert(n==#packet.blocks and n>=1 and n<=B.max,"Block library must hold 1-"..B.max.." blocks")
    for _,block in ipairs(packet.blocks) do T.ValidateBlock({version=1,kind="block",block=block}) end
    return packet
end
function B.Unique(store,base)
    local names={};for _,b in pairs(store.blocks or {}) do names[b.name:lower()]=true end
    if not names[base:lower()] then return base end
    local i=2;local stem=base:sub(1,34)
    while names[(stem.." ("..i..")"):lower()] do i=i+1 end
    return stem.." ("..i..")"
end
function B.AddAll(store,packet)
    store.blocks=store.blocks or {}
    local count=0;for _ in pairs(store.blocks) do count=count+1 end
    assert(count+#packet.blocks<=B.max,"Block limit reached ("..B.max..")")
    local names={}
    for _,block in ipairs(packet.blocks) do local _,name=B.Add(store,{version=1,kind="block",block=block});names[#names+1]=name end
    return names
end
function B.Add(store,packet)
    store.blocks=store.blocks or {}
    local count=0;for _ in pairs(store.blocks) do count=count+1 end
    assert(count<B.max,"Block limit reached ("..B.max..")")
    -- Imported blocks never carry communication or macro-write permissions.
    local graph=A.MigrateGraph(G.Copy(packet.block.graph));A.Messaging.ResetPermissions(graph)
    local i=1;while store.blocks["b"..i] do i=i+1 end
    local name=B.Unique(store,packet.block.name)
    store.blocks["b"..i]={name=name,fragment={nodes=graph.nodes,edges=graph.edges}}
    return "b"..i,name
end

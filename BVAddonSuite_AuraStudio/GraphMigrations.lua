local _,A=...
if A.blocked then return end
local G=A.G
local seen=setmetatable({},{__mode="k"})
-- Copy-on-migration: applied snapshots, history and caller-owned imports are
-- never rewritten in place. One new source serves all legacy bars in a graph.
local function migrate(graph)
    if type(graph)~="table" or seen[graph] then return graph end
    if type(graph.nodes)~="table" or type(graph.edges)~="table" or G.IsSecret(graph) then return graph end
    local bars,count={},0
    for id,node in pairs(graph.nodes)do
        count=count+1
        if type(node)=="table" and node.type=="media_bar" and type(node.config)=="table" and node.config.source=="player_health" then bars[#bars+1]=id end
    end
    if #bars==0 then seen[graph]=true;return graph end
    table.sort(bars)
    local targets={};for _,id in ipairs(bars)do targets[id]=true end
    local removed=0
    for _,e in ipairs(graph.edges)do if targets[e.to] and (e.input=="value" or e.input=="maximum")then removed=removed+1 end end
    -- Do not delete user nodes or exceed existing resource limits to upgrade a
    -- full graph. The hidden compatibility path keeps those auras functional.
    if count>=G.maxNodes or #graph.edges-removed+#bars*2>G.maxEdges then seen[graph]=true;return graph,"legacy capacity" end
    local out=G.Copy(graph)
    local first=out.nodes[bars[1]]
    local source=G.Add(out,"unit",A.catalog,(first.x or 0)-320,first.y or 0)
    out.nodes[source].config.unit="player"
    out.nodes[source].config.outputs={health=true,healthMax=true}
    out.nodes[source].title="Player health"
    for i=#out.edges,1,-1 do local e=out.edges[i];if targets[e.to] and (e.input=="value" or e.input=="maximum")then table.remove(out.edges,i)end end
    for _,id in ipairs(bars)do
        out.nodes[id].config.source="values"
        out.edges[#out.edges+1]={from=source,output="health",to=id,input="value"}
        out.edges[#out.edges+1]={from=source,output="healthMax",to=id,input="maximum"}
    end
    seen[out]=true
    return out,"player health migrated"
end
function A.MigrateGraph(graph)
    if seen[graph] then return graph end
    if type(graph)=="table" and type(graph.nodes)=="table" and type(graph.edges)=="table" then
        -- Older editors retained local values/exposure flags after removing
        -- formatter/logic slots. Repair copies only; keep unknown keys
        -- and connected inputs so validation still reports malformed graphs.
        local repaired=false
        for id,n in pairs(graph.nodes) do
            local prefix=({string_formatter="value",format_values="value",logic="in",logic_and="in",logic_or="in"})[n.type]
            if prefix and type(n.values)=="table" and type(n.exposed)=="table" then
                local def=G.Definition(A.catalog[n.type],n)
                if def then for i=1,16 do
                    local key=prefix..i
                    if not def.inputs[key] and (n.values[key]~=nil or n.exposed[key]~=nil) and not G.Binding(graph,id,key) then
                        if not repaired then graph=G.Copy(graph);repaired=true end
                        graph.nodes[id].values[key]=nil;graph.nodes[id].exposed[key]=nil
                    end
                end end
            end
        end
        local legacy={}
        for id,n in pairs(graph.nodes) do if n.type=="action_display" and not n.config.legacySuggest and ((n.values and n.values.highlight~=nil) or (n.exposed and n.exposed.highlight~=nil)) then legacy[id]=true end end
        for _,e in ipairs(graph.edges) do if e.input=="highlight" and graph.nodes[e.to] and graph.nodes[e.to].type=="action_display" and not graph.nodes[e.to].config.legacySuggest then legacy[e.to]=true end end
        if next(legacy) then graph=G.Copy(graph);for id in pairs(legacy) do graph.nodes[id].config.legacySuggest=true end end
    end
    local ok,result,status=pcall(migrate,graph)
    if not ok then return graph,"migration requires valid graph" end
    if A.MigrateNodeFamilies then
        local familyOK,family,familyStatus=pcall(A.MigrateNodeFamilies,result)
        if familyOK then result=family;status=familyStatus or status end
    end
    seen[result]=true
    return result,status
end

-- Explicit, draft-only removal of retired displays. Visibility is not ownership.
local _,ns=...
local D,L=ns.DisplayAnchors,ns.Layout
local function usage()
    local refs={}
    local function add(id,kind,key,label)
        if type(id)~="string" then return end
        refs[id]=refs[id] or {};refs[id][kind..":"..key]={kind=kind,key=key,label=label}
    end
    local function links(raw,kind,key,label)
        if type(raw)~="table" then return end
        add(raw.widthTarget,kind,key,label);add(raw.heightTarget,kind,key,label)
        add(type(raw.link)=="table" and raw.link.target or nil,kind,key,label)
        if raw.templateRoot~=key then add(raw.templateRoot,kind,key,label) end
    end
    for id,raw in pairs(L:Nodes())do
        links(raw,"layout",id,"Element: "..(type(raw)=="table" and raw.label or id))
    end
    local profile=ns.Settings:Profile()
    local studio=profile.modules and profile.modules.aura_studio
    for key,rec in pairs(studio and studio.graphs or {})do
        local label="Graph: "..(rec.name or key)
        for _,field in ipairs({"draft","applied"})do
            local graph=rec[field]
            for _,node in pairs(graph and graph.nodes or {})do
                local c=node.config or {}
                add(c.layoutId,"graph",key,label);add(c.displayGroup,"graph",key,label)
                for _,element in pairs(c.elements or {})do add(element.layoutId,"graph",key,label)end
            end
        end
        local snapshot=rec.displayLayout or {}
        for _,id in pairs(snapshot.anchorRefs or {})do add(id,"graph",key,label)end
        for _,field in ipairs({"elements","dependencies"})do
            for id,raw in pairs(snapshot[field] or {})do
                add(id,"graph",key,label);links(raw,"graph",key,label)
            end
        end
    end
    for id,record in pairs(D.records)do
        if next(record.owners or {}) then add(id,"runtime",id,"Active display owner")end
    end
    for owner,groups in pairs(D.stacks or {})do
        if not owner.stopped then for _,group in pairs(groups)do
            add(group.config.layoutId,"runtime",group.config.layoutId,"Active display stack")
            for _,element in pairs(group.config.elements or {})do add(element.layoutId,"runtime",element.layoutId,"Active display stack")end
        end end
    end
    return refs
end
local function references(index,id,ignored)
    local out={}
    for _,ref in pairs(index[id] or {})do
        if ref.kind~="layout" or not (ignored and ignored[ref.key]) then out[#out+1]=ref.label end
    end
    table.sort(out);return out
end
function D:DisplayReferences(id,ignored) return references(usage(),id,ignored) end
function D:CleanupCandidates()
    local index,out=usage(),{}
    for id,raw in pairs(L:Nodes())do
        if type(raw)=="table" and raw.displayAnchor==1 and raw.anchorPoint~=1 then
            local owned=false
            for _,ref in pairs(index[id] or {})do if ref.kind~="layout" then owned=true end end
            if not owned then out[#out+1]={id=id,label=raw.label or "Aura display",references=references(index,id)}end
        end
    end
    table.sort(out,function(a,b)return a.label==b.label and a.id<b.id or a.label<b.label end)
    return out
end
function D:DeleteUnusedDisplays(ids)
    if InCombatLockdown() or not L.draft then return false,"Clean up while editing, outside combat." end
    local selected,count={},0
    for _,id in ipairs(ids or {})do
        local raw=L.draft[id]
        if not raw or raw.displayAnchor~=1 or raw.anchorPoint==1 then return false,"Select unused aura displays only." end
        if not selected[id]then selected[id]=true;count=count+1 end
    end
    if count==0 then return false,"Select a display to remove." end
    local index=usage()
    for id in pairs(selected)do
        local refs=references(index,id,selected)
        if #refs>0 then return false,"Display is still referenced: "..table.concat(refs,", "),refs end
    end
    for id in pairs(selected)do L.draft[id]=nil end
    L.dirty=true;self:Sync();L:Refresh(true);return true
end

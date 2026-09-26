-- One-time conversion of the retired group placement into ordinary Layout links.
-- Stage and validate before committing; keep the exact previous data for recovery.
local _,ns=...
local M=ns.LayoutModel
function ns.MigrateAnchorChains(profile)
    local layout=profile.layout
    if not layout or layout.anchorChains==1 then return end
    local elements=layout.elements or {}; local groups={}
    for id,raw in pairs(elements) do if type(raw)=="table" and raw.displayGroup==1 then groups[id]={raw=raw,items={}} end end
    if not next(groups) then layout.anchorChains=1; return end
    local studio=profile.modules and profile.modules.aura_studio
    local graphs=studio and studio.graphs or {}
    local seen={}
    -- Applied membership wins if a graph has an uncommitted different assignment.
    for _,which in ipairs({"applied","draft"}) do
        local ids={}; for id in pairs(graphs) do ids[#ids+1]=id end; table.sort(ids)
        for _,id in ipairs(ids) do
            local graph=graphs[id][which]
            for _,node in pairs(graph and graph.nodes or {}) do
                local c=node.config
                if node.type=="icon" and c and c.layoutId and not seen[c.layoutId] then
                    seen[c.layoutId]=true
                    local group=groups[c.displayGroup]
                    if group then group.items[#group.items+1]={id=c.layoutId,order=M.Number(c.displayOrder,0,-10000,10000),texture=c.texture,name=graphs[id].name.." / "..node.id} end
                end
            end
        end
    end
    local staged=M.Copy(elements)
    for id,group in pairs(groups) do
        local root=M.Normalize(staged[id]); root.displayGroup=nil; root.anchorPoint=1
        -- Keep the legacy first-cell rectangle: external references and matching
        -- dimensions retain their exact identity and size. New anchors are 0x0.
        staged[id]=root
        table.sort(group.items,function(a,b) return a.order==b.order and a.id<b.id or a.order<b.order end)
        local side=({UP="TOP",DOWN="BOTTOM",LEFT="LEFT",RIGHT="RIGHT"})[root.growth] or "RIGHT"
        local extent=(side=="TOP" or side=="BOTTOM") and root.height or root.width
        local previous=id
        for index,item in ipairs(group.items) do
            local n=M.Copy(staged[item.id] or {})
            n.displayAnchor=1; n.label=n.label or item.name; n.previewTexture=n.previewTexture or item.texture
            n.width,n.height=root.width,root.height; n.widthTarget,n.heightTarget=nil,nil
            n.link={target=previous,side=side,align="CENTER",gap=index==1 and -extent or M.Number(root.spacing,6,0,128),offset=0}
            n.collapseWidth,n.collapseHeight,n.collapseGap=true,true,true
            staged[item.id]=n; previous=item.id
        end
        root.growth,root.spacing=nil,nil
    end
    local ok,why=M.Validate(staged); assert(ok,"Anchor migration left original data unchanged: "..tostring(why))
    layout.anchorChainBackup=layout.anchorChainBackup or {version=1,elements=M.Copy(elements),graphs=M.Copy(graphs)}
    layout.elements=staged; layout.anchorChains=1
end

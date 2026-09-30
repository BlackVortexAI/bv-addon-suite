-- Stable slot ownership, independent of ordinary display recycling.
local _,ns=...
local Q={owners={}};ns.ActionStacks=Q
local V,M=ns.GraphValues,ns.LayoutModel
function Q:Tokens(config)
    local out={}
    if config.target=="party" or config.target=="raid" then
        for i=1,config.target=="party" and 4 or 40 do out[i]=config.target..i end
    else out[1]=config.target end
    return out
end
function Q:ValidLayout(config)
    local nodes=ns.Layout:Nodes();local root=nodes[config.layoutId]
    if not root or root.link or root.widthTarget or root.heightTarget then return false,"Action Stack root requires a free screen position" end
    local own={};for _,e in ipairs(config.elements) do own[e.layoutId]=true end
    for _,e in ipairs(config.elements) do
        local raw=nodes[e.layoutId]
        if not raw or raw.widthTarget and not own[raw.widthTarget] or raw.heightTarget and not own[raw.heightTarget]
            or raw.link and not own[raw.link.target] then return false,"Action elements may only link within their template" end
    end
    return true
end
local function placeholder(unit)
    return ns.DisplayModel.New("text",{font="alegreyaSansBold",fontSize=12,align="CENTER",wrap=true},unit.." / pending")
end
function Q:Open(owner,key,config,mode)
    assert(self:ValidLayout(config))
    self:Close(owner,key)
    self.owners[owner]=self.owners[owner] or {}
    local group={owner=owner,key=key,config=M.Copy(config),mode=mode,slots={}}
    self.owners[owner][key]=group
    for index,unit in ipairs(self:Tokens(config)) do group.slots[unit]={unit=unit,index=index,views={},media={},placeholder=placeholder(unit),visible=mode=="secure"} end
    self:Render(group)
end
function Q:Clear(owner,key,reference)
    local group=self.owners[owner] and self.owners[owner][key];if not group then return end
    local binding=reference and V.Object(reference,"unitref")
    for unit,slot in pairs(group.slots) do if not binding or binding.unit==unit and (not slot.reference or slot.reference==reference) then
        slot.media={};slot.hint=nil;slot.reference=nil
        if group.mode=="ooc" then slot.visible=false;slot.spellID=nil end
    end end
    self:Render(group,binding and binding.unit)
end
function Q:Set(owner,key,visible,payload,reference)
    local group=self.owners[owner] and self.owners[owner][key];if not group then return end
    if not visible or not payload then
        local binding=reference and V.Object(reference,"unitref")
        for unit,slot in pairs(group.slots) do if not binding or binding.unit==unit and (not slot.reference or slot.reference==reference) then slot.media={};slot.hint=nil;slot.reference=nil;slot.visible=false end end
        return self:Render(group,binding and binding.unit)
    end
    reference=payload.instance or reference
    local binding=reference and V.Object(reference,"unitref")
    if reference and not binding then return end
    if binding and owner.instanceRuntime then
        local current=owner.bindings and owner.bindings[binding.unit]
        if not current or current.reference~=reference then return end
    end
    for unit,slot in pairs(group.slots) do if not binding or binding.unit==unit then
        slot.media=V.RuntimeCopy(payload.media or {});slot.hint=payload.highlight;slot.reference=reference;slot.visible=true
        if group.mode=="ooc" then slot.spellID=payload.spellID end
    end end
    self:Render(group,binding and binding.unit)
end
function Q:Render(group,onlyUnit,refresh)
    local config=group.config
    if refresh or not group.prepared then
        local nodes=ns.Layout:Nodes();local records={};local levels={}
        for _,element in ipairs(config.elements) do records[element.layoutId]=nodes[element.layoutId];levels[element.layoutId]=ns.Layout:Level(element.layoutId) end
        local base=ns.Layout.rects and ns.Layout.rects[config.layoutId] or ns.DisplayAnchors.records[config.layoutId] and ns.DisplayAnchors.records[config.layoutId].rect
        local allowed=not ns.Layout.draft and not group.owner.stopped and ns.Layout:IsAvailable(config.layoutId)
        if refresh and group.prepared and group.allowed==allowed and ns.DisplayModel.Equal(group.records,records)
            and ns.DisplayModel.Equal(group.base,base) and ns.DisplayModel.Equal(group.levels,levels) then return end
        local template=base and M.ResolveTemplate(records,config.layoutId,base)
        local valid=self:ValidLayout(config)
        group.allowed=allowed;group.valid=valid and template~=nil;group.records=M.Copy(records);group.levels=levels;group.prepared=true
        if template and base then group.template=template;group.base=M.Copy(base) end
    end
    local template,base=group.template,group.base
    local visible=group.valid and group.allowed
    if not template or not base then return end
    local minX,maxX,minY,maxY
    for _,r in pairs(template.rects) do
        minX=math.min(minX or math.huge,r.x-r.width/2);maxX=math.max(maxX or -math.huge,r.x+r.width/2)
        minY=math.min(minY or math.huge,r.y-r.height/2);maxY=math.max(maxY or -math.huge,r.y+r.height/2)
    end
    for _,slot in pairs(group.slots) do if not onlyUnit or slot.unit==onlyUnit then
        local col=(slot.index-1)%config.columns;local row=math.floor((slot.index-1)/config.columns)
        for _,element in ipairs(config.elements) do
            local rect=template.rects[element.layoutId]
            local rec=slot.views[element.id] or {id=element.layoutId};slot.views[element.id]=rec;rec.level=(group.levels[element.layoutId] or 0)+5
            local geometry=rect and {x=base.x+rect.x+col*(maxX-minX+config.spacingX),y=base.y+rect.y-row*(maxY-minY+config.spacingY),width=rect.width,height=rect.height}
            local media=slot.media[element.id] or slot.placeholder
            if group.owner.test then
                ns.DisplayAnchors:Paint(rec,geometry,media,visible and slot.visible~=false and geometry~=nil)
            else
                ns.SecureActionMedia:Paint(rec,geometry,media,{owner=group.owner,spellID=slot.spellID or config.spellID,unit=slot.unit,mode=group.mode,hint=slot.hint},visible and slot.visible~=false and geometry~=nil)
            end
        end
    end end
end
function Q:RenderAll()
    for _,groups in pairs(self.owners) do for _,group in pairs(groups) do self:Render(group,nil,true) end end
end
function Q:Close(owner,key)
    local groups=self.owners[owner];if not groups then return end
    for id,group in pairs(groups) do if not key or id==key then
        for _,slot in pairs(group.slots) do for _,rec in pairs(slot.views) do
            ns.SecureActionMedia:Release(rec);ns.DisplayAnchors:ReleaseView(rec)
        end end
        groups[id]=nil
    end end
    if not next(groups) then self.owners[owner]=nil end
end
ns.Settings:BeforeProfileChange(Q,function()
    local owners={};for owner in pairs(Q.owners) do owners[#owners+1]=owner end
    for _,owner in ipairs(owners) do Q:Close(owner) end
end)

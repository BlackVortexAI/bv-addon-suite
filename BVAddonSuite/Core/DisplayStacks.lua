-- Repeated display ownership is separate from ordinary, single-view displays.
local _,ns=...
local D,M,V=ns.DisplayAnchors,ns.LayoutModel,ns.GraphValues
D.stacks={}
D.stackOwnerRevision=0
function D:StackActive(id)
    for _,groups in pairs(self.stacks) do for _,group in pairs(groups) do
        if not group.owner.stopped and next(group.entries) then
            for _,element in ipairs(group.config.elements) do if element.layoutId==id then return true end end
        end
    end end
    return false
end
local function stored() return ns.Layout.draft or ns.Layout:Store() end
function D:ClearStack(owner,key,reference)
    local group=self.stacks[owner] and self.stacks[owner][key]
    if not group then return end
    local binding=reference and V.Object(reference,"unitref")
    for id,entry in pairs(group.entries) do if not binding or id==binding.id then
        for _,rec in pairs(entry.views) do self:ReleaseView(rec) end
        group.entries[id]=nil
    end end
    group.layoutPending=true
    if next(group.entries) then self:QueueStack(group) else group.stackPending=nil end
    self:PruneStacks();ns.Layout:UpdateCursorTracking()
end
function D:CloseStacks(owner)
    self.stackOwnerRevision=self.stackOwnerRevision+1
    local groups=self.stacks[owner];self.stacks[owner]=nil
    for _,group in pairs(groups or {}) do for _,entry in pairs(group.entries) do
        for _,rec in pairs(entry.views) do self:ReleaseView(rec) end
    end end
    self:PruneStacks()
    -- A lower-priority owner may become visible after this owner disappears.
    local roots={};for _,group in pairs(groups or {}) do roots[group.config.layoutId]=true end
    for _,otherGroups in pairs(self.stacks) do for _,group in pairs(otherGroups) do if roots[group.config.layoutId] then
        group.layoutPending=true;self:QueueStack(group)
    end
    end end
    ns.Layout:UpdateCursorTracking()
end
function D:OpenStack(owner,key,config,priority)
    self.stackOwnerRevision=self.stackOwnerRevision+1
    self.stacks[owner]=self.stacks[owner] or {}
    if self.stacks[owner][key] then self:ClearStack(owner,key) end
    self.serial=self.serial+1
    local root=config.layoutId;local nodes=stored();local records={}
    for _,element in ipairs(config.elements) do records[element.layoutId]=nodes[element.layoutId] end
    local base=self.records[root] and self.records[root].rect or {x=0,y=0}
    local template=M.ResolveTemplate(records,root,base)
    self.stacks[owner][key]={owner=owner,key=key,config=M.Copy(config),entries={},priority=priority or 0,serial=self.serial,
        template=template,rootRaw=M.Copy(nodes[root]),baseRect=M.Copy(base),templateRecords=M.Copy(records),layoutPending=true}
    -- Hide superseded ownership immediately, then queue the replacement.
    for _,groups in pairs(self.stacks) do for _,group in pairs(groups) do if group.config.layoutId==root then
        if not self:StackWinner(group) then
            for _,entry in pairs(group.entries) do for _,rec in pairs(entry.views) do self:ReleaseView(rec) end end
        end
        group.layoutPending=true;self:QueueStack(group)
    end end end
    ns.Layout:UpdateExternalTracking()
end
function D:SetStack(owner,key,visible,payload,reference)
    local group=self.stacks[owner] and self.stacks[owner][key];if not group then return end
    reference=payload and payload.instance or reference
    local binding=reference and V.Object(reference,"unitref")
    if not binding then if not visible then self:ClearStack(owner,key) end;return end
    if not visible or not payload then self:ClearStack(owner,key,reference);return end
    local entry=group.entries[binding.id]
    local firstEntry=not next(group.entries)
    if not entry then
        local count=0;for _ in pairs(group.entries) do count=count+1 end
        assert(count<40,"Display Stack instance limit (40)")
        entry={id=binding.id,appearance=binding.appearance,reference=reference,unit=binding.unit,views={}}
        group.entries[binding.id]=entry
        group.layoutPending=true
    end
    local media={}
    for _,element in ipairs(group.config.elements) do
        local value=payload.media and payload.media[element.id]
        assert(value==nil or ns.DisplayModel.Valid(value),"Invalid stack media")
        media[element.id]=V.RuntimeCopy(value)
    end
    if V.IsSecret(entry.sortValue) or V.IsSecret(payload.sortValue) or entry.sortValue~=payload.sortValue then group.layoutPending=true end
    entry.media=media;entry.sortValue=payload.sortValue
    -- Demand follows ownership/membership, never the currently visible view.
    -- A newly populated external stack must start observing its pending target.
    if firstEntry then ns.Layout:UpdateExternalTracking() end
    if group.failed then
        if GetTime()<(group.retryAt or 0) then return end
        group.failed=nil;group.layoutPending=true
    end
    if group.layoutPending then self:QueueStack(group) end
    self:QueueStack(group,entry)
end
-- Templates and ordering are prepared once for a layout/membership change.
function D:PrepareStack(group)
    group.layoutPending=nil
    local nodes=stored();local root=group.config.layoutId;local raw=nodes[root]
    local records={};for _,element in ipairs(group.config.elements) do records[element.layoutId]=nodes[element.layoutId] end
    local template=raw and M.ResolveTemplate(records,root,self.records[root] and self.records[root].rect)
    if template then
        group.template=template;group.rootRaw=M.Copy(raw);group.templateRecords=M.Copy(records)
        group.baseRect=M.Copy(self.records[root] and self.records[root].rect or {x=0,y=0})
    else
        -- Keep accepted geometry during incomplete/unapplied template edits.
        template=group.template;raw=group.rootRaw
        if raw and group.templateRecords then
            local external=M.Copy(ns.Layout.rects or {})
            for id,rect in pairs(ns.Layout.externalRects or {}) do external[id]=M.Copy(rect) end
            local rects=M.Resolve(group.templateRecords,external,UIParent:GetWidth(),UIParent:GetHeight())
            group.baseRect=rects[root] or group.baseRect
        end
    end
    local anchor=raw and raw.link and raw.link.target
    local entries={};for _,entry in pairs(group.entries) do entries[#entries+1]=entry;entry.place=nil end
    local stackConfig=anchor and nodes[anchor] and nodes[anchor].stack
    group.stackSettings=M.Copy(stackConfig)
    if anchor and nodes[anchor] and nodes[anchor].anchorPoint==1 and not stackConfig then stackConfig={maxEntries=1} end
    local placements=template and M.StackPlacements(template,entries,stackConfig) or {}
    group.anchor=anchor
    for _,place in ipairs(placements) do place.entry.place=place end
    for _,entry in pairs(group.entries) do
        if entry.place then self:QueueStack(group,entry)
        else for _,rec in pairs(entry.views) do self:ReleaseView(rec) end end
    end
end
function D:StackWinner(group)
    if group.winnerRevision==self.stackOwnerRevision and group.winner and not group.winner.owner.stopped then return group.winner==group end
    local root=group.config.layoutId;local winner=group
    for _,groups in pairs(self.stacks) do for _,other in pairs(groups) do
        if not other.owner.stopped and other.config.layoutId==root and
            (other.priority>winner.priority or other.priority==winner.priority and other.serial>winner.serial) then winner=other end
    end end
    group.winner=winner;group.winnerRevision=self.stackOwnerRevision
    return winner==group
end
function D:PaintStackEntry(group,entry)
    local place,template=entry.place,group.template
    local allowed=ns.Layout:IsAvailable(group.config.layoutId) and place and template and self:StackWinner(group) and not ns.Layout.draft and not group.owner.stopped
    local native
    if allowed and group.anchor==ns.Layout.NAMEPLATE_TARGET and not group.owner.test then
        local api=C_NamePlate and C_NamePlate.GetNamePlateForUnit
        if api then local found,result=pcall(api,entry.unit);if found and not V.IsSecret(result) then native=result end end
        allowed=native~=nil
    end
    if not allowed then for _,rec in pairs(entry.views) do self:ReleaseView(rec) end;return end
    local base=group.baseRect or {x=0,y=0}
    for _,element in ipairs(group.config.elements) do
        local rect=template.rects[element.layoutId]
        local rec=entry.views[element.id] or {id=element.layoutId,inputOwner=group.owner,instance=entry.reference}
        entry.views[element.id]=rec
        if rect then
            local geometry={x=rect.x+(native and 0 or base.x)+(native and 0 or place.offsetX or 0),
                y=rect.y+(native and 0 or base.y)+(native and 0 or place.offsetY or 0),width=rect.width,height=rect.height}
            local media=entry.media and entry.media[element.id]
            if not native and rec.view and rec.view.nativeAnchor then ns.UI:ResetDisplayAttachment(rec.view);rec.geometry=nil end
            self:Paint(rec,geometry,media,media~=nil)
            if native and rec.view and media then
                local ok,why=ns.UI:AnchorDisplayToNameplate(rec.view,native,geometry,group.rootRaw.link,template.root)
                assert(ok,why)
            end
        else self:ReleaseView(rec) end
    end
end
function D:RenderStacks(force)
    if ns.ActionStacks then ns.ActionStacks:RenderAll() end
    -- Direct callers/editor transitions retain immediate presentation. Runtime
    -- layout refreshes invalidate only groups whose accepted inputs changed.
    if force==nil then force=true end
    if self.renderingStacks then return end;self.renderingStacks=true
    local nodes=stored()
    for _,groups in pairs(self.stacks) do for _,group in pairs(groups) do
        local allowed=ns.Layout:IsAvailable(group.config.layoutId)
        local changed=force or group.layoutPending or group.layoutAllowed~=allowed
        group.layoutAllowed=allowed
        group.drawLevels=group.drawLevels or {}
        if not allowed then
            for _,entry in pairs(group.entries) do for _,rec in pairs(entry.views) do self:ReleaseView(rec) end end
        end
        for _,element in ipairs(group.config.elements) do
            local level=ns.Layout:Level(element.layoutId)
            if group.drawLevels[element.layoutId]~=level then group.drawLevels[element.layoutId]=level;changed=true end
            if not ns.DisplayModel.Equal(group.templateRecords and group.templateRecords[element.layoutId],nodes[element.layoutId]) then changed=true end
        end
        local raw=nodes[group.config.layoutId];local anchor=raw and raw.link and raw.link.target
        if not ns.DisplayModel.Equal(group.stackSettings,anchor and nodes[anchor] and nodes[anchor].stack or nil) then changed=true end
        local base=self.records[group.config.layoutId] and self.records[group.config.layoutId].rect
        if anchor~=ns.Layout.NAMEPLATE_TARGET then
            if not ns.DisplayModel.Equal(group.baseRect,base) then changed=true end
        elseif base and (not group.baseRect or base.width~=group.baseRect.width or base.height~=group.baseRect.height) then changed=true end
        if changed then group.layoutPending=true;self:QueueStack(group) end
    end end
    if force then self:FlushStacks(true) end
    self.renderingStacks=false
    ns.Layout:UpdateCursorTracking()
end
ns.Settings:BeforeProfileChange(D.stacks,function() local owners={};for owner in pairs(D.stacks) do owners[#owners+1]=owner end;for _,owner in ipairs(owners) do D:CloseStacks(owner) end end)

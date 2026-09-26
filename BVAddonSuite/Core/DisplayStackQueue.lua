-- One demand-driven visual queue. Semantic events stay in the graph runtime.
local _,ns=...
local D=ns.DisplayAnchors
D.stackQueue={};D.stackHead=1
D.stackSliceLimit=8;D.stackSliceBudget=.75
function D:StackCurrent(group)
    return self.stacks[group.owner] and self.stacks[group.owner][group.key]==group and not group.owner.stopped
end
function D:WakeStacks()
    if self.stackTimer or self.flushingStacks or #self.stackQueue<self.stackHead then return end
    self.stackTimer=C_Timer.NewTimer(.016,function()
        self.stackTimer=nil;self:FlushStacks(false)
    end)
end
function D:QueueStack(group,entry)
    if not self:StackCurrent(group) then return end
    local target=entry or group
    if not target.stackPending then
        local item={group=group,entry=entry};target.stackPending=item
        if ns.Performance.active then ns.Performance:Queued(item);ns.Performance:Count("visual_enqueued") end
        self.stackQueue[#self.stackQueue+1]=item
    elseif ns.Performance.active then
        ns.Performance:Count("visual_coalesced")
    end
    self:WakeStacks()
end
function D:PruneStacks()
    local kept={}
    for i=self.stackHead,#self.stackQueue do
        local item=self.stackQueue[i];local group,entry=item.group,item.entry
        local target=entry or group
        if self:StackCurrent(group) and (not entry or group.entries[entry.id]==entry) and target.stackPending==item then
            kept[#kept+1]=item
        elseif target.stackPending==item then target.stackPending=nil end
    end
    self.stackQueue=kept;self.stackHead=1
    if #kept==0 and self.stackTimer then self.stackTimer:Cancel();self.stackTimer=nil end
end
function D:FailStack(group,why)
    group.failed=true;group.layoutPending=nil;group.stackPending=nil
    group.retryAt=GetTime()+1
    for _,entry in pairs(group.entries) do
        entry.stackPending=nil
        for _,rec in pairs(entry.views) do self:ReleaseView(rec) end
    end
    local message=ns.GraphValues.Error(why)
    if group.failure~=message then
        group.failure=message
        if self.diagnose then self.diagnose(group.config.layoutId,message) else ns:Report('display/stack',message) end
    end
end
function D:FlushStacks(force)
    if self.flushingStacks then return end
    local perfStarted=ns.Performance.active and ns.Performance:Begin()
    if self.stackTimer then self.stackTimer:Cancel();self.stackTimer=nil end
    self.flushingStacks=true
    local started=debugprofilestop and debugprofilestop() or 0;local work=0;local layoutChanged=false
    while self.stackHead<=#self.stackQueue do
        local item=self.stackQueue[self.stackHead];self.stackHead=self.stackHead+1
        local group,entry=item.group,item.entry;local target=entry or group
        if target.stackPending==item then
            target.stackPending=nil
            if self:StackCurrent(group) and not group.failed and (not entry or group.entries[entry.id]==entry) then
                if ns.Performance.active then ns.Performance:Wait(item,"visual_wait_ms") end
                local ok,why=pcall(function()
                    if group.layoutPending then
                        local prepareStarted=ns.Performance.active and ns.Performance:Begin()
                        self:PrepareStack(group);layoutChanged=true
                        if ns.Performance.active then ns.Performance:Finish("stack_prepare_ms",prepareStarted) end
                    end
                    if entry then
                        -- Preparation may have requeued this entry. This paint
                        -- consumes its newest state without another queue slot.
                        entry.stackPending=nil;self:PaintStackEntry(group,entry)
                    end
                end)
                if not ok then
                    if ns.Performance.active then ns.Performance:Count("visual_errors") end
                    self:FailStack(group,why)
                end
            end
        end
        work=work+1
        -- A complete instance is atomic; time is a soft limit, not preemption.
        if not force and (work>=self.stackSliceLimit or debugprofilestop and debugprofilestop()-started>=self.stackSliceBudget) then break end
    end
    self.flushingStacks=false
    if self.stackHead>#self.stackQueue then self.stackQueue={};self.stackHead=1
    elseif self.stackHead>128 and self.stackHead>#self.stackQueue/2 then self:PruneStacks() end
    self:WakeStacks()
    if layoutChanged then ns.Layout:UpdateCursorTracking() end
    if ns.Performance.active then ns.Performance:Finish("visual_slice_ms",perfStarted) end
end

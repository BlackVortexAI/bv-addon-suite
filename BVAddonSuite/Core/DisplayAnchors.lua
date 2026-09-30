-- Owners control visibility; the shared Layout resolver owns all geometry.
local _,ns=...
local D={records={},owners={},serial=0,pool={}}
ns.DisplayAnchors=D
local function validID(id) return type(id)=="string" and #id==40 and id:match("^bv_aura:%x+$") end
local function nodes() return ns.Layout.draft or (ns.Settings:Profile().layout or {}).elements or {} end
local function label(raw) return (raw.anchorPoint==1 and "Anchor: " or "")..(type(raw.label)=="string" and raw.label or "Aura display") end
function D:ReleaseView(rec,keepSecure)
    if rec.presentation and rec.presentation.release then rec.presentation.release() end
    if not keepSecure and ns.SecureActionMedia then ns.SecureActionMedia:Release(rec) end
    if not keepSecure and ns.SecureSpells then ns.SecureSpells:Release(rec) end
    if rec.view then rec.view:Present(nil,false); if ns.UI.ResetDisplayAttachment then ns.UI:ResetDisplayAttachment(rec.view) end; self.pool[#self.pool+1]=rec.view; rec.view=nil; rec.geometry=nil end
end
function D:NewID()
    ns.Layout:Store(); local stored=nodes()
    for _=1,32 do
        local parts={}; for i=1,8 do parts[i]=string.format("%04x",math.random(0,65535)) end
        local id="bv_aura:"..table.concat(parts); if not stored[id] then return id end
    end
    error("Could not allocate a unique display anchor")
end
function D:Sync()
    local profile=ns.Settings:Profile(); ns.MigrateAnchorChains(profile)
    local stored=nodes()
    if self.profile~=profile then
        for _,rec in pairs(self.records) do self:ReleaseView(rec) end
        self.records={}; self.owners={}; self.previewItems=nil; self.profile=profile
    end
    local kept={}
    for _,id in ipairs(ns.Layout.order) do
        local def=ns.Layout.elements[id]
        if def.displayAnchor and (not stored[id] or not self.records[id]) then
            if self.records[id] then self:ReleaseView(self.records[id]) end
            self.records[id]=nil; ns.Layout.elements[id]=nil; ns.Layout.applied[id]=nil
        else kept[#kept+1]=id end
    end
    ns.Layout.order=kept
    for id,raw in pairs(stored) do
        if validID(id) and type(raw)=="table" and (raw.displayAnchor==1 or raw.anchorPoint==1) then
            local rec=self.records[id]
            if not rec then
                rec={id=id,owners={},raw=raw,visible=false}; self.records[id]=rec
                local point=raw.anchorPoint==1
                ns.Layout:Register(id,{displayAnchor=true,anchorPoint=point,label=label(raw),
                    defaults=function() return rec.raw end,
                    listed=function() return not rec.presentation or rec.presentation.enabled end,
                    limits={minWidth=point and 0 or 8,maxWidth=512,minHeight=point and 0 or 8,maxHeight=512},
                    validate=point and function(n,all) return D:ValidateAnchor(n,all,id) end or nil,
                    active=not point and function() return rec.presentation and rec.presentation.active() or rec.visible or D.StackActive and D:StackActive(id) end or nil,
                    measure=function(rect) if rec.presentation then return rec.presentation.measure(rect) end end,
                    transform=not point and function() return rec.visible and not rec.preview and rec.media or nil end or nil,
                    apply=function(rect)
                        rec.rect=rect
                        if not point then
                            -- Layout can move a sibling outside its runtime step.
                            -- Never route a display fault to the global Lua popup.
                            local ok,why=pcall(D.Paint,D,rec,rect,rec.media or rec.texture,rec.visible)
                            if not ok then
                                pcall(D.Paint,D,rec,rect,nil,false)
                                local message=ns.GraphValues.Error(why)
                                if rec.paintError~=message and D.diagnose then D.diagnose(rec.id,message) end
                                rec.paintError=message
                            else rec.paintError=nil end
                        end
                    end,
                    preview=function(enabled) rec.preview=enabled==true; if not point then D:Render(rec) end end,
                    enabled=function() if rec.presentation then return rec.presentation.enabled end;return point or next(rec.owners)~=nil or D.StackActive and D:StackActive(id) end})
            end
            rec.raw=raw; ns.Layout.elements[id].label=label(raw)
            ns.Layout.elements[id].templateId=raw.templateId;ns.Layout.elements[id].templateRoot=raw.templateRoot
        end
    end
end
function D:ValidateAnchor(n,all,id)
    if type(n.label)~="string" or not n.label:find("%S") or #n.label>80 or n.label:find("[%c|]") then return false,"Use an anchor name of 1..80 characters without control codes or |" end
    for key,raw in pairs(all) do
        if key~=id and raw.anchorPoint==1 and type(raw.label)=="string" and raw.label:lower()==n.label:lower() then return false,"That anchor name is already in use" end
    end
    return true
end
function D:NewAnchor()
    ns.Layout:Store(); local stored=nodes(); local count,names=0,{}
    for _,raw in pairs(stored) do if raw.anchorPoint==1 then count=count+1; names[type(raw.label)=="string" and raw.label:lower() or ""]=true end end
    assert(count<32,"Anchor limit reached (32 per profile)")
    local index=1; while names["anchor "..index] do index=index+1 end
    local id=self:NewID()
    stored[id]={anchorPoint=1,label="Anchor "..index,width=0,height=0,x=0,y=0,screen="CENTER"}
    if ns.Layout.draft then ns.Layout.dirty=true end
    self:Sync(); ns.Layout:Refresh(); if not ns.Layout.draft then ns.Layout:Saved() end; return id
end
-- Read saved module data as well: deletion must stay safe with AuraStudio unloaded.
function D:AnchorReferences(id)
    local refs,seen={},{}
    local function add(key,text)
        if not seen[key] then seen[key]=true; refs[#refs+1]=text end
    end
    local function linked(raw)
        return type(raw)=="table" and (raw.widthTarget==id or raw.heightTarget==id or (raw.link and raw.link.target==id))
    end
    for key,raw in pairs(nodes()) do
        if key~=id and linked(raw) then add("layout:"..key,"Element: "..(raw.label or (ns.Layout.elements[key] or {}).label or key)) end
    end
    local profile=ns.Settings:Profile()
    local studio=profile.modules and profile.modules.aura_studio
    for key,rec in pairs(studio and studio.graphs or {}) do
        local used=false
        for _,graph in pairs({rec.draft,rec.applied}) do
            for _,node in pairs(graph.nodes or {}) do
                local c=node.config or {}; if c.layoutId==id or c.displayGroup==id then used=true end
            end
        end
        local snapshot=rec.displayLayout or {}
        for _,target in pairs(snapshot.anchorRefs or {}) do if target==id then used=true end end
        for _,collection in ipairs({snapshot.elements or {},snapshot.dependencies or {}}) do
            for target,raw in pairs(collection) do if target==id or linked(raw) then used=true end end
        end
        if used then add("graph:"..key,"Graph (saved layout): "..(rec.name or key)) end
    end
    table.sort(refs); return refs
end
function D:DeleteAnchor(id)
    local L=ns.Layout
    if InCombatLockdown() or not L.draft then return false,"Delete anchors while editing, outside combat." end
    local raw=L.draft[id]
    if not raw or raw.anchorPoint~=1 then return false,"Only neutral anchor points can be deleted." end
    local refs=self:AnchorReferences(id)
    if #refs>0 then return false,"Anchor is still referenced.",refs end
    L.draft[id]=nil; L.dirty=true
    self:Sync(); L:Refresh(true); return true
end
function D:Ensure(id,name,texture,saved,presentation)
    assert(validID(id),"Invalid display anchor ID")
    local ref=ns.IconCatalog:Reference(texture); assert(ref,"Invalid icon texture")
    local stored=ns.Layout:Store()
    local changed=not stored[id] or stored[id].label~=name or stored[id].previewTexture~=ref
    if not stored[id] then stored[id]=saved and ns.LayoutModel.Copy(saved) or {displayAnchor=1,width=48,height=48,x=0,y=0,screen="CENTER"} end
    assert(stored[id].displayAnchor==1,"Display anchor identity collision")
    stored[id].label=name; stored[id].previewTexture=ref
    if ns.Layout.draft then
        if not ns.Layout.draft[id] then ns.Layout.draft[id]=ns.LayoutModel.Copy(stored[id]) end
        ns.Layout.draft[id].label=name; ns.Layout.draft[id].previewTexture=ref
    end
    self:Sync()
    local rec=self.records[id]
    if rec.presentation~=presentation then self:ReleaseView(rec);rec.presentation=presentation end
    ns.Layout.elements[id].autoHeight=presentation~=nil
    if changed or not self.records[id].rect then ns.Layout:Refresh() end
    return id
end
function D:BeginPreview() self.previewItems=self.previewProvider and self.previewProvider() or {} end
function D:Paint(rec,rect,texture,visible)
    if rec.presentation then rec.presentation.paint(rect,rec.preview==true);return end
    if rec.actionEntry and not rec.preview then
        self:ReleaseView(rec,true)
        if rec.secureButton then ns.SecureSpells:Release(rec) end
        rec.level=ns.Layout:Level(rec.id)
        local e=rec.actionEntry;local a=e.action
        local keys,labels
        if e.shortcut and self.shortcutProvider then keys,labels=self.shortcutProvider(e.shortcut) end
        ns.SecureActionMedia:Paint(rec,rect,rec.media,a and {owner=e.owner,action=a,mode="secure",hint=e.actionHint,hoverMedia=e.hoverMedia,pressedMedia=e.pressedMedia,
            shortcuts=keys,shortcutLabels=labels},visible and ns.Layout:IsAvailable(rec.id))
        return
    elseif rec.actionSurface then ns.SecureActionMedia:Release(rec) end
    if ns.SecureSpells and rec.secureEntry and not rec.preview then
        self:ReleaseView(rec,true)
        ns.SecureSpells:Paint(rec,rect,visible and ns.Layout:IsAvailable(rec.id))
        return
    elseif ns.SecureSpells and rec.secureButton then ns.SecureSpells:Release(rec) end
    visible=visible and ns.Layout:IsAvailable(rec.id) and rect~=nil and rect.width>0 and rect.height>0
    if not visible and not rec.view then return end
    local perfStarted=ns.Performance.active and ns.Performance:Begin()
    if ns.Performance.active then ns.Performance:Count("paint_calls") end
    if not rec.view then rec.view=table.remove(self.pool) or ns.UI:DisplayIcon(); rec.geometry=nil end
    if ns.ExternalFrames then ns.ExternalFrames:MarkOwned(rec.view) end
    rec.view:SetDisplayLevel(ns.Layout:Level(rec.id))
    if rec.preview then rec.view:SetNativeSource(nil) else rec.view:SetNativeSource(self.nativeSource) end
    if not rec.inputCallback then rec.inputCallback=function(event)
        if rec.instance then event.instance=rec.instance end
        if rec.inputOwner and D.inputHandler then D.inputHandler(rec.inputOwner,event) end
    end end
    if rec.preview or not rec.inputOwner or rec.inputOwner.test then rec.view:SetInputHandler(nil)
    else rec.view:SetInputHandler(rec.inputCallback,rec.inputOwner,rec.instance) end
    local old=rec.geometry
    if visible and (not old or old.x~=rect.x or old.y~=rect.y or old.width~=rect.width or old.height~=rect.height) then
        rec.view:Geometry(rect); rec.geometry=ns.LayoutModel.Copy(rect)
    end
    rec.view:Present(texture,visible)
    local missing=visible and rec.view.assetUnavailable==true
    if missing and not rec.assetError and self.diagnose then self.diagnose(rec.id,"Graphic asset unavailable. Check the addon path and file format.") end
    rec.assetError=missing
    if ns.Performance.active then ns.Performance:Finish("paint_ms",perfStarted) end
end
function D:Render(rec)
    local chosen
    for _,entry in pairs(rec.owners) do
        if not chosen or entry.priority>chosen.priority or (entry.priority==chosen.priority and entry.serial>chosen.serial) then chosen=entry end
    end
    local item=rec.preview and self.previewItems and self.previewItems[rec.id]
    rec.inputOwner=chosen and chosen.owner or nil
    rec.actionEntry=chosen and chosen.actionDisplay and chosen or nil
    rec.secureEntry=chosen and chosen.secureSpell and chosen or nil
    local texture=rec.preview and ns.IconCatalog:Reference(item and item.texture or rec.raw.previewTexture) or (chosen and chosen.texture)
    local media=rec.preview and item and item.media or (not rec.preview and chosen and chosen.media)
    if not media and texture and ((rec.preview and item and item.cropBorder==false) or (not rec.preview and chosen and chosen.cropBorder==false)) then
        media=ns.DisplayModel.New("icon",{texture=texture,cropBorder=false})
    end
    if rec.preview and media then media=ns.GraphValues.RuntimeCopy(media); media.ops={}; media.alpha=1 end
    local visible=(media~=nil or texture~=nil) and (rec.preview or (chosen and chosen.visible==true)) or false
    local changed=rec.visible~=visible or not ns.DisplayModel.SameLayout(rec.media,media)
    rec.visible=visible; rec.texture=texture; rec.media=media
    if changed then ns.Layout:Refresh() end
    if rec.preview then
        -- A broken preview must never abort navigation or leave the editor
        -- half-open. Keep its mover available so the graph can be repaired.
        local ok,why=pcall(self.Paint,self,rec,rec.rect,media or texture,visible)
        if not ok then
            pcall(self.Paint,self,rec,rec.rect,nil,false)
            local message=ns.GraphValues.Error(why)
            if rec.paintError~=message and self.diagnose then self.diagnose(rec.id,message) end
            rec.paintError=message
        else rec.paintError=nil end
    else self:Paint(rec,rec.rect,media or texture,visible) end
    if not chosen and not rec.preview then self:ReleaseView(rec) end
end
function D:Open(owner,items,priority)
    local seen={}
    for _,item in ipairs(items) do
        assert(self.records[item.anchor] and self.records[item.anchor].raw.displayAnchor==1 and not seen[item.anchor],"Invalid or repeated display anchor")
        assert(ns.IconCatalog:Reference(item.texture),"Invalid icon texture"); seen[item.anchor]=true
    end
    self:Close(owner); local bindings={}; self.owners[owner]=bindings
    for _,item in ipairs(items) do
        local rec=self.records[item.anchor]; self.serial=self.serial+1
        local entry={record=rec,owner=owner,texture=assert(ns.IconCatalog:Reference(item.texture)),visible=false,priority=priority or 0,serial=self.serial}
        entry.actionDisplay=item.actionDisplay
        entry.shortcut=item.actionDisplay and item.shortcut or nil
        entry.secureSpell=item.secureSpell
        entry.cropBorder=item.cropBorder
        bindings[item.key]=entry; rec.owners[owner]=entry; self:Render(rec)
    end
    ns.Layout:UpdateExternalTracking()
end
function D:SetSecureHint(owner,key,hint)
    local entry=self.owners[owner] and self.owners[owner][key]
    if entry and entry.secureSpell then
        entry.secureHint=nil
        if not ns.GraphValues.IsSecret(hint) and type(hint)=="boolean" then entry.secureHint=hint end
        if ns.SecureSpells then ns.SecureSpells:Cue(entry.record) end
    end
end
-- Profile key assignments changed: repaint shortcut-enabled action displays.
function D:RefreshShortcuts()
    for _,rec in pairs(self.records) do
        if rec.actionEntry and rec.actionEntry.shortcut then self:Render(rec) end
    end
end
function D:SetAction(owner,key,visible,media,action,hint,states)
    local entry=self.owners[owner] and self.owners[owner][key];if not entry then return end
    assert(action==nil or ns.GraphModel.Action(action),"Invalid spell action")
    assert(media==nil or ns.DisplayModel.Valid(media),"Invalid action media")
    entry.action=action and ns.GraphValues.RuntimeCopy(action) or nil
    entry.hoverMedia=states and ns.GraphValues.RuntimeCopy(states.hoverMedia) or nil
    entry.pressedMedia=states and ns.GraphValues.RuntimeCopy(states.pressedMedia) or nil
    entry.actionHint=not ns.GraphValues.IsSecret(hint) and hint==true
    entry.visible=visible==true;entry.media=media and ns.GraphValues.RuntimeCopy(media) or nil
    self:Render(entry.record)
end
function D:Set(owner,key,visible,media)
    local bindings=self.owners[owner]; local entry=bindings and bindings[key]
    if media~=nil then assert(ns.DisplayModel.Valid(media),"Invalid display media") end
    if entry and (entry.visible~=(visible==true) or not ns.DisplayModel.Equal(entry.media,media)
        or (media and (media.nativeBinding or media.cooldown))) then
        entry.visible=visible==true; entry.media=media and ns.GraphValues.RuntimeCopy(media) or nil; self:Render(entry.record)
    end
end
function D:Close(owner)
    local bindings=self.owners[owner]; if not bindings then return end
    self.owners[owner]=nil
    for _,entry in pairs(bindings) do entry.record.owners[owner]=nil; self:Render(entry.record) end
    ns.Layout:UpdateExternalTracking()
end

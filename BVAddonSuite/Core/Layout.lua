local _, ns = ...
local M = ns.LayoutModel
local Layout = { elements={}, order={}, providers={}, applied={}, saveListeners={} }
ns.Layout = Layout
Layout.CURSOR_TARGET = "builtin:cursor"
Layout.NAMEPLATE_TARGET = "builtin:nameplate"

function Layout:TargetAllowed(id,axis,target)
    if axis=="height" and self.elements[id] and self.elements[id].autoHeight then return target=="none" end
    local targetDef=self.elements[target]
    if targetDef and targetDef.listed and not targetDef.listed() then return false end
    local external=type(target)=="string" and target:match("^frame:(.*)$")
    if external and (not ns.ExternalFrames or not ns.ExternalFrames:CanReference(external,self:Nodes())) then return false end
    local all=self:Nodes();local n=all[id]
    if not n or id==target then return false end
    local child=n.templateId and n.templateRoot~=id
    if target=="none" then return not child or axis~="position" end
    if target==self.NAMEPLATE_TARGET then return axis=="position" and n.templateId~=nil and n.templateRoot==id end
    if child then local t=all[target];return t~=nil and t.templateId==n.templateId end
    return true
end
function Layout:StackSettings(id)
    local all=self:Nodes();local n=all[id]
    local root=n and n.templateId and all[n.templateRoot]
    local anchor=root and root.link and all[root.link.target]
    return anchor and anchor.anchorPoint==1 and anchor.stack and M.NormalizeStack(anchor.stack) or nil
end

function Layout:ReadCursor()
    if type(GetCursorPosition)~="function" then return nil end
    local ok,x,y=pcall(GetCursorPosition)
    local scale=UIParent:GetEffectiveScale()
    if not ok or ns.GraphValues.IsSecret(x) or ns.GraphValues.IsSecret(y) or ns.GraphValues.IsSecret(scale) then return nil end
    if x==nil or y==nil or scale==nil or M.Number(x,nil,-1000000,1000000)~=x or M.Number(y,nil,-1000000,1000000)~=y
        or M.Number(scale,nil,.01,100)~=scale then return nil end
    return {x=x/scale-UIParent:GetWidth()/2,y=y/scale-UIParent:GetHeight()/2,width=0,height=0}
end
function Layout:FreezeCursor(freeze)
    self.cursorFrozen=freeze and (self:ReadCursor() or {x=0,y=0,width=0,height=0}) or nil
    if freeze then self:StopCursor() end
end
function Layout:StopCursor()
    if self.cursorTimer then self.cursorTimer:Cancel(); self.cursorTimer=nil end
    ns.Events:Release(self)
    self.cursorLast=nil
end
function Layout:NeedsCursor()
    if self.cursorFrozen then return false end
    local nodes=self:Nodes()
    local function follows(id,seen)
        if id==self.CURSOR_TARGET then return true end
        if seen[id] or not self.elements[id] or not nodes[id] then return false end
        seen[id]=true
        local link=nodes[id].link
        return link and follows(link.target,seen) or false
    end
    for id,def in pairs(self.elements) do
        if not def.anchorPoint and (not def.enabled or def.enabled()) and (not def.active or def.active())
            and (not def.cursorActive or def.cursorActive())
            and follows(id,{}) then return true end
    end
    return false
end
function Layout:UpdateExternalTracking()
    if ns.ExternalFrames then ns.ExternalFrames:SyncDemand(self:Nodes(),self.elements,self.draft~=nil) end
end
function Layout:IsAvailable(id)
    if self.availability and self.availability[id]~=nil then return self.availability[id] end
    return not ns.ExternalFrames or ns.ExternalFrames:Allows(id,self:Nodes())
end
function Layout:Level(id) return self.levels and self.levels[id] or 8 end
function Layout:UpdateCursorTracking()
    self:UpdateExternalTracking()
    if not self:NeedsCursor() then self:StopCursor(); return end
    if self.cursorTimer or not (C_Timer and C_Timer.NewTicker) then return end
    self.cursorLast=self:ReadCursor()
    self.cursorTimer=C_Timer.NewTicker(.016,function()
        local ok=ns:Call("layout/cursor",function()
            if not self:NeedsCursor() then self:StopCursor(); return end
            local rect=self:ReadCursor(); local old=self.cursorLast
            if (rect==nil)~=(old==nil) or (rect and (not old or rect.x~=old.x or rect.y~=old.y)) then
                self.cursorLast=rect; self:Refresh()
            end
        end)
        if not ok then self:StopCursor() end
    end)
    for _,event in ipairs({"UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED"}) do
        ns.Events:Subscribe(self,event,function() self.cursorLast=nil; self:Refresh(true) end)
    end
    ns.Events:Subscribe(self,"PLAYER_LOGOUT",function() self:StopCursor() end)
end

function Layout:Register(id, definition)
    assert(type(id)=="string" and id:find(":",1,true) and not self.elements[id],"Unique namespaced layout ID required")
    assert(type(definition.defaults)=="function" and type(definition.apply)=="function","Editable element contract missing")
    self.elements[id]=definition; self.order[#self.order+1]=id
end
-- Editor presentation flags set by the owning node: hidden elements stay out of
-- the Layout Editor (links still move them), locked ones keep their size.
function Layout:SetEditorFlags(id,hidden,sizeLocked)
    local def=self.elements[id];if not def then return end
    def.editorHidden=hidden==true or nil;def.sizeLocked=sizeLocked==true or nil
end
-- Future providers return rectangles in UIParent coordinates and call Notify when
-- geometry/availability changes. Registration never discovers or mutates a frame.
function Layout:RegisterProvider(name, provider)
    assert(not self.providers[name] and type(provider.resolve)=="function","Invalid target provider")
    self.providers[name]=provider
end
function Layout:Store()
    local profile=ns.Settings:Profile()
    if type(profile.layout)~="table" then profile.layout={version=1,elements={}} end
    assert(profile.layout.version==1,"Unsupported layout schema")
    if type(profile.layout.elements)~="table" then profile.layout.elements={} end
    if ns.DisplayAnchors then ns.DisplayAnchors:Sync() end
    for _,id in ipairs(self.order) do
        if not profile.layout.elements[id] and not (self.draft and self.draft[id]) then profile.layout.elements[id]=M.Normalize(self.elements[id].defaults()) end
    end
    return profile.layout.elements
end
function Layout:Nodes() return self.draft or self:Store() end
function Layout:Get(id) return M.Normalize(assert(self:Nodes()[id],"Unknown layout element")) end
function Layout:Resolve()
    if ns.DisplayAnchors then ns.DisplayAnchors:Sync() end
    -- Keep dormant package data in storage, but never resolve absent addon frames.
    local stored,nodes,external=self:Nodes(),{},{}
    for _,id in ipairs(self.order) do nodes[id]=stored[id] end
    self.levels,self.drawRanks,self.drawCount=M.DrawOrder(nodes)
    if ns.ExternalFrames then ns.ExternalFrames:SyncDemand(nodes,self.elements,self.draft~=nil) end
    for _,raw in pairs(nodes) do
        local n=M.Normalize(raw)
        for _,id in pairs({n.widthTarget,n.heightTarget,n.link and n.link.target}) do
            if id==self.CURSOR_TARGET then
                external[id]=self.cursorFrozen or self:ReadCursor()
            elseif id==self.NAMEPLATE_TARGET then
                -- Stable editing reference only. Native nameplate attachment is
                -- performed by the display owner without reading frame geometry.
                external[id]={x=0,y=0,width=0,height=0}
            elseif not nodes[id] and not external[id] then
                local name,key=id:match("^([^:]+):(.+)$")
                local provider=name and self.providers[name]
                if provider then
                    local ok,rect=ns:Call("layout/target",provider.resolve,key)
                    if ok and type(rect)=="table" then
                        local valid=true
                        for _,field in ipairs({"x","y","width","height"}) do
                            if M.Number(rect[field],nil,-10000,10000)~=rect[field] or rect[field]==nil then valid=false end
                        end
                        if valid and rect.width>0 and rect.height>0 then external[id]=rect end
                    end
                end
            end
        end
    end
    local activity,transforms={},{}
    local editing=self.draft and not (ns.LayoutEditor and ns.LayoutEditor.suspended)
    if not editing then
        for id,def in pairs(self.elements) do if def.active and not (stored[id] and stored[id].templateId) then activity[id]=def.active()==true end end
        for id,def in pairs(self.elements) do if def.transform and not (stored[id] and stored[id].templateId) then transforms[id]=def.transform() end end
    end
    local unboundedNodes={}
    for id,raw in pairs(nodes)do if raw.templateId and raw.templateRoot~=id then unboundedNodes[id]=true end end
    local rects,warnings,constrained=M.Resolve(nodes,external,UIParent:GetWidth(),UIParent:GetHeight(),activity,transforms,{unboundedNodes=unboundedNodes})
    -- Content-sized surfaces report their current footprint without writing
    -- runtime text measurements into the user's saved layout.
    local measured=false
    for id,def in pairs(self.elements) do
        if def.measure and rects[id] then
            local height,width=def.measure(rects[id])
            if height and M.Number(height,nil,1,2000)==height then
                nodes[id]=M.Copy(nodes[id]);nodes[id].height=height;nodes[id].heightTarget=nil;measured=true
                if width and M.Number(width,nil,1,5000)==width then nodes[id].width=width;nodes[id].widthTarget=nil end
            end
        end
    end
    if measured then rects,warnings,constrained=M.Resolve(nodes,external,UIParent:GetWidth(),UIParent:GetHeight(),activity,transforms,{unboundedNodes=unboundedNodes}) end
    self.availability={}
    if ns.ExternalFrames then
        local memo={}
        for id in pairs(nodes) do self.availability[id]=ns.ExternalFrames:Allows(id,nodes,memo) end
    end
    self.externalRects=external
    self.constrained=constrained
    return rects,warnings
end
local function same(a,b) return a and b and a.x==b.x and a.y==b.y and a.width==b.width and a.height==b.height end
function Layout:Refresh(force,immediateStacks)
    if self.refreshing then return end
    local perfStarted=ns.Performance.active and ns.Performance:Begin()
    self.refreshing=true
    local ok,err=pcall(function()
        self.rects,self.warnings=self:Resolve()
        for _,id in ipairs(self.order) do
            local rect=self.rects[id]
            local allowed=self:IsAvailable(id)
            self.appliedAvailability=self.appliedAvailability or {}
            self.appliedLevels=self.appliedLevels or {}
            local level=self:Level(id)
            if force or not same(rect,self.applied[id]) or self.appliedAvailability[id]~=allowed or self.appliedLevels[id]~=level then
                self.appliedLevels[id]=level
                self.appliedAvailability[id]=allowed
                self.applied[id]=M.Copy(rect)
                ns:Call("layout/"..id,self.elements[id].apply,rect,allowed)
            end
        end
    end)
    self.refreshing=false
    if not ok then ns:Report("layout",err) end
    if ns.DisplayAnchors and ns.DisplayAnchors.RenderStacks then ns:Call("layout/stacks",function()ns.DisplayAnchors:RenderStacks(force==true or immediateStacks==true or self.draft~=nil)end)end
    self:UpdateCursorTracking()
    if ns.LayoutEditor and ns.LayoutEditor.active then ns.LayoutEditor:Refresh() end
    if ns.Performance.active then ns.Performance:Finish("layout_ms",perfStarted) end
end
function Layout:Notify() self:Refresh() end
function Layout:AfterSave(owner,callback) self.saveListeners[owner]=callback end
function Layout:Saved()
    for _,callback in pairs(self.saveListeners) do ns:Call("layout/save",callback) end
end
function Layout:Change(id, patch)
    assert(self.elements[id],"Unknown editable element")
    local nodes=M.Copy(self:Nodes()); local n=M.Normalize(nodes[id])
    for key,value in pairs(patch) do n[key]=value~=false and M.Copy(value) or nil end
    local limits=self.elements[id].limits or {}
    if patch.width then n.width=M.Number(n.width,720,limits.minWidth or 1,limits.maxWidth or 5000) end
    if patch.height then n.height=M.Number(n.height,22,limits.minHeight or 1,limits.maxHeight or 2000) end
    nodes[id]=M.Normalize(n)
    local validate=self.elements[id].validate
    if validate then local ok,why=validate(nodes[id],nodes); if not ok then return false,why end end
    local ok,why=M.Validate(nodes); if not ok then return false,why end
    if self.draft then self.draft=nodes; self.dirty=true else ns.Settings:Profile().layout.elements=nodes end
    self:Refresh(false,true); if not self.draft then self:Saved() end; return true
end
function Layout:Unlink(id,axis)
    local r=self:Resolve(); r=r[id]
    if axis=="position" then return self:Change(id,{link=false,screen="CENTER",x=r.x,y=r.y}) end
    return self:Change(id,{[axis.."Target"]=false,[axis]=r[axis]})
end
function Layout:Move(id,x,y)
    local n=self:Get(id)
    local rects=self:Resolve(); local rect=rects[id]
    x,y=M.ClampCenter(x,y,rect.width,rect.height,UIParent:GetWidth(),UIParent:GetHeight())
    if not n.link then return self:Change(id,{screen="CENTER",x=x,y=y}) end
    -- Correct the intended offset, not just the drawn edge position. This also
    -- lets dragging/numeric input recover an old offscreen anchor in one move.
    local r=self.constrained[id] or rect
    local a=M.Copy(n.link); local dx,dy=x-r.x,y-r.y
    if a.side=="CENTER" then a.offset=a.offset+dx; a.gap=a.gap+dy
    elseif a.side=="TOP" or a.side=="BOTTOM" then a.offset=a.offset+dx; a.gap=a.gap+dy*(a.side=="TOP" and 1 or -1)
    else a.offset=a.offset+dy; a.gap=a.gap+dx*(a.side=="RIGHT" and 1 or -1) end
    return self:Change(id,{link=a})
end
function Layout:Begin()
    assert(not self.draft,"Layout editing is already active")
    self:FreezeCursor(true)
    self.draft=M.Copy(self:Store()); self.dirty=false; self:Refresh(true)
end
function Layout:Finish(save)
    if not self.draft then return end
    if save then
        local rects=self:Resolve()
        for id,n in pairs(self.draft) do if rects[id] then n.fallback=M.Copy(rects[id]) end end
        ns.Settings:Profile().layout.elements=self.draft
    end
    self.draft=nil; self.dirty=false; self.applied={}; self:FreezeCursor(false); self:Refresh(true)
    if save then self:Saved() end
end
ns.Settings:BeforeProfileChange(Layout,function() Layout:StopCursor(); Layout.cursorFrozen=nil end)

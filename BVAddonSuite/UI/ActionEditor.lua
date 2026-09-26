local _,ns=...
local UI,M,A,G=ns.UI,ns.DesignSystem.Metrics,ns.Actions,ns.GraphModel
local function at(w,p,x,y) M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y);return w end
function UI:MacroActionEditor(owner,controller)
    local d=self:Dialog(nil,620,490,owner);local p=d.content
    d.title:SetText("Saved macro")
    at(self:Label(p,"Select a game macro, or create one. Save changes the game macro immediately.",12,"muted"),p,20,12)
    d.note=at(self:Label(p,"",12,"text"),p,20,334);M.Size(d.note,580,60)
    function d:Valid()
        local graph=controller:Graph();local node=graph and graph.draft.nodes[self.nodeID]
        return self.store==controller:Store() and self.graph==graph and not controller.inspectApplied and node and node.type=="macro_action"
            and node.config.name==self.originalName and node.config.scope==self.originalScope
    end
    function d:Load(index)
        local selected
        for _,m in ipairs(A.Macros(true)) do if m.index==index then selected=m end end
        self.snapshot=selected and G.Copy(selected) or nil
        self.name:ClearFocus()
        self.name:SetText(selected and selected.name or "")
        self.scope:SetValue(selected and selected.scope or "character");self.scopeValue=selected and selected.scope or "character"
        self.body:SetText(selected and selected.body or "")
        self.note:SetText(selected and "Editing "..selected.scope.." macro. Existing names are kept; use New to create another macro." or "New macro: choose a name and scope, then Create.")
        self.save:SetText(selected and "Save changes" or "Create macro")
        self.name:EnableMouse(not selected);self.name:SetAlpha(selected and .5 or 1)
        if selected then self.scope:Disable() else self.scope:Enable() end
    end
    function d:RefreshOptions(selected)
        local options={{value=0,label="New macro..."}}
        for _,m in ipairs(A.Macros(true)) do options[#options+1]={value=m.index,label=m.name.." ("..m.scope..")"} end
        self.macros:SetOptions(options);self.macros:SetValue(selected or 0)
    end
    d.macros=at(self:Dropdown(p,580,{},function(index) d:Load(index) end),p,20,42)
    at(self:Label(p,"Name",12,"muted"),p,20,85)
    d.name=at(self:Input(p,320,function()end),p,20,104);d.name:SetMaxLetters(16)
    d.scope=at(self:Dropdown(p,240,{{value="account",label="Account"},{value="character",label="Character"}},function(value) d.scopeValue=value end),p,360,104)
    d.body=at(self:TransferText(p,580,180,255),p,20,146)
    if d.body.input.SetCountInvisibleLetters then d.body.input:SetCountInvisibleLetters(true) end
    d.save=at(self:Button(p,"Save changes",150,function()
        if not d:Valid() then d.note:SetText("Graph selection changed; reopen this editor.");return end
        local snapshot=d.snapshot
        local saved,why=A.SaveMacro(snapshot,snapshot and snapshot.name or d.name:GetText(),snapshot and snapshot.scope or d.scopeValue,d.body.input:GetText())
        if not saved then d.note:SetText(why);return end
        d:RefreshOptions(saved.index);d:Load(saved.index);d.note:SetText("Saved to game macros. Use selected connects this macro to the node.")
    end,"primary"),p,20,400)
    d.use=at(self:Button(p,"Use selected",150,function()
        if not d:Valid() then d.note:SetText("Graph selection changed; reopen this editor.");return end
        local m=d.snapshot;local current=m and A.FindMacro(m.name,m.scope,true)
        if not current then d.note:SetText("Select or save a unique game macro first.");return end
        if not A.Same(m,current) then d.note:SetText("Macro changed externally; reload before selecting.");return end
        if d.body.input:GetText()~=m.body then d.note:SetText("Save or reload the edited text before selecting.");return end
        controller:Edit(function(graph)
            local c=graph.nodes[d.nodeID].config;c.name=current.name;c.scope=current.scope
        end)
        d:Hide()
    end),p,180,400)
    d.reload=at(self:Button(p,"Reload",100,function()
        local m=d.snapshot;local current=m and A.FindMacro(m.name,m.scope,true)
        d:RefreshOptions(current and current.index);d:Load(current and current.index or 0)
    end),p,340,400)
    at(self:Button(p,"Close",100,function() d:Hide() end,"ghost"),p,500,400)
    d:HookScript("OnHide",function() d.snapshot=nil;d.body.input:ClearFocus();d.name:ClearFocus();if not next(ns.SecureActionMedia.macros) then A.macroCache=nil end end)
    function d:Open(id)
        self.store=controller:Store();self.graph=controller:Graph();self.nodeID=id
        local c=self.graph.draft.nodes[id].config;self.originalName=c.name;self.originalScope=c.scope
        local selected=A.FindMacro(c.name,c.scope,true)
        self:RefreshOptions(selected and selected.index);self:Load(selected and selected.index or 0)
        self:FitContent(620,490);self:Show()
    end
    return d
end

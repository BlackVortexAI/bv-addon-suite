local _,G=...
if not G.ready then return end
-- Import and export dialogs: GatherMate2 with a preview before anything is
-- written, the text exchange (export to copy, import with a count first),
-- forgetting the nodes only others shared, and routes as text (editor).
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local X={}
G.Exchange=X

function X:Dialog()
    if self.dialog then return self.dialog end
    UI:WithStyle(G:Style(),function()
        local d=UI:Dialog("BVGatherExchange",480,380)
        d.text=UI:TransferText(d.content,450,220,400000)
        M.Point(d.text,"TOPLEFT",d.content,"TOPLEFT",16,-12)
        d.note=UI:Label(d.content,"",11,"muted");M.Point(d.note,"TOPLEFT",d.content,"TOPLEFT",16,-240);M.Size(d.note,440,48);d.note:SetWordWrap(true)
        d.ok=UI:Button(d.content,"OK",120,function() X:Confirm() end,true);M.Point(d.ok,"BOTTOMRIGHT",d.content,"BOTTOMRIGHT",-16,12)
        d.cancel=UI:Button(d.content,"Cancel",100,function() d:Hide() end);M.Point(d.cancel,"RIGHT",d.ok,"LEFT",-8,0)
        d:Hide()
        self.dialog=d
    end)
    return self.dialog
end
function X:Open(mode,summary,text)
    local d=self:Dialog()
    d.mode=mode
    d.text:SetShown(mode=="export" or mode=="import" or mode=="routeExport" or mode=="routeImport" or mode=="areasExport" or mode=="areasImport")
    if mode=="export" then
        local text,count=G.Import:Export()
        d.title:SetText("Export nodes");d.text:SetText(text)
        d.note:SetText(count.." nodes. Select all with Ctrl+A and copy with Ctrl+C; the other side imports it under Gather.")
        d.ok:SetText("Close");d.cancel:Hide()
    elseif mode=="import" then
        d.title:SetText("Import nodes");d.text:SetText("")
        d.note:SetText("Paste a node export (it starts with BVGATHER1). The next step shows what is new before anything is added.")
        d.ok:SetText("Check");d.cancel:Show()
    elseif mode=="importConfirm" or mode=="gathermate" then
        d.title:SetText(mode=="gathermate" and "Import from GatherMate2" or "Import nodes")
        d.note:SetText(G.Import.Describe(summary).."\nAdd them? Nodes you already know are counted, not doubled.")
        d.ok:SetText("Import");d.cancel:Show()
    elseif mode=="routeExport" then
        d.title:SetText("Export route");d.text:SetText(text or "")
        d.note:SetText("Select all with Ctrl+A and copy with Ctrl+C; the other side imports it in the route editor.")
        d.ok:SetText("Close");d.cancel:Hide()
    elseif mode=="areasExport" then
        d.title:SetText("Export areas and transitions");d.text:SetText(text or "")
        d.note:SetText("Painted areas and transitions of the editor's zones. Select all with Ctrl+A and copy with Ctrl+C.")
        d.ok:SetText("Close");d.cancel:Hide()
    elseif mode=="areasImport" then
        d.title:SetText("Import areas and transitions");d.text:SetText("")
        d.note:SetText("Paste an export (it starts with BVAREAS1). The next step shows what is new.")
        d.ok:SetText("Check");d.cancel:Show()
    elseif mode=="areasConfirm" then
        d.title:SetText("Import areas and transitions")
        d.note:SetText(string.format("%d areas and %d transitions, %d of them new. Add the new ones?",summary.areas,summary.links,summary.new))
        d.ok:SetText("Import");d.cancel:Show()
    elseif mode=="routeImport" then
        d.title:SetText("Import route");d.text:SetText("")
        d.note:SetText("Paste a route export (it starts with BVROUTE1). It is saved under its name and opens in the editor.")
        d.ok:SetText("Import");d.cancel:Show()
    end
    d:Show()
    if mode=="import" or mode=="routeImport" then d.text.input:SetFocus() end
end
function X:Confirm()
    local d=self.dialog
    if d.mode=="export" or d.mode=="routeExport" or d.mode=="areasExport" then d:Hide()
    elseif d.mode=="areasImport" then
        local summary=G.Plan:ImportAreas(d.text.input:GetText(),false)
        if not summary then G:Print("That is no areas export (it starts with BVAREAS1).");return end
        self.pendingText=d.text.input:GetText()
        self:Open("areasConfirm",summary)
        return
    elseif d.mode=="areasConfirm" then
        local summary=G.Plan:ImportAreas(self.pendingText,true)
        self.pendingText=nil;d:Hide()
        G:Print(summary.new.." areas and transitions added.")
        if G.Editor.window and G.Editor.window:IsShown() then G.Editor:Stale();G.Editor:Layout() end
        return
    elseif d.mode=="routeImport" then
        local name,route=G.Plan:Import(d.text.input:GetText())
        if not name then G:Print("That is no route export (it starts with BVROUTE1).");return end
        d:Hide()
        G.Editor:Imported(name,route)
        return
    elseif d.mode=="import" then
        local summary=G.Import:Text(d.text.input:GetText(),false)
        if not summary then G:Print("That is no node export (it starts with BVGATHER1).");return end
        self.pendingText=d.text.input:GetText()
        self:Open("importConfirm",summary)
    elseif d.mode=="importConfirm" then
        local summary=G.Import:Text(self.pendingText,true)
        self.pendingText=nil;d:Hide()
        local merged=G.Data:Cleanup()
        G:Print("Imported: "..G.Import.Describe(summary)..(merged>0 and (", "..merged.." duplicates merged") or "")..".");G:Changed()
    elseif d.mode=="gathermate" then
        local summary=G.Import:GatherMate(true)
        d:Hide()
        local merged=G.Data:Cleanup()
        if summary then G:Print("Imported from GatherMate2: "..G.Import.Describe(summary)..(merged>0 and (", "..merged.." duplicates merged") or "")..".") end
        G:Changed()
    end
    if ns.Config then ns.Config:Refresh() end
end
function X:GatherMate()
    local summary=G.Import:GatherMate(false)
    if not summary then G:Print("No GatherMate2 data found. It is read while GatherMate2 is loaded.");return end
    self:Open("gathermate",summary)
end
function X:ForgetShared()
    -- Shared live and text imports: their sources go.
    local removed=G.Data:SourceCount("shared")+G.Data:SourceCount("text")
    G.Data:ForgetSource("shared");G.Data:ForgetSource("text")
    G:Print(removed.." shared node"..(removed==1 and "" or "s").." forgotten.")
    G:Changed()
    if ns.Config then ns.Config:Refresh() end
end

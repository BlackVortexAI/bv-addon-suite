-- Bounded, reusable clipboard report surface; callers provide sanitized text.
local _,ns=...
local UI,M=ns.UI,ns.DesignSystem.Metrics
local PAGE_BYTES,MAX_BYTES=60000,1200000
local function at(w,p,x,y) M.Point(w,"TOPLEFT",p,"TOPLEFT",x,-y); return w end
function UI:DiagnosticReport(title,text)
    assert(not ns.GraphValues.IsSecret(title) and type(title)=="string","Plain report title required")
    assert(not ns.GraphValues.IsSecret(text) and type(text)=="string","Sanitized report text required")
    local dialog=self.diagnosticReport
    if not dialog then
        dialog=self:Dialog("BVAddonSuiteDiagnosticReport",620,520); self.diagnosticReport=dialog
        local p=dialog.content
        dialog.hint=at(self:Label(p,"Snapshot text. Select a page, then Ctrl+C to copy.",12,"muted"),p,20,12); M.Size(dialog.hint,580,36)
        dialog.text=at(self:TransferText(p,580,314,PAGE_BYTES,function()
            if not dialog.loading then dialog:ShowPage(dialog.page) end
        end),p,20,52)
        dialog.pageLabel=at(self:Label(p,"",11,"muted"),p,20,380); M.Size(dialog.pageLabel,580,32)
        dialog.previous=at(self:Button(p,"Previous",102,function() dialog:ShowPage(dialog.page-1) end),p,20,420)
        dialog.next=at(self:Button(p,"Next",86,function() dialog:ShowPage(dialog.page+1) end),p,130,420)
        dialog.select=at(self:Button(p,"Select page",128,function() dialog.text.input:SetFocus(); dialog.text.input:HighlightText() end),p,224,420)
        dialog.close=at(self:Button(p,"Close",100,function() dialog:Hide() end,"ghost"),p,500,420)
        function dialog:ShowPage(page)
            if not self.pages or #self.pages==0 then return end
            self.page=math.max(1,math.min(#self.pages,page)); self.loading=true
            self.text:SetText(self.pages[self.page]); self.loading=false
            self.pageLabel:SetText("Page "..self.page.." / "..#self.pages.." — "..self.byteCount.." bytes"..(self.truncated and " — truncated at "..MAX_BYTES.." bytes" or ""))
            if self.page>1 then self.previous:Enable() else self.previous:Disable() end
            if self.page<#self.pages then self.next:Enable() else self.next:Disable() end
        end
        dialog:HookScript("OnHide",function()
            dialog.text.input:ClearFocus(); dialog.pages=nil; dialog.page=nil; dialog.loading=true; dialog.text:SetText(""); dialog.loading=false
        end)
    end
    dialog.pages={};dialog.byteCount=#text;dialog.truncated=#text>MAX_BYTES
    local first,limit=1,math.min(#text,MAX_BYTES)
    while first<=limit do
        local last=math.min(first+PAGE_BYTES-1,limit)
        -- Do not split a UTF-8 codepoint at a page or truncation boundary.
        while last>=first and text:byte(last+1) and text:byte(last+1)>=128 and text:byte(last+1)<192 do last=last-1 end
        if last<first then break end
        dialog.pages[#dialog.pages+1]=text:sub(first,last);first=last+1
    end
    if #dialog.pages==0 then dialog.pages[1]="" end
    dialog.title:SetText(title:sub(1,120));dialog:FitContent(620,520);dialog:Show();dialog:ShowPage(1)
    UI:FocusWindow(dialog);return dialog
end

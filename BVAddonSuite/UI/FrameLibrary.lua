-- Shared frame-reference management. No native frame is modified by this dialog.
local _,ns=...
local UI,D,X=ns.UI,ns.DesignSystem.Metrics,ns.ExternalFrames
local B={};UI.frameLibrary=B
local function at(w,p,x,y)return UI:Place(w,p,x,y)end
local function safe(value)return type(value)=="string"and not ns.GraphValues.IsSecret(value)and value:gsub("|","||")or ""end
function B:Message(value)self.status:SetText(safe(value))end
function B:Preview(reference)
 self.highlight:Hide();if not reference then return end
 local sample=X:Probe(reference);local r=sample and sample.rect
 if sample.state=="ready"and r then
  self.highlight:ClearAllPoints();self.highlight:SetPoint("CENTER",UIParent,"CENTER",r.x,r.y)
  self.highlight:SetSize(r.width,r.height);self.highlight:Show()
 end
end
function B:Select(reference)
 local entry=ns.FrameLibrary:Lookup(reference);if not entry then return end
 self.selected=reference;self.reference:SetText(reference);self.label:SetText(entry.label);self:Refresh()
end
function B:Refresh()
 if not self.window then return end
 local items=ns.FrameLibrary:List();local pages=math.max(1,math.ceil(#items/6));self.page=math.max(1,math.min(self.page or 1,pages))
 for index,row in ipairs(self.rows)do
  local entry=items[(self.page-1)*6+index];row.reference=entry and entry.reference
  row:SetShown(entry~=nil)
  if entry then UI:FitCaption(row.title,(entry.reference==self.selected and "• "or "")..entry.label,D.ToNative(660));UI:FitCaption(row.caption,entry.reference,D.ToNative(660))
   UI:AttachTooltip(row,entry.label,entry.reference.."\n"..(entry.objectType or "Frame"))end
 end
 self.pages:SetText(self.page.." / "..pages.." · "..#items.." saved")
 if self.page>1 then self.previous:Enable()else self.previous:Disable()end
 if self.page<pages then self.next:Enable()else self.next:Disable()end
 local selected=self.selected and ns.FrameLibrary:Lookup(self.selected)
 for _,button in ipairs({self.rename,self.remove})do if selected then button:Enable()else button:Disable()end end
 self.use:SetShown(self.options and self.options.choose~=nil)
 if selected then self.use:Enable()else self.use:Disable()end
end
function B:Save()
 local reference=self.reference:GetText();local label=self.label:GetText()
 if not ns.FrameLibrary:ValidateReference(reference)then self:Message("Enter a global frame name or stable dotted field path.");return end
 local sample=X:Probe(reference)
 if sample.state~="ready"and sample.state~="hidden"then self:Message("Reference is "..safe(sample.state)..". Inspect an accessible frame before saving.");return end
 local entry,why=ns.FrameLibrary:Save(reference,label~=""and label or reference,sample.objectType)
 if not entry then self:Message(why);return end
 self.selected=entry.reference;self:Refresh();self:Message("Saved to the shared Frame library.")
end
function B:Build()
 if self.window then return end
 local w=UI:Dialog("BVAddonSuiteFrameLibrary",720,650);self.window=w;w.title:SetText("Frame library");X:MarkOwned(w)
 local p=w.content
 at(UI:Label(p,"Frame reference",11,"muted"),p,18,0)
 self.reference=at(UI:Input(p,510),p,18,18);self.reference:SetMaxLetters(256)
 UI:AttachTooltip(self.reference,"Frame reference","Global name or stable dotted field path. Save checks its current accessibility.")
 self.save=at(UI:Button(p,"Save reference",152,function()self:Save()end,true),p,550,18)
 at(UI:Label(p,"Display name",11,"muted"),p,18,48)
 self.label=at(UI:Input(p,510),p,18,66);self.label:SetMaxLetters(96)
 UI:AttachTooltip(self.label,"Display name","Shared descriptive name, at most 96 bytes. Renaming does not change a reference.")
 self.rename=at(UI:Button(p,"Rename",152,function()
  local ok,why=ns.FrameLibrary:Rename(self.selected,self.label:GetText());self:Message(ok and "Display name updated."or why);self:Refresh()
 end),p,550,66)
 self.rows={}
 for index=1,6 do
  local row=at(UI:Button(p,"",684,function(control)if control.reference then self:Select(control.reference)end end),p,18,120+(index-1)*54)
  D.Height(row,48)
  row.title=at(UI:Label(row,"",13,"text"),row,12,5);D.Size(row.title,660,20)
  row.caption=at(UI:Label(row,"",10,"muted"),row,12,28);D.Size(row.caption,660,16)
  row:HookScript("OnEnter",function()self:Preview(row.reference)end);row:HookScript("OnLeave",function()self:Preview()end)
  self.rows[index]=row
 end
 self.previous=at(UI:Button(p,"Previous",100,function()self.page=self.page-1;self:Refresh()end),p,18,452)
 self.pages=at(UI:Label(p,"",12,"text"),p,136,460);D.Size(self.pages,240,22)
 self.next=at(UI:Button(p,"Next",100,function()self.page=self.page+1;self:Refresh()end),p,398,452)
 self.remove=at(UI:Button(p,"Remove",152,function()
  local ok,why=ns.FrameLibrary:Remove(self.selected);if ok then self.selected=nil;self:Message("Reference removed.")else self:Message(why)end;self:Refresh()
 end),p,550,452)
 self.status=at(UI:Label(p,"Inspect game frames or save an accessible reference. Hover saved rows to preview them.",12,"muted"),p,18,502);D.Size(self.status,684,42)
 self.inspect=at(UI:Button(p,"Inspect frames",160,function()UI.frameInspector:Start()end),p,18,556)
 self.close=at(UI:Button(p,"Close",100,function()w:Hide()end),p,196,556)
 self.use=at(UI:Button(p,"Use selected",152,function()
  local entry=self.selected and ns.FrameLibrary:Lookup(self.selected);local options=self.options
  if entry and options and options.choose then w:Hide();options.choose(entry.reference)end
 end,true),p,550,556)
 self.highlight=UI:Panel(UIParent,1,1,"accent");self.highlight:SetAlpha(.20);self.highlight:SetFrameStrata("DIALOG");self.highlight:EnableMouse(false);self.highlight:Hide();X:MarkOwned(self.highlight)
 w:HookScript("OnHide",function()self:Preview();self.reference:ClearFocus();self.label:ClearFocus()end)
end
function UI:OpenFrameLibrary(options)
 B:Build();B.options=options;B.page=1;B:Refresh();B.window:FitContent(720,650);B.window:Show();return B
end
ns.Commands:RegisterAction("frames",function()UI:OpenFrameLibrary()end)
ns.Settings:BeforeProfileChange(B,function()if B.window then B.window:Hide();B.options=nil end end)

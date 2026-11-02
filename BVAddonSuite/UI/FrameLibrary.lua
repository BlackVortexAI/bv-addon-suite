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
 -- Keep pagination stable, but do not reserve six rows for an empty library.
 local slots=math.max(1,math.min(6,#items));local y=128+slots*54
 self.empty:SetShown(#items==0)
 at(self.previous,self.window.content,18,y);at(self.pages,self.window.content,136,y+8)
 at(self.next,self.window.content,398,y);at(self.remove,self.window.content,550,y)
 at(self.status,self.window.content,18,y+50)
 at(self.inspect,self.window.content,18,y+104);at(self.close,self.window.content,196,y+104);at(self.use,self.window.content,550,y+104)
 self.window:FitContent(720,y+198)
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
 local style=UI:InterfaceStyle();if not style then return end
 local function make(method,...)
  local args,n={...},select('#',...)
  return UI:WithStyle(style,function()return UI[method](UI,unpack(args,1,n))end)
 end
 self.style=style
 local w=make("Dialog","BVAddonSuiteFrameLibrary",720,650,nil,{escapeScope=style.materialProfile=="interface"});self.window=w;w.title:SetText("Frame library");X:MarkOwned(w)
 local p=w.content
 at(make("Label",p,"Frame reference",11,"muted"),p,18,0)
 self.reference=at(make("Input",p,510),p,18,18);self.reference:SetMaxLetters(256)
 UI:AttachTooltip(self.reference,"Frame reference","Global name or stable dotted field path. Save checks its current accessibility.")
 self.save=at(make("Button",p,"Save reference",152,function()self:Save()end,true),p,550,18)
 at(make("Label",p,"Display name",11,"muted"),p,18,48)
 self.label=at(make("Input",p,510),p,18,66);self.label:SetMaxLetters(96)
 UI:AttachTooltip(self.label,"Display name","Shared descriptive name, at most 96 bytes. Renaming does not change a reference.")
 self.rename=at(make("Button",p,"Rename",152,function()
  local ok,why=ns.FrameLibrary:Rename(self.selected,self.label:GetText());self:Message(ok and "Display name updated."or why);self:Refresh()
 end),p,550,66)
 self.rows={}
 self.empty=at(make("Label",p,"No saved frame references. Use Inspect frames or enter a reference above.",12,"muted"),p,18,130);D.Size(self.empty,684,40)
 for index=1,6 do
  local row=at(make("Button",p,"",684,function(control)if control.reference then self:Select(control.reference)end end),p,18,120+(index-1)*54)
  D.Height(row,48)
  row.title=at(make("Label",row,"",13,"text"),row,12,5);D.Size(row.title,660,20)
  row.caption=at(make("Label",row,"",10,"muted"),row,12,28);D.Size(row.caption,660,16)
  row:HookScript("OnEnter",function()self:Preview(row.reference)end);row:HookScript("OnLeave",function()self:Preview()end)
  self.rows[index]=row
 end
 self.previous=at(make("Button",p,"Previous",100,function()self.page=self.page-1;self:Refresh()end),p,18,452)
 self.pages=at(make("Label",p,"",12,"text"),p,136,460);D.Size(self.pages,240,22)
 self.next=at(make("Button",p,"Next",100,function()self.page=self.page+1;self:Refresh()end),p,398,452)
 self.remove=at(make("Button",p,"Remove",152,function()
  local ok,why=ns.FrameLibrary:Remove(self.selected);if ok then self.selected=nil;self:Message("Reference removed.")else self:Message(why)end;self:Refresh()
 end),p,550,452)
 self.status=at(make("Label",p,"Inspect game frames or save an accessible reference. Hover saved rows to preview them.",12,"muted"),p,18,502);D.Size(self.status,684,42)
 self.inspect=at(make("Button",p,"Inspect frames",160,function()UI.frameInspector:Start()end),p,18,556)
 self.close=at(make("Button",p,"Close",100,function()w:Hide()end),p,196,556)
 self.use=at(make("Button",p,"Use selected",152,function()
  local entry=self.selected and ns.FrameLibrary:Lookup(self.selected);local options=self.options
  if entry and options and options.choose then w:Hide();options.choose(entry.reference)end
 end,true),p,550,556)
 if style.materialProfile=="interface" then
  -- A world-space selection marker is a flat tint, not a decorated panel.
  -- Keep opacity on its owner so material repaint cannot make it opaque.
  self.highlight=CreateFrame("Frame",nil,UIParent);D.Size(self.highlight,1,1)
  local tint=self.highlight:CreateTexture(nil,"BACKGROUND");tint:SetAllPoints()
  style:Bind(function()tint:SetColorTexture(style:Color("accent"))end,self.highlight)
 else self.highlight=make("Panel",UIParent,1,1,"accent")end
 self.highlight:SetAlpha(.20);self.highlight:SetFrameStrata("DIALOG");self.highlight:EnableMouse(false);self.highlight:Hide();X:MarkOwned(self.highlight)
 if w.TrackEscapeInput then w:TrackEscapeInput(self.reference);w:TrackEscapeInput(self.label)end
 w:HookScript("OnHide",function()self:Preview();self.reference:ClearFocus();self.label:ClearFocus()end)
end
function UI:OpenFrameLibrary(options)
 B:Build();if not B.window then return end;B.options=options;B.page=1;B:Refresh();B.window:Show();return B
end
ns.Commands:RegisterAction("frames",function()UI:OpenFrameLibrary()end)
ns.Settings:BeforeProfileChange(B,function()if B.window then B.window:Hide();B.options=nil end end)

-- Live inspection uses owned UI only. Candidate discovery and safe frame reads live in Core.
local _,ns=...
local UI,D,X,V=ns.UI,ns.DesignSystem.Metrics,ns.ExternalFrames,ns.GraphValues
local I={};UI.frameInspector=I
local function at(w,p,x,y)return UI:Place(w,p,x,y)end
local function text(value,fallback)return type(value)=="string"and not V.IsSecret(value)and value:gsub("|","||")or fallback or "Unavailable"end
local function shortLabel(value)
 value=text(value,"Frame"):gsub("[%c|]","")
 local length=math.min(96,#value)
 if length<#value then while length>0 and value:byte(length+1)>=128 and value:byte(length+1)<192 do length=length-1 end end
 return value:sub(1,length)
end
function I:Highlight(sample)
 self.highlight:Hide()
 local r=sample and sample.rect
 if sample and sample.state=="ready"and r then
  self.highlight:ClearAllPoints();self.highlight:SetPoint("CENTER",UIParent,"CENTER",r.x,r.y)
  self.highlight:SetSize(r.width,r.height);self.highlight:Show()
 end
end
function I:Describe(frame)
 local ok,sample=pcall(X.Describe,X,frame)
 return ok and type(sample)=="table"and sample or {state="restricted",label="Unavailable frame"}
end
function I:PositionInfo()
 local ok,x,y=pcall(GetCursorPosition);local scale=UIParent:GetEffectiveScale()
 if not ok or V.IsSecret(x)or V.IsSecret(y)or type(x)~="number"or type(y)~="number"then return end
 local w,h=self.info:GetWidth(),self.info:GetHeight();local sw,sh=UIParent:GetWidth(),UIParent:GetHeight()
 x,y=x/scale,y/scale;local left=x+18;if left+w>sw-8 then left=x-w-18 end
 left=math.max(8,math.min(left,sw-w-8));local bottom=math.max(8,math.min(y-h+18,sh-h-8))
 self.info:ClearAllPoints();self.info:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",left,bottom)
 self.infoBounds={left=left,bottom=bottom,width=w,height=h}
end
function I:Tick()
 if not self.active or self.frozen then return end
 local ok,rows,source=pcall(X.Candidates,X);self.candidates=ok and type(rows)=="table"and rows or {};self.source=source
 local sample=self.candidates[1];self:Highlight(sample)
 UI:FitCaption(self.infoTitle,sample and text(sample.label or sample.name,"Unnamed frame")or "No accessible frame",D.ToNative(336))
 self.infoText:SetText(sample and (text(sample.objectType,"Frame").." · "..text(sample.state).."\nParent: "..text(sample.parentName,"Unknown").."\n"..(sample.persistable and text(sample.reference)or "No stable reference — cannot save"))or "Move over a game window. BV windows are excluded.")
 self.count:SetText(source=="focus_only"and "Limited mouse-focus fallback · Ctrl+Shift+F"or source=="unavailable"and "Frame enumeration unavailable"or #self.candidates.." candidates · Ctrl+Shift+F to capture")
 self:PositionInfo()
end
function I:Live(message)
 self.frozen=nil;self.selection={};self.page=1;self.popup:Hide();self.info:Show()
 self.helpText:SetText(message or "Frame inspector · Move to inspect · Ctrl+Shift+F capture · Esc exit")
 self:Tick()
end
function I:RefreshCapture()
 local rows=self.frozen or {};local pages=math.max(1,math.ceil(#rows/6));self.page=math.max(1,math.min(self.page or 1,pages))
 for index,row in ipairs(self.rows)do
  local candidate=rows[(self.page-1)*6+index];row.candidate=candidate;row.index=(self.page-1)*6+index;row:Hide()
  if candidate then
   UI:FitCaption(row.title,text(candidate.label or candidate.name,"Unnamed frame"),D.ToNative(550))
   row.detail:SetText(text(candidate.objectType,"Frame").." · "..text(candidate.state).." · Parent: "..text(candidate.parentName,"Unknown"))
   row.reference:SetText(candidate.persistable and text(candidate.reference)or "No stable reference — cannot save")
   UI:AttachTooltip(row,text(candidate.label or candidate.name,"Unnamed frame"),text(candidate.reference,"No stable reference").."\nParent: "..text(candidate.parentName,"Unknown"))
   row.toggle:SetValue(self.selection[row.index]==true)
   if candidate.persistable then row.toggle:Enable()else row.toggle:Disable()end
   row:Show()
  end
 end
 self.pages:SetText(self.page.." / "..pages)
 if self.page>1 then self.previous:Enable()else self.previous:Disable()end
 if self.page<pages then self.next:Enable()else self.next:Disable()end
 local count=0;for index in pairs(self.selection)do if rows[index]and rows[index].persistable then count=count+1 end end
 self.save:SetLabelText("Save selected ("..count..")");if count>0 then self.save:Enable()else self.save:Disable()end
end
function I:Capture()
 if not self.active or self.frozen then return end
 self:Tick();self.frozen=self.candidates;self.selection={};self.page=1
 self.info:Hide();self:Highlight(nil);self.captureStatus:SetText("Select stable references to save. Hover a row to highlight its original frame.")
 self:RefreshCapture();self.popup:FitContent(660,640);self.popup:Show()
 self.helpText:SetText("Frame inspector · Captured list frozen · Esc returns to live inspection")
end
function I:SaveSelected()
 if not self.active or not self.frozen then return end
 local saved,failed=0,0;local reason
 for index,candidate in ipairs(self.frozen)do if self.selection[index]and candidate.persistable then
  local now=self:Describe(candidate.frame)
  if not now.persistable or now.reference~=candidate.reference then failed=failed+1;reason="A captured frame changed; capture it again."
  else
   local entry,why=ns.FrameLibrary:Save(candidate.reference,shortLabel(candidate.label or candidate.name),candidate.objectType)
   if entry then saved=saved+1;self.selection[index]=nil else failed=failed+1;reason=why end
  end
 end end
 if failed>0 then self.captureStatus:SetText(saved.." saved. "..text(reason,"Some references could not be saved."));self:RefreshCapture()
 else self:Live(saved.." saved to Frame library · Ctrl+Shift+F capture again · Esc exit")end
end
function I:Key(key)
 if V.IsSecret(key)or not self.active or InCombatLockdown()then return false end
 if key=="ESCAPE"then if self.frozen then self:Live()else self:Stop(true)end;return true end
 if key=="F"and IsControlKeyDown()and IsShiftKeyDown()then self:Capture();return true end
 return false
end
function I:Build()
 if self.host then return end
 self.host=CreateFrame("Frame","BVAddonSuiteFrameInspection",UIParent);self.host:SetAllPoints(UIParent);self.host:SetFrameStrata("FULLSCREEN_DIALOG");self.host:SetFrameLevel(100);self.host:EnableMouse(false);X:MarkOwned(self.host);self.host:Hide()
 self.host:SetScript("OnKeyDown",function(_,key)UI:SetKeyboardPropagation(self.host,not self:Key(key))end)
 self.host:SetScript("OnKeyUp",function()if not InCombatLockdown()then UI:SetKeyboardPropagation(self.host,true)end end)
 self.help=UI:Panel(self.host,800,42,"surface");D.Point(self.help,"TOP",UIParent,"TOP",0,-24);self.help:EnableMouse(false)
 self.helpText=at(UI:Label(self.help,"",13,"text"),self.help,16,12);D.Size(self.helpText,768,24)
 self.info=UI:Panel(self.host,360,136,"surface");self.info:EnableMouse(false);self.info:SetFrameLevel(110);self.help:SetFrameLevel(110)
 self.infoTitle=at(UI:Label(self.info,"",14,"accent",true),self.info,12,10);D.Size(self.infoTitle,336,20)
 self.infoText=at(UI:Label(self.info,"",11,"text"),self.info,12,38);D.Size(self.infoText,336,66)
 self.count=at(UI:Label(self.info,"",10,"muted"),self.info,12,112);D.Size(self.count,336,18)
 self.highlight=UI:Panel(self.host,1,1,"accent");self.highlight:EnableMouse(false);self.highlight:SetAlpha(.20);self.highlight:SetFrameLevel(101);self.highlight:Hide();X:MarkOwned(self.highlight)
 local w=UI:Dialog("BVAddonSuiteFrameCapture",660,640,self.host);self.popup=w;X:MarkOwned(w);w.title:SetText("Captured frames")
 local p=w.content;self.captureStatus=at(UI:Label(p,"",12,"muted"),p,18,10);D.Size(self.captureStatus,624,42)
 self.rows={}
 for index=1,6 do
  local row=UI:Button(p,"",624,function(control)
   if control.candidate and control.candidate.persistable then self.selection[control.index]=not self.selection[control.index]and true or nil;self:RefreshCapture()end
  end);D.Height(row,66);at(row,p,18,62+(index-1)*68)
  row.toggle=at(UI:Switch(row,false,function(value)self.selection[row.index]=value and true or nil;self:RefreshCapture()end),row,10,21)
  row.title=at(UI:Label(row,"",13,"text",true),row,58,5);D.Size(row.title,550,19)
  row.detail=at(UI:Label(row,"",10,"muted"),row,58,25);D.Size(row.detail,550,16)
  row.reference=at(UI:Label(row,"",10,"muted"),row,58,44);D.Size(row.reference,550,16)
  row:HookScript("OnEnter",function()if row.candidate then self:Highlight(self:Describe(row.candidate.frame))end end)
  row:HookScript("OnLeave",function()self:Highlight(nil)end)
  row.toggle:HookScript("OnEnter",function()if row.candidate then self:Highlight(self:Describe(row.candidate.frame))end end)
  row.toggle:HookScript("OnLeave",function()self:Highlight(nil)end);self.rows[index]=row
 end
 self.previous=at(UI:Button(p,"Previous",100,function()self.page=self.page-1;self:RefreshCapture()end),p,18,478)
 self.pages=at(UI:Label(p,"",12,"text"),p,138,486)
 self.next=at(UI:Button(p,"Next",100,function()self.page=self.page+1;self:RefreshCapture()end),p,190,478)
 self.save=at(UI:Button(p,"Save selected",170,function()self:SaveSelected()end,true),p,472,478)
 self.resume=at(UI:Button(p,"Continue inspecting",180,function()self:Live()end),p,18,524)
 self.exit=at(UI:Button(p,"Exit inspector",140,function()self:Stop(true)end),p,502,524)
 w:HookScript("OnHide",function()self:Highlight(nil);if self.active and self.frozen and not self.closing then self:Live()end end)
end
function I:HideEditors()
 self.restore={};local state=self.restore
 state.windows=UI:VisibleWindows()
 local E=ns.LayoutEditor
 if E.active and not E.suspended then state.layout=E;E:SetInspectionHidden(true)end
 if ns.Config.window and ns.Config.window:IsShown()then state.config=true;X:MarkOwned(ns.Config.window);ns.Config.window:Hide()end
 local studio=ns.AuraStudio and ns.AuraStudio.editor
 if studio and studio.window:IsShown()then
  state.studio={editor=studio,selected=ns.LayoutModel.Copy(studio.selected),detail=studio.details and studio.details:IsShown()and studio.detailMode,focus=studio.focusNode}
  X:MarkOwned(studio.window);studio.window:Hide()
 end
 local library=UI.frameLibrary
 if library and library.window and library.window:IsShown()then state.library=true;library.window:Hide()end
 for index=#state.windows,1,-1 do state.windows[index]:Hide()end
 UI:CloseDropdown();UI:HideTooltip();if UI.colorPopup then UI.colorPopup:Hide()end
end
function I:Start()
 if InCombatLockdown()then ns:Print("Start frame inspection outside combat.");return end
 if self.active then return end
 self:Build();self.profile=ns.Settings:Profile();self:HideEditors();self.active=true;self.host:Show();self.host:EnableKeyboard(true);UI:SetKeyboardPropagation(self.host,true)
 self.generation=(self.generation or 0)+1;local generation=self.generation
 self:Live();self.timer=C_Timer.NewTicker(.1,function()if self.active and self.generation==generation then self:Tick()end end)
 ns.Events:Subscribe(self,"PLAYER_REGEN_DISABLED",function()self:Stop(false)end)
 ns.Events:Subscribe(self,"PLAYER_LOGOUT",function()self:Stop(false)end)
end
function I:Open()self:Start()end
function I:Stop(restore)
 if not self.active then return end
 self.active=false;self.generation=(self.generation or 0)+1;self.closing=true;if self.timer then self.timer:Cancel();self.timer=nil end
 self.popup:Hide();self.host:Hide();self.highlight:Hide();self.closing=nil;self.frozen=nil;self.candidates={};ns.Events:Release(self)
 if not InCombatLockdown()then self.host:EnableKeyboard(false);UI:SetKeyboardPropagation(self.host,true)end
 local saved=self.restore;self.restore=nil
 local valid=restore and self.profile==ns.Settings:Profile()and not InCombatLockdown()
 if saved and saved.layout then saved.layout:SetInspectionHidden(false,not valid)end
 if valid and saved then
  if saved.config then ns.Config.window:Show()end
  if saved.studio then local e=saved.studio.editor;e:Open();e.selected=saved.studio.selected;e:Render();if saved.studio.detail=="node"then e:Details("node",saved.studio.focus)end end
  if saved.library and UI.frameLibrary then UI.frameLibrary:Refresh();UI.frameLibrary.window:Show()end
  for _,window in ipairs(saved.windows or {})do
   -- Dialog OnHide can invalidate tokens, confirmation targets and watchers.
   -- Rebuild known safe node details/library above; never resurrect stale modals.
   if not window.FitContent and window~=self.popup and window~=self.host and (not saved.layout or window~=saved.layout.root)
    and (not saved.studio or window~=saved.studio.editor.window)then window:Show()end
  end
 end
 self.profile=nil
end
ns.Commands:RegisterAction("inspect",function()I:Start()end)
ns.Settings:BeforeProfileChange(I,function()I:Stop(false)end)

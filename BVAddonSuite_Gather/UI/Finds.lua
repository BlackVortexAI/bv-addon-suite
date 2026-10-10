local _,G=...
if not G.ready then return end
-- Minimap finds (Florian 2026-10-10): the last 20 herbs and ores the scanner
-- saw on the minimap, newest first; names of your list in the accent colour.
-- Like the tracker's window; opened by itself or with the gather mode.
-- Distance and direction follow you (once a second); a click on a find
-- draws a purple line from you to it (Florian 2026-10-10).
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local W={rows={}}
G.Finds=W
local WIDTH,ROW=290,18

function W:Build()
    if self.window then return self.window end
    local rows=G.Scanner.RECENT
    local height=82+rows*ROW
    UI:WithStyle(G:Style(),function()
        local w=UI:Window("BVGatherFinds",WIDTH,height,{title="Minimap finds",minWidth=WIDTH,minHeight=height,compact=true})
        for i=#UISpecialFrames,1,-1 do if UISpecialFrames[i]=="BVGatherFinds" then table.remove(UISpecialFrames,i) end end
        w:SetResizable(false);if w.resizeGrip then w.resizeGrip:Hide() end;if w.maximize then w.maximize:Hide() end
        self.window=w
        local c=w.content
        self.status=UI:Label(c,"",11,"muted");M.Point(self.status,"TOPLEFT",c,"TOPLEFT",12,-8);M.Size(self.status,WIDTH-104,18);self.status:SetWordWrap(false)
        self.clear=UI:Button(c,"Clear",72,function() G.Scanner:Clear() end,"ghost");M.Point(self.clear,"TOPRIGHT",c,"TOPRIGHT",-12,-4)
        for i=1,rows do
            local row=CreateFrame("Button",nil,c);M.Size(row,WIDTH-24,ROW);M.Point(row,"TOPLEFT",c,"TOPLEFT",12,-36-(i-1)*ROW)
            row.mark=row:CreateTexture(nil,"BACKGROUND");row.mark:SetAllPoints(row);row.mark:SetColorTexture(.72,.42,1,.25);row.mark:Hide()
            row.hover=row:CreateTexture(nil,"BACKGROUND");row.hover:SetAllPoints(row);row.hover:SetColorTexture(1,1,1,.06);row.hover:Hide()
            row:SetScript("OnEnter",function(self) self.hover:Show() end)
            row:SetScript("OnLeave",function(self) self.hover:Hide() end)
            row:SetScript("OnClick",function(self) if self.find then G.Scanner:Target(self.find) end end)
            ns.UI:AttachTooltip(row,"Go there","Click: a purple line from you to this find on the minimap and the map. Click again to clear; it ends when you get there or gather it, when it is gone, or when you walk far away.")
            row.name=UI:Label(row,"",11,"text");M.Point(row.name,"LEFT",row,"LEFT",0,0);M.Size(row.name,WIDTH-130,ROW);row.name:SetWordWrap(false)
            row.info=UI:Label(row,"",11,"muted");M.Point(row.info,"RIGHT",row,"RIGHT",0,0);M.Size(row.info,104,ROW);row.info:SetJustifyH("RIGHT")
            self.rows[i]=row
        end
        self.empty=UI:Label(c,"",11,"muted");M.Point(self.empty,"TOPLEFT",c,"TOPLEFT",12,-38);M.Size(self.empty,WIDTH-24,60);self.empty:SetWordWrap(true)
        w.drag:HookScript("OnDragStop",function() UI:SaveWindowPosition(w) end)
        w:HookScript("OnShow",function() W:Refresh();W:Watch(true) end)
        w:HookScript("OnHide",function() W:Watch(false) end)
        -- Closed with its X it stays closed after a reload (like the tracker).
        if w.close then w.close:HookScript("OnClick",function() G:Config().findsWindow=false end) end
        if not UI:RestoreWindowPosition(w) then w:ClearAllPoints();w:SetPoint("RIGHT",UIParent,"RIGHT",-420,-200) end
        w:Hide()
    end)
    return self.window
end
function W:Show(on)
    local w=self:Build()
    if on==nil then on=not w:IsShown() end
    G:Config().findsWindow=on and true or false
    w:SetShown(on)
end
-- Distance, direction and "how long ago" tick once a second while open.
function W:Watch(on)
    if on and not self.ticker then self.ticker=C_Timer.NewTicker(1,function() W:Refresh() end)
    elseif not on and self.ticker then self.ticker:Cancel();self.ticker=nil end
end
local function ago(seconds)
    if seconds<60 then return "now" end
    if seconds<3600 then return math.floor(seconds/60).."m" end
    return math.floor(seconds/3600).."h"
end
local STATUS={off="Scanner off (Scanner tab or the HUD)",missing="This client cannot read the minimap",combat="Scanner paused: combat",
    mouse="Scanner paused: mouse not on the HUD's minimap",active="Scanner active"}
function W:Refresh()
    local w=self.window
    if not (w and w:IsShown()) then return end
    local S=G.Scanner
    local status=S.status
    if status~="off" and status~="missing" and not G.Hud:On() then self.status:SetText("Scanner waits for the HUD")
    else self.status:SetText(STATUS[status] or "") end
    local now=time()
    for i,row in ipairs(self.rows) do
        local find=S.recent[i]
        row:SetShown(find~=nil)
        row.find=find
        row.mark:SetShown(find~=nil and find.node~=nil and find.node==S.target)
        if find then
            row.name:SetText(find.name)
            if find.watched then row.name:SetTextColor(G:Style():Color("accent")) else row.name:SetTextColor(G:Style():Color("text")) end
            local yards,direction=S:Relative(find)
            row.info:SetText(string.format("%s  ·  %d yd %s",ago(now-find.time),yards,direction))
        end
    end
    self.empty:SetShown(#S.recent==0)
    self.empty:SetText("Herbs and ore the scanner sees on the HUD's minimap show here, newest first (Find Herbs or Find Minerals must be on).")
end
function W:Enable(context)
    if G:Config().findsWindow then self:Show(true) end
    context:Defer(function() if W.window then W.window:Hide() end;W:Watch(false) end)
end

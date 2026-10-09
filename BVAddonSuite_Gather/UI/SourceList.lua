local _,G=...
if not G.ready then return end
-- The data sources as a list of three columns (Florian 2026-10-09: greyed
-- switches and no row for your own finds were "very misleading"): a check
-- whether the source is used, its name, its number of nodes. Every source
-- can be switched, also an empty one and your own finds.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local L={}
G.SourceList=L
L.ROW=26
L.ROWS={
    {id="own",label="Own finds",help="Nodes you gathered yourself, where you stood."},
    {id="known",label="Gather Data (known spawns)",help="Known spawn points of BV Addon Suite - Gather Data (if installed), smaller and fainter until you find them."},
    {id="gathermate",label="GatherMate2 import",help="Nodes imported from GatherMate2."},
    {id="text",label="Text imports",help="Nodes from text someone shared with you (Import nodes)."},
    {id="import",label="Earlier imports",help="Nodes from imports of older versions."},
    {id="shared",label="Group and guild",help="Nodes your group and guild sent while you play."},
}
local function grouped(n)
    local text=tostring(n)
    while true do
        local changed
        text,changed=text:gsub("^(%d+)(%d%d%d)","%1,%2")
        if changed==0 then return text end
    end
end
function L:Build(parent,changed)
    local f=CreateFrame("Frame",nil,parent);f.rows={}
    f.headName=UI:Label(f,"Source",11,"muted");f.headCount=UI:Label(f,"Nodes",11,"muted");f.headCount:SetJustifyH("RIGHT")
    for i,def in ipairs(L.ROWS) do
        local row=CreateFrame("Frame",nil,f);row.def=def
        row.check=UI:GetStyle():Check(row,"",false,function(value)
            G.Data:SetSourceOn(def.id,value)
            if changed then changed() end
        end)
        row.name=UI:Label(row,def.label,12,"text")
        row.count=UI:Label(row,"",12,"muted");row.count:SetJustifyH("RIGHT")
        UI:AttachTooltip(row.check,def.label,def.help.." Off: kept, but not shown and not used for routes.")
        f.rows[i]=row
    end
    function f:Refresh()
        for _,row in ipairs(self.rows) do
            row.check:SetValue(G.Data:SourceOn(row.def.id) and true or false)
            row.count:SetText(grouped(G.Data:SourceCount(row.def.id)))
        end
    end
    function f:Resize(width)
        M.Width(self,width)
        local count=110
        M.Point(self.headName,"TOPLEFT",self,"TOPLEFT",40,-4);M.Size(self.headName,width-count-56,16)
        M.Point(self.headCount,"TOPRIGHT",self,"TOPRIGHT",-8,-4);M.Size(self.headCount,count,16)
        for i,row in ipairs(self.rows) do
            row:ClearAllPoints();M.Point(row,"TOPLEFT",self,"TOPLEFT",0,-i*L.ROW);M.Size(row,width,L.ROW)
            row.check:ClearAllPoints();M.Point(row.check,"LEFT",row,"LEFT",8,0);M.Size(row.check,24,L.ROW)
            row.name:ClearAllPoints();M.Point(row.name,"LEFT",row,"LEFT",40,0);M.Size(row.name,width-count-56,L.ROW)
            row.count:ClearAllPoints();M.Point(row.count,"RIGHT",row,"RIGHT",-8,0);M.Size(row.count,count,L.ROW)
        end
        local height=(#self.rows+1)*L.ROW
        M.Height(self,height)
        return height
    end
    f:Resize(600)
    return f
end

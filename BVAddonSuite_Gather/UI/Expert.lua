local _,G=...
if not G.ready then return end
-- Expert settings (Florian 2026-10-09): the fixed values of route planning
-- and following, for players who want to tune them; in a window of their
-- own behind a button, so the normal settings stay short. Stored in
-- config.expert; G:ApplyExpert puts them into the planning tables.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local X={}
G.Expert=X
-- {key, table, field, default, low, high, step, format, title, help, section}
X.VALUES={
    {"level","Plan","LEVEL",6,2,20,1,"%d yd","Same level","Nodes share a stop only within this height difference; a node down in a ravine gets its own stop.","Route planning"},
    {"climb","Plan","CLIMB",0,0,30,1,"x%d","Level change","When ordering the stops, each yard of height between two levels counts this many yards of way where no real way was measured. 0: the measured ways alone decide.","Route planning"},
    {"neighbours","Plan","NEIGHBOURS",6,0,15,1,"%d","Real ways measured","For each stop the real way (round cliffs and water) to this many nearest stops is measured before ordering them; more is better in mazes like ravines but slower. 0: straight lines only."},
    {"lost","Plan","LOST",3,1,10,.5,"x%.1f","Way not found","A way to a neighbouring stop that the search does not find counts this many times the straight line."},
    {"trim","Plan","TRIM",10,0,20,1,"%d yd","Side trip shortened by","A stop off the main way is reached and left by one way; its tip is shortened by this much (following counts a point reached at 20 yd). 0: to the stop itself."},
    {"worthRun","Plan","WORTHRUN",8,1,15,1,"%d","Stops checked together","\"Way per node\" looks at runs of up to this many neighbouring stops."},
    {"known","Plan","KNOWN",.5,0,1,.05,"x%.2f","Known spawn weight","How much a known spawn you never found counts for \"Way per node\" (1 = like your own find)."},
    {"road","Grid","ROAD",.6,.3,1,.05,"x%.2f","Road and walked way cost","Ground cost on roads and often walked ways (1 = like any other ground)."},
    {"steep","Grid","STEEP",8,2,20,.5,"x%.1f","Steep slope cost","Cost of a steep slope you can still walk."},
    {"swim","Grid","SWIM",6,1,20,.5,"x%.1f","Swimming cost","Cost of swimming water with \"Avoid water\" on."},
    {"clear","Grid","CLEAR",1.25,1,3,.05,"x%.2f","Straight line up to","A leg goes straight when no cell on the line costs more than this; otherwise the way round is searched."},
    {"drop","Grid","DROP",12,2,30,.5,"%.1f yd","Jump marked from","A step down this high or more on a steep face is drawn orange."},
    {"safeDrop","Grid","SAFEDROP",12,4,30,1,"%d yd","Short drop at most","With \"Down cliffs: Short drops\", the highest drop a route may take."},
    {"maxRise","Grid","MAXRISE",14,4,30,1,"%d yd","Highest step","A step between neighbouring cells that rises more than this is a wall (never climbed), one that falls more is a cliff (a jump)."},
    {"goalStep","Grid","GOALSTEP",4,0,10,1,"%d yd","Step up to a node","A small step up onto a node's spot that is allowed although the slope is steep."},
    {"arrive","Follow","ARRIVE",20,5,50,1,"%d yd","Point reached at","Following: this close counts as reached; the next point follows.","Following"},
    {"onLeg","Follow","ON",10,2,40,1,"%d yd","On the leg within","Following: this close to the current leg, no other leg is looked at."},
    {"closer","Follow","CLOSER",15,5,60,1,"%d yd","Other leg closer by","Following: another leg becomes the active one when it is this much closer, twice in a row."},
}
local function target(name)
    if name=="Plan" then return G.Plan elseif name=="Grid" then return G.Grid elseif name=="Follow" then return G.Follow end
end
function X:Store()
    local c=G:Config()
    if type(c.expert)~="table" then c.expert={} end
    return c.expert
end
function X:Value(def)
    local v=self:Store()[def[1]]
    if type(v)~="number" or v~=v then return def[4] end
    return math.max(def[5],math.min(def[6],v))
end
function X:Apply()
    for _,def in ipairs(X.VALUES) do
        local t=target(def[2])
        if t then t[def[3]]=self:Value(def) end
    end
    -- The slope table holds the steep cost.
    if G.Grid and G.Grid.SLOPE then G.Grid.SLOPE[4]=G.Grid.STEEP end
end
function X:Reset()
    G:Config().expert={}
    self:Apply()
    if self.window and self.window:IsShown() then self:Refresh() end
end
function X:Changed() local n=0;for _ in pairs(self:Store()) do n=n+1 end;return n>0 end
function X:Build()
    if self.window then return self.window end
    UI:WithStyle(G:Style(),function()
        local w=UI:Window("BVGatherExpert",560,640,{title="Gather expert settings",minWidth=520,minHeight=420})
        self.window=w
        local form=UI:Form(w.content,520,560,w.content);UI:Place(form,w.content,10,10)
        local g=UI:SettingsGrid(form.content)
        self.controls={}
        local section
        for _,def in ipairs(X.VALUES) do
            if def[11] and def[11]~=section then section=def[11];g:Section(section:lower():gsub(" ",""),section) end
            local key=def[1]
            self.controls[key]=g:Row(def[9],UI:InlineSlider(g,190,def[5],def[6],def[7],def[8],function(value)
                X:Store()[key]=value;X:Apply()
            end),{help=def[10].." Default: "..string.format(def[8],def[4]).."."})
        end
        g:Section("reset","Defaults")
        g:Row("All values",UI:Button(g,"Reset to defaults",190,function() X:Reset() end),{help="Every expert value back to its default."})
        g:Row("Explained",UI:Button(g,"Open in the wiki",190,function() G.Wiki:Open("page:expert") end),{help="Every value with its default, range and examples."})
        g:Row("Note",UI:Label(g,"Planning values apply to the next Calculate; following values at once.",11,"muted"),{width=300})
        local function arrange()
            local width=math.max(300,M.GetWidth(w.content)-40)
            UI:Place(g,form.content,0,0)
            local h=g:Arrange(width)+8
            -- The form scrolls once its content is taller (Florian 2026-10-09:
            -- it did not scroll).
            local viewH=math.max(100,M.GetHeight(w.content)-20)
            M.Size(form,width,viewH);M.Width(form.content,width)
            if form.slider then M.Height(form.slider,viewH) end
            form:SetContentHeight(h)
        end
        w:HookScript("OnSizeChanged",arrange)
        w:HookScript("OnShow",function() arrange();X:Refresh() end)
        if not UI:RestoreWindowPosition(w) then w:ClearAllPoints();w:SetPoint("CENTER",UIParent,"CENTER",0,0) end
        w.drag:HookScript("OnDragStop",function() UI:SaveWindowPosition(w) end)
        w:Hide()
        arrange()
    end)
    return self.window
end
function X:Refresh()
    for _,def in ipairs(X.VALUES) do
        local control=self.controls and self.controls[def[1]]
        if control then control:SetValue(self:Value(def)) end
    end
end
function X:Open()
    local w=self:Build()
    w:Show();if w.Raise then w:Raise() end
    return w
end

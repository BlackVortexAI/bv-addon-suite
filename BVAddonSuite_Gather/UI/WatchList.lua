local _,G=...
if not G.ready then return end
-- The scanner's list in the settings (Florian 2026-10-10): one row per herb
-- or ore with its sound (the default, none, or one chosen with a preview),
-- a test button and Remove; below a choice to add one. A row says when its
-- tracking is off ("needs Find Herbs"), so an entry that never warns is
-- explained instead of looking broken.
local ns=G.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local L={}
G.WatchList=L
L.ROW=32

-- A sound's name for the list: the game's SoundKit name or the file's.
local kitNames
function L.SoundLabel(sound)
    if sound==false then return "No sound" end
    if type(sound)~="table" then return "Default sound" end
    if sound.source=="sharedmedia" then return (tostring(sound.sound):gsub("^lsm:","")) end
    if not kitNames then
        kitNames={}
        for name,id in pairs(rawget(_G,"SOUNDKIT") or {}) do if type(id)=="number" then kitNames[id]=name:gsub("_"," "):lower() end end
    end
    return kitNames[sound.soundKit] or ("Sound "..tostring(sound.soundKit))
end
-- Choose a sound with the Core picker: the game's sounds or the SharedMedia
-- sounds of other addons (Florian 2026-10-10: many game sounds make poor
-- alarms), with a preview; it opens on the source of the current sound.
function L:Choose(owner,current,done)
    local c=G:Config()
    if type(current)~="table" then current=c.scanSound end
    local config={source=current.source=="sharedmedia" and "sharedmedia" or "soundkit",soundKit=current.soundKit or G.Scanner.DEFAULT_SOUND.soundKit,
        sound=current.sound,channel=c.scanChannel,volume=100}
    if self.picker then self.picker:Hide() end
    self.picker=UI:SoundPicker(owner,config,function(value,source)
        if source=="sharedmedia" then done({source="sharedmedia",sound=value}) else done({source="soundkit",soundKit=value}) end
    end,{sources=true})
end

local SOUND_OPTIONS={{value="default",label="Default sound"},{value="none",label="No sound"},{value="choose",label="Choose sound..."}}
function L:Build(parent,changed)
    local f=CreateFrame("Frame",nil,parent);f.rows={}
    f.headName=UI:Label(f,"Herb or ore",11,"muted");f.headSound=UI:Label(f,"Sound",11,"muted")
    f.empty=UI:Label(f,"Nothing on the list yet: add a herb or ore below.",12,"muted")
    local S=G.Scanner
    local function row(i)
        if f.rows[i] then return f.rows[i] end
        local r=CreateFrame("Frame",nil,f)
        r.name=UI:Label(r,"",12,"text");r.name:SetWordWrap(false)
        r.hint=UI:Label(r,"",11,"muted");r.hint:SetWordWrap(false)
        r.sound=UI:Dropdown(r,170,SOUND_OPTIONS,function(value)
            local entry=r.entry;if not entry then return end
            if value=="choose" then
                L:Choose(parent,entry.sound,function(sound) entry.sound=sound;f:Refresh();S:Play(entry) end)
            else entry.sound=value=="none" and false or nil end
            f:Refresh()
        end)
        r.test=UI:Button(r,"Test",56,function() if r.entry and not S:Play(r.entry) then G:Print("No sound for "..r.entry.name..".") end end,"ghost")
        r.remove=UI:Button(r,"Remove",76,function() if r.entry then S:Remove(r.entry.name);changed() end end,"ghost")
        UI:AttachTooltip(r.test,"Test","Plays this entry's sound on the chosen channel.")
        f.rows[i]=r
        return r
    end
    f.add=UI:Dropdown(f,300,{},function(name)
        if S:Add(name) then changed() end
        f.add:SetLabelText("Add a herb or ore...")
    end)
    f.add:SetOptionsProvider(function()
        local out={}
        for _,kind in ipairs({"herb","ore"}) do
            for _,name in ipairs(S:Names(kind)) do
                if not S:Watched(name) then out[#out+1]={value=name,label=(kind=="herb" and "Herb: " or "Ore: ")..G.WithSkill(name)} end
            end
        end
        if #out==0 then out[1]={value="",label="Every known herb and ore is on the list"} end
        return out
    end)
    f.add:SetLabelText("Add a herb or ore...")
    UI:AttachTooltip(f.add,"Add","Herbs and ores Gather knows (skill in brackets). Each entry warns once when it shows on the minimap.")
    function f:Refresh()
        local list=S:List()
        for i,entry in ipairs(list) do
            local r=row(i);r.entry=entry;r:Show()
            r.name:SetText(G.WithSkill(entry.name))
            local kind=S:Kind(entry.name)
            r.hint:SetText(kind and (S:Hint(kind) or "") or "")
            r.sound:SetLabelText(L.SoundLabel(entry.sound))
        end
        for i=#list+1,#self.rows do self.rows[i]:Hide();self.rows[i].entry=nil end
        self.empty:SetShown(#list==0)
    end
    function f:Resize(width)
        M.Width(self,width)
        local count=#S:List()
        local soundX=width-170-56-76-24
        M.Point(self.headName,"TOPLEFT",self,"TOPLEFT",8,-4);M.Size(self.headName,soundX-16,16)
        M.Point(self.headSound,"TOPLEFT",self,"TOPLEFT",soundX,-4);M.Size(self.headSound,170,16)
        local y=-22
        for i=1,count do
            local r=self.rows[i] or row(i)
            r:ClearAllPoints();M.Point(r,"TOPLEFT",self,"TOPLEFT",0,y);M.Size(r,width,L.ROW)
            r.name:ClearAllPoints();M.Point(r.name,"TOPLEFT",r,"TOPLEFT",8,-2);M.Size(r.name,soundX-16,16)
            r.hint:ClearAllPoints();M.Point(r.hint,"TOPLEFT",r,"TOPLEFT",8,-17);M.Size(r.hint,soundX-16,14)
            r.sound:ClearAllPoints();M.Point(r.sound,"LEFT",r,"LEFT",soundX,0)
            r.test:ClearAllPoints();M.Point(r.test,"LEFT",r.sound,"RIGHT",6,0)
            r.remove:ClearAllPoints();M.Point(r.remove,"LEFT",r.test,"RIGHT",6,0)
            y=y-L.ROW
        end
        self.empty:ClearAllPoints();M.Point(self.empty,"TOPLEFT",self,"TOPLEFT",8,y-4);M.Size(self.empty,width-16,18)
        if count==0 then y=y-26 end
        self.add:ClearAllPoints();M.Point(self.add,"TOPLEFT",self,"TOPLEFT",8,y-6)
        local height=-y+44
        M.Height(self,height)
        return height
    end
    f:Refresh()
    f:Resize(600)
    return f
end

local _,L=...
if not L.ready then return end
-- Our own Combat Log filter and the line colours (0.7.2).
-- COMBAT_LOG_MESSAGE gives each line's colour as readable numbers; with
-- "Entire Line: By Source" it is the source's unit colour of the active
-- filter (signal probe 2026-10-07: you grey, friendly blue, hostile red,
-- your killing blow brightened to white). By default you and your pet share
-- one grey. With your pet in its own colour, a line tells you, your pet and
-- everyone else apart, whatever else the filter takes.
-- Setting up: Blizzard applies the filter through a call allowed only for
-- untainted code (C_CombatLog.ApplyFilterSettings, AllowedWhenUntainted), so
-- a filter an addon writes during a session would taint it. Written once out
-- of combat and followed at once by /reload, it comes back from the saved
-- file as Blizzard's own (Florian 2026-10-07: a filter survives /reload with
-- its colours; research docs/research/2026-10-07-combat-log-filter-import.md).
-- After the reload the filter is checked (issecurevariable) and the result
-- told in the chat. Existing filters are never changed; the filter list is
-- account-wide, so the new filter appears for every character.
local F={NAME="BV Combat Text",TOLERANCE=.02,HIGHLIGHT=1.5}
L.LogFilter=F
-- Colours of the filter we set up: you as Blizzard's grey, your pet orange.
F.ME={r=.7,g=.7,b=.7}
F.PET={r=1,g=.5,b=0}

local function readable(v) return v~=nil and not L.Secret(v) end
local function copy(t)
    if type(t)~="table" then return t end
    local out={}
    for k,v in pairs(t) do out[k]=copy(v) end
    return out
end
local function masks()
    local mine,pet=_G.COMBATLOG_FILTER_MINE,_G.COMBATLOG_FILTER_MY_PET
    if type(mine)~="number" or type(pet)~="number" then return nil end
    return mine,pet
end
local function rgb(c)
    if type(c)~="table" then return nil end
    local r,g,b=c.r,c.g,c.b
    if type(r)~="number" or type(g)~="number" or type(b)~="number" then return nil end
    return {r=r,g=g,b=b}
end
local function same(a,b,tol)
    tol=tol or F.TOLERANCE
    return a and b and math.abs(a.r-b.r)<=tol and math.abs(a.g-b.g)<=tol and math.abs(a.b-b.b)<=tol
end
-- A killing blow's line: its colour brightened (Blizzard: x1.5, at most 1).
local function bright(c) return {r=math.min(1,c.r*F.HIGHLIGHT),g=math.min(1,c.g*F.HIGHLIGHT),b=math.min(1,c.b*F.HIGHLIGHT)} end

-- Colours of the active filter. Returns {me, pet, byLine, meUnique,
-- petUnique} or nil when not readable. me/petUnique: no other unit colour
-- of the filter (and not each other) looks the same.
function F:Colours()
    local settings=_G.Blizzard_CombatLog_CurrentSettings
    local mine,pet=masks()
    if type(settings)~="table" or not mine then return nil end
    local colors,options=settings.colors,settings.settings
    if type(colors)~="table" or type(colors.unitColoring)~="table" or type(options)~="table" then return nil end
    local unit=colors.unitColoring
    local me,mp=rgb(unit[mine]),rgb(unit[pet])
    if not me then return nil end
    local out={me=me,pet=mp,byLine=options.lineColoring==true and options.lineColorPriority==1}
    local function unique(c,own)
        if not c then return false end
        for key,value in pairs(unit) do
            if key~=own and same(rgb(value),c) then return false end
        end
        return true
    end
    out.meUnique=unique(me,mine)
    out.petUnique=mp~=nil and unique(mp,pet)
    return out
end
-- Lines told apart by colour: the line colours follow the source and your
-- own colour is no one else's.
function F:Usable(colours)
    colours=colours or self:Colours()
    return colours~=nil and colours.byLine and colours.meUnique
end
-- Whose line: "me", "pet" or nil (someone else, or not readable).
function F:Classify(r,g,b,colours)
    if not (readable(r) and readable(g) and readable(b)) or type(r)~="number" then return nil end
    local c={r=r,g=g,b=b}
    if same(c,colours.me) or same(c,bright(colours.me)) then return "me" end
    if colours.pet and colours.petUnique and (same(c,colours.pet) or same(c,bright(colours.pet))) then return "pet" end
    return nil
end

-- Setting up -------------------------------------------------------------------------
-- Why it cannot be set up now, or nil.
function F:Blocked()
    if InCombatLockdown and InCombatLockdown() then return "in combat" end
    local saved=_G.Blizzard_CombatLog_Filters
    if type(saved)~="table" or type(saved.filters)~="table" then return "Combat Log not loaded yet: open the Combat Log tab once" end
    if not masks() then return "Combat Log constants missing" end
    return nil
end
function F:Find()
    local saved=_G.Blizzard_CombatLog_Filters
    if type(saved)~="table" or type(saved.filters)~="table" then return nil end
    for i,filter in ipairs(saved.filters) do
        if type(filter)=="table" and filter.name==self.NAME then return i,filter end
    end
end
-- The template: the first filter whose parts only take your own actions
-- (WoW's "My actions"), else the first one. Its message types are kept.
local function template(filters,mine)
    for _,filter in ipairs(filters) do
        local own=type(filter)=="table" and type(filter.filters)=="table"
        if own then
            for _,part in ipairs(filter.filters) do
                local flags=type(part)=="table" and part.sourceFlags
                if type(flags)=="table" then
                    for key,on in pairs(flags) do if on and key~=mine then own=false end end
                end
            end
        end
        if own then return filter end
    end
    return filters[1]
end
-- Writes the filter (new, or ours again) and selects it. The reload that
-- must follow at once is the dialog's secure /reload macro: ReloadUI() is
-- protected on Forever (ADDON_ACTION_BLOCKED, Florian 2026-10-07), the
-- game's own /reload from a macro button is not.
function F:SetUp()
    local blocked=self:Blocked()
    if blocked then L:Print("Combat Log filter not set up: "..blocked..".");return false end
    local saved=_G.Blizzard_CombatLog_Filters
    local mine,pet=masks()
    local index=self:Find()
    local base=template(saved.filters,mine)
    if type(base)~="table" then L:Print("Combat Log filter not set up: no filter to start from.");return false end
    local filter=copy(base)
    filter.name,filter.quickButtonName=self.NAME,self.NAME
    filter.tooltip="Your actions and your pet's, each in its own colour (BV Combat Text)."
    -- A quick button above the Combat Log (Blizzard shows one only with
    -- quickButtonDisplay): the Start button selects the filter with it.
    filter.hasQuickButton,filter.onQuickBar=true,true
    filter.quickButtonDisplay={solo=true,party=true,raid=true}
    if type(filter.filters)~="table" then filter.filters={} end
    for _,part in ipairs(filter.filters) do
        if type(part)=="table" and type(part.sourceFlags)=="table" and part.sourceFlags[mine] then part.sourceFlags[pet]=true end
    end
    if type(filter.colors)~="table" then filter.colors={} end
    if type(filter.colors.unitColoring)~="table" then filter.colors.unitColoring={} end
    filter.colors.unitColoring[mine]={a=1,r=self.ME.r,g=self.ME.g,b=self.ME.b}
    filter.colors.unitColoring[pet]={a=1,r=self.PET.r,g=self.PET.g,b=self.PET.b}
    if type(filter.settings)~="table" then filter.settings={} end
    filter.settings.lineColoring,filter.settings.lineColorPriority=true,1
    if index then saved.filters[index]=filter else table.insert(saved.filters,filter);index=#saved.filters end
    saved.currentFilter=index
    L:DB().logFilter={pending=true,index=index,time=time and time() or 0}
    L:Print("Combat Log filter \""..self.NAME.."\" set up. Reloading the interface ...")
    return true
end
-- The quick button that selects our filter, while it is set up and another
-- one is selected (Blizzard names them CombatLogQuickButtonFrameButton1..n,
-- their ID is the filter's index; only shown ones fit on the bar).
F.QUICK="CombatLogQuickButtonFrameButton"
function F:QuickButton()
    local index=self:Find()
    if not index or self:Selected() then return nil end
    for i=1,20 do
        local name=self.QUICK..i
        local button=_G[name]
        if not button then break end
        local okShown,shown=pcall(button.IsShown,button)
        local okId,id=pcall(button.GetID,button)
        if okShown and shown and okId and id==index then return name end
    end
end
-- Asks first (UI/FilterDialog.lua: the interface reloads), then sets up.
function F:Confirm()
    local blocked=self:Blocked()
    if blocked then L:Print("Combat Log filter not set up: "..blocked..".");return nil end
    return L.FilterDialog:Show(function() return F:SetUp() end)
end
-- Our filter is the one Blizzard applies. Judged by the applied settings,
-- not by currentFilter: that index goes stale when filters are deleted or
-- moved in the settings (Florian 2026-10-07: "BV filter selected" after
-- deleting it while "What happened to me?" was active).
function F:Selected()
    local current=_G.Blizzard_CombatLog_CurrentSettings
    return type(current)=="table" and current.name==self.NAME
end
-- After the reload: is our filter Blizzard's own now and selected?
function F:Verify()
    local db=L:DB()
    local record=db.logFilter
    if type(record)~="table" or not record.pending then return nil end
    local saved=_G.Blizzard_CombatLog_Filters
    if type(saved)~="table" or type(saved.filters)~="table" then return nil end -- later, once loaded
    record.pending=nil
    local index,filter=self:Find()
    local result={found=index~=nil,selected=index~=nil and saved.currentFilter==index}
    local check=_G.issecurevariable
    if type(check)=="function" and filter then
        local function secure(t,key) local ok,v=pcall(check,t,key);return ok and v==true end
        result.secure=secure(saved,"currentFilter") and secure(filter,"name") and secure(filter,"colors") and secure(filter,"filters")
    end
    record.result=result
    if result.found and result.selected and result.secure~=false then
        L:Print("Combat Log filter \""..self.NAME.."\" is set up and active.")
    else
        L:Print("Combat Log filter \""..self.NAME.."\" could not be confirmed ("..(not result.found and "not found" or not result.selected and "not selected" or "not Blizzard's own")
            .."). Combat Text keeps working as before; select another filter or /reload once more.")
    end
    return result
end
function F:Enable(context)
    if not self:Verify() then
        -- The Combat Log loads on demand: check once it is there.
        pcall(context.Subscribe,context,"ADDON_LOADED",function(_,name) if name=="Blizzard_CombatLog" then F:Verify();L.Log:HookQuick();L.Log:Update() end end)
    end
end

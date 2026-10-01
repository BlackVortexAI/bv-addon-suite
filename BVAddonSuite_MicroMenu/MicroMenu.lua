local package=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireRelease then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BVAddonSuite Core 0.8.88. Update all BV packages together; saved data is preserved.") end
    return
end
if not ns:RequireRelease(package,"0.8.88") then return end
local N,UI,D=ns.NativeButtons,ns.UI,ns.DesignSystem.Metrics

-- Known micro buttons (Forever/Classic and Mainline names), default order,
-- label and Lucide symbol. Unknown *MicroButton children are appended.
local known={
    {"CharacterMicroButton","Character","user"},
    {"ProfessionMicroButton","Professions","hammer"},
    {"PlayerSpellsMicroButton","Spells and talents","book-open"},
    {"SpellbookMicroButton","Spellbook","book-open"},
    {"TalentMicroButton","Talents","star"},
    {"AchievementMicroButton","Achievements","trophy"},
    {"LegacyMicroButton","Legacy","hourglass"},
    {"QuestLogMicroButton","Quest log","scroll-text"},
    {"HousingMicroButton","Housing","house"},
    {"SocialsMicroButton","Social","message-circle"},
    {"GuildMicroButton","Guild","shield"},
    {"WorldMapMicroButton","World map","map"},
    {"PVPMicroButton","PvP","swords"},
    {"LFDMicroButton","Group finder","search"},
    {"LFGMicroButton","Group finder","search"},
    {"CollectionsMicroButton","Collections","paw-print"},
    {"EJMicroButton","Adventure guide","compass"},
    {"HelpMicroButton","Help","circle-help"},
    {"StoreMicroButton","Shop","shopping-bag"},
    {"MainMenuMicroButton","Game menu","settings"},
}
local info={}
for index,row in ipairs(known) do info[row[1]]={index=index,label=row[2],symbol=row[3]} end
local Micro
-- Unknown buttons found as MicroMenu children; remembered because borrowing
-- moves them out of MicroMenu.
local extra={}

-- Existing buttons in the saved order; new ones keep their default position.
local function discover()
    local names,seen={},{}
    for _,row in ipairs(known) do
        local b=_G[row[1]]
        -- Buttons without a parent exist as globals but are not used by this
        -- game version (native report 0.8.76); leave them alone.
        if type(b)=="table" and type(b.SetParent)=="function" and b:GetParent()~=nil then names[#names+1]=row[1];seen[row[1]]=true end
    end
    if MicroMenu and MicroMenu.GetChildren then
        for _,child in ipairs({MicroMenu:GetChildren()}) do
            local name=child.GetName and child:GetName()
            if type(name)=="string" and name:match("MicroButton$") and not seen[name] and not extra[name] then
                extra[name]=true;extra[#extra+1]=name
            end
        end
    end
    for _,name in ipairs(extra) do
        if not seen[name] and type(_G[name])=="table" then names[#names+1]=name;seen[name]=true end
    end
    return names,seen
end
local function ordered(cfg)
    local names,seen=discover()
    local out,used={},{}
    for _,name in ipairs(type(cfg.order)=="table" and cfg.order or {}) do
        if seen[name] and not used[name] then out[#out+1]=name;used[name]=true end
    end
    for _,name in ipairs(names) do if not used[name] then out[#out+1]=name;used[name]=true end end
    return out
end
local function label(name) return info[name] and info[name].label or (name:gsub("MicroButton$","")) end

-- Panel-open (pushed) and disabled states follow Blizzard's own calls.
local function track(button)
    if button.bvMicroTracked then return end
    button.bvMicroTracked=true
    local function sync()
        local plate=Micro and Micro.plates[button]
        if not plate then return end
        plate:SetActive(button.GetButtonState and button:GetButtonState()=="PUSHED")
        plate:SetDisabled(button.IsEnabled and not button:IsEnabled())
    end
    for _,method in ipairs({"SetButtonState","Enable","Disable","SetEnabled"}) do
        if type(button[method])=="function" then hooksecurefunc(button,method,sync) end
    end
end
local function entries(cfg)
    local out={}
    local hidden=type(cfg.hidden)=="table" and cfg.hidden or {}
    for _,name in ipairs(ordered(cfg)) do
        local button=_G[name]
        track(button)
        local keep={}
        -- Notification flashes stay Blizzard's.
        for _,key in ipairs({"FlashBorder","FlashContent"}) do if button[key] then keep[button[key]]=true end end
        local plain=cfg.symbols==false
        -- Blizzard pictures: "Background" off hides Blizzard's button background.
        local art=not plain and N.Art(button,keep) or nil
        if plain and cfg.background==false then
            art={}
            for _,key in ipairs({"Background","PushedBackground"}) do if button[key] then art[#art+1]=button[key] end end
        end
        out[#out+1]={key=name,button=button,hidden=hidden[name]==true,plain=plain,
            symbol=info[name] and info[name].symbol or "circle",art=art,
            state={active=button.GetButtonState and button:GetButtonState()=="PUSHED",disabled=button.IsEnabled and not button:IsEnabled()}}
    end
    return out
end

Micro=N:Bar({
    id="micro_menu",layout="bv:micromenu",label="Micro Menu",anchor="BOTTOMRIGHT",x=-8,y=8,
    defaults={enabled=false,skin="obsidian",shape="square",size=26,spacing=3,perLine=12,vertical=false,
        fade=false,fadeAlpha=.2,symbols=true},
    entries=entries,
    -- Buttons stay MicroMenu children; see NativeButtons bar:Borrow (0.8.76).
    reparent=false,
    decor=function()
        local list={}
        for _,key in ipairs({"BorderArt","BackgroundArt"}) do if MicroMenu and MicroMenu[key] then list[#list+1]=MicroMenu[key] end end
        return list
    end,
    install=function(bar)
        -- Blizzard lays the menu out again on vehicle, pet battle and resize;
        -- answer at once so its positions never show for a frame.
        for _,owner in ipairs({MicroMenu,MicroMenuContainer}) do
            if type(owner)=="table" and type(owner.Layout)=="function" then
                hooksecurefunc(owner,"Layout",function()
                    if not bar.active then return end
                    if bar.arranging then bar:Queue() else bar:Arrange() end
                end)
            end
        end
    end,
    restore=function()
        if MicroMenu and MicroMenu.Layout then MicroMenu:Layout() end
        if MicroMenuContainer and MicroMenuContainer.Layout then MicroMenuContainer:Layout() end
    end,
})
ns.MicroMenu=Micro

local function move(name,delta)
    local cfg=Micro:Config();local list=ordered(cfg)
    for i,value in ipairs(list) do
        if value==name then
            local j=i+delta
            if j>=1 and j<=#list then list[i],list[j]=list[j],list[i] end
            break
        end
    end
    cfg.order=list;Micro:Changed()
end
local function setShown(name,value)
    local cfg=Micro:Config()
    cfg.hidden=type(cfg.hidden)=="table" and cfg.hidden or {}
    cfg.hidden[name]=not value or nil
    Micro:Changed()
end

ns.Modules:Register({id="micro_menu",OnEnable=function(context) Micro:Enable(context) end})
local page
ns.Config:RegisterPage("micromenu",{title="Micro Menu",description="Character, spellbook, quest log and more as one skinned, movable bar.",
    build=function(parent)
        if not page then
            page=UI:NativeBarPage(parent,Micro,function(p,cfg,changed)
                local g=p.grid
                p.symbols=p:Row("BV symbols",UI:Switch(g,true,function(value) cfg().symbols=value;changed() end),
                    "Off: keep Blizzard's pictures, only position and size change.")
                p:Section("buttons","Buttons")
                -- One row per button: label "n. Name", then visible / up / down.
                p.slots={}
                for i=1,#ordered(cfg()) do
                    local slot=UI:Panel(g,168,26,"surface");UI:HideSurface(slot)
                    slot.bvVisible=UI:Place(UI:Switch(slot,true,function(value) if slot.bvName then setShown(slot.bvName,value) end end),slot,0,3)
                    slot.bvUp=UI:Place(UI:Button(slot,"Up",58,function() if slot.bvName then move(slot.bvName,-1) end end,"ghost"),slot,46,0)
                    slot.bvDown=UI:Place(UI:Button(slot,"Down",58,function() if slot.bvName then move(slot.bvName,1) end end,"ghost"),slot,110,0)
                    for _,b in ipairs({slot.bvUp,slot.bvDown}) do D.Height(b,24) end
                    p.slots[i]=slot
                    p:Row(i..".",slot,"Switch: show the button. Up / Down: change the order.",{fixedHeight=true})
                end
                function p:RefreshExtra(c)
                    self.symbols:SetValue(c.symbols~=false)
                    local list=ordered(c)
                    local hidden=type(c.hidden)=="table" and c.hidden or {}
                    for i,slot in ipairs(self.slots) do
                        slot.bvName=list[i]
                        if slot.bvName then
                            slot.bvVisible:SetValue(not hidden[slot.bvName])
                            slot.bvGridRow.label:SetText(i..".  "..label(slot.bvName))
                        end
                    end
                end
            end)
        end
        return page
    end,
    refresh=function() if page then page:Refresh() end end})
ns.Commands:Register("micro","micro_menu","micromenu")
if ns.ready and IsLoggedIn() then ns.Modules:Reconcile() end

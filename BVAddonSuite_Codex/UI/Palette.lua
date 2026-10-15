local _,C=...
if not C.ready then return end
-- The search field (Florian 2026-10-11: like Spotlight or EasyFind; "go
-- wild on the looks"): a large search bar with a magnifier, the matches as
-- you type, each with a symbol of what it is (a trainer, a banker, a flight
-- master, a zeppelin, an instance, a mailbox ...), its kind, how many places
-- and the distance to the nearest as a badge. Up and down choose (an accent
-- bar marks it), Enter or a click adds it to the tour, Shift+Enter (or a
-- Shift-click) leads there at once, Ctrl+Enter starts the tour, Escape
-- closes. An empty field suggests: what you chose lately, your class
-- trainer, the places everyone needs. A mistyped word still finds.
local ns=C.ns
local UI,M=ns.UI,ns.DesignSystem.Metrics
local P={rows={},chosen=1}
C.Palette=P
P.ROWS=C.MAX
local ROW,WIDTH,BAR=42,600,48
local WHITE="Interface\\Buttons\\WHITE8X8"
local KIND={npc="NPC",category="All of them",flight="Flight master",transport="Transport",entrance="Instance",object="Object",item="Item",quest="Quest",zone="Area",action="BV",turnin="Turn in",bundle="Tour"}
-- A symbol for what an entry is: by its kind, else by words of its title.
local SYMBOLS={
    {"flight master","plane"},{"wind rider","plane"},{"gryphon","plane"},{"hippogryph","plane"},
    {"zeppelin","plane-takeoff"},{"ship","ship"},{"tram","cable-car"},
    {"mailbox","mail"},{"anvil","hammer"},{"forge","flame"},{"meeting stone","users"},
    {"banker","vault"},{"auction","gavel"},{"innkeeper","beer"},{"stable","paw-print"},
    {"trainer","book-open"},{"repair","wrench"},{"vendor","shopping-bag"},{"supplies","shopping-bag"},{"merchant","shopping-bag"},
    {"guard","shield"},{"battlemaster","swords"},{"spirit healer","heart"},
}
-- The game's own icons (Florian 2026-10-12: easier to recognise than our
-- symbols): an item's icon, else one by kind or by words of its title. Each
-- a list of candidates, the first the client has (GetFileIDFromPath); none
-- of them, or no way to ask: our symbol. Suite actions keep their symbols.
-- File IDs Florian picked in Aura Studio (2026-10-12) come first: a texture
-- by its ID needs no check.
local I="Interface\\Icons\\"
local T="Interface\\Minimap\\Tracking\\"
P.ART={
    flight={4640485,T.."FlightMaster",I.."Ability_Mount_Wyvern_01",I.."Ability_Mount_Gryphon_01"},
    -- Florian's pick 4622474 (ability_evoker_rewind); 4322474 first, a typo,
    -- is a sound file (a green square in game).
    zeppelin={4622474,I.."inv_hordezeppelinmountclassic",I.."inv_zeppelinmount",I.."inv_hordezeppelinmount",I.."INV_Misc_Bomb_04",I.."Ability_Mount_Wyvern_01"},
    ship={4622474,I.."inv_hordezeppelinmountclassic",I.."inv_zeppelinmount",I.."inv_hordezeppelinmount",I.."INV_Misc_Anchor",I.."Spell_Frost_SummonWaterElemental"},
    tram={4622474,I.."inv_hordezeppelinmountclassic",I.."inv_zeppelinmount",I.."inv_hordezeppelinmount",I.."INV_Gizmo_02",I.."Trade_Engineering"},
    entrance={135741,I.."Spell_Arcane_PortalUnderCity",I.."Spell_Shadow_Teleport"},
    raid={134153,I.."Spell_Arcane_PortalUnderCity"},
    -- Quests the yellow "!", turn-ins the yellow "?" (Florian 2026-10-12);
    -- the red question mark only stands in where no icon is found.
    quest={"Interface\\GossipFrame\\AvailableQuestIcon",I.."INV_Misc_Note_01"},
    turnin={"Interface\\GossipFrame\\ActiveQuestIcon",I.."INV_Misc_Note_02"},
    zone={I.."INV_Misc_Map_01"},
    city={I.."Spell_Arcane_TeleportOrgrimmar",I.."Spell_Arcane_TeleportStormwind",I.."INV_Misc_Map_01"},
    item={134400},
    missing={134400},
    bundle={I.."INV_Misc_Note_06",I.."INV_Misc_Note_01"},
    banker={1269443,T.."Banker",I.."INV_Misc_Bag_10"},
    auction={T.."Auctioneer",I.."INV_Misc_Coin_02"},
    innkeeper={1041860,T.."Innkeeper",I.."INV_Misc_Rune_01"},
    mailbox={133471,T.."Mailbox",I.."INV_Letter_01"},
    stable={T.."StableMaster",I.."Ability_Hunter_BeastTaming"},
    repair={T.."Repair",I.."Ability_Repair",I.."Trade_BlackSmithing"},
    vendor={T.."Food",I.."INV_Misc_Bag_07",I.."INV_Misc_Coin_03"},
    anvil={I.."Trade_BlackSmithing"},
    forge={I.."Spell_Fire_Fire",I.."Trade_BlackSmithing"},
    meeting={I.."Spell_Shadow_Teleport"},
    guard={I.."Ability_Warrior_DefensiveStance",I.."INV_Shield_06"},
    battlemaster={132147,T.."BattleMaster",I.."INV_BannerPVP_02",I.."INV_BannerPVP_01"},
    spirit={I.."Spell_Holy_Resurrection"},
    trainer={134945,T.."Class",I.."INV_Misc_Book_09"},
    riding={132261},
    profession={134945,T.."Profession",I.."INV_Misc_Book_11"},
    alchemy={I.."Trade_Alchemy"},herbalism={I.."Trade_Herbalism"},mining={I.."Trade_Mining"},
    tailoring={I.."Trade_Tailoring"},engineering={I.."Trade_Engineering"},leatherworking={I.."Trade_LeatherWorking"},
    blacksmithing={I.."Trade_BlackSmithing"},enchanting={I.."Trade_Engraving"},skinning={I.."INV_Misc_Pelt_Wolf_01"},
    fishing={I.."Trade_Fishing"},cooking={I.."INV_Misc_Food_15"},["first aid"]={I.."Spell_Holy_SealOfSacrifice"},
    npc={I.."INV_Misc_GroupNeedMore",I.."INV_Misc_Head_Human_01"},
}
-- Raids by their instance map (Molten Core, Onyxia, Blackwing Lair,
-- Zul'Gurub, the Ruins and Temple of Ahn'Qiraj, Naxxramas).
P.RAIDS={[409]=true,[249]=true,[469]=true,[309]=true,[509]=true,[531]=true,[533]=true}
-- Words of a title and the icon they ask for (the first found).
P.ARTWORDS={
    {"flight master","flight"},{"wind rider","flight"},{"gryphon","flight"},{"hippogryph","flight"},{"bat handler","flight"},
    {"zeppelin","zeppelin"},{"ship","ship"},{"boat","ship"},{"tram","tram"},
    {"mailbox","mailbox"},{"anvil","anvil"},{"forge","forge"},{"meeting stone","meeting"},
    {"banker","banker"},{"auction","auction"},{"innkeeper","innkeeper"},{"stable","stable"},
    {"riding","riding"},{"trainer","trainer"},{"instructor","trainer"},
    {"alchemy","alchemy"},{"herbalism","herbalism"},{"mining","mining"},{"tailoring","tailoring"},{"engineering","engineering"},
    {"leatherworking","leatherworking"},{"blacksmithing","blacksmithing"},{"enchanting","enchanting"},{"skinning","skinning"},
    {"fishing","fishing"},{"cooking","cooking"},{"first aid","first aid"},
    {"repair","repair"},{"vendor","vendor"},{"supplies","vendor"},{"merchant","vendor"},
    {"guard","guard"},{"battlemaster","battlemaster"},{"spirit healer","spirit"},
}
local have={}
local function exists(path)
    if type(path)=="number" then return true end
    if have[path]==nil then
        local ask=rawget(_G,"GetFileIDFromPath")
        if type(ask)~="function" then return false end
        local ok,id=pcall(ask,path)
        have[path]=ok and type(id)=="number" and id>0 or false
    end
    return have[path]
end
local function first(key)
    for _,path in ipairs(P.ART[key] or {}) do if exists(path) then return path end end
end
-- The icon for an entry: a texture (path or file ID), or nil for our symbol.
function P.Art(e)
    if e.kind=="action" then return nil end
    if e.kind=="item" then
        -- By its ID (always known to the client), else by its name (only
        -- once it is in the client's cache). Florian 2026-10-12: every item
        -- showed the question mark; the client has these under C_Item (the
        -- old globals are gone), so both are asked.
        local call=C.Call
        local function icon(key)
            local tex=type(key)=="number" and (call("C_Item.GetItemIconByID",key) or call("GetItemIcon",key)) or nil
            if tex then return tex end
            tex=select(5,call("C_Item.GetItemInfoInstant",key))
            if tex then return tex end
            return (select(5,call("GetItemInfoInstant",key)))
        end
        for _,key in ipairs({e.itemID or false,e.name}) do
            if key then local tex=icon(key);if tex then return tex end end
        end
        return first("item")
    end
    if e.kind=="flight" then return first("flight") end
    if e.kind=="entrance" then return first(P.RAIDS[e.instance or 0] and "raid" or "entrance") end
    if e.kind=="quest" then return first("quest") end
    if e.kind=="turnin" then return first("turnin") end
    if e.kind=="bundle" then return first("bundle") end
    if e.kind=="zone" then return first(e.detail=="City" and "city" or "zone") end
    local words=e.words or ""
    for _,w in ipairs(P.ARTWORDS) do
        if words:find(w[1],1,true) then local path=first(w[2]);if path then return path end end
    end
    if e.kind=="npc" or e.kind=="category" then return first("npc") or first("missing") end
    -- None found: the placeholder.
    return first("missing")
end
-- Which icons the client has (/bv codex icons): every candidate, found or not.
function P:IconReport()
    local keys={}
    for key in pairs(P.ART) do keys[#keys+1]=key end
    table.sort(keys)
    local missing={}
    for _,key in ipairs(keys) do
        local path=first(key)
        C:Print(string.format("%s: %s",key,path and tostring(path):gsub("^Interface\\Icons\\",""):gsub("^Interface\\","") or "none (our symbol)"))
        for _,p in ipairs(P.ART[key]) do if not exists(p) then missing[#missing+1]=tostring(p):match("([^\\]+)$") end end
    end
    if type(rawget(_G,"GetFileIDFromPath"))~="function" then C:Print("This client cannot be asked for files (GetFileIDFromPath): our symbols are used.") end
    C:Print("Not in this client: "..(#missing>0 and table.concat(missing,", ") or "-"))
end
function P.Symbol(e)
    if e.kind=="action" then return e.symbol or "layout-dashboard" end
    if e.kind=="entrance" then return "castle" end
    if e.kind=="item" then return "shopping-bag" end
    if e.kind=="quest" then return "scroll-text" end
    if e.kind=="turnin" then return "circle-check" end
    if e.kind=="bundle" then return "route" end
    if e.kind=="zone" then return e.detail=="City" and "landmark" or "map" end
    if e.kind=="flight" then return "plane" end
    local words=e.words or ""
    for _,s in ipairs(SYMBOLS) do if words:find(s[1],1,true) then return s[2] end end
    return e.kind=="category" and "users" or "user"
end
-- An icon's symbol changed in place.
local function setIcon(icon,name)
    if not icon or icon.symbolName==name or not (icon.glyph and ns.Symbols) then return end
    local symbol=ns.Symbols:UIName(name) or (ns.Symbols:Valid(name) and name)
    if not symbol then return end
    local path,l,r,t,b=ns.Symbols:Coords(symbol,M.ToNative(20))
    icon.glyph:SetTexture(path);icon.glyph:SetTexCoord(l,r,t,b)
    icon.symbolName=name
end
P.SetIcon=setIcon
local function color(key,alpha)
    local r,g,b=UI:GameStyle(nil):Color(key)
    return r,g,b,alpha or 1
end
-- The footer's keys: {key cap, what it does}.
P.KEYS={{"Enter","add"},{"Shift+Enter","navigate now"},{"Ctrl+Enter","tour"}}
function P:Build()
    if self.window then return self.window end
    UI:WithStyle(UI:GameStyle(nil),function()
        local w=UI:Window("BVCodexPalette",WIDTH,BAR+60+P.ROWS*ROW,{title="Codex"})
        self.window=w
        local c=w.content
        -- The search bar: a raised field, the magnifier, the input.
        local bar=UI:Panel(c,WIDTH-28,BAR,"raised",10,.95)
        M.Point(bar,"TOPLEFT",c,"TOPLEFT",14,-8)
        self.bar=bar
        bar.icon=UI:Icon(bar,"search",22,"accent");bar.icon:ClearAllPoints();M.Point(bar.icon,"LEFT",bar,"LEFT",14,0)
        -- The field without a frame of its own (the bar is its frame), larger type.
        local style=UI:GetStyle()
        local input=style:Input(bar,WIDTH-92,false,"",nil,true)
        input:SetMaxLetters(60)
        input:SetScript("OnEnterPressed",function() P:Enter() end)
        UI:Bind(input,function() style:Font(input,17) end)
        style:Font(input,17)
        M.Point(input,"LEFT",bar,"LEFT",40,0)
        input:HookScript("OnTextChanged",function() P:Update() end)
        input:SetScript("OnEscapePressed",function() w:Hide() end)
        input:SetScript("OnArrowPressed",function(_,key) if key=="UP" then P:Choose(P.chosen-1) elseif key=="DOWN" then P:Choose(P.chosen+1) end end)
        input:SetScript("OnTabPressed",function() P:Choose(P.chosen+1) end)
        UI:AttachTooltip(input,"Search","An NPC, a title (\"Warlock Trainer\", \"Banker\"), a flight master, a zeppelin, an instance, \"Mailbox\". Enter adds it to your tour.")
        self.input=input
        for i=1,P.ROWS do self:Row(c,i) end
        -- What is happening, and the keys.
        -- A hairline over the footer; the keys as key caps (Florian
        -- 2026-10-11: finer, like the launchers he knows).
        self.rule=UI:Rule(c,WIDTH-28);M.Point(self.rule,"BOTTOMLEFT",c,"BOTTOMLEFT",14,36)
        self.note=UI:Label(c,"",11,"muted");M.Point(self.note,"BOTTOMLEFT",c,"BOTTOMLEFT",18,12);M.Size(self.note,WIDTH-330,16)
        self.keys={}
        local prev
        for i=#P.KEYS,1,-1 do
            local k=P.KEYS[i]
            local text=UI:Label(c,k[2],11,"muted")
            if prev then M.Point(text,"RIGHT",prev,"LEFT",-12,0) else M.Point(text,"BOTTOMRIGHT",c,"BOTTOMRIGHT",-18,13) end
            local cap=UI:Panel(c,10,18,"raised",4,.95)
            local key=UI:Label(cap,k[1],10,"text",true);M.Point(key,"CENTER",cap,"CENTER",0,0)
            local width=key.GetStringWidth and M.ToDesign(key:GetStringWidth() or 0) or 0
            M.Width(cap,math.max(18,math.floor(width+12)))
            M.Point(cap,"RIGHT",text,"LEFT",-5,0)
            self.keys[i]={cap=cap,key=key,text=text}
            prev=cap
        end
        w:HookScript("OnShow",function() P.input:SetFocus() end)
        w:Hide()
    end)
    return self.window
end
function P:Row(c,i)
    local row=CreateFrame("Button",nil,c)
    M.Size(row,WIDTH-28,ROW-4);M.Point(row,"TOPLEFT",c,"TOPLEFT",14,-(BAR+18+(i-1)*ROW))
    row.bg=row:CreateTexture(nil,"BACKGROUND");row.bg:SetAllPoints(row);row.bg:SetTexture(WHITE);row.bg:SetVertexColor(1,1,1,0)
    row.hover=row:CreateTexture(nil,"HIGHLIGHT");row.hover:SetAllPoints(row);row.hover:SetTexture(WHITE);row.hover:SetVertexColor(1,1,1,.05)
    -- The chosen one: an accent bar on its left.
    row.mark=row:CreateTexture(nil,"ARTWORK");row.mark:SetTexture(WHITE);row.mark:SetVertexColor(color("accent"))
    M.Point(row.mark,"TOPLEFT",row,"TOPLEFT",0,-4);M.Point(row.mark,"BOTTOMLEFT",row,"BOTTOMLEFT",0,4);M.Width(row.mark,3)
    -- Its symbol on a small tile.
    row.tile=UI:Panel(row,30,30,"raised",8,.9);M.Point(row.tile,"LEFT",row,"LEFT",10,0)
    row.icon=UI:Icon(row.tile,"user",18,"muted");row.icon:ClearAllPoints();M.Point(row.icon,"CENTER",row.tile,"CENTER",0,0)
    -- Or the game's icon on it.
    row.art=row.tile:CreateTexture(nil,"OVERLAY");M.Point(row.art,"TOPLEFT",row.tile,"TOPLEFT",2,-2);M.Point(row.art,"BOTTOMRIGHT",row.tile,"BOTTOMRIGHT",-2,2);row.art:Hide()
    row.name=UI:Label(row,"",13,"text",true);M.Point(row.name,"TOPLEFT",row,"TOPLEFT",50,-4);M.Size(row.name,WIDTH-250,16)
    -- In an enemy base: marked (Florian 2026-10-14).
    row.warn=UI:Icon(row,"triangle-alert",14,"warning");row.warn:Hide()
    row.warn:EnableMouse(true)
    UI:AttachTooltip(row.warn,"Enemy base","This place lies in an enemy base. Leading you there turns avoiding enemy bases off for that way.")
    row.detail=UI:Label(row,"",11,"muted");M.Point(row.detail,"TOPLEFT",row,"TOPLEFT",50,-21);M.Size(row.detail,WIDTH-250,14);row.detail:SetWordWrap(false)
    -- The distance, quiet on the right (the chosen row's in full colour).
    row.badge=CreateFrame("Frame",nil,row);M.Size(row.badge,92,22);M.Point(row.badge,"RIGHT",row,"RIGHT",-76,0)
    row.far=UI:Label(row.badge,"",12,"muted");M.Point(row.far,"RIGHT",row.badge,"RIGHT",0,0);row.far:SetJustifyH("RIGHT")
    -- Two symbols on the right (Florian 2026-10-12: a click on the row
    -- added it at once, Shift could not be reached): into the tour, or
    -- the tour cleared and led there now. A click on the row chooses it.
    row.add=UI:IconButton(row,"plus",function() P:Pick(i) end,"ghost");M.Size(row.add,28,28);M.Point(row.add,"RIGHT",row,"RIGHT",-40,0)
    row.go=UI:IconButton(row,"navigation",function() P:GoNow(i) end,"ghost");M.Size(row.go,28,28);M.Point(row.go,"RIGHT",row,"RIGHT",-8,0)
    UI:AttachTooltip(row.add,"Add to tour","Into your tour, after the stops in it (Enter).")
    UI:AttachTooltip(row.go,"Navigate now","Clears the tour, takes only this and leads you there at once (Shift+Enter).")
    -- A window or setting of the suite opens with a click.
    row:SetScript("OnClick",function()
        local m=P.found and P.found[i]
        if m and m.entry.kind=="action" then return P:Run(m) end
        P:Choose(i);P.input:SetFocus()
    end)
    row:SetScript("OnDoubleClick",function() P:Pick(i) end)
    row:SetScript("OnEnter",function() P:Choose(i) end)
    self.rows[i]=row
end
function P:Open(text)
    local w=self:Build()
    w:Show()
    self.input:SetText(text or "")
    self.input:SetFocus()
    self:Update()
end
function P:Toggle()
    local w=self:Build()
    if w:IsShown() then w:Hide() else self:Open() end
end
-- The matches for what is typed.
function P:Update()
    if not self.window then return end
    local text=self.input:GetText()
    local found,why=C:Search(text)
    local empty=not text:match("%S")
    if found and empty then found=C:Suggestions() end
    self.found=found or {}
    if not found then self.note:SetText(why)
    elseif not empty and #found==0 then self.note:SetText("Nothing found.")
    elseif empty then self.note:SetText("Suggestions   -   your tour: "..#C.Tour.stops.." stops")
    elseif found[1].fuzzy then self.note:SetText(#found.." found for a word or two spelled a little differently")
    else self.note:SetText(#found.." found") end
    self.chosen=math.min(math.max(1,self.chosen or 1),math.max(1,#self.found))
    for i,row in ipairs(self.rows) do
        local m=self.found[i]
        row:SetShown(m~=nil)
        if m then
            local e=m.entry
            local art=P.Art(e)
            if art then
                row.art:SetTexture(art)
                -- The icons' own border trimmed; other textures whole.
                if type(art)=="number" or tostring(art):find("^Interface\\Icons\\") then row.art:SetTexCoord(.08,.92,.08,.92) else row.art:SetTexCoord(0,1,0,1) end
            else setIcon(row.icon,P.Symbol(e)) end
            row.art:SetShown(art~=nil);row.icon:SetShown(art==nil)
            -- Where (Florian 2026-10-14): the zone of the place shown.
            local zone=m.place and e.kind~="zone" and e.kind~="category" and e.kind~="action" and e.kind~="bundle" and C:ZoneAt(m.place.cont,m.place.x,m.place.y)
            row.name:SetText(zone and (e.name.."  ("..zone..")") or e.name)
            local hostile=m.place and e.kind~="category" and e.kind~="action" and e.kind~="bundle" and C:Hostile(m.place.cont,m.place.x,m.place.y)
            row.warn:SetShown(hostile and true or false)
            -- Room for the warning after the name (Florian 2026-10-15: it lay
            -- over a shortened zone name).
            M.Size(row.name,hostile and WIDTH-272 or WIDTH-250,16)
            if hostile then
                row.warn:ClearAllPoints();M.Point(row.warn,"LEFT",row.name,"LEFT",math.min(row.name.GetStringWidth and row.name:GetStringWidth() or 0,WIDTH-272)+6,0)
                row.name:SetTextColor(color("warning"))
            else row.name:SetTextColor(color("text")) end
            local parts={KIND[e.kind] or e.kind}
            if e.detail and e.kind~="category" then parts[#parts+1]=e.detail end
            if #e.places>1 then parts[#parts+1]=#e.places.." places" end
            if e.kind=="category" and m.place then
                local at=C:ZoneAt(m.place.cont,m.place.x,m.place.y)
                parts[#parts+1]="nearest: "..m.place.name..(at and (" ("..at..")") or "")
            end
            if m.why=="recent" then parts[#parts+1]="lately" end
            if m.why=="done" then parts[#parts+1]="done" end
            row.detail:SetText(table.concat(parts,"  -  "))
            row.add:SetShown(e.kind~="action");row.go:SetShown(e.kind~="action")
            row.far:SetText(e.kind=="action" and "Open" or e.kind=="bundle" and (#e.entries.." stops") or m.yards and (m.yards>=1000 and string.format("%.1f km",m.yards/1000) or string.format("%d yd",m.yards)) or "elsewhere")
        end
    end
    -- As tall as its matches (four rows at least).
    M.Height(self.window,BAR+96+math.max(4,#self.found)*ROW)
    self:Choose(self.chosen)
end
function P:Choose(i)
    if not self.found or #self.found==0 then return end
    if i<1 then i=#self.found elseif i>#self.found then i=1 end
    self.chosen=i
    for k,row in ipairs(self.rows) do
        local on=k==i
        -- The chosen row: a soft accent wash, its symbol and distance lit.
        row.bg:SetVertexColor(color("accent",on and .1 or 0))
        row.mark:SetShown(on)
        if row.icon.SetColor then row.icon.colorRole=on and "accent" or "muted";row.icon:SetColor(color(on and "accent" or "muted")) end
        row.far:SetTextColor(color(on and "text" or "muted"))
    end
end
-- Enter: with Shift there at once, with Ctrl the tour starts, else into the tour.
function P:Enter()
    if IsControlKeyDown and IsControlKeyDown() then
        self.window:Hide()
        C.Tour:Navigate()
        return
    end
    if IsShiftKeyDown and IsShiftKeyDown() then return self:GoNow(self.chosen) end
    return self:Pick(self.chosen)
end
-- Navigate now: the tour cleared, only this in it, led there at once.
function P:GoNow(i)
    local m=self.found and self.found[i]
    if not m then return end
    if m.entry.kind=="action" then return self:Run(m) end
    if m.entry.kind=="bundle" then return self:Bundle(m,true) end
    C:Remember(m.entry)
    self.window:Hide()
    C:Print(string.format("Navigate now: \"%s\" (the tour cleared).",m.entry.name))
    C.Tour:Only({m.entry})
end
-- A window or setting: it opens, the palette closes.
function P:Run(m)
    self.window:Hide()
    local ok,err=pcall(m.entry.run)
    if not ok then C:Print("Could not open "..m.entry.name..": "..tostring(err)) end
end
-- Several at once (all done quests): each into the tour, the best order
-- on; navigated now: the tour only these, started.
function P:Bundle(m,go)
    local T=C.Tour
    T:Ensure()
    if go then
        T:SetBest(true)
        self.window:Hide()
        C:Print(string.format("Navigate now: %d stops (the tour cleared, best order).",#m.entry.entries))
        T:Only(m.entry.entries)
        return
    end
    for _,e in ipairs(m.entry.entries) do T:Add(e) end
    T:SetBest(true)
    C:Print(string.format("%d stops added to your tour (%d stops, best order).",#m.entry.entries,#T.stops))
    if go then self.window:Hide();T:Navigate();return end
    self.input:SetText("")
    self:Update()
    if T.Window then T.Window:Open() end
end
-- A match into the tour; the tour shows.
function P:Pick(i)
    local m=self.found and self.found[i]
    if not m then return end
    if m.entry.kind=="action" then return self:Run(m) end
    if m.entry.kind=="bundle" then return self:Bundle(m) end
    C:Remember(m.entry)
    C.Tour:Ensure()
    C.Tour:Add(m.entry)
    C:Print(string.format("\"%s\" added to your tour (%d stops).",m.entry.name,#C.Tour.stops))
    self.input:SetText("")
    self:Update()
    -- The tour shows what was added, beside the search, never over it
    -- (Florian 2026-10-12: it opened in the middle, on top of the search).
    local W=C.Tour.Window
    if not W then return end
    local was=W.window and W.window:IsShown()
    W:Open()
    if not was then self:Beside(W.window) end
    if self.window.Raise then self.window:Raise() end
end
-- A window put next to the search: right of it, or left where the screen
-- has no room on the right.
P.GAP=12
function P:Beside(other)
    local w=self.window
    if not (w and other) then return end
    local right=((w:GetLeft() or 0)+(w:GetWidth() or 0))*w:GetEffectiveScale()
    local width=(other:GetWidth() or 0)*other:GetEffectiveScale()
    local screen=(UIParent:GetWidth() or 0)*UIParent:GetEffectiveScale()
    other:ClearAllPoints()
    if screen>0 and right+width+P.GAP>screen then M.Point(other,"TOPRIGHT",w,"TOPLEFT",-P.GAP,0)
    else M.Point(other,"TOPLEFT",w,"TOPRIGHT",P.GAP,0) end
    -- Kept where it is, not tied to the search when that closes.
    local left,top=other:GetLeft(),other:GetTop()
    if left and top then other:ClearAllPoints();other:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top) end
end

-- Ctrl+Space opens the search (Florian 2026-10-11): set once, when the
-- search has no key yet and Ctrl+Space is free; never over another
-- binding (said in the chat then). Out of combat only.
P.KEY="CTRL-SPACE"
function P:DefaultKey()
    if type(BVCodexDB)~="table" then BVCodexDB={} end
    if BVCodexDB.keySet then return true end
    if InCombatLockdown and InCombatLockdown() then return false end
    BVCodexDB.keySet=true
    if C.Call("GetBindingKey","BVCODEX_SEARCH") then return true end
    local taken=C.Call("GetBindingAction",P.KEY)
    if type(taken)=="string" and taken~="" then
        C:Print("Ctrl+Space is taken ("..taken.."): give the Codex search a key in the key bindings (BV Addon Suite).")
        return true
    end
    if C.Call("SetBinding",P.KEY,"BVCODEX_SEARCH") then
        C.Call("SaveBindings",C.Call("GetCurrentBindingSet") or 1)
        C:Print("Ctrl+Space opens the Codex search (change it in the key bindings).")
    end
    return true
end
local keys=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED"}) do pcall(keys.RegisterEvent,keys,event) end
keys:SetScript("OnEvent",function(frame) if P:DefaultKey() then for _,event in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_REGEN_ENABLED"}) do pcall(frame.UnregisterEvent,frame,event) end end end)
P.keys=keys
-- In the minimap launcher's menu (Florian 2026-10-15: grouped).
if ns.Launcher and ns.Launcher.AddEntry then
    ns.Launcher:AddEntry({id="codexsearch",label="Codex search",order=40,group="navigation",icon="search",onClick=function() P:Open() end})
    ns.Launcher:AddEntry({id="codextour",label="Tour",order=41,group="navigation",icon="map-pinned",onClick=function() C.Tour:Ensure();C.Tour.Window:Open() end})
end

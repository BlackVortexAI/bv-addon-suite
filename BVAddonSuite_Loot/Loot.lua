local package,L=...
local ns=BVAddonSuiteCore
if not ns or not ns.RequireCore then
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(package.." requires BV Addon Suite - Core 0.8.89 or newer. Update Core; saved data is preserved.") end
    return
end
-- Own version, oldest compatible Core, Core interface generation.
if not ns:RequireCore(package,"0.8.92","0.8.96",1) then return end
-- Shared state of the loot package. Files below fill L (package-private table):
-- Rolls (data), RollFrame/Monitor/Results (views), Master (window), Sim.
L.ns=ns
ns.Loot=L
L.ready=true
L.ID="loot"
L.override={} -- Simulation replaces single Blizzard calls here; never _G.

L.DEFAULTS={enabled=false,
    -- Roll bars (native group loot and BV roll requests).
    -- rollKind/rollStats (0.8.90): item kind and primary stats left of the
    -- bar, each on its own; until 0.8.89 one switch, rollInfo (taken over).
    rolls=true,rollWidth=330,rollHeight=30,rollSpacing=6,rollGrow="UP",rollMax=8,rollKind=true,rollStats=true,rollKeep=false,
    rollQualityBar=true,rollBarColor="3D7BD9FF",hideBlizzard=true,
    -- Loot monitor toasts.
    monitor=true,monitorSelf=true,monitorGroup=true,monitorMoney=true,monitorSelfQuality=0,monitorGroupQuality=2,
    monitorDuration=6,monitorMax=8,monitorWidth=270,monitorGrow="UP",
    -- Roll results.
    results=true,resultsMode="toast",resultsDuration=15,resultsMax=5,resultsRows=5,resultsWidth=290,resultsGrow="DOWN",
    -- Tooltip mode: seconds a finished roll keeps its bar (0.8.90).
    resultsLinger=20,
    -- Master loot window and roll requests.
    master=true,masterAutoOpen=true,masterRollTime=30,masterOptions="need_greed",masterAnnounce=false,acceptRequests=true,
    -- Custom roll of the master looter: reason text and symbol.
    customEnabled=false,customText="",customSymbol="star",customAfter="",
    -- In-game style (0.8.91, Core 0.8.95 style families): own family or the
    -- suite's, optional roll bar background, opacity of toasts and cards (%).
    styleFamily="inherit",rollBackground=false,rollBgOpacity=75,rollBgOwnColor=false,rollBgColor="141414FF",panelOpacity=100}
local GROW={UP=true,DOWN=true}
-- tooltip (0.8.90): no cards; the overview shows on hovering a roll bar.
local MODES={toast=true,sticky=true,tooltip=true}
local function num(value,default,low,high,integer)
    if type(value)~="number" or value~=value then value=default end
    value=math.max(low,math.min(high,value))
    if integer then value=math.floor(value+.5) end
    return value
end
function L:Config()
    local cfg=ns.Settings:Module(self.ID)
    if cfg.rollKind==nil and cfg.rollInfo~=nil then cfg.rollKind,cfg.rollStats=cfg.rollInfo==true,cfg.rollInfo==true end
    for key,value in pairs(self.DEFAULTS) do if cfg[key]==nil then cfg[key]=value end end
    for _,key in ipairs({"rolls","rollKind","rollStats","rollKeep","rollQualityBar","hideBlizzard","monitor","monitorSelf","monitorGroup",
        "monitorMoney","results","master","masterAutoOpen","masterAnnounce","acceptRequests","customEnabled","rollBackground","rollBgOwnColor"}) do cfg[key]=cfg[key]==true end
    if L.CleanCustom then cfg.customText,cfg.customSymbol=L.CleanCustom(cfg.customText,cfg.customSymbol) end
    if type(cfg.customAfter)~="string" or not (cfg.customAfter=="" or L.OPTIONS[cfg.customAfter]) or cfg.customAfter=="pass" then cfg.customAfter="" end
    cfg.rollWidth=num(cfg.rollWidth,330,200,600,true);cfg.rollHeight=num(cfg.rollHeight,30,20,48,true)
    cfg.rollSpacing=num(cfg.rollSpacing,6,0,24,true);cfg.rollMax=num(cfg.rollMax,8,1,12,true)
    cfg.monitorSelfQuality=num(cfg.monitorSelfQuality,0,0,5,true);cfg.monitorGroupQuality=num(cfg.monitorGroupQuality,2,0,5,true)
    cfg.monitorDuration=num(cfg.monitorDuration,6,2,30);cfg.monitorMax=num(cfg.monitorMax,8,1,15,true)
    cfg.monitorWidth=num(cfg.monitorWidth,270,180,500,true)
    cfg.resultsDuration=num(cfg.resultsDuration,15,3,120);cfg.resultsMax=num(cfg.resultsMax,5,1,10,true)
    cfg.resultsRows=num(cfg.resultsRows,5,1,10,true);cfg.resultsWidth=num(cfg.resultsWidth,290,200,500,true)
    cfg.resultsLinger=num(cfg.resultsLinger,20,3,120,true)
    cfg.masterRollTime=num(cfg.masterRollTime,30,10,120,true)
    cfg.rollBgOpacity=num(cfg.rollBgOpacity,75,0,100,true);cfg.panelOpacity=num(cfg.panelOpacity,100,20,100,true)
    if cfg.styleFamily~="inherit" and not ns.Styles.families[cfg.styleFamily] then cfg.styleFamily="inherit" end
    if type(cfg.rollBgColor)~="string" or not cfg.rollBgColor:match("^%x%x%x%x%x%x%x%x$") then cfg.rollBgColor="141414FF" end
    for _,key in ipairs({"rollGrow","monitorGrow","resultsGrow"}) do if not GROW[cfg[key]] then cfg[key]=self.DEFAULTS[key] end end
    if not MODES[cfg.resultsMode] then cfg.resultsMode="toast" end
    if type(cfg.rollBarColor)~="string" or not cfg.rollBarColor:match("^%x%x%x%x%x%x%x%x$") then cfg.rollBarColor="3D7BD9FF" end
    if not self.PRESETS[cfg.masterOptions] then cfg.masterOptions="need_greed" end
    return cfg
end
function L:Active() return self.context~=nil end
-- Style family of the module (own or the suite's) and the roll bar padding
-- its optional background adds on every side.
function L:Family() return ns.Styles:Family(self.ID) end
-- The WoW gold frame (2 + inner line) needs more room than the thin borders.
function L.RollPad(cfg)
    if not cfg.rollBackground then return 0 end
    return select(2,L:Family()).border=="gold" and 6 or 4
end

-- Blizzard calls go through here so the simulation can stand in for single
-- calls (fake roll ids, fake loot window) without replacing globals.
function L.API(name)
    local f=L.override[name]
    if f then return f end
    f=_G[name]
    if f==nil and C_Item and (name=="GetItemInfo" or name=="GetItemStats" or name=="GetItemIconByID") then f=C_Item[name] end
    return f
end
function L.Call(name,...)
    local f=L.API(name)
    if type(f)~="function" then return nil end
    return f(...)
end

-- Secret values (restricted chat in instances) are never inspected.
function L.Secret(value) return issecretvalue and issecretvalue(value) or false end
function L.Readable(value) return value~=nil and not L.Secret(value) end

-- Player names: realm suffixes are dropped for display and comparison.
function L.Short(name)
    if type(name)~="string" or L.Secret(name) or name=="" then return nil end
    return (name:match("^([^%-]+)")) or name
end
-- WoW Forever characters carry a surname: UnitName hands it back as its
-- second value (retail: the realm) and the client's chat lines and loot
-- history show "First Last" (Florian's roll results 2026-10-07: "Loky" and
-- "Loky Lock" as two players). Units are named the same way here.
local separator=Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
L.SEPARATOR=separator
function L.UnitFull(unit)
    local name,surname=L.Call("UnitName",unit)
    name=L.Short(name)
    if not name then return nil end
    if type(surname)=="string" and not L.Secret(surname) and surname~="" then
        local tail=separator..surname
        if name:sub(-#tail)~=tail then name=name..tail end
    end
    return name
end
function L.Me() return L.UnitFull("player") or "?" end
-- The part before the surname, nil for a one-word name.
function L.FirstName(name)
    if type(name)~="string" then return nil end
    local at=name:find(separator,1,true)
    return at and at>1 and name:sub(1,at-1) or nil
end
L.CLASS_FALLBACK={1,.82,.6}
function L.ClassColor(class)
    local colors=CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c=class and colors and colors[class]
    if c then return c.r,c.g,c.b end
    return unpack(L.CLASS_FALLBACK)
end
function L.ClassOf(name)
    if name==nil then return nil end
    if name==L.Me() then local _,class=L.Call("UnitClass","player");return class end
    if L.roster and L.roster[name] then return L.roster[name] end
    local ok,_,class=pcall(L.API("UnitClass") or function() end,name)
    return ok and L.Readable(class) and class or nil
end
function L.Colored(name,class)
    local r,g,b=L.ClassColor(class or L.ClassOf(name))
    return string.format("|cff%02x%02x%02x%s|r",r*255,g*255,b*255,name or "?")
end
L.QUALITY={[0]={.62,.62,.62},[1]={1,1,1},[2]={.12,1,0},[3]={0,.44,.87},[4]={.64,.21,.93},[5]={1,.5,0},[6]={.9,.8,.5},[7]={0,.8,1}}
function L.QualityColor(quality)
    local c=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and c.r then return c.r,c.g,c.b end
    c=L.QUALITY[quality] or L.QUALITY[1]
    return c[1],c[2],c[3]
end

-- Global strings -> Lua patterns. %s, %d and positional %1$s; the matcher
-- returns captures in argument order, so "%2$s ... %1$s" works.
local cache={}
function L.Pattern(fmt)
    if type(fmt)~="string" or L.Secret(fmt) then return nil end
    local hit=cache[fmt]
    if hit then return hit.pattern,hit.order end
    local out,order,i,n={"^"},{},1,0
    while i<=#fmt do
        local c=fmt:sub(i,i)
        if c=="%" then
            local pos,kind=fmt:match("^%%(%d)%$([sd])",i)
            if pos then n=n+1;order[n]=tonumber(pos);i=i+4
            else
                kind=fmt:sub(i+1,i+1)
                if kind=="s" or kind=="d" then n=n+1;order[n]=n;i=i+2
                elseif kind=="%" then out[#out+1]="%%";i=i+2;kind=nil
                else out[#out+1]="%%";i=i+1;kind=nil end
            end
            if kind=="s" then out[#out+1]="(.-)" elseif kind=="d" then out[#out+1]="(%-?%d+)" end
        else
            out[#out+1]=c:find("[%(%)%.%+%-%*%?%[%]%^%$]") and "%"..c or c
            i=i+1
        end
    end
    out[#out+1]="$"
    hit={pattern=table.concat(out),order=order}
    cache[fmt]=hit
    return hit.pattern,hit.order
end
function L.Match(fmt,text)
    if type(text)~="string" or L.Secret(text) then return nil end
    local pattern,order=L.Pattern(fmt)
    if not pattern then return nil end
    local captures={text:match(pattern)}
    if #captures==0 then return nil end
    local args={}
    for index,position in ipairs(order) do args[position]=captures[index] end
    return true,args
end
-- Modern clients start loot roll lines with a loot history link, e.g.
-- LOOT_ROLL_NEED = "|HlootHistory:%d|h[Loot]|h: %s has selected Need for: %s"
-- (Florian's client 2026-10-06 prints "[Loot]: %s has selected Need for: %s").
-- Its number is no part of the line's meaning but shifts every argument, so
-- the leading link is removed from the template and from the chat line
-- before they are matched; lines without it pass unchanged.
function L.RollFormat(fmt)
    if type(fmt)~="string" then return fmt end
    return (fmt:gsub("^|H[^|]*|h%[[^%]]*%]|h:?%s*","",1))
end
function L.RollText(text)
    if type(text)~="string" or L.Secret(text) then return text end
    return (text:gsub("^|H[^|]*|h%[[^%]]*%]|h:?%s*","",1))
end
-- string.format with positional arguments (the client supports them; the
-- simulation builds chat lines from the same global strings).
function L.Format(fmt,...)
    local args,n={...},0
    return (fmt:gsub("%%(%d?)%$?([sd%%])",function(pos,kind)
        if kind=="%" then return "%" end
        if pos~="" then return tostring(args[tonumber(pos)]) end
        n=n+1;return tostring(args[n])
    end))
end

-- Items. Info may not be cached yet; callers retry on GET_ITEM_INFO_RECEIVED.
function L.ItemID(link)
    if type(link)=="number" then return link end
    if type(link)~="string" or L.Secret(link) then return nil end
    return tonumber(link:match("item:(%-?%d+)"))
end
function L.Item(link)
    local info={link=link,id=L.ItemID(link)}
    if not info.id then return info end
    local name,itemLink,quality,level,_,itemType,subType,_,equipLoc,icon,_,classID,subClassID,bindType=L.Call("GetItemInfo",link)
    if not L.Readable(name) then
        info.icon=L.Call("GetItemIconByID",info.id)
        return info,false
    end
    info.name,info.quality,info.level,info.type,info.subType,info.equipLoc,info.icon,info.classID,info.subClassID,info.bindType=
        name,quality,level,itemType,subType,equipLoc,icon,classID,subClassID,bindType
    if type(itemLink)=="string" then info.link=info.link or itemLink end
    return info,true
end
-- "Leder", "Einhandschwerter" ...: armor/weapon subtype, otherwise the type.
function L.ItemKind(info)
    if not info or not info.name then return nil end
    if info.classID==4 and info.subClassID==0 and info.equipLoc and _G[info.equipLoc] then return _G[info.equipLoc] end
    if (info.classID==2 or info.classID==4) and info.subType and info.subType~="" then return info.subType end
    return info.subType~="" and info.subType or info.type
end
local STATS={"ITEM_MOD_STRENGTH_SHORT","ITEM_MOD_AGILITY_SHORT","ITEM_MOD_STAMINA_SHORT","ITEM_MOD_INTELLECT_SHORT","ITEM_MOD_SPIRIT_SHORT"}
function L.ItemStats(link)
    local ok,stats=pcall(L.API("GetItemStats") or function() end,link)
    if not ok or type(stats)~="table" then return nil end
    local out={}
    for _,key in ipairs(STATS) do
        if stats[key] then out[#out+1]=_G[key] or key:match("ITEM_MOD_(.-)_SHORT"):lower() end
    end
    return #out>0 and table.concat(out," | ") or nil
end

-- Loot method: master looter detection for both API generations.
function L.IsMasterLooter()
    if L.override.IsMasterLooter then return L.override.IsMasterLooter() end
    local method,partyID,raidID,master
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        method,partyID,raidID=C_PartyInfo.GetLootMethod()
        local e=Enum and Enum.LootMethod
        master=e~=nil and method~=nil and (method==e.Masterlooter or method==e.MasterLooter)
    elseif GetLootMethod then
        method,partyID,raidID=GetLootMethod()
        master=method=="master"
    end
    if not master then return false end
    if raidID then return L.Call("UnitIsUnit","player","raid"..raidID)==true end
    return partyID==0
end
function L.InGroup(name)
    if not name then return false end
    if name==L.Me() or (L.roster and L.roster[name]) then return true end
    return (L.Call("UnitInRaid",name) or L.Call("UnitInParty",name)) and true or false
end
function L.GroupChannel()
    if L.Call("IsInRaid") then return "RAID" end
    if L.Call("IsInGroup") then return "PARTY" end
    return nil
end

-- Internal and public callbacks. Listener errors never break the loot flow.
L.listeners={}
function L:On(event,owner,callback) self.listeners[event]=self.listeners[event] or {};self.listeners[event][owner]=callback end
function L:Off(owner) for _,list in pairs(self.listeners) do list[owner]=nil end end
function L:Emit(event,...)
    local list=self.listeners[event]
    if not list then return end
    for owner,callback in pairs(list) do ns:Call("loot/"..event,callback,...) end
end

function L:Print(text) ns:Print("|cffe6bd83Loot:|r "..tostring(text)) end

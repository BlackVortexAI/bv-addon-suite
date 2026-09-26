-- Optional visible-result enrichment, separate from the proven name-only scan.
-- Native C++ failures cannot be caught by pcall. Only the bounded visible-result
-- controller requests enrichment; this adapter never enumerates the full index.
local _,ns=...
local Metadata={}; Metadata.__index=Metadata; ns.SpellMetadataModel=Metadata
local LIMIT=4096
local blocked={ [1251535]=true, [1251678]=true }
local function escape(text) return (text or ""):gsub("|","||") end
function Metadata.New(api,index)
    return setmetatable({api=api,index=index,attempts={},details={},texts={},textOrder={}},Metadata)
end
function Metadata:Paused() return self.api.InCombatLockdown and self.api.InCombatLockdown() or false end
function Metadata:Secret(value) return self.api.issecretvalue and self.api.issecretvalue(value) or false end
function Metadata:Number(value,integer)
    if self:Secret(value) or type(value)~="number" or value~=value or value<0 or value>=math.huge then return end
    if integer and (value<1 or value>2147483647 or value~=math.floor(value)) then return end
    return value
end
function Metadata:Text(value,limit)
    if not self:Secret(value) and type(value)=="string" and value~="" then return value:sub(1,limit or 256) end
end
function Metadata:Readable(value)
    return not self:Secret(value) and type(value)=="table" and (not self.api.canaccesstable or self.api.canaccesstable(value))
end
function Metadata:Cache()
    local current=self.index:Current(); if not current then return end
    if self.current~=current then self.current=current; self.attempts={}; self.details={}; self.texts={}; self.textOrder={}; self.requestedText={} end
    if current.spellMetadata==nil then current.spellMetadata={format=1,entries={},order={}} end
    local cache=current.spellMetadata
    if type(cache)~="table" or cache.format~=1 or type(cache.entries)~="table" or type(cache.order)~="table" then return end
    return cache
end
function Metadata:Get(id)
    local cache=self:Cache(); local data=cache and cache.entries[id]
    return type(data)=="table" and data or nil
end
function Metadata:Put(id,data)
    local cache=self:Cache(); if not cache then return end
    if not cache.entries[id] then
        if #cache.order>=LIMIT then cache.entries[table.remove(cache.order,1)]=nil end
        cache.order[#cache.order+1]=id
    end
    cache.entries[id]=data
end
function Metadata:Observe(items)
    for _,item in ipairs(items) do
        local id,icon=self:Number(item.spellID,true),self:Number(item.icon,true)
        if id and icon then
            local data=self:Get(id) or {}; data.observedIcon=icon
            self:Put(id,data)
        end
    end
end
function Metadata:Allowed(entry,consent)
    if consent~=true or not self.index:Status().ready then return end
    local id=self:Number(entry.value,true); if not id or entry.unverified then return end
    self:Cache()
    local name=self:Text(entry.name) or ""
    if blocked[id] or name:upper():find("(DNT)",1,true) then self.attempts[id]="blocked"; return end
    if self:Paused() then return end
    return id
end
function Metadata:Call(query,...)
    if type(query)~="function" then return end
    local ok,value=pcall(query,...)
    if ok and not self:Secret(value) then return value end
end
function Metadata:TooltipLines(raw,name,subtext)
    local ok,result=pcall(function()
        if not self:Readable(raw) or not self:Readable(raw.lines) then return end
        local out={lines={}}; local remaining=1200
        for i=1,16 do
            local line=raw.lines[i]; if not self:Secret(line) and line==nil then break end
            if self:Readable(line) then
                local left=self:Text(line.leftText,remaining); local right=self:Text(line.rightText,remaining)
                if i==1 and left==name then
                    -- Header-right may be duration or other context, not a rank.
                    if right and right~=subtext then out.lines[#out.lines+1]=escape(right); remaining=remaining-#right end
                else
                    local text=(left or "")..(left and right and "    " or "")..(right or "")
                    if text~="" then
                        text=text:sub(1,remaining); out.lines[#out.lines+1]=escape(text); remaining=remaining-#text
                        if remaining<=0 then out.lines[#out.lines+1]="..."; break end
                    end
                end
            end
        end
        if #out.lines>0 then return out end
    end)
    if ok then return result end
end
function Metadata:LoadText(entry,consent,observed)
    local id=self:Allowed(entry,consent); if not id then return end
    local spells,tips=self.api.C_Spell or {},self.api.C_TooltipInfo or {}
    local text={rank=self:Text(self:Call(spells.GetSpellSubtext,id)),source="Spell definition"}
    local raw
    if observed and observed.unit=="player" then
        if observed.auraInstanceID and type(tips.GetUnitAuraByAuraInstanceID)=="function" then
            raw=self:Call(tips.GetUnitAuraByAuraInstanceID,"player",observed.auraInstanceID,observed.filter)
        elseif observed.index then raw=self:Call(tips.GetUnitAura,"player",observed.index,observed.filter) end
    end
    local parsed=self:TooltipLines(raw,entry.name,text.rank)
    if parsed then text.source="Active player aura"
    else
        -- Preserve the selected ID instead of silently following its override.
        parsed=self:TooltipLines(self:Call(tips.GetSpellByID,id,false,true,true),entry.name,text.rank)
    end
    if parsed then text.lines=parsed.lines
    else
        local description=self:Text(self:Call(spells.GetSpellDescription,id),1200)
        if description then text.lines={escape(description)} end
    end
    text.pending=not text.lines or (type(spells.GetSpellSubtext)=="function" and not text.rank)
    if not self.texts[id] then
        if #self.textOrder>=256 then self.texts[table.remove(self.textOrder,1)]=nil end
        self.textOrder[#self.textOrder+1]=id
    end
    -- Session-only: descriptions and character-dependent values are not SavedVariables.
    self.texts[id]=text
    if text.pending and not self.requestedText then self.requestedText={} end
    if text.pending and not self.requestedText[id] then
        self.requestedText[id]=true; self:Call(spells.RequestLoadSpellData,id)
    end
end
function Metadata:Load(entry,consent)
    local id=self:Allowed(entry,consent); if not id or self.attempts[id] then return end
    local cached=self:Get(id)
    local query=self.api.C_Spell and self.api.C_Spell.GetSpellInfo
    if type(query)~="function" then self.attempts[id]="API unavailable"; self:LoadText(entry,consent); return end
    self.attempts[id]="unavailable"
    -- One requested result only. Never call GetSpellTexture or enumerate IDs here.
    local ok,raw=pcall(query,id)
    if not ok then self.attempts[id]="API error"; self:LoadText(entry,consent); return end
    local parsed,data=pcall(function()
        if not self:Readable(raw) then return end
        return {native=true,icon=self:Number(raw.iconID,true),originalIcon=self:Number(raw.originalIconID,true),
            resolvedID=self:Number(raw.spellID,true),castTime=self:Number(raw.castTime),
            minRange=self:Number(raw.minRange),maxRange=self:Number(raw.maxRange)}
    end)
    if parsed and data and (data.icon or data.originalIcon or data.castTime or data.minRange or data.maxRange) then
        self.details[id]=data
        self:Put(id,{native=true,icon=data.icon or (cached and cached.icon),originalIcon=data.originalIcon or (cached and cached.originalIcon),
            observedIcon=cached and cached.observedIcon})
        self.attempts[id]="loaded"
    end
    self:LoadText(entry,consent)
end
function Metadata:Row(entry,observed)
    local id=entry.value; local data=self:Get(id) or {}
    local observedIcon=observed and self:Number(observed.icon,true)
    local icon=observedIcon or self:Number(data.observedIcon,true)
    local iconSource=icon and (observedIcon and "Active player aura" or "Previously observed player aura")
    if not icon then
        icon=self:Number(data.originalIcon,true) or self:Number(data.icon,true)
        if icon then iconSource="Client spell metadata" end
    end
    local category=observed and (observed.filter=="HELPFUL" and "Buff" or observed.filter=="HARMFUL" and "Debuff")
    local text=self.texts[id] or {}; local live=self.details[id] or {}
    local lines={}
    if text.lines then
        for _,line in ipairs(text.lines) do lines[#lines+1]=line end
        lines[#lines+1]=""; lines[#lines+1]="Source: "..text.source
    else lines[#lines+1]="Game description unavailable or still loading. Hover again to retry." end
    lines[#lines+1]="Spell ID: "..id
    lines[#lines+1]="Aura type: "..(category or "Unknown")
    if observed then
        local stacks,duration=self:Number(observed.stacks),self:Number(observed.duration)
        lines[#lines+1]="Stacks: "..(stacks and tostring(stacks) or "Unavailable")
        lines[#lines+1]="Duration: "..(duration and (duration==0 and "No timed expiration" or string.format("%g s",duration)) or "Unavailable")
        lines[#lines+1]="Aura values are a snapshot. Use Refresh auras to update."
    end
    local cast,min,max=self:Number(live.castTime),self:Number(live.minRange),self:Number(live.maxRange)
    if not text.lines and cast then lines[#lines+1]="Cast time (snapshot): "..(cast==0 and "Instant" or string.format("%g s",cast/1000)) end
    if not text.lines and min and max then lines[#lines+1]=string.format("Range (snapshot): %g - %g yd",min,max) end
    local resolved=self:Number(live.resolvedID,true)
    if resolved and resolved~=id then lines[#lines+1]="Client metadata resolves to Spell ID: "..resolved end
    lines[#lines+1]="Icon: "..(icon and (icon.." / "..iconSource) or "Unavailable")
    local status=self.attempts[id]
    if blocked[id] or (entry.name or ""):upper():find("(DNT)",1,true) then
        lines[#lines+1]="Native lookup blocked: known crash-related or development spell."
    elseif entry.unverified then lines[#lines+1]="Unverified ID: no native lookup performed."
    elseif not data.native then lines[#lines+1]="Native details: "..(status or "Not loaded yet; visible results load automatically.") end
    local label=escape(entry.name)..(text.rank and (" - "..escape(text.rank)) or "").."  ["..id.."]"
    return {value=id,name=entry.name,unverified=entry.unverified,icon=icon,rank=text.rank,textPending=text.pending,
        label=label,summary=category and (category.." / active player aura") or
            (icon and "Spell / icon available" or "Spell / icon unavailable"),origin=table.concat(lines,"\n")}
end

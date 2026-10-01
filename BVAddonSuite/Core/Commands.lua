local _,ns=...
local Commands={aliases={}}
ns.Commands=Commands
local known={exp="BVAddonSuite_Experience",xp="BVAddonSuite_Experience",experience="BVAddonSuite_Experience",rep="BVAddonSuite_Reputation",reputation="BVAddonSuite_Reputation",aura="BVAddonSuite_AuraStudio",aurastudio="BVAddonSuite_AuraStudio",bags="BVAddonSuite_Bags",micro="BVAddonSuite_MicroMenu",loot="BVAddonSuite_Loot"}
function Commands:Register(alias,id,page,open)
    assert(not self.aliases[alias],"Duplicate command alias")
    self.aliases[alias]={id=id,page=page,open=open}
end
function Commands:RegisterAction(alias,callback)
    assert(type(alias)=="string" and alias:match("^[a-z]+$") and type(callback)=="function","Invalid command action")
    assert(not self.aliases[alias],"Duplicate command alias")
    self.aliases[alias]={run=callback}
end
-- Opt-in, session-only counters. Never record unit names, payloads or native values.
function ns:RecordDisplayInput(stage)
    if self.Performance and self.Performance.active then self.Performance:Count("input_"..stage) end
    local counts=self.displayInputCounts
    if counts then counts[stage]=(counts[stage] or 0)+1 end
end
Commands:RegisterAction("clickdebug",function(action)
    if action=="on" then ns.displayInputCounts={};ns:Print("Click counters enabled/reset. Use /bv clickdebug status, then /bv clickdebug off.")
    elseif action=="off" then ns.displayInputCounts=nil;ns:Print("Click counters disabled.")
    elseif action=="status" then
        local counts=ns.displayInputCounts
        if not counts then ns:Print("Click counters are off. Use /bv clickdebug on.");return end
        local out={}
        for _,key in ipairs({"down","up","click","queued","processed","cancelled","full"}) do out[#out+1]=key.."="..tostring(counts[key] or 0) end
        ns:Print(table.concat(out," / "))
    else ns:Print("Use /bv clickdebug [on|status|off]") end
end)
function Commands:Run(message)
    local command,action=(message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command=="" then ns.Config:Toggle(); return end
    local module=self.aliases[command]
    if not module then
        if known[command] then ns:Print(known[command].." is not loaded. Install/enable it in WoW's AddOns list together with BV Addon Suite - Core, then reload.")
        else ns:Print("/bv | /bv exp [on|off] | /bv rep [on|off] | /bv perf [start|report]") end
        return
    end
    if module.run then module.run(action); return end
    if action=="on" or action=="off" then
        ns.Modules:SetEnabled(module.id,action=="on")
        ns:Print(command..": "..ns.Modules.records[module.id].state)
        ns.Config:Refresh()
    elseif action=="" then if module.open then module.open() else ns.Config:OpenPage(module.page) end
    else ns:Print("Use /bv "..command.." [on|off]") end
end

local _,L=...
if not L.ready then return end
-- Blizzard's own floating combat text, optionally switched off while the module
-- runs. The values found before are kept in BVCombatTextDB.blizzard and put
-- back when the option or the module is turned off, also after a crash or
-- /reload without a clean stop (next login with the module off).
local ns=L.ns
-- Two independent parts: enableFloatingCombatText is the text at your own
-- character (damage and heals you take, option hideBlizzardSelf); the *_v2
-- pair are the numbers over units you hit or heal (option hideBlizzard).
-- Blizzard's numbers over enemies are your own only: the client knows the
-- attacker, addons do not (combat log closed), so keeping them can be useful.
local B={SELF={"enableFloatingCombatText"},ENEMY={"floatingCombatTextCombatDamage_v2","floatingCombatTextCombatHealing_v2"}}
B.CVARS={B.SELF[1],B.ENEMY[1],B.ENEMY[2]}
L.Blizzard=B

local function get(name)
    local f=C_CVar and C_CVar.GetCVar or GetCVar
    if type(f)~="function" then return nil end
    local ok,value=pcall(f,name)
    return ok and type(value)=="string" and value or nil
end
local function set(name,value)
    local f=C_CVar and C_CVar.SetCVar or SetCVar
    if type(f)~="function" then return false end
    local ok,result=pcall(f,name,value)
    return ok and result~=false
end
-- Changes wait for the end of combat.
function B:Later(callback)
    if not (InCombatLockdown and InCombatLockdown()) then callback();return end
    self.pending=callback
    ns.Events:Subscribe(self,"PLAYER_REGEN_ENABLED",function()
        ns.Events:Release(self)
        local f=self.pending;self.pending=nil
        if f then f() end
    end)
end
-- hide: set of CVar names to switch off; every other saved one is given back.
function B:Set(hide)
    local db=L:DB()
    local saved=type(db.blizzard)=="table" and db.blizzard or {}
    for _,name in ipairs(self.CVARS) do
        local value=get(name)
        if hide[name] then
            if value then
                if saved[name]==nil then saved[name]=value end
                if value~="0" then set(name,"0") end
            end
        elseif saved[name]~=nil then
            if type(saved[name])=="string" and value~=nil then set(name,saved[name]) end
            saved[name]=nil
        end
    end
    db.blizzard=next(saved) and saved or nil
end
function B:Restore() self:Set({}) end
function B:Apply()
    self:Later(function()
        local hide={}
        if L:Active() then
            local cfg=L:Config()
            if cfg.hideBlizzardSelf then for _,name in ipairs(self.SELF) do hide[name]=true end end
            if cfg.hideBlizzard then for _,name in ipairs(self.ENEMY) do hide[name]=true end end
        end
        self:Set(hide)
    end)
end
function B:Enable(context)
    self:Apply()
    context:Defer(function() self:Later(function() self:Restore() end) end)
end
-- Values left from a session that ended without a clean stop.
local function leftover()
    if not L:Active() then B:Later(function() if not L:Active() then B:Restore() end end) end
end
if IsLoggedIn and IsLoggedIn() then leftover()
else
    local login={}
    ns.Events:Subscribe(login,"PLAYER_LOGIN",function() ns.Events:Release(login);leftover() end)
end

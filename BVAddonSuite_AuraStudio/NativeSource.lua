-- Native-only render adapter. Raw values live only in this call stack; callers
-- receive plain status, never health values or duration objects.
local _,A=...
if A.blocked then return end
local N={}; A.NativeSource=N
function N.New(api)
    local self={}
    local function secret(value) return api.issecretvalue and api.issecretvalue(value) end
    local function number(value,maximum)
        if secret(value) then return true end
        return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
            and value>=0 and (not maximum or value>0)
    end
    function self:BindHealth(widget,unit)
        unit=unit or "player"
        if not A.UnitSource.ValidToken(unit) then return false,"unavailable" end
        if not api.UnitHealth or not api.UnitHealthMax or not widget.SetValue or not widget.SetMinMaxValues then return false,"unsupported" end
        local ok,status=pcall(function()
            local current=api.UnitHealth(unit); local maximum=api.UnitHealthMax(unit)
            if not number(current) or not number(maximum,true) then return "unavailable" end
            widget:SetMinMaxValues(0,maximum); widget:SetValue(current)
            return "bound"
        end)
        return ok and status=="bound",ok and status or "error"
    end
    function self:BindCooldown(widget,spellID)
        if not api.C_Spell or not api.C_Spell.GetSpellCooldownDuration or not widget.SetCooldownFromDurationObject then return false,"unsupported" end
        if type(spellID)~="number" or spellID<1 or spellID>2147483647 or spellID~=math.floor(spellID) then return false,"unavailable" end
        local ok,status=pcall(function()
            local duration=api.C_Spell.GetSpellCooldownDuration(spellID)
            if not secret(duration) and duration==nil then return "unavailable" end
            widget:SetCooldownFromDurationObject(duration)
            return "bound"
        end)
        return ok and status=="bound",ok and status or "error"
    end
    function self:ClearHealth(widget)
        if widget.SetMinMaxValues and widget.SetValue then return pcall(function() widget:SetMinMaxValues(0,1); widget:SetValue(0) end) end
        return false
    end
    function self:ClearCooldown(widget)
        if widget.Clear then return pcall(widget.Clear,widget) end
        return false
    end
    return self
end

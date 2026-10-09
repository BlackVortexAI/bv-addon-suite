local _,ns=...
-- Blizzard's info line (UI_INFO_MESSAGE in UIErrorsFrame), shared by the
-- packages that replace some of its lines with their own notifications:
-- Quest leaves out objective progress, Map leaves out "Discovered". While at
-- least one filter is registered, Core takes the event from the frame and
-- hands every other message on to Blizzard's own handler; with the last
-- filter gone the frame gets its event back. One owner, so two packages
-- never fight over the frame.
local I={filters={},owner={}}
ns.InfoMessages=I

-- fn(messageType, message) returns true when its package shows the line itself.
function I:Filter(key,fn)
    assert(type(key)=="string" and type(fn)=="function","Invalid info message filter")
    self.filters[key]=fn
    self:Update()
end
function I:Release(key)
    self.filters[key]=nil
    self:Update()
end
function I:Taken(messageType,message)
    for _,fn in pairs(self.filters) do
        local ok,taken=pcall(fn,messageType,message)
        if ok and taken then return true end
    end
    return false
end
function I:Update()
    local frame=rawget(_G,"UIErrorsFrame")
    local need=next(self.filters)~=nil
    if need==(self.taken==true) then return end
    if need then
        if not (frame and frame.UnregisterEvent and frame.GetScript) then return end
        local handler=frame:GetScript("OnEvent")
        if not handler or not pcall(frame.UnregisterEvent,frame,"UI_INFO_MESSAGE") then return end
        self.handler,self.taken=handler,true
        ns.Events:Subscribe(self.owner,"UI_INFO_MESSAGE",function(_,messageType,message,...)
            if I:Taken(messageType,message) then return end
            pcall(frame:GetScript("OnEvent") or I.handler,frame,"UI_INFO_MESSAGE",messageType,message,...)
        end)
    else
        ns.Events:Release(self.owner)
        if frame then pcall(frame.RegisterEvent,frame,"UI_INFO_MESSAGE") end
        self.taken=false
    end
end

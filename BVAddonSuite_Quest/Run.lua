local _,Q=...
if not Q.ready then return end
-- Dungeon run (party instances, modelled on Horizon Focus): time inside, XP
-- and gold gained with their rates per hour, bosses killed. The run survives
-- a reload and a corpse run: it is kept while you are outside and continues
-- when you enter the same instance again within an hour. Read only.
local R={}
Q.Run=R
local Call,Readable=Q.Call,Q.Readable
local function now() return time and time() or math.floor(GetTime()) end
local function number(value) return type(value)=="number" and Readable(value) end

function R:State()
    local cfg=Q:Config()
    if type(cfg.run)~="table" then cfg.run=nil end
    return cfg.run
end
-- Name and id of the party instance you are in, nil outside one.
function R:Instance()
    local name,kind,_,_,_,_,_,id=Call("GetInstanceInfo")
    if kind=="party" and type(name)=="string" then return name,id end
    return nil
end
function R:Baseline()
    self.lastXP,self.lastMax,self.lastMoney=Call("UnitXP","player"),Call("UnitXPMax","player"),Call("GetMoney")
end
function R:Check()
    local name,id=self:Instance()
    self.inside=name~=nil
    if name then
        local run,t=self:State(),now()
        if not run or run.id~=id or run.name~=name or t-(run.seen or 0)>3600 then
            run={name=name,id=id,started=t,seen=t,xp=0,money=0,bosses={}}
            Q:Config().run=run
        end
        run.seen=t
    end
    self:Baseline()
    Q:Emit("Run")
end
function R:XP()
    local xp,max=Call("UnitXP","player"),Call("UnitXPMax","player")
    local run=self.inside and self:State()
    if run and number(xp) and number(self.lastXP) then
        -- A level-up wraps the counter: the rest of the old level counts too.
        local delta=xp>=self.lastXP and xp-self.lastXP or ((number(self.lastMax) and self.lastMax or self.lastXP)-self.lastXP)+xp
        if delta>0 then run.xp=run.xp+delta;run.seen=now() end
    end
    self.lastXP,self.lastMax=xp,max
    if run then Q:Emit("Run") end
end
function R:Money()
    local money=Call("GetMoney")
    local run=self.inside and self:State()
    if run and number(money) and number(self.lastMoney) and money>self.lastMoney then run.money=run.money+(money-self.lastMoney);run.seen=now() end
    self.lastMoney=money
    if run then Q:Emit("Run") end
end
function R:Boss(_,name,_,_,success)
    local run=self.inside and self:State()
    if run and success==1 and type(name)=="string" then run.bosses[#run.bosses+1]=name;Q:Emit("Run") end
end
function R:Restart()
    Q:Config().run=nil
    self:Check()
end
-- Display values: elapsed seconds, XP and gold with their per-hour rates, and
-- the time to the next level at this pace.
function R:Values()
    local run=self:State()
    if not run then return nil end
    local elapsed=math.max(1,now()-run.started)
    local xpRate,moneyRate=run.xp/elapsed*3600,run.money/elapsed*3600
    local eta
    local xp,max=Call("UnitXP","player"),Call("UnitXPMax","player")
    if number(xp) and number(max) and run.xp>0 then eta=(max-xp)/(run.xp/elapsed) end
    return {name=run.name,elapsed=elapsed,xp=run.xp,money=run.money,xpRate=xpRate,moneyRate=moneyRate,eta=eta,bosses=run.bosses}
end
function R:Enable(context)
    local function check() R:Check() end
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA"}) do pcall(context.Subscribe,context,event,check) end
    pcall(context.Subscribe,context,"PLAYER_XP_UPDATE",function() R:XP() end)
    pcall(context.Subscribe,context,"PLAYER_MONEY",function() R:Money() end)
    pcall(context.Subscribe,context,"ENCOUNTER_END",function(_,...) R:Boss(...) end)
    self:Check()
end

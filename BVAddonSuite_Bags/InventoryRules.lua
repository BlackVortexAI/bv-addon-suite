-- BV Bags inventory prototype. Compile user text once; never execute it.
local ns=BVAddonSuiteCore
if not (ns and ns.Bags) then return end
local R={}
ns.Bags.InventoryRules=R
local function trim(s) return s:match("^%s*(.-)%s*$") end
local numbers={id=true,quality=true,count=true,bag=true,level=true,class=true,subclass=true,bound=true}
local strings={name=true,type=true,subtype=true,equip=true}
local types={[12]="quest",[2]="gear",[4]="gear",[0]="use",[7]="trade",[5]="reagent"}
-- '*' is the only wildcard. Ordered literal fragments use plain searches:
-- no Lua-pattern backtracking, including for malformed user input.
local function textTest(value)
    value=value:lower()
    if not value:find("*",1,true) then return function(s) return s:find(value,1,true)~=nil end end
    local parts={}
    for p in value:gmatch("[^*]+") do parts[#parts+1]=p end
    local head,tail=value:sub(1,1)~="*",value:sub(-1)~="*"
    return function(s)
        local at=1
        for i,p in ipairs(parts) do
            local a,b
            if i==#parts and tail then
                a=#s-#p+1;b=#s
                if a<at or s:sub(a)~=p then return false end
            else a,b=s:find(p,at,true) end
            if not a or (i==1 and head and a~=1) then return false end
            at=b+1
        end
        return true
    end
end
local function predicate(raw)
    local s=trim(raw)
    local neg=s:sub(1,1)=="!"
    if neg then s=trim(s:sub(2)) end
    local k,op,v=s:match("^([%a]+)%s*([:<>!=]+)%s*(.-)%s*$")
    if not k or v=="" then return nil,"Expected field:value or field>=number" end
    k=k:lower()
    local test
    if numbers[k] then
        local n=tonumber(v)
        if not n or not v:match("^%d+$") then return nil,k.." needs a whole number" end
        if op==":" or op=="=" then test=function(x) return x==n end
        elseif op=="!=" then test=function(x) return x~=n end
        elseif op==">=" then test=function(x) return x>=n end
        elseif op=="<=" then test=function(x) return x<=n end
        elseif op==">" then test=function(x) return x>n end
        elseif op=="<" then test=function(x) return x<n end
        else return nil,"Unknown number comparison" end
    elseif k=="family" and op==":" then
        return function(item) return item.class~=nil and ((types[item.class] or "misc")==v)~=neg end
    elseif strings[k] and op==":" then test=textTest(v)
    else return nil,"Unknown field or operator: "..k..op end
    return function(item)
        local x=item[k]
        if x==nil then return false end -- missing data cannot satisfy a negation
        if strings[k] then x=x:lower() end
        return test(x)~=neg
    end
end
function R.Compile(source)
    if type(source)~="string" or #source>240 then return nil,"Limit: 240 bytes" end
    local groups,count={},0
    for group in (source.."|"):gmatch("(.-)|") do
        local terms={}
        for term in (group..";"):gmatch("(.-);") do
            count=count+1
            if count>16 then return nil,"Limit: 16 conditions" end
            local test,err=predicate(term)
            if not test then return nil,"Condition "..count..": "..err end
            terms[#terms+1]=test
        end
        groups[#groups+1]=terms
    end
    return function(item)
        for _,terms in ipairs(groups) do
            local yes=true
            for _,test in ipairs(terms) do if not test(item) then yes=false;break end end
            if yes then return true end
        end
        return false
    end
end
R.groups={
    {key="quest",name="Quest",color="eab95a",icon=134939},
    {key="gear",name="Equipment",color="80a8df",icon=135147},
    {key="use",name="Consumables",color="84c28b",icon=134829},
    {key="trade",name="Materials",color="bd98d9",icon=134400},
    {key="reagent",name="Reagents",color="8ccccb",icon=134075},
    {key="misc",name="Other",color="b4aaa0",icon=133633},
}
function R.Classify(item,manual,rules)
    if item.id and manual[item.id] then return manual[item.id],"Item assignment" end
    for _,r in ipairs(rules) do if r.test and r.test(item) then return r.key,r.source end end
    return types[item.class] or "misc","Item class"
end
-- Different categories can have different slot pitches. Try the left edge
-- and the right edge of each placed card, then take the lowest free position.
R.sizes={24,28,32,36,40,48,54}
function R.Pack(groups,width,defaultSize,sizes)
    local placed,depth={},0
    for _,g in ipairs(groups) do
        local size=sizes and sizes[g.key] or defaultSize
        local pitch=size+4
        local columns=math.max(1,math.floor(width/pitch))
        g.slot=size
        g.cols=math.min(columns,#g.items,math.max(2,math.ceil(math.sqrt(#g.items*1.8))))
        if g.cols>0 then
            local span=math.max(g.cols*pitch,math.min(width,g.headingWidth or 0))
            g.width=span
            local bestX,bestY=0,math.huge
            for edge=0,#placed do
                local x=edge==0 and 0 or placed[edge].right
                if x+span<=width or edge==0 then
                    local y=0
                    for _,card in ipairs(placed) do
                        if x<card.right and x+span>card.left then y=math.max(y,card.bottom) end
                    end
                    if y<bestY or (y==bestY and x<bestX) then bestX,bestY=x,y end
                end
            end
            g.x,g.y=bestX,bestY
            local bottom=bestY+18+math.ceil(#g.items/g.cols)*pitch+4
            placed[#placed+1]={left=bestX,right=bestX+span,bottom=bottom}
            depth=math.max(depth,bottom)
        end
    end
    return depth
end

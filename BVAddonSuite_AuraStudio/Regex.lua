-- Bounded regular expressions without backtracking (Pike VM, RE2 style).
-- Lua patterns run in C and cannot be interrupted; this engine counts every
-- step, so a pathological pattern yields "unknown" instead of freezing.
-- Supported: literals, . [...] [^...] \d\D\w\W\s\S \b\B ^ $ ( ) (?: ) |
-- * + ? {n} {n,} {n,m} and lazy variants. Not supported: backreferences,
-- lookaround. Text is matched by UTF-8 code points.
local _,A=...
if A.blocked then return end
local R={maxPattern=256,maxText=1024,maxProgram=4000,maxRepeat=100,maxSteps=100000,maxGroups=9,cacheLimit=64};A.Regex=R
R.cache={};R.cacheSize=0
local function decode(s)
    local cps,starts,i,n={},{},1,#s
    while i<=n do
        local c=s:byte(i);local cp,len
        if c<128 then cp,len=c,1
        elseif c>=194 and c<224 and i+1<=n then
            local c2=s:byte(i+1);if c2>=128 and c2<192 then cp,len=(c-192)*64+(c2-128),2 end
        elseif c>=224 and c<240 and i+2<=n then
            local c2,c3=s:byte(i+1,i+2);if c2>=128 and c2<192 and c3>=128 and c3<192 then cp,len=((c-224)*64+(c2-128))*64+(c3-128),3 end
        elseif c>=240 and c<245 and i+3<=n then
            local c2,c3,c4=s:byte(i+1,i+3)
            if c2>=128 and c2<192 and c3>=128 and c3<192 and c4>=128 and c4<192 then cp,len=(((c-240)*64+(c2-128))*64+(c3-128))*64+(c4-128),4 end
        end
        if not cp then cp,len=c,1 end -- invalid byte: matched as itself
        cps[#cps+1]=cp;starts[#starts+1]=i;i=i+len
    end
    starts[#cps+1]=n+1
    return cps,starts
end
R.Decode=decode
-- ASCII and Latin-1 capitals, the same range as Text Compare.
local function lower(cp) if (cp>=65 and cp<=90) or (cp>=192 and cp<=222 and cp~=215) then return cp+32 end return cp end
local function upper(cp) if (cp>=97 and cp<=122) or (cp>=224 and cp<=254 and cp~=247) then return cp-32 end return cp end
local function isWord(cp) return cp~=nil and ((cp>=48 and cp<=57) or (cp>=65 and cp<=90) or (cp>=97 and cp<=122) or cp==95) end
local function isDigit(cp) return cp>=48 and cp<=57 end
local function isSpace(cp) return cp==32 or (cp>=9 and cp<=13) end
local classes={d=isDigit,w=isWord,s=isSpace}
-- Parser: pattern code points -> tree. Errors are plain messages.
local function parse(p,ignoreCase)
    local pos,groups=1,0
    local function peek(k) return p[pos+(k or 0)] end
    local function fail(msg) error({regex=msg},0) end
    local function ch(s) return s:byte() end
    local function literal(cp)
        if ignoreCase then local a,b=lower(cp),upper(cp);return function(c) return c==a or c==b end end
        return function(c) return c==cp end
    end
    local function escapeClass(cp)
        local name=string.char(cp):lower();local f=classes[name]
        if f and string.char(cp)~=name then return function(c) return not f(c) end end
        return f
    end
    local simple={[ch"t"]=9,[ch"n"]=10,[ch"r"]=13,[ch"f"]=12,[ch"v"]=11}
    local function escaped()
        local cp=peek();if not cp then fail("Pattern ends with a backslash") end
        pos=pos+1
        if cp>=49 and cp<=57 then fail("Backreferences are not supported") end
        if simple[cp] then return "cp",simple[cp] end
        local f=cp<128 and escapeClass(cp);if f then return "fn",f end
        if (cp>=65 and cp<=90) or (cp>=97 and cp<=122) then fail("Unknown escape \\"..string.char(cp)) end
        return "cp",cp
    end
    local function class()
        local negate=false;if peek()==ch"^" then negate=true;pos=pos+1 end
        local tests,first={},true
        while true do
            local cp=peek();if not cp then fail("Missing ]") end
            if cp==ch"]" and not first then pos=pos+1;break end
            first=false;pos=pos+1
            local kind,value
            if cp==ch"\\" then kind,value=escaped() else kind,value="cp",cp end
            if kind=="fn" then tests[#tests+1]=value
            elseif peek()==ch"-" and peek(1) and peek(1)~=ch"]" then
                pos=pos+1;local hi=peek();pos=pos+1
                if hi==ch"\\" then local k,v=escaped();if k~="cp" then fail("Invalid class range") end;hi=v end
                if hi<value then fail("Invalid class range") end
                local lo=value
                tests[#tests+1]=function(c) return c>=lo and c<=hi end
            else local v=value;tests[#tests+1]=function(c) return c==v end end
        end
        local function any(c) for _,t in ipairs(tests) do if t(c) then return true end end return false end
        local function match(c)
            local hit=any(c) or (ignoreCase and (any(lower(c)) or any(upper(c))))
            if negate then return not hit end
            return hit
        end
        return match
    end
    local alternation
    local function atom()
        local cp=peek()
        if cp==ch"(" then
            pos=pos+1
            local capture=true
            if peek()==ch"?" then
                if peek(1)==ch":" then capture=false;pos=pos+2
                else fail("Lookaround and group flags are not supported") end
            end
            local index
            if capture then groups=groups+1;index=groups;if groups>R.maxGroups then fail("At most "..R.maxGroups.." capture groups") end end
            local body=alternation()
            if peek()~=ch")" then fail("Missing )") end
            pos=pos+1
            return {t="group",index=index,body=body}
        elseif cp==ch"[" then pos=pos+1;return {t="char",test=class()}
        elseif cp==ch"." then pos=pos+1;return {t="char",test=function(c) return c~=10 end}
        elseif cp==ch"^" then pos=pos+1;return {t="assert",kind="bol"}
        elseif cp==ch"$" then pos=pos+1;return {t="assert",kind="eol"}
        elseif cp==ch"\\" then
            pos=pos+1
            if peek()==ch"b" or peek()==ch"B" then local k=peek()==ch"b" and "word" or "nonword";pos=pos+1;return {t="assert",kind=k} end
            local kind,value=escaped()
            if kind=="fn" then return {t="char",test=value} end
            return {t="char",test=literal(value)}
        elseif cp==ch"*" or cp==ch"+" or cp==ch"?" then fail("Nothing to repeat")
        end
        pos=pos+1;return {t="char",test=literal(cp)}
    end
    local function number()
        local start,value=pos,0
        while peek() and isDigit(peek()) do value=value*10+peek()-48;pos=pos+1 end
        if pos==start then return nil end
        return value
    end
    local function quantifier(node)
        local cp=peek();local min,max
        if cp==ch"*" then min,max=0,nil;pos=pos+1
        elseif cp==ch"+" then min,max=1,nil;pos=pos+1
        elseif cp==ch"?" then min,max=0,1;pos=pos+1
        elseif cp==ch"{" then
            local save=pos;pos=pos+1
            local a=number()
            if a and peek()==ch"}" then min,max=a,a;pos=pos+1
            elseif a and peek()==ch"," then
                pos=pos+1;local b=number()
                if peek()==ch"}" then min,max=a,b;pos=pos+1 else pos=save;return node end
            else pos=save;return node end -- literal {
            if max and max<min then fail("Invalid repeat {"..min..","..max.."}") end
            if min>R.maxRepeat or (max and max>R.maxRepeat) then fail("Repeat counts above "..R.maxRepeat.." are not supported") end
        else return node end
        if node.t=="assert" then fail("Nothing to repeat") end
        local greedy=true;if peek()==ch"?" then greedy=false;pos=pos+1 end
        if peek()==ch"*" or peek()==ch"+" or (peek()==ch"?" and greedy==false) then fail("Nested quantifier") end
        return {t="repeat",min=min,max=max,greedy=greedy,body=node}
    end
    local function concat()
        local list={}
        while peek() and peek()~=ch"|" and peek()~=ch")" do list[#list+1]=quantifier(atom()) end
        return {t="concat",list=list}
    end
    alternation=function()
        local list={concat()}
        while peek()==ch"|" do pos=pos+1;list[#list+1]=concat() end
        if #list==1 then return list[1] end
        return {t="alt",list=list}
    end
    local tree=alternation()
    if peek()==ch")" then fail("Unmatched )") end
    return tree,groups
end
-- Tree -> instructions: char(test), split(x,y) with x preferred, jmp, save, assert, match.
local function compile(tree)
    local prog={}
    local function emit(ins) prog[#prog+1]=ins;if #prog>R.maxProgram then error({regex="Pattern is too complex"},0) end;return #prog end
    local gen
    gen=function(node)
        if node.t=="char" then emit({op="char",test=node.test})
        elseif node.t=="assert" then emit({op="assert",kind=node.kind})
        elseif node.t=="concat" then for _,n in ipairs(node.list) do gen(n) end
        elseif node.t=="group" then
            if node.index then emit({op="save",n=node.index*2}) end
            gen(node.body)
            if node.index then emit({op="save",n=node.index*2+1}) end
        elseif node.t=="alt" then
            local jumps={}
            for i,n in ipairs(node.list) do
                if i<#node.list then
                    local split=emit({op="split"})
                    prog[split].x=#prog+1;gen(n);jumps[#jumps+1]=emit({op="jmp"});prog[split].y=#prog+1
                else gen(n) end
            end
            for _,j in ipairs(jumps) do prog[j].x=#prog+1 end
        elseif node.t=="repeat" then
            for _=1,node.min do gen(node.body) end
            local function fork(split,body,out) if node.greedy then prog[split].x,prog[split].y=body,out else prog[split].x,prog[split].y=out,body end end
            if node.max==nil then
                local split=emit({op="split"});gen(node.body);emit({op="jmp",x=split})
                fork(split,split+1,#prog+1)
            else
                local splits={}
                for _=node.min+1,node.max do local s=emit({op="split"});splits[#splits+1]=s;gen(node.body) end
                for _,s in ipairs(splits) do fork(s,s+1,#prog+1) end
            end
        end
    end
    emit({op="save",n=0});gen(tree);emit({op="save",n=1});emit({op="match"})
    return prog
end
-- Compile once per pattern/flag; returns program or nil, message.
function R.Compile(pattern,ignoreCase)
    if type(pattern)~="string" then return nil,"Pattern must be text" end
    if #pattern==0 then return nil,"Pattern is empty" end
    if #pattern>R.maxPattern then return nil,"Pattern is longer than "..R.maxPattern.." bytes" end
    local key=(ignoreCase and "i:" or "c:")..pattern
    local hit=R.cache[key];if hit then return hit end
    local ok,result=pcall(function()
        local tree,groups=parse((decode(pattern)),ignoreCase)
        return {prog=compile(tree),groups=groups}
    end)
    if not ok then
        if type(result)=="table" and result.regex then return nil,result.regex end
        return nil,"Invalid pattern"
    end
    if R.cacheSize>=R.cacheLimit then R.cache={};R.cacheSize=0 end
    R.cache[key]=result;R.cacheSize=R.cacheSize+1
    return result
end
-- One leftmost-first search from code point index `from`. budget is a table
-- {steps=n}; exceeding it raises {budget=true}.
local function search(prog,cps,from,budget)
    local n=#cps;local marks,gen={},0;local matched
    local function isBoundary(pos) return isWord(cps[pos-1])~=isWord(cps[pos]) end
    local function add(list,pc,caps,pos)
        local stack={pc,caps}
        while #stack>0 do
            local c=table.remove(stack);local p=table.remove(stack)
            budget.steps=budget.steps-1;if budget.steps<0 then error({budget=true},0) end
            if marks[p]~=gen then
                marks[p]=gen
                local ins=prog[p]
                if ins.op=="jmp" then stack[#stack+1]=ins.x;stack[#stack+1]=c
                elseif ins.op=="split" then
                    stack[#stack+1]=ins.y;stack[#stack+1]=c;stack[#stack+1]=ins.x;stack[#stack+1]=c
                elseif ins.op=="save" then
                    local copy={};for k,v in pairs(c) do copy[k]=v end;copy[ins.n]=pos
                    stack[#stack+1]=p+1;stack[#stack+1]=copy
                elseif ins.op=="assert" then
                    local ok=(ins.kind=="bol" and pos==1) or (ins.kind=="eol" and pos==n+1)
                        or (ins.kind=="word" and isBoundary(pos)) or (ins.kind=="nonword" and not isBoundary(pos))
                    if ok then stack[#stack+1]=p+1;stack[#stack+1]=c end
                else list[#list+1]=p;list[#list+1]=c end
            end
        end
    end
    gen=gen+1;local clist={};add(clist,1,{},from)
    for pos=from,n+1 do
        local cp=cps[pos];gen=gen+1;local nlist={}
        for i=1,#clist,2 do
            local p,c=clist[i],clist[i+1];local ins=prog[p]
            budget.steps=budget.steps-1;if budget.steps<0 then error({budget=true},0) end
            if ins.op=="match" then matched=c;break
            elseif cp and ins.test(cp) then add(nlist,p+1,c,pos+1) end
        end
        if pos<=n and not matched then add(nlist,1,{},pos+1) end
        clist=nlist;if #clist==0 then break end
    end
    return matched
end
-- Runs `fn(budget)` with a fresh step budget; returns its results, or nil and
-- the reason when the budget is exhausted.
local function bounded(fn)
    local budget={steps=R.maxSteps}
    local ok,a,b,c=pcall(fn,budget)
    if ok then return a,b,c end
    if type(a)=="table" and a.budget then return nil,"step limit reached" end
    error(a,0)
end
local function slice(text,starts,a,b) return text:sub(starts[a],starts[b]-1) end
local function prepare(pattern,text,ignoreCase)
    if A.G.IsSecret(text) or type(text)~="string" then return nil,"text unavailable" end
    local program,why=R.Compile(pattern,ignoreCase);if not program then return nil,why end
    local cps,starts=decode(text)
    if #cps>R.maxText then return nil,"text is longer than "..R.maxText.." characters" end
    return program,cps,starts
end
-- Test: true/false, or nil and a reason.
function R.Test(pattern,text,ignoreCase)
    local program,cps=prepare(pattern,text,ignoreCase);if not program then return nil,cps end
    return bounded(function(budget) return search(program.prog,cps,1,budget)~=nil,"ready" end)
end
-- First match: {matched, text, groups[1..9]} with "" for groups that did not take part.
function R.Match(pattern,text,ignoreCase)
    local program,cps,starts=prepare(pattern,text,ignoreCase);if not program then return nil,cps end
    return bounded(function(budget)
        local caps=search(program.prog,cps,1,budget)
        local out={matched=caps~=nil,text="",groups={}}
        for i=1,R.maxGroups do out.groups[i]="" end
        if caps then
            out.text=slice(text,starts,caps[0],caps[1])
            for i=1,program.groups do if caps[i*2] and caps[i*2+1] then out.groups[i]=slice(text,starts,caps[i*2],caps[i*2+1]) end end
        end
        return out,"ready"
    end)
end
-- Replacement template: $0..$9 insert groups, $$ inserts $.
local function expand(template,text,starts,caps,groups)
    return (template:gsub("%$([%d%$])",function(k)
        if k=="$" then return "$" end
        local i=tonumber(k)
        if i>groups and i>0 then return "" end
        local a,b=caps[i*2],caps[i*2+1]
        if not a or not b then return "" end
        return slice(text,starts,a,b)
    end))
end
-- Replace first or all matches; returns text, count or nil, reason.
function R.Replace(pattern,text,template,all,ignoreCase)
    if type(template)~="string" or #template>R.maxPattern then return nil,"Replacement must be text up to "..R.maxPattern.." bytes" end
    local program,cps,starts=prepare(pattern,text,ignoreCase);if not program then return nil,cps end
    return bounded(function(budget)
        local parts,from,last,count={},1,1,0
        while from<=#cps+1 do
            local caps=search(program.prog,cps,from,budget)
            if not caps then break end
            parts[#parts+1]=slice(text,starts,last,caps[0])
            parts[#parts+1]=expand(template,text,starts,caps,program.groups)
            count=count+1;last=caps[1]
            if caps[1]==caps[0] then
                -- Empty match: copy one character and continue after it.
                if caps[1]<=#cps then parts[#parts+1]=slice(text,starts,caps[1],caps[1]+1) end
                from=caps[1]+1;last=from
            else from=caps[1] end
            if not all then break end
        end
        if last<=#cps then parts[#parts+1]=slice(text,starts,last,#cps+1) end
        return table.concat(parts),count
    end)
end

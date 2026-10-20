-- Directional checks on bounded source-height patches. No traversability grant.
local _,Routing=...
if not Routing.ready then return end
local R=Routing.Grid
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local digits={}
for i=1,#alphabet do digits[alphabet:byte(i)]=i-1 end
local function vertex(p,which,index)
    local cache=p[which.."Cache"]
    if not cache then cache={};p[which.."Cache"]=cache end
    local v=cache[index]
    if v==nil then
        local at=(index-1)*3+1
        local a,b,c=p[which]:byte(at,at+2)
        v=p.base+(digits[a]*4096+digits[b]*64+digits[c])/1000
        cache[index]=v
    end
    return v
end
local function height(p,x,y,unit)
    local u,v=(x-p.x0)/unit,(y-p.y0)/unit
    local cx,cy=math.floor(u),math.floor(v)
    if cx<0 or cy<0 or cx>=p.cols or cy>=p.rows or p.mask:byte(cy*p.cols+cx+1)~=49 then return nil end
    u,v=u-cx,v-cy
    local i=cy*(p.cols+1)+cx+1
    local a,b=vertex(p,"outer",i),vertex(p,"outer",i+1)
    local c,d=vertex(p,"outer",i+p.cols+1),vertex(p,"outer",i+p.cols+2)
    local m=vertex(p,"inner",cy*p.cols+cx+1)
    if v<=u and v<=1-u then return a+(b-a)*u+(2*m-a-b)*v end
    if u>=v and u>=1-v then return b+(d-b)*v+(2*m-b-d)*(1-u) end
    if v>=u and v>=1-u then return c+(d-c)*u+(2*m-c-d)*(1-v) end
    return a+(c-a)*v+(2*m-a-c)*u
end
R.FineHeight=height
local function clip(a,d,lo,hi,t0,t1)
    if math.abs(d)<1e-12 then if a<lo or a>hi then return nil end;return t0,t1 end
    local x,y=(lo-a)/d,(hi-a)/d
    if x>y then x,y=y,x end
    t0,t1=math.max(t0,x),math.min(t1,y)
    if t0>t1 then return nil end
    return t0,t1
end
function R.FineWall(s,ax,ay,bx,by)
    local data=BVRoutingFineTerrain
    local f=s.terrain
    if not (data and type(f)=="table" and f.a) then return 0 end
    -- Same ADT axes as TerrainCell: east/south increasing, in yards.
    local mid=1600/3*32
    local x,y=mid-(f.a[f.ix]+ax*f.dx),mid-(f.a[f.iy]+ay*f.dy)
    local xx,yy=mid-(f.a[f.ix]+bx*f.dx),mid-(f.a[f.iy]+by*f.dy)
    local dx,dy=xx-x,yy-y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<1e-8 then return 0 end
    local ux,uy=dx/length,dy/length
    local up,down,fall=false,false,nil
    for _,p in ipairs(data.patches) do
        if p.instance==f.instance and math.max(x,xx)>=p.x0 and math.min(x,xx)<=p.x0+p.cols*data.unit
            and math.max(y,yy)>=p.y0 and math.min(y,yy)<=p.y0+p.rows*data.unit then
            local first,last=clip(x,ux,p.x0,p.x0+p.cols*data.unit,-25,length+25)
            if first then first,last=clip(y,uy,p.y0,p.y0+p.rows*data.unit,first,last) end
            if first and last>first then
                local count=math.max(1,math.ceil((last-first)/.5))
                local step=(last-first)/count
                local previous,sign,total,touches=nil,0,0,false
                local function finish()
                    if touches and total>=3.01 then
                        if sign>0 then up=true else down=true;fall=math.max(fall or 0,total) end
                    end
                end
                for j=0,count do
                    local t=first+j*step
                    local z=height(p,x+ux*t,y+uy*t,data.unit)
                    local dz=previous and z and z-previous
                    local nextSign=dz and math.abs(dz)>1.1968*step and (dz>0 and 1 or -1) or 0
                    if nextSign==0 or nextSign~=sign then finish();total=0;touches=false end
                    sign=nextSign
                    if nextSign~=0 then
                        total=total+math.abs(dz)
                        touches=touches or (t>0 and t-step<length)
                    end
                    previous=z
                end
                finish()
            end
        end
    end
    return (up and 1 or 0)+(down and 2 or 0),fall
end

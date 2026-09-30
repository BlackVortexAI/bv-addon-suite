-- Data only. Bounded parsing and independently bounded DEFLATE blocks; never eval.
local _,ns=...
local C={maxRaw=262144,maxText=400000,maxInput=600000,maxDepth=24,maxItems=50000}
ns.TransferCodec=C
local function library()
    local lib,minor=LibStub:GetLibrary("LibDeflate")
    assert(minor==3 and lib._VERSION=="1.0.2-release","Unverified LibDeflate version; import/export is unavailable until BV supports it")
    return lib
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)~=math.huge end
function C.Serialize(value)
    local out,seen,size,items={}, {},0,0
    local function put(s) size=size+#s; assert(size<=C.maxRaw,"Transfer exceeds 256 KiB"); out[#out+1]=s end
    local function visit(v,depth)
        assert(not ns.GraphValues.IsSecret(v),"Secret or opaque values cannot be exported")
        items=items+1; assert(items<=C.maxItems and depth<=C.maxDepth,"Transfer structure limit exceeded")
        local kind=type(v)
        if kind=="boolean" then put(v and "T" or "F")
        elseif kind=="number" then assert(finite(v),"Non-finite transfer number"); local s=string.format("%.17g",v); put("n"..#s..":"..s)
        elseif kind=="string" then assert(#v<=8192,"Transfer string too long"); put("s"..#v..":"..v)
        elseif kind=="table" then
            assert(not getmetatable(v) and not seen[v],"Transfer must be plain acyclic data"); seen[v]=true
            local keys={}; for k in pairs(v) do
                assert(not ns.GraphValues.IsSecret(k),"Secret or opaque keys cannot be exported")
                assert(type(k)=="string" or (finite(k) and k>=1 and k==math.floor(k)),"Invalid transfer key")
                keys[#keys+1]=k; assert(#keys<=C.maxItems,"Transfer entry limit exceeded")
            end
            table.sort(keys,function(a,b) if type(a)~=type(b) then return type(a)<type(b) end; return a<b end)
            put("{"..#keys..":"); for _,k in ipairs(keys) do visit(k,depth+1); visit(v[k],depth+1) end; seen[v]=nil
        else error("Unsupported transfer value") end
    end
    visit(value,0); return table.concat(out)
end
local function reader(s)
    local p=1
    local function take(n) assert(n>=0 and p+n-1<=#s,"Truncated transfer"); local v=s:sub(p,p+n-1); p=p+n; return v end
    local function integer(max)
        local digits=s:sub(p,p+8):match("^(%d+):"); assert(digits and #digits<=8,"Invalid transfer length")
        p=p+#digits+1; local n=tonumber(digits); assert(n<=max,"Transfer resource limit exceeded"); return n
    end
    return take,integer,function() return p>#s end
end
function C.Deserialize(raw)
    assert(type(raw)=="string" and #raw<=C.maxRaw,"Transfer exceeds 256 KiB")
    local take,integer,done=reader(raw); local items=0
    local function read(depth)
        items=items+1; assert(items<=C.maxItems and depth<=C.maxDepth,"Transfer structure limit exceeded")
        local tag=take(1)
        if tag=="T" then return true elseif tag=="F" then return false
        elseif tag=="s" then return take(integer(8192))
        elseif tag=="n" then local n=tonumber(take(integer(32))); assert(finite(n),"Invalid transfer number"); return n
        elseif tag=="{" then
            local n=integer(C.maxItems); assert(items+n*2<=C.maxItems,"Transfer entry limit exceeded")
            local t={}; for _=1,n do
                local k=read(depth+1)
                assert(type(k)=="string" or (finite(k) and k>=1 and k==math.floor(k)),"Invalid transfer key")
                assert(t[k]==nil,"Duplicate transfer key"); t[k]=read(depth+1)
            end; return t
        end
        error("Unknown transfer data tag")
    end
    local result=read(0); assert(done(),"Trailing transfer data"); return result
end
-- Adaptive blocks: shrink a block until it compresses into the 512-byte cap
-- the decoder enforces before inflating. Only while enough of the 64 blocks
-- remain for the rest as plain 4096-byte blocks, so every raw size still fits.
local function nextBlock(lib,raw,p,used)
    local left=#raw-p+1; local size=math.min(4096,left)
    local function fits(n) return math.ceil((left-n)/4096)<=63-used end
    for _=1,5 do
        if not fits(size) then break end
        local block=raw:sub(p,p+size-1); local compressed=lib:CompressDeflate(block,{level=9})
        if #compressed<=512 and #compressed<#block then return "D",block,compressed end
        local guess=math.floor(size*480/#compressed)
        if guess<256 or guess>=size then break end
        size=guess
    end
    local block=raw:sub(p,p+math.min(4096,left)-1)
    return "R",block,block
end
function C.Encode(value)
    local lib=library(); local raw=C.Serialize(value)
    local parts={tostring(lib:Adler32(raw)),":",tostring(#raw),":"}
    local p,used=1,0
    while p<=#raw do
        local mode,block,payload=nextBlock(lib,raw,p,used)
        parts[#parts+1]=mode..#block..":"..#payload..":"..payload
        p=p+#block;used=used+1
    end
    local encoded="!BVA:1!"..lib:EncodeForPrint(table.concat(parts))
    assert(#encoded<=C.maxText,"Export string too large"); return encoded
end
-- Addon-message form of an export string: the same bytes without the
-- printable 6-bit encoding (about 25% shorter). FromWire restores the string
-- for the normal bounded Decode.
function C.ToWire(text)
    assert(type(text)=="string" and text:sub(1,7)=="!BVA:1!","Unsupported export prefix/version (expected !BVA:1!)")
    local lib=library(); local body=lib:DecodeForPrint(text:sub(8)); assert(body,"Invalid printable transfer data")
    return lib:EncodeForWoWAddonChannel(body)
end
function C.FromWire(wire)
    assert(type(wire)=="string" and #wire<=C.maxText,"Shared data too large")
    local lib=library(); local body=lib:DecodeForWoWAddonChannel(wire)
    assert(body and #body<=C.maxRaw+2048,"Invalid shared transfer data")
    return "!BVA:1!"..lib:EncodeForPrint(body)
end
function C.Decode(text)
    assert(type(text)=="string" and #text<=C.maxInput,"Import string too large")
    text=text:gsub("[ \t\r\n]","")
    assert(#text<=C.maxText and text:sub(1,7)=="!BVA:1!","Unsupported export prefix/version (expected !BVA:1!)")
    local lib=library(); local body=lib:DecodeForPrint(text:sub(8))
    assert(body and #body<=C.maxRaw+2048,"Invalid printable transfer data")
    -- checksum has ten digits, unlike lengths in the bounded reader.
    local checksum=body:match("^(%d+):"); assert(checksum and #checksum<=10,"Invalid transfer checksum")
    local take,integer,done=reader(body:sub(#checksum+2)); local total=integer(C.maxRaw)
    local blocks,size={},0
    while not done() do
        assert(#blocks<64,"Too many transfer blocks")
        local mode=take(1); local expected=integer(4096); assert(expected>0,"Empty transfer block")
        assert(mode=="R" or mode=="D","Unknown transfer block")
        local length=integer(mode=="D" and 512 or 4096); local payload=take(length)
        if mode=="D" then
            -- PRE-inflate compressed cap bounds even hostile expansion to
            -- <=1032*512+258 bytes. Do not replace this with a post-hoc total check.
            local remaining; payload,remaining=lib:DecompressDeflate(payload)
            assert(payload and remaining==0,"Invalid compressed block")
        end
        assert(#payload==expected,"Transfer block length mismatch")
        size=size+#payload; assert(size<=total,"Transfer length exceeded"); blocks[#blocks+1]=payload
    end
    assert(size==total,"Truncated transfer payload"); local raw=table.concat(blocks)
    assert(lib:Adler32(raw)==tonumber(checksum),"Transfer checksum mismatch")
    return C.Deserialize(raw)
end

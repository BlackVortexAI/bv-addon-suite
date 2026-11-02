local _, Chat = ...
if not Chat.core then return end
local core=Chat.core
local layout,metrics=core.Layout,core.DesignSystem.Metrics
local registered={}
local leavingProfile=false

function Chat:LayoutID()
    return "bv:chat_window_"..self:WindowID()
end

local axes={BOTTOMLEFT={-1,-1},BOTTOM={0,-1},BOTTOMRIGHT={1,-1},LEFT={-1,0},CENTER={0,0},
    RIGHT={1,0},TOPLEFT={-1,1},TOP={0,1},TOPRIGHT={1,1}}
local function defaults(workspace)
    local cfg=workspace:Config()
    local number=workspace:WindowID()
    local width=metrics.ToNative(math.max(400,tonumber(cfg.hudWidth) or 535))
    local height=metrics.ToNative(math.max(215,tonumber(cfg.hudHeight) or 265))
    local screen,x,y="BOTTOMLEFT",metrics.ToNative(24),metrics.ToNative(72)
    local positions=core.Settings.db.windowPositions
    local name=number==1 and "BVChatWorkspace" or "BVChatWorkspace"..number
    local saved=positions and positions[name]
    if type(saved)=="table" and axes[saved[1]] and axes[saved[2]] and type(saved[3])=="number" and type(saved[4])=="number" then
        -- The former movable window could anchor different widget/screen
        -- corners. Layout uses a single matching screen anchor for both.
        local widget,relative=axes[saved[1]],axes[saved[2]]
        screen=saved[2]
        x=saved[3]+(relative[1]-widget[1])*width/2
        y=saved[4]+(relative[2]-widget[2])*height/2
    elseif number>1 then
        local offset=(number-2)%8*24
        screen,x,y="BOTTOMRIGHT",metrics.ToNative(-24-offset),metrics.ToNative(72+offset)
    elseif ChatFrame1 and ChatFrame1.GetLeft and ChatFrame1:GetLeft() and ChatFrame1:GetBottom() then
        local scale=ChatFrame1:GetEffectiveScale()/UIParent:GetEffectiveScale()
        x,y=ChatFrame1:GetLeft()*scale,ChatFrame1:GetBottom()*scale
    end
    return {screen=screen,x=x,y=y,width=width,height=height}
end

local function place(owner,rect)
    local window=owner.window
    if not window or not rect then return end
    local level=layout:Level(owner:LayoutID())
    if window:GetFrameLevel()~=level then window:SetFrameLevel(level) end
    window:ClearAllPoints()
    window:SetPoint("CENTER",UIParent,"CENTER",rect.x,rect.y)
    window:SetSize(rect.width,rect.height)
end

local function release(id)
    registered[id]=nil
    layout.elements[id],layout.applied[id]=nil,nil
    for index=#layout.order,1,-1 do
        if layout.order[index]==id then table.remove(layout.order,index);break end
    end
end

function Chat:SyncLayoutWindows()
    if leavingProfile or not core.Settings.db then return end
    local live,changed={},false
    for _,owner in ipairs(Chat:ListWindows()) do
        local id=owner:LayoutID()
        live[id]=true
        local label="Chat · "..owner:WindowName().." (#"..owner:WindowID()..")"
        local def=layout.elements[id]
        if not def then
            registered[id]=true
            layout:Register(id,{
                label=label,
                limits={minWidth=metrics.ToNative(400),minHeight=metrics.ToNative(215),maxWidth=5000,maxHeight=2000},
                defaults=function() return defaults(owner) end,
                apply=function(rect) place(owner,rect) end,
                enabled=function() return Chat.running==true and owner:IsWindowEnabled() end,
                -- Core's labeled mover previews hidden readers without
                -- opening the HUD, marking messages read or taking input.
                preview=function() end,
            })
            if layout.draft and not layout.draft[id] then layout.draft[id]=core.LayoutModel.Normalize(defaults(owner)) end
            changed=true
        elseif def.label~=label then def.label=label;changed=true end
    end
    for id in pairs(registered) do if not live[id] then release(id);changed=true end end
    if changed then layout:Refresh(true) end
end

function Chat:PlaceLayoutWindow()
    Chat:SyncLayoutWindows()
    local id=self:LayoutID()
    if registered[id] then place(self,layout.rects and layout.rects[id]) end
end
function Chat:OpenLayoutEditor(afterClose)
    Chat:SyncLayoutWindows()
    local id=self:LayoutID()
    if not registered[id] then return false end
    local editor=core.LayoutEditor
    editor:Open(id,afterClose)
    if editor.active and not editor.suspended and not editor:InView(id) then
        editor:SetView("normal")
        editor:Select(id)
    end
    return editor.active==true and not editor.suspended and editor.selected==id
end
function Chat:CanRemoveLayoutWindow()
    if layout.draft then
        core:Print("Save or discard the Layout Editor before removing a chat window.")
        return false
    end
    local refs=core.DisplayAnchors:AnchorReferences(self:LayoutID())
    if #refs==0 then return true end
    core:Print("Unlink this chat window in the Layout Editor before removing it: "..table.concat(refs,", "))
    return false
end
function Chat:RemoveLayoutWindow()
    local id=self:LayoutID()
    release(id)
    local store=core.Settings:Profile().layout
    if store and store.elements then store.elements[id]=nil end
    if layout.draft then layout.draft[id]=nil end
    layout:Refresh(true)
end

core.Settings:BeforeProfileChange(registered,function()
    leavingProfile=true
    for id in pairs(registered) do release(id) end
end)
core.Settings:AfterProfileChange(registered,function()
    leavingProfile=false
    Chat:SyncLayoutWindows()
end)
core.Events:Subscribe(registered,"PLAYER_ENTERING_WORLD",function() Chat:SyncLayoutWindows() end)

-- Native attachment boundary for replicated media. No acquisition, geometry
-- readback, event subscription or ticker belongs to this reusable UI helper.
local _,ns=...
function ns.UI:ResetDisplayAttachment(view)
    view.nativeAttachment=nil;view.nativeAnchor=nil;view.nativeGeometry=nil;view.displayPlacement=nil;view.visible=false;view.lastRect=nil
    pcall(view.Present,view,nil,false)
    local ok=pcall(function()
        view:SetParent(UIParent);view.nativeLevelBase=nil
        if view.SetDisplayLevel then view:SetDisplayLevel(view.displayLevel or 8)end
        view:ClearAllPoints()
    end)
    return ok
end
function ns.UI:AnchorDisplayToNameplate(view,frame,rect,link,rootRect)
    local V,M=ns.GraphValues,ns.LayoutModel
    local ok=pcall(function()
        assert(not V.IsSecret(frame) and frame~=nil,"Nameplate frame unavailable")
        assert(type(rect)=="table" and not V.IsSecret(rect),"Nameplate geometry unavailable")
        for _,key in ipairs({"x","y","width","height"})do
            local value=rect[key]
            assert(not V.IsSecret(value) and value~=nil and M.Number(value,nil,-100000,100000)==value,"Nameplate offsets must be readable")
        end
        local media=type(view.lastValue)=="table" and view.lastValue or nil
        local visual=ns.DisplayModel.Transform(rect,media,"visual")
        assert(visual.width>0 and visual.height>0,"Nameplate geometry is empty")
        if frame.IsForbidden then local forbidden=frame:IsForbidden();assert(not V.IsSecret(forbidden) and not forbidden,"Nameplate frame is unavailable")end
        local a=M.Normalize({link=link}).link or {side="CENTER",align="CENTER",gap=0,offset=0}
        local root=rootRect or rect
        for _,axis in ipairs({"width","height"})do assert(not V.IsSecret(root[axis]) and M.Number(root[axis],nil,0,10000)==root[axis] and root[axis]~=nil,"Root size must be readable")end
        local point,x,y="CENTER",visual.x,visual.y
        if a.side=="CENTER"then x=x+a.offset;y=y+a.gap
        elseif a.side=="TOP"or a.side=="BOTTOM"then
            point=a.side..(a.align=="START" and "LEFT" or a.align=="END" and "RIGHT" or "")
            x=x+a.offset+(a.align=="START" and root.width/2 or a.align=="END" and -root.width/2 or 0)
            y=y+(a.side=="TOP" and 1 or -1)*(root.height/2+a.gap)
        else
            point=(a.align=="START" and "TOP" or a.align=="END" and "BOTTOM" or "")..a.side
            x=x+(a.side=="RIGHT" and 1 or -1)*(root.width/2+a.gap)
            y=y+a.offset+(a.align=="START" and -root.height/2 or a.align=="END" and root.height/2 or 0)
        end
        if not view.nativeAttachmentHook then
            view.nativeAttachmentHook=true
            view:HookScript("OnShow",function(self)
                local saved=self.nativeAttachment
                if saved then ns.UI:AnchorDisplayToNameplate(self,saved.frame,saved.rect,saved.link,saved.root)end
            end)
        end
        local old=view.nativeGeometry
        local saved=view.nativeAttachment
        if not saved or saved.frame~=frame or not ns.DisplayModel.Equal(saved.rect,rect)
            or not ns.DisplayModel.Equal(saved.link,link) or not ns.DisplayModel.Equal(saved.root,root) then
            view.nativeAttachment={frame=frame,rect=M.Copy(rect),link=M.Copy(link),root=M.Copy(root)}
        end
        if view.nativeAnchor==frame and old and old.point==point and old.x==x and old.y==y
            and old.width==visual.width and old.height==visual.height then return end
        if view.ResetFeedback then view:ResetFeedback() end
        if view.nativeAnchor~=frame then
            -- Frame level is hierarchy metadata, never nameplate geometry. An
            -- explicitly ordered pooled child does not inherit it on SetParent.
            if view.SetDisplayLevel then
                local level=frame:GetFrameLevel()
                assert(not V.IsSecret(level) and type(level)=="number" and M.Number(level,nil,0,60000)==level,"Nameplate level unavailable")
                view.nativeLevelBase=level+1
            end
            view.nativeAnchor=frame;view:SetParent(frame)
        end
        if view.SetDisplayLevel then view:SetDisplayLevel(view.displayLevel or 8)end
        view.displayPlacement=nil
        view:ClearAllPoints();view:SetPoint("CENTER",frame,point,x,y)
        view:SetSize(visual.width,visual.height)
        view.nativeGeometry={point=point,x=x,y=y,width=visual.width,height=visual.height}
        if view.RefreshFeedback then view:RefreshFeedback() end
    end)
    if not ok then
        pcall(view.Present,view,nil,false);self:ResetDisplayAttachment(view)
        return false,"Nameplate attachment unavailable"
    end
    return true
end

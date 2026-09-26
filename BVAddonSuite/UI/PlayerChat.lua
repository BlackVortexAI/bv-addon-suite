-- A request is reviewed here; only this dedicated click calls the native adapter.
local _,ns=...
local UI,D=ns.UI,ns.DesignSystem.Metrics
local function at(w,p,x,y)return UI:Place(w,p,x,y)end
local labels={submitted_unconfirmed="Submitted to the game; delivery is unconfirmed.",expired="Request expired.",inactive="The graph is no longer active.",restricted="Chat is currently restricted.",call_failed="The game rejected the send request.",cancelled="Request cancelled.",context_unavailable="The selected channel is unavailable.",unsupported="This client cannot send this request."}
function UI:BindPlayerChat(service)
    local binding=self.playerChatBinding
    if binding and binding.service==service then return end
    if binding then binding.service:Unsubscribe(binding)end
    if self.playerChatReview then self.playerChatReview:Hide()end
    binding={service=service};self.playerChatBinding=binding
    local function refresh(_,reason)
        local rows=service:List()
        local dialog=UI.playerChatReview
        if #rows==0 and not dialog then return end
        if not dialog then
            dialog=UI:Dialog("BVAddonSuitePlayerChat",560,350);UI.playerChatReview=dialog
            local p=dialog.content
            dialog.title:SetText("Player chat — review before sending")
            dialog.destination=at(UI:Label(p,"",14,"text",true),p,20,8);D.Size(dialog.destination,520,40);dialog.destination:SetWordWrap(true)
            dialog.message=at(UI:Label(p,"",14,"text"),p,20,50);D.Size(dialog.message,520,112);dialog.message:SetWordWrap(true)
            dialog.status=at(UI:Label(p,"",12,"muted"),p,20,174);D.Size(dialog.status,520,52)
            dialog.next=at(UI:Button(p,"Review next",130,function()
                local current=dialog.service:List();dialog.selected=current[1] and current[1].id;dialog.armed=nil;dialog:Refresh()
            end),p,20,250)
            dialog.cancel=at(UI:Button(p,"Discard",110,function()
                local id=dialog.selected;dialog.selected=nil;dialog.armed=nil
                if id then dialog.service:Cancel(id)end
                dialog.status:SetText(labels.cancelled);dialog:Refresh()
            end),p,164,250)
            dialog.send=at(UI:Button(p,"Send message",160,function()
                local id=dialog.selected;local armed=dialog.armed;dialog.armed=nil
                if not id or armed~=id then return end
                dialog.selected=nil
                local status=dialog.service:Confirm(id)
                dialog:Refresh();dialog.status:SetText(labels[status] or "Request could not be sent.")
            end,true),p,380,250)
            dialog.send:HookScript("OnMouseDown",function(_,button)
                dialog.armed=button=="LeftButton" and dialog.selected or nil
            end)
            dialog.send:HookScript("OnLeave",function()dialog.armed=nil end)
            function dialog:Refresh()
                local list=self.service:List();local chosen
                for _,row in ipairs(list)do if row.id==self.selected then chosen=row;break end end
                if chosen then
                    self.destination:SetText(chosen.channel..(chosen.target~="" and " / "..chosen.target or ""))
                    self.message:SetText(chosen.text);self.send:Enable();self.cancel:Enable()
                else
                    self.selected=nil;self.armed=nil;self.destination:SetText("No request selected")
                    self.message:SetText("");self.send:Disable();self.cancel:Disable()
                end
                if #list>0 then self.next:Enable()else self.next:Disable()end
                self.count=#list
            end
            dialog:HookScript("OnHide",function(self)
                self.armed=nil;self.selected=nil;self.message:SetText("")
            end)
        end
        dialog.service=service
        -- Never replace an already reviewed row as other wishes arrive or expire.
        if reason=="requested" and not dialog:IsShown() and #rows>0 then
            dialog.selected=rows[1].id;dialog.armed=nil
            dialog.status:SetText("Only Send message sends this exact text. Requests expire after 15 seconds.")
            dialog:FitContent(560,350);dialog:Show()
        end
        dialog:Refresh()
        if #rows==0 and reason~="submitted_unconfirmed" and reason~="cancelled" then dialog:Hide()end
    end
    service:Subscribe(binding,refresh)
    refresh(binding,"bound")
end
ns.Commands:RegisterAction("chat",function()
    local binding=UI.playerChatBinding
    if not binding or #binding.service:List()==0 then ns:Print("No pending player chat requests.");return end
    local dialog=UI.playerChatReview
    if dialog then
        local rows=binding.service:List();dialog.selected=rows[1] and rows[1].id;dialog.armed=nil
        dialog:Show();dialog:Refresh()
    end
end)

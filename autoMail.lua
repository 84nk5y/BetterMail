local TARGET_PLAYER = "Banksy-Draenor"
local ITEM_IDS_TO_SEND = { [225567] = true } -- Use ID as key for speed



AutoMailFrameMixin = {}

function AutoMailFrameMixin:OnLoad()
    self.itemRows = {}
    self:RegisterEvent("BAG_UPDATE")
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterEvent("MAIL_SEND_SUCCESS")
    self.RecipientText:SetText("Recipient: |cffffffff" .. TARGET_PLAYER .. "|r")
end

hooksecurefunc("MailFrameTab_OnClick", function(self, tabID)
    if tabID == 3 then
        MailFrameInset:SetPoint("TOPLEFT", 4, -80);
		InboxFrame:Hide();
		SendMailFrame:Hide();
		SetSendMailShowing(false);
		MailFrame:SetTitle("Auto Mail");
        AutoMailFrame:Show()
    else
        AutoMailFrame:Hide()
    end
end)

function AutoMailFrameMixin:OnEvent(event, ...)
    if event == "MAIL_CLOSED" then
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" then
        -- Delay 0.5s to let the mail system "breath" before next batch
        C_Timer.After(0.5, function() self:SendNextBatch() end)
    elseif self:IsVisible() then
        self:UpdateItemList()
    end
end

function AutoMailFrameMixin:UpdateItemList()
    for _, row in ipairs(self.itemRows) do row:Hide() end
    
    local bagData = {}
    local anyItemsToSend = false
    
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                
                -- 1. Check Binding/Mailability
                local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(id)
                local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                local isBound = C_Item.IsBound(itemLoc)
                
                -- Only proceed if it is NOT BoP (1), NOT Quest (4), and NOT already bound
                if bindType ~= 1 and bindType ~= 4 and not isBound then
                    local isInList = ITEM_IDS_TO_SEND[id] or false
                    
                    if not bagData[id] then
                        bagData[id] = { count = 0, isAllowed = isInList }
                    end
                    
                    bagData[id].count = bagData[id].count + info.stackCount
                    if isInList then anyItemsToSend = true end
                end
            end
        end
    end
    
    -- 2. Sort the IDs (White items at top, then alphabetical)
    local sortedIDs = {}
    for id in pairs(bagData) do table.insert(sortedIDs, id) end
    table.sort(sortedIDs, function(a, b)
        if bagData[a].isAllowed ~= bagData[b].isAllowed then
            return bagData[a].isAllowed 
        end
        local nameA = C_Item.GetItemInfo(a) or ""
        local nameB = C_Item.GetItemInfo(b) or ""
        return nameA < nameB
    end)
    
    -- 3. Render only the items that passed the filter
    local yOffset, count = 0, 0
    local scrollChild = self.ScrollFrame.Content
    
    for _, itemID in ipairs(sortedIDs) do
        local data = bagData[itemID]
        count = count + 1
        local name, _, _, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        
        if not self.itemRows[count] then
            self.itemRows[count] = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        end
        
        local row = self.itemRows[count]
        row:SetPoint("TOPLEFT", 10, -yOffset)
        
        local colorCode = data.isAllowed and "|cffffffff" or "|cff808080"
        row:SetText(string.format("|T%s:14:14:0:0|t %s%s x%d|r", texture or 134400, colorCode, name or "Loading...", data.count))
        row:Show()
        
        yOffset = yOffset + 18
    end
    
    -- 4. Update Button
    if not anyItemsToSend then
        self.SendButton:SetText("No Items to Send")
        self.SendButton:Disable()
    else
        self.SendButton:SetText("Send All Items")
        self.SendButton:Enable()
    end
end

function AutoMailFrameMixin:SendNextBatch()
    if not MailFrame:IsVisible() then return end
    
    local itemsAttached = 0
    ClearSendMail()
    
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and ITEM_IDS_TO_SEND[info.itemID] then
                itemsAttached = itemsAttached + 1
                C_Container.PickupContainerItem(bag, slot)
                ClickSendMailItemButton(itemsAttached)
                
                if itemsAttached == 12 then break end
            end
        end
        if itemsAttached == 12 then break end
    end
    
    if itemsAttached > 0 then
        SendMail(TARGET_PLAYER, "Bulk Item Export", "")
    end
end
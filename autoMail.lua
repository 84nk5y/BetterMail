BAM_SavedVars = BAM_SavedVars or {}

AutoMailFrameMixin = {}

function AutoMailFrameMixin:OnLoad()
    self.bagData = {}
    self.itemRows = {}
    self:RegisterEvent("VARIABLES_LOADED")
    self:RegisterEvent("BAG_UPDATE")
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterEvent("MAIL_SEND_SUCCESS")
    self.RecipientText:SetText("Recipient: |cffffffff|r")
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
    if event == "VARIABLES_LOADED" then
        if not BAM_SavedVars.ITEM_IDS_TO_SEND then
            BAM_SavedVars.ITEM_IDS_TO_SEND = {
                [225567] = true, -- Default example
            }
        end
        if not BAM_SavedVars.TARGET_PLAYER then
            BAM_SavedVars.TARGET_PLAYER = "Sales-Draenor"
        end
    elseif event == "MAIL_CLOSED" then
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" then
        -- Delay 0.5s to let the mail system "breath" before next batch
        C_Timer.After(0.5, function() self:SendNextBatch() end)
    elseif self:IsVisible() then
        self:UpdateItemList(true)
    end
end

local function HasMailableBound(bindType)
    return bindType == Enum.ItemBind.None or bindType == Enum.ItemBind.OnEquip or bindType == Enum.ItemBind.OnUse
end

function AutoMailFrameMixin:CollectMaillableItemsFromBags()
    self.bagData = {}

    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                local itemName, itemLink, _, _, _, itemType, itemSubType, _, _, itemTexture, _, _, _, bindType, _, _, isCraftingReagent, _ = C_Item.GetItemInfo(id)
                local itemLoc = ItemLocation:CreateFromBagAndSlot(bag, slot)

                if (isCraftingReagent or HasMailableBound(bindType)) and not info.isBound then
                    if not self.bagData[id] then
                        self.bagData[id] = {
                            name = itemName,
                            link = itemLink,
                            location = itemLoc,
                            isCraftingReagent = isCraftingReagent,
                            count = 0,
                            texture = itemTexture
                        }
                    end
                    
                    self.bagData[id].count = self.bagData[id].count + info.stackCount
                end
            end
        end
    end
end

function AutoMailFrameMixin:UpdateItemList(fullScan)
    self.RecipientText:SetText("Recipient: |cffffffff" .. BAM_SavedVars.TARGET_PLAYER .. "|r")

    for _, row in ipairs(self.itemRows) do row:Hide() end
    
    if fullScan then self:CollectMaillableItemsFromBags() end

    -- 2. Sort the IDs (White items at top, then alphabetical)
    local sortedIDs = {}
    for id, item in pairs(self.bagData) do
        item.isAllowed = BAM_SavedVars.ITEM_IDS_TO_SEND[id] or false
        table.insert(sortedIDs, id)
    end
    table.sort(sortedIDs, function(a, b)
        local itemA = self.bagData[a]
        local itemB = self.bagData[b]
        if itemA.isAllowed ~= itemB.isAllowed then
            return itemA.isAllowed 
        end
        if itemA.isCraftingReagent ~= itemB.isCraftingReagent then
            return itemA.isCraftingReagent
        end
        return itemA.name < itemB.name
    end)
    
    -- 3. Render only the items that passed the filter
    local yOffset = 0
    local scrollChild = self.ScrollFrame.Content
    local anyItemsToSend = false

    for i, itemID in ipairs(sortedIDs) do
        local data = self.bagData[itemID]

        anyItemsToSend = anyItemsToSend or data.isAllowed
        
        if not self.itemRows[i] then
            self.itemRows[i] = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        end
        
        local row = self.itemRows[i]
        row:SetPoint("TOPLEFT", 10, -yOffset)
        
        local colorCode = data.isAllowed and "|cffffffff" or "|cff808080"
        row:SetText(string.format("|T%s:14:14:0:0|t %s%s (x%d)|r", data.texture or 134400, colorCode, data.name or "Loading...", data.count))
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
            if info and BAM_SavedVars.ITEM_IDS_TO_SEND[info.itemID] then
                itemsAttached = itemsAttached + 1
                C_Container.PickupContainerItem(bag, slot)
                ClickSendMailItemButton(itemsAttached)
                
                if itemsAttached == 12 then break end
            end
        end
        if itemsAttached == 12 then break end
    end
    
    if itemsAttached > 0 then
        SendMail(BAM_SavedVars.TARGET_PLAYER, "Bulk Item Export", "")
    end
end
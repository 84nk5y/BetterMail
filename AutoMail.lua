BAM_SavedVars = {}

local MORE_MAIL_TO_SEND = false

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
        MailFrameInset:SetPoint("TOPLEFT", 4, -58);
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
            BAM_SavedVars.ITEM_IDS_TO_SEND = {}
        end
        if not BAM_SavedVars.TARGET_PLAYER then
            BAM_SavedVars.TARGET_PLAYER = "Sales-Draenor"
        end
    elseif event == "MAIL_CLOSED" then
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" and MORE_MAIL_TO_SEND then
        -- Delay 2s to let the mail system "breath" before next batch
        C_Timer.After(2, function() self:SendNextBatch() end)
    elseif self:IsVisible() then
        self:UpdateItemList(true)
    end
end

function AutoMailFrameMixin:ToggleItemSelection(item)
    local itemID = item.ID
    local itemName = item.name

    if BAM_SavedVars.ITEM_IDS_TO_SEND[itemID] then
        BAM_SavedVars.ITEM_IDS_TO_SEND[itemID] = nil
        print("|cffB0C4DEAutoMail|r |cffff0000Removed|r item from list: " .. itemName .. "(".. itemID .. ")")
    else
        BAM_SavedVars.ITEM_IDS_TO_SEND[itemID] = itemName
        print("|cffB0C4DEAutoMail|r |cff00ff00Added|r item to list: " .. itemName .. "(".. itemID .. ")")
    end

    self:UpdateItemList(false)
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

                if not info.isBound then
                    if not self.bagData[id] then
                        self.bagData[id] = {
                            ID = id,
                            name = itemName,
                            bag = bag,
                            bagSlot = slot,
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
    self.RecipientText:SetText("Recipient: |cffffffff" .. (BAM_SavedVars.TARGET_PLAYER or "Unknown") .. "|r")

    for _, row in ipairs(self.itemRows) do row:Hide() end

    if fullScan then self:CollectMaillableItemsFromBags() end

    local sortedIDs = {}
    for id, item in pairs(self.bagData) do
        if BAM_SavedVars.ITEM_IDS_TO_SEND[id] then
            item.isAllowed = true
        else
            item.isAllowed = false
        end
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

    local yOffset = 0
    local scrollChild = self.ScrollFrame.Content
    local anyItemsToSend = false

    for i, itemID in ipairs(sortedIDs) do
        local data = self.bagData[itemID]
        anyItemsToSend = anyItemsToSend or data.isAllowed

        if not self.itemRows[i] then
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(260, 18)
            btn:SetNormalFontObject("GameFontHighlight")
            btn:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")

            btn.Text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            btn.Text:SetPoint("LEFT", 5, 0)
            btn.Text:SetJustifyH("LEFT")

            btn:SetScript("OnClick", function(rowBtn)
                if IsShiftKeyDown() then
                    self:ToggleItemSelection(rowBtn.item)
                end
            end)

            self.itemRows[i] = btn
        end

        local row = self.itemRows[i]
        row:SetPoint("TOPLEFT", 0, -yOffset)
        row.item = data

        local colorCode = data.isAllowed and "|cffffffff" or "|cff808080"
        row.Text:SetText(string.format("|T%s:14:14:0:0|t %s%s (x%d)|r",
            data.texture or 134400, colorCode, data.name or "Loading...", data.count))

        row:Show()
        yOffset = yOffset + 18
    end

    if not anyItemsToSend then
        self.SendButton:SetText("No Items to Send")
        self.SendButton:Disable()
    else
        self.SendButton:SetText("Send All Items")
        self.SendButton:Enable()
    end
end

function AutoMailFrameMixin:SendNextBatch()
    if not AutoMailFrame:IsVisible() then return end

    ClearSendMail()

    MORE_MAIL_TO_SEND = false

    local itemsAttached = 0
    for id, item in pairs(self.bagData) do
        if BAM_SavedVars.ITEM_IDS_TO_SEND[id] then
            itemsAttached = itemsAttached + 1
            C_Container.PickupContainerItem(item.bag, item.bagSlot)
            ClickSendMailItemButton(itemsAttached)

            if itemsAttached == 12 then
                MORE_MAIL_TO_SEND = true
                break
            end
        end
    end

    if itemsAttached > 0 then
        print("|cffB0C4DEAutoMail|r Sending "..itemsAttached.." to "..BAM_SavedVars.TARGET_PLAYER)
        SendMail(BAM_SavedVars.TARGET_PLAYER, "AutoMail package", "")
    end
end
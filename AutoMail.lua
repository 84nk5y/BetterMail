BAM_SavedVars = { Items = {}, Recepient = "Sales-Draenor" }

local MORE_MAIL_TO_SEND = false
local MAX_MAIL_ATTACHMENTS = 12

AutoMailFrameMixin = {}

function AutoMailFrameMixin:OnLoad()
    self.bagData = {}
    self.itemRows = {}
    self.sortedItemIDs = {}
    self.updatePending = false
    self:RegisterEvent("BAG_UPDATE")
    self:RegisterEvent("MAIL_SHOW")
    self:RegisterEvent("MAIL_CLOSED")
    self:RegisterEvent("MAIL_SEND_SUCCESS")
    self.RecipientText:SetText("Recipient: |cffffffff|r")
end

hooksecurefunc("MailFrameTab_OnClick", function(self, tabID)
    if tabID == 3 then
        MailFrameInset:SetPoint("TOPLEFT", 4, -58)
        InboxFrame:Hide()
        SendMailFrame:Hide()
        SetSendMailShowing(false)
        MailFrame:SetTitle("Auto Mail")
        AutoMailFrame:Show()
    else
        AutoMailFrame:Hide()
    end
end)

function AutoMailFrameMixin:OnEvent(event, ...)
    if event == "MAIL_CLOSED" then
        MORE_MAIL_TO_SEND = false
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" and MORE_MAIL_TO_SEND then
        -- Delay 2s to let the mail system "breathe" before next batch
        C_Timer.After(2, function() self:SendNextBatch() end)
    elseif self:IsVisible() then
        if not self.updatePending then
            self.updatePending = true
            C_Timer.After(0.2, function()
                self.updatePending = false
                if self:IsVisible() then
                    self:UpdateItemList(true)
                end
            end)
        end
    end
end

function AutoMailFrameMixin:ToggleItemSelection(item)
    local itemID = item.ID
    local itemName = item.name

    if BAM_SavedVars.Items[itemID] then
        BAM_SavedVars.Items[itemID] = nil
        print("|cffB0C4DE[AutoMail]|r |cffff0000Removed|r item from list: "..itemName.."(".. itemID..")")
    else
        BAM_SavedVars.Items[itemID] = itemName
        print("|cffB0C4DE[AutoMail]|r |cff00ff00Added|r item to list: "..itemName.."(".. itemID..")")
    end

    self:UpdateItemList(false)
end

function AutoMailFrameMixin:CollectMaillableItemsFromBags()
    self.bagData = {}

    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isBound then
                local id = info.itemID
                local itemName, itemLink, _, _, _, itemType, itemSubType, _, _, itemTexture, _, _, _, bindType, _, _, isCraftingReagent, _ = C_Item.GetItemInfo(id)

                if itemName then
                    if not self.bagData[id] then
                        self.bagData[id] = {
                            ID = id,
                            name = itemName,
                            locations = {},
                            isCraftingReagent = isCraftingReagent,
                            count = 0,
                            texture = itemTexture
                        }
                    end

                    table.insert(self.bagData[id].locations, {bag = bag, slot = slot})
                    self.bagData[id].count = self.bagData[id].count + info.stackCount
                end
            end
        end
    end
end

function AutoMailFrameMixin:UpdateItemList(fullScan)
    self.RecipientText:SetText("Recipient: |cffffffff"..(BAM_SavedVars.Recepient or "Unknown").."|r")

    for _, row in ipairs(self.itemRows) do row:Hide() end

    if fullScan then self:CollectMaillableItemsFromBags() end

    local sortedIDs = {}
    for id, item in pairs(self.bagData) do
        if BAM_SavedVars.Items[id] then
            item.isAllowed = true
        else
            item.isAllowed = false
        end
        table.insert(sortedIDs, id)
    end

    local bagData = self.bagData
    table.sort(sortedIDs, function(a, b)
        local itemA = bagData[a]
        local itemB = bagData[b]
        if itemA.isAllowed ~= itemB.isAllowed then
            return itemA.isAllowed
        end
        if itemA.isCraftingReagent ~= itemB.isCraftingReagent then
            return itemA.isCraftingReagent
        end
        return itemA.name < itemB.name
    end)

    self.sortedItemIDs = sortedIDs

    local yOffset = 0
    local scrollChild = self.ScrollFrame.Content
    local anyItemsToSend = false

    for i, itemID in ipairs(sortedIDs) do
        local data = bagData[itemID]
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

    local recipient = BAM_SavedVars.Recepient
    if not recipient or recipient == "" then
        print("|cffB0C4DE[AutoMail]|r |cffff0000Error:|r No recipient set!")
        return
    end

    ClearSendMail()

    MORE_MAIL_TO_SEND = false

    local itemsAttached = 0

    for _, id in ipairs(self.sortedItemIDs) do
        local item = self.bagData[id]
        if BAM_SavedVars.Items[id] then
            for _, loc in ipairs(item.locations) do
                itemsAttached = itemsAttached + 1
                C_Container.PickupContainerItem(loc.bag, loc.slot)
                ClickSendMailItemButton(itemsAttached)

                if itemsAttached == MAX_MAIL_ATTACHMENTS then
                    MORE_MAIL_TO_SEND = true
                    break
                end
            end
            if itemsAttached == MAX_MAIL_ATTACHMENTS then
                break
            end
        end
    end

    if itemsAttached > 0 then
        print("|cffB0C4DE[AutoMail]|r Sending "..itemsAttached.." item(s) to "..recipient)
        SendMail(recipient, "AutoMail package", "")
    end
end
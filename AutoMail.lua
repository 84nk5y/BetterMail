BAM_SavedVars = BAM_SavedVars or { Items = {}, Recipient = "Sales-Draenor" }

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

    self.RecipientText:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
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
        MailFrameInset:SetPoint("TOPLEFT", 4, -80)
    end
end)

function AutoMailFrameMixin:OnEvent(event, ...)
    if event == "MAIL_CLOSED" then
        MORE_MAIL_TO_SEND = false
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" and MORE_MAIL_TO_SEND then
        C_Timer.After(1.5, function() self:SendNextBatch() end)
    elseif self:IsVisible() then
        if not self.updatePending then
            self.updatePending = true
            C_Timer.After(0.3, function()
                self.updatePending = false
                if self:IsVisible() then self:UpdateItemList(true) end
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
                if not self.bagData[id] then
                    local itemName, itemLink, _, _, _, itemType, itemSubType, _, _, itemTexture, _, _, _, bindType, _, _, isCraftingReagent, _ = C_Item.GetItemInfo(id)

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

function AutoMailFrameMixin:UpdateItemList(fullScan)
    if fullScan then self:CollectMaillableItemsFromBags() end

    self.RecipientText:SetText("Recipient: |cffffffff"..(BAM_SavedVars.Recipient or "Unknown").."|r")

    local container = self.ScrollFrame.Content
    for _, row in ipairs(self.itemRows) do row:Hide() end

    local displayList = {}
    for id, item in pairs(self.bagData) do
        if BAM_SavedVars.Items[id] then item.isAllowed = true end
        table.insert(displayList, item)
    end

    table.sort(displayList, function(a, b)
        if a.isAllowed ~= b.isAllowed then return a.isAllowed end
        if a.isCraftingReagent ~= a.isCraftingReagent then return a.isCraftingReagent end
        return a.name < b.name
    end)

    local anyItemsToSend = false
    for i, data in ipairs(displayList) do
        anyItemsToSend = anyItemsToSend or data.isAllowed
        if not self.itemRows[i] then
            local rb = CreateFrame("Button", nil, container)
            rb.layoutIndex = i
            rb:SetSize(260, 20)
            rb:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight")
            rb.Text = rb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rb.Text:SetPoint("LEFT", 5, 0)
            rb:SetScript("OnClick", function(rb) if IsShiftKeyDown() then self:ToggleItemSelection(rb.item) end end)
            self.itemRows[i] = rb
        end

        local row = self.itemRows[i]
        row.item = data
        local color = data.isAllowed and "|cffffffff" or "|cff808080"
        row.Text:SetText(string.format("|T%s:14:14:0:0|t %s%s (x%d)|r", data.texture or 134400, color, data.name or "Loading...", data.count))
        row:Show()
    end

    container:Layout()
    container:Show()

    self.ScrollFrame:UpdateScrollChildRect()

    self.SendButton:SetEnabled(anyItemsToSend)
    self.SendButton:SetText(anyItemsToSend and "Send All Items" or "No Items to Send")
end

function AutoMailFrameMixin:SendNextBatch()
    if not self:IsVisible() then return end

    local recipient = BAM_SavedVars.Recipient
    if not recipient or recipient == "" then
        print("|cffB0C4DE[AutoMail]|r |cffff0000Error:|r No recipient set!")
        return
    end

    ClearSendMail()
    local itemsAttached = 0
    MORE_MAIL_TO_SEND = false

    for id, _ in pairs(BAM_SavedVars.Items) do
        local item = self.bagData[id]
        if item then
            for _, loc in ipairs(item.locations) do
                if itemsAttached < MAX_MAIL_ATTACHMENTS then
                    C_Container.PickupContainerItem(loc.bag, loc.slot)
                    ClickSendMailItemButton(itemsAttached + 1)
                    itemsAttached = itemsAttached + 1
                else
                    MORE_MAIL_TO_SEND = true
                    break
                end
            end
        end
        if MORE_MAIL_TO_SEND then break end
    end

    if itemsAttached > 0 then
        print("|cffB0C4DE[AutoMail]|r Sending "..itemsAttached.." item(s) to "..recipient)
        SendMail(recipient, "AutoMail package", "")
    end
end
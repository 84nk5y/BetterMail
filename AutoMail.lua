BAM_SavedVars = BAM_SavedVars or { Items = {}, Recipient = "Sales-Draenor" }

local MAX_MAIL_ATTACHMENTS = 12

AutoMailFrameMixin = {}

function AutoMailFrameMixin:OnLoad()
    self.bagData = {}
    self.sortedItemIDs = {}
    self.updatePending = false
    self.moreMailToSend = false

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
        self.moreMailToSend = false
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" and self.moreMailToSend then
        C_Timer.After(1.5, function() self:SendMailBatch() end)
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

function AutoMailFrameMixin:UpdateItemList(fullScan)
    if fullScan then self:CollectMaillableItemsFromBags() end

    self.RecipientText:SetText("Recipient: |cffffffff"..(BAM_SavedVars.Recipient or "Unknown").."|r")

    local container = self.ScrollFrame.Content

    if not self.pool then
        self.pool = CreateFramePool("Button", container, "AutoMailEntryTemplate")
    end
    self.pool:ReleaseAll()

    local displayList = {}
    for id, item in pairs(self.bagData) do
        item.isAllowed = (BAM_SavedVars.Items[id] ~= nil)
        table.insert(displayList, item)
    end

    table.sort(displayList, function(a, b)
        if a.isAllowed ~= b.isAllowed then return a.isAllowed end
        if a.isCraftingReagent ~= b.isCraftingReagent then return a.isCraftingReagent end
        if a.name ~= b.name then return a.name < b.name end
        return (a.quality or 0) > (b.quality or 0)
    end)

    local panel = self
    local anyItemsToSend = false

    for i, data in ipairs(displayList) do
        anyItemsToSend = anyItemsToSend or data.isAllowed

        local entry = self.pool:Acquire()

        entry.layoutIndex = i
        entry.item = data

        if data.rarity then
            local r, g, b = C_Item.GetItemQualityColor(data.rarity)
            entry.IconBorder:SetVertexColor(r, g, b)
            entry.IconBorder:Show()
        else
            entry.IconBorder:Hide()
        end

        entry.Icon:SetTexture(data.texture)

        if data.quality then
            entry.QualityOverlay:SetAtlas(string.format("Professions-Icon-Quality-Tier%d-Inv", data.quality));
            entry.QualityOverlay:Show()
        else
            entry.QualityOverlay:Hide()
        end

        if data.count > 1 then
            entry.Quantity:SetText(data.count)
            entry.Quantity:Show()
            entry.Quantity:SetScale(0.7)
        else
            entry.Quantity:Hide()
        end

        local color = data.isAllowed and "|cffffffff" or "|cff808080"
        entry.Text:SetText(string.format("%s%s|r", color, data.name))

        entry:SetScript("OnClick", function(self)
            if IsShiftKeyDown() then
                panel:ToggleItemSelection(self.item)
            end
        end)

        entry:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
            GameTooltip:SetItemByID(self.item.ID)
            GameTooltip:Show()
        end)

        entry:SetScript("OnLeave", GameTooltip_Hide)

        entry:Show()
    end

    container:Layout()
    container:Show()

    self.ScrollFrame:UpdateScrollChildRect()

    self.SendButton:SetEnabled(anyItemsToSend)
    self.SendButton:SetText(anyItemsToSend and "Send All Items" or "No Items to Send")
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
                    local itemName, itemLink, rarity, _, _, itemType, itemSubType, _, _, itemTexture, _, _, _, bindType, _, _, isCraftingReagent, _ = C_Item.GetItemInfo(id)
                    local quality = (isCraftingReagent and C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)) or nil

                    self.bagData[id] = {
                        ID = id,
                        name = itemName,
                        locations = {},
                        isCraftingReagent = isCraftingReagent,
                        count = 0,
                        rarity = rarity,
                        quality = quality,
                        texture = itemTexture
                    }
                end
                table.insert(self.bagData[id].locations, {bag = bag, slot = slot})
                self.bagData[id].count = self.bagData[id].count + info.stackCount
            end
        end
    end
end

function AutoMailFrameMixin:SendMailBatch()
    if not self:IsVisible() then return end

    local recipient = BAM_SavedVars.Recipient
    if not recipient or recipient == "" then
        print("|cffB0C4DE[AutoMail]|r |cffff0000Error:|r No recipient set!")
        return
    end

    ClearSendMail()
    local itemsAttached = 0
    self.moreMailToSend = false

    for id, _ in pairs(BAM_SavedVars.Items) do
        local item = self.bagData[id]
        if item then
            for _, loc in ipairs(item.locations) do
                if itemsAttached < MAX_MAIL_ATTACHMENTS then
                    C_Container.PickupContainerItem(loc.bag, loc.slot)
                    ClickSendMailItemButton(itemsAttached + 1)
                    itemsAttached = itemsAttached + 1
                else
                    self.moreMailToSend = true
                    break
                end
            end
        end
        if self.moreMailToSend then break end
    end

    if itemsAttached > 0 then
        print("|cffB0C4DE[AutoMail]|r Sending "..itemsAttached.." item(s) to "..recipient)
        SendMail(recipient, "AutoMail package", "")
    end
end
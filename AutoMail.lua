local ADDON_NAME, _ = ...

BAM_SavedVars = BAM_SavedVars or { Items = {}, Recipient = "Sales-Draenor" }

local MAX_MAIL_ATTACHMENTS = 12
local BATCH_SEND_DELAY = 1.5

AutoMailFrameMixin = {}

function AutoMailFrameMixin:OnLoad()
    self.bagData = {}
    self.sortedItemIDs = {}
    self.updatePending = false
    self.moreMailToSend = false
    self.isSending = false

    self:RegisterEvent("BAG_UPDATE_DELAYED")
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
        self.isSending = false
        self:Hide()
    elseif event == "MAIL_SEND_SUCCESS" then
        if self.moreMailToSend then
            C_Timer.After(BATCH_SEND_DELAY, function() self:SendMailBatch() end)
        else
            self.isSending = false
        end
    elseif self:IsVisible() and (event == "MAIL_SHOW" or event == "BAG_UPDATE_DELAYED") then
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

        if data.quality then
            local r, g, b = C_Item.GetItemQualityColor(data.quality)
            entry.IconBorder:SetVertexColor(r, g, b)
            entry.IconBorder:Show()
        else
            entry.IconBorder:Hide()
        end

        entry.Icon:SetTexture(data.texture)

        if data.craftingQualityInfo then
            if not entry.QualityOverlay then
                entry.QualityOverlay = entry:CreateTexture(nil, "OVERLAY")
                entry.QualityOverlay:SetPoint("TOPLEFT", -2, 2)
                entry.QualityOverlay:SetDrawLayer("OVERLAY", 7)
            end

            entry.QualityOverlay:SetAtlas(data.craftingQualityInfo.iconInventory, TextureKitConstants.UseAtlasSize)
            entry.QualityOverlay:Show()
        elseif entry.QualityOverlay then
            entry.QualityOverlay:Hide()
        end

        if data.count > 1 then
            entry.Quantity:SetText(data.count)
            entry.Quantity:Show()
            if entry.Quantity:GetScale() ~= 0.7 then
                entry.Quantity:SetScale(0.7)
            end
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
            GameTooltip:AddLine(" ")
            if self.item.isAllowed then
                GameTooltip:AddLine("|cffff4444Shift-click to remove from send list|r", 1, 1, 1)
            else
                GameTooltip:AddLine("|cff44ff44Shift-click to add to send list|r", 1, 1, 1)
            end
            GameTooltip:Show()
        end)

        entry:SetScript("OnLeave", GameTooltip_Hide)

        entry:Show()
    end

    container:Layout()
    container:Show()

    self.ScrollFrame:UpdateScrollChildRect()

    self.SendButton:SetEnabled(anyItemsToSend and not self.isSending)
    self.SendButton:SetText(anyItemsToSend and "Send All Items" or "No Items to Send")
end

function AutoMailFrameMixin:ToggleItemSelection(item)
    local itemID = item.ID
    local itemName = item.name

    if BAM_SavedVars.Items[itemID] then
        BAM_SavedVars.Items[itemID] = nil
        print("|cffB0C4DE["..ADDON_NAME.."]|r |cffff0000Removed|r item from list: "..itemName.." ("..itemID..")")
    else
        BAM_SavedVars.Items[itemID] = itemName
        print("|cffB0C4DE["..ADDON_NAME.."]|r |cff00ff00Added|r item to list: "..itemName.." ("..itemID..")")
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
                local link = info.hyperlink

                if not self.bagData[id] then
                    local _, _, _, _, _, _, _, _, _, itemTexture, _, _, _, _, _, _, isCraftingReagent = C_Item.GetItemInfo(link)
                    local craftingQualityInfo = isCraftingReagent and C_TradeSkillUI.GetItemReagentQualityInfo(id) or nil

                    self.bagData[id] = {
                        ID = id,
                        name = info.itemName,
                        locations = {},
                        isCraftingReagent = isCraftingReagent,
                        count = 0,
                        quality = info.quality,
                        craftingQualityInfo = craftingQualityInfo,
                        texture = itemTexture
                    }
                end

                if self.bagData[id] then
                    table.insert(self.bagData[id].locations, { bag = bag, slot = slot })
                    self.bagData[id].count = self.bagData[id].count + info.stackCount
                end
            end
        end
    end
end

function AutoMailFrameMixin:SendMailBatch()
    if not self:IsVisible() then
        self.isSending = false
        return
    end

    local recipient = BAM_SavedVars.Recipient
    if not recipient or recipient == "" then
        print("|cffB0C4DE["..ADDON_NAME.."]|r |cffff0000Error:|r No recipient set!")
        self.isSending = false
        return
    end

    self:CollectMaillableItemsFromBags()

    ClearCursor()
    ClearSendMail()

    local itemsAttached = 0
    self.moreMailToSend = false

    local toSend = {}
    for id, _ in pairs(BAM_SavedVars.Items) do
        local item = self.bagData[id]
        if item then
            table.insert(toSend, item)
        end
    end
    table.sort(toSend, function(a, b) return a.ID < b.ID end)

    for _, item in ipairs(toSend) do
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
        if self.moreMailToSend then break end
    end

    if itemsAttached > 0 then
        local suffix = self.moreMailToSend and " (more to follow...)" or ""
        print("|cffB0C4DE[AutoMail]|r Sending "..itemsAttached.." item(s) to "..recipient..suffix)
        SendMail(recipient, "AutoMail package", "")
    else
        self.isSending = false
        print("|cffB0C4DE[AutoMail]|r Nothing left to send.")
    end
end
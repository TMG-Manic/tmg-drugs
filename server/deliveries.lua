TMGCore = exports['tmg-core']:GetCoreObject()

-- Functions
exports('GetDealers', function()
    return Config.Dealers
end)

-- Callbacks
TMGCore.Functions.CreateCallback('tmg-drugs:server:RequestConfig', function(_, cb)
    cb(Config.Dealers)
end)

local function SaveDealer(dealerName)
    local data = Config.Dealers[dealerName]
    if not data then return end
    exports['tmgnosql']:SaveToCollection('dealers', { name = dealerName }, data)
end
-- Events
RegisterNetEvent('tmg-drugs:server:updateDealerItems', function(itemData, amount, dealer)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or not Config.Dealers[dealer] then return end

    local product = Config.Dealers[dealer]['products'][itemData.slot]
    
    if product.amount - amount >= 0 then
        Config.Dealers[dealer]['products'][itemData.slot].amount -= amount
        
        SaveDealer(dealer)
        
        TriggerClientEvent('tmg-drugs:client:setDealerItems', -1, itemData, amount, dealer)
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.item_unavailable'), 'error')
    end
end)

RegisterNetEvent('tmg-drugs:server:giveDeliveryItems', function(deliveryData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local item = Config.DeliveryItems[deliveryData.item].item
    if not item then return end
    exports['tmg-inventory']:AddItem(src, item, deliveryData.amount, false, false, 'tmg-drugs:server:giveDeliveryItems')
    TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'add')
end)

RegisterNetEvent('tmg-drugs:server:successDelivery', function(deliveryData, inTime)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local item = Config.DeliveryItems[deliveryData.item].item
    local itemAmount = deliveryData.amount
    local payout = deliveryData.itemData.payout * itemAmount
    local copsOnline = TMGCore.Functions.GetDutyCount('police')
    local invItem = Player.Functions.GetItemByName(item)
    if inTime then
        if invItem and invItem.amount >= itemAmount then -- on time correct amount
            exports['tmg-inventory']:RemoveItem(src, item, itemAmount, false, 'tmg-drugs:server:successDelivery')
            if copsOnline > 0 then
                local copModifier = copsOnline * Config.PoliceDeliveryModifier
                if Config.UseMarkedBills then
                    local info = { worth = math.floor(payout * copModifier) }
                    exports['tmg-inventory']:AddItem(src, 'markedbills', 1, false, info, 'tmg-drugs:server:successDelivery')
                else
                    Player.Functions.AddMoney('cash', math.floor(payout * copModifier), 'tmg-drugs:server:successDelivery')
                end
            else
                if Config.UseMarkedBills then
                    local info = { worth = payout }
                    exports['tmg-inventory']:AddItem(src, 'markedbills', 1, false, info, 'tmg-drugs:server:successDelivery')
                else
                    Player.Functions.AddMoney('cash', payout, 'tmg-drugs:server:successDelivery')
                end
            end
            TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
            TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.order_delivered'), 'success')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('tmg-drugs:client:sendDeliveryMail', src, 'perfect', deliveryData)
                Player.Functions.AddRep('dealer', Config.DeliveryRepGain)
            end)
        else
            TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.order_not_right'), 'error') -- on time incorrect amount
            if invItem then
                local newItemAmount = invItem.amount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                exports['tmg-inventory']:RemoveItem(src, item, newItemAmount, false, 'tmg-drugs:server:successDelivery')
                TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
                Player.Functions.AddMoney('cash', math.floor(modifiedPayout / Config.WrongAmountFee), 'tmg-drugs:server:successDelivery')
            end
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('tmg-drugs:client:sendDeliveryMail', src, 'bad', deliveryData)
                Player.Functions.RemoveRep('dealer', Config.DeliveryRepLoss)
            end)
        end
    else
        if invItem and invItem.amount >= itemAmount then -- late correct amount
            TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.too_late'), 'error')
            exports['tmg-inventory']:RemoveItem(src, item, itemAmount, false, 'tmg-drugs:server:successDelivery')
            Player.Functions.AddMoney('cash', math.floor(payout / Config.OverdueDeliveryFee), 'tmg-drugs:server:successDelivery')
            TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
            SetTimeout(math.random(5000, 10000), function()
                TriggerClientEvent('tmg-drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                Player.Functions.RemoveRep('dealer', Config.DeliveryRepLoss)
            end)
        else
            if invItem then -- late incorrect amount
                local newItemAmount = invItem.amount
                local modifiedPayout = deliveryData.itemData.payout * newItemAmount
                TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.too_late'), 'error')
                exports['tmg-inventory']:RemoveItem(src, item, itemAmount, false, 'tmg-drugs:server:successDelivery')
                Player.Functions.AddMoney('cash', math.floor(modifiedPayout / Config.OverdueDeliveryFee), 'tmg-drugs:server:successDelivery')
                TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
                SetTimeout(math.random(5000, 10000), function()
                    TriggerClientEvent('tmg-drugs:client:sendDeliveryMail', src, 'late', deliveryData)
                    Player.Functions.RemoveRep('dealer', Config.DeliveryRepLoss)
                end)
            end
        end
    end
end)

RegisterNetEvent('tmg-drugs:server:dealerShop', function(currentDealer)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end
    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local dealerData = Config.Dealers[currentDealer]
    if not dealerData then return end
    local dist = #(playerCoords - vector3(dealerData.coords.x, dealerData.coords.y, dealerData.coords.z))
    if dist > 5.0 then return end
    local curRep = Player.Functions.GetRep('dealer')
    local repItems = {}
    for k in pairs(dealerData.products) do
        if curRep >= dealerData['products'][k].minrep then
            repItems[#repItems+1] = dealerData['products'][k]
        end
    end
    exports['tmg-inventory']:CreateShop({
        name = dealerData.name,
        label = dealerData.name,
        slots = #repItems,
        coords = dealerData.coords,
        items = repItems,
    })
    exports['tmg-inventory']:OpenShop(src, dealerData.name)
end)

-- Commands

TMGCore.Commands.Add('newdealer', "Create a new drug dealer", {
    { name = 'name', help = 'Name of the dealer' },
    { name = 'min', help = 'Minimum appearance time (0-24)' },
    { name = 'max', help = 'Maximum appearance time (0-24)' }
}, true, function(source, args)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local dealerName = tostring(args[1])
    local coords = GetEntityCoords(GetPlayerPed(src))

    if Config.Dealers[dealerName] then 
        return TriggerClientEvent('TMGCore:Notify', src, "Dealer already exists in the registry.", 'error') 
    end

    local dealerData = {
        ["name"] = dealerName,
        ["coords"] = { 
            ["x"] = coords.x, 
            ["y"] = coords.y, 
            ["z"] = coords.z 
        },
        ["time"] = { 
            ["min"] = tonumber(args[2]) or 0, 
            ["max"] = tonumber(args[3]) or 24 
        },
        ["products"] = Config.Products,
        ["createdby"] = Player.PlayerData.citizenid,
        ["createdAt"] = os.time()
    }

    local success = exports['tmgnosql']:InsertDocument('dealers', dealerData)

    if success then
        Config.Dealers[dealerName] = dealerData
        
        TriggerClientEvent('tmg-drugs:client:RefreshDealers', -1, Config.Dealers)
        
        TriggerClientEvent('TMGCore:Notify', src, "New dealer '" .. dealerName .. "' anchored to the network.", "success")
        print(string.format("^5[TMG]^7 Mainframe: Dealer asset '%s' registered by %s", dealerName, Player.PlayerData.citizenid))
    else
        TriggerClientEvent('TMGCore:Notify', src, "Mainframe Error: Failed to anchor dealer asset.", "error")
    end
end, 'admin')

TMGCore.Commands.Add('deletedealer', "Remove a dealer from the network", {
    { name = 'name', help = 'The unique name of the dealer to purge' }
}, true, function(source, args)
    local src = source
    local dealerName = tostring(args[1])

    if Config.Dealers[dealerName] then
        
        local success = exports['tmgnosql']:DeleteOne('dealers', { 
            ["name"] = dealerName 
        })

        if success then
            Config.Dealers[dealerName] = nil
            
            TriggerClientEvent('tmg-drugs:client:RefreshDealers', -1, Config.Dealers)
            
            TriggerClientEvent('TMGCore:Notify', src, "Dealer '" .. dealerName .. "' has been purged from the mainframe.", 'success')
            print(string.format("^5[TMG]^7 Mainframe: Dealer asset '%s' deleted by Admin %s", dealerName, GetPlayerName(src)))
        else
            TriggerClientEvent('TMGCore:Notify', src, "Mainframe Error: Failed to delete " .. dealerName, 'error')
        end
    else
        TriggerClientEvent('TMGCore:Notify', src, "Dealer '" .. dealerName .. "' does not exist in the registry.", 'error')
    end
end, 'admin')

TMGCore.Commands.Add('dealers', Lang:t('info.dealers_command_desc'), {}, false, function(source, _)
    local DealersText = ''
    if Config.Dealers ~= nil and next(Config.Dealers) ~= nil then
        for _, v in pairs(Config.Dealers) do
            DealersText = DealersText .. Lang:t('info.list_dealers_name_prefix') .. v['name'] .. '<br>'
        end
        TriggerClientEvent('chat:addMessage', source, {
            template = '<div class="chat-message advert"><div class="chat-message-body"><strong>' .. Lang:t('info.list_dealers_title') .. '</strong><br><br> ' .. DealersText .. '</div></div>',
            args = {}
        })
    else
        TriggerClientEvent('TMGCore:Notify', source, Lang:t('error.no_dealers'), 'error')
    end
end, 'admin')

TMGCore.Commands.Add('dealergoto', Lang:t('info.dealergoto_command_desc'), { {
    name = Lang:t('info.dealergoto_command_help1_name'),
    help = Lang:t('info.dealergoto_command_help1_help')
} }, true, function(source, args)
    local DealerName = tostring(args[1])
    if Config.Dealers[DealerName] then
        local ped = GetPlayerPed(source)
        SetEntityCoords(ped, Config.Dealers[DealerName]['coords']['x'], Config.Dealers[DealerName]['coords']['y'], Config.Dealers[DealerName]['coords']['z'])
        TriggerClientEvent('TMGCore:Notify', source, Lang:t('success.teleported_to_dealer', { dealerName = DealerName }), 'success')
    else
        TriggerClientEvent('TMGCore:Notify', source, Lang:t('error.dealer_not_exists'), 'error')
    end
end, 'admin')

CreateThread(function()
    Wait(1000)
    
    local dealers = exports['tmgnosql']:FetchAll'dealers', {}
    
    if dealers and #dealers > 0 then
        for _, data in ipairs(dealers) do
            Config.Dealers[data.name] = data
        end
        
        print(string.format("^5[TMG]^7 Mainframe: Distribution Registry Loaded | %d dealers synced.", #dealers))
    else
        print("^3[TMG]^7 Mainframe: Distribution Registry empty. No dealers found.")
    end
    
    TriggerClientEvent('tmg-drugs:client:RefreshDealers', -1, Config.Dealers)
end)
TMGCore = exports['tmg-core']:GetCoreObject()
local StolenDrugs = {}

local function getAvailableDrugs(source)
    local AvailableDrugs = {}
    local Player = TMGCore.Functions.GetPlayer(source)

    if not Player then return nil end

    for k in pairs(Config.DrugsPrice) do
        local item = Player.Functions.GetItemByName(k)

        if item then
            AvailableDrugs[#AvailableDrugs + 1] = {
                item = item.name,
                amount = item.amount,
                label = TMGCore.Shared.Items[item.name]['label']
            }
        end
    end
    return table.type(AvailableDrugs) ~= 'empty' and AvailableDrugs or nil
end

TMGCore.Functions.CreateCallback('tmg-drugs:server:cornerselling:getAvailableDrugs', function(source, cb)
    cb(getAvailableDrugs(source))
end)

RegisterNetEvent('tmg-drugs:server:giveStealItems', function(drugType, amount)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player or StolenDrugs == {} then return end
    for k, v in pairs(StolenDrugs) do
        if drugType == v.item and amount == v.amount then
            exports['tmg-inventory']:AddItem(src, drugType, amount, false, false, 'tmg-drugs:server:giveStealItems')
            table.remove(StolenDrugs, k)
        end
    end
end)

RegisterNetEvent('tmg-drugs:server:sellCornerDrugs', function(drugType, amount, price)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    local availableDrugs = getAvailableDrugs(src)
    if not availableDrugs or not Player then return end
    local item = availableDrugs[drugType].item
    local hasItem = Player.Functions.GetItemByName(item)
    if hasItem.amount >= amount then
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.offer_accepted'), 'success')
        exports['tmg-inventory']:RemoveItem(src, item, amount, false, 'tmg-drugs:server:sellCornerDrugs')
        Player.Functions.AddMoney('cash', price, 'tmg-drugs:server:sellCornerDrugs')
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
        TriggerClientEvent('tmg-drugs:client:refreshAvailableDrugs', src, getAvailableDrugs(src))
    else
        TriggerClientEvent('tmg-drugs:client:cornerselling', src)
    end
end)

RegisterNetEvent('tmg-drugs:server:robCornerDrugs', function(drugType, amount)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    local availableDrugs = getAvailableDrugs(src)
    if not availableDrugs or not Player then return end
    local item = availableDrugs[drugType].item
    exports['tmg-inventory']:RemoveItem(src, item, amount, false, 'tmg-drugs:server:robCornerDrugs')
    table.insert(StolenDrugs, { item = item, amount = amount })
    TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[item], 'remove')
    TriggerClientEvent('tmg-drugs:client:refreshAvailableDrugs', src, getAvailableDrugs(src))
end)

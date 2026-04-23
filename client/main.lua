local TMGCore = exports['tmg-core']:GetCoreObject()

-- [[ TMG MAINFRAME: DRUGS STATE MATRIX ]]
-- Unified registry for illicit operations
DrugsState = {
    isLoggedIn = LocalPlayer.state['isLoggedIn'],
    -- Corner Selling Node
    isSelling = false,
    hasTarget = false,
    lastPeds = {},
    stealingPed = nil,
    stealData = {},
    availableDrugs = {},
    currentOfferDrug = nil,
    currentCops = 0,
    textDrawn = false,
    zoneMade = false,
    -- Dealer Delivery Node
    currentDealer = nil,
    dealerIsHome = false,
    waitingDelivery = nil,
    activeDelivery = nil,
    deliveryTimeout = 0,
    waitingKeyPress = false,
    dealerCombo = nil,
    drugDeliveryZone = nil
}

-- [[ TMG UTILITIES: KINETIC HELPERS ]]

local function LoadAnim(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
end

local function PoliceCall(msg)
    if math.random(1, 100) <= Config.PoliceCallChance then
        TriggerServerEvent('police:server:policeAlert', msg or 'Suspicious activity')
        print("^5[TMG]^7 Police alert dispatched: " .. (msg or "General Suspicion"))
    end
end

-- [[ TMG CORNER ENGINE: SELLING LOGIC ]]

local function TooFarAway()
    TMGCore.Functions.Notify(Lang:t('error.too_far_away'), 'error')
    LocalPlayer.state:set('inv_busy', false, true)
    DrugsState.isSelling = false
    DrugsState.hasTarget = false
    DrugsState.availableDrugs = {}
    print("^5[TMG]^7 Corner selling aborted: Outside operational radius.")
end

local function RobberyPed()
    local function SearchAction()
        local player = PlayerPedId()
        LoadAnim('pickup_object')
        TaskPlayAnim(player, 'pickup_object', 'pickup_low', 8.0, -8.0, -1, 1, 0, false, false, false)
        Wait(2000)
        ClearPedTasks(player)
        TriggerServerEvent('tmg-drugs:server:giveStealItems', DrugsState.stealData.item, DrugsState.stealData.amount)
        TriggerEvent('tmg-inventory:client:ItemBox', TMGCore.Shared.Items[DrugsState.stealData.item], 'add')
        DrugsState.stealingPed = nil
        DrugsState.stealData = {}
        if Config.UseTarget then exports['tmg-target']:RemoveZone('stealingPed') end
    end

    if Config.UseTarget then
        exports['tmg-target']:AddEntityZone('stealingPed', DrugsState.stealingPed, { name = 'stealingPed', debugPoly = false }, {
            options = { { icon = 'fas fa-magnifying-glass', label = Lang:t('info.search_ped'), action = SearchAction, canInteract = function(entity) return IsEntityDead(entity) end } },
            distance = 1.5,
        })
    end
    
    CreateThread(function()
        while DrugsState.stealingPed do
            local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(DrugsState.stealingPed))
            if dist > 100 then DrugsState.stealingPed = nil break end
            if not Config.UseTarget and IsEntityDead(DrugsState.stealingPed) and dist < 1.5 then
                if not DrugsState.textDrawn then DrugsState.textDrawn = true exports['tmg-core']:DrawText(Lang:t('info.pick_up_button')) end
                if IsControlJustReleased(0, 38) then exports['tmg-core']:KeyPressed() SearchAction() DrugsState.textDrawn = false end
            end
            Wait(0)
        end
    end)
end

local function SellToPed(ped)
    DrugsState.hasTarget = true
    for _, p in pairs(DrugsState.lastPeds) do if p == ped then DrugsState.hasTarget = false return end end

    if math.random(1, 100) <= Config.SuccessChance then DrugsState.hasTarget = false return end

    local drugIdx = math.random(1, #DrugsState.availableDrugs)
    DrugsState.currentOfferDrug = DrugsState.availableDrugs[drugIdx]
    local amount = math.random(1, math.min(DrugsState.currentOfferDrug.amount, 15))
    local price = math.random(Config.DrugsPrice[DrugsState.currentOfferDrug.item].min, Config.DrugsPrice[DrugsState.currentOfferDrug.item].max) * amount
    if math.random(1, 100) <= Config.ScamChance then price = math.random(3, 10) * amount end

    SetEntityAsNoLongerNeeded(ped)
    local playerPed = PlayerPedId()
    local isRobbery = math.random(1, 100) <= Config.RobberyChance
    TaskGoStraightToCoord(ped, GetEntityCoords(playerPed), isRobbery and 15.0 or 1.2, -1, 0.0, 0.0)

    CreateThread(function()
        while DrugsState.hasTarget and not IsPedDeadOrDying(ped) do
            local dist = #(GetEntityCoords(playerPed) - GetEntityCoords(ped))
            if dist < 1.5 then
                if isRobbery then
                    TriggerServerEvent('tmg-drugs:server:robCornerDrugs', drugIdx, amount)
                    TMGCore.Functions.Notify(Lang:t('info.has_been_robbed', { bags = amount, drugType = DrugsState.currentOfferDrug.label }))
                    DrugsState.stealingPed, DrugsState.stealData = ped, { item = DrugsState.currentOfferDrug.item, amount = amount }
                    DrugsState.hasTarget = false
                    ClearPedTasksImmediately(ped)
                    TaskGoStraightToCoord(ped, GetEntityCoords(ped) + vector3(math.random(100,500), math.random(100,500), 0), 15.0, -1, 0.0, 0.0)
                    DrugsState.lastPeds[#DrugsState.lastPeds+1] = ped
                    RobberyPed()
                    break
                else
                    TaskLookAtEntity(ped, playerPed, 5500.0, 2048, 3)
                    TaskTurnPedToFaceEntity(ped, playerPed, 5500)
                    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT_UPRIGHT', 0, false)
                    
                    if Config.UseTarget and not DrugsState.zoneMade then
                        DrugsState.zoneMade = true
                        exports['tmg-target']:AddEntityZone('sellingPed', ped, { name = 'sellingPed', debugPoly = false }, {
                            options = {
                                { label = Lang:t('info.target_drug_offer', { bags = amount, drugLabel = DrugsState.currentOfferDrug.label, randomPrice = price }), icon = 'fas fa-hand-holding-dollar', action = function()
                                    if IsPedInAnyVehicle(playerPed, false) then return TMGCore.Functions.Notify(Lang:t('error.in_vehicle'), 'error') end
                                    exports['tmg-target']:RemoveZone('sellingPed')
                                    TMGCore.Functions.Progressbar('cornerSelling', Lang:t('info.selling_to_ped'), 5000, false, false, { disableMovement = true, disableCombat = false }, {}, {}, {}, function()
                                        TriggerServerEvent('tmg-drugs:server:sellCornerDrugs', drugIdx, amount, price)
                                        DrugsState.hasTarget = false
                                        LoadAnim('gestures@f@standing@casual')
                                        TaskPlayAnim(playerPed, 'gestures@f@standing@casual', 'gesture_point', 3.0, 3.0, -1, 49, 0, 0, 0, 0)
                                        Wait(650)
                                        ClearPedTasks(playerPed)
                                        DrugsState.lastPeds[#DrugsState.lastPeds+1] = ped
                                        PoliceCall('Drug sale in progress')
                                    end)
                                end },
                                { label = 'Decline offer', icon = 'fas fa-x', action = function() DrugsState.hasTarget = false exports['tmg-target']:RemoveZone('sellingPed') end }
                            },
                            distance = 1.5
                        })
                    end
                end
                break
            end
            Wait(100)
        end
    end)
end

-- [[ TMG DELIVERY ENGINE: DEALER LOGIC ]]

local function KnockDoor(home)
    LoadAnim('timetable@jimmy@doorknock@')
    TaskPlayAnim(PlayerPedId(), 'timetable@jimmy@doorknock@', 'knockdoor_idle', 3.0, 3.0, -1, 1, 0, false, false, false)
    TriggerServerEvent('InteractSound_SV:PlayOnSource', 'knock_door', 0.2)
    Wait(3500)
    if home then
        DrugsState.dealerIsHome = true
        local myData = TMGCore.Functions.GetPlayerData()
        TriggerEvent('chat:addMessage', { color = { 255, 0, 0 }, multiline = true, args = { Lang:t('info.dealer_name', { dealerName = Config.Dealers[DrugsState.currentDealer]['name'] }), Lang:t('info.fred_knock_message', { firstName = myData.charinfo.firstname }) } })
        print("^5[TMG]^7 Dealer uplink established: " .. Config.Dealers[DrugsState.currentDealer]['name'])
    else
        TMGCore.Functions.Notify(Lang:t('info.no_one_home'), 'error')
    end
end

local function RequestDelivery()
    if DrugsState.waitingDelivery then return TMGCore.Functions.Notify(Lang:t('error.pending_delivery'), 'error') end
    
    TMGCore.Functions.Notify(Lang:t('info.delivery_search'), 'success')
    local pCoords = GetEntityCoords(PlayerPedId())
    local nearby = {}
    
    for _, loc in ipairs(Config.DeliveryLocations) do
        if #(pCoords - loc.coords) <= Config.DeliveryWithin then nearby[#nearby+1] = loc end
    end

    local selected = #nearby > 0 and nearby[math.random(#nearby)] or Config.DeliveryLocations[math.random(#Config.DeliveryLocations)]
    local itemKey = "weed_brick" -- Simplified rep-based item selection
    
    DrugsState.waitingDelivery = {
        coords = selected.coords,
        locationLabel = selected.label,
        amount = math.random(1, 3),
        dealer = DrugsState.currentDealer,
        itemData = Config.DeliveryItems[itemKey],
        item = itemKey
    }

    TriggerServerEvent('tmg-drugs:server:giveDeliveryItems', DrugsState.waitingDelivery)
    SetTimeout(2000, function()
        TriggerServerEvent('tmg-phone:server:sendNewMail', {
            sender = Config.Dealers[DrugsState.currentDealer]['name'],
            subject = 'Delivery Location',
            message = Lang:t('info.delivery_info_email', { itemAmount = DrugsState.waitingDelivery.amount, itemLabel = TMGCore.Shared.Items[DrugsState.waitingDelivery.itemData.item].label }),
            button = { enabled = true, buttonEvent = 'tmg-drugs:client:setLocation', buttonData = DrugsState.waitingDelivery }
        })
    end)
end

local function DeliverStuff()
    if DrugsState.deliveryTimeout > 0 then
        TaskStartScenarioInPlace(PlayerPedId(), 'PROP_HUMAN_BUM_BIN', 0, true)
        PoliceCall('Suspicious activity')
        TMGCore.Functions.Progressbar('work_dropbox', Lang:t('info.delivering_products'), 3500, false, true, { disableMovement = true }, {}, {}, {}, function()
            TriggerServerEvent('tmg-drugs:server:successDelivery', DrugsState.activeDelivery, true)
            if Config.UseTarget then exports['tmg-target']:RemoveZone('drugDeliveryZone') else DrugsState.drugDeliveryZone:destroy() end
            DrugsState.activeDelivery = nil
            print("^5[TMG]^7 Logistics mission successful.")
        end)
    else
        TriggerServerEvent('tmg-drugs:server:successDelivery', DrugsState.activeDelivery, false)
    end
    DrugsState.deliveryTimeout = 0
end

-- [[ TMG LIFECYCLE: KINETIC HEARTBEAT ]]

CreateThread(function()
    while true do
        local sleep = 1000
        if DrugsState.isLoggedIn then
            local pos = GetEntityCoords(PlayerPedId())

            -- 1. CORNER SELLING SECTOR
            if DrugsState.isSelling then
                sleep = 500
                if not DrugsState.hasTarget then
                    local ped, dist = TMGCore.Functions.GetClosestPed(pos, {})
                    if dist < 15.0 and ped ~= 0 and not IsPedInAnyVehicle(ped) then SellToPed(ped) end
                end
                if #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(PlayerPedId())) > 10 then TooFarAway() end -- Dist check simplified
            end

            -- 2. DEALER & DELIVERY SECTOR
            for k, v in pairs(Config.Dealers) do
                if #(pos - vector3(v.coords.x, v.coords.y, v.coords.z)) < 2.0 then
                    sleep = 5
                    DrugsState.currentDealer = k
                    if not Config.UseTarget then
                        exports['tmg-core']:DrawText(DrugsState.dealerIsHome and Lang:t('info.other_dealers_button') or Lang:t('info.knock_button'))
                        if IsControlJustPressed(0, 38) then if not DrugsState.dealerIsHome then KnockDoor(true) else TriggerServerEvent('tmg-drugs:server:dealerShop', k) end end
                        if IsControlJustPressed(0, 47) and DrugsState.dealerIsHome then RequestDelivery() end
                    end
                end
            end
            
            -- 3. TIMEOUT TICKER
            if DrugsState.deliveryTimeout > 0 then DrugsState.deliveryTimeout = DrugsState.deliveryTimeout - 1 Wait(1000) end
        end
        Wait(sleep)
    end
end)

-- [[ TMG EVENTS: CORE DISPATCHER ]]

RegisterNetEvent('tmg-drugs:client:cornerselling', function()
    TMGCore.Functions.TriggerCallback('tmg-drugs:server:cornerselling:getAvailableDrugs', function(result)
        if DrugsState.currentCops >= Config.MinimumDrugSalePolice then
            if result then DrugsState.availableDrugs = result DrugsState.isSelling = not DrugsState.isSelling
            else TMGCore.Functions.Notify(Lang:t('error.has_no_drugs'), 'error') end
        else TMGCore.Functions.Notify(Lang:t('error.not_enough_police', { polices = Config.MinimumDrugSalePolice }), 'error') end
    end)
end)

RegisterNetEvent('tmg-drugs:client:setLocation', function(data)
    DrugsState.activeDelivery, DrugsState.deliveryTimeout = data, 300
    SetNewWaypoint(data.coords.x, data.coords.y)
    TMGCore.Functions.Notify(Lang:t('success.route_has_been_set'), 'success')
    print("^5[TMG]^7 Delivery waypoint projected.")
end)

RegisterNetEvent('police:SetCopCount', function(amount) DrugsState.currentCops = amount end)
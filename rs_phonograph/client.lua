local volume = 0.3
local loopEnabled = false
local nuiOpen = false
local phonographEntities = {}
local closestEntity = nil
local closestId = nil
local lastPlacedPhonograph = nil
local phonographData = {}
local distance = 50.0

local function openNui()
    if nuiOpen then return end
    nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = "showNUI",
        allowCustom = Config.AllowCustomSongs,
        allowList = Config.AllowListSongs,
        songs = Config.SongList,
        translations = Config.MusicTranslations
    })
end

local function closeNui()
    nuiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = "hideNUI" })
end

RegisterNUICallback("playUrl", function(data, cb)
    if data.url and data.url:sub(1, 4) == "http" then
        TriggerServerEvent('rs_phonograph:server:playMusic', closestId, GetEntityCoords(closestEntity), data.url, volume)
        TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.PlayMessage, "generic_textures", "tick", 1500, "COLOR_GREEN")
    else
        TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.InvalidUrlMessage, "menu_textures", "cross", 500, "COLOR_RED")
    end
    cb({})
end)

RegisterNUICallback("playSelected", function(data, cb)
    if data.url then
        TriggerServerEvent('rs_phonograph:server:playMusic', closestId, GetEntityCoords(closestEntity), data.url, volume)
        TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.PlaySelect, "generic_textures", "tick", 1500, "COLOR_GREEN")
    end
    cb({})
end)

RegisterNUICallback("stopAudio", function(_, cb)
    TriggerServerEvent('rs_phonograph:server:stopMusic', closestId)
    TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.StopMessage, "menu_textures", "cross", 500, "COLOR_RED")
    cb({})
end)

RegisterNUICallback("setVolume", function(data, cb)
    volume = math.max(0.0, math.min(data.volume / 100, 1.0))
    TriggerEvent('rs_phonograph:client:setVolume', closestId, volume)
    cb({})
end)

RegisterNUICallback("toggleLoop", function(_, cb)
    loopEnabled = not loopEnabled
    TriggerServerEvent('rs_phonograph:server:toggleLoop', closestId, loopEnabled)
    cb({})
end)

RegisterNUICallback("closeNui", function(_, cb)
    closeNui()
    cb({})
end)

RegisterNetEvent('rs_phonograph:client:spawnPhonograph')
AddEventHandler('rs_phonograph:client:spawnPhonograph', function(data)
    phonographData[data.id] = data
end)

RegisterNetEvent('rs_phonograph:client:removePhonograph')
AddEventHandler('rs_phonograph:client:removePhonograph', function(uniqueId)
    local entity = phonographEntities[uniqueId]
    if entity and DoesEntityExist(entity) then
        DeleteObject(entity)
    end
    phonographEntities[uniqueId] = nil
    phonographData[uniqueId] = nil
end)

Citizen.CreateThread(function()
    TriggerServerEvent('rs_phonograph:server:requestPhonographs')
end)

RegisterNetEvent('rs_phonograph:client:receivePhonographs')
AddEventHandler('rs_phonograph:client:receivePhonographs', function(phonographs)
    if phonographs then
        for _, data in pairs(phonographs) do
            TriggerEvent('rs_phonograph:client:spawnPhonograph', data)
        end
    end
end)

CreateThread(function()
    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)

        for id, data in pairs(phonographData) do
            local pos = vector3(data.x, data.y, data.z)
            local dist = #(playerCoords - pos)

            if dist < distance and not phonographEntities[id] then
                local propModel = `p_phonograph01x`
                RequestModel(propModel)
                while not HasModelLoaded(propModel) do Wait(10) end

                local object = CreateObject(propModel, data.x, data.y, data.z, false, false, false)
                SetEntityHeading(object, tonumber(data.rotation.z or 0.0) % 360.0)
                FreezeEntityPosition(object, true)
                SetEntityAsMissionEntity(object, true)

                phonographEntities[id] = object
            end

            if dist > distance and phonographEntities[id] then
                DeleteEntity(phonographEntities[id])
                phonographEntities[id] = nil
            end
        end

        Wait(1000)
    end
end)

Citizen.CreateThread(function()
    local showingPhonograph = false

    while true do
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearPhonograph = false
        closestEntity, closestId = nil, nil

        for uniqueId, entity in pairs(phonographEntities or {}) do
            if DoesEntityExist(entity) then
                local entityCoords = GetEntityCoords(entity)
                local distance = #(playerCoords - entityCoords)
                if distance < 1.5 then
                    nearPhonograph = true
                    closestEntity = entity
                    closestId = uniqueId
                    break
                end
            end
        end

        if nearPhonograph then
            if not showingPhonograph then
                SendNUIMessage({
                    type = "showPhonograph",
                    textTop = Config.Promp.openmanuUi,
                    textBottom = Config.Promp.Collect,
                })
                showingPhonograph = true
            end

            if IsControlJustReleased(0, Config.Promp.openUi) then
                if closestId then
                    openNui()
                else
                    TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.UnregisteredMessage, "generic_textures", "tick", 3000, "COLOR_GREEN")
                end
            end

            if IsControlJustReleased(0, Config.Promp.collectPhonograph) then
                if closestId then
                    TriggerServerEvent('rs_phonograph:server:pickUpByOwner', closestId)
                else
                    TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.UnregisteredMessage, "generic_textures", "tick", 3000, "COLOR_GREEN")
                end
            end
        else
            if showingPhonograph then
                SendNUIMessage({ type = "hidePhonograph" })
                showingPhonograph = false
            end
        end

        Citizen.Wait(nearPhonograph and 0 or 500)
    end
end)

RegisterNetEvent('rs_phonograph:client:placePropPhonograph')
AddEventHandler('rs_phonograph:client:placePropPhonograph', function()
    local phonographModel = GetHashKey('p_phonograph01x')
    RequestModel(phonographModel)
    while not HasModelLoaded(phonographModel) do Wait(10) end

    local playerPed = PlayerPedId()
    local px, py, pz = table.unpack(GetEntityCoords(playerPed, true))
    local ox, oy, oz = table.unpack(GetOffsetFromEntityInWorldCoords(playerPed, 0.0, 2.5, 0.0))

    local groundSuccess, groundZ = GetGroundZFor_3dCoord(ox, oy, pz, false)
    if groundSuccess then pz = groundZ end

    local tempObject = CreateObject(phonographModel, ox, oy, pz, true, false, false)
    PlaceObjectOnGroundProperly(tempObject)

    local posX, posY, posZ = table.unpack(GetEntityCoords(tempObject))
    local heading = GetEntityHeading(tempObject)

    local moveStep = 0.05
    local isPlacing = true

    FreezeEntityPosition(tempObject, true)
    SetEntityCollision(tempObject, false, false)
    SetEntityAlpha(tempObject, 150, false)
    SendNUIMessage({ 
        action = "show",
        translations = Config.ControlTranslations
    })

    lastPlacedPhonograph = {
        entity = tempObject,
        coords = vector3(posX, posY, posZ),
        rotation = vector3(0.0, 0.0, heading)
    }

    CreateThread(function()
        while isPlacing do
            Wait(0)

            for _, keyCode in pairs(Config.Keys) do
                DisableControlAction(0, keyCode, true)
            end

            local moved = false

            if IsDisabledControlJustPressed(0,Config.Keys.moveForward) then posY = posY + moveStep; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.moveBackward) then posY = posY - moveStep; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.moveLeft) then posX = posX - moveStep; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.moveRight) then posX = posX + moveStep; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.moveUp) then posZ = posZ + moveStep; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.moveDown) then posZ = posZ - moveStep; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.rotateLeftZ) then heading = heading + 5; moved = true end
            if IsDisabledControlJustPressed(0,Config.Keys.rotateRightZ) then heading = heading - 5; moved = true end

            if IsDisabledControlJustPressed(0,Config.Keys.speedPlace) then
                local myInput = {
                    type = "enableinput",
                    inputType = "input",
                    button = Config.Input.Confirm,
                    placeholder = Config.Input.MinMax,
                    style = "block",
                    attributes = {
                        inputHeader = Config.Input.Speed,
                        type = "text",
                        pattern = "[0-9.]+",
                        title = Config.Input.Change,
                        style = "border-radius: 10px; background-color: ; border:none;"
                    }
                }

                local result = exports.vorp_inputs:advancedInput(myInput)
                if result and result ~= "" then
                    local testint = tonumber(result)
                    if testint and testint ~= 0 then
                        moveStep = math.max(0.01, math.min(testint, 5))
                    end
                end
            end

            if moved then
                SetEntityCoords(tempObject, posX, posY, posZ, true, true, true, false)
                SetEntityHeading(tempObject, heading)
            end

            if IsDisabledControlJustPressed(0,Config.Keys.confirmPlace) then

                isPlacing = false
                SendNUIMessage({ action = "hide" })

                local pos = GetEntityCoords(tempObject)
                local rot = vector3(0.0, 0.0, GetEntityHeading(tempObject))

                DeleteObject(tempObject)
                lastPlacedPhonograph = nil

                Wait(1000)

                TriggerServerEvent('rs_phonograph:server:saveOwner', pos, rot)
                TriggerServerEvent("rs_phonograph:givePhonograph")

                TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.Place, "generic_textures", "tick", 2000, "COLOR_GREEN")
            end

            if IsDisabledControlJustPressed(0,Config.Keys.cancelPlace) then
                isPlacing = false
                SendNUIMessage({ action = "hide" })

                if DoesEntityExist(tempObject) then
                    DeleteObject(tempObject)
                end

                lastPlacedPhonograph = nil

                TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.Cancel, "menu_textures", "cross", 2000, "COLOR_RED")
            end
        end
    end)
end)

local currentlyPlaying = {}

local function getSoundName(uniqueId)
    return tostring(uniqueId)
end

RegisterNetEvent('rs_phonograph:client:playMusic')
AddEventHandler('rs_phonograph:client:playMusic', function(uniqueId, coords, url, volume, loop, timeStamp)
    local soundName = getSoundName(uniqueId)
    local effectSoundName = soundName .. "_effect"
    local looped = loop or false

    if currentlyPlaying[uniqueId] then
        if exports.xsound:soundExists(soundName) then
            pcall(function() exports.xsound:Destroy(soundName) end)
        end
        if Config.WithEffect and exports.xsound:soundExists(effectSoundName) then
            pcall(function() exports.xsound:Destroy(effectSoundName) end)
        end
    end

    currentlyPlaying[uniqueId] = {
        url = url,
        volume = volume,
        coords = coords,
        loop = looped,
        timeStamp = timeStamp or 0
    }

    exports.xsound:PlayUrlPos(soundName, url, volume, coords, looped)
    exports.xsound:Distance(soundName, Config.SoundDistance)

    if timeStamp and timeStamp > 0 then
        Citizen.CreateThread(function()
            Citizen.Wait(500)
            if exports.xsound:soundExists(soundName) then
                pcall(function()
                    exports.xsound:setTimeStamp(soundName, timeStamp)
                end)
            end
        end)
    end

    if Config.WithEffect then
        local effectVolume = volume * Config.VolumeEffect
        exports.xsound:PlayUrlPos(effectSoundName, "https://www.youtube.com/watch?v=m5Mz9Tqs9CE", effectVolume, coords, looped)
        exports.xsound:Distance(effectSoundName, Config.SoundDistance)
    end

    if exports.xsound.onPlayEnd then
        exports.xsound:onPlayEnd(soundName, function()
            local data = currentlyPlaying[uniqueId]
            if not data then return end

            if data.loop then

                TriggerServerEvent('rs_phonograph:server:resetLoop', uniqueId)
                currentlyPlaying[uniqueId].timeStamp = 0

                if Config.WithEffect then
                    local effectVolume = data.volume * Config.VolumeEffect
                    exports.xsound:PlayUrlPos(effectSoundName, "https://www.youtube.com/watch?v=m5Mz9Tqs9CE", effectVolume, data.coords, true)
                    exports.xsound:Distance(effectSoundName, Config.SoundDistance)
                end
            else
                if Config.WithEffect and exports.xsound:soundExists(effectSoundName) then
                    pcall(function() exports.xsound:Destroy(effectSoundName) end)
                end
                if exports.xsound:soundExists(soundName) then
                    pcall(function() exports.xsound:Destroy(soundName) end)
                end
                currentlyPlaying[uniqueId] = nil
                TriggerServerEvent('rs_phonograph:server:soundEnded', uniqueId)
            end
        end)
    end
end)

RegisterNetEvent("vorp:SelectedCharacter")
AddEventHandler("vorp:SelectedCharacter", function()
    TriggerServerEvent('rs_phonograph:server:syncMusic')
end)

RegisterNetEvent('rs_phonograph:client:stopMusic')
AddEventHandler('rs_phonograph:client:stopMusic', function(uniqueId)
    local soundName = getSoundName(uniqueId)
    local effectSoundName = soundName .. "_effect"

    if exports.xsound:soundExists(soundName) then
        pcall(function() exports.xsound:Destroy(soundName) end)
    end

    if Config.WithEffect and exports.xsound:soundExists(effectSoundName) then
        pcall(function() exports.xsound:Destroy(effectSoundName) end)
    end

    currentlyPlaying[uniqueId] = nil
    TriggerServerEvent('rs_phonograph:server:soundEnded', uniqueId)
end)

RegisterNetEvent('rs_phonograph:client:toggleLoop')
AddEventHandler('rs_phonograph:client:toggleLoop', function(uniqueId, state)
    local soundName = getSoundName(uniqueId)
    local effectSoundName = soundName .. "_effect"

    if currentlyPlaying[uniqueId] then
        currentlyPlaying[uniqueId].loop = state
    end

    if state then
        if exports.xsound:soundExists(soundName) then
            pcall(function() exports.xsound:setSoundLoop(soundName, true) end)
        else
            local data = currentlyPlaying[uniqueId]
            if data then
                exports.xsound:PlayUrlPos(soundName, data.url, data.volume, data.coords, true)
                exports.xsound:Distance(soundName, Config.SoundDistance)
                if Config.WithEffect then
                    local effectVolume = data.volume * Config.VolumeEffect
                    exports.xsound:PlayUrlPos(effectSoundName, "https://www.youtube.com/watch?v=m5Mz9Tqs9CE", effectVolume, data.coords, true)
                    exports.xsound:Distance(effectSoundName, Config.SoundDistance)
                end
            end
        end

        if Config.WithEffect and exports.xsound:soundExists(effectSoundName) then
            pcall(function() exports.xsound:setSoundLoop(effectSoundName, true) end)
        end
    else
        if exports.xsound:soundExists(soundName) then
            pcall(function() exports.xsound:Destroy(soundName) end)
        end
        if Config.WithEffect and exports.xsound:soundExists(effectSoundName) then
            pcall(function() exports.xsound:Destroy(effectSoundName) end)
        end
    end
end)

RegisterNetEvent('rs_phonograph:client:notifyLoop')
AddEventHandler('rs_phonograph:client:notifyLoop', function(state)
    if state then
        TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.LoopOnMessage, "generic_textures", "tick", 3000, "COLOR_GREEN")
    else
        TriggerEvent("vorp:NotifyLeft", Config.Notify.Phono, Config.Notify.LoopOffMessage, "menu_textures", "cross", 3000, "COLOR_RED")
    end
end)

RegisterNetEvent('rs_phonograph:client:setVolume')
AddEventHandler('rs_phonograph:client:setVolume', function(uniqueId, newVolume)
    local soundName = getSoundName(uniqueId)
    local effectSoundName = soundName .. "_effect"

    if exports.xsound:soundExists(soundName) then
        pcall(function() exports.xsound:setVolume(soundName, newVolume) end)
    end

    if Config.WithEffect and exports.xsound:soundExists(effectSoundName) then
        pcall(function() exports.xsound:setVolume(effectSoundName, newVolume * Config.VolumeEffect) end)
    end

    if currentlyPlaying[uniqueId] then
        currentlyPlaying[uniqueId].volume = newVolume
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for uniqueId, entity in pairs(phonographEntities) do
            if entity and DoesEntityExist(entity) then
                DeleteObject(entity)
            end
        end
        phonographEntities = {}
        phonographData = {}
    end
end)

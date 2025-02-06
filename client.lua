local QBCore = exports['qb-core']:GetCoreObject()

-- Limit kontrolü için export
local function CheckJobLimit(jobName)
    local p = promise.new()
    
    QBCore.Functions.TriggerCallback('glitchy-limiters:server:getLimitInfo', function(result)
        p:resolve(result)
    end, jobName)
    
    return Citizen.Await(p)
end

-- Para kazanma için export
local function AddJobMoney(jobName, amount)
    local p = promise.new()
    
    QBCore.Functions.TriggerCallback('glitchy-limiters:server:addMoney', function(success, message)
        p:resolve({success = success, message = message})
    end, jobName, amount)
    
    return Citizen.Await(p)
end

-- Exportları kaydet
exports('CheckJobLimit', CheckJobLimit)
exports('AddJobMoney', AddJobMoney)


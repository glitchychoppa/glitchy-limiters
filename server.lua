local QBCore = exports['qb-core']:GetCoreObject()

print('[Limiters] Kazanç Limiti Scripti Başlatıldı.')

-- Veritabanı işlemleri için yardımcı fonksiyonlar
local function createNewLimit(citizenId, jobName)
    local currentTime = os.date('%Y-%m-%d %H:%M:%S', os.time())
    MySQL.Async.execute("INSERT INTO limiters (citizenid, jobname, earned, lastReset, usedTolerance) VALUES (?, ?, ?, ?, ?)", 
        {citizenId, jobName, 0, currentTime, false})
    return {earned = 0, lastReset = currentTime, usedTolerance = false}
end

local function checkAndResetLimit(limitData, jobName)
    if not limitData or not limitData.lastReset then return limitData end
    
    local currentTime = os.time()
    local lastResetTime = nil
    
    -- lastReset bir string ise parse et, değilse direkt kullan
    if type(limitData.lastReset) == "string" then
        lastResetTime = os.time({
            year = tonumber(limitData.lastReset:sub(1,4)),
            month = tonumber(limitData.lastReset:sub(6,7)),
            day = tonumber(limitData.lastReset:sub(9,10)),
            hour = tonumber(limitData.lastReset:sub(12,13)),
            min = tonumber(limitData.lastReset:sub(15,16)),
            sec = tonumber(limitData.lastReset:sub(18,19))
        })
    else
        lastResetTime = tonumber(limitData.lastReset)
    end
    
    if not lastResetTime then return limitData end
    
    local jobConfig = Config.Limiters[jobName]
    if not jobConfig then return limitData end
    
    -- Son sıfırlamadan bu yana geçen süreyi saat cinsinden hesapla
    local hoursSinceReset = (currentTime - lastResetTime) / 3600
    local cooldown = jobConfig.cooldown or 24 -- Eğer cooldown tanımlanmamışsa 24 saat varsayılan değer
    
    -- Belirlenen saat kadar geçtiyse sıfırla
    if hoursSinceReset >= cooldown then
        local newResetTime = os.date('%Y-%m-%d %H:%M:%S', currentTime)
        MySQL.Async.execute("UPDATE limiters SET earned = 0, lastReset = ?, usedTolerance = ? WHERE citizenid = ? AND jobname = ?",
            {newResetTime, false, limitData.citizenid, jobName})
        limitData.earned = 0
        limitData.lastReset = newResetTime
        limitData.usedTolerance = false
        print(string.format("[Limiters] %s mesleği için limit sıfırlandı. Oyuncu: %s", jobName, limitData.citizenid))
    end
    
    return limitData
end

-- Ana callback fonksiyonu
QBCore.Functions.CreateCallback('glitchy-limiters:server:getLimitInfo', function(source, cb, jobName)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, "Oyuncu bulunamadı") end
    
    local citizenId = Player.PlayerData.citizenid
    local jobConfig = Config.Limiters[jobName]
    
    if not jobConfig then return cb(false, "Meslek limiti tanımlı değil") end
    
    MySQL.Async.fetchAll("SELECT * FROM limiters WHERE citizenid = ? AND jobname = ?", 
        {citizenId, jobName}, function(result)
        if not result then return cb(false, "Veritabanı hatası") end
        
        local limitData = result[1]
        if not limitData then
            limitData = createNewLimit(citizenId, jobName)
        else
            limitData = checkAndResetLimit(limitData, jobName)
        end
        
        -- İnsiyatif değerini ekleyerek maksimum limiti hesapla
        local maxLimit = jobConfig.cash + (jobConfig.tolerance or 0)
        
        cb({
            success = limitData.earned < maxLimit,
            earned = limitData.earned,
            remaining = maxLimit - limitData.earned,
            maxLimit = maxLimit,
            baseLimit = jobConfig.cash,
            tolerance = jobConfig.tolerance or 0
        })
    end)
end)

-- Para kazanma callback'i
QBCore.Functions.CreateCallback('glitchy-limiters:server:addMoney', function(source, cb, jobName, amount)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(false, "Oyuncu bulunamadı") end
    
    local citizenId = Player.PlayerData.citizenid
    local jobConfig = Config.Limiters[jobName]
    
    if not jobConfig then return cb(false, "Meslek limiti tanımlı değil") end
    
    MySQL.Async.fetchAll("SELECT * FROM limiters WHERE citizenid = ? AND jobname = ?", 
        {citizenId, jobName}, function(result)
        if not result then return cb(false, "Veritabanı hatası") end
        
        local limitData = result[1]
        if not limitData then
            limitData = createNewLimit(citizenId, jobName)
        else
            limitData = checkAndResetLimit(limitData, jobName)
        end
        
        local baseLimit = jobConfig.cash
        local maxLimit = jobConfig.cash + (jobConfig.tolerance or 0)
        local newEarned = limitData.earned + amount
        
        -- İnsiyatif kontrolü
        if newEarned > baseLimit then
            if limitData.usedTolerance then
                return cb(false, "Tolerans hakkınızı kullandınız, normal limit: $" .. baseLimit)
            elseif newEarned > maxLimit then
                return cb(false, string.format("Maksimum limit aşılacak (Limit + Tolerans: $%s)", maxLimit))
            else
                -- İnsiyatif kullanılıyor
                MySQL.Async.execute("UPDATE limiters SET earned = ?, usedTolerance = ? WHERE citizenid = ? AND jobname = ?",
                    {newEarned, true, citizenId, jobName})
                
                cb(true, {
                    message = "Para eklendi (Tolerans kullanıldı)",
                    remaining = 0, -- İnsiyatif kullanıldığı için kalan 0
                    earned = newEarned,
                    maxLimit = maxLimit,
                    usedTolerance = true
                })
            end
        else
            -- Normal limit içinde işlem
            MySQL.Async.execute("UPDATE limiters SET earned = ? WHERE citizenid = ? AND jobname = ?",
                {newEarned, citizenId, jobName})
            
            cb(true, {
                message = "Para eklendi",
                remaining = baseLimit - newEarned,
                earned = newEarned,
                maxLimit = limitData.usedTolerance and baseLimit or maxLimit,
                usedTolerance = limitData.usedTolerance
            })
        end
    end)
end)

QBCore.Functions.CreateCallback('glitchy-limiters:server:checkLimit', function(source, cb, citizenId, jobName)
    local limit = Config.Limiters[jobName]
    if not limit then
        cb(false, "Meslek limiti tanımlı değil.")
        return
    end

    local currentTime = os.date('%Y-%m-%d %H:%M:%S', os.time())

    MySQL.Async.fetchAll("SELECT * FROM limiters WHERE citizenid = ? AND jobname = ?", {citizenId, jobName}, function(result)
        if not result then
            cb(false, "SQL sorgusu başarısız.")
            return
        end

        if #result == 0 then
            MySQL.Async.execute("INSERT INTO limiters (citizenid, jobname, earned, lastReset) VALUES (?, ?, ?, ?)", 
                {citizenId, jobName, 0, currentTime}, function(affectedRows)
                if affectedRows > 0 then
                    cb(true, "Yeni kayıt oluşturuldu.")
                else
                    cb(false, "Yeni kayıt oluşturulamadı.")
                end
            end)
        else
            local playerData = result[1]
            
            -- Otomatik limit sıfırlama kontrolü
            if checkAndResetLimit(playerData, jobName) then
                playerData.earned = 0
            end
            
            local newEarned = playerData.earned + 10

            if newEarned > limit.cash then
                cb(false, "Kazanç limiti aşıldı.")
            else
                MySQL.Async.execute("UPDATE limiters SET earned = ?, lastReset = ? WHERE citizenid = ? AND jobname = ?",
                    {newEarned, currentTime, citizenId, jobName}, function(affectedRows)
                    if affectedRows > 0 then
                        cb(true, "Kazanç güncellendi.")
                    else
                        cb(false, "Kazanç güncellenemedi.")
                    end
                end)
            end
        end
    end)
end)

-- Limit bilgisi sorgulama
QBCore.Functions.CreateCallback("glitchy-limitersserver:getLimit", function(source, cb, jobName)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        print("[Limiters] Hata: Oyuncu bulunamadı. Source:", source)
        cb(nil, "Oyuncunun limiti bulunamadı.")
        return
    end

    local citizenId = Player.PlayerData.citizenid

    MySQL.Async.fetchAll("SELECT * FROM limiters WHERE citizenid = ? AND jobname = ?", {citizenId, jobName}, function(result)
        if not result or #result == 0 then
            print("[Limiters] Limit bilgisi bulunamadı. CitizenId:", citizenId, "JobName:", jobName)
            cb(nil, "Oyuncunun limiti bulunamadı.")
        else
            print("[Limiters] Limit bilgisi bulundu. CitizenId:", citizenId, "JobName:", jobName, "Data:", json.encode(result[1]))
            cb(result[1], "Limit bilgisi alındı.")
        end
    end)
end)

QBCore.Functions.CreateCallback('glitchy-limiters:server:updsetateEarnedMoney', function(source, cb, citizenId, jobName, price)
    local currentTime = os.date('%Y-%m-%d %H:%M:%S', os.time())
    MySQL.Async.execute("UPDATE limiters SET earned = earned + ? WHERE citizenid = ? AND jobname = ?", {price, citizenId, jobName}, function(affectedRows)
        if affectedRows > 0 then
            cb(true, "Kazanç güncellendi.")
        else
            cb(false, "Kazanç güncellenemedi.")
        end
    end)
end)

-- Limit sıfırlama
QBCore.Functions.CreateCallback("glitchy-limitersserver:resetLimit", function(source, cb, jobName)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then
        print("[Limiters] Hata: Oyuncu bulunamadı. Source:", source)
        cb(false, "Oyuncu bulunamadı.")
        return
    end

    local citizenId = Player.PlayerData.citizenid
    local resetTime = os.date('%Y-%m-%d %H:%M:%S', os.time())

    MySQL.Async.execute("UPDATE limiters SET earned = 0, lastReset = ? WHERE citizenid = ? AND jobname = ?", {
        resetTime, citizenId, jobName
    }, function(affectedRows)
        if affectedRows > 0 then
            print("[Limiters] Limit sıfırlandı. CitizenId:", citizenId, "JobName:", jobName)
            cb(true, "Limit sıfırlandı.")
        else
            print("[Limiters] Hata: Limit sıfırlanamadı. CitizenId:", citizenId, "JobName:", jobName)
            cb(false, "Limit sıfırlanamadı.")
        end
    end)
end)



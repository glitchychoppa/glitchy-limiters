Config = Config or {}

Config.Limiters = {
    dealer = {
        tolerance = 700,    -- Tolerans değeri
        cash = 10000,      -- Temel limit
        cooldown = 8       -- Kaç saat sonra sıfırlanacak
    },
    miner = {
        tolerance = 500,
        cash = 8000,
        cooldown = 5       -- 5 saat sonra sıfırlanır
    }
}
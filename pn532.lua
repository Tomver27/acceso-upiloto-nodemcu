-- pn532.lua — Driver I2C minimalista para PN532 en NodeMCU
-- SDA = D8 (GPIO15), SCL = D7 (GPIO13)

local M = {}

local I2C_ID   = 0
local PN532_ADDR = 0x24  -- dirección I2C del PN532 (puede ser 0x24 o 0x48)

local SDA_PIN = 8   -- D8 = GPIO15
local SCL_PIN = 7   -- D7 = GPIO13

-- Comandos PN532
local CMD_SAMCONFIGURATION   = 0x14
local CMD_INLISTPASSIVETARGET = 0x4A

-- Escribe bytes al PN532 y espera ACK
local function write_cmd(cmd_bytes)
    local len = #cmd_bytes + 1  -- TFI + datos
    local lcs = (0xFF - (len % 256)) + 1  -- LCS
    -- Calcular DCS
    local dcs = 0xD4  -- TFI host -> PN532
    for _, b in ipairs(cmd_bytes) do
        dcs = dcs + b
    end
    dcs = (0x100 - (dcs % 256)) % 256

    i2c.start(I2C_ID)
    i2c.address(I2C_ID, PN532_ADDR, i2c.TRANSMITTER)
    i2c.write(I2C_ID, 0x00)          -- leading zero
    i2c.write(I2C_ID, 0x00, 0xFF)    -- preamble
    i2c.write(I2C_ID, len % 256)     -- LEN
    i2c.write(I2C_ID, lcs % 256)     -- LCS
    i2c.write(I2C_ID, 0xD4)          -- TFI
    for _, b in ipairs(cmd_bytes) do
        i2c.write(I2C_ID, b)
    end
    i2c.write(I2C_ID, dcs)           -- DCS
    i2c.write(I2C_ID, 0x00)          -- postamble
    i2c.stop(I2C_ID)
end

-- Lee la respuesta del PN532 (hasta max_bytes)
local function read_response(max_bytes)
    tmr.delay(20000)  -- espera 20 ms
    i2c.start(I2C_ID)
    i2c.address(I2C_ID, PN532_ADDR, i2c.RECEIVER)
    local data = i2c.read(I2C_ID, max_bytes)
    i2c.stop(I2C_ID)
    return data
end

-- Inicializa I2C y configura SAMConfiguration
function M.begin()
    i2c.setup(I2C_ID, SDA_PIN, SCL_PIN, i2c.SLOW)
    tmr.delay(50000)  -- 50 ms

    -- SAMConfiguration: modo normal, sin IRQ
    write_cmd({CMD_SAMCONFIGURATION, 0x01, 0x14, 0x01})
    tmr.delay(20000)
    read_response(10)  -- consumir ACK/respuesta
    print("[PN532] Inicializado")
end

-- Intenta leer un tag ISO14443A. Devuelve el UID como string hex o nil.
function M.read_uid()
    write_cmd({CMD_INLISTPASSIVETARGET, 0x01, 0x00})
    tmr.delay(100000)  -- 100 ms para que el tag responda

    local raw = read_response(20)
    if not raw or #raw < 12 then
        return nil
    end

    -- Formato de respuesta: preamble(3) + LEN + LCS + TFI(0xD5) + cmd(0x4B) + nTargets + ...
    -- Byte offset (base 1 en Lua string):
    --   1-3: 0x00 0x00 0xFF  (o status byte en I2C)
    --   buscar 0xD5 0x4B
    local idx = nil
    for i = 1, #raw - 1 do
        if raw:byte(i) == 0xD5 and raw:byte(i+1) == 0x4B then
            idx = i
            break
        end
    end

    if not idx then return nil end

    local n_targets = raw:byte(idx + 2)
    if n_targets < 1 then return nil end

    local uid_len = raw:byte(idx + 7)  -- NbNFCIDBytes
    if not uid_len or uid_len == 0 then return nil end

    local uid = ""
    for i = 1, uid_len do
        local b = raw:byte(idx + 7 + i)
        if b then
            uid = uid .. string.format("%02X", b)
        end
    end

    return uid
end

return M

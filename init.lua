-- Configuración
local function load_env(path)
    local env = {}

    if not file.open(path, "r") then
        return env
    end

    while true do
        local line = file.readline()
        if not line then
            break
        end

        line = line:gsub("[\r\n]+", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key and value then
                -- Soporta valores entre comillas: SSID="MiRed"
                value = value:gsub('^"(.*)"$', "%1")
                env[key] = value
            end
        end
    end

    file.close()
    return env
end

local env = load_env(".env")
local SSID = env.SSID or ""
local PASSWORD = env.PASSWORD or ""
local BRIDGE_URL = env.BRIDGE_URL or ""
local LED_CONWIFI = 5 -- GPIO14 = D5
local LED_ERROR = 6 -- GPIO12 = D6
local LED_DETECTADO = 7 -- GPIO13 = D7
local LED_REGISTRADO = 8 -- GPIO15 = D8
local CSV_FILE = "accesses.csv"

if SSID == "" or PASSWORD == "" then
    print("Error: define SSID y PASSWORD en .env")
    return
end

-- GPIO setup
gpio.mode(LED_ERROR, gpio.OUTPUT)
gpio.write(LED_ERROR, gpio.HIGH) -- encendido mientras NO hay WiFi
gpio.mode(LED_CONWIFI, gpio.OUTPUT)
gpio.write(LED_CONWIFI, gpio.LOW)
gpio.mode(LED_REGISTRADO, gpio.OUTPUT)
gpio.write(LED_REGISTRADO, gpio.LOW)
gpio.mode(LED_DETECTADO, gpio.OUTPUT)
gpio.write(LED_DETECTADO, gpio.LOW)

local last_uid = ""
local sending = false
local wifi_connected = false

local function save_to_csv(uid)
    if file.open(CSV_FILE, "a+") then
        file.write(uid .. "\n")
        file.close()
        print("UID guardado offline: " .. uid)
    else
        print("Error: no se pudo abrir CSV")
    end
end

local function upload_csv()
    if not file.open(CSV_FILE, "r") then
        print("Sin registros offline pendientes")
        sending = false
        return
    end

    local lines = {}
    while true do
        local line = file.readline()
        if not line then break end
        line = line:gsub("[\r\n]+", "")
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    file.close()

    if #lines == 0 then
        file.remove(CSV_FILE)
        sending = false
        return
    end

    local json_parts = {}
    for _, uid in ipairs(lines) do
        table.insert(json_parts, '"' .. uid .. '"')
    end
    local body = '{"uids":[' .. table.concat(json_parts, ",") .. "]}"
    print("Subiendo " .. #lines .. " registros offline...")

    http.post(BRIDGE_URL .. "/upload_csv", "Content-Type: application/json", body, function(c, d)
        sending = false
        if c == 200 then
            local ok, result = pcall(sjson.decode, d)
            if ok and result and result.failed and #result.failed > 0 then
                print(#result.failed .. " registros fallidos, conservando en CSV")
                if file.open(CSV_FILE, "w") then
                    for _, f_uid in ipairs(result.failed) do
                        file.write(f_uid .. "\n")
                    end
                    file.close()
                end
            else
                print("Todos los registros subidos, eliminando CSV")
                file.remove(CSV_FILE)
            end
            gpio.write(LED_REGISTRADO, gpio.HIGH)
            local t = tmr.create()
            t:alarm(3000, tmr.ALARM_SINGLE, function()
                gpio.write(LED_REGISTRADO, gpio.LOW)
            end)
        else
            print("Error subiendo CSV: " .. tostring(c))
            gpio.write(LED_ERROR, gpio.HIGH)
            local t = tmr.create()
            t:alarm(3000, tmr.ALARM_SINGLE, function()
                gpio.write(LED_ERROR, gpio.LOW)
            end)
        end
    end)
end

-- Conectar WiFi primero para no interferir con la inicialización del stack
print("WiFi SSID: " .. SSID)
wifi.setmode(wifi.STATION)
wifi.sta.config({
    ssid = SSID,
    pwd = PASSWORD
})
wifi.sta.connect()

-- Iniciar NFC con un pequeño delay para que el stack WiFi arranque primero
local nfc_init_t = tmr.create()
nfc_init_t:alarm(1000, tmr.ALARM_SINGLE, function()
    local nfc = require("pn532")
    nfc.begin()
    print("NFC iniciado")

    local nfc_timer = tmr.create()
    nfc_timer:alarm(1000, tmr.ALARM_AUTO, function()
        if sending then return end
        local uid = nfc.read_uid()
        if uid then
            if uid ~= last_uid then
                last_uid = uid
                print("Tarjeta detectada UID: " .. uid)
                gpio.write(LED_DETECTADO, gpio.HIGH)
                collectgarbage("collect")
                if wifi_connected then
                    -- Modo online: enviar directamente
                    sending = true
                    local nfc_body = '{"uid":"' .. uid .. '"}'
                    http.post(BRIDGE_URL .. "/access", "Content-Type: application/json", nfc_body, function(c, d)
                        sending = false
                        gpio.write(LED_DETECTADO, gpio.LOW)
                        local blink_pin = (c == 201) and LED_REGISTRADO or LED_ERROR
                        if c == 201 then
                            print("Entrada registrada para UID: " .. uid)
                        else
                            print("Error al registrar entrada: " .. tostring(c))
                        end
                        gpio.write(blink_pin, gpio.HIGH)
                        local t = tmr.create()
                        t:alarm(3000, tmr.ALARM_SINGLE, function()
                            gpio.write(blink_pin, gpio.LOW)
                        end)
                    end)
                else
                    -- Modo offline: guardar en CSV
                    save_to_csv(uid)
                    gpio.write(LED_DETECTADO, gpio.LOW)
                end
            end
            -- si uid == last_uid, tarjeta sigue puesta, no hacer nada
        else
            last_uid = "" -- se retiró la tarjeta, permite releer
        end
    end)
end)

-- Chequear conexión cada 2 segundos
local wifi_timer = tmr.create()
wifi_timer:alarm(2000, tmr.ALARM_AUTO, function()
    local status = wifi.sta.status()
    if status == 5 then
        gpio.write(LED_CONWIFI, gpio.HIGH)
        gpio.write(LED_ERROR, gpio.LOW)
        local ip = wifi.sta.getip()
        print("Conectado! IP: " .. ip)
        wifi_timer:unregister()
        wifi_connected = true

        -- Registrar conexión y subir registros offline
        local mac = wifi.sta.getmac()
        local body = '{"mac_address":"' .. mac .. '","ip_address":"' .. ip .. '"}'
        http.post(BRIDGE_URL .. "/connection", "Content-Type: application/json", body, function(code, data)
            if code == 201 then
                print("Conexion registrada en BD")
            elseif code == 404 then
                print("Modulo no registrado en BD, se omite el insert")
            else
                print("Error al registrar conexion: " .. tostring(code))
            end
            -- Subir registros offline acumulados
            sending = true
            upload_csv()
        end)
    else
        print("Esperando WiFi... status: " .. tostring(status))
    end
end)
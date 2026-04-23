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
local SSID         = env.SSID or ""
local PASSWORD     = env.PASSWORD or ""
local SUPABASE_URL = env.SUPABASE_URL or ""
local SUPABASE_KEY = env.SUPABASE_KEY or ""
local BRIDGE_URL = env.BRIDGE_URL or ""
local LED_PIN  = 1  -- GPIO5 = D1
local LED_PIN2 = 2  -- GPIO4 = D2

print(i2c)

local function wifi_status_text(code)
    if code == 0 then return "IDLE" end
    if code == 1 then return "CONNECTING" end
    if code == 2 then return "WRONG_PASSWORD" end
    if code == 3 then return "NO_AP_FOUND" end
    if code == 4 then return "CONNECT_FAIL" end
    if code == 5 then return "GOT_IP" end
    return "UNKNOWN"
end

if SSID == "" or PASSWORD == "" then
    print("Error: define SSID y PASSWORD en .env")
    return
end

print("WiFi SSID: " .. SSID)
print("WiFi password length: " .. string.len(PASSWORD))

-- D2 encendido mientras NO hay conexión WiFi
gpio.mode(LED_PIN2, gpio.OUTPUT)
gpio.write(LED_PIN2, gpio.HIGH)

-- D1 encendido cuando ya hay conexión WiFi
gpio.mode(LED_PIN, gpio.OUTPUT)
gpio.write(LED_PIN, gpio.LOW)

-- Conectar WiFi
wifi.setmode(wifi.STATION)
wifi.sta.config({ssid = SSID, pwd = PASSWORD})
wifi.sta.connect()

-- Chequear conexión cada 2 segundos
local wifi_timer = tmr.create()
wifi_timer:alarm(2000, tmr.ALARM_AUTO, function()
    local status = wifi.sta.status()
    if status == 5 then
        gpio.write(LED_PIN, gpio.HIGH)
        gpio.write(LED_PIN2, gpio.LOW)
        local ip = wifi.sta.getip()
        print("Conectado! IP: " .. ip)
        wifi_timer:unregister()  -- para el chequeo

        -- Registrar conexión enviando MAC e IP al bridge HTTP local
        local mac = wifi.sta.getmac()
        local body = '{"mac_address":"' .. mac .. '","ip_address":"' .. ip .. '"}'
        print("Esta es la ip del bridge: " .. BRIDGE_URL)
        http.post(BRIDGE_URL .. "/connection", "Content-Type: application/json", body, function(code, data)
            if code == 201 then
                print("Conexion registrada en BD")
            elseif code == 404 then
                print("Modulo no registrado en BD, se omite el insert")
            else
                print("Error al registrar conexion: " .. tostring(code))
            end
        end)

        -- Iniciar lectura NFC una vez conectado
        local nfc = require("pn532")
        nfc.begin()

        local nfc_timer = tmr.create()
        nfc_timer:alarm(1000, tmr.ALARM_AUTO, function()
            local uid = nfc.read_uid()
            if uid then
                print("Tag detectado: " .. uid)
                local nfc_body = '{"uid":"' .. uid .. '"}'
                http.post(BRIDGE_URL .. "/access", "Content-Type: application/json", nfc_body, function(c, d)
                    if c == 200 then
                        print("Acceso permitido")
                        gpio.write(LED_PIN, gpio.LOW)
                        tmr.create():alarm(500, tmr.ALARM_SINGLE, function()
                            gpio.write(LED_PIN, gpio.HIGH)
                        end)
                    elseif c == 403 then
                        print("Acceso denegado")
                    else
                        print("Error al verificar acceso: " .. tostring(c))
                    end
                end)
            end
        end)
    else
        print("Esperando... status: " .. tostring(status))
    end
end)
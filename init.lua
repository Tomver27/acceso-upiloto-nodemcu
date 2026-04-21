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
local SSID     = env.SSID or ""
local PASSWORD = env.PASSWORD or ""
local LED_PIN  = 1  -- GPIO5 = D1
local LED_PIN2 = 2  -- GPIO4 = D2

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
wifi.sta.config(SSID, PASSWORD)
wifi.sta.connect()

-- Chequear conexión cada 2 segundos
tmr.alarm(1, 2000, 1, function()
    local status = wifi.sta.status()
    if status == 5 then
        gpio.write(LED_PIN, gpio.HIGH)
        gpio.write(LED_PIN2, gpio.LOW)
        print("Conectado! IP: " .. wifi.sta.getip())
        tmr.stop(1)  -- para el chequeo
    else
        print("Esperando... status: " .. status .. " (" .. wifi_status_text(status) .. ")")
    end
end)
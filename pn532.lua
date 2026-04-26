local M={}
local ID=0
local ADDR=0x24
local SDA=2
local SCL=1
local SAM=0x14
local INL=0x4A

local function wcmd(bytes)
  local len=#bytes+1
  local lcs=(0xFF-(len%256)+1)%256
  local dcs=0xD4
  for _,b in ipairs(bytes) do dcs=dcs+b end
  dcs=(0x100-(dcs%256))%256
  i2c.start(ID)
  i2c.address(ID,ADDR,i2c.TRANSMITTER)
  i2c.write(ID,0x00,0x00,0xFF)
  i2c.write(ID,len%256,lcs%256,0xD4)
  for _,b in ipairs(bytes) do i2c.write(ID,b) end
  i2c.write(ID,dcs,0x00)
  i2c.stop(ID)
end

local function wrdy(ms)
  local tries=math.floor(ms/10)
  for i=1,tries do
    tmr.delay(10000)
    i2c.start(ID)
    local ok=i2c.address(ID,ADDR,i2c.RECEIVER)
    if not ok then i2c.stop(ID) return false end
    local b=i2c.read(ID,1)
    i2c.stop(ID)
    if b and b:byte(1)==0x01 then return true end
    if i%10==0 then tmr.wdclr() end
  end
  return false
end

-- Lee N bytes crudos (sin sub(2), sin procesar)
local function rraw(n, ms)
  ms = ms or 200
  if not wrdy(ms) then return nil end
  i2c.start(ID)
  i2c.address(ID, ADDR, i2c.RECEIVER)
  local d = i2c.read(ID, n)
  i2c.stop(ID)
  return d
end

function M.begin()
  i2c.setup(ID,SDA,SCL,i2c.SLOW)
  tmr.delay(50000)
  wcmd({SAM,0x01,0x14,0x00})
  -- Leer ACK (6 bytes)
  rraw(6, 500)
  -- Leer respuesta SAMConfiguration
  rraw(10, 500)
  print("[PN532] OK")
end

function M.read_uid()
  wcmd({INL,0x01,0x00})

  -- Paso 1: leer y descartar el ACK (6 bytes)
  local ack = rraw(6, 500)
  if not ack then return nil end

  -- Paso 2: leer la respuesta real (hasta 30 bytes)
  local raw = rraw(30, 1000)
  if not raw then return nil end

  -- Buscar D5 4B en la respuesta real
  local idx
  for i=1,#raw-1 do
    if raw:byte(i)==0xD5 and raw:byte(i+1)==0x4B then idx=i break end
  end
  if not idx then return nil end          -- sin tarjeta
  if raw:byte(idx+2) < 1 then return nil end  -- ntargets = 0

  local ul = raw:byte(idx+7)
  if not ul or ul == 0 then return nil end

  local uid = ""
  for i=1,ul do
    local b = raw:byte(idx+7+i)
    if b then uid = uid..string.format("%02x", b) end
  end
  return uid
end

return M
# Acceso uPiloto - NodeMCU

Programa para el dispositivo NodeMCU que se conecta a internet y realiza peticiones POST a una base de datos de Supabase para mantener registro de los estudiantes que entran.

## Configuración

Crea un archivo `.env` basado en `.env.example` con tus credenciales WiFi:

```
SSID=tu_red_wifi
PASSWORD=tu_password_wifi
```

## Comandos

### Ver archivos en el dispositivo

```bash
nodemcu-tool fsinfo --port /dev/ttyUSB0 --baud 9600
```

### Subir archivos al dispositivo

```bash
nodemcu-tool upload init.lua .env --port /dev/ttyUSB0 --baud 9600
```

### Ver terminal del dispositivo

```bash
nodemcu-tool terminal --port /dev/ttyUSB0 --baud 9600
```

-- ============================================================
-- POR QUÉ SE NECESITA UN BRIDGE HTTP LOCAL
-- ============================================================

El NodeMCU (ESP8266) no puede conectarse directamente a la API REST de Supabase
por dos limitaciones de hardware:

1. **RAM insuficiente para el handshake TLS moderno**
   Supabase está detrás de Cloudflare, que exige TLS 1.2+ con cipher suites
   basados en ECDHE (intercambio de claves Diffie-Hellman sobre curvas elípticas).
   El ESP8266 solo dispone de ~40 KB de RAM libre en tiempo de ejecución; la
   negociación ECDHE requiere mantener en memoria los parámetros de la curva,
   los certificados de la cadena y los buffers de registro TLS simultáneamente,
   lo que supera ampliamente esa capacidad. El handshake nunca completa y la
   conexión cae con error de timeout.

2. **Almacenamiento limitado para certificados raíz**
   Verificar el certificado del servidor requiere tener almacenada la CA raíz
   (o al menos el certificado del servidor). La flash del ESP8266 disponible
   para el sistema de archivos SPIFFS es de ~1–2 MB compartidos con el firmware
   y el código de la aplicación, y la cadena de certificados de Cloudflare ocupa
   varios KB adicionales. Más importante aún, el módulo `tls` del firmware
   NodeMCU 3.x no expone una API para cargar CAs personalizadas desde archivos,
   por lo que la validación del servidor no es posible sin recompilar el firmware.

**Solución adoptada:** un servidor Flask (`bridge.py`) corre en la misma red local
que el NodeMCU. El dispositivo hace una petición HTTP plana (sin TLS) al bridge,
que sí dispone de los recursos necesarios para establecer la conexión HTTPS con
Supabase y reenviar la operación.

**Solución adoptada:** esta solución no durará por siempre, seguramente se cambie el 
dispositivo o por su defecto se despliegue un servicio en la nube con nextjs que funcione de intermediario

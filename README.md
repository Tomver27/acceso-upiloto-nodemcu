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

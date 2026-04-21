import os
import requests
from flask import Flask, request, jsonify
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_KEY"]
BRIDGE_PORT  = int(os.environ.get("BRIDGE_PORT", 5000))

app = Flask(__name__)

SUPABASE_HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
}


@app.post("/connection")
def register_connection():
    data = request.get_json(silent=True, force=True)
    if not data or "mac_address" not in data or "ip_address" not in data:
        return jsonify({"error": "Se requieren mac_address e ip_address"}), 400

    mac_address = data["mac_address"]
    ip_address  = data["ip_address"]

    print(f"[DEBUG] MAC recibida: {mac_address!r}")

    # Buscar el modulo por MAC en Supabase
    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/Modules",
        headers=SUPABASE_HEADERS,
        params={"mac_address": f"ilike.{mac_address}", "select": "id,mac_address"},
        timeout=10,
    )

    print(f"[DEBUG] Supabase status: {resp.status_code}")
    print(f"[DEBUG] Supabase respuesta: {resp.text!r}")

    if resp.status_code != 200:
        return jsonify({"error": f"Error consultando Modules: {resp.status_code}", "detail": resp.text}), 502

    modules = resp.json()
    if not modules:
        return jsonify({"error": "Modulo no registrado en BD"}), 404

    id_module = modules[0]["id"]

    # Insertar en Connections
    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/Connections",
        headers={**SUPABASE_HEADERS, "Prefer": "return=minimal"},
        json={"ip_address": ip_address, "id_module": id_module},
        timeout=10,
    )

    if resp.status_code == 201:
        return jsonify({"ok": True, "id_module": id_module}), 201

    return jsonify({"error": f"Error insertando en Connections: {resp.status_code}", "detail": resp.text}), 502


if __name__ == "__main__":
    print(f"Bridge escuchando en http://0.0.0.0:{BRIDGE_PORT}/connection")
    app.run(host="0.0.0.0", port=BRIDGE_PORT)

import os
import requests
from flask import Flask, request, jsonify
from datetime import datetime  # por si necesitas start_date manual
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

SUPABASE_SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", SUPABASE_KEY)
SUPABASE_SERVICE_HEADERS = {
    "apikey": SUPABASE_SERVICE_KEY,
    "Authorization": f"Bearer {SUPABASE_SERVICE_KEY}",
    "Content-Type": "application/json",
}

# Variable global para guardar el lab del módulo activo
current_module = {"id": None, "id_lab": None}

@app.post("/connection")
def register_connection():
    data = request.get_json(silent=True, force=True)
    if not data or "mac_address" not in data or "ip_address" not in data:
        return jsonify({"error": "Se requieren mac_address e ip_address"}), 400

    mac_address = data["mac_address"]
    ip_address  = data["ip_address"]

    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/Modules",
        headers=SUPABASE_HEADERS,
        params={"mac_address": f"ilike.{mac_address}", "select": "id,mac_address,id_lab"},  # <-- agregar id_lab
        timeout=10,
    )

    if resp.status_code != 200:
        return jsonify({"error": f"Error consultando Modules: {resp.status_code}"}), 502

    modules = resp.json()
    if not modules:
        return jsonify({"error": "Modulo no registrado en BD"}), 404

    # Guardar globalmente para usarlo en /access
    current_module["id"]     = modules[0]["id"]
    current_module["id_lab"] = modules[0].get("id_lab")

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/Connections",
        headers={**SUPABASE_HEADERS, "Prefer": "return=minimal"},
        json={"ip_address": ip_address, "id_module": current_module["id"]},
        timeout=10,
    )

    if resp.status_code == 201:
        print(f"[DEBUG] Módulo {current_module['id']} conectado, lab={current_module['id_lab']}")
        return jsonify({"ok": True}), 201

    return jsonify({"error": f"Error en Connections: {resp.status_code}"}), 502


@app.post("/access")
def register_entry():
    data = request.get_json(silent=True, force=True)
    if not data or "uid" not in data:
        return jsonify({"error": "Se requiere uid"}), 400

    card_uuid = data["uid"].upper()
    id_lab    = current_module.get("id_lab")

    print(f"[DEBUG] UID recibido: {card_uuid!r}, id_lab={id_lab}")

    payload = {"card_uuid": card_uuid, "granted": True}
    if id_lab:
        payload["id_lab"] = id_lab

    print(f"[DEBUG] Payload a Entries: {payload}")

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/Entries",
        headers={**SUPABASE_SERVICE_HEADERS, "Prefer": "return=representation"},
        json=payload,
        timeout=10,
    )

    print(f"[DEBUG] Supabase Entries status: {resp.status_code}")
    print(f"[DEBUG] Supabase Entries respuesta: {resp.text!r}")

    if resp.status_code in (200, 201):
        return jsonify({"ok": True, "card_uuid": card_uuid}), 201

    return jsonify({"error": f"Error en Entries: {resp.status_code}", "detail": resp.text}), 502


if __name__ == "__main__":
    print(f"Bridge escuchando en http://0.0.0.0:{BRIDGE_PORT}/connection")
    app.run(host="0.0.0.0", port=BRIDGE_PORT)

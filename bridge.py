import os
import requests
from flask import Flask, request, jsonify
from datetime import datetime, timezone
from dotenv import load_dotenv

load_dotenv(override=True)

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
        print(f"[DEBUG] Supabase Modules status: {resp.status_code}, body: {resp.text!r}, apy_key: {SUPABASE_KEY!r} ")
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

    print(f"[DEBUG] Supabase Connections status: {resp.status_code}, body: {resp.text!r}")
    return jsonify({"error": f"Error en Connections: {resp.status_code}"}), 502


@app.post("/access")
def register_entry():
    data = request.get_json(silent=True, force=True)
    if not data or "uid" not in data:
        return jsonify({"error": "Se requiere uid"}), 400

    card_uuid = data["uid"].upper()
    id_lab    = current_module.get("id_lab")
    print('[DEBUG] current_module global: ', current_module)
    print(f"[DEBUG] UID recibido: {card_uuid!r}, id_lab={id_lab}")

    # Buscar entrada abierta (end_date IS NULL) para esta tarjeta en este lab
    check_params = {
        "card_uuid": f"eq.{card_uuid}",
        "end_date": "is.null",
        "select": "id",
    }
    if id_lab:
        check_params["id_lab"] = f"eq.{id_lab}"

    check_resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/Entries",
        headers=SUPABASE_SERVICE_HEADERS,
        params=check_params,
        timeout=10,
    )
    print(f"[DEBUG] Búsqueda entrada abierta status: {check_resp.status_code}, body: {check_resp.text!r}")

    if check_resp.status_code == 200 and check_resp.json():
        # Existe entrada abierta → cerrarla con end_date = ahora
        entry_id = check_resp.json()[0]["id"]
        end_date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        print(f"[DEBUG] Usando service key (primeros 20 chars): {SUPABASE_SERVICE_KEY[:20]!r}")
        patch_resp = requests.patch(
            f"{SUPABASE_URL}/rest/v1/Entries",
            headers={**SUPABASE_SERVICE_HEADERS, "Prefer": "return=representation"},
            params={"id": f"eq.{entry_id}"},
            json={"end_date": end_date},
            timeout=10,
        )
        print(f"[DEBUG] PATCH Entries status: {patch_resp.status_code}, body: {patch_resp.text!r}")
        if patch_resp.status_code in (200, 201) and patch_resp.json():
            return jsonify({"ok": True, "action": "closed", "card_uuid": card_uuid, "entry_id": entry_id}), 201
        if patch_resp.status_code in (200, 201) and not patch_resp.json():
            print("[DEBUG] PATCH devolvió [] — RLS bloqueó el UPDATE. Verifica SUPABASE_SERVICE_KEY en .env")
            return jsonify({"error": "RLS bloqueó la actualización: configura SUPABASE_SERVICE_KEY con el service_role key"}), 502
        return jsonify({"error": f"Error cerrando entrada: {patch_resp.status_code}", "detail": patch_resp.text}), 502

    # No hay entrada abierta → crear nueva
    payload = {"card_uuid": card_uuid, "granted": True, "id_reason": 1}
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
        return jsonify({"ok": True, "action": "opened", "card_uuid": card_uuid}), 201

    return jsonify({"error": f"Error en Entries: {resp.status_code}", "detail": resp.text}), 502


def _process_entry(card_uuid, id_lab):
    """Lógica compartida de abrir/cerrar entrada. Retorna (ok: bool, accion: str)."""
    card_uuid = card_uuid.upper()

    check_params = {
        "card_uuid": f"eq.{card_uuid}",
        "end_date": "is.null",
        "select": "id",
    }
    if id_lab:
        check_params["id_lab"] = f"eq.{id_lab}"

    check_resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/Entries",
        headers=SUPABASE_SERVICE_HEADERS,
        params=check_params,
        timeout=10,
    )

    if check_resp.status_code == 200 and check_resp.json():
        entry_id = check_resp.json()[0]["id"]
        end_date = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
        patch_resp = requests.patch(
            f"{SUPABASE_URL}/rest/v1/Entries",
            headers={**SUPABASE_SERVICE_HEADERS, "Prefer": "return=representation"},
            params={"id": f"eq.{entry_id}"},
            json={"end_date": end_date},
            timeout=10,
        )
        if patch_resp.status_code in (200, 201) and patch_resp.json():
            return True, "closed"
        return False, f"Error cerrando entrada {entry_id}: {patch_resp.status_code}"

    payload = {"card_uuid": card_uuid, "granted": True, "id_reason": 1}
    if id_lab:
        payload["id_lab"] = id_lab

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/Entries",
        headers={**SUPABASE_SERVICE_HEADERS, "Prefer": "return=representation"},
        json=payload,
        timeout=10,
    )
    if resp.status_code in (200, 201):
        return True, "opened"
    return False, f"Error en Entries: {resp.status_code}"


@app.post("/upload_csv")
def upload_csv():
    data = request.get_json(silent=True, force=True)
    if not data or "uids" not in data:
        return jsonify({"error": "Se requieren uids"}), 400

    uids   = data["uids"]
    id_lab = current_module.get("id_lab")
    processed, failed = [], []

    for uid in uids:
        try:
            ok, action = _process_entry(uid, id_lab)
            if ok:
                print(f"[DEBUG] upload_csv OK {uid.upper()}: {action}")
                processed.append(uid.upper())
            else:
                print(f"[DEBUG] upload_csv FAIL {uid.upper()}: {action}")
                failed.append(uid.upper())
        except Exception as e:
            print(f"[DEBUG] upload_csv excepción {uid}: {e}")
            failed.append(uid.upper())

    print(f"[DEBUG] upload_csv: {len(processed)} procesados, {len(failed)} fallidos")
    return jsonify({"processed": processed, "failed": failed}), 200


if __name__ == "__main__":
    print(f"Bridge escuchando en http://0.0.0.0:{BRIDGE_PORT}/connection")
    app.run(host="0.0.0.0", port=BRIDGE_PORT)

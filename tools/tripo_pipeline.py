#!/usr/bin/env python3
"""Gera personagens com esqueleto e animações via Tripo API:
imagem -> modelo 3D -> verificação -> rig -> animações (retarget) -> GLB.
A chave vai no header Authorization (TRIPO_API_KEY; num ambiente com proxy
que injeta a credencial, qualquer valor serve).
Uso: python3 tools/tripo_pipeline.py nome:imagem.jpg [...]
Saída: assets/models/rigged/<nome>.glb (+ log de tarefas em tools/tripo_tasks.json)"""
import json, os, sys, time, urllib.request, uuid

API = "https://api.tripo3d.ai/v2/openapi"
KEY = os.environ.get("TRIPO_API_KEY", "proxy-injected")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/models/rigged")
LOG = os.path.join(ROOT, "tools/tripo_tasks.json")
UA = "horda-tools/1.0"
ANIMS = ["preset:idle", "preset:walk", "preset:run", "preset:slash", "preset:hurt"]

def req(method, path, body=None, headers=None):
    h = {"Authorization": "Bearer " + KEY, "User-Agent": UA}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    h.update(headers or {})
    r = urllib.request.Request(API + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(r, timeout=120) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"{method} {path} -> {e.code}: {e.read().decode()[:500]}")

def upload(path):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{os.path.basename(path)}\"\r\n"
            f"Content-Type: image/jpeg\r\n\r\n").encode() + open(path, "rb").read() + f"\r\n--{boundary}--\r\n".encode()
    r = urllib.request.Request(API + "/upload", data=body, method="POST", headers={
        "Authorization": "Bearer " + KEY, "User-Agent": UA, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(r, timeout=120) as resp:
        d = json.load(resp)
    return d["data"]["image_token"]

def task(body):
    d = req("POST", "/task", body)
    if d.get("code") != 0:
        raise RuntimeError(f"task {body['type']}: {d}")
    return d["data"]["task_id"]

def wait(tid, label):
    while True:
        d = req("GET", f"/task/{tid}")["data"]
        st = d.get("status")
        if st in ("success", "failed", "cancelled", "banned", "expired", "unknown"):
            print(f"  {label}: {st}", flush=True)
            if st != "success":
                raise RuntimeError(f"{label} {st}: {json.dumps(d)[:600]}")
            return d
        time.sleep(5)

def model_url(d):
    o = d.get("output", {})
    return o.get("model") or o.get("pbr_model") or o.get("base_model")

def log(name, key, value):
    logd = json.load(open(LOG)) if os.path.exists(LOG) else {}
    logd.setdefault(name, {})[key] = value
    json.dump(logd, open(LOG, "w"), indent=1)

def run(name, image):
    os.makedirs(OUT, exist_ok=True)
    prev = (json.load(open(LOG)) if os.path.exists(LOG) else {}).get(name, {})
    print(f"[{name}]", flush=True)
    model_tid = prev.get("model")
    if not model_tid:
        tok = upload(image)
        model_tid = task({"type": "image_to_model", "file": {"type": "jpg", "file_token": tok},
                          "texture": True, "pbr": False, "face_limit": 12000, "auto_size": True})
        log(name, "model", model_tid)
    wait(model_tid, "modelo")
    rig_tid = prev.get("rig")
    if not rig_tid:
        chk = wait(task({"type": "animate_prerigcheck", "original_model_task_id": model_tid}), "pré-checagem")
        out = chk.get("output", {})
        print(f"  riggable={out.get('riggable')} tipo={out.get('rig_type')}", flush=True)
        rig_tid = task({"type": "animate_rig", "original_model_task_id": model_tid, "out_format": "glb",
                        "rig_type": out.get("rig_type") or "biped", "spec": "tripo"})
        log(name, "rig", rig_tid)
    wait(rig_tid, "rig")
    anim_tid = prev.get("anim")
    if not anim_tid:
        anim_tid = task({"type": "animate_retarget", "original_model_task_id": rig_tid, "out_format": "glb",
                         "animations": ANIMS, "bake_animation": True, "export_with_geometry": True})
        log(name, "anim", anim_tid)
    d = wait(anim_tid, "animações")
    url = model_url(d)
    if not url:
        raise RuntimeError(f"sem URL de saída: {json.dumps(d)[:600]}")
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=300) as r:
        open(os.path.join(OUT, name + ".glb"), "wb").write(r.read())
    print(f"  -> assets/models/rigged/{name}.glb", flush=True)

if __name__ == "__main__":
    for job in sys.argv[1:]:
        n, img = job.split(":", 1)
        try:
            run(n, img)
        except Exception as e:
            print(f"  ERRO {n}: {e}", flush=True)
    print("saldo:", req("GET", "/user/balance")["data"], flush=True)

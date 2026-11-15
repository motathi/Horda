#!/usr/bin/env python3
"""Baixa pacotes gratuitos (CC0) do itch.io pelo fluxo "pague quanto quiser" com valor zero.
Uso: python3 tools/itch_fetch.py <pasta_destino> usuario/jogo [...]
Lista os arquivos de cada pacote e baixa os .zip para <pasta_destino>/<jogo>/.
Os pacotes usados no jogo e suas licenças estão em assets/third_party/CREDITS.md."""
import http.cookiejar, json, os, re, sys, urllib.parse, urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) horda-tools/1.0"
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

def get(url):
    r = urllib.request.Request(url, headers={"User-Agent": UA})
    with opener.open(r, timeout=120) as resp:
        return resp.read().decode("utf-8", "replace")

def post(url, data):
    body = urllib.parse.urlencode(data).encode()
    r = urllib.request.Request(url, data=body, headers={"User-Agent": UA, "X-Requested-With": "XMLHttpRequest"})
    with opener.open(r, timeout=120) as resp:
        return json.loads(resp.read().decode())

def csrf(html):
    m = re.search(r'name="csrf_token"\s+value="([^"]+)"', html) or re.search(r'csrf_token"\s*:\s*"([^"]+)"', html)
    if not m:
        raise RuntimeError("csrf_token não encontrado")
    return m.group(1)

def fetch(dest, user, game, want=None):
    base = f"https://{user}.itch.io/{game}"
    page = get(base)
    tok = csrf(page)
    dl = post(base + "/download_url", {"csrf_token": tok})
    if "url" not in dl:
        raise RuntimeError(f"sem download gratuito: {dl}")
    dpage = get(dl["url"])
    tok = csrf(dpage)
    uploads = re.findall(r'data-upload_id="(\d+)".*?class="upload_name"[^>]*>.*?<strong[^>]*title="([^"]+)"[^>]*>.*?class="file_size"[^>]*><span>([^<]+)<', dpage, re.S)
    out = os.path.join(dest, game)
    os.makedirs(out, exist_ok=True)
    for uid, name, size in uploads:
        print(f"  [{game}] {name} ({size})", flush=True)
        if want and not any(w.lower() in name.lower() for w in want):
            continue
        f = post(f"{base}/file/{uid}?source=game_download", {"csrf_token": tok})
        path = os.path.join(out, name)
        if os.path.exists(path):
            continue
        r = urllib.request.Request(f["url"], headers={"User-Agent": UA})
        with opener.open(r, timeout=600) as resp, open(path, "wb") as fh:
            while chunk := resp.read(1 << 20):
                fh.write(chunk)
        print(f"    -> {path}", flush=True)

if __name__ == "__main__":
    dest = sys.argv[1]
    for spec in sys.argv[2:]:
        # usuario/jogo[:filtro1,filtro2] — filtros escolhem arquivos pelo nome
        spec, _, flt = spec.partition(":")
        user, game = spec.split("/")
        try:
            fetch(dest, user, game, [x for x in flt.split(",") if x] or None)
        except Exception as e:
            print(f"  ERRO {spec}: {e}", flush=True)

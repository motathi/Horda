#!/usr/bin/env python3
"""Baixa conteúdos do OpenGameArt.org somente se a página declarar licença CC0.
Uso: python3 tools/oga_fetch.py <pasta_destino> slug1 slug2 ...
Grava <destino>/<slug>/ com os arquivos e um meta.json (título, autor, licença, URL)."""
import html, json, os, re, sys, urllib.request

UA = "Mozilla/5.0 (X11; Linux x86_64) horda-tools/1.0"

def get(url, binary=False):
    r = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(r, timeout=300) as resp:
        data = resp.read()
    return data if binary else data.decode("utf-8", "replace")

def fetch(dest, slug):
    url = f"https://opengameart.org/content/{slug}"
    page = get(url)
    lic_block = re.search(r'field-name-field-art-licenses(.*?)field-name-collect|field-name-field-art-licenses(.*?)$', page, re.S)
    lic_text = (lic_block.group(1) or lic_block.group(2) or "") if lic_block else ""
    lics = re.findall(r"class='license-name'>([^<]+)<", lic_text)
    if not any("CC0" in l for l in lics):
        print(f"  PULADO {slug}: licença {lics}")
        return
    title = html.unescape(re.search(r'<h2[^>]*>([^<]+)</h2>', page).group(1)) if re.search(r'<h2[^>]*>([^<]+)</h2>', page) else slug
    author = re.search(r'field-name-author-submitter.*?<a href="/users/[^"]+">([^<]+)</a>', page, re.S)
    files = sorted(set(re.findall(r'href="(https://opengameart\.org/sites/default/files/[^"]+)"', page)))
    out = os.path.join(dest, slug)
    os.makedirs(out, exist_ok=True)
    for f in files:
        name = urllib.request.unquote(f.rsplit("/", 1)[1])
        if name.lower().endswith((".png", ".jpg", ".gif")):
            continue
        p = os.path.join(out, name)
        if not os.path.exists(p):
            open(p, "wb").write(get(f, True))
        print(f"  {slug}: {name} ({os.path.getsize(p) // 1024} KB)")
    json.dump({"title": title, "author": author.group(1) if author else "?", "license": [l for l in lics if "CC0" in l][0],
               "url": url, "files": [urllib.request.unquote(f.rsplit("/", 1)[1]) for f in files]},
              open(os.path.join(out, "meta.json"), "w"), ensure_ascii=False, indent=1)

if __name__ == "__main__":
    for s in sys.argv[2:]:
        try:
            fetch(sys.argv[1], s)
        except Exception as e:
            print(f"  ERRO {s}: {e}")

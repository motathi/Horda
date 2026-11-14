#!/usr/bin/env python3
"""Generate game art via BytePlus ARK (Seedream). Usage:
  ARK_API_KEY=... python3 tools/gen_image.py tools/art_prompts.json [name ...]
Reads a JSON list of {name, out, size, prompt}; skips files that already exist."""
import json, os, sys, urllib.request, concurrent.futures as cf

API = "https://ark.ap-southeast.bytepluses.com/api/v3/images/generations"
MODEL = os.environ.get("ARK_IMAGE_MODEL", "dola-seedream-5-0-pro-260628")
STYLE = os.environ.get("ARK_STYLE", "")

def gen(job, root):
    out = os.path.join(root, job["out"])
    if os.path.exists(out):
        return f"skip {job['name']}"
    body = json.dumps({"model": MODEL, "prompt": job["prompt"] + STYLE, "size": job.get("size", "2048x2048"),
                       "response_format": "url", "watermark": False}).encode()
    req = urllib.request.Request(API, body, {"Authorization": "Bearer " + os.environ["ARK_API_KEY"],
                                             "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        data = json.load(r)
    if "data" not in data:
        return f"FAIL {job['name']}: {data}"
    url = data["data"][0]["url"]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".download"
    urllib.request.urlretrieve(url, tmp)
    os.replace(tmp, out)
    return f"ok {job['name']} -> {job['out']}"

if __name__ == "__main__":
    jobs = json.load(open(sys.argv[1]))
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    names = set(sys.argv[2:])
    jobs = [j for j in jobs if not names or j["name"] in names]
    with cf.ThreadPoolExecutor(6) as ex:
        for res in ex.map(lambda j: gen(j, root), jobs):
            print(res, flush=True)

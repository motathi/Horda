#!/usr/bin/env python3
"""Pós-processa GLBs gerados por IA: adiciona normais suaves (quando ausentes),
centraliza a base do modelo na origem (pés/chão em y=0) e normaliza a altura.
Uso: python3 tools/fix_glb.py entrada.glb saida.glb [altura_metros]"""
import json, struct, sys
import numpy as np

def read_glb(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF'
    off = 12; js = None; binc = b''
    while off < len(b):
        ln, typ = struct.unpack('<II', b[off:off+8])
        chunk = b[off+8:off+8+ln]
        if typ == 0x4E4F534A: js = json.loads(chunk)
        elif typ == 0x004E4942: binc = chunk
        off += 8 + ln
    return js, bytearray(binc)

COMP = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}

def get_acc(js, binc, i):
    a = js['accessors'][i]; bv = js['bufferViews'][a['bufferView']]
    fmt, sz = COMP[a['componentType']]; n = NCOMP[a['type']]
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    dt = {'f': np.float32, 'I': np.uint32, 'H': np.uint16, 'B': np.uint8}[fmt]
    stride = bv.get('byteStride', sz * n)
    if stride == sz * n:
        arr = np.frombuffer(bytes(binc[start:start + a['count'] * sz * n]), dtype=dt).reshape(-1, n)
    else:
        raw = np.frombuffer(bytes(binc[start:start + a['count'] * stride]), dtype=np.uint8).reshape(-1, stride)
        arr = raw[:, :sz * n].copy().view(dt).reshape(-1, n)
    return arr.copy()

def add_buffer(js, binc, data, target=None):
    while len(binc) % 4: binc.append(0)
    off = len(binc); binc.extend(data.tobytes())
    bv = {'buffer': 0, 'byteOffset': off, 'byteLength': data.nbytes}
    if target: bv['target'] = target
    js['bufferViews'].append(bv)
    return len(js['bufferViews']) - 1

def set_acc_data(js, binc, i, arr):
    """Substitui os dados de um accessor (mesmo tamanho) apontando para um novo bufferView."""
    a = js['accessors'][i]
    a['bufferView'] = add_buffer(js, binc, arr.astype(np.float32), 34962)
    a['byteOffset'] = 0
    a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()

def main(src, dst, height=None):
    js, binc = read_glb(src)
    # Caixa delimitadora global para centralizar/escalar.
    allpos = []
    for m in js['meshes']:
        for p in m['primitives']:
            allpos.append(get_acc(js, binc, p['attributes']['POSITION']))
    allp = np.concatenate(allpos)
    mn, mx = allp.min(0), allp.max(0)
    scale = 1.0
    if height:
        scale = float(height) / max(1e-6, (mx[1] - mn[1]))
    shift = np.array([-(mn[0] + mx[0]) / 2, -mn[1], -(mn[2] + mx[2]) / 2], dtype=np.float32)
    for m in js['meshes']:
        for p in m['primitives']:
            pi = p['attributes']['POSITION']
            pos = (get_acc(js, binc, pi) + shift) * scale
            set_acc_data(js, binc, pi, pos)
            if 'NORMAL' not in p['attributes']:
                idx = get_acc(js, binc, p['indices']).reshape(-1, 3).astype(np.int64) if 'indices' in p else np.arange(len(pos)).reshape(-1, 3)
                v0, v1, v2 = pos[idx[:, 0]], pos[idx[:, 1]], pos[idx[:, 2]]
                fn = np.cross(v1 - v0, v2 - v0)
                nrm = np.zeros_like(pos)
                for k in range(3):
                    np.add.at(nrm, idx[:, k], fn)
                l = np.linalg.norm(nrm, axis=1, keepdims=True); l[l == 0] = 1
                nrm = (nrm / l).astype(np.float32)
                bvi = add_buffer(js, binc, nrm, 34962)
                js['accessors'].append({'bufferView': bvi, 'componentType': 5126, 'count': len(nrm), 'type': 'VEC3'})
                p['attributes']['NORMAL'] = len(js['accessors']) - 1
    # Nós sem transformações estranhas (o deslocamento já foi aplicado nos vértices).
    for n in js.get('nodes', []):
        for k in ('translation', 'scale', 'matrix'):
            n.pop(k, None)
    for mat in js.get('materials', []):
        pbr = mat.setdefault('pbrMetallicRoughness', {})
        pbr.setdefault('metallicFactor', 0.0)
        pbr['metallicFactor'] = min(pbr['metallicFactor'], 0.1)
    js['buffers'] = [{'byteLength': len(binc)}]
    while len(binc) % 4: binc.append(0)
    jb = json.dumps(js, separators=(',', ':')).encode()
    while len(jb) % 4: jb += b' '
    out = b'glTF' + struct.pack('<II', 2, 12 + 8 + len(jb) + 8 + len(binc))
    out += struct.pack('<II', len(jb), 0x4E4F534A) + jb + struct.pack('<II', len(binc), 0x004E4942) + bytes(binc)
    open(dst, 'wb').write(out)
    print(f"{dst}: bbox {np.round(mn,3)}..{np.round(mx,3)} scale {scale:.3f}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)

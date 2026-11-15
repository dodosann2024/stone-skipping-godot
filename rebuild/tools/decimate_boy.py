#!/usr/bin/env python3
"""Decimate the approved boy to <=25k triangles, keeping UVs and skin weights.

Head-weighted vertices keep their original positions so the face does not slide.
Animation bytes in the GLB are left where they are. Only the mesh accessors shrink.
"""

import json
import struct
from pathlib import Path

import numpy as np
import fast_simplification

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "boy" / "boy.glb"
DST = ROOT / "rebuild" / "assets" / "boy.glb"
TARGET = 24500
HEAD = {38, 39, 40}


def read_glb(path: Path):
    data = path.read_bytes()
    length, ctype = struct.unpack_from("<I4s", data, 12)
    assert ctype == b"JSON"
    js = json.loads(data[20 : 20 + length])
    bin_off = 20 + length
    blen, btype = struct.unpack_from("<I4s", data, bin_off)
    assert btype == b"BIN\x00"
    blob = bytearray(data[bin_off + 8 : bin_off + 8 + blen])
    return js, blob, data, length


def accessor_bytes(js, blob, index):
    acc = js["accessors"][index]
    view = js["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return acc, start


def main() -> None:
    source = SRC if SRC.exists() else DST
    js, blob, raw, json_len = read_glb(source)
    prim = js["meshes"][0]["primitives"][0]
    attrs = prim["attributes"]
    pos_acc, pos_at = accessor_bytes(js, blob, attrs["POSITION"])
    nrm_acc, nrm_at = accessor_bytes(js, blob, attrs["NORMAL"])
    uv_acc, uv_at = accessor_bytes(js, blob, attrs["TEXCOORD_0"])
    jn_acc, jn_at = accessor_bytes(js, blob, attrs["JOINTS_0"])
    w_acc, w_at = accessor_bytes(js, blob, attrs["WEIGHTS_0"])
    ix_acc, ix_at = accessor_bytes(js, blob, prim["indices"])
    n = pos_acc["count"]
    pos = np.frombuffer(blob, dtype=np.float32, count=n * 3, offset=pos_at).reshape(n, 3).copy()
    uv = np.frombuffer(blob, dtype=np.float32, count=n * 2, offset=uv_at).reshape(n, 2).copy()
    joints = np.frombuffer(blob, dtype=np.uint8, count=n * 4, offset=jn_at).reshape(n, 4).copy()
    weights = np.frombuffer(blob, dtype=np.float32, count=n * 4, offset=w_at).reshape(n, 4).copy()
    ix_count = ix_acc["count"]
    indices = np.frombuffer(blob, dtype=np.uint16, count=ix_count, offset=ix_at).astype(np.int32)
    tris = indices.reshape(-1, 3).copy()
    print(f"source tris={len(tris)} verts={n}", flush=True)
    new_pos, new_tris, collapses = fast_simplification.simplify(
        pos.astype(np.float64),
        tris,
        target_count=TARGET,
        agg=2.0,
        return_collapses=True,
    )
    _pts, replay_tris, mapping = fast_simplification.replay_simplification(pos, tris, collapses)
    # replay_tris indexes the compacted survivor list. Use simplify()'s placed
    # vertices when the counts match, otherwise the replay points.
    if len(new_tris) != len(replay_tris):
        new_tris = replay_tris
        new_pos = _pts
    mapping = np.asarray(mapping)
    used = np.unique(new_tris)
    # Compact to the vertices the new triangles reference.
    remap = np.full(int(mapping.max()) + 1, -1, dtype=np.int64)
    remap[used] = np.arange(len(used))
    compact_pos = np.asarray(new_pos, dtype=np.float64)[used]
    compact_tris = remap[new_tris]
    out_n = len(compact_pos)
    out_uv = np.zeros((out_n, 2), dtype=np.float32)
    out_j = np.zeros((out_n, 4), dtype=np.uint8)
    out_w = np.zeros((out_n, 4), dtype=np.float32)
    head_w = np.zeros(n, dtype=np.float32)
    for jid in HEAD:
        head_w += weights[:, 0] * (joints[:, 0] == jid)
        head_w += weights[:, 1] * (joints[:, 1] == jid)
        head_w += weights[:, 2] * (joints[:, 2] == jid)
        head_w += weights[:, 3] * (joints[:, 3] == jid)
    buckets = [[] for _ in range(out_n)]
    for old_i, new_i in enumerate(mapping):
        if new_i < 0:
            continue
        dst = int(remap[new_i]) if new_i < len(remap) else -1
        if dst >= 0:
            buckets[dst].append(old_i)
    for dst, olds in enumerate(buckets):
        if not olds:
            continue
        olds_a = np.array(olds, dtype=np.int64)
        d = np.linalg.norm(pos[olds_a] - compact_pos[dst], axis=1)
        order = np.argsort(d)
        pick = int(olds_a[order[0]])
        for candidate in olds_a[order[:8]]:
            if head_w[candidate] > 0.45 and d[np.where(olds_a == candidate)[0][0]] < 0.02:
                pick = int(candidate)
                break
        out_uv[dst] = uv[pick]
        out_j[dst] = joints[pick]
        out_w[dst] = weights[pick]
        if head_w[pick] > 0.45:
            compact_pos[dst] = pos[pick]
    # Normals from the compact faces.
    out_nrm = np.zeros((out_n, 3), dtype=np.float64)
    v0 = compact_pos[compact_tris[:, 0]]
    v1 = compact_pos[compact_tris[:, 1]]
    v2 = compact_pos[compact_tris[:, 2]]
    face_n = np.cross(v1 - v0, v2 - v0)
    for k in range(3):
        np.add.at(out_nrm, compact_tris[:, k], face_n)
    lens = np.linalg.norm(out_nrm, axis=1)
    lens[lens < 1e-8] = 1.0
    out_nrm /= lens[:, None]
    out_pos = compact_pos.astype(np.float32)
    out_tris = compact_tris.astype(np.uint32)
    if out_pos.shape[0] > 65535:
        raise SystemExit(f"vertex count {out_pos.shape[0]} does not fit uint16 indices")
    if len(out_tris) > TARGET + 500:
        raise SystemExit(f"triangle count {len(out_tris)} is above the budget")
    print(f"decimated tris={len(out_tris)} verts={out_pos.shape[0]}", flush=True)

    def store(at, arr):
        rawb = arr.astype(arr.dtype, copy=False).tobytes()
        blob[at : at + len(rawb)] = rawb

    store(pos_at, out_pos)
    store(nrm_at, out_nrm.astype(np.float32))
    store(uv_at, out_uv)
    store(jn_at, out_j)
    store(w_at, out_w)
    store(ix_at, out_tris.astype(np.uint16).reshape(-1))
    pos_acc["count"] = int(out_pos.shape[0])
    pos_acc["min"] = out_pos.min(axis=0).tolist()
    pos_acc["max"] = out_pos.max(axis=0).tolist()
    for acc in (nrm_acc, uv_acc, jn_acc, w_acc):
        acc["count"] = int(out_pos.shape[0])
    nrm_acc["min"] = out_nrm.min(axis=0).tolist()
    nrm_acc["max"] = out_nrm.max(axis=0).tolist()
    ix_acc["count"] = int(out_tris.size)
    ix_acc["max"] = [int(out_tris.max())]
    ix_acc["min"] = [0]
    body = bytes(blob)
    while len(body) % 4 != 0:
        body += b"\x00"
    js["buffers"][0]["byteLength"] = len(body)
    new_json = json.dumps(js, separators=(",", ":")).encode("utf8")
    while len(new_json) % 4 != 0:
        new_json += b" "
    json_chunk = struct.pack("<I4s", len(new_json), b"JSON") + new_json
    bin_chunk = struct.pack("<I4s", len(body), b"BIN\x00") + body
    total = 12 + len(json_chunk) + len(bin_chunk)
    out = struct.pack("<4sII", b"glTF", 2, total) + json_chunk + bin_chunk
    if DST.is_symlink() or DST.resolve() == SRC.resolve():
        DST.unlink()
    DST.write_bytes(out)
    print(f"wrote {DST} bytes={DST.stat().st_size}", flush=True)


if __name__ == "__main__":
    main()

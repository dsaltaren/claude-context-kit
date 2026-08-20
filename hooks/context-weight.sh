#!/bin/bash
# PostToolUse: mide el PESO REAL que cada resultado de herramienta deja en el
# contexto, en bytes, y avisa por peso en vez de por numero de llamadas.
#
# Por que existe: contar llamadas es un proxy malo. Un Read de 674 KB suma 1 al
# contador y pesa como seis capturas. Lo que se paga es el tamano del contexto
# reenviado en cada llamada, no cuantas veces se llamo.
#
# Guarda en el mismo fichero de estado, bajo la clave "weight":
#   bytes      total acumulado de resultados desde el ultimo /compact
#   img_bytes  cuanto de eso son imagenes
#   top        los peores ofensores por herramienta
#
# Solo observa. No bloquea nada. Ante cualquier error sale 0.

input=$(cat)

/usr/bin/python3 -c '
import sys, json, os, re

WARN_MB = 8     # primer aviso
STEP_MB = 5     # y luego cada 5 MB

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

sid = str(d.get("session_id") or "")
if not sid:
    sys.exit(0)
tool = str(d.get("tool_name") or "?")

tr = d.get("tool_response")
if tr is None:
    sys.exit(0)
try:
    size = len(json.dumps(tr))
except Exception:
    try:
        size = len(str(tr))
    except Exception:
        sys.exit(0)

is_img = False
if isinstance(tr, dict):
    is_img = bool(tr.get("isImage"))
if "screenshot" in tool or "get_fill_image" in tool:
    is_img = True

state_dir = os.path.join(os.path.expanduser("~"), ".claude", "state", "session-size")
safe = re.sub(r"[^A-Za-z0-9_.-]", "_", sid)[:80]
path = os.path.join(state_dir, safe)

try:
    with open(path) as f:
        st = json.load(f)
except Exception:
    st = {}

w = st.get("weight")
if not isinstance(w, dict):
    w = {}
prev_mb = int(w.get("bytes", 0)) // (1024 * 1024)

w["bytes"] = int(w.get("bytes", 0)) + size
if is_img:
    w["img_bytes"] = int(w.get("img_bytes", 0)) + size

top = w.get("top")
if not isinstance(top, dict):
    top = {}
top[tool] = int(top.get(tool, 0)) + size
# Solo los 12 peores, para que el fichero de estado no crezca sin limite.
w["top"] = dict(sorted(top.items(), key=lambda kv: -kv[1])[:12])
try:
    tmp = path + ".tmp"
    # Releer justo antes de escribir: session-size-warn.sh escribe el mismo
    # fichero y cada uno debe tocar solo sus propias claves.
    try:
        with open(path) as f:
            cur = json.load(f)
        if not isinstance(cur, dict):
            cur = {}
    except Exception:
        cur = dict(st)
    cur["weight"] = w
    with open(tmp, "w") as f:
        json.dump(cur, f)
    os.replace(tmp, path)
except Exception:
    pass

now_mb = w["bytes"] // (1024 * 1024)
crossed = (now_mb >= WARN_MB and prev_mb < WARN_MB) or (
    now_mb >= WARN_MB and (now_mb - WARN_MB) // STEP_MB > (prev_mb - WARN_MB) // STEP_MB)

if crossed:
    img_mb = w.get("img_bytes", 0) / 1048576.0
    worst = sorted(w["top"].items(), key=lambda kv: -kv[1])[:3]
    detalle = ", ".join("%s %.1f MB" % (k.replace("mcp__", ""), v / 1048576.0)
                        for k, v in worst)
    print(json.dumps({"systemMessage":
        "[peso] %d MB de resultados desde el ultimo /compact (%.1f MB en imagenes). "
        "Lo mas pesado: %s. Esto se reenvia entero en cada llamada: considera "
        "/compact o delegar lo que queda a un subagente." % (now_mb, img_mb, detalle)}))
' <<< "$input"

exit 0

#!/bin/bash
# PreToolUse hook para mcp__paper__get_screenshot.
#
# Deniega la captura de un nodo de Paper que ya se ha capturado varias veces
# SIN haberlo editado entre medias. Recapturar un nodo que no ha cambiado
# devuelve una imagen identica: no aporta informacion y cuesta ~100 KB que se
# reenvian en cada llamada posterior de la sesion.
#
# NO limita el bucle normal de trabajo: tras cualquier edicion del nodo el
# contador se reinicia y se puede volver a capturar.
#
# Umbrales:
#   - captura 1, 2, 3 del mismo nodo sin editar -> pasan
#   - captura 4 en adelante -> DENEGADA con motivo
#
# Escape: PAPER_SHOT_GUARD=off
#
# Estado compartido con session-size-warn.sh:
#   ~/.claude/state/session-size/<session_id>   clave "clean" = capturas sin editar
#
# Ante cualquier error deja pasar la captura. Nunca bloquea por accidente.

if [ "$PAPER_SHOT_GUARD" = "off" ]; then
  exit 0
fi

input=$(cat)
STATE_DIR="$HOME/.claude/state/session-size"
mkdir -p "$STATE_DIR" 2>/dev/null

/usr/bin/python3 -c '
import sys, json, os, re

LIMIT = 3  # capturas permitidas sin edicion intermedia; la siguiente se deniega

def allow():
    sys.exit(0)

try:
    d = json.load(sys.stdin)
except Exception:
    allow()

ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    allow()

nid = ti.get("nodeId") or ti.get("node_id") or ""
if not isinstance(nid, str) or not nid:
    allow()  # sin nodo identificable no podemos decidir: dejar pasar
nid = nid[:60]

sid = str(d.get("session_id") or "unknown")
state_dir = os.path.join(os.path.expanduser("~"), ".claude", "state", "session-size")
safe = re.sub(r"[^A-Za-z0-9_.-]", "_", sid)[:80]
path = os.path.join(state_dir, safe)

clean = {}
try:
    with open(path) as f:
        st = json.load(f)
    c = st.get("clean", {})
    if isinstance(c, dict):
        clean = {k: int(v) for k, v in c.items()}
except Exception:
    pass

n = clean.get(nid, 0)

if n >= LIMIT:
    reason = (
        "Bloqueado: ya capturaste %s %d veces sin editarlo. La imagen seria identica "
        "y cuesta ~100 KB que se reenvian en cada llamada posterior. "
        "Si verificas un valor (color, tamano, espaciado, binding) usa get_computed_styles: "
        "900 B en vez de 100 KB. Si el nodo cambio de verdad, edita primero. "
        "Si necesitas saltarte esto: PAPER_SHOT_GUARD=off." % (nid, n)
    )
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        },
        "systemMessage": reason,
    }
    print(json.dumps(out))
    sys.exit(0)

allow()
' <<< "$input"

exit 0

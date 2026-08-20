#!/bin/bash
# UserPromptSubmit hook: cuando Danny ejecuta /compact, reinicia el contador de
# sesion para que la statusline vuelva a verde.
#
# Por que: el contador cuenta llamadas acumuladas de la sesion. /compact aligera
# el contexto pero no borra el fichero de estado, asi que la statusline seguia
# en rojo despues de compactar y el aviso dejaba de significar nada.
#
# Tras el reset, la statusline mide llamadas DESDE EL ULTIMO COMPACT, que es lo
# que de verdad indica cuanto pesa el contexto actual.
#
# Guarda "compacts" para no perder el historico de cuantas veces se compacto.
# No borra "nodes" (historico de recapturas por nodo) ni "clean" (contador que
# consume paper-shot-guard.sh): el nodo sigue sin cambiar tras un compact, asi
# que recapturarlo sigue siendo igual de inutil.
#
# Ante cualquier error sale 0 y no toca nada.

set -uo pipefail

INPUT=$(cat)

/usr/bin/python3 -c '
import sys, json, os, re

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

prompt = str(d.get("prompt") or "")
if not re.match(r"^\s*/compact\b", prompt):
    sys.exit(0)

sid = str(d.get("session_id") or "")
if not sid:
    sys.exit(0)

safe = re.sub(r"[^A-Za-z0-9_.-]", "_", sid)[:80]
base = os.path.join(os.path.expanduser("~"), ".claude", "state", "session-size")
path = os.path.join(base, safe)

try:
    with open(path) as f:
        st = json.load(f)
except Exception:
    st = {}

before_calls = int(st.get("calls", 0) or 0)
before_shots = int(st.get("shots", 0) or 0)

before_mb = 0.0
try:
    before_mb = int((st.get("weight") or {}).get("bytes", 0)) / 1048576.0
except Exception:
    pass

st["calls"] = 0
st["shots"] = 0
# El peso SI se reinicia: compactar descarga de verdad los resultados viejos.
st["weight"] = {}
st["compacts"] = int(st.get("compacts", 0) or 0) + 1
st["last_compact_at_calls"] = before_calls

try:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, path)
except Exception:
    sys.exit(0)

# El nudge del hook Stop vuelve a poder avisar tras el proximo umbral.
try:
    os.remove(path + ".nudged")
except Exception:
    pass

print(json.dumps({"systemMessage":
    "Contador reiniciado: se compacto tras %d llamadas, %d capturas y %.0f MB "
    "de resultados. La statusline vuelve a contar desde cero."
    % (before_calls, before_shots, before_mb)}))
' <<< "$INPUT"

exit 0

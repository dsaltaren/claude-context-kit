#!/bin/bash
# Stop hook: al terminar un turno, si la sesion ya pesa demasiado, obliga a
# Claude a decirselo a Danny EN LA RESPUESTA, en vez de dejarlo en un contador
# que se puede ignorar.
#
# Por que existe: la statusline avisa de forma pasiva y es facil no mirarla.
# Este hook hace que el aviso aparezca escrito, una vez por umbral, en el punto
# exacto en el que Danny decide si sigue o compacta.
#
# NO compacta ni corta nada. Solo hace que la propuesta se diga en voz alta.
#
# Umbrales: 300 llamadas (primer aviso), luego cada 200.
# Anti-repeticion: guarda el ultimo umbral avisado para no repetirse cada turno.
#
# Ante cualquier error sale 0 y no dice nada.

set -uo pipefail

INPUT=$(cat)

/usr/bin/python3 -c '
import sys, json, os, re

# Se avisa por % de contexto real (leido del transcript), no por numero de
# llamadas: una llamada puede pesar 900 B o 700 KB. Las llamadas quedan solo
# como respaldo si el transcript no se puede leer.
PCT_FIRST = 55    # first warning, as % of the context window
PCT_STEP  = 15    # then every 15 points
FIRST = 300   # fallback: first warning by call count
STEP  = 200   # fallback: then every 200 calls

try:
    d = json.load(sys.stdin)
except Exception:
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
    calls = int(st.get("calls", 0))
    shots = int(st.get("shots", 0))
except Exception:
    sys.exit(0)

# Peso real: la ultima linea del transcript con uso de tokens dice cuanto de la
# ventana esta ocupado ahora mismo. Es el dato honesto; las llamadas son proxy.
pct = None
tokens = 0
try:
    tp = str(d.get("transcript_path") or "")
    if tp and os.path.exists(tp):
        size = os.path.getsize(tp)
        with open(tp, "rb") as f:
            if size > 400000:
                f.seek(size - 400000)
                f.readline()
            tail = f.read().decode("utf-8", "replace").splitlines()
        for line in reversed(tail):
            try:
                obj = json.loads(line)
            except Exception:
                continue
            u = (obj.get("message") or {}).get("usage") or {}
            tot = (int(u.get("input_tokens", 0) or 0)
                   + int(u.get("cache_read_input_tokens", 0) or 0)
                   + int(u.get("cache_creation_input_tokens", 0) or 0))
            if tot > 0:
                tokens = tot
                # Ventana de 1M en este perfil; si cambia, el respaldo por
                # llamadas sigue cubriendo el caso.
                pct = min(100, int(tot * 100 / 1000000))
                break
except Exception:
    pct = None

# Umbral absoluto: 200K tokens es donde una sesion deja de ser normal, sea cual
# sea la ventana. En una de 1M eso es solo el 21%, asi que esperar al 55% dejaria
# pasar sesiones enormes sin decir nada.
TOK_FIRST = 200000
pct_real = pct
if tokens and tokens >= TOK_FIRST and (pct is None or pct < PCT_FIRST):
    pct = max(pct or 0, PCT_FIRST)   # entra por el mismo camino de avisos

if pct is not None:
    if pct < PCT_FIRST:
        sys.exit(0)
    tier = PCT_FIRST + ((pct - PCT_FIRST) // PCT_STEP) * PCT_STEP
    tier = 10000 + tier   # own range, cannot collide with the call-count tiers
else:
    if calls < FIRST:
        sys.exit(0)
    tier = FIRST + ((calls - FIRST) // STEP) * STEP

# No repetir el mismo umbral en cada turno.
seen_path = path + ".nudged"
try:
    with open(seen_path) as f:
        if int(f.read().strip() or 0) >= tier:
            sys.exit(0)
except Exception:
    pass

try:
    with open(seen_path, "w") as f:
        f.write(str(tier))
except Exception:
    pass

# Dos canales a la vez, porque van a destinatarios distintos:
#
#   reason           -> lo VE DANNY en el chat, como linea de aviso destacada
#   additionalContext -> lo lee CLAUDE, para que ademas lo diga en su respuesta
#
# "ok": false NO bloquea nada aqui: solo hace que el reason se pinte.

if tokens:
    medida = "%dK tokens of context" % (tokens // 1000)
    if pct_real is not None:
        medida += " (%d%% of the window)" % pct_real
elif pct_real is not None:
    medida = "%d%% of the context window" % pct_real
else:
    medida = "%d tool calls" % calls
reason = ("Context: %s in this session (%d screenshots). "
          "Good moment for /handoff and then /compact." % (medida, shots))

msg = (
    "CONTEXT WARNING, addressed to you (the assistant), not to the user: this "
    "session now holds %s (%d screenshots). The whole context is resent on every "
    "call, so cost is already growing fast. "
    "Before doing anything else, tell the user in one line that it is a good "
    "moment to run /handoff (dump decisions and dead ends to disk) and then "
    "/compact. That order matters: compacting first destroys what needed writing "
    "down. Wait for their decision, do not compact yourself. "
    "If you already said this in this same turn, do not repeat it."
) % (medida, shots)

# NO se usa "ok": false. En un hook Stop eso pide continuar el turno, que es
# justo lo que hizo entrar en bucle a stop-hot-md.sh en junio. El turno debe
# terminar limpio; el aviso viaja por systemMessage y additionalContext.
print(json.dumps({
    "systemMessage": reason,
    "hookSpecificOutput": {
        "hookEventName": "Stop",
        "additionalContext": msg
    }
}))
' <<< "$INPUT"

exit 0

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
PCT_FIRST = 55    # primer aviso, en % de la ventana de contexto
PCT_STEP  = 15    # y luego cada 15 puntos
FIRST = 300   # respaldo: primer aviso por llamadas
STEP  = 200   # respaldo: y luego cada 200 llamadas

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
                # Ventana de 1M en este perfil; si cambia, el respaldo por
                # llamadas sigue cubriendo el caso.
                pct = min(100, int(tot * 100 / 1000000))
                break
except Exception:
    pct = None

if pct is not None:
    if pct < PCT_FIRST:
        sys.exit(0)
    tier = PCT_FIRST + ((pct - PCT_FIRST) // PCT_STEP) * PCT_STEP
    tier = 10000 + tier   # espacio propio, no colisiona con el de llamadas
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

medida = ("%d%% de la ventana de contexto" % pct) if pct is not None else (
         "%d llamadas" % calls)
reason = ("Contexto: %s en esta sesion (%d capturas). "
          "Buen momento para /handoff y luego /compact." % (medida, shots))

msg = (
    "AVISO DE CONTEXTO, dirigido a ti (Claude), no a Danny: esta sesion ocupa ya "
    "%s (%d capturas). El contexto se reenvia entero en cada llamada, asi que el "
    "coste crece rapido. "
    "Antes de seguir, dile a Danny en una linea que conviene ejecutar /handoff "
    "(volcar decisiones y trampas a disco) y despues /compact. Ese orden importa: "
    "compactar primero borra justo lo que habia que volcar. "
    "Espera su decision, no compactes tu. "
    "Si ya se lo has dicho en este mismo turno, no lo repitas."
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

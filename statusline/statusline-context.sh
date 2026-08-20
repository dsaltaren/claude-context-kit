#!/bin/bash
# Statusline de Claude Code.
#
# Usa los campos NATIVOS que Claude Code ya entrega por stdin (context_window,
# cost, rate_limits): no hace falta estimar nada leyendo el transcript.
# Comprobado el 19-ago-2026 contra el payload real (version 2.1.235).
#
# Muestra, en este orden de prioridad:
#   1. % de contexto usado      -> cuando compactar
#   2. coste de la sesion en $  -> la senal honesta del gasto
#   3. ventana de 5h y 7 dias   -> cuando te vas a quedar sin cuota
#   4. capturas de Paper        -> unico dato propio, del hook session-size-warn
#
# Colores de paleta 256, no los 8 basicos: el verde y el amarillo ANSI estandar
# se ven casi iguales en algunos temas y aqui el color ES la senal.
#
# Ante cualquier error imprime una linea minima y sale 0: nunca rompe el prompt.

input=$(cat)

/usr/bin/python3 -c '
import sys, json, os, re

RESET = "\033[0m"
DIM   = "\033[2m"
GREEN = "\033[38;5;114m"
YELL  = "\033[1;38;5;214m"
RED   = "\033[1;38;5;203m"

try:
    d = json.load(sys.stdin)
except Exception:
    print("")
    sys.exit(0)

def dig(*path, default=0):
    cur = d
    for k in path:
        if not isinstance(cur, dict):
            return default
        cur = cur.get(k)
        if cur is None:
            return default
    return cur

parts = []

cwd = d.get("cwd") or dig("workspace", "current_dir", default="")
if cwd:
    parts.append(DIM + os.path.basename(str(cwd).rstrip("/")) + RESET)

model = dig("model", "display_name", default="")
if model:
    parts.append(DIM + str(model).replace(" (1M context)", " 1M") + RESET)

# 1. Contexto. Es lo que decide cuando compactar.
used = dig("context_window", "used_percentage", default=None)
if isinstance(used, (int, float)):
    used = int(used)
    # En una ventana de 1M el porcentaje engana: 22% son ya 215K tokens, mas de
    # lo que cabria entero en una ventana estandar. Se muestran los tokens
    # absolutos junto al %, y el aviso salta al pasar de 200K, que es donde una
    # sesion deja de ser normal sea cual sea el tamano de la ventana.
    tok = dig("context_window", "total_input_tokens", default=0)
    tok = int(tok) if isinstance(tok, (int, float)) else 0
    grande = bool(dig("context_window", "exceeds_200k_tokens", default=False)) or tok > 200000

    col = RED if used >= 75 else YELL if (used >= 50 or grande) else GREEN
    # Con los tokens absolutos delante, el % es el dato secundario: se muestra
    # Los tokens absolutos van junto al %: el porcentaje contra una ventana
    # una ventana estandar entera.
    if tok >= 10000:
        txt = "%d%% ctx (%dK)" % (used, tok // 1000)
    else:
        txt = "%d%% ctx" % used
    # Mismo consejo que el hook Stop, para que las dos senales no se contradigan:
    # handoff primero, compact despues. Compactar antes borra lo que ibas a volcar.
    # El consejo va entero: cabe en una ventana de ancho normal, y el hook
    # Stop repite la version larga por escrito de todas formas.
    if used >= 75:
        txt += " -> /handoff + /compact NOW"
    elif used >= 50 or grande:
        txt += " -> /handoff and /compact"
    parts.append(col + txt + RESET)

# Quien paga esto. Se lee del .claude.json de la config activa (CLAUDE_CONFIG_DIR
# o ~/.claude): con suscripcion plana el $ es un precio sombra, no gasto real.
cuenta, plano, dudoso = "", False, False
try:
    cfgdir = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")
    # Para la config por defecto la credencial viva es ~/.claude.json (fuera del
    # directorio). Dentro puede quedar un .claude.json antiguo de otra cuenta:
    # comprobado el 19-ago-2026, habia tres y dos eran restos de junio. Se elige
    # SIEMPRE el mas recientemente modificado, que es el que la CLI esta usando.
    cand = [os.path.join(cfgdir, ".claude.json")]
    if os.path.abspath(cfgdir) == os.path.abspath(os.path.expanduser("~/.claude")):
        cand.append(os.path.expanduser("~/.claude.json"))
    cand = [c for c in cand if os.path.exists(c)]
    cand.sort(key=os.path.getmtime, reverse=True)
    # Si los candidatos discrepan en cuenta y el segundo se toco hace poco,
    # /login pudo escribir en otro sitio: mejor avisar que mostrar la cuenta
    # equivocada con confianza.
    if len(cand) > 1:
        try:
            mails = []
            for c in cand[:2]:
                with open(c) as f:
                    mails.append(str((json.load(f).get("oauthAccount") or {})
                                     .get("emailAddress") or ""))
            if mails[0] != mails[1]:
                dt = os.path.getmtime(cand[0]) - os.path.getmtime(cand[1])
                if dt < 60:   # menos de un minuto de diferencia: ambiguo
                    dudoso = True
        except Exception:
            pass
    for c in cand:
        with open(c) as f:
            acc = (json.load(f).get("oauthAccount") or {})
        mail = str(acc.get("emailAddress") or "")
        tier = str(acc.get("organizationRateLimitTier") or "")
        seat = str(acc.get("seatTier") or "")
        if mail:
            cuenta = mail.split("@")[0]
            # Both Claude subscriptions (personal Max, Team seat) and API keys
            # report a dollar figure, but a subscription never bills per token:
            # on a flat plan that number is a shadow price, not a charge.
            if "max" in tier.lower() or "pro" in tier.lower():
                cuenta += " max"
                plano = True
            elif seat and seat.lower() != "none":
                cuenta += " team"
                plano = True
            break
except Exception:
    pass

if cuenta:
    if dudoso:
        parts.append(YELL + cuenta + "?" + RESET)
    else:
        parts.append(DIM + cuenta + RESET)

# 2. Cuota semanal. Con suscripcion plana ES el limite real: cuando llega a 100
# te quedas sin trabajar, y ningun importe en dolares te avisa de eso.
wk = dig("rate_limits", "seven_day", "used_percentage", default=None)
if isinstance(wk, (int, float)) and wk > 0:
    wk = int(wk)
    col = RED if wk >= 80 else YELL if wk >= 60 else GREEN
    txt = "%d%% wk" % wk
    if wk >= 80:
        txt += " -> quota running low"
    parts.append(col + txt + RESET)

# 3. Coste. En plan plano es precio sombra (lo que costaria por API), no gasto:
# se pinta apagado y con ~ para no alarmar con un numero que no se paga.
cost = dig("cost", "total_cost_usd", default=None)
if isinstance(cost, (int, float)) and cost > 0:
    if plano:
        # Suscripcion: el "~" marca que es equivalente en API, no un cobro.
        parts.append(DIM + "~$%.0f" % cost + RESET)
    else:
        # Solo si algun dia se usa una API key de verdad.
        col = RED if cost >= 100 else YELL if cost >= 40 else GREEN
        parts.append(col + "$%.0f" % cost + RESET)

# 4. Capturas de Paper: dato propio, no nativo. Solo importa si hay muchas.
sid = str(d.get("session_id") or "")
shots = 0
weight_mb = 0.0
if sid:
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", sid)[:80]
    p = os.path.join(os.path.expanduser("~"), ".claude",
                     "state", "session-size", safe)
    try:
        with open(p) as f:
            st = json.load(f)
        shots = int(st.get("shots", 0))
        weight_mb = int((st.get("weight") or {}).get("bytes", 0)) / 1048576.0
    except Exception:
        pass
if shots >= 20:
    col = RED if shots >= 60 else YELL
    txt = "%d shots" % shots
    if shots >= 60:
        txt += " -> delegate to a subagent"
    parts.append(col + txt + RESET)

# Peso de resultados desde el ultimo /compact (hook context-weight). Es lo unico
# que dice QUE herramienta se comio el contexto; el % nativo dice cuanto, no que.
if weight_mb >= 15:
    parts.append((RED if weight_mb >= 30 else YELL) + "%.0f MB res" % weight_mb + RESET)

print("  ".join(parts))
' <<< "$input"

exit 0

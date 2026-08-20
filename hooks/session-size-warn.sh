#!/bin/bash
# PostToolUse hook (no matcher): counts tool calls and Paper screenshots per session
# and prints a stderr reminder when the context is getting expensive.
#
# It only observes. It cannot end, compact or alter a session. Always exits 0.
# Los avisos salen por systemMessage (stdout), NO por stderr: stderr no llega al
# modelo y por eso 87 avisos se perdieron en la sesion del 19-ago.
#
# Thresholds:
#   - tool calls: warn at 300, then every 100  -> sugiere /compact, nunca cerrar
#   - screenshots: warn at 40, then every 20
#   - same Paper node captured a 3rd time: suggest get_computed_styles
#
# Mantiene ademas el contador "clean" (capturas de un nodo SIN edicion
# intermedia) que consume paper-shot-guard.sh para denegar la 4a recaptura.
# Una edicion del nodo borra su entrada en "clean" y permite capturar de nuevo.
#
# State lives in ~/.claude/state/session-size/<session_id>

input=$(cat)
STATE_DIR="$HOME/.claude/state/session-size"
mkdir -p "$STATE_DIR" 2>/dev/null

/usr/bin/python3 -c '
import sys, json, os, re

try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)

sid = str(d.get("session_id") or "unknown")
tool = str(d.get("tool_name") or "")
ti = d.get("tool_input") or {}
if not isinstance(ti, dict):
    ti = {}

state_dir = os.path.join(os.path.expanduser("~"), ".claude", "state", "session-size")
safe = re.sub(r"[^A-Za-z0-9_.-]", "_", sid)[:80]
path = os.path.join(state_dir, safe)

calls = shots = 0
nodes = {}
clean = {}
st = {}   # se conserva entero: otros hooks (context-weight) escriben aqui tambien
try:
    with open(path) as f:
        st = json.load(f)
    if not isinstance(st, dict):
        st = {}
    calls = int(st.get("calls", 0))
    shots = int(st.get("shots", 0))
    n = st.get("nodes", {})
    if isinstance(n, dict):
        nodes = {k: int(v) for k, v in n.items()}
    c = st.get("clean", {})
    if isinstance(c, dict):
        clean = {k: int(v) for k, v in c.items()}
except Exception:
    pass

calls += 1
msgs = []

# Una edicion "ensucia" el nodo: vuelve a poder capturarse desde cero.
EDIT_TOOLS = ("write_html", "update_styles", "set_text_content",
              "delete_nodes", "move_nodes", "duplicate_nodes", "rename_nodes")
if "mcp__paper__" in tool and any(t in tool for t in EDIT_TOOLS):
    touched = []
    for key in ("targetNodeId", "nodeId", "node_id"):
        v = ti.get(key)
        if isinstance(v, str):
            touched.append(v[:60])
    for key in ("nodeIds", "node_ids", "updates", "nodes", "moves"):
        v = ti.get(key)
        if isinstance(v, list):
            for item in v:
                if isinstance(item, str):
                    touched.append(item[:60])
                elif isinstance(item, dict):
                    for k2 in ("id", "nodeId", "parentId", "before", "after"):
                        s = item.get(k2)
                        if isinstance(s, str):
                            touched.append(s[:60])
                    ids = item.get("nodeIds")
                    if isinstance(ids, list):
                        touched += [str(x)[:60] for x in ids]
    for t_id in touched:
        clean.pop(t_id, None)

is_shot = ("get_screenshot" in tool
           or "computer-use__screenshot" in tool
           or tool.endswith("__screenshot")
           or tool in ("mcp__claude-in-chrome__computer",
                       "mcp__claude-in-chrome__browser_batch"))
is_paper = "mcp__paper__" in tool
if is_shot:
    shots += 1
    # Paper may expose the node under different key names; tolerate all, never break.
    raw = ti.get("node_id") or ti.get("nodeId") or ti.get("node_ids") or ti.get("nodeIds")
    if raw is None:
        nid = ""
    elif isinstance(raw, (list, tuple)):
        nid = ",".join(str(x) for x in raw)
    else:
        nid = str(raw)
    nid = nid[:60]
    if nid and is_paper:
        nodes[nid] = nodes.get(nid, 0) + 1
        clean[nid] = clean.get(nid, 0) + 1
        if nodes[nid] >= 3:
            msgs.append(
                "[paper] ya capturaste %s %d veces. Si solo verificas un valor, "
                "get_computed_styles son 900 B frente a 126 KB." % (nid, nodes[nid] - 1)
            )

# Volume warnings: at threshold, then every step.
if calls >= 300 and (calls - 300) % 100 == 0:
    msgs.append(
        "[sesion] %d llamadas, %d capturas. El contexto pesa mucho por llamada. "
        "Considera /compact para aligerar sin perder el hilo." % (calls, shots)
    )

if is_shot and shots >= 40 and (shots - 40) % 20 == 0:
    msgs.append(
        "[imagenes] %d capturas en esta sesion. Las imagenes son el 89%% del "
        "contexto en Paper y el 57%% en navegador. Agrupa antes de mirar y "
        "captura el area mas pequena que responda la pregunta." % shots
    )

try:
    tmp = path + ".tmp"
    # Releer justo antes de escribir: context-weight.sh escribe el mismo fichero
    # y sobrescribir el dict entero borraba su clave "weight" en cada llamada.
    try:
        with open(path) as f:
            cur = json.load(f)
        if not isinstance(cur, dict):
            cur = {}
    except Exception:
        cur = dict(st)
    cur.update({"calls": calls, "shots": shots, "nodes": nodes, "clean": clean})
    with open(tmp, "w") as f:
        json.dump(cur, f)
    os.replace(tmp, path)
except Exception:
    pass

# Los avisos van por systemMessage (stdout), que SI entra en el contexto del
# modelo. stderr no lo lee nadie: es lo que hizo que 87 avisos se perdieran.
if msgs:
    try:
        print(json.dumps({"systemMessage": " ".join(msgs)}))
    except Exception:
        for m in msgs:
            sys.stderr.write(m + "\n")
' <<< "$input"

exit 0

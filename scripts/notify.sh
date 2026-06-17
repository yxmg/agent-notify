#!/usr/bin/env bash
# agent-notify — Claude Code / Codex 完成通知 → 企业微信
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/format.sh"

CONFIG="$HOME/.agent-notify/config.json"
STATE_DIR="$HOME/.agent-notify/state"

[ -f "$CONFIG" ] || exit 0
WEBHOOK=$(jq -r '.webhook // ""' "$CONFIG" 2>/dev/null || echo "")
[ -n "$WEBHOOK" ] || exit 0
mkdir -p "$STATE_DIR"

EVENT_DATA=$(cat)
EVENT_TYPE="${1:-unknown}"
NOW=$(date +%s)

# Skip sub-agents
AGENT_ID=$(jq -r '.agent_id // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
[ -n "$AGENT_ID" ] && exit 0

# Stop hook re-entry guard
STOP_ACTIVE=$(jq -r '.stop_hook_active // false' <<< "$EVENT_DATA" 2>/dev/null || echo "false")
[ "$EVENT_TYPE" = "stop" ] && [ "$STOP_ACTIVE" = "true" ] && exit 0

# Rate limiting
RATE_LIMIT=$(jq -r '.rate_limit // 10' "$CONFIG" 2>/dev/null || echo "10")
RATE_FILE="$STATE_DIR/rate_$EVENT_TYPE"
if [ -f "$RATE_FILE" ]; then
    LAST=$(cat "$RATE_FILE" 2>/dev/null || echo "0")
    [ $((NOW - LAST)) -lt "$RATE_LIMIT" ] && exit 0
fi
echo "$NOW" > "$RATE_FILE"

# Parse event fields
CWD=$(jq -r '.cwd // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
PROJECT=$(basename "${CWD:-unknown}")
TRANSCRIPT=$(jq -r '.transcript_path // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
MODEL=$(jq -r '.model // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
LAST_MSG=$(jq -r '.last_assistant_message // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
HOOK_EVENT=$(jq -r '.hook_event_name // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
NOTIF_TYPE=$(jq -r '.notification_type // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")
SESSION_ID=$(jq -r '.session_id // ""' <<< "$EVENT_DATA" 2>/dev/null || echo "")

if [[ "${TRANSCRIPT:-}" == *".claude"* ]] || [ "$HOOK_EVENT" = "Notification" ]; then
    AGENT="Claude Code"
else
    AGENT="Codex"
fi
HOSTNAME_SHORT=$(hostname -s 2>/dev/null || echo "")

STATUS_LABEL="" STATUS_COLOR="info" SUMMARY=""
SESSION_TASK="" LAST_TASK="" ELAPSED="" T_START="" T_END=""

case "$EVENT_TYPE" in
    stop)
        STATUS_LABEL="任务完成 ✅"
        STATUS_COLOR="info"
        SUMMARY=$(printf '%s' "$LAST_MSG" | awk 'NF{print;exit}' | cut -c1-120)
        SUMMARY="${SUMMARY:-任务已完成}"

        if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
            _r=$(python3 - "$TRANSCRIPT" "$NOW" <<'PYEOF'
import sys, json, re
from datetime import datetime, timezone

transcript_path, now_str = sys.argv[1], sys.argv[2]
now = int(now_str)
session_task = ''
last_task = ''
start_ts = ''
pending_ts = ''
pending_text = ''

INJECTED = (
    'This session is being continued from a previous conversation',
    '<system-reminder>',
)

def is_injected(t): return any(t.startswith(p) for p in INJECTED)

def clean(text, n=50):
    for ln in text.split('\n'):
        ln = re.sub(r'https?://\S+', '', ln.strip()).strip()
        if ln and not re.match(r'^https?://\S+$', ln):
            return ln[:n] + ('...' if len(ln) > n else '')
    return text[:n]

def user_text(obj):
    ts = obj.get('timestamp', '')
    # Claude Code format
    if obj.get('type') == 'user':
        msg = obj.get('message', {})
        if not isinstance(msg, dict) or msg.get('role') != 'user': return None, ts
        c = msg.get('content', '')
        if isinstance(c, str):
            t = c.strip(); return (t if t and not is_injected(t) else None), ts
        if isinstance(c, list):
            for i in c:
                if isinstance(i, dict) and i.get('type') == 'text':
                    t = (i.get('text') or '').strip()
                    if t and not is_injected(t): return t, ts
        return None, ts
    # Codex format
    if obj.get('type') == 'response_item':
        p = obj.get('payload', {})
        if p.get('role') != 'user': return None, ts
        parts = []
        for i in p.get('content', []):
            if isinstance(i, dict) and i.get('type') == 'input_text':
                t = (i.get('text') or '').strip()
                if t and not t.startswith('#') and not t.startswith('<'): parts.append(t)
        return ('\n'.join(parts).strip() or None), ts
    return None, ts

def is_asst(obj):
    if obj.get('type') == 'assistant': return True
    if obj.get('type') == 'response_item':
        return obj.get('payload', {}).get('role') in ('assistant', 'developer')
    return False

try:
    for line in open(transcript_path, errors='ignore'):
        line = line.strip()
        if not line: continue
        try:
            obj = json.loads(line)
            text, ts = user_text(obj)
            if text:
                if not session_task: session_task = clean(text)
                pending_ts, pending_text = ts, text
            elif is_asst(obj) and pending_ts:
                start_ts, last_task = pending_ts, clean(pending_text)
                pending_ts = pending_text = ''
        except: pass
except: pass

if not start_ts:
    start_ts = pending_ts
    last_task = clean(pending_text) if pending_text else ''

elapsed = t_start = t_end = ''
if start_ts:
    try:
        dt = datetime.fromisoformat(start_ts.split('.')[0].rstrip('Z')).replace(tzinfo=timezone.utc)
        secs = now - int(dt.timestamp())
        if 5 < secs < 86400:
            elapsed = f"{secs}秒" if secs < 60 else f"{secs//60}分{secs%60}秒"
        t_start = dt.astimezone().strftime("%H:%M:%S")
        t_end = datetime.fromtimestamp(now).astimezone().strftime("%H:%M:%S")
    except: pass

print(json.dumps({"session_task": session_task, "last_task": last_task,
                  "elapsed": elapsed, "start": t_start, "end": t_end}))
PYEOF
2>/dev/null || echo '{}')
            SESSION_TASK=$(jq -r '.session_task // ""' <<< "$_r" 2>/dev/null || echo "")
            LAST_TASK=$(jq -r '.last_task // ""' <<< "$_r" 2>/dev/null || echo "")
            ELAPSED=$(jq -r '.elapsed // ""' <<< "$_r" 2>/dev/null || echo "")
            T_START=$(jq -r '.start // ""' <<< "$_r" 2>/dev/null || echo "")
            T_END=$(jq -r '.end // ""' <<< "$_r" 2>/dev/null || echo "")
        fi
        ;;
    notification)
        case "$NOTIF_TYPE" in
            idle_prompt) STATUS_LABEL="等待响应 ⏳"; STATUS_COLOR="warning" ;;
            *)           STATUS_LABEL="需要确认 🔔"; STATUS_COLOR="warning" ;;
        esac
        SUMMARY=$(printf '%s' "${LAST_MSG:-需要你的操作}" | awk 'NF{print;exit}' | cut -c1-120)
        ;;
    *)
        exit 0
        ;;
esac

# Pending mechanism: cancel if user interacts within delay
DELAY=$(jq -r '.delay // 5' "$CONFIG" 2>/dev/null || echo "5")
rm -f "$STATE_DIR"/pending_* 2>/dev/null || true
PENDING="$STATE_DIR/pending_${SESSION_ID}_${NOW}_$$"
echo "$EVENT_TYPE" > "$PENDING"

(
    sleep "$DELAY"
    [ -f "$PENDING" ] || exit 0

    EVENT_JSON=$(jq -n \
        --arg agent       "$AGENT" \
        --arg status_label "$STATUS_LABEL" \
        --arg status_color "$STATUS_COLOR" \
        --arg summary     "$SUMMARY" \
        --arg project     "$PROJECT" \
        --arg session_task "$SESSION_TASK" \
        --arg last_task   "$LAST_TASK" \
        --arg elapsed     "$ELAPSED" \
        --arg t_start     "$T_START" \
        --arg t_end       "$T_END" \
        --arg model       "$MODEL" \
        --arg hostname    "$HOSTNAME_SHORT" \
        '{agent:$agent, status_label:$status_label, status_color:$status_color,
          summary:$summary, project:$project, session_task:$session_task,
          last_task:$last_task, elapsed:$elapsed, t_start:$t_start, t_end:$t_end,
          model:$model, hostname:$hostname}')

    CONTENT=$(build_wechat_markdown "$EVENT_JSON")

    curl -sf --max-time 10 \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg c "$CONTENT" '{msgtype:"markdown",markdown:{content:$c}}')" \
        "$WEBHOOK" >/dev/null 2>&1 || true

    rm -f "$PENDING"
) </dev/null >/dev/null 2>&1 &
disown

exit 0

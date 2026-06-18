#!/usr/bin/env bash
# agent-notify installer
# Usage (local):  bash install.sh [WEBHOOK_URL]
# Usage (remote): bash <(curl -fsSL https://raw.githubusercontent.com/yxmg/agent-notify/main/install.sh) [WEBHOOK_URL]
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/yxmg/agent-notify/main"
INSTALL_DIR="${AGENT_NOTIFY_DIR:-$HOME/.agent-notify}"

# ── Colors ─────────────────────────────────────────────────────────────────
G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' N='\033[0m'
ok()   { echo -e "${G}✓${N} $*"; }
warn() { echo -e "${Y}!${N} $*"; }
die()  { echo -e "${R}✗${N} $*" >&2; exit 1; }

# ── Webhook URL ─────────────────────────────────────────────────────────────
WEBHOOK="${1:-}"
if [ -z "$WEBHOOK" ]; then
    echo ""
    echo "🤖  agent-notify — Claude Code / Codex 任务完成通知 → 企业微信"
    echo ""
    read -rp "企业微信 Webhook URL: " WEBHOOK
fi
[[ "$WEBHOOK" == https://qyapi.weixin.qq.com/* ]] || die "Invalid webhook URL (must start with https://qyapi.weixin.qq.com/)"

# ── Detect running mode (local repo vs curl) ────────────────────────────────
LOCAL_REPO=""
_src="${BASH_SOURCE[0]:-}"
if [ -n "$_src" ] && [ "$_src" != "/dev/stdin" ] && [ -f "$_src" ]; then
    _dir="$(cd "$(dirname "$_src")" && pwd)"
    [ -f "$_dir/scripts/notify.sh" ] && LOCAL_REPO="$_dir"
fi

get_file() {
    local rel="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -n "$LOCAL_REPO" ]; then
        cp "$LOCAL_REPO/$rel" "$dst"
    else
        curl -fsSL "$REPO_RAW/$rel" -o "$dst"
    fi
}

# ── Install scripts ─────────────────────────────────────────────────────────
echo ""
echo "Installing to $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR/state"

get_file "scripts/notify.sh"        "$INSTALL_DIR/scripts/notify.sh"
get_file "scripts/clear_pending.sh" "$INSTALL_DIR/scripts/clear_pending.sh"
get_file "scripts/lib/format.sh"    "$INSTALL_DIR/scripts/lib/format.sh"
chmod +x "$INSTALL_DIR/scripts/notify.sh" "$INSTALL_DIR/scripts/clear_pending.sh"
ok "Scripts installed"

# ── Write config ─────────────────────────────────────────────────────────────
cat > "$INSTALL_DIR/config.json" <<JSON
{
  "webhook": "$WEBHOOK",
  "delay": 5,
  "rate_limit": 10
}
JSON
ok "Config written → $INSTALL_DIR/config.json"

# ── Register Claude Code hooks ───────────────────────────────────────────────
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 - "$CLAUDE_SETTINGS" "$INSTALL_DIR/scripts" <<'PYEOF'
import json, sys
sf, sd = sys.argv[1], sys.argv[2]
notify, clear = f"{sd}/notify.sh", f"{sd}/clear_pending.sh"

with open(sf) as f: s = json.load(f)
h = s.setdefault("hooks", {})

def upsert(event, matcher, cmd, timeout=None):
    entries = h.setdefault(event, [])
    entry = next((e for e in entries if e.get("matcher") == matcher), None)
    if not entry:
        entry = {"matcher": matcher, "hooks": []}
        entries.append(entry)
    hl = entry.setdefault("hooks", [])
    if any(cmd in hk.get("command", "") for hk in hl): return
    hk = {"type": "command", "command": cmd}
    if timeout: hk["timeout"] = timeout
    hl.append(hk)

upsert("Stop",             "*", f"{notify} stop",         5)
upsert("Notification",     "*", f"{notify} notification", 5)
upsert("UserPromptSubmit", "*", clear,                    3)
upsert("PreToolUse",       "*", clear,                    3)

with open(sf, "w") as f: json.dump(s, f, indent=2, ensure_ascii=False)
PYEOF
    ok "Claude Code hooks registered"
else
    warn "~/.claude/settings.json not found — skipping Claude Code hooks"
fi

# ── Register Codex hooks ─────────────────────────────────────────────────────
CODEX_HOOKS="$HOME/.codex/hooks.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
if [ -d "$HOME/.codex" ]; then
    # Enable codex_hooks feature flag if not already set
    if [ -f "$CODEX_CONFIG" ]; then
        if ! grep -q "codex_hooks" "$CODEX_CONFIG"; then
            printf '\n[features]\ncodex_hooks = true\n' >> "$CODEX_CONFIG"
            ok "Codex: enabled codex_hooks in config.toml"
        fi
    else
        printf '[features]\ncodex_hooks = true\n' > "$CODEX_CONFIG"
        ok "Codex: created config.toml with codex_hooks = true"
    fi
    # Create hooks.json if missing
    [ -f "$CODEX_HOOKS" ] || echo '{"hooks":{}}' > "$CODEX_HOOKS"
fi
if [ -f "$CODEX_HOOKS" ]; then
    python3 - "$CODEX_HOOKS" "$INSTALL_DIR/scripts" <<'PYEOF'
import json, sys
hf, sd = sys.argv[1], sys.argv[2]
notify, clear = f"{sd}/notify.sh", f"{sd}/clear_pending.sh"

with open(hf) as f: h = json.load(f)
hooks = h.setdefault("hooks", {})

def upsert(event, matcher, cmd, timeout=None):
    entries = hooks.setdefault(event, [])
    entry = next((e for e in entries if e.get("matcher") == matcher), None)
    if not entry:
        entry = {"matcher": matcher, "hooks": []}
        entries.append(entry)
    hl = entry.setdefault("hooks", [])
    if any(cmd in hk.get("command", "") for hk in hl): return
    hk = {"type": "command", "command": cmd}
    if timeout: hk["timeout"] = timeout
    hl.append(hk)

upsert("Stop",             "*", f"{notify} stop",         5)
upsert("Notification",     "*", f"{notify} notification", 5)
upsert("UserPromptSubmit", "*", clear,                    3)
upsert("PreToolUse",       "*", clear,                    3)

with open(hf, "w") as f: json.dump(h, f, indent=2)
PYEOF
    ok "Codex hooks registered"
else
    warn "~/.codex/hooks.json not found — skipping Codex hooks"
fi

echo ""
ok "agent-notify installed!"
echo ""
echo "  Config:  $INSTALL_DIR/config.json"
echo "  Test:    echo '{\"session_id\":\"t\",\"cwd\":\"$(pwd)\",\"last_assistant_message\":\"done\",\"hook_event_name\":\"Stop\"}' | $INSTALL_DIR/scripts/notify.sh stop"
echo ""

#!/usr/bin/env bash
# Claude Code statusline installer (Soulfy build, v2)
#
# What it does:
#   1. Writes ~/.claude/statusline-command.sh   (the renderer)
#   2. Writes ~/.claude/monthly-cost.sh         (Anthropic Admin API token aggregator)
#   3. Scaffolds ~/.claude/.env                 (placeholder for ANTHROPIC_ADMIN_KEY)
#   4. Merges statusLine config into ~/.claude/settings.json
#
# Output displayed in Claude Code (default: two lines, breaks before Ctx):
#   🏠 Local | 📁 Dir: folder | 🐍 Py: python | 🌿 Git: branch | 🤖 Model: model | 📅 mm/dd HH:MM | Taipei: ⛅️ +20°C
#   🧠 Ctx: ▓▓▓ % | 💸 Cost: NT$x | 📊 Tokens: 50.5M↓ 4.0M↑ | ⏱️ Time: duration | Limit: 🟢 5h:x% | 🟢 7d:x%
# Lead element switches to "🌐 SSH: user@host" (yellow, bold) when running over SSH.
# Set STATUSLINE_LAYOUT=single to fold it back into one line.
#
# Requirements:
#   - jq        (brew install jq)
#   - python3   (system default OK, ≥3.6)
#   - awk, git  (built-in on macOS / most Linux)
#
# Optional:
#   - ANTHROPIC_ADMIN_KEY in ~/.claude/.env  (enables 📊 monthly token usage)
#     Get one at: https://console.anthropic.com → Settings → API Keys → Admin Keys
#   - curl in PATH  (enables 🌤️ weather indicator via wttr.in — no API key needed)
#
# Usage:
#   bash install-statusline.sh
#   bash install-statusline.sh --uninstall

set -e

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
STATUSLINE_PATH="$CLAUDE_DIR/statusline-command.sh"
MONTHLY_PATH="$CLAUDE_DIR/monthly-cost.sh"
ENV_PATH="$CLAUDE_DIR/.env"
SETTINGS_PATH="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

# ── Uninstall ────────────────────────────────────────────────────────────────
if [ "$1" = "--uninstall" ]; then
  rm -f "$STATUSLINE_PATH" "$MONTHLY_PATH" "$CLAUDE_DIR/monthly-cost.cache" "$CLAUDE_DIR/weather.cache"
  if [ -f "$SETTINGS_PATH" ] && command -v jq >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq 'del(.statusLine)' "$SETTINGS_PATH" > "$tmp" && mv "$tmp" "$SETTINGS_PATH"
  fi
  echo "✅ Uninstalled (kept ~/.claude/.env in case it has other vars)"
  exit 0
fi

# ── Dep checks ───────────────────────────────────────────────────────────────
missing=()
for cmd in jq python3 awk; do
  command -v "$cmd" > /dev/null 2>&1 || missing+=("$cmd")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "❌ Missing required tools: ${missing[*]}"
  echo "   Install on macOS:  brew install ${missing[*]}"
  echo "   Install on Linux:  apt install ${missing[*]}  (or your distro's pkg mgr)"
  exit 1
fi
command -v git > /dev/null 2>&1 || echo "ℹ️  git not found — branch indicator will be hidden"

# ── 1. Write statusline-command.sh ───────────────────────────────────────────
cat > "$STATUSLINE_PATH" <<'STATUSLINE_EOF'
#!/usr/bin/env bash
# Claude Code status line — Soulfy build (single-line output)

input=$(cat)

RESET="\033[0m"; BOLD="\033[1m"; DIM="\033[2m"
GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"
CYAN="\033[36m"; WHITE="\033[37m"; MAGENTA="\033[35m"

color_pct() {
  local ipct
  ipct=$(printf "%.0f" "$1" 2>/dev/null || echo "0")
  if [ "$ipct" -lt 50 ]; then printf "%s" "$GREEN"
  elif [ "$ipct" -lt 80 ]; then printf "%s" "$YELLOW"
  else printf "%s" "$RED"
  fi
}

dot_pct() {
  local ipct
  ipct=$(printf "%.0f" "$1" 2>/dev/null || echo "0")
  if [ "$ipct" -lt 50 ]; then printf "🟢"
  elif [ "$ipct" -lt 80 ]; then printf "🟡"
  else printf "🔴"
  fi
}

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
folder=$(basename "$cwd")

git_branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
fi

py_version=""
if command -v python3 > /dev/null 2>&1; then
  py_version=$(cd "$cwd" 2>/dev/null && python3 --version 2>/dev/null | awk '{print $2}')
fi

model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')

# Local vs SSH context (sshd sets SSH_CONNECTION/SSH_CLIENT/SSH_TTY)
if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
  loc_user="${USER:-$(whoami 2>/dev/null)}"
  loc_host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo remote)
  loc_label=$(printf "${BOLD}${YELLOW}🌐 SSH: %s@%s${RESET}" "$loc_user" "$loc_host")
else
  loc_label=$(printf "${GREEN}🏠 Local${RESET}")
fi

# Date + time (local timezone)
datetime_str=$(date +'%m/%d %H:%M')

# Weather via wttr.in (no API key, IP-geolocated unless STATUSLINE_WEATHER_LOCATION set).
# Cached at ~/.claude/weather.cache; background refresh when stale.
weather_str=""
WEATHER_CACHE="${CLAUDE_DIR:-$HOME/.claude}/weather.cache"
WEATHER_TTL="${STATUSLINE_WEATHER_TTL:-600}"
WEATHER_LOC="${STATUSLINE_WEATHER_LOCATION:-}"
if [ "${STATUSLINE_WEATHER:-1}" = "1" ] && command -v curl > /dev/null 2>&1; then
  needs_w=1
  if [ -f "$WEATHER_CACHE" ]; then
    wmt=$(stat -f "%m" "$WEATHER_CACHE" 2>/dev/null || stat -c "%Y" "$WEATHER_CACHE" 2>/dev/null)
    if [ -n "$wmt" ]; then
      wage=$(( $(date +%s) - wmt ))
      [ "$wage" -lt "$WEATHER_TTL" ] && needs_w=0
    fi
  fi
  if [ "$needs_w" = "1" ]; then
    (curl -fsSL --max-time 3 "https://wttr.in/${WEATHER_LOC}?format=3" \
       -o "$WEATHER_CACHE.tmp" 2>/dev/null \
       && mv "$WEATHER_CACHE.tmp" "$WEATHER_CACHE" &) >/dev/null 2>&1
  fi
  if [ -f "$WEATHER_CACHE" ]; then
    weather_str=$(head -c 120 "$WEATHER_CACHE" 2>/dev/null | tr -d '\n')
  fi
fi

line1="$loc_label"
line1+=$(printf " ${DIM}|${RESET} ${BOLD}${CYAN}📁 Dir: %s${RESET}" "$folder")
[ -n "$py_version" ] && line1+=$(printf " ${DIM}|${RESET} 🐍 Py: ${WHITE}%s${RESET}" "$py_version")
[ -n "$git_branch" ] && line1+=$(printf " ${DIM}|${RESET} 🌿 Git: ${MAGENTA}%s${RESET}" "$git_branch")
line1+=$(printf " ${DIM}|${RESET} 🤖 Model: ${WHITE}%s${RESET}" "$model")
line1+=$(printf " ${DIM}|${RESET} 📅 ${WHITE}%s${RESET}" "$datetime_str")
[ -n "$weather_str" ] && line1+=$(printf " ${DIM}|${RESET} %s" "$weather_str")

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
BAR_WIDTH=10
if [ -n "$used_pct" ]; then
  filled=$(awk "BEGIN {printf \"%d\", ($used_pct / 100) * $BAR_WIDTH}")
  empty_count=$((BAR_WIDTH - filled))
  bar=""
  for i in $(seq 1 "$filled"); do bar+="▓"; done
  for i in $(seq 1 "$empty_count"); do bar+="░"; done
  bar_color=$(color_pct "$used_pct")
  ipct=$(printf "%.0f" "$used_pct")
  ctx_display=$(printf "🧠 Ctx: ${bar_color}%s${RESET} %d%%" "$bar" "$ipct")
else
  ctx_display=$(printf "🧠 Ctx: ${DIM}░░░░░░░░░░${RESET}")
fi

twd_rate="${STATUSLINE_TWD_RATE:-32}"

# Session cost (NT$ from cost.total_cost_usd)
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // .cost.total_usd // empty')
cost_display=""
if [ -n "$cost_usd" ]; then
  cost_twd=$(awk "BEGIN {printf \"%.0f\", $cost_usd * $twd_rate}")
  cost_display=$(printf "💸 Cost: NT\$%s" "$cost_twd")
fi

# Monthly TOKEN usage (Admin API → cache)
monthly_display=""
MONTHLY_CACHE="${CLAUDE_DIR:-$HOME/.claude}/monthly-cost.cache"
MONTHLY_SCRIPT="${CLAUDE_DIR:-$HOME/.claude}/monthly-cost.sh"
fmt_tok() {
  local n="${1:-0}"
  awk -v n="$n" 'BEGIN {
    if (n >= 1e9)      printf "%.1fB", n/1e9
    else if (n >= 1e6) printf "%.1fM", n/1e6
    else if (n >= 1e3) printf "%.1fK", n/1e3
    else               printf "%d",   n
  }'
}
if [ -f "$MONTHLY_CACHE" ]; then
  in_tok=$(jq -r '.total_input_tokens  // empty' "$MONTHLY_CACHE" 2>/dev/null)
  out_tok=$(jq -r '.total_output_tokens // empty' "$MONTHLY_CACHE" 2>/dev/null)
  if [ -n "$in_tok" ] && [ -n "$out_tok" ]; then
    monthly_display=$(printf "📊 Tokens: %s↓ %s↑" "$(fmt_tok "$in_tok")" "$(fmt_tok "$out_tok")")
  fi
fi
# Background refresh if cache stale (>5 min) — fire-and-forget
if [ -x "$MONTHLY_SCRIPT" ]; then
  needs_refresh=1
  if [ -f "$MONTHLY_CACHE" ]; then
    cur_month=$(date +%Y-%m)
    cached_month=$(jq -r '.month // ""' "$MONTHLY_CACHE" 2>/dev/null)
    cache_mtime=$(stat -f "%m" "$MONTHLY_CACHE" 2>/dev/null || stat -c "%Y" "$MONTHLY_CACHE" 2>/dev/null)
    age=$(( $(date +%s) - cache_mtime ))
    [ "$cached_month" = "$cur_month" ] && [ "$age" -lt 300 ] && needs_refresh=0
  fi
  if [ "$needs_refresh" = "1" ]; then
    (bash "$MONTHLY_SCRIPT" >/dev/null 2>&1 &) >/dev/null 2>&1
  fi
fi

duration_display=""
total_dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
if [ -n "$total_dur_ms" ] && [ "$total_dur_ms" -gt 0 ]; then
  elapsed=$((total_dur_ms / 1000))
else
  transcript=$(echo "$input" | jq -r '.transcript_path // empty')
  elapsed=0
  if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    start_mtime=$(stat -f "%B" "$transcript" 2>/dev/null || stat -c "%W" "$transcript" 2>/dev/null)
    [ -n "$start_mtime" ] && [ "$start_mtime" -gt 0 ] && elapsed=$(( $(date +%s) - start_mtime ))
  fi
fi
if [ "$elapsed" -gt 0 ]; then
  if [ "$elapsed" -ge 3600 ]; then
    duration_display=$(printf "⏱️ Time: %dh %02dm" "$((elapsed/3600))" "$(((elapsed%3600)/60))")
  else
    duration_display=$(printf "⏱️ Time: %dm %02ds" "$((elapsed/60))" "$((elapsed%60))")
  fi
fi

five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rate_display=""
if [ -n "$five_pct" ]; then
  fc=$(color_pct "$five_pct"); fd=$(dot_pct "$five_pct")
  rate_display+=$(printf "Limit: %s ${fc}5h:%d%%${RESET}" "$fd" "$(printf "%.0f" "$five_pct")")
fi
if [ -n "$week_pct" ]; then
  wc=$(color_pct "$week_pct"); wd=$(dot_pct "$week_pct")
  [ -n "$rate_display" ] && rate_display+=" ${DIM}|${RESET} "
  rate_display+=$(printf "%s ${wc}7d:%d%%${RESET}" "$wd" "$(printf "%.0f" "$week_pct")")
fi

line2="$ctx_display"
[ -n "$cost_display" ]    && line2+=" ${DIM}|${RESET} $cost_display"
[ -n "$monthly_display" ] && line2+=" ${DIM}|${RESET} $monthly_display"
[ -n "$duration_display" ] && line2+=" ${DIM}|${RESET} $duration_display"
[ -n "$rate_display" ]    && line2+=" ${DIM}|${RESET} $rate_display"

# Layout: STATUSLINE_LAYOUT = multi (default) | single | auto
# - "multi"   → two lines, breaking before the Ctx bar
# - "single"  → one line, line1 · line2
# - "auto"    → single if $COLUMNS ≥ 220, else multi.
#               $COLUMNS isn't reliably set in a statusline subprocess,
#               so auto mostly behaves like "multi" unless you export
#               COLUMNS from your shell rc.
layout="${STATUSLINE_LAYOUT:-multi}"
if [ "$layout" = "auto" ]; then
  cols="${COLUMNS:-0}"
  [ "$cols" = "0" ] && cols=$(tput cols 2>/dev/null || echo 0)
  if [ "$cols" -ge 220 ] 2>/dev/null; then layout="single"; else layout="multi"; fi
fi

if [ "$layout" = "single" ]; then
  printf "%b ${DIM}·${RESET} %b\n" "$line1" "$line2"
else
  printf "%b\n%b\n" "$line1" "$line2"
fi
STATUSLINE_EOF
chmod +x "$STATUSLINE_PATH"

# ── 2. Write monthly-cost.sh ─────────────────────────────────────────────────
cat > "$MONTHLY_PATH" <<'MONTHLY_EOF'
#!/usr/bin/env bash
# Monthly token usage aggregator — Anthropic Admin API.
# Pulls usage_report/messages, sums tokens by category for the given month.
# Cache: 1-hour TTL.
#
# Usage:
#   monthly-cost.sh           # current month, cached
#   monthly-cost.sh --force   # ignore cache, recompute
#   monthly-cost.sh 2026-04   # specific month, ignores cache

set -e

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CACHE_FILE="$CLAUDE_DIR/monthly-cost.cache"
ENV_FILE="$CLAUDE_DIR/.env"
TTL_SECONDS="${MONTHLY_COST_TTL:-3600}"

if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi

force=0
if [ "$1" = "--force" ]; then force=1; shift; fi
month="${1:-$(date +%Y-%m)}"

if [ "$force" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
  cached_month=$(jq -r '.month // ""' "$CACHE_FILE" 2>/dev/null || echo "")
  if [ "$cached_month" = "$month" ]; then
    cache_mtime=$(stat -f "%m" "$CACHE_FILE" 2>/dev/null || stat -c "%Y" "$CACHE_FILE" 2>/dev/null)
    age=$(( $(date +%s) - cache_mtime ))
    if [ "$age" -lt "$TTL_SECONDS" ]; then cat "$CACHE_FILE"; exit 0; fi
  fi
fi

start_date="${month}-01"
year=$(echo "$month" | cut -d- -f1)
mo=$(echo "$month" | cut -d- -f2)
if [ "$mo" = "12" ]; then end_date="$((year + 1))-01-01"
else next_mo=$(printf "%02d" $((10#$mo + 1))); end_date="${year}-${next_mo}-01"
fi
starting_at="${start_date}T00:00:00Z"
ending_at="${end_date}T00:00:00Z"

if [ -z "${ANTHROPIC_ADMIN_KEY:-}" ]; then
  echo '{"month":"'"$month"'","error":"ANTHROPIC_ADMIN_KEY missing in ~/.claude/.env"}'
  exit 1
fi

output=$(MONTH="$month" STARTING="$starting_at" ENDING="$ending_at" \
         ADMIN_KEY="$ANTHROPIC_ADMIN_KEY" python3 - <<'PY'
import json, os, sys
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from datetime import datetime, timezone

month     = os.environ["MONTH"]
starting  = os.environ["STARTING"]
ending    = os.environ["ENDING"]
admin_key = os.environ["ADMIN_KEY"]

base = "https://api.anthropic.com/v1/organizations/usage_report/messages"
headers = {
    "x-api-key": admin_key,
    "anthropic-version": "2023-06-01",
}

totals = {
    "uncached_input": 0, "cache_creation_5m": 0, "cache_creation_1h": 0,
    "cache_read": 0, "output": 0, "web_search_requests": 0,
}
days = []
page = None
api_calls = 0
max_pages = 200

while True:
    params = f"starting_at={starting}&ending_at={ending}&limit=31"
    if page: params += f"&page={page}"
    req = Request(f"{base}?{params}", headers=headers)
    try:
        with urlopen(req, timeout=15) as r:
            payload = json.loads(r.read().decode("utf-8"))
    except (HTTPError, URLError) as e:
        print(json.dumps({"month": month, "error": f"admin api failed: {e}"}, ensure_ascii=False))
        sys.exit(2)
    api_calls += 1
    for bucket in payload.get("data", []):
        bucket_start = bucket.get("starting_at", "")
        day = {"date": bucket_start[:10], "uncached_input": 0,
               "cache_creation_5m": 0, "cache_creation_1h": 0,
               "cache_read": 0, "output": 0}
        for row in bucket.get("results", []):
            ui = int(row.get("uncached_input_tokens") or 0)
            cc = row.get("cache_creation") or {}
            c5 = int(cc.get("ephemeral_5m_input_tokens") or 0)
            c1 = int(cc.get("ephemeral_1h_input_tokens") or 0)
            cr = int(row.get("cache_read_input_tokens") or 0)
            ot = int(row.get("output_tokens") or 0)
            ws = int((row.get("server_tool_use") or {}).get("web_search_requests") or 0)
            totals["uncached_input"]    += ui
            totals["cache_creation_5m"] += c5
            totals["cache_creation_1h"] += c1
            totals["cache_read"]        += cr
            totals["output"]            += ot
            totals["web_search_requests"] += ws
            day["uncached_input"]    += ui
            day["cache_creation_5m"] += c5
            day["cache_creation_1h"] += c1
            day["cache_read"]        += cr
            day["output"]            += ot
        if any(v for k, v in day.items() if k != "date"):
            days.append(day)
    if not payload.get("has_more"): break
    page = payload.get("next_page")
    if not page or api_calls >= max_pages: break

total_input_all = (totals["uncached_input"] + totals["cache_creation_5m"]
                   + totals["cache_creation_1h"] + totals["cache_read"])
total_all = total_input_all + totals["output"]

print(json.dumps({
    "month": month,
    "source": "admin-api",
    "totals": totals,
    "total_input_tokens":  total_input_all,
    "total_output_tokens": totals["output"],
    "total_tokens": total_all,
    "days": days,
    "api_pages_fetched": api_calls,
    "computed_at": datetime.now(timezone.utc).isoformat(),
}, ensure_ascii=False))
PY
)

if [ "$month" = "$(date +%Y-%m)" ]; then
  tmp="$CACHE_FILE.tmp"; printf '%s\n' "$output" > "$tmp"; mv "$tmp" "$CACHE_FILE"
fi
echo "$output"
MONTHLY_EOF
chmod +x "$MONTHLY_PATH"

# ── 3. Scaffold ~/.claude/.env (only if missing — never overwrite real key) ──
if [ ! -f "$ENV_PATH" ]; then
  cat > "$ENV_PATH" <<'ENV_EOF'
# Claude Code statusline secrets — keep this file private (chmod 600)
# Get an Admin Key at: https://console.anthropic.com → Settings → API Keys → Admin Keys
ANTHROPIC_ADMIN_KEY=

# Optional overrides
# STATUSLINE_TWD_RATE=32                  # USD → TWD rate for the 💸 indicator
# MONTHLY_COST_TTL=3600                   # cache TTL in seconds for 📊 monthly tokens
# STATUSLINE_WEATHER=1                    # set to 0 to disable the 🌤️ indicator
# STATUSLINE_WEATHER_LOCATION=Taipei      # blank = wttr.in IP-geolocates you
# STATUSLINE_WEATHER_TTL=600              # cache TTL in seconds for 🌤️ weather
# STATUSLINE_LAYOUT=multi                 # multi (default) | single | auto
ENV_EOF
  chmod 600 "$ENV_PATH"
  echo "ℹ️  Created $ENV_PATH (placeholder — fill in ANTHROPIC_ADMIN_KEY for 📊 token indicator)"
else
  echo "ℹ️  Kept existing $ENV_PATH (not overwritten)"
fi

# ── 4. Merge into settings.json ──────────────────────────────────────────────
STATUSLINE_JSON=$(jq -n --arg cmd "bash $STATUSLINE_PATH" \
  '{type:"command", command:$cmd}')

if [ -f "$SETTINGS_PATH" ]; then
  tmp=$(mktemp)
  jq --argjson sl "$STATUSLINE_JSON" '. + {statusLine: $sl}' "$SETTINGS_PATH" > "$tmp" && mv "$tmp" "$SETTINGS_PATH"
else
  jq -n --argjson sl "$STATUSLINE_JSON" '{statusLine: $sl}' > "$SETTINGS_PATH"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo
echo "✅ Installed"
echo "   statusline:     $STATUSLINE_PATH"
echo "   monthly aggr:   $MONTHLY_PATH"
echo "   env (secrets):  $ENV_PATH"
echo "   settings:       $SETTINGS_PATH"
echo
echo "Next steps:"
echo "  1. Edit $ENV_PATH and paste your ANTHROPIC_ADMIN_KEY"
echo "     (otherwise the 📊 monthly token indicator will be hidden)"
echo "  2. Restart Claude Code:  /exit  →  claude --continue"
echo
echo "Optional:"
echo "  bash $MONTHLY_PATH --force        # warm the monthly cache now"
echo "  bash $(basename "$0") --uninstall # remove statusline"

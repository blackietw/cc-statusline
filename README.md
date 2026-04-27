# cc-statusline

A single-line status line for [Claude Code](https://claude.com/claude-code), with local/SSH context, directory, git branch, model, context bar, session cost (NT$), monthly token usage, rate-limit indicators, date/time, and weather.

Default (two lines, breaks before Ctx):

```
🏠 Local | 📁 Dir: my-project | 🐍 Py: 3.12.4 | 🌿 Git: main | 🤖 Model: claude-opus-4-7 | 📅 04/27 14:00 | Taipei: ⛅️ +20°C
🧠 Ctx: ▓▓▓░░░░░░░ 30% | 💸 Cost: NT$24 | 📊 Tokens: 50.5M↓ 4.0M↑ | ⏱️ Time: 12m 34s | Limit: 🟢 5h:18% | 🟢 7d:42%
```

Over SSH (lead indicator turns yellow with `user@host`, so you can never confuse a remote session for a local one):

```
🌐 SSH: jimmy@prod-box | 📁 Dir: my-project | ...
```

Force a single line on wide terminals via `STATUSLINE_LAYOUT=single` in `~/.claude/.env`. See *Configuration* below.

## What gets installed

The installer writes three files into `~/.claude/`:

| File | Purpose |
|---|---|
| `statusline-command.sh` | The renderer Claude Code calls every prompt |
| `monthly-cost.sh` | Aggregates monthly token usage via the Anthropic Admin API (cached, 1 h TTL) |
| `.env` | Placeholder for `ANTHROPIC_ADMIN_KEY` (only created if missing, `chmod 600`) |

It also merges a `statusLine` block into `~/.claude/settings.json`.

## Requirements

- `jq` &nbsp;&nbsp;`brew install jq`
- `python3` (≥ 3.6, system default is fine)
- `awk`, `git` (built-in on macOS / most Linux)
- `curl` (optional — only needed for the 🌤️ weather indicator; built-in on macOS / most Linux)

## Install

```bash
bash install.statusline.sh
```

Then restart Claude Code (`/exit` → `claude --continue`).

## Enable the 📊 monthly token indicator (optional)

1. Get an **Admin Key** at <https://console.anthropic.com> → *Settings → API Keys → Admin Keys*.
2. Paste it into `~/.claude/.env`:
   ```
   ANTHROPIC_ADMIN_KEY=sk-ant-admin-...
   ```
3. Warm the cache once:
   ```bash
   bash ~/.claude/monthly-cost.sh --force
   ```

Without an admin key the 📊 indicator is simply hidden — everything else still works.

## Configuration

Override defaults via `~/.claude/.env`:

| Variable | Default | Effect |
|---|---|---|
| `STATUSLINE_TWD_RATE` | `32` | USD → TWD rate for 💸 Cost. Set to your local currency rate, or remove the indicator from `statusline-command.sh` if you don't want currency conversion. |
| `MONTHLY_COST_TTL` | `3600` | Cache TTL in seconds for the 📊 monthly token indicator |
| `STATUSLINE_WEATHER` | `1` | Set to `0` to hide the 🌤️ weather indicator |
| `STATUSLINE_WEATHER_LOCATION` | *(empty)* | City name for [wttr.in](https://wttr.in) (e.g. `Taipei`, `London`). Empty = IP-geolocate. |
| `STATUSLINE_WEATHER_TTL` | `600` | Cache TTL in seconds for the 🌤️ weather indicator |
| `STATUSLINE_LAYOUT` | `auto` | `single` = one line, `multi` = two lines, `auto` = single if `$COLUMNS ≥ 220` else multi |

The 🌤️ indicator queries [wttr.in](https://wttr.in) (no API key, no signup). Cached results live in `~/.claude/weather.cache`; a stale cache triggers a fire-and-forget background refresh.

### About responsive (`auto`) layout

Truly automatic resizing isn't possible: Claude Code calls the statusline as a subprocess that doesn't inherit the terminal, so `tput cols` and `stty size` fail and `$COLUMNS` is usually unset. To make `auto` actually flip to single-line on wide windows, export `COLUMNS` from your shell rc — e.g.

```bash
# in ~/.zshrc / ~/.bashrc
export COLUMNS
trap 'export COLUMNS=$(tput cols)' WINCH
```

Without that, `auto` behaves like `multi`. The pragmatic alternative is to pick `single` or `multi` once and forget it.

## Uninstall

```bash
bash install.statusline.sh --uninstall
```

Removes `statusline-command.sh`, `monthly-cost.sh`, the cache file, and the `statusLine` entry from `settings.json`. **Keeps `~/.claude/.env`** in case it has unrelated variables.

## License

MIT

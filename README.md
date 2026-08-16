# Codex 1M Context

One-click, open-source enabler for the **1M-token context window** in [OpenAI Codex](https://developers.openai.com/codex).

Based on the official instructions from [@thsottiaux](https://x.com/thsottiaux/status/2089082893804896524) (Codex @ OpenAI):

```toml
model = "gpt-5.6-sol"
model_context_window = 1000000
model_auto_compact_token_limit = 900000
```

## One-click install

From this repo (recommended — installs the `codex-1m` helper):

```bash
./install.sh
```

Or download-and-run:

```bash
curl -fsSL https://raw.githubusercontent.com/manojnagendra/Codex/main/install.sh -o /tmp/codex-1m.sh
bash /tmp/codex-1m.sh
```

Piped install also works for the config change:

```bash
curl -fsSL https://raw.githubusercontent.com/manojnagendra/Codex/main/install.sh | bash
```

Then **restart Codex** and start a **new session**.

## What it does

1. Creates a timestamped backup of `~/.codex/config.toml`
2. Upserts the three top-level keys above (before any `[section]` headers)
3. Installs a `codex-1m` helper to `~/.local/bin` for status / disable / one-off runs

OpenAI tuned the default context limit for performance and cost. A larger window lets Codex keep more code, tool output, and history before summarizing older turns. You need a model that supports it — **GPT-5.6 Sol** documents a 1,050,000-token window.

## Commands

```bash
./install.sh                  # enable (default)
./install.sh status           # show current settings
./install.sh disable          # remove 1M overrides
./install.sh run              # one-off session, no config edit
./install.sh --keep-model     # enable without changing model=
./install.sh --profile        # write ~/.codex/1m.config.toml instead
./install.sh --dry-run        # preview changes
```

After install:

```bash
codex-1m status
codex-1m run -- "summarize this repo"
codex-1m disable
```

### Profile mode (safer)

Leaves your default config alone and writes a profile overlay:

```bash
./install.sh --profile
codex --profile 1m
```

### Manual one-off (from the tweet)

```bash
codex -m gpt-5.6-sol \
  -c model_context_window=1000000 \
  -c model_auto_compact_token_limit=900000
```

## Options

| Flag | Meaning |
|------|---------|
| `--model NAME` | Model to set (default: `gpt-5.6-sol`) |
| `--keep-model` | Do not change `model=` |
| `--window N` | Context window (default: `1000000`) |
| `--compact N` | Auto-compact threshold (default: `900000`) |
| `--profile` | Use `~/.codex/1m.config.toml` |
| `--profile-name NAME` | Custom profile name |
| `--dry-run` | Print planned config, write nothing |
| `--yes` / `-y` | Skip prompts |
| `--no-bin` | Skip installing `codex-1m` |

## Requirements

- `bash`, `python3`
- OpenAI Codex CLI / app already installed and authenticated
- A model that supports the large window (e.g. `gpt-5.6-sol`)

## Safety notes

- Always backs up `config.toml` before writing
- Only edits **top-level** keys before the first `[section]` — plugin / marketplace tables are left alone
- Larger context can cost more and may feel slower; OpenAI’s defaults are intentional tradeoffs
- After enabling, restart the Codex client and start a **new** session

## Uninstall

```bash
./install.sh disable
./install.sh uninstall
```

## License

MIT

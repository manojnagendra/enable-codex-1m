# How to enable the Codex 1M context window (one-click)

**enable-codex-1m** — enable OpenAI Codex’s **1,000,000-token (1M) context window** in one command.  
Open-source MIT installer for `~/.codex/config.toml`. Useful if Codex shows ~258k / 272k / 400k instead of 1M.

> **Search terms this solves:** enable Codex 1M context · Codex 1 million token context window · GPT-5.6 Sol 1M · `model_context_window = 1000000` · Codex stuck at 258400 · increase Codex context window · Codex auto compact 900000

Community tool. **Not affiliated with OpenAI.** Based on official guidance from [@thsottiaux](https://x.com/thsottiaux/status/2089082893804896524) (Codex @ OpenAI).

## Quick answer

To turn on the **Codex 1M-token context window** for **GPT-5.6 Sol**, set these top-level keys in `~/.codex/config.toml`, then restart Codex and start a **new session**:

```toml
model = "gpt-5.6-sol"
model_context_window = 1000000
model_auto_compact_token_limit = 900000
```

Or run this one-click enabler (backs up your config first):

```bash
curl -fsSL https://raw.githubusercontent.com/manojnagendra/enable-codex-1m/main/install.sh -o /tmp/codex-1m.sh
bash /tmp/codex-1m.sh
```

## Why Codex shows ~258k instead of 1M

By default, Codex often uses a smaller effective input budget (commonly reported around **258,400** tokens: roughly `272000 × 95%`) even when the API model page lists **~1,050,000** tokens for GPT-5.6 Sol.

OpenAI tunes that default for **performance and cost**. A larger window keeps more code, tool output, and chat history before auto-compaction summarizes older turns.

This repo applies the documented override so you can opt into the larger window when you need it.

## One-click install

```bash
curl -fsSL https://raw.githubusercontent.com/manojnagendra/enable-codex-1m/main/install.sh -o /tmp/codex-1m.sh
bash /tmp/codex-1m.sh
```

Clone instead:

```bash
git clone https://github.com/manojnagendra/enable-codex-1m.git
cd enable-codex-1m
./install.sh
```

Then:

1. **Restart** the Codex app / CLI  
2. Start a **new** session  
3. Confirm with `codex-1m status` (or check `model_context_window` in `~/.codex/config.toml`)

## What the installer changes

| Setting | Value | Purpose |
|--------|-------|---------|
| `model` | `gpt-5.6-sol` | Model with a documented ~1.05M context window |
| `model_context_window` | `1000000` | Ask Codex to use a 1M-token context budget |
| `model_auto_compact_token_limit` | `900000` | Start auto-compaction near 900k (headroom before the ceiling) |

Also:

- Timestamped backup of `~/.codex/config.toml`
- Safe upsert of **top-level** keys only (before the first `[section]`)
- Optional `codex-1m` helper in `~/.local/bin`

## Manual / one-off (no installer)

Same settings as the [official tip](https://x.com/thsottiaux/status/2089082893804896524):

```bash
codex -m gpt-5.6-sol \
  -c model_context_window=1000000 \
  -c model_auto_compact_token_limit=900000
```

## Commands

```bash
./install.sh                  # enable 1M context (default)
./install.sh status           # show current 1M-related settings
./install.sh disable          # remove 1M overrides
./install.sh run              # one-off Codex session with 1M flags
./install.sh --keep-model     # keep your current model= line
./install.sh --profile        # write ~/.codex/1m.config.toml instead
./install.sh --dry-run        # preview without writing
```

After install:

```bash
codex-1m status
codex-1m run -- "summarize this repo"
codex-1m disable
```

### Safer profile mode

```bash
./install.sh --profile
codex --profile 1m
```

## FAQ

### How do I enable 1M context in Codex?

Run the install command above, or add `model_context_window = 1000000` and `model_auto_compact_token_limit = 900000` to `~/.codex/config.toml` with `model = "gpt-5.6-sol"`, then restart and open a new session.

### Does this work with GPT-5.6 Sol?

Yes — that’s the model called out in the official tip. Use `--keep-model` only if you already use a model that supports the larger window.

### Will this bypass plan or server limits?

No. It only edits **local** Codex config. If your plan or Codex’s server catalog clamps the window, this tool cannot override that.

### Is it safe?

It backs up `config.toml` before writing and only changes top-level keys. Still review `install.sh` before piping to bash. Larger context can cost more and feel slower; OpenAI’s defaults are intentional.

### How do I undo it?

```bash
./install.sh disable
# or restore the timestamped ~/.codex/config.toml.bak.* backup
```

## Requirements

- macOS / Linux with `bash` and `python3`
- OpenAI Codex CLI or app installed and signed in
- A model that supports the large window (e.g. **gpt-5.6-sol**)

## Disclaimer

Unofficial community project. Not affiliated with OpenAI. Use at your own risk. Codex defaults, model catalogs, and supported overrides can change.

## Contributing

Issues and PRs welcome. Keep the installer **safe**, **idempotent**, and **easy to reverse**.

## License

[MIT](./LICENSE) © Manoj Nagendra

---

**Related:** OpenAI Codex · GPT-5.6 Sol · 1M token context window · `model_context_window` · `model_auto_compact_token_limit` · Codex config.toml

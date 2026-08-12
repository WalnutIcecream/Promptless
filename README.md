# Promptless

> Your terminal shouldn't need an IDE wrapper to understand English.

**promptless** is a shell classifier that sits on your Enter key. Known commands pass through in <10µs. Everything else — "find all the dead CSS", "explain that error", "deploy the latest tag" — goes straight to opencode with native-style session management and a readable terminal formatter for every opencode event type. Zero non-system dependencies. A shell script and a Python snippet.

```bash
# Install
git clone https://github.com/WalnutIcecream/promptless ~/.promptless && bash ~/.promptless/install.sh

# Then just type
ls -la                    # → runs normally
check if the server is running  # → opencode run --auto "check if..."
/session                  # → list this directory's sessions, pick one
/new                      # → fresh session
```

## How it works

```
Your Enter key
    │
    ▼
┌──────────────────────────────────────┐
│           classify_and_route()       │
│                                      │
│  1. Hash lookup against $PATH cache  │  ← 95% of inputs return here, <10µs
│  2. Shell metacharacter scan         │  ← pipes, redirects, flags → command
│  3. English function-word matching   │  ← "the", "my", "should", "from"
│  4. Default: run as command          │  ← safe fallback, not prompt
└──────────────────────────────────────┘
    │              │
  command          prompt
    │              │
    ▼              ▼
  shell        opencode run --format json --auto
  executes        │    (fresh, or --session <current>)
  normally        ▼
            format_output.py
            (text, tool_use,
             errors, token usage)
                │
                ▼
            current session id
            captured in memory
```

## Project layout

```
promptless/
├── lib/
│   ├── classifier.sh     # core: cache, heuristics, session mgmt
│   ├── sessions.py       # /session list + interactive picker
│   └── format_output.py  # JSON event parser for terminal output
├── shell/
│   ├── promptless.bash    # readline macro chain for bash
│   └── promptless.zsh     # zle widget override for zsh
├── install.sh             # copies files, appends source line to .bashrc/.zshrc
├── test/
│   ├── test_classifier.sh # 37 classifier tests
│   └── test_sessions.sh   # session picker tests
└── README.md
```

## Inside each module

### `lib/classifier.sh` — the brain

Three functions, one decision:

| Function | Purpose | Latency |
|---|---|---|
| `is_shell_command()` | Main decision pipeline — returns 0 (command) or 1 (prompt) | ~1-200µs |
| `has_nlp_structure()` | Word-boundary matching against 70+ English function words | ~50µs |
| `is_ambiguous_verb()` | ~200 words like "find", "build", "test" that exist as both commands and English verbs | ~10µs |
| `opencode_with_context()` | Launches opencode with `--auto`, pipes JSON stream to `format_output.py`, captures the session id | varies |

The hot path is a single associative-array lookup (`COMMAND_CACHE["$first_word"]`). This is the same data structure `compgen -c` builds, pre-populated at shell startup. Only when a word is not found *or* is in the ambiguous-verb list do we fall through to the NLP heuristics.

The NLP detector pads the argument string with spaces (`" $rest "`) and uses bash `case` word-boundary patterns. `*" the "*` matches "the" as a standalone word without false-positives on "theme" or "other". File extension detection (`file.py`, `data.json`) escapes false positives on command arguments that happen to contain English words.

### `lib/format_output.py` — the formatter

Reads newline-delimited JSON events from opencode's `--format json --auto` stream and renders them as readable terminal output:

| Event type | Display |
|---|---|
| `text` | Streamed directly to terminal in real-time |
| `tool_use` (completed) | Tool name with green checkmark, shell command, and output |
| `tool_use` (error) | Tool name with red cross, error message, and attempted command |
| `tool_use` (running) | Yellow spinner with the running command |
| `step_finish` | Dimmed token usage per step (↑input ↓output) |

Non-JSON lines (stderr from opencode or providers) pass through verbatim. The formatter also captures the session ID from the first event and exposes it to the shell wrapper so a freshly created session becomes the in-memory current one.

The `--auto` flag is required because `opencode run` in non-interactive mode silently denies all tool calls without it. With `--auto`, tools execute and their results are visible in the formatted output — no silent failures, no hidden permission prompts.

### `lib/sessions.py` — the /session picker

Backs the `/session` slash command. Runs `opencode session list --format json`, filters to the current directory (matching the native TUI `/sessions` behavior), and renders a numbered list of title + last-updated time. You pick a number to continue that session, `n` to start a new one, or `q` to cancel. The shell then records your choice as the current session.

### `shell/promptless.bash` — the bash bridge

Readline macro chaining. Enter (`\C-m`) expands to `\C-x\C-p\n`:

- `\C-x\C-p` is bound via `bind -x` to `classify_and_route()` which inspects `READLINE_LINE`
- Command → no-op, the trailing `\n` accepts the line and runs it
- Prompt → rewrites the line to `opencode_with_context <escaped-prompt>`, then `\n` accepts it
- `opencode_with_context` runs `opencode run --format json --auto` and pipes through `format_output.py`

**Limitation**: multi-line pastes and bracketed paste mode can interact poorly with the macro chain.

### `shell/promptless.zsh` — the zsh bridge

Cleaner approach via zle widget override. Wraps `accept-line`:

- Command → delegates to `.accept-line` (the original)
- Prompt → `print -s` to history, `zle -I` to release terminal, `opencode_with_context` directly
- `/session` → releases the terminal and runs the interactive picker
- `/new` → drops the current session, next prompt starts fresh

No macro chaining fragility — zsh's widget system handles this natively.

### Session management

Sessions work the way native opencode does. There is **no per-project session file and no automatic resume** of your last conversation.

- The current session lives **in memory for this shell instance only**. Each new shell starts with no current session — a fresh shell's first prompt starts a brand-new opencode session.
- `/session` lists this directory's past sessions (title + last updated). Pick one to continue it, `n` to start fresh, `q` to cancel.
- `/new` drops the current session so your next prompt starts a fresh one.
- Consecutive prompts in the same shell continue the current conversation, exactly like typing in the opencode TUI — and nothing survives a shell restart.

```bash
$ /session
promptless sessions · /home/walnut/project-a
------------------------------------------------------------
    1) Fix the auth bug                              3:12 PM
    2) Add dark mode                                11:02 AM · 7/28
    n) New session
Select a session (1-2, n=new, q=cancel): 1
promptless: now using session ses_1ab2cd...
# prompt → continues that conversation
/new
# prompt → starts fresh
```

## Requirements

- **opencode** in `$PATH` (the only runtime dependency)
- **Python ≥ 3.6** (for `format_output.py` and `sessions.py` — standard on all modern systems)
- **Bash ≥ 4.0** or **Zsh ≥ 5.8** (for associative array support)
- `compgen` available (built into bash; zsh sources via `compgen -abk`)

## Adding new commands

To add a new ambiguous verb, edit the `is_ambiguous_verb()` case list in `lib/classifier.sh`:

```bash
# Before
find|make|test|echo|...
# After
find|make|test|echo|your-verb|...
```

To test:

```bash
bash test/test_classifier.sh && bash test/test_sessions.sh
```

To customise the output format (colours, tool display, token visibility), edit `lib/format_output.py`. The ANSI colour constants are at the top of `main()` and the event handlers are in the `if/elif` chain.

## License

MIT. No telemetry, no cloud, no backend.

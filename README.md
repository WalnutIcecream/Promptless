# Promptless

> Your terminal shouldn't need an IDE wrapper to understand English.

**promptless** is a shell classifier that sits on your Enter key. Known commands pass through in <10µs. Everything else — "find all the dead CSS", "explain that error", "deploy the latest tag" — goes straight to opencode with project-scoped conversation persistence and a readable terminal formatter for every opencode event type. Zero non-system dependencies. A shell script and a Python snippet.

```bash
# Install
git clone https://github.com/you/promptless ~/.promptless && bash ~/.promptless/install.sh

# Then just type
ls -la                    # → runs normally
check if the server is running  # → opencode run --continue "check if..."
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
  executes        │
  normally        ▼
            format_output.py
            (text, tool_use,
             errors, token usage)
                │
                ▼
            + session persisted
              to .promptless-session
```

## Project layout

```
promptless/
├── lib/
│   ├── classifier.sh     # 326 lines — core: cache, heuristics, session mgmt
│   └── format_output.py  # 175 lines — JSON event parser for terminal output
├── shell/
│   ├── promptless.bash    # 47 lines — readline macro chain for bash
│   └── promptless.zsh     # 55 lines — zle widget override for zsh
├── install.sh             # copies files, appends source line to .bashrc/.zshrc
├── test/
│   └── test_classifier.sh # 37 test cases, all passing
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
| `opencode_with_context()` | Launches opencode with `--auto`, pipes JSON stream to `format_output.py`, writes session to `.promptless-session` | varies |

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

Non-JSON lines (stderr from opencode or providers) pass through verbatim. The formatter also captures the session ID from the first event and writes it to `.promptless-session` so the shell wrapper doesn't need to parse JSON itself.

The `--auto` flag is required because `opencode run` in non-interactive mode silently denies all tool calls without it. With `--auto`, tools execute and their results are visible in the formatted output — no silent failures, no hidden permission prompts.

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
- `/new`/`/reset` → `reset_project_session`, shows `zle -M` status message

No macro chaining fragility — zsh's widget system handles this natively.

### Session persistence

Each project root (detected by `.git`, `package.json`, `Cargo.toml`, etc.) gets its own `.promptless-session` file containing the opencode session ID. Switching directories switches conversations automatically.

```bash
cd ~/project-a
# prompt → continues project-a's conversation
cd ~/project-b
# prompt → continues project-b's conversation
/new
# prompt → starts fresh in project-b
```

## Requirements

- **opencode** in `$PATH` (the only runtime dependency)
- **Python ≥ 3.6** (for `format_output.py` — standard on all modern systems)
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

To change session markers, edit the `marker` list in `find_project_root()`:

```bash
for marker in .git .hg .bzr package.json Cargo.toml go.mod ...
```

To test:

```bash
bash test/test_classifier.sh
```

To customise the output format (colours, tool display, token visibility), edit `lib/format_output.py`. The ANSI colour constants are at the top of `main()` and the event handlers are in the `if/elif` chain.

## License

MIT. No telemetry, no cloud, no backend.

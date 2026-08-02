# promptless — dual-mode shell: commands run, prompts go to opencode
#
# Determines whether terminal input is a native shell command or a natural-language
# prompt intended for opencode.  Also manages project-scoped opencode sessions so
# each project directory gets its own conversation context.

declare -A COMMAND_CACHE 2>/dev/null
CACHED_PATH=""

# File stored per-project to remember the last opencode session ID.
PROMPTLESS_SESSION_FILE=".promptless-session"


# ---------------------------------------------------------------------------
# Cache Management
# ---------------------------------------------------------------------------

build_command_cache() {
    local current_path="${PATH}"

    if [[ "$current_path" == "$CACHED_PATH" && "${#COMMAND_CACHE[@]}" -gt 0 ]]; then
        return 0
    fi

    CACHED_PATH="$current_path"
    COMMAND_CACHE=()

    local command_name
    while IFS= read -r command_name; do
        if [[ -n "$command_name" ]]; then
            COMMAND_CACHE["$command_name"]=1
        fi
    done < <(compgen -c 2>/dev/null || compgen -abk 2>/dev/null)
}


# ---------------------------------------------------------------------------
# Ambiguous Verb Detection
# ---------------------------------------------------------------------------

is_ambiguous_verb() {
    local word="$1"

    case "$word" in
        find|make|test|echo|kill|wait|jobs|time|read|\
        set|enable|history|source|help|open|close|\
        create|update|delete|list|check|show|count|\
        start|stop|build|write|diff|sort|join|split|\
        cut|link|copy|move|paste|replace|rename|\
        remove|add|change|format|group|install|setup|\
        edit|view|scan|mount|export|import|fetch|push|\
        pull|merge|patch|release|commit|rebase|clone|\
        monitor|trace|score|rank|filter|search|compare|\
        verify|print|sleep|let|eval|generate|compile|\
        configure|deploy|schedule|cancel|encrypt|decrypt|\
        sign|transform|migrate|restore|backup|benchmark|\
        profile|document|package|publish|audit|review|\
        outline|draft|revise|proofread|annotate|\
        highlight|quote|cite|reference|define|contrast|\
        evaluate|recommend|suggest|propose|estimate|\
        measure|weigh|balance|prioritize|triage|escalate|\
        delegate|assign|unassign|claim|release|lock|\
        unlock|protect|expose|hide|reveal|mask|redact|\
        teach|learn|train|predict|classify|cluster|\
        segment|resolve|normalize|validate|parse|draw|\
        design|implement|refactor|debug|optimize|\
        translate|summarize|convert|upload|download|\
        scrape|sanitize|calculate|compute)
            return 0 ;;
    esac

    return 1
}


# ---------------------------------------------------------------------------
# Main Classifier
# ---------------------------------------------------------------------------

# Returns 0 (shell truthy) if the input should run as a native shell command.
# Returns 1 (shell falsy) if it looks like an opencode prompt.
is_shell_command() {
    local raw_input="$1"

    if [[ -z "$raw_input" ]]; then
        return 0
    fi

    local input="$raw_input"
    if [[ "$input" == " "* ]]; then
        input="${raw_input#"${raw_input%%[![:space:]]*}"}"
    fi

    local first_word="${input%% *}"
    local remainder="${input#* }"
    if [[ "$remainder" == "$input" ]]; then
        remainder=""
    fi

    # ----- Hot path: known, non-ambiguous command --------------------------
    if [[ -n "${COMMAND_CACHE[$first_word]:-}" ]]; then
        if ! is_ambiguous_verb "$first_word"; then
            return 0
        fi
    fi

    # ----- Shell builtins --------------------------------------------------
    case "|$first_word|" in
        \|cd\||\|echo\||\|export\||\|source\||\|alias\||\|eval\||\|exec\||\
\|exit\||\|type\||\|which\||\|help\||\|time\||\|set\||\|unset\||\|shift\||\
\|umask\||\|enable\||\|bind\||\|declare\||\|typeset\||\|local\||\|readonly\||\
\|printf\||\|mapfile\||\|readarray\||\|builtin\||\|caller\||\|command\||\|compgen\||\
\|complete\||\|compopt\||\|dirs\||\|disown\||\|getopts\||\|popd\||\|pushd\||\
\|pwd\||\|return\||\|shopt\||\|suspend\||\|trap\||\|times\||\|false\||\
\|ulimit\||\|logout\||\|continue\||\|break\|)
            return 0 ;;
    esac

    # ----- Single-word unknown input ---------------------------------------
    if [[ -z "$remainder" ]]; then
        return 0
    fi

    # ----- Shell metacharacters --------------------------------------------
    case "$input" in
        *'|'*|*'>'*|*'<'*|*'&'*|*';'*|*'`'*|*--?*|\\*|\"*)
            return 0 ;;
        ./*|../*|/*|~/*|!'*'|'#'*)
            return 0 ;;
    esac

    # ----- Unambiguous NLP signals -----------------------------------------
    case "$input" in
        *'?'|*'? ')
            return 1 ;;
    esac

    case "$first_word" in
        how|what|why|when|where|who|which|whose|\
        can|could|would|should|is|are|do|does|did|will|shall|may|might|\
        please|tell|explain|describe)
            return 1 ;;
    esac

    # ----- NLP structural-word detection -----------------------------------
    if has_nlp_structure "$remainder"; then
        return 1
    fi

    return 0
}


# ---------------------------------------------------------------------------
# NLP Structure Detection
# ---------------------------------------------------------------------------

has_nlp_structure() {
    local arguments="$1"

    if [[ -z "$arguments" ]]; then
        return 1
    fi

    local padded=" $arguments "

    case "$padded" in
        *\ a\ *|*\ an\ *|*\ the\ *|*\ my\ *|*\ our\ *|*\ your\ *|\
        *\ her\ *|*\ his\ *|*\ its\ *|*\ me\ *|*\ us\ *|*\ them\ *|\
        *\ this\ *|*\ these\ *|*\ those\ *|*\ that\ *|*\ it\ *|\
        *\ to\ *|*\ for\ *|*\ of\ *|*\ in\ *|*\ on\ *|*\ at\ *|\
        *\ and\ *|*\ or\ *|*\ but\ *|*\ if\ *|*\ not\ *|\
        *\ should\ *|*\ could\ *|*\ would\ *|*\ might\ *|*\ will\ *|\
        *\ must\ *|*\ can\ *|*\ does\ *|\
        *\ just\ *|*\ also\ *|*\ only\ *|*\ very\ *|*\ really\ *|\
        *\ please\ *|*\ maybe\ *|*\ perhaps\ *|*\ probably\ *|\
        *\ is\ *|*\ are\ *|*\ was\ *|*\ were\ *|*\ have\ *|\
        *\ has\ *|*\ had\ *|*\ been\ *|*\ being\ *|*\ be\ *|\
        *\ from\ *|*\ about\ *|*\ with\ *|*\ without\ *|\
        *\ some\ *|*\ all\ *|*\ every\ *|*\ any\ *|*\ am\ *|\
        *\ like\ *|\
        *\ what\ *|*\ where\ *|*\ when\ *|*\ why\ *|*\ how\ *)
            ;;

        *)
            return 1 ;;
    esac

    # Strong NLP signals (determiners + core prepositions) — high confidence.
    case "$padded" in
        *\ a\ *|*\ the\ *|*\ my\ *|*\ our\ *|*\ your\ *)
            return 0 ;;
    esac

    # File extension in arguments → more likely command arguments.
    case "$arguments" in
        *.[a-zA-Z][a-zA-Z0-9]*[[:space:]]*|\
        *.[a-zA-Z][a-zA-Z0-9]|\
        *.[a-zA-Z])
            return 1 ;;
    esac

    return 0
}


# ---------------------------------------------------------------------------
# Project-Scoped Session Management
# ---------------------------------------------------------------------------

# Find the project root by walking up from the current directory looking for
# common version-control or project markers.  Falls back to the current
# directory if none is found.
find_project_root() {
    local directory="$1"
    directory="$(cd "$directory" 2>/dev/null && pwd)" || return 1

    local marker
    while [[ "$directory" != "/" ]]; do
        for marker in .git .hg .bzr package.json Cargo.toml go.mod composer.json Makefile; do
            if [[ -e "$directory/$marker" ]]; then
                echo "$directory"
                return 0
            fi
        done
        directory="$(dirname "$directory")"
    done

    # No project marker found — fall back to current directory.
    echo "$1"
}


# Get or create a session file path for the current project.
project_session_file() {
    local project_root
    project_root="$(find_project_root "$(pwd)" 2>/dev/null)" || return 1
    echo "${project_root}/${PROMPTLESS_SESSION_FILE}"
}


# Read the stored session ID for this project, if any.
read_project_session() {
    local session_file
    session_file="$(project_session_file 2>/dev/null)" || return 1
    if [[ -f "$session_file" ]]; then
        cat "$session_file"
    fi
}


# Write a session ID to the project's session file.
write_project_session() {
    local session_id="$1"
    local session_file
    session_file="$(project_session_file 2>/dev/null)" || return 1
    echo "$session_id" > "$session_file"
}


# Delete the project session file, forcing a fresh session next time.
reset_project_session() {
    local session_file
    session_file="$(project_session_file 2>/dev/null)" || return 1
    if [[ -f "$session_file" ]]; then
        rm "$session_file"
    fi
}


# Resolve the path to the Python output formatter, searching relative to
# this script first (development layout) then the installed location.
_promptless_formatter_path() {
    local here_dir
    here_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

    local dev_path="${here_dir}/format_output.py"
    local installed_path="${HOME}/.promptless/lib/format_output.py"

    if [[ -x "$dev_path" ]]; then
        echo "$dev_path"
    elif [[ -x "$installed_path" ]]; then
        echo "$installed_path"
    else
        echo ""
    fi
}


# Launch opencode with the given prompt, continuing this project's session
# if one exists, or starting a new one.
#
# Uses --auto so tool calls execute without blocking on interactive
# permission prompts, which cannot work in the non-interactive shell-piped
# mode.  Output is streamed through a Python formatter that handles every
# opencode JSON event type: text, tool_use (completed/error/running), and
# step boundaries — all surfaced in a readable terminal format.
opencode_with_context() {
    local prompt="$1"
    local session_id
    session_id="$(read_project_session 2>/dev/null)" || true

    local formatter
    formatter="$(_promptless_formatter_path)"
    if [[ -z "$formatter" ]]; then
        echo "promptless: formatter not found (expected lib/format_output.py)" >&2
        return 1
    fi

    local session_file
    session_file="$(project_session_file 2>/dev/null)" || true

    if [[ -n "$session_id" ]]; then
        opencode run --format json --auto --session "$session_id" "$prompt" 2>&1
    else
        opencode run --format json --auto "$prompt" 2>&1
    fi | "$formatter" "$session_file"
}


# ---------------------------------------------------------------------------
# Initialisation
# ---------------------------------------------------------------------------

build_command_cache

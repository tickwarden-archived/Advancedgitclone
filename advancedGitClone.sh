#!/usr/bin/env bash
# advancedGitClone — A proper git clone wrapper
# Usage: advancedGitClone [options] <url> [dest]
# https://github.com/runtoolkit/advancedGitClone

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Defaults ────────────────────────────────────────────────────────────────
BRANCH=""
DEPTH=""
SUBMODULES=false
SPARSE_PATTERNS=()
TOKEN=""
RETRIES=3
RETRY_DELAY=5
VERBOSE=false
DEST=""
URL=""
DRY_RUN=false
PARTIAL_CLEANUP=true

# ─── Helpers ─────────────────────────────────────────────────────────────────
log_info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()    { echo -e "${BOLD}──── $* ────${RESET}"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[VERB]${RESET}  $*" || true; }

die() {
    log_error "$*"
    exit 1
}

usage() {
    cat <<EOF
${BOLD}advancedGitClone${RESET} — A proper git clone wrapper

${BOLD}USAGE${RESET}
    advancedGitClone [OPTIONS] <url> [destination]

${BOLD}OPTIONS${RESET}
    -b, --branch <branch>       Clone specific branch (default: repo default)
    -d, --depth <n>             Shallow clone with depth n (0 = full history)
    -s, --submodules            Initialize and update submodules recursively
    -p, --sparse <pattern>      Sparse checkout pattern (repeatable)
    -t, --token <token>         GitHub/GitLab token for private repos
    -r, --retries <n>           Retry count on failure (default: 3)
    -w, --retry-delay <secs>    Seconds between retries (default: 5)
    -n, --no-cleanup            Keep partial clone on failure
    -v, --verbose               Verbose output
        --dry-run               Print the git command without executing
    -h, --help                  Show this help

${BOLD}EXAMPLES${RESET}
    # Basic clone
    advancedGitClone https://github.com/org/repo

    # Shallow clone, specific branch, into custom dir
    advancedGitClone -b main -d 1 https://github.com/org/repo my-dir

    # Private repo with token
    advancedGitClone -t ghp_xxxx https://github.com/org/private-repo

    # Sparse checkout (only src/ and docs/)
    advancedGitClone -p 'src/' -p 'docs/' https://github.com/org/repo

    # With submodules, 5 retries
    advancedGitClone -s -r 5 https://github.com/org/repo

    # Dry run — show what would be run
    advancedGitClone --dry-run -b dev -d 50 https://github.com/org/repo
EOF
}

# ─── Argument Parsing ─────────────────────────────────────────────────────────
parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--branch)
                [[ -z "${2:-}" ]] && die "--branch requires a value"
                BRANCH="$2"; shift 2 ;;
            -d|--depth)
                [[ -z "${2:-}" ]] && die "--depth requires a value"
                [[ "$2" =~ ^[0-9]+$ ]] || die "--depth must be a non-negative integer"
                DEPTH="$2"; shift 2 ;;
            -s|--submodules)
                SUBMODULES=true; shift ;;
            -p|--sparse)
                [[ -z "${2:-}" ]] && die "--sparse requires a pattern"
                SPARSE_PATTERNS+=("$2"); shift 2 ;;
            -t|--token)
                [[ -z "${2:-}" ]] && die "--token requires a value"
                TOKEN="$2"; shift 2 ;;
            -r|--retries)
                [[ -z "${2:-}" ]] && die "--retries requires a value"
                [[ "$2" =~ ^[0-9]+$ ]] || die "--retries must be a non-negative integer"
                RETRIES="$2"; shift 2 ;;
            -w|--retry-delay)
                [[ -z "${2:-}" ]] && die "--retry-delay requires a value"
                [[ "$2" =~ ^[0-9]+$ ]] || die "--retry-delay must be a non-negative integer"
                RETRY_DELAY="$2"; shift 2 ;;
            -n|--no-cleanup)
                PARTIAL_CLEANUP=false; shift ;;
            -v|--verbose)
                VERBOSE=true; shift ;;
            --dry-run)
                DRY_RUN=true; shift ;;
            -h|--help)
                usage; exit 0 ;;
            --)
                shift; positional+=("$@"); break ;;
            -*)
                die "Unknown option: $1 (use --help for usage)" ;;
            *)
                positional+=("$1"); shift ;;
        esac
    done

    [[ ${#positional[@]} -eq 0 ]] && die "Repository URL is required"
    URL="${positional[0]}"
    [[ ${#positional[@]} -ge 2 ]] && DEST="${positional[1]}"
}

# ─── Validation ──────────────────────────────────────────────────────────────
validate() {
    command -v git &>/dev/null || die "git is not installed or not in PATH"

    # Basic URL sanity check
    [[ "$URL" =~ ^(https?|git|ssh):// || "$URL" =~ ^git@ ]] \
        || die "URL doesn't look valid: $URL"

    # Infer dest from URL if not given
    if [[ -z "$DEST" ]]; then
        DEST="${URL##*/}"         # strip up to last /
        DEST="${DEST%.git}"       # strip .git suffix
        [[ -z "$DEST" ]] && die "Could not infer destination from URL; specify it explicitly"
    fi

    # Destination must not already exist
    if [[ -e "$DEST" ]]; then
        die "Destination already exists: $DEST"
    fi

    # Depth=0 means full history — treat as no-depth flag
    if [[ -n "$DEPTH" && "$DEPTH" -eq 0 ]]; then
        log_verbose "depth=0 → full history (no --depth flag)"
        DEPTH=""
    fi

    # Sparse requires at least one pattern
    if [[ ${#SPARSE_PATTERNS[@]} -gt 0 ]]; then
        # Sparse checkout + submodules work together but warn
        [[ "$SUBMODULES" == true ]] && \
            log_warn "Sparse checkout + submodules: only files matching patterns are checked out in submodules too."
    fi
}

# ─── Token injection ──────────────────────────────────────────────────────────
inject_token() {
    local url="$1"
    if [[ -z "$TOKEN" ]]; then
        echo "$url"
        return
    fi

    # Supports https://github.com/... and https://gitlab.com/...
    if [[ "$url" =~ ^https://([^/]+)/(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local path="${BASH_REMATCH[2]}"
        echo "https://x-token:${TOKEN}@${host}/${path}"
    else
        log_warn "Token injection is only supported for HTTPS URLs; skipping token"
        echo "$url"
    fi
}

# ─── Build git clone command ──────────────────────────────────────────────────
build_clone_cmd() {
    local effective_url
    effective_url="$(inject_token "$URL")"

    local cmd=(git clone --progress)

    [[ -n "$BRANCH" ]] && cmd+=(--branch "$BRANCH")
    [[ -n "$DEPTH" ]]  && cmd+=(--depth "$DEPTH")

    # Sparse checkout requires --no-checkout + --filter for efficiency
    if [[ ${#SPARSE_PATTERNS[@]} -gt 0 ]]; then
        cmd+=(--no-checkout --filter=blob:none)
    fi

    cmd+=("$effective_url" "$DEST")
    echo "${cmd[@]}"
}

# ─── Sparse setup (post-clone) ────────────────────────────────────────────────
setup_sparse() {
    log_step "Sparse Checkout Setup"
    pushd "$DEST" &>/dev/null

    git sparse-checkout init --cone
    git sparse-checkout set "${SPARSE_PATTERNS[@]}"
    log_verbose "Sparse patterns: ${SPARSE_PATTERNS[*]}"

    log_info "Checking out sparse tree..."
    git checkout

    popd &>/dev/null
    log_ok "Sparse checkout done (${#SPARSE_PATTERNS[@]} pattern(s))"
}

# ─── Submodule init ───────────────────────────────────────────────────────────
setup_submodules() {
    log_step "Submodule Init"
    pushd "$DEST" &>/dev/null

    local sub_cmd=(git submodule update --init --recursive --progress)
    [[ -n "$DEPTH" ]] && sub_cmd+=(--depth "$DEPTH")

    log_info "Updating submodules recursively..."
    "${sub_cmd[@]}" || die "Submodule update failed"

    popd &>/dev/null
    log_ok "Submodules initialized"
}

# ─── Retry wrapper ────────────────────────────────────────────────────────────
run_with_retry() {
    local attempt=1

    while true; do
        log_verbose "Clone attempt $attempt/$((RETRIES + 1))"

        if eval "$@"; then
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -gt $RETRIES ]]; then
            return $exit_code
        fi

        log_warn "Attempt $attempt failed (exit $exit_code). Retrying in ${RETRY_DELAY}s... ($((RETRIES - attempt + 1)) left)"

        # Remove partial clone before retry
        if [[ "$PARTIAL_CLEANUP" == true && -d "$DEST" ]]; then
            log_verbose "Removing partial clone: $DEST"
            rm -rf "$DEST"
        fi

        sleep "$RETRY_DELAY"
        ((attempt++))
    done
}

# ─── Cleanup on unexpected exit ───────────────────────────────────────────────
cleanup_on_interrupt() {
    echo ""
    if [[ "$PARTIAL_CLEANUP" == true && -d "${DEST:-}" ]]; then
        log_warn "Interrupted. Cleaning up partial clone: $DEST"
        rm -rf "$DEST"
    else
        log_warn "Interrupted. Partial clone left at: ${DEST:-unknown}"
    fi
    exit 130
}

# ─── Print summary ────────────────────────────────────────────────────────────
print_summary() {
    log_step "Clone Summary"
    echo -e "  ${BOLD}URL:${RESET}        $URL"
    echo -e "  ${BOLD}Dest:${RESET}       $DEST"
    [[ -n "$BRANCH" ]] && echo -e "  ${BOLD}Branch:${RESET}     $BRANCH"
    [[ -n "$DEPTH" ]]  && echo -e "  ${BOLD}Depth:${RESET}      $DEPTH"
    [[ "$SUBMODULES" == true ]] && echo -e "  ${BOLD}Submodules:${RESET} yes"
    [[ ${#SPARSE_PATTERNS[@]} -gt 0 ]] && \
        echo -e "  ${BOLD}Sparse:${RESET}     ${SPARSE_PATTERNS[*]}"
    [[ -n "$TOKEN" ]] && echo -e "  ${BOLD}Auth:${RESET}       token (hidden)"
    echo -e "  ${BOLD}Retries:${RESET}    $RETRIES (delay: ${RETRY_DELAY}s)"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    validate

    trap cleanup_on_interrupt INT TERM

    local clone_cmd
    clone_cmd="$(build_clone_cmd)"

    print_summary

    if [[ "$DRY_RUN" == true ]]; then
        log_step "Dry Run"
        # Mask token in dry-run output (sed for safe literal replacement)
        local display_cmd
        if [[ -n "$TOKEN" ]]; then
            display_cmd="$(printf '%s' "$clone_cmd" | sed "s|x-token:[^@]*@|x-token:****@|g")"
        else
            display_cmd="$clone_cmd"
        fi
        echo -e "  ${YELLOW}Would run:${RESET} $display_cmd"
        [[ ${#SPARSE_PATTERNS[@]} -gt 0 ]] && \
            echo -e "  ${YELLOW}Then:${RESET}      sparse-checkout init + set + checkout (in $DEST)"
        [[ "$SUBMODULES" == true ]] && \
            echo -e "  ${YELLOW}Then:${RESET}      submodule update --init --recursive (in $DEST)"
        exit 0
    fi

    log_step "Cloning"
    if ! run_with_retry "$clone_cmd"; then
        if [[ "$PARTIAL_CLEANUP" == true && -d "$DEST" ]]; then
            log_warn "Clone failed. Removing partial directory: $DEST"
            rm -rf "$DEST"
        fi
        die "Clone failed after $((RETRIES + 1)) attempt(s)"
    fi

    log_ok "Clone complete → $DEST"

    [[ ${#SPARSE_PATTERNS[@]} -gt 0 ]] && setup_sparse
    [[ "$SUBMODULES" == true ]]        && setup_submodules

    log_step "Done"
    log_ok "Repository ready at: $(realpath "$DEST")"
}

main "$@"

# advancedGitClone

A `git clone` wrapper that handles the things plain `git clone` doesn't: retries, sparse checkout, submodules, token auth, partial cleanup, and dry-run preview — all in one command.

## Requirements

- Bash 4.0+
- Git 2.25+ (for sparse checkout cone mode)

## Installation

```bash
# Clone this repo
git clone https://github.com/runtoolkit/advancedGitClone
cd advancedGitClone

# Install globally
chmod +x advancedGitClone.sh
sudo cp advancedGitClone.sh /usr/local/bin/advancedGitClone
```

Or with the included alias file:

```bash
# Source aliases in your shell profile (~/.bashrc or ~/.zshrc)
echo 'source /path/to/alias.sh' >> ~/.bashrc
source ~/.bashrc
```

## Usage

```
advancedGitClone [OPTIONS] <url> [destination]
```

## Options

| Flag | Long form | Default | Description |
|------|-----------|---------|-------------|
| `-b` | `--branch <branch>` | repo default | Clone a specific branch |
| `-d` | `--depth <n>` | full history | Shallow clone with depth `n` (`0` = full history) |
| `-s` | `--submodules` | off | Initialize and update submodules recursively |
| `-p` | `--sparse <pattern>` | — | Sparse checkout pattern (repeatable) |
| `-t` | `--token <token>` | — | Auth token for private repos (HTTPS only) |
| `-r` | `--retries <n>` | `3` | Retry count on network failure |
| `-w` | `--retry-delay <secs>` | `5` | Seconds to wait between retries |
| `-n` | `--no-cleanup` | — | Keep partial clone directory on failure |
| `-v` | `--verbose` | — | Print extra diagnostic output |
|      | `--dry-run` | — | Show what would run without executing |
| `-h` | `--help` | — | Show help |

## Examples

```bash
# Basic clone
advancedGitClone https://github.com/org/repo

# Specific branch, shallow depth, custom destination
advancedGitClone -b main -d 1 https://github.com/org/repo my-dir

# Private repo using a GitHub token
advancedGitClone -t ghp_xxxx https://github.com/org/private-repo

# Sparse checkout — only clone src/ and docs/
advancedGitClone -p 'src/' -p 'docs/' https://github.com/org/repo

# Clone with submodules, retry up to 5 times
advancedGitClone -s -r 5 https://github.com/org/repo

# Preview what would be executed without actually running it
advancedGitClone --dry-run -b dev -d 50 -s https://github.com/org/repo
```

## Features

**Retry logic** — On network failure, the script waits and retries automatically. The partial clone directory is wiped before each retry so you never get a corrupted clone. Use `-n` to skip cleanup and inspect what was partially fetched.

**Sparse checkout** — Uses cone mode (`--filter=blob:none` + `--no-checkout`) for efficient partial clones. Only the files matching your `-p` patterns are downloaded. Multiple patterns are supported.

**Submodule support** — Initializes and updates all submodules recursively. If a shallow depth is set with `-d`, it is passed to the submodule update as well.

**Token auth** — Injects the token into the HTTPS URL as `x-token:TOKEN@host` at runtime. The token is never written to disk and is masked in `--dry-run` output.

**Interrupt cleanup** — If you `Ctrl+C` mid-clone, the partial directory is removed automatically (unless `-n` is set).

**Input validation** — Catches bad arguments early: invalid URL scheme, non-integer depth/retries, missing required values, destination already exists.

## Token Security

The token is injected into the clone URL in memory and never written to `.git/config` or any file. It does not appear in `--dry-run` output (replaced with `****`). However, it may appear in your shell history if passed directly on the command line. To avoid this:

```bash
# Read from environment variable instead
advancedGitClone -t "$GITHUB_TOKEN" https://github.com/org/private-repo

# Or read interactively
read -rs TOKEN
advancedGitClone -t "$TOKEN" https://github.com/org/private-repo
```

## Aliases

The included `alias.sh` provides short forms:

```bash
agc          # advancedGitClone
agc-shallow  # advancedGitClone -d 1
agc-full     # advancedGitClone -s
agc-priv     # advancedGitClone -t "$GITHUB_TOKEN"
agc-dry      # advancedGitClone --dry-run
```

## License

MIT

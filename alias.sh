#!/usr/bin/env bash
# alias.sh — advancedGitClone aliases
# Source this file: . ~/alias.sh  OR  source ~/alias.sh

alias agc='advancedGitClone'

alias agc-shallow='advancedGitClone -d 1'
alias agc-full='advancedGitClone -s'
alias agc-priv='advancedGitClone -t "$GITHUB_TOKEN"'
alias agc-dry='advancedGitClone --dry-run'

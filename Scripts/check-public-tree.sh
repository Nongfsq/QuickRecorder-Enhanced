#!/bin/sh
set -eu

forbidden_paths='(^|/)(AGENTS|AGENTS\.override|CLAUDE)\.md$|^appcast\.xml$|^img/|^docs/lecture-compression/|\.(m4a|qma|mp4|mov|m4v|wav)$'
if git ls-files | grep -E "$forbidden_paths" >/dev/null; then
    git ls-files | grep -E "$forbidden_paths"
    printf 'Public tree contains an internal, generated, or recording path.\n' >&2
    exit 1
fi

privacy_pattern='/Users/[^/[:space:]]+|/Volumes/[^/[:space:]]+|CloudStorage|OneDrive|QuickRecorder Code Signing|certificate root|Quayside|/Desktop/'
if git grep -nI -E "$privacy_pattern" -- . ':(exclude)Scripts/check-public-tree.sh' >/dev/null; then
    git grep -nI -E "$privacy_pattern" -- . ':(exclude)Scripts/check-public-tree.sh'
    printf 'Public tree contains a local path or personal-environment marker.\n' >&2
    exit 1
fi

secret_pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-|sk-[A-Za-z0-9]{20,}'
if git grep -nI -E "$secret_pattern" -- . ':(exclude)Scripts/check-public-tree.sh' >/dev/null; then
    git grep -nI -E "$secret_pattern" -- . ':(exclude)Scripts/check-public-tree.sh'
    printf 'Public tree contains a credential-like value.\n' >&2
    exit 1
fi

printf 'Public tree safety checks passed.\n'

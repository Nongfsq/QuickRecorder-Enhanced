#!/bin/sh
set -eu

forbidden_paths='(^|/)(AGENTS|AGENTS\.override|CLAUDE)\.md$|^appcast\.xml$|^img/|^progress/|^docs/lecture-compression/|\.(aiff|caf|m4a|mkv|qma|mp4|mov|m4v|wav|webm|xcresult)$'
if git ls-files | grep -E "$forbidden_paths" >/dev/null; then
    git ls-files | grep -E "$forbidden_paths"
    printf 'Public tree contains an internal, generated, or recording path.\n' >&2
    exit 1
fi

if git grep -n 'FFmpegRuntime in Resources' -- QuickRecorder.xcodeproj/project.pbxproj >/dev/null; then
    git grep -n 'FFmpegRuntime in Resources' -- QuickRecorder.xcodeproj/project.pbxproj
    printf 'Release resources must not copy the local optional FFmpeg runtime folder.\n' >&2
    exit 1
fi

privacy_pattern='/Users/[^/[:space:]]+|/Volumes/[^/[:space:]]+|CloudStorage|OneDrive|QuickRecorder Code Signing|certificate root|Quayside|/Desktop/'
secret_pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-|sk-[A-Za-z0-9]{20,}'

check_content() {
    label=$1
    pattern=$2
    message=$3
    shift 3

    if git grep "$@" -nI -E "$pattern" -- . ':(exclude)Scripts/check-public-tree.sh' >/dev/null; then
        git grep "$@" -nI -E "$pattern" -- . ':(exclude)Scripts/check-public-tree.sh'
        printf '%s (%s).\n' "$message" "$label" >&2
        exit 1
    fi
}

check_content 'working tree' "$privacy_pattern" 'Public tree contains a local path or personal-environment marker'
check_content 'index' "$privacy_pattern" 'Public tree contains a local path or personal-environment marker' --cached
check_content 'working tree' "$secret_pattern" 'Public tree contains a credential-like value'
check_content 'index' "$secret_pattern" 'Public tree contains a credential-like value' --cached

printf 'Public tree safety checks passed.\n'

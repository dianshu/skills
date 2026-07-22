#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf '%s\n' "$2" >&2
    exit "$1"
}

require_state() {
    [[ $# -eq 1 ]] || fail 64 'state directory required'
    [[ -f "$1/root" && -f "$1/start-sha" && -f "$1/start-head" ]] || fail 65 'invalid guard state'
}

status_output() {
    git -C "$1" status --porcelain=v1 --untracked-files=all
}

verify_repository_identity() {
    local state="$1" root expected_sha expected_head current_sha current_head
    root="$(cat "$state/root")"
    expected_sha="$(cat "$state/start-sha")"
    expected_head="$(cat "$state/start-head")"
    current_sha="$(git -C "$root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || fail 28 'HEAD no longer resolves to a commit'
    current_head="$(git -C "$root" symbolic-ref -q HEAD 2>/dev/null || printf 'DETACHED')"
    [[ "$current_sha" == "$expected_sha" && "$current_head" == "$expected_head" ]] || fail 28 'HEAD changed during the run'
}

validate_manifest_path() {
    local root="$1" path="$2" code="$3" candidate component components
    candidate="$root"
    IFS='/' read -r -a components <<< "$path"
    for component in "${components[@]}"; do
        candidate="$candidate/$component"
        [[ ! -L "$candidate" ]] || fail "$code" "manifest path crosses a symlink: $path"
    done
}

write_diff_fingerprint() {
    local state="$1"
    local output="$2"
    local root sha paths path hash
    root="$(cat "$state/root")"
    sha="$(cat "$state/start-sha")"
    verify_repository_identity "$state"
    git -C "$root" diff --no-renames --binary --full-index "$sha" -- > "$output"
    printf '\0CACHED\0' >> "$output"
    git -C "$root" diff --cached --no-renames --binary --full-index "$sha" -- >> "$output"
    printf '\0UNTRACKED\0' >> "$output"
    paths="$state/untracked.$$"
    git -C "$root" ls-files --others --exclude-standard -z > "$paths"
    while IFS= read -r -d '' path; do
        if [[ -L "$root/$path" ]]; then
            printf '%s\0symlink\0%s\0' "$path" "$(readlink "$root/$path")" >> "$output"
        elif [[ -f "$root/$path" ]]; then
            hash="$(git -C "$root" hash-object -- "$path")"
            if [[ -x "$root/$path" ]]; then executable=1; else executable=0; fi
            printf '%s\0file:%s\0%s\0' "$path" "$executable" "$hash" >> "$output"
        else
            printf '%s\0other\0\0' "$path" >> "$output"
        fi
    done < "$paths"
    rm -f "$paths"
}

command="${1:-}"
[[ -n "$command" ]] || fail 64 'usage: git-guard.sh <preflight|freeze|arm|check-clean|check-scope|require-changed|snapshot-diff|check-diff|rollback> ...'
shift

case "$command" in
    preflight)
        [[ $# -eq 1 ]] || fail 64 'usage: git-guard.sh preflight <state-dir>'
        root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail 66 'not a Git repository'
        [[ -z "$(status_output "$root")" ]] || fail 10 'worktree is not clean'
        sha="$(git -C "$root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" || fail 11 'repository has no commit'
        if git -C "$root" ls-files --stage | grep '^160000 ' >/dev/null; then
            fail 14 'repositories with submodules are not supported'
        fi
        mkdir -p "$1"
        state="$(cd "$1" && pwd -P)"
        root="$(cd "$root" && pwd -P)"
        case "$state/" in
            "$root/"*) fail 12 'state directory must be outside the repository' ;;
        esac
        printf '%s\n' "$root" > "$state/root"
        printf '%s\n' "$sha" > "$state/start-sha"
        git -C "$root" symbolic-ref -q HEAD > "$state/start-head" 2>/dev/null || printf 'DETACHED\n' > "$state/start-head"
        rm -f "$state/armed" "$state/manifest"
        printf '{"status":"OK","sha":"%s"}\n' "$sha"
        ;;

    freeze)
        [[ $# -ge 2 ]] || fail 64 'usage: git-guard.sh freeze <state-dir> <path>...'
        state="$1"
        shift
        require_state "$state"
        root="$(cat "$state/root")"
        : > "$state/manifest.tmp"
        for path in "$@"; do
            [[ -n "$path" && "$path" != *$'\n'* ]] || fail 13 'manifest path is empty or contains a newline'
            case "$path" in
                /*|.|..|./*|../*|*/../*|*/..|*/./*|*//*|*/) fail 13 "invalid manifest path: $path" ;;
            esac
            validate_manifest_path "$root" "$path" 13
            printf '%s\n' "$path" >> "$state/manifest.tmp"
        done
        LC_ALL=C sort -u "$state/manifest.tmp" > "$state/manifest"
        rm -f "$state/manifest.tmp"
        printf '{"status":"FROZEN","paths":%s}\n' "$(wc -l < "$state/manifest" | tr -d ' ')"
        ;;

    arm)
        [[ $# -eq 1 ]] || fail 64 'usage: git-guard.sh arm <state-dir>'
        require_state "$1"
        : > "$1/armed"
        printf '{"status":"ARMED"}\n'
        ;;

    check-clean)
        [[ $# -eq 1 ]] || fail 64 'usage: git-guard.sh check-clean <state-dir>'
        require_state "$1"
        root="$(cat "$1/root")"
        verify_repository_identity "$1"
        [[ -z "$(status_output "$root")" ]] || fail 20 'worktree changed'
        printf '{"status":"CLEAN"}\n'
        ;;

    check-scope)
        [[ $# -ge 1 && $# -le 2 ]] || fail 64 'usage: git-guard.sh check-scope <state-dir> [--require-nonempty]'
        state="$1"
        require_state "$state"
        [[ -f "$state/manifest" ]] || fail 65 'scope is not frozen'
        require_nonempty=false
        if [[ $# -eq 2 ]]; then
            [[ "$2" == '--require-nonempty' ]] || fail 64 "unknown option: $2"
            require_nonempty=true
        fi
        root="$(cat "$state/root")"
        sha="$(cat "$state/start-sha")"
        verify_repository_identity "$state"
        while IFS= read -r path; do
            validate_manifest_path "$root" "$path" 21
        done < "$state/manifest"
        changed="$state/changed.$$"
        trap 'rm -f "$changed"' EXIT
        git -C "$root" diff --no-renames --name-only -z "$sha" -- > "$changed"
        git -C "$root" diff --cached --no-renames --name-only -z "$sha" -- >> "$changed"
        git -C "$root" ls-files --others --exclude-standard -z >> "$changed"
        count=0
        while IFS= read -r -d '' path; do
            count=$((count + 1))
            grep -Fqx -- "$path" "$state/manifest" || fail 21 "out-of-scope path: $path"
        done < "$changed"
        if [[ "$require_nonempty" == true && "$count" -eq 0 ]]; then
            fail 22 'diff is empty'
        fi
        rm -f "$changed"
        trap - EXIT
        printf '{"status":"IN_SCOPE","paths":%s}\n' "$count"
        ;;

    require-changed)
        [[ $# -ge 2 ]] || fail 64 'usage: git-guard.sh require-changed <state-dir> <path>...'
        state="$1"
        shift
        require_state "$state"
        [[ -f "$state/manifest" ]] || fail 65 'scope is not frozen'
        root="$(cat "$state/root")"
        sha="$(cat "$state/start-sha")"
        verify_repository_identity "$state"
        changed="$state/required-changed.$$"
        trap 'rm -f "$changed"' EXIT
        git -C "$root" diff --no-renames --name-only -z "$sha" -- > "$changed"
        git -C "$root" diff --cached --no-renames --name-only -z "$sha" -- >> "$changed"
        git -C "$root" ls-files --others --exclude-standard -z >> "$changed"
        for required in "$@"; do
            grep -Fqx -- "$required" "$state/manifest" || fail 29 "required path is outside scope: $required"
            found=false
            while IFS= read -r -d '' path; do
                if [[ "$path" == "$required" ]]; then found=true; break; fi
            done < "$changed"
            [[ "$found" == true ]] || fail 29 "required path did not change: $required"
        done
        rm -f "$changed"
        trap - EXIT
        printf '{"status":"REQUIRED_PATHS_CHANGED","paths":%s}\n' "$#"
        ;;

    snapshot-diff)
        [[ $# -eq 1 ]] || fail 64 'usage: git-guard.sh snapshot-diff <state-dir>'
        require_state "$1"
        write_diff_fingerprint "$1" "$1/diff-fingerprint"
        printf '{"status":"DIFF_SNAPSHOTTED"}\n'
        ;;

    check-diff)
        [[ $# -eq 1 ]] || fail 64 'usage: git-guard.sh check-diff <state-dir>'
        require_state "$1"
        [[ -f "$1/diff-fingerprint" ]] || fail 65 'diff fingerprint is not recorded'
        current="$1/diff-fingerprint.current"
        trap 'rm -f "$current"' EXIT
        write_diff_fingerprint "$1" "$current"
        cmp -s "$1/diff-fingerprint" "$current" || fail 27 'diff changed during gate execution'
        rm -f "$current"
        trap - EXIT
        printf '{"status":"DIFF_UNCHANGED"}\n'
        ;;

    rollback)
        [[ $# -eq 1 ]] || fail 64 'usage: git-guard.sh rollback <state-dir>'
        state="$1"
        require_state "$state"
        [[ -f "$state/armed" ]] || fail 23 'rollback is not armed'
        root="$(cat "$state/root")"
        sha="$(cat "$state/start-sha")"
        verify_repository_identity "$state"
        git -C "$root" reset --hard "$sha" >/dev/null || fail 24 'git reset failed'
        git -C "$root" clean -fd >/dev/null || fail 25 'git clean failed'
        verify_repository_identity "$state"
        [[ -z "$(status_output "$root")" ]] || fail 26 'worktree is still dirty after rollback'
        printf '{"status":"FAILED_ROLLED_BACK","sha":"%s"}\n' "$sha"
        ;;

    *)
        fail 64 "unknown command: $command"
        ;;
esac

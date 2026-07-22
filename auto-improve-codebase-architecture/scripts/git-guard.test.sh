#!/usr/bin/env bash
set -euo pipefail

guard="$(cd "$(dirname "$0")" && pwd)/git-guard.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

new_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name Test
    printf 'base\n' > "$repo/app.txt"
    printf 'ignored.log\n' > "$repo/.gitignore"
    git -C "$repo" add app.txt .gitignore
    git -C "$repo" commit -qm init
}

repo="$tmp/repo"
state="$tmp/state"
new_repo "$repo"

# Preflight rejects every Git-visible dirty path, including untracked files.
printf 'dirty\n' > "$repo/untracked.txt"
if (cd "$repo" && "$guard" preflight "$state") >/dev/null 2>&1; then
    echo 'expected dirty preflight to fail' >&2
    exit 1
fi
rm "$repo/untracked.txt"

(cd "$repo" && "$guard" preflight "$state") >/dev/null
[[ "$(cat "$state/start-sha")" == "$(git -C "$repo" rev-parse --verify 'HEAD^{commit}')" ]]

# Scope accepts only frozen paths and requires a non-empty final diff.
"$guard" freeze "$state" app.txt tests/new.test.txt
printf 'changed\n' > "$repo/app.txt"
mkdir -p "$repo/tests"
printf 'test\n' > "$repo/tests/new.test.txt"
"$guard" check-scope "$state" --require-nonempty >/dev/null
"$guard" require-changed "$state" tests/new.test.txt >/dev/null
if "$guard" require-changed "$state" tests/missing.test.txt >/dev/null 2>&1; then
    echo 'expected unchanged required path to fail' >&2
    exit 1
fi
"$guard" snapshot-diff "$state" >/dev/null
chmod +x "$repo/tests/new.test.txt"
if "$guard" check-diff "$state" >/dev/null 2>&1; then
    echo 'expected untracked executable-bit change to fail' >&2
    exit 1
fi
chmod -x "$repo/tests/new.test.txt"
"$guard" check-diff "$state" >/dev/null
printf 'changed again\n' > "$repo/app.txt"
if "$guard" check-diff "$state" >/dev/null 2>&1; then
    echo 'expected changed frozen diff fingerprint to fail' >&2
    exit 1
fi
printf 'changed\n' > "$repo/app.txt"
"$guard" check-diff "$state" >/dev/null
printf 'outside\n' > "$repo/outside.txt"
if "$guard" check-scope "$state" --require-nonempty >/dev/null 2>&1; then
    echo 'expected out-of-scope diff to fail' >&2
    exit 1
fi

# Rollback restores tracked files, removes untracked files, and preserves ignored files.
printf 'keep\n' > "$repo/ignored.log"
"$guard" arm "$state"
"$guard" rollback "$state" >/dev/null
[[ "$(cat "$repo/app.txt")" == 'base' ]]
[[ ! -e "$repo/tests/new.test.txt" ]]
[[ ! -e "$repo/outside.txt" ]]
[[ "$(cat "$repo/ignored.log")" == 'keep' ]]
[[ -z "$(git -C "$repo" status --porcelain=v1 --untracked-files=all)" ]]

# A staged-then-deleted out-of-scope file cannot hide in the index.
index_repo="$tmp/index-repo"
index_state="$tmp/index-state"
new_repo "$index_repo"
(cd "$index_repo" && "$guard" preflight "$index_state") >/dev/null
"$guard" freeze "$index_state" app.txt >/dev/null
printf 'changed\n' > "$index_repo/app.txt"
printf 'staged\n' > "$index_repo/outside.txt"
git -C "$index_repo" add outside.txt
rm "$index_repo/outside.txt"
if "$guard" check-scope "$index_state" --require-nonempty >/dev/null 2>&1; then
    echo 'expected staged-only out-of-scope path to fail' >&2
    exit 1
fi

# Rename detection cannot hide deletion of an out-of-scope source path.
rename_repo="$tmp/rename-repo"
rename_state="$tmp/rename-state"
new_repo "$rename_repo"
mkdir -p "$rename_repo/src"
printf 'source\n' > "$rename_repo/src/a"
git -C "$rename_repo" add src/a
git -C "$rename_repo" commit -qm source
(cd "$rename_repo" && "$guard" preflight "$rename_state") >/dev/null
"$guard" freeze "$rename_state" src/b >/dev/null
git -C "$rename_repo" mv src/a src/b
if "$guard" check-scope "$rename_state" --require-nonempty >/dev/null 2>&1; then
    echo 'expected rename source outside scope to fail' >&2
    exit 1
fi

# Non-canonical paths are rejected instead of later mismatching Git paths.
if "$guard" freeze "$rename_state" src/./b >/dev/null 2>&1; then
    echo 'expected non-canonical manifest path to fail' >&2
    exit 1
fi

# Rollback refuses a changed branch/HEAD before running destructive reset.
head_repo="$tmp/head-repo"
head_state="$tmp/head-state"
new_repo "$head_repo"
(cd "$head_repo" && "$guard" preflight "$head_state") >/dev/null
"$guard" arm "$head_state" >/dev/null
git -C "$head_repo" checkout -qb temporary
echo committed > "$head_repo/new.txt"
git -C "$head_repo" add new.txt
git -C "$head_repo" commit -qm temporary
head_before="$(git -C "$head_repo" rev-parse HEAD)"
if "$guard" rollback "$head_state" >/dev/null 2>&1; then
    echo 'expected rollback with changed HEAD to fail' >&2
    exit 1
fi
[[ "$(git -C "$head_repo" rev-parse HEAD)" == "$head_before" ]]

# Frozen paths cannot escape the repository through a symlink component.
symlink_repo="$tmp/symlink-repo"
symlink_state="$tmp/symlink-state"
external="$tmp/external"
new_repo "$symlink_repo"
mkdir -p "$external"
ln -s "$external" "$symlink_repo/link"
git -C "$symlink_repo" add link
git -C "$symlink_repo" commit -qm symlink
(cd "$symlink_repo" && "$guard" preflight "$symlink_state") >/dev/null
if "$guard" freeze "$symlink_state" link/generated >/dev/null 2>&1; then
    echo 'expected symlink escape path to fail' >&2
    exit 1
fi
"$guard" freeze "$symlink_state" app.txt >/dev/null
rm "$symlink_repo/app.txt"
printf 'external\n' > "$external/file"
ln -s "$external/file" "$symlink_repo/app.txt"
if "$guard" check-scope "$symlink_state" --require-nonempty >/dev/null 2>&1; then
    echo 'expected post-freeze symlink replacement to fail' >&2
    exit 1
fi

# Simplified rollback intentionally declines repositories containing submodules.
child="$tmp/child"
submodule_repo="$tmp/submodule-repo"
submodule_state="$tmp/submodule-state"
new_repo "$child"
new_repo "$submodule_repo"
git -C "$submodule_repo" -c protocol.file.allow=always submodule add -q "$child" vendor/child
git -C "$submodule_repo" commit -qm submodule
if (cd "$submodule_repo" && "$guard" preflight "$submodule_state") >/dev/null 2>&1; then
    echo 'expected submodule preflight to fail' >&2
    exit 1
fi

echo 'git-guard tests: pass'

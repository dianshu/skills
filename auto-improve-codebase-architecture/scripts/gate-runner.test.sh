#!/usr/bin/env bash
set -euo pipefail

scripts="$(cd "$(dirname "$0")" && pwd)"
guard="$scripts/git-guard.sh"
runner="$scripts/gate-runner.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
state="$tmp/state"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
printf 'base\n' > "$repo/app.txt"
cat > "$repo/sample.test.ts" <<'TEST'
import { expect, test } from "bun:test";
test("sample", () => expect(1).toBe(1));
TEST
cat > "$repo/Makefile" <<'MAKE'
test:
	@bun test ./sample.test.ts
lint:
	@echo 'lint passed'
MAKE
git -C "$repo" add app.txt sample.test.ts Makefile
git -C "$repo" commit -qm init

(cd "$repo" && "$guard" preflight "$state") >/dev/null
"$guard" arm "$state" >/dev/null
"$runner" discover "$state" >/dev/null
if "$runner" discover "$state" >/dev/null 2>&1; then
    echo 'expected gate manifest rediscovery to fail' >&2
    exit 1
fi
grep -Fqx $'test\tMakefile:test\tmake test\tbun' "$state/gates.tsv"
grep -Fqx $'lint\tMakefile:lint\tmake lint\t-' "$state/gates.tsv"
"$runner" run "$state" baseline "$guard" >/dev/null
[[ "$(cat "$state/gate-run-status")" == 'PASS' ]]

"$guard" freeze "$state" app.txt >/dev/null
printf 'changed\n' > "$repo/app.txt"
"$runner" run "$state" final "$guard" >/dev/null
[[ "$(cat "$state/gate-run-status")" == 'PASS' ]]
[[ "$(cat "$repo/app.txt")" == 'changed' ]]
printf '\n# changed gate source\n' >> "$repo/Makefile"
"$runner" run "$state" final "$guard" >/dev/null 2>&1
[[ "$(cat "$state/gate-run-status")" == 'FAILED' ]]
git -C "$repo" checkout -- Makefile

# A baseline gate that mutates the repository is rolled back automatically.
mutating="$tmp/mutating"
mutating_state="$tmp/mutating-state"
mkdir -p "$mutating"
git -C "$mutating" init -q
git -C "$mutating" config user.email test@example.com
git -C "$mutating" config user.name Test
printf 'base\n' > "$mutating/app.txt"
cat > "$mutating/sample.test.ts" <<'TEST'
import { expect, test } from "bun:test";
test("sample", () => expect(1).toBe(1));
TEST
cat > "$mutating/Makefile" <<'MAKE'
test:
	@echo '# gate mutation' >> Makefile
	@bun test ./sample.test.ts
MAKE
git -C "$mutating" add app.txt sample.test.ts Makefile
git -C "$mutating" commit -qm init
(cd "$mutating" && "$guard" preflight "$mutating_state") >/dev/null
"$guard" arm "$mutating_state" >/dev/null
"$runner" discover "$mutating_state" >/dev/null
"$runner" run "$mutating_state" baseline "$guard" >/dev/null
[[ "$(cat "$mutating_state/gate-run-status")" == 'FAILED_ROLLED_BACK' ]]
! grep -Fq '# gate mutation' "$mutating/Makefile"
[[ -z "$(git -C "$mutating" status --porcelain=v1 --untracked-files=all)" ]]

# Gate commands may not leave a background process that mutates files later.
background="$tmp/background"
background_state="$tmp/background-state"
mkdir -p "$background"
git -C "$background" init -q
git -C "$background" config user.email test@example.com
git -C "$background" config user.name Test
printf 'base\n' > "$background/app.txt"
cat > "$background/sample.test.ts" <<'TEST'
import { expect, test } from "bun:test";
test("sample", () => expect(1).toBe(1));
TEST
cat > "$background/Makefile" <<'MAKE'
test:
	@bun test ./sample.test.ts
	@nohup sh -c 'sleep 1; echo late > app.txt' >/dev/null 2>&1 &
MAKE
git -C "$background" add app.txt sample.test.ts Makefile
git -C "$background" commit -qm init
(cd "$background" && "$guard" preflight "$background_state") >/dev/null
"$guard" arm "$background_state" >/dev/null
"$runner" discover "$background_state" >/dev/null
"$runner" run "$background_state" baseline "$guard" >/dev/null
[[ "$(cat "$background_state/gate-run-status")" == 'NOOP' ]]
sleep 1.2
[[ "$(cat "$background/app.txt")" == 'base' ]]

# A fake success message is not accepted as behavior-test proof.
fake="$tmp/fake"
fake_state="$tmp/fake-state"
mkdir -p "$fake"
git -C "$fake" init -q
git -C "$fake" config user.email test@example.com
git -C "$fake" config user.name Test
cat > "$fake/Makefile" <<'MAKE'
test:
	@echo '1 test passed'
MAKE
git -C "$fake" add Makefile
git -C "$fake" commit -qm init
(cd "$fake" && "$guard" preflight "$fake_state") >/dev/null
if "$runner" discover "$fake_state" >/dev/null 2>&1; then
    echo 'expected fake behavior-test discovery to fail' >&2
    exit 1
fi

# Discovery fails closed when no behavior test gate exists.
empty="$tmp/empty"
empty_state="$tmp/empty-state"
mkdir -p "$empty"
git -C "$empty" init -q
git -C "$empty" config user.email test@example.com
git -C "$empty" config user.name Test
printf 'base\n' > "$empty/app.txt"
git -C "$empty" add app.txt
git -C "$empty" commit -qm init
(cd "$empty" && "$guard" preflight "$empty_state") >/dev/null
if "$runner" discover "$empty_state" >/dev/null 2>&1; then
    echo 'expected empty gate discovery to fail' >&2
    exit 1
fi

echo 'gate-runner tests: pass'

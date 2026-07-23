#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf '%s\n' "$2" >&2
    exit "$1"
}

require_state() {
    [[ -f "$1/root" && -f "$1/start-sha" && -f "$1/start-head" ]] || fail 65 'invalid guard state'
}

detect_runner() {
    local text
    text="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$text" in
        *'bun test'*) printf 'bun\n' ;;
        *vitest*) printf 'vitest\n' ;;
        *jest*) printf 'jest\n' ;;
        *pytest*) printf 'pytest\n' ;;
        *'cargo test'*) printf 'cargo\n' ;;
        *) printf 'none\n' ;;
    esac
}

add_source() {
    local source_path="$1" hash
    hash="$(git -C "$root" hash-object -- "$source_path")" || fail 34 "cannot hash gate source: $source_path"
    if ! grep -Fq -- "${source_path}"$'\t' "$sources_tmp" 2>/dev/null; then
        printf '%s\t%s\n' "$source_path" "$hash" >> "$sources_tmp"
    fi
}

add_gate() {
    local order="$1" category="$2" source="$3" source_path="$4" gate_command="$5" runner="$6" key
    if [[ "$category" == test || "$category" == integration || "$category" == e2e ]]; then
        [[ "$runner" != none ]] || return 0
    else
        runner='-'
    fi
    key="${category}"$'\t'"${gate_command}"
    if ! cut -f2,4 "$gates_tmp" 2>/dev/null | grep -Fqx -- "$key"; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$order" "$category" "$source" "$gate_command" "$runner" >> "$gates_tmp"
        add_source "$source_path"
    fi
}

check_frozen_inputs() {
    local state="$1" root source_path expected actual manifest_hash
    root="$(cat "$state/root")"
    manifest_hash="$(git hash-object --stdin < "$state/gates.tsv")"
    if [[ "$manifest_hash" != "$(cat "$state/gates.sha")" ]]; then
        printf '%s\n' 'gate manifest changed after discovery' >&2
        return 1
    fi
    while IFS=$'\t' read -r source_path expected; do
        actual="$(git -C "$root" hash-object -- "$source_path" 2>/dev/null)" || {
            printf 'gate source disappeared: %s\n' "$source_path" >&2
            return 1
        }
        if [[ "$actual" != "$expected" ]]; then
            printf 'gate source changed after discovery: %s\n' "$source_path" >&2
            return 1
        fi
    done < "$state/gate-sources.tsv"
}

behavior_output_has_tests() {
    local runner="$1" log="$2"
    case "$runner" in
        bun)
            grep -Eiq '(^|[^0-9])[1-9][0-9]*[[:space:]]+pass' "$log"
            ;;
        vitest)
            grep -Eiq '(Tests|Test Files)[[:space:]]+[1-9][0-9]*[[:space:]]+passed' "$log"
            ;;
        jest)
            grep -Eiq 'Tests:[[:space:]]+[1-9][0-9]*[[:space:]]+passed' "$log"
            ;;
        pytest)
            grep -Eiq '(^|[^0-9])[1-9][0-9]*[[:space:]]+passed' "$log"
            ;;
        cargo)
            grep -Eiq 'test result: ok\.[[:space:]]+[1-9][0-9]*[[:space:]]+passed' "$log"
            ;;
        *)
            return 1
            ;;
    esac
}

emit_run_result() {
    local state="$1" status="$2" reason="$3" gates="${4:-0}" behavior="${5:-0}" tmp
    printf '%s\n' "$status" > "$state/gate-run-status"
    tmp="$(mktemp "$state/gate-result.XXXXXX")"
    printf '{"status":"%s","reason":"%s","gates":%s,"behaviorGates":%s}\n' "$status" "$reason" "$gates" "$behavior" > "$tmp"
    mv "$tmp" "$state/gate-result.json"
    cat "$state/gate-result.json"
}

stop_process_group() {
    local leader="$1"
    if kill -0 -- "-$leader" 2>/dev/null; then
        kill -TERM -- "-$leader" 2>/dev/null || true
        sleep 0.1
        kill -KILL -- "-$leader" 2>/dev/null || true
        return 0
    fi
    return 1
}

command="${1:-}"
[[ -n "$command" ]] || fail 64 'usage: gate-runner.sh <discover|run> ...'
shift

case "$command" in
    discover)
        [[ $# -eq 1 ]] || fail 64 'usage: gate-runner.sh discover <state-dir>'
        state="$1"
        require_state "$state"
        [[ ! -e "$state/gates.tsv" ]] || fail 33 'gate manifest is already frozen'
        root="$(cat "$state/root")"
        gates_tmp="$state/gates.tmp"
        sources_tmp="$state/gate-sources.tmp"
        : > "$gates_tmp"
        : > "$sources_tmp"

        order=1
        for directory in .claude/scripts .pi/scripts; do
            for spec in \
                'test:test.sh' \
                'test:test-unit.sh' \
                'integration:test-integration.sh' \
                'e2e:e2e.sh' \
                'lint:lint.sh' \
                'typecheck:typecheck.sh' \
                'build:build.sh'; do
                category="${spec%%:*}"
                script="${spec#*:}"
                source_path="$directory/$script"
                if [[ -f "$root/$source_path" ]]; then
                    runner="$(detect_runner "$(cat "$root/$source_path")")"
                    add_gate "$order" "$category" "$source_path" "$source_path" "bash $source_path" "$runner"
                fi
            done
        done

        order=2
        if [[ -f "$root/Makefile" ]]; then
            for spec in \
                'test:test' \
                'test:test-unit' \
                'integration:test-integration' \
                'e2e:e2e' \
                'e2e:test-e2e' \
                'lint:lint' \
                'typecheck:typecheck' \
                'build:build'; do
                category="${spec%%:*}"
                target="${spec#*:}"
                if grep -Eq "^${target}([[:space:]]*):" "$root/Makefile"; then
                    recipe="$(awk -v target="$target" '$0 ~ "^" target "[[:space:]]*:" { found=1; next } found && /^\t/ { print; next } found { exit }' "$root/Makefile")"
                    runner="$(detect_runner "$recipe")"
                    add_gate "$order" "$category" "Makefile:$target" Makefile "make $target" "$runner"
                fi
            done
        fi

        order=3
        if [[ -f "$root/package.json" ]]; then
            command -v jq >/dev/null 2>&1 || fail 30 'jq is required to inspect package.json scripts'
            if [[ -f "$root/bun.lock" || -f "$root/bun.lockb" ]]; then
                package_runner='bun run'
            elif [[ -f "$root/pnpm-lock.yaml" ]]; then
                package_runner='pnpm run'
            elif [[ -f "$root/yarn.lock" ]]; then
                package_runner='yarn run'
            else
                package_runner='npm run'
            fi
            for spec in \
                'test:test' \
                'test:test:unit' \
                'integration:test:integration' \
                'e2e:e2e' \
                'e2e:test:e2e' \
                'lint:lint' \
                'typecheck:typecheck' \
                'build:build'; do
                category="${spec%%:*}"
                key="${spec#*:}"
                script_body="$(jq -r --arg key "$key" '.scripts[$key] // empty' "$root/package.json")"
                if [[ -n "$script_body" ]]; then
                    runner="$(detect_runner "$script_body")"
                    add_gate "$order" "$category" "package.json:scripts.$key" package.json "$package_runner $key" "$runner"
                fi
            done
        fi

        [[ -s "$gates_tmp" ]] || fail 31 'no supported standard gates discovered'
        tab=$'\t'
        LC_ALL=C sort -t "$tab" -k2,2 -k1,1n -k3,3 "$gates_tmp" | cut -f2,3,4,5 > "$state/gates.tsv"
        LC_ALL=C sort -u "$sources_tmp" > "$state/gate-sources.tsv"
        rm -f "$gates_tmp" "$sources_tmp"
        if ! grep -Eq $'^(test|integration|e2e)\t' "$state/gates.tsv"; then
            fail 32 'no supported behavior test gate discovered'
        fi
        git hash-object --stdin < "$state/gates.tsv" > "$state/gates.sha"
        printf '{"status":"READY","gates":%s}\n' "$(wc -l < "$state/gates.tsv" | tr -d ' ')"
        ;;

    run)
        [[ $# -eq 3 ]] || fail 64 'usage: gate-runner.sh run <state-dir> <baseline|final> <guard-path>'
        state="$1"
        mode="$2"
        guard="$3"
        require_state "$state"
        [[ -f "$state/gates.tsv" && -f "$state/gates.sha" && -f "$state/gate-sources.tsv" ]] || fail 65 'gate manifest is not discovered'
        [[ "$mode" == baseline || "$mode" == final ]] || fail 64 "invalid gate mode: $mode"
        command -v setsid >/dev/null 2>&1 || fail 38 'setsid is required for controlled gate processes'
        root="$(cat "$state/root")"
        rm -f "$state/gate-run-status" "$state/gate-result.json"
        if ! check_frozen_inputs "$state"; then
            if [[ "$mode" == baseline ]] && ! "$guard" check-clean "$state" >/dev/null; then
                if "$guard" rollback "$state" >/dev/null; then
                    status='FAILED_ROLLED_BACK'
                else
                    status='ROLLBACK_FAILED'
                fi
            elif [[ "$mode" == baseline ]]; then
                status='NOOP'
            else
                status='FAILED'
            fi
            emit_run_result "$state" "$status" 'frozen gate inputs changed'
            exit 0
        fi
        : > "$state/gate-results.tsv"
        behavior_count=0
        if [[ "$mode" == final ]]; then
            "$guard" snapshot-diff "$state" >/dev/null
        fi

        index=0
        while IFS=$'\t' read -r category source gate_command runner; do
            index=$((index + 1))
            log="$state/gate-$mode-$index.log"
            set +e
            (cd "$root" && setsid bash -o pipefail -c "$gate_command") > "$log" 2>&1 &
            leader=$!
            wait "$leader"
            exit_code=$?
            set -e
            background_processes=false
            if stop_process_group "$leader"; then
                background_processes=true
                exit_code=70
            fi
            cat "$log"
            proof='n/a'
            case "$category" in
                test|integration|e2e)
                    if behavior_output_has_tests "$runner" "$log"; then
                        proof='executed'
                        behavior_count=$((behavior_count + 1))
                    else
                        proof='missing'
                    fi
                    ;;
            esac
            printf '%s\t%s\t%s\t%s\t%s\n' "$category" "$source" "$gate_command" "$exit_code" "$proof" >> "$state/gate-results.tsv"

            inputs_ok=true
            if ! check_frozen_inputs "$state"; then
                inputs_ok=false
                exit_code=71
            fi
            if [[ "$mode" == baseline ]]; then
                if ! "$guard" check-clean "$state" >/dev/null; then
                    if "$guard" rollback "$state" >/dev/null; then
                        status='FAILED_ROLLED_BACK'
                    else
                        status='ROLLBACK_FAILED'
                    fi
                    emit_run_result "$state" "$status" 'baseline changed worktree' "$index" "$behavior_count"
                    exit 0
                fi
            else
                if ! "$guard" check-scope "$state" >/dev/null || ! "$guard" check-diff "$state" >/dev/null; then
                    emit_run_result "$state" 'FAILED' 'final gate changed diff or scope' "$index" "$behavior_count"
                    exit 0
                fi
            fi

            if [[ "$exit_code" -ne 0 || "$proof" == missing || "$background_processes" == true || "$inputs_ok" == false ]]; then
                if [[ "$mode" == baseline ]]; then status='NOOP'; else status='FAILED'; fi
                emit_run_result "$state" "$status" 'gate failed, escaped a process, or executed no supported tests' "$index" "$behavior_count"
                exit 0
            fi
        done < "$state/gates.tsv"

        if [[ "$behavior_count" -lt 1 ]]; then
            if [[ "$mode" == baseline ]]; then status='NOOP'; else status='FAILED'; fi
            emit_run_result "$state" "$status" 'no behavior tests executed' "$index" "$behavior_count"
            exit 0
        fi
        emit_run_result "$state" 'PASS' 'all gates passed' "$index" "$behavior_count"
        ;;

    *)
        fail 64 "unknown command: $command"
        ;;
esac

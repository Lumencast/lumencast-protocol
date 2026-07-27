#!/usr/bin/env bash
# Lumencast cross-language interop matrix driver.
#
# Walks the (server-impl × harness-impl) matrix and runs every
# conformance scenario through each pair. Skips homogeneous pairs
# (same SDK on both sides) — those are covered by each SDK's own CI.
#
# Usage :
#   ./run-matrix.sh                              # full matrix
#   ./run-matrix.sh --server go --harness js     # single pair
#   ./run-matrix.sh --scenario ping-pong-roundtrip  # single scenario
#   ./run-matrix.sh --report MATRIX.md           # write report file
#
# Environment :
#   LUMENCAST_GO  — path to lumencast-go checkout (default ../../lumencast-go)
#   LUMENCAST_JS  — path to lumencast-js checkout (default ../../lumencast-js)
#   LUMENCAST_RS  — path to lumencast-rs checkout (default ../../lumencast-rs)
#   INTEROP_VERBOSE=1 — stream subprocess stdout/stderr inline.
#
# Exit codes :
#   0 — every cell passed
#   1 — at least one cell failed
#   2 — a structural / configuration error (no SDKs, ports unavailable, …)
#
# This driver is SDK-agnostic ; the (impl-name → CLI invocation) map
# lives in `_resolve_sdk()`. To add an SDK, edit only that function.

set -u
set -o pipefail

readonly INTEROP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${INTEROP_DIR}/.." && pwd)"
readonly SCENARIOS_DIR="${REPO_ROOT}/conformance/v1/scenarios"

LUMENCAST_GO="${LUMENCAST_GO:-${REPO_ROOT}/../lumencast-go}"
LUMENCAST_JS="${LUMENCAST_JS:-${REPO_ROOT}/../lumencast-js}"
LUMENCAST_RS="${LUMENCAST_RS:-${REPO_ROOT}/../lumencast-rs}"
LUMENCAST_PY="${LUMENCAST_PY:-${REPO_ROOT}/../lumencast-py}"

readonly SDKS=(go js rs py)

# Per-cell defaults.
WANT_SERVER=""
WANT_HARNESS=""
WANT_SCENARIO=""
REPORT_PATH=""

usage() {
    cat <<USAGE
usage: run-matrix.sh [--server NAME] [--harness NAME] [--scenario NAME] [--report FILE]

  --server NAME    restrict to a single server impl (go | js | rs | py)
  --harness NAME   restrict to a single harness impl (go | js | rs | py)
  --scenario NAME  restrict to a single scenario (no .yaml suffix)
  --report FILE    write a markdown report to FILE
  -h, --help       show this help

Without filters, every (server × harness) pair where server != harness
is run against every scenario in conformance/v1/scenarios/.
USAGE
}

while (( $# )); do
    case "$1" in
        --server)   WANT_SERVER="$2"; shift 2 ;;
        --harness)  WANT_HARNESS="$2"; shift 2 ;;
        --scenario) WANT_SCENARIO="$2"; shift 2 ;;
        --report)   REPORT_PATH="$2"; shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Ask a CLI for its own help and check that it advertises `${2}`. An SDK
# that has not shipped its interop hooks yet still ships a `lumencast`
# binary : without this probe such a cell reports FAIL (a regression the
# protocol repo cannot fix) instead of n/a (not wired yet).
_supports_subcommand() {
    local launcher="$1" sub="$2" help_out=""
    local timeout_cmd=""
    command -v timeout >/dev/null 2>&1 && timeout_cmd="timeout 20"
    # shellcheck disable=SC2086
    help_out="$(${timeout_cmd} ${launcher} --help 2>&1)" || true
    grep -qE "(^|[^[:alnum:]_-])${sub}([^[:alnum:]_-]|$)" <<<"${help_out}"
}

# Map impl name → "<command> ..." invocation lines that the driver
# substitutes {CONTROL_PORT} and {WS_PORT} into for serve-scenario, and
# {WS_URL} and {CONTROL_URL} into for conformance.
#
# Returns 1 (→ cell reported n/a) when the SDK is absent, unbuilt, or does
# not advertise the requested interop subcommand.
_resolve_sdk() {
    local impl="$1" mode="$2"  # mode = serve | conform
    local launcher="" prefix="" bin="" entry=""
    case "${impl}" in
        go)
            bin="${LUMENCAST_GO}/bin/lumencast"
            [[ -x "${bin}" ]] || return 1
            launcher="${bin}"
            ;;
        js)
            case "${mode}" in
                serve)   entry="${LUMENCAST_JS}/packages/server/dist/cli.js" ;;
                conform) entry="${LUMENCAST_JS}/packages/protocol/dist/cli.js" ;;
                *)       return 1 ;;
            esac
            [[ -f "${entry}" ]] || return 1
            launcher="node ${entry}"
            ;;
        rs)
            bin="${LUMENCAST_RS}/target/release/lumencast"
            [[ -x "${bin}" ]] || return 1
            launcher="${bin}"
            ;;
        py)
            # The py SDK is usable only when its checkout is present AND the
            # module is importable : a bare system python3 would otherwise
            # resolve here and produce bogus FAILs for every py cell.
            [[ -d "${LUMENCAST_PY}" ]] || return 1
            entry="${LUMENCAST_PY}/.venv/bin/python"
            [[ -x "${entry}" ]] || entry="${LUMENCAST_PY}/.venv/Scripts/python.exe"
            [[ -x "${entry}" ]] || entry="$(command -v python3 || command -v python || true)"
            [[ -n "${entry}" && -x "${entry}" ]] || return 1
            "${entry}" -c 'import lumencast' >/dev/null 2>&1 || return 1
            launcher="${entry} -m lumencast"
            prefix="env LUMENCAST_PROTOCOL_REPO=${REPO_ROOT} "
            ;;
        *) return 1 ;;
    esac

    case "${mode}" in
        serve)
            _supports_subcommand "${launcher}" serve-scenario || return 1
            echo "${prefix}${launcher} serve-scenario --test-control-port {CONTROL_PORT} --ws-port {WS_PORT}"
            ;;
        conform)
            _supports_subcommand "${launcher}" conformance || return 1
            echo "${prefix}${launcher} conformance --server {WS_URL} --control-url {CONTROL_URL}"
            ;;
        *) return 1 ;;
    esac
}

_log() { printf '[interop] %s\n' "$*" >&2; }

_pick_free_port() {
    # Ask the kernel for a free port. Bash + python fallback for
    # portability across CI images.
    python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

_wait_for_discovery() {
    local stdout_file="$1" timeout_s="${2:-15}"
    local started_at; started_at="$(date +%s)"
    while true; do
        if grep -E '"control_url"\s*:\s*"http://' "${stdout_file}" >/dev/null 2>&1; then
            return 0
        fi
        if (( $(date +%s) - started_at >= timeout_s )); then
            return 1
        fi
        sleep 0.1
    done
}

_run_pair() {
    local server="$1" harness="$2" scenario_filter="${3:-}"
    local serve_cmd conform_cmd
    serve_cmd="$(_resolve_sdk "${server}" serve 2>/dev/null)" || {
        _log "skip ${server}×${harness}: server SDK not built"
        echo "n/a"
        return 0
    }
    conform_cmd="$(_resolve_sdk "${harness}" conform 2>/dev/null)" || {
        _log "skip ${server}×${harness}: harness SDK not built"
        echo "n/a"
        return 0
    }

    local control_port ws_port
    control_port="$(_pick_free_port)"
    ws_port="$(_pick_free_port)"

    local serve_invocation="${serve_cmd//\{CONTROL_PORT\}/${control_port}}"
    serve_invocation="${serve_invocation//\{WS_PORT\}/${ws_port}}"

    local stdout_file; stdout_file="$(mktemp -t interop.XXXXXX.stdout)"
    local stderr_file; stderr_file="$(mktemp -t interop.XXXXXX.stderr)"

    # shellcheck disable=SC2086
    ${serve_invocation} >"${stdout_file}" 2>"${stderr_file}" &
    local server_pid=$!

    if ! _wait_for_discovery "${stdout_file}" 15; then
        kill -TERM "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
        _log "${server}×${harness}: server never printed discovery line"
        [[ -n "${INTEROP_VERBOSE:-}" ]] && cat "${stderr_file}" >&2
        rm -f "${stdout_file}" "${stderr_file}"
        echo "FAIL"
        return 1
    fi

    local ws_url="ws://127.0.0.1:${ws_port}/lsdp.v1"
    local control_url="http://127.0.0.1:${control_port}"

    local conform_invocation="${conform_cmd//\{WS_URL\}/${ws_url}}"
    conform_invocation="${conform_invocation//\{CONTROL_URL\}/${control_url}}"
    if [[ -n "${scenario_filter}" ]]; then
        conform_invocation="${conform_invocation} --scenario ${scenario_filter}"
    fi

    local rc=0
    local conform_log; conform_log="$(mktemp -t interop.XXXXXX.conform)"
    # shellcheck disable=SC2086
    if [[ -n "${INTEROP_VERBOSE:-}" ]]; then
        ${conform_invocation} 2>&1 | tee "${conform_log}" || rc=$?
    else
        ${conform_invocation} >"${conform_log}" 2>&1 || rc=$?
    fi

    kill -TERM "${server_pid}" 2>/dev/null || true
    wait "${server_pid}" 2>/dev/null || true

    if (( rc == 0 )); then
        echo "PASS"
    else
        _log "${server}×${harness}: harness rc=${rc}"
        [[ -n "${INTEROP_VERBOSE:-}" ]] || tail -n 40 "${conform_log}" >&2
        echo "FAIL"
    fi

    rm -f "${stdout_file}" "${stderr_file}" "${conform_log}"
    return 0
}

main() {
    if [[ ! -d "${SCENARIOS_DIR}" ]]; then
        _log "no scenarios at ${SCENARIOS_DIR}"
        exit 2
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        _log "python3 required for free-port discovery"
        exit 2
    fi

    declare -A results
    local total_fails=0
    local total_cells=0
    local executed=0

    for server in "${SDKS[@]}"; do
        [[ -n "${WANT_SERVER}" && "${server}" != "${WANT_SERVER}" ]] && continue
        for harness in "${SDKS[@]}"; do
            [[ -n "${WANT_HARNESS}" && "${harness}" != "${WANT_HARNESS}" ]] && continue
            [[ "${server}" == "${harness}" ]] && continue

            _log "running pair: server=${server} × harness=${harness}"
            local outcome
            outcome="$(_run_pair "${server}" "${harness}" "${WANT_SCENARIO}")"
            results["${server}×${harness}"]="${outcome}"
            total_cells=$((total_cells + 1))
            case "${outcome}" in
                PASS) executed=$((executed + 1)) ;;
                FAIL) executed=$((executed + 1)); total_fails=$((total_fails + 1)) ;;
            esac
        done
    done

    {
        echo
        echo "Interop matrix — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo
        printf '| Server | Harness | Outcome |\n'
        printf '|---|---|---|\n'
        for key in "${!results[@]}"; do
            local s="${key%%×*}" h="${key##*×}"
            printf '| %s | %s | %s |\n' "${s}" "${h}" "${results[${key}]}"
        done | sort
        echo
        printf '%s executed cell(s) out of %s — %s failed, %s reported n/a (SDK absent or interop hooks not wired).\n' \
            "${executed}" "${total_cells}" "${total_fails}" "$((total_cells - executed))"
    } | tee /dev/stderr | { [[ -n "${REPORT_PATH}" ]] && cat > "${REPORT_PATH}" || cat > /dev/null; }

    if (( executed == 0 )); then
        # Every cell was n/a : no conformance scenario ran at all. Reporting
        # success here is the false-pass this driver exists to prevent.
        _log "no cell could run (${total_cells} cells, all n/a) — refusing to report success"
        exit 2
    fi
    if (( total_fails > 0 )); then
        _log "${total_fails}/${executed} executed cells failed"
        exit 1
    fi
    _log "${executed}/${executed} executed cells passed"
}

main "$@"

#!/usr/bin/env bash
# HULLDOWN full validation gate: format, lint, type-check (Roblox API), unit/integration tests, place build.
# Usage: scripts/check.sh [--fix] [--only fmt|lint|types|test|build] [-- test-filter]
# Tools are resolved from PATH; set HULLDOWN_TOOLS to a directory containing the binaries to prepend it.
set -uo pipefail
cd "$(dirname "$0")/.."
if [[ -n "${HULLDOWN_TOOLS:-}" ]]; then export PATH="$HULLDOWN_TOOLS:$PATH"; fi
DEFS="${HULLDOWN_ROBLOX_DEFS:-${HULLDOWN_TOOLS:-.tools}/roblox.d.luau}"

FIX=0; ONLY=""; FILTER=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--fix) FIX=1 ;;
		--only) ONLY="$2"; shift ;;
		--) shift; FILTER="${*:-}"; break ;;
	esac
	shift
done

FAILED=()
run_step() {
	local name="$1"; shift
	if [[ -n "$ONLY" && "$ONLY" != "$name" ]]; then return; fi
	echo "==> $name"
	if "$@"; then echo "    ok: $name"; else echo "    FAILED: $name"; FAILED+=("$name"); fi
}

fmt() {
	if [[ $FIX -eq 1 ]]; then stylua src tests; else stylua --check src tests; fi
}
lint() { selene src tests; }
types() {
	rojo sourcemap default.project.json -o sourcemap.json >/dev/null || return 1
	local out
	out=$(luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions="$DEFS" \
		--ignore="**/node_modules/**" src 2>&1 | grep -vE '^\[(INFO|WARN)\]')
	if [[ -n "$out" ]]; then echo "$out"; local n; n=$(echo "$out" | grep -cE '(TypeError|SyntaxError|Lint)'); echo "    $n diagnostics"; return 1; fi
}
tests() { lune run tests/run.luau -- $FILTER; }
build() { mkdir -p build && rojo build default.project.json -o build/Hulldown.rbxl >/dev/null; }

run_step fmt fmt
run_step lint lint
run_step types types
run_step test tests
run_step build build

if [[ ${#FAILED[@]} -gt 0 ]]; then echo "CHECK FAILED: ${FAILED[*]}"; exit 1; fi
echo "ALL CHECKS PASSED"

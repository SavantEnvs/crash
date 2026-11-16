#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer checks of the plain-flags crash binary built by mayhem/build.sh:
# open each seed dump (ELF kdump, compressed kdump) with the fixture namelist and assert the bytes
# `rd -p` reads back from physical memory, plus the expression evaluator and a read-error path.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

CRASH="$SRC/mayhem/build/oracle/crash"
NAMELIST="$SRC/mayhem/build/fixture/vmlinux"
SEEDS="$SRC/mayhem/crash/testsuite"
for f in "$CRASH" "$NAMELIST"; do
  [ -x "$f" ] || { echo "missing $f: mayhem/build.sh must build it" >&2; emit_ctrf crash-known-answer 0 1; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
passed=0
failed=0

# expect <dump> <crash command> <fixed string that must appear in the output>...
expect() {
  local dump="$1" cmd="$2"; shift 2
  printf '%s\nquit\n' "$cmd" > "$tmp/cmds"
  local out
  out="$(cd "$tmp" && timeout 60 "$CRASH" --minimal -i "$tmp/cmds" "$NAMELIST" "$SEEDS/$dump" </dev/null 2>&1)"
  local needle ok=1
  for needle in "$@"; do
    grep -qF -- "$needle" <<<"$out" || { ok=0; echo "FAIL [$dump: $cmd] missing: $needle" >&2; }
  done
  if [ "$ok" = 1 ]; then passed=$((passed + 1)); echo "ok   [$dump: $cmd]"
  else failed=$((failed + 1)); printf '%s\n' "$out" | tail -15 >&2; fi
}

expect elf64.core               "rd -p 1000 4" "432d4d454859414d 214b4f2d48534152" "MAYHEM-CRASH-OK!"
expect elf64.core               "rd -p 1010 2" "0706050403020100 0f0e0d0c0b0a0908"
expect elf64.core               "rd -p 0 2"    "physical address: 0"
expect elf64-two-segments.core  "rd -p 100000 2" "532d444e4f434553 2121544e454d4745" "SECOND-SEGMENT!!"
expect elf64-vmcoreinfo.core    "rd -p 1000 2" "MAYHEM-CRASH-OK!"
expect kdump-v2.dump            "rd -p 1000 2" "432d4d454859414d 214b4f2d48534152"
expect kdump-v2-zlib.dump       "rd -p 2000 2" "4741502d42494c5a 2121214f57542d45" "ZLIB-PAGE-TWO!!!"
expect elf64.core               "eval 0x1000+0x234" "hexadecimal: 1234" "decimal: 4660"

emit_ctrf crash-known-answer "$passed" "$failed"

#!/usr/bin/env bash
#
# mayhem/build.sh — build crash twice: a plain-flags binary for the functional oracle (mayhem/test.sh)
# and an ASan+UBSan binary for fuzzing. Runs inside the commit image as `mayhem` in /mayhem, offline.
#
# crash embeds gdb 16.2 (fetched by upstream's Makefile; pre-fetched into /opt/toolchains/deps). The
# gdb half is built once, uninstrumented, with the same gcc/g++ the oracle uses; only crash's own
# sources (the dump-file parsers being fuzzed) are rebuilt with $SANITIZER_FLAGS and relinked.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX MAYHEM_JOBS

GDB_VER=16.2
GDB_TARBALL=/opt/toolchains/deps/gdb-$GDB_VER/src/gdb-$GDB_VER.tar.gz
[ -f "$GDB_TARBALL" ] || { echo "missing $GDB_TARBALL (Dockerfile pre-fetch)" >&2; exit 1; }

cd "$SRC"
B="$SRC/mayhem/build"
rm -rf "$B"
mkdir -p "$B/tree" "$B/oracle" "$B/fixture"

# Out-of-tree copy: upstream's build is in-tree only.
tar -C "$SRC" --exclude=./.git --exclude=./mayhem/build --exclude=./crash -cf - . | tar -C "$B/tree" -xf -
cd "$B/tree"
ln -s "$GDB_TARBALL" "gdb-$GDB_VER.tar.gz"

# 1) Plain build (upstream's default compiler, no sanitizers): the embedded gdb and the oracle binary.
#    CC/CXX are dropped from the environment so gdb's configure picks the same gcc/g++ as the Makefile.
#    gcc 14 defaults to DWARF-5; the linked crash binary must carry DWARF < 4 (§6.2 item 10), gdb's
#    objects included, so the plain build gets -gdwarf-3 too.
plain() { env -u CC -u CXX -u LDFLAGS -u SANITIZER_FLAGS -u DEBUG_FLAGS \
  CFLAGS="$DEBUG_FLAGS -O2" CXXFLAGS="$DEBUG_FLAGS -O2" "$@"; }
#    The lzo/snappy/zstd goals only add -DLZO/-DSNAPPY/-DZSTD; they still run the full default build.
plain make -j"$MAYHEM_JOBS" lzo snappy zstd >"$B/plain-build.log" 2>&1 || { tail -50 "$B/plain-build.log" >&2; exit 1; }
cp crash "$B/oracle/crash"

# 2) Fuzz binary: rebuild crash's own objects with the sanitizers and relink against the plain gdb.
#    -fno-sanitize=alignment: crash reads on-disk structures through casts on every dump format.
SAN="$SANITIZER_FLAGS -fno-sanitize=alignment $DEBUG_FLAGS -O1"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/lsan_off.o"
rm -f crash crashlib.a ./*.o
# The crash Makefile hardcodes CC=gcc and gdb's Makefile clears command-line overrides before
# re-entering it, so build crash's objects here, where CC=clang is honoured.
plain make GDB_FLAGS=-DGDB_${GDB_VER//./_} CC=clang CFLAGS="$SAN" library >"$B/san-lib.log" 2>&1 \
  || { tail -50 "$B/san-lib.log" >&2; exit 1; }
CRASH_TARGET="$(cat gdb-$GDB_VER/crash.target)"
(
  cd "gdb-$GDB_VER/gdb"
  plain make CRASH_TARGET="$CRASH_TARGET" CC=clang \
    CFLAGS="$SAN $(tr '\n' ' ' < ../../CFLAGS.extra)" \
    CC_LD="\$(LIBTOOL) \$(SILENT_FLAG) --tag=CXX --mode=link clang++ $SAN $B/lsan_off.o" \
    gdb >"$B/san-build.log" 2>&1 || { tail -50 "$B/san-build.log" >&2; exit 1; }
)
cp crash "$SRC/crash"

# 3) Namelist stand-in: crash needs an ELF with struct task_struct debug info before it opens a dump.
$CC $DEBUG_FLAGS -O0 -static -nostdlib -Wl,-e,main -o "$B/fixture/vmlinux" "$SRC/mayhem/crash/fixture.c"

if [ -n "$SANITIZER_FLAGS" ]; then
  nm "$SRC/crash" | grep __asan_init >/dev/null || { echo "crash was not linked with ASan" >&2; exit 1; }
fi
ls -la "$SRC/crash" "$B/oracle/crash" "$B/fixture/vmlinux"

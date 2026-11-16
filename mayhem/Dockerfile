# syntax=docker/dockerfile:1.7
#
# Commit image for crash (Linux kernel crash-dump analyzer): builds on the org C/C++ base.
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile --build-arg COMMIT=$(git rev-parse HEAD) -t mytag .
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# crash embeds gdb and links termcap/gmp/mpfr plus the dump decompressors (lzo, snappy, zstd).
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        libncurses-dev libgmp-dev libmpfr-dev liblzo2-dev libsnappy-dev libzstd-dev zlib1g-dev texinfo \
 && rm -rf /var/lib/apt/lists/*

# crash's Makefile wget()s the gdb tarball it embeds; pre-fetch the pinned one so build.sh runs offline.
ARG GDB_VER=16.2
ARG GDB_SHA256=bdc1da4a033280ac752e7d34b0418efaa45bed093235cb88e62ea961752a37f8
RUN d=/opt/toolchains/deps/gdb-${GDB_VER} && mkdir -p "$d/src" \
 && curl -fsSL -o "$d/src/gdb-${GDB_VER}.tar.gz" https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VER}.tar.gz \
 && echo "${GDB_SHA256}  $d/src/gdb-${GDB_VER}.tar.gz" | sha256sum -c - \
 && chmod -R a+rX "$d"

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Optional compile-cache pre-fill (SPEC §6.2 item 18); falls back to the plain build on older bases.
RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem

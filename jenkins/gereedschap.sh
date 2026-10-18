#!/usr/bin/env bash
# Installeert de tools van migratie-tools in één map, zonder Docker en zonder root, met
# vaste versies: cruft (in een Python-venv), multi-gitter en jq. Wat er al staat in de
# juiste versie, wordt niet opnieuw gedownload. Downloads worden gecontroleerd met de
# SHA-256-hashes hieronder, ook als ze via een mirror komen.
#
# Gebruik: jenkins/gereedschap.sh [<map>]      (standaard .tools)
# Daarna:  export PATH="<map>/bin:<map>/venv/bin:$PATH" CRUFT_PYTHON="<map>/venv/bin/python"
#
# Achter een afgeschermd netwerk (bv. via Nexus):
#   PIP_INDEX_URL       PyPI-proxy; pip leest deze variabele zelf
#   MULTI_GITTER_BASIS  map met de multi-gitter-downloads
#                       (standaard https://github.com/lindell/multi-gitter/releases/download)
#   JQ_BASIS            map met de jq-downloads
#                       (standaard https://github.com/jqlang/jq/releases/download)
# Nodig op de agent: bash, curl, tar, python3 met venv (Debian/Ubuntu: python3-venv).
set -euo pipefail

MAP="${1:-.tools}"
CRUFT_VERSIE=2.16.0
MULTI_GITTER_VERSIE=0.63.1
JQ_VERSIE=1.8.1
MULTI_GITTER_BASIS="${MULTI_GITTER_BASIS:-https://github.com/lindell/multi-gitter/releases/download}"
JQ_BASIS="${JQ_BASIS:-https://github.com/jqlang/jq/releases/download}"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    mg="multi-gitter_${MULTI_GITTER_VERSIE}_Linux_x86_64.tar.gz"
    mg_sha=94711a96c75975be9cfd9f3bd1d94a371b85716ac40be35f50b7b4cd271caf8d
    jq="jq-linux-amd64"; jq_sha=020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d ;;
  Linux-aarch64|Linux-arm64)
    mg="multi-gitter_${MULTI_GITTER_VERSIE}_Linux_ARM64.tar.gz"
    mg_sha=f4afde8bf0ab46a433901615e579f3c139ee0347162d615399d4e805e622c1ea
    jq="jq-linux-arm64"; jq_sha=6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4 ;;
  Darwin-arm64)
    mg="multi-gitter_${MULTI_GITTER_VERSIE}_Darwin_ARM64.tar.gz"
    mg_sha=df3ea56fe2fb5684a4634e00de3c69082a64b09fd68a7cf1c4169ebab92de49b
    jq="jq-macos-arm64"; jq_sha=a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603 ;;
  *) echo "platform $(uname -s)-$(uname -m) wordt niet ondersteund" >&2; exit 1 ;;
esac

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

download() {  # <url> <doel> <sha256>
  curl -fsSL --retry 3 -o "$2" "$1"
  if [ "$(sha256 "$2")" != "$3" ]; then
    echo "controle mislukt voor $1 (SHA-256 klopt niet)" >&2
    rm -f "$2"
    exit 1
  fi
}

mkdir -p "$MAP/bin"
MAP="$(cd "$MAP" && pwd)"

# multi-gitter
if [ "$("$MAP/bin/multi-gitter" version 2>/dev/null | sed -n 's/^multi-gitter version: //p')" != "$MULTI_GITTER_VERSIE" ]; then
  echo ">> multi-gitter $MULTI_GITTER_VERSIE"
  tmp="$(mktemp -d)"
  download "$MULTI_GITTER_BASIS/v$MULTI_GITTER_VERSIE/$mg" "$tmp/mg.tar.gz" "$mg_sha"
  tar -xzf "$tmp/mg.tar.gz" -C "$tmp" multi-gitter
  mv "$tmp/multi-gitter" "$MAP/bin/multi-gitter"
  rm -rf "$tmp"
fi

# jq
if [ "$("$MAP/bin/jq" --version 2>/dev/null)" != "jq-$JQ_VERSIE" ]; then
  echo ">> jq $JQ_VERSIE"
  download "$JQ_BASIS/jq-$JQ_VERSIE/$jq" "$MAP/bin/jq" "$jq_sha"
  chmod +x "$MAP/bin/jq"
fi

# cruft, in een eigen venv (de versie is vastgepind, zie de README)
if [ "$("$MAP/venv/bin/python" -c 'import importlib.metadata as m; print(m.version("cruft"))' 2>/dev/null)" != "$CRUFT_VERSIE" ]; then
  echo ">> cruft $CRUFT_VERSIE"
  rm -rf "$MAP/venv"
  python3 -m venv "$MAP/venv" \
    || { echo "python3 -m venv werkt niet (op Debian/Ubuntu: installeer python3-venv)" >&2; exit 1; }
  "$MAP/venv/bin/pip" install --quiet --disable-pip-version-check "cruft==$CRUFT_VERSIE"
fi

echo "gereedschap klaar in $MAP: multi-gitter $MULTI_GITTER_VERSIE, jq $JQ_VERSIE, cruft $CRUFT_VERSIE"

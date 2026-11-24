#!/usr/bin/env bash
# Assembles the exact source ProTech Support is built from: upstream RustDesk at the commit recorded in BASE.txt (plus its hbb_common
# submodule at the recorded commit), then ProTech's patches on top. Nothing else is changed.
#
#   scripts/assemble-source.sh <destination-dir> [--mac]
#
# Windows apps are built from patches/main/0001-0003 and patches/hbb_common/*. The macOS app additionally applies patches/main/0004
# (--mac): ProTech names, its own bundle id, no "install the service" card. After 0001-0003 the result is checked against the git tree
# hashes recorded in BASE.txt, so anyone can prove that the source they got is the source we built from.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:?usage: assemble-source.sh <destination-dir> [--mac]}"
MAC=0; [ "${2:-}" = "--mac" ] && MAC=1

field() { sed -n "s/^$1[[:space:]]*:[[:space:]]*//p" "$HERE/BASE.txt" | head -1 | awk '{print $1}'; }
UPSTREAM="$(field 'upstream repo')"; MAIN_BASE="$(field 'main base commit')"; HBB_BASE="$(field 'hbb_common base')"
HBB_REPO="$(field 'hbb_common repo')"; MAIN_TREE="$(field 'main tree')"; HBB_TREE="$(field 'hbb_common tree')"
for v in UPSTREAM MAIN_BASE HBB_BASE HBB_REPO MAIN_TREE HBB_TREE; do [ -n "${!v}" ] || { echo "BASE.txt: missing $v" >&2; exit 1; }; done

# git needs an identity to apply patches (git am); it is only used for the local commits, never published
export GIT_AUTHOR_NAME="ProTech Build" GIT_AUTHOR_EMAIL="build@localhost" GIT_COMMITTER_NAME="ProTech Build" GIT_COMMITTER_EMAIL="build@localhost"
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=advice.detachedHead GIT_CONFIG_VALUE_1=false

[ ! -e "$DEST" ] || [ -z "$(ls -A "$DEST" 2>/dev/null)" ] || { echo "destination $DEST exists and is not empty" >&2; exit 1; }
mkdir -p "$DEST"; cd "$DEST"

echo "== upstream $UPSTREAM @ $MAIN_BASE"
git init -q .
git remote add origin "$UPSTREAM"
git fetch -q --depth 1 origin "$MAIN_BASE"
git checkout -q FETCH_HEAD
[ "$(git rev-parse HEAD)" = "$MAIN_BASE" ] || { echo "fetched $(git rev-parse HEAD), expected $MAIN_BASE" >&2; exit 1; }

echo "== hbb_common submodule @ $HBB_BASE"
[ "$(git ls-tree HEAD libs/hbb_common | awk '{print $3}')" = "$HBB_BASE" ] || { echo "the submodule pin in upstream is not $HBB_BASE" >&2; exit 1; }
git submodule init -q libs/hbb_common
git config submodule.libs/hbb_common.url "$HBB_REPO"
git submodule update -q --depth 1 libs/hbb_common
[ "$(git -C libs/hbb_common rev-parse HEAD)" = "$HBB_BASE" ] || { echo "hbb_common is at the wrong commit" >&2; exit 1; }

echo "== ProTech patches: hbb_common"
git -C libs/hbb_common am -q --committer-date-is-author-date "$HERE"/patches/hbb_common/*.patch
[ "$(git -C libs/hbb_common rev-parse 'HEAD^{tree}')" = "$HBB_TREE" ] || { echo "hbb_common tree differs from BASE.txt" >&2; exit 1; }
echo "   hbb_common tree $HBB_TREE: matches BASE.txt"

echo "== ProTech patches: main (0001-0003)"
git am -q --committer-date-is-author-date "$HERE"/patches/main/000[123]-*.patch
[ "$(git rev-parse 'HEAD^{tree}')" = "$MAIN_TREE" ] || { echo "main tree differs from BASE.txt" >&2; exit 1; }
echo "   main tree $MAIN_TREE: matches BASE.txt"

if [ "$MAC" = 1 ]; then
  echo "== ProTech patches: macOS (0004)"
  git am -q --committer-date-is-author-date "$HERE"/patches/main/0004-*.patch
fi
echo "== source ready in $DEST ($(git log --oneline | wc -l | tr -d ' ') commit(s) in the shallow clone, $(git status --short | wc -l | tr -d ' ') uncommitted)"

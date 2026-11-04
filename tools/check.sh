#!/usr/bin/env bash
# Local checks of the recipes: run them before every push (there is no hosted CI).
#   tools/check.sh [--since REF | --all] [pkg...]
#   tools/check.sh --quick
# ShellCheck of the tools and every recipe, tools/lint.sh of every recipe, then the links and sha256
# (tools/lint.sh --fetch) of the recipes changed since REF (default: the merge base with origin/main,
# uncommitted changes included) or of the named ones. --all downloads and verifies every source;
# --quick: no downloads (tools/hooks/pre-push).
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=changed SINCE='' PKGS=()
while (($#)); do
	case $1 in
		--quick) MODE=quick && shift ;;
		--all) MODE=all && shift ;;
		--since) SINCE=$2 && shift 2 ;;
		-h | --help) sed -n '2,8p' "$0" | cut -c3- && exit 0 ;;
		-*) echo "tools/check.sh: unknown option: $1" >&2 && exit 2 ;;
		*) PKGS+=("$1") && shift ;;
	esac
done
step() { printf '\n\033[1;36m==>\033[0m %s\n' "$*"; }

step shellcheck
shellcheck -x tools/*.sh tools/hooks/pre-push
shellcheck -s bash packages/*/recipe
step "lint every recipe"
tools/lint.sh
[[ $MODE == quick ]] && exit 0

if [[ $MODE == all ]]; then
	mapfile -t PKGS < <(ls packages)
elif ((${#PKGS[@]} == 0)); then
	base=${SINCE:-$(git merge-base HEAD origin/main 2>/dev/null || true)}
	if [[ -z $base ]]; then
		echo "tools/check.sh: no origin/main to compare with: --since REF, --all or package names" >&2
		exit 2
	fi
	mapfile -t PKGS < <(git diff --name-only "$base" -- packages | cut -d/ -f2 | sort -u)
fi
have=()
for p in "${PKGS[@]}"; do
	if [[ -f packages/$p/recipe ]]; then have+=("$p"); fi
done
if ((${#have[@]} == 0)); then
	echo "no changed recipe: nothing to download"
	exit 0
fi
step "links and sha256: ${have[*]}"
tools/lint.sh --fetch "${have[@]}"

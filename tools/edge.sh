#!/usr/bin/env bash
# The edge channel of rolling release+++: upstream releases every day. Run it from cron or a timer:
#   23 5 * * *  cd ~/CleanLinux-Recipes && tools/edge.sh
# In a temporary worktree: edge = origin/edge (a new branch from origin/main the first time) with
# origin/main merged in; tools/updates.sh --write bumps the recipes, tools/lint.sh and tools/lint.sh
# --fetch verify the bumped ones, the commit is pushed to edge. With GH_TOKEN (a token with the repo
# scope) a pull request edge -> main is opened when edge is ahead of main and none is open yet.
#   tools/edge.sh [--dry-run]     --dry-run: everything but the push and the pull request
# REMOTE=origin by default. GITHUB_TOKEN (or GH_TOKEN) also raises the GitHub API limits of updates.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
DRY=0
case ${1:-} in
	--dry-run) DRY=1 ;;
	-h | --help) sed -n '2,9p' "$0" | cut -c3- && exit 0 ;;
	'') ;;
	*) echo "tools/edge.sh: unknown argument: $1" >&2 && exit 2 ;;
esac
REMOTE=${REMOTE:-origin}
export GITHUB_TOKEN=${GITHUB_TOKEN:-${GH_TOKEN:-}}
top=$PWD
wt=$(mktemp -d "${TMPDIR:-/tmp}/cleanlinux-edge.XXXXXX")
log=$wt.updates
cleanup() {
	git -C "$top" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
	rm -f "$log"
}
trap cleanup EXIT

git fetch -q "$REMOTE" main
if git ls-remote --exit-code --heads "$REMOTE" edge >/dev/null; then
	git fetch -q "$REMOTE" edge
	git worktree add -q --detach "$wt" "$REMOTE/edge"
	git -C "$wt" merge -q --no-edit "$REMOTE/main"
else
	git worktree add -q --detach "$wt" "$REMOTE/main"
fi
cd "$wt"

status=0
tools/updates.sh --write | tee "$log" || status=$?
if ((status != 0)); then echo "edge: some upstream versions could not be checked" >&2; fi
mapfile -t pkgs < <(git diff --name-only -- packages | cut -d/ -f2 | sort -u)
if ((${#pkgs[@]})); then
	tools/lint.sh "${pkgs[@]}"
	tools/lint.sh --fetch "${pkgs[@]}"
	git commit -qam "Upstream updates $(date -u +%F)" -m "$(cat "$log")"
	echo "edge: bumped ${pkgs[*]}"
else
	echo "edge: everything is up to date"
fi
if ((DRY)); then
	echo "edge: --dry-run, nothing pushed ($(git rev-list --count "$REMOTE/main..HEAD") commits ahead of main)"
	exit 0
fi
git push -q "$REMOTE" HEAD:refs/heads/edge

ahead=$(git rev-list --count "$REMOTE/main..HEAD")
if [[ -z ${GH_TOKEN:-} ]] || ((ahead == 0)); then exit 0; fi
url=$(git remote get-url "$REMOTE")
repo=${url#*github.com[:/]}
repo=${repo%.git}
api=https://api.github.com/repos/$repo
auth=(-H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json")
open=$(curl -fsS "${auth[@]}" "$api/pulls?state=open&base=main&head=${repo%%/*}:edge" | grep -c '"number":' || true)
if ((open == 0)); then
	curl -fsS "${auth[@]}" -X POST "$api/pulls" -d @- >/dev/null <<JSON
{"title": "Upstream updates", "head": "edge", "base": "main",
 "body": "Bumped by tools/updates.sh, links and sha256 verified by tools/lint.sh --fetch (tools/edge.sh). Use CHANNEL=edge in burn.conf to follow them right away."}
JSON
	echo "edge: opened a pull request edge -> main"
fi

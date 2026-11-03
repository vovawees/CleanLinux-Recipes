#!/usr/bin/env bash
# shellcheck disable=SC2016 # '${var}' strings are expanded inside the recipe environment
# Upstream release watcher for rolling release+++: which recipes are behind upstream?
#   tools/updates.sh [-v] [--write] [pkg...]
# Prints "pkg  old -> new" for every recipe with a newer upstream release.
#   -v        also print the recipes that are up to date
#   --write   bump the version, reset release=1, download the new sources, rewrite sha256=()
# The upstream is inferred from the recipe's sources, no extra metadata needed:
#   gnu://dir/...                   directory listings on the GNU mirror
#   kernel://kernel/...             latest stable kernel (kernel.org/releases.json)
#   kernel://<dir>/vX.Y/...         kernel.org directory listings (util-linux, ...)
#   https://github.com/<owner>/<repo>/...   latest GitHub release (GITHUB_TOKEN raises API limits)
#   any other https:// URL          the directory listing next to the file
# Recipes with _basever + _patches=({001..NNN}) (bash, readline) also follow the official patch level.
set -euo pipefail
shopt -s nullglob inherit_errexit
cd "$(dirname "$0")/.."
GNU_MIRROR=${GNU_MIRROR:-https://ftpmirror.gnu.org/gnu}
KERNEL_MIRROR=${KERNEL_MIRROR:-https://cdn.kernel.org/pub/linux}
CACHE=${UPDATES_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cleanlinux-updates}
MARK=@@V@@
WRITE=0 VERBOSE=0
while [[ ${1:-} == -* ]]; do
	case $1 in
		--write) WRITE=1 ;;
		-v) VERBOSE=1 ;;
		*) echo "usage: tools/updates.sh [-v] [--write] [pkg...]" >&2 && exit 2 ;;
	esac
	shift
done
pkgs=("$@")
if ((${#pkgs[@]} == 0)); then
	for r in packages/*/recipe; do r=${r%/recipe} && pkgs+=("${r#packages/}"); done
fi

warn() { printf 'warning: %s\n' "$*" >&2; }
get() {
	local -a auth=()
	if [[ $1 == https://api.github.com/* && -n ${GITHUB_TOKEN:-} ]]; then
		auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
	fi
	curl -fsSL --retry 3 --connect-timeout 20 "${auth[@]}" "$1"
}
url_expand() {
	case $1 in
		gnu://*) printf '%s\n' "$GNU_MIRROR/${1#gnu://}" ;;
		kernel://*) printf '%s\n' "$KERNEL_MIRROR/${1#kernel://}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}
# newest plain release (digits and dots only) from stdin
newest() { grep -E '^[0-9]+(\.[0-9]+)*$' | sort -uV | tail -n1; }
# shellcheck disable=SC2001 # a bracket expression, not a fixed string
ere_quote() { sed 's/[].[\*^$+?(){}|]/\\&/g' <<<"$1"; }
# versions in a directory listing: entries PREFIX<version>SUFFIX
listing() { # URL PREFIX SUFFIX
	{ get "$1" || true; } | grep -oE "$(ere_quote "$2")[0-9]+(\\.[0-9]+)*$(ere_quote "$3")" |
		awk -v p="${#2}" -v s="${#3}" '{ print substr($0, p + 1, length($0) - p - s) }' | sort -uV || true
}

# recipe_eval PKG [VAR=VALUE...] -- EXPR...: evaluate strings in the recipe's environment
recipe_eval() (
	set +eu
	local pkg=$1 e
	shift
	name='' version='' release=1 source=() sha256=() patches=() CARCH=x86_64 CHOST=x86_64-cleanlinux-linux-gnu
	# shellcheck source=/dev/null
	. "packages/$pkg/recipe" >/dev/null 2>&1
	while (($#)) && [[ $1 != -- ]]; do printf -v "${1%%=*}" '%s' "${1#*=}" && shift; done
	shift
	for e; do eval "printf '%s\n' \"$e\""; done
)

# raw URL strings of a recipe, as written (unexpanded)
raw_urls() { grep -oE '(gnu|kernel)://[^ "'"'"')]+|https://[^ "'"'"')]+' "packages/$1/recipe" | grep -F '$' || true; }

# latest PKG VAR RAW: newest upstream value of VAR for the source written as RAW
latest() {
	local pkg=$1 var=$2 raw=$3 u path dir file pre suf c d v
	u=$(recipe_eval "$pkg" "$var=$MARK" -- "$raw")
	u=${u#*::}
	case $u in
		kernel://kernel/*)
			get https://www.kernel.org/releases.json | tr -d ' \n' |
				sed -nE 's/.*"latest_stable":\{"version":"([0-9.]+)".*/\1/p'
			;;
		https://github.com/*/*)
			local repo tag
			repo=$(cut -d/ -f4,5 <<<"$u")
			tag=$(get "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null |
				sed -nE 's/^ *"tag_name": *"([^"]+)".*/\1/p' | head -n1) || true
			v=$(sed -E 's/^[^0-9]*//' <<<"$tag")
			if [[ ! $v =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
				v=$(get "https://api.github.com/repos/$repo/tags?per_page=100" |
					sed -nE 's/^ *"name": *"[^0-9"]*([0-9][^"]*)".*/\1/p' | newest)
			fi
			printf '%s\n' "$v"
			;;
		*://*)
			path=$(url_expand "$u")
			file=${path##*/} dir=${path%/*}
			[[ $file == *"$MARK"* ]] || return 0
			pre=${file%%"$MARK"*} suf=${file#*"$MARK"}
			if [[ $dir == *"$MARK"* ]]; then
				# version in a directory too (gcc-X/, util-linux/vX.Y/): newest directory with a release
				local top=${dir%%"$MARK"*} rest=${dir#*"$MARK"}
				local dpre=${top##*/}
				top=${top%/*}
				for c in $(listing "$top/" "$dpre" "${rest%%/*}/" | sort -rV | head -n 3); do
					d=$top/$dpre$c${rest}
					v=$(listing "$d/" "$pre" "$suf" | newest)
					if [[ -n $v ]]; then printf '%s\n' "$v" && return 0; fi
				done
			else
				listing "$dir/" "$pre" "$suf" | newest
			fi
			;;
	esac
}

# patchlevel PKG BASEVER: newest official patch for _basever (bash, readline), the GNU layout
#   PKG/PKG-BASEVER-patches/PKG<BASEVER without dots>-NNN
patchlevel() {
	listing "$GNU_MIRROR/$1/$1-$2-patches/" "$1${2//./}-" "" | sed 's/^0*//; s/^$/0/' | newest
}

set_patches() { # PKG N: _patches=({001..N}), _patches=() for none
	local f=packages/$1/recipe r='()'
	if (($2 > 0)); then r=$(printf '({001..%03d})' "$2"); fi
	sed -i -E "s/^_patches=\\([^)]*\\)/_patches=$r/" "$f"
}

set_var() { # PKG VAR NEW
	local f=packages/$1/recipe
	sed -i -E "s/(^|[[:space:]])$2=[^[:space:]]+/\\1$2=$3/" "$f"
}

rewrite_sha256() { # PKG
	local pkg=$1 f=packages/$1/recipe s file url sum
	local -a srcs=() sums=()
	mapfile -t srcs < <(recipe_eval "$pkg" -- '${source[@]}' | tr ' ' '\n' | sed '/^$/d')
	mkdir -p "$CACHE"
	for s in "${srcs[@]}"; do
		if [[ $s == *::* ]]; then file=${s%%::*} s=${s#*::}; else file=${s##*/}; fi
		if [[ $s != *://* ]]; then
			sums+=("$(sha256sum "packages/$pkg/$s" | cut -d' ' -f1)")
			continue
		fi
		url=$(url_expand "$s")
		if [[ ! -s $CACHE/$file ]]; then
			curl -fsSL --retry 3 --connect-timeout 20 -o "$CACHE/$file.part" "$url" ||
				{ [[ $s == gnu://* ]] && curl -fsSL --retry 3 -o "$CACHE/$file.part" "https://ftp.gnu.org/gnu/${s#gnu://}"; } ||
				{ warn "$pkg: download failed: $url" && return 1; }
			mv -f "$CACHE/$file.part" "$CACHE/$file"
		fi
		sums+=("$(sha256sum "$CACHE/$file" | cut -d' ' -f1)")
	done
	awk -v new="$(if ((${#sums[@]} == 1)); then printf 'sha256=(%s)' "${sums[0]}"; else
		printf 'sha256=(\n'; printf '\t%s\n' "${sums[@]}"; printf ')'; fi)" '
		skip && /\)/ { skip = 0; next }
		skip { next }
		/^sha256=\(/ { print new; if ($0 !~ /\)/) skip = 1; next }
		{ print }' "$f" >"$f.new"
	mv -f "$f.new" "$f"
}

found=0 errors=0
for pkg in "${pkgs[@]}"; do
	[[ -f packages/$pkg/recipe ]] || { warn "$pkg: no such recipe" && errors=1 && continue; }
	changes=()
	declare -A seen=()
	while IFS= read -r raw; do
		[[ $raw == *-patches/* ]] && continue # the official patches: see _patches below
		# the variable that carries the version: first $var / ${var...} in the file name
		var=$(sed -E 's/.*:://; s|.*/||' <<<"$raw" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | head -n1 | tr -d '${')
		[[ -n $var && -z ${seen[$var]:-} ]] || continue
		seen[$var]=1
		cur=$(recipe_eval "$pkg" -- "\${$var}")
		new=$(latest "$pkg" "$var" "$raw") || new=''
		if [[ -z $new ]]; then
			warn "$pkg: cannot find the upstream version of \$$var"
			errors=1
			continue
		fi
		if [[ $(printf '%s\n%s\n' "$cur" "$new" | sort -V | tail -n1) != "$cur" ]]; then
			changes+=("$var|$cur|$new")
		elif ((VERBOSE)); then
			printf '%-14s %s=%s is the latest\n' "$pkg" "$var" "$cur"
		fi
	done < <(raw_urls "$pkg")
	unset seen
	if grep -q '^_patches=' "packages/$pkg/recipe"; then
		base=$(recipe_eval "$pkg" -- '${_basever}')
		for c in "${changes[@]}"; do [[ $c == _basever\|* ]] && base=${c##*|}; done
		cur=$(recipe_eval "$pkg" -- '${#_patches[@]}')
		new=$(patchlevel "$pkg" "$base") || new=''
		if [[ -z $new && $base != "$(recipe_eval "$pkg" -- '${_basever}')" ]]; then
			new=0 # a new release without patches yet
		elif [[ -z $new ]]; then
			warn "$pkg: cannot list the upstream patches of $base" && errors=1
			new=$cur
		fi
		if [[ $new != "$cur" ]]; then
			changes+=("_patches|$cur|$new")
		elif ((VERBOSE)); then
			printf '%-14s %s official patches, the latest\n' "$pkg" "$cur"
		fi
	fi
	((${#changes[@]})) || continue
	found=1
	old=$(recipe_eval "$pkg" -- '${version}')
	if ((WRITE)); then
		for c in "${changes[@]}"; do
			IFS='|' read -r var _ new <<<"$c"
			if [[ $var == _patches ]]; then set_patches "$pkg" "$new"; else set_var "$pkg" "$var" "$new"; fi
		done
		set_var "$pkg" release 1
		rewrite_sha256 "$pkg" || { errors=1 && continue; }
	fi
	new=$(recipe_eval "$pkg" -- '${version}')
	detail=''
	for c in "${changes[@]}"; do
		IFS='|' read -r var cur nv <<<"$c"
		[[ $var == version ]] || detail+=" $var $cur->$nv"
	done
	if ((WRITE)); then
		printf '%-14s %s -> %s%s\n' "$pkg" "$old" "$new" "${detail:+  (${detail# })}"
	else
		# without --write the version expression is not re-evaluated: show the changes
		printf '%-14s %s%s\n' "$pkg" "$old" "$(for c in "${changes[@]}"; do IFS='|' read -r var cur nv <<<"$c"; printf '  %s: %s -> %s' "$var" "$cur" "$nv"; done)"
	fi
done
((found)) || echo "all recipes are up to date"
exit "$errors"

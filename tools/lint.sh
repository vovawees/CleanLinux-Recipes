#!/usr/bin/env bash
# Self-contained recipe checker (no burn needed), used by CI.
#   tools/lint.sh [--fetch] [pkg...]
# --fetch also downloads the remote sources and verifies their sha256.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."
GNU_MIRROR=${GNU_MIRROR:-https://ftpmirror.gnu.org/gnu}
KERNEL_MIRROR=${KERNEL_MIRROR:-https://cdn.kernel.org/pub/linux}
BUILD_TYPES=(autotools meson cmake make cargo python custom meta)
OPTIONS=('!lto' '!strip' '!hardening' '!prune' '!linker' staticlibs emptydirs o3)
# layers of the base (see README): spin and user overlays use 'extra', not this repository
CATEGORIES=(core devel meta kernel firmware drivers platform)
FETCH=0
if [[ ${1:-} == --fetch ]]; then FETCH=1 && shift; fi
pkgs=("$@")
if ((${#pkgs[@]} == 0)); then
	for r in packages/*/recipe; do r=${r%/recipe} && pkgs+=("${r#packages/}"); done
fi
in_list() {
	local n=$1 x
	shift
	for x; do [[ $x == "$n" ]] && return 0; done
	return 1
}
url_expand() {
	case $1 in
		gnu://*) printf '%s\n' "$GNU_MIRROR/${1#gnu://}" ;;
		kernel://*) printf '%s\n' "$KERNEL_MIRROR/${1#kernel://}" ;;
		*) printf '%s\n' "$1" ;;
	esac
}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# split packages of every recipe (split=(...)): valid dependencies like recipes
declare -A SPLIT_OF=()
for r in packages/*/recipe; do
	while IFS= read -r s; do
		[[ -n $s ]] && SPLIT_OF[$s]=${r#packages/} && SPLIT_OF[$s]=${SPLIT_OF[$s]%/recipe}
	done < <(split=() CARCH=x86_64 CHOST=x86_64-cleanlinux-linux-gnu bash -c '. "$1" >/dev/null 2>&1; printf "%s\n" "${split[@]}"' _ "$r")
done

# check_one PKG: prints problems, one per line
check_one() (
	local dir=packages/$1 s f p i url file sum
	[[ -f $dir/recipe ]] || {
		echo "$1: no recipe"
		exit 0
	}
	bash -n "$dir/recipe" || {
		echo "$1: syntax error"
		exit 0
	}
	name='' version='' release=1 summary='' homepage='' category='' build_type=autotools
	license=() source=() sha256=() depends=() makedepends=() features=() patches=() options=() split=()
	CARCH=x86_64 CHOST=x86_64-cleanlinux-linux-gnu
	# shellcheck source=/dev/null
	. "$dir/recipe"
	[[ $name == "$1" ]] || echo "$1: name '$name' does not match the directory"
	[[ $version =~ ^[A-Za-z0-9._+~]+$ ]] || echo "$1: bad version '$version'"
	[[ $release =~ ^[1-9][0-9]*$ ]] || echo "$1: release must be a positive integer"
	[[ -n $summary ]] || echo "$1: summary is empty"
	((${#license[@]})) || echo "$1: license is empty"
	[[ $homepage == http*://* ]] || echo "$1: homepage must be a URL"
	if [[ $category == extra ]]; then
		echo "$1: category 'extra' is for spin and user overlays, not for the base repository"
	elif ! in_list "$category" "${CATEGORIES[@]}"; then
		echo "$1: category must be one of: ${CATEGORIES[*]} (got '$category')"
	fi
	in_list "$build_type" "${BUILD_TYPES[@]}" || echo "$1: unknown build_type '$build_type'"
	if [[ $build_type != meta ]] && ((${#source[@]} == 0)); then echo "$1: no sources"; fi
	((${#source[@]} == ${#sha256[@]})) || echo "$1: ${#source[@]} sources but ${#sha256[@]} sha256 sums"
	local -a names=() known=()
	for i in "${!source[@]}"; do
		s=${source[$i]} sum=${sha256[$i]:-}
		if [[ $s == *::* ]]; then file=${s%%::*} s=${s#*::}; else file=${s##*/}; fi
		names+=("$file")
		[[ $sum =~ ^[0-9a-f]{64}$ || $sum == SKIP ]] || echo "$1: bad sha256 for $file"
		if [[ $s != *://* ]]; then
			[[ -f $dir/$s ]] || echo "$1: local source '$s' is missing"
			[[ $sum == SKIP || ! -f $dir/$s || $(sha256sum "$dir/$s" | cut -d' ' -f1) == "$sum" ]] ||
				echo "$1: sha256 mismatch for local file $s"
			continue
		fi
		case $s in https://* | gnu://* | kernel://*) ;; *) echo "$1: insecure URL $s (use https)" ;; esac
		[[ $sum != SKIP ]] || echo "$1: remote source $file needs a real sha256"
		if ((FETCH)) && [[ $sum != SKIP ]]; then
			url=$(url_expand "$s")
			if ! curl -fsSL --retry 3 --connect-timeout 20 -o "$tmp/$file" "$url"; then
				if [[ $s == gnu://* ]] && curl -fsSL --retry 3 -o "$tmp/$file" "https://ftp.gnu.org/gnu/${s#gnu://}"; then
					:
				else
					echo "$1: download failed: $url"
					continue
				fi
			fi
			[[ $(sha256sum "$tmp/$file" | cut -d' ' -f1) == "$sum" ]] || echo "$1: sha256 mismatch for $url"
			rm -f "$tmp/$file"
		fi
	done
	for p in "${patches[@]}"; do
		[[ -f $dir/$p || -f $dir/patches/$p ]] || in_list "$p" "${names[@]}" || echo "$1: patch '$p' is missing"
	done
	for f in "${features[@]}"; do
		[[ $f =~ ^[+-]?[a-z0-9][a-z0-9_-]*$ ]] || echo "$1: bad feature '$f'"
		known+=("${f#[+-]}")
	done
	# split packages: own name, files_KEY and summary_KEY (KEY: the name, '_' for other characters)
	local -a deps=("${depends[@]}" "${makedepends[@]}")
	local key n
	for s in "${split[@]}"; do
		[[ $s =~ ^[a-z0-9][a-z0-9+._-]*$ ]] || echo "$1: bad split name '$s'"
		[[ $s != "$name" ]] || echo "$1: split '$s' is the name of the recipe"
		[[ ! -f packages/$s/recipe ]] || echo "$1: split '$s' is also a recipe"
		key=${s//[^A-Za-z0-9_]/_}
		local -n files_ref="files_$key" summary_ref="summary_$key" depends_ref="depends_$key"
		n=0
		if declare -p "files_$key" >/dev/null 2>&1; then n=${#files_ref[@]}; fi
		((n)) || echo "$1: split '$s' has no files_$key"
		[[ -n ${summary_ref:-} ]] || echo "$1: split '$s' has no summary_$key"
		if declare -p "depends_$key" >/dev/null 2>&1; then deps+=("${depends_ref[@]}"); fi
		unset -n files_ref summary_ref depends_ref
	done
	for p in "${deps[@]}"; do
		[[ -f packages/${p%%:*}/recipe || -n ${SPLIT_OF[${p%%:*}]:-} ]] || echo "$1: unknown dependency '${p%%:*}'"
		if [[ $p == *:* ]]; then
			f=${p#*:}
			in_list "${f#!}" "${known[@]}" || echo "$1: dependency '$p' uses undeclared feature '${f#!}'"
		fi
	done
	for f in "${options[@]}"; do in_list "$f" "${OPTIONS[@]}" || echo "$1: unknown option '$f'"; done
	while IFS= read -r -d '' f; do
		if (($(stat -c %s "$f") > 262144)); then
			echo "$1: file too large for a recipe repository: ${f#"$dir"/}"
		elif [[ -s $f ]] && ! grep -Iq . "$f"; then
			echo "$1: binary file not allowed: ${f#"$dir"/}"
		fi
	done < <(find "$dir" -type f -print0)
)

problems=0
for p in "${pkgs[@]}"; do
	out=$(check_one "$p" 2>&1) || out="$p: recipe failed to load"$'\n'"$out"
	if [[ -n $out ]]; then
		printf '%s\n' "$out"
		problems=$((problems + $(wc -l <<<"$out")))
	fi
done
if ((problems)); then
	echo "lint: $problems problem(s)"
	exit 1
fi
echo "lint: ${#pkgs[@]} recipe(s) OK$( ((FETCH)) && echo ', sources verified')"

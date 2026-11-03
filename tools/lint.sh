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
OPTIONS=('!lto' '!strip' '!hardening' '!prune' staticlibs emptydirs)
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
	name='' version='' release=1 summary='' homepage='' build_type=autotools
	license=() source=() sha256=() depends=() makedepends=() features=() patches=() options=()
	CARCH=x86_64 CHOST=x86_64-cleanlinux-linux-gnu
	# shellcheck source=/dev/null
	. "$dir/recipe"
	[[ $name == "$1" ]] || echo "$1: name '$name' does not match the directory"
	[[ $version =~ ^[A-Za-z0-9._+~]+$ ]] || echo "$1: bad version '$version'"
	[[ $release =~ ^[1-9][0-9]*$ ]] || echo "$1: release must be a positive integer"
	[[ -n $summary ]] || echo "$1: summary is empty"
	((${#license[@]})) || echo "$1: license is empty"
	[[ $homepage == http*://* ]] || echo "$1: homepage must be a URL"
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
	for p in "${depends[@]}" "${makedepends[@]}"; do
		[[ -f packages/${p%%:*}/recipe ]] || echo "$1: unknown dependency '${p%%:*}'"
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

#!/usr/bin/env bash
# The package table of README.md from the recipes (name, category, version, build type, summary).
#   tools/readme.sh            print the table
#   tools/readme.sh --write    replace the table in README.md
#   tools/readme.sh --check    fail when README.md is behind the recipes (tools/check.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
row() ( # PKG: its row, from the recipe sourced the way tools/lint.sh does (the same defaults)
	name='' version='' summary='' category='' build_type=autotools
	# shellcheck disable=SC2034 # the recipes read them
	CARCH=x86_64 CHOST=x86_64-cleanlinux-linux-gnu
	# shellcheck source=/dev/null
	. "packages/$1/recipe"
	printf '| `%s` | %s | %s | %s | %s |\n' "$name" "$category" "$version" "$build_type" "$summary"
)
table() {
	printf '| Пакет | Категория | Версия | Сборка | Описание |\n|---|---|---|---|---|\n'
	local d
	for d in packages/*/; do
		d=${d%/}
		row "${d#packages/}"
	done
}
splice() { # README with its table replaced: from the header row to the last row
	awk -v table="$1" '
		/^\| Пакет \| Категория \|/ { print table; skip = 1; next }
		skip && /^\|/ { next }
		{ skip = 0; print }
	' README.md
}
case ${1:-} in
	'') table ;;
	--write)
		new=$(splice "$(table)")
		printf '%s\n' "$new" >README.md
		;;
	--check)
		if [[ $(splice "$(table)") != "$(cat README.md)" ]]; then
			echo "README.md: the package table is behind the recipes (tools/readme.sh --write)" >&2
			exit 1
		fi
		;;
	*) sed -n '2,5p' "$0" | cut -c3- && exit 2 ;;
esac

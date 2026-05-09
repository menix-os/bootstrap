#!/bin/sh
set -uex
# check if $1 is a valid build directory
[ -f "${1:-/dev/null}"/.jinx-parameters ] || exit 1

# find compile_commands.json
sourcedir="$2/$3"
until [ -z "$sourcedir" ] || [ -L "$sourcedir/compile_commands.json" ]; do
	sourcedir="${sourcedir%/*}"
done

# if not found, exit
[ -z "$sourcedir" ] && exit 2

cd "$1"

# run the lsp server
exec ../jinx/jinx run-in "$3" \
    sh -c \
    'set -x && cd ${source_dir} && \
    env HOME=${build_dir}/clangd_home \
        XDG_CACHE_HOME=${build_dir}/clangd_home/cache \
    clangd -background-index -header-insertion=never --path-mappings '$(dirname ${sourcedir})'=/base_dir/sources'

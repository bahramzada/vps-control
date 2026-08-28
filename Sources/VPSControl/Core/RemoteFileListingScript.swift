import Foundation

enum RemoteFileListingScript {
    static let maximumEntries = 500

    static let source = #"""
#!/usr/bin/env bash
set -u
export LC_ALL=C

emit_error() {
    printf 'VPSF/1\0error\0%s\0end\0' "$1"
    exit 0
}

hex_path="${1-}"
if [ -z "$hex_path" ]; then
    requested_path="$HOME"
else
    case "$hex_path" in
        *[!0-9a-f]* ) emit_error invalid_path ;;
    esac
    [ $(( ${#hex_path} % 2 )) -eq 0 ] || emit_error invalid_path
    [ ${#hex_path} -le 8192 ] || emit_error invalid_path

    requested_path=""
    for ((index=0; index<${#hex_path}; index+=2)); do
        pair="${hex_path:index:2}"
        [ "$pair" != "00" ] || emit_error invalid_path
        printf -v byte '%b' "\\x$pair"
        requested_path+="$byte"
    done
fi

case "$requested_path" in
    /* ) ;;
    * ) emit_error invalid_path ;;
esac

canonical_path="$(realpath -e -- "$requested_path" 2>/dev/null)" || emit_error not_found
[ -d "$canonical_path" ] || emit_error not_directory
[ -r "$canonical_path" ] && [ -x "$canonical_path" ] || emit_error permission_denied

printf 'VPSF/1\0path\0%s\0' "$canonical_path"

mapfile -d '' -t fields < <(
    find "$canonical_path" -mindepth 1 -maxdepth 1 \
        -printf 'entry\0%f\0%y\0%s\0%T@\0%M\0%u\0%g\0' \
        2>/dev/null | head -z -n 4008
)

entry_count=$(( ${#fields[@]} / 8 ))
visible_count=$entry_count
truncated=0
if [ "$visible_count" -gt 500 ]; then
    visible_count=500
    truncated=1
fi

field_count=$(( visible_count * 8 ))
for ((index=0; index<field_count; index++)); do
    printf '%s\0' "${fields[index]}"
done

printf 'truncated\0%s\0end\0' "$truncated"
"""#
}

import Foundation

enum RemoteDiagnosticsCollectorScript {
    static let maximumFailedUnits = 64
    static let maximumListeners = 128

    static let source = #"""
#!/usr/bin/env bash
set -u
export LC_ALL=C

clean() {
    local value="${1-}"
    value="${value//$'\t'/ }"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    printf '%s' "${value:0:200}"
}

os_id="unknown"
version_id="unknown"
pretty_name="Linux"
if [ -r /etc/os-release ]; then
    while IFS='=' read -r key value; do
        value="${value#\"}"
        value="${value%\"}"
        case "$key" in
            ID) os_id="$value" ;;
            VERSION_ID) version_id="$value" ;;
            PRETTY_NAME) pretty_name="$value" ;;
        esac
    done < /etc/os-release
fi

printf 'VPSD/1\n'
printf 'time\t%s\n' "$(date +%s)"
printf 'platform\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(clean "$os_id")" \
    "$(clean "$version_id")" \
    "$(clean "$pretty_name")" \
    "$(clean "$(hostname 2>/dev/null || true)")" \
    "$(clean "$(uname -r 2>/dev/null || true)")" \
    "$(clean "$(uname -m 2>/dev/null || true)")"

update_status="unavailable"
pending_updates="-"
security_updates="-"
update_cache_epoch="0"
update_cache=/var/lib/update-notifier/updates-available
if [ -r "$update_cache" ]; then
    update_status="invalid"
    pending=""
    security=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^([0-9]+)[[:space:]]+updates[[:space:]]+can[[:space:]]+be[[:space:]]+applied[[:space:]]+immediately ]]; then
            pending="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^([0-9]+)[[:space:]]+of[[:space:]]+these[[:space:]]+updates[[:space:]]+are[[:space:]]+standard[[:space:]]+security[[:space:]]+updates ]]; then
            security="${BASH_REMATCH[1]}"
        fi
    done < "$update_cache"
    update_cache_epoch="$(stat -c %Y "$update_cache" 2>/dev/null || printf 0)"
    if [ -n "$pending" ]; then
        update_status="available"
        pending_updates="$pending"
        security_updates="${security:-0}"
    fi
fi
printf 'updates\t%s\t%s\t%s\t%s\n' \
    "$update_status" "$pending_updates" "$security_updates" "$update_cache_epoch"

if [ -e /var/run/reboot-required ]; then
    printf 'reboot_required\t1\n'
else
    printf 'reboot_required\t0\n'
fi

failed_availability="unsupported"
failed_total=0
failed_records=()
if command -v systemctl >/dev/null 2>&1; then
    failed_availability="available"
    failed_output="$(systemctl --failed --no-legend --no-pager --plain 2>/dev/null || true)"
    while read -r unit _ active sub _; do
        [ -n "${unit-}" ] || continue
        failed_total=$((failed_total + 1))
        if [ "${#failed_records[@]}" -lt 64 ]; then
            failed_records+=("failed_unit"$'\t'"$(clean "$unit")"$'\t'"$(clean "$active")"$'\t'"$(clean "$sub")")
        fi
    done <<< "$failed_output"
fi
failed_truncated=0
[ "$failed_total" -le 64 ] || failed_truncated=1
printf 'failed_units\t%s\t%s\t%s\n' "$failed_availability" "$failed_total" "$failed_truncated"
if [ "${#failed_records[@]}" -gt 0 ]; then
    printf '%s\n' "${failed_records[@]}"
fi

listener_availability="unsupported"
listener_total=0
listener_records=()
if command -v ss >/dev/null 2>&1; then
    listener_availability="available"
    while read -r netid _ _ _ local_address _; do
        case "$netid" in
            tcp*) transport="tcp" ;;
            udp*) transport="udp" ;;
            *) continue ;;
        esac

        if [[ "$local_address" =~ ^\[(.*)\]:([0-9]+)$ ]]; then
            address="${BASH_REMATCH[1]}"
            port="${BASH_REMATCH[2]}"
        else
            address="${local_address%:*}"
            port="${local_address##*:}"
        fi
        [[ "$port" =~ ^[0-9]+$ ]] || continue
        [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || continue

        if [[ "$address" == *:* ]]; then
            family="v6"
        else
            family="v4"
        fi
        case "$address" in
            "*"|"0.0.0.0"|"::") scope="wildcard" ;;
            127.*|"::1") scope="loopback" ;;
            *) scope="specific" ;;
        esac

        listener_total=$((listener_total + 1))
        if [ "${#listener_records[@]}" -lt 128 ]; then
            listener_records+=("listener"$'\t'"$transport"$'\t'"$family"$'\t'"$scope"$'\t'"$(clean "$address")"$'\t'"$port")
        fi
    done < <(ss -H -lnut 2>/dev/null)
fi
listener_truncated=0
[ "$listener_total" -le 128 ] || listener_truncated=1
printf 'listeners\t%s\t%s\t%s\n' "$listener_availability" "$listener_total" "$listener_truncated"
if [ "${#listener_records[@]}" -gt 0 ]; then
    printf '%s\n' "${listener_records[@]}"
fi

printf 'end\n'
"""#
}

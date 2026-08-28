import Foundation

enum RemoteMetricsCollectorScript {
    static let source = #"""
#!/usr/bin/env bash
set -u
export LC_ALL=C

printf 'VPSC/1\n'
printf 'boot\t%s\n' "$(tr -d '\n' </proc/sys/kernel/random/boot_id 2>/dev/null || true)"
printf 'time\t%s\n' "$(date +%s)"

if read -r _ cpu_user cpu_nice cpu_system cpu_idle cpu_iowait cpu_irq cpu_softirq cpu_steal _ </proc/stat; then
    printf 'cpu\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$cpu_user" "$cpu_nice" "$cpu_system" "$cpu_idle" \
        "$cpu_iowait" "$cpu_irq" "$cpu_softirq" "$cpu_steal"
fi

if read -r load_one load_five load_fifteen runnable </proc/loadavg; then
    printf 'load\t%s\t%s\t%s\t%s\n' "$load_one" "$load_five" "$load_fifteen" "$runnable"
fi

if read -r uptime_seconds _ </proc/uptime; then
    printf 'uptime\t%s\n' "$uptime_seconds"
fi

awk '
    /^MemTotal:/ { mem_total=$2 * 1024 }
    /^MemAvailable:/ { mem_available=$2 * 1024 }
    /^SwapTotal:/ { swap_total=$2 * 1024 }
    /^SwapFree:/ { swap_free=$2 * 1024 }
    END { printf "mem\t%.0f\t%.0f\t%.0f\t%.0f\n", mem_total, mem_available, swap_total, swap_free }
' /proc/meminfo

df -B1 -P / 2>/dev/null | awk 'NR == 2 { printf "disk\t/\t%s\t%s\t%s\t%s\n", $2, $3, $4, $5 }'

default_interface="$(ip -o route show default 2>/dev/null | awk 'NR == 1 { for (i=1; i<=NF; i++) if ($i == "dev") { print $(i+1); exit } }')"
if [ -n "$default_interface" ]; then
    printf 'default_net\t%s\n' "$default_interface"
fi

awk -F: '
    NR > 2 {
        interface=$1
        gsub(/[[:space:]]/, "", interface)
        if (interface != "" && interface != "lo") {
            data=$2
            sub(/^[[:space:]]+/, "", data)
            split(data, fields, /[[:space:]]+/)
            printf "net\t%s\t%s\t%s\n", interface, fields[1], fields[9]
        }
    }
' /proc/net/dev

for service_name in ssh docker fail2ban ufw; do
    service_state="$(systemctl is-active "$service_name" 2>/dev/null || true)"
    [ -n "$service_state" ] || service_state="unknown"
    printf 'service\t%s\t%s\n' "$service_name" "$service_state"
done

if command -v docker >/dev/null 2>&1; then
    docker_version="$(docker --version 2>/dev/null || true)"
    [ -n "$docker_version" ] && printf 'docker_cli\t%s\n' "$docker_version"
    if [ -S /var/run/docker.sock ] && [ -r /var/run/docker.sock ] && [ -w /var/run/docker.sock ]; then
        printf 'docker_socket_access\tavailable\n'
    elif [ -S /var/run/docker.sock ]; then
        printf 'docker_socket_access\tpermission_locked\n'
    else
        printf 'docker_socket_access\tunsupported\n'
    fi
else
    printf 'docker_socket_access\tunsupported\n'
fi

printf 'end\n'
"""#
}

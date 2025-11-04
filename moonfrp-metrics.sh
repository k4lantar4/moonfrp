#!/bin/bash

#==============================================================================
# MoonFRP Metrics Module
# Version: 0.1.0
# Description: Service/System/Tunnel metrics collection and Prometheus export
#==============================================================================

# Use safer bash settings in script execution; be lenient when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
fi

# Source core if available for logging/utilities
if [[ -z "${MOONFRP_CORE_LOADED:-}" ]]; then
    if [[ -f "$(dirname "$0")/moonfrp-core.sh" ]]; then
        # shellcheck disable=SC1091
        source "$(dirname "$0")/moonfrp-core.sh"
    elif [[ -f "/root/moonfrp/moonfrp-core.sh" ]]; then
        # shellcheck disable=SC1091
        source "/root/moonfrp/moonfrp-core.sh"
    else
        # Minimal fallback logger
        log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] ${*:2}"; }
    fi
fi

#==============================================================================
# Configuration
#==============================================================================

METRICS_DIR="${METRICS_DIR:-$HOME/.moonfrp/metrics}"
METRICS_FILE="${METRICS_FILE:-$METRICS_DIR/moonfrp_metrics.prom}"
METRICS_TMP_FILE="${METRICS_TMP_FILE:-$METRICS_FILE.tmp}"
METRICS_HISTORY_DIR="${METRICS_HISTORY_DIR:-$METRICS_DIR/history}"

# Defaults
RETENTION_HOURS="${RETENTION_HOURS:-24}"
METRICS_INTERVAL_SECONDS="${METRICS_INTERVAL_SECONDS:-60}"

#==============================================================================
# Helpers
#==============================================================================

ensure_metrics_directories() {
    mkdir -p "$METRICS_DIR" "$METRICS_HISTORY_DIR"
}

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

write_atomic() {
    local tmp_file="$1"
    local final_file="$2"
    sync -f "$(dirname "$final_file")" 2>/dev/null || true
    mv -f "$tmp_file" "$final_file"
}

prune_history() {
    find "$METRICS_HISTORY_DIR" -type f -mmin +$((RETENTION_HOURS*60)) -print -delete 2>/dev/null || true
}

#==============================================================================
# Collectors
#==============================================================================

# Service metrics: counts of moonfrp-* services
collect_service_metrics() {
    local ts="$1"
    local total=0 active=0 failed=0

    if command -v systemctl >/dev/null 2>&1; then
        # List units prefixed with moonfrp-
        total=$(systemctl list-units --type=service --all 2>/dev/null | grep -E "^\s*moonfrp-.*\.service" | wc -l | tr -d ' ')
        active=$(systemctl list-units --type=service --all 2>/dev/null | grep -E "^\s*moonfrp-.*\.service" | grep -c " active ")
        failed=$(systemctl list-units --type=service --all 2>/dev/null | grep -E "^\s*moonfrp-.*\.service" | grep -c " failed ")
    else
        total=0; active=0; failed=0
    fi

    echo "# HELP moonfrp_services_total Total number of moonfrp-* services"
    echo "# TYPE moonfrp_services_total gauge"
    echo "moonfrp_services_total ${total}"
    echo "# HELP moonfrp_services_active Active moonfrp-* services"
    echo "# TYPE moonfrp_services_active gauge"
    echo "moonfrp_services_active ${active}"
    echo "# HELP moonfrp_services_failed Failed moonfrp-* services"
    echo "# TYPE moonfrp_services_failed gauge"
    echo "moonfrp_services_failed ${failed}"
}

# System metrics: CPU %, Memory used MB, total RX/TX bytes
_read_proc_stat_total_idle() {
    # Return total and idle jiffies
    # shellcheck disable=SC2002
    local cpu_line
    cpu_line=$(cat /proc/stat | grep '^cpu ')
    # Fields: user nice system idle iowait irq softirq steal guest guest_nice
    # shellcheck disable=SC2206
    local fields=($cpu_line)
    local idle=$(( ${fields[4]} + ${fields[5]} ))
    local total=0
    local i
    for ((i=1;i<${#fields[@]};i++)); do
        total=$(( total + ${fields[$i]} ))
    done
    echo "$total $idle"
}

_cpu_usage_percent_sample() {
    local t1 i1 t2 i2
    read -r t1 i1 < <(_read_proc_stat_total_idle)
    sleep 1
    read -r t2 i2 < <(_read_proc_stat_total_idle)
    local dt=$((t2 - t1))
    local di=$((i2 - i1))
    if (( dt <= 0 )); then echo 0; return; fi
    local used=$((dt - di))
    # Scale to percent with 2 decimals
    awk -v u="$used" -v dt="$dt" 'BEGIN{printf "%.2f", (u*100.0/dt)}'
}

_memory_used_mb() {
    local mem_total mem_avail
    mem_total=$(grep -i '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_avail=$(grep -i '^MemAvailable:' /proc/meminfo | awk '{print $2}')
    if [[ -z "$mem_total" || -z "$mem_avail" ]]; then echo 0; return; fi
    awk -v t="$mem_total" -v a="$mem_avail" 'BEGIN{printf "%.0f", (t-a)/1024}'
}

_net_totals_bytes() {
    # Sum all interfaces including lo for simplicity
    awk 'NR>2 {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev
}

collect_system_metrics() {
    local ts="$1"
    local cpu_percent mem_used_mb rx_bytes tx_bytes
    cpu_percent=$(_cpu_usage_percent_sample)
    mem_used_mb=$(_memory_used_mb)
    read -r rx_bytes tx_bytes < <(_net_totals_bytes)

    echo "# HELP moonfrp_cpu_usage_percent CPU usage percent over ~1s sample"
    echo "# TYPE moonfrp_cpu_usage_percent gauge"
    echo "moonfrp_cpu_usage_percent ${cpu_percent}"
    echo "# HELP moonfrp_memory_used_megabytes Memory used in MB"
    echo "# TYPE moonfrp_memory_used_megabytes gauge"
    echo "moonfrp_memory_used_megabytes ${mem_used_mb}"
    echo "# HELP moonfrp_net_rx_bytes_total Total received bytes across interfaces"
    echo "# TYPE moonfrp_net_rx_bytes_total counter"
    echo "moonfrp_net_rx_bytes_total ${rx_bytes}"
    echo "# HELP moonfrp_net_tx_bytes_total Total transmitted bytes across interfaces"
    echo "# TYPE moonfrp_net_tx_bytes_total counter"
    echo "moonfrp_net_tx_bytes_total ${tx_bytes}"
}

# Tunnel metrics: placeholder counts or FRP API integration when available
collect_tunnel_metrics() {
    local ts="$1"

    # Configuration for FRP dashboard API access
    local frp_port="${DEFAULT_SERVER_DASHBOARD_PORT:-7500}"
    local frp_user="${DEFAULT_SERVER_DASHBOARD_USER:-admin}"
    local frp_pass="${DEFAULT_SERVER_DASHBOARD_PASSWORD:-}"
    local frp_host="${FRP_DASHBOARD_HOST:-127.0.0.1}"
    local frp_url="${FRP_DASHBOARD_URL:-http://${frp_host}:${frp_port}}"

    # Counters (aggregate)
    local total_tunnels=0 total_conns=0 total_errors=0 failure_events=0

    # Emit schema headers
    echo "# HELP moonfrp_tunnel_connections_total Current connections per tunnel"
    echo "# TYPE moonfrp_tunnel_connections_total gauge"
    echo "# HELP moonfrp_tunnel_bandwidth_bytes_total Total bandwidth bytes per tunnel"
    echo "# TYPE moonfrp_tunnel_bandwidth_bytes_total counter"
    echo "# HELP moonfrp_tunnel_errors_total Error events per tunnel"
    echo "# TYPE moonfrp_tunnel_errors_total counter"
    echo "# HELP moonfrp_tunnel_failure_total Tunnel failure events"
    echo "# TYPE moonfrp_tunnel_failure_total counter"

    # Helper to fetch and parse proxies of a given kind (tcp/http/https/udp/stcp/xtcp)
    _emit_proxies_for_kind() {
        local kind="$1"
        local endpoint="${frp_url}/api/proxy/${kind}"
        local auth_opts=()
        if [[ -n "$frp_pass" ]]; then auth_opts=("-u" "${frp_user}:${frp_pass}"); fi
        local json
        json=$(curl -sS --max-time 1 "${auth_opts[@]}" "$endpoint" 2>/dev/null || true)
        if [[ -z "$json" ]]; then
            return 1
        fi
        # Very light parsing: extract name and a connections-like field when present
        # Accept keys: cur_conns, curConns
        # Emit zeros for bandwidth/errors until deeper integration is added
        # Ensure we only iterate when array-like content exists
        echo "$json" | tr '\n' ' ' | sed 's/\s\+/ /g' | awk -v kind="$kind" '
            BEGIN{RS="\\},\\{"}
            {
                name=""; conns="";
                if (match($0, /"name"\s*:\s*"([^"]+)"/, m)) name=m[1];
                if (match($0, /"cur[_A-Za-z]*[cC]onn[s]?"\s*:\s*([0-9]+)/, c)) conns=c[1];
                if (name!="") {
                    if (conns=="") conns=0;
                    printf("moonfrp_tunnel_connections_total{tunnel=\"%s\",kind=\"%s\"} %d\n", name, kind, conns);
                    printf("moonfrp_tunnel_bandwidth_bytes_total{tunnel=\"%s\",kind=\"%s\"} %d\n", name, kind, 0);
                    printf("moonfrp_tunnel_errors_total{tunnel=\"%s\",kind=\"%s\"} %d\n", name, kind, 0);
                }
            }
        '
        return 0
    }

    local kinds=(tcp http https udp stcp xtcp)
    local any_emitted=false
    for k in "${kinds[@]}"; do
        if _emit_proxies_for_kind "$k" >/tmp/.moonfrp_emit_$$ 2>/dev/null; then
            any_emitted=true
            # Update overall counters roughly (count lines and sum conns)
            local count emitted_conns
            count=$(wc -l </tmp/.moonfrp_emit_$$ | tr -d ' ')
            # Sum connections by grepping the first metric lines only
            emitted_conns=$(grep -E '^moonfrp_tunnel_connections_total' /tmp/.moonfrp_emit_$$ | awk '{s+=$2} END{print s+0}')
            total_tunnels=$(( total_tunnels + count/3 ))
            total_conns=$(( total_conns + emitted_conns ))
            cat /tmp/.moonfrp_emit_$$
        fi
        rm -f /tmp/.moonfrp_emit_$$ 2>/dev/null || true
    done

    if [[ "$any_emitted" != "true" ]]; then
        # API unreachable or empty; emit overall zeros and mark a failure event
        echo "# HELP moonfrp_tunnel_count Total number of tunnels detected"
        echo "# TYPE moonfrp_tunnel_count gauge"
        echo "# HELP moonfrp_tunnel_errors Total error count across tunnels (best-effort)"
        echo "# TYPE moonfrp_tunnel_errors counter"
        echo "# HELP moonfrp_tunnel_bandwidth_bps Estimated aggregate bandwidth (best-effort)"
        echo "# TYPE moonfrp_tunnel_bandwidth_bps gauge"
        echo "# HELP moonfrp_alerts_tunnel_failures_total Total tunnel failure alert events"
        echo "# TYPE moonfrp_alerts_tunnel_failures_total counter"
        echo "# HELP moonfrp_tunnel_failure_total Legacy alias for failure events"
        echo "# TYPE moonfrp_tunnel_failure_total counter"
        echo "moonfrp_tunnel_connections_total{tunnel=\"__overall__\",kind=\"all\"} 0"
        echo "moonfrp_tunnel_bandwidth_bytes_total{tunnel=\"__overall__\",kind=\"all\"} 0"
        echo "moonfrp_tunnel_errors_total{tunnel=\"__overall__\",kind=\"all\"} 0"
        failure_events=$((failure_events + 1))
        # Aggregate gauges/counters aligned with dashboard expectations
        echo "moonfrp_tunnel_count 0"
        echo "moonfrp_tunnel_errors 0"
        echo "moonfrp_tunnel_bandwidth_bps 0"
        echo "moonfrp_alerts_tunnel_failures_total ${failure_events}"
        echo "moonfrp_tunnel_failure_total ${failure_events}"
        return 0
    fi

    # Emit aggregate gauges/counters for dashboards
    echo "# HELP moonfrp_tunnel_count Total number of tunnels detected"
    echo "# TYPE moonfrp_tunnel_count gauge"
    echo "# HELP moonfrp_tunnel_errors Total error count across tunnels (best-effort)"
    echo "# TYPE moonfrp_tunnel_errors counter"
    echo "# HELP moonfrp_tunnel_bandwidth_bps Estimated aggregate bandwidth (best-effort)"
    echo "# TYPE moonfrp_tunnel_bandwidth_bps gauge"
    echo "# HELP moonfrp_alerts_tunnel_failures_total Total tunnel failure alert events"
    echo "# TYPE moonfrp_alerts_tunnel_failures_total counter"
    echo "# HELP moonfrp_tunnel_failure_total Legacy alias for failure events"
    echo "# TYPE moonfrp_tunnel_failure_total counter"
    if (( total_tunnels == 0 )); then
        failure_events=$((failure_events + 1))
    fi
    echo "moonfrp_tunnel_count ${total_tunnels}"
    echo "moonfrp_tunnel_errors ${total_errors}"
    echo "moonfrp_tunnel_bandwidth_bps 0"
    echo "moonfrp_alerts_tunnel_failures_total ${failure_events}"
    echo "moonfrp_tunnel_failure_total ${failure_events}"
}

# Orchestrator: combines collectors and writes snapshot file (history) and current .prom
collect_metrics() {
    local ts
    ts=$(now_iso)
    ensure_metrics_directories

    local tmp="$METRICS_TMP_FILE"
    {
        echo "# MoonFRP Metrics - ${ts}"
        collect_service_metrics "$ts"
        collect_system_metrics "$ts"
        collect_tunnel_metrics "$ts"
    } > "$tmp"

    # Save snapshot for history
    cp -f "$tmp" "$METRICS_HISTORY_DIR/metrics_${ts}.prom" 2>/dev/null || true
    prune_history

    # Atomic move to final exposition file
    write_atomic "$tmp" "$METRICS_FILE"
    log "INFO" "Metrics collected at ${ts} -> $METRICS_FILE"
}

# Prometheus export helper (wrapper around collect to ensure file exists)
export_metrics_prometheus() {
    collect_metrics
}

# Background worker
collect_metrics_background() {
    log "INFO" "Starting background metrics collection every ${METRICS_INTERVAL_SECONDS}s"
    while true; do
        collect_metrics || log "ERROR" "Metrics collection cycle failed"
        sleep "$METRICS_INTERVAL_SECONDS"
    done
}

# Initialize: start background worker (nohup)
init_metrics() {
    ensure_metrics_directories
    if pgrep -f "moonfrp-metrics.sh.*collect_metrics_background" >/dev/null 2>&1; then
        log "INFO" "Metrics background worker already running"
        return 0
    fi
    nohup bash -c "source \"$0\"; collect_metrics_background" >/dev/null 2>&1 &
    log "INFO" "Metrics background worker started"
}

# Simple dashboard view from current .prom file
show_metrics_dashboard() {
    ensure_metrics_directories
    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "MoonFRP Metrics Dashboard"
        echo "No metrics available yet. The collector may still be starting."
        return 0
    fi
    echo "MoonFRP Metrics Dashboard (source: $METRICS_FILE)"
    echo "Updated: $(stat -c %y "$METRICS_FILE" 2>/dev/null || date)"
    echo ""
    awk '
        /^moonfrp_services_total /{st=$2}
        /^moonfrp_services_active /{sa=$2}
        /^moonfrp_services_failed /{sf=$2}
        /^moonfrp_cpu_usage_percent /{cpu=$2}
        /^moonfrp_memory_used_megabytes /{mem=$2}
        /^moonfrp_net_rx_bytes_total /{rx=$2}
        /^moonfrp_net_tx_bytes_total /{tx=$2}
        /^moonfrp_tunnel_count /{tc=$2}
        /^moonfrp_tunnel_errors /{te=$2}
        /^moonfrp_alerts_tunnel_failures_total /{tf=$2}
        END{
            printf "Services: total=%s active=%s failed=%s\n", st+0, sa+0, sf+0;
            printf "System: cpu=%.2f%% mem=%s MB\n", cpu+0, mem+0;
            printf "Network: rx=%s bytes tx=%s bytes\n", rx+0, tx+0;
            printf "Tunnels: count=%s errors=%s alerts=%s\n", tc+0, te+0, tf+0;
        }
    ' "$METRICS_FILE"
}

# Prometheus/textfile collector integration snippet
show_prometheus_integration_snippet() {
    cat <<'EOF'
# Add this to node_exporter textfile collector configuration (systemd unit example):
#
# [Service]
# Environment="NODE_EXPORTER_TEXTFILE_DIRECTORY=/var/lib/node_exporter/textfile_collector"
#
# Then ensure moonfrp writes to a file under that directory, e.g.:
#   METRICS_DIR=/var/lib/node_exporter/textfile_collector
#   METRICS_FILE=$METRICS_DIR/moonfrp_metrics.prom
#
# Alternatively, scrape using Promtail/other agents reading the same file.
EOF
}

# Alert hook placeholder
on_tunnel_failure() {
    local tunnel="$1" reason="$2"
    # Integration point for external alerting systems
    log "WARN" "Tunnel failure detected: ${tunnel} reason=${reason}"
}

# Export selected functions for sourcing contexts
export -f ensure_metrics_directories now_iso write_atomic prune_history
export -f collect_service_metrics collect_system_metrics collect_tunnel_metrics
export -f collect_metrics export_metrics_prometheus collect_metrics_background
export -f init_metrics show_metrics_dashboard show_prometheus_integration_snippet on_tunnel_failure

# CLI usage if executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    cmd="${1:-}"
    case "$cmd" in
        init) init_metrics ;;
        collect) collect_metrics ;;
        background) collect_metrics_background ;;
        dashboard) show_metrics_dashboard ;;
        *)
            echo "Usage: $0 {init|collect|background|dashboard}"
            exit 1
            ;;
    esac
fi


#!/usr/bin/env bash
# Read-only VPS capacity and prerequisite audit. This script deliberately installs, starts, writes,
# pulls and deploys nothing. Configure checks through environment variables, never command arguments.
set -u

OPENWA_INSTALL_DIR="${OPENWA_INSTALL_DIR:-/opt/brunova/openwa}"
OPENWA_API_PORT="${OPENWA_API_PORT:-2785}"
OPENWA_EXPECTED_MIB="${OPENWA_EXPECTED_MIB:-1280}"
OPENWA_MIN_MARGIN_MIB="${OPENWA_MIN_MARGIN_MIB:-768}"
OPENWA_PREFERRED_MARGIN_MIB="${OPENWA_PREFERRED_MARGIN_MIB:-1024}"

pass_count=0
warn_count=0
fail_count=0

pass() { pass_count=$((pass_count + 1)); printf '[PASS] %s - %s\n' "$1" "$2"; }
warn() { warn_count=$((warn_count + 1)); printf '[WARN] %s - %s\n' "$1" "$2"; }
fail() { fail_count=$((fail_count + 1)); printf '[FAIL] %s - %s\n' "$1" "$2"; }

arch="$(uname -m 2>/dev/null || printf unknown)"
case "$arch" in x86_64|amd64) pass architecture "AMD64 detected" ;; *) fail architecture "expected AMD64, found $arch" ;; esac

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  os_id="$(. /etc/os-release; printf '%s' "${ID:-unknown}")"
  # shellcheck disable=SC1091
  os_version="$(. /etc/os-release; printf '%s' "${VERSION_ID:-unknown}")"
  if [ "$os_id" = ubuntu ]; then pass operating_system "Ubuntu $os_version"; else fail operating_system "expected Ubuntu, found $os_id $os_version"; fi
else
  fail operating_system '/etc/os-release is unavailable'
fi

cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || printf 0)"
if [ "$cpu_count" -ge 2 ] 2>/dev/null; then pass cpu "${cpu_count} vCPU available"; else fail cpu "at least 2 vCPU required; found $cpu_count"; fi

if [ -r /proc/meminfo ]; then
  total_mib=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))
  available_mib=$(( $(awk '/^MemAvailable:/{print $2}' /proc/meminfo) / 1024 ))
  swap_total_mib=$(( $(awk '/^SwapTotal:/{print $2}' /proc/meminfo) / 1024 ))
  swap_free_mib=$(( $(awk '/^SwapFree:/{print $2}' /proc/meminfo) / 1024 ))
  swap_used_mib=$((swap_total_mib - swap_free_mib))
  if [ "$total_mib" -ge 3800 ]; then pass memory_total "${total_mib} MiB total"; else fail memory_total "${total_mib} MiB total; about 4 GiB required"; fi
  required_preferred=$((OPENWA_EXPECTED_MIB + OPENWA_PREFERRED_MARGIN_MIB))
  required_minimum=$((OPENWA_EXPECTED_MIB + OPENWA_MIN_MARGIN_MIB))
  if [ "$available_mib" -ge "$required_preferred" ]; then
    pass memory_headroom "${available_mib} MiB available; preserves at least ${OPENWA_PREFERRED_MARGIN_MIB} MiB after OpenWA"
  elif [ "$available_mib" -ge "$required_minimum" ]; then
    warn memory_headroom "${available_mib} MiB available; only minimum post-OpenWA margin is expected"
  else
    fail memory_headroom "${available_mib} MiB available; need at least ${required_minimum} MiB before deploy"
  fi
  if [ "$swap_total_mib" -gt 0 ]; then
    if [ "$swap_used_mib" -eq 0 ]; then pass swap "${swap_total_mib} MiB configured, unused"; else warn swap "${swap_used_mib}/${swap_total_mib} MiB already used"; fi
  else
    warn swap 'no swap configured; Chromium OOM spikes have no host cushion'
  fi
else
  fail memory '/proc/meminfo is unavailable'
fi

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    docker_version="$(docker version --format '{{.Server.Version}}' 2>/dev/null || printf unknown)"
    pass docker_engine "Docker Engine $docker_version reachable"
    if docker compose version >/dev/null 2>&1; then pass compose "$(docker compose version --short 2>/dev/null)"; else fail compose 'Docker Compose v2 unavailable'; fi
    container_count="$(docker ps -a -q 2>/dev/null | wc -l | tr -d ' ')"
    pass existing_containers "${container_count} container(s) inventoried; review names separately"
    if docker system df >/dev/null 2>&1; then pass docker_disk_usage 'docker system df completed'; else warn docker_disk_usage 'docker system df failed'; fi
  else
    fail docker_engine 'Docker CLI exists but daemon is unreachable'
  fi
else
  fail docker_engine 'Docker is not installed'
fi

probe_dir="$OPENWA_INSTALL_DIR"
while [ ! -e "$probe_dir" ] && [ "$probe_dir" != / ]; do probe_dir="$(dirname "$probe_dir")"; done
if disk_line="$(df -Pk "$probe_dir" 2>/dev/null | tail -n 1)"; then
  disk_free_mib=$(( $(printf '%s\n' "$disk_line" | awk '{print $4}') / 1024 ))
  disk_used_pct="$(printf '%s\n' "$disk_line" | awk '{print $5}')"
  if [ "$disk_free_mib" -ge 5120 ]; then pass disk "${disk_free_mib} MiB free, usage $disk_used_pct"; else fail disk "${disk_free_mib} MiB free; require at least 5120 MiB"; fi
else
  fail disk "cannot inspect filesystem containing $OPENWA_INSTALL_DIR"
fi

if [ -d "$OPENWA_INSTALL_DIR" ]; then
  install_mode="$(stat -c '%a' "$OPENWA_INSTALL_DIR" 2>/dev/null || printf unknown)"
  if [ -r "$OPENWA_INSTALL_DIR" ] && [ -w "$OPENWA_INSTALL_DIR" ]; then pass install_path "$OPENWA_INSTALL_DIR exists and is accessible (mode $install_mode)"; else fail install_path "$OPENWA_INSTALL_DIR exists but is not readable/writable"; fi
else
  warn install_path "$OPENWA_INSTALL_DIR does not exist; creation is intentionally out of scope"
fi

if command -v ss >/dev/null 2>&1; then
  listeners="$(ss -H -ltn 2>/dev/null | awk -v port=":$OPENWA_API_PORT" '$4 ~ port"$" {print $4}')"
  if [ -z "$listeners" ]; then
    pass api_port "loopback port $OPENWA_API_PORT is available"
  elif printf '%s\n' "$listeners" | grep -Eq "^(0\.0\.0\.0|\[::\]|\*):$OPENWA_API_PORT$"; then
    fail api_port "port $OPENWA_API_PORT is publicly bound"
  else
    warn api_port "port $OPENWA_API_PORT is already bound on a non-public address; verify an existing OpenWA install"
  fi
else
  warn api_port 'ss is unavailable; port binding was not checked'
fi

if command -v nginx >/dev/null 2>&1; then
  if nginx -t >/dev/null 2>&1; then pass nginx 'installed and current configuration validates'; else fail nginx 'installed but nginx -t failed (permissions or invalid configuration)'; fi
else
  fail nginx 'Nginx is not installed'
fi

if command -v curl >/dev/null 2>&1; then
  registry_code="$(curl -sS -o /dev/null --max-time 10 -w '%{http_code}' https://registry-1.docker.io/v2/ 2>/dev/null || printf 000)"
  case "$registry_code" in 200|401) pass registry_outbound "Docker registry reachable (HTTP $registry_code)" ;; *) fail registry_outbound "registry probe returned HTTP $registry_code" ;; esac
else
  fail registry_outbound 'curl is unavailable'
fi

if command -v timedatectl >/dev/null 2>&1; then
  ntp_sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || printf unknown)"
  if [ "$ntp_sync" = yes ]; then pass clock 'NTP synchronized'; else warn clock "NTP synchronization state: $ntp_sync"; fi
else
  warn clock 'timedatectl unavailable; verify UTC clock manually'
fi

if command -v ufw >/dev/null 2>&1; then
  firewall_state="$(ufw status 2>/dev/null || true)"
  if printf '%s' "$firewall_state" | grep -Eq '^Status: active'; then
    if printf '%s' "$firewall_state" | grep -Eq "(^|[[:space:]])$OPENWA_API_PORT(/tcp)?[[:space:]]+ALLOW"; then fail firewall "UFW exposes $OPENWA_API_PORT"; else pass firewall "UFW active; no allow rule found for $OPENWA_API_PORT"; fi
  else
    warn firewall 'UFW inactive or unreadable; verify the host firewall/security group manually'
  fi
else
  warn firewall 'UFW unavailable; verify the host firewall/security group manually'
fi

if [ -n "${OPENWA_OFFSITE_BACKUP_TARGET:-}" ]; then
  warn offsite_backup 'target is configured but a write/restore test is intentionally not performed by read-only preflight'
else
  warn offsite_backup 'OPENWA_OFFSITE_BACKUP_TARGET is unset; off-host encrypted backup remains a blocker'
fi

printf 'SUMMARY pass=%s warn=%s fail=%s\n' "$pass_count" "$warn_count" "$fail_count"
if [ "$fail_count" -gt 0 ]; then
  printf 'GLOBAL=FAIL\n'
  exit 1
elif [ "$warn_count" -gt 0 ]; then
  printf 'GLOBAL=WARN\n'
  exit 0
else
  printf 'GLOBAL=PASS\n'
  exit 0
fi

#!/usr/bin/env bash
# Linux-only; dependencies: bash, coreutils, awk, procps, util-linux (flock).
set -euo pipefail
export LC_ALL=C
umask 077

cpu_threshold=90
mem_threshold=85
disk_threshold=80
critical_threshold=95
log_file="${HEALTH_LOG_FILE:-health_log.txt}"
max_log_bytes=1048576
keep_logs=5
json_mode=false

usage() {
  cat <<'HELP'
Usage: system_health.sh [options]
  --cpu PERCENT          CPU warning threshold (default: 90)
  --mem PERCENT          Memory warning threshold (default: 85)
  --disk PERCENT         Disk warning threshold (default: 80)
  --critical PERCENT     Critical threshold for all resources (default: 95)
  --json                 Emit one JSON object; warnings go to stderr
  --log-file PATH        Append log (default: HEALTH_LOG_FILE or health_log.txt)
  --max-log-bytes N      Rotate before appending above N bytes (default: 1048576)
  --keep-logs N          Keep N rotated files (default: 5)
  --help                 Show this help
Warning thresholds must be lower than the critical threshold.
Exit codes: 0 healthy, 1 warning, 2 critical or collection/configuration failure.
CPU is sampled over one second; memory uses MemAvailable; disk uses df -a.
HELP
}

fail() { printf '[CRITICAL] %s\n' "$*" >&2; exit 2; }
trap 'printf "[CRITICAL] Collection/logging failed at line %s\n" "$LINENO" >&2; exit 2' ERR

while (($#)); do
  case "$1" in
    --help) usage; exit 0 ;;
    --json) json_mode=true; shift ;;
    --cpu|--mem|--disk|--critical|--log-file|--max-log-bytes|--keep-logs)
      (($# >= 2)) || fail "Missing value for $1"
      case "$1" in
        --cpu) cpu_threshold=$2 ;;
        --mem) mem_threshold=$2 ;;
        --disk) disk_threshold=$2 ;;
        --critical) critical_threshold=$2 ;;
        --log-file) log_file=$2 ;;
        --max-log-bytes) max_log_bytes=$2 ;;
        --keep-logs) keep_logs=$2 ;;
      esac
      shift 2 ;;
    *) fail "Unknown option: $1 (see --help)" ;;
  esac
done

for value in "$cpu_threshold" "$mem_threshold" "$disk_threshold" "$critical_threshold"; do
  [[ $value =~ ^(0|[1-9][0-9]?)$|^100$ ]] || fail "Thresholds must be integers from 0 to 100"
done
((cpu_threshold < critical_threshold && mem_threshold < critical_threshold &&
  disk_threshold < critical_threshold)) || fail "Warning thresholds must be below --critical"
[[ $max_log_bytes =~ ^[1-9][0-9]*$ && $keep_logs =~ ^[1-9][0-9]*$ ]] || fail "Rotation values must be positive integers"
((keep_logs <= 100)) || fail "--keep-logs must be at most 100"
for dependency in awk df ps flock timeout stat date; do
  command -v "$dependency" >/dev/null || fail "Required command missing: $dependency"
done

timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hostname_value=$(hostname)
status=0
warnings=()
cpu_sample() {
  # Exclude guest/guest_nice: they are already included in user/nice counters.
  awk '/^cpu / {total=0; for(i=2;i<=9;i++) total+=$i; print total, $5+$6; exit}' /proc/stat
}
read -r total_before idle_before < <(cpu_sample)
sleep 1
read -r total_after idle_after < <(cpu_sample)
cpu_usage=$(awk -v t="$((total_after-total_before))" -v i="$((idle_after-idle_before))" \
  'BEGIN {if(t<=0) exit 1; printf "%.2f", 100*(t-i)/t}')
mem_usage=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {
  if(t<=0) exit 1; printf "%.2f", 100*(t-a)/t}' /proc/meminfo)
read -r load_one load_five load_fifteen _ < /proc/loadavg
if ! disk_output=$(timeout 10 df -Pka 2>&1); then
  status=2
  warnings+=("[CRITICAL] Some filesystem statistics are unavailable: df failed or timed out")
fi
process_output=$(ps -eo pid=,rss=,comm= --sort=-rss | awk 'NR<=5 {print}')

json_escape() {
  local value=$1
  value=${value//\\/\\\\}; value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

check_threshold() {
  local name=$1 usage_value=$2 warning=$3 level=0
  level=$(awk -v n="$usage_value" -v w="$warning" -v c="$critical_threshold" \
    'BEGIN {print (n>=c ? 2 : (n>=w ? 1 : 0))}')
  if ((level > status)); then status=$level; fi
  if ((level > 0)); then
    local prefix=WARNING
    if ((level == 2)); then prefix=CRITICAL; fi
    warnings+=("[$prefix] $name is ${usage_value}% (warning ${warning}%, critical ${critical_threshold}%)")
  fi
}
check_threshold CPU "$cpu_usage" "$cpu_threshold"
check_threshold Memory "$mem_usage" "$mem_threshold"

disks_json="["
separator=""
while read -r filesystem blocks used available capacity mountpoint; do
  [[ $blocks =~ ^[0-9]+$ ]] || continue
  percent=${capacity%\%}
  [[ $percent =~ ^[0-9]+$ ]] || percent=0
  if ((blocks > 0)); then check_threshold "Disk $mountpoint" "$percent" "$disk_threshold"; fi
  disks_json+="${separator}{\"filesystem\":$(json_escape "$filesystem"),\"mountpoint\":$(json_escape "$mountpoint"),\"size_kib\":$blocks,\"used_kib\":$used,\"available_kib\":$available,\"used_percent\":$percent}"
  separator=,
done <<< "$disk_output"
disks_json+="]"

processes_json="["
separator=""
while read -r pid rss process; do
  processes_json+="${separator}{\"pid\":$pid,\"name\":$(json_escape "$process"),\"rss_kib\":$rss}"
  separator=,
done <<< "$process_output"
processes_json+="]"
warnings_json="["
separator=""
for warning in "${warnings[@]}"; do
  warnings_json+="${separator}$(json_escape "$warning")"
  separator=,
  printf '%s\n' "$warning" >&2
done
warnings_json+="]"

entry="{\"timestamp\":$(json_escape "$timestamp"),\"hostname\":$(json_escape "$hostname_value"),\"exit_code\":$status,\"cpu_percent\":$cpu_usage,\"memory_percent\":$mem_usage,\"load_average\":[$load_one,$load_five,$load_fifteen],\"filesystems\":$disks_json,\"top_processes\":$processes_json,\"warnings\":$warnings_json}"
if ! "$json_mode"; then
  entry="[$timestamp] host=$hostname_value status=$status CPU=${cpu_usage}% memory=${mem_usage}% load=$load_one,$load_five,$load_fifteen
Filesystems (KiB):
$disk_output
Top 5 processes by RSS (KiB):
$process_output"
  for warning in "${warnings[@]}"; do entry+=$'\n'"$warning"; done
fi

mkdir -p -- "$(dirname -- "$log_file")"
exec 9>"${log_file}.lock"
flock -w 5 9 || fail "Another health collector holds the log lock"
if [[ -f $log_file ]] && (( $(stat -c %s -- "$log_file") + ${#entry} + 1 > max_log_bytes )); then
  for ((i=keep_logs; i>=2; i--)); do
    if [[ -f ${log_file}.$((i-1)) ]]; then mv -f -- "${log_file}.$((i-1))" "${log_file}.$i"; fi
  done
  mv -f -- "$log_file" "${log_file}.1"
fi
printf '%s\n' "$entry" >> "$log_file"
printf '%s\n' "$entry"
exit "$status"

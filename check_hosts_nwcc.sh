#!/usr/bin/env bash
###############################################################################
# check_hosts_summary.sh (Table + CSV output with execution time)
###############################################################################

set -euo pipefail

LIST="${LIST:-hostlist.txt}"                      # Host list file
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-.corp.local}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-3}"           # Timeout in seconds

TS="$(date +%Y%m%d_%H%M%S)"
OUTTXT="${OUTTXT:-result_${TS}.txt}"
OUTCSV="${OUTCSV:-result_${TS}.csv}"
START_NS="$(date +%s%N)"
START_ISO="$(date '+%Y-%m-%dT%H:%M:%S%z')"

# Output helper (for formatted table display)
p() {
  local fmt="$1"; shift || true
  # shellcheck disable=SC2059
  printf "$fmt" "$@" | tee -a "$OUTTXT"
}

detect_os() {
  local h="$1"
  shopt -s nocasematch
  if   [[ "$h" =~ ^(xh|00001) ]]; then echo "Ubuntu"
  elif [[ "$h" =~ ^IN-[0-9]+$ ]]; then echo "Windows"
  else echo "Unknown"
  fi
  shopt -u nocasematch
}

make_fqdn() {
  local h="$1"
  [[ "$h" == *.* ]] && echo "$h" || echo "${h}${DOMAIN_SUFFIX}"
}

resolve_v4() {
  local fq="$1"
  local out
  out="$(getent hosts "$fq" 2>/dev/null || true)"
  awk '$1 ~ /^[0-9.]+$/ {print $1; exit}' <<< "$out"
}

tcp_check() {
  local host="$1" port="$2"
  timeout "$CONNECT_TIMEOUT" bash -c "</dev/tcp/${host}/${port}" &>/dev/null
}

# Initialize output files
: > "$OUTTXT"
: > "$OUTCSV"

# Table header
p "%-21s | %-8s | %-18s | %-15s\n" "HOST" "OS" "Network Status" "SSH/RDP"
p "%s\n" "---------------------+----------+--------------------+-----------------"

# CSV header
echo "timestamp,host,os,fqdn/ip,network_status,connection_status,port" >> "$OUTCSV"

mapfile -t LINES < "$LIST"

for raw in "${LINES[@]}"; do
  host="${raw%$'\r'}"
  host="$(printf '%s' "$host" | sed 's/[[:space:]]*$//')"
  [[ -z "$host" ]] && continue

  os=$(detect_os "$host")
  fq=$(make_fqdn "$host")

  if [[ "$os" == "Ubuntu" ]]; then
    port_main=22
  elif [[ "$os" == "Windows" ]]; then
    port_main=3389
  else
    port_main=""
  fi

  ip=$(resolve_v4 "$fq")

  # If DNS resolution fails
  if [[ -z "$ip" ]]; then
    net="✖ No connection (DNS unresolved)"
    case "$os" in
      Ubuntu)  conn="✖ SSH unavailable" ;;
      Windows) conn="✖ RDP unavailable" ;;
      *)       conn="—" ;;
    esac
  else
    # If primary port is defined
    if [[ -n "$port_main" ]]; then
      if tcp_check "$fq" "$port_main"; then
        net="✓ Network reachable"
        if [[ "$os" == "Ubuntu" ]]; then conn="✓ SSH available"; else conn="✓ RDP available"; fi
      else
        if [[ "$os" == "Windows" ]]; then
          net="Network status uncertain"
          conn="✖ RDP unavailable"
        else
          net="✖ Not reachable"
          conn="✖ SSH unavailable"
        fi
      fi
    else
      # Fallback port checks
      if tcp_check "$fq" 22 || tcp_check "$fq" 3389; then
        net="✓ Network reachable"
      else
        net="✖ Not reachable"
      fi
      conn="Unknown"
    fi
  fi

  p "%-21s | %-8s | %-18s | %-15s\n" "$host" "$os" "$net" "$conn"

  # CSV output (ISO timestamp, host, OS, FQDN/IP, network status, connection status, port)
  printf "%s,%s,%s,%s/%s,%s,%s,%s\n" \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    "$host" "$os" "$fq" "${ip:-N/A}" \
    "$net" "$conn" "${port_main:-N/A}" >> "$OUTCSV"
done

p "%s\n" "--------------------------------------------------------------------------"
p "%s\n" "Network Status = TCP reachability to primary OS port (Ubuntu:22 / Windows:3389)"
p "%s\n" "For Windows, if unreachable, network status may be reported as uncertain (RDP unavailable)"

END_NS="$(date +%s%N)"
END_ISO="$(date '+%Y-%m-%dT%H:%M:%S%z')"
DUR_MS=$(( (END_NS - START_NS) / 1000000 ))

p "%s\n" "Start: ${START_ISO} / End: ${END_ISO} / Duration: $((DUR_MS/1000)).$(printf '%03d' $((DUR_MS%1000))) sec"

printf "\nOutput files:\n  - Table format: %s\n  - CSV format: %s\n" "$OUTTXT" "$OUTCSV"

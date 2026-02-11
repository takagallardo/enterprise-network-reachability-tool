#!/usr/bin/env bash
###############################################################################
# check_hosts_summary.sh（表＋CSV出力＋実行時間付き）
###############################################################################

set -euo pipefail

LIST="${LIST:-hostlist.txt}"                      # ホスト名リストファイル
DOMAIN_SUFFIX="${DOMAIN_SUFFIX:-.pc.internal.woven.tech}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-3}"           # 秒

TS="$(date +%Y%m%d_%H%M%S)"
OUTTXT="${OUTTXT:-result_${TS}.txt}"
OUTCSV="${OUTCSV:-result_${TS}.csv}"
START_NS="$(date +%s%N)"
START_ISO="$(date '+%Y-%m-%dT%H:%M:%S%z')"

# 出力ヘルパー（表形式用）
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

# 出力ヘッダ
: > "$OUTTXT"
: > "$OUTCSV"
p "%-21s | %-8s | %-18s | %-15s\n" "HOST" "OS" "ネットワーク接続" "SSH/RDP"
p "%s\n" "---------------------+----------+--------------------+-----------------"
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
  if [[ -z "$ip" ]]; then
    net="✖ 接続なし (DNS未解決)"
    case "$os" in
      Ubuntu)  conn="✖ SSH不可" ;;
      Windows) conn="✖ RDP不可" ;;
      *)       conn="—" ;;
    esac
  else
    if [[ -n "$port_main" ]]; then
      if tcp_check "$fq" "$port_main"; then
        net="✓ ネットワーク接続"
        if [[ "$os" == "Ubuntu" ]]; then conn="✓ SSH可"; else conn="✓ RDP可"; fi
      else
        if [[ "$os" == "Windows" ]]; then
          net="ネットワーク接続不明"
          conn="✖ RDP不可"
        else
          net="✖ 接続なし"
          conn="✖ SSH不可"
        fi
      fi
    else
      if tcp_check "$fq" 22 || tcp_check "$fq" 3389; then
        net="✓ ネットワーク接続"
      else
        net="✖ 接続なし"
      fi
      conn="不明"
    fi
  fi

  p "%-21s | %-8s | %-18s | %-15s\n" "$host" "$os" "$net" "$conn"

  # CSV用出力（ISO時刻,ホスト,OS,FQDN/IP,ネットワーク状態,接続状態,ポート）
  printf "%s,%s,%s,%s/%s,%s,%s,%s\n" \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" \
    "$host" "$os" "$fq" "${ip:-N/A}" \
    "$net" "$conn" "${port_main:-N/A}" >> "$OUTCSV"
done

p "%s\n" "--------------------------------------------------------------------------"
p "%s\n" "※ ネットワーク接続 = OS代表ポートへのTCP到達性（Ubuntu:22 / Windows:3389）"
p "%s\n" "※ Windowsで到達不可時は『ネットワーク接続不明』として扱います（RDP不可）"

END_NS="$(date +%s%N)"
END_ISO="$(date '+%Y-%m-%dT%H:%M:%S%z')"
DUR_MS=$(( (END_NS - START_NS) / 1000000 ))
p "%s\n" "実行開始: ${START_ISO} / 実行終了: ${END_ISO} / 実行時間: $((DUR_MS/1000)).$(printf '%03d' $((DUR_MS%1000)))秒"

printf "\n✅ 出力ファイル:\n  - 表形式: %s\n  - CSV形式: %s\n" "$OUTTXT" "$OUTCSV"


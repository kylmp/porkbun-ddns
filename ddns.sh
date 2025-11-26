#!/usr/bin/env bash
set -euo pipefail

CONFIG="/root/porkbun-ddns/ddns.conf"

if [ ! -r "$CONFIG" ]; then
  echo "Config file not found or not readable: $CONFIG" >&2
  exit 1
fi

# Required in ddns.conf:
#   PORKBUN_API_KEY
#   PORKBUN_API_SECRET
#   IP_FILE
#   STATUS_FILE
#   PORKBUN_API_BASE
#   RECORDS=( "domain ttl type subdomain" ... )
# shellcheck source=/root/porkbun-ddns/ddns.conf
source "$CONFIG"

RUN_TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
UPDATED_COUNT=0
FAILED_COUNT=0

# ---- Get public IP via randomized providers --------------------------------

get_public_ip() {
  local services=(
    "https://api.ipify.org"
    "https://ifconfig.co/ip"
    "https://icanhazip.com"
    "https://ipinfo.io/ip"
  )

  local count=${#services[@]}
  local ip=""
  local start=$((RANDOM % count))

  for ((i = 0; i < count; i++)); do
    local idx=$(((start + i) % count))
    local service="${services[$idx]}"

    ip=$(curl -s --max-time 5 "$service" | tr -d '[:space:]')

    # Validate IPv4
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "$ip"
      return 0
    fi
  done

  return 1
}

CURRENT_IP=$(get_public_ip || true)

if [ -z "$CURRENT_IP" ]; then
  echo "Error: failed to retrieve public IP" >&2

  mkdir -p "$(dirname "$STATUS_FILE")" 2>/dev/null || true
  {
    echo "timestamp=$RUN_TIMESTAMP"
    echo "status=error"
    echo "message=ERROR: Could not determine public IP"
    echo "current_ip="
    echo "updated_records=0"
    echo "failed_records=0"
  } > "$STATUS_FILE" 2>/dev/null || true

  exit 1
fi

echo "Current IP: $CURRENT_IP"

# ---- Update a single DNS record -------------------------------------------

update_record() {
  local domain="$1"
  local ttl="$2"
  local type="$3"
  local sub="$4"

  local url host_label

  case "$sub" in
    ""|"@" )
      # root domain
      url="${PORKBUN_API_BASE}/dns/editByNameType/${domain}/${type}"
      host_label="${domain}"
      ;;
    * )
      url="${PORKBUN_API_BASE}/dns/editByNameType/${domain}/${type}/${sub}"
      host_label="${sub}.${domain}"
      ;;
  esac

  local payload
  payload=$(cat <<EOF
{
  "apikey": "$PORKBUN_API_KEY",
  "secretapikey": "$PORKBUN_API_SECRET",
  "content": "$CURRENT_IP",
  "ttl": $ttl
}
EOF
)

  local response
  response=$(curl -s -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "$payload")

  if [[ "$response" == *'"status":"SUCCESS"'* ]]; then
    echo "✔ Updated: ${host_label} → ${CURRENT_IP} (TTL=${ttl})"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
    return 0
  else
    echo "✘ Failed: ${host_label} — $response"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    return 1
  fi
}

# ---- Update all records ----------------------------------------------------

all_ok=0

echo "--- Updating records ---"
for entry in "${RECORDS[@]}"; do
  # Each entry: domain ttl type subdomain
  # shellcheck disable=SC2086
  read -r rec_domain rec_ttl rec_type rec_sub <<<"$entry"

  rec_sub=${rec_sub:-@}  # missing subdomain = root

  echo "Updating: domain=${rec_domain}, ttl=${rec_ttl}, type=${rec_type}, sub='${rec_sub}'"

  if ! update_record "$rec_domain" "$rec_ttl" "$rec_type" "$rec_sub"; then
    all_ok=1
  fi
done

# ---- Always update IP_FILE with last seen IP -------------------------------

mkdir -p "$(dirname "$IP_FILE")" 2>/dev/null || true
echo "$CURRENT_IP" > "$IP_FILE"

# ---- Determine status: ok / partial / error --------------------------------

status="ok"
message="OK: Successfully updated ${UPDATED_COUNT} record(s)"

if [ "$UPDATED_COUNT" -gt 0 ] && [ "$FAILED_COUNT" -gt 0 ]; then
  status="partial"
  message="PARTIAL: ${UPDATED_COUNT} record(s) updated, ${FAILED_COUNT} failed"
elif [ "$UPDATED_COUNT" -eq 0 ] && [ "$FAILED_COUNT" -gt 0 ]; then
  status="error"
  message="ERROR: All ${FAILED_COUNT} record(s) failed during update"
fi

# ---- Write status file -----------------------------------------------------

mkdir -p "$(dirname "$STATUS_FILE")" 2>/dev/null || true
{
  echo "timestamp=$RUN_TIMESTAMP"
  echo "status=$status"
  echo "message=$message"
  echo "current_ip=$CURRENT_IP"
  echo "updated_records=$UPDATED_COUNT"
  echo "failed_records=$FAILED_COUNT"
} > "$STATUS_FILE" 2>/dev/null || true

# Exit code: 0 on all_ok, 1 otherwise (so cron/monitoring can alert on failures)
exit "$all_ok"

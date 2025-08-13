#!/usr/bin/env bash
#
# quick-check.sh — Smoke test for the Utilities stack
# - Validates Caddy and Authelia configs
# - Verifies core containers are Up
# - Performs SNI HTTPS checks for key hostnames via Caddy
#
# Usage:
#   ./quick-check.sh [UTILITIES_IP] [LOCAL_DOMAIN]
#   env UTILITIES_IP=192.168.1.1 LOCAL_DOMAIN=home ./quick-check.sh
#
set -Eeuo pipefail

COLOR_RED=$'\033[1;31m'
COLOR_GRN=$'\033[1;32m'
COLOR_YEL=$'\033[1;33m'
COLOR_BLU=$'\033[1;34m'
COLOR_RST=$'\033[0m'

ok()    { echo "${COLOR_GRN}✔${COLOR_RST} $*"; }
warn()  { echo "${COLOR_YEL}⚠${COLOR_RST} $*"; }
err()   { echo "${COLOR_RED}✖${COLOR_RST} $*"; }
info()  { echo "${COLOR_BLU}ℹ${COLOR_RST} $*"; }

# Defaults
UTIL_DIR="${UTIL_DIR:-$HOME/docker/utilities}"
COMPOSE="docker compose -f \"$UTIL_DIR/docker-compose.yml\""

# Read optional args
UTILITIES_IP="${1:-${UTILITIES_IP:-}}"
LOCAL_DOMAIN_ARG="${2:-${LOCAL_DOMAIN:-}}"

# Source .env if present to get LOCAL_DOMAIN, etc.
if [[ -f "$UTIL_DIR/.env" ]]; then
  # shellcheck disable=SC1090
  source "$UTIL_DIR/.env"
fi

# Resolve domain and IP
LOCAL_DOMAIN="${LOCAL_DOMAIN_ARG:-${LOCAL_DOMAIN:-lan}}"
if [[ -z "${UTILITIES_IP}" ]]; then
  # Best-effort pick of primary IPv4; override with arg/env if needed
  UTILITIES_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

if [[ -z "${UTILITIES_IP}" ]]; then
  err "Unable to determine utilities IP. Pass as first arg or set UTILITIES_IP env."
  exit 1
fi

info "Using utilities dir: $UTIL_DIR"
info "Using utilities IP:  $UTILITIES_IP"
info "Using local domain:   $LOCAL_DOMAIN"

shopt -s expand_aliases
alias dcomp="$COMPOSE"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing command: $1"; exit 1; }
}
need_cmd docker

section() { echo; echo "=== $* ==="; }

section "Container status"
# shellcheck disable=SC2086
if ! eval $COMPOSE ps; then
  err "docker compose ps failed"
  exit 1
fi

section "Validate Caddy config"
if ! docker run --rm -v "$UTIL_DIR/caddy:/c" caddy:latest caddy validate --config /c/Caddyfile >/dev/null 2>&1; then
  err "caddy validate failed"
  docker run --rm -v "$UTIL_DIR/caddy:/c" caddy:latest caddy validate --config /c/Caddyfile || true
  exit 1
else
  ok "Caddyfile is valid"
fi

section "Validate Authelia config"
if ! docker run --rm -v "$UTIL_DIR/authelia/config:/config" authelia/authelia:latest \
  authelia validate-config --config /config/configuration.yml >/dev/null 2>&1; then
  err "Authelia validate-config failed"
  docker run --rm -v "$UTIL_DIR/authelia/config:/config" authelia/authelia:latest \
    authelia validate-config --config /config/configuration.yml || true
  exit 1
else
  ok "Authelia configuration validates"
fi

section "Internal reachability (from Caddy container)"
if ! docker compose -f "$UTIL_DIR/docker-compose.yml" exec -T caddy sh -c \
  'apk add --no-cache curl >/dev/null 2>&1 || true; curl -sS -o /dev/null -w "%{http_code}\n" http://authelia:9091/' >/tmp/_authelia_hc 2>/dev/null; then
  err "Could not exec into caddy container"
  exit 1
fi
AUTHELIA_HC="$(cat /tmp/_authelia_hc || true)"
if [[ "$AUTHELIA_HC" =~ ^(200|302)$ ]]; then
  ok "Authelia reachable from Caddy (HTTP $AUTHELIA_HC)"
else
  warn "Authelia health from Caddy returned HTTP $AUTHELIA_HC"
fi

curl_sni() {
  local host="$1"; shift
  local path="$1"; shift
  local expect="$1"; shift
  local url="https://${host}${path}"
  local code
  code="$(curl -kIs --resolve "${host}:443:${UTILITIES_IP}" "$url" | awk '/^HTTP/{print $2}' | tail -n1)"
  if [[ "$code" == "$expect" ]]; then
    ok "$host $path -> $code"
    return 0
  else
    warn "$host $path -> $code (expected $expect)"
    return 1
  fi
}

has_location_contains() {
  local host="$1"; shift
  local path="$1"; shift
  local needle="$1"; shift
  local loc
  loc="$(curl -kIs --resolve "${host}:443:${UTILITIES_IP}" "https://${host}${path}" | awk -F': ' 'tolower($1)=="location"{print $2}' | tr -d '\r')"
  if [[ "$loc" == *"$needle"* ]]; then
    ok "$host $path location contains '$needle'"
    return 0
  else
    warn "$host $path location is '$loc' (did not contain '$needle')"
    return 1
  fi
}

section "SNI HTTPS checks via Caddy"
fail=0

# Authelia portal should render
curl_sni "authelia.${LOCAL_DOMAIN}" "/authelia/" "200" || fail=$((fail+1))

# Protected sites should 302 to /authelia when unauthenticated
for h in "glance" "code" "uptime" "vaultwarden"; do
  curl_sni "${h}.${LOCAL_DOMAIN}" "/" "302" || fail=$((fail+1))
  has_location_contains "${h}.${LOCAL_DOMAIN}" "/" "/authelia/?rd=" || fail=$((fail+1))
done

# Open WebUI (not protected here) should respond (200/302 acceptable)
OPEN_CODE="$(curl -kIs --resolve "open.${LOCAL_DOMAIN}:443:${UTILITIES_IP}" "https://open.${LOCAL_DOMAIN}/" | awk '/^HTTP/{print $2}' | tail -n1)"
if [[ "$OPEN_CODE" =~ ^(200|302)$ ]]; then
  ok "open.${LOCAL_DOMAIN} / -> $OPEN_CODE"
else
  warn "open.${LOCAL_DOMAIN} / -> $OPEN_CODE"
  fail=$((fail+1))
fi

# Proxmox via Caddy (status may vary; treat 2xx/3xx/4xx as pass, 5xx as fail)
PROX_CODE="$(curl -kIs --resolve "proxmox.${LOCAL_DOMAIN}:443:${UTILITIES_IP}" "https://proxmox.${LOCAL_DOMAIN}/" | awk '/^HTTP/{print $2}' | tail -n1)"
if [[ "$PROX_CODE" =~ ^(1|2|3|4)[0-9][0-9]$ ]]; then
  ok "proxmox.${LOCAL_DOMAIN} / -> $PROX_CODE"
else
  warn "proxmox.${LOCAL_DOMAIN} / -> $PROX_CODE"
  fail=$((fail+1))
fi

section "Summary"
if [[ "$fail" -eq 0 ]]; then
  ok "All checks passed"
  exit 0
else
  err "$fail check(s) failed"
  exit 1
fi


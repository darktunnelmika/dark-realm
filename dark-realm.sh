#!/usr/bin/env bash
# ==============================================================================
#  DARK VPN · REALM PRO
#  Native Realm relay manager with the shared DARK operator experience.
#  Upstream core: https://github.com/zhboner/realm
#  Support: @mikakhadm
#
#  DARKVPN-REALM-SCRIPT
# ==============================================================================
set -u

SCRIPT_VER="1.0.0"
SCHEMA_VER="1"
DEV_ID="@mikakhadm"

CORE_REPO="zhboner/realm"
CORE_PIN="v2.9.6"
SELF_REPO="darktunnelmika/dark-realm"

BASE_DIR="${DARK_REALM_BASE_DIR:-/etc/dark-realm}"
TUN_DIR="$BASE_DIR/tunnels"
CERT_STORE="$BASE_DIR/certs"
RUNTIME_DIR="$BASE_DIR/runtime"
BACKUP_DIR="$BASE_DIR/backups"
BIN_PATH="${DARK_REALM_BIN_PATH:-/usr/local/bin/realm}"
CMD_PATH="${DARK_REALM_CMD_PATH:-/usr/local/bin/darkrealm}"
UNIT_FILE="${DARK_REALM_UNIT_FILE:-/etc/systemd/system/dark-realm@.service}"
RS_UNIT="${DARK_REALM_RS_UNIT:-/etc/systemd/system/dark-realm-restart@.service}"
RS_TIMER="${DARK_REALM_RS_TIMER:-/etc/systemd/system/dark-realm-restart@.timer}"
CORE_VER_FILE="$BASE_DIR/core.version"
UPDATE_URL_FILE="$BASE_DIR/update.url"
SELF_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")"

DEFAULT_GATEWAY_PORT="3080"
DEFAULT_PROFILE="balanced"
MAX_ENDPOINTS="${DARK_REALM_MAX_ENDPOINTS:-256}"
PAIR_MAX_BYTES=8192

# curl | bash leaves stdin attached to the download pipe. Reattach it so every
# interactive read uses the real terminal.
if [ ! -t 0 ] && [ -r /dev/tty ] && [ "${DARK_REALM_LIB_ONLY:-0}" != "1" ]; then
  exec </dev/tty
fi

# ===================================================================== UI ===
R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; Y=$'\e[38;5;221m'
C=$'\e[38;5;81m';  M=$'\e[38;5;177m'; W=$'\e[1;97m'
D=$'\e[38;5;244m'; N=$'\e[0m';        BD=$'\e[1m'
L1=$'\e[38;5;33m'; L2=$'\e[38;5;39m'; L3=$'\e[38;5;45m'
L4=$'\e[38;5;51m'; L5=$'\e[38;5;87m'; L6=$'\e[38;5;123m'
BG_OK=$'\e[48;5;22m'; BG_ERR=$'\e[48;5;52m'; BG_WARN=$'\e[48;5;58m'
UIW=64

shopt -s extglob 2>/dev/null || true
if ! locale charmap 2>/dev/null | grep -qi 'utf-\?8'; then
  for _locale in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if locale -a 2>/dev/null | grep -qix "${_locale//./\\.}"; then
      export LC_ALL="$_locale"
      break
    fi
  done
fi
_probe='é'; [ "${#_probe}" -eq 1 ] && UTF_OK=1 || UTF_OK=0

vislen() {
  local s="${1//$'\e['*([0-9;])m/}"
  if [ "$UTF_OK" = 1 ]; then printf '%s' "${#s}"; return; fi
  local b c
  b="$(LC_ALL=C; printf '%s' "$s" | wc -c)"
  c="$(printf '%s' "$s" | LC_ALL=C grep -o $'[\x80-\xbf]' 2>/dev/null | wc -l)"
  printf '%s' $(( b - c ))
}
rep() { local ch="$1" n="$2"; [ "${n:-0}" -gt 0 ] 2>/dev/null || return 0; printf "${ch}%.0s" $(seq 1 "$n"); }
top() { printf '  %s╭%s╮%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
mid() { printf '  %s├%s┤%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
bot() { printf '  %s╰%s╯%s\n' "$C" "$(rep '─' $((UIW+2)))" "$N"; }
row() {
  local t="$1" l p
  l="$(vislen "$t")"; p=$((UIW-l)); (( p < 0 )) && p=0
  printf '  %s│%s %s%*s %s│%s\n' "$C" "$N" "$t" "$p" "" "$C" "$N"
}
blank() { row ""; }
item() { row "$(printf '%s%s%s  %s%-25s%s %s%s%s' "$Y" "[$1]" "$N" "$W" "$2" "$N" "$D" "${3:-}" "$N")"; }
kv() { row "$(printf '%s%-15s%s %s' "$D" "$1" "$N" "$2")"; }
sect() { row "$(printf '%s%s%s' "$M$BD" "$1" "$N")"; }
badge() { printf '%s %s %s' "$2$BD" "$1" "$N"; }

ok()   { printf '  %s+%s %s\n' "$G" "$N" "$*"; }
bad()  { printf '  %sx%s %s\n' "$R" "$N" "$*" >&2; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
info() { printf '  %s>%s %s\n' "$C" "$N" "$*"; }
dim()  { printf '    %s%s%s\n' "$D" "$*" "$N"; }

ask() {
  local p="$1" d="${2:-}" v
  if [ -n "$d" ]; then
    read -r -p "$(printf '  %s>%s %s %s[%s]%s: ' "$C" "$N" "$p" "$D" "$d" "$N")" v
  else
    read -r -p "$(printf '  %s>%s %s: ' "$C" "$N" "$p")" v
  fi
  ANS="${v:-$d}"
}
ask_secret() {
  local p="$1" v
  read -rs -p "$(printf '  %s>%s %s: ' "$C" "$N" "$p")" v
  printf '\n'
  ANS="$v"
}
yesno() {
  local p="$1" d="$2" v
  read -r -p "$(printf '  %s>%s %s %s[%s]%s: ' "$C" "$N" "$p" "$D" "$([ "$d" = y ] && echo 'Y/n' || echo 'y/N')" "$N")" v
  v="${v:-$d}"
  [[ "$v" =~ ^[Yy]$ ]]
}
getkey() {
  local k
  printf '  %s>%s Select: ' "$C" "$N"
  read -rsn1 k
  [ -z "$k" ] && k="_"
  printf '%s\n\n' "$k"
  KEY="$k"
}
pause() { printf '\n  %spress any key%s' "$D" "$N"; read -rsn1 _; echo; }

core_version_short() {
  if [ -x "$BIN_PATH" ]; then
    local v
    v="$("$BIN_PATH" --version 2>/dev/null | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"
    [ -n "$v" ] && { printf '%s' "$v"; return; }
    [ -s "$CORE_VER_FILE" ] && { cat "$CORE_VER_FILE"; return; }
    printf 'installed'
  else
    printf 'not installed'
  fi
}
core_badge() {
  if [ -x "$BIN_PATH" ]; then badge "READY" "$BG_OK$W"; else badge "NO CORE" "$BG_ERR$W"; fi
}
header() {
  clear 2>/dev/null || true
  top
  row "$(printf '%s██████╗  %s█████╗ %s██████╗ %s██╗  ██╗%s' "$L1" "$L2" "$L3" "$L4" "$N")"
  row "$(printf '%s██╔══██╗%s██╔══██╗%s██╔══██╗%s██║ ██╔╝%s' "$L1" "$L2" "$L3" "$L4" "$N")"
  row "$(printf '%s██║  ██║%s███████║%s██████╔╝%s█████╔╝ %s' "$L2" "$L3" "$L4" "$L5" "$N")"
  row "$(printf '%s██║  ██║%s██╔══██║%s██╔══██╗%s██╔═██╗ %s' "$L2" "$L3" "$L4" "$L5" "$N")"
  row "$(printf '%s██████╔╝%s██║  ██║%s██║  ██║%s██║  ██╗%s' "$L3" "$L4" "$L5" "$L6" "$N")"
  row "$(printf '%s╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝%s' "$D" "$N")"
  row "$(printf '%sR%s E%s A%s L%s M%s   %sNative high-performance relay%s' "$L2" "$L3" "$L4" "$L5" "$L6" "$W$BD" "$N")"
  mid
  row "$(printf '%s  %score %s%s   %sv%s%s   %s%s%s' "$(core_badge)" "$D" "$N$W" "$(core_version_short)" "$D" "$SCRIPT_VER" "$N" "$M" "$DEV_ID" "$N")"
  bot
  if [ -n "${1:-}" ]; then
    echo
    printf '  %s>%s %s%s%s\n' "$L4" "$N" "$W$BD" "$1" "$N"
  fi
  echo
}

# ================================================================ BASICS ===
need_root() { [ "$(id -u)" -eq 0 ] || { bad "run as root"; exit 1; }; }
now_epoch() { date +%s; }
valid_port() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
valid_int_range() { [[ "${1:-}" =~ ^[0-9]+$ ]] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]; }
valid_name() { [[ "${1:-}" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$ ]]; }
valid_profile() { case "${1:-}" in stable|balanced|low_ping|turbo|custom) return 0;; *) return 1;; esac; }
valid_transport() { case "${1:-}" in tcp|tls|ws|wss) return 0;; *) return 1;; esac; }
valid_log_level() { case "${1:-}" in off|error|warn|info|debug|trace) return 0;; *) return 1;; esac; }
valid_ws_mask() { case "${1:-}" in skipped|fixed|standard) return 0;; *) return 1;; esac; }
valid_bool() { [ "${1:-}" = 0 ] || [ "${1:-}" = 1 ]; }
valid_ws_path() { [[ "${1:-}" =~ ^/[A-Za-z0-9._~/-]{1,127}$ ]] && [[ "$1" != *".."* ]]; }
valid_alpn() { [ -z "${1:-}" ] || [[ "$1" =~ ^[A-Za-z0-9./,-]{1,64}$ ]]; }
valid_bind() {
  local v="${1:-}"
  valid_ipv4 "$v"
}
valid_domain() {
  local d="${1:-}"
  [ "${#d}" -le 253 ] || return 1
  [[ "$d" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}
valid_ipv4() {
  local ip="${1:-}" o
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1:4}"; do
    [ "${#o}" -gt 1 ] && [ "${o:0:1}" = 0 ] && return 1
    [ "$o" -le 255 ] || return 1
  done
}
valid_host() {
  valid_ipv4 "${1:-}" && return 0
  valid_domain "${1:-}"
}
contains_control() { LC_ALL=C printf '%s' "${1:-}" | grep -q '[[:cntrl:]]'; }
safe_path_value() {
  local p="${1:-}"
  [ -n "$p" ] && [ "${#p}" -le 512 ] && [[ "$p" = /* ]] && [[ "$p" != *$'\n'* ]] && [[ "$p" != *$'\r'* ]] && [[ "$p" != *".."* ]]
}
toml_escape() {
  local s="${1:-}"
  contains_control "$s" && return 1
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}
random_path() {
  local r
  if command -v openssl >/dev/null 2>&1; then r="$(openssl rand -hex 8)"; else r="$(date +%s%N | sha256sum | cut -c1-16)"; fi
  printf '/%s' "$r"
}
sha256_text() { printf '%s' "$1" | sha256sum | awk '{print $1}'; }
b64url_enc() { base64 -w0 2>/dev/null | tr '+/' '-_' | tr -d '='; }
b64url_dec() {
  local s="${1//-/+}" rem
  s="${s//_/\/}"; rem=$(( ${#s} % 4 ))
  [ "$rem" -eq 2 ] && s="${s}=="
  [ "$rem" -eq 3 ] && s="${s}="
  [ "$rem" -eq 1 ] && return 1
  printf '%s' "$s" | base64 -d 2>/dev/null
}
pkg_mgr() {
  command -v apt-get >/dev/null 2>&1 && { echo apt; return; }
  command -v dnf >/dev/null 2>&1 && { echo dnf; return; }
  command -v yum >/dev/null 2>&1 && { echo yum; return; }
  command -v apk >/dev/null 2>&1 && { echo apk; return; }
  echo none
}
install_deps() {
  local missing=0 c
  for c in curl tar ss awk sed grep openssl sha256sum base64 python3 getent; do
    command -v "$c" >/dev/null 2>&1 || missing=1
  done
  [ "$missing" -eq 0 ] && return 0
  info "installing dependencies"
  case "$(pkg_mgr)" in
    apt)
      apt-get update -qq >/dev/null 2>&1 || true
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl tar iproute2 openssl ca-certificates coreutils python3 libc-bin procps >/dev/null 2>&1
      ;;
    dnf) dnf install -y curl tar iproute openssl ca-certificates coreutils python3 glibc-common procps-ng >/dev/null 2>&1 ;;
    yum) yum install -y curl tar iproute openssl ca-certificates coreutils python3 glibc-common procps-ng >/dev/null 2>&1 ;;
    apk) apk add --no-cache bash curl tar iproute2 openssl ca-certificates coreutils python3 musl-utils procps >/dev/null 2>&1 ;;
    *) bad "no supported package manager"; return 1 ;;
  esac
}
ensure_dirs() {
  mkdir -p "$BASE_DIR" "$TUN_DIR" "$CERT_STORE" "$RUNTIME_DIR" "$BACKUP_DIR"
  chmod 700 "$BASE_DIR" "$TUN_DIR" "$CERT_STORE" "$RUNTIME_DIR" "$BACKUP_DIR"
  [ -f "$UPDATE_URL_FILE" ] || printf 'https://raw.githubusercontent.com/%s/main/dark-realm.sh\n' "$SELF_REPO" > "$UPDATE_URL_FILE"
  chmod 600 "$UPDATE_URL_FILE"
}
arch_asset() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) printf 'unsupported' ;;
  esac
}
service_name() { printf 'dark-realm@%s.service' "$1"; }
tunnel_dir() { printf '%s/%s' "$TUN_DIR" "$1"; }
tunnel_names() { find "$TUN_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.partial-*' -printf '%f\n' 2>/dev/null | sort; }
tunnel_count() { tunnel_names | grep -c . || true; }
first_field() { printf '%s' "$1" | cut -d'>' -f1; }


# ============================================================= MAPPINGS ===
CANON_MAPS=""
MAP_COUNT=0

_append_map() {
  local public="$1" target="$2" backbone="$3"
  valid_port "$public" && valid_port "$target" && valid_port "$backbone" || return 1
  if printf ',%s,' "$CANON_MAPS" | grep -q ",${public}>"; then
    bad "duplicate public port: $public"
    return 1
  fi
  CANON_MAPS="${CANON_MAPS:+$CANON_MAPS,}${public}>${target}@${backbone}"
  MAP_COUNT=$((MAP_COUNT+1))
  [ "$MAP_COUNT" -le "$MAX_ENDPOINTS" ] || { bad "endpoint limit exceeded ($MAX_ENDPOINTS)"; return 1; }
}
expand_mappings() {
  local input="${1//[[:space:]]/}" base="$2" token left right start end p target next
  CANON_MAPS=""; MAP_COUNT=0; next="$base"
  valid_port "$base" || { bad "invalid backbone base port"; return 1; }
  [ -n "$input" ] || { bad "port mapping cannot be empty"; return 1; }
  IFS=',' read -r -a _tokens <<< "$input"
  for token in "${_tokens[@]}"; do
    [ -n "$token" ] || { bad "empty port mapping"; return 1; }
    if [[ "$token" == *">"* ]]; then
      left="${token%%>*}"; right="${token#*>}"
      valid_port "$right" || { bad "invalid target in $token"; return 1; }
    else
      left="$token"; right=""
    fi
    if [[ "$left" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"; end="${BASH_REMATCH[2]}"
      valid_port "$start" && valid_port "$end" && [ "$start" -le "$end" ] || { bad "invalid range: $left"; return 1; }
      [ $((end-start+1)) -le "$MAX_ENDPOINTS" ] || { bad "range is too large"; return 1; }
      for ((p=start; p<=end; p++)); do
        target="${right:-$p}"
        _append_map "$p" "$target" "$next" || return 1
        next=$((next+1)); [ "$next" -le 65536 ] || { bad "backbone port range overflow"; return 1; }
      done
    elif valid_port "$left"; then
      target="${right:-$left}"
      _append_map "$left" "$target" "$next" || return 1
      next=$((next+1)); [ "$next" -le 65536 ] || { bad "backbone port range overflow"; return 1; }
    else
      bad "invalid mapping: $token"
      return 1
    fi
  done
  [ "$MAP_COUNT" -gt 0 ]
}
validate_canonical_maps() {
  local maps="$1" e public target backbone count=0 seen=","
  [ -n "$maps" ] && [ "${#maps}" -le 8192 ] || return 1
  IFS=',' read -r -a _entries <<< "$maps"
  for e in "${_entries[@]}"; do
    [[ "$e" =~ ^([0-9]+)\>([0-9]+)@([0-9]+)$ ]] || return 1
    public="${BASH_REMATCH[1]}"; target="${BASH_REMATCH[2]}"; backbone="${BASH_REMATCH[3]}"
    valid_port "$public" && valid_port "$target" && valid_port "$backbone" || return 1
    [[ "$seen" != *",$public,"* ]] || return 1
    seen="${seen}${public},"
    count=$((count+1)); [ "$count" -le "$MAX_ENDPOINTS" ] || return 1
  done
  [ "$count" -gt 0 ]
}
mapping_count() { tr ',' '\n' <<< "$1" | grep -c . || true; }
mapping_public_ports() {
  local e
  IFS=',' read -r -a _entries <<< "$1"
  for e in "${_entries[@]}"; do printf '%s\n' "${e%%>*}"; done
}
mapping_target_ports() {
  local e tail
  IFS=',' read -r -a _entries <<< "$1"
  for e in "${_entries[@]}"; do tail="${e#*>}"; printf '%s\n' "${tail%%@*}"; done
}
mapping_backbone_ports() {
  local e
  IFS=',' read -r -a _entries <<< "$1"
  for e in "${_entries[@]}"; do printf '%s\n' "${e##*@}"; done
}
mapping_summary() {
  local e n=0
  IFS=',' read -r -a _entries <<< "$1"
  for e in "${_entries[@]}"; do
    n=$((n+1))
    [ "$n" -le 8 ] && printf '    %s\n' "$e"
  done
  [ "${#_entries[@]}" -gt 8 ] && printf '    ... +%d more\n' $((${#_entries[@]}-8))
}

# ================================================================ META ====
reset_meta() {
  META_SCHEMA="$SCHEMA_VER"
  NAME=""; ROLE=""; GATEWAY_HOST=""; TARGET_HOST="127.0.0.1"; BIND_ADDR="0.0.0.0"
  TRANSPORT="tcp"; PROFILE="balanced"; MAPS=""; TLS_DOMAIN=""; TLS_CERT=""; TLS_KEY=""
  TLS_INSECURE="0"; SNI=""; ALPN=""; WS_HOST=""; WS_PATH=""; WS_MASK="skipped"
  NOFILE="524288"; TCP_TIMEOUT="5"; TCP_KEEPALIVE="15"; TCP_KEEPALIVE_PROBE="3"
  LOG_LEVEL="warn"; RESTART_SEC="2"; SCHEDULE="off"; THROUGH=""; INTERFACE=""
  SOURCE_ALLOWLIST=""; CREATED_AT="$(now_epoch)"
}
meta_allowed_key() {
  case "$1" in
    SCHEMA|NAME|ROLE|GATEWAY_HOST|TARGET_HOST|BIND_ADDR|TRANSPORT|PROFILE|MAPS|TLS_DOMAIN|TLS_CERT|TLS_KEY|TLS_INSECURE|SNI|ALPN|WS_HOST|WS_PATH|WS_MASK|NOFILE|TCP_TIMEOUT|TCP_KEEPALIVE|TCP_KEEPALIVE_PROBE|LOG_LEVEL|RESTART_SEC|SCHEDULE|THROUGH|INTERFACE|SOURCE_ALLOWLIST|CREATED_AT) return 0 ;;
    *) return 1 ;;
  esac
}
assign_meta_key() {
  local k="$1" v="$2"
  case "$k" in
    SCHEMA) META_SCHEMA="$v" ;;
    NAME) NAME="$v" ;;
    ROLE) ROLE="$v" ;;
    GATEWAY_HOST) GATEWAY_HOST="$v" ;;
    TARGET_HOST) TARGET_HOST="$v" ;;
    BIND_ADDR) BIND_ADDR="$v" ;;
    TRANSPORT) TRANSPORT="$v" ;;
    PROFILE) PROFILE="$v" ;;
    MAPS) MAPS="$v" ;;
    TLS_DOMAIN) TLS_DOMAIN="$v" ;;
    TLS_CERT) TLS_CERT="$v" ;;
    TLS_KEY) TLS_KEY="$v" ;;
    TLS_INSECURE) TLS_INSECURE="$v" ;;
    SNI) SNI="$v" ;;
    ALPN) ALPN="$v" ;;
    WS_HOST) WS_HOST="$v" ;;
    WS_PATH) WS_PATH="$v" ;;
    WS_MASK) WS_MASK="$v" ;;
    NOFILE) NOFILE="$v" ;;
    TCP_TIMEOUT) TCP_TIMEOUT="$v" ;;
    TCP_KEEPALIVE) TCP_KEEPALIVE="$v" ;;
    TCP_KEEPALIVE_PROBE) TCP_KEEPALIVE_PROBE="$v" ;;
    LOG_LEVEL) LOG_LEVEL="$v" ;;
    RESTART_SEC) RESTART_SEC="$v" ;;
    SCHEDULE) SCHEDULE="$v" ;;
    THROUGH) THROUGH="$v" ;;
    INTERFACE) INTERFACE="$v" ;;
    SOURCE_ALLOWLIST) SOURCE_ALLOWLIST="$v" ;;
    CREATED_AT) CREATED_AT="$v" ;;
  esac
}
load_meta() {
  local name="$1" file k v
  file="$TUN_DIR/$name/meta.conf"
  [ -r "$file" ] || { bad "metadata not found: $name"; return 1; }
  reset_meta; META_SCHEMA=""
  while IFS='=' read -r k v || [ -n "${k:-}" ]; do
    [ -n "$k" ] || continue
    meta_allowed_key "$k" || continue
    contains_control "$v" && { bad "unsafe metadata value"; return 1; }
    assign_meta_key "$k" "$v"
  done < "$file"
  validate_meta
}
validate_meta() {
  [ "${META_SCHEMA:-$SCHEMA_VER}" = "$SCHEMA_VER" ] || { bad "unsupported metadata schema"; return 1; }
  valid_name "$NAME" || { bad "invalid tunnel name"; return 1; }
  case "$ROLE" in edge|gateway) ;; *) bad "invalid role"; return 1;; esac
  valid_host "$GATEWAY_HOST" || { bad "invalid gateway host"; return 1; }
  valid_host "$TARGET_HOST" || { bad "invalid target host"; return 1; }
  valid_bind "$BIND_ADDR" || { bad "invalid bind address"; return 1; }
  valid_transport "$TRANSPORT" || { bad "invalid transport"; return 1; }
  valid_profile "$PROFILE" || { bad "invalid profile"; return 1; }
  validate_canonical_maps "$MAPS" || { bad "invalid mappings"; return 1; }
  valid_bool "$TLS_INSECURE" || return 1
  valid_int_range "$NOFILE" 1024 4194304 || return 1
  valid_int_range "$TCP_TIMEOUT" 0 300 || return 1
  valid_int_range "$TCP_KEEPALIVE" 0 3600 || return 1
  valid_int_range "$TCP_KEEPALIVE_PROBE" 1 30 || return 1
  valid_int_range "$RESTART_SEC" 1 60 || return 1
  valid_log_level "$LOG_LEVEL" || return 1
  valid_alpn "$ALPN" || return 1
  case "$SCHEDULE" in off|1h|6h|12h|24h) ;; *) return 1;; esac
  if [ "$TRANSPORT" = tls ] || [ "$TRANSPORT" = wss ]; then
    valid_domain "$TLS_DOMAIN" && valid_domain "$SNI" || { bad "invalid TLS domain/SNI"; return 1; }
    if [ "$ROLE" = gateway ]; then
      safe_path_value "$TLS_CERT" && safe_path_value "$TLS_KEY" || { bad "invalid certificate paths"; return 1; }
    fi
  fi
  if [ "$TRANSPORT" = ws ] || [ "$TRANSPORT" = wss ]; then
    valid_domain "$WS_HOST" && valid_ws_path "$WS_PATH" && valid_ws_mask "$WS_MASK" || { bad "invalid WebSocket settings"; return 1; }
  fi
  return 0
}
write_meta_to() {
  local dir="$1" file="$1/meta.conf"
  mkdir -p "$dir"
  umask 077
  {
    printf 'SCHEMA=%s\n' "$SCHEMA_VER"
    printf 'NAME=%s\n' "$NAME"
    printf 'ROLE=%s\n' "$ROLE"
    printf 'GATEWAY_HOST=%s\n' "$GATEWAY_HOST"
    printf 'TARGET_HOST=%s\n' "$TARGET_HOST"
    printf 'BIND_ADDR=%s\n' "$BIND_ADDR"
    printf 'TRANSPORT=%s\n' "$TRANSPORT"
    printf 'PROFILE=%s\n' "$PROFILE"
    printf 'MAPS=%s\n' "$MAPS"
    printf 'TLS_DOMAIN=%s\n' "$TLS_DOMAIN"
    printf 'TLS_CERT=%s\n' "$TLS_CERT"
    printf 'TLS_KEY=%s\n' "$TLS_KEY"
    printf 'TLS_INSECURE=%s\n' "$TLS_INSECURE"
    printf 'SNI=%s\n' "$SNI"
    printf 'ALPN=%s\n' "$ALPN"
    printf 'WS_HOST=%s\n' "$WS_HOST"
    printf 'WS_PATH=%s\n' "$WS_PATH"
    printf 'WS_MASK=%s\n' "$WS_MASK"
    printf 'NOFILE=%s\n' "$NOFILE"
    printf 'TCP_TIMEOUT=%s\n' "$TCP_TIMEOUT"
    printf 'TCP_KEEPALIVE=%s\n' "$TCP_KEEPALIVE"
    printf 'TCP_KEEPALIVE_PROBE=%s\n' "$TCP_KEEPALIVE_PROBE"
    printf 'LOG_LEVEL=%s\n' "$LOG_LEVEL"
    printf 'RESTART_SEC=%s\n' "$RESTART_SEC"
    printf 'SCHEDULE=%s\n' "$SCHEDULE"
    printf 'THROUGH=%s\n' "$THROUGH"
    printf 'INTERFACE=%s\n' "$INTERFACE"
    printf 'SOURCE_ALLOWLIST=%s\n' "$SOURCE_ALLOWLIST"
    printf 'CREATED_AT=%s\n' "$CREATED_AT"
  } > "$file.tmp"
  chmod 600 "$file.tmp"
  mv -f "$file.tmp" "$file"
}


# ============================================================= PAIR CODE ===
PAIR_NAME=""; PAIR_GATEWAY=""; PAIR_TARGET=""; PAIR_TRANSPORT=""; PAIR_PROFILE=""
PAIR_MAPS=""; PAIR_TLS_DOMAIN=""; PAIR_TLS_INSECURE="0"; PAIR_SNI=""; PAIR_ALPN=""
PAIR_WS_HOST=""; PAIR_WS_PATH=""; PAIR_WS_MASK=""; PAIR_CREATED=""

pair_payload_from_loaded_meta() {
  cat <<EOF
schema=$SCHEMA_VER
name=$NAME
gateway=$GATEWAY_HOST
target=$TARGET_HOST
transport=$TRANSPORT
profile=$PROFILE
maps=$MAPS
tls_domain=$TLS_DOMAIN
tls_insecure=$TLS_INSECURE
sni=$SNI
alpn=$ALPN
ws_host=$WS_HOST
ws_path=$WS_PATH
ws_mask=$WS_MASK
created=$CREATED_AT
EOF
}
generate_pair_code() {
  local payload encoded sum
  payload="$(pair_payload_from_loaded_meta)"
  encoded="$(printf '%s' "$payload" | b64url_enc)"
  sum="$(sha256_text "$payload")"
  printf 'DR1.%s.%s' "$encoded" "$sum"
}
reset_pair() {
  PAIR_NAME=""; PAIR_GATEWAY=""; PAIR_TARGET="127.0.0.1"; PAIR_TRANSPORT=""
  PAIR_PROFILE="balanced"; PAIR_MAPS=""; PAIR_TLS_DOMAIN=""; PAIR_TLS_INSECURE="0"
  PAIR_SNI=""; PAIR_ALPN=""; PAIR_WS_HOST=""; PAIR_WS_PATH=""; PAIR_WS_MASK="skipped"; PAIR_CREATED=""
}
parse_pair_code() {
  local code="${1:-}" prefix encoded expected payload actual k v
  [ "${#code}" -le "$PAIR_MAX_BYTES" ] || { bad "pair code is too large"; return 1; }
  IFS='.' read -r prefix encoded expected _extra <<< "$code"
  [ "$prefix" = DR1 ] && [ -n "$encoded" ] && [[ "$expected" =~ ^[a-f0-9]{64}$ ]] && [ -z "${_extra:-}" ] || {
    bad "invalid DR1 pair code"; return 1;
  }
  payload="$(b64url_dec "$encoded")" || { bad "pair code base64 is invalid"; return 1; }
  [ "${#payload}" -le 6144 ] || { bad "decoded pair code is too large"; return 1; }
  actual="$(sha256_text "$payload")"
  [ "$actual" = "$expected" ] || { bad "pair code checksum mismatch"; return 1; }
  reset_pair
  while IFS='=' read -r k v || [ -n "${k:-}" ]; do
    [ -n "$k" ] || continue
    contains_control "$v" && { bad "pair code contains control characters"; return 1; }
    case "$k" in
      schema) [ "$v" = "$SCHEMA_VER" ] || { bad "unsupported pair schema"; return 1; } ;;
      name) PAIR_NAME="$v" ;;
      gateway) PAIR_GATEWAY="$v" ;;
      target) PAIR_TARGET="$v" ;;
      transport) PAIR_TRANSPORT="$v" ;;
      profile) PAIR_PROFILE="$v" ;;
      maps) PAIR_MAPS="$v" ;;
      tls_domain) PAIR_TLS_DOMAIN="$v" ;;
      tls_insecure) PAIR_TLS_INSECURE="$v" ;;
      sni) PAIR_SNI="$v" ;;
      alpn) PAIR_ALPN="$v" ;;
      ws_host) PAIR_WS_HOST="$v" ;;
      ws_path) PAIR_WS_PATH="$v" ;;
      ws_mask) PAIR_WS_MASK="$v" ;;
      created) PAIR_CREATED="$v" ;;
      *) bad "unknown pair-code field: $k"; return 1 ;;
    esac
  done <<< "$payload"
  valid_name "$PAIR_NAME" || { bad "invalid pair tunnel name"; return 1; }
  valid_host "$PAIR_GATEWAY" && valid_host "$PAIR_TARGET" || { bad "invalid pair endpoint"; return 1; }
  valid_transport "$PAIR_TRANSPORT" && valid_profile "$PAIR_PROFILE" || { bad "invalid pair transport/profile"; return 1; }
  validate_canonical_maps "$PAIR_MAPS" || { bad "invalid pair mappings"; return 1; }
  valid_bool "$PAIR_TLS_INSECURE" || return 1
  valid_alpn "$PAIR_ALPN" || return 1
  [[ "$PAIR_CREATED" =~ ^[0-9]{1,12}$ ]] || { bad "invalid pair timestamp"; return 1; }
  if [ "$PAIR_TRANSPORT" = tls ] || [ "$PAIR_TRANSPORT" = wss ]; then
    valid_domain "$PAIR_TLS_DOMAIN" && valid_domain "$PAIR_SNI" || { bad "invalid pair TLS data"; return 1; }
  fi
  if [ "$PAIR_TRANSPORT" = ws ] || [ "$PAIR_TRANSPORT" = wss ]; then
    valid_domain "$PAIR_WS_HOST" && valid_ws_path "$PAIR_WS_PATH" && valid_ws_mask "$PAIR_WS_MASK" || {
      bad "invalid pair WebSocket data"; return 1;
    }
  fi
}
apply_pair_to_meta() {
  reset_meta
  NAME="$PAIR_NAME"; ROLE="gateway"; GATEWAY_HOST="$PAIR_GATEWAY"; TARGET_HOST="$PAIR_TARGET"
  TRANSPORT="$PAIR_TRANSPORT"; PROFILE="$PAIR_PROFILE"; MAPS="$PAIR_MAPS"
  TLS_DOMAIN="$PAIR_TLS_DOMAIN"; TLS_INSECURE="$PAIR_TLS_INSECURE"; SNI="$PAIR_SNI"; ALPN="$PAIR_ALPN"
  WS_HOST="$PAIR_WS_HOST"; WS_PATH="$PAIR_WS_PATH"; WS_MASK="$PAIR_WS_MASK"; CREATED_AT="$PAIR_CREATED"
  apply_profile "$PROFILE"
}

# =============================================================== PROFILE ===
apply_profile() {
  PROFILE="$1"
  case "$PROFILE" in
    stable)
      NOFILE=262144; TCP_TIMEOUT=10; TCP_KEEPALIVE=20; TCP_KEEPALIVE_PROBE=5; LOG_LEVEL=warn; RESTART_SEC=3 ;;
    balanced)
      NOFILE=524288; TCP_TIMEOUT=5; TCP_KEEPALIVE=15; TCP_KEEPALIVE_PROBE=3; LOG_LEVEL=warn; RESTART_SEC=2 ;;
    low_ping)
      NOFILE=524288; TCP_TIMEOUT=3; TCP_KEEPALIVE=5; TCP_KEEPALIVE_PROBE=3; LOG_LEVEL=warn; RESTART_SEC=1 ;;
    turbo)
      NOFILE=1048576; TCP_TIMEOUT=4; TCP_KEEPALIVE=10; TCP_KEEPALIVE_PROBE=3; LOG_LEVEL=error; RESTART_SEC=1 ;;
    custom) : ;;
  esac
}
pick_profile() {
  top; sect "PERFORMANCE PROFILE"; blank
  item 1 "Stable" "lossy or unstable routes"
  item 2 "Balanced" "recommended default"
  item 3 "Low Ping" "latency-sensitive TCP"
  item 4 "Turbo" "many users / connections"
  item 5 "Custom" "validated real Realm values"
  bot; echo; getkey
  case "$KEY" in
    1) PROFILE=stable ;;
    3) PROFILE=low_ping ;;
    4) PROFILE=turbo ;;
    5) PROFILE=custom ;;
    *) PROFILE=balanced ;;
  esac
  apply_profile "$PROFILE"
  if [ "$PROFILE" = custom ]; then
    ask "file descriptor limit" "524288"; NOFILE="$ANS"
    valid_int_range "$NOFILE" 1024 4194304 || { bad "invalid nofile"; return 1; }
    ask "TCP connect timeout seconds (0 disables)" "5"; TCP_TIMEOUT="$ANS"
    valid_int_range "$TCP_TIMEOUT" 0 300 || { bad "invalid timeout"; return 1; }
    ask "TCP keepalive seconds (0 uses system)" "15"; TCP_KEEPALIVE="$ANS"
    valid_int_range "$TCP_KEEPALIVE" 0 3600 || { bad "invalid keepalive"; return 1; }
    ask "TCP keepalive probes" "3"; TCP_KEEPALIVE_PROBE="$ANS"
    valid_int_range "$TCP_KEEPALIVE_PROBE" 1 30 || { bad "invalid probe count"; return 1; }
    ask "systemd restart delay seconds" "2"; RESTART_SEC="$ANS"
    valid_int_range "$RESTART_SEC" 1 60 || { bad "invalid restart delay"; return 1; }
    ask "log level (off/error/warn/info/debug/trace)" "warn"; LOG_LEVEL="$ANS"
    valid_log_level "$LOG_LEVEL" || { bad "invalid log level"; return 1; }
  fi
}
pick_transport() {
  top; sect "TRANSPORT"; blank
  item 1 "TCP" "fastest, no domain"
  item 2 "TLS" "encrypted, domain + certificate"
  item 3 "WS" "WebSocket, Host + Path"
  item 4 "WSS" "WebSocket + TLS"
  item 0 "Back" ""
  bot; echo; getkey
  case "$KEY" in 1) TRANSPORT=tcp;; 2) TRANSPORT=tls;; 3) TRANSPORT=ws;; 4) TRANSPORT=wss;; *) return 1;; esac
}
configure_transport_edge() {
  TLS_DOMAIN=""; TLS_CERT=""; TLS_KEY=""; TLS_INSECURE=0; SNI=""; ALPN=""
  WS_HOST=""; WS_PATH=""; WS_MASK=skipped
  if [ "$TRANSPORT" = tls ] || [ "$TRANSPORT" = wss ]; then
    ask "TLS domain pointing to KHAREJ Gateway"
    valid_domain "$ANS" || { bad "invalid domain"; return 1; }
    TLS_DOMAIN="${ANS,,}"
    ask "SNI" "$TLS_DOMAIN"; SNI="${ANS,,}"
    valid_domain "$SNI" || { bad "invalid SNI"; return 1; }
    ask "ALPN (blank for default)" ""; ALPN="$ANS"
    valid_alpn "$ALPN" || { bad "invalid ALPN"; return 1; }
    echo
    top; sect "CERTIFICATE MODE"; blank
    item 1 "Trusted certificate" "Let's Encrypt / valid CA"
    item 2 "Self-signed test" "client verification disabled"
    bot; echo; getkey
    [ "$KEY" = 2 ] && TLS_INSECURE=1 || TLS_INSECURE=0
  fi
  if [ "$TRANSPORT" = ws ] || [ "$TRANSPORT" = wss ]; then
    local defhost
    defhost="${TLS_DOMAIN:-$GATEWAY_HOST}"
    valid_domain "$defhost" || defhost="gateway.example.com"
    ask "WebSocket Host" "$defhost"; WS_HOST="${ANS,,}"
    valid_domain "$WS_HOST" || { bad "invalid WebSocket Host"; return 1; }
    ask "WebSocket Path" "$(random_path)"; WS_PATH="$ANS"
    valid_ws_path "$WS_PATH" || { bad "invalid WebSocket Path"; return 1; }
    top; sect "WEBSOCKET MASK"; blank
    item 1 "Skipped" "fastest native default"
    item 2 "Fixed" "stable mask per connection"
    item 3 "Standard" "standards-compatible masking"
    bot; echo; getkey
    case "$KEY" in 2) WS_MASK=fixed;; 3) WS_MASK=standard;; *) WS_MASK=skipped;; esac
  fi
}

# ================================================================ CONFIG ===
edge_transport_string() {
  local out=""
  case "$TRANSPORT" in
    tcp) out="" ;;
    tls)
      out="tls;sni=$SNI"
      [ -n "$ALPN" ] && out="$out;alpn=$ALPN"
      [ "$TLS_INSECURE" = 1 ] && out="$out;insecure"
      ;;
    ws) out="ws;host=$WS_HOST;path=$WS_PATH;mask=$WS_MASK" ;;
    wss)
      out="ws;host=$WS_HOST;path=$WS_PATH;mask=$WS_MASK;tls;sni=$SNI"
      [ -n "$ALPN" ] && out="$out;alpn=$ALPN"
      [ "$TLS_INSECURE" = 1 ] && out="$out;insecure"
      ;;
  esac
  printf '%s' "$out"
}
gateway_transport_string() {
  case "$TRANSPORT" in
    tcp) printf '' ;;
    tls) printf 'tls;cert=%s;key=%s' "$TLS_CERT" "$TLS_KEY" ;;
    ws) printf 'ws;host=%s;path=%s' "$WS_HOST" "$WS_PATH" ;;
    wss) printf 'ws;host=%s;path=%s;tls;cert=%s;key=%s' "$WS_HOST" "$WS_PATH" "$TLS_CERT" "$TLS_KEY" ;;
  esac
}
generate_config_to() {
  local dir="$1" file="$1/config.toml" transport e public tail target backbone
  mkdir -p "$dir"
  umask 077
  {
    printf '[log]\n'
    printf 'level = "%s"\n' "$(toml_escape "$LOG_LEVEL")"
    printf 'output = "stdout"\n\n'
    printf '[network]\n'
    printf 'no_tcp = false\n'
    printf 'use_udp = false\n'
    printf 'tcp_timeout = %s\n' "$TCP_TIMEOUT"
    printf 'tcp_keepalive = %s\n' "$TCP_KEEPALIVE"
    printf 'tcp_keepalive_probe = %s\n' "$TCP_KEEPALIVE_PROBE"
    printf '\n'
    if [ "$ROLE" = edge ]; then transport="$(edge_transport_string)"; else transport="$(gateway_transport_string)"; fi
    IFS=',' read -r -a _entries <<< "$MAPS"
    for e in "${_entries[@]}"; do
      public="${e%%>*}"; tail="${e#*>}"; target="${tail%%@*}"; backbone="${e##*@}"
      printf '[[endpoints]]\n'
      if [ "$ROLE" = edge ]; then
        printf 'listen = "%s:%s"\n' "$(toml_escape "$BIND_ADDR")" "$public"
        printf 'remote = "%s:%s"\n' "$(toml_escape "$GATEWAY_HOST")" "$backbone"
        [ -n "$THROUGH" ] && printf 'through = "%s"\n' "$(toml_escape "$THROUGH")"
        [ -n "$INTERFACE" ] && printf 'interface = "%s"\n' "$(toml_escape "$INTERFACE")"
        [ -n "$transport" ] && printf 'remote_transport = "%s"\n' "$(toml_escape "$transport")"
      else
        printf 'listen = "%s:%s"\n' "$(toml_escape "$BIND_ADDR")" "$backbone"
        printf 'remote = "%s:%s"\n' "$(toml_escape "$TARGET_HOST")" "$target"
        [ -n "$THROUGH" ] && printf 'through = "%s"\n' "$(toml_escape "$THROUGH")"
        [ -n "$INTERFACE" ] && printf 'interface = "%s"\n' "$(toml_escape "$INTERFACE")"
        [ -n "$transport" ] && printf 'listen_transport = "%s"\n' "$(toml_escape "$transport")"
      fi
      printf '\n'
    done
  } > "$file.tmp"
  chmod 600 "$file.tmp"
  mv -f "$file.tmp" "$file"
}
validate_config_file() {
  local file="$1" expected="$2" count
  [ -s "$file" ] || { bad "empty Realm config"; return 1; }
  count="$(grep -c '^\[\[endpoints\]\]$' "$file" || true)"
  [ "$count" -eq "$expected" ] || { bad "config endpoint count mismatch"; return 1; }
  grep -q '^\[network\]$' "$file" && grep -q '^listen = "' "$file" && grep -q '^remote = "' "$file" || {
    bad "config structure is incomplete"; return 1;
  }
  if python3 - "$file" >/dev/null 2>&1 <<'PY'
import sys
try:
    import tomllib
except ImportError:
    raise SystemExit(0)
with open(sys.argv[1], "rb") as fh:
    data = tomllib.load(fh)
assert isinstance(data.get("endpoints"), list) and data["endpoints"]
for ep in data["endpoints"]:
    assert ep.get("listen") and ep.get("remote")
PY
  then
    return 0
  fi
  bad "TOML validation failed"
  return 1
}
config_fingerprint() {
  local name="$1"
  sha256sum "$TUN_DIR/$name/config.toml" "$TUN_DIR/$name/meta.conf" 2>/dev/null | sha256sum | awk '{print $1}'
}


# =============================================================== SYSTEMD ===
ensure_units() {
  mkdir -p "$(dirname "$UNIT_FILE")"
  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=DARK Realm Tunnel (%i)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=simple
ExecStart=$BIN_PATH -c $TUN_DIR/%i/config.toml
Restart=always
RestartSec=2
TimeoutStopSec=15
KillSignal=SIGTERM
UMask=0077
LimitNOFILE=524288
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true

[Install]
WantedBy=multi-user.target
EOF
  cat > "$RS_UNIT" <<EOF
[Unit]
Description=Scheduled restart for DARK Realm (%i)
After=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/systemctl restart dark-realm@%i.service
EOF
  cat > "$RS_TIMER" <<EOF
[Unit]
Description=Scheduled restart timer for DARK Realm (%i)

[Timer]
OnBootSec=15min
OnUnitActiveSec=24h
Persistent=true
Unit=dark-realm-restart@%i.service

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload 2>/dev/null || true
}
write_unit_dropin() {
  local name="$1" dir="/etc/systemd/system/dark-realm@${1}.service.d"
  mkdir -p "$dir"
  cat > "$dir/override.conf" <<EOF
[Service]
LimitNOFILE=$NOFILE
RestartSec=$RESTART_SEC
EOF
  chmod 644 "$dir/override.conf"
  systemctl daemon-reload 2>/dev/null || true
}
set_restart_timer() {
  local name="$1" schedule="$2" dropin="/etc/systemd/system/dark-realm-restart@${name}.timer.d"
  systemctl disable --now "dark-realm-restart@$name.timer" >/dev/null 2>&1 || true
  rm -rf "$dropin"
  [ "$schedule" = off ] && { systemctl daemon-reload >/dev/null 2>&1 || true; return 0; }
  local interval
  case "$schedule" in 1h) interval=1h;; 6h) interval=6h;; 12h) interval=12h;; *) interval=24h;; esac
  mkdir -p "$dropin"
  cat > "$dropin/override.conf" <<EOF
[Timer]
OnUnitActiveSec=
OnUnitActiveSec=$interval
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now "dark-realm-restart@$name.timer" >/dev/null 2>&1
}
expected_ports_loaded() {
  if [ "$ROLE" = edge ]; then mapping_public_ports "$MAPS"; else mapping_backbone_ports "$MAPS"; fi
}
port_is_listening() {
  local p="$1"
  ss -H -lnt 2>/dev/null | awk -v p="$p" '{a=$4; sub(/^.*:/,"",a); if(a==p) found=1} END{exit !found}'
}
port_owner() {
  local p="$1"
  ss -H -lntp 2>/dev/null | awk -v p="$p" '$4 ~ (":" p "$") {print; exit}'
}
check_port_conflicts_loaded() {
  local p conflict=0
  while read -r p; do
    [ -n "$p" ] || continue
    if port_is_listening "$p"; then
      bad "port $p is already listening"
      dim "$(port_owner "$p")"
      conflict=1
    fi
  done < <(expected_ports_loaded)
  [ "$conflict" -eq 0 ]
}
check_target_ports_loaded() {
  local p missing=0
  [ "$ROLE" = gateway ] || return 0
  while read -r p; do
    [ -n "$p" ] || continue
    if ! ss -H -lnt 2>/dev/null | awk -v p="$p" -v h="$TARGET_HOST" '
      {a=$4; sub(/^.*:/,"",a); if(a==p) found=1} END{exit !found}'; then
      warn "target $TARGET_HOST:$p is not listening yet"
      missing=1
    fi
  done < <(mapping_target_ports "$MAPS" | sort -nu)
  return "$missing"
}
service_active() { systemctl is-active --quiet "$(service_name "$1")" 2>/dev/null; }
service_pid() { systemctl show "$(service_name "$1")" -p MainPID --value 2>/dev/null || echo 0; }
service_uptime() {
  local started now
  started="$(systemctl show "$(service_name "$1")" -p ActiveEnterTimestampMonotonic --value 2>/dev/null)"
  [[ "$started" =~ ^[0-9]+$ ]] || { echo 0; return; }
  now="$(awk '{printf "%.0f", $1*1000000}' /proc/uptime 2>/dev/null)"
  [[ "$now" =~ ^[0-9]+$ ]] || { echo 0; return; }
  echo $(( (now-started)/1000000 ))
}
verify_tunnel_health() {
  local name="$1" p failed=0
  service_active "$name" || { bad "service is not active"; journalctl -u "$(service_name "$name")" -n 12 --no-pager -o cat 2>/dev/null | sed 's/^/    /'; return 1; }
  load_meta "$name" || return 1
  while read -r p; do
    [ -n "$p" ] || continue
    port_is_listening "$p" || { bad "expected listener missing: $p"; failed=1; }
  done < <(expected_ports_loaded)
  [ "$failed" -eq 0 ]
}
start_tunnel() {
  local name="$1"
  systemctl enable --now "$(service_name "$name")" >/dev/null 2>&1
  sleep 1
  verify_tunnel_health "$name"
}
stop_tunnel_hard() {
  local name="$1" pid
  systemctl disable --now "$(service_name "$name")" >/dev/null 2>&1 || true
  pid="$(service_pid "$name")"
  valid_int_range "${pid:-0}" 1 99999999 && kill "$pid" 2>/dev/null || true
}
restart_tunnel() {
  systemctl restart "$(service_name "$1")" >/dev/null 2>&1
  sleep 1
  verify_tunnel_health "$1"
}
transactional_regen() {
  local name="$1" dir="$TUN_DIR/$name" backup="$dir/backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  cp -a "$dir/config.toml" "$dir/meta.conf" "$backup/" 2>/dev/null || true
  write_meta_to "$dir" || return 1
  generate_config_to "$dir" || return 1
  validate_config_file "$dir/config.toml" "$(mapping_count "$MAPS")" || {
    cp -af "$backup/"* "$dir/" 2>/dev/null || true
    return 1
  }
  write_unit_dropin "$name"
  if restart_tunnel "$name"; then
    ok "configuration applied"
    return 0
  fi
  warn "health check failed; rolling back"
  cp -af "$backup/"* "$dir/" 2>/dev/null || true
  systemctl restart "$(service_name "$name")" >/dev/null 2>&1 || true
  return 1
}

# ================================================================== CORE ===
release_metadata() {
  local endpoint="$1" asset="$2" json
  json="$(mktemp)" || return 1
  if ! curl -fsSL --retry 3 --max-time 30 -o "$json" "$endpoint"; then rm -f "$json"; return 1; fi
  python3 - "$json" "$asset" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
name = sys.argv[2]
for asset in data.get("assets", []):
    if asset.get("name") == name:
        digest = asset.get("digest") or ""
        if digest.startswith("sha256:"):
            digest = digest.split(":", 1)[1]
        print(data.get("tag_name", ""))
        print(asset.get("browser_download_url", ""))
        print(digest)
        raise SystemExit(0)
raise SystemExit(2)
PY
  local rc=$?
  rm -f "$json"
  return "$rc"
}
install_core_release() {
  local tag="$1" arch asset endpoint meta rtag url digest tmp dir found actual old
  arch="$(arch_asset)"
  [ "$arch" != unsupported ] || { bad "only amd64 and arm64 are supported in v1"; return 1; }
  asset="realm-${arch}-unknown-linux-musl.tar.gz"
  if [ "$tag" = latest ]; then
    endpoint="https://api.github.com/repos/$CORE_REPO/releases/latest"
  else
    endpoint="https://api.github.com/repos/$CORE_REPO/releases/tags/$tag"
  fi
  info "reading Realm release metadata"
  meta="$(release_metadata "$endpoint" "$asset")" || { bad "verified release asset not found"; return 1; }
  rtag="$(sed -n '1p' <<< "$meta")"; url="$(sed -n '2p' <<< "$meta")"; digest="$(sed -n '3p' <<< "$meta")"
  [ -n "$rtag" ] && [[ "$url" = https://* ]] && [[ "$digest" =~ ^[a-fA-F0-9]{64}$ ]] || {
    bad "release metadata has no usable SHA-256 digest"; return 1;
  }
  tmp="$(mktemp)" || return 1; dir="$(mktemp -d)" || { rm -f "$tmp"; return 1; }
  info "downloading $asset ($rtag)"
  if ! curl -fL --retry 3 --max-time 180 -o "$tmp" "$url"; then rm -rf "$tmp" "$dir"; bad "download failed"; return 1; fi
  actual="$(sha256sum "$tmp" | awk '{print $1}')"
  [ "${actual,,}" = "${digest,,}" ] || { rm -rf "$tmp" "$dir"; bad "SHA-256 verification failed"; return 1; }
  ok "SHA-256 verified"
  tar -xzf "$tmp" -C "$dir" || { rm -rf "$tmp" "$dir"; bad "archive extraction failed"; return 1; }
  found="$(find "$dir" -type f -name realm -perm -u+x | head -n1)"
  [ -n "$found" ] || { rm -rf "$tmp" "$dir"; bad "Realm binary not found in archive"; return 1; }
  "$found" --version >/dev/null 2>&1 || { rm -rf "$tmp" "$dir"; bad "downloaded binary failed version check"; return 1; }
  old=""
  if [ -x "$BIN_PATH" ]; then
    old="$BIN_PATH.bak.$(date +%s)"
    cp -a "$BIN_PATH" "$old" || { rm -rf "$tmp" "$dir"; return 1; }
  fi
  install -m 0755 "$found" "$BIN_PATH.new" || { rm -rf "$tmp" "$dir"; return 1; }
  mv -f "$BIN_PATH.new" "$BIN_PATH"
  printf '%s\n' "$rtag" > "$CORE_VER_FILE"; chmod 600 "$CORE_VER_FILE"
  rm -rf "$tmp" "$dir"
  ensure_units
  local failed=0 n
  for n in $(tunnel_names); do
    systemctl restart "$(service_name "$n")" >/dev/null 2>&1 || failed=1
  done
  sleep 1
  for n in $(tunnel_names); do verify_tunnel_health "$n" >/dev/null 2>&1 || failed=1; done
  if [ "$failed" -ne 0 ] && [ -n "$old" ]; then
    bad "one or more tunnels failed; restoring previous core"
    cp -af "$old" "$BIN_PATH"
    for n in $(tunnel_names); do systemctl restart "$(service_name "$n")" >/dev/null 2>&1 || true; done
    return 1
  fi
  ok "Realm core installed: $rtag"
}
install_core_local() {
  local src
  ask "local Realm binary path"; src="$ANS"
  [ -x "$src" ] || { bad "file is not executable"; return 1; }
  "$src" --version >/dev/null 2>&1 || { bad "not a working Realm binary"; return 1; }
  dim "sha256: $(sha256sum "$src" | awk '{print $1}')"
  yesno "install this local binary?" n || return 1
  [ -x "$BIN_PATH" ] && cp -a "$BIN_PATH" "$BIN_PATH.bak.$(date +%s)"
  install -m 0755 "$src" "$BIN_PATH"
  "$BIN_PATH" --version | head -n1 > "$CORE_VER_FILE"
  ok "local core installed"
}
screen_core() {
  while :; do
    header "CORE MANAGER"
    top; sect "REALM CORE"; blank
    kv "installed" "$W$(core_version_short)$N"
    kv "pinned" "$CORE_PIN"
    kv "architecture" "$(uname -m)"
    mid
    item 1 "Install pinned" "$CORE_PIN, verified"
    item 2 "Install latest" "verified GitHub release"
    item 3 "Install local binary" "shows SHA-256"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) install_core_release "$CORE_PIN"; pause ;;
      2) install_core_release latest; pause ;;
      3) install_core_local; pause ;;
      0|_) return ;;
    esac
  done
}


# ============================================================= CERTIFICATES
cert_cn() { openssl x509 -in "$1" -noout -subject 2>/dev/null | sed -nE 's/.*CN[[:space:]]*=[[:space:]]*([^,/]+).*/\1/p' | head -n1; }
cert_expiry_epoch() {
  local d
  d="$(openssl x509 -in "$1" -noout -enddate 2>/dev/null | cut -d= -f2)"
  [ -n "$d" ] || { echo 0; return; }
  date -d "$d" +%s 2>/dev/null || echo 0
}
cert_days_left() {
  local e
  e="$(cert_expiry_epoch "$1")"
  [ "$e" -gt 0 ] 2>/dev/null || { echo -1; return; }
  echo $(( (e-$(now_epoch))/86400 ))
}
cert_pair_matches() {
  local a b
  a="$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  b="$(openssl pkey -in "$2" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
  [ -n "$a" ] && [ "$a" = "$b" ]
}
cert_matches_host() {
  local cert="$1" host="$2" output
  # OpenSSL 3.0 on some distributions prints a hostname mismatch while still
  # returning status 0. Parse the canonical positive result instead of trusting
  # the process exit code so SAN validation behaves consistently everywhere.
  output="$(openssl x509 -in "$cert" -noout -checkhost "$host" 2>&1 || true)"
  printf '%s\n' "$output" | grep -Fq 'does match certificate'
}
CERT_PATHS=(); CERT_KEYS=(); CERT_NAMES=()
scan_certs() {
  CERT_PATHS=(); CERT_KEYS=(); CERT_NAMES=()
  local d c k cn cand i j dup
  for d in "$CERT_STORE"/*/ /etc/letsencrypt/live/*/ /root/cert/*/ /etc/ssl/panel/*/; do
    [ -d "$d" ] || continue
    c=""; k=""
    for cand in "$d/fullchain.pem" "$d/fullchain.crt" "$d/cert.pem" "$d/cert.crt" "$d"/*.crt; do
      [ -s "$cand" ] || continue
      c="$cand"; break
    done
    [ -n "$c" ] || continue
    for cand in "$d/privkey.pem" "$d/private.key" "$d/key.pem" "${c%.*}.key"; do
      [ -s "$cand" ] || continue
      k="$cand"; break
    done
    [ -n "$k" ] || continue
    cert_pair_matches "$c" "$k" || continue
    dup=0
    for i in "${!CERT_PATHS[@]}"; do [ "${CERT_PATHS[$i]}" = "$c" ] && dup=1; done
    [ "$dup" -eq 1 ] && continue
    cn="$(cert_cn "$c")"; [ -n "$cn" ] || cn="$(basename "${d%/}")"
    CERT_PATHS+=("$c"); CERT_KEYS+=("$k"); CERT_NAMES+=("$cn")
  done
}
local_ips() {
  ip -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | sort -u
}
domain_resolves_here() {
  local domain="$1" resolved localip hit=1
  DOMAIN_RESOLVED="$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ')"
  [ -n "$DOMAIN_RESOLVED" ] || return 2
  while read -r resolved; do
    [ -n "$resolved" ] || continue
    while read -r localip; do
      [ "$resolved" = "$localip" ] && hit=0
    done < <(local_ips)
  done < <(tr ' ' '\n' <<< "$DOMAIN_RESOLVED")
  return "$hit"
}
port80_free() { ! port_is_listening 80; }
port80_user() { port_owner 80; }
acme_bin() { printf '%s/.acme.sh/acme.sh' "${HOME:-/root}"; }
ensure_acme() {
  local domain="$1"
  [ -x "$(acme_bin)" ] && return 0
  info "installing acme.sh"
  curl -fsSL https://get.acme.sh | sh -s "email=admin@$domain" >/dev/null 2>&1
  [ -x "$(acme_bin)" ] || { bad "acme.sh installation failed"; return 1; }
}
internal_reload_cert() {
  local domain="${1:-}" n failed=0
  valid_domain "$domain" || exit 2
  ensure_dirs
  for n in $(tunnel_names); do
    load_meta "$n" >/dev/null 2>&1 || continue
    [ "$TLS_DOMAIN" = "$domain" ] || continue
    systemctl restart "$(service_name "$n")" >/dev/null 2>&1 || failed=1
  done
  sleep 1
  for n in $(tunnel_names); do
    load_meta "$n" >/dev/null 2>&1 || continue
    [ "$TLS_DOMAIN" = "$domain" ] || continue
    verify_tunnel_health "$n" >/dev/null 2>&1 || failed=1
  done
  exit "$failed"
}
issue_cert() {
  local domain="$1" rc out log reloadcmd
  valid_domain "$domain" || { bad "invalid certificate domain"; return 1; }
  info "checking DNS for $domain"
  domain_resolves_here "$domain"; rc=$?
  case "$rc" in
    0) ok "$domain resolves to this Gateway (${DOMAIN_RESOLVED% })" ;;
    2) bad "domain has no A/AAAA record"; return 1 ;;
    1) bad "domain resolves to ${DOMAIN_RESOLVED% }, not this Gateway"; return 1 ;;
  esac
  if ! port80_free; then
    bad "port 80 is busy; HTTP-01 cannot start"
    dim "$(port80_user)"
    return 1
  fi
  ensure_acme "$domain" || return 1
  out="$CERT_STORE/$domain"; mkdir -p "$out"; chmod 700 "$out"
  log="$(mktemp)" || return 1
  info "requesting Let's Encrypt certificate"
  if ! "$(acme_bin)" --issue -d "$domain" --standalone --server letsencrypt --keylength ec-256 >"$log" 2>&1; then
    bad "certificate issuance failed"
    tail -n 10 "$log" | sed 's/^/    /'
    rm -f "$log"; return 1
  fi
  rm -f "$log"
  reloadcmd="$CMD_PATH --internal-reload-cert $domain"
  if ! "$(acme_bin)" --install-cert -d "$domain" --ecc \
      --fullchain-file "$out/fullchain.pem" \
      --key-file "$out/privkey.pem" \
      --reloadcmd "$reloadcmd" >/dev/null 2>&1; then
    bad "certificate issued but installation failed"
    return 1
  fi
  chmod 600 "$out/privkey.pem"; chmod 644 "$out/fullchain.pem"
  cert_pair_matches "$out/fullchain.pem" "$out/privkey.pem" || { bad "installed cert/key mismatch"; return 1; }
  cert_matches_host "$out/fullchain.pem" "$domain" || { bad "certificate SAN does not match domain"; return 1; }
  TLS_CERT="$out/fullchain.pem"; TLS_KEY="$out/privkey.pem"
  ok "certificate ready and auto-renew enabled"
}
make_self_signed() {
  local domain="$1" out="$2" cfg
  mkdir -p "$out"; cfg="$(mktemp)" || return 1
  cat > "$cfg" <<EOF
[req]
distinguished_name=req_dn
x509_extensions=v3_req
prompt=no
[req_dn]
CN=$domain
[v3_req]
subjectAltName=DNS:$domain
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
    -keyout "$out/privkey.pem" -out "$out/fullchain.pem" -config "$cfg" >/dev/null 2>&1
  local rc=$?; rm -f "$cfg"
  [ "$rc" -eq 0 ] || return 1
  chmod 600 "$out/privkey.pem"; chmod 644 "$out/fullchain.pem"
  TLS_CERT="$out/fullchain.pem"; TLS_KEY="$out/privkey.pem"
}
choose_certificate() {
  local domain="$1" allow_self="$2" i days choice
  TLS_CERT=""; TLS_KEY=""
  scan_certs
  while :; do
    top; sect "CERTIFICATE — KHAREJ GATEWAY"; blank
    row "$(printf '%sDomain:%s %s' "$D" "$N" "$domain")"
    if [ "${#CERT_PATHS[@]}" -gt 0 ]; then
      for i in "${!CERT_PATHS[@]}"; do
        days="$(cert_days_left "${CERT_PATHS[$i]}")"
        if cert_matches_host "${CERT_PATHS[$i]}" "$domain"; then
          row "$(printf '%s[%d]%s %-25s %s%sd left%s' "$Y" "$((i+1))" "$N" "${CERT_NAMES[$i]:0:25}" "$G" "$days" "$N")"
        else
          row "$(printf '%s[%d]%s %-25s %sSAN mismatch%s' "$Y" "$((i+1))" "$N" "${CERT_NAMES[$i]:0:25}" "$R" "$N")"
        fi
      done
    else
      row "$(printf '%sNo certificate pairs found%s' "$D" "$N")"
    fi
    blank
    item i "Get Let's Encrypt" "issue for domain now"
    [ "$allow_self" = 1 ] && item s "Create self-signed" "test mode only"
    item m "Enter paths manually" ""
    item 0 "Back" ""
    bot; echo
    read -r -p "$(printf '  %s>%s Select: ' "$C" "$N")" choice
    case "$choice" in
      i|I) issue_cert "$domain" && return 0 ;;
      s|S)
        [ "$allow_self" = 1 ] || { bad "pair code requires a trusted certificate"; pause; continue; }
        make_self_signed "$domain" "$CERT_STORE/$domain-selfsigned" || { bad "self-signed generation failed"; return 1; }
        ok "self-signed test certificate created"; return 0
        ;;
      m|M)
        ask "certificate path"; TLS_CERT="$ANS"
        ask "private key path"; TLS_KEY="$ANS"
        safe_path_value "$TLS_CERT" && safe_path_value "$TLS_KEY" && [ -s "$TLS_CERT" ] && [ -s "$TLS_KEY" ] || {
          bad "certificate/key file not found"; continue;
        }
        cert_pair_matches "$TLS_CERT" "$TLS_KEY" || { bad "certificate and key do not match"; continue; }
        if ! cert_matches_host "$TLS_CERT" "$domain"; then
          [ "$allow_self" = 1 ] || { bad "certificate SAN does not match $domain"; continue; }
          warn "certificate SAN mismatch accepted only because Pair Code is test/insecure"
        fi
        return 0
        ;;
      0) return 1 ;;
      *)
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#CERT_PATHS[@]}" ]; then
          i=$((choice-1))
          days="$(cert_days_left "${CERT_PATHS[$i]}")"
          [ "$days" -gt 1 ] || { bad "certificate is expired or expires too soon"; continue; }
          if ! cert_matches_host "${CERT_PATHS[$i]}" "$domain"; then
            [ "$allow_self" = 1 ] || { bad "certificate SAN mismatch"; continue; }
            warn "SAN mismatch accepted only for insecure test mode"
          fi
          TLS_CERT="${CERT_PATHS[$i]}"; TLS_KEY="${CERT_KEYS[$i]}"
          return 0
        fi
        bad "invalid selection"
        ;;
    esac
  done
}


# =============================================================== CREATION ===
partial_cleanup() { find "$TUN_DIR" -mindepth 1 -maxdepth 1 -type d -name '.partial-*' -mmin +30 -exec rm -rf {} + 2>/dev/null || true; }
tunnel_exists() { [ -d "$TUN_DIR/$1" ]; }
summarize_loaded() {
  top; sect "REVIEW"; blank
  kv "name" "$NAME"
  kv "role" "$ROLE"
  kv "gateway" "$GATEWAY_HOST"
  kv "target" "$TARGET_HOST"
  kv "transport" "$TRANSPORT"
  kv "profile" "$PROFILE"
  kv "mappings" "$(mapping_count "$MAPS")"
  [ -n "$TLS_DOMAIN" ] && kv "TLS domain" "$TLS_DOMAIN"
  [ -n "$WS_PATH" ] && kv "WS path" "$WS_PATH"
  kv "nofile" "$NOFILE"
  blank
  row "$D Port mapping: public>target@backbone $N"
  while read -r _line; do row "$_line"; done < <(mapping_summary "$MAPS")
  bot
}
commit_new_tunnel() {
  local stage="$1" final="$TUN_DIR/$NAME"
  tunnel_exists "$NAME" && { bad "tunnel already exists"; return 1; }
  validate_meta || return 1
  write_meta_to "$stage" || return 1
  generate_config_to "$stage" || return 1
  validate_config_file "$stage/config.toml" "$(mapping_count "$MAPS")" || return 1
  mv "$stage" "$final" || return 1
  write_unit_dropin "$NAME"
  set_restart_timer "$NAME" "$SCHEDULE" || true
  if start_tunnel "$NAME"; then
    ok "tunnel $NAME created"
    return 0
  fi
  warn "creation failed health verification; removing partial tunnel"
  stop_tunnel_hard "$NAME"
  rm -rf "$final" "/etc/systemd/system/dark-realm@${NAME}.service.d"
  systemctl daemon-reload >/dev/null 2>&1 || true
  return 1
}
screen_new_edge() {
  header "NEW TUNNEL — IRAN EDGE"
  [ -x "$BIN_PATH" ] || { bad "install the Realm core first"; pause; return; }
  reset_meta; ROLE=edge
  local input base stage
  ask "tunnel name"; NAME="$ANS"
  valid_name "$NAME" || { bad "use letters, numbers, _ or - (max 32)"; pause; return; }
  tunnel_exists "$NAME" && { bad "tunnel already exists"; pause; return; }
  ask "KHAREJ Gateway IP/domain"; GATEWAY_HOST="${ANS,,}"
  valid_host "$GATEWAY_HOST" || { bad "invalid Gateway host"; pause; return; }
  ask "local target host on KHAREJ" "127.0.0.1"; TARGET_HOST="${ANS,,}"
  valid_host "$TARGET_HOST" || { bad "invalid target host"; pause; return; }
  ask "backbone base port on KHAREJ" "$DEFAULT_GATEWAY_PORT"; base="$ANS"
  valid_port "$base" || { bad "invalid backbone port"; pause; return; }
  echo
  dim "Examples: 443 | 443,2053,2083 | 2000-2100 | 443>8000,2053>8000"
  ask "public ports / mappings"; input="$ANS"
  expand_mappings "$input" "$base" || { pause; return; }
  MAPS="$CANON_MAPS"
  pick_transport || return
  configure_transport_edge || { pause; return; }
  pick_profile || { pause; return; }
  ask "listen address" "0.0.0.0"; BIND_ADDR="$ANS"
  valid_bind "$BIND_ADDR" || { bad "invalid listen address"; pause; return; }
  CREATED_AT="$(now_epoch)"
  check_port_conflicts_loaded || { pause; return; }
  summarize_loaded
  yesno "create this IRAN Edge tunnel?" y || { info "cancelled"; pause; return; }
  stage="$TUN_DIR/.partial-${NAME}-$$"; rm -rf "$stage"; mkdir -p "$stage"; chmod 700 "$stage"
  if commit_new_tunnel "$stage"; then
    echo
    top; sect "PAIR CODE — paste on KHAREJ"; blank
    row "$Y$(generate_pair_code)$N"
    blank; row "$DThis code contains deployment metadata only; no private key.$N"; bot
  fi
  pause
}
screen_new_gateway() {
  header "NEW TUNNEL — KHAREJ GATEWAY"
  [ -x "$BIN_PATH" ] || { bad "install the Realm core first"; pause; return; }
  local code stage
  ask "paste DR1 Pair Code"; code="$ANS"
  parse_pair_code "$code" || { pause; return; }
  apply_pair_to_meta
  tunnel_exists "$NAME" && { bad "tunnel already exists: $NAME"; pause; return; }
  # The Pair Code's Gateway is informational; this server must own the listener.
  if [ "$TRANSPORT" = tls ] || [ "$TRANSPORT" = wss ]; then
    choose_certificate "$TLS_DOMAIN" "$TLS_INSECURE" || { info "certificate selection cancelled"; pause; return; }
  fi
  ask "backbone listen address" "0.0.0.0"; BIND_ADDR="$ANS"
  valid_bind "$BIND_ADDR" || { bad "invalid listen address"; pause; return; }
  check_port_conflicts_loaded || { pause; return; }
  check_target_ports_loaded || {
    yesno "continue while one or more local targets are offline?" n || { pause; return; }
  }
  summarize_loaded
  yesno "create this KHAREJ Gateway tunnel?" y || { info "cancelled"; pause; return; }
  stage="$TUN_DIR/.partial-${NAME}-$$"; rm -rf "$stage"; mkdir -p "$stage"; chmod 700 "$stage"
  commit_new_tunnel "$stage"
  pause
}

# ================================================================ PICKER ===
SELECTED=""
pick_tunnel() {
  local -a names=()
  local n i=1 choice
  while read -r n; do [ -n "$n" ] && names+=("$n"); done < <(tunnel_names)
  [ "${#names[@]}" -gt 0 ] || { bad "no tunnels found"; return 1; }
  top; sect "SELECT TUNNEL"; blank
  for n in "${names[@]}"; do
    load_meta "$n" >/dev/null 2>&1 || continue
    row "$(printf '%s[%d]%s %-24s %s%-8s%s %s%s%s' "$Y" "$i" "$N" "$n" "$M" "$ROLE" "$N" "$D" "$TRANSPORT" "$N")"
    i=$((i+1))
  done
  item 0 "Back" ""
  bot; echo
  read -r -p "$(printf '  %s>%s Select: ' "$C" "$N")" choice
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  [ "$choice" -ge 1 ] && [ "$choice" -le "${#names[@]}" ] || return 1
  SELECTED="${names[$((choice-1))]}"
}
role_label() { [ "$1" = edge ] && echo "IRAN EDGE" || echo "KHAREJ GATEWAY"; }
format_duration() {
  local s="${1:-0}" d h m
  d=$((s/86400)); h=$(((s%86400)/3600)); m=$(((s%3600)/60))
  [ "$d" -gt 0 ] && printf '%dd %dh' "$d" "$h" || printf '%dh %dm' "$h" "$m"
}
session_count_loaded() {
  local ports snapshot
  if [ "$ROLE" = edge ]; then ports="$(mapping_public_ports "$MAPS" | paste -sd, -)"; else ports="$(mapping_backbone_ports "$MAPS" | paste -sd, -)"; fi
  [ -n "$ports" ] || { echo 0; return; }
  snapshot="$(mktemp)" || { echo 0; return; }
  ss -Htan state established 2>/dev/null > "$snapshot"
  python3 - "$ports" "$snapshot" <<'PY'
import re, sys
ports={int(x) for x in sys.argv[1].split(",") if x}
count=0
for line in open(sys.argv[2], errors="ignore"):
    found={int(x) for x in re.findall(r'(?::|\])(\d+)(?:\s|$)', line)}
    if found & ports:
        count += 1
print(count)
PY
  rm -f "$snapshot"
}
socket_bytes_loaded() {
  local ports state="$RUNTIME_DIR/$NAME.traffic" snapshot
  if [ "$ROLE" = edge ]; then ports="$(mapping_public_ports "$MAPS" | paste -sd, -)"; else ports="$(mapping_backbone_ports "$MAPS" | paste -sd, -)"; fi
  snapshot="$(mktemp)" || { echo '0 0 0 0'; return; }
  ss -tinH 2>/dev/null > "$snapshot"
  python3 - "$ports" "$state" "$snapshot" <<'PY'
import json, os, re, sys, time
ports={int(x) for x in sys.argv[1].split(",") if x}
state=sys.argv[2]; snapshot=sys.argv[3]
records=[]; active=False; rx=tx=0
for line in open(snapshot, errors="ignore"):
    if line and not line[0].isspace():
        if active: records.append((rx,tx))
        nums={int(x) for x in re.findall(r'(?::|\])(\d+)(?:\s|$)', line)}
        active=bool(nums & ports); rx=tx=0
    if active:
        m=re.search(r'\bbytes_received:(\d+)', line)
        if m: rx=int(m.group(1))
        m=re.search(r'\bbytes_sent:(\d+)', line)
        if m: tx=int(m.group(1))
if active: records.append((rx,tx))
now=time.time(); rx=sum(x for x,_ in records); tx=sum(x for _,x in records)
old=None
try: old=json.load(open(state))
except Exception: pass
os.makedirs(os.path.dirname(state), exist_ok=True)
tmp=state+".tmp"
with open(tmp,"w") as fh: json.dump({"t":now,"rx":rx,"tx":tx}, fh)
os.replace(tmp,state)
if not old or now <= old.get("t",0):
    print(f"{rx} {tx} 0 0")
else:
    dt=max(now-old["t"],.1)
    print(f"{rx} {tx} {max(0,rx-old['rx'])*8/dt:.0f} {max(0,tx-old['tx'])*8/dt:.0f}")
PY
  rm -f "$snapshot"
}
human_bits() {
  python3 - "${1:-0}" <<'PY'
import sys
v=float(sys.argv[1]); u=["bps","Kbps","Mbps","Gbps"]; i=0
while v>=1000 and i<len(u)-1: v/=1000; i+=1
print(f"{v:.1f} {u[i]}")
PY
}


# ================================================================ MANAGE ===
show_tunnel_header() {
  local name="$1" state pid uptime sessions
  load_meta "$name" || return 1
  if service_active "$name"; then state="$G ACTIVE $N"; else state="$R DOWN $N"; fi
  pid="$(service_pid "$name")"; uptime="$(service_uptime "$name")"; sessions="$(session_count_loaded)"
  top; sect "$(role_label "$ROLE") — $name"; blank
  kv "status" "$state"
  kv "PID / uptime" "${pid:-0} / $(format_duration "$uptime")"
  kv "transport" "$TRANSPORT"
  kv "gateway" "$GATEWAY_HOST"
  kv "profile" "$PROFILE"
  kv "endpoints" "$(mapping_count "$MAPS")"
  kv "sessions" "$sessions"
  [ -n "$TLS_DOMAIN" ] && kv "TLS domain" "$TLS_DOMAIN"
  bot
}
save_current_then_regen() {
  local name="$1"
  validate_meta || return 1
  transactional_regen "$name"
}
edit_ports_edge() {
  local name="$1" input base oldmaps oldports p
  load_meta "$name" || return
  [ "$ROLE" = edge ] || { bad "port mappings are controlled by the IRAN Edge Pair Code"; pause; return; }
  oldmaps="$MAPS"; oldports="$(mapping_public_ports "$oldmaps" | paste -sd, -)"
  ask "new backbone base port" "$(mapping_backbone_ports "$MAPS" | head -n1)"; base="$ANS"
  valid_port "$base" || { bad "invalid base port"; pause; return; }
  dim "Examples: 443 | 443,2053 | 2000-2100 | 443>8000,2053>8000"
  ask "new public mappings"; input="$ANS"
  expand_mappings "$input" "$base" || { pause; return; }
  MAPS="$CANON_MAPS"
  while read -r p; do
    [ -n "$p" ] || continue
    if port_is_listening "$p" && ! tr ',' '\n' <<< "$oldports" | grep -qx "$p"; then
      bad "new public port $p is already in use"; MAPS="$oldmaps"; pause; return
    fi
  done < <(mapping_public_ports "$MAPS")
  summarize_loaded
  yesno "apply mappings and generate a new Pair Code?" n || { MAPS="$oldmaps"; return; }
  save_current_then_regen "$name" || { pause; return; }
  echo
  top; sect "NEW PAIR CODE"; blank; row "$Y$(generate_pair_code)$N"; bot
  pause
}
edit_profile() {
  local name="$1"
  load_meta "$name" || return
  pick_profile || return
  save_current_then_regen "$name"; pause
}
edit_endpoint() {
  local name="$1"
  load_meta "$name" || return
  if [ "$ROLE" = edge ]; then
    ask "KHAREJ Gateway IP/domain" "$GATEWAY_HOST"; GATEWAY_HOST="${ANS,,}"
    valid_host "$GATEWAY_HOST" || { bad "invalid Gateway host"; pause; return; }
  else
    ask "local target host" "$TARGET_HOST"; TARGET_HOST="${ANS,,}"
    valid_host "$TARGET_HOST" || { bad "invalid target host"; pause; return; }
  fi
  save_current_then_regen "$name"; pause
}
edit_transport() {
  local name="$1" old_transport old_cert old_key
  load_meta "$name" || return
  old_transport="$TRANSPORT"; old_cert="$TLS_CERT"; old_key="$TLS_KEY"
  pick_transport || return
  if [ "$ROLE" = edge ]; then
    configure_transport_edge || { TRANSPORT="$old_transport"; return; }
  else
    # Gateway transport changes should normally arrive from an updated Pair Code.
    if [ "$TRANSPORT" = tls ] || [ "$TRANSPORT" = wss ]; then
      [ -n "$TLS_DOMAIN" ] || { ask "TLS domain"; TLS_DOMAIN="${ANS,,}"; SNI="$TLS_DOMAIN"; }
      choose_certificate "$TLS_DOMAIN" "$TLS_INSECURE" || { TRANSPORT="$old_transport"; TLS_CERT="$old_cert"; TLS_KEY="$old_key"; return; }
    else
      TLS_CERT=""; TLS_KEY=""
    fi
    if [ "$TRANSPORT" = ws ] || [ "$TRANSPORT" = wss ]; then
      ask "WebSocket Host" "${WS_HOST:-$TLS_DOMAIN}"; WS_HOST="${ANS,,}"
      ask "WebSocket Path" "${WS_PATH:-$(random_path)}"; WS_PATH="$ANS"
      valid_domain "$WS_HOST" && valid_ws_path "$WS_PATH" || { bad "invalid WS settings"; pause; return; }
    fi
  fi
  save_current_then_regen "$name" || { pause; return; }
  if [ "$ROLE" = edge ]; then
    warn "apply the new Pair Code on KHAREJ before production traffic"
    top; sect "UPDATED PAIR CODE"; blank; row "$Y$(generate_pair_code)$N"; bot
  fi
  pause
}
import_pair_gateway() {
  local name="$1" code olddir="$TUN_DIR/$1" backup
  load_meta "$name" || return
  [ "$ROLE" = gateway ] || { bad "only KHAREJ Gateway imports Pair Codes"; pause; return; }
  ask "paste updated DR1 Pair Code"; code="$ANS"
  parse_pair_code "$code" || { pause; return; }
  [ "$PAIR_NAME" = "$name" ] || { bad "Pair Code belongs to $PAIR_NAME, not $name"; pause; return; }
  backup="$olddir/backups/pair-import-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"; cp -a "$olddir/config.toml" "$olddir/meta.conf" "$backup/"
  apply_pair_to_meta
  if [ "$TRANSPORT" = tls ] || [ "$TRANSPORT" = wss ]; then
    choose_certificate "$TLS_DOMAIN" "$TLS_INSECURE" || { info "cancelled"; pause; return; }
  fi
  BIND_ADDR="0.0.0.0"
  save_current_then_regen "$name" || {
    cp -af "$backup/"* "$olddir/" 2>/dev/null || true
    pause; return
  }
  pause
}
edit_schedule() {
  local name="$1"
  load_meta "$name" || return
  top; sect "SCHEDULED RESTART"; blank
  item 1 "Off" ""; item 2 "Every 1 hour" ""; item 3 "Every 6 hours" ""; item 4 "Every 12 hours" ""; item 5 "Every 24 hours" ""
  bot; echo; getkey
  case "$KEY" in 2) SCHEDULE=1h;; 3) SCHEDULE=6h;; 4) SCHEDULE=12h;; 5) SCHEDULE=24h;; *) SCHEDULE=off;; esac
  write_meta_to "$TUN_DIR/$name"
  set_restart_timer "$name" "$SCHEDULE"
  ok "scheduled restart: $SCHEDULE"; pause
}
show_config() {
  local name="$1"
  header "CONFIG — $name"
  sed 's/^/    /' "$TUN_DIR/$name/config.toml"
  echo; dim "fingerprint: $(config_fingerprint "$name")"; pause
}
edit_toml_manual() {
  local name="$1" file="$TUN_DIR/$1/config.toml" backup editor
  load_meta "$name" || return
  backup="$file.manual.$(date +%s).bak"; cp -a "$file" "$backup"
  editor="${EDITOR:-nano}"
  command -v "$editor" >/dev/null 2>&1 || editor=vi
  "$editor" "$file"
  if ! validate_config_file "$file" "$(mapping_count "$MAPS")"; then
    bad "invalid config; restoring backup"; cp -af "$backup" "$file"; pause; return
  fi
  if ! restart_tunnel "$name"; then
    bad "service failed; restoring backup"; cp -af "$backup" "$file"; systemctl restart "$(service_name "$name")" >/dev/null 2>&1 || true
  else
    ok "manual config accepted"
  fi
  pause
}
backup_tunnel() {
  local name="$1" out="$BACKUP_DIR/${name}-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -C "$TUN_DIR" -czf "$out" "$name" || { bad "backup failed"; return 1; }
  chmod 600 "$out"; ok "backup: $out"
}
restore_tunnel_backup() {
  local name="$1" -a files=() f choice tmp current
  while read -r f; do files+=("$f"); done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${name}-*.tar.gz" | sort -r)
  [ "${#files[@]}" -gt 0 ] || { bad "no backup archive found"; pause; return; }
  top; sect "RESTORE $name"; blank
  for choice in "${!files[@]}"; do row "$(printf '%s[%d]%s %s' "$Y" "$((choice+1))" "$N" "$(basename "${files[$choice]}")")"; done
  item 0 "Back" ""; bot; echo
  read -r -p "$(printf '  %s>%s Select: ' "$C" "$N")" choice
  [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ] || return
  f="${files[$((choice-1))]}"; tmp="$(mktemp -d)"
  tar -tzf "$f" | grep -Eq '(^/|(^|/)\.\.(/|$))' && { bad "unsafe archive"; rm -rf "$tmp"; pause; return; }
  tar -xzf "$f" -C "$tmp" || { rm -rf "$tmp"; bad "extract failed"; pause; return; }
  [ -s "$tmp/$name/config.toml" ] && [ -s "$tmp/$name/meta.conf" ] || { rm -rf "$tmp"; bad "invalid archive"; pause; return; }
  current="$TUN_DIR/$name.before-restore.$(date +%s)"; cp -a "$TUN_DIR/$name" "$current"
  stop_tunnel_hard "$name"; rm -rf "$TUN_DIR/$name"; mv "$tmp/$name" "$TUN_DIR/$name"; rm -rf "$tmp"
  if load_meta "$name" && validate_config_file "$TUN_DIR/$name/config.toml" "$(mapping_count "$MAPS")" && start_tunnel "$name"; then
    ok "restored"
  else
    bad "restore failed; rolling back"
    stop_tunnel_hard "$name"; rm -rf "$TUN_DIR/$name"; mv "$current" "$TUN_DIR/$name"; start_tunnel "$name" >/dev/null 2>&1 || true
  fi
  pause
}
delete_tunnel() {
  local name="$1"
  load_meta "$name" || return
  warn "this removes the service and tunnel config; shared certificates are preserved"
  ask "type the tunnel name to confirm"; [ "$ANS" = "$name" ] || { info "cancelled"; pause; return; }
  stop_tunnel_hard "$name"; set_restart_timer "$name" off
  rm -rf "$TUN_DIR/$name" "/etc/systemd/system/dark-realm@${name}.service.d" "/etc/systemd/system/dark-realm-restart@${name}.timer.d"
  systemctl daemon-reload >/dev/null 2>&1 || true
  ok "deleted $name"; pause
}
screen_tunnel() {
  local name="$1"
  while tunnel_exists "$name"; do
    header "MANAGE TUNNEL"
    show_tunnel_header "$name" || { pause; return; }
    mid; sect "CONTROL"
    item 1 "Start" ""; item 2 "Stop" ""; item 3 "Restart" ""
    load_meta "$name" || return
    if [ "$ROLE" = edge ]; then mid; sect "PAIRING"; item p "Pair Code" "paste on KHAREJ"; fi
    if [ "$ROLE" = gateway ]; then mid; sect "PAIRING"; item p "Import Pair Code" "update from IRAN"; fi
    mid; sect "CONFIGURE"
    [ "$ROLE" = edge ] && item 4 "Ports / mappings" ""
    item 5 "Performance profile" ""
    item 6 "Endpoint" ""
    item 7 "Transport / TLS" ""
    item r "Scheduled restart" "$SCHEDULE"
    mid; sect "INSPECT"
    item 8 "Show config" ""
    item l "Logs + connections" ""
    item f "Fingerprint" ""
    mid; sect "ADVANCED"
    item b "Backup" ""; item o "Restore" ""; item e "Edit TOML" ""; item d "Delete tunnel" ""
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) systemctl start "$(service_name "$name")"; sleep 1; verify_tunnel_health "$name"; pause ;;
      2) systemctl stop "$(service_name "$name")"; ok "stopped"; pause ;;
      3) restart_tunnel "$name"; pause ;;
      p|P)
        load_meta "$name" || continue
        if [ "$ROLE" = edge ]; then top; sect "PAIR CODE"; blank; row "$Y$(generate_pair_code)$N"; bot; pause
        else import_pair_gateway "$name"; fi
        ;;
      4) edit_ports_edge "$name" ;;
      5) edit_profile "$name" ;;
      6) edit_endpoint "$name" ;;
      7) edit_transport "$name" ;;
      r|R) edit_schedule "$name" ;;
      8) show_config "$name" ;;
      l|L) screen_logs "$name" ;;
      f|F) header "FINGERPRINT — $name"; dim "$(config_fingerprint "$name")"; pause ;;
      b|B) backup_tunnel "$name"; pause ;;
      o|O) restore_tunnel_backup "$name" ;;
      e|E) edit_toml_manual "$name" ;;
      d|D) delete_tunnel "$name" ;;
      0|_) return ;;
    esac
  done
}
screen_manage() {
  while :; do
    header "MANAGE TUNNELS"
    pick_tunnel || return
    screen_tunnel "$SELECTED"
  done
}


# ============================================================= DASHBOARD ===
screen_dashboard() {
  while :; do
    header "DASHBOARD"
    local n state pid up sessions bytes rx tx certdays
    top; sect "LIVE TUNNELS"; blank
    if [ "$(tunnel_count)" -eq 0 ]; then
      row "$D No tunnels configured $N"
    else
      for n in $(tunnel_names); do
        load_meta "$n" >/dev/null 2>&1 || continue
        if service_active "$n"; then state="$G●$N"; else state="$R●$N"; fi
        pid="$(service_pid "$n")"; up="$(service_uptime "$n")"; sessions="$(session_count_loaded)"
        bytes="$(socket_bytes_loaded 2>/dev/null || echo '0 0 0 0')"
        rx="$(awk '{print $3}' <<< "$bytes")"; tx="$(awk '{print $4}' <<< "$bytes")"
        row "$(printf '%s %-17s %s%-7s%s %s%-4s%s RX %-11s TX %-11s' "$state" "$n" "$M" "$TRANSPORT" "$N" "$W" "$sessions" "$N" "$(human_bits "$rx")" "$(human_bits "$tx")")"
        row "$(printf '  %s%s · PID %s · %s · %s endpoints%s' "$D" "$(role_label "$ROLE")" "$pid" "$(format_duration "$up")" "$(mapping_count "$MAPS")" "$N")"
        if [ -n "$TLS_CERT" ] && [ -s "$TLS_CERT" ]; then
          certdays="$(cert_days_left "$TLS_CERT")"
          row "$(printf '  %sTLS %s · %sd remaining%s' "$D" "$TLS_DOMAIN" "$certdays" "$N")"
        fi
        blank
      done
    fi
    bot
    echo
    dim "traffic attribution is derived from kernel TCP socket counters (best effort)"
    printf '\n  %s[r]%s refresh   %s[0]%s back\n\n' "$Y" "$N" "$Y" "$N"
    getkey
    case "$KEY" in 0|_) return;; *) :;; esac
  done
}

# ============================================================ DIAGNOSTICS ===
tcp_probe_ms() {
  python3 - "$1" "$2" <<'PY'
import socket, sys, time
host=sys.argv[1]; port=int(sys.argv[2]); start=time.perf_counter()
try:
    with socket.create_connection((host,port), timeout=4): pass
    print(int((time.perf_counter()-start)*1000))
except OSError:
    print(-1)
PY
}
tls_probe_loaded() {
  [ "$TRANSPORT" = tls ] || [ "$TRANSPORT" = wss ] || { info "not a TLS transport"; return 0; }
  local port
  port="$(mapping_backbone_ports "$MAPS" | head -n1)"
  info "TLS handshake to $GATEWAY_HOST:$port with SNI $SNI"
  timeout 10 openssl s_client -connect "$GATEWAY_HOST:$port" -servername "$SNI" -verify_return_error </dev/null 2>&1 \
    | grep -E 'subject=|issuer=|Verify return code|Verification error' | sed 's/^/    /'
}
health_report() {
  local name="$1" p ms
  load_meta "$name" || return 1
  header "HEALTH — $name"
  service_active "$name" && ok "systemd service active" || bad "systemd service inactive"
  [ -x "$BIN_PATH" ] && ok "Realm core: $(core_version_short)" || bad "Realm core missing"
  validate_config_file "$TUN_DIR/$name/config.toml" "$(mapping_count "$MAPS")" && ok "generated TOML structure valid" || true
  while read -r p; do
    port_is_listening "$p" && ok "listener $p active" || bad "listener $p missing"
  done < <(expected_ports_loaded)
  if [ "$ROLE" = edge ]; then
    p="$(mapping_backbone_ports "$MAPS" | head -n1)"
    ms="$(tcp_probe_ms "$GATEWAY_HOST" "$p")"
    [ "$ms" -ge 0 ] && ok "Gateway TCP reachability: ${ms}ms" || bad "Gateway unreachable: $GATEWAY_HOST:$p"
    tls_probe_loaded
  else
    while read -r p; do
      port_is_listening "$p" && ok "local target $TARGET_HOST:$p listening" || warn "local target $TARGET_HOST:$p not detected"
    done < <(mapping_target_ports "$MAPS" | sort -nu)
    if [ -n "$TLS_CERT" ]; then
      cert_pair_matches "$TLS_CERT" "$TLS_KEY" && ok "certificate and private key match" || bad "certificate/key mismatch"
      cert_matches_host "$TLS_CERT" "$TLS_DOMAIN" && ok "certificate SAN matches $TLS_DOMAIN" || bad "certificate SAN mismatch"
      ok "certificate expires in $(cert_days_left "$TLS_CERT") days"
    fi
  fi
  echo
  journalctl -u "$(service_name "$name")" -n 15 --no-pager -o cat 2>/dev/null | sed 's/^/    /'
}
screen_logs() {
  local name="$1"
  while :; do
    header "LOGS + CONNECTIONS — $name"
    load_meta "$name" || return
    top; sect "INSPECT"; blank
    item 1 "Live log" "Ctrl+C returns"
    item 2 "Last 80 lines" ""
    item 3 "Connections" "kernel sockets"
    item 4 "Health report" ""
    item 5 "TLS handshake" ""
    item 6 "Tunnel throughput" "iperf3 helper"
    item 7 "Redacted export" ""
    item 8 "Toggle debug logs" ""
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) clear; journalctl -u "$(service_name "$name")" -f -n 40 --no-pager; pause ;;
      2) header "RECENT LOG — $name"; journalctl -u "$(service_name "$name")" -n 80 --no-pager -o cat | sed 's/^/    /'; pause ;;
      3)
        header "CONNECTIONS — $name"
        local ports
        if [ "$ROLE" = edge ]; then ports="$(mapping_public_ports "$MAPS" | paste -sd'|' -)"; else ports="$(mapping_backbone_ports "$MAPS" | paste -sd'|' -)"; fi
        ss -Htanp 2>/dev/null | grep -E ":($ports)([[:space:]]|$)" | head -n 200 | sed 's/^/    /'
        pause
        ;;
      4) health_report "$name"; pause ;;
      5) header "TLS — $name"; tls_probe_loaded; pause ;;
      6) throughput_menu "$name" ;;
      7) export_diagnostics "$name"; pause ;;
      8)
        [ "$LOG_LEVEL" = debug ] && LOG_LEVEL=warn || LOG_LEVEL=debug
        transactional_regen "$name"; pause
        ;;
      0|_) return ;;
    esac
  done
}
export_diagnostics() {
  local name="$1" out="$BACKUP_DIR/${name}-diagnostics-$(date +%Y%m%d-%H%M%S).txt"
  load_meta "$name" || return 1
  {
    echo "DARK REALM PRO diagnostics"
    echo "timestamp=$(date -Is)"
    echo "script=$SCRIPT_VER core=$(core_version_short)"
    echo "name=$NAME role=$ROLE transport=$TRANSPORT profile=$PROFILE"
    echo "gateway=$GATEWAY_HOST target=$TARGET_HOST maps=$MAPS"
    echo "tls_domain=$TLS_DOMAIN tls_cert=$TLS_CERT tls_key=[REDACTED]"
    echo "fingerprint=$(config_fingerprint "$name")"
    echo
    systemctl status "$(service_name "$name")" --no-pager -l 2>&1 || true
    echo
    ss -lntp 2>&1 || true
    echo
    journalctl -u "$(service_name "$name")" -n 100 --no-pager -o cat 2>&1 || true
  } > "$out"
  chmod 600 "$out"
  ok "redacted diagnostics: $out"
}

# ---------------------------------------------- true tunnel throughput helper
speed_payload_loaded() {
  cat <<EOF
schema=1
gateway=$GATEWAY_HOST
transport=$TRANSPORT
tls_insecure=$TLS_INSECURE
sni=$SNI
alpn=$ALPN
ws_host=$WS_HOST
ws_path=$WS_PATH
ws_mask=$WS_MASK
test_port=$SPEED_BACKBONE
created=$(now_epoch)
EOF
}
generate_speed_code() {
  local payload encoded sum
  payload="$(speed_payload_loaded)"; encoded="$(printf '%s' "$payload" | b64url_enc)"; sum="$(sha256_text "$payload")"
  printf 'DRS1.%s.%s' "$encoded" "$sum"
}
parse_speed_code() {
  local code="$1" p enc sum extra payload actual k v
  SPEED_GATEWAY=""; SPEED_TRANSPORT=""; SPEED_TLS_INSECURE=0; SPEED_SNI=""; SPEED_ALPN=""
  SPEED_WS_HOST=""; SPEED_WS_PATH=""; SPEED_WS_MASK=skipped; SPEED_BACKBONE=""
  IFS='.' read -r p enc sum extra <<< "$code"
  [ "$p" = DRS1 ] && [ -z "${extra:-}" ] && [[ "$sum" =~ ^[a-f0-9]{64}$ ]] || return 1
  payload="$(b64url_dec "$enc")" || return 1
  actual="$(sha256_text "$payload")"; [ "$actual" = "$sum" ] || return 1
  while IFS='=' read -r k v; do
    case "$k" in
      schema) [ "$v" = 1 ] || return 1 ;;
      gateway) SPEED_GATEWAY="$v" ;;
      transport) SPEED_TRANSPORT="$v" ;;
      tls_insecure) SPEED_TLS_INSECURE="$v" ;;
      sni) SPEED_SNI="$v" ;;
      alpn) SPEED_ALPN="$v" ;;
      ws_host) SPEED_WS_HOST="$v" ;;
      ws_path) SPEED_WS_PATH="$v" ;;
      ws_mask) SPEED_WS_MASK="$v" ;;
      test_port) SPEED_BACKBONE="$v" ;;
      created) [[ "$v" =~ ^[0-9]+$ ]] || return 1 ;;
      *) return 1 ;;
    esac
  done <<< "$payload"
  valid_host "$SPEED_GATEWAY" && valid_transport "$SPEED_TRANSPORT" && valid_port "$SPEED_BACKBONE" && valid_bool "$SPEED_TLS_INSECURE"
}
ensure_iperf() {
  command -v iperf3 >/dev/null 2>&1 && return 0
  info "installing iperf3"
  case "$(pkg_mgr)" in
    apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iperf3 >/dev/null 2>&1 ;;
    dnf) dnf install -y iperf3 >/dev/null 2>&1 ;;
    yum) yum install -y iperf3 >/dev/null 2>&1 ;;
    apk) apk add --no-cache iperf3 >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}
start_speed_responder() {
  local name="$1" run transport cfg qbin qcfg qiperf qlog
  load_meta "$name" || return
  [ "$ROLE" = gateway ] || { bad "start the responder on KHAREJ Gateway"; pause; return; }
  ensure_iperf || { bad "iperf3 unavailable"; pause; return; }
  ask "temporary backbone test port" "56565"; SPEED_BACKBONE="$ANS"
  valid_port "$SPEED_BACKBONE" && ! port_is_listening "$SPEED_BACKBONE" || { bad "test backbone port is invalid or busy"; pause; return; }
  ask "temporary local iperf port" "56566"; local iperf_port="$ANS"
  valid_port "$iperf_port" && ! port_is_listening "$iperf_port" || { bad "iperf port is invalid or busy"; pause; return; }
  run="/run/dark-realm-speed-${name}-$$"; mkdir -p "$run"; chmod 700 "$run"; cfg="$run/config.toml"
  transport="$(gateway_transport_string)"
  {
    echo '[log]'; echo 'level = "error"'; echo 'output = "stdout"'; echo
    echo '[network]'; echo 'no_tcp = false'; echo 'use_udp = false'; echo
    echo '[[endpoints]]'
    printf 'listen = "0.0.0.0:%s"\n' "$SPEED_BACKBONE"
    printf 'remote = "127.0.0.1:%s"\n' "$iperf_port"
    [ -n "$transport" ] && printf 'listen_transport = "%s"\n' "$(toml_escape "$transport")"
  } > "$cfg"
  printf -v qbin '%q' "$BIN_PATH"; printf -v qcfg '%q' "$cfg"; printf -v qiperf '%q' "$iperf_port"; printf -v qlog '%q' "$run/session.log"
  nohup bash -c "
    set -u
    $qbin -c $qcfg >>$qlog 2>&1 &
    rp=\$!
    trap 'kill \$rp 2>/dev/null || true; rm -rf $(printf '%q' "$run")' EXIT
    sleep 1
    iperf3 -s -1 -p $qiperf >>$qlog 2>&1
  " >/dev/null 2>&1 &
  sleep 1
  port_is_listening "$SPEED_BACKBONE" || { bad "temporary Realm responder failed"; cat "$run/session.log" 2>/dev/null; rm -rf "$run"; pause; return; }
  top; sect "SPEED CODE — paste on IRAN"; blank
  row "$Y$(generate_speed_code)$N"
  blank; row "$DResponder exits automatically after one iperf3 test.$N"; bot
  pause
}
run_speed_client() {
  local code run cfg transport local_port rp
  ensure_iperf || { bad "iperf3 unavailable"; pause; return; }
  ask "paste DRS1 speed code"; code="$ANS"
  parse_speed_code "$code" || { bad "invalid speed code"; pause; return; }
  local_port=56567
  while port_is_listening "$local_port"; do local_port=$((local_port+1)); [ "$local_port" -le 56650 ] || { bad "no free local test port"; return; }; done
  run="$(mktemp -d)"; cfg="$run/config.toml"
  TRANSPORT="$SPEED_TRANSPORT"; TLS_INSECURE="$SPEED_TLS_INSECURE"; SNI="$SPEED_SNI"; ALPN="$SPEED_ALPN"
  WS_HOST="$SPEED_WS_HOST"; WS_PATH="$SPEED_WS_PATH"; WS_MASK="$SPEED_WS_MASK"
  transport="$(edge_transport_string)"
  {
    echo '[log]'; echo 'level = "error"'; echo 'output = "stdout"'; echo
    echo '[network]'; echo 'no_tcp = false'; echo 'use_udp = false'; echo
    echo '[[endpoints]]'
    printf 'listen = "127.0.0.1:%s"\n' "$local_port"
    printf 'remote = "%s:%s"\n' "$(toml_escape "$SPEED_GATEWAY")" "$SPEED_BACKBONE"
    [ -n "$transport" ] && printf 'remote_transport = "%s"\n' "$(toml_escape "$transport")"
  } > "$cfg"
  "$BIN_PATH" -c "$cfg" >"$run/realm.log" 2>&1 & rp=$!
  sleep 1
  if ! port_is_listening "$local_port"; then
    bad "temporary Edge relay failed"; cat "$run/realm.log"; kill "$rp" 2>/dev/null || true; rm -rf "$run"; pause; return
  fi
  info "running 10-second, 4-stream test through Realm transport"
  iperf3 -c 127.0.0.1 -p "$local_port" -t 10 -P 4
  kill "$rp" 2>/dev/null || true; wait "$rp" 2>/dev/null || true; rm -rf "$run"
  pause
}
throughput_menu() {
  local name="$1"
  load_meta "$name" || return
  if [ "$ROLE" = gateway ]; then start_speed_responder "$name"; else run_speed_client; fi
}
screen_diag() {
  while :; do
    header "DIAGNOSTICS"
    pick_tunnel || return
    screen_logs "$SELECTED"
  done
}


# ================================================================ UPDATE ===
update_script() {
  local url tmp nv
  url="$(cat "$UPDATE_URL_FILE" 2>/dev/null)"
  [[ "$url" = https://* ]] || { bad "update URL must use HTTPS"; return 1; }
  tmp="$(mktemp)" || return 1
  info "downloading manager update"
  if ! curl -fsSL --retry 3 --max-time 60 -o "$tmp" "$url"; then rm -f "$tmp"; bad "download failed"; return 1; fi
  sed -i 's/\r$//' "$tmp"
  grep -q 'DARKVPN-REALM-SCRIPT' "$tmp" || { rm -f "$tmp"; bad "download is not DARK Realm Manager"; return 1; }
  bash -n "$tmp" || { rm -f "$tmp"; bad "downloaded script has syntax errors"; return 1; }
  nv="$(grep -m1 '^SCRIPT_VER=' "$tmp" | cut -d'"' -f2)"
  [ -n "$nv" ] || { rm -f "$tmp"; bad "version marker missing"; return 1; }
  cp -a "$SELF_PATH" "$SELF_PATH.bak.$(date +%s)" 2>/dev/null || true
  install -m 0755 "$tmp" "$SELF_PATH.new" || { rm -f "$tmp"; return 1; }
  mv -f "$SELF_PATH.new" "$SELF_PATH"; rm -f "$tmp"
  [ "$SELF_PATH" != "$CMD_PATH" ] && install -m 0755 "$SELF_PATH" "$CMD_PATH"
  ok "updated manager to v$nv"
  sleep 1
  exec "$SELF_PATH"
}
screen_update() {
  while :; do
    header "UPDATE"
    top; sect "VERSIONS"; blank
    kv "core" "$(core_version_short)"
    kv "manager" "v$SCRIPT_VER"
    kv "source" "$(cat "$UPDATE_URL_FILE" 2>/dev/null)"
    mid
    item 1 "Core manager" "pinned / latest / local"
    item 2 "Update manager" "verified marker + syntax"
    item 3 "Set update URL" "HTTPS only"
    item 4 "Install command" "darkrealm"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) screen_core ;;
      2) update_script; pause ;;
      3)
        ask "raw HTTPS URL"; [[ "$ANS" = https://* ]] || { bad "HTTPS required"; pause; continue; }
        yesno "trust this source for future updates?" n || continue
        printf '%s\n' "$ANS" > "$UPDATE_URL_FILE"; chmod 600 "$UPDATE_URL_FILE"; ok "saved"; pause
        ;;
      4) install -m 0755 "$SELF_PATH" "$CMD_PATH" && ok "run: darkrealm" || bad "install failed"; pause ;;
      0|_) return ;;
    esac
  done
}

# ======================================================= BACKUP / RESTORE ===
create_full_backup() {
  local include_keys="$1" out="$BACKUP_DIR/dark-realm-$(date +%Y%m%d-%H%M%S).tar.gz"
  local -a excludes=()
  [ "$include_keys" = 1 ] || excludes+=(--exclude='certs/*/privkey.pem' --exclude='certs/*/*.key')
  tar -C "$BASE_DIR" "${excludes[@]}" -czf "$out" \
    --exclude='backups' --exclude='runtime' . || { bad "backup failed"; return 1; }
  chmod 600 "$out"
  ok "backup: $out"
  [ "$include_keys" = 0 ] && warn "private keys were excluded"
}
restore_full_backup() {
  local -a files=() f
  local choice tmp safety
  while read -r f; do files+=("$f"); done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'dark-realm-*.tar.gz' | sort -r)
  [ "${#files[@]}" -gt 0 ] || { bad "no full backup found"; return 1; }
  top; sect "RESTORE BACKUP"; blank
  for choice in "${!files[@]}"; do row "$(printf '%s[%d]%s %s' "$Y" "$((choice+1))" "$N" "$(basename "${files[$choice]}")")"; done
  item 0 "Back" ""; bot; echo
  read -r -p "$(printf '  %s>%s Select: ' "$C" "$N")" choice
  [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ] || return 1
  f="${files[$((choice-1))]}"
  tar -tzf "$f" | grep -Eq '(^/|(^|/)\.\.(/|$))' && { bad "unsafe archive"; return 1; }
  tmp="$(mktemp -d)"; tar -xzf "$f" -C "$tmp" || { rm -rf "$tmp"; return 1; }
  [ -d "$tmp/tunnels" ] || { rm -rf "$tmp"; bad "backup has no tunnel directory"; return 1; }
  safety="$BACKUP_DIR/pre-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -C "$BASE_DIR" -czf "$safety" --exclude='backups' --exclude='runtime' . 2>/dev/null || true
  local n
  for n in $(tunnel_names); do stop_tunnel_hard "$n"; done
  find "$BASE_DIR" -mindepth 1 -maxdepth 1 ! -name backups ! -name runtime -exec rm -rf {} +
  cp -a "$tmp/." "$BASE_DIR/"; rm -rf "$tmp"
  ensure_dirs; ensure_units
  local failed=0
  for n in $(tunnel_names); do
    load_meta "$n" && write_unit_dropin "$n" && start_tunnel "$n" || failed=1
  done
  if [ "$failed" -eq 0 ]; then ok "backup restored"; else warn "restore completed but one or more tunnels need attention"; fi
  dim "pre-restore safety archive: $safety"
}
screen_backup() {
  while :; do
    header "BACKUP / RESTORE"
    top; sect "DATA SAFETY"; blank
    item 1 "Backup (no private keys)" "recommended"
    item 2 "Backup including keys" "sensitive archive"
    item 3 "Restore full backup" ""
    item 4 "Backup one tunnel" ""
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1) create_full_backup 0; pause ;;
      2)
        warn "the archive will contain TLS private keys"
        ask "type EXPORT KEYS to continue"
        [ "$ANS" = "EXPORT KEYS" ] && create_full_backup 1 || info "cancelled"
        pause
        ;;
      3) restore_full_backup; pause ;;
      4) pick_tunnel && backup_tunnel "$SELECTED"; pause ;;
      0|_) return ;;
    esac
  done
}

# ============================================================= UNINSTALL ===
screen_uninstall() {
  while :; do
    header "UNINSTALL"
    top; sect "SELECT SCOPE"; blank
    item 1 "Manager only" "preserve core, tunnels and certificates"
    item 2 "Tunnels + core" "preserve certificates"
    item 3 "Full cleanup" "remove all DARK Realm data"
    item 0 "Back" ""
    bot; echo; getkey
    case "$KEY" in
      1)
        ask "type REMOVE MANAGER"; [ "$ANS" = "REMOVE MANAGER" ] || { info "cancelled"; pause; continue; }
        rm -f "$CMD_PATH"
        ok "manager command removed; data preserved"; exit 0
        ;;
      2)
        ask "type REMOVE TUNNELS"; [ "$ANS" = "REMOVE TUNNELS" ] || { info "cancelled"; pause; continue; }
        local n
        for n in $(tunnel_names); do stop_tunnel_hard "$n"; set_restart_timer "$n" off; done
        rm -rf "$TUN_DIR" "$RUNTIME_DIR"
        rm -f "$BIN_PATH" "$UNIT_FILE" "$RS_UNIT" "$RS_TIMER"
        rm -rf /etc/systemd/system/dark-realm@*.service.d /etc/systemd/system/dark-realm-restart@*.timer.d
        systemctl daemon-reload >/dev/null 2>&1 || true
        ok "tunnels and core removed; certificates preserved"; pause
        ;;
      3)
        warn "this removes tunnels, core, manager metadata and DARK Realm certificate copies"
        ask "type DELETE EVERYTHING"; [ "$ANS" = "DELETE EVERYTHING" ] || { info "cancelled"; pause; continue; }
        local n
        for n in $(tunnel_names); do stop_tunnel_hard "$n"; set_restart_timer "$n" off; done
        rm -f "$BIN_PATH" "$CMD_PATH" "$UNIT_FILE" "$RS_UNIT" "$RS_TIMER"
        rm -rf "$BASE_DIR" /etc/systemd/system/dark-realm@*.service.d /etc/systemd/system/dark-realm-restart@*.timer.d
        systemctl daemon-reload >/dev/null 2>&1 || true
        ok "DARK Realm removed"; exit 0
        ;;
      0|_) return ;;
    esac
  done
}

# ================================================================== MAIN ===
main_menu() {
  while :; do
    header
    local total running
    total="$(tunnel_count)"
    running="$(systemctl list-units 'dark-realm@*.service' --state=running --no-legend 2>/dev/null | grep -c . || true)"
    top
    row "$(printf '%s%s%s tunnels   %s%s%s running   %s%s%s' "$W$BD" "$total" "$N" "$G$BD" "$running" "$N" "$D" "$([ -x "$BIN_PATH" ] && echo 'core ready' || echo 'core missing')" "$N")"
    mid; sect "SETUP"
    item 1 "Core" "install / update Realm"
    item 2 "New Tunnel — IRAN" "Edge, creates DR1 Pair Code"
    item 3 "New Tunnel — KHAREJ" "Gateway, accepts DR1"
    mid; sect "OPERATE"
    item 4 "Manage Tunnels" ""
    item 5 "Dashboard" ""
    item 6 "Diagnostics" ""
    mid; sect "MAINTENANCE"
    item 7 "Update" ""
    item 8 "Backup / Restore" ""
    item 9 "Uninstall" ""
    item 0 "Exit" ""
    bot; echo; getkey
    case "$KEY" in
      1) screen_core ;;
      2) screen_new_edge ;;
      3) screen_new_gateway ;;
      4) screen_manage ;;
      5) screen_dashboard ;;
      6) screen_diag ;;
      7) screen_update ;;
      8) screen_backup ;;
      9) screen_uninstall ;;
      0|q|Q) clear 2>/dev/null || true; printf '  %sDARK VPN · Realm%s  %s%s%s\n\n' "$C" "$N" "$D" "$DEV_ID" "$N"; exit 0 ;;
    esac
  done
}

# Internal non-interactive renewal hook.
if [ "${1:-}" = "--internal-reload-cert" ]; then
  internal_reload_cert "${2:-}"
fi
if [ "${1:-}" = "--version" ]; then
  printf 'DARK REALM PRO v%s\n' "$SCRIPT_VER"
  exit 0
fi

if [ "${DARK_REALM_LIB_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

need_root
install_deps || exit 1
ensure_dirs
partial_cleanup
ensure_units
main_menu

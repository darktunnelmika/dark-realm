#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export DARK_REALM_LIB_ONLY=1
export DARK_REALM_BASE_DIR="$TMP/etc"
export DARK_REALM_BIN_PATH="$TMP/bin/realm"
export DARK_REALM_CMD_PATH="$TMP/bin/darkrealm"
export DARK_REALM_UNIT_FILE="$TMP/systemd/dark-realm@.service"
export DARK_REALM_RS_UNIT="$TMP/systemd/dark-realm-restart@.service"
export DARK_REALM_RS_TIMER="$TMP/systemd/dark-realm-restart@.timer"

# shellcheck source=../dark-realm.sh
source "$ROOT/dark-realm.sh"

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok_test() { pass=$((pass+1)); echo "ok $pass - $*"; }

valid_port 443 || fail "valid_port"
! valid_port 0 || fail "port zero accepted"
! valid_port 65536 || fail "oversized port accepted"
ok_test "port validation"

valid_domain "edge.example.com" || fail "valid domain rejected"
! valid_domain "-bad.example.com" || fail "bad domain accepted"
! valid_domain "localhost" || fail "single-label domain accepted"
ok_test "domain validation"

expand_mappings '443,2053>8000,3000-3002' 3080 >/dev/null
[ "$CANON_MAPS" = '443>443@3080,2053>8000@3081,3000>3000@3082,3001>3001@3083,3002>3002@3084' ] || fail "mapping expansion"
[ "$MAP_COUNT" -eq 5 ] || fail "mapping count"
GOOD_MAPS="$CANON_MAPS"
! expand_mappings '443,$(id)' 3080 >/dev/null 2>&1 || fail "shell input accepted"
! expand_mappings '3000-2000' 3080 >/dev/null 2>&1 || fail "reverse range accepted"
ok_test "mapping parser and rejection"

reset_meta
NAME="test"; ROLE="edge"; GATEWAY_HOST="edge.example.com"; TARGET_HOST="127.0.0.1"
TRANSPORT="wss"; PROFILE="balanced"; MAPS="$GOOD_MAPS"; TLS_DOMAIN="edge.example.com"
SNI="edge.example.com"; ALPN="h2,http/1.1"; WS_HOST="edge.example.com"; WS_PATH="/safe-path"
WS_MASK="standard"; TLS_INSECURE=0; CREATED_AT=1700000000
apply_profile balanced
code="$(generate_pair_code)"
parse_pair_code "$code" || fail "valid pair code rejected"
[ "$PAIR_NAME" = test ] && [ "$PAIR_TRANSPORT" = wss ] || fail "pair values wrong"
badcode="${code%?}0"
! parse_pair_code "$badcode" >/dev/null 2>&1 || fail "tampered pair code accepted"
ok_test "pair code round-trip and checksum"

payload=$'schema=1\nname=test\ngateway=edge.example.com\ntarget=127.0.0.1\ntransport=tcp\nprofile=balanced\nmaps=443>443@3080\ncreated=1700000000\npwn=$(id)'
encoded="$(printf '%s' "$payload" | b64url_enc)"
sum="$(sha256_text "$payload")"
! parse_pair_code "DR1.$encoded.$sum" >/dev/null 2>&1 || fail "unknown injection field accepted"
ok_test "pair code field whitelist"

mkdir -p "$TUN_DIR/evil"
marker="$TMP/pwned"
cat > "$TUN_DIR/evil/meta.conf" <<EOF
SCHEMA=1
NAME=\$(touch $marker)
ROLE=edge
GATEWAY_HOST=edge.example.com
TARGET_HOST=127.0.0.1
BIND_ADDR=0.0.0.0
TRANSPORT=tcp
PROFILE=balanced
MAPS=443>443@3080
TLS_INSECURE=0
NOFILE=524288
TCP_TIMEOUT=5
TCP_KEEPALIVE=15
TCP_KEEPALIVE_PROBE=3
LOG_LEVEL=warn
RESTART_SEC=2
SCHEDULE=off
CREATED_AT=1700000000
EOF
! load_meta evil >/dev/null 2>&1 || fail "malicious metadata accepted"
[ ! -e "$marker" ] || fail "metadata executed shell"
ok_test "metadata is parsed as data, never sourced"

reset_meta
NAME="tcp"; ROLE="edge"; GATEWAY_HOST="edge.example.com"; TARGET_HOST="127.0.0.1"
TRANSPORT="tcp"; PROFILE="balanced"; MAPS='443>8000@3080'; apply_profile balanced
cfg="$TMP/config-tcp"; mkdir -p "$cfg"; generate_config_to "$cfg"
grep -q 'listen = "0.0.0.0:443"' "$cfg/config.toml" || fail "TCP listen missing"
grep -q 'remote = "edge.example.com:3080"' "$cfg/config.toml" || fail "TCP remote missing"
! grep -q 'transport' "$cfg/config.toml" || fail "TCP got fake transport"
validate_config_file "$cfg/config.toml" 1 || fail "TCP TOML invalid"
ok_test "native TCP config generation"

reset_meta
NAME="wss"; ROLE="gateway"; GATEWAY_HOST="edge.example.com"; TARGET_HOST="127.0.0.1"
TRANSPORT="wss"; PROFILE="turbo"; MAPS='443>8000@3080'; TLS_DOMAIN="edge.example.com"
SNI="edge.example.com"; WS_HOST="edge.example.com"; WS_PATH="/chat"; WS_MASK=standard
TLS_CERT="/etc/dark-realm/certs/edge.example.com/fullchain.pem"
TLS_KEY="/etc/dark-realm/certs/edge.example.com/privkey.pem"; apply_profile turbo
cfg="$TMP/config-wss"; mkdir -p "$cfg"; generate_config_to "$cfg"
grep -q 'listen_transport = "ws;host=edge.example.com;path=/chat;tls;cert=' "$cfg/config.toml" || fail "WSS transport missing"
validate_config_file "$cfg/config.toml" 1 || fail "WSS TOML invalid"
ok_test "native WSS config generation"

certdir="$TMP/certs"; mkdir -p "$certdir"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=edge.example.com' \
  -addext 'subjectAltName=DNS:edge.example.com' \
  -keyout "$certdir/key.pem" -out "$certdir/cert.pem" >/dev/null 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$certdir/wrong.pem" >/dev/null 2>&1
cert_pair_matches "$certdir/cert.pem" "$certdir/key.pem" || fail "matching cert/key rejected"
! cert_pair_matches "$certdir/cert.pem" "$certdir/wrong.pem" || fail "mismatched cert/key accepted"
cert_matches_host "$certdir/cert.pem" edge.example.com || fail "SAN match rejected"
! cert_matches_host "$certdir/cert.pem" other.example.com || fail "SAN mismatch accepted"
ok_test "certificate key and SAN validation"

grep -q 'DARKVPN-REALM-SCRIPT' "$ROOT/dark-realm.sh" || fail "manager marker missing"
grep -q 'DARK VPN · REALM PRO installer' "$ROOT/install.sh" || fail "installer marker missing"
bash -n "$ROOT/dark-realm.sh"
bash -n "$ROOT/install.sh"
ok_test "manager and installer syntax"

echo "1..$pass"

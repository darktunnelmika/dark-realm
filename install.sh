#!/usr/bin/env bash
# ==============================================================================
#  DARK VPN · REALM PRO installer
#  curl -fsSL https://raw.githubusercontent.com/darktunnelmika/dark-realm/main/install.sh | bash
# ==============================================================================
set -u

RAW="https://raw.githubusercontent.com/darktunnelmika/dark-realm/main/dark-realm.sh"
DEST="/usr/local/bin/darkrealm"
BASE_DIR="${DARK_REALM_BASE_DIR:-/etc/dark-realm}"

R=$'\e[38;5;203m'; G=$'\e[38;5;114m'; C=$'\e[38;5;81m'; D=$'\e[38;5;244m'; N=$'\e[0m'
ok()   { printf '  %s+%s %s\n' "$G" "$N" "$1"; }
bad()  { printf '  %sx%s %s\n' "$R" "$N" "$1" >&2; }
info() { printf '  %s>%s %s\n' "$C" "$N" "$1"; }

echo
printf '  %sDARK VPN · REALM PRO%s  installer\n\n' "$C" "$N"

if [ "$(id -u)" -ne 0 ]; then
  bad "must run as root (use sudo)"
  exit 1
fi

need=""
for c in curl sed grep; do command -v "$c" >/dev/null 2>&1 || need="$need $c"; done
if [ -n "$need" ]; then
  info "installing:$need"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $need
  elif command -v dnf >/dev/null 2>&1; then dnf install -y $need
  elif command -v yum >/dev/null 2>&1; then yum install -y $need
  elif command -v apk >/dev/null 2>&1; then apk add --no-cache $need
  else bad "install these commands manually:$need"; exit 1
  fi
fi

tmp="$(mktemp)" || { bad "cannot create temporary file"; exit 1; }
trap 'rm -f "$tmp"' EXIT

info "downloading manager"
if ! curl -fsSL --retry 3 --max-time 60 -o "$tmp" "$RAW"; then
  bad "download failed; check access to raw.githubusercontent.com"
  exit 1
fi
sed -i 's/\r$//' "$tmp"

grep -q 'DARKVPN-REALM-SCRIPT' "$tmp" || { bad "download is not DARK Realm Manager"; exit 1; }
bash -n "$tmp" || { bad "downloaded manager has syntax errors"; exit 1; }
ver="$(grep -m1 '^SCRIPT_VER=' "$tmp" | cut -d'"' -f2)"
[ -n "$ver" ] || { bad "manager version marker missing"; exit 1; }

mkdir -p "$BASE_DIR" && chmod 700 "$BASE_DIR"
[ -f "$DEST" ] && cp -a "$DEST" "$DEST.bak.$(date +%s)" 2>/dev/null || true
install -m 0755 "$tmp" "$DEST" || { bad "cannot install $DEST"; exit 1; }
printf '%s\n' "$RAW" > "$BASE_DIR/update.url"
chmod 600 "$BASE_DIR/update.url"

ok "installed DARK REALM PRO v$ver"
printf '\n  %srun later with:%s  darkrealm\n\n' "$D" "$N"

if [ -r /dev/tty ]; then
  exec "$DEST" </dev/tty
fi

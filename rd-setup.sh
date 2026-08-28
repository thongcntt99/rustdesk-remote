#!/usr/bin/env bash
# =============================================================================
# rd-setup.sh — Cài & cấu hình RustDesk trên macOS để điều khiển từ xa
#
# Cách dùng (trên máy Mac, chạy trong Terminal):
#   curl -fsSL https://raw.githubusercontent.com/<user>/rd/main/rd-setup.sh | sudo bash -s -- "Mac-01"
#
# Tuỳ chọn qua biến môi trường (đặt sau sudo, ví dụ: ... | sudo RD_PASSWORD=abc bash -s -- Mac-01):
#   RD_PASSWORD   Mật khẩu cố định muốn đặt (mặc định: tự sinh 12 ký tự)
#   RD_VERSION    Phiên bản RustDesk cụ thể, ví dụ 1.4.0 (mặc định: bản mới nhất)
#   RD_SERVER     ID/relay server riêng (mặc định: 45.77.71.138; đặt RD_SERVER="" để dùng server công cộng)
#   RD_KEY        Public key của server riêng (mặc định: key của server trên)
#   RD_NO_PMSET=1 Không tắt chế độ ngủ của máy
#   RD_NO_HOSTS_PIN=1  Không tự ghim IP rs-ny.rustdesk.com vào /etc/hosts khi DNS bị chặn
#   RD_RS_IP      IP thật của rs-ny.rustdesk.com (mặc định 209.250.254.15) dùng khi ghim
#
# Script sẽ:
#   1. Tải RustDesk đúng kiến trúc (Apple Silicon / Intel) và cài vào /Applications
#   2. Đổi tên máy (ComputerName / HostName / LocalHostName)
#   3. Đặt mật khẩu cố định, (tuỳ chọn) trỏ về server riêng
#   4. Tắt chế độ ngủ để máy luôn nhận kết nối
#   5. Thêm RustDesk vào Login Items để tự chạy khi đăng nhập
#   6. Mở 3 cửa sổ Privacy (Screen Recording / Accessibility / Input Monitoring)
#   7. In ra ID ⇥ Tên ⇥ Mật khẩu để dán vào Google Sheet
# =============================================================================
set -euo pipefail
RD_SETUP_VERSION="2026-08-28.6"
# ---- Server RustDesk riêng (mặc định). Để trống RD_SERVER nếu muốn dùng server công cộng. ----
RD_SERVER="${RD_SERVER-45.77.71.138}"
RD_KEY="${RD_KEY-noUsY6djm6ymHXXS4vYyqNwNhgmXePerJa6TlPI62BU=}"

# ---------- màu & log ----------
if [ -t 1 ]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi
log()  { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
die()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
trap 'die "Script dừng tại dòng $LINENO (lệnh: $BASH_COMMAND). Gửi ảnh màn hình này để được hỗ trợ."' ERR

# ---------- kiểm tra điều kiện ----------
[ "$(uname -s)" = "Darwin" ] || die "Script này chỉ chạy trên macOS."
[ "$(id -u)" -eq 0 ] || die "Hãy chạy bằng sudo:  curl ... | sudo bash -s -- \"Mac-01\""

MACHINE_NAME="${1:-}"
[ -n "$MACHINE_NAME" ] || die "Thiếu tên máy. Ví dụ:  ... | sudo bash -s -- \"Mac-01\""

# Người dùng đang đăng nhập ở màn hình (không phải root) — RustDesk lưu cấu hình theo user này
CONSOLE_USER="$(stat -f '%Su' /dev/console 2>/dev/null || true)"
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  CONSOLE_USER="${SUDO_USER:-}"
fi
if [ -z "$CONSOLE_USER" ] || [ "$CONSOLE_USER" = "root" ]; then
  die "Không xác định được user đang đăng nhập."
fi
CONSOLE_UID="$(id -u "$CONSOLE_USER")"
USER_HOME="$(dscl . -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
[ -n "$USER_HOME" ] || USER_HOME="/Users/$CONSOLE_USER"
as_user() { sudo -u "$CONSOLE_USER" -H env HOME="$USER_HOME" "$@"; }
# Chạy lệnh trong session GUI của user (cần cho `open`, osascript)
as_gui_user() { launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" -H env HOME="$USER_HOME" "$@"; }

ARCH="$(uname -m)"
case "$ARCH" in
  arm64)  RD_ARCH="aarch64" ;;
  x86_64) RD_ARCH="x86_64" ;;
  *)      die "Kiến trúc không hỗ trợ: $ARCH" ;;
esac

APP="/Applications/RustDesk.app"
RD="$APP/Contents/MacOS/RustDesk"

log "rd-setup v${RD_SETUP_VERSION}   Máy: ${C_B}${MACHINE_NAME}${C_0}   User: ${CONSOLE_USER}   Kiến trúc: ${ARCH}"

# ---------- 1. tải & cài RustDesk ----------
TMP="$(mktemp -d /tmp/rd-setup.XXXXXX)"
MOUNT_POINT=""
cleanup() {
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    hdiutil detach "$MOUNT_POINT" -quiet -force >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

resolve_dmg_url() {
  if [ -n "${RD_VERSION:-}" ]; then
    echo "https://github.com/rustdesk/rustdesk/releases/download/${RD_VERSION}/rustdesk-${RD_VERSION}-${RD_ARCH}.dmg"
    return
  fi
  local url
  url="$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest \
        | grep -o "https://github.com/rustdesk/rustdesk/releases/download/[^\"]*-${RD_ARCH}\.dmg" \
        | head -n1 || true)"
  [ -n "$url" ] || die "Không tìm được link tải RustDesk cho ${RD_ARCH}. Thử đặt RD_VERSION=1.4.0"
  echo "$url"
}

if [ -x "$RD" ] && [ -z "${RD_VERSION:-}" ]; then
  log "RustDesk đã có sẵn tại $APP — bỏ qua bước tải."
else
  DMG_URL="$(resolve_dmg_url)"
  log "Tải: $DMG_URL"
  curl -fL --progress-bar -o "$TMP/rustdesk.dmg" "$DMG_URL"

  log "Gắn ảnh đĩa & sao chép vào /Applications ..."
  MOUNT_POINT="$TMP/mnt"
  mkdir -p "$MOUNT_POINT"
  hdiutil attach "$TMP/rustdesk.dmg" -nobrowse -quiet -mountpoint "$MOUNT_POINT"
  SRC_APP="$(find "$MOUNT_POINT" -maxdepth 2 -name 'RustDesk.app' | head -n1)"
  [ -n "$SRC_APP" ] || die "Không thấy RustDesk.app trong file dmg."

  # Dừng bản cũ (nếu có) trước khi ghi đè
  pkill -x RustDesk >/dev/null 2>&1 || true
  rm -rf "$APP"
  cp -R "$SRC_APP" "$APP"
  hdiutil detach "$MOUNT_POINT" -quiet
  MOUNT_POINT=""

  xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
  chown -R root:admin "$APP"
  chmod -R a+rX "$APP"
  log "Đã cài RustDesk vào $APP"
fi

# ---------- 2. đặt tên máy ----------
HOST_SAFE="$(printf '%s' "$MACHINE_NAME" | tr -c 'A-Za-z0-9-' '-' | sed 's/^-*//; s/-*$//')"
[ -n "$HOST_SAFE" ] || HOST_SAFE="mac"
scutil --set ComputerName  "$MACHINE_NAME"
scutil --set HostName      "$HOST_SAFE"
scutil --set LocalHostName "$HOST_SAFE"
dscacheutil -flushcache >/dev/null 2>&1 || true
log "Đặt tên máy: $MACHINE_NAME (hostname: $HOST_SAFE)"

# ---------- 2b. mạng chặn DNS rustdesk.com? → ghim IP thật vào /etc/hosts ----------
# Một số mạng trả về IP giả (vd. 0.0.1.138) cho *.rustdesk.com. Nếu vậy, ghim IP thật để app đăng ký được.
RD_RS_HOST="rs-ny.rustdesk.com"
RD_RS_IP="${RD_RS_IP:-209.250.254.15}"
if [ -z "${RD_SERVER:-}" ] && [ "${RD_NO_HOSTS_PIN:-0}" != "1" ]; then
  RESOLVED="$(dig +short +time=3 +tries=1 "$RD_RS_HOST" 2>/dev/null | grep -E '^[0-9]+\.' | head -n1 || true)"
  case "$RESOLVED" in
    "$RD_RS_IP") log "DNS phân giải $RD_RS_HOST đúng ($RESOLVED)." ;;
    ""|0.*|127.*)
      if grep -q "$RD_RS_HOST" /etc/hosts 2>/dev/null; then
        log "$RD_RS_HOST đã được ghim trong /etc/hosts."
      else
        warn "DNS trả về '${RESOLVED:-rỗng}' cho $RD_RS_HOST (mạng chặn). Ghim $RD_RS_IP vào /etc/hosts."
        printf '%s %s
' "$RD_RS_IP" "$RD_RS_HOST" >> /etc/hosts
        dscacheutil -flushcache >/dev/null 2>&1 || true
        killall -HUP mDNSResponder >/dev/null 2>&1 || true
      fi ;;
    *) log "DNS phân giải $RD_RS_HOST = $RESOLVED (khác IP đã biết, giữ nguyên)." ;;
  esac
  nc -z -w 5 "$RD_RS_IP" 21116 >/dev/null 2>&1 && log "Kết nối TCP tới $RD_RS_IP:21116 OK."     || warn "Không kết nối được $RD_RS_IP:21116 — mạng có thể chặn cả IP; cân nhắc tự dựng server (RD_SERVER)."
fi

# ---------- 3. sinh mật khẩu (ghi vào cấu hình ở bước 6, sau khi app đã tạo file) ----------
if [ -n "${RD_PASSWORD:-}" ]; then
  PASSWORD="$RD_PASSWORD"
else
  # head đọc trước một khối cố định để không SIGPIPE tr (set -o pipefail sẽ làm script thoát)
  PASSWORD="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' | cut -c1-12)"
  [ "${#PASSWORD}" -eq 12 ] || die "Không sinh được mật khẩu ngẫu nhiên. Chạy lại với RD_PASSWORD=<mật khẩu>."
fi

# ---------- 4. không cho máy ngủ ----------
if [ "${RD_NO_PMSET:-0}" != "1" ]; then
  pmset -a sleep 0 displaysleep 0 disksleep 0 >/dev/null 2>&1 || warn "pmset thất bại (bỏ qua)."
  pmset -a womp 1 >/dev/null 2>&1 || true   # Wake on LAN
  log "Đã tắt chế độ ngủ (sleep/display/disk = 0)."
fi

# ---------- 5. tự chạy khi đăng nhập ----------
LOGIN_ITEM_SCRIPT='tell application "System Events"
  if not (exists login item "RustDesk") then
    make login item at end with properties {path:"/Applications/RustDesk.app", hidden:false}
  end if
end tell'
if as_gui_user osascript -e "$LOGIN_ITEM_SCRIPT" >/dev/null 2>&1; then
  log "Đã thêm RustDesk vào Login Items."
else
  warn "Không thêm được Login Item (thêm tay: System Settings → General → Login Items)."
fi

# ---------- 6. khởi động app & mở cửa sổ Privacy ----------
log "Mở RustDesk ..."
rd_running() { pgrep -x RustDesk >/dev/null 2>&1; }
# Thử lần lượt 3 cách mở app trong phiên GUI của user, cách nào giữ được app chạy thì dừng
launch_rd() {
  local attempt
  for attempt in 1 2 3; do
    case "$attempt" in
      1) launchctl asuser "$CONSOLE_UID" open -a "$APP" >/dev/null 2>&1 || true ;;
      2) sudo -u "$CONSOLE_USER" open -a "$APP" >/dev/null 2>&1 || true ;;
      3) launchctl asuser "$CONSOLE_UID" sudo -u "$CONSOLE_USER" -H env HOME="$USER_HOME" "$RD" >/dev/null 2>&1 & ;;
    esac
    sleep 4
    if rd_running; then return 0; fi
  done
  return 1
}
if launch_rd; then
  log "RustDesk đang chạy (PID $(pgrep -x RustDesk | head -n1))."
else
  warn "RustDesk KHÔNG chạy được. Mở tay: Finder → Applications → RustDesk. Nếu vẫn không lên, chạy lệnh sau để xem lỗi:"
  warn "  $RD"
fi

# ---------- 6b. ghi cấu hình: server riêng + mật khẩu cố định ----------
# RustDesk 1.4 từ chối `--password` khi chưa cài service, nên ghi thẳng vào file cấu hình của user.
CFG_DIR="$USER_HOME/Library/Preferences/com.carriez.RustDesk"
CFG1="$CFG_DIR/RustDesk.toml"    # id, password
CFG2="$CFG_DIR/RustDesk2.toml"   # [options] server, key
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$CFG1" ] && break; sleep 1; done
[ -f "$CFG1" ] || warn "Chưa thấy $CFG1 (app chưa tạo cấu hình) — vẫn tiếp tục ghi."

log "Dừng RustDesk để ghi cấu hình ..."
pkill -x RustDesk >/dev/null 2>&1 || true
sleep 1
mkdir -p "$CFG_DIR"

# mật khẩu: thay dòng password = ... hoặc thêm mới
if grep -q '^password = ' "$CFG1" 2>/dev/null; then
  sed -i '' "s|^password = .*|password = '${PASSWORD}'|" "$CFG1"
else
  printf "password = '%s'\n" "$PASSWORD" >> "$CFG1"
fi

# server riêng: ghi vào [options] của RustDesk2.toml
if [ -n "$RD_SERVER" ]; then
  touch "$CFG2"
  grep -q '^\[options\]' "$CFG2" || printf '\n[options]\n' >> "$CFG2"
  TMP2="$(mktemp)"
  grep -vE '^(custom-rendezvous-server|relay-server|api-server|key) = ' "$CFG2" > "$TMP2" || true
  awk -v srv="$RD_SERVER" -v key="$RD_KEY" -v q="'" '
    { print }
    /^\[options\]/ && !done {
      print "custom-rendezvous-server = " q srv q
      print "relay-server = " q srv q
      if (key != "") print "key = " q key q
      done = 1
    }' "$TMP2" > "$CFG2"
  rm -f "$TMP2"
  log "Trỏ về server riêng: $RD_SERVER"
fi
chown -R "$CONSOLE_USER" "$CFG_DIR"

# xác minh đọc lại
grep -q "^password = '${PASSWORD}'" "$CFG1" && log "Mật khẩu đã ghi vào cấu hình." || warn "KHÔNG xác minh được mật khẩu trong $CFG1 — kiểm tra tay."
if [ -n "$RD_SERVER" ]; then
  grep -q "^custom-rendezvous-server = '${RD_SERVER}'" "$CFG2" && log "Server đã ghi vào cấu hình." || warn "KHÔNG xác minh được server trong $CFG2."
fi

log "Mở lại RustDesk ..."
launch_rd || warn "RustDesk không chạy lại được — mở tay từ Applications."

log "Mở 3 cửa sổ Privacy — hãy GẠT CÔNG TẮC RustDesk ở cả 3 (nếu chưa thấy dòng RustDesk: bấm + → Applications → RustDesk):"
for pane in Privacy_ScreenCapture Privacy_Accessibility Privacy_ListenEvent; do
  as_gui_user open "x-apple.systempreferences:com.apple.preference.security?${pane}" >/dev/null 2>&1 || true
  sleep 1
done

# ---------- 7. lấy ID ----------
RD_ID=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  RD_ID="$(as_user "$RD" --get-id 2>/dev/null | tr -d '[:space:]' || true)"
  if [ -n "$RD_ID" ] && [ "$RD_ID" != "0" ]; then break; fi
  sleep 2
done
[ -n "$RD_ID" ] || RD_ID="(chưa có — mở app RustDesk để xem ID)"

# ---------- FileVault ----------
if fdesetup status 2>/dev/null | grep -qi 'FileVault is On'; then FV="On"; else FV="Off"; fi

# ---------- tổng kết ----------
echo
echo "${C_B}================ HOÀN TẤT: ${MACHINE_NAME} ================${C_0}"
echo "  ID        : ${RD_ID}"
echo "  Tên máy   : ${MACHINE_NAME}"
echo "  Mật khẩu  : ${PASSWORD}"
echo "  Server    : ${RD_SERVER:-công cộng (rustdesk.com)}"
echo "  FileVault : ${FV}"
if rd_running; then echo "  App       : đang chạy"; else echo "  App       : ${C_R}KHÔNG chạy${C_0} → mở tay từ Applications, nếu không Windows sẽ báo offline"; fi
echo
echo "Việc cần làm tay:"
echo "  1. Gạt công tắc RustDesk trong 3 cửa sổ Privacy vừa mở (Screen Recording, Accessibility, Input Monitoring)."
echo "  2. Mở RustDesk, đối chiếu mật khẩu. Lệch thì bấm ⋯ → Set permanent password → dán: ${PASSWORD}"
if [ "$FV" = "On" ]; then
  echo "  3. ${C_Y}FileVault đang BẬT${C_0} → System Settings → Privacy & Security → FileVault → Turn Off"
  echo "     (nếu không tắt, máy khởi động lại sẽ kẹt ở màn hình mở khoá ổ đĩa, không điều khiển được)."
fi
echo "  •  Nên bật tự đăng nhập: System Settings → Users & Groups → Automatic login → chọn ${CONSOLE_USER}"
echo
echo "Dòng dán vào Google Sheet (ID ⇥ Tên ⇥ Mật khẩu):"
printf '%s\t%s\t%s\n' "$RD_ID" "$MACHINE_NAME" "$PASSWORD"
echo

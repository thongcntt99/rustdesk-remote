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
#   RD_SERVER     Địa chỉ relay/ID server tự host (bỏ trống = dùng server công cộng)
#   RD_KEY        Public key của server tự host (đi kèm RD_SERVER)
#   RD_NO_PMSET=1 Không tắt chế độ ngủ của máy
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

# ---------- màu & log ----------
if [ -t 1 ]; then
  C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
  C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""
fi
log()  { printf '%s[+]%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
die()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

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

log "Máy: ${C_B}${MACHINE_NAME}${C_0}   User: ${CONSOLE_USER}   Kiến trúc: ${ARCH}"

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

# ---------- 3. mật khẩu & server ----------
if [ -n "${RD_PASSWORD:-}" ]; then
  PASSWORD="$RD_PASSWORD"
else
  # 12 ký tự chữ + số, tránh ký tự dễ nhầm (0/O, 1/l/I)
  PASSWORD="$(LC_ALL=C tr -dc 'A-HJ-NP-Za-km-z2-9' </dev/urandom | head -c 12)"
fi

if [ -n "${RD_SERVER:-}" ]; then
  log "Trỏ về server riêng: $RD_SERVER"
  if [ -n "${RD_KEY:-}" ]; then
    as_user "$RD" --config "host=${RD_SERVER},key=${RD_KEY}" >/dev/null 2>&1 || warn "Không đặt được server (bỏ qua)."
  else
    as_user "$RD" --config "host=${RD_SERVER}" >/dev/null 2>&1 || warn "Không đặt được server (bỏ qua)."
  fi
fi

log "Đặt mật khẩu cố định ..."
as_user "$RD" --password "$PASSWORD" >/dev/null 2>&1 || warn "Lệnh --password báo lỗi — hãy đối chiếu trong app và đặt tay nếu cần."

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
as_gui_user open -a "$APP" >/dev/null 2>&1 || warn "Không mở được app, hãy mở tay từ /Applications."
sleep 3

log "Mở 3 cửa sổ Privacy — hãy GẠT CÔNG TẮC RustDesk ở cả 3:"
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
echo "  FileVault : ${FV}"
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

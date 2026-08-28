# rd — Điều khiển nhiều máy Mac từ 1 máy Windows bằng RustDesk

Bộ file này giúp cài RustDesk lên từng máy Mac bằng **một dòng lệnh**, rồi kết nối từ Windows.

| File | Dùng ở đâu | Việc gì |
|---|---|---|
| [rd-setup.sh](rd-setup.sh) | Mac | Cài RustDesk, đặt tên máy, đặt mật khẩu cố định, tắt ngủ, mở cửa sổ Privacy, in ra ID/Tên/Mật khẩu |
| [machines.example.csv](machines.example.csv) | Windows | Mẫu bảng ID / Tên máy / Mật khẩu — sao chép thành `machines.csv` (file này bị `.gitignore`, không bao giờ lên repo Public) |
| [connect.ps1](connect.ps1) | Windows | Chọn máy trong bảng và mở phiên RustDesk tới máy đó |
| [typer/typer.cmd](typer/typer.cmd) | Windows | Auto Typer: nhập 1 đoạn, chọn delay & tốc độ, bấm nút → gõ phím vào cửa sổ đang mở (vd. phiên RustDesk) |

---

## Phần 1 — Chuẩn bị, làm 1 lần trên Windows

1. Tạo tài khoản GitHub nếu chưa có.
2. Tạo repo mới tên `rd`, để **Public**.
3. Bấm **Add file → Upload files**, kéo file `rd-setup.sh` vào, Commit.
4. Bấm vào file `rd-setup.sh` → bấm nút **Raw** → copy URL trên thanh địa chỉ. Dạng:

   ```
   https://raw.githubusercontent.com/<tên-bạn>/rd/main/rd-setup.sh
   ```
5. Tạo một Google Sheet 3 cột: **ID | Tên máy | Mật khẩu** (hoặc sao chép `machines.example.csv` → `machines.csv` trong thư mục này).

Xong. Không bao giờ phải làm lại.

> Nếu upload bằng `git push` từ Windows thay vì kéo-thả trên web: file `.gitattributes` trong repo đã ép `rd-setup.sh` giữ xuống dòng LF, nên `bash` trên Mac không bị lỗi `\r`.

---

## Phần 2 — Trên từng máy Mac, ~2 phút mỗi máy

6. Mở **Terminal**, dán lệnh này (thay URL và tên máy):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/<tên-bạn>/rd/main/rd-setup.sh | sudo bash -s -- "Mac-01"
   ```
7. Nhập mật khẩu máy Mac khi nó hỏi. Chờ script chạy.
8. Ba cửa sổ Privacy tự bật lên — gạt công tắc **RustDesk** ở cả ba: **Screen Recording**, **Accessibility**, **Input Monitoring**.
9. Mở app RustDesk, đối chiếu mật khẩu hiển thị với chuỗi script vừa in. Lệch thì bấm **⋯ → Set permanent password** → dán vào.
10. Nhìn dòng cuối script in ra: `FileVault: On` thì vào **System Settings → Privacy & Security → FileVault** tắt đi (nếu không, máy khởi động lại sẽ kẹt ở màn hình mở khoá ổ đĩa).
11. Copy dòng `ID⇥Tên⇥Mật khẩu` ở cuối, dán vào Google Sheet / `machines.csv`.

Lặp bước 6–11 cho từng máy. Máy tiếp theo đổi `"Mac-01"` thành `"Mac-02"`.

**Nên làm thêm (1 lần/máy):** System Settings → Users & Groups → **Automatic login** → chọn user. Khi mất điện/khởi động lại, máy tự vào màn hình và RustDesk tự chạy (script đã thêm vào Login Items).

### Tuỳ chọn nâng cao

Đặt biến môi trường ngay sau `sudo`:

```bash
# Tự chọn mật khẩu thay vì để script sinh ngẫu nhiên
curl -fsSL <URL> | sudo RD_PASSWORD='MatKhau123' bash -s -- "Mac-01"

# Ghim phiên bản RustDesk cụ thể
curl -fsSL <URL> | sudo RD_VERSION=1.4.0 bash -s -- "Mac-01"

# Script mặc định trỏ về server riêng 45.77.71.138 (xem server/README.md). Muốn dùng server công cộng:
curl -fsSL <URL> | sudo RD_SERVER= bash -s -- "Mac-01"
# Hoặc server khác:
curl -fsSL <URL> | sudo RD_SERVER=rd.congty.vn RD_KEY='<public key>' bash -s -- "Mac-01"

# Không tắt chế độ ngủ của máy
curl -fsSL <URL> | sudo RD_NO_PMSET=1 bash -s -- "Mac-01"
```

---

## Phần 3 — Trên Windows

12. Cài RustDesk: tải `.exe` từ <https://github.com/rustdesk/rustdesk/releases>.
12b. Trỏ về server riêng (1 lần): ⚙ Settings → **Network** → Unlock → **ID server** `45.77.71.138`, **Relay server** `45.77.71.138`, **Key** `noUsY6djm6ymHXXS4vYyqNwNhgmXePerJa6TlPI62BU=`, API server để trống → Apply. Xem thêm [server/README.md](server/README.md).
13. Với mỗi dòng trong Sheet: nhập **ID → Connect → dán mật khẩu → tick Remember password**.
14. Kết nối được rồi thì bấm **ngôi sao** để ghim máy đó vào danh sách.
15. Trong phiên, mở thanh công cụ → **Keyboard → Map mode**, để phím **Windows** đóng vai **Cmd**.

**Cách nhanh hơn với `connect.ps1`:** điền `machines.csv`, rồi trong PowerShell:

```powershell
.\connect.ps1              # hiện danh sách, chọn số để kết nối
.\connect.ps1 Mac-01       # kết nối thẳng theo tên
.\connect.ps1 -All         # mở tất cả máy trong bảng
```

### Auto Typer (gõ chữ tự động vào phiên RustDesk)

Bấm đúp `typer\typer.cmd` (không cần cài gì, dùng PowerShell có sẵn):

1. Cửa sổ nhỏ hiện ở góc dưới bên phải màn hình. Nhập nội dung cần gõ vào ô trên cùng — **nhiều dòng được**, mỗi xuống dòng sẽ gõ thành phím Enter; Tab cũng gõ thành phím Tab.
2. Chọn **Chờ (giây)** — mặc định 5 — và **Tốc độ 1–10** — mặc định 8 (10 nhanh nhất ≈ 30 ms/ký tự, 1 chậm nhất ≈ 300 ms/ký tự).
3. Bấm **Bắt đầu** (hoặc **Ctrl+Enter**), rồi click vào cửa sổ đích (phiên RustDesk) trước khi hết giờ đếm ngược.
4. Giữ **Esc** nếu muốn dừng giữa chừng.

Cách gõ: mỗi ký tự được gửi như **một phím bấm thật** (mã phím + scancode + Shift nếu cần) nên RustDesk/AnyDesk/VNC chuyển sang máy Mac đúng như người gõ. Tick **Enter cuối** để nhấn thêm Enter sau khi gõ xong.

**Lưu ý quan trọng:**
- **Tắt bộ gõ tiếng Việt (UniKey/EVKey…) trên Windows** trước khi bấm Bắt đầu — nếu không nó sẽ biến đổi phím (vd. Telex: `[`→ơ, `aa`→â) y như khi bạn gõ tay.
- Ký tự **không có trên bàn phím** (chữ có dấu như `ệ`, `ơ`) không thể gửi thành phím bấm thật; qua RustDesk sẽ không ra đúng. Nội dung gửi sang Mac nên dùng chữ không dấu / lệnh terminal.
- Trong phiên RustDesk nên để **Keyboard → Map mode** để phím bên Windows ánh xạ 1:1 sang Mac.

---

## Kiểm tra trước khi nhân ra nhiều máy

Làm trọn quy trình với **1 máy Mac** trước, xác nhận đủ 4 điều rồi mới làm hàng loạt:

- [ ] Từ Windows nhìn thấy màn hình Mac (Screen Recording đã cấp).
- [ ] Chuột/bàn phím điều khiển được (Accessibility + Input Monitoring đã cấp).
- [ ] Khởi động lại Mac → không cần chạm vào máy mà vẫn kết nối lại được (FileVault Off + Automatic login + Login Item).
- [ ] Để máy yên 30 phút → vẫn kết nối được (máy không ngủ).

## Sự cố thường gặp

| Hiện tượng | Nguyên nhân / cách sửa |
|---|---|
| Kết nối được nhưng màn hình đen | Chưa gạt Screen Recording. Gạt xong phải **thoát hẳn RustDesk rồi mở lại**. |
| Nhìn thấy nhưng không bấm được | Chưa gạt Accessibility / Input Monitoring. |
| Mật khẩu sai | Mở RustDesk trên Mac → ⋯ → Set permanent password, dán lại mật khẩu trong Sheet. |
| Sau khi khởi động lại không kết nối được | FileVault còn bật, hoặc chưa bật Automatic login. |
| `bash: $'\r': command not found` | File `.sh` bị xuống dòng CRLF. Tải lại từ nút Raw, hoặc chạy `sed -i '' 's/\r$//' rd-setup.sh`. |
| Script báo không tìm được link tải | GitHub API bị giới hạn tạm thời. Chạy lại với `RD_VERSION=1.4.0`. |

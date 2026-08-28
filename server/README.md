# RustDesk Server trên EasyPanel

Hai container: **hbbs** (ID server, port 21115/21116) và **hbbr** (relay, port 21117). Không cần domain, không đi qua Traefik.

## 1. Mở firewall trên máy chủ EasyPanel

SSH vào máy chủ:

```bash
sudo ufw allow 21115:21117/tcp && sudo ufw allow 21116/udp && sudo ufw reload
```

Nếu nhà cung cấp có firewall riêng (Hetzner Cloud Firewall, Vultr, AWS Security Group, Oracle…), mở thêm ở đó cùng các port trên. Nếu không dùng `ufw` thì bỏ qua lệnh trên.

## 2. Tạo service trên EasyPanel

1. Vào Project → **+ Service** → chọn **Compose**.
2. Tên: `rustdesk`.
3. Tab **Source** (hoặc Compose): dán toàn bộ nội dung file [docker-compose.yml](docker-compose.yml).
4. Tab **Environment**: thêm `RELAY_HOST=<IP public máy chủ>` (ví dụ `RELAY_HOST=203.0.113.10`, hoặc domain trỏ về máy chủ).
5. **Deploy**. Chờ cả 2 container trạng thái Running.

## 3. Lấy public key

Trong EasyPanel mở **Console** của container `rustdesk-hbbs`, hoặc SSH vào máy chủ:

```bash
docker exec rustdesk-hbbs cat /root/id_ed25519.pub
```

Kết quả là một chuỗi ~44 ký tự, ví dụ `Xk2sbF3kQ8...=`. Đây là `RD_KEY`.

## 4. Kiểm tra từ ngoài (chạy trên Windows)

```powershell
Test-NetConnection <IP> -Port 21116
Test-NetConnection <IP> -Port 21117
```

Cả hai phải `TcpTestSucceeded : True`.

## 5. Trỏ client về server riêng

**Máy Mac** — chạy script với 2 biến:

```bash
curl -fsSL https://raw.githubusercontent.com/thongcntt99/rustdesk-remote/main/rd-setup.sh | sudo RD_SERVER=<IP> RD_KEY='<key>' bash -s -- "Mac-01"
```

(Hoặc sửa mặc định `RD_SERVER`/`RD_KEY` ngay trong `rd-setup.sh` để khỏi truyền mỗi lần.)

**Windows** — RustDesk → ⚙ Settings → **Network** → Unlock → ID/Relay server:

| Ô | Giá trị |
|---|---|
| ID server | `<IP>` |
| Relay server | `<IP>` |
| API server | *(để trống)* |
| Key | `<key>` |

Sau khi trỏ về server riêng: **không cần đăng nhập** Google/GitHub, không dính chặn DNS `rustdesk.com`, và relay là của bạn nên không bị giới hạn băng thông.

## Cập nhật / sao lưu

- Cập nhật: trên EasyPanel bấm **Redeploy** (image `latest` được kéo lại).
- Sao lưu: thư mục `data/` của service (chứa `id_ed25519` + `id_ed25519.pub`). **Mất key = phải cấu hình lại key trên toàn bộ client**, nên hãy lưu 2 file này ra ngoài.

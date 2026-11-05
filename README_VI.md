<p align="center">
  <img src="assets/icon-256.png" alt="WinDebloat Tool" width="128">
</p>

<h1 align="center">WinDebloat Tool</h1>

<p align="center">
  Tạo ISO cài đặt Windows 10 / 11 gọn nhẹ từ ISO gốc của Microsoft.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="Giấy phép MIT"></a>
  <img src="https://img.shields.io/badge/PowerShell-2.0%2B-5391FE.svg?logo=powershell&logoColor=white" alt="PowerShell 2.0+">
  <img src="https://img.shields.io/badge/Windows-7%20%E2%80%93%2011-0078D6.svg" alt="Windows 7 – 11">
</p>

<p align="center">
  <a href="README.md">English</a> · Tiếng Việt
</p>

---

## Giới thiệu
WinDebloat Tool gỡ ứng dụng cài sẵn, tắt quảng cáo, gợi ý và cơ chế tự cài ứng dụng ngay trong bộ cài
Windows, nhờ đó mọi máy cài từ ISO mới đều sạch ngay từ đầu. Công cụ có thể tải ISO chính thức trực tiếp từ
Microsoft hoặc dùng file ISO có sẵn trên máy. Chế độ **Đơn giản** tạo ISO hoàn chỉnh chỉ với một nút bấm;
chế độ **Nâng cao** cho phép tuỳ chỉnh đầy đủ ứng dụng, tinh chỉnh, phiên bản Windows và tuỳ chọn cài đặt.
Giao diện có tiếng Việt, tiếng Anh, tiếng Trung giản thể và tiếng Khmer; công cụ chạy trên Windows 7 SP1 trở
lên với PowerShell 2.0 trở lên.

## Điểm nổi bật
- Tải ISO chính thức từ Microsoft, kiểm tra SHA256, hoặc dùng file ISO có sẵn.
- Gỡ ứng dụng cài sẵn với lựa chọn mặc định an toàn; các thành phần cốt lõi như Store, Windows Security được giữ nguyên.
- Tinh chỉnh Registry offline: tắt quảng cáo, gợi ý, Copilot, Widgets, telemetry và nhiều mục khác.
- Chọn phiên bản cần giữ (ví dụ Home + Pro), tuỳ chọn cài đặt tự động với tài khoản local và tích hợp bản cập nhật offline.
- ISO khởi động được cả BIOS lẫn UEFI, kèm file SHA256 và log chi tiết.
- Có sẵn mẫu cấu hình và lưu được mẫu riêng; danh sách ứng dụng, tinh chỉnh nằm trong [`data/`](data), dễ xem và chỉnh sửa.

## Bắt đầu nhanh
1. Tải `WinDebloatTool_v1.2.2.zip` tại mục [Releases](https://github.com/thanhtai2009/WinDebloatTool/releases/latest).
2. Nhấp chuột phải vào file zip → **Properties** → chọn **Unblock**, rồi giải nén.
3. Nhấp đúp **`run.bat`** và đồng ý cấp quyền quản trị.
4. Chọn **Đơn giản** để tạo ISO bằng một nút bấm, hoặc **Nâng cao** để tuỳ chỉnh đầy đủ, rồi bấm **BẮT ĐẦU**.
5. Ghi ISO vừa tạo ra USB bằng Rufus hoặc Ventoy, hoặc dùng trong máy ảo.

Mỗi lần tạo thường mất 30–90 phút. Thay đổi của từng phiên bản xem tại [CHANGELOG.md](CHANGELOG.md).

## Yêu cầu
- Windows 7 SP1 trở lên (khuyến nghị Windows 10 / 11), PowerShell 2.0 trở lên.
- Quyền quản trị (`run.bat` tự yêu cầu).
- Khoảng 25 GB dung lượng trống.
- Chỉ cần Internet khi tải ISO hoặc cài oscdimg (tự cài từ Windows ADK chính thức nếu máy chưa có).
- Riêng Windows 7 cần thêm 7-Zip và `oscdimg.exe` trong thư mục `tools\`; việc tải file cần hỗ trợ TLS 1.2.

## An toàn
- Chỉ dùng công cụ của Microsoft để chỉnh sửa image (DISM, reg.exe, oscdimg); aria2 đi kèm chỉ dùng để tải file.
- ISO gốc không bao giờ bị thay đổi; công cụ tạo ISO mới và tự dọn thư mục làm việc.
- File tải về được đối chiếu SHA256 của Microsoft; file không khớp sẽ bị xoá.
- Thay đổi chỉ áp dụng cho máy cài từ ISO mới. Ứng dụng đã gỡ có thể cài lại từ Microsoft Store.

## Credits
- [Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat) (MIT): danh sách ứng dụng và mức độ an toàn.
- [ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) và
  [farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows) (MIT): tinh chỉnh quyền riêng tư và mẫu cấu hình.
- [ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder): chỉ tham khảo ý tưởng, không lấy mã.
- [pbatard/Fido](https://github.com/pbatard/Fido) (GPL-3.0): tài liệu về cách tải ISO từ Microsoft, không lấy mã.
- [aria2](https://aria2.github.io/) (GPL-2.0 trở lên): đi kèm nguyên bản trong `tools/aria2/`
  (xem [`NOTICE.txt`](tools/aria2/NOTICE.txt) và [`COPYING`](tools/aria2/COPYING)).
- [massgrave.dev](https://massgrave.dev/genuine-installation-media): danh sách file gốc của Microsoft cho nguồn tải dự phòng.
- Biểu tượng được vẽ riêng cho dự án theo phong cách Material 3 Expressive; không phải logo Windows.

Windows, DISM và Windows ADK là sản phẩm của Microsoft. Dự án không phân phối lại thành phần nào của Microsoft.

## Giấy phép
[MIT](LICENSE) Copyright (c) 2026 TaiNT13@PNC STG & WinDebloat Tool contributors. aria2 trong `tools/aria2/` giữ giấy phép riêng
(GPL-2.0).

---

<p align="center"><sub>Designed by TaiNT13@PNC STG</sub></p>

# Win11 Debloat Tool – Hướng dẫn tiếng Việt

Công cụ biến **ISO Windows 11 gốc của Microsoft** thành **ISO gọn nhẹ** (đã gỡ app rác, tắt quảng cáo/gợi ý),
chạy trên Windows, có giao diện, chỉ dùng công cụ của Microsoft (DISM, reg.exe, oscdimg trong Windows ADK).
Không tải phần mềm bên thứ ba.

> **Lưu ý trung thực:** tool **chưa được chạy thử trên Windows thật**. Code được viết và kiểm tra trên Linux
> (kiểm tra cú pháp PowerShell, PSScriptAnalyzer, quét tương thích PowerShell 2.0, test giả lập dism/reg).
> Cùng bộ thay đổi này đã được làm thật trên một ISO Win11 bằng công cụ Linux; ISO đó đã boot vào màn hình
> cài đặt Windows trong máy ảo (UEFI + Secure Boot), nhưng chưa thử cài hết. Tool Windows này làm lại đúng quy trình đó bằng công cụ của Microsoft. Lần chạy đầu
> nếu có lỗi, hãy gửi file log.

## Cách dùng nhanh
1. Giải nén file zip, bấm đúp **`run.bat`** → chọn **Yes** khi Windows hỏi quyền Administrator.
2. **Nguồn ISO**:
   - Đã có ISO: bấm **Chọn...** và chọn file.
   - Chưa có: bấm **Lấy danh sách** → chọn phiên bản, kiến trúc (x64/arm64), ngôn ngữ (mặc định English US)
     → **Tải**. File tải thẳng từ máy chủ Microsoft và được kiểm tra SHA256 với bảng hash Microsoft công bố.
   - Nếu Microsoft chặn tải trong app: bấm **Mở trang Microsoft**, tải bằng trình duyệt rồi **Chọn...** file đó.
3. Tick các app muốn gỡ (mặc định đã chọn sẵn), tinh chỉnh registry, phiên bản (Tất cả / Home+Pro / nhập index).
4. Chọn nơi lưu ISO đầu ra → bấm **BẮT ĐẦU**. Mất khoảng 20–60 phút, cần trống khoảng **25 GB**.
   Bấm **Huỷ** thì tool dừng sau bước đang chạy (bước DISM không ngắt giữa chừng được).
5. Kết quả: file `.iso`, `.iso.sha256`, file log, và `kept_indexN.txt` (danh sách app còn lại).
6. Ghi ra USB bằng **Rufus** hoặc **Ventoy** (install.wim lớn hơn 4 GB nên chép thẳng vào USB FAT32 sẽ lỗi).

Lần đầu nếu thiếu **oscdimg.exe**, tool sẽ hỏi: cài *Deployment Tools* của Windows ADK từ Microsoft
(chỉ phần đó, có kiểm tra chữ ký số) hoặc cài qua winget.

Chạy dòng lệnh (không giao diện):
```
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_gon.iso -Edition HomePro
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf     (chạy thử, không thay đổi gì)
run.bat -Check                                                  (kiểm tra máy)
```

## Tool thay đổi những gì
**Gỡ (mặc định):** Clipchamp, Teams mới, Outlook mới, Tin tức, Bing Search, Thời tiết, app Xbox, Game Bar,
Xbox TCUI, Xbox Identity Provider, Xbox Speech-to-text, Solitaire, Get Help, Microsoft 365 hub,
Power Automate, To Do, Dev Home, Feedback Hub, Phone Link, Cross Device, Quick Assist, Copilot, Family;
bản cũ thì gỡ thêm Cortana, Maps, People, Tips, Copilot provider, Teams cũ.
Tuỳ chọn (không tick sẵn): Widgets, Media Player, Phim & TV, Camera, Đồng hồ, Ghi âm, Sticky Notes, Mail & Lịch.

**Luôn giữ lại:** Store, Defender/Bảo mật, Edge, WebView2, Máy tính, Ảnh, Notepad, Terminal, Snipping Tool,
Paint, codec, runtime, App Installer (winget). Mọi app đã gỡ đều cài lại được từ Store.

**Registry (sửa trực tiếp trong image):** tắt consumer features/app gợi ý; tắt Copilot (policy);
tắt tin tức Widgets; chặn tự cài Teams/Chat; BypassNRO=1 (cài không cần mạng); user mới tắt gợi ý,
tắt tự cài app, tắt gợi ý ở Start; ẩn nút Chat trên taskbar; xoá tác vụ tự cài Outlook/Dev Home/Cross Device
lúc cài đặt (UScheduler_Oobe).

**autounattend.xml** (đặt ở gốc ISO): tự đồng ý EULA, ẩn màn hình bắt đăng nhập tài khoản Microsoft
để tạo **tài khoản local**. Chọn ổ đĩa, phiên bản, key, vùng, tên tài khoản vẫn do anh chọn khi cài.

Muốn sửa danh sách: mở `config\DebloatConfig.psd1` bằng Notepad.

## Cần biết
- **Không bỏ qua TPM 2.0 / Secure Boot / CPU.** Máy không đủ chuẩn vẫn bị chặn như ISO gốc.
- Gỡ Xbox thì **đăng nhập Xbox / Game Pass và Game Bar sẽ hỏng** cho tới khi cài lại từ Store.
- Bản cập nhật lớn của Windows có thể cài lại Copilot/Outlook/Teams; policy chỉ hạn chế, không chắc chắn 100%.
- Microsoft có thể chặn tải (VPN, vùng, tải quá nhiều – mã 715-123130) → dùng trình duyệt.
- Link tải của Microsoft hết hạn sau khoảng 24 giờ.
- Thư mục làm việc phải ở ổ NTFS trong máy (không dùng ổ mạng).

## Hỗ trợ phiên bản Windows (máy chạy tool)
- **Windows 10 / 11:** mục tiêu chính, đầy đủ tính năng.
- **Windows 8 / 8.1:** thử nghiệm. DISM của Win8 không xử lý được Win11 nên tool dùng DISM có sẵn trong ISO
  (gỡ app bằng cách sửa registry + xoá thư mục, giống bản tham chiếu). ADK mới không cài được →
  chép `oscdimg.exe` từ máy Win10/11 có ADK vào thư mục `tools\`.
- **Windows 7 SP1:** thử nghiệm, ít chắc chắn nhất. Code chạy được trên PowerShell 2.0, nhưng cần:
  **7-Zip** (Win7 không mount được ISO), `oscdimg.exe` chép vào `tools\` (ADK cuối cùng cài được trên Win7
  là ADK 8.1, Microsoft đã gỡ khỏi trang tải), và DISM trong ISO có thể không chạy với driver WIM của Win7.
  Muốn tải ISO trong app cần TLS 1.2: cài KB3140245 + .NET 4.5.2 trở lên (hoặc KB3154518 cho .NET 3.5.1), nên cài WMF 5.1.
  **Khuyên thật:** nên chạy tool trên máy Windows 10/11.

Nút **Kiểm tra máy** (hoặc `run.bat -Check`) báo phiên bản Windows/PowerShell/.NET, TLS 1.2, DISM,
oscdimg, cách mở ISO, dung lượng trống, kèm hướng dẫn tiếng Việt.

## Giấy phép
MIT. Quy trình tải từ Microsoft được cộng đồng mô tả (đặc biệt là Fido, GPL-3.0); tool này tự viết lại,
**không chứa code của Fido**, nên giữ giấy phép MIT.

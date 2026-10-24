# WinDebloat Tool (Windows 10 / 11) – Hướng dẫn tiếng Việt

Công cụ biến **ISO Windows 10 hoặc Windows 11 gốc của Microsoft** thành **ISO gọn nhẹ** (đã gỡ app rác, tắt quảng cáo/gợi ý),
chạy trên Windows, có giao diện, chỉ dùng công cụ của Microsoft (DISM, reg.exe, oscdimg trong Windows ADK).
Không tải phần mềm bên thứ ba.

Tên cũ là *Win11 Debloat Tool*. Từ bản 0.2.0 file chính là `WinDebloatTool.ps1`; file `Win11DebloatTool.ps1`
vẫn giữ để chạy được như cũ, `run.bat` dùng y như trước.

> **Lưu ý trung thực:** tool **chưa được chạy thử trên Windows thật**. Code được viết và kiểm tra trên Linux
> (kiểm tra cú pháp PowerShell, PSScriptAnalyzer, quét tương thích PowerShell 2.0, test giả lập dism/reg).
> Cùng bộ thay đổi này đã được làm thật trên một ISO Win11 bằng công cụ Linux; ISO đó đã boot vào màn hình
> cài đặt Windows trong máy ảo (UEFI + Secure Boot), nhưng chưa thử cài hết. Tool Windows này làm lại đúng quy trình đó bằng công cụ của Microsoft. Lần chạy đầu
> nếu có lỗi, hãy gửi file log. **Bộ gỡ cho Windows 10 mới chỉ được test giả lập, chưa áp dụng lên image Windows 10 thật.**

## Cách dùng nhanh
1. Giải nén file zip, bấm đúp **`run.bat`** → chọn **Yes** khi Windows hỏi quyền Administrator.
2. **Nguồn ISO**:
   - Đã có ISO: bấm **Chọn...** và chọn file.
   - Chưa có: bấm **Lấy danh sách** → chọn phiên bản (Windows 11 hoặc Windows 10 22H2), kiến trúc (x64/arm64/x86), ngôn ngữ (mặc định English US)
     → **Tải**. File tải thẳng từ máy chủ Microsoft và được kiểm tra SHA256 với bảng hash Microsoft công bố.
   - Nếu Microsoft chặn tải trong app: bấm **Mở trang Microsoft**, tải bằng trình duyệt rồi **Chọn...** file đó.
   - Ô **Hệ điều hành** tự nhận Windows 10 hay 11 (xem bên dưới); có thể chọn tay.
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
run.bat -NoGui -IsoPath D:\Win10_22H2_English_x64v1.iso -OutputIso D:\Win10_gon.iso -TargetOs Win10
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf     (chạy thử, không thay đổi gì)
run.bat -Check                                                  (kiểm tra máy)
```

## Windows 10 hay Windows 11? (tự nhận hệ điều hành)
Khi chạy, tool đọc số build của image bằng DISM: **10240–21999 là Windows 10** (22H2 = 19045),
**từ 22000 là Windows 11**, rồi dùng bộ gỡ tương ứng trong `config\DebloatConfig.psd1`.
Giao diện đoán ngay từ tên file, sau đó đọc phần đầu file install.wim trong ISO (Windows 8 trở lên)
hoặc theo bản vừa tải, và đổi danh sách app/tinh chỉnh cho đúng. Trên Windows 7 chỉ đoán theo tên file;
nếu không đoán được thì lúc chạy tool vẫn tự nhận theo image. Ô **Hệ điều hành** (`-TargetOs`) cho phép
chọn tay; nếu chọn khác với image thực tế, log sẽ cảnh báo.

## Tool thay đổi những gì – Windows 11
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

## Tool thay đổi những gì – Windows 10 (22H2)
**Gỡ (mặc định):** 3D Builder, 3D Viewer, Print 3D, Mixed Reality Portal, People (Danh bạ), Skype, Mobile Plans,
Wallet, Messaging, Thời tiết, Tin tức, Get Help, Tips, Office hub, OneNote (bản Store), Solitaire, app Xbox,
Game Bar, Xbox TCUI / Identity Provider / Speech-to-text, Your Phone, Feedback Hub, **Cortana**; nếu bản
ISO mới có thì gỡ thêm Clipchamp, Teams, To Do, Power Automate, Outlook mới, Copilot, Family.
Tuỳ chọn (không tick sẵn): Groove Music, Phim & TV, Bản đồ, Paint 3D, Mail & Lịch, Camera, Báo thức & Đồng hồ,
Ghi âm, Sticky Notes.

**Luôn giữ lại:** Store, Defender/Bảo mật, Edge, Máy tính, Ảnh, Snip & Sketch, Paint cổ điển, codec (HEIF,
WebP, VP9…), runtime (VCLibs, .NET Native, UI.Xaml), App Installer.

**Registry:** tắt consumer features/app gợi ý; user mới tắt tự cài app và gợi ý (ContentDeliveryManager);
tắt Cortana và tìm kiếm web trong ô Search; telemetry mức thấp nhất (AllowTelemetry=0 – bản Home/Pro sẽ
hiểu là mức "Required/Basic", chỉ Enterprise/Education mới về "Security"), tắt ID quảng cáo, tắt hỏi
feedback; tắt News and Interests trên taskbar; ẩn Meet Now; tắt Copilot; xoá tác vụ tự cài Outlook/Dev Home
nếu có. **Tuỳ chọn (không tick sẵn):** gỡ OneDrive setup cho user mới (xoá `Run\OneDriveSetup`).

Không đụng TPM/Secure Boot (Windows 10 không cần). **autounattend.xml** dùng chung, nhưng với Windows 10
tool bỏ lệnh BypassNRO (chỉ dành cho Win11; Win10 vốn đã có lựa chọn "Offline account" khi không có mạng).

Muốn sửa danh sách: mở `config\DebloatConfig.psd1` bằng Notepad (`Apps`/`Tweaks` cho Windows 11,
`Win10Apps`/`Win10Tweaks` cho Windows 10, `Protected` = danh sách không bao giờ gỡ, áp dụng cả hai).

## Cần biết
- **Không bỏ qua TPM 2.0 / Secure Boot / CPU** (Windows 11). Máy không đủ chuẩn vẫn bị chặn như ISO gốc.
- Windows 10 đã hết hỗ trợ từ 14/10/2025 (chỉ còn bản vá qua chương trình ESU), nhưng Microsoft vẫn cho tải ISO.
- Gỡ Xbox thì **đăng nhập Xbox / Game Pass và Game Bar sẽ hỏng** cho tới khi cài lại từ Store.
- Bản cập nhật lớn của Windows có thể cài lại Copilot/Outlook/Teams; policy chỉ hạn chế, không chắc chắn 100%.
- Microsoft có thể chặn tải (VPN, vùng, tải quá nhiều – mã 715-123130) → dùng trình duyệt.
- Link tải của Microsoft hết hạn sau khoảng 24 giờ.
- Thư mục làm việc phải ở ổ NTFS trong máy (không dùng ổ mạng).

## Khi gặp lỗi
- **File log:** giao diện ghi log vào `logs\WinDebloat_gui_<ngày>_<giờ>.log` trong thư mục tool (nếu thư mục
  không ghi được thì vào `%TEMP%`). Bấm **Mở thư mục log** trong cửa sổ để mở. Khi tạo ISO, tool còn ghi
  `WinDebloat_<giờ>.log` cạnh file ISO đầu ra. Gặp lỗi thì gửi các file này.
- **Bấm "Lấy danh sách" không ra / lỗi "remote name could not be resolved: vlscppe.microsoft.com":**
  DNS, phần mềm chặn quảng cáo, file hosts hoặc nhà mạng đang chặn hai tên miền `vlscppe.microsoft.com`
  và `ov-df.microsoft.com` mà Microsoft dùng để chống tải tự động. Từ bản 0.2.1 danh sách vẫn hiện bình
  thường. Nếu đến lúc tải Microsoft báo từ chối (*Sentinel* / 715-123130) thì đổi DNS sang 1.1.1.1 hoặc
  8.8.8.8 (hoặc bỏ chặn hai tên miền trên), tắt VPN, hoặc bấm **Mở trang Microsoft** để tải bằng trình duyệt.
- Nếu hoàn toàn không có mạng, danh sách phiên bản Windows 11 / Windows 10 vẫn hiện; bấm **Tải** sẽ mở
  trang tải chính thức của Microsoft.

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

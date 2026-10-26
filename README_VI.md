# WinDebloat Tool (Windows 10 / 11) – Hướng dẫn tiếng Việt

Công cụ biến **ISO Windows 10 hoặc Windows 11 gốc của Microsoft** thành **ISO gọn nhẹ** (đã gỡ app rác, tắt quảng cáo/gợi ý),
chạy trên Windows, có giao diện, chỉ dùng công cụ của Microsoft (DISM, reg.exe, oscdimg trong Windows ADK).
Phần mềm bên thứ ba duy nhất là **aria2** (GPLv2, giữ nguyên bản gốc) đi kèm để tải ISO nhanh hơn bằng nhiều luồng – xem mục *Bên thứ ba*.

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
   - Chưa có: chọn bản (mọi bản Windows 11 21H2…26H2 và Windows 10 1507…22H2 Microsoft còn cung cấp), kiến trúc
     (x64/arm64/x86) → bấm **Lấy ngôn ngữ** → chọn ngôn ngữ (mặc định English US) → **Tải về**. File tải thẳng từ máy chủ Microsoft và được kiểm tra SHA256 với bảng hash Microsoft công bố.
   - Nếu Microsoft chặn tải trong app: bấm **Mở trang Microsoft**, tải bằng trình duyệt rồi **Chọn...** file đó.
   - Ô **Hệ điều hành** tự nhận Windows 10 hay 11 (xem bên dưới); có thể chọn tay.
3. Tick các app muốn gỡ (mặc định đã chọn sẵn), tinh chỉnh registry, phiên bản (Tất cả / Home+Pro / nhập index).
4. Chọn nơi lưu ISO đầu ra → bấm **BẮT ĐẦU**. Mất khoảng 20–60 phút, cần trống khoảng **25 GB**.
   Bấm **Huỷ** thì tool dừng sau bước đang chạy (bước DISM không ngắt giữa chừng được).
5. Kết quả: file `.iso`, `.iso.sha256`, file log, và `kept_indexN.txt` (danh sách app còn lại).
6. Ghi ra USB bằng **Rufus** hoặc **Ventoy** (install.wim lớn hơn 4 GB nên chép thẳng vào USB FAT32 sẽ lỗi).

Nếu thiếu **oscdimg.exe**, bấm **Cài oscdimg** (hoặc **BẮT ĐẦU**, tool cũng kiểm tra): tool chỉ cài phần
*Deployment Tools* của Windows ADK chính thức (`adksetup.exe /features OptionId.DeploymentTools /quiet`, có
kiểm tra chữ ký số) hoặc cài qua winget. Tự tải: <https://learn.microsoft.com/windows-hardware/get-started/adk-install>.

Nút **Tải về** chỉ hỏi thư mục lưu (mặc định là thư mục dùng lần trước, nếu không có thì `%USERPROFILE%\Downloads`),
không cần ô ISO đầu ra. Ô ISO đầu ra để trống thì **BẮT ĐẦU** tự dùng `<tên ISO nguồn>_debloated.iso` cạnh
file nguồn. Đường dẫn trống hoặc sai sẽ có thông báo ngắn thay vì báo lỗi.

### Ngôn ngữ giao diện
Tiếng Việt (mặc định), English, 简体中文 và ភាសាខ្មែរ – chọn ở ô cạnh **Mở thư mục nhật ký**, đổi ngay lập tức
và được nhớ trong `settings.psd1` (trong thư mục tool, nếu không ghi được thì `%APPDATA%\WinDebloatTool`).
Chữ nằm trong `lang\*.psd1` (UTF-8 có BOM). Phông: Segoe UI; tiếng Trung dùng Microsoft YaHei UI →
Microsoft YaHei; tiếng Khmer dùng Leelawadee UI (Windows 8+) → Khmer UI (Windows 7) → DaunPenh. Khung nhật ký
hiện tiếng Anh kèm tiếng Việt khi giao diện là tiếng Việt; file nhật ký luôn có cả hai.
**Bản tiếng Trung và tiếng Khmer được dịch với sự hỗ trợ của máy** – rất mong người bản ngữ góp ý, sửa
(sửa `lang\zh-CN.psd1` / `lang\km.psd1`, giữ nguyên `{0}`; `tests/Test-Offline.ps1` kiểm tra đủ khoá).

Chạy dòng lệnh (không giao diện):
```
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_gon.iso -Edition HomePro
run.bat -NoGui -IsoPath D:\Win10_22H2_English_x64v1.iso -OutputIso D:\Win10_gon.iso -TargetOs Win10
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf     (chạy thử, không thay đổi gì)
run.bat -Check                                                  (kiểm tra máy)
```

## Tải từ Microsoft
- **Các bản Windows:** danh sách gồm mọi bản mà hệ thống tải của Microsoft còn phục vụ. Kiểm tra trực tiếp
  ngày 25/10/2026: tất cả đều lấy được ngôn ngữ và link tải – Windows 11 26H2, 25H2 (+v2), 24H2 (x64 + ARM64);
  23H2, 22H2 v1 + v2, 21H2 (x64); Windows 10 22H2 về tới 1507 (x64 + x86). Bản Windows 11 22H2 đầu tiên
  (mã 2360) được đánh dấu không còn cung cấp vì máy chủ tải trả lỗi HTTP 400. Lỗi *SentinelReject* thường
  ngẫu nhiên nên tool tự thử lại với phiên mới; lỗi 715-123130 (IP, khu vực hoặc VPN bị chặn) thì không thử lại. Nếu Microsoft gỡ bản nào, bấm **Lấy ngôn ngữ**
  sẽ báo "Microsoft không còn cung cấp bản này, hãy dùng file ISO có sẵn". Microsoft chỉ công bố SHA256 cho các
  bản mới nhất; với bản cũ, mã SHA256 được ghi vào log để anh tự đối chiếu.
- **aria2** (có sẵn trong `tools\aria2\x64|x86\aria2c.exe`; hoặc `tools\aria2c.exe`, cạnh script, hoặc trong PATH):
  tải 16 luồng (`-x16 -s16 -k1M`), tải tiếp được, luôn kiểm tra chứng chỉ; chỉnh trong mục `Download` của
  `config\DebloatConfig.psd1`. Ô **Dùng aria2 (tải đa luồng)** bật sẵn khi tìm thấy aria2; tốc độ và số luồng
  hiện ở dòng trạng thái; bấm **Huỷ** sẽ dừng aria2c ngay (bấm **Tải về** lại để tải tiếp).
  Nếu aria2 lỗi (ví dụ 403), tool ghi cảnh báo và tự chuyển sang bộ tải một luồng có sẵn (cũng tải tiếp được).
- **Windows 7:** aria2 1.37 dùng TLS của Windows; thiếu bản cập nhật TLS 1.2 (KB3140245) thì aria2 lỗi và tool
  tự chuyển sang bộ tải có sẵn (chưa thử trên Win7).

## Nguồn dự phòng (không phải Microsoft, chỉ dùng khi đồng ý)
Tool luôn tải từ Microsoft trước. Chỉ khi Microsoft không cung cấp được (bản đã bị gỡ, bị chặn *Sentinel* /
715-123130, máy chủ tải lỗi), thông báo lỗi mới hỏi thêm: **Yes = thử bản sao file gốc của Microsoft
được liệt kê trên [massgrave.dev](https://massgrave.dev/genuine-installation-media)**, No = mở trang
Microsoft, Cancel = đóng.
- Hộp thoại tiếp theo ghi rõ tên file, máy chủ tải và mã SHA256 mong đợi, kèm lời nhắc máy chủ đó **không
  phải của Microsoft**. Không bấm *Yes* thì không có gì xảy ra. Tên máy chủ được ghi vào nhật ký.
- Các trang lưu file (buzzheavier.com, zerofs.link) chỉ có trang tải, nên tool mở trang đó trong trình
  duyệt. Tải xong, hãy chọn file trong hộp thoại vừa hiện ra.
- **Bắt buộc kiểm tra SHA256.** File chỉ được nhận khi SHA256 trùng với mã của file gốc Microsoft (MSDN).
  Không trùng thì file **bị xoá** và tool báo cả hai mã. Tool không bao giờ chạy file đã tải; ISO chỉ được
  DISM đọc như khi tạo ISO bình thường.
- Danh sách có sẵn (chỉ tiếng Anh Mỹ; 10 mục `Mirrors` trong `config\DebloatConfig.psd1`): Windows 11 26H2
  consumer / business x64, Windows 10 22H2 (bản 10/2025) consumer / business x64 + x86, Windows 11
  Enterprise LTSC 2024 và IoT Enterprise LTSC 2024 x64, Windows 10 Enterprise LTSC 2021 x64 + x86.
  Trang link của massgrave.dev không công bố mã hash, nên mỗi mã SHA256 được lấy từ hai danh sách độc lập
  (msnews.ru, và ntriver.org / macrohard0.github.io) và hai bên khớp nhau (25/10/2026). Mã của bản 26H2
  consumer cũng trùng với mã Microsoft công bố. File nào chưa xác nhận được mã thì không đưa vào.
- Muốn thêm: chép một mục rồi sửa `FileName`, `Url`, `Sha256` (mã của file gốc Microsoft), `Os`, `Arch`,
  `Release`, `Kind`. Mục không có SHA256 hợp lệ (64 ký tự) sẽ không bao giờ được đề xuất.

## Windows 10 hay Windows 11? (tự nhận hệ điều hành)
Khi chạy, tool đọc số build của image bằng DISM: **10240–21999 là Windows 10** (22H2 = 19045),
**từ 22000 là Windows 11**, rồi dùng bộ gỡ tương ứng trong `config\DebloatConfig.psd1`.
Giao diện đoán ngay từ tên file, sau đó đọc phần đầu file install.wim trong ISO (Windows 8 trở lên)
hoặc theo bản vừa tải, và đổi danh sách app/tinh chỉnh cho đúng. Trên Windows 7 chỉ đoán theo tên file;
nếu không đoán được thì lúc chạy tool vẫn tự nhận theo image. Ô **Hệ điều hành** (`-TargetOs`) cho phép
chọn tay; nếu chọn khác với image thực tế, log sẽ cảnh báo.

**Danh sách theo đúng bản:** số build còn cho biết bản cụ thể (19045 = Win10 22H2; 22000 = Win11 21H2, 22621 = 22H2,
22631 = 23H2, 26100 = 24H2, 26200 = 25H2, 26300 trở lên = 26H2). Mỗi mục trong `DebloatConfig.psd1` có thể có
`MinBuild` / `MaxBuild`; giao diện hiện ví dụ *Windows 11 24H2 (26100)* và chỉ liệt kê mục hợp với bản đó
(24H2 không còn Cortana, 21H2 chưa có Clipchamp/Outlook). App có trong danh sách nhưng không có trong image thì
được bỏ qua và ghi vào log.

## Tool thay đổi những gì – Windows 11
**Gỡ (mặc định):** Clipchamp, Teams mới, Outlook mới, Tin tức, Bing Search, Thời tiết, app Xbox, Game Bar,
Solitaire, Microsoft 365 hub,
Power Automate, To Do, Dev Home, Feedback Hub, Phone Link, Cross Device, Quick Assist, Copilot, Family;
bản cũ thì gỡ thêm Cortana, Maps, People, Tips, Copilot provider, Teams cũ.
Tuỳ chọn (không tick sẵn): Widgets, Media Player, Phim & TV, Camera, Đồng hồ, Ghi âm, Sticky Notes, Mail & Lịch,
và các mục ghi *unsafe* (gỡ đi có thể hỏng game, hộp thoại Store, đăng nhập Xbox hoặc trình sửa lỗi): Xbox TCUI,
Xbox Identity Provider, Xbox Speech-to-text, Get Help (đến bản 0.3.0 vẫn gỡ mặc định).

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
Wallet, Messaging, Thời tiết, Tin tức, Tips, Office hub, OneNote (bản Store), Solitaire, app Xbox,
Game Bar (Xbox TCUI / Identity Provider / Speech-to-text và Get Help vẫn có trong danh sách nhưng không tick sẵn), Your Phone, Feedback Hub, **Cortana**; nếu bản
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
  không ghi được thì vào `%TEMP%`). Bấm **Mở thư mục nhật ký** trong cửa sổ để mở. Khi tạo ISO, tool còn ghi
  `WinDebloat_<giờ>.log` cạnh file ISO đầu ra. Gặp lỗi thì gửi các file này.
- **Bấm "Lấy ngôn ngữ" không ra / lỗi "remote name could not be resolved: vlscppe.microsoft.com":**
  DNS, phần mềm chặn quảng cáo, file hosts hoặc nhà mạng đang chặn hai tên miền `vlscppe.microsoft.com`
  và `ov-df.microsoft.com` mà Microsoft dùng để chống tải tự động. Từ bản 0.2.1 danh sách vẫn hiện bình
  thường. Nếu đến lúc tải Microsoft báo từ chối (*Sentinel* / 715-123130) thì đổi DNS sang 1.1.1.1 hoặc
  8.8.8.8 (hoặc bỏ chặn hai tên miền trên), tắt VPN, hoặc bấm **Mở trang Microsoft** để tải bằng trình duyệt.
- **ISO đầu ra to hơn ISO gốc:** mỗi phiên bản (Home, Pro, Education...) sau khi sửa sẽ lưu riêng phần file đã
  thay đổi, nên chọn **Tất cả** (khoảng 10 phiên bản) làm ISO to lên nhiều. Hãy chọn **Home + Pro** hoặc chỉ các
  phiên bản cần dùng, và/hoặc bật **Nén kiểu ESD** (ISO nhỏ nhất, chậm hơn). Trong log, các dòng `SIZE ...` cho
  biết dung lượng ở từng bước; nếu ISO to hơn ISO gốc quá 500 MB, log có dòng `WARN` kèm danh sách file lớn nhất.
- Nếu hoàn toàn không có mạng, danh sách phiên bản Windows 11 / Windows 10 vẫn hiện; bấm **Tải về** sẽ mở
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

## Bên thứ ba
- Code của tool dùng giấy phép MIT. Thư mục `tools\aria2\` chứa **aria2 1.37.0** (`aria2c.exe`) bản Windows chính thức,
  giấy phép **GPLv2**, giữ nguyên không sửa, chạy như một chương trình riêng (chỉ đóng gói chung – "mere aggregation").
  Giấy phép, README, AUTHORS, NEWS và `NOTICE.txt` (link gốc, SHA256 của file zip và exe, link mã nguồn) nằm trong thư mục đó.
  Muốn cập nhật, thay `aria2c.exe` bằng bản chính thức mới hơn.

## Ghi công
- **Icon ứng dụng và icon trên các nút:** vẽ riêng cho dự án này (file SVG gốc trong `assets/`, dựng lại bằng
  `python3 assets/build_assets.py`), giấy phép MIT như code. Icon là các ô cửa sổ cách điệu cùng cây chổi, không phải
  logo Windows của Microsoft.
- **[Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)** (MIT): danh sách ứng dụng và mức đánh giá an toàn /
  tuỳ chọn / không an toàn (`Config/Apps.json`, trang wiki *App Removal*) là nguồn tham khảo chính cho danh sách gỡ.
  Không sao chép code.
- **[pbatard/Fido](https://github.com/pbatard/Fido)** (GPL-3.0): mô tả quy trình tải ISO từ Microsoft mà
  `lib/MsDownload.ps1` tự viết lại (không chứa code của Fido).

## Giấy phép
MIT. Quy trình tải từ Microsoft được cộng đồng mô tả (đặc biệt là Fido, GPL-3.0); tool này tự viết lại,
**không chứa code của Fido**, nên giữ giấy phép MIT.

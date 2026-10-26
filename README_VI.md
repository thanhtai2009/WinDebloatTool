<p align="center">
  <img src="assets/icon-256.png" alt="WinDebloat Tool" width="128">
</p>

<h1 align="center">WinDebloat Tool</h1>

<p align="center">
  Biến ISO Windows 10 / Windows 11 gốc của Microsoft thành ISO cài đặt gọn nhẹ, sạch ứng dụng thừa.
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

WinDebloat Tool gỡ các ứng dụng cài sẵn, tắt quảng cáo, gợi ý và tự cài ứng dụng **ngay trong bộ cài
Windows**. Nhờ vậy, mọi máy cài từ ISO này đều sạch ngay từ đầu. Công cụ chạy trên Windows, có giao diện
đồ hoạ và chế độ dòng lệnh, chỉ dùng công cụ của Microsoft (DISM, reg.exe, oscdimg). Chương trình bên
thứ ba duy nhất đi kèm là aria2, dùng để tải ISO nhanh hơn.

## Mục lục
- [Tính năng](#tính-năng)
- [Yêu cầu](#yêu-cầu)
- [Bắt đầu nhanh](#bắt-đầu-nhanh)
- [Hướng dẫn giao diện](#hướng-dẫn-giao-diện)
- [Chế độ dòng lệnh](#chế-độ-dòng-lệnh)
- [Mẫu cấu hình](#mẫu-cấu-hình)
- [Tích hợp bản cập nhật offline](#tích-hợp-bản-cập-nhật-offline)
- [File trả lời tự động (autounattend.xml)](#file-trả-lời-tự-động-autounattendxml)
- [Sửa danh sách ứng dụng và tinh chỉnh](#sửa-danh-sách-ứng-dụng-và-tinh-chỉnh)
- [Phiên bản Windows được hỗ trợ](#phiên-bản-windows-được-hỗ-trợ)
- [Những gì được thay đổi](#những-gì-được-thay-đổi)
- [Nguồn tải ISO](#nguồn-tải-iso)
- [Ngôn ngữ](#ngôn-ngữ)
- [Câu hỏi thường gặp và xử lý lỗi](#câu-hỏi-thường-gặp-và-xử-lý-lỗi)
- [Lưu ý an toàn](#lưu-ý-an-toàn)
- [Ghi công](#ghi-công)
- [Giấy phép](#giấy-phép)

## Tính năng
- **Hỗ trợ Windows 10 và Windows 11:** tự nhận diện hệ điều hành và bản phát hành theo số build trong
  image, rồi chọn danh sách ứng dụng và tinh chỉnh phù hợp. Cũng có thể chọn tay.
- **Tải ISO gốc từ Microsoft ngay trong công cụ:** mọi bản Windows 11 (21H2 – 26H2) và Windows 10
  (1507 – 22H2) mà Microsoft còn cung cấp, đủ ngôn ngữ và kiến trúc. Tải đa luồng bằng aria2 (16 kết nối),
  tải tiếp được khi bị ngắt. Kiểm tra SHA256 nếu Microsoft có công bố.
- **Gỡ ứng dụng:** danh sách ứng dụng cài sẵn (Clipchamp, Teams, Outlook mới, Copilot, Xbox, Tin tức,
  Thời tiết, Solitaire, Liên kết Điện thoại...). Mặc định an toàn, có mục tuỳ chọn thêm; các gói dễ gây
  lỗi được đánh dấu *không an toàn* và để trống.
- **Tinh chỉnh Registry ngay trong image:** tắt tính năng quảng cáo, Copilot, tin tức Widgets, tự cài
  Teams/Chat, gợi ý cho người dùng mới và tác vụ tự cài ứng dụng khi cài đặt. Trên Windows 10 còn tắt
  Cortana và tìm kiếm web, giảm thu thập dữ liệu chẩn đoán xuống mức thấp nhất và ẩn Tin tức và sở thích.
- **Thêm tinh chỉnh quyền riêng tư (tuỳ chọn, mặc định tắt):** giảm dữ liệu chẩn đoán, mã quảng cáo,
  trải nghiệm cá nhân hoá, kết quả web trong ô tìm kiếm, Recall, Widgets, Reserved Storage, tự cài OneDrive.
- **Chọn phiên bản Windows:** giữ tất cả, chỉ Home và Pro, hoặc theo số thứ tự.
- **Tự tạo autounattend.xml (tuỳ chọn):** tài khoản cục bộ (mật khẩu tuỳ chọn), BypassNRO, bỏ kiểm tra
  TPM / Secure Boot / RAM, vùng và bàn phím, bỏ qua câu hỏi quyền riêng tư, script dọn dẹp ở lần đăng nhập
  đầu. Dùng được cho Windows 10 và 11, x64 và ARM64. **Phần chia ổ đĩa luôn do bạn tự chọn khi cài.**
- **Tích hợp bản cập nhật offline (tuỳ chọn):** tích hợp các file `.msu` / `.cab` bạn đã tải (SSU, bản
  cập nhật tích luỹ, .NET, Safe OS) theo đúng thứ tự, có thể cập nhật cả `boot.wim` và WinRE.
- **Mẫu cấu hình:** có sẵn *An toàn* và *Gọn tối đa*; lưu lựa chọn của bạn ra file `.json` để lần sau mở
  lại (trong giao diện hoặc bằng `-Preset`).
- **Danh sách dạng JSON:** ứng dụng và tinh chỉnh nằm trong `data/apps.json` và `data/tweaks.json`, có tên
  ở mọi ngôn ngữ giao diện. Giao diện dựng danh sách đánh dấu từ hai file này.
- **Tuỳ chọn dung lượng:** nén thường (`install.wim`) hoặc nén kiểu ESD (`install.esd`, ISO nhỏ nhất).
  Có thể chia `install.wim` lớn hơn 4 GB để chép vào USB FAT32. Có tuỳ chọn dọn WinSxS.
- **ISO khởi động được:** ISO chạy cả BIOS lẫn UEFI, tạo bằng oscdimg, kèm file SHA256. Nút **Cài
  oscdimg** chỉ cài phần Deployment Tools của Windows ADK chính thức.
- **Thư mục tạm an toàn:** file tạm không bao giờ lọt vào ISO. Thư mục tạm luôn được dọn sau khi chạy
  xong, bị lỗi hay bị huỷ. Thư mục còn sót từ lần trước được tự nhận ra và dọn; thư mục chứa file của
  người khác thì không bao giờ bị xoá.
- **Nhật ký rõ ràng:** mọi bước đều ghi vào file nhật ký, có dung lượng image và ISO, và cảnh báo nếu ISO
  đầu ra lớn hơn nhiều so với ISO gốc.
- **Giao diện 4 ngôn ngữ:** tiếng Việt, tiếng Anh, tiếng Trung giản thể và tiếng Khmer.

## Yêu cầu
| | |
|---|---|
| Hệ điều hành | Windows 7 SP1 trở lên (nên dùng Windows 10 / 11) |
| PowerShell | 2.0 trở lên (có sẵn trong Windows) |
| Quyền | Administrator (`run.bat` tự xin quyền) |
| oscdimg | Thuộc bộ *Deployment Tools* của Windows ADK. Bấm **Cài oscdimg** trong công cụ, hoặc chép `oscdimg.exe` vào thư mục `tools\` |
| Dung lượng trống | Khoảng 25 GB trên ổ chứa thư mục đầu ra (thư mục tạm được tạo ở đó) |
| Mạng | Chỉ cần khi tải ISO; tạo ISO từ file có sẵn thì không cần mạng |

## Bắt đầu nhanh
1. Tải `WinDebloatTool_v1.1.0.zip` và giải nén ra một thư mục.
2. Bỏ chặn file một lần: chuột phải vào file zip → **Thuộc tính** (Properties) → đánh dấu **Bỏ chặn** (Unblock) *trước khi*
   giải nén. Hoặc sau khi giải nén, chạy trong PowerShell 3.0 trở lên:
   `Get-ChildItem -Recurse 'C:\duong\dan\WinDebloatTool' | Unblock-File`
3. Bấm đúp **`run.bat`** và đồng ý cấp quyền Administrator. Cũng có thể chạy `WinDebloatTool.ps1` từ
   PowerShell đang chạy với quyền Administrator.
4. Chọn ISO nguồn, chọn ứng dụng và tuỳ chọn, rồi bấm **BẮT ĐẦU**.
5. Ghi ISO ra USB bằng **Rufus** hoặc **Ventoy**, hoặc dùng cho máy ảo.

Mỗi lần tạo mất khoảng 20–60 phút. Thư mục đầu ra sẽ có file ISO, `<tên>.iso.sha256`, file nhật ký
`WinDebloat_<giờ>.log` và các file `kept_indexN.txt` (danh sách ứng dụng còn lại trong từng phiên bản).

## Hướng dẫn giao diện
**1. ISO nguồn**
- **File ISO có sẵn trên máy:** bấm *Chọn...* để chọn file ISO.
- **Tải ISO gốc từ Microsoft:** chọn phiên bản và kiến trúc, bấm *Lấy ngôn ngữ*, chọn ngôn ngữ rồi bấm
  *Tải về*. ISO được lưu vào thư mục bạn chọn và tự điền vào ô nguồn.
- **Hệ điều hành:** *Tự nhận diện* đọc số build trong image và hiện ra, ví dụ *Windows 11 24H2 (26100)*.
  Có thể chọn cố định Windows 10 hoặc Windows 11.

**2. Ứng dụng sẽ gỡ**: danh sách khớp với bản Windows đã nhận diện. Các nút *Mặc định*, *Chọn hết*,
*Bỏ hết* giúp chọn nhanh. Ứng dụng không có trong image sẽ được bỏ qua và ghi vào nhật ký.

**3. Tuỳ chọn** gồm ba thẻ:
- **Tuỳ chọn**
  - **Phiên bản Windows:** *Tất cả*, *Home + Pro*, hoặc *Số thứ tự* (ví dụ `1,6`). Nút *Xem các phiên
    bản trong ISO* cho biết số thứ tự của từng phiên bản.
  - **Tinh chỉnh Registry:** đánh dấu các tinh chỉnh muốn dùng (xem
    [Những gì được thay đổi](#những-gì-được-thay-đổi)). Rê chuột lên một tinh chỉnh để xem mô tả; nhãn
    *[mạnh tay]* là tinh chỉnh có thể gây tác dụng phụ.
  - **Dọn WinSxS (chậm):** chạy `DISM /Cleanup-Image /StartComponentCleanup` cho từng phiên bản.
  - **Nén kiểu ESD:** tạo `install.esd`, ISO nhỏ nhất nhưng chạy lâu hơn nhiều.
  - **Chạy thử:** chỉ cho biết sẽ làm gì, không thay đổi gì.
- **Cài đặt tự động**: các tuỳ chọn cho file trả lời (xem
  [File trả lời tự động](#file-trả-lời-tự-động-autounattendxml)).
- **Cập nhật**: thư mục chứa file `.msu` / `.cab`, nút *Kiểm tra gói* để liệt kê theo thứ tự tích hợp, và
  các tuỳ chọn cho `boot.wim`, WinRE, ResetBase (xem [Tích hợp bản cập nhật offline](#tích-hợp-bản-cập-nhật-offline)).

**Mẫu cấu hình** (hàng dưới các danh sách): chọn *An toàn*, *Gọn tối đa* hoặc mẫu đã mở rồi bấm *Áp dụng*;
*Mở...* để mở file mẫu `.json`, *Lưu...* để lưu lựa chọn hiện tại (không bao giờ lưu mật khẩu).

**4. ISO đầu ra**: đường dẫn file ISO sẽ tạo. Để trống thì công cụ tạo `<tên nguồn>_debloated.iso` cạnh
file nguồn.

Hàng nút dưới cùng:
- **Kiểm tra máy:** báo phiên bản Windows, PowerShell, .NET, TLS 1.2, DISM, oscdimg và dung lượng trống.
- **Cài oscdimg:** cài phần Deployment Tools của Windows ADK.
- **BẮT ĐẦU** / **Huỷ:** bắt đầu hoặc dừng quá trình tạo ISO.
- *Mở thư mục nhật ký*: mở thư mục chứa file nhật ký.

## Chế độ dòng lệnh
```bat
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_gon.iso -Edition HomePro
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_nho.iso -Compression Recovery
run.bat -NoGui -IsoPath D:\Win10_22H2_English_x64v1.iso -OutputIso D:\Win10_gon.iso -TargetOs Win10
run.bat -IsoPath D:\Win11.iso -OutputIso D:\out.iso -WhatIf     # chạy thử
run.bat -Check                                                 # chỉ kiểm tra máy
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_min.iso -Preset aggressive
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_upd.iso -UpdatesPath D:\Updates -UpdateWinRE
run.bat -NoGui -IsoPath D:\Win11.iso -OutputIso D:\Win11_auto.iso -LocalUser Tai -SkipPrivacy -Locale vi-VN -FirstLogonCleanup
```

| Tham số | Ý nghĩa |
|---|---|
| `-IsoPath <file>` | ISO nguồn (có tham số này là chạy dòng lệnh) |
| `-OutputIso <file>` | ISO sẽ tạo |
| `-NoGui` | Chạy dòng lệnh, không mở giao diện |
| `-Edition All\|HomePro\|Custom` | Phiên bản giữ lại (mặc định `All`) |
| `-Indexes 1,6` | Số thứ tự phiên bản khi dùng `-Edition Custom` |
| `-TargetOs Auto\|Win10\|Win11` | Hồ sơ áp dụng (mặc định `Auto`, nhận diện theo image) |
| `-NoAutounattend` | Không thêm `autounattend.xml` |
| `-Preset safe\|aggressive\|<file.json>` | Dùng mẫu cấu hình; tham số bạn ghi rõ sẽ được ưu tiên hơn mẫu |
| `-LocalUser <tên>` | File trả lời: tạo tài khoản cục bộ (quản trị) với tên này |
| `-LocalPassword <mật khẩu>` | Mật khẩu (lưu dạng chữ thường trên ISO). Không ghi thì công cụ hỏi; để trống = không mật khẩu |
| `-NoBypassNro` | Windows 11: không bật BypassNRO |
| `-BypassChecks` | Windows 11: bỏ kiểm tra TPM / Secure Boot / RAM khi cài |
| `-SkipPrivacy` | Bỏ qua các câu hỏi quyền riêng tư (chọn mức tối thiểu) |
| `-FirstLogonCleanup` | Lần đăng nhập đầu: gỡ lại các ứng dụng đã chọn nếu bị cài lại |
| `-Locale vi-VN` / `-Keyboard 042a:0000042a` | Vùng (định dạng, vị trí) và bàn phím; để trống = hỏi khi cài |
| `-AutounattendPath <file>` | Dùng file trả lời của bạn thay cho file tự tạo |
| `-UpdatesPath <thư mục>` | Tích hợp các file `.msu` / `.cab` trong thư mục này |
| `-UpdateBootWim` | Cập nhật cả `boot.wim` (trình cài đặt) với SSU + LCU |
| `-UpdateWinRE` | Cập nhật cả WinRE (`Winre.wim`) với SSU + Safe OS |
| `-ResetBase` | Chạy `StartComponentCleanup /ResetBase` sau khi cập nhật (nhỏ hơn, nhưng không gỡ được bản cập nhật) |
| `-ComponentCleanup` | Dọn WinSxS cho từng phiên bản |
| `-Compression Max\|Recovery` | `Max` = `install.wim` nén thường (mặc định); `Recovery` = `install.esd`, nhỏ nhất, chậm hơn |
| `-SplitWimMB <MB>` | Chia `install.wim` lớn hơn 4 GB thành các phần `install*.swm`, ví dụ `3800` cho USB FAT32 |
| `-WorkDir <thư mục>` | Thư mục tạm (mặc định `<thư mục đầu ra>\WinDebloat_work`) |
| `-KeepWorkDir` | Giữ lại thư mục tạm sau khi chạy |
| `-MinFreeGB <số>` | Dung lượng trống tối thiểu (mặc định `25`) |
| `-OscdimgPath <file>` | Đường dẫn `oscdimg.exe` nếu công cụ không tự tìm thấy |
| `-DryRun` / `-WhatIf` | Chạy thử, không thay đổi gì |
| `-Check` | Chỉ kiểm tra máy |

`Win11DebloatTool.ps1` là tên gọi khác của `WinDebloatTool.ps1`, nhận cùng các tham số.

## Mẫu cấu hình
Mẫu cấu hình lưu lại các lựa chọn: phiên bản Windows, ứng dụng, tinh chỉnh, tuỳ chọn file trả lời (không
bao giờ lưu mật khẩu), tuỳ chọn cập nhật, kiểu nén và dọn WinSxS.

| Mẫu | Tác dụng |
|---|---|
| **An toàn** (`safe`) | Lựa chọn mặc định: mọi phiên bản, ứng dụng và tinh chỉnh mặc định, nén thường. |
| **Gọn tối đa** (`aggressive`) | Chỉ Home + Pro, gỡ thêm ứng dụng tuỳ chọn, bật mọi tinh chỉnh trừ bỏ kiểm tra TPM, bỏ qua câu hỏi quyền riêng tư, dọn dẹp ở lần đăng nhập đầu, nén ESD và dọn WinSxS. Không bao giờ chọn gói *không an toàn*. |

Trong giao diện, chọn mẫu rồi bấm **Áp dụng**, hoặc **Lưu...** / **Mở...** file `.json` của bạn. Ở dòng
lệnh dùng `-Preset safe`, `-Preset aggressive` hoặc `-Preset D:\cua-toi.json`; tham số ghi rõ được ưu
tiên. Định dạng (`"schema": "windebloat-preset/1"`):

```json
{
  "schema": "windebloat-preset/1",
  "name": { "vi": "Của tôi", "en": "Mine" },
  "editions": { "mode": "All | HomePro | Custom", "indexes": [1, 6] },
  "apps":   { "select": "defaults | level | list | all | none", "level": "safe | aggressive", "ids": [], "exclude": [] },
  "tweaks": { "select": "list", "ids": ["BypassNRO", "CopilotOff"] },
  "unattend": { "enabled": true, "localAccount": true, "userName": "Tai", "bypassNro": true, "bypassChecks": false,
                "skipPrivacy": true, "firstLogonCleanup": true, "locale": "vi-VN", "keyboard": "042a:0000042a" },
  "updates": { "enabled": false, "folder": "", "bootWim": false, "winre": false, "resetBase": false },
  "image": { "compression": "Max | Recovery", "componentCleanup": false }
}
```
Mẫu có chứa `"password"` sẽ bị từ chối. Mã ứng dụng hoặc tinh chỉnh không có trong danh sách sẽ được bỏ qua
(có thể là mã của phiên bản Windows còn lại).

## Tích hợp bản cập nhật offline
Công cụ **không** tự tải bản cập nhật. Hãy tải từ
[Microsoft Update Catalog](https://www.catalog.update.microsoft.com/) (tìm theo số KB của tháng, đúng phiên
bản và kiến trúc) rồi để chung một thư mục:

```
D:\Updates\
  ssu\        windows10.0-kb5005112-x64.msu         (SSU, nếu là file riêng)
  windows11.0-kb5043080-x64.msu                       (bản tích luỹ checkpoint - KB cũ hơn được tích hợp trước)
  windows11.0-kb5044284-x64.msu                       (bản tích luỹ mới nhất)
  netfx\      windows11.0-kb5044033-x64-ndp481.msu   (bản tích luỹ .NET Framework)
  safeos\     windows11.0-kb5044615-x64.cab          (Safe OS dynamic update, cho WinRE)
```
Loại gói được nhận theo thư mục con (`ssu`, `lcu`, `netfx` / `dotnet`, `safeos` / `winre`) hoặc theo tên
file (`SSU-*`, `*ndp*`, `*netfx*`, `*safeos*`); còn lại được coi là bản tích luỹ (LCU). Trên Windows, công
cụ còn xem bên trong từng file `.msu` để nhận ra gói gộp SSU + LCU. Thứ tự: **SSU → LCU (KB cũ trước) →
.NET**. `install.wim` nhận SSU + LCU + .NET, `boot.wim` (tuỳ chọn) nhận SSU + LCU ở mọi index, WinRE (tuỳ
chọn) nhận SSU + Safe OS. Gói không phù hợp (0x800f081e) hoặc bị lỗi chỉ được ghi cảnh báo, công cụ vẫn
tiếp tục với gói kế tiếp.

**ResetBase** chạy `DISM /Cleanup-Image /StartComponentCleanup /ResetBase` sau khi cập nhật: image nhỏ hơn,
nhưng không gỡ được các bản cập nhật đã tích hợp. Tích hợp bản cập nhật làm thời gian tạo ISO tăng nhiều
(thường thêm 20–40 phút cho mỗi phiên bản).

## File trả lời tự động (autounattend.xml)
Thẻ **Cài đặt tự động** (hoặc các tham số dòng lệnh ở trên) tạo `autounattend.xml` ở gốc ISO. Khi không
chọn gì thêm, file giống hệt bản 1.0 (tự đồng ý điều khoản, ẩn trang tài khoản Microsoft, BypassNRO trên
Windows 11).

| Tuỳ chọn | Tác dụng |
|---|---|
| Tài khoản cục bộ | Tạo sẵn tài khoản cục bộ có quyền quản trị. Mật khẩu là tuỳ chọn và được lưu **dạng chữ thường** trong `autounattend.xml` – đừng chia sẻ ISO đó. |
| BypassNRO | Windows 11: cài được khi không có mạng / không cần tài khoản Microsoft. |
| Bỏ kiểm tra TPM / Secure Boot / RAM | Windows 11: đặt `LabConfig` trong lúc trình cài đặt chạy (bước windowsPE). Với máy không đủ yêu cầu, có thể đánh dấu thêm tinh chỉnh *Bỏ qua kiểm tra TPM, Secure Boot, RAM, CPU khi cài*, tinh chỉnh này ghi cả vào `boot.wim`. |
| Vùng / bàn phím | Định dạng, vị trí và bàn phím; để *(hỏi khi cài)* nếu muốn chọn lúc cài. Ngôn ngữ trình cài đặt luôn là ngôn ngữ của image. |
| Bỏ qua câu hỏi quyền riêng tư | Tự trả lời các trang quyền riêng tư ở mức tối thiểu. |
| Dọn dẹp ở lần đăng nhập đầu | Chạy một script một lần khi đăng nhập lần đầu, gỡ lại các ứng dụng đã chọn nếu trình cài đặt hoặc OOBE cài lại chúng (nhật ký: `C:\Windows\Setup\Scripts\W11D-FirstLogon.log`). |

Phần chia ổ đĩa **không bao giờ** được tự động hoá: bạn luôn tự chọn ổ khi cài, nên không có dữ liệu nào bị
xoá nhầm.

## Sửa danh sách ứng dụng và tinh chỉnh
`data/apps.json` và `data/tweaks.json` chứa các danh sách (tên bằng vi, en, zh-CN và km; `level` safe /
aggressive / unsafe; `default`; `os`; `minBuild` / `maxBuild` nếu cần). Tinh chỉnh ghi vào các hive offline
`SOFTWARE`, `SYSTEM`, `DEFAULT` hoặc `NTUSER` (hồ sơ người dùng mặc định). Mục nào sai sẽ bị bỏ qua và ghi
cảnh báo vào nhật ký; `tests\Test-Parse.ps1` kiểm tra hai file này. `config/DebloatConfig.psd1` chỉ được
dùng khi thiếu file JSON.

## Phiên bản Windows được hỗ trợ
**Image có thể làm gọn**

| Windows | Bản phát hành (build) |
|---|---|
| Windows 11 | 21H2 (22000), 22H2 (22621), 23H2 (22631), 24H2 (26100), 25H2 (26200), 26H2 (26300) – x64 và ARM64 |
| Windows 10 | 1507 (10240) đến 22H2 (19045) – x64 và x86 |

Build 22000 trở lên dùng hồ sơ Windows 11; build 10240–21999 dùng hồ sơ Windows 10. Mỗi mục trong file
cấu hình có thể giới hạn theo khoảng build, nên mỗi bản Windows chỉ hiện những ứng dụng nó thực sự có.

**Máy chạy công cụ**

| Máy chạy | Ghi chú |
|---|---|
| Windows 10 / 11 | Khuyên dùng. Dùng DISM của hệ thống hoặc của ADK, mở ISO trực tiếp, cài oscdimg ngay trong công cụ. |
| Windows 8 / 8.1 | Dùng DISM có sẵn trong ISO. Chép `oscdimg.exe` vào `tools\` (bản ADK hiện tại không cài được). |
| Windows 7 SP1 | Cần 7-Zip (để mở ISO) và `oscdimg.exe` trong `tools\`. Muốn tải ISO cần TLS 1.2 (KB3140245, .NET 4.5.2 trở lên; nên cài WMF 5.1). |

## Những gì được thay đổi
**Windows 11 – gỡ mặc định:** Clipchamp, Teams (mới), Outlook (mới), Tin tức, Bing Search, Thời tiết,
ứng dụng Xbox, Xbox Game Bar, Solitaire, Microsoft 365, Power Automate, To Do, Dev Home, Trung tâm Phản hồi,
Liên kết Điện thoại, Cross Device, Hỗ trợ nhanh, Copilot, Microsoft Family, Mẹo. Trên các bản cũ còn gỡ
Cortana, Bản đồ, Mọi người, Copilot provider và Teams bản cá nhân.
**Tuỳ chọn:** Widgets, Media Player, Phim & TV, Máy ảnh, Đồng hồ, Trình ghi âm, Sticky Notes, Thư và
Lịch.

**Windows 10 – gỡ mặc định:** 3D Builder, 3D Viewer, Print 3D, Mixed Reality Portal, Mọi người, Skype,
Mobile Plans, Wallet, Messaging, Thời tiết, Tin tức, Mẹo, Office, OneNote cho Windows 10, Solitaire, Xbox
Console Companion, Xbox Game Bar, Điện thoại của bạn, Trung tâm Phản hồi, Cortana. Nếu có trong image thì
gỡ thêm Clipchamp, Teams, To Do, Power Automate, Outlook (mới), Copilot và Microsoft Family.
**Tuỳ chọn:** Groove Music, Phim & TV, Bản đồ, Paint 3D, Thư và Lịch, Máy ảnh, Báo thức & Đồng hồ,
Ghi âm, Sticky Notes.

**Luôn giữ lại:** Microsoft Store, Bảo mật Windows, Edge, WebView2, Máy tính, Ảnh, Notepad, Terminal,
Công cụ Cắt, Paint, bộ giải mã đa phương tiện, các thư viện chạy ứng dụng (VCLibs, .NET Native, UI.Xaml,
Windows App Runtime) và App Installer (winget).

**Tinh chỉnh Registry – Windows 11**

| Tinh chỉnh | Khoá |
|---|---|
| Tắt tự cài ứng dụng gợi ý | `Policies\Microsoft\Windows\CloudContent` DisableWindowsConsumerFeatures, DisableConsumerAccountStateContent, DisableCloudOptimizedContent = 1 |
| Tắt Copilot | `Policies\Microsoft\Windows\WindowsCopilot` TurnOffWindowsCopilot = 1 (cho máy và người dùng mặc định) |
| Tắt tin tức Widgets | `Policies\Microsoft\Windows\Windows Feeds` EnableFeeds = 0 |
| Chặn tự cài Teams/Chat | `CurrentVersion\Communications` ConfigureChatAutoInstall = 0 |
| BypassNRO | `CurrentVersion\OOBE` BypassNRO = 1 |
| Người dùng mới: tắt gợi ý | `ContentDeliveryManager` của người dùng mặc định = 0, Start_IrisRecommendations = 0 |
| Ẩn nút Chat | `Explorer\Advanced` TaskbarMn = 0 (người dùng mặc định) |
| Xoá tác vụ tự cài khi cài đặt | `WindowsUpdate\Orchestrator\UScheduler_Oobe\{OutlookUpdate, DevHomeUpdate, CrossDeviceUpdate}` |

**Tinh chỉnh tuỳ chọn (mặc định tắt, áp dụng cho cả hai bản Windows nếu không ghi chú)**

| Tinh chỉnh | Khoá |
|---|---|
| Giảm dữ liệu chẩn đoán (Windows 11) | `Policies\Microsoft\Windows\DataCollection` AllowTelemetry = 0, DoNotShowFeedbackNotifications = 1 |
| Tắt mã quảng cáo | `Policies\...\AdvertisingInfo` DisabledByGroupPolicy = 1; người dùng mặc định AdvertisingInfo Enabled = 0 |
| Tắt trải nghiệm cá nhân hoá | người dùng mặc định DisableTailoredExperiencesWithDiagnosticData = 1 |
| Tắt kết quả web khi tìm kiếm (Windows 11) | `Policies\...\Windows Search` DisableWebSearch = 1, ConnectedSearchUseWeb = 0; DisableSearchBoxSuggestions = 1 |
| Tắt Recall (Windows 11) | `Policies\...\WindowsAI` DisableAIDataAnalysis = 1, AllowRecallEnablement = 0 |
| Tắt hẳn Widgets (Windows 11) | `Policies\Microsoft\Dsh` AllowNewsAndInterests = 0 |
| Không tự cài OneDrive *(mạnh tay)* | xoá `Run\OneDriveSetup` của người dùng mặc định |
| Tắt Reserved Storage *(mạnh tay)* | `ReserveManager` ShippedWithReserves = 0 |
| Bỏ kiểm tra TPM / Secure Boot / RAM / CPU *(mạnh tay, Windows 11)* | `Setup\LabConfig` Bypass*Check = 1 trong image **và trong `boot.wim`** (trình cài đặt) |

**Tinh chỉnh Registry – Windows 10**

| Tinh chỉnh | Khoá |
|---|---|
| Tắt tự cài ứng dụng gợi ý | `Policies\Microsoft\Windows\CloudContent` DisableWindowsConsumerFeatures, DisableSoftLanding, DisableCloudOptimizedContent = 1 |
| Người dùng mới: tắt gợi ý, tự cài ứng dụng | `ContentDeliveryManager` của người dùng mặc định (SilentInstalledAppsEnabled, PreInstalledAppsEnabled, SubscribedContent-*) = 0 |
| Tắt Cortana và tìm kiếm web | `Policies\Microsoft\Windows\Windows Search` AllowCortana = 0, DisableWebSearch = 1, ConnectedSearchUseWeb = 0; người dùng mặc định BingSearchEnabled = 0, CortanaConsent = 0 |
| Thu thập dữ liệu chẩn đoán thấp nhất | `Policies\Microsoft\Windows\DataCollection` AllowTelemetry = 0 (Home/Pro: mức *Bắt buộc*), DoNotShowFeedbackNotifications = 1 |
| Tắt Tin tức và sở thích | `Policies\Microsoft\Windows\Windows Feeds` EnableFeeds = 0 |
| Ẩn Meet Now và Mọi người | `Policies\Explorer` HideSCAMeetNow = 1, PeopleBand = 0 |
| Tắt Copilot | giống Windows 11 |
| Xoá tác vụ tự cài khi cài đặt | `UScheduler_Oobe\{OutlookUpdate, DevHomeUpdate}` nếu có |
| Không tự cài OneDrive (tuỳ chọn) | xoá `Run\OneDriveSetup` của người dùng mặc định |

**autounattend.xml** (đặt ở gốc ISO, tuỳ chọn): tự đồng ý điều khoản và ẩn các trang tài khoản Microsoft để
bạn tạo tài khoản cục bộ. Trên Windows 11 còn bật BypassNRO trong lúc cài. Ngôn ngữ trình cài đặt và kiến
trúc được đặt khớp với image.

Mọi danh sách nằm trong [`data/apps.json`](data/apps.json) và [`data/tweaks.json`](data/tweaks.json) (xem
[Sửa danh sách ứng dụng và tinh chỉnh](#sửa-danh-sách-ứng-dụng-và-tinh-chỉnh)). Mã ứng dụng có thể dùng ký
tự đại diện.

**Quy trình tạo ISO:** mở hoặc giải nén ISO → chép vào thư mục tạm → với từng phiên bản giữ lại:
`DISM /Mount-Image` → tích hợp bản cập nhật (SSU, LCU, .NET) và WinRE nếu chọn → gỡ ứng dụng → nạp
Registry của image và áp dụng tinh chỉnh → dọn WinSxS / ResetBase (nếu chọn) → `/Unmount-Image /Commit` →
xuất các phiên bản giữ lại vào một `install.wim` / `install.esd` mới → cập nhật `boot.wim` (nếu chọn) →
thêm `autounattend.xml` → `oscdimg` (BIOS + UEFI) → tính SHA256.

## Nguồn tải ISO
1. **Microsoft (luôn thử trước).** Công cụ dùng cùng dịch vụ tải với trang web của Microsoft. Link tải có
   hiệu lực khoảng 24 giờ. Tải bằng aria2 khi đánh dấu *Dùng aria2*; nếu aria2 lỗi thì tự chuyển sang trình
   tải có sẵn.
2. **Nguồn dự phòng (chỉ khi bạn đồng ý, chỉ khi Microsoft không cho tải).** Khi Microsoft từ chối, bản
   phát hành đã bị gỡ hoặc link lỗi, công cụ có thể đề nghị tải bản sao của đúng file gốc Microsoft theo
   danh sách trên [massgrave.dev](https://massgrave.dev/genuine-installation-media). Hộp thoại ghi rõ tên
   file, máy chủ tải (không phải của Microsoft) và mã SHA256 cần khớp; không bấm *Có* thì không làm gì.
   File chỉ được nhận khi **SHA256 trùng với file gốc của Microsoft**, sai thì bị xoá. Danh sách nằm ở mục
   `Mirrors` trong `config/DebloatConfig.psd1`; mục nào thiếu SHA256 hợp lệ sẽ không bao giờ được dùng.

## Ngôn ngữ
Giao diện có **Tiếng Việt** (mặc định), **English**, **简体中文** và **ភាសាខ្មែរ**. Đổi ngôn ngữ ở ô góc
dưới bên phải, lựa chọn được ghi nhớ. Nội dung nằm trong `lang/*.psd1`, rất mong mọi người góp ý sửa
(giữ nguyên các chỗ `{0}`). File nhật ký ghi cả tiếng Anh và tiếng Việt.

## Câu hỏi thường gặp và xử lý lỗi
**ISO đầu ra to hơn mong đợi.**
Mỗi phiên bản giữ lại sẽ lưu riêng phần file đã thay đổi, nên chọn *Tất cả* (khoảng 10 phiên bản trên ISO
hiện nay) làm image to lên. Hãy chỉ giữ phiên bản cần dùng (ví dụ *Home + Pro*) và/hoặc đánh dấu **Nén
kiểu ESD**. Nhật ký có các dòng `SIZE ...` cho từng bước, và liệt kê các file lớn nhất nếu ISO lớn hơn ISO
gốc quá 500 MB.

**Thư mục tạm của lần chạy trước vẫn còn.**
Công cụ tự nhận ra và dọn: gỡ Registry đang nạp, huỷ image còn mount, xoá thư mục. Nếu trong thư mục có file
không do công cụ tạo ra thì không xoá gì cả: giao diện sẽ hỏi có dùng thư mục mới (ví dụ
`D:\WinDebloat_work_2`) không, còn chế độ dòng lệnh tự chọn thư mục mới.

**Không tải được (lỗi 715-123130 hoặc "Sentinel").**
Microsoft chặn tải tự động với một số địa chỉ IP, vùng hoặc VPN. Hãy tắt VPN, đổi DNS (1.1.1.1 hoặc
8.8.8.8) hoặc đổi mạng, hoặc bấm *Mở trang Microsoft* để tải bằng trình duyệt rồi chọn file bằng nút
*Chọn...*. Công cụ cũng có thể đề nghị nguồn dự phòng đã kiểm tra SHA256 (xem
[Nguồn tải ISO](#nguồn-tải-iso)). Nếu *Lấy ngôn ngữ* báo không phân giải được "vlscppe.microsoft.com" thì
trình chặn quảng cáo, file hosts hoặc DNS đang chặn máy chủ tải của Microsoft.

**Thiếu oscdimg.exe.**
Bấm **Cài oscdimg**: công cụ chỉ cài phần Deployment Tools của Windows ADK chính thức (có kiểm tra chữ ký
số, hoặc cài qua winget). Cách khác: tải ADK tại
<https://learn.microsoft.com/windows-hardware/get-started/adk-install>, chép `oscdimg.exe` vào `tools\`
hoặc dùng tham số `-OscdimgPath`.

**USB không khởi động hoặc chép file bị lỗi.**
`install.wim` thường lớn hơn 4 GB. Hãy dùng Rufus hoặc Ventoy, hoặc tạo ISO với `-SplitWimMB 3800` (hoặc
nén kiểu ESD) để chép thẳng vào USB FAT32.

**File nhật ký ở đâu?**
Trong giao diện, bấm *Mở thư mục nhật ký* (thư mục `logs\` trong thư mục công cụ). Mỗi lần tạo ISO còn ghi
`WinDebloat_<giờ>.log` cạnh ISO đầu ra. Khi báo lỗi, hãy gửi kèm các file này.

## Lưu ý an toàn
- Ứng dụng bị gỡ **ngay trong image**, nên mọi máy cài từ ISO này sẽ không có chúng. Có thể cài lại từ
  Microsoft Store.
- Các gói mà tính năng khác cần đến (Xbox TCUI, Xbox Identity Provider, Xbox Speech-to-text, Get Help)
  được đánh dấu **không an toàn** và không bao giờ bị gỡ mặc định. Gỡ các thành phần Xbox sẽ làm hỏng đăng
  nhập Xbox / Game Pass và Game Bar.
- Thành phần cốt lõi (Store, Bảo mật Windows, Edge, WebView2, thư viện chạy ứng dụng, bộ giải mã,
  App Installer) được bảo vệ, không gỡ được qua danh sách.
- Chỉ bỏ qua kiểm tra phần cứng của Windows 11 (TPM 2.0, Secure Boot, RAM, CPU) khi bạn chọn tuỳ chọn
  hoặc tinh chỉnh đó. Máy không đủ yêu cầu có thể không nhận được bản cập nhật tính năng.
- Mật khẩu trong file trả lời được lưu dạng chữ thường trên ISO.
- *ResetBase* khiến các bản cập nhật đã tích hợp không gỡ được nữa.
- Bản cập nhật lớn của Windows có thể cài lại một số ứng dụng; các chính sách chỉ hạn chế, không chặn được
  hoàn toàn.
- Công cụ không bao giờ chạy file đã tải về. ISO nguồn không bao giờ bị sửa.

## Ghi công
- **[Raphire/Win11Debloat](https://github.com/Raphire/Win11Debloat)** (MIT): danh sách ứng dụng và cách
  phân loại an toàn / tuỳ chọn / không an toàn là tài liệu tham khảo chính cho danh sách gỡ.
- **[ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)** (MIT) và
  **[farag2/Sophia-Script-for-Windows](https://github.com/farag2/Sophia-Script-for-Windows)** (MIT): tham
  khảo cho các tinh chỉnh quyền riêng tư (dữ liệu chẩn đoán, mã quảng cáo, trải nghiệm cá nhân hoá, Recall,
  Widgets) và ý tưởng mẫu cấu hình.
- **[ntdevlabs/tiny11builder](https://github.com/ntdevlabs/tiny11builder)**: chỉ tham khảo ý tưởng (xử lý
  `boot.wim`, khoá LabConfig, thứ tự cập nhật); dự án này không có giấy phép nên không lấy mã nào từ đó.
- **[pbatard/Fido](https://github.com/pbatard/Fido)** (GPL-3.0): mô tả cách tải ISO từ Microsoft; dự án
  này tự viết lại, không dùng mã của Fido.
- **[aria2](https://aria2.github.io/)** (GPL-2.0 trở lên): đi kèm nguyên bản trong `tools/aria2/`, chạy
  như một chương trình riêng. Xem [`tools/aria2/NOTICE.txt`](tools/aria2/NOTICE.txt) để biết nguồn, mã
  SHA256 và giấy phép ([`COPYING`](tools/aria2/COPYING)).
- **[massgrave.dev](https://massgrave.dev/genuine-installation-media)**: danh sách file gốc Microsoft dùng
  cho nguồn tải dự phòng.
- Biểu tượng ứng dụng và biểu tượng nút được vẽ riêng cho dự án (file SVG gốc trong `assets/`). Biểu tượng
  không phải logo Windows của Microsoft.

Windows, DISM và Windows ADK là sản phẩm của Microsoft. Dự án không phân phối lại bất kỳ thành phần nào
của Microsoft.

## Giấy phép
[MIT](LICENSE) Copyright (c) 2026 TaiNT13@PNC STG & WinDebloat Tool contributors. aria2 trong `tools/aria2/` giữ giấy phép riêng
(GPL-2.0).

---

<p align="center"><sub>Designed by TaiNT13@PNC STG</sub></p>

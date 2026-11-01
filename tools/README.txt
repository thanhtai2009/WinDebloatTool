Third-party tools / Công cụ bên thứ ba
=====================================

aria2\   aria2 1.37.0 (GPLv2+), bundled, unmodified - multi-connection ISO download.
         See aria2\NOTICE.txt (source, hashes, license). aria2c.exe placed directly in
         this folder, next to the script or on PATH is also used (tools\aria2c.exe first).
         aria2 1.37.0, giấy phép GPLv2, kèm sẵn, không chỉnh sửa - dùng để tải ISO đa luồng.

Optional: put oscdimg.exe here (copied from Windows ADK "Deployment Tools\amd64\Oscdimg")
if the ADK cannot be installed on this PC (Windows 7/8.x). 7z.exe may also be placed here.
Tùy chọn: chép oscdimg.exe vào đây nếu máy không cài được ADK (Windows 7/8.x).

New-RulesManifest.ps1  (maintainers) rewrites data\rules-manifest.json after a change of data\apps.json or
         data\tweaks.json. Commit the three files together; clients only accept rule files whose SHA256
         matches the manifest on the main branch.
         (dành cho người duy trì) tạo lại data\rules-manifest.json sau khi sửa apps.json / tweaks.json.

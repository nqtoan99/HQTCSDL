# Aurora Cruise · mốc nền tảng và tổng quan

Mốc hiện tại: đăng nhập/đăng xuất, mật khẩu băm scrypt, phiên 8 giờ, 8 vai trò và màn Tổng quan đọc dữ liệu theo quyền. Tổng quan cho phép hành khách chọn booking hoặc nhân viên chọn chuyến để xem lịch cảng, thống kê hoạt động/đăng ký, chi phí trong phạm vi được cấp và thông báo. Chưa có API ghi đăng ký/check-in/POS/tài chính hay chỉnh sửa lịch trình. Không phụ thuộc thư mục `cruise-sql` khi chạy.

## Chạy

Cần Node.js từ 18, SQL Server và sqlcmd trong PATH. Mở terminal ở thư mục này:

```powershell
npm run setup
npm start
```

Mở http://localhost:3001 hoặc nhấp đúp CHAY-WEB.cmd. Database riêng CruiseWeek1; không dùng CruiseCoursework của bản đầy đủ. Nếu dùng SQLEXPRESS, đặt $env:SQL_SERVER = '.\SQLEXPRESS' trước setup/start. Có thể đổi SQL_DATABASE và PORT; giữ cùng cấu hình khi setup/server/test. Không có dependency bên ngoài hoặc bước build.

## Tài khoản

Mật khẩu demo: Aurora123! Mỗi tài khoản được lưu hash với salt riêng.

| Vai trò | Email |
|---|---|
| Hành khách | guest1@demo.local đến guest20@demo.local |
| Điều phối | itinerary@demo.local |
| Hoạt động | checkin@demo.local |
| Tour bờ | shore@demo.local |
| POS | pos@demo.local |
| Tài chính | finance@demo.local |
| Vận hành | operations@demo.local |
| Quản trị | admin@demo.local |

## Mốc đã triển khai và phần tiếp theo

Đã có một lát cắt đầu cuối có thể review và push: đăng nhập/phân quyền, chọn ngữ cảnh chuyến hoặc booking, API đọc tổng quan và giao diện responsive. Tiếp theo là nghiệp vụ ghi đăng ký/hủy, check-in, ghi nhận POS, đối soát tài chính, chỉnh lịch và gửi thông báo.

## SQL và kiểm tra

Setup chạy 01-schema → 03-seed → 04-auth trên DB mới; lần sau giữ dữ liệu/mật khẩu hiện có. Seed không gọi usp_Register. Nếu dùng SSMS bật SQLCMD Mode. Sau khi chạy SQL bằng tay, chạy setup để cấp hash demo.

Chạy npm run check và npm run test:auth. Test dùng SQL Server thật, cổng tạm và một fixture tài khoản được dọn sau kiểm tra. Chi tiết API/quyền: docs/AUTH.md. Kết quả: docs/AUTH-TEST-RESULTS.md. ERD/DICTIONARY/DESIGN/REQUIREMENTS cũ mô tả thiết kế đích, chưa phải toàn bộ chức năng đã triển khai.

## Code cần push

Push server.mjs, src, public, scripts, tests, database, docs, README.md, CHAY-WEB.cmd, package.json, package-lock.json và .gitignore. Không push .tmp, node_modules, .env hoặc log.

Các API hiện có: POST /api/login, POST /api/logout, GET /api/me, GET /api/state, GET /api/bookings/:id, GET /api/departments/:role, GET /api/admin/users. Backend kiểm tra quyền dù client sửa URL/menu. Cookie HttpOnly và SameSite=Strict; restart server cần đăng nhập lại. Bản học phần chạy localhost.

# Aurora Cruise · mốc nền tảng và tổng quan

Mốc hiện tại: đăng nhập/đăng xuất, mật khẩu băm scrypt, phiên 8 giờ, 8 vai trò, Tổng quan theo booking/chuyến, quản lý chuyến/lịch cảng và phần đầu nghiệp vụ đăng ký hoạt động. Hành khách có thể đăng ký đúng hoạt động trong chuyến của booking; SQL chống đăng ký trùng, khóa sức chứa, đưa khách vào danh sách chờ và lưu mức giá theo gói tại thời điểm đăng ký. Chưa có hủy đăng ký, kiểm tra trùng lịch, tự chuyển danh sách chờ, check-in, POS và cập nhật tài chính. Không phụ thuộc thư mục `cruise-sql` khi chạy.

## Chạy

Cần Node.js từ 18, SQL Server và sqlcmd trong PATH. Mở terminal ở thư mục này:

```powershell
npm run setup
npm start
```

Mở http://localhost:3001 hoặc nhấp đúp CHAY-WEB.cmd. Database riêng CruiseWeek1; không dùng CruiseCoursework của bản đầy đủ. Nếu dùng SQLEXPRESS, đặt $env:SQL_SERVER = '.\SQLEXPRESS' trước setup/start. Có thể đổi SQL_DATABASE và PORT; giữ cùng cấu hình khi setup/server/test. Không có dependency bên ngoài hoặc bước build.

## Tài khoản

Mật khẩu demo: Aurora123! Mỗi tài khoản được lưu hash với salt riêng.

Trong dữ liệu mẫu, gói Premium bao gồm hoạt động Đêm nhạc trên biển; gói Tiêu chuẩn giữ mức phí niêm yết. Mức giá được chốt khi tạo đăng ký.

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

Đã hoàn tất lát cắt Tổng quan theo yêu cầu: chọn booking/chuyến, thông tin hành trình, trạng thái và điểm dừng, hoạt động kèm sức chứa/đăng ký, chi phí và các giao dịch gần đây theo quyền, thông báo gần đây và lịch trải nghiệm tiếp theo. Cũng đã có đăng nhập/phân quyền, tạo/sửa chuyến, quản lý điểm dừng, đổi giờ cảng có kiểm tra xung đột tour, lưu lý do/lịch sử và tự tạo thông báo. Phần tiếp theo là nghiệp vụ ghi đăng ký/hủy, check-in, ghi nhận POS và đối soát tài chính.

## SQL và kiểm tra

Setup chạy 01-schema → 03-seed → 04-auth → 05-itinerary → 06-registration trên DB mới. Với DB CruiseWeek1 hiện có, setup giữ dữ liệu rồi chạy các migration để cập nhật lịch trình và đăng ký. Seed không gọi usp_Register. Nếu dùng SSMS bật SQLCMD Mode. Sau khi chạy SQL bằng tay, chạy setup để cấp hash demo và cập nhật migration.

Chạy npm run check và npm run test:auth. Test dùng SQL Server thật, cổng tạm và một fixture tài khoản được dọn sau kiểm tra. Chi tiết API/quyền: docs/AUTH.md. Kết quả: docs/AUTH-TEST-RESULTS.md. ERD/DICTIONARY/DESIGN/REQUIREMENTS cũ mô tả thiết kế đích, chưa phải toàn bộ chức năng đã triển khai.

## Code cần push

Push server.mjs, src, public, scripts, tests, database, docs, README.md, CHAY-WEB.cmd, package.json, package-lock.json và .gitignore. Không push .tmp, node_modules, .env hoặc log.

Các API hiện có: POST /api/login, POST /api/logout, POST /api/itinerary/cruises, POST /api/itinerary/stops, POST /api/registrations, GET /api/me, GET /api/state, GET /api/bookings/:id, GET /api/departments/:role, GET /api/admin/users. Backend và SQL đều kiểm tra quyền sở hữu booking khi đăng ký. Cookie HttpOnly và SameSite=Strict; restart server cần đăng nhập lại. Bản học phần chạy localhost.

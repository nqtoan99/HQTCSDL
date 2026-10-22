# Aurora Cruise · mốc nền tảng và tổng quan

Mốc hiện tại: đăng nhập/đăng xuất, mật khẩu băm scrypt, phiên 8 giờ, 8 vai trò, Tổng quan theo booking/chuyến và quản lý chuyến/lịch cảng cho ITINERARY/ADMIN. Tổng quan hiển thị hành trình, điểm dừng, trải nghiệm và sức chứa, lượt xác nhận/chờ, chi tiết giao dịch theo quyền, thông báo; có thể chọn booking hoặc chuyến để đổi ngữ cảnh. Người dùng được phép tạo/sửa chuyến, thêm/sửa điểm dừng; giờ cảng, cảng cũ/mới, lý do, người cập nhật và thông báo được lưu cùng nghiệp vụ. Chưa có API ghi đăng ký/check-in/POS/tài chính. Không phụ thuộc thư mục `cruise-sql` khi chạy.

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

Đã hoàn tất lát cắt Tổng quan theo yêu cầu: chọn booking/chuyến, thông tin hành trình, trạng thái và điểm dừng, hoạt động kèm sức chứa/đăng ký, chi phí và các giao dịch gần đây theo quyền, thông báo gần đây và lịch trải nghiệm tiếp theo. Cũng đã có đăng nhập/phân quyền, tạo/sửa chuyến, quản lý điểm dừng, đổi giờ cảng có kiểm tra xung đột tour, lưu lý do/lịch sử và tự tạo thông báo. Phần tiếp theo là nghiệp vụ ghi đăng ký/hủy, check-in, ghi nhận POS và đối soát tài chính.

## SQL và kiểm tra

Setup chạy 01-schema → 03-seed → 04-auth → 05-itinerary trên DB mới. Với DB CruiseWeek1 hiện có, setup giữ dữ liệu rồi chạy migration 05-itinerary để thêm nhật ký chuyến và cảng cùng các procedure lịch trình. Seed không gọi usp_Register. Nếu dùng SSMS bật SQLCMD Mode. Sau khi chạy SQL bằng tay, chạy setup để cấp hash demo và cập nhật migration.

Chạy npm run check và npm run test:auth. Test dùng SQL Server thật, cổng tạm và một fixture tài khoản được dọn sau kiểm tra. Chi tiết API/quyền: docs/AUTH.md. Kết quả: docs/AUTH-TEST-RESULTS.md. ERD/DICTIONARY/DESIGN/REQUIREMENTS cũ mô tả thiết kế đích, chưa phải toàn bộ chức năng đã triển khai.

## Code cần push

Push server.mjs, src, public, scripts, tests, database, docs, README.md, CHAY-WEB.cmd, package.json, package-lock.json và .gitignore. Không push .tmp, node_modules, .env hoặc log.

Các API hiện có: POST /api/login, POST /api/logout, POST /api/itinerary/cruises, POST /api/itinerary/stops, GET /api/me, GET /api/state, GET /api/bookings/:id, GET /api/departments/:role, GET /api/admin/users. Backend kiểm tra quyền dù client sửa URL/menu; SQL procedure cũng kiểm tra vai trò ITINERARY/ADMIN. Cookie HttpOnly và SameSite=Strict; restart server cần đăng nhập lại. Bản học phần chạy localhost.

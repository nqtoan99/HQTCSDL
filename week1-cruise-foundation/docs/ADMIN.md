# Quản trị hệ thống

Màn Quản trị dành cho vai trò `ADMIN`. API và stored procedure cùng kiểm tra tài khoản quản trị còn hoạt động; việc gọi SQL trực tiếp không bỏ qua được lớp quyền này.

Các thao tác gồm người dùng và nhiều vai trò, danh mục tàu/khu vực/cabin/cảng/nhà cung cấp/dịch vụ/gói/thiết bị, booking, dịch vụ trong gói, chính sách hủy–hoàn và trạng thái mã định danh. Thao tác nhiều bảng chạy trong transaction và ghi `ActorId` cùng `CorrelationId` để truy vết.

Quy tắc bảo vệ chính:

- Không tự khóa hoặc tự gỡ quyền quản trị và luôn giữ ít nhất một quản trị viên hoạt động.
- Cabin và khu vực phải có tàu cha tồn tại; thiết bị đã phát sinh POS/check-in không được đổi sang loại trái với lịch sử.
- Booking có account `SETTLED` không được đổi cabin hoặc gói.
- Bật/tắt dịch vụ trong gói theo kiểu idempotent; gửi lại cùng trạng thái không tạo audit giả.

Chạy `npm run test:admin` để tạo database `CruiseWeek1AdminTest`, kiểm tra các quy tắc trên và tự xóa database sau khi hoàn tất.

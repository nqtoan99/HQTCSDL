# POS ngoại tuyến

## Luồng hiện tại

- POS lấy danh mục dịch vụ và máy POS từ SQL Server khi đăng nhập có kết nối.
- App shell được cache bằng service worker. Danh mục POS tối thiểu được lưu ở trình duyệt để tiếp tục tạo giao dịch khi máy chủ tạm mất kết nối.
- Giao dịch được ghi vào localStorage theo UserId trước khi gửi. Mỗi mục có UUID riêng và UUID không đổi khi retry.
- Khi có kết nối, API kiểm tra quyền POS, chuẩn hóa dữ liệu rồi gọi `dbo.usp_PostPOS`. Giá và dịch vụ thuộc gói được xác nhận ở SQL Server.
- SQL dùng `Transactions.ClientId` có unique constraint cùng khóa theo UUID để chống ghi lặp, kể cả hai request cùng lúc. Gửi lại đúng payload trả về giao dịch đã có; dùng UUID cũ với nội dung khác bị từ chối.
- `RegistrationId` có unique filtered index chỉ áp dụng với đăng ký khác `NULL`. Nhờ vậy một booking chỉ có một giao dịch phí hoạt động, trong khi booking vẫn có thể phát sinh nhiều giao dịch POS.
- Trình duyệt chỉ xóa mục hàng đợi sau khi nhận ACK từ API. Nếu mất phản hồi sau khi SQL commit, gửi lại cùng UUID không tạo khoản phí thứ hai.

## Kiểm tra

Chạy `npm run setup`, `npm start`; đăng nhập `pos@demo.local` với mật khẩu `Aurora123!`. Vào **POS ngoại tuyến**, lưu giao dịch, bật Network → Offline, tải lại trang và xác nhận mục vẫn có trong hàng đợi. Khi có mạng lại, bấm **Kết nối lại** nếu đang dùng cache, sau đó **Đồng bộ ngay**. Giao dịch được ghi ở SQL, hàng đợi giảm sau khi server xác nhận.

Chạy `npm run test:pos` để kiểm tra API và SQL trên database ngẫu nhiên riêng. Bộ kiểm thử xác nhận tính giá ở SQL, retry UUID, hai request đồng thời, từ chối payload khác, mã khách sai và quyền truy cập. Database tạm được xóa ở bước dọn dẹp.

## Giới hạn

Không tính giá khi offline; số tiền chỉ có sau khi SQL Server chấp nhận giao dịch. Không xóa dữ liệu trang web khi còn mục chờ trong hàng đợi.

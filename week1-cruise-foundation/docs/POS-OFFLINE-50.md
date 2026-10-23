# POS ngoại tuyến · mốc 50%

## Đã có trong mốc này

- Màn hình POS riêng cho vai trò POS và quản trị viên.
- Danh mục dịch vụ và thiết bị POS được lấy từ API khi đang kết nối.
- Cache giao diện bằng service worker để mở lại app shell khi mất kết nối.
- Cache tối thiểu cho POS gồm tên tài khoản, vai trò POS, dịch vụ và thiết bị; không cache booking, hành khách hay dữ liệu tài chính.
- Giao dịch được lưu trong localStorage theo UserId, giữ nguyên sau khi tải lại trang.
- Mỗi giao dịch có UUID riêng, được tạo một lần khi bấm lưu và giữ nguyên khi đọc lại hàng đợi.
- Giá chưa được tính/chốt ở trình duyệt. SQL Server sẽ xác nhận giá khi tích hợp đồng bộ.

## Chưa thuộc mốc 50%

Chưa gửi giao dịch lên server, chưa có procedure đồng bộ idempotent, chưa chống phát lại bằng unique key ở SQL Server và chưa lưu biên nhận. Nút đồng bộ chỉ xuất hiện ở mốc sau khi API và T-SQL cùng sẵn sàng; hiện giao dịch luôn được lưu an toàn tại trình duyệt.

## Kiểm tra thủ công

1. Chạy `npm run setup`, sau đó `npm start`; đăng nhập `pos@demo.local` với mật khẩu `Aurora123!`.
2. Mở mục **POS ngoại tuyến**, nhập `AURORA-001`, chọn dịch vụ/thiết bị, đặt số lượng và lưu.
3. Ghi lại UUID hiển thị, tải lại trang, mở POS và xác nhận giao dịch còn trong hàng đợi với cùng UUID.
4. Mở DevTools → Application → Service Workers/Cache Storage để xác nhận `aurora-week1-shell-v1` chứa trang, CSS, JavaScript và manifest. Trong Network bật Offline rồi tải lại; giao diện app shell và POS cục bộ vẫn mở.
5. Thử lưu nhiều giao dịch và xác nhận mỗi giao dịch có UUID khác nhau; đổi sang tài khoản khác khi có kết nối và xác nhận hàng đợi được tách theo tài khoản.

Giao dịch trong mốc này chỉ được lưu cục bộ, chưa phải chứng từ đã ghi vào SQL Server. Không xóa dữ liệu trang web khi còn hàng đợi.

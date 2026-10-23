# Chi phí hành khách

## Chức năng

- Mỗi booking có một tài khoản chi tiêu. Màn hình chỉ lấy các booking thuộc hành khách đang đăng nhập.
- Chi phí tạm tính là tổng giao dịch `POSTED` cộng phần chưa hoàn của giao dịch `REFUNDED`. Giao dịch `VOID` không được tính.
- Bảng giao dịch hiển thị khoản phát sinh, khoản hoàn và chi phí ròng. Hủy hoạt động có hoàn một phần được phản ánh từ `Transactions.RefundAmount`.
- Sau khi tài chính chốt tài khoản, hành khách xem hóa đơn, số tiền, phương thức và thời điểm thanh toán; có thể in hoặc lưu hóa đơn thành PDF.
- Hành khách gửi tranh chấp cho giao dịch đã ghi nhận hoặc đã hoàn. Một giao dịch chỉ có tối đa một tranh chấp `OPEN`; tranh chấp đang mở chặn chốt tài khoản.

## Bảo vệ dữ liệu

`GET /api/passenger/finance` yêu cầu vai trò `PASSENGER` và truy vấn theo `UserId` trong phiên đăng nhập. API không nhận `UserId` từ trình duyệt. `POST /api/passenger/disputes` cũng lấy người gửi từ phiên; `dbo.usp_SubmitPassengerDispute` kiểm tra lại vai trò và quan hệ `Transaction → Account → Booking → Passenger` trước khi ghi. SQL lưu người gửi, thời điểm, trạng thái, phản hồi xử lý và ghi audit.

Các migration `12-passenger-finance.sql` bổ sung metadata tranh chấp, chỉ mục truy vấn và thủ tục gửi tranh chấp. `scripts/setup.mjs` áp dụng migration này cả trên database tuần 1 đã có.

## Chạy và kiểm thử

```powershell
npm run setup
npm run test:finance
npm start
```

Đăng nhập bằng `guest1@demo.local` / `Aurora123!`, chọn **Chi phí hành khách** ở thanh bên. Hóa đơn chỉ xuất hiện sau khi tài chính chốt tài khoản. `MOCK` là khoản thanh toán ghi sổ mô phỏng; ứng dụng không kết nối ngân hàng.

`npm run test:finance` tạo database tạm riêng và kiểm tra quyền sở hữu booking, chi phí tạm, hoàn một phần, tranh chấp hợp lệ/trùng, chặn chốt khi còn tranh chấp mở, sau đó kiểm tra hóa đơn/thanh toán sau khi tài chính giải quyết. Database tạm được xóa khi kết thúc.

# Thiết kế hệ thống và quy tắc nghiệp vụ

## Kiến trúc

HTML/CSS/JavaScript responsive → HTTP API Node.js → sqlcmd Windows Authentication → SQL Server. Frontend lấy dữ liệu từ API, gửi ID/đầu vào nghiệp vụ. API không nhận giá giao dịch hoặc UserId nhân viên do client tự chọn; lấy actor từ phiên đã đăng nhập. Chuỗi được escape thành literal Unicode, tên procedure/parameter do code cố định. SQLCMD được gọi bằng spawn, không qua shell; JSON được chuyển qua hex UTF-16 để giữ đúng tiếng Việt trên Windows console ẩn.

Các thao tác cập nhật nhiều bảng dùng SET XACT_ABORT ON, BEGIN TRY/BEGIN CATCH, BEGIN TRAN/COMMIT và ROLLBACK khi lỗi. Khóa UPDLOCK/HOLDLOCK trên hoạt động và tài khoản tuần tự hóa đăng ký, ghi chi phí, hủy và chốt hóa đơn. UNIQUE ngăn đăng ký lặp, check-in lặp, hóa đơn lặp và UUID giao dịch lặp. Filtered unique index chỉ cho một khoản phí đăng ký POSTED, cho phép giữ lịch sử phí REFUNDED khi đăng ký lại.

Trigger kiểm tra cabin với tàu, khu vực hoặc điểm dừng với chuyến, và giao dịch với account. Hóa đơn phải bằng số dư tính từ POSTED/REFUNDED/VOID; thanh toán phải bằng hóa đơn. `usp_SettleAccount` khóa account, kiểm tra tranh chấp, tạo hóa đơn và thanh toán rồi chuyển SETTLED trong một transaction. Audit của cùng nghiệp vụ dùng chung CorrelationId để truy vết.

## Mô hình dữ liệu

User là danh tính đăng nhập, Passenger là hồ sơ hành khách. Booking xác định khách thuộc chuyến, cabin và gói nào; vì vậy không gán trực tiếp cabin/gói vào User. Mỗi Booking có một Account và các Identifier, và có nhiều Registration. Registration nối Booking với Activity, CheckIn thuộc Registration, Feedback thuộc Registration đã check-in. Cabin phải thuộc tàu của chuyến; hoạt động trên tàu phải thuộc khu vực của chính tàu; tour bờ phải thuộc điểm dừng của chính chuyến và không vượt giờ rời cảng.

Giao dịch hoạt động lưu RegistrationId, giao dịch POS lưu ServiceId/DeviceId/StaffId. CHECK bảo đảm hai loại không trộn. Quantity là số lượng POS; Amount được chụp tại thời điểm giao dịch nên việc đổi giá danh mục sau đó không sửa lịch sử. RefundAmount ghi số thực hoàn; số dư = POSTED Amount + REFUNDED (Amount − RefundAmount), VOID không tính. Không lưu tổng số dư dư thừa vào Accounts. Invoice chụp tổng cuối chuyến trong cùng transaction với Payment và trạng thái SETTLED.

Các bảng danh mục, quan hệ và chứng từ được tách theo thực thể. Quan hệ nhiều–nhiều dùng UserRoles, PackageServices, GroupMembers. Tổng doanh thu/lấp đầy là view hoặc function, không cập nhật bằng frontend. Xem DICTIONARY.md để thấy từng PK/FK, kiểu và nullable; UNIQUE/CHECK cụ thể nằm trong các script SQL.

## Quy tắc

- Đăng ký chỉ cho booking thuộc đúng chuyến chưa đóng, account mở và hoạt động OPEN chưa bắt đầu. Phí đã gồm trong gói = 0. Hết chỗ chuyển WAITLIST và chưa ghi phí. Khi khách hủy hoặc tăng sức chứa, khách chờ được chuyển theo CreatedAt/RegistrationId và ghi phí tại thời điểm được nhận.
- Hủy chỉ trước CancelHours và chưa check-in, hoàn RefundPercent. Nhân viên hủy cả hoạt động hoàn 100%; chặn hủy nếu có tài khoản đã chốt cần xử lý chứng từ riêng.
- Check-in yêu cầu mã còn hiệu lực, đăng ký CONFIRMED và thiết bị CHECKIN. Không tích hợp máy đọc phần cứng. Mốc thời gian check-in chưa giới hạn vào một cửa sổ giờ riêng để thuận tiện demo, nhưng mã/đăng ký/trạng thái hoạt động luôn được kiểm tra.
- Tour có nhóm/xe/hướng dẫn viên. Chỉ registration đúng tour và CONFIRMED được gán nhóm. Nhân viên SHORE ghi ReturnedAt. Cảnh báo chưa về phát sinh khi còn dưới 30 phút đến giờ rời cảng và tiếp tục sau giờ đó.
- POS xác thực mã, lấy gói/giá trong DB, ghi chi phí tạm tính. UUID ClientId giữ nguyên qua các lần gửi. Receipt và charge được commit cùng nhau; payload khác dùng UUID cũ bị từ chối.
- Chỉ FINANCE/ADMIN được void/hoàn giao dịch POS, giải quyết tranh chấp và chốt hóa đơn. Chốt bị chặn khi còn dispute OPEN hoặc giao dịch POS chưa được đối soát. Đối soát lưu ReconciledAt/ReconciledBy. Không thu tiền qua ngân hàng; payment DEMO là mô phỏng xác nhận đã thu.
- Chỉ chủ booking gửi dispute/feedback. `usp_SubmitPassengerDispute` xác minh chủ giao dịch ở SQL và ngăn tranh chấp OPEN trùng; tranh chấp mở chặn chốt tài khoản. Feedback hoạt động yêu cầu đã check-in và đã kết thúc; feedback chuyến yêu cầu EndDate đã qua hoặc CLOSED.
- Lịch mới phải nằm trong chuyến, không chồng điểm dừng và không cắt tour bờ. Thay đổi lịch lưu thời gian cũ/mới, lý do, actor và thông báo trong cùng transaction.
- Định danh có thể bị vô hiệu; không xóa chứng từ đã dùng. Đóng tài khoản ngăn ghi thêm chi phí/đăng ký. Không tự tước quyền hoặc khóa tài khoản admin đang thao tác.

## Thời gian và tiền

Tiền VND dùng decimal(18,2); giao diện hiển thị phân nhóm theo vi-VN. Lịch hoạt động/cảng dùng giờ địa phương của SQL Server (máy demo Việt Nam); audit/check-in/giao dịch dùng SYSUTCDATETIME và giao diện chuyển sang giờ trình duyệt. Date chỉ lưu ngày. Không dùng float cho giá hay số dư.

## Phạm vi ứng dụng

Bản học phần local, không phải hệ thống thu tiền sản xuất. Kết nối DB bằng Windows identity của backend; session trong RAM; sqlcmd mở kết nối theo request. Không có tài khoản SQL/password lưu trong repo. Các tài khoản demo và kiểu thanh toán DEMO được ghi rõ. Việc dùng web responsive, mô phỏng mã định danh và BLE mẫu bám kế hoạch đã cung cấp.

# Kiểm tra kiểu dữ liệu API và Unicode

API trong Week 1 chỉ nhận ID là số nguyên dương an toàn hoặc chuỗi chữ số nguyên chuẩn. ID tùy chọn có thể bỏ trống hoặc bằng 0 để biểu thị thao tác tạo mới. Boolean phải được gửi dưới dạng JSON `true` hoặc `false`; API không tự chuyển `1`, `0`, `"true"` hay `"false"` thành boolean.

Body JSON được đọc theo số byte, ghép đủ các chunk rồi giải mã UTF-8 nghiêm ngặt trước khi parse. Chuỗi có Unicode không hợp lệ, byte UTF-8 sai, JSON không phải object và request vượt giới hạn sẽ bị từ chối.

Chuỗi đưa vào truy vấn SQL được escape dấu nháy và dùng literal Unicode `N'...'`. `sqlcmd` tiếp tục chạy với code page UTF-8; dữ liệu phản hồi từ SQL Server được chuyển qua JSON UTF-16LE để giữ nguyên tiếng Việt trên Windows.

Chạy kiểm tra bằng:

```powershell
npm run check
npm run test:input-validation
```

Bài kiểm thử tích hợp tạo database tạm có tên ngẫu nhiên, xác nhận API từ chối ID/boolean sai kiểu, ghi rồi đọc lại chuỗi tiếng Việt và xóa database kiểm thử khi hoàn tất.

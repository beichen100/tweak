# iPhone-VCAM

Bản nâng cấp với các tính năng mới và sửa lỗi

## Cập nhật mới

- **Hỗ trợ âm thanh**: Phát âm thanh từ video thay thế cùng với hình ảnh
- **Sửa lỗi camera**: Thêm tính năng tự động sửa lỗi camera bằng LDRestart và UICache
- **Tương thích iOS 15+**: Nâng cấp hỗ trợ cho các phiên bản iOS mới nhất
- **Giao diện người dùng cải tiến**: Chế độ UI tối giản để tránh gián đoạn các ứng dụng đang chạy
- **Sửa lỗi video dài**: Khắc phục vấn đề mất hiệu lực khi quay video lâu
- **Hỗ trợ Sileo**: Có thể cài đặt qua Sileo trên iOS 15+ đã jailbreak
- **Phím tắt mới**: Thêm phím tắt để mở cài đặt tweak nhanh chóng

# Hướng dẫn cài đặt

## Cài đặt qua Cydia
1. Thêm repo này vào Cydia: `https://repo.trizau.com/`
2. Tìm và cài đặt "VCAM - Virtual Camera"
3. Khởi động lại thiết bị

## Cài đặt qua Sileo (iOS 15+)
1. Thêm repo này vào Sileo: `https://repo.trizau.com/`
2. Tìm và cài đặt "VCAM - Virtual Camera"
3. Khởi động lại thiết bị

## Cài đặt thủ công
1. Tải file .deb từ [GitHub Releases](https://github.com/trizau/iOS-VCAM/releases)
2. Sử dụng Filza để cài đặt file .deb
3. Khởi động lại thiết bị

# Cách sử dụng
- **-** là phím giảm âm lượng, **+** là phím tăng âm lượng

## Phím tắt
| Tổ hợp phím | Chức năng |
|-------------|-----------|
| **+** rồi **-** | Mở menu đầy đủ |
| **-** rồi **+** | Mở bộ chọn video / Tải video |
| **+**, **-**, **+** | Mở cài đặt tweak |

## Chế độ đầy đủ
Nhấn **+** rồi **-** trong vòng 1 giây để mở menu đầy đủ với các tùy chọn:
- Chọn video
- Tải video từ URL
- Tắt thay thế
- Sửa lỗi camera
- Chuyển đổi chế độ UI

## Chế độ nhanh
Nhấn **-** rồi **+** trong vòng 1 giây để:
- Mở bộ chọn video nếu chưa cấu hình URL tải xuống
- Tải video từ URL nếu đã cấu hình

## Cài đặt Tweak
Nhấn **+**, **-** rồi **+** trong vòng 1 giây để:
- Mở ứng dụng Settings và đi tới phần cài đặt của VCAM

# Giải quyết vấn đề

## Lỗi camera trên iOS 15+
Nếu camera không hoạt động sau khi jailbreak, hãy sử dụng tính năng "Sửa lỗi camera" trong menu của tweak. Tính năng này sẽ sử dụng PowerSelector để thực hiện LDRestart và UICache.

## Lỗi khi quay video dài
Phiên bản mới đã khắc phục vấn đề mất hiệu lực khi quay video dài bằng cách tự động làm mới buffer.

## Hỗ trợ âm thanh
Phiên bản mới hỗ trợ phát âm thanh từ video thay thế. Bạn có thể bật/tắt tính năng này trong phần cài đặt.

# Bảng so sánh tính năng

| Tính năng | Phiên bản cũ | Phiên bản mới |
|-----------|--------------|---------------|
| Thay thế video | ✅ | ✅ |
| Hỗ trợ âm thanh | ❌ | ✅ |
| Hỗ trợ iOS 15 | ❌ | ✅ |
| Quay video dài | ❌ | ✅ |
| Chế độ UI đơn giản | ❌ | ✅ |
| Công cụ sửa camera | ❌ | ✅ |
| Hỗ trợ Sileo | ❌ | ✅ |
| Menu cài đặt | ❌ | ✅ | 
# Floating Downloader 3.0

یک دانلودر اندرویدی مدرن با:

- دانلود واقعی فایل‌های HTTP/HTTPS
- ذخیره استاندارد در `Downloads` با Android MediaStore
- پنجره شناور برای دانلود سریع
- مرورگر داخلی با تشخیص لینک‌های مستقیم رسانه
- تاریخچه دانلودهای تکمیل‌شده
- رابط کاربری RTL و Dark حرفه‌ای
- GitHub Actions برای `flutter analyze` و ساخت APK

## نکته مهم درباره «واقعی بودن»

این پروژه لینک‌های مستقیم فایل را واقعاً دانلود و در Downloads ذخیره می‌کند. دیگر از مسیر ثابت
`/storage/emulated/0/Download` یا مجوزهای قدیمی Storage استفاده نمی‌شود.

لینک‌های HLS مثل `.m3u8` و محتوای DRM عمداً به عنوان MP4 جعلی ذخیره نمی‌شوند. برای تبدیل HLS به MP4
باید یک موتور remux/segment downloader جداگانه اضافه شود و برای DRM نیز محدودیت‌های فنی و حقوقی وجود دارد.

## اجرای پروژه

```bash
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter build apk --release
```

حداقل Android SDK این نسخه 29 است.

## معماری ذخیره‌سازی

Dart فایل را ابتدا در cache موقت دانلود می‌کند، سپس با MethodChannel به Android native می‌فرستد.
Android با `MediaStore.Downloads` فایل را در پوشه Downloads عمومی ثبت می‌کند و بعد فایل موقت حذف می‌شود.

## تست

قبل از انتشار APK روی یک دستگاه واقعی این موارد را تست کنید:

1. دانلود یک MP4 عمومی.
2. دانلود یک MP3 عمومی.
3. باز کردن مرورگر و شناسایی یک لینک MP4 مستقیم.
4. فعال‌سازی Overlay و دانلود از پنجره شناور.
5. بررسی فایل در برنامه Files > Downloads.
6. اجرای `flutter analyze` بدون خطا.

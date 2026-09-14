# Floating Downloader 3.0

## Aetheria Music

The Android build also includes an offline music library and playback surface. On
first use, the Music tab requests `READ_MEDIA_AUDIO` on Android 13 and newer, or
`READ_EXTERNAL_STORAGE` on older releases, then queries `MediaStore` for local
tracks of at least 30 seconds. Playback is provided by a native Media3 session,
so play/pause, queue navigation, seek, repeat, shuffle, lock-screen controls, and
background playback continue outside the Flutter UI. Audio Studio exposes the
platform equalizer, bass boost, loudness enhancer, and output-device profile
detection. The selected language (Persian/English) and Dark/Light/AMOLED theme
are persisted locally.

یک دانلودر اندرویدی مدرن با:

- دانلود واقعی فایل‌های HTTP/HTTPS
- ذخیره استاندارد در `Downloads` با Android MediaStore
- پنجره شناور برای دانلود سریع
- مرورگر داخلی با تشخیص لینک‌های مستقیم رسانه
- تاریخچه دانلودهای تکمیل‌شده
- صف دانلود با محدودیت هم‌زمانی و کنترل مکث/ادامه/لغو/تلاش دوباره
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

`DownloadQueueController` صف را خارج از `main.dart` مدیریت می‌کند و سرویس دانلود مسئول
اعتبارسنجی لینک، پاک‌سازی نام فایل و انتقال امن به MediaStore است. دانلودهای در حال اجرا
در پس‌زمینه‌ی Flutter ادامه پیدا می‌کنند؛ برای تداوم پس از کشته‌شدن کامل process، یک
foreground download service بومی (خارج از وابستگی‌های فعلی) لازم است.

## تست

قبل از انتشار APK روی یک دستگاه واقعی این موارد را تست کنید:

1. دانلود یک MP4 عمومی.
2. دانلود یک MP3 عمومی.
3. باز کردن مرورگر و شناسایی یک لینک MP4 مستقیم.
4. فعال‌سازی Overlay و دانلود از پنجره شناور.
5. بررسی فایل در برنامه Files > Downloads.
6. اجرای `flutter analyze` بدون خطا.

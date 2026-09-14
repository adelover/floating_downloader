# Floating Downloader 3.0 — اصلاحات

این نسخه بر اساس فایل ZIP ارسالی بازطراحی و اصلاح شده است.

## باگ‌ها و مشکلات اصلی اصلاح‌شده

1. حذف دانلود به مسیر ثابت `/storage/emulated/0/Download`.
2. حذف مجوزهای قدیمی `READ/WRITE_EXTERNAL_STORAGE`.
3. ذخیره واقعی فایل با Android `MediaStore.Downloads` از طریق MethodChannel.
4. حذف وابستگی و کد YouTube Explode که در نسخه قبلی مسیر دانلود ناپایدار و وابسته به APIهای YouTube ایجاد می‌کرد.
5. حذف کیفیت‌های جعلی 1080p/720p/480p؛ نسخه جدید کیفیت ساختگی نمایش نمی‌دهد.
6. جلوگیری از ذخیره‌کردن `.m3u8` به‌عنوان MP4 جعلی.
7. تشخیص لینک‌های مستقیم MP4/WebM/MKV/MOV/MP3/M4A/WAV و لینک‌های `videoplayback`.
8. مدیریت فایل موقت و پاک‌سازی آن پس از انتقال به Downloads.
9. مدیریت progress واقعی دانلود.
10. ثبت تاریخچه واقعی دانلودهای کامل‌شده.
11. مقاوم‌سازی تاریخچه در برابر JSON خراب.
12. اصلاح Search URL با `Uri.https` به‌جای چسباندن خام query.
13. اصلاح BottomSheet مرورگر؛ حذف الگوی مشکل‌ساز `Expanded` داخل `Column` با ارتفاع نامحدود.
14. اضافه شدن `onLoadResource` و `onDownloadStartRequest` در WebView برای تشخیص بهتر رسانه.
15. اضافه شدن `useOnLoadResource` و `useOnDownloadStart`.
16. اضافه شدن `mounted` checks در مسیرهای async حساس.
17. اصلاح Overlay برای Androidهای جدید و Foreground Service از نوع `specialUse`.
18. استفاده از `OverlayFlag.focusPointer` تا TextField پنجره شناور بتواند ورودی کیبورد بگیرد.
19. انتقال Android build به Plugin DSL.
20. حذف buildscript قدیمی و تنظیم Java/Kotlin روی 17.
21. ارتقای AGP به 8.6.1 و Gradle به 8.7 برای سازگاری پایدارتر با Flutter 3.47.
22. تنظیم minSdk روی 29 برای تکیه بر MediaStore و حذف مسیرهای legacy.
23. به‌روزرسانی وابستگی‌های اصلی Dio، Shared Preferences، URL Launcher و Launcher Icons.
24. اضافه شدن GitHub Actions برای `flutter analyze` و ساخت release APK.
25. اضافه شدن تست‌های unit برای helperهای دانلود.

## UI جدید

- داشبورد کاملاً جدید RTL
- Dark UI با کارت‌های مدرن
- صفحه Home با ورودی لینک و Paste
- آمار دانلودهای فعال و تکمیل‌شده
- Quick Actions
- NavigationBar مدرن
- Browser UI جدید با نوار آدرس، back/forward/reload
- لیست رسانه‌های پیدا شده با BottomSheet حرفه‌ای
- Download History با وضعیت و حجم فایل
- Settings با ساختار تمیز
- Floating Downloader بازطراحی‌شده

## محدودیت عمدی

HLS (`.m3u8`) و DRM به‌عنوان MP4 تقلبی ذخیره نمی‌شوند. برای HLS باید یک موتور segment/remux واقعی اضافه شود؛ DRM نیز قابل دور زدن یا تضمین‌شده نیست.

## اعتبارسنجی

در محیط فعلی Flutter/Dart SDK نصب نبود، بنابراین `flutter analyze` و `flutter build apk` در همین محیط قابل اجرا نبودند. ساختار YAML/XML و فایل‌های پروژه بررسی شده‌اند و workflow نیز `flutter analyze` را قبل از build اجرا می‌کند.

برای نهایی‌کردن build روی سیستم خود:

```bash
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release
```

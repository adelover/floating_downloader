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

---

# اصلاحات دور دوم (بررسی مستقل کد فعلی)

نسخه‌ی ZIP قبلی («fixed») با اینکه در `FIX_REPORT.md` ادعا شده بود کامل و آماده‌ی build است،
در عمل چند باگ واقعی داشت که مانع از build شدن یا کارکرد درست برنامه می‌شد. این‌ها همگی
بدون تغییر ساختار کلی پروژه (همان معماری تک‌فایلی `lib/main.dart` + همان تنظیمات Android) برطرف شدند:

1. **باگ بحرانی build — پکیج‌های گم‌شده در `pubspec.yaml`**: `lib/main.dart` پکیج‌های
   `flutter_inappwebview` (مرورگر داخلی) و `flutter_overlay_window` (پنجره شناور) را
   import و به‌طور کامل استفاده می‌کرد، ولی این دو در `pubspec.yaml` اصلاً اضافه نشده بودند.
   سمت Android (AndroidManifest، MainActivity) درست تنظیم شده بود، فقط پکیج‌های Flutter آن
   کم بود. نتیجه: `flutter pub get` و هر build با خطای «Target of URI doesn't exist» شکست
   می‌خورد. رفع شد با اضافه‌کردن `flutter_inappwebview: ^6.1.5` و
   `flutter_overlay_window: ^0.5.0`.

2. **کد مرده/تکراری و گمراه‌کننده**: فایل `lib/services/download_service.dart` یک نسخه‌ی
   قدیمی و کاملاً جدا از `DownloadService`/`MediaInfo` واقعی داخل `main.dart` بود (اسم‌های
   کلاس تکراری)، هیچ‌جا import نمی‌شد، از `youtube_explode_dart` قدیمی برای دانلود مستقیم
   استفاده می‌کرد (دقیقاً همان چیزی که در همین فایل ادعا شده بود حذف شده) و باگ خودش را هم
   داشت (فایل‌های mp3 را با `Gal.putImage` ذخیره می‌کرد). این فایل حذف شد و به همراه آن
   پکیج‌های `path_provider`، `permission_handler` و `gal` هم از `pubspec.yaml` پاک شدند،
   چون تنها مصرف‌کننده‌شان همین فایل بود.

3. **باگ منطقی — مرتب‌سازی کیفیت یوتیوب اشتباه بود**: در `PlatformExtractor._qualityRank`
   الگوی Regex به‌صورت `r'(\\d{3,4})p'` نوشته شده بود که در یک raw string معادل «یک بک‌اسلش
   واقعی + حرف d» است، نه رقم؛ یعنی هیچ‌وقت با برچسب‌هایی مثل `720p` مطابقت پیدا نمی‌کرد و
   نتیجه‌اش این بود که کیفیت‌های ویدیوی یوتیوب هیچ‌وقت واقعاً بر اساس رزولوشن مرتب نمی‌شدند.
   به `r'(\d{3,4})p'` اصلاح شد.

4. **مرورگر/دانلود لینک‌های HTTP ساده کار نمی‌کرد**: در AndroidManifest
   `android:usesCleartextTraffic="false"` بود، در حالی که خود `DownloadService.download`
   صراحتاً اسکیم `http` را هم قبول می‌کند و مرورگر داخلی قرار است هر سایتی را باز کند. با
   کلایرتکست خاموش، اندروید هر درخواست HTTP (بدون TLS) را در سطح سیستم‌عامل بلاک می‌کند،
   حتی اگر کد Dart اجازه‌اش را بدهد. به `true` تغییر یافت تا لینک‌های http هم واقعاً کار کنند.

5. **باگ CI/Build — Gradle Wrapper اصلاً داخل ZIP نبود**: نه `android/gradlew`، نه
   `android/gradlew.bat` و نه `android/gradle/wrapper/gradle-wrapper.jar` در پروژه وجود
   داشتند (فقط `gradle-wrapper.properties` بود). بدون این فایل‌ها هر build (چه در
   GitHub Actions چه لوکال) بلافاصله با خطای «Cannot find executable for gradlew» شکست
   می‌خورد. یک مرحله‌ی جدید به `.github/workflows/build.yml` اضافه شد که قبل از build با
   Gradle از‌پیش‌نصب‌شده‌ی خود ranner (`gradle wrapper --gradle-version 8.12
   --distribution-type all`) این فایل‌ها را می‌سازد. **برای build لوکال (مثلاً از طریق
   Termux/proot با Flutter نصب‌شده)**، اگر به همین خطا برخوردید، یک‌بار از ریشه‌ی پروژه
   `flutter create .` را اجرا کنید (فایل‌های lib و تنظیمات فعلی شما دست‌نخورده می‌مانند و
   فقط فایل‌های پلتفرمی گم‌شده مثل Gradle Wrapper بازسازی می‌شوند)، یا مستقیماً در پوشه‌ی
   `android` دستور `gradle wrapper --gradle-version 8.12 --distribution-type all` را
   بزنید.

6. **نظافت مخزن**: یک `README(1).md` تکراری (نسخه‌ی ناقص‌تر همان `README.md`) حذف شد و یک
   `.gitignore` استاندارد Flutter اضافه شد، چون پروژه قبلاً هیچ `.gitignore`ای نداشت و خطر
   داشت فایل‌های build/امضا به‌اشتباه commit شوند. طبق همین `.gitignore`، فایل‌های
   `android/gradlew`، `gradlew.bat` و `gradle-wrapper.jar` عمداً از گیت کنار گذاشته شده‌اند
   (چون هر بار در CI ساخته می‌شوند)؛ برای build لوکال طبق بند ۵ عمل کنید.

## چیزهایی که تغییر داده نشد

- معماری کلی (`lib/main.dart` تک‌فایلی، ساختار Android، اسم پکیج، نسخه‌ها) دست‌نخورده ماند.
- منطق اصلی دانلود/اعتبارسنجی فایل که در دور اول درست پیاده‌سازی شده بود (بدون فایل جعلی،
  MediaStore، بررسی Content-Type و Magic Number) همان‌طور باقی ماند چون مشکلی نداشت.

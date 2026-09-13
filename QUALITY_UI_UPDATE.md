# نسخه اصلاح‌شده Floating Downloader

## اصلاحات این نسخه

- اتصال استخراج‌کننده YouTube به `youtube_explode_dart` به‌جای oEmbed تنها.
- استخراج عنوان، سازنده، thumbnail و StreamManifest واقعی.
- نمایش کیفیت‌های واقعی muxed و bitrateهای واقعی audio.
- دانلود مستقیم StreamInfo با progress واقعی و ذخیره در MediaStore/Downloads.
- فرمت صوتی YouTube به‌صورت M4A/AAC ذخیره می‌شود؛ بدون جعل MP3.
- جلوگیری از نمایش کیفیت‌های ساختگی.
- رفع دو خطای احتمالی Dart در `catchError` برای حذف فایل موقت.
- فعال شدن کارت YouTube به‌عنوان پلتفرم قابل دانلود.
- اضافه شدن سوییچ سریع Dark/Light در هدر صفحه خانه.
- نگه‌داشتن تنظیمات تم با SharedPreferences.
- تم روشن/تاریک و کارت‌ها/Borderهای theme-aware.
- حفظ UI RTL با حال‌وهوای Telegram (رنگ آبی، کارت‌های گرد، NavigationBar و quick actions).

## محدودیت YouTube

YouTube بسیاری از کیفیت‌های بالاتر از 360p را به‌صورت video-only ارائه می‌کند؛ این نسخه فقط streamهایی را برای دانلود مستقیم نشان می‌دهد که صدا و تصویر را در یک فایل دارند، بنابراین فایل خروجی ناقص تولید نمی‌شود. برای 720p/1080p واقعی باید video-only + audio-only با یک muxer/FFmpeg ترکیب شوند.

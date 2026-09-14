import 'package:flutter/services.dart';

/// کانال ارتباطی مشترک با کد Kotlin سمت اندروید (ذخیره در Downloads،
/// باز/اشتراک/حذف فایل، بررسی Wi-Fi، دریافت متن اشتراک‌گذاری‌شده).
final storageChannel = MethodChannel('com.example.floating_downloader/storage');

/// User-Agent یکسان بین مرورگر داخلی و سرویس دانلود، تا سرور همیشه یک
/// مرورگر را ببیند (جلوگیری از رد شدن درخواست به‌خاطر ناهماهنگی هدر).
final browserUserAgent =
    'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/131 Mobile Safari/537.36';

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// مدل کاربر احراز‌شده
class AuthUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String provider; // 'google' یا 'github'
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  AuthUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.provider,
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'provider': provider,
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String,
    photoUrl: json['photoUrl'] as String?,
    provider: json['provider'] as String,
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String?,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );

  bool get isTokenExpired => DateTime.now().isAfter(expiresAt);
}

/// سرویس احراز‌هویت مرکزی برای Google و GitHub
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  late final GoogleSignIn _googleSignIn;
  late final Dio _dio;
  
  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _error;

  // تنظیمات GitHub OAuth
  static const String _githubClientId = 'YOUR_GITHUB_CLIENT_ID';
  static const String _githubClientSecret = 'YOUR_GITHUB_CLIENT_SECRET';
  static const String _githubRedirectUrl = 'com.floating.downloader://oauth-callback';
  static const String _githubAuthUrl = 'https://github.com/login/oauth/authorize';
  static const String _githubTokenUrl = 'https://github.com/login/oauth/access_token';
  static const String _githubApiUrl = 'https://api.github.com';

  AuthUser? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _currentUser != null && !_currentUser!.isTokenExpired;

  Future<void> initialize() async {
    _googleSignIn = GoogleSignIn(
      scopes: ['email', 'profile'],
    );
    _dio = Dio();
    await _loadStoredUser();
  }

  /// بارگیری کاربر ذخیره‌شده از SharedPreferences
  Future<void> _loadStoredUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('auth_user');
      
      if (userJson != null) {
        _currentUser = AuthUser.fromJson(jsonDecode(userJson));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('خطا در بارگیری کاربر ذخیره‌شده: $e');
    }
  }

  /// ذخیره کاربر در SharedPreferences
  Future<void> _saveUser(AuthUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user', jsonEncode(user.toJson()));
      _currentUser = user;
      notifyListeners();
    } catch (e) {
      debugPrint('خطا در ذخیره کاربر: $e');
    }
  }

  /// ورود با Google
  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _error = 'ورود گوگل لغو شد.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final now = DateTime.now();
      
      final user = AuthUser(
        id: googleUser.id,
        email: googleUser.email,
        displayName: googleUser.displayName ?? 'کاربر Google',
        photoUrl: googleUser.photoUrl,
        provider: 'google',
        accessToken: googleAuth.accessToken ?? '',
        refreshToken: googleAuth.idToken,
        expiresAt: now.add(Duration(hours: 1)),
      );

      await _saveUser(user);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'خطا در ورود گوگل: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// ورود با GitHub (استفاده از OAuth2)
  Future<bool> signInWithGitHub() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. تولید state برای امنیت
      final state = _generateRandomString(32);
      
      // 2. ساخت Authorization URL
      final authUrl = Uri.parse(_githubAuthUrl).replace(
        queryParameters: {
          'client_id': _githubClientId,
          'redirect_uri': _githubRedirectUrl,
          'scope': 'user:email read:user',
          'state': state,
          'allow_signup': 'true',
        },
      );

      // 3. باز کردن مرورگر برای ورود
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw 'نمی‌توان URL GitHub را باز کرد.';
      }

      // نکته: در یک app واقعی، باید Deep Link یا Custom URL Scheme را مدیریت کنید
      // تا پس از ورود GitHub، کاربر به برنامه برگردد و کد authorization را دریافت کنید.
      // این مثال ساده‌شده است.
      
      _error = 'لطفاً پس از ورود به GitHub، به برنامه برگردید.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'خطا در ورود GitHub: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// پردازش Authorization Code از GitHub (پس از Callback)
  Future<bool> handleGitHubCallback(String authCode) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. تبدیل Authorization Code به Access Token
      final tokenResponse = await _dio.post(
        _githubTokenUrl,
        options: Options(
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'client_id': _githubClientId,
          'client_secret': _githubClientSecret,
          'code': authCode,
          'redirect_uri': _githubRedirectUrl,
        },
      );

      if (tokenResponse.statusCode != 200) {
        throw 'خطا در دریافت توکن: ${tokenResponse.statusMessage}';
      }

      final accessToken = tokenResponse.data['access_token'] as String?;
      if (accessToken == null) {
        throw 'توکن دریافت نشد.';
      }

      // 2. دریافت اطلاعات کاربر GitHub
      final userResponse = await _dio.get(
        '$_githubApiUrl/user',
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Accept': 'application/vnd.github+json',
          },
        ),
      );

      if (userResponse.statusCode != 200) {
        throw 'خطا در دریافت اطلاعات کاربر.';
      }

      final userData = userResponse.data as Map<String, dynamic>;
      
      // 3. دریافت ایمیل کاربر
      String userEmail = userData['email'] as String? ?? '${userData['login']}@github.com';
      
      if (userEmail.isEmpty) {
        final emailResponse = await _dio.get(
          '$_githubApiUrl/user/emails',
          options: Options(
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Accept': 'application/vnd.github+json',
            },
          ),
        );

        if (emailResponse.statusCode == 200) {
          final emails = emailResponse.data as List?;
          if (emails != null && emails.isNotEmpty) {
            userEmail = (emails.first as Map<String, dynamic>)['email'] as String? ?? '';
          }
        }
      }

      final now = DateTime.now();
      final user = AuthUser(
        id: userData['id'].toString(),
        email: userEmail,
        displayName: userData['name'] as String? ?? userData['login'] as String? ?? 'GitHub User',
        photoUrl: userData['avatar_url'] as String?,
        provider: 'github',
        accessToken: accessToken,
        refreshToken: null, // GitHub OAuth2 توکن‌های refresh دارند اگر برای آن درخواست کنید
        expiresAt: now.add(Duration(hours: 8)), // GitHub tokens عادی منقضی نمی‌شوند
      );

      await _saveUser(user);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'خطا در پردازش ورود GitHub: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// خروج
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_currentUser?.provider == 'google') {
        await _googleSignIn.signOut();
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_user');
      
      _currentUser = null;
      _error = null;
    } catch (e) {
      _error = 'خطا در خروج: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// تجدید Access Token (اگر منقضی شده باشد)
  Future<void> refreshTokenIfNeeded() async {
    if (_currentUser == null || !_currentUser!.isTokenExpired) return;

    try {
      if (_currentUser!.provider == 'google' && _currentUser!.refreshToken != null) {
        final googleUser = await _googleSignIn.signInSilently();
        if (googleUser != null) {
          final googleAuth = await googleUser.authentication;
          final newToken = googleAuth.accessToken;
          
          if (newToken != null) {
            final updatedUser = AuthUser(
              id: _currentUser!.id,
              email: _currentUser!.email,
              displayName: _currentUser!.displayName,
              photoUrl: _currentUser!.photoUrl,
              provider: _currentUser!.provider,
              accessToken: newToken,
              refreshToken: _currentUser!.refreshToken,
              expiresAt: DateTime.now().add(Duration(hours: 1)),
            );
            await _saveUser(updatedUser);
          }
        }
      }
    } catch (e) {
      debugPrint('خطا در تجدید توکن: $e');
    }
  }

  /// کمک‌کننده: تولید string تصادفی
  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecond;
    return List.generate(
      length,
      (index) => chars[(random + index) % chars.length],
    ).join();
  }

  /// دریافت User Agent برای درخواست
  String get userAgent => 'FloatingDownloader/3.6.0 (OAuth2 Client)';
}

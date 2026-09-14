import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String provider;
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

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  AuthService._internal();

  late final GoogleSignIn _googleSignIn;
  late final Dio _dio;
  
  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _error;

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
    _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
    _dio = Dio();
    await _loadStoredUser();
  }

  Future<void> _loadStoredUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('auth_user');
      if (userJson != null) {
        _currentUser = AuthUser.fromJson(jsonDecode(userJson));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    }
  }

  Future<void> _saveUser(AuthUser user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user', jsonEncode(user.toJson()));
      _currentUser = user;
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving user: $e');
    }
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _error = 'Google login cancelled';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final now = DateTime.now();
      
      final user = AuthUser(
        id: googleUser.id,
        email: googleUser.email,
        displayName: googleUser.displayName ?? 'Google User',
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
      _error = 'Google login error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signInWithGitHub() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final state = _generateRandomString(32);
      final authUrl = Uri.parse(_githubAuthUrl).replace(
        queryParameters: {
          'client_id': _githubClientId,
          'redirect_uri': _githubRedirectUrl,
          'scope': 'user:email read:user',
          'state': state,
          'allow_signup': 'true',
        },
      );

      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        throw 'Cannot open GitHub URL';
      }

      _error = 'After logging in to GitHub, please return to the app';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'GitHub login error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> handleGitHubCallback(String authCode) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final tokenResponse = await _dio.post(
        _githubTokenUrl,
        options: Options(headers: {'Accept': 'application/json'}),
        data: {
          'client_id': _githubClientId,
          'client_secret': _githubClientSecret,
          'code': authCode,
          'redirect_uri': _githubRedirectUrl,
        },
      );

      final accessToken = tokenResponse.data['access_token'] as String?;
      if (accessToken == null) throw 'Token not received';

      final userResponse = await _dio.get(
        '$_githubApiUrl/user',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );

      final userData = userResponse.data as Map<String, dynamic>;
      String userEmail = userData['email'] as String? ?? '${userData['login']}@github.com';

      final now = DateTime.now();
      final user = AuthUser(
        id: userData['id'].toString(),
        email: userEmail,
        displayName: userData['name'] ?? userData['login'] ?? 'GitHub User',
        photoUrl: userData['avatar_url'] as String?,
        provider: 'github',
        accessToken: accessToken,
        refreshToken: null,
        expiresAt: now.add(Duration(hours: 8)),
      );

      await _saveUser(user);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'GitHub callback error: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

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
      _error = 'Logout error: ${e.toString()}';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _generateRandomString(int length) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().millisecond;
    return List.generate(length, (index) => chars[(random + index) % chars.length]).join();
  }
}

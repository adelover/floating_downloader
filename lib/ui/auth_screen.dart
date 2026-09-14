import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

Color get _bg => Color(0xFF090B12);
Color get _surface => Color(0xFF121722);
Color get _primary => Color(0xFF7C5CFF);
Color get _cyan => Color(0xFF2AABEE);
Color get _success => Color(0xFF36D399);
Color get _danger => Color(0xFFFF5D73);
Color get _muted => Color(0xFF8D96A8);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Consumer<AuthService>(
          builder: (context, authService, _) {
            if (authService.isAuthenticated) {
              return _UserProfile(user: authService.currentUser!);
            }
            return _LoginScreen();
          },
        ),
      ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 40),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [_primary, _cyan],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _cyan.withOpacity(.35),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(Icons.security_rounded, color: Colors.white, size: 64),
                ),
                SizedBox(height: 32),
                Text(
                  'احراز‌هویت امن',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'برای دسترسی به تمام ویژگی‌های Floating Downloader، لطفاً با حساب Google یا GitHub خود وارد شوید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                SizedBox(height: 40),
                
                // Google Sign-In Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: authService.isLoading
                        ? null
                        : () async {
                            final success = await authService.signInWithGoogle();
                            if (success && mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: Color(0xFFEA4335),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: authService.isLoading && authService.currentUser == null
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.g_mobiledata, size: 24),
                    label: Text(
                      'ورود با Google',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                
                // GitHub Sign-In Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: authService.isLoading
                        ? null
                        : () async {
                            final success = await authService.signInWithGitHub();
                            if (success && mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: Color(0xFF24292E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: authService.isLoading && authService.currentUser == null
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.code, size: 24),
                    label: Text(
                      'ورود با GitHub',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                
                if (authService.error != null) ...[
                  SizedBox(height: 24),
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _danger.withOpacity(.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _danger.withOpacity(.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: _danger, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            authService.error!,
                            style: TextStyle(color: _danger, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                SizedBox(height: 32),
                Text(
                  'داده‌های شما محفوظ و رمزگذاری شده نگهداری می‌شوند',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UserProfile extends StatelessWidget {
  final AuthUser user;

  const _UserProfile({required this.user});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                SizedBox(height: 24),
                if (user.photoUrl != null)
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(user.photoUrl!),
                  )
                else
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [_primary, _cyan],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                    ),
                    child: Icon(Icons.person_rounded, color: Colors.white, size: 60),
                  ),
                SizedBox(height: 24),
                Text(
                  user.displayName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  user.email,
                  style: TextStyle(
                    color: _muted,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 12),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: user.provider == 'google'
                        ? Color(0xFFEA4335).withOpacity(.2)
                        : Color(0xFF24292E).withOpacity(.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: user.provider == 'google'
                          ? Color(0xFFEA4335).withOpacity(.5)
                          : Color(0xFF24292E).withOpacity(.5),
                    ),
                  ),
                  child: Text(
                    user.provider == 'google' ? 'ورود شده با Google' : 'ورود شده با GitHub',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: user.provider == 'google'
                          ? Color(0xFFEA4335)
                          : Color(0xFF24292E),
                    ),
                  ),
                ),
                SizedBox(height: 40),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _primary.withOpacity(.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'اطلاعات حساب',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 16),
                      _InfoRow(label: 'ID', value: user.id),
                      SizedBox(height: 12),
                      _InfoRow(label: 'ایمیل', value: user.email),
                      SizedBox(height: 12),
                      _InfoRow(
                        label: 'منقضی‌شدن توکن',
                        value: user.expiresAt.toLocal().toString().split('.')[0],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await authService.signOut();
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _danger, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(Icons.logout_rounded, color: _danger),
                    label: Text(
                      'خروج از حساب',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: _danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

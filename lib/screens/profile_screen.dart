import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:student_amaliyot_app/services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthService
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {
  static const _keyUserId = 'user_id';
  static const _keyToken = 'token';
  static const _keyUsername = 'username';

  static Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    try {
      final res = await http
          .post(
        Uri.parse('https://shaxa.mycoder.uz/api/student/login'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      )
          .timeout(const Duration(seconds: 15));

      final body = jsonDecode(res.body) as Map<String, dynamic>;

      if (res.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>? ?? {};
        final student = data['student'] as Map<String, dynamic>? ?? {};

        final rawId = student['id'];
        final int? userId =
        rawId == null ? null : int.tryParse(rawId.toString());
        final token = data['token']?.toString();
        final uname = student['username']?.toString() ?? username;

        if (userId == null || token == null || token.isEmpty) {
          return AuthResult.failure(
            "Server noto'g'ri javob berdi (id yoki token yo'q).",
          );
        }

        await saveSession(
          userId: userId,
          token: token,
          username: uname,
        );

        return AuthResult.success(userId: userId, token: token);
      }

      final msg = body['message']?.toString() ??
          body['detail']?.toString() ??
          'Login xato (${res.statusCode})';

      return AuthResult.failure(msg);
    } on SocketException {
      return AuthResult.failure('Internet aloqasi mavjud emas.');
    } on TimeoutException {
      return AuthResult.failure('Server javob bermadi.');
    } on FormatException {
      return AuthResult.failure("Serverdan noto'g'ri javob keldi.");
    } catch (e) {
      return AuthResult.failure('Xato: $e');
    }
  }

  static Future<void> saveSession({
    required int userId,
    required String token,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUserId, userId);
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUsername, username);
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_keyUserId);
    final token = prefs.getString(_keyToken);
    return id != null && token != null && token.isNotEmpty;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUsername);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyUserId);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthResult
// ─────────────────────────────────────────────────────────────────────────────
class AuthResult {
  final bool ok;
  final String? error;
  final int? userId;
  final String? token;

  const AuthResult._({
    required this.ok,
    this.error,
    this.userId,
    this.token,
  });

  factory AuthResult.success({
    required int userId,
    required String token,
  }) =>
      AuthResult._(
        ok: true,
        userId: userId,
        token: token,
      );

  factory AuthResult.failure(String error) =>
      AuthResult._(
        ok: false,
        error: error,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Nested models
// ─────────────────────────────────────────────────────────────────────────────
class StudentGroup {
  final int id;
  final String name;
  final String faculty;
  final String directionName;
  final int studentCount;

  const StudentGroup({
    required this.id,
    required this.name,
    required this.faculty,
    required this.directionName,
    required this.studentCount,
  });

  factory StudentGroup.fromJson(Map<String, dynamic> j) {
    final directionJson = j['direction'] as Map<String, dynamic>?;

    return StudentGroup(
      id: int.tryParse(j['id'].toString()) ?? 0,
      name: j['name']?.toString() ?? '—',
      faculty: j['faculty']?.toString() ?? '—',
      directionName: directionJson?['name']?.toString() ??
          j['direction_name']?.toString() ??
          '—',
      studentCount: int.tryParse(
        (j['students_count'] ?? j['student_count'] ?? 0).toString(),
      ) ??
          0,
    );
  }
}

class StudentOrganization {
  final int id;
  final String name;
  final String? address;
  final String? phone;
  final String? email;

  const StudentOrganization({
    required this.id,
    required this.name,
    this.address,
    this.phone,
    this.email,
  });

  factory StudentOrganization.fromJson(Map<String, dynamic> j) =>
      StudentOrganization(
        id: int.tryParse(j['id'].toString()) ?? 0,
        name: j['name']?.toString() ?? '—',
        address: j['address']?.toString(),
        phone: j['phone']?.toString(),
        email: j['email']?.toString(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Main model
// ─────────────────────────────────────────────────────────────────────────────
class StudentProfile {
  final int id;
  final String username;
  final String fullName;
  final String groupName;
  final String faculty;
  final bool isActive;
  final String? internshipStart;
  final String? internshipEnd;
  final String? createdAt;
  final StudentGroup? group;
  final StudentOrganization? organization;

  const StudentProfile({
    required this.id,
    required this.username,
    required this.fullName,
    required this.groupName,
    required this.faculty,
    required this.isActive,
    this.internshipStart,
    this.internshipEnd,
    this.createdAt,
    this.group,
    this.organization,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) {
    final d = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    final groupJson = d['group'] as Map<String, dynamic>?;
    final orgJson = d['organization'] as Map<String, dynamic>?;

    return StudentProfile(
      id: int.tryParse(d['id'].toString()) ?? 0,
      username: d['username']?.toString() ?? '—',
      fullName: d['full_name']?.toString() ?? '—',
      groupName:
      groupJson?['name']?.toString() ?? d['group_name']?.toString() ?? '—',
      faculty:
      groupJson?['faculty']?.toString() ?? d['faculty']?.toString() ?? '—',
      isActive: d['is_active'] == true ||
          d['is_active'].toString() == 'true' ||
          d['is_active'].toString() == '1',
      internshipStart: d['internship_start_date']?.toString(),
      internshipEnd: d['internship_end_date']?.toString(),
      createdAt: d['created_at']?.toString(),
      group: groupJson != null ? StudentGroup.fromJson(groupJson) : null,
      organization:
      orgJson != null ? StudentOrganization.fromJson(orgJson) : null,
    );
  }

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2 &&
        parts[0].isNotEmpty &&
        parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';
  }

  String get formattedDate {
    if (createdAt == null || createdAt!.isEmpty) return '—';
    try {
      final dt = DateTime.parse(createdAt!).toLocal();
      return '${_p(dt.day)}.${_p(dt.month)}.${dt.year}';
    } catch (_) {
      return createdAt!;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

// ─────────────────────────────────────────────────────────────────────────────
// AkkountPage
// ─────────────────────────────────────────────────────────────────────────────
class AkkountPage extends StatefulWidget {
  const AkkountPage({super.key});

  @override
  State<AkkountPage> createState() => _AkkountPageState();
}

class _AkkountPageState extends State<AkkountPage>
    with SingleTickerProviderStateMixin {
  StudentProfile? _profile;
  bool _isLoading = true;
  String _error = '';

  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  String formatDate(String? value) {
    if (value == null || value.isEmpty) return 'Belgilanmagan';

    try {
      final dt = DateTime.parse(value).toLocal();
      return '${dt.year}-${_p(dt.month)}-${_p(dt.day)}';
    } catch (_) {
      return value;
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _shimmerAnim = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOutSine),
    );

    _loadProfile();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final apiService = ApiService();
      final token = await apiService.getToken();

      if (token == null || token.isEmpty) {
        return _setError('Sessiya tugagan. Iltimos qayta kiring.');
      }

      final res = await http
          .get(
        Uri.parse('https://shaxa.mycoder.uz/api/student/portal/profile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      switch (res.statusCode) {
        case 200:
          final body = json.decode(res.body) as Map<String, dynamic>;
          setState(() {
            _profile = StudentProfile.fromJson(body);
            _isLoading = false;
          });
          break;

        case 401:
          await apiService.clearSession();
          _setError('Sessiya tugagan. Iltimos qayta kiring.');
          break;

        case 403:
          _setError("Bu akkauntga ruxsat yo'q.");
          break;

        case 404:
          _setError('Profil topilmadi.');
          break;

        default:
          _setError('Server xatosi (${res.statusCode}).');
          break;
      }
    } on SocketException {
      if (mounted) _setError('Internet aloqasi mavjud emas.');
    } on TimeoutException {
      if (mounted) {
        _setError("Server javob bermadi. Keyinroq urinib ko'ring.");
      }
    } on FormatException {
      if (mounted) _setError("Serverdan noto'g'ri javob keldi.");
    } catch (e) {
      if (mounted) _setError('Xato: $e');
    }
  }

  void _setError(String msg) {
    setState(() {
      _error = msg;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        color: Colors.teal,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: _isLoading
                  ? _buildShimmer()
                  : _error.isNotEmpty
                  ? _buildError()
                  : _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 230,
      pinned: true,
      backgroundColor: Colors.teal.shade700,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
        onPressed: () => Navigator.maybePop(context),
      ),
      actions: [
        IconButton(
          tooltip: 'Yangilash',
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: _loadProfile,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF00695C), Color(0xFF00ACC1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Positioned(
              top: -50,
              right: -50,
              child: _circle(200, Colors.white.withOpacity(0.06)),
            ),
            Positioned(
              bottom: -40,
              left: -40,
              child: _circle(160, Colors.white.withOpacity(0.05)),
            ),
            if (!_isLoading && _error.isEmpty && _profile != null)
              SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 12),
                    Stack(
                      children: [
                        Hero(
                          tag: 'profile_avatar',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 14,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 42,
                              backgroundColor: Colors.teal.shade800,
                              child: Text(
                                _profile!.initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 3,
                          right: 3,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: _profile!.isActive
                                  ? Colors.greenAccent.shade400
                                  : Colors.grey,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _profile!.fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        _profile!.isActive ? '⛔  Nofaol' : '✅  Faol talaba',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
    ),
  );

  Widget _buildContent() {
    final p = _profile!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label("Shaxsiy ma'lumotlar"),
          _InfoCard(
            items: [
              _InfoItem(
                Icons.person_outline_rounded,
                'Username',
                p.username,
              ),
              _InfoItem(
                Icons.calendar_today_outlined,
                "Ro'yxatdan o'tgan",
                p.formattedDate,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _label("Ta'lim ma'lumotlari"),
          _InfoCard(
            items: [
              _InfoItem(Icons.school_outlined, "Fakultet", p.faculty),
              _InfoItem(Icons.group_outlined, 'Guruh', p.groupName),
              if (p.group != null)
                _InfoItem(
                  Icons.event_note_outlined,
                  "Yo'nalish",
                  p.group!.directionName,
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (p.organization != null) ...[
            _label('Amaliyot tashkiloti'),
            _InfoCard(
              items: [
                _InfoItem(
                  Icons.business_outlined,
                  'Tashkilot',
                  p.organization!.name,
                ),
                if (p.organization!.address != null)
                  _InfoItem(
                    Icons.location_on_outlined,
                    'Manzil',
                    p.organization!.address!,
                  ),
                if (p.organization!.phone != null)
                  _InfoItem(
                    Icons.phone_outlined,
                    'Telefon',
                    p.organization!.phone!,
                  ),
                if (p.organization!.email != null)
                  _InfoItem(
                    Icons.email_outlined,
                    'Email',
                    p.organization!.email!,
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _label('Amaliyot muddati'),
          _InfoCard(
            items: [
              _InfoItem(
                Icons.play_circle_outline,
                'Boshlanish',
                formatDate(p.internshipStart),
              ),
              _InfoItem(
                Icons.stop_circle_outlined,
                'Tugash',
                formatDate(p.internshipEnd),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Color(0xFF2C3E50),
        letterSpacing: 0.1,
      ),
    ),
  );

  Widget _buildShimmer() {
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _ShimmerBox(
              width: double.infinity,
              height: 110,
              anim: _shimmerAnim,
            ),
            const SizedBox(height: 16),
            _ShimmerBox(
              width: double.infinity,
              height: 150,
              anim: _shimmerAnim,
            ),
            const SizedBox(height: 16),
            _ShimmerBox(
              width: double.infinity,
              height: 110,
              anim: _shimmerAnim,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ShimmerBox(
                    height: 80,
                    anim: _shimmerAnim,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShimmerBox(
                    height: 80,
                    anim: _shimmerAnim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return SizedBox(
      height: 380,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.red.shade400,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _error,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  "Qayta urinish",
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────
class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem(this.icon, this.label, this.value);
}

class _InfoCard extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoCard({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length * 2 - 1, (i) {
          if (i.isOdd) {
            return const Divider(
              height: 1,
              indent: 56,
              endIndent: 16,
              thickness: 0.5,
            );
          }

          return _InfoRow(item: items[i ~/ 2]);
        }),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final _InfoItem item;

  const _InfoRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.icon,
              color: Colors.teal.shade600,
              size: 19,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1A2533),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double? width;
  final double height;
  final Animation<double> anim;
  final double radius;

  const _ShimmerBox({
    this.width,
    required this.height,
    required this.anim,
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment(anim.value - 1, 0),
          end: Alignment(anim.value + 1, 0),
          colors: const [
            Color(0xFFE8EDF2),
            Color(0xFFF4F7FA),
            Color(0xFFE8EDF2),
          ],
        ),
      ),
    );
  }
}
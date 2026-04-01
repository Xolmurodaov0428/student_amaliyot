import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AuthService helper
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {
  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────
class AttendanceRecord {
  final int id;
  final int studentId;
  final DateTime date;
  final String session;
  final String status;
  final String? checkInTime;
  final String? checkOutTime;
  final String? notes;
  final double? latitude;
  final double? longitude;

  const AttendanceRecord({
    required this.id,
    required this.studentId,
    required this.date,
    required this.session,
    required this.status,
    this.checkInTime,
    this.checkOutTime,
    this.notes,
    this.latitude,
    this.longitude,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) {
    return AttendanceRecord(
      id: int.tryParse(j['id'].toString()) ?? 0,
      studentId: int.tryParse(j['student_id'].toString()) ?? 0,
      date: DateTime.parse(
        j['date']?.toString() ?? DateTime.now().toIso8601String(),
      ),
      session: j['session']?.toString() ?? 'session_1',
      status: j['status']?.toString() ?? 'absent',
      checkInTime: j['check_in_time']?.toString(),
      checkOutTime: j['check_out_time']?.toString(),
      notes: j['notes']?.toString(),
      latitude: double.tryParse(j['latitude']?.toString() ?? ''),
      longitude: double.tryParse(j['longitude']?.toString() ?? ''),
    );
  }

  int get sessionNumber {
    if (session.contains('1')) return 1;
    if (session.contains('2')) return 2;
    if (session.contains('3')) return 3;
    return 1;
  }

  String get sessionName {
    if (sessionNumber == 1) return 'Ertalabki seans';
    if (sessionNumber == 2) return 'Kunduzi seans';
    return 'Kechki seans';
  }
}

class DayAttendance {
  final DateTime date;
  final List<AttendanceRecord> records;
  final int dailySessions;

  const DayAttendance(this.date, this.records, this.dailySessions);

  bool get session1 =>
      records.any((r) => r.sessionNumber == 1 && r.status == 'present');

  bool get session2 =>
      records.any((r) => r.sessionNumber == 2 && r.status == 'present');

  bool get session3 =>
      records.any((r) => r.sessionNumber == 3 && r.status == 'present');

  int get presentCount {
    int count = 0;
    if (session1) count++;
    if (dailySessions >= 2 && session2) count++;
    if (dailySessions >= 3 && session3) count++;
    return count;
  }

  String get statusLabel {
    if (presentCount >= dailySessions) return "To'liq";
    if (presentCount == 0) return "Yo'q";
    return 'Qisman';
  }

  String get dateStr =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Responsive helper
// ─────────────────────────────────────────────────────────────────────────────
class _R {
  final double w;
  const _R(this.w);

  bool get isXS => w < 360;
  bool get isSM => w < 414;

  double get pad => isXS ? 10 : (isSM ? 14 : 18);
  double get gap => isXS ? 12 : (isSM ? 16 : 20);
  double get radius => isXS ? 12 : 16;

  double get fs10 => isXS ? 10 : (isSM ? 11 : 12);
  double get fs12 => isXS ? 11 : (isSM ? 12 : 13);
  double get fs14 => isXS ? 12 : (isSM ? 13 : 14);
  double get fs16 => isXS ? 13 : (isSM ? 15 : 16);
  double get fs18 => isXS ? 14 : (isSM ? 16 : 18);
  double get fs20 => isXS ? 16 : (isSM ? 18 : 20);
  double get fs32 => isXS ? 24 : (isSM ? 28 : 32);

  double get iconSm => isXS ? 18 : (isSM ? 20 : 22);
  double get iconMd => isXS ? 22 : (isSM ? 24 : 26);
  double get circle => isXS ? 100 : (isSM ? 115 : 130);
  double get stroke => isXS ? 9 : (isSM ? 10 : 12);
  double get slotPad => isXS ? 6 : (isSM ? 8 : 10);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────
class DavomatPage extends StatefulWidget {
  const DavomatPage({super.key});

  @override
  State<DavomatPage> createState() => _DavomatPageState();
}

class _DavomatPageState extends State<DavomatPage> {
  bool is9amChecked = false;
  bool is1pmChecked = false;
  bool is4pmChecked = false;
  DateTime selectedDate = DateTime.now();

  bool _isLoading = false;
  String _error = '';

  List<DayAttendance> _history = [];
  int dailySessions = 3;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  int get _selectedCount =>
      [is9amChecked, is1pmChecked, is4pmChecked].where((e) => e).length;

  bool _canSelectMore() => _selectedCount < dailySessions;

  String _selectedDateKey() {
    return '${selectedDate.year.toString().padLeft(4, '0')}-'
        '${selectedDate.month.toString().padLeft(2, '0')}-'
        '${selectedDate.day.toString().padLeft(2, '0')}';
  }

  Set<String> _existingSessionsForSelectedDate() {
    final target = _selectedDateKey();

    for (final day in _history) {
      final dayKey = '${day.date.year.toString().padLeft(4, '0')}-'
          '${day.date.month.toString().padLeft(2, '0')}-'
          '${day.date.day.toString().padLeft(2, '0')}';

      if (dayKey == target) {
        return day.records
            .where((r) => r.status == 'present')
            .map((r) => r.session)
            .toSet();
      }
    }

    return <String>{};
  }

  void _syncCheckedSessionsFromHistory() {
    final existing = _existingSessionsForSelectedDate();

    setState(() {
      is9amChecked = existing.contains('session_1');
      is1pmChecked = existing.contains('session_2');
      is4pmChecked = existing.contains('session_3');
    });
  }

  void _handleCheck({
    required int sessionNumber,
    required bool? value,
  }) {
    final newValue = value ?? false;
    final existing = _existingSessionsForSelectedDate();

    if (sessionNumber == 1 && existing.contains('session_1')) {
      _snack('Bu sana uchun 1-seans allaqachon saqlangan.', Colors.orange);
      return;
    }
    if (sessionNumber == 2 && existing.contains('session_2')) {
      _snack('Bu sana uchun 2-seans allaqachon saqlangan.', Colors.orange);
      return;
    }
    if (sessionNumber == 3 && existing.contains('session_3')) {
      _snack('Bu sana uchun 3-seans allaqachon saqlangan.', Colors.orange);
      return;
    }

    if (newValue && !_canSelectMore()) {
      _snack(
        'Bir kunda faqat $dailySessions ta seans belgilash mumkin.',
        Colors.orange,
      );
      return;
    }

    setState(() {
      if (sessionNumber == 1) is9amChecked = newValue;
      if (sessionNumber == 2) is1pmChecked = newValue;
      if (sessionNumber == 3) is4pmChecked = newValue;
    });
  }

  String _currentTimeHHmm() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime _sessionWindowStart(String session) {
    if (dailySessions == 1) {
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        11,
        30,
      );
    }

    if (dailySessions == 2) {
      if (session == 'session_1') {
        return DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          9,
          0,
        );
      }
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        13,
        0,
      );
    }

    if (session == 'session_1') {
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        9,
        0,
      );
    }

    if (session == 'session_2') {
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        13,
        0,
      );
    }

    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      15,
      30,
    );
  }

  DateTime _sessionWindowEnd(String session) {
    if (dailySessions == 1) {
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        12,
        0,
      );
    }

    if (dailySessions == 2) {
      if (session == 'session_1') {
        return DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          9,
          30,
        );
      }
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        13,
        30,
      );
    }

    if (session == 'session_1') {
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        9,
        30,
      );
    }

    if (session == 'session_2') {
      return DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        13,
        30,
      );
    }

    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      16,
      0,
    );
  }

  bool _isTooEarlyForSession(String session) {
    final now = DateTime.now();
    final start = _sessionWindowStart(session);
    return now.isBefore(start);
  }

  bool _isLateForSession(String session) {
    final now = DateTime.now();
    final end = _sessionWindowEnd(session);
    return now.isAfter(end);
  }

  String _sessionTimeText(String session) {
    final start = _sessionWindowStart(session);
    final end = _sessionWindowEnd(session);

    String fmt(DateTime d) {
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    return '${fmt(start)} dan ${fmt(end)} gacha';
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('GPS yoqilmagan. Lokatsiyani yoqing.');
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception('Lokatsiya ruxsati berilmadi.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Lokatsiya ruxsati doimiy rad etilgan. Sozlamadan yoqing.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  // GET API
  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final token = await AuthService.getToken();

      if (token == null || token.isEmpty) {
        return _setError('Sessiya tugagan. Qayta kiring.');
      }

      final res = await http
          .get(
        Uri.parse('https://shaxa.mycoder.uz/api/student/attendance'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = body['data'] as Map<String, dynamic>?;

        if (data == null) {
          return _setError('Javobda data topilmadi.');
        }

        final student = data['student'] as Map<String, dynamic>?;
        final attendances = (data['attendances'] as List<dynamic>? ?? []);

        int apiDailySessions = 3;
        if (student != null) {
          apiDailySessions = int.tryParse(
            student['daily-sesions']?.toString() ??
                student['daily_sessions']?.toString() ??
                '3',
          ) ??
              3;
        }

        if (apiDailySessions < 1) apiDailySessions = 1;
        if (apiDailySessions > 3) apiDailySessions = 3;

        final records = attendances
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList();

        final Map<String, List<AttendanceRecord>> grouped = {};
        for (final r in records) {
          final key = '${r.date.year.toString().padLeft(4, '0')}-'
              '${r.date.month.toString().padLeft(2, '0')}-'
              '${r.date.day.toString().padLeft(2, '0')}';
          grouped.putIfAbsent(key, () => []).add(r);
        }

        final history = grouped.entries.map((e) {
          final date = DateTime.parse(e.key);
          return DayAttendance(date, e.value, apiDailySessions);
        }).toList();

        history.sort((a, b) => b.date.compareTo(a.date));

        setState(() {
          dailySessions = apiDailySessions;
          _history = history;
          _isLoading = false;
        });

        _syncCheckedSessionsFromHistory();
      } else if (res.statusCode == 401) {
        _setError('Sessiya tugagan. Qayta kiring.');
      } else {
        _setError('Server xatosi (${res.statusCode}).');
      }
    } on SocketException {
      if (mounted) _setError('Internet aloqasi mavjud emas.');
    } on TimeoutException {
      if (mounted) _setError('Server javob bermadi.');
    } on FormatException {
      if (mounted) _setError('Serverdan noto‘g‘ri JSON keldi.');
    } catch (e) {
      if (mounted) _setError('Xato: $e');
    }
  }

  void _setError(String msg) => setState(() {
    _error = msg;
    _isLoading = false;
  });

  // POST API
  Future<void> _save() async {
    if (_selectedCount == 0) {
      _snack('Kamida bitta seansni belgilang!', Colors.red);
      return;
    }

    if (_selectedCount > dailySessions) {
      _snack('Faqat $dailySessions ta seans saqlash mumkin.', Colors.red);
      return;
    }

    final userId = await AuthService.getUserId();
    final token = await AuthService.getToken();

    if (userId == null || token == null || token.isEmpty) {
      _snack('Sessiya tugagan. Qayta kiring.', Colors.red);
      return;
    }

    final selectedSessions = <String>[];
    if (is9amChecked) selectedSessions.add('session_1');
    if (dailySessions >= 2 && is1pmChecked) selectedSessions.add('session_2');
    if (dailySessions >= 3 && is4pmChecked) selectedSessions.add('session_3');

    final existingSessions = _existingSessionsForSelectedDate();
    final sessionsToSend = selectedSessions
        .where((session) => !existingSessions.contains(session))
        .toList();

    if (sessionsToSend.isEmpty) {
      _snack(
        'Bu sana uchun tanlangan seanslar allaqachon saqlangan.',
        Colors.orange,
      );
      return;
    }

    for (final session in sessionsToSend) {
      if (_isTooEarlyForSession(session)) {
        _snack(
          '$session uchun vaqt hali kelmagan. Ruxsat: ${_sessionTimeText(session)}',
          Colors.orange,
        );
        return;
      }
    }

    try {
      setState(() => _isLoading = true);

      final position = await _getCurrentPosition();

      for (final session in sessionsToSend) {
        final late = _isLateForSession(session);

        final body = {
          'student_id': userId,
          'date': _selectedDateKey(),
          'session': session,
          'status': 'present',
          'check_in_time': _currentTimeHHmm(),
          'check_out_time': null,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'notes': late ? 'Kechikib keldi' : 'Check-in via mobile',
        };

        final res = await http
            .post(
          Uri.parse('https://shaxa.mycoder.uz/api/student/attendance'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
            .timeout(const Duration(seconds: 15));

        if (res.statusCode != 200 && res.statusCode != 201) {
          throw Exception('Server xatosi: ${res.statusCode} ${res.body}');
        }
      }

      if (!mounted) return;

      final skippedCount = selectedSessions.length - sessionsToSend.length;

      if (skippedCount > 0) {
        _snack(
          '${sessionsToSend.length} ta yangi seans saqlandi, $skippedCount tasi oldin saqlangan.',
          Colors.green,
        );
      } else {
        _snack('Davomat muvaffaqiyatli saqlandi! ✅', Colors.green);
      }

      await _loadHistory();

      final existingAfterReload = _existingSessionsForSelectedDate();

      setState(() {
        is9amChecked = existingAfterReload.contains('session_1');
        is1pmChecked = existingAfterReload.contains('session_2');
        is4pmChecked = existingAfterReload.contains('session_3');
        _isLoading = false;
      });
    } on SocketException {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Internet aloqasi mavjud emas.', Colors.red);
      }
    } on TimeoutException {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Server javob bermadi.', Colors.red);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _snack('Xato: $e', Colors.red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final r = _R(box.maxWidth);
      return Scaffold(
        backgroundColor: Colors.grey[100],
        floatingActionButton: _fab(r),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadHistory,
            color: Colors.teal,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.fromLTRB(r.pad, 12, r.pad, 88),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dateCard(r),
                  SizedBox(height: r.gap),
                  _attendanceSection(r),
                  SizedBox(height: r.gap),
                  _historySection(r),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _fab(_R r) => FloatingActionButton.extended(
    onPressed: _isLoading ? null : _save,
    backgroundColor: Colors.teal,
    icon: Icon(Icons.save, size: r.iconSm),
    label: Text('Saqlash', style: TextStyle(fontSize: r.fs14)),
  );

  Widget _dateCard(_R r) => Container(
    padding: EdgeInsets.symmetric(horizontal: r.pad, vertical: 14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.teal.shade400, Colors.teal.shade600],
      ),
      borderRadius: BorderRadius.circular(r.radius),
      boxShadow: [
        BoxShadow(
          color: Colors.teal.withOpacity(0.3),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(Icons.calendar_month, color: Colors.white, size: r.iconMd),
          onPressed: _pickDate,
        ),
        SizedBox(width: r.isXS ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bugungi sana',
                style: TextStyle(color: Colors.white70, fontSize: r.fs12),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _fmtDate(selectedDate),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: r.fs20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          _weekday(selectedDate),
          style: TextStyle(color: Colors.white, fontSize: r.fs14),
        ),
      ],
    ),
  );

  Widget _attendanceSection(_R r) {
    final total = _selectedCount;
    final pct = dailySessions == 0 ? 0.0 : (total / dailySessions) * 100;

    return Column(
      children: [
        _progressCard(r, pct, total),
        SizedBox(height: r.gap * 0.65),
        _checkboxCard(r),
      ],
    );
  }

  Widget _progressCard(_R r, double pct, int total) {
    final color = pct >= 100 ? Colors.green : Colors.teal;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        vertical: r.isXS ? 14 : 18,
        horizontal: r.pad,
      ),
      decoration: _card(r),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: r.circle,
                height: r.circle,
                child: CircularProgressIndicator(
                  value: (pct / 100).clamp(0.0, 1.0),
                  strokeWidth: r.stroke,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${pct.toInt()}%',
                      style: TextStyle(
                        fontSize: r.fs32,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  Text(
                    '$total / $dailySessions seans',
                    style: TextStyle(fontSize: r.fs12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(width: r.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Bugungi davomat',
                  style: TextStyle(
                    fontSize: r.fs16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: r.isXS ? 6 : 10),
                Text(
                  pct >= 100
                      ? "Davomat to'liq ✅"
                      : (pct == 0 ? 'Boshlanmagan' : 'Qisman bajarilgan'),
                  style: TextStyle(
                    fontSize: r.fs14,
                    fontWeight: FontWeight.w500,
                    color: pct >= 100
                        ? Colors.green
                        : (pct == 0 ? Colors.grey : Colors.teal),
                  ),
                ),
                SizedBox(height: r.isXS ? 8 : 12),
                Wrap(
                  spacing: r.isXS ? 4 : 6,
                  runSpacing: 4,
                  children: [
                    _badge(r, 'Ertala', is9amChecked),
                    if (dailySessions >= 2) _badge(r, 'Kunduz', is1pmChecked),
                    if (dailySessions >= 3) _badge(r, 'Kech', is4pmChecked),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(_R r, String label, bool active) => Container(
    padding: EdgeInsets.symmetric(horizontal: r.isXS ? 5 : 7, vertical: 3),
    decoration: BoxDecoration(
      color: active ? Colors.teal : Colors.grey[200],
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: active ? Colors.white : Colors.grey[500],
        fontSize: r.fs10,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _checkboxCard(_R r) => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(r.pad, 14, r.pad, 8),
    decoration: _card(r),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.teal, size: r.iconSm),
            const SizedBox(width: 6),
            Text(
              'Davomat belgilash ($dailySessions ta seans)',
              style: TextStyle(fontSize: r.fs16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        SizedBox(height: r.isXS ? 10 : 14),
        _slot(
          r,
          time: dailySessions == 1 ? '11:30' : '9:00',
          label: 'Ertalabki seans',
          icon: Icons.wb_sunny,
          color: Colors.orange,
          checked: is9amChecked,
          onChange: (v) => _handleCheck(sessionNumber: 1, value: v),
        ),
        if (dailySessions >= 2) ...[
          const Divider(height: 4, thickness: 0.5),
          _slot(
            r,
            time: '13:00',
            label: 'Kunduzi seans',
            icon: Icons.wb_sunny_outlined,
            color: Colors.amber,
            checked: is1pmChecked,
            onChange: (v) => _handleCheck(sessionNumber: 2, value: v),
          ),
        ],
        if (dailySessions >= 3) ...[
          const Divider(height: 4, thickness: 0.5),
          _slot(
            r,
            time: '15:30',
            label: 'Kechki seans',
            icon: Icons.nights_stay,
            color: Colors.indigo,
            checked: is4pmChecked,
            onChange: (v) => _handleCheck(sessionNumber: 3, value: v),
          ),
        ],
      ],
    ),
  );

  Widget _slot(
      _R r, {
        required String time,
        required String label,
        required IconData icon,
        required Color color,
        required bool checked,
        required ValueChanged<bool?> onChange,
      }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: r.isXS ? 5 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(r.slotPad),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: r.iconSm),
          ),
          SizedBox(width: r.isXS ? 8 : 12),
          Text(
            time,
            maxLines: 1,
            style: TextStyle(
              fontSize: r.fs16,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
          SizedBox(width: r.isXS ? 6 : 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600], fontSize: r.fs12),
            ),
          ),
          SizedBox(
            width: 40,
            child: Checkbox(
              value: checked,
              onChanged: _isLoading ? null : onChange,
              activeColor: Colors.teal,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historySection(_R r) {
    if (_isLoading && _history.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: Colors.teal),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
              const SizedBox(height: 12),
              Text(_error, style: TextStyle(color: Colors.grey[700])),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }

    if (_history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'Davomat tarixi yo\'q',
            style: TextStyle(color: Colors.grey[600], fontSize: r.fs14),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Davomat tarixi',
          style: TextStyle(fontSize: r.fs18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._history.map((day) => _historyCard(r, day)),
      ],
    );
  }

  Widget _historyCard(_R r, DayAttendance day) {
    final Color statusColor;
    final IconData statusIcon;
    switch (day.statusLabel) {
      case "To'liq":
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'Qisman':
        statusColor = Colors.orange;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(horizontal: r.pad, vertical: 12),
      decoration: _card(r),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: r.iconMd),
          SizedBox(width: r.isXS ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day.dateStr,
                  style: TextStyle(
                    fontSize: r.fs14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _miniBox(r, day.session1),
                    if (day.dailySessions >= 2) ...[
                      const SizedBox(width: 4),
                      _miniBox(r, day.session2),
                    ],
                    if (day.dailySessions >= 3) ...[
                      const SizedBox(width: 4),
                      _miniBox(r, day.session3),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: r.isXS ? 8 : 10,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              day.statusLabel,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: r.fs12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBox(_R r, bool on) {
    final size = r.isXS ? 15.0 : 18.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on ? Colors.teal : Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: on ? Icon(Icons.check, color: Colors.white, size: size - 5) : null,
    );
  }

  BoxDecoration _card(_R r) => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(r.radius),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ],
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2026),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.teal),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
      });
      _syncCheckedSessionsFromHistory();
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  String _weekday(DateTime d) =>
      const ['Dush', 'Sesh', 'Chor', 'Pay', 'Juma', 'Shan', 'Yak'][d.weekday - 1];
}
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Custom exceptions
// ─────────────────────────────────────────────────────────────────────────────
class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class NetworkException implements Exception {
  final String message;

  const NetworkException([this.message = 'Internet aloqasi mavjud emas.']);

  @override
  String toString() => 'NetworkException: $message';
}

class ParseException implements Exception {
  final String message;

  const ParseException([this.message = 'Javobni o‘qishda xato.']);

  @override
  String toString() => 'ParseException: $message';
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthUser model
// ─────────────────────────────────────────────────────────────────────────────
class AuthUser {
  final int id;
  final String token;
  final String? username;
  final String? fullName;

  const AuthUser({
    required this.id,
    required this.token,
    this.username,
    this.fullName,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Student model
// ─────────────────────────────────────────────────────────────────────────────
class Student {
  final int id;
  final String name;
  final String? email;
  final String? phone;

  const Student({
    required this.id,
    required this.name,
    this.email,
    this.phone,
  });

  factory Student.fromJson(Map<String, dynamic> j) {
    final rawId = j['id'];
    final int id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;

    return Student(
      id: id,
      name: (j['name'] ?? j['full_name'] ?? j['username'] ?? '').toString(),
      email: j['email']?.toString(),
      phone: j['phone']?.toString(),
    );
  }

  @override
  String toString() => 'Student(id: $id, name: $name)';
}

// ─────────────────────────────────────────────────────────────────────────────
// ApiService
// ─────────────────────────────────────────────────────────────────────────────
class ApiService {
  static const String _baseUrl = 'https://shaxa.mycoder.uz/api/student';
  static const Duration _timeout = Duration(seconds: 15);

  static const String keyToken = 'token';
  static const String keyUserId = 'user_id';
  static const String keyUsername = 'username';
  static const String keyFullName = 'full_name';

  static const Map<String, String> _baseHeaders = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  Map<String, String> _authHeaders(String token) => {
    ..._baseHeaders,
    'Authorization': 'Bearer $token',
  };

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyToken);
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyUserId);
  }

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyUsername);
  }

  Future<String?> getFullName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyFullName);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyToken);
    await prefs.remove(keyUserId);
    await prefs.remove(keyUsername);
    await prefs.remove(keyFullName);
  }

  String _extractMessage(
      Map<String, dynamic> map, {
        String fallback = 'Xatolik yuz berdi.',
      }) {
    final dynamic message = map['message'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString();
    }
    return fallback;
  }

  Map<String, dynamic> _decodeToMap(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw const ParseException('Server javobi obyekt formatida emas.');
    } on FormatException {
      throw const ParseException('Serverdan noto‘g‘ri JSON keldi.');
    }
  }

  // ── Login with real API ───────────────────────────────────────
  Future<AuthUser> login(String username, String password) async {
    late http.Response response;

    try {
      response = await http
          .post(
        Uri.parse('$_baseUrl/login'),
        headers: _baseHeaders,
        body: jsonEncode({
          'username': username.trim(),
          'password': password,
        }),
      )
          .timeout(_timeout);
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException('Server javob bermadi.');
    }

    final Map<String, dynamic> map = _decodeToMap(response.body);

    if (response.statusCode == 401) {
      throw ApiException(
        401,
        _extractMessage(map, fallback: 'Login yoki parol noto‘g‘ri.'),
      );
    }

    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        _extractMessage(map, fallback: 'Login qilishda xato.'),
      );
    }

    final bool success = map['success'] == true;
    if (!success) {
      throw ApiException(
        400,
        _extractMessage(map, fallback: 'Login muvaffaqiyatsiz.'),
      );
    }

    final dynamic dataRaw = map['data'];
    if (dataRaw is! Map<String, dynamic>) {
      throw const ParseException('Javobda data topilmadi.');
    }

    final String? token = dataRaw['token']?.toString();

    final dynamic studentRaw = dataRaw['student'];
    if (studentRaw is! Map<String, dynamic>) {
      throw const ParseException('Javobda student topilmadi.');
    }

    final int? userId = studentRaw['id'] is int
        ? studentRaw['id'] as int
        : int.tryParse(studentRaw['id']?.toString() ?? '');

    final String? uname = studentRaw['username']?.toString();
    final String? fullName = studentRaw['full_name']?.toString();

    if (token == null || token.isEmpty) {
      throw const ParseException('Javobda token topilmadi.');
    }

    if (userId == null) {
      throw const ParseException('Javobda student id topilmadi.');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyToken, token);
    await prefs.setInt(keyUserId, userId);

    if (uname != null && uname.isNotEmpty) {
      await prefs.setString(keyUsername, uname);
    }

    if (fullName != null && fullName.isNotEmpty) {
      await prefs.setString(keyFullName, fullName);
    }

    return AuthUser(
      id: userId,
      token: token,
      username: uname,
      fullName: fullName,
    );
  }

  // ── Get students ───────────────────────────────────────────────
  Future<List<Student>> getStudents() async {
    final token = await getToken();

    if (token == null || token.isEmpty) {
      throw const ApiException(401, 'Sessiya tugagan. Iltimos, qayta kiring.');
    }

    late http.Response response;
    try {
      response = await http
          .get(
        Uri.parse('$_baseUrl/students'),
        headers: _authHeaders(token),
      )
          .timeout(_timeout);
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException('Server javob bermadi.');
    }

    if (response.statusCode == 401) {
      await clearSession();
      throw const ApiException(401, 'Sessiya tugagan. Iltimos, qayta kiring.');
    }

    if (response.statusCode != 200) {
      try {
        final map = _decodeToMap(response.body);
        throw ApiException(
          response.statusCode,
          _extractMessage(map, fallback: 'Studentlarni olishda xato.'),
        );
      } on ParseException {
        throw ApiException(response.statusCode, 'Studentlarni olishda xato.');
      }
    }

    try {
      final raw = jsonDecode(response.body);

      if (raw is List) {
        return raw
            .map((e) => Student.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      if (raw is Map<String, dynamic>) {
        if (raw['data'] is List) {
          final list = raw['data'] as List<dynamic>;
          return list
              .map((e) => Student.fromJson(e as Map<String, dynamic>))
              .toList();
        }

        if (raw['students'] is List) {
          final list = raw['students'] as List<dynamic>;
          return list
              .map((e) => Student.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }

      throw const ParseException('Studentlar ro‘yxati topilmadi.');
    } on ParseException {
      rethrow;
    } on FormatException {
      throw const ParseException('Studentlar javobi noto‘g‘ri formatda.');
    } catch (_) {
      throw const ParseException('Studentlar ro‘yxatini o‘qishda xato.');
    }
  }

  // ── Generic authenticated GET ───────────────────────────────
  Future<dynamic> authenticatedGet(String endpoint) async {
    final token = await getToken();

    if (token == null || token.isEmpty) {
      throw const ApiException(401, 'Token topilmadi.');
    }

    final String cleanEndpoint =
    endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;

    late http.Response response;
    try {
      response = await http
          .get(
        Uri.parse('$_baseUrl/$cleanEndpoint'),
        headers: _authHeaders(token),
      )
          .timeout(_timeout);
    } on SocketException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException('Server javob bermadi.');
    }

    if (response.statusCode == 401) {
      await clearSession();
      throw const ApiException(401, 'Sessiya tugagan.');
    }

    if (response.statusCode != 200) {
      try {
        final map = _decodeToMap(response.body);
        throw ApiException(
          response.statusCode,
          _extractMessage(map, fallback: 'So‘rov xatosi.'),
        );
      } on ParseException {
        throw ApiException(response.statusCode, 'So‘rov xatosi.');
      }
    }

    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const ParseException('Javobni o‘qishda xato.');
    }
  }
}
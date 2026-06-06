import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/auth/auth_tokens.dart';

class AuthRepository {
  const AuthRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<AuthTokens> login(
      {required String email, required String password}) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
    };

    _debugLogRequest('POST', '/api/v1/auth/login', body);

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );

      final data = res.data;
      if (data == null) throw Exception('Invalid response');
      final tokens = AuthTokens.fromJson(data);
      if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
        throw Exception('Invalid token response');
      }
      return tokens;
    } on DioException catch (e) {
      throw Exception(_messageFromDio(e));
    }
  }

  Future<void> requestLoginOtp({
    required String email,
    required String password,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
    };

    _debugLogRequest('POST', '/api/v1/auth/login', body);

    try {
      await _dio.post<dynamic>(
        '/api/v1/auth/login',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw AuthRequestException(
        _messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> requestRegisterOtp({
    required String email,
    required String password,
    required String displayName,
    required String dateOfBirth,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedDisplayName = displayName.trim();

    final body = <String, dynamic>{
      'email': trimmedEmail,
      'password': password,
      'display_name': trimmedDisplayName,
      'date_of_birth': dateOfBirth,
    };

    _debugLogRequest('POST', '/api/v1/auth/register', body);

    try {
      await _dio.post<dynamic>(
        '/api/v1/auth/register',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint("POST /api/v1/auth/register failed");
        debugPrint("STATUS: ${e.response?.statusCode}");
        debugPrint("RAW RESPONSE:");
        debugPrint(e.response?.data.toString());
      }
      final msg = _messageFromDio(e);

      throw AuthRequestException(
        msg,
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> forgotPassword({required String email}) async {
    final body = <String, dynamic>{
      'email': email,
    };

    _debugLogRequest('POST', '/api/v1/auth/forgot-password', body);

    try {
      await _dio.post<dynamic>(
        '/api/v1/auth/forgot-password',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw AuthRequestException(
        _messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'otp': otp,
      'new_password': newPassword,
    };

    _debugLogRequest('POST', '/api/v1/auth/reset-password', body);

    try {
      await _dio.post<dynamic>(
        '/api/v1/auth/reset-password',
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      throw AuthRequestException(
        _messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> resendLoginOtp({required String email}) async {
    try {
      await _dio.post<dynamic>(
        '/api/v1/auth/login/resend',
        data: <String, dynamic>{
          'email': email,
        },
      );
    } on DioException catch (e) {
      throw Exception(_messageFromDio(e));
    }
  }

  Future<void> resendRegisterOtp({required String email}) async {
    try {
      await _dio.post<dynamic>(
        '/api/v1/auth/register/resend',
        data: <String, dynamic>{
          'email': email,
        },
      );
    } on DioException catch (e) {
      throw Exception(_messageFromDio(e));
    }
  }

  Future<AuthTokens> verifyLoginOtp({
    required String email,
    required String otp,
  }) async {
    const path = '/api/v1/auth/login/verify';
    final body = <String, dynamic>{
      'email': email,
      'otp': otp,
    };

    _debugLogRequest('POST', path, body);
    if (kDebugMode) {
      debugPrint('OTP verify request body $path: ${jsonEncode(body)}');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );

      final data = response.data;
      if (data == null) throw Exception('Invalid token response');

      final accessToken = data['access_token'];
      final refreshToken = data['refresh_token'];

      if (kDebugMode) {
        final redacted = Map<String, dynamic>.from(data);
        if (redacted.containsKey('access_token')) {
          redacted['access_token'] = '***';
        }
        if (redacted.containsKey('refresh_token')) {
          redacted['refresh_token'] = '***';
        }
        debugPrint('OTP verify response $path: ${jsonEncode(redacted)}');

        final masked = (accessToken is String && accessToken.length > 12)
            ? '${accessToken.substring(0, 12)}...'
            : (accessToken is String ? accessToken : '');
        debugPrint('TOKEN: $masked');
        debugPrint(
          'OTP tokens present (login): access=${accessToken is String && accessToken.isNotEmpty} refresh=${refreshToken is String && refreshToken.isNotEmpty}',
        );
      }

      if (accessToken is! String ||
          accessToken.isEmpty ||
          refreshToken is! String ||
          refreshToken.isEmpty) {
        throw Exception('Invalid token response');
      }

      return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
    } on DioException catch (e) {
      throw AuthRequestException(
        _messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<AuthTokens> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    const path = '/api/v1/auth/register/verify';
    final body = <String, dynamic>{
      'email': email,
      'otp': otp,
    };

    _debugLogRequest('POST', path, body);
    if (kDebugMode) {
      debugPrint('OTP verify request body $path: ${jsonEncode(body)}');
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        path,
        data: body,
        options: Options(contentType: Headers.jsonContentType),
      );

      final data = response.data;
      if (data == null) throw Exception('Invalid token response');

      final accessToken = data['access_token'];
      final refreshToken = data['refresh_token'];

      if (kDebugMode) {
        final redacted = Map<String, dynamic>.from(data);
        if (redacted.containsKey('access_token')) {
          redacted['access_token'] = '***';
        }
        if (redacted.containsKey('refresh_token')) {
          redacted['refresh_token'] = '***';
        }
        debugPrint('OTP verify response $path: ${jsonEncode(redacted)}');
        debugPrint(
          'OTP tokens present (register): access=${accessToken is String && accessToken.isNotEmpty} refresh=${refreshToken is String && refreshToken.isNotEmpty}',
        );
      }

      if (accessToken is! String ||
          accessToken.isEmpty ||
          refreshToken is! String ||
          refreshToken.isEmpty) {
        throw Exception('Invalid token response');
      }

      return AuthTokens(accessToken: accessToken, refreshToken: refreshToken);
    } on DioException catch (e) {
      throw AuthRequestException(
        _messageFromDio(e),
        statusCode: e.response?.statusCode,
      );
    }
  }
}

class AuthRequestException implements Exception {
  const AuthRequestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

void _debugLogRequest(String method, String path, Map<String, dynamic> body) {
  if (!kDebugMode) return;

  final redacted = Map<String, dynamic>.from(body);
  const secretKeys = <String>{
    'password',
    'new_password',
    'otp',
    'access_token',
    'refresh_token',
    'refreshToken',
    'accessToken',
  };

  for (final k in secretKeys) {
    if (redacted.containsKey(k)) redacted[k] = '***';
  }

  debugPrint('$method $path body=${jsonEncode(redacted)}');
}

String _messageFromDio(DioException e) {
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    final detail = data['detail'];
    if (detail is String && detail.trim().isNotEmpty) return detail;
    final msg = data['message'];
    if (msg is String && msg.trim().isNotEmpty) return msg;
  }

  if (data is String && data.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail;
      }
    } catch (_) {
      // ignore
    }
    return data;
  }

  return e.message ?? 'Request failed';
}

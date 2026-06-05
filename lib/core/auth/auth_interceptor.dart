import 'dart:async';

import 'package:dio/dio.dart';

import 'auth_tokens.dart';
import 'token_storage.dart';

class AuthInterceptor extends QueuedInterceptorsWrapper {
  AuthInterceptor({
    required Dio dio,
    required TokenStorage tokenStorage,
    required String baseUrl,
  })  : _dio = dio,
        _tokenStorage = tokenStorage,
        _refreshDio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 15),
          ),
        );

  static const _kRetryKey = '__auth_retry';

  final Dio _dio;
  final TokenStorage _tokenStorage;
  final Dio _refreshDio;

  Future<AuthTokens?>? _refreshing;

  bool _isAuthEndpoint(RequestOptions options) {
    final path = options.path;
    return path.startsWith('/api/v1/auth/');
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_isAuthEndpoint(options)) {
      handler.next(options);
      return;
    }

    final accessToken = await _tokenStorage.readAccessToken();
    if (accessToken != null && accessToken.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final options = err.requestOptions;

    if (response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    if (_isAuthEndpoint(options)) {
      handler.next(err);
      return;
    }

    if (options.extra[_kRetryKey] == true) {
      handler.next(err);
      return;
    }

    final tokens = await _refreshTokens();
    if (tokens == null) {
      await _tokenStorage.clearTokens();
      handler.next(err);
      return;
    }

    try {
      options.extra[_kRetryKey] = true;
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      final retryResponse = await _dio.fetch<dynamic>(options);
      handler.resolve(retryResponse);
    } catch (e) {
      handler.next(
        e is DioException
            ? e
            : DioException(
                requestOptions: options,
                error: e,
                type: DioExceptionType.unknown,
              ),
      );
    }
  }

  Future<AuthTokens?> _refreshTokens() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    final completer = Completer<AuthTokens?>();
    _refreshing = completer.future;

    () async {
      try {
        final refreshToken = await _tokenStorage.readRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) {
          completer.complete(null);
          return;
        }

        final res = await _refreshDio.post<Map<String, dynamic>>(
          '/api/v1/auth/refresh',
          data: <String, dynamic>{'refresh_token': refreshToken},
        );

        final data = res.data;
        if (data == null) {
          completer.complete(null);
          return;
        }

        final tokens = AuthTokens.fromJson(data);
        if (tokens.accessToken.isEmpty || tokens.refreshToken.isEmpty) {
          completer.complete(null);
          return;
        }

        await _tokenStorage.writeTokens(tokens);
        completer.complete(tokens);
      } catch (_) {
        completer.complete(null);
      } finally {
        _refreshing = null;
      }
    }();

    return completer.future;
  }
}

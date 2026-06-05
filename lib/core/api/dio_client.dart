import 'package:dio/dio.dart';

import '../auth/auth_interceptor.dart';
import '../auth/token_storage.dart';
import 'api_config.dart';

class DioClient {
  DioClient._(this._dio);

  final Dio _dio;

  static DioClient create(
      {String? baseUrl, required TokenStorage tokenStorage}) {
    final resolvedBaseUrl = baseUrl ?? ApiConfig.baseUrl;

    final dio = Dio(
      BaseOptions(
        baseUrl: resolvedBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
      ),
    );

    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        tokenStorage: tokenStorage,
        baseUrl: resolvedBaseUrl,
      ),
    );

    return DioClient._(dio);
  }

  Dio get dio => _dio;
}

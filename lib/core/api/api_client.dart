import 'package:dio/dio.dart';

import 'dio_client.dart';

class ApiClient {
  ApiClient({required DioClient dioClient}) : _dio = dioClient.dio;

  final Dio _dio;

  Dio get dio => _dio;
}

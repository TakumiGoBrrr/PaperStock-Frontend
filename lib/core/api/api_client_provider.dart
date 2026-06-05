import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import 'api_client.dart';
import 'dio_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return ApiClient(dioClient: DioClient.create(tokenStorage: tokenStorage));
});

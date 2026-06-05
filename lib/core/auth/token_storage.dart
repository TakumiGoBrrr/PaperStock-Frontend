import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage_service.dart';
import 'auth_tokens.dart';

class TokenStorage {
  TokenStorage({required StorageService storage}) : _storage = storage;

  static const _kAccessTokenKey = 'access_token';
  static const _kRefreshTokenKey = 'refresh_token';

  final StorageService _storage;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  String? _cachedRefreshToken;

  Stream<void> get changes => _changes.stream;

  bool get hasRefreshTokenCached => (_cachedRefreshToken ?? '').isNotEmpty;

  Future<String?> readAccessToken() {
    return _storage.read(key: _kAccessTokenKey);
  }

  Future<String?> readRefreshToken() async {
    final v = await _storage.read(key: _kRefreshTokenKey);
    _cachedRefreshToken = v;
    return v;
  }

  Future<void> writeTokens(AuthTokens tokens) async {
    await _storage.write(key: _kAccessTokenKey, value: tokens.accessToken);
    await _storage.write(key: _kRefreshTokenKey, value: tokens.refreshToken);
    _cachedRefreshToken = tokens.refreshToken;
    _changes.add(null);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _kAccessTokenKey);
    await _storage.delete(key: _kRefreshTokenKey);
    _cachedRefreshToken = null;
    _changes.add(null);
  }

  void dispose() {
    _changes.close();
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  final service = ref.watch(storageServiceProvider);
  final storage = TokenStorage(storage: service);
  ref.onDispose(storage.dispose);
  return storage;
});

final tokenStorageChangesProvider = StreamProvider<void>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return storage.changes;
});

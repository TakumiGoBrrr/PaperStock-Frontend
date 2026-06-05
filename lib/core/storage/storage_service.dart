import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class StorageService {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class SecureStorageService implements StorageService {
  SecureStorageService(this._storage);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('SecureStorageService: Error reading key $key: $e');
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  @override
  Future<void> write({required String key, required String value}) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('SecureStorageService: Error writing key $key: $e');
      try {
        await _storage.deleteAll();
        await _storage.write(key: key, value: value);
      } catch (_) {}
    }
  }

  @override
  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('SecureStorageService: Error deleting key $key: $e');
    }
  }
}

class SharedPreferencesStorageService implements StorageService {
  SharedPreferencesStorageService({SharedPreferences? preferences})
      : _prefs = preferences == null
            ? SharedPreferences.getInstance()
            : Future<SharedPreferences>.value(preferences);

  final Future<SharedPreferences> _prefs;

  @override
  Future<String?> read({required String key}) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete({required String key}) async {
    final prefs = await _prefs;
    await prefs.remove(key);
  }
}

final storageServiceProvider = Provider<StorageService>((ref) {
  if (kIsWeb) {
    return SharedPreferencesStorageService();
  }
  return SecureStorageService(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: false,
        resetOnError: true,
      ),
    ),
  );
});

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client_provider.dart';
import '../../../core/auth/auth_tokens.dart';
import '../../../core/auth/token_storage.dart';
import '../data/auth_repository.dart';

class AuthState {
  const AuthState._({required this.isAuthenticated});

  final bool isAuthenticated;

  const AuthState.authenticated() : this._(isAuthenticated: true);

  const AuthState.unauthenticated() : this._(isAuthenticated: false);
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = ref.watch(apiClientProvider).dio;
  return AuthRepository(dio: dio);
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final authProvider = authControllerProvider;

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    ref.watch(tokenStorageChangesProvider);

    final tokenStorage = ref.watch(tokenStorageProvider);
    final refreshToken = await tokenStorage.readRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      return const AuthState.authenticated();
    }
    return const AuthState.unauthenticated();
  }

  void setAuthenticated(bool value) {
    state = AsyncData(
      value
          ? const AuthState.authenticated()
          : const AuthState.unauthenticated(),
    );
  }

  Future<void> login({required String email, required String password}) async {
    final previous = state.valueOrNull ?? const AuthState.unauthenticated();
    state = const AsyncLoading();

    final repo = ref.read(authRepositoryProvider);
    final tokenStorage = ref.read(tokenStorageProvider);

    try {
      final AuthTokens tokens =
          await repo.login(email: email, password: password);
      await tokenStorage.writeTokens(tokens);
      state = const AsyncData(AuthState.authenticated());
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> requestLoginOtp({
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.requestLoginOtp(email: email, password: password);
  }

  Future<void> requestRegisterOtp({
    required String email,
    required String password,
    required String displayName,
    required String dateOfBirth,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.requestRegisterOtp(
      email: email,
      password: password,
      displayName: displayName,
      dateOfBirth: dateOfBirth,
    );
  }

  Future<void> resendLoginOtp({required String email}) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.resendLoginOtp(email: email);
  }

  Future<void> resendRegisterOtp({required String email}) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.resendRegisterOtp(email: email);
  }

  Future<void> verifyLoginOtp({
    required String email,
    required String otp,
  }) async {
    final previous = state.valueOrNull ?? const AuthState.unauthenticated();
    state = const AsyncLoading();

    final repo = ref.read(authRepositoryProvider);
    final tokenStorage = ref.read(tokenStorageProvider);

    try {
      final AuthTokens tokens =
          await repo.verifyLoginOtp(email: email, otp: otp);

      if (kDebugMode) {
        debugPrint(
          'OTP verify tokens (login): access=${tokens.accessToken.isNotEmpty} refresh=${tokens.refreshToken.isNotEmpty}',
        );
      }

      await tokenStorage.writeTokens(tokens);

      if (kDebugMode) {
        final storedAccess = await tokenStorage.readAccessToken();
        final storedRefresh = await tokenStorage.readRefreshToken();
        debugPrint(
          'OTP stored tokens (login): access=${(storedAccess ?? '').isNotEmpty} refresh=${(storedRefresh ?? '').isNotEmpty}',
        );
      }

      state = const AsyncData(AuthState.authenticated());
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    final previous = state.valueOrNull ?? const AuthState.unauthenticated();
    state = const AsyncLoading();

    final repo = ref.read(authRepositoryProvider);
    final tokenStorage = ref.read(tokenStorageProvider);

    try {
      final AuthTokens tokens =
          await repo.verifyRegisterOtp(email: email, otp: otp);

      if (kDebugMode) {
        debugPrint(
          'OTP verify tokens (register): access=${tokens.accessToken.isNotEmpty} refresh=${tokens.refreshToken.isNotEmpty}',
        );
      }

      await tokenStorage.writeTokens(tokens);

      if (kDebugMode) {
        final storedAccess = await tokenStorage.readAccessToken();
        final storedRefresh = await tokenStorage.readRefreshToken();
        debugPrint(
          'OTP stored tokens (register): access=${(storedAccess ?? '').isNotEmpty} refresh=${(storedRefresh ?? '').isNotEmpty}',
        );
      }

      state = const AsyncData(AuthState.authenticated());
    } catch (_) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> forgotPassword({required String email}) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.forgotPassword(email: email);
  }

  Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.resetPassword(email: email, otp: otp, newPassword: newPassword);
  }

  Future<void> logout() async {
    final tokenStorage = ref.read(tokenStorageProvider);
    await tokenStorage.clearTokens();
    state = const AsyncData(AuthState.unauthenticated());
  }
}

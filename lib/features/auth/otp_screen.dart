import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/token_storage.dart';
import '../../core/storage/storage_service.dart';
import '../../core/widgets/app_header.dart';
import '../feed/controller/feed_controller.dart';
import '../notifications/controller/notifications_controller.dart';
import '../profile/controller/profile_controller.dart';
import 'controller/auth_controller.dart';

class OtpArgs {
  const OtpArgs({
    required this.email,
    required this.isRegisterFlow,
  });

  final String email;
  final bool isRegisterFlow;
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.args});

  final OtpArgs args;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const _kResendCooldown = Duration(seconds: 30);

  final _otpController = TextEditingController();

  Timer? _timer;
  int _secondsLeft = _kResendCooldown.inSeconds;
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _kResendCooldown.inSeconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 0) {
        t.cancel();
        setState(() {
          _secondsLeft = 0;
        });
        return;
      }
      setState(() {
        _secondsLeft -= 1;
      });
    });
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0) return;
    setState(() {
      _errorText = null;
      _otpController.clear();
    });

    final args = widget.args;
    try {
      final auth = ref.read(authControllerProvider.notifier);
      if (args.isRegisterFlow) {
        await auth.resendRegisterOtp(email: args.email);
      } else {
        await auth.resendLoginOtp(email: args.email);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent. Check your email.')),
      );
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _verify() async {
    if (_isSubmitting) return;

    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorText = 'Enter the 6-digit code';
      });
      return;
    }

    setState(() {
      _errorText = null;
      _isSubmitting = true;
    });

    try {
      final args = widget.args;
      final repo = ref.read(authRepositoryProvider);

      final tokens = args.isRegisterFlow
          ? await repo.verifyRegisterOtp(email: args.email, otp: code)
          : await repo.verifyLoginOtp(email: args.email, otp: code);

      final tokenStorage = ref.read(tokenStorageProvider);
      await tokenStorage.writeTokens(tokens);

      final storage = ref.read(storageServiceProvider);
      final saved = await storage.read(key: 'access_token');

      if (kDebugMode) {
        final masked = (saved ?? '').length <= 12
            ? (saved ?? '')
            : '${saved!.substring(0, 12)}...';
        print('SAVED TOKEN: $masked');
      }

      if (saved == null || saved.isEmpty) {
        throw Exception('Verification failed');
      }

      ref.read(authProvider.notifier).setAuthenticated(true);

      // Fresh session loads after login.
      ref.invalidate(feedControllerProvider);
      ref.invalidate(profileControllerProvider);
      ref.invalidate(currentUserIdProvider);
      ref.invalidate(notificationsControllerProvider);
      ref.invalidate(unreadNotificationsCountProvider);

      if (!mounted) return;
      if (widget.args.isRegisterFlow) {
        context.go('/interests');
      } else {
        context.go('/feed');
      }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');

      if (!mounted) return;
      setState(() {
        _errorText = msg.isEmpty ? 'Verification failed' : msg;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? 'Verification failed' : msg)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: SafeArea(
          bottom: false,
          child: AppHeader(
            title: Text(
              'PaperStock',
              style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            left: IconButton(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomInset),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'Enter OTP',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'We sent a 6-digit code.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _verify(),
                          decoration: InputDecoration(
                            labelText: 'OTP',
                            counterText: '',
                            errorText: _errorText,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _isSubmitting ? null : _verify,
                          child: _isSubmitting
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Verify'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: (_secondsLeft > 0) ? null : _resend,
                          child: Text(
                            _secondsLeft > 0
                                ? 'Resend in 00:${_twoDigits(_secondsLeft)}'
                                : 'Resend code',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/app_header.dart';
import 'controller/auth_controller.dart';
import 'data/auth_repository.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isContinuingToOtp = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isContinuingToOtp) return;

    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() => _isContinuingToOtp = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      await ref.read(authControllerProvider.notifier).requestLoginOtp(
            email: email,
            password: password,
          );

      final args = OtpArgs(email: email, isRegisterFlow: false);

      if (!mounted) return;
      await context.push('/otp', extra: args);
    } catch (e) {
      if (!mounted) return;

      if (e is AuthRequestException && e.statusCode == 429) {
        _showTimeoutBanner(context, e.message);
        return;
      }

      final isEmailNotFound = e is AuthRequestException && e.statusCode == 404;
      if (isEmailNotFound) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account not found. Redirecting to sign up...'),
            duration: Duration(seconds: 2),
          ),
        );
        context.push('/register?email=${Uri.encodeComponent(email)}&password=${Uri.encodeComponent(password)}');
        return;
      }

      final isDisabled = e is AuthRequestException &&
          e.statusCode == 403 &&
          e.message.toLowerCase().contains('account has been disabled');

      final isUnauthorized = e is AuthRequestException && e.statusCode == 401;

      final text = isDisabled
          ? 'Your account has been disabled. Please contact support.'
          : (isUnauthorized
              ? 'Invalid email or password'
              : 'Couldn\'t log in. Try again.');

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    } finally {
      if (mounted) setState(() => _isContinuingToOtp = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colorScheme.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: SafeArea(
          bottom: false,
          child: AppHeader(
            title: Text(
              'PaperStock',
              style: GoogleFonts.playfairDisplay(fontSize: 20, fontWeight: FontWeight.w700),
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
                  padding: EdgeInsets.fromLTRB(24, 32, 24, 24 + bottomInset),
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight - 56),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Center(
                              child: Image.asset(
                                theme.brightness == Brightness.dark
                                    ? 'assets/logo_dark.png'
                                    : 'assets/logo_light.png',
                                height: 72,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Welcome back',
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to continue to PaperStock',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _emailController,
                              autofillHints: const [AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                              ),
                              validator: (value) {
                                final v = (value ?? '').trim();
                                if (v.isEmpty) return 'Email is required';
                                if (!_isValidEmail(v)) {
                                  return 'Enter a valid email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passwordController,
                              autofillHints: const [AutofillHints.password],
                              obscureText: !_showPassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                      () => _showPassword = !_showPassword),
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  tooltip: _showPassword
                                      ? 'Hide password'
                                      : 'Show password',
                                ),
                              ),
                              validator: (value) {
                                final v = value ?? '';
                                if (v.isEmpty) return 'Password is required';
                                if (v.length < 8) {
                                  return 'Password must be at least 8 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: _isContinuingToOtp ? null : _submit,
                              child: _isContinuingToOtp
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Continue'),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _isContinuingToOtp
                                  ? null
                                  : () => context.push('/forgot-password'),
                              child: const Text('Forgot password?'),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _isContinuingToOtp
                                  ? null
                                  : () => context.push('/register'),
                              child: const Text('Create an account'),
                            ),
                          ],
                        ),
                      ),
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

bool _isValidEmail(String input) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(input);
}

void _showTimeoutBanner(BuildContext context, String message) {
  final scaffoldMessenger = ScaffoldMessenger.of(context);
  scaffoldMessenger.clearMaterialBanners();
  scaffoldMessenger.showMaterialBanner(
    MaterialBanner(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top > 0
            ? MediaQuery.of(context).padding.top + 8.0
            : 16.0,
        bottom: 12.0,
        left: 16.0,
        right: 8.0,
      ),
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      leading: const Icon(Icons.timer_outlined, color: Colors.white),
      backgroundColor: Colors.red[700],
      actions: [
        TextButton(
          onPressed: () => scaffoldMessenger.clearMaterialBanners(),
          child: const Text(
            'DISMISS',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
  Future.delayed(const Duration(seconds: 6), () {
    scaffoldMessenger.clearMaterialBanners();
  });
}


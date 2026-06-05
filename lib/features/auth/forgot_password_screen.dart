import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/app_header.dart';
import 'controller/auth_controller.dart';
import 'data/auth_repository.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  String? _emailInlineError;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    if (_emailInlineError != null) {
      setState(() {
        _emailInlineError = null;
      });
    }

    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
    });

    try {
      final email = _emailController.text.trim();

      await ref
          .read(authControllerProvider.notifier)
          .forgotPassword(email: email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check your email for the code.')),
      );

      final args = ResetPasswordArgs(email: email);
      await context.push('/reset-password', extra: args);
    } on AuthRequestException catch (e) {
      if (!mounted) return;

      if (e.statusCode == 429) {
        _showTimeoutBanner(context, e.message);
        return;
      }

      if (e.statusCode == 404) {
        setState(() {
          _emailInlineError = 'No account found with this email';
        });
        _formKey.currentState?.validate();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t send code. Try again.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t send code. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
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
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Forgot password',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'We\'ll email you a one-time code.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            autofillHints: const <String>[AutofillHints.email],
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                            ),
                            onChanged: (_) {
                              if (_emailInlineError == null) return;
                              setState(() {
                                _emailInlineError = null;
                              });
                            },
                            onFieldSubmitted: (_) => _submit(),
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return 'Email is required';
                              if (!_isValidEmail(v)) {
                                return 'Enter a valid email';
                              }
                              if (_emailInlineError != null) {
                                return _emailInlineError;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Send code'),
                          ),
                        ],
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


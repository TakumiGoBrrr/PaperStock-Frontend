import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/app_header.dart';
import 'controller/auth_controller.dart';

class ResetPasswordArgs {
  const ResetPasswordArgs({required this.email});

  final String email;
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.args});

  final ResetPasswordArgs args;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  String? _otpError;

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() {
        _otpError = 'Enter the 6-digit code';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSubmitting = true;
      _otpError = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).resetPassword(
            email: widget.args.email,
            otp: otp,
            newPassword: _passwordController.text,
          );

      if (!mounted) return;
      final controller = ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
      await controller.closed;
      if (!mounted) return;
      context.go('/login');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t reset password. Try again.')),
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
                            'Reset password',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Code sent to ${widget.args.email}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _otpController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Code',
                              errorText: _otpError,
                            ),
                            onChanged: (_) {
                              if (_otpError == null) return;
                              setState(() {
                                _otpError = null;
                              });
                            },
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) return 'Code is required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'New password',
                              helperText: 'At least 8 characters',
                            ),
                            onFieldSubmitted: (_) => _submit(),
                            validator: (value) {
                              final v = value ?? '';
                              if (v.isEmpty) return 'Password is required';
                              if (v.length < 8) {
                                return 'Must be at least 8 characters';
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
                                : const Text('Reset password'),
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => context.go('/login'),
                            child: const Text('Back to login'),
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

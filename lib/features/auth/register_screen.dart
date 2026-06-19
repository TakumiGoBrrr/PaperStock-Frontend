import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_config.dart';
import '../../core/widgets/app_header.dart';
import 'controller/auth_controller.dart';
import 'data/auth_repository.dart';
import 'otp_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({
    super.key,
    this.initialEmail,
    this.initialPassword,
  });

  final String? initialEmail;
  final String? initialPassword;

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;

  bool _isContinuingToOtp = false;
  bool _showPassword = false;
  String? _displayNameServerError;

  // Play Store compliance: explicit consent + age gate.
  bool _agreedToPrivacy = false;
  DateTime? _dateOfBirth;

  static const int _minimumSignupAge = 13;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _emailController = TextEditingController(text: widget.initialEmail);
    _passwordController = TextEditingController(text: widget.initialPassword);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isContinuingToOtp) return;

    final form = _formKey.currentState;
    if (form == null) return;
    if (!form.validate()) return;

    if (_dateOfBirth == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your date of birth to continue.'),
        ),
      );
      return;
    }

    if (_ageInYears(_dateOfBirth!) < _minimumSignupAge) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You must be at least $_minimumSignupAge years old to use PaperStock.',
          ),
        ),
      );
      return;
    }

    if (!_agreedToPrivacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the Privacy Policy to continue.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _isContinuingToOtp = true);

    try {
      final email = _emailController.text.trim();
      final displayName = _displayNameController.text.trim();
      final password = _passwordController.text;

      await ref.read(authControllerProvider.notifier).requestRegisterOtp(
            email: email,
            password: password,
            displayName: displayName,
            dateOfBirth: _formatDob(_dateOfBirth!),
          );

      final args = OtpArgs(email: email, isRegisterFlow: true);

      if (!mounted) return;
      await context.push('/otp', extra: args);
    } catch (e) {
      if (!mounted) return;

      final msg = (e is AuthRequestException)
          ? e.message
          : e.toString().replaceFirst('Exception: ', '');
      final lower = msg.toLowerCase();

      if (kDebugMode) {
        debugPrint('Register OTP request failed: $msg');
      }

      if (e is AuthRequestException && e.statusCode == 429) {
        _showTimeoutBanner(context, msg);
        return;
      }

      if (lower.contains('username already taken')) {
        setState(() => _displayNameServerError = 'Username already taken');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(msg.isEmpty ? 'Couldn\'t create account. Try again.' : msg),
        ),
      );
    } finally {
      if (mounted) setState(() => _isContinuingToOtp = false);
    }

  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse(ApiConfig.privacyPolicyUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the Privacy Policy.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the Privacy Policy.')),
      );
    }
  }

  static int _ageInYears(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  static String _formatDob(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickDateOfBirth() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    // Default the picker to a plausible adult birth year.
    final initial = _dateOfBirth ?? DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
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
                                    ? 'assets/logo_light.png'
                                    : 'assets/logo_dark.png',
                                height: 72,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Create your account',
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Join PaperStock and start sharing ideas',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _displayNameController,
                              autofillHints: const [AutofillHints.username],
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Display name',
                                helperText: 'Letters, numbers, underscore (3–30)',
                                errorText: _displayNameServerError,
                              ),
                              onChanged: (_) {
                                if (_displayNameServerError == null) return;
                                setState(() => _displayNameServerError = null);
                              },
                              validator: (value) {
                                final v = (value ?? '').trim();
                                if (v.isEmpty) {
                                  return 'Display name is required';
                                }
                                if (v.length < 3) {
                                  return 'Must be at least 3 characters';
                                }
                                if (v.length > 30) {
                                  return 'Must be 30 characters or less';
                                }
                                if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
                                  return 'Only letters, numbers, and underscore allowed';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _emailController,
                              autofillHints: const [AutofillHints.email],
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                helperText:
                                    'Email is private and not visible to others',
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
                              autofillHints: const [AutofillHints.newPassword],
                              obscureText: !_showPassword,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                helperText: 'At least 8 characters',
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
                            InkWell(
                              onTap: _pickDateOfBirth,
                              borderRadius: BorderRadius.circular(8),
                              child: InputDecorator(
                                decoration: InputDecoration(
                                  labelText: 'Date of birth',
                                  helperText:
                                      'You must be at least $_minimumSignupAge years old to join.',
                                  prefixIcon: const Icon(Icons.cake_outlined),
                                ),
                                child: Text(
                                  _dateOfBirth == null
                                      ? 'Select your date of birth'
                                      : _formatDob(_dateOfBirth!),
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: _dateOfBirth == null
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ConsentCheckbox(
                              value: _agreedToPrivacy,
                              onChanged: (v) =>
                                  setState(() => _agreedToPrivacy = v ?? false),
                              child: Text.rich(
                                TextSpan(
                                  style: theme.textTheme.bodyMedium,
                                  children: <InlineSpan>[
                                    const TextSpan(
                                        text: 'I have read and agree to the '),
                                    WidgetSpan(
                                      alignment: PlaceholderAlignment.middle,
                                      child: GestureDetector(
                                        onTap: _openPrivacyPolicy,
                                        child: Text(
                                          'Privacy Policy',
                                          style:
                                              theme.textTheme.bodyMedium?.copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const TextSpan(text: '.'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: (_isContinuingToOtp ||
                                      _dateOfBirth == null ||
                                      !_agreedToPrivacy)
                                  ? null
                                  : _submit,
                              child: _isContinuingToOtp
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Create account'),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _isContinuingToOtp
                                  ? null
                                  : () => context.pop(),
                              child: const Text('I already have an account'),
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

class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
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


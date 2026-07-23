import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets/window_controls.dart';
import 'auth_api.dart';

enum _Mode { signIn, register, verify, forgotPassword, resetPassword }

/// Forces lowercase a-z only — mirrors the backend's username rule.
class _LowercaseLettersFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = newValue.text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return newValue.copyWith(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onAuthenticated});

  final Future<void> Function(AuthResult result) onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _api = AuthApi();
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  final _identifierCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _submitting = false;
  String? _error;
  String? _info;
  String? _pendingEmail;
  String? _resetEmail;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _referralCtrl.dispose();
    _identifierCtrl.dispose();
    _newPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
      _info = null;
    });
    try {
      switch (_mode) {
        case _Mode.signIn:
          final result = await _api.login(
            emailOrUsername: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
          await widget.onAuthenticated(result);
        case _Mode.forgotPassword:
          final identifier = _identifierCtrl.text.trim();
          final resolvedEmail = await _api.forgotPassword(identifier);
          setState(() {
            // The backend never confirms whether the account exists, so
            // this moves forward either way; resolvedEmail is only set
            // when a real account matched (needed for resetPassword).
            _resetEmail = resolvedEmail ?? identifier;
            _mode = _Mode.resetPassword;
            _info = 'If an account exists, a code was sent.';
          });
        case _Mode.resetPassword:
          final result = await _api.resetPassword(
            email: _resetEmail ?? _identifierCtrl.text.trim(),
            code: _codeCtrl.text.trim(),
            newPassword: _newPasswordCtrl.text,
          );
          await widget.onAuthenticated(result);
        case _Mode.register:
          final email = _emailCtrl.text.trim();
          await _api.register(
            email: email,
            username: _usernameCtrl.text.trim(),
            password: _passwordCtrl.text,
            name: _nameCtrl.text.trim(),
            referralCode: _referralCtrl.text.trim(),
          );
          setState(() {
            _pendingEmail = email;
            _mode = _Mode.verify;
          });
        case _Mode.verify:
          final result = await _api.verifyEmail(
            email: _pendingEmail!,
            code: _codeCtrl.text.trim(),
          );
          await widget.onAuthenticated(result);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resendCode() async {
    if (_pendingEmail == null) return;
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await _api.resendCode(_pendingEmail!);
      setState(() => _info = 'Code resent — check your inbox.');
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);

    return Scaffold(
      backgroundColor: theme.bgSurface,
      body: Column(
        children: [
          const WindowControls(canMaximize: false),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 320, maxWidth: 380),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Logo(theme: theme),
                        const SizedBox(height: 32),
                        ..._buildModeContent(theme),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildModeContent(CroplooTheme theme) {
    switch (_mode) {
      case _Mode.signIn:
        return _signInFields(theme);
      case _Mode.register:
        return _registerFields(theme);
      case _Mode.verify:
        return _verifyFields(theme);
      case _Mode.forgotPassword:
        return _forgotPasswordFields(theme);
      case _Mode.resetPassword:
        return _resetPasswordFields(theme);
    }
  }

  List<Widget> _signInFields(CroplooTheme theme) => [
        Text('Welcome back', style: CroplooText.h1.copyWith(color: theme.textPrimary)),
        const SizedBox(height: 6),
        Text('The basis for better trades.',
            style: CroplooText.body.copyWith(color: theme.textSecondary)),
        const SizedBox(height: 28),
        _Field(
          controller: _emailCtrl,
          label: 'EMAIL OR USERNAME',
          hint: 'you@company.com or username',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _passwordCtrl,
          label: 'PASSWORD',
          hint: '••••••••',
          isPassword: true,
          validator: (v) =>
              (v == null || v.length < 6) ? 'At least 6 characters' : null,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _mode = _Mode.forgotPassword;
                      _error = null;
                      _info = null;
                    }),
            child: Text('Forgot password?',
                style: CroplooText.body.copyWith(color: theme.textSecondary)),
          ),
        ),
        ..._messages(theme),
        const SizedBox(height: 16),
        _SubmitButton(theme: theme, submitting: _submitting, label: 'Sign in', onPressed: _submit),
        const SizedBox(height: 16),
        _switchModeLink(
          theme,
          text: "Don't have an account? Create one",
          onTap: () => setState(() {
            _mode = _Mode.register;
            _error = null;
            _info = null;
          }),
        ),
      ];

  List<Widget> _registerFields(CroplooTheme theme) => [
        Text('Create your account', style: CroplooText.h1.copyWith(color: theme.textPrimary)),
        const SizedBox(height: 6),
        Text('The basis for better trades.',
            style: CroplooText.body.copyWith(color: theme.textSecondary)),
        const SizedBox(height: 28),
        _Field(
          controller: _nameCtrl,
          label: 'NAME',
          hint: 'Arkadiy',
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _usernameCtrl,
          label: 'USERNAME (lowercase letters only)',
          hint: 'arkadiy',
          inputFormatters: [_LowercaseLettersFormatter()],
          validator: (v) => (v == null || !RegExp(r'^[a-z]{3,20}$').hasMatch(v))
              ? '3-20 lowercase letters (a-z)'
              : null,
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _emailCtrl,
          label: 'EMAIL',
          hint: 'you@company.com',
          keyboardType: TextInputType.emailAddress,
          validator: (v) =>
              (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _passwordCtrl,
          label: 'PASSWORD',
          hint: '••••••••',
          isPassword: true,
          validator: (v) =>
              (v == null || v.length < 6) ? 'At least 6 characters' : null,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _referralCtrl,
          label: 'REFERRAL CODE (OPTIONAL)',
          hint: "a colleague's username",
        ),
        ..._messages(theme),
        const SizedBox(height: 24),
        _SubmitButton(
          theme: theme,
          submitting: _submitting,
          label: 'Create account',
          onPressed: _submit,
        ),
        const SizedBox(height: 16),
        _switchModeLink(
          theme,
          text: 'Already have an account? Sign in',
          onTap: () => setState(() {
            _mode = _Mode.signIn;
            _error = null;
            _info = null;
          }),
        ),
      ];

  List<Widget> _verifyFields(CroplooTheme theme) => [
        Text('Check your email', style: CroplooText.h1.copyWith(color: theme.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Enter the 8-digit code we sent to ${_pendingEmail ?? 'your email'}.',
          style: CroplooText.body.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(height: 28),
        _Field(
          controller: _codeCtrl,
          label: 'VERIFICATION CODE',
          hint: '00000000',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          validator: (v) => (v == null || v.length != 8) ? 'Enter the 8-digit code' : null,
          onSubmitted: (_) => _submit(),
        ),
        ..._messages(theme),
        const SizedBox(height: 24),
        _SubmitButton(theme: theme, submitting: _submitting, label: 'Verify', onPressed: _submit),
        const SizedBox(height: 16),
        _switchModeLink(theme, text: 'Resend code', onTap: _resendCode),
      ];

  List<Widget> _forgotPasswordFields(CroplooTheme theme) => [
        Text('Reset your password', style: CroplooText.h1.copyWith(color: theme.textPrimary)),
        const SizedBox(height: 6),
        Text(
          "Enter your email or username and we'll send you a reset code.",
          style: CroplooText.body.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(height: 28),
        _Field(
          controller: _identifierCtrl,
          label: 'EMAIL OR USERNAME',
          hint: 'you@company.com or username',
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          onSubmitted: (_) => _submit(),
        ),
        ..._messages(theme),
        const SizedBox(height: 24),
        _SubmitButton(
            theme: theme, submitting: _submitting, label: 'Send reset code', onPressed: _submit),
        const SizedBox(height: 16),
        _switchModeLink(
          theme,
          text: 'Back to sign in',
          onTap: () => setState(() {
            _mode = _Mode.signIn;
            _error = null;
            _info = null;
          }),
        ),
      ];

  List<Widget> _resetPasswordFields(CroplooTheme theme) => [
        Text('Check your email', style: CroplooText.h1.copyWith(color: theme.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Enter the 8-digit code and choose a new password.',
          style: CroplooText.body.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(height: 28),
        _Field(
          controller: _codeCtrl,
          label: 'RESET CODE',
          hint: '00000000',
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          validator: (v) => (v == null || v.length != 8) ? 'Enter the 8-digit code' : null,
        ),
        const SizedBox(height: 16),
        _Field(
          controller: _newPasswordCtrl,
          label: 'NEW PASSWORD',
          hint: '••••••••',
          isPassword: true,
          validator: (v) =>
              (v == null || v.length < 6) ? 'At least 6 characters' : null,
          onSubmitted: (_) => _submit(),
        ),
        ..._messages(theme),
        const SizedBox(height: 24),
        _SubmitButton(
            theme: theme,
            submitting: _submitting,
            label: 'Reset password & sign in',
            onPressed: _submit),
        const SizedBox(height: 16),
        _switchModeLink(theme, text: 'Resend code', onTap: () => _api.forgotPassword(_resetEmail ?? '')),
        const SizedBox(height: 8),
        _switchModeLink(
          theme,
          text: 'Back to sign in',
          onTap: () => setState(() {
            _mode = _Mode.signIn;
            _error = null;
            _info = null;
          }),
        ),
      ];

  List<Widget> _messages(CroplooTheme theme) => [
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: CroplooText.body.copyWith(color: theme.negative)),
        ],
        if (_info != null) ...[
          const SizedBox(height: 16),
          Text(_info!, style: CroplooText.body.copyWith(color: theme.positive)),
        ],
      ];

  Widget _switchModeLink(CroplooTheme theme, {required String text, required VoidCallback onTap}) {
    return Center(
      child: TextButton(
        onPressed: _submitting ? null : onTap,
        child: Text(text, style: CroplooText.body.copyWith(color: theme.textSecondary)),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.theme});

  final CroplooTheme theme;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      theme.isDark ? 'assets/logo_text_black.png' : 'assets/logo_text_white.png',
      height: 72,
      alignment: Alignment.centerLeft,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.theme,
    required this.submitting,
    required this.label,
    required this.onPressed,
  });

  final CroplooTheme theme;
  final bool submitting;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: submitting ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.accent,
          foregroundColor: theme.contrastColor(theme.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
        ),
        child: submitting
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.contrastColor(theme.accent),
                ),
              )
            : Text(
                label,
                style: CroplooText.bodyStrong.copyWith(color: theme.contrastColor(theme.accent)),
              ),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.isPassword = false,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool isPassword;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final void Function(String)? onSubmitted;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final theme = CroplooTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: CroplooText.label.copyWith(color: theme.textSecondary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: widget.controller,
          obscureText: widget.isPassword && _obscured,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          validator: widget.validator,
          onFieldSubmitted: widget.onSubmitted,
          style: CroplooText.data.copyWith(color: theme.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscured ? PhosphorIconsRegular.eye : PhosphorIconsRegular.eyeSlash,
                      size: 18,
                      color: theme.textSecondary,
                    ),
                    onPressed: () => setState(() => _obscured = !_obscured),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

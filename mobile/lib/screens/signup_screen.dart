import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/backend_service.dart';
import '../widgets/language_toggle.dart';

enum _SignupMode { create, join }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _familyNameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _backendService = BackendService();
  bool _loading = false;
  bool _obscurePassword = true;
  _SignupMode _mode = _SignupMode.create;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    _familyNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final authResponse = await Supabase.instance.client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final accessToken = authResponse.session?.accessToken;
      if (accessToken == null) {
        throw Exception(
            'Signup succeeded but no session returned. '
            'Check if email confirmation is required in Supabase.');
      }

      await _backendService.onboardUser(
        displayName: _displayNameController.text.trim(),
        familyName: _mode == _SignupMode.create
            ? _familyNameController.text.trim()
            : null,
        inviteCode: _mode == _SignupMode.join
            ? _inviteCodeController.text.trim().toUpperCase()
            : null,
        accessToken: accessToken,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      final clean = raw.startsWith('Exception: ') ? raw.substring(11) : raw;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(clean), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('signup.title'.tr()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: const [LanguageToggle()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_SignupMode>(
                segments: [
                  ButtonSegment(
                    value: _SignupMode.create,
                    label: Text('signup.start_new_family'.tr()),
                    icon: const Icon(Icons.family_restroom),
                  ),
                  ButtonSegment(
                    value: _SignupMode.join,
                    label: Text('signup.join_with_code'.tr()),
                    icon: const Icon(Icons.group_add),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: 'signup.your_name'.tr(),
                  prefixIcon: const Icon(Icons.person_outlined),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'signup.name_required'.tr()
                    : null,
              ),
              const SizedBox(height: 16),
              if (_mode == _SignupMode.create)
                TextFormField(
                  controller: _familyNameController,
                  decoration: InputDecoration(
                    labelText: 'signup.family_name'.tr(),
                    hintText: 'signup.family_name_hint'.tr(),
                    prefixIcon: const Icon(Icons.family_restroom),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'signup.family_name_required'.tr()
                      : null,
                )
              else
                TextFormField(
                  controller: _inviteCodeController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: InputDecoration(
                    labelText: 'signup.invite_code'.tr(),
                    hintText: 'signup.invite_code_hint'.tr(),
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'signup.invite_code_required'.tr();
                    if (t.length != 8) return 'signup.invite_code_length'.tr();
                    return null;
                  },
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'login.email'.tr(),
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) => v == null || v.isEmpty
                    ? 'login.email_required'.tr()
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'login.password'.tr(),
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'login.password_required'.tr();
                  }
                  if (v.length < 6) {
                    return 'signup.password_min_length'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'signup.confirm_password'.tr(),
                  prefixIcon: const Icon(Icons.lock_outlined),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'signup.passwords_mismatch'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text('signup.create_account'.tr(),
                          style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

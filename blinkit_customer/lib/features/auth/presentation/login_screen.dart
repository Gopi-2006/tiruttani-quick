import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/text_styles.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_textfield.dart';
import '../../../core/utils/validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthRepository();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _acceptedPrivacyPolicy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingLarge),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(AppIcons.shoppingBag, size: AppDimensions.iconSizeExtraLarge, color: AppColors.primary),
                  const SizedBox(height: AppDimensions.spacingNormal),
                  const Text(
                    AppStrings.appTitle,
                    style: TextStyles.title,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.spacingExtraLarge),
                  const Text(
                    'Welcome back! Please sign in with your email and password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 16),
                  ),
                  const SizedBox(height: AppDimensions.spacingExtraLarge),
                  CustomTextField(
                    controller: _emailController,
                    labelText: Labels.email,
                    prefixIcon: AppIcons.email,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.validateEmail,
                  ),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  CustomTextField(
                    controller: _passwordController,
                    labelText: Labels.password,
                    prefixIcon: AppIcons.lock,
                    obscureText: true,
                    validator: Validators.validatePassword,
                  ),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  Row(
                    children: [
                      Checkbox(
                        value: _acceptedPrivacyPolicy,
                        activeColor: AppColors.primary,
                        onChanged: _loading
                            ? null
                            : (val) {
                                setState(() {
                                  _acceptedPrivacyPolicy = val ?? false;
                                });
                              },
                      ),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text('I agree to the '),
                            GestureDetector(
                              onTap: () async {
                                final url = Uri.parse(AppConstants.privacyPolicyUrl);
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Text(' terms.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDimensions.spacingMedium),
                  CustomButton(
                    text: 'Sign In',
                    onPressed: (_acceptedPrivacyPolicy && !_loading) ? _loginWithEmail : null,
                    loading: _loading,
                  ),
                  const SizedBox(height: AppDimensions.spacingLarge),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: AppDimensions.paddingSmall),
                        child: Text('OR', style: TextStyle(color: AppColors.muted)),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: AppDimensions.spacingLarge),
                  CustomButton(
                    text: ButtonTexts.continueWithGoogle,
                    onPressed: (_acceptedPrivacyPolicy && !_loading) ? _googleLogin : null,
                    icon: AppIcons.login,
                    loading: _loading,
                  ),
                  const SizedBox(height: AppDimensions.spacingLarge),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?"),
                      TextButton(
                        onPressed: _loading ? null : () => context.go(AppRoutes.signUp),
                        child: const Text(ButtonTexts.signUp),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loginWithEmail() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      await _auth.signInWithEmail(email: email, password: password);
    } catch (e) {
      if (!mounted) return;
      final errorMsg = AuthExceptionHandler.parseException(e);
      _showErrorSnackBar(errorMsg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    if (_loading) return;

    setState(() => _loading = true);
    try {
      await _auth.signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      final errorMsg = AuthExceptionHandler.parseException(e);
      // Suppress cancelled status to avoid unnecessary alarm
      if (!errorMsg.contains('cancelled')) {
        _showErrorSnackBar(errorMsg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

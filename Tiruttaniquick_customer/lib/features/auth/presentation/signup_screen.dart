import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/text_styles.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_textfield.dart';
import '../../../core/widgets/custom_app_bar.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = AuthRepository();
  bool _loading = false;
  bool _acceptedPrivacyPolicy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: AppStrings.signUpTitle),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  AppStrings.createAccountHeader,
                  style: TextStyles.title,
                ),
                const SizedBox(height: AppDimensions.spacingLarge),
                CustomTextField(
                  controller: _nameController,
                  labelText: Labels.fullName,
                  prefixIcon: AppIcons.person,
                  validator: Validators.validateName,
                ),
                const SizedBox(height: AppDimensions.spacingMedium),
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
                      onChanged: (val) {
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
                  text: ButtonTexts.createAccount,
                  onPressed: (_loading || !_acceptedPrivacyPolicy) ? null : _signUp,
                  loading: _loading,
                ),
                const SizedBox(height: AppDimensions.spacingLarge),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(Messages.alreadyHaveAccount),
                    TextButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: const Text(ButtonTexts.login),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await _auth.signUpWithEmail(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')))
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

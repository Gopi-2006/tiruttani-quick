import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/text_styles.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_app_bar.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _codeController = TextEditingController();
  final _auth = AuthRepository();
  bool _loading = false;
  int _seconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_seconds <= 1) {
        timer.cancel();
        setState(() => _seconds = 0);
        return;
      }

      setState(() => _seconds--);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: AppStrings.otpTitle),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingLarge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppDimensions.spacingExtraLarge),
                const Icon(AppIcons.sms, size: AppDimensions.iconSizeExtraLarge, color: AppColors.primary),
                const SizedBox(height: AppDimensions.spacingLarge),
                const Text(
                  AppStrings.enterOtpHeader,
                  style: TextStyles.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.spacingSmall),
                const Text(
                  AppStrings.useOtpSentToPhonePrompt,
                  textAlign: TextAlign.center,
                  style: TextStyles.muted,
                ),
                const SizedBox(height: AppDimensions.spacingExtraLarge),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(fontSize: 28, letterSpacing: 10, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(counterText: ''),
                ),
                const SizedBox(height: AppDimensions.spacingLarge),
                CustomButton(
                  text: ButtonTexts.verifyOtp,
                  onPressed: _loading ? null : _verify,
                  loading: _loading,
                ),
                const SizedBox(height: AppDimensions.spacingMedium),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(Messages.didNotReceiveOtp),
                    TextButton(
                      onPressed: _seconds > 0 ? null : _resend,
                      child: Text(_seconds > 0 ? 'Resend in $_seconds s' : ButtonTexts.resend),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => context.go(AppRoutes.home),
                  child: const Text(ButtonTexts.skipForDemo),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _verify() async {
    if (_codeController.text.length != 6) return;

    setState(() => _loading = true);
    final verified = await _auth.verifyOtp(_codeController.text);
    if (!mounted) return;

    if (verified) {
      context.go(AppRoutes.home);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(Messages.invalidOrExpiredOtp)));
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _resend() async {
    final profile = await _auth.getCurrentProfile();
    if (profile != null) {
      await _auth.retryOtp(phone: profile.phone);
    }
    _startTimer();
  }
}

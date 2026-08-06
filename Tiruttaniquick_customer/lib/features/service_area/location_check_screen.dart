import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';
import '../../services/service_area_provider.dart';

class LocationCheckScreen extends StatefulWidget {
  const LocationCheckScreen({super.key});

  @override
  State<LocationCheckScreen> createState() => _LocationCheckScreenState();
}

class _LocationCheckScreenState extends State<LocationCheckScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final TextEditingController _pincodeController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _pincodeController = TextEditingController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ServiceAreaProvider>(context, listen: false);
      if (provider.status == ServiceAreaStatus.notChecked) {
        provider.initServiceArea();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  void _submitPincode(ServiceAreaProvider provider) {
    if (_formKey.currentState?.validate() ?? false) {
      provider.checkManualPincode(_pincodeController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<ServiceAreaProvider>(
        builder: (context, provider, child) {
          final isChecking = provider.isChecking;
          final isError = provider.isError;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Pulsing GPS / Location Icon
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1.1).animate(
                          CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                        ),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 54,
                            color: isError ? AppColors.error : AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        isChecking ? 'Detecting Location...' : 'Enter Delivery Pincode',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      // Description / Status
                      Text(
                        isChecking
                            ? 'Please wait while we fetch your current location to check availability.'
                            : 'We need to verify if we serve your area before you can browse products.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      if (isChecking) ...[
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                        const SizedBox(height: 24),
                      ] else ...[
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (isError && provider.errorMessage != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(AppDimensions.paddingNormal),
                                  decoration: BoxDecoration(
                                    color: AppColors.error.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(AppDimensions.borderRadiusNormal),
                                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: AppColors.error),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          provider.errorMessage!,
                                          style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              TextFormField(
                                controller: _pincodeController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                decoration: const InputDecoration(
                                  hintText: 'Enter 6-digit pincode',
                                  prefixIcon: Icon(Icons.pin_drop, color: AppColors.muted),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Pincode is required';
                                  }
                                  if (value.length != 6) {
                                    return 'Pincode must be exactly 6 digits';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              ElevatedButton(
                                onPressed: () => _submitPincode(provider),
                                child: const Text(
                                  'Verify Pincode',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 12),

                              OutlinedButton.icon(
                                onPressed: () => provider.checkGPSLocation(),
                                icon: const Icon(Icons.gps_fixed_rounded),
                                label: const Text(
                                  'Use GPS Location Instead',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

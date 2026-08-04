import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:blinkit_shared/blinkit_shared.dart';
import '../../services/service_area_provider.dart';

class ServiceUnavailableScreen extends StatefulWidget {
  const ServiceUnavailableScreen({super.key});

  @override
  State<ServiceUnavailableScreen> createState() => _ServiceUnavailableScreenState();
}

class _ServiceUnavailableScreenState extends State<ServiceUnavailableScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest(ServiceAreaProvider provider) async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _submitting = true;
      });

      try {
        await provider.submitNotificationRequest(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        );
        if (!mounted) return;
        setState(() {
          _submitted = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you! We will notify you when service is available.'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _submitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<ServiceAreaProvider>(
        builder: (context, provider, child) {
          final detected = provider.detectedPincode ?? 'Unknown';
          final allowedStr = provider.allowedPincodes.isEmpty
              ? '631209, 631211'
              : provider.allowedPincodes.join(', ');

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  // Block / Alert Icon
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.location_off_rounded,
                      size: 48,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  const Text(
                    'Service Not Available Yet',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.text,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Message
                  const Text(
                    'Sorry, we currently deliver only in selected areas.',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.muted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Pincode details card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.paddingNormal),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Detected Pincode:',
                                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
                              ),
                              Text(
                                detected,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.error,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Available Pincode:',
                                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
                              ),
                              Text(
                                allowedStr,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => provider.checkGPSLocation(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh GPS'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            provider.reset();
                          },
                          child: const Text('Try Another Pincode'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Notify me block
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.paddingNormal),
                      child: _submitted
                          ? const Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
                                    SizedBox(width: 12),
                                    Text(
                                      'Notification Registered!',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'We have saved your details. We will contact you once we open delivery services in your area.',
                                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                                ),
                              ],
                            )
                          : Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Notify Me When Available',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Leave your info below, and we will update you as soon as we start shipping here.',
                                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Full Name',
                                      prefixIcon: Icon(Icons.person_outline, size: 20),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Name is required';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Phone Number',
                                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Phone is required';
                                      }
                                      if (value.length != 10) {
                                        return 'Phone number must be exactly 10 digits';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _submitting ? null : () => _submitRequest(provider),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: AppColors.text,
                                    ),
                                    child: _submitting
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation(AppColors.text),
                                            ),
                                          )
                                        : const Text(
                                            'Notify Me',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

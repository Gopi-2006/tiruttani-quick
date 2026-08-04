import 'package:blinkit_shared/blinkit_shared.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../services/service_area_provider.dart';
import '../../../services/settings_provider.dart';
import '../../../config/admob_config.dart';
import '../../../widgets/banner_ad_widget.dart';

import '../../../../core/widgets/custom_app_bar.dart';
import '../../../../core/widgets/custom_button.dart';
import '../../../../core/widgets/custom_textfield.dart';
import '../../../../core/widgets/loading_widget.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  UserProfileModel? _profile;
  List<AddressModel> _addresses = [];
  bool _savingPhone = false;
  bool _savingAddress = false;

  Future<void> _launchReviewForm() async {
    final Uri url = Uri.parse(AppConstants.reviewGoogleFormUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open review link: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profile = await AuthRepository().getCurrentProfile();
    if (!mounted) return;

    final uid = user.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('addresses')
        .where('userId', isEqualTo: uid)
        .get();

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _addresses = snapshot.docs
          .map((doc) => AddressModel.fromFirestore(doc.id, doc.data()))
          .toList();
      _loading = false;
    });
  }

  Future<void> _logout() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await NotificationService.instance.clearToken(user.uid);
    }
    await AuthRepository().signOut();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  Future<void> _editPhone() async {
    final current = (_profile?.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final controller = TextEditingController(text: current);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.translate('editPhone')),
        content: CustomTextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          labelText: context.translate('phone'),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(), child: Text(context.translate('cancel'))),
          ElevatedButton(onPressed: () => context.pop(controller.text.trim()), child: Text(context.translate('save'))),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    final digits = result.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 10) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(ValidationMessages.enterValidPhone)));
      return;
    }

    setState(() => _savingPhone = true);
    try {
      await AuthRepository().updateProfilePhone(digits);
      if (!mounted) return;
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update phone: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingPhone = false);
    }
  }

  Future<void> _addOrEditAddress(AddressModel? address) async {
    final isEdit = address != null;
    final labelCtrl = TextEditingController(text: address?.label ?? '');
    final fullAddressCtrl = TextEditingController(text: address?.fullAddress ?? '');
    final landmarkCtrl = TextEditingController(text: address?.landmark ?? '');
    final pincodeCtrl = TextEditingController(text: address?.pincode ?? '600001');
    final phoneCtrl = TextEditingController(text: address?.phone ?? _profile?.phone ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? context.translate('editAddress') : context.translate('addAddress')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.translate('fillManuallyNote'),
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: AppDimensions.spacingSmall),
              CustomTextField(controller: labelCtrl, labelText: context.translate('label')),
              const SizedBox(height: AppDimensions.spacingSmall),
              CustomTextField(controller: fullAddressCtrl, labelText: context.translate('fullAddress'), maxLines: 2),
              const SizedBox(height: AppDimensions.spacingSmall),
              CustomTextField(controller: landmarkCtrl, labelText: context.translate('landmark')),
              const SizedBox(height: AppDimensions.spacingSmall),
              CustomTextField(controller: pincodeCtrl, labelText: context.translate('pincode'), keyboardType: TextInputType.number),
              const SizedBox(height: AppDimensions.spacingSmall),
              CustomTextField(controller: phoneCtrl, labelText: context.translate('phone'), keyboardType: TextInputType.phone),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => context.pop(false), child: Text(context.translate('cancel'))),
          ElevatedButton(onPressed: () => context.pop(true), child: Text(context.translate('save'))),
        ],
      ),
    );

    if (result != true) return;
    if (!mounted) return;

    final pincodeText = pincodeCtrl.text.trim();
    setState(() => _savingAddress = true);
    try {
      final isAllowed = await Provider.of<ServiceAreaProvider>(context, listen: false).isPincodeAllowed(pincodeText);
      if (!isAllowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.translate('pincodeWarning')),
              backgroundColor: AppColors.error,
            ),
          );
        }
        setState(() => _savingAddress = false);
        return;
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (isEdit) {
        await FirebaseFirestore.instance.collection('addresses').doc(address.id).update({
          'label': labelCtrl.text.trim(),
          'fullAddress': fullAddressCtrl.text.trim(),
          'landmark': landmarkCtrl.text.trim(),
          'city': AppConstants.city,
          'state': AppConstants.state,
          'pincode': pincodeCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('addresses').add({
          'userId': user.uid,
          'label': labelCtrl.text.trim().isEmpty ? 'Home' : labelCtrl.text.trim(),
          'fullAddress': fullAddressCtrl.text.trim(),
          'landmark': landmarkCtrl.text.trim(),
          'city': AppConstants.city,
          'state': AppConstants.state,
          'pincode': pincodeCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'isDefault': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save address: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingAddress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      if (!ConnectivityProvider.instance.isOnline) {
        return Scaffold(
          appBar: CustomAppBar(title: context.translate('profileTitle')),
          body: OfflinePlaceholderWidget(
            onRetrySuccess: _loadData,
          ),
        );
      }
      return const Scaffold(
        body: LoadingWidget(),
      );
    }

    final profilePhone = (_profile?.phone ?? '').trim();
    final profilePhoneDigits = profilePhone.replaceAll(RegExp(r'[^0-9]'), '');
    final showProfilePhone = profilePhoneDigits.length >= 10;

    return Scaffold(
      appBar: CustomAppBar(
        title: context.translate('profileTitle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/settings'),
          ),
        ],
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(AppIcons.arrowBack),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    (_profile?.name ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: AppColors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: AppDimensions.spacingMedium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_profile?.name ?? 'User',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(_profile?.email ?? '',
                          style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingLarge),
            Text(context.translate('contact'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppDimensions.spacingSmall),
            if (_profile?.email != null)
              _InfoRow(icon: AppIcons.email, label: context.translate('gmail'), value: _profile!.email!),
            if (showProfilePhone)
              _InfoRow(
                icon: AppIcons.phone,
                label: context.translate('phone'),
                value: profilePhoneDigits,
                trailing: _savingPhone
                    ? const SizedBox(width: 18, height: 18, child: LoadingWidget(size: 14))
                    : IconButton(icon: const Icon(AppIcons.edit, size: 18), onPressed: _editPhone),
              ),
            if (!showProfilePhone)
              CustomButton(
                onPressed: _savingPhone ? null : _editPhone,
                text: _savingPhone ? 'Saving...' : context.translate('addPhone'),
                icon: AppIcons.addSimple,
                outline: true,
              ),
            const SizedBox(height: AppDimensions.spacingLarge),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.translate('savedAddresses'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                IconButton(icon: const Icon(AppIcons.addSimple), onPressed: _savingAddress ? null : () => _addOrEditAddress(null)),
              ],
            ),
            const SizedBox(height: AppDimensions.spacingSmall),
            if (_addresses.isEmpty)
              Text(context.translate('noSavedAddresses'), style: const TextStyle(color: AppColors.muted))
            else
              ..._addresses.map(
                (address) => Card(
                  margin: const EdgeInsets.only(bottom: AppDimensions.marginSmall),
                  child: ListTile(
                    leading: const Icon(AppIcons.location),
                    title: Text(address.label),
                    subtitle: Text('${address.fullAddress}, ${address.city}'),
                    trailing: IconButton(icon: const Icon(AppIcons.edit, size: 18), onPressed: _savingAddress ? null : () => _addOrEditAddress(address)),
                  ),
                ),
              ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.rate_review_rounded, color: AppColors.primary),
                title: Text(
                  context.translate('reviewsFeedback'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(context.translate('reviewsSubtitle')),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.muted),
                onTap: _launchReviewForm,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingMedium),
            Card(
              child: ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: AppColors.error),
                title: Text(
                  context.translate('deleteAccount'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Submit a request to delete your account and data'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.muted),
                onTap: () => context.push(AppRoutes.deleteAccount),
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLarge),
            SizedBox(
              width: double.infinity,
              child: CustomButton(
                onPressed: _logout,
                icon: AppIcons.logout,
                text: context.translate('logout'),
                outline: true,
              ),
            ),
            const SizedBox(height: AppDimensions.spacingLarge),
          ],
        ),
      ),
      bottomNavigationBar: BannerAdWidget(adUnitId: AdMobConfig.myProfileBannerId),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({required this.icon, required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Expanded(child: Text(value, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
          if (trailing != null) ...[trailing!],
        ],
      ),
    );
  }
}

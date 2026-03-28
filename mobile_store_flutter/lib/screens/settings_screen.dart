import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../screens/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ── Export ────────────────────────────────────────────────────────────────

  Future<void> _export(BuildContext context) async {
    try {
      final json = await DatabaseService.exportJson();
      final dir = await getTemporaryDirectory();
      final date = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      final file = File('${dir.path}/mobile_store_backup_$date.json');
      await file.writeAsString(json);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Mobile Store Backup $date',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  // ── Import ────────────────────────────────────────────────────────────────

  Future<void> _import(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final json = await file.readAsString();

      // Confirm before importing
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Backup?'),
          content: const Text(
              'New records from the backup will be added to your existing data. '
              'Nothing will be deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (ok != true) return;

      final counts = await DatabaseService.importJson(json);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Imported: ${counts['products']} products, '
            '${counts['customers']} customers, '
            '${counts['invoices']} invoices.',
          ),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _logout(BuildContext context) async {
    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Store info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.storefront_outlined),
                    const SizedBox(width: 8),
                    Text('Store Info', style: theme.textTheme.titleMedium),
                  ]),
                  const Divider(height: 20),
                  _infoRow('Name', AppConfig.storeName),
                  _infoRow('Address', AppConfig.storeAddress),
                  _infoRow('Phone', AppConfig.storePhone),
                  _infoRow('Email', AppConfig.storeEmail),
                  _infoRow('Currency', AppConfig.currency),
                  if (AppConfig.taxRate > 0)
                    _infoRow('Tax Rate', '${(AppConfig.taxRate * 100).toStringAsFixed(1)}%'),
                  const SizedBox(height: 8),
                  Text(
                    'To change store details, edit lib/config.dart and rebuild.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Logged-in user
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.person_outline),
                    const SizedBox(width: 8),
                    Text('Account', style: theme.textTheme.titleMedium),
                  ]),
                  const Divider(height: 20),
                  _infoRow('Username', AuthService.username ?? ''),
                  _infoRow('Role', AuthService.role ?? ''),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Backup section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.backup_outlined),
                    const SizedBox(width: 8),
                    Text('Data Backup', style: theme.textTheme.titleMedium),
                  ]),
                  const Divider(height: 20),
                  Text(
                    'All data is stored on this device. '
                    'Export a backup and save it to Google Drive, email, '
                    'or any other service to keep it safe.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('Export Backup'),
                      onPressed: () => _export(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Import Backup'),
                      onPressed: () => _import(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Import adds new records without deleting existing ones.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Logout
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('Logout',
                  style: TextStyle(color: Colors.red)),
              onPressed: () => _logout(context),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Mobile Store v1.0',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
}

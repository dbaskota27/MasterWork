import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/database_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Subscription status
        _SubscriptionCard(),
        const SizedBox(height: 12),

        // Store Info (manager)
        if (AuthService.isManager)
          _SectionTile(
            icon: Icons.storefront_outlined,
            title: 'Store Information',
            subtitle: 'Name, address, phone, payment QR',
            onTap: () => _push(const _StoreInfoScreen()),
          ),
        const SizedBox(height: 8),

        // Change Password
        _SectionTile(
          icon: Icons.lock_outline,
          title: 'Change Password',
          subtitle: 'Update your login password',
          onTap: () => _push(const _ChangePasswordScreen()),
        ),
        const SizedBox(height: 8),

        // User Management (manager)
        if (AuthService.isManager) ...[
          _SectionTile(
            icon: Icons.manage_accounts_outlined,
            title: 'User Management',
            subtitle: 'Add, edit, or remove workers & managers',
            onTap: () => _push(const _UserManagementScreen()),
          ),
          const SizedBox(height: 8),
        ],

        // Export
        _SectionTile(
          icon: Icons.backup_outlined,
          title: 'Export Backup',
          subtitle: 'Save data to Google Drive, email, etc.',
          onTap: () => _export(context),
        ),
        const SizedBox(height: 8),

        // Import
        _SectionTile(
          icon: Icons.download_outlined,
          title: 'Import Backup',
          subtitle: 'Restore data from a backup file',
          onTap: () => _import(context),
        ),
        const SizedBox(height: 24),

        // Logout
        OutlinedButton.icon(
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          onPressed: () => _logout(context),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Signed in as ${AuthService.userEmail ?? ""}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }

  void _push(Widget s) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  Future<void> _export(BuildContext ctx) async {
    try {
      final json = await DatabaseService.exportJson();
      final dir = await getTemporaryDirectory();
      final date = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
      final file = File('${dir.path}/mobile_store_backup_$date.json');
      await file.writeAsString(json);
      await Share.shareXFiles([XFile(file.path)],
          subject: 'Mobile Store Backup $date');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _import(BuildContext ctx) async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) return;
      final file = File(result.files.single.path!);
      final json = await file.readAsString();

      if (!ctx.mounted) return;
      final ok = await showDialog<bool>(
        context: ctx,
        builder: (_) => AlertDialog(
          title: const Text('Import Backup?'),
          content: const Text('New records will be added. Nothing deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (ok != true) return;

      final counts = await DatabaseService.importJson(json);
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(
              'Imported: ${counts['products']} products, '
              '${counts['customers']} customers, '
              '${counts['invoices']} invoices.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _logout(BuildContext ctx) async {
    await AuthService.logout();
    if (!ctx.mounted) return;
    Navigator.of(ctx).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

// ── Section tile ──────────────────────────────────────────────────────────────

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _SectionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext ctx) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(ctx).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ── Subscription card ─────────────────────────────────────────────────────────

class _SubscriptionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isActive = SubscriptionService.isActive;
    final label = SubscriptionService.statusLabel;
    final expiry = SubscriptionService.expiry;

    return Card(
      color: isActive ? Colors.green.shade50 : Colors.orange.shade50,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.verified_outlined : Icons.warning_outlined,
              color: isActive ? Colors.green.shade700 : Colors.orange.shade700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subscription: $label',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isActive
                              ? Colors.green.shade700
                              : Colors.orange.shade700)),
                  if (expiry != null)
                    Text(
                        'Expires: ${DateFormat('MMM d, y').format(expiry)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Store Info Screen
// ══════════════════════════════════════════════════════════════════════════════

class _StoreInfoScreen extends StatefulWidget {
  const _StoreInfoScreen();
  @override
  State<_StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<_StoreInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name      = TextEditingController();
  final _address   = TextEditingController();
  final _phone     = TextEditingController();
  final _email     = TextEditingController();
  final _paymentQr = TextEditingController();
  final _currency  = TextEditingController();
  final _taxRate   = TextEditingController();
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await DatabaseService.getStoreInfo();
      _name.text      = info['name'] ?? '';
      _address.text   = info['address'] ?? '';
      _phone.text     = info['phone'] ?? '';
      _email.text     = info['email'] ?? '';
      _paymentQr.text = info['payment_qr'] ?? '';
      _currency.text  = info['currency'] ?? '\$';
      _taxRate.text   = (info['tax_rate'] ?? 0).toString();
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _paymentQr, _currency, _taxRate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DatabaseService.updateStoreInfo({
        'name':       _name.text.trim(),
        'address':    _address.text.trim(),
        'phone':      _phone.text.trim(),
        'email':      _email.text.trim(),
        'payment_qr': _paymentQr.text.trim(),
        'currency':   _currency.text.trim().isEmpty ? '\$' : _currency.text.trim(),
        'tax_rate':   double.tryParse(_taxRate.text) ?? 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Store info saved!')));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store Information')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  _f(_name, 'Store Name *', validator: _req),
                  _f(_address, 'Address'),
                  _f(_phone, 'Phone', type: TextInputType.phone),
                  _f(_email, 'Email', type: TextInputType.emailAddress),
                  _f(_paymentQr, 'Payment QR Link', hint: 'https://venmo.com/you'),
                  _f(_currency, 'Currency Symbol', hint: '\$'),
                  _f(_taxRate, 'Tax Rate (0.08 = 8%)',
                      type: const TextInputType.numberWithOptions(decimal: true)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _f(TextEditingController c, String l,
          {TextInputType? type, String? hint, String? Function(String?)? validator}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: l, hintText: hint),
          validator: validator,
        ),
      );
  String? _req(String? v) => v == null || v.trim().isEmpty ? 'Required' : null;
}

// ══════════════════════════════════════════════════════════════════════════════
// Change Password
// ══════════════════════════════════════════════════════════════════════════════

class _ChangePasswordScreen extends StatefulWidget {
  const _ChangePasswordScreen();
  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final _formKey  = GlobalKey<FormState>();
  final _newCtrl  = TextEditingController();
  final _confCtrl = TextEditingController();
  bool _saving = false, _obscure = true;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await AuthService.changePassword(_newCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Password changed!')));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(children: [
            TextFormField(
              controller: _newCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'New Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (v == null || v.length < 6) return 'At least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Confirm Password'),
              validator: (v) => v != _newCtrl.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Change Password'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// User Management
// ══════════════════════════════════════════════════════════════════════════════

class _UserManagementScreen extends StatefulWidget {
  const _UserManagementScreen();
  @override
  State<_UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<_UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await AuthService.getStoreUsers();
    setState(() { _users = users; _loading = false; });
  }

  Future<void> _delete(String id, String displayName) async {
    if (id == AuthService.userId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Can't delete yourself.")));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove "$displayName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.deleteStoreUser(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('No users.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final role = u['role'] ?? 'worker';
                    final name = u['display_name'] ?? 'Unknown';
                    final isMe = u['user_id'] == AuthService.userId;

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: role == 'manager'
                              ? Colors.blue.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            role == 'manager' ? Icons.admin_panel_settings : Icons.person,
                            color: role == 'manager'
                                ? Colors.blue.shade700
                                : Colors.green.shade700,
                            size: 20,
                          ),
                        ),
                        title: Row(children: [
                          Text(name),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('you', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            ),
                          ],
                        ]),
                        subtitle: Text(role),
                        trailing: !isMe
                            ? Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditDialog(u),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => _delete(u['id'], name),
                                ),
                              ])
                            : null,
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
        onPressed: _showAddDialog,
      ),
    );
  }

  void _showAddDialog() {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    String role = 'worker';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Add User', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'The user must sign up with this same email to access the store.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Worker'),
                    value: 'worker',
                    groupValue: role,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setSheetState(() => role = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Manager'),
                    value: 'manager',
                    groupValue: role,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setSheetState(() => role = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await AuthService.inviteWorker(
                        email: emailCtrl.text.trim(),
                        displayName: nameCtrl.text.trim(),
                        role: role,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                    child: const Text('Add'),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> user) {
    final nameCtrl = TextEditingController(text: user['display_name'] ?? '');
    String role = user['role'] ?? 'worker';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20, right: 20, top: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Edit User', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Worker'),
                    value: 'worker',
                    groupValue: role,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setSheetState(() => role = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Manager'),
                    value: 'manager',
                    groupValue: role,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setSheetState(() => role = v!),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      await AuthService.updateStoreUser(user['id'], {
                        'display_name': nameCtrl.text.trim(),
                        'role': role,
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                    child: const Text('Save'),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

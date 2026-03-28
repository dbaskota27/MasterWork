import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../screens/login_screen.dart';

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
        // ── Store Info ──
        _SectionTile(
          icon: Icons.storefront_outlined,
          title: 'Store Information',
          subtitle: 'Name, address, phone, payment QR',
          onTap: () => _push(const _StoreInfoScreen()),
        ),
        const SizedBox(height: 8),

        // ── Change My Password ──
        _SectionTile(
          icon: Icons.lock_outline,
          title: 'Change My Password',
          subtitle: 'Update your own login credentials',
          onTap: () => _push(_ChangePasswordScreen(
            username: AuthService.username!,
          )),
        ),
        const SizedBox(height: 8),

        // ── User Management (manager only) ──
        if (AuthService.isManager) ...[
          _SectionTile(
            icon: Icons.manage_accounts_outlined,
            title: 'User Management',
            subtitle: 'Add, edit, or remove worker & manager accounts',
            onTap: () => _push(const _UserManagementScreen()),
          ),
          const SizedBox(height: 8),
        ],

        // ── Backup ──
        _SectionTile(
          icon: Icons.backup_outlined,
          title: 'Export Backup',
          subtitle: 'Save all data to Google Drive, email, etc.',
          onTap: () => _export(context),
        ),
        const SizedBox(height: 8),
        _SectionTile(
          icon: Icons.download_outlined,
          title: 'Import Backup',
          subtitle: 'Restore data from a backup file',
          onTap: () => _import(context),
        ),
        const SizedBox(height: 24),

        // ── Logout ──
        OutlinedButton.icon(
          icon: const Icon(Icons.logout, color: Colors.red),
          label: const Text('Logout', style: TextStyle(color: Colors.red)),
          onPressed: () => _logout(context),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text('Mobile Store v1.0',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ),
      ],
    );
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _export(BuildContext context) async {
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _import(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final json = await file.readAsString();

      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Backup?'),
          content: const Text(
              'New records will be added to existing data. Nothing will be deleted.'),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Imported: ${counts['products']} products, '
              '${counts['customers']} customers, '
              '${counts['invoices']} invoices.'),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    await AuthService.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

// ── Section tile ──────────────────────────────────────────────────────────────

class _SectionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _SectionTile(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Store Info screen
// ══════════════════════════════════════════════════════════════════════════════

class _StoreInfoScreen extends StatefulWidget {
  const _StoreInfoScreen();

  @override
  State<_StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<_StoreInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name       = TextEditingController();
  final _address    = TextEditingController();
  final _phone      = TextEditingController();
  final _email      = TextEditingController();
  final _paymentQr  = TextEditingController();
  final _currency   = TextEditingController();
  final _taxRate    = TextEditingController();

  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await SettingsService.getStoreInfo();
    _name.text      = info['name']!;
    _address.text   = info['address']!;
    _phone.text     = info['phone']!;
    _email.text     = info['email']!;
    _paymentQr.text = info['payment_qr']!;
    _currency.text  = info['currency']!;
    _taxRate.text   = info['tax_rate']!;
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
      await SettingsService.saveStoreInfo(
        name:       _name.text.trim(),
        address:    _address.text.trim(),
        phone:      _phone.text.trim(),
        email:      _email.text.trim(),
        paymentQr:  _paymentQr.text.trim(),
        currency:   _currency.text.trim().isEmpty ? '\$' : _currency.text.trim(),
        taxRate:    double.tryParse(_taxRate.text) ?? 0,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Store info saved!')));
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
                child: Column(
                  children: [
                    _field(_name, 'Store Name *',
                        validator: _required),
                    _field(_address, 'Address'),
                    _field(_phone, 'Phone',
                        type: TextInputType.phone),
                    _field(_email, 'Email',
                        type: TextInputType.emailAddress),
                    _field(_paymentQr, 'Payment QR Link',
                        hint: 'https://venmo.com/yourhandle'),
                    _field(_currency, 'Currency Symbol',
                        hint: '\$'),
                    _field(_taxRate, 'Tax Rate (0.08 = 8%)',
                        type: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          final d = double.tryParse(v);
                          if (d == null || d < 0 || d > 1) return 'Enter a value between 0 and 1';
                          return null;
                        }),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    TextInputType? type,
    String? hint,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: validator,
        ),
      );

  String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Required' : null;
}

// ══════════════════════════════════════════════════════════════════════════════
// Change Password screen
// ══════════════════════════════════════════════════════════════════════════════

class _ChangePasswordScreen extends StatefulWidget {
  final String username;
  const _ChangePasswordScreen({required this.username});

  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    // Verify current password
    final users = await SettingsService.getUsers();
    final user = users[widget.username];
    if (user == null || user['password'] != _currentCtrl.text) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Current password is incorrect.')));
      }
      return;
    }

    try {
      await SettingsService.changePassword(
          username: widget.username, newPassword: _newCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password changed!')));
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
      appBar: AppBar(
          title: Text('Change Password — ${widget.username}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _currentCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _newCtrl,
                obscureText: _obscure,
                decoration:
                    const InputDecoration(labelText: 'New Password'),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 4) return 'At least 4 characters';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmCtrl,
                obscureText: _obscure,
                decoration: const InputDecoration(
                    labelText: 'Confirm New Password'),
                validator: (v) => v != _newCtrl.text
                    ? 'Passwords do not match'
                    : null,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Change Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// User Management screen (manager only)
// ══════════════════════════════════════════════════════════════════════════════

class _UserManagementScreen extends StatefulWidget {
  const _UserManagementScreen();

  @override
  State<_UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<_UserManagementScreen> {
  Map<String, Map<String, String>> _users = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await SettingsService.getUsers();
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _delete(String username) async {
    // Prevent deleting self
    if (username == AuthService.username) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can't delete your own account.")));
      return;
    }
    // Prevent deleting last manager
    final managers = _users.values
        .where((u) => u['role'] == 'manager')
        .length;
    if (_users[username]?['role'] == 'manager' && managers <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cannot delete the last manager account.')));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete "$username"?'),
        content: const Text('This user will no longer be able to log in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    await SettingsService.deleteUser(username);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('No users found.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final username = _users.keys.elementAt(i);
                    final user = _users[username]!;
                    final isMe = username == AuthService.username;
                    final role = user['role'] ?? 'worker';

                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: role == 'manager'
                              ? Colors.blue.shade100
                              : Colors.green.shade100,
                          child: Icon(
                            role == 'manager'
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: role == 'manager'
                                ? Colors.blue.shade700
                                : Colors.green.shade700,
                            size: 20,
                          ),
                        ),
                        title: Row(children: [
                          Text(username),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('you',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                            ),
                          ]
                        ]),
                        subtitle: Text(role),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: 'Edit',
                              onPressed: () => _showUserForm(
                                  username: username, user: user),
                            ),
                            if (!isMe)
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: 'Delete',
                                onPressed: () => _delete(username),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
        onPressed: () => _showUserForm(),
      ),
    );
  }

  void _showUserForm({String? username, Map<String, String>? user}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserForm(
        existingUsername: username,
        existingRole: user?['role'],
        onSaved: _load,
      ),
    );
  }
}

// ── User add/edit form ────────────────────────────────────────────────────────

class _UserForm extends StatefulWidget {
  final String? existingUsername;
  final String? existingRole;
  final VoidCallback onSaved;

  const _UserForm({
    this.existingUsername,
    this.existingRole,
    required this.onSaved,
  });

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _formKey    = GlobalKey<FormState>();
  late final TextEditingController _username;
  final _password   = TextEditingController();
  final _confirm    = TextEditingController();
  late String _role;
  bool _saving  = false;
  bool _obscure = true;

  bool get _isEdit => widget.existingUsername != null;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(text: widget.existingUsername ?? '');
    _role     = widget.existingRole ?? 'worker';
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // For edit, password can be left blank (keep existing)
    if (!_isEdit && _password.text.isEmpty) return;

    setState(() => _saving = true);
    try {
      if (_isEdit && _password.text.isEmpty) {
        // Just update role
        final users = await SettingsService.getUsers();
        users[widget.existingUsername!]!['role'] = _role;
        await SettingsService.upsertUser(
          username: widget.existingUsername!,
          password: users[widget.existingUsername!]!['password']!,
          role: _role,
        );
      } else {
        await SettingsService.upsertUser(
          username: _username.text.trim().toLowerCase(),
          password: _password.text,
          role: _role,
        );
      }
      if (mounted) {
        widget.onSaved();
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? 'Edit User' : 'Add User',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // Username (read-only on edit)
            TextFormField(
              controller: _username,
              enabled: !_isEdit,
              decoration: const InputDecoration(labelText: 'Username *'),
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            // Password
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: _isEdit
                    ? 'New Password (leave blank to keep)'
                    : 'Password *',
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                if (!_isEdit && (v == null || v.isEmpty)) return 'Required';
                if (v != null && v.isNotEmpty && v.length < 4) {
                  return 'At least 4 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Confirm password (only when password is being set)
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(
                  labelText: 'Confirm Password'),
              validator: (v) {
                if (_password.text.isNotEmpty && v != _password.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Role selector
            Text('Role', style: Theme.of(context).textTheme.labelLarge),
            Row(children: [
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Worker'),
                  subtitle: const Text('Limited access'),
                  value: 'worker',
                  groupValue: _role,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _role = v!),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text('Manager'),
                  subtitle: const Text('Full access'),
                  value: 'manager',
                  groupValue: _role,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _role = v!),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'Save' : 'Add User'),
                ),
              ),
            ]),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

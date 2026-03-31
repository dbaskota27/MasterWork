import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/worker_service.dart';
import '../services/database_service.dart';
import '../services/theme_service.dart';
import 'login_screen.dart';
import 'sales_targets_screen.dart';
import 'cash_register_screen.dart';

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
        // Dark Mode toggle
        Card(
          margin: EdgeInsets.zero,
          child: ValueListenableBuilder<ThemeMode>(
            valueListenable: ThemeService.themeMode,
            builder: (ctx, mode, _) {
              return SwitchListTile(
                secondary: Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode
                      : Icons.light_mode,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Dark Mode'),
                subtitle: Text(mode == ThemeMode.dark
                    ? 'On'
                    : mode == ThemeMode.light
                        ? 'Off'
                        : 'System'),
                value: mode == ThemeMode.dark,
                onChanged: (val) {
                  ThemeService.setThemeMode(
                      val ? ThemeMode.dark : ThemeMode.light);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Store Info (manager)
        if (WorkerService.isManager)
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
        if (WorkerService.isManager) ...[
          _SectionTile(
            icon: Icons.manage_accounts_outlined,
            title: 'User Management',
            subtitle: 'Add, edit, or remove workers & managers',
            onTap: () => _push(const _UserManagementScreen()),
          ),
          const SizedBox(height: 8),
        ],

        // Sales Targets (manager)
        if (WorkerService.isManager) ...[
          _SectionTile(
            icon: Icons.track_changes,
            title: 'Sales Targets',
            subtitle: 'Set daily/monthly targets per worker',
            onTap: () => _push(const SalesTargetsScreen()),
          ),
          const SizedBox(height: 8),
        ],

        // Cash Register (manager)
        if (WorkerService.isManager) ...[
          _SectionTile(
            icon: Icons.point_of_sale,
            title: 'Cash Register',
            subtitle: 'Open/close register, track cash flow',
            onTap: () => _push(const CashRegisterScreen()),
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
            'Signed in as ${WorkerService.workerName ?? AuthService.userEmail ?? ""}',
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
    WorkerService.logout();
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
  final _name              = TextEditingController();
  final _address           = TextEditingController();
  final _phone             = TextEditingController();
  final _email             = TextEditingController();
  final _paymentQr         = TextEditingController();
  final _currency          = TextEditingController();
  final _taxRate           = TextEditingController();
  final _pointsPerUnit     = TextEditingController();
  final _pointsValue       = TextEditingController();
  final _defaultLowStock   = TextEditingController();
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
      _pointsPerUnit.text = (info['points_per_unit'] ?? 1).toString();
      _pointsValue.text   = (info['points_value'] ?? 0.01).toString();
      _defaultLowStock.text = (info['default_low_stock_threshold'] ?? 5).toString();
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _phone, _email, _paymentQr, _currency, _taxRate, _pointsPerUnit, _pointsValue, _defaultLowStock]) {
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
        'tax_rate':       double.tryParse(_taxRate.text) ?? 0,
        'points_per_unit': double.tryParse(_pointsPerUnit.text) ?? 1,
        'points_value':    double.tryParse(_pointsValue.text) ?? 0.01,
        'default_low_stock_threshold': int.tryParse(_defaultLowStock.text) ?? 5,
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
                  const SizedBox(height: 8),
                  Text('Inventory', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _f(_defaultLowStock, 'Default Low Stock Threshold',
                      hint: '5', type: TextInputType.number),
                  const SizedBox(height: 8),
                  Text('Loyalty Points', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  _f(_pointsPerUnit, 'Points earned per \$1 spent',
                      hint: '1', type: const TextInputType.numberWithOptions(decimal: true)),
                  _f(_pointsValue, 'Value of 1 point in \$',
                      hint: '0.01', type: const TextInputType.numberWithOptions(decimal: true)),
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
      final wid = WorkerService.workerId;
      if (wid == null) throw Exception('No worker logged in');
      await WorkerService.changePassword(wid, _newCtrl.text);
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
    final users = await WorkerService.listWorkers();
    setState(() { _users = users; _loading = false; });
  }

  Future<void> _delete(int id, String name) async {
    if (id == WorkerService.workerId) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Can't delete yourself.")));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Remove "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    await WorkerService.deleteWorker(id);
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
                    final username = u['username'] ?? '';
                    final id = (u['id'] as num).toInt();
                    final isMe = id == WorkerService.workerId;

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
                        subtitle: Text('@$username · $role'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.key_outlined),
                            tooltip: 'Reset Password',
                            onPressed: () => _showPasswordDialog(id, name),
                          ),
                          if (!isMe) ...[
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showEditDialog(u),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => _delete(id, name),
                            ),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Add Worker'),
        onPressed: _showAddDialog,
      ),
    );
  }

  void _showAddDialog() {
    final nameCtrl     = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passCtrl     = TextEditingController();
    String role = 'worker';
    bool saving = false;
    String? error;

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
              Text('Add Worker', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Display Name *'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Username *',
                  hintText: 'e.g. ram, worker1',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: 'Password *'),
                obscureText: true,
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
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
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
                    onPressed: saving ? null : () async {
                      if (nameCtrl.text.trim().isEmpty ||
                          usernameCtrl.text.trim().isEmpty ||
                          passCtrl.text.length < 4) {
                        setSheetState(() => error = 'Fill all fields. Password min 4 chars.');
                        return;
                      }
                      setSheetState(() { saving = true; error = null; });
                      try {
                        await WorkerService.createWorker(
                          username: usernameCtrl.text.trim(),
                          password: passCtrl.text,
                          displayName: nameCtrl.text.trim(),
                          role: role,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        _load();
                      } catch (e) {
                        setSheetState(() {
                          saving = false;
                          error = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
                    child: saving
                        ? const SizedBox(height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Create'),
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
    final id = (user['id'] as num).toInt();

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
                      await WorkerService.updateWorker(id,
                        displayName: nameCtrl.text.trim(),
                        role: role,
                      );
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

  void _showPasswordDialog(int id, String name) {
    final passCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reset Password', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('For: $name', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: passCtrl,
              decoration: const InputDecoration(labelText: 'New Password *'),
              obscureText: true,
            ),
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
                    if (passCtrl.text.length < 4) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Min 4 characters')),
                      );
                      return;
                    }
                    await WorkerService.changePassword(id, passCtrl.text);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Password reset for $name')),
                      );
                    }
                  },
                  child: const Text('Reset'),
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

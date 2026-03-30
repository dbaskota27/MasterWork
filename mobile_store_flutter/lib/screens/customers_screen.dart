import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import '../services/worker_service.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  late Future<List<Customer>> _future;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      setState(() => _future = DatabaseService.getCustomers());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search customers…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: _future,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }
                final customers = (snap.data ?? [])
                    .where((c) =>
                        c.name.toLowerCase().contains(_search) ||
                        (c.phone?.contains(_search) ?? false) ||
                        (c.email?.toLowerCase().contains(_search) ?? false))
                    .toList();

                if (customers.isEmpty) {
                  return const Center(child: Text('No customers found.'));
                }

                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (ctx, i) => _CustomerTile(
                      customer: customers[i],
                      onUpdated: _reload,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: WorkerService.isManager
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.person_add),
              label: const Text('Add Customer'),
              onPressed: () => _showForm(context),
            )
          : null,
    );
  }

  void _showForm(BuildContext context, {Customer? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerForm(
        existing: existing,
        onSaved: (c) async {
          if (existing == null) {
            await DatabaseService.addCustomer(c);
          } else {
            await DatabaseService.updateCustomer(existing.id, {
              'name': c.name,
              'phone': c.phone,
              'email': c.email,
            });
          }
          _reload();
        },
        onDelete: existing != null
            ? () async {
                await DatabaseService.deleteCustomer(existing.id);
                _reload();
              }
            : null,
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onUpdated;
  const _CustomerTile({required this.customer, required this.onUpdated});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(customer.name[0].toUpperCase())),
        title: Text(customer.name),
        subtitle: Text([
          if (customer.phone != null) customer.phone!,
          if (customer.email != null) customer.email!,
          '${customer.pointsBalance.toStringAsFixed(0)} pts',
        ].join(' · ')),
        onTap: WorkerService.isManager
            ? () => _showEdit(context)
            : null,
      ),
    );
  }

  void _showEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomerForm(
        existing: customer,
        onSaved: (c) async {
          await DatabaseService.updateCustomer(customer.id, {
            'name': c.name,
            'phone': c.phone,
            'email': c.email,
          });
          onUpdated();
        },
        onDelete: () async {
          await DatabaseService.deleteCustomer(customer.id);
          onUpdated();
        },
      ),
    );
  }
}

class _CustomerForm extends StatefulWidget {
  final Customer? existing;
  final Future<void> Function(Customer) onSaved;
  final Future<void> Function()? onDelete;
  const _CustomerForm(
      {this.existing, required this.onSaved, this.onDelete});

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _name, _phone, _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _email = TextEditingController(text: widget.existing?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final c = Customer(
      id: widget.existing?.id ?? 0,
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
    );
    try {
      await widget.onSaved(c);
      if (mounted) Navigator.pop(context);
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
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.existing == null ? 'Add Customer' : 'Edit Customer',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            Row(children: [
              if (widget.onDelete != null)
                IconButton.filled(
                  icon: const Icon(Icons.delete_outline),
                  style:
                      IconButton.styleFrom(backgroundColor: Colors.red.shade50),
                  color: Colors.red,
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Delete Customer?'),
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
                    if (ok == true) {
                      await widget.onDelete!();
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
              const Spacer(),
              OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ]),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

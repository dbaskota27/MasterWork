import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'store_setup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      await AuthService.login(email: email, password: password);

      if (!mounted) return;

      // No store linked yet? → store setup
      if (AuthService.storeId == null) {
        _goTo(const StoreSetupScreen());
        return;
      }

      _goTo(const HomeScreen());
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _friendlyError(e.toString());
      });
    }
  }

  void _goTo(Widget screen) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  String _friendlyError(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('invalid login') || lower.contains('invalid credentials')) {
      return 'Invalid email or password.';
    }
    if (lower.contains('email not confirmed') || lower.contains('email_not_confirmed')) {
      return 'Email not confirmed. Check your inbox or ask admin to confirm your account.';
    }
    if (lower.contains('network') || lower.contains('socket')) {
      return 'No internet connection.';
    }
    // Show actual error for debugging
    return 'Login failed: $msg';
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email first, then tap Forgot Password.')),
      );
      return;
    }
    try {
      await AuthService.sendPasswordReset(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset link sent to $email')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.storefront_rounded,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text('Mobile Store',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Sign in to your account',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6))),
                    const SizedBox(height: 28),

                    // Email
                    TextField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _forgotPassword,
                        child: const Text('Forgot Password?', style: TextStyle(fontSize: 13)),
                      ),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(_error!,
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
                    ],

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Sign In'),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      'Contact admin for account access.',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

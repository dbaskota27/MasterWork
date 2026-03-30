import 'package:flutter/material.dart';
import '../config.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import 'login_screen.dart';
import 'home_screen.dart';

class SubscriptionWallScreen extends StatelessWidget {
  const SubscriptionWallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = SubscriptionService.status;

    final title = status == SubStatus.suspended
        ? 'Account Suspended'
        : 'Subscription Expired';

    final message = status == SubStatus.suspended
        ? 'Your account has been suspended. Please contact support to resolve this.'
        : 'Your free trial or subscription has ended.\n'
            'Contact us to activate your account and continue using the app.';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status == SubStatus.suspended
                      ? Icons.block
                      : Icons.hourglass_bottom,
                  size: 80,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(height: 20),
                Text(title,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 14)),
                const SizedBox(height: 32),

                // Contact info
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Contact Support',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.phone, size: 18, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(AppConfig.supportPhone),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.email_outlined, size: 18, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(AppConfig.supportEmail),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Retry button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check Again'),
                    onPressed: () async {
                      await SubscriptionService.check();
                      if (SubscriptionService.isActive && context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                        );
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Subscription is still inactive.')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  onPressed: () async {
                    await AuthService.logout();
                    if (context.mounted) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

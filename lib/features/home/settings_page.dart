import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_prefs.dart';
import '../../core/auth_service.dart';
import '../../core/navigation.dart';
import '../welcome/welcome_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _logout(BuildContext context) async {
    final guest = await AppPrefs.isGuest();
    if (guest) {
      await AppPrefs.setGuest(false);
      if (!context.mounted) return;
      Navigator.of(context)
          .pushAndRemoveUntil(fadeRoute(const WelcomePage()), (_) => false);
      return;
    }
    try {
      await AuthService.signOut();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not log out: $error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name =
        user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(
            'Your account',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.person_outline_rounded),
              ),
              title: Text(
                name?.isNotEmpty == true
                    ? name!
                    : (user?.email == null ? 'Guest mode' : 'CampusFlow user'),
              ),
              subtitle: Text(
                user?.email ??
                    'Your favourites and alerts are stored on this device.',
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Card(
            elevation: 0,
            child: ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('CampusFlow'),
              subtitle: Text('Live campus crowd information'),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: Text(user == null ? 'Leave guest mode' : 'Log out'),
          ),
        ],
      ),
    );
  }
}

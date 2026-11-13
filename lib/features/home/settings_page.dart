import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_prefs.dart';
import '../../core/auth_service.dart';
import '../../core/navigation.dart';
import '../../widgets/app_logo.dart';
import '../welcome/welcome_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<Map<String, dynamic>?> _profile = _loadProfile();
  bool _saving = false;

  Future<Map<String, dynamic>?> _loadProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    return Supabase.instance.client
        .from('profiles')
        .select('full_name,role')
        .eq('id', user.id)
        .maybeSingle();
  }

  Future<void> _editName(String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'full_name': name})
          .eq('id', user.id);
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'full_name': name}),
      );
      if (mounted) {
        setState(() {
          _saving = false;
          _profile = _loadProfile();
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update profile: $error')),
      );
    }
  }

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
    final metadataName =
        user?.userMetadata?['full_name']?.toString() ??
        user?.userMetadata?['name']?.toString();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final name =
              (profile?['full_name']?.toString().trim().isNotEmpty == true)
              ? profile!['full_name'].toString()
              : (metadataName?.trim().isNotEmpty == true
                    ? metadataName!
                    : 'CampusFlow member');
          final role =
              profile?['role']?.toString() ??
              (user == null ? 'Guest' : 'Student');
          final provider = user?.appMetadata['provider']?.toString() ?? 'Email';
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF102E40), Color(0xFF147D7A)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    const AppLogo(size: 72),
                    const SizedBox(height: 13),
                    Text(
                      name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? 'Guest mode · saved on this device',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        role.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Account',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: const Text('Display name'),
                      subtitle: Text(name),
                      trailing: user == null
                          ? null
                          : IconButton(
                              tooltip: 'Edit name',
                              onPressed: _saving ? null : () => _editName(name),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.edit_outlined),
                            ),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.alternate_email_rounded),
                      title: const Text('Email'),
                      subtitle: Text(user?.email ?? 'Not signed in'),
                    ),
                    if (user != null) ...[
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(
                          provider == 'google'
                              ? Icons.g_mobiledata_rounded
                              : Icons.verified_user_outlined,
                          size: 26,
                        ),
                        title: const Text('Sign-in method'),
                        subtitle: Text(
                          provider == 'google'
                              ? 'Google'
                              : 'Email and password',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'CampusFlow',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Card(
                elevation: 0,
                child: ListTile(
                  leading: Icon(Icons.sensors_outlined),
                  title: Text('Campus modules'),
                  subtitle: Text('Lift Lobby · Cafeteria · Parking'),
                ),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => _logout(context),
                icon: const Icon(Icons.logout_rounded),
                label: Text(user == null ? 'Leave guest mode' : 'Log out'),
              ),
            ],
          );
        },
      ),
    );
  }
}


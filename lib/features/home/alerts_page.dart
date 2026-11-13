import 'package:flutter/material.dart';

import '../../core/alert_engine.dart';
import 'campus_data.dart';
import 'sheets.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});
  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  Future<void> _reload() async {
    await AlertEngine.instance.refreshRules();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Alerts'),
      actions: [
        IconButton(
          tooltip: 'Add alert',
          onPressed: () async {
            await showAlertEditorSheet(context);
            if (mounted) setState(() {});
          },
          icon: const Icon(Icons.add_alert_rounded),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<dynamic>>(
        future: Future.wait([
          CampusRepository.instance.loadAlerts(),
          CampusRepository.instance.loadAlertHistory(),
          CampusRepository.instance.loadZones(),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 100),
                Center(
                  child: Text('Could not load alerts. Pull down to retry.'),
                ),
              ],
            );
          }
          final alerts = snapshot.data?[0] as List<CampusAlert>? ?? const [];
          final history =
              snapshot.data?[1] as List<AlertHistoryItem>? ?? const [];
          final zones = snapshot.data?[2] as List<CampusZone>? ?? const [];
          final names = {for (final zone in zones) zone.id: zone.name};
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              Text(
                'My alerts',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Get a notification when a place changes.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (alerts.isEmpty)
                _EmptyAlerts(
                  onAdd: () async {
                    await showAlertEditorSheet(context);
                    if (mounted) setState(() {});
                  },
                )
              else
                ...alerts.map(
                  (alert) => Dismissible(
                    key: ValueKey(alert.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 18),
                      margin: const EdgeInsets.only(bottom: 9),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    onDismissed: (_) async {
                      await CampusRepository.instance.deleteAlert(alert);
                      await AlertEngine.instance.refreshRules();
                      if (mounted) setState(() {});
                    },
                    child: Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .45),
                      child: ListTile(
                        onTap: () async {
                          final zone = zones.cast<CampusZone?>().firstWhere(
                            (item) => item?.id == alert.zoneId,
                            orElse: () => null,
                          );
                          await showAlertEditorSheet(
                            context,
                            zone: zone,
                            alert: alert,
                          );
                          if (mounted) setState(() {});
                        },
                        title: Text(
                          names[alert.zoneId] ?? 'Campus place',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(_conditionText(alert)),
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        trailing: Switch(
                          value: alert.active,
                          onChanged: (value) async {
                            await CampusRepository.instance.setAlertActive(
                              alert,
                              value,
                            );
                            await AlertEngine.instance.refreshRules();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'History',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (history.isEmpty)
                const Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(Icons.history_rounded),
                    title: Text('No notifications yet'),
                    subtitle: Text(
                      'Triggered alert notifications will appear here.',
                    ),
                  ),
                )
              else
                ...history.map(
                  (item) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const CircleAvatar(
                      child: Icon(Icons.notifications_rounded),
                    ),
                    title: Text(item.zoneName),
                    subtitle: Text(item.message),
                    trailing: Text(
                      _timeAgo(item.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.notifications_none_rounded, size: 38),
          const SizedBox(height: 8),
          const Text('No alerts set up yet'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Create an alert'),
          ),
        ],
      ),
    ),
  );
}

String _conditionText(CampusAlert alert) => switch (alert.condition) {
  'wait_below' =>
    'Notify when wait is below ${alert.threshold?.toStringAsFixed(0) ?? '—'} min',
  'crowd_above' =>
    'Notify when crowd is above ${alert.threshold?.toStringAsFixed(0) ?? '—'}%',
  _ => 'Notify when the place becomes quiet',
};
String _timeAgo(DateTime time) {
  final d = DateTime.now().difference(time);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

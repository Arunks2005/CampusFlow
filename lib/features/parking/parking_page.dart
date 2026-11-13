import 'dart:async';

import 'package:flutter/material.dart';

import 'parking_repository.dart';

class ParkingPage extends StatefulWidget {
  const ParkingPage({super.key});

  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> {
  final _repository = ParkingRepository.instance;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  List<ParkingLot> _lots = const [];
  List<ParkingSession> _sessions = const [];
  List<ParkingEvent> _events = const [];
  bool _loading = true;
  bool _admin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _subscription = _repository.watchLots().listen(
      (_) => _load(),
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final isAdmin = await _repository.isAdmin();
      final lots = await _repository.loadLots();
      final sessions = isAdmin
          ? await _repository.loadActiveSessions()
          : <ParkingSession>[];
      final events = isAdmin
          ? await _repository.loadRecentEvents()
          : <ParkingEvent>[];
      if (!mounted) return;
      setState(() {
        _admin = isAdmin;
        _lots = lots;
        _sessions = sessions;
        _events = events;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Parking information could not be loaded. Check your connection and try again.';
      });
      debugPrint('Parking data load failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Parking')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  Text(
                    'Parking at a glance',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Check space availability before arriving.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_lots.isEmpty)
                    const _EmptyParking()
                  else
                    for (final lot in _lots) ...[
                      _LotCard(lot: lot),
                      const SizedBox(height: 12),
                    ],
                  if (_admin) ...[
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: 'Vehicles currently parked',
                      trailing: '${_sessions.length}',
                    ),
                    const SizedBox(height: 8),
                    if (_sessions.isEmpty)
                      const _InfoCard(
                        text: 'No active vehicle sessions yet. Plate records will appear after the entry camera confirms a plate.',
                      ),
                    for (final session in _sessions)
                      Card(
                        elevation: 0,
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.directions_car_outlined),
                          ),
                          title: Text(
                            session.plate,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          subtitle: Text(
                            'Entered ${_timeLabel(session.enteredAt)} · ${session.lotId}',
                          ),
                          trailing: Text(
                            '${(session.confidence * 100).round()}%',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                      ),
                    const SizedBox(height: 14),
                    const _SectionHeader(title: 'Recent camera activity'),
                    const SizedBox(height: 8),
                    if (_events.isEmpty)
                      const _InfoCard(
                        text: 'Camera detections will appear here after the scanner is configured.',
                      ),
                    for (final event in _events.take(8))
                      Card(
                        elevation: 0,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            event.eventType == 'entry'
                                ? Icons.login_rounded
                                : Icons.logout_rounded,
                          ),
                          title: Text(
                            '${event.plate} · ${event.eventType.toUpperCase()}',
                          ),
                          subtitle: Text(
                            '${_timeLabel(event.detectedAt)} · ${(event.confidence * 100).round()}% OCR confidence',
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Plate numbers are shown only to administrators.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    const _InfoCard(
                      text: 'Availability is public. Vehicle plate numbers and visit history are restricted to administrators.',
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _LotCard extends StatelessWidget {
  const _LotCard({required this.lot});
  final ParkingLot lot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = lot.capacity == 0
        ? 0.0
        : (lot.currentVehicles / lot.capacity).clamp(0.0, 1.0).toDouble();
    final recent =
        DateTime.now().difference(lot.updatedAt) < const Duration(minutes: 2);
    final spaces = (lot.capacity - lot.currentVehicles).clamp(0, lot.capacity);
    final color = fill >= .9
        ? theme.colorScheme.error
        : fill >= .7
        ? const Color(0xFFCB861A)
        : theme.colorScheme.primary;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(Icons.local_parking_rounded, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lot.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (lot.location.isNotEmpty)
                        Text(
                          lot.location,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (recent
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surfaceContainerHighest)
                            .withValues(alpha: recent ? .1 : 1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    recent ? 'LIVE' : 'UPDATED ${_age(lot.updatedAt)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: recent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$spaces',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(width: 7),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'spaces available',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${lot.currentVehicles} / ${lot.capacity}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 9,
                color: color,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      if (trailing != null)
        Text(trailing!, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

class _EmptyParking extends StatelessWidget {
  const _EmptyParking();
  @override
  Widget build(BuildContext context) => const _InfoCard(
    text: 'No parking lots are configured yet. Add a lot in Supabase to show live availability here.',
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

String _timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String _age(DateTime time) {
  if (time.millisecondsSinceEpoch == 0) return '—';
  final mins = DateTime.now().difference(time).inMinutes;
  if (mins < 1) return 'just now';
  if (mins < 60) return '${mins}m ago';
  return '${mins ~/ 60}h ago';
}


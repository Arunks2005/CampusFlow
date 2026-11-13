import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/home/campus_data.dart';

/// Watches live rows while the app is open and fires local alerts on crossings.
/// Alert history is device-local; alert rules remain per-user in Supabase, or
/// on-device for guests.
class AlertEngine {
  AlertEngine._();

  static final AlertEngine instance = AlertEngine._();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final CampusRepository _repository = CampusRepository.instance;

  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _liveSubscription;
  final Map<String, ZoneReading> _previousByZone = {};
  List<CampusAlert> _rules = const [];
  Map<String, CampusZone> _zonesById = const {};
  bool _hasBaseline = false;
  bool _initialized = false;
  int _ruleLoadVersion = 0;

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(settings: settings);
    _initialized = true;
  }

  void start() {
    _authSubscription?.cancel();
    _liveSubscription?.cancel();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => unawaited(refreshRules()),
      onError: (Object error) =>
          debugPrint('Alert auth listener error: $error'),
    );
    unawaited(_loadZones());
    unawaited(refreshRules());
    _liveSubscription = _repository.watchLiveZones().listen(
      (rows) => _consumeLiveRows(rows),
      onError: (Object error) =>
          debugPrint('Alert live listener error: $error'),
    );
  }

  Future<bool> requestPermission() async {
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  Future<void> refreshRules() async {
    final version = ++_ruleLoadVersion;
    try {
      final rules = await _repository.loadAlerts();
      if (version == _ruleLoadVersion) _rules = rules;
    } catch (error) {
      debugPrint('Could not refresh alert rules: $error');
    }
  }

  Future<void> _loadZones() async {
    try {
      final zones = await _repository.loadZones();
      _zonesById = {for (final zone in zones) zone.id: zone};
    } catch (error) {
      debugPrint('Could not load alert zone names: $error');
    }
  }

  void _consumeLiveRows(List<Map<String, dynamic>> rows) {
    final current = <String, ZoneReading>{};
    for (final row in rows) {
      if (row['zone_id'] == null) continue;
      final map = Map<String, dynamic>.from(row);
      final reading = ZoneReading.fromMap(map);
      current[reading.zoneId] = reading;
    }

    if (!_hasBaseline) {
      _previousByZone
        ..clear()
        ..addAll(current);
      _hasBaseline = true;
      return;
    }

    final triggered = <CampusAlert>[];
    for (final entry in current.entries) {
      final previous = _previousByZone[entry.key];
      final next = entry.value;
      if (previous == null) continue;
      for (final rule in _rules) {
        if (rule.active &&
            rule.zoneId == entry.key &&
            _crossed(rule, previous, next)) {
          triggered.add(rule);
        }
      }
    }

    _previousByZone
      ..clear()
      ..addAll(current);

    for (final rule in triggered) {
      unawaited(_notify(rule));
    }
  }

  bool _crossed(CampusAlert rule, ZoneReading previous, ZoneReading next) {
    final threshold = rule.threshold;
    switch (rule.condition) {
      case 'wait_below':
        return threshold != null &&
            previous.waitMinutes >= threshold &&
            next.waitMinutes < threshold;
      case 'becomes_quiet':
        return previous.level != 'quiet' && next.level == 'quiet';
      case 'crowd_above':
        if (threshold == null) return false;
        final capacity = _zonesById[rule.zoneId]?.capacity ?? 0;
        if (capacity <= 0) return false;
        final oldPercent = previous.count * 100 / capacity;
        final newPercent = next.count * 100 / capacity;
        return oldPercent < threshold && newPercent >= threshold;
      default:
        return false;
    }
  }

  Future<void> _notify(CampusAlert rule) async {
    final zoneName = _zonesById[rule.zoneId]?.name ?? 'A campus place';
    final threshold = rule.threshold;
    final message = switch (rule.condition) {
      'wait_below' =>
        'The estimated wait at $zoneName is now under ${_format(threshold)} min.',
      'becomes_quiet' => '$zoneName is quiet now.',
      'crowd_above' => 'Crowd at $zoneName has reached ${_format(threshold)}%.',
      _ => 'There is a new update for $zoneName.',
    };

    final item = AlertHistoryItem(
      title: 'CampusFlow alert',
      message: message,
      zoneName: zoneName,
      createdAt: DateTime.now(),
    );
    try {
      await _repository.addAlertHistory(item);
      await _notifications.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title: item.title,
        body: message,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'campusflow_alerts',
            'Campus alerts',
            channelDescription: 'Updates for the campus places you follow.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      debugPrint('Could not show local campus alert: $error');
    }
  }

  String _format(double? value) {
    if (value == null) return '—';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

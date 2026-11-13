import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CampusZone {
  const CampusZone({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    required this.capacity,
    required this.amberPercent,
    required this.redPercent,
  });

  final String id;
  final String name;
  final String type;
  final String location;
  final int capacity;
  final int amberPercent;
  final int redPercent;

  bool get isCafeteria => type == 'cafeteria';

  factory CampusZone.fromMap(Map<String, dynamic> row) => CampusZone(
    id: row['id'].toString(),
    name: row['name']?.toString() ?? 'Campus place',
    type: row['type']?.toString() ?? '',
    location: row['location']?.toString() ?? '',
    capacity: _asInt(row['capacity']),
    amberPercent: _asInt(row['amber_pct'], fallback: 50),
    redPercent: _asInt(row['red_pct'], fallback: 80),
  );
}

class ZoneReading {
  const ZoneReading({
    required this.zoneId,
    required this.count,
    required this.queueLength,
    required this.waitMinutes,
    required this.level,
    required this.updatedAt,
  });

  final String zoneId;
  final int count;
  final int queueLength;
  final double waitMinutes;
  final String level;
  final DateTime updatedAt;

  factory ZoneReading.fromMap(Map<String, dynamic> row) => ZoneReading(
    zoneId: row['zone_id'].toString(),
    count: _asInt(row['count']),
    queueLength: _asInt(row['queue_len']),
    waitMinutes: _asDouble(row['est_wait_min']),
    level: row['level']?.toString() ?? 'quiet',
    updatedAt:
        DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class CampusAlert {
  const CampusAlert({
    required this.id,
    required this.zoneId,
    required this.condition,
    required this.active,
    this.threshold,
  });

  final String id;
  final String zoneId;
  final String condition;
  final bool active;
  final double? threshold;

  CampusAlert copyWith({bool? active}) => CampusAlert(
    id: id,
    zoneId: zoneId,
    condition: condition,
    active: active ?? this.active,
    threshold: threshold,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'zone_id': zoneId,
    'condition': condition,
    'threshold': threshold,
    'active': active,
  };

  factory CampusAlert.fromMap(Map<String, dynamic> row) => CampusAlert(
    id: row['id'].toString(),
    zoneId: row['zone_id'].toString(),
    condition: row['condition']?.toString() ?? 'becomes_quiet',
    threshold: row['threshold'] == null ? null : _asDouble(row['threshold']),
    active: row['active'] == true,
  );
}

class AlertHistoryItem {
  const AlertHistoryItem({
    required this.title,
    required this.message,
    required this.zoneName,
    required this.createdAt,
  });

  final String title;
  final String message;
  final String zoneName;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'title': title,
    'message': message,
    'zone_name': zoneName,
    'created_at': createdAt.toIso8601String(),
  };

  factory AlertHistoryItem.fromMap(Map<String, dynamic> row) =>
      AlertHistoryItem(
        title: row['title']?.toString() ?? 'CampusFlow alert',
        message: row['message']?.toString() ?? '',
        zoneName: row['zone_name']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class ForecastEstimate {
  const ForecastEstimate({
    required this.time,
    required this.averageCount,
    required this.averageWait,
    required this.samples,
  });

  final DateTime time;
  final double averageCount;
  final double averageWait;
  final int samples;

  double occupancy(int capacity) =>
      capacity <= 0 ? 0 : (averageCount / capacity).clamp(0.0, 1.0).toDouble();
}

class CampusRepository {
  CampusRepository._();

  static final CampusRepository instance = CampusRepository._();
  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;
  bool get isGuest => _userId == null;

  static const _guestFavouritesKey = 'campusflow_module3_guest_favourites';
  static const _guestAlertsKey = 'campusflow_module3_guest_alerts';

  Future<List<CampusZone>> loadZones() async {
    final rows = await _client
        .from('zones')
        .select('id,name,type,location,capacity,amber_pct,red_pct,active')
        .eq('active', true)
        .order('name');
    return rows
        .map((row) => CampusZone.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Stream<List<Map<String, dynamic>>> watchLiveZones() =>
      _client.from('zone_live').stream(primaryKey: ['zone_id']);

  /// REST snapshot fallback for devices where the Realtime websocket is
  /// blocked or delayed. `zone_live` has one current row per zone.
  Future<List<ZoneReading>> loadLiveZones() async {
    final rows = await _client
        .from('zone_live')
        .select('zone_id,count,queue_len,est_wait_min,level,updated_at');
    return rows
        .map((row) => ZoneReading.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ZoneReading>> loadReadings(String zoneId, {int days = 14}) async {
    final since = DateTime.now().toUtc().subtract(Duration(days: days));
    final rows = await _client
        .from('readings')
        .select('zone_id,ts,count,queue_len,est_wait_min,level')
        .eq('zone_id', zoneId)
        .gte('ts', since.toIso8601String())
        .order('ts');
    return rows
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          map['updated_at'] = map['ts'];
          return ZoneReading.fromMap(map);
        })
        .toList(growable: false);
  }

  Future<Set<String>> loadFavouriteIds() async {
    final userId = _userId;
    if (userId == null) {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_guestFavouritesKey) ?? <String>[]).toSet();
    }

    final rows = await _client
        .from('favourites')
        .select('zone_id')
        .eq('user_id', userId);
    return rows.map((row) => row['zone_id'].toString()).toSet();
  }

  Future<void> setFavourite(String zoneId, bool favourite) async {
    final userId = _userId;
    if (userId == null) {
      final prefs = await SharedPreferences.getInstance();
      final current = (prefs.getStringList(_guestFavouritesKey) ?? <String>[])
          .toSet();
      if (favourite) {
        current.add(zoneId);
      } else {
        current.remove(zoneId);
      }
      await prefs.setStringList(_guestFavouritesKey, current.toList()..sort());
      return;
    }

    if (favourite) {
      await _client.from('favourites').insert({'zone_id': zoneId});
    } else {
      await _client
          .from('favourites')
          .delete()
          .eq('user_id', userId)
          .eq('zone_id', zoneId);
    }
  }

  Future<List<CampusAlert>> loadAlerts() async {
    final userId = _userId;
    if (userId == null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_guestAlertsKey);
      if (raw == null) return const [];
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (row) => CampusAlert.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
    }

    final rows = await _client
        .from('alert_rules')
        .select('id,zone_id,condition,threshold,active,created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows
        .map((row) => CampusAlert.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<CampusAlert> saveAlert({
    required String? id,
    required String zoneId,
    required String condition,
    required double? threshold,
    required bool active,
  }) async {
    final userId = _userId;
    if (userId == null) {
      final current = await loadAlerts();
      final nextId = id ?? 'guest-${DateTime.now().microsecondsSinceEpoch}';
      final item = CampusAlert(
        id: nextId,
        zoneId: zoneId,
        condition: condition,
        threshold: threshold,
        active: active,
      );
      final updated = [
        for (final alert in current)
          if (alert.id != nextId) alert,
        item,
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _guestAlertsKey,
        jsonEncode(updated.map((alert) => alert.toJson()).toList()),
      );
      return item;
    }

    final values = <String, dynamic>{
      'zone_id': zoneId,
      'condition': condition,
      'threshold': threshold,
      'active': active,
    };
    if (id == null) {
      final row = await _client
          .from('alert_rules')
          .insert(values)
          .select('id,zone_id,condition,threshold,active')
          .single();
      return CampusAlert.fromMap(Map<String, dynamic>.from(row));
    }

    final row = await _client
        .from('alert_rules')
        .update(values)
        .eq('id', id)
        .eq('user_id', userId)
        .select('id,zone_id,condition,threshold,active')
        .single();
    return CampusAlert.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> setAlertActive(CampusAlert alert, bool active) async {
    final userId = _userId;
    if (userId == null) {
      final current = await loadAlerts();
      final updated = current
          .map(
            (item) =>
                item.id == alert.id ? item.copyWith(active: active) : item,
          )
          .toList(growable: false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _guestAlertsKey,
        jsonEncode(updated.map((item) => item.toJson()).toList()),
      );
      return;
    }
    await _client
        .from('alert_rules')
        .update({'active': active})
        .eq('id', alert.id)
        .eq('user_id', userId);
  }

  Future<void> deleteAlert(CampusAlert alert) async {
    final userId = _userId;
    if (userId == null) {
      final current = await loadAlerts();
      final updated = current.where((item) => item.id != alert.id).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _guestAlertsKey,
        jsonEncode(updated.map((item) => item.toJson()).toList()),
      );
      return;
    }
    await _client
        .from('alert_rules')
        .delete()
        .eq('id', alert.id)
        .eq('user_id', userId);
  }

  Future<List<AlertHistoryItem>> loadAlertHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _historyKey;
    final raw = prefs.getString(key);
    if (raw == null) return const [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
          (row) =>
              AlertHistoryItem.fromMap(Map<String, dynamic>.from(row as Map)),
        )
        .toList(growable: false);
  }

  Future<void> addAlertHistory(AlertHistoryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadAlertHistory();
    final updated = [item, ...current].take(100).toList(growable: false);
    await prefs.setString(
      _historyKey,
      jsonEncode(updated.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> submitReport({
    required String? zoneId,
    required String reason,
    required String? comment,
  }) async {
    await _client.from('reports').insert({
      'zone_id': zoneId,
      'reason': reason,
      'comment': comment?.trim().isEmpty == true ? null : comment?.trim(),
    });
  }

  String get _historyKey =>
      'campusflow_module3_alert_history_${_userId ?? 'guest'}';
}

List<ForecastEstimate> forecastForZone(
  CampusZone zone,
  List<ZoneReading> history, {
  DateTime? from,
  int hours = 2,
}) {
  final now = from ?? DateTime.now();
  final forecasts = <ForecastEstimate>[];

  for (var offset = 1; offset <= hours; offset++) {
    final target = now.add(Duration(hours: offset));
    final samples = history
        .where((reading) {
          final time = reading.updatedAt;
          return time.isBefore(now) &&
              time.weekday == target.weekday &&
              time.hour == target.hour;
        })
        .toList(growable: false);
    if (samples.isEmpty) continue;

    final averageCount =
        samples.fold<double>(0, (sum, sample) => sum + sample.count) /
        samples.length;
    final averageWait =
        samples.fold<double>(0, (sum, sample) => sum + sample.waitMinutes) /
        samples.length;
    forecasts.add(
      ForecastEstimate(
        time: target,
        averageCount: averageCount,
        averageWait: averageWait,
        samples: samples.length,
      ),
    );
  }

  return forecasts;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

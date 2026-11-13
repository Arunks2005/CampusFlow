import 'package:supabase_flutter/supabase_flutter.dart';

class ParkingLot {
  const ParkingLot({
    required this.id,
    required this.name,
    required this.location,
    required this.capacity,
    required this.currentVehicles,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String location;
  final int capacity;
  final int currentVehicles;
  final DateTime updatedAt;

  factory ParkingLot.fromMap(Map<String, dynamic> row) => ParkingLot(
    id: row['id'].toString(),
    name: row['name']?.toString() ?? 'Campus parking',
    location: row['location']?.toString() ?? '',
    capacity: (row['capacity'] as num?)?.toInt() ?? 0,
    currentVehicles: (row['current_vehicles'] as num?)?.toInt() ?? 0,
    updatedAt:
        DateTime.tryParse(row['updated_at']?.toString() ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class ParkingSession {
  const ParkingSession({
    required this.id,
    required this.plate,
    required this.lotId,
    required this.enteredAt,
    required this.confidence,
  });

  final int id;
  final String plate;
  final String lotId;
  final DateTime enteredAt;
  final double confidence;

  factory ParkingSession.fromMap(Map<String, dynamic> row) => ParkingSession(
    id: (row['id'] as num).toInt(),
    plate: row['plate_number'].toString(),
    lotId: row['lot_id'].toString(),
    enteredAt: DateTime.parse(row['entered_at'].toString()).toLocal(),
    confidence: (row['entry_confidence'] as num?)?.toDouble() ?? 0,
  );
}

class ParkingEvent {
  const ParkingEvent({
    required this.plate,
    required this.eventType,
    required this.detectedAt,
    required this.confidence,
  });

  final String plate;
  final String eventType;
  final DateTime detectedAt;
  final double confidence;

  factory ParkingEvent.fromMap(Map<String, dynamic> row) => ParkingEvent(
    plate: row['plate_number'].toString(),
    eventType: row['event_type'].toString(),
    detectedAt: DateTime.parse(row['detected_at'].toString()).toLocal(),
    confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
  );
}

class ParkingRepository {
  ParkingRepository._();
  static final instance = ParkingRepository._();

  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  Future<List<ParkingLot>> loadLots() async {
    final rows = await _client
        .from('parking_lots')
        .select('id,name,location,capacity,current_vehicles,updated_at')
        .eq('active', true)
        .order('name');
    return rows
        .map((row) => ParkingLot.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Stream<List<Map<String, dynamic>>> watchLots() =>
      _client.from('parking_lots').stream(primaryKey: ['id']);

  Future<bool> isAdmin() async {
    final id = _userId;
    if (id == null) return false;
    final row = await _client
        .from('profiles')
        .select('role')
        .eq('id', id)
        .maybeSingle();
    return row?['role'] == 'admin';
  }

  Future<List<ParkingSession>> loadActiveSessions() async {
    final rows = await _client
        .from('parking_sessions')
        .select('id,lot_id,plate_number,entered_at,entry_confidence')
        .isFilter('exited_at', null)
        .order('entered_at', ascending: false);
    return rows
        .map((row) => ParkingSession.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<ParkingEvent>> loadRecentEvents() async {
    final rows = await _client
        .from('parking_events')
        .select('plate_number,event_type,detected_at,confidence')
        .order('detected_at', ascending: false)
        .limit(20);
    return rows
        .map((row) => ParkingEvent.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }
}


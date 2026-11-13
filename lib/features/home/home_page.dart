import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_theme.dart';
import '../../core/crowd_level.dart';
import '../../widgets/app_logo.dart';
import 'campus_data.dart';
import 'sheets.dart';
import 'zone_detail_page.dart';

enum _PlaceFilter { all, cafeteria, lifts, favourites }

enum _SortMode { recommended, shortestWait, leastBusy, name }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _repository = CampusRepository.instance;
  final _search = TextEditingController();
  final Map<String, ZoneReading> _live = {};
  final Map<String, int> _trend = {};

  List<CampusZone> _zones = const [];
  Set<String> _favourites = <String>{};
  StreamSubscription<List<Map<String, dynamic>>>? _liveSubscription;
  Timer? _ageTimer;
  Timer? _livePollTimer;
  _PlaceFilter _filter = _PlaceFilter.all;
  _SortMode _sort = _SortMode.recommended;
  String _query = '';
  bool _loading = true;
  bool _streamError = false;
  bool _snapshotConnected = false;
  bool _livePollInProgress = false;
  String? _loadError;
  String? _busyFavourite;

  @override
  void initState() {
    super.initState();
    _loadPage();
    _listenForLiveData();
    unawaited(_refreshLiveSnapshot());
    _livePollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshLiveSnapshot());
    });
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _livePollTimer?.cancel();
    _liveSubscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPage() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final zones = await _repository.loadZones();
      final favourites = await _repository.loadFavouriteIds();
      if (!mounted) return;
      setState(() {
        _zones = zones;
        _favourites = favourites;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError =
            'Couldn’t load campus places. Check your connection and try again.';
      });
    }
  }

  void _listenForLiveData() {
    _liveSubscription?.cancel();
    _liveSubscription = _repository.watchLiveZones().listen(
      (rows) {
        final next = <String, ZoneReading>{};
        for (final row in rows) {
          if (row['zone_id'] == null) continue;
          final map = Map<String, dynamic>.from(row);
          final reading = ZoneReading.fromMap(map);
          next[reading.zoneId] = reading;
        }
        _applyLiveSnapshot(next, fromRealtime: true);
      },
      onError: (Object _) {
        if (mounted) setState(() => _streamError = true);
      },
    );
  }

  Future<void> _refreshLiveSnapshot() async {
    if (_livePollInProgress) return;
    _livePollInProgress = true;
    try {
      final readings = await _repository.loadLiveZones();
      final next = {for (final reading in readings) reading.zoneId: reading};
      _applyLiveSnapshot(next, fromRest: true);
    } catch (error) {
      debugPrint('Could not refresh live zone snapshot: $error');
      if (mounted) setState(() => _snapshotConnected = false);
    } finally {
      _livePollInProgress = false;
    }
  }

  void _applyLiveSnapshot(
    Map<String, ZoneReading> next, {
    bool fromRealtime = false,
    bool fromRest = false,
  }) {
    if (!mounted) return;
    setState(() {
      for (final entry in next.entries) {
        final previous = _live[entry.key];
        if (previous != null) {
          _trend[entry.key] = entry.value.count > previous.count
              ? 1
              : entry.value.count < previous.count
              ? -1
              : 0;
        }
      }
      _live
        ..clear()
        ..addAll(next);
      if (fromRealtime) _streamError = false;
      if (fromRest) _snapshotConnected = true;
    });
  }

  Future<void> _toggleFavourite(CampusZone zone) async {
    final wasFavourite = _favourites.contains(zone.id);
    setState(() => _busyFavourite = zone.id);
    try {
      await _repository.setFavourite(zone.id, !wasFavourite);
      if (!mounted) return;
      setState(() {
        if (wasFavourite) {
          _favourites.remove(zone.id);
        } else {
          _favourites.add(zone.id);
        }
        _busyFavourite = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyFavourite = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update favourites. Please try again.'),
        ),
      );
    }
  }

  Future<void> _openZone(CampusZone zone) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ZoneDetailPage(zone: zone)),
    );
  }

  List<CampusZone> get _visibleZones {
    final query = _query.trim().toLowerCase();
    final result = _zones.where((zone) {
      final typeMatches = switch (_filter) {
        _PlaceFilter.all => true,
        _PlaceFilter.cafeteria => zone.isCafeteria,
        _PlaceFilter.lifts => zone.type == 'lift',
        _PlaceFilter.favourites => _favourites.contains(zone.id),
      };
      final textMatches =
          query.isEmpty ||
          zone.name.toLowerCase().contains(query) ||
          zone.location.toLowerCase().contains(query);
      return typeMatches && textMatches;
    }).toList();

    result.sort((a, b) {
      final aReading = _live[a.id];
      final bReading = _live[b.id];
      switch (_sort) {
        case _SortMode.shortestWait:
          return (aReading?.waitMinutes ?? double.infinity).compareTo(
            bReading?.waitMinutes ?? double.infinity,
          );
        case _SortMode.leastBusy:
          final aFill = a.capacity == 0
              ? 1.0
              : (aReading?.count ?? a.capacity) / a.capacity;
          final bFill = b.capacity == 0
              ? 1.0
              : (bReading?.count ?? b.capacity) / b.capacity;
          return aFill.compareTo(bFill);
        case _SortMode.name:
          return a.name.compareTo(b.name);
        case _SortMode.recommended:
          final aScore = _isOffline(aReading) ? 2 : _levelRank(aReading?.level);
          final bScore = _isOffline(bReading) ? 2 : _levelRank(bReading?.level);
          final rank = aScore.compareTo(bScore);
          return rank == 0 ? a.name.compareTo(b.name) : rank;
      }
    });
    return result;
  }

  List<CampusZone> get _quickSuggestions {
    final options =
        _zones.where((zone) {
          final reading = _live[zone.id];
          return reading != null && !_isOffline(reading);
        }).toList()..sort(
          (a, b) => (_live[a.id]?.waitMinutes ?? 999).compareTo(
            _live[b.id]?.waitMinutes ?? 999,
          ),
        );
    return options.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Text('CampusFlow'),
          ],
        ),
        actions: [
          PopupMenuButton<_SortMode>(
            tooltip: 'Sort places',
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _SortMode.recommended,
                child: Text('Recommended'),
              ),
              PopupMenuItem(
                value: _SortMode.shortestWait,
                child: Text('Shortest wait'),
              ),
              PopupMenuItem(
                value: _SortMode.leastBusy,
                child: Text('Least busy'),
              ),
              PopupMenuItem(value: _SortMode.name, child: Text('Name A–Z')),
            ],
            icon: const Icon(Icons.sort_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _HomeLoadError(message: _loadError!, retry: _loadPage)
          : RefreshIndicator(
              onRefresh: _loadPage,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text(
                    'See the crowd before you go',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _greeting(),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _CampusSummary(
                    zones: _zones,
                    readings: _live,
                    streamError: _streamError && !_snapshotConnected,
                  ),
                  if (_quickSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    _SectionTitle(
                      title: 'Shortest wait right now',
                      subtitle: 'A quick pick for your next stop',
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 112,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickSuggestions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final zone = _quickSuggestions[index];
                          final reading = _live[zone.id]!;
                          return _SuggestionCard(
                            zone: zone,
                            reading: reading,
                            onTap: () => _openZone(zone),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 26),
                  TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search cafeteria, lift or building',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FilterRow(
                    selected: _filter,
                    onSelect: (filter) => setState(() => _filter = filter),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _SectionTitle(
                          title: 'Campus places',
                          subtitle: '${_visibleZones.length} places',
                        ),
                      ),
                      _LiveStatus(offline: _streamError && !_snapshotConnected),
                    ],
                  ),
                  if (_visibleZones.isEmpty)
                    const _NoPlaces()
                  else
                    for (final zone in _visibleZones) ...[
                      const SizedBox(height: 12),
                      _ZoneCard(
                        zone: zone,
                        reading: _live[zone.id],
                        trend: _trend[zone.id] ?? 0,
                        favourite: _favourites.contains(zone.id),
                        favouriteBusy: _busyFavourite == zone.id,
                        onTap: () => _openZone(zone),
                        onFavourite: () => _toggleFavourite(zone),
                        onAlert: () =>
                            showAlertEditorSheet(context, zone: zone),
                      ),
                    ],
                  const SizedBox(height: 14),
                  Text(
                    'Crowd levels use anonymous sensor counts.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _greeting() {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata;
    final name = metadata?['full_name'] ?? metadata?['name'];
    final display = name is String && name.trim().isNotEmpty
        ? name.trim().split(RegExp(r'\s+')).first
        : 'there';
    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return '$timeGreeting, $display. Find a place that suits you.';
  }
}

class _CampusSummary extends StatelessWidget {
  const _CampusSummary({
    required this.zones,
    required this.readings,
    required this.streamError,
  });
  final List<CampusZone> zones;
  final Map<String, ZoneReading> readings;
  final bool streamError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = zones
        .where((zone) => readings.containsKey(zone.id))
        .length;
    final quiet = zones
        .where((zone) => readings[zone.id]?.level == 'quiet')
        .length;
    final busy = zones
        .where((zone) => readings[zone.id]?.level == 'busy')
        .length;
    final crowded = zones
        .where((zone) => readings[zone.id]?.level == 'crowded')
        .length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppGradients.hero,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDark.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded, color: Colors.white),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Campus pulse',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _LiveStatus(offline: streamError, inverted: true),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            zones.isEmpty
                ? 'No active places yet'
                : available == 0
                ? 'Waiting for sensor readings'
                : '$quiet quiet  ·  $busy busy  ·  $crowded crowded',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            available == 0
                ? 'Live crowd levels will appear here as sensors report.'
                : '$available of ${zones.length} places reporting live',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelect});
  final _PlaceFilter selected;
  final ValueChanged<_PlaceFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    const values = [
      (_PlaceFilter.all, 'All'),
      (_PlaceFilter.cafeteria, 'Cafeteria'),
      (_PlaceFilter.lifts, 'Lifts'),
      (_PlaceFilter.favourites, 'Favourites'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in values) ...[
            ChoiceChip(
              label: Text(entry.$2),
              selected: selected == entry.$1,
              onSelected: (_) => onSelect(entry.$1),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _LiveStatus extends StatelessWidget {
  const _LiveStatus({required this.offline, this.inverted = false});
  final bool offline;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final foreground = inverted
        ? Colors.white
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final background = inverted
        ? Colors.white.withValues(alpha: 0.14)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: offline ? Colors.grey : const Color(0xFF63D69A),
          ),
          const SizedBox(width: 6),
          Text(
            offline ? 'Offline' : 'Live',
            style: TextStyle(
              color: foreground,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.zone,
    required this.reading,
    required this.onTap,
  });
  final CampusZone zone;
  final ZoneReading reading;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 230,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(
                  zone.isCafeteria
                      ? Icons.restaurant_rounded
                      : Icons.elevator_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        zone.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _waitLabel(reading.waitMinutes),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({
    required this.zone,
    required this.reading,
    required this.trend,
    required this.favourite,
    required this.favouriteBusy,
    required this.onTap,
    required this.onFavourite,
    required this.onAlert,
  });

  final CampusZone zone;
  final ZoneReading? reading;
  final int trend;
  final bool favourite;
  final bool favouriteBusy;
  final VoidCallback onTap;
  final VoidCallback onFavourite;
  final VoidCallback onAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = _crowdLevel(reading?.level);
    final offline = _isOffline(reading);
    final fill = zone.capacity == 0
        ? 0.0
        : ((reading?.count ?? 0) / zone.capacity).clamp(0.0, 1.0).toDouble();

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      zone.isCafeteria
                          ? Icons.restaurant_rounded
                          : Icons.elevator_rounded,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          zone.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          zone.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: favourite
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    onPressed: favouriteBusy ? null : onFavourite,
                    icon: favouriteBusy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            favourite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: favourite
                                ? Colors.pinkAccent
                                : scheme.onSurfaceVariant,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (offline)
                    const _OfflineBadge()
                  else
                    _CrowdBadge(level: level),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      offline
                          ? 'Waiting for sensor data'
                          : 'Current campus occupancy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _TrendIcon(trend: trend),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _SmallMetric(
                      icon: Icons.groups_rounded,
                      label: 'People',
                      value: reading == null
                          ? '—'
                          : '${reading!.count}/${zone.capacity}',
                    ),
                    Container(
                      width: 1,
                      height: 34,
                      color: scheme.outlineVariant.withValues(alpha: .7),
                    ),
                    _SmallMetric(
                      icon: Icons.queue_rounded,
                      label: 'Queue',
                      value: reading == null ? '—' : '${reading!.queueLength}',
                    ),
                    Container(
                      width: 1,
                      height: 34,
                      color: scheme.outlineVariant.withValues(alpha: .7),
                    ),
                    _SmallMetric(
                      icon: Icons.schedule_rounded,
                      label: 'Wait',
                      value: reading == null
                          ? '—'
                          : _waitLabel(reading!.waitMinutes),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: reading == null ? null : fill,
                  minHeight: 7,
                  backgroundColor: scheme.surfaceContainerHighest,
                  color: offline ? Colors.grey : level.color,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    offline
                        ? 'Sensor offline'
                        : 'Updated ${_ageLabel(reading!.updatedAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: offline
                          ? scheme.onSurfaceVariant
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onAlert,
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 17,
                    ),
                    label: const Text('Add alert'),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrowdBadge extends StatelessWidget {
  const _CrowdBadge({required this.level});
  final CrowdLevel level;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: level.color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(
      level.label,
      style: TextStyle(
        color: level.textColor,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        'Sensor offline',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  const _SmallMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: theme.colorScheme.primary),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: Text(
                value,
                key: ValueKey(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendIcon extends StatelessWidget {
  const _TrendIcon({required this.trend});
  final int trend;
  @override
  Widget build(BuildContext context) {
    final icon = trend > 0
        ? Icons.trending_up_rounded
        : trend < 0
        ? Icons.trending_down_rounded
        : Icons.trending_flat_rounded;
    final color = trend > 0
        ? AppColors.red
        : trend < 0
        ? AppColors.green
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: trend > 0
          ? 'Crowd increasing'
          : trend < 0
          ? 'Crowd decreasing'
          : 'Crowd steady',
      child: Icon(icon, color: color),
    );
  }
}

class _NoPlaces extends StatelessWidget {
  const _NoPlaces();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 46,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'No places match this view',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try another filter or search term.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError({required this.message, required this.retry});
  final String message;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 44),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

CrowdLevel _crowdLevel(String? level) => switch (level) {
  'busy' => CrowdLevel.busy,
  'crowded' => CrowdLevel.crowded,
  _ => CrowdLevel.quiet,
};

bool _isOffline(ZoneReading? reading) =>
    reading == null ||
    DateTime.now().difference(reading.updatedAt) > const Duration(minutes: 3);

int _levelRank(String? level) => switch (level) {
  'quiet' => 0,
  'busy' => 1,
  'crowded' => 2,
  _ => 3,
};

String _waitLabel(double minutes) {
  if (minutes <= 0) return 'No wait';
  if (minutes < 1) return '<1 min';
  return '${minutes == minutes.roundToDouble() ? minutes.toStringAsFixed(0) : minutes.toStringAsFixed(1)} min';
}

String _ageLabel(DateTime updatedAt) {
  final seconds = DateTime.now().difference(updatedAt).inSeconds;
  if (seconds < 5) return 'just now';
  if (seconds < 60) return '${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  return '${minutes ~/ 60}h ago';
}

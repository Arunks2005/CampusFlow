import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'campus_data.dart';

class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  String _mode = 'break';
  Future<List<dynamic>> _load() async {
    final zones = await CampusRepository.instance.loadZones();
    final relevant = zones
        .where((z) => _mode == 'break' ? z.isCafeteria : z.type == 'lift')
        .toList();
    final histories = await Future.wait(
      relevant.map(
        (z) => CampusRepository.instance.loadReadings(z.id, days: 28),
      ),
    );
    return [relevant, histories];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Planner')),
    body: FutureBuilder<List<dynamic>>(
      key: ValueKey(_mode),
      future: _load(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load the planner. Check your connection and try again.',
              ),
            ),
          );
        }
        final zones = snapshot.data?[0] as List<CampusZone>? ?? const [];
        final histories =
            snapshot.data?[1] as List<List<ZoneReading>>? ?? const [];
        final slots = <({CampusZone zone, ForecastEstimate estimate})>[];
        for (var i = 0; i < zones.length; i++) {
          for (final estimate in forecastForZone(
            zones[i],
            histories[i],
            hours: 4,
          )) {
            slots.add((zone: zones[i], estimate: estimate));
          }
        }
        slots.sort(
          (a, b) => a.estimate.averageWait.compareTo(b.estimate.averageWait),
        );
        final recommended = slots.isEmpty ? null : slots.first;
        return RefreshIndicator(
          onRefresh: () async {
            if (mounted) setState(() {});
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
            children: [
              Text(
                'Make the most of your break',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose what you are planning. We’ll suggest a quieter time from previous readings.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'break',
                    label: Text('Plan my break'),
                    icon: Icon(Icons.restaurant_rounded),
                  ),
                  ButtonSegment(
                    value: 'lift',
                    label: Text('Plan my lift'),
                    icon: Icon(Icons.elevator_rounded),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (values) =>
                    setState(() => _mode = values.first),
              ),
              const SizedBox(height: 20),
              if (recommended != null)
                _Recommendation(
                  zone: recommended.zone,
                  estimate: recommended.estimate,
                ),
              const SizedBox(height: 20),
              Text(
                'Predicted crowd timeline',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (slots.isEmpty)
                const _NoPlannerHistory()
              else
                ...slots.map(
                  (slot) =>
                      _TimelineTile(zone: slot.zone, estimate: slot.estimate),
                ),
              const SizedBox(height: 12),
              Text(
                'Predictions use the average of available readings for the same weekday and hour. More history improves the estimate.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _Recommendation extends StatelessWidget {
  const _Recommendation({required this.zone, required this.estimate});
  final CampusZone zone;
  final ForecastEstimate estimate;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Theme.of(context).colorScheme.primary,
          Theme.of(context).colorScheme.tertiary,
        ],
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        const SizedBox(height: 10),
        const Text('Recommended time', style: TextStyle(color: Colors.white70)),
        Text(
          DateFormat('h:mm a').format(estimate.time),
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        Text(
          '${zone.name} · about ${estimate.averageWait.toStringAsFixed(0)} min wait · ${estimate.averageCount.toStringAsFixed(0)} people',
          style: const TextStyle(color: Colors.white),
        ),
      ],
    ),
  );
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.zone, required this.estimate});
  final CampusZone zone;
  final ForecastEstimate estimate;
  @override
  Widget build(BuildContext context) {
    final fill = estimate.occupancy(zone.capacity);
    final color = fill < .5
        ? const Color(0xff41A77A)
        : fill < .8
        ? const Color(0xffD99A35)
        : const Color(0xffD45E58);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .45),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    zone.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(DateFormat('h:mm a').format(estimate.time)),
                const SizedBox(width: 10),
                Text('${estimate.averageWait.toStringAsFixed(0)} min'),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 9,
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Text(
                  '${(fill * 100).round()}% expected crowd',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  '${estimate.samples} sample${estimate.samples == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPlannerHistory extends StatelessWidget {
  const _NoPlannerHistory();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .45),
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Text(
      'There are no matching historical readings yet. Run the CampusFlow simulator to back-fill sample data and make forecasts available.',
    ),
  );
}

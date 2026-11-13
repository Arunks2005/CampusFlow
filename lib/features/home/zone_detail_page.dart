import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'campus_data.dart';
import 'sheets.dart';

class ZoneDetailPage extends StatefulWidget {
  const ZoneDetailPage({super.key, required this.zone});
  final CampusZone zone;
  @override
  State<ZoneDetailPage> createState() => _ZoneDetailPageState();
}

class _ZoneDetailPageState extends State<ZoneDetailPage> {
  late Future<List<ZoneReading>> _history;
  @override
  void initState() {
    super.initState();
    _history = CampusRepository.instance.loadReadings(widget.zone.id, days: 14);
  }

  Future<void> _refresh() async {
    setState(
      () => _history = CampusRepository.instance.loadReadings(
        widget.zone.id,
        days: 14,
      ),
    );
    await _history;
  }

  Future<void> _share(ZoneReading? reading) async {
    final text = reading == null
        ? '${widget.zone.name} on CampusFlow'
        : '${widget.zone.name}: ${reading.level}, ${reading.count} people, queue ${reading.queueLength}, estimated wait ${reading.waitMinutes.toStringAsFixed(0)} min.';
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'CampusFlow place update'),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.zone.name),
      actions: [
        IconButton(
          tooltip: 'Share',
          onPressed: () => _share(null),
          icon: const Icon(Icons.share_rounded),
        ),
      ],
    ),
    body: FutureBuilder<List<ZoneReading>>(
      future: _history,
      builder: (context, snapshot) {
        final history = snapshot.data ?? const <ZoneReading>[];
        final latest = history.isNotEmpty ? history.last : null;
        final forecast = forecastForZone(widget.zone, history, hours: 2);
        final currentLevel = latest?.level ?? 'quiet';
        final color = _levelColor(currentLevel);
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.zone.isCafeteria
                              ? Icons.restaurant_rounded
                              : Icons.elevator_rounded,
                          color: color,
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.zone.location,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(
                          label: Text(
                            latest == null
                                ? 'No recent data'
                                : _levelLabel(currentLevel),
                          ),
                          backgroundColor: color.withValues(alpha: .14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      latest == null
                          ? 'Waiting for sensor readings'
                          : '${latest.count} people here now',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      latest == null
                          ? 'Start the simulator or connect a sensor to see live details.'
                          : 'Updated ${_relative(latest.updatedAt)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () =>
                              showAlertEditorSheet(context, zone: widget.zone),
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text('Add alert'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () =>
                              showReportIssueSheet(context, zone: widget.zone),
                          icon: const Icon(Icons.flag_outlined),
                          label: const Text('Report issue'),
                        ),
                        TextButton.icon(
                          onPressed: () => _share(latest),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Share'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'People',
                      value: latest == null
                          ? '—'
                          : '${latest.count}/${widget.zone.capacity}',
                      icon: Icons.groups_rounded,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _StatTile(
                      label: 'Space left',
                      value: latest == null
                          ? '—'
                          : '${(widget.zone.capacity - latest.count).clamp(0, widget.zone.capacity)}',
                      icon: Icons.event_seat_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'Queue',
                      value: latest?.queueLength.toString() ?? '—',
                      icon: Icons.queue_rounded,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _StatTile(
                      label: 'Wait',
                      value: latest == null
                          ? '—'
                          : '${latest.waitMinutes.toStringAsFixed(0)} min',
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ChartCard(
                title: 'Last 60 minutes',
                subtitle: 'People counted',
                readings: history
                    .where(
                      (r) => r.updatedAt.isAfter(
                        DateTime.now().subtract(const Duration(hours: 1)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              _ChartCard(
                title: 'Today',
                subtitle: 'People counted by time',
                readings: history
                    .where(
                      (r) => DateUtils.isSameDay(r.updatedAt, DateTime.now()),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Text(
                'Next 2 hours',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (forecast.isEmpty)
                const _NoForecast()
              else ...[
                for (final estimate in forecast)
                  _ForecastTile(
                    estimate: estimate,
                    capacity: widget.zone.capacity,
                  ),
                const SizedBox(height: 8),
                Text(
                  'Best time to go: ${DateFormat('h:mm a').format(forecast.reduce((a, b) => a.averageWait <= b.averageWait ? a : b).time)}',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Estimate uses past readings for the same weekday and hour.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.readings,
  });
  final String title;
  final String subtitle;
  final List<ZoneReading> readings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = readings
        .asMap()
        .entries
        .map(
          (entry) => FlSpot(entry.key.toDouble(), entry.value.count.toDouble()),
        )
        .toList();
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(subtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: points.length < 2
                  ? Center(
                      child: Text(
                        points.isEmpty
                            ? 'No readings yet. Start the simulator to fill this chart.'
                            : '${points.first.y.toInt()} people recorded',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        minY: 0,
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 32,
                            ),
                          ),
                          rightTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: points,
                            isCurved: true,
                            color: theme.colorScheme.primary,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: theme.colorScheme.primary.withValues(
                                alpha: .12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastTile extends StatelessWidget {
  const _ForecastTile({required this.estimate, required this.capacity});
  final ForecastEstimate estimate;
  final int capacity;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.schedule_rounded),
    title: Text(DateFormat('h:mm a').format(estimate.time)),
    subtitle: Text(
      '${estimate.averageCount.toStringAsFixed(0)} people expected · ${estimate.samples} past sample${estimate.samples == 1 ? '' : 's'}',
    ),
    trailing: Text(
      '${estimate.averageWait.toStringAsFixed(0)} min',
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _NoForecast extends StatelessWidget {
  const _NoForecast();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .45),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Text(
      'There is not enough history to forecast this time yet. The simulator can add sample history.',
    ),
  );
}

Color _levelColor(String level) => switch (level) {
  'busy' => const Color(0xffD99124),
  'crowded' => const Color(0xffD9534F),
  _ => const Color(0xff26996E),
};
String _levelLabel(String level) => switch (level) {
  'busy' => 'Busy',
  'crowded' => 'Crowded',
  _ => 'Quiet',
};
String _relative(DateTime time) {
  final seconds = DateTime.now().difference(time).inSeconds;
  if (seconds < 60) return '${seconds}s ago';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  return '${minutes ~/ 60}h ago';
}

import 'package:flutter/material.dart';

import '../../core/alert_engine.dart';
import 'campus_data.dart';

Future<void> showAlertEditorSheet(
  BuildContext context, {
  CampusZone? zone,
  CampusAlert? alert,
}) async {
  final repository = CampusRepository.instance;
  final zones = await repository.loadZones();
  if (!context.mounted || zones.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) =>
        _AlertEditor(zones: zones, initialZone: zone, alert: alert),
  );
}

class _AlertEditor extends StatefulWidget {
  const _AlertEditor({required this.zones, this.initialZone, this.alert});
  final List<CampusZone> zones;
  final CampusZone? initialZone;
  final CampusAlert? alert;
  @override
  State<_AlertEditor> createState() => _AlertEditorState();
}

class _AlertEditorState extends State<_AlertEditor> {
  late String _zoneId;
  late String _condition;
  late final TextEditingController _threshold;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _zoneId =
        widget.alert?.zoneId ?? widget.initialZone?.id ?? widget.zones.first.id;
    _condition = widget.alert?.condition ?? 'wait_below';
    _threshold = TextEditingController(
      text: widget.alert?.threshold?.toStringAsFixed(0) ?? '5',
    );
  }

  @override
  void dispose() {
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = double.tryParse(_threshold.text.trim());
    if (_condition != 'becomes_quiet' && (value == null || value <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a number greater than zero.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await CampusRepository.instance.saveAlert(
        id: widget.alert?.id,
        zoneId: _zoneId,
        condition: _condition,
        threshold: _condition == 'becomes_quiet' ? null : value,
        active: true,
      );
      await AlertEngine.instance.requestPermission();
      await AlertEngine.instance.refreshRules();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Alert saved.')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save alert: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final thresholdLabel = _condition == 'crowd_above'
        ? 'Crowd percentage'
        : 'Wait in minutes';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        8,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.alert == null ? 'Create an alert' : 'Edit alert',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String>(
            initialValue: _zoneId,
            decoration: const InputDecoration(labelText: 'Campus place'),
            items: [
              for (final item in widget.zones)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _zoneId = value);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _condition,
            decoration: const InputDecoration(labelText: 'Notify me when'),
            items: const [
              DropdownMenuItem(
                value: 'wait_below',
                child: Text('Wait drops below a number'),
              ),
              DropdownMenuItem(
                value: 'becomes_quiet',
                child: Text('The place becomes quiet'),
              ),
              DropdownMenuItem(
                value: 'crowd_above',
                child: Text('Crowd rises above a percentage'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _condition = value);
            },
          ),
          if (_condition != 'becomes_quiet') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _threshold,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: thresholdLabel,
                suffixText: _condition == 'crowd_above' ? '%' : 'min',
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save alert'),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showReportIssueSheet(
  BuildContext context, {
  CampusZone? zone,
}) async {
  final zones = await CampusRepository.instance.loadZones();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportEditor(zones: zones, initialZone: zone),
  );
}

class _ReportEditor extends StatefulWidget {
  const _ReportEditor({required this.zones, this.initialZone});
  final List<CampusZone> zones;
  final CampusZone? initialZone;
  @override
  State<_ReportEditor> createState() => _ReportEditorState();
}

class _ReportEditorState extends State<_ReportEditor> {
  late String? _zoneId = widget.initialZone?.id;
  String _reason = 'Looks too crowded';
  final _comment = TextEditingController();
  bool _sending = false;
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await CampusRepository.instance.submitReport(
        zoneId: _zoneId,
        reason: _reason,
        comment: _comment.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks. Your report was sent.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send report: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      22,
      8,
      22,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Report an issue',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          initialValue: _zoneId,
          decoration: const InputDecoration(
            labelText: 'Campus place (optional)',
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('General campus issue'),
            ),
            ...widget.zones.map(
              (item) => DropdownMenuItem<String?>(
                value: item.id,
                child: Text(item.name),
              ),
            ),
          ],
          onChanged: (value) => setState(() => _zoneId = value),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _reason,
          decoration: const InputDecoration(labelText: 'What happened?'),
          items:
              const [
                    'Looks too crowded',
                    'Sensor seems wrong',
                    'Place is closed',
                    'Other',
                  ]
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
          onChanged: (value) {
            if (value != null) setState(() => _reason = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          maxLines: 3,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Add a note (optional)'),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Sending…' : 'Send report'),
          ),
        ),
      ],
    ),
  );
}

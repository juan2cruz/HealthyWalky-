import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health/health.dart';
import '../../../core/supabase/client.dart';
import '../models/step_entry.dart';
import '../providers/steps_provider.dart';

bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

class StepsScreen extends ConsumerStatefulWidget {
  const StepsScreen({super.key});

  @override
  ConsumerState<StepsScreen> createState() => _StepsScreenState();
}

class _StepsScreenState extends ConsumerState<StepsScreen> {
  bool _healthAuthorized = false;
  bool _healthChecked = false;
  bool _syncing = false;
  bool _requestingPermission = false;

  @override
  void initState() {
    super.initState();
    _initHealth();
  }

  Future<void> _initHealth() async {
    if (!_isMobile) {
      setState(() => _healthChecked = true);
      return;
    }
    await Health().configure();
    final authorized =
        await Health().hasPermissions([HealthDataType.STEPS]) ?? false;
    setState(() {
      _healthAuthorized = authorized;
      _healthChecked = true;
    });
    if (authorized) _syncHealth();
  }

  Future<void> _requestHealthPermission() async {
    try {
      final authorized = await Health().requestAuthorization(
        [HealthDataType.STEPS],
        permissions: [HealthDataAccess.READ],
      );
      setState(() => _healthAuthorized = authorized);
      if (authorized) {
        _syncHealth();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permiso denegado. Asegúrate de activar el interruptor de "Pasos" en la pantalla de Health Connect.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al solicitar permisos: $e')),
        );
      }
    }
  }

  Future<void> _syncHealth() async {
    final challenge = ref.read(activeChallengeProvider).valueOrNull;
    if (!_isMobile || !_healthAuthorized || challenge == null) return;

    setState(() => _syncing = true);
    try {
      final now = DateTime.now();
      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final syncFrom = challenge.startDate.isAfter(sevenDaysAgo)
          ? challenge.startDate
          : sevenDaysAgo;
      final source = Platform.isAndroid ? 'google_fit' : 'apple_health';

      for (var d = syncFrom; !d.isAfter(now); d = d.add(const Duration(days: 1))) {
        final dayStart = DateTime(d.year, d.month, d.day);
        final dayEnd = DateTime(d.year, d.month, d.day, 23, 59, 59);
        final steps = await Health().getTotalStepsInInterval(dayStart, dayEnd);
        if (steps != null && steps > 0) {
          await supabase.rpc('upsert_steps', params: {
            'p_step_date': _isoDate(d),
            'p_step_count': steps,
            'p_source': source,
          });
        }
      }
      ref.invalidate(myStepsProvider(challenge.id));
      ref.invalidate(myTotalStepsProvider(challenge.id));
      ref.invalidate(myConflictsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al sincronizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _resolveConflict(StepConflict conflict) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            'Conflicto el ${_formatDate(conflict.stepDate)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: conflict.options
              .map((o) => ListTile(
                    title: Text(o.label),
                    subtitle: Text('${o.stepCount} pasos'),
                    trailing: o.isCanonical
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () => Navigator.pop(ctx, o.source),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Decidir más tarde'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    try {
      await supabase.rpc('resolve_step_conflict', params: {
        'p_step_date': _isoDate(conflict.stepDate),
        'p_winning_source': picked,
      });
      ref.invalidate(myConflictsProvider);
      final challenge = ref.read(activeChallengeProvider).valueOrNull;
      if (challenge != null) {
        ref.invalidate(myStepsProvider(challenge.id));
        ref.invalidate(myTotalStepsProvider(challenge.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _openManualEntry(
      String challengeId, DateTime start, DateTime end) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManualStepSheet(
        challengeStart: start,
        challengeEnd: end,
        onSaved: (date, count) async {
          final result = await supabase.rpc('upsert_steps', params: {
            'p_step_date': _isoDate(date),
            'p_step_count': count,
            'p_source': 'manual',
          });
          if (result == 'conflict') ref.invalidate(myConflictsProvider);
        },
      ),
    );
    // Invalidate AFTER the sheet is dismissed so the parent widget
    // is fully visible before triggering the rebuild.
    if (saved == true && challengeId.isNotEmpty) {
      ref.invalidate(myStepsProvider(challengeId));
      ref.invalidate(myTotalStepsProvider(challengeId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final challengeAsync = ref.watch(activeChallengeProvider);
    final conflictsAsync = ref.watch(myConflictsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mis pasos')),
      body: challengeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (challenge) {
          if (challenge == null) {
            return const Center(
              child: Text('No hay ningún desafío activo',
                  style: TextStyle(color: Colors.grey)),
            );
          }

          final stepsAsync = ref.watch(myStepsProvider(challenge.id));
          final totalAsync = ref.watch(myTotalStepsProvider(challenge.id));
          final conflicts = conflictsAsync.valueOrNull ?? [];

          return RefreshIndicator(
            onRefresh: () async {
              if (_isMobile && _healthAuthorized) await _syncHealth();
              ref.invalidate(myStepsProvider(challenge.id));
              ref.invalidate(myTotalStepsProvider(challenge.id));
              ref.invalidate(myConflictsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Health banner (mobile, not yet authorized) ─────
                if (_healthChecked && _isMobile && !_healthAuthorized)
                  _HealthBanner(
                    onConnect: _requestingPermission
                        ? null
                        : _requestHealthPermission,
                  ),

                // ── Conflicts banner ───────────────────────────────
                if (conflicts.isNotEmpty)
                  _ConflictsBanner(
                    count: conflicts.length,
                    onResolve: () => _resolveConflict(conflicts.first),
                  ),

                // ── Summary card ───────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(challenge.title,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatDate(challenge.startDate)} → ${_formatDate(challenge.endDate)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.directions_walk,
                                size: 28, color: Colors.green),
                            const SizedBox(width: 8),
                            Text(
                              totalAsync.valueOrNull != null
                                  ? '${_formatNumber(totalAsync.value!)} pasos totales'
                                  : '—',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                        // Sync row (mobile + authorized)
                        if (_isMobile && _healthAuthorized) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _syncing ? null : _syncHealth,
                            icon: _syncing
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.sync, size: 16),
                            label: Text(_syncing
                                ? 'Sincronizando…'
                                : 'Sincronizar ahora'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Day-by-day history ─────────────────────────────
                Text('Historial',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (DateTime.now().isBefore(challenge.startDate))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'El desafío comienza el ${_formatDate(challenge.startDate)}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  stepsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Error: $e'),
                    data: (steps) {
                      if (steps.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text('Aún no hay pasos registrados',
                                style: TextStyle(color: Colors.grey)),
                          ),
                        );
                      }
                      return Column(
                        children: steps
                            .map((s) => _StepDayTile(
                                  entry: s,
                                  onEdit: () => _openManualEntry(
                                      challenge.id,
                                      challenge.startDate,
                                      challenge.endDate),
                                ))
                            .toList(),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final ch = challengeAsync.valueOrNull;
          // Use challenge dates if active; otherwise allow entry for last 90 days
          final now = DateTime.now();
          _openManualEntry(
            ch?.id ?? '',
            ch?.startDate ?? now.subtract(const Duration(days: 90)),
            ch?.endDate ?? now,
          );
        },
        tooltip: 'Añadir pasos',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _HealthBanner extends StatelessWidget {
  final VoidCallback? onConnect;
  const _HealthBanner({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final label = Platform.isAndroid ? 'Google Fit' : 'Apple Health';
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.favorite_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Conecta $label para sincronización automática'),
            ),
            TextButton(
              onPressed: onConnect,
              child: onConnect == null
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Conectar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onResolve;
  const _ConflictsBanner({required this.count, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onResolve,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count ${count == 1 ? 'día con datos en conflicto' : 'días con datos en conflicto'} — Resolver',
                style: const TextStyle(color: Colors.orange),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.orange),
          ],
        ),
      ),
    );
  }
}

class _StepDayTile extends StatelessWidget {
  final StepEntry entry;
  final VoidCallback onEdit;
  const _StepDayTile({required this.entry, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: entry.hasConflict
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.12),
        child: Icon(
          entry.hasConflict
              ? Icons.warning_amber_outlined
              : Icons.directions_walk,
          size: 16,
          color: entry.hasConflict ? Colors.orange : Colors.green,
        ),
      ),
      title: Text(_formatDate(entry.stepDate)),
      subtitle: Text(entry.isManual ? 'Manual' : entry.source.replaceAll('_', ' ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _formatNumber(entry.stepCount),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16),
            onPressed: onEdit,
            tooltip: 'Editar',
          ),
        ],
      ),
    );
  }
}

class _ManualStepSheet extends StatefulWidget {
  final DateTime challengeStart;
  final DateTime challengeEnd;
  final Future<void> Function(DateTime date, int count) onSaved;

  const _ManualStepSheet({
    required this.challengeStart,
    required this.challengeEnd,
    required this.onSaved,
  });

  @override
  State<_ManualStepSheet> createState() => _ManualStepSheetState();
}

class _ManualStepSheetState extends State<_ManualStepSheet> {
  late DateTime _selectedDate;
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    // Clamp today to [challengeStart, challengeEnd]. If the challenge hasn't
    // started yet, default to challengeStart so the picker remains valid.
    if (today.isAfter(widget.challengeEnd)) {
      _selectedDate = widget.challengeEnd;
    } else if (today.isBefore(widget.challengeStart)) {
      _selectedDate = widget.challengeStart;
    } else {
      _selectedDate = today;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    // Ensure lastDate is never before firstDate (pre-challenge scenario).
    final lastDate = today.isAfter(widget.challengeEnd)
        ? widget.challengeEnd
        : today.isBefore(widget.challengeStart)
            ? widget.challengeStart
            : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: widget.challengeStart,
      lastDate: lastDate,
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _save() async {
    final count = int.tryParse(_ctrl.text.trim());
    if (count == null || count < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Introduce un número de pasos válido')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSaved(_selectedDate, count);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Registrar pasos',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_formatDate(_selectedDate)),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Número de pasos',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _isoDate(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

String _formatDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

String _formatNumber(int n) {
  if (n >= 1000) {
    return '${(n / 1000).toStringAsFixed(1)}k';
  }
  return '$n';
}

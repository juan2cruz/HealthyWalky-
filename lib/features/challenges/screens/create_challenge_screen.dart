import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/supabase/client.dart';
import '../providers/challenge_provider.dart';

class CreateChallengeScreen extends ConsumerStatefulWidget {
  const CreateChallengeScreen({super.key});

  @override
  ConsumerState<CreateChallengeScreen> createState() =>
      _CreateChallengeScreenState();
}

class _CreateChallengeScreenState
    extends ConsumerState<CreateChallengeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _enrollmentType = 'individual';
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final DateTime firstDate;
    final DateTime initialDate;

    if (isStart) {
      firstDate = now;
      initialDate = _startDate ?? now;
    } else {
      // End date must be strictly after start date
      final minEnd = (_startDate ?? now).add(const Duration(days: 1));
      firstDate = minEnd;
      initialDate = (_endDate != null && _endDate!.isAfter(minEnd))
          ? _endDate!
          : minEnd;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        // Clear end date if it's no longer valid
        if (_endDate != null && !_endDate!.isAfter(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Seleccionar fecha';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona las fechas de inicio y fin')));
      return;
    }
    if (!_endDate!.isAfter(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La fecha fin debe ser posterior a la fecha inicio')));
      return;
    }
    setState(() => _loading = true);
    try {
      await supabase.rpc('create_challenge', params: {
        'p_title': _titleCtrl.text.trim(),
        'p_description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'p_start_date': _startDate!.toIso8601String().substring(0, 10),
        'p_end_date': _endDate!.toIso8601String().substring(0, 10),
        'p_enrollment_type': _enrollmentType,
      });
      ref.invalidate(challengesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo desafío')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Título del desafío'),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Obligatorio' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)'),
                ),
                const SizedBox(height: 24),
                Text('Fechas',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: true),
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: 16),
                        label: Text(_formatDate(_startDate)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('→'),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: false),
                        icon: const Icon(Icons.calendar_today_outlined,
                            size: 16),
                        label: Text(_formatDate(_endDate)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Tipo de competición',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'individual',
                      label: Text('Individual'),
                      icon: Icon(Icons.person_outlined),
                    ),
                    ButtonSegment(
                      value: 'team',
                      label: Text('Equipos'),
                      icon: Icon(Icons.groups_outlined),
                    ),
                  ],
                  selected: {_enrollmentType},
                  onSelectionChanged: (s) =>
                      setState(() => _enrollmentType = s.first),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Crear desafío'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

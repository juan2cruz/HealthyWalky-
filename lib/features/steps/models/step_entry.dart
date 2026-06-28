class StepEntry {
  final DateTime stepDate;
  final int stepCount;
  final String source;
  final String syncStatus;

  const StepEntry({
    required this.stepDate,
    required this.stepCount,
    required this.source,
    required this.syncStatus,
  });

  bool get hasConflict => syncStatus == 'conflict';
  bool get isManual => source == 'manual';
  bool get isFromHealth => source == 'google_fit' || source == 'apple_health';

  factory StepEntry.fromMap(Map<String, dynamic> map) => StepEntry(
        stepDate: DateTime.parse(map['step_date'] as String),
        stepCount: map['step_count'] as int,
        source: map['source'] as String,
        syncStatus: map['sync_status'] as String,
      );
}

// Represents two conflicting records for the same day
class StepConflict {
  final DateTime stepDate;
  final List<StepConflictOption> options;

  const StepConflict({required this.stepDate, required this.options});

  factory StepConflict.fromRows(
      String dateStr, List<Map<String, dynamic>> rows) {
    return StepConflict(
      stepDate: DateTime.parse(dateStr),
      options: rows
          .map((r) => StepConflictOption(
                source: r['source'] as String,
                stepCount: r['step_count'] as int,
                isCanonical: r['is_canonical'] as bool,
              ))
          .toList(),
    );
  }
}

class StepConflictOption {
  final String source;
  final int stepCount;
  final bool isCanonical;

  const StepConflictOption({
    required this.source,
    required this.stepCount,
    required this.isCanonical,
  });

  String get label => switch (source) {
        'manual' => 'Entrada manual',
        'google_fit' => 'Google Fit',
        'apple_health' => 'Apple Health',
        _ => source,
      };
}

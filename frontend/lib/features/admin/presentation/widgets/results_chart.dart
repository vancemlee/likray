import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../domain/models/results_model.dart';

/// Виджет результатов для одного класса.
///
/// Если голосов < 5 (hiddenDueToSmallCount = true) — показывает серую
/// плашку «Данные скрыты» вместо графика (защита от деанонимизации).
/// Если данных достаточно — рисует BarChart по блоку heavy_subjects.
class ClassResultsCard extends StatelessWidget {
  final ClassResultsModel classResults;

  const ClassResultsCard({super.key, required this.classResults});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  classResults.className,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Голосов: ${classResults.voteCount}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            classResults.hiddenDueToSmallCount
                ? _HiddenDataPlaceholder(voteCount: classResults.voteCount)
                : _ResultsCharts(aggregates: classResults.aggregates ?? {}),
          ],
        ),
      ),
    );
  }
}

/// Серая плашка «Данные скрыты» при n < 5.
class _HiddenDataPlaceholder extends StatelessWidget {
  final int voteCount;

  const _HiddenDataPlaceholder({required this.voteCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('hidden_data_placeholder'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: Colors.grey.shade500),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Данные скрыты (проголосовало $voteCount из минимум 5).\n'
              'Защита анонимности: результаты не отображаются для малых выборок.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Набор графиков по блокам анкеты.
class _ResultsCharts extends StatelessWidget {
  final Map<String, dynamic> aggregates;

  const _ResultsCharts({required this.aggregates});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (aggregates.containsKey('heavy_subjects'))
          _HeavySubjectsChart(
            data: aggregates['heavy_subjects'] as Map<String, dynamic>,
          ),
        if (aggregates.containsKey('pe'))
          _PEChart(
            // Бэк отдаёт {"pe": {"preference": {"first": N, "last": N, ...}}}.
            // Достаём вложенный словарь "preference" — именно по нему рисуется график.
            data: ((aggregates['pe'] as Map<String, dynamic>?)?['preference']
                    as Map<String, dynamic>?) ??
                const {},
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// График: Тяжёлые предметы
// ---------------------------------------------------------------------------

/// BarChart распределения предпочтений по тяжёлым предметам.
/// Ось X — предметы, ось Y — количество голосов за каждый тайм-слот.
class _HeavySubjectsChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _HeavySubjectsChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Подготовка данных: каждый предмет → список BarChartRodData
    final subjects = ['math', 'physics', 'chemistry', 'cs', 'foreign_language'];
    final subjectLabels = {
      'math': 'Матем.',
      'physics': 'Физика',
      'chemistry': 'Химия',
      'cs': 'Инф.',
      'foreign_language': 'Ин.яз.',
    };
    final slots = ['lessons_1_2', 'lessons_3_4', 'lessons_5_6', 'any'];
    final slotColors = [
      theme.colorScheme.primary,
      theme.colorScheme.secondary,
      theme.colorScheme.tertiary,
      Colors.grey,
    ];

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < subjects.length; i++) {
      final subjectData = data[subjects[i]];
      if (subjectData is! Map<String, dynamic>) continue;

      final rods = <BarChartRodData>[];
      for (int j = 0; j < slots.length; j++) {
        final count =
            (subjectData[slots[j]] as num?)?.toDouble() ?? 0.0;
        rods.add(BarChartRodData(
          toY: count,
          color: slotColors[j],
          width: 8,
          borderRadius: BorderRadius.circular(2),
        ));
      }
      barGroups.add(BarChartGroupData(x: i, barRods: rods, barsSpace: 2));
    }

    if (barGroups.isEmpty) {
      return const Text('Нет данных по предметам');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Тяжёлые предметы',
            style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: BarChart(
            key: const Key('heavy_subjects_chart'),
            BarChartData(
              barGroups: barGroups,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) => Text(
                      subjectLabels[subjects[value.toInt()]] ?? '',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
            ),
          ),
        ),
        // Легенда
        Wrap(
          spacing: 12,
          children: [
            _legend(slotColors[0], '1–2 урок'),
            _legend(slotColors[1], '3–4 урок'),
            _legend(slotColors[2], '5–6 урок'),
            _legend(slotColors[3], 'Не важно'),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// График: Физкультура
// ---------------------------------------------------------------------------

class _PEChart extends StatelessWidget {
  final Map<String, dynamic> data;

  const _PEChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = ['first', 'last', 'middle', 'any'];
    final labels = {
      'first': 'Первым',
      'last': 'Последним',
      'middle': 'В середине',
      'any': 'Не важно',
    };

    final sections = <PieChartSectionData>[];
    for (final opt in options) {
      final count = (data[opt] as num?)?.toDouble() ?? 0;
      if (count > 0) {
        sections.add(PieChartSectionData(
          value: count,
          title: '${count.toInt()}',
          color: _colorForOption(opt, theme),
          radius: 50,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ));
      }
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Физкультура', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          height: 140,
          child: PieChart(
            PieChartData(sections: sections, sectionsSpace: 2),
          ),
        ),
        Wrap(
          spacing: 12,
          children: options
              .where((o) => (data[o] as num?)?.toDouble() != null &&
                  (data[o] as num).toDouble() > 0)
              .map((o) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _colorForOption(o, theme),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(labels[o] ?? o,
                          style: const TextStyle(fontSize: 11)),
                    ],
                  ))
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Color _colorForOption(String opt, ThemeData theme) {
    switch (opt) {
      case 'first':
        return theme.colorScheme.primary;
      case 'last':
        return theme.colorScheme.secondary;
      case 'middle':
        return theme.colorScheme.tertiary;
      default:
        return Colors.grey;
    }
  }
}

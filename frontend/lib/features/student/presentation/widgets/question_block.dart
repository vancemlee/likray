import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/student_providers.dart';

/// Универсальный виджет для одного блока анкеты.
///
/// Тип блока определяется полем "type" из ответа бэка.
/// Поддерживаемые типы: subjects_time, exams, free_periods, radio, text.
/// Каждый тип рендерится своим приватным виджетом (_SubjectsTimeBlock и т.д.).
class QuestionBlock extends ConsumerWidget {
  final Map<String, dynamic> block;

  const QuestionBlock({super.key, required this.block});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = block['type'] as String? ?? '';
    final title = block['title'] as String? ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    )),
            if (block['description'] != null) ...[
              const SizedBox(height: 4),
              Text(
                block['description'] as String,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            _buildBlockContent(type, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockContent(String type, WidgetRef ref) {
    switch (type) {
      case 'subjects_time':
        return _SubjectsTimeBlock(block: block);
      case 'exams':
        return _ExamsBlock(block: block);
      case 'free_periods':
        return _FreePeriodsBlock(block: block);
      case 'radio':
        return _RadioBlock(block: block);
      case 'text':
        return _TextBlock(block: block);
      default:
        return Text('Неизвестный тип блока: $type');
    }
  }
}

// ---------------------------------------------------------------------------
// Блок 1: Тяжёлые предметы — время дня
// ---------------------------------------------------------------------------

class _SubjectsTimeBlock extends ConsumerWidget {
  final Map<String, dynamic> block;

  const _SubjectsTimeBlock({required this.block});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects =
        List<Map<String, dynamic>>.from(block['subjects'] as List? ?? []);
    final options =
        List<Map<String, dynamic>>.from(block['options'] as List? ?? []);
    final answers = ref.watch(surveyAnswersProvider);
    final notifier = ref.read(surveyAnswersProvider.notifier);

    return Column(
      children: subjects.map((subject) {
        final key = subject['key'] as String;
        final label = subject['label'] as String;
        final current = answers.heavySubjects[key] ?? 'any';

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: options.map((opt) {
                  final value = opt['value'] as String;
                  final optLabel = opt['label'] as String;
                  return ChoiceChip(
                    label: Text(optLabel),
                    selected: current == value,
                    onSelected: (_) =>
                        notifier.setHeavySubject(key, value),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Блок 2: Контрольные — слайдер + чекбокс
// ---------------------------------------------------------------------------

class _ExamsBlock extends ConsumerWidget {
  final Map<String, dynamic> block;

  const _ExamsBlock({required this.block});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answers = ref.watch(surveyAnswersProvider);
    final notifier = ref.read(surveyAnswersProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Максимум контрольных в один день: ${answers.examsMaxPerDay}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          value: answers.examsMaxPerDay.toDouble(),
          min: 1,
          max: 4,
          divisions: 3,
          label: answers.examsMaxPerDay.toString(),
          onChanged: (v) => notifier.setExamsMaxPerDay(v.round()),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Понедельник и пятница — желательно без контрольных'),
          value: answers.examsNoMonFri,
          onChanged: (v) => notifier.setExamsNoMonFri(v ?? false),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Блок 3: Окна — радио + чекбокс
// ---------------------------------------------------------------------------

class _FreePeriodsBlock extends ConsumerWidget {
  final Map<String, dynamic> block;

  const _FreePeriodsBlock({required this.block});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options =
        List<Map<String, dynamic>>.from(block['options'] as List? ?? []);
    final answers = ref.watch(surveyAnswersProvider);
    final notifier = ref.read(surveyAnswersProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...options.map((opt) {
          final value = opt['value'] as String;
          final label = opt['label'] as String;
          return RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: value,
            groupValue: answers.freePeriodsChoice,
            onChanged: (v) => notifier.setFreePeriodsChoice(v!),
          );
        }),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Лучше одно длинное окно, чем несколько коротких'),
          value: answers.freePeriodsPreferLong,
          onChanged: (v) => notifier.setFreePeriodsPreferLong(v ?? false),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Блок 4: Физкультура — простая радио-группа
// ---------------------------------------------------------------------------

class _RadioBlock extends ConsumerWidget {
  final Map<String, dynamic> block;

  const _RadioBlock({required this.block});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options =
        List<Map<String, dynamic>>.from(block['options'] as List? ?? []);
    final answers = ref.watch(surveyAnswersProvider);
    final notifier = ref.read(surveyAnswersProvider.notifier);

    return Column(
      children: options.map((opt) {
        final value = opt['value'] as String;
        final label = opt['label'] as String;
        return RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value,
          groupValue: answers.pePreference,
          onChanged: (v) => notifier.setPEPreference(v!),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Блок 5: Свободный текст
// ---------------------------------------------------------------------------

class _TextBlock extends ConsumerWidget {
  final Map<String, dynamic> block;

  const _TextBlock({required this.block});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxLength = (block['max_length'] as int?) ?? 280;
    final placeholder =
        block['placeholder'] as String? ?? 'Ваше пожелание...';
    final notifier = ref.read(surveyAnswersProvider.notifier);

    return TextField(
      maxLength: maxLength,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: placeholder,
        helperText: 'Необязательно',
      ),
      onChanged: notifier.setFreeText,
    );
  }
}

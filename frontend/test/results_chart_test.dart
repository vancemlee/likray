import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:likray/features/admin/domain/models/results_model.dart';
import 'package:likray/features/admin/presentation/widgets/results_chart.dart';

void main() {
  group('ClassResultsCard', () {
    testWidgets('показывает серую плашку когда n < 5', (tester) async {
      const model = ClassResultsModel(
        classId: 1,
        className: '10В',
        voteCount: 3,
        hiddenDueToSmallCount: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ClassResultsCard(classResults: model),
          ),
        ),
      );

      // Плашка «данные скрыты» должна отображаться
      expect(find.byKey(const Key('hidden_data_placeholder')), findsOneWidget);
      // Текст с количеством голосов
      expect(find.textContaining('проголосовало 3'), findsOneWidget);
      // График НЕ должен рендериться
      expect(find.byKey(const Key('heavy_subjects_chart')), findsNothing);
    });

    testWidgets('показывает имя класса и количество голосов', (tester) async {
      const model = ClassResultsModel(
        classId: 2,
        className: '11А',
        voteCount: 3,
        hiddenDueToSmallCount: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ClassResultsCard(classResults: model),
          ),
        ),
      );

      expect(find.text('11А'), findsOneWidget);
      expect(find.textContaining('Голосов: 3'), findsOneWidget);
    });

    testWidgets('рендерит график когда n >= 5', (tester) async {
      final model = ClassResultsModel(
        classId: 3,
        className: '9Б',
        voteCount: 8,
        hiddenDueToSmallCount: false,
        aggregates: {
          'heavy_subjects': {
            'math': {'lessons_1_2': 3, 'lessons_3_4': 2, 'lessons_5_6': 1, 'any': 2},
            'physics': {'lessons_1_2': 1, 'lessons_3_4': 4, 'lessons_5_6': 2, 'any': 1},
            'chemistry': {'lessons_1_2': 2, 'lessons_3_4': 2, 'lessons_5_6': 2, 'any': 2},
            'cs': {'lessons_1_2': 0, 'lessons_3_4': 3, 'lessons_5_6': 3, 'any': 2},
            'foreign_language': {'lessons_1_2': 4, 'lessons_3_4': 2, 'lessons_5_6': 1, 'any': 1},
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClassResultsCard(classResults: model),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Плашки «скрыто» НЕ должно быть
      expect(find.byKey(const Key('hidden_data_placeholder')), findsNothing);
      // График должен рендериться
      expect(find.byKey(const Key('heavy_subjects_chart')), findsOneWidget);
    });
  });
}

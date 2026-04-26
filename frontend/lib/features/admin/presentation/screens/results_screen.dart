import 'dart:io';

import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/api/api_client.dart';
import '../providers/admin_providers.dart';
import '../widgets/results_chart.dart';

/// Экран результатов голосования по сессии.
///
/// Загружает агрегированные данные GET /admin/voting-sessions/:id/results.
/// Для каждого класса показывает:
///   — если n ≥ 5: графики (BarChart + PieChart из fl_chart)
///   — если n < 5: серую плашку «Данные скрыты»
///
/// Кнопки «Экспорт CSV» и «Экспорт PDF» скачивают файлы через dio,
/// сохраняют их в директорию документов приложения и пробуют открыть
/// системным просмотрщиком через url_launcher.
class ResultsScreen extends ConsumerWidget {
  final int sessionId;

  const ResultsScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(adminResultsProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Результаты'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/sessions'),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.download),
            tooltip: 'Экспорт',
            onSelected: (format) => _export(context, ref, format),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Экспорт CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf),
                  title: Text('Экспорт PDF'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: resultsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Не удалось загрузить результаты:\n$e',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(adminResultsProvider(sessionId)),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (results) => results.classes.isEmpty
            ? const Center(
                child: Text(
                  'Нет данных по классам для этой сессии.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: results.classes.length,
                itemBuilder: (context, index) => ClassResultsCard(
                  classResults: results.classes[index],
                ),
              ),
      ),
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    String format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = ref.read(dioProvider);
      final path = format == 'csv'
          ? '/admin/voting-sessions/$sessionId/export/csv'
          : '/admin/voting-sessions/$sessionId/export/pdf';

      messenger.showSnackBar(
        SnackBar(content: Text('Скачиваем ${format.toUpperCase()}...')),
      );

      final response = await dio.get<List<int>>(
        path,
        options: dio_pkg.Options(responseType: dio_pkg.ResponseType.bytes),
      );

      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Сервер вернул пустой ответ')),
        );
        return;
      }

      // Web — браузер сам сохраняет, остальные платформы — пишем в файл.
      if (kIsWeb) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${(bytes.length / 1024).toStringAsFixed(1)} КБ получено '
              '(на web сохранение через браузерный API).',
            ),
          ),
        );
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'likray_session_${sessionId}_${DateTime.now().millisecondsSinceEpoch}.$format';
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Сохранено: ${file.path} (${(bytes.length / 1024).toStringAsFixed(1)} КБ)',
          ),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => launchUrl(Uri.file(file.path)),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка экспорта: $e')),
      );
    }
  }
}

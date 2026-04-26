import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/admin_providers.dart';

/// Экран управления кодами доступа для класса.
///
/// Показывает ранее выданные коды (через API) и позволяет
/// сгенерировать новые. Новые коды показываются один раз с
/// предупреждением и кнопкой «Скопировать все».
class CodesScreen extends ConsumerWidget {
  final int classId;

  const CodesScreen({super.key, required this.classId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newCodesAsync = ref.watch(generateCodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Коды доступа'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Сгенерировать коды',
            onPressed: () => _showGenerateDialog(context, ref),
          ),
        ],
      ),
      body: newCodesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Ошибка: $e', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (codes) => codes.isEmpty
            ? _EmptyCodesView(onGenerate: () => _showGenerateDialog(context, ref))
            : _NewCodesView(codes: codes),
      ),
    );
  }

  Future<void> _showGenerateDialog(BuildContext context, WidgetRef ref) async {
    int count = 30;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сгенерировать коды'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Количество кодов: $count'),
              Slider(
                value: count.toDouble(),
                min: 1,
                max: 50,
                divisions: 49,
                label: count.toString(),
                onChanged: (v) => setDialogState(() => count = v.round()),
              ),
              const Text(
                '⚠️ Коды показываются только один раз!\nСохраните их сразу после генерации.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref
                  .read(generateCodesProvider.notifier)
                  .generate(classId, count);
            },
            child: const Text('Сгенерировать'),
          ),
        ],
      ),
    );
  }
}

class _EmptyCodesView extends StatelessWidget {
  final VoidCallback onGenerate;

  const _EmptyCodesView({required this.onGenerate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.vpn_key_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Коды ещё не сгенерированы.\nНажмите + чтобы создать.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onGenerate,
            icon: const Icon(Icons.add),
            label: const Text('Сгенерировать коды'),
          ),
        ],
      ),
    );
  }
}

class _NewCodesView extends StatelessWidget {
  final List<String> codes;

  const _NewCodesView({required this.codes});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Предупреждение
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Коды показываются только один раз! Сохраните их прямо сейчас.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        // Кнопка «Скопировать все»
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ElevatedButton.icon(
            key: const Key('copy_all_button'),
            onPressed: () {
              final text = codes.join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${codes.length} кодов скопировано'),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Скопировать все'),
          ),
        ),
        const SizedBox(height: 8),
        // Список кодов
        Expanded(
          child: ListView.builder(
            itemCount: codes.length,
            itemBuilder: (context, index) => ListTile(
              leading: Text(
                '${index + 1}.',
                style: const TextStyle(color: Colors.grey),
              ),
              title: Text(
                codes[index],
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: codes[index]));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Код скопирован')),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

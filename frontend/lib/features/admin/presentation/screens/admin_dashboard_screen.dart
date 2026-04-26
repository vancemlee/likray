import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/admin_providers.dart';

/// Главный дашборд администратора.
/// Показывает список классов с действиями «Коды», «Сессии», «Результаты».
/// Кнопка-FAB создаёт новый класс через POST /admin/classes.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classesAsync = ref.watch(adminClassesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.ballot),
            tooltip: 'Сессии голосования',
            onPressed: () => context.go('/admin/sessions'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () async {
              await ref.read(authNotifierProvider.notifier).logout();
              if (context.mounted) context.go('/admin/login');
            },
          ),
        ],
      ),
      body: classesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: 'Не удалось загрузить классы: $e',
          onRetry: () => ref.invalidate(adminClassesProvider),
        ),
        data: (classes) => classes.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.school_outlined,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text(
                        'Классов ещё нет.\nСоздайте первый класс кнопкой ниже.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showCreateClassDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Создать класс'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                itemCount: classes.length,
                itemBuilder: (context, index) {
                  final cls = classes[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(cls.name.isNotEmpty ? cls.name[0] : '?'),
                      ),
                      title: Text(cls.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Нажмите для управления'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          switch (action) {
                            case 'codes':
                              context
                                  .go('/admin/classes/${cls.id}/codes');
                            case 'sessions':
                              context.go('/admin/sessions');
                            case 'results':
                              context.go('/admin/sessions');
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'codes',
                            child: ListTile(
                              leading: Icon(Icons.vpn_key),
                              title: Text('Коды'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'sessions',
                            child: ListTile(
                              leading: Icon(Icons.ballot),
                              title: Text('Сессии'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'results',
                            child: ListTile(
                              leading: Icon(Icons.bar_chart),
                              title: Text('Результаты'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_class_fab'),
        onPressed: () => _showCreateClassDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Новый класс'),
      ),
    );
  }

  Future<void> _showCreateClassDialog(
      BuildContext context, WidgetRef ref) async {
    int grade = 10;
    final letterCtrl = TextEditingController(text: 'А');
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Создать класс'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: grade,
                decoration: const InputDecoration(labelText: 'Параллель'),
                items: List.generate(11, (i) => i + 1)
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text('$g класс'),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => grade = v ?? grade),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('class_letter_field'),
                controller: letterCtrl,
                decoration: const InputDecoration(
                  labelText: 'Буква',
                  hintText: 'А, Б, В, …',
                ),
                maxLength: 5,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                final letter = letterCtrl.text.trim();
                if (letter.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Введите букву класса')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                try {
                  final created = await ref
                      .read(createClassProvider.notifier)
                      .create(grade, letter);
                  ref.invalidate(adminClassesProvider);
                  if (created != null) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Создан класс ${created.name}')),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось создать класс'),
                      ),
                    );
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Ошибка: $e')),
                  );
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

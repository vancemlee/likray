import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/voting_session_model.dart';
import '../providers/admin_providers.dart';

/// Экран управления сессиями голосования.
/// Кнопки «Открыть»/«Закрыть» меняют статус сессии.
/// Кнопка «Результаты» ведёт на results_screen.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(adminSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Сессии голосования'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin'),
        ),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Ошибка загрузки: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(adminSessionsProvider),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        data: (sessions) => sessions.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.ballot_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Сессий пока нет.\nСоздайте первую.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateDialog(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Создать сессию'),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        session.label,
                        style:
                            const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(session.statusLabel),
                      leading: CircleAvatar(
                        backgroundColor: session.isOpen
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        child: Icon(
                          session.isOpen
                              ? Icons.lock_open
                              : Icons.lock_outline,
                          color: session.isOpen
                              ? Colors.green.shade700
                              : Colors.grey,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _SessionToggleButton(session: session),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.bar_chart),
                            tooltip: 'Результаты',
                            onPressed: () => context
                                .go('/admin/sessions/${session.id}/results'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create_session_fab'),
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Новая сессия'),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    int quarter = 1;
    int year = DateTime.now().year;
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Создать сессию голосования'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: quarter,
                decoration: const InputDecoration(labelText: 'Четверть'),
                items: [1, 2, 3, 4]
                    .map((q) => DropdownMenuItem(
                          value: q,
                          child: Text('$q четверть'),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => quarter = v ?? quarter),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: year.toString(),
                decoration: const InputDecoration(labelText: 'Год'),
                keyboardType: TextInputType.number,
                onChanged: (v) => year = int.tryParse(v) ?? year,
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
                Navigator.pop(ctx);
                try {
                  final created = await ref
                      .read(createSessionProvider.notifier)
                      .create(quarter, year);
                  ref.invalidate(adminSessionsProvider);
                  if (created != null) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Создана сессия: ${created.label}'),
                      ),
                    );
                  } else {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Не удалось создать сессию'),
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

class _SessionToggleButton extends ConsumerWidget {
  final VotingSessionModel session;

  const _SessionToggleButton({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionAsync = ref.watch(sessionActionProvider);
    final isLoading = actionAsync is AsyncLoading;

    return isLoading
        ? const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            icon: Icon(
              session.isOpen ? Icons.lock : Icons.lock_open,
              color: session.isOpen ? Colors.orange : Colors.green,
            ),
            tooltip: session.isOpen ? 'Закрыть' : 'Открыть',
            onPressed: () async {
              final notifier = ref.read(sessionActionProvider.notifier);
              if (session.isOpen) {
                await notifier.closeSession(session.id);
              } else {
                await notifier.openSession(session.id);
              }
              ref.invalidate(adminSessionsProvider);
            },
          );
  }
}

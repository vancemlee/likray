import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../core/storage/token_storage.dart';
import '../providers/student_providers.dart';
import '../widgets/question_block.dart';

/// Экран анкеты ученика.
///
/// Загружает структуру анкеты через GET /votes/active (JWT в Authorization).
/// Рендерит 5 блоков динамически по типу из ответа бэка.
/// Прогресс-бар отображает процент заполненных блоков.
/// После успешной отправки — удаляет student_token и переходит на /thank-you.
class QuestionnaireScreen extends ConsumerWidget {
  const QuestionnaireScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voteAsync = ref.watch(activeVoteProvider);

    return voteAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  e is ApiException
                      ? studentFriendlyError(e)
                      : 'Не удалось загрузить анкету',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(activeVoteProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (voteData) => _QuestionnaireBody(voteData: voteData),
    );
  }
}

class _QuestionnaireBody extends ConsumerStatefulWidget {
  final dynamic voteData;

  const _QuestionnaireBody({required this.voteData});

  @override
  ConsumerState<_QuestionnaireBody> createState() =>
      _QuestionnaireBodyState();
}

class _QuestionnaireBodyState extends ConsumerState<_QuestionnaireBody> {
  bool _isSubmitting = false;
  String? _submitError;

  Future<void> _submit() async {
    final answers = ref.read(surveyAnswersProvider);
    if (!answers.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполни все обязательные поля')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      await ref.read(voteSubmitProvider.notifier).submit(answers);

      // Инвалидируем токен после успешного голосования
      await ref.read(tokenStorageProvider).deleteStudentToken();

      if (mounted) {
        context.go('/thank-you');
      }
    } on ApiException catch (e) {
      setState(() => _submitError = studentFriendlyError(e));
    } catch (_) {
      setState(() => _submitError = 'Ошибка при отправке. Попробуйте ещё раз.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.voteData.blocks as List<Map<String, dynamic>>;
    final voteData = widget.voteData;

    return Scaffold(
      appBar: AppBar(
        title: Text('${voteData.className} — ${voteData.quarterLabel}'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Прогресс-бар: фиксированное число блоков = 5
          LinearProgressIndicator(
            value: blocks.isEmpty ? 0 : 1.0,
            backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in blocks)
                    QuestionBlock(
                      key: ValueKey(block['key']),
                      block: block,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _submitError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ElevatedButton(
                key: const Key('submit_vote_button'),
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Отправить голос'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

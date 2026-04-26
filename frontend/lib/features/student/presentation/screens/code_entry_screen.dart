import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_exceptions.dart';
import '../../../../core/storage/token_storage.dart';
import '../../data/student_repository.dart';

/// Экран ввода одноразового кода ученика.
///
/// Flow:
///   1. Ученик вводит 8-значный код.
///   2. POST /auth/student/redeem → получаем student_token.
///   3. Токен сохраняется в secure_storage.
///   4. Переход на /questionnaire.
///
/// Ошибки показываются понятными русскими сообщениями.
class CodeEntryScreen extends ConsumerStatefulWidget {
  const CodeEntryScreen({super.key});

  @override
  ConsumerState<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends ConsumerState<CodeEntryScreen> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(studentRepositoryProvider);
      final result = await repo.redeemCode(code);

      // Сохраняем анонимный JWT в защищённом хранилище
      await ref.read(tokenStorageProvider).saveStudentToken(result.accessToken);

      if (mounted) {
        context.go('/questionnaire');
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = studentFriendlyError(e);
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Что-то пошло не так. Попробуйте ещё раз.';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = _codeController.text.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.how_to_vote_outlined,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Likray',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Введи код, который выдал классный руководитель',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: 'Код доступа',
                      hintText: 'Например: ABCD1234',
                      errorText: _errorMessage,
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: hasText
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _codeController.clear();
                                setState(() => _errorMessage = null);
                              },
                            )
                          : null,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                    enabled: !_isLoading,
                  ),
                  const SizedBox(height: 24),
                  // Кнопка disabled если поле пустое или идёт загрузка
                  ElevatedButton(
                    key: const Key('submit_button'),
                    onPressed: (hasText && !_isLoading) ? _submit : null,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
                  ),
                  const SizedBox(height: 16),
                  // Ссылка для администраторов
                  TextButton(
                    onPressed: () => context.go('/admin/login'),
                    child: Text(
                      'Войти как администратор',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

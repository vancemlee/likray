import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'features/admin/presentation/providers/admin_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Path-based URLs на web: /admin/login вместо /#/admin/login.
  // На остальных платформах вызов — no-op.
  usePathUrlStrategy();

  // Создаём контейнер заранее, чтобы инициализировать auth-состояние
  // из secure_storage до первой отрисовки (избегаем «моргания» редиректа).
  final container = ProviderContainer();
  await container.read(authNotifierProvider.notifier).initialize();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LikrayApp(),
    ),
  );
}

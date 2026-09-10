import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/theme_controller.dart';
import 'router.dart';
import 'ui/theme.dart';

class AyeayeApp extends ConsumerWidget {
  const AyeayeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return ShadApp.router(
      title: 'ayeaye',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      materialThemeBuilder: AppTheme.material,
      // ShadToaster has to sit above the router so a toast survives a push.
      builder: (context, child) => ShadToaster(child: child ?? const SizedBox()),
    );
  }
}

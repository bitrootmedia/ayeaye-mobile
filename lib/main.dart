import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'app.dart';
import 'core/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolved up front so screens can read filter and sort choices
  // synchronously; they are tiny and the app cannot draw a list without them.
  final prefs = await SharedPreferences.getInstance();

  timeago.setLocaleMessages('en_short', timeago.EnShortMessages());

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(Prefs(prefs))],
      child: const AyeayeApp(),
    ),
  );
}

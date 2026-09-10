import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Checks every endpoint the app calls against the instance's own OpenAPI
/// document.
///
/// The spec is the only authority on these paths — `SITE_URL/api/openapi.json`
/// covers all 151 of them — and a typo in one is invisible until somebody taps
/// the screen that uses it. This turns that into a failing test.
///
/// The `/api/auth/*` routes are deliberately excluded: SuperTokens' middleware
/// serves them rather than FastAPI, so they are not in the document at all.
void main() {
  late Set<String> specPaths;
  late String repoSource;

  setUpAll(() {
    final spec = jsonDecode(File('tool/openapi.json').readAsStringSync())
        as Map<String, dynamic>;
    specPaths = (spec['paths'] as Map<String, dynamic>)
        .keys
        .map(_normalise)
        .toSet();
    repoSource = File('lib/core/api/repo.dart').readAsStringSync();
  });

  /// `/api/organisations/{org_id}/tasks/{task_id}` and
  /// `/api/organisations/o1/tasks/$taskId` both become
  /// `/api/organisations/{}/tasks/{}`.
  test('the spec parsed and looks like ayeaye', () {
    expect(specPaths, contains('/api/me'));
    expect(specPaths, contains('/api/organisations/{}/tasks'));
    expect(specPaths.length, greaterThan(140));
  });

  test('every path the repository builds exists in the spec', () {
    final called = _pathsCalledBy(repoSource);
    expect(called, isNotEmpty, reason: 'the extractor found nothing to check');

    final missing = called.where((p) => !specPaths.contains(p)).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'these are not in the API spec:\n${missing.join('\n')}',
    );
  });

  test('it covers the areas the endpoint map lists', () {
    final called = _pathsCalledBy(repoSource);
    // A guard against a whole feature silently losing its wiring.
    for (final expected in [
      '/api/me',
      '/api/me/tokens',
      '/api/me/mfa/status',
      '/api/notifications',
      '/api/reminders',
      '/api/sparks',
      '/api/organisations',
      '/api/organisations/{}/tasks',
      '/api/organisations/{}/tasks/board',
      '/api/organisations/{}/tasks/{}/comments',
      '/api/organisations/{}/tasks/{}/attachments',
      '/api/organisations/{}/attachments/{}/confirm',
      '/api/organisations/{}/dashboard',
      '/api/organisations/{}/planner',
      '/api/organisations/{}/calendar',
      '/api/organisations/{}/search',
      '/api/organisations/{}/bookmarks',
      '/api/organisations/{}/kb/books',
      '/api/organisations/{}/time/entries',
      '/api/me/timer',
    ]) {
      expect(called, contains(expected), reason: expected);
    }
  });
}

String _normalise(String path) => path.replaceAll(RegExp(r'\{[^}]*\}'), '{}');

/// Pulls the path literals out of the repository's source.
///
/// Crude on purpose: the repository is deliberately flat — every method is a
/// path plus a decode — so a regex over its string literals is an accurate
/// inventory of what the app can ask for.
Set<String> _pathsCalledBy(String source) {
  final out = <String>{};
  final literals = RegExp(r"'((?:/api|\$\{_org\(orgId\)\})[^']*)'");

  for (final match in literals.allMatches(source)) {
    var path = match.group(1)!;
    // The org-scoped helper expands to the spec's own prefix.
    path = path.replaceAll(r'${_org(orgId)}', '/api/organisations/{org_id}');
    // `$taskId`, `${x}` and `{org_id}` all become a placeholder.
    path = path.replaceAll(RegExp(r'\$\{[^}]*\}'), '{}');
    path = path.replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '{}');
    path = _normalise(path);
    // SuperTokens serves these; they are not in the document.
    if (path.startsWith('/api/auth/')) continue;
    out.add(path);
  }
  return out;
}

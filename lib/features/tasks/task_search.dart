import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/states.dart';

/// Search across the organisation.
///
/// One endpoint returns tasks, projects, articles and people together, so this
/// groups hits by kind rather than pretending they are one list.
Future<void> showTaskSearch(BuildContext context) => showShadSheet<void>(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (context) => const _SearchSheet(),
    );

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  SearchOut? _results;
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Debounced: search runs server-side and a request per keystroke would
  /// punish both the phone and the instance.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _run(value));
  }

  Future<void> _run(String value) async {
    final query = value.trim();
    setState(() {
      _query = query;
      _error = null;
    });
    if (query.length < 2) {
      setState(() {
        _results = null;
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final orgId = ref.read(requireOrgIdProvider);
      final results = await ref.read(repoProvider).search(orgId, query);
      if (!mounted || _query != query) return;
      setState(() {
        _results = results;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ShadSheet(
        title: const Text('Search'),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.62,
          child: Column(
            children: [
              ShadInput(
                controller: _controller,
                placeholder: const Text('Tasks, projects, articles, people'),
                autofocus: true,
                leading: Icon(
                  LucideIcons.search,
                  size: 16,
                  color: context.colors.mutedForeground,
                ),
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: _run,
              ),
              const SizedBox(height: Gap.md),
              Expanded(child: _body()),
            ],
          ),
        ),
      );

  Widget _body() {
    if (_error != null) {
      return ErrorView(error: _error!, onRetry: () => _run(_query));
    }
    if (_busy && _results == null) return const LoadingView();
    if (_query.length < 2) {
      return const EmptyState(
        icon: LucideIcons.search,
        title: 'Search this organisation',
        message: 'Type at least two characters.',
      );
    }
    final hits = _results?.hits ?? const <SearchHitOut>[];
    if (hits.isEmpty) {
      return EmptyState(
        icon: LucideIcons.searchX,
        title: 'Nothing found',
        message: 'No matches for "$_query".',
      );
    }

    final grouped = <String, List<SearchHitOut>>{};
    for (final hit in hits) {
      grouped.putIfAbsent(hit.kind, () => []).add(hit);
    }

    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: Gap.sm, bottom: 4),
            child: Text(
              _kindLabel(entry.key, entry.value.length),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: context.colors.mutedForeground,
              ),
            ),
          ),
          for (final hit in entry.value) _HitRow(hit: hit),
        ],
      ],
    );
  }

  static String _kindLabel(String kind, int count) => switch (kind) {
        'task' => 'TASKS ($count)',
        'project' => 'PROJECTS ($count)',
        'article' => 'ARTICLES ($count)',
        'person' || 'member' => 'PEOPLE ($count)',
        'book' => 'BOOKS ($count)',
        'note' => 'NOTES ($count)',
        'bookmark' => 'BOOKMARKS ($count)',
        _ => '${kind.toUpperCase()} ($count)',
      };
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit});

  final SearchHitOut hit;

  @override
  Widget build(BuildContext context) {
    final destination = _destinationFor(hit);
    return InkWell(
      onTap: destination == null
          ? null
          : () {
              Navigator.of(context).pop();
              context.push(destination);
            },
      child: Padding
      (
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          children: [
            Icon(
              _iconFor(hit.kind),
              size: 15,
              color: context.colors.mutedForeground,
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: hit.inactive
                          ? context.colors.mutedForeground
                          : context.colors.foreground,
                      decoration:
                          hit.inactive ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (hit.subtitle != null || hit.context != null)
                    Text(
                      [hit.subtitle, hit.context]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.colors.mutedForeground,
                      ),
                    ),
                ],
              ),
            ),
            if (destination != null)
              Icon(
                LucideIcons.chevronRight,
                size: 15,
                color: context.colors.mutedForeground,
              ),
          ],
        ),
      ),
    );
  }

  /// Only the kinds this app has a screen for are tappable; the rest still
  /// show, because knowing a thing exists is useful even here.
  static String? _destinationFor(SearchHitOut hit) => switch (hit.kind) {
        'task' => '/task/${hit.id}',
        'article' => '/kb/article/${hit.id}',
        'book' => '/kb/book/${hit.id}',
        _ => null,
      };

  static IconData _iconFor(String kind) => switch (kind) {
        'task' => LucideIcons.listTodo,
        'project' => LucideIcons.folder,
        'article' => LucideIcons.fileText,
        'book' => LucideIcons.bookMarked,
        'person' || 'member' => LucideIcons.user,
        'note' => LucideIcons.stickyNote,
        'bookmark' => LucideIcons.bookmark,
        _ => LucideIcons.circleDot,
      };
}

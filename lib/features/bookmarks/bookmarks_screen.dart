import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/theme.dart';
import '../../ui/toast.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';

final bookmarksProvider = FutureProvider<List<BookmarkOut>>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const [];
  return ref.watch(repoProvider).bookmarks(orgId);
});

/// Links the team keeps. Pinned ones first, as the server orders them.
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarksProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        leading: const HeaderBack(),
        title: const HeaderTitle('Bookmarks'),
        actions: [
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.plus, size: 18),
            onPressed: () => _add(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(bookmarksProvider),
        child: AsyncView(
          value: bookmarks,
          onRetry: () => ref.invalidate(bookmarksProvider),
          data: (items) {
            if (items.isEmpty) {
              return CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    child: EmptyState(
                      icon: LucideIcons.bookmark,
                      title: 'No bookmarks',
                      message: 'Links worth keeping for the whole team.',
                      action: ShadButton(
                        onPressed: () => _add(context, ref),
                        leading: const Icon(LucideIcons.plus, size: 16),
                        child: const Text('Add a link'),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _Row(bookmark: items[index]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final orgId = ref.read(currentOrgIdProvider);
    if (orgId == null) {
      showToast(context, 'Pick an organisation first');
      return;
    }
    final url = TextEditingController();
    final description = TextEditingController();
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog(
        title: const Text('New bookmark'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          child: Column(
            children: [
              ShadInputFormField(
                controller: url,
                label: const Text('URL'),
                placeholder: const Text('https://…'),
                keyboardType: TextInputType.url,
                autocorrect: false,
                autofocus: true,
              ),
              const SizedBox(height: Gap.md),
              ShadInputFormField(
                controller: description,
                label: const Text('Description'),
                maxLength: 300,
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || url.text.trim().isEmpty || !context.mounted) return;
    await runGuarded(
      context,
      () => ref.read(repoProvider).createBookmark(
            orgId,
            url: url.text.trim(),
            description: description.text.trim(),
          ),
      success: 'Saved',
    );
    ref.invalidate(bookmarksProvider);
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.bookmark});

  final BookmarkOut bookmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
        onTap: () async {
          final uri = Uri.tryParse(bookmark.url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.md,
          ),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.colors.border)),
          ),
          child: Row(
            children: [
              Icon(
                bookmark.pinned ? LucideIcons.pin : LucideIcons.link,
                size: 15,
                color: bookmark.pinned
                    ? context.colors.primary
                    : context.colors.mutedForeground,
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.description.isEmpty
                          ? _host(bookmark.url)
                          : bookmark.description,
                      maxLines: 2,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      bookmark.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.muted,
                    ),
                  ],
                ),
              ),
              if (bookmark.canEdit)
                ShadIconButton.ghost(
                  width: 30,
                  height: 30,
                  icon: Icon(
                    bookmark.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                    size: 14,
                  ),
                  onPressed: () async {
                    final orgId = ref.read(requireOrgIdProvider);
                    await runGuarded(
                      context,
                      () => ref.read(repoProvider).setBookmarkPinned(
                            orgId,
                            bookmark.id,
                            !bookmark.pinned,
                          ),
                    );
                    ref.invalidate(bookmarksProvider);
                  },
                ),
            ],
          ),
        ),
      );

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;
}

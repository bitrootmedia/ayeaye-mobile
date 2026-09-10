import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api/repo.dart';
import '../../core/models/models.dart';
import '../../core/org_controller.dart';
import '../../ui/format.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/rich_body.dart';
import '../../ui/widgets/screen_header.dart';
import '../../ui/widgets/states.dart';

final booksProvider = FutureProvider<List<BookOut>>((ref) async {
  final orgId = ref.watch(currentOrgIdProvider);
  if (orgId == null) return const [];
  return ref.watch(repoProvider).books(orgId);
});

final articlesProvider =
    FutureProvider.family<List<ArticleOut>, String>((ref, bookId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).articles(orgId, bookId);
});

final articleProvider =
    FutureProvider.family<ArticleOut, String>((ref, articleId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).article(orgId, articleId);
});

/// An article's current revision — where the body actually lives.
final articleBodyProvider =
    FutureProvider.family<RevisionOut?, String>((ref, articleId) async {
  final orgId = ref.watch(requireOrgIdProvider);
  return ref.watch(repoProvider).currentRevision(orgId, articleId);
});

/// The knowledge base, for reading.
///
/// Authoring stays on the web: the body is sanitised HTML on a narrow
/// allow-list, and a phone is a poor place to write a reference document. What
/// a phone *is* good for is looking something up, so that is what this does.
class BooksScreen extends ConsumerWidget {
  const BooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: const ScreenHeader(
        leading: HeaderBack(),
        title: HeaderTitle('Knowledge base'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(booksProvider),
        child: AsyncView(
          value: books,
          onRetry: () => ref.invalidate(booksProvider),
          data: (items) {
            if (items.isEmpty) {
              return const CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    child: EmptyState(
                      icon: LucideIcons.bookMarked,
                      title: 'No books yet',
                      message: 'Books and articles created on the web show up '
                          'here to read.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final book = items[index];
                return InkWell(
                  onTap: () => context.push('/kb/book/${book.id}'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.lg,
                      vertical: Gap.md,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.colors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.book,
                          size: 17,
                          color: context.colors.mutedForeground,
                        ),
                        const SizedBox(width: Gap.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.name,
                                style: context.texts.p.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if ((book.description ?? '').isNotEmpty)
                                Text(
                                  book.description!,
                                  maxLines: 2,
                                  style: context.texts.muted,
                                ),
                            ],
                          ),
                        ),
                        CountBadge(book.articleCount),
                        const SizedBox(width: Gap.sm),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: context.colors.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class BookScreen extends ConsumerWidget {
  const BookScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(articlesProvider(bookId));
    final book = ref
        .watch(booksProvider)
        .value
        ?.where((b) => b.id == bookId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        leading: const HeaderBack(),
        title: HeaderTitle(book?.name ?? 'Book'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(articlesProvider(bookId)),
        child: AsyncView(
          value: articles,
          onRetry: () => ref.invalidate(articlesProvider(bookId)),
          data: (items) {
            if (items.isEmpty) {
              return const CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    child: EmptyState(
                      icon: LucideIcons.fileText,
                      title: 'No articles',
                      message: 'This book is empty, or its articles are still '
                          'private drafts.',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final article = items[index];
                return InkWell(
                  onTap: () => context.push('/kb/article/${article.id}'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Gap.lg,
                      vertical: Gap.md,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.colors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                article.title.isEmpty
                                    ? 'Untitled'
                                    : article.title,
                                style: context.texts.p,
                              ),
                              Text(
                                'Updated ${Fmt.ago(article.updatedAt)}',
                                style: context.texts.muted,
                              ),
                            ],
                          ),
                        ),
                        if (article.isPrivate)
                          ShadBadge.outline(child: const Text('Draft')),
                        const SizedBox(width: Gap.sm),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: context.colors.mutedForeground,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class ArticleScreen extends ConsumerWidget {
  const ArticleScreen({super.key, required this.articleId});

  final String articleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final article = ref.watch(articleProvider(articleId));
    final body = ref.watch(articleBodyProvider(articleId));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: ScreenHeader(
        leading: const HeaderBack(),
        title: HeaderTitle(article.value?.title ?? 'Article'),
      ),
      body: AsyncView(
        value: article,
        onRetry: () => ref.invalidate(articleProvider(articleId)),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(articleProvider(articleId));
            ref.invalidate(articleBodyProvider(articleId));
          },
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              Text(
                data.title.isEmpty ? 'Untitled' : data.title,
                style: context.texts.h3,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                'By ${Fmt.person(data.owner?.displayName, data.owner?.email)} '
                '· updated ${Fmt.ago(data.updatedAt)}',
                style: context.texts.muted,
              ),
              const SizedBox(height: Gap.lg),
              AsyncView(
                value: body,
                onRetry: () => ref.invalidate(articleBodyProvider(articleId)),
                loading: const Padding(
                  padding: EdgeInsets.all(Gap.xl),
                  child: LoadingView(),
                ),
                data: (revision) => revision == null
                    ? Text('This article has no content yet.',
                        style: context.texts.muted)
                    : RichBody(
                        revision.body,
                        baseUrl: ref.watch(repoProvider).api.baseUrl,
                      ),
              ),
              const SizedBox(height: Gap.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

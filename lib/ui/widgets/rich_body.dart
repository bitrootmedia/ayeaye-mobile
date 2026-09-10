import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// Renders a task description or article body.
///
/// The server stores **sanitised HTML** on an allow-list: `h2`/`h3`, lists,
/// `strong`/`em`, links, code blocks carrying `language-*` classes, and images
/// carrying `data-attachment-id`. So the app *renders* HTML — and edits as
/// markdown, since the write endpoints accept `description_format: markdown`
/// and no Flutter editor emits the allow-listed shape.
///
/// Old descriptions are plain text and stay that way: a body with no `<` in it
/// is rendered with its whitespace preserved rather than fed through an HTML
/// parser, which would collapse the line breaks somebody typed.
class RichBody extends StatelessWidget {
  const RichBody(
    this.body, {
    super.key,
    this.baseUrl,
    this.textStyle,
    this.onTapLink,
  });

  final String? body;

  /// Resolves same-origin `/media/*` image sources.
  final String? baseUrl;

  final TextStyle? textStyle;
  final void Function(String url)? onTapLink;

  bool get _isEmpty => (body ?? '').trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isEmpty) return const SizedBox.shrink();
    final text = body!;
    final style = textStyle ??
        context.texts.p.copyWith(height: 1.5, color: context.colors.foreground);

    if (!text.contains('<')) {
      return SelectableText(text, style: style);
    }

    return HtmlWidget(
      text,
      baseUrl: baseUrl == null ? null : Uri.tryParse(baseUrl!),
      textStyle: style,
      renderMode: RenderMode.column,
      customStylesBuilder: (element) => switch (element.localName) {
        // The product only has h2/h3 — `#` is promoted to `##` on write — so
        // these are the only headings that can appear.
        'h2' => {'font-size': '17px', 'font-weight': '600', 'margin': '14px 0 6px'},
        'h3' => {'font-size': '15px', 'font-weight': '600', 'margin': '12px 0 4px'},
        'p' => {'margin': '0 0 10px'},
        'ul' || 'ol' => {'margin': '0 0 10px'},
        'li' => {'margin': '0 0 3px'},
        'code' => {'font-family': 'monospace', 'font-size': '13px'},
        'pre' => {'margin': '0 0 10px'},
        'a' => {'text-decoration': 'none'},
        'blockquote' => {'margin': '0 0 10px 0', 'padding-left': '12px'},
        _ => null,
      },
      customWidgetBuilder: (element) {
        if (element.localName == 'pre') {
          return _CodeBlock(element.text);
        }
        if (element.localName == 'blockquote') {
          return _Quote(element.text);
        }
        return null;
      },
      onTapUrl: (url) async {
        if (onTapLink != null) {
          onTapLink!(url);
          return true;
        }
        final uri = Uri.tryParse(url);
        if (uri == null) return false;
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      },
      onErrorBuilder: (_, element, _) =>
          Text(element.text, style: style),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.code);

  final String code;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: Gap.md),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: context.colors.muted,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.colors.border),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            code.trimRight(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.45,
              color: context.colors.foreground,
            ),
          ),
        ),
      );
}

class _Quote extends StatelessWidget {
  const _Quote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: Gap.md),
        padding: const EdgeInsets.only(left: Gap.md),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: context.colors.border, width: 3),
          ),
        ),
        child: Text(
          text.trim(),
          style: context.texts.p.copyWith(
            color: context.colors.mutedForeground,
            fontStyle: FontStyle.italic,
            height: 1.5,
          ),
        ),
      );
}

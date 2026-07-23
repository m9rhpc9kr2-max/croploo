import 'package:flutter/material.dart';

import '../../core/theme/typography.dart';

/// Renders CullyAI's markdown-flavored replies as actual formatted text
/// instead of showing the raw `##`/`**`/`-` syntax. Deliberately not a full
/// markdown engine — just the handful of things Claude actually emits in
/// chat replies (headings, **bold**, bullet lists) — kept lightweight and
/// styled to this app's own type scale rather than a generic markdown look.
class FormattedAiText extends StatelessWidget {
  final String text;
  final Color baseColor;
  final Color headingColor;
  final Color accentColor;

  const FormattedAiText({
    super.key,
    required this.text,
    required this.baseColor,
    required this.headingColor,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final blocks = <Widget>[];
    var isFirstBlock = true;

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;

      final heading = _headingLevel(line);
      final bullet = _asBullet(line);

      if (heading != null) {
        blocks.add(Padding(
          padding: EdgeInsets.only(top: isFirstBlock ? 0 : 14, bottom: 4),
          child: _RichLine(
            spans: _parseInline(heading.text, _headingStyle(heading.level, headingColor)),
          ),
        ));
      } else if (bullet != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 3, left: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 1),
                child: Text('→',
                    style: CroplooText.bodyStrong.copyWith(
                        color: accentColor, fontSize: 13)),
              ),
              Expanded(
                child: _RichLine(
                  spans: _parseInline(
                      bullet,
                      CroplooText.body.copyWith(color: baseColor, fontSize: 13, height: 1.55)),
                ),
              ),
            ],
          ),
        ));
      } else {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 2),
          child: _RichLine(
            spans: _parseInline(
                line,
                CroplooText.body.copyWith(color: baseColor, fontSize: 13, height: 1.55)),
          ),
        ));
      }
      isFirstBlock = false;
    }

    if (blocks.isEmpty) {
      return Text('…', style: CroplooText.body.copyWith(color: baseColor, fontSize: 13));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocks);
  }

  TextStyle _headingStyle(int level, Color color) {
    switch (level) {
      case 1:
        return CroplooText.h3.copyWith(color: color, fontSize: 16, fontWeight: FontWeight.w700);
      case 2:
        return CroplooText.h3.copyWith(color: color, fontSize: 14.5, fontWeight: FontWeight.w700);
      default:
        return CroplooText.h3.copyWith(color: color, fontSize: 13.5, fontWeight: FontWeight.w600);
    }
  }

  ({int level, String text})? _headingLevel(String line) {
    final match = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (match == null) return null;
    return (level: match.group(1)!.length, text: match.group(2)!.trim());
  }

  String? _asBullet(String line) {
    final match = RegExp(r'^[-*•]\s+(.*)$').firstMatch(line);
    return match?.group(1)?.trim();
  }

  /// Parses `**bold**` / `*bold*` segments out of [line], stripping the
  /// asterisks and applying [style] with a bold weight to those spans.
  List<InlineSpan> _parseInline(String line, TextStyle style) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*');
    var cursor = 0;

    for (final match in pattern.allMatches(line)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: line.substring(cursor, match.start), style: style));
      }
      final boldText = match.group(1) ?? match.group(2) ?? '';
      spans.add(TextSpan(
        text: boldText,
        style: style.copyWith(fontWeight: FontWeight.w700),
      ));
      cursor = match.end;
    }
    if (cursor < line.length) {
      spans.add(TextSpan(text: line.substring(cursor), style: style));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: line, style: style));
    }
    return spans;
  }
}

class _RichLine extends StatelessWidget {
  final List<InlineSpan> spans;

  const _RichLine({required this.spans});

  @override
  Widget build(BuildContext context) {
    return RichText(text: TextSpan(children: spans));
  }
}

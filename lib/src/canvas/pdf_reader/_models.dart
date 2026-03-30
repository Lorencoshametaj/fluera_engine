part of 'pdf_reader_screen.dart';

/// Reading mode for PDF pages.
enum _ReadingMode { light, dark, sepia }

/// Data for a single bookmark.
class _BookmarkData {
  final Color color;
  String note;
  _BookmarkData({this.color = const Color(0xFFEF5350), this.note = ''});
}

/// Simple search match (standalone, no PdfDocumentNode needed).
class _SimpleSearchMatch {
  final int pageIndex;
  final int startOffset;
  final int endOffset;
  final String snippet;

  const _SimpleSearchMatch({
    required this.pageIndex,
    required this.startOffset,
    required this.endOffset,
    required this.snippet,
  });
}

/// Simple page text data holder (text + geometry rects).
class _PageTextData {
  final String text;
  final List<PdfTextRect> rects;

  const _PageTextData({required this.text, required this.rects});
}

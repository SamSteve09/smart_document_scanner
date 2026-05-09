import 'dart:io';

class DocumentDraft {
  final File sourceFile;
  String extractedText;
  String title;
  String category;
  String tagsText;
  final DateTime capturedAt;

  DocumentDraft({
    required this.sourceFile,
    required this.extractedText,
    required this.title,
    required this.category,
    required this.tagsText,
    DateTime? capturedAt,
  }) : capturedAt = capturedAt ?? DateTime.now();

  List<String> get tags => tagsText
      .split(',')
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
}

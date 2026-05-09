class DocumentRecord {
  final String id;
  final String title;
  final String category;
  final String imagePath;
  final String extractedText;
  final List<String> tags;
  final DateTime capturedAt;

  const DocumentRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.imagePath,
    required this.extractedText,
    required this.tags,
    required this.capturedAt,
  });

  factory DocumentRecord.fromJson(Map<String, dynamic> json) => DocumentRecord(
    id: json['id'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    imagePath: json['imagePath'] as String,
    extractedText: json['extractedText'] as String,
    tags: (json['tags'] as List<dynamic>).map((tag) => tag as String).toList(),
    capturedAt: DateTime.parse(json['capturedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'imagePath': imagePath,
    'extractedText': extractedText,
    'tags': tags,
    'capturedAt': capturedAt.toIso8601String(),
  };

  DocumentRecord copyWith({
    String? id,
    String? title,
    String? category,
    String? imagePath,
    String? extractedText,
    List<String>? tags,
    DateTime? capturedAt,
  }) {
    return DocumentRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      imagePath: imagePath ?? this.imagePath,
      extractedText: extractedText ?? this.extractedText,
      tags: tags ?? this.tags,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}

import 'package:smart_document_scanner/models/document_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DocumentRecord serializes and deserializes', () {
    final record = DocumentRecord(
      id: '1',
      title: 'Invoice 123',
      category: 'Invoice',
      imagePath: '/tmp/invoice.jpg',
      extractedText: 'Invoice text',
      tags: ['invoice', 'paid'],
      capturedAt: DateTime.parse('2026-05-09T10:00:00Z'),
    );

    final decoded = DocumentRecord.fromJson(record.toJson());

    expect(decoded.id, record.id);
    expect(decoded.title, record.title);
    expect(decoded.category, record.category);
    expect(decoded.imagePath, record.imagePath);
    expect(decoded.extractedText, record.extractedText);
    expect(decoded.tags, record.tags);
    expect(decoded.capturedAt, record.capturedAt);
  });
}

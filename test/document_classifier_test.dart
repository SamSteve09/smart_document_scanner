import 'package:smart_document_scanner/services/document_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Classifies receipt text as Receipt', () {
    const text = 'Supermarket\nReceipt\nSubtotal 24.50\nTax 2.45\nTotal 26.95';
    expect(DocumentClassifier.suggestCategory(text), 'Receipt');
  });

  test('Suggests title from first meaningful line', () {
    const text = 'Acme Corporation\nInvoice No 123\nAmount Due 99.00';
    expect(
      DocumentClassifier.suggestTitle(text, category: 'Invoice'),
      'Acme Corporation',
    );
  });

  test('Extracts useful tags', () {
    const text = 'Invoice\nDue date: 2026-05-09\nSignature required';
    expect(
      DocumentClassifier.suggestTags(text),
      containsAll(['invoice', 'date', 'signature']),
    );
  });

  test('Classifies Indonesian receipt text as Receipt', () {
    const text =
        'Minimarket\nStruk\nSubtotal 24.500\nPajak 2.450\nTotal 26.950';
    expect(DocumentClassifier.suggestCategory(text), 'Receipt');
  });
}

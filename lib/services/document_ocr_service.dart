import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:image/image.dart' as img;

import '../models/document_draft.dart';
import 'document_classifier.dart';

class DocumentOcrService {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final LanguageIdentifier _languageIdentifier = LanguageIdentifier(
    confidenceThreshold: 0.4,
  );

  Future<DocumentDraft> scan(File imageFile) async {
    final processed = await _preprocessImage(imageFile);
    final processedText = await _recognizeAndCleanText(processed);
    final originalText = processed.path == imageFile.path
        ? processedText
        : await _recognizeAndCleanText(imageFile);
    final text = _chooseBetterText(processedText, originalText);

    String language = 'en';
    try {
      final lang = await _languageIdentifier.identifyLanguage(text);
      if (lang.isNotEmpty && lang != 'und') {
        language = lang;
      } else {
        language = DocumentClassifier.detectLanguage(text.toLowerCase());
      }
    } catch (e) {
      language = DocumentClassifier.detectLanguage(text.toLowerCase());
    }

    final category = DocumentClassifier.suggestCategory(
      text,
      language: language,
    );
    final title = DocumentClassifier.suggestTitle(text, category: category);
    final tags = DocumentClassifier.suggestTags(text).join(', ');

    return DocumentDraft(
      sourceFile: imageFile,
      extractedText: text,
      title: title,
      category: category,
      tagsText: tags,
    );
  }

  void dispose() {
    _recognizer.close();
    _languageIdentifier.close();
  }

  Future<File> _preprocessImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return file;

      img.Image gray = img.grayscale(image);
      gray = img.adjustColor(gray, contrast: 1.1, gamma: 0.95);

      const maxDim = 1600;
      if (gray.width > maxDim || gray.height > maxDim) {
        final isWide = gray.width > gray.height;
        gray = img.copyResize(
          gray,
          width: isWide ? maxDim : null,
          height: isWide ? null : maxDim,
        );
      }

      final out = img.encodeJpg(gray, quality: 90);
      final tmp = File(
        '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}_proc.jpg',
      );
      await tmp.writeAsBytes(out);
      return tmp;
    } catch (e) {
      return file;
    }
  }

  Future<String> _recognizeAndCleanText(File file) async {
    final inputImage = InputImage.fromFilePath(file.path);
    final recognized = await _recognizer.processImage(inputImage);
    final rawText = _extractOrderedText(recognized);
    return _postProcessText(rawText);
  }

  String _extractOrderedText(RecognizedText recognized) {
    final blocks = recognized.blocks.toList()
      ..sort((a, b) {
        final aTop = a.boundingBox.top;
        final bTop = b.boundingBox.top;
        final topCompare = aTop.compareTo(bTop);
        if (topCompare != 0) return topCompare;
        final aLeft = a.boundingBox.left;
        final bLeft = b.boundingBox.left;
        return aLeft.compareTo(bLeft);
      });

    final lines = <String>[];
    for (final block in blocks) {
      final orderedLines = block.lines.toList()
        ..sort((a, b) {
          final aTop = a.boundingBox.top;
          final bTop = b.boundingBox.top;
          final topCompare = aTop.compareTo(bTop);
          if (topCompare != 0) return topCompare;
          final aLeft = a.boundingBox.left;
          final bLeft = b.boundingBox.left;
          return aLeft.compareTo(bLeft);
        });

      for (final line in orderedLines) {
        final text = line.text.trim();
        if (text.isNotEmpty) {
          lines.add(text);
        }
      }
    }

    return lines.join('\n');
  }

  String _postProcessText(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => _normalizeLine(line))
        .where((line) => line.isNotEmpty)
        .toList();

    final deduped = <String>[];
    for (final line in lines) {
      if (deduped.isEmpty || deduped.last.toLowerCase() != line.toLowerCase()) {
        deduped.add(line);
      }
    }

    return deduped.join('\n');
  }

  String _normalizeLine(String line) {
    var cleaned = line.replaceAll(RegExp(r'[\u00A0\t]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAllMapped(RegExp(r'\b[\w-]+\b'), (match) {
      return _normalizeToken(match.group(0)!);
    });
    return cleaned;
  }

  String _normalizeToken(String token) {
    if (token.length <= 2) return token;
    if (RegExp(r'^\d+[.,]?\d*$').hasMatch(token)) return token;
    if (RegExp(r'^[A-Za-z]+$').hasMatch(token) == false) return token;

    final lower = token.toLowerCase();
    const directCorrections = <String, String>{
      '0': 'o',
      '1': 'i',
      'l': 'i',
      '5': 's',
      '8': 'b',
      't0tal': 'total',
      'subt0tal': 'subtotal',
      'inv0ice': 'invoice',
      'recelpt': 'receipt',
      'strukl': 'struk',
      'kwltansi': 'kwitansi',
      'faktur': 'faktur',
      'jumlahh': 'jumlah',
    };

    final direct = directCorrections[lower];
    if (direct != null) return _matchCase(token, direct);

    final language = _inferTokenLanguage(lower);
    final vocabulary = language == 'id'
        ? _indonesianOCRVocabulary
        : _englishOCRVocabulary;

    final bestMatch = _findClosestToken(lower, vocabulary);
    if (bestMatch != null) return _matchCase(token, bestMatch);

    return token;
  }

  String _inferTokenLanguage(String token) {
    if (DocumentClassifier.detectLanguage(token) == 'id') return 'id';
    return 'en';
  }

  String _matchCase(String original, String replacement) {
    if (original.toUpperCase() == original) {
      return replacement.toUpperCase();
    }
    if (original[0].toUpperCase() == original[0]) {
      return replacement[0].toUpperCase() + replacement.substring(1);
    }
    return replacement;
  }

  String? _findClosestToken(String token, List<String> vocabulary) {
    String? best;
    var bestDistance = 3;
    for (final candidate in vocabulary) {
      final distance = _levenshtein(token, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, i);
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        current[j] = [
          previous[j] + 1,
          current[j - 1] + 1,
          previous[j - 1] + cost,
        ].reduce((value, element) => value < element ? value : element);
      }
      for (var j = 0; j <= b.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }

  static const List<String> _englishOCRVocabulary = <String>[
    'receipt',
    'invoice',
    'subtotal',
    'tax',
    'total',
    'amount',
    'date',
    'address',
    'phone',
    'signature',
    'customer',
    'cashier',
    'change',
    'payment',
    'due',
    'bill',
    'company',
    'name',
    'reference',
    'number',
  ];

  static const List<String> _indonesianOCRVocabulary = <String>[
    'struk',
    'kwitansi',
    'faktur',
    'subtotal',
    'pajak',
    'total',
    'jumlah',
    'tanggal',
    'alamat',
    'telepon',
    'tanda',
    'tangan',
    'nama',
    'pelanggan',
    'kasir',
    'kembalian',
    'pembayaran',
    'jatuh',
    'tempo',
    'nomor',
    'perusahaan',
    'bukti',
  ];

  String _chooseBetterText(String first, String second) {
    final firstScore = _textScore(first);
    final secondScore = _textScore(second);
    return secondScore > firstScore ? second : first;
  }

  int _textScore(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 0;
    final letters = RegExp(r'[A-Za-z0-9]').allMatches(trimmed).length;
    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .where((line) => line.trim().isNotEmpty)
        .length;
    return letters + (lines * 5) + trimmed.length;
  }
}

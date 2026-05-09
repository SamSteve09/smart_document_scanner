import 'dart:math' as math;

class DocumentClassifier {
  static const categories = <String>[
    'Receipt',
    'Invoice',
    'ID Card',
    'Form',
    'Letter',
    'Note',
    'Other',
  ];

  static const List<String> _englishStopWords = <String>[
    'the',
    'and',
    'of',
    'to',
    'in',
    'for',
    'is',
    'on',
    'with',
    'this',
    'that',
    'from',
    'by',
    'at',
    'an',
    'a',
    'or',
    'as',
    'be',
    'it',
    'are',
    'was',
    'were',
    'receipt',
    'invoice',
  ];

  static const List<String> _indonesianStopWords = <String>[
    'dan',
    'yang',
    'untuk',
    'di',
    'ke',
    'dari',
    'pada',
    'ini',
    'itu',
    'dengan',
    'atau',
    'sebuah',
    'adalah',
    'oleh',
    'kami',
    'anda',
    'saya',
    'kami',
    'dalam',
    'ke',
    'yang',
    'untuk',
    'struk',
    'faktur',
  ];

  static const List<String> _indonesianLanguageHints = <String>[
    'struk',
    'kwitansi',
    'faktur',
    'nota',
    'tagihan',
    'jumlah',
    'tanggal',
    'alamat',
    'nomor',
    'bukti',
    'surat',
    'formulir',
    'tanda',
    'lahir',
    'nik',
    'ktp',
  ];

  static const List<String> _englishLanguageHints = <String>[
    'receipt',
    'invoice',
    'total',
    'amount',
    'date',
    'address',
    'phone',
    'signature',
    'dear',
    'subject',
    'meeting',
    'note',
  ];

  static const Map<String, Map<String, List<String>>> _trainingSamples = {
    'en': {
      'Receipt': [
        'receipt subtotal tax total cashier change item qty payment',
        'store receipt total tax cash card thank you',
        'purchase item amount due receipt number',
      ],
      'Invoice': [
        'invoice bill to invoice no due date amount due po number',
        'invoice total balance payable payment terms',
        'invoice company address tax subtotal total',
      ],
      'ID Card': [
        'id card name date of birth gender nationality passport license',
        'driver license identity number birth place address',
        'official identity card issue date signature',
      ],
      'Form': [
        'form signature address checkbox please fill date of birth',
        'application form name address phone email signature',
        'registration form choose option select checkbox',
      ],
      'Letter': [
        'dear sir or madam subject sincerely regards letter',
        'to whom it may concern formal letter regards',
        'salutation body signature closing letter',
      ],
      'Note': [
        'todo note remember agenda meeting chapter lesson',
        'personal note summary reminder task meeting',
        'quick note highlights memo draft',
      ],
    },
    'id': {
      'Receipt': [
        'struk subtotal pajak total kasir kembalian item qty pembayaran',
        'nota pembelian total tunai kartu terima kasih',
        'struk nomor bukti jumlah harga barang',
      ],
      'Invoice': [
        'faktur tagihan nomor faktur tanggal jatuh tempo jumlah yang harus dibayar',
        'invoice total saldo terutang syarat pembayaran',
        'faktur perusahaan alamat pajak subtotal total',
      ],
      'ID Card': [
        'ktp kartu tanda penduduk nama tanggal lahir jenis kelamin nik',
        'kartu identitas nomor identitas tempat lahir alamat',
        'identitas resmi tanda tangan tanggal terbit',
      ],
      'Form': [
        'formulir tanda tangan alamat centang mohon diisi tanggal lahir',
        'formulir pendaftaran nama alamat telepon email tanda tangan',
        'lembar isian pilih opsi centang',
      ],
      'Letter': [
        'kepada dengan hormat perihal salam hormat kami surat',
        'surat resmi salam penutup tanda tangan',
        'isi surat pernyataan hormat kami',
      ],
      'Note': [
        'catatan ingat agenda rapat notulen pelajaran',
        'catatan pribadi ringkasan pengingat tugas rapat',
        'memo singkat poin penting draft',
      ],
    },
  };

  static const Map<String, Map<String, List<String>>> _anchorTokens = {
    'en': {
      'Receipt': ['receipt', 'subtotal', 'cashier', 'tax', 'change', 'qty'],
      'Invoice': ['invoice', 'bill', 'due', 'amount', 'po'],
      'ID Card': ['identity', 'passport', 'license', 'gender', 'birth'],
      'Form': ['form', 'signature', 'checkbox', 'please', 'fill'],
      'Letter': ['dear', 'sincerely', 'regards', 'subject'],
      'Note': ['todo', 'note', 'remember', 'agenda', 'memo'],
    },
    'id': {
      'Receipt': [
        'struk',
        'kwitansi',
        'subtotal',
        'kasir',
        'pajak',
        'kembalian',
        'nota',
      ],
      'Invoice': ['faktur', 'tagihan', 'jatuh tempo', 'dibayar', 'invoice'],
      'ID Card': ['ktp', 'nik', 'penduduk', 'lahir'],
      'Form': ['formulir', 'tanda tangan', 'centang', 'diisi'],
      'Letter': ['kepada', 'hormat', 'perihal', 'salam'],
      'Note': ['catatan', 'ingat', 'rapat', 'notulen', 'memo'],
    },
  };

  static String suggestCategory(String text, {String? language}) {
    final normalizedText = text.toLowerCase();
    final lang = _normalizeLanguage(language ?? detectLanguage(normalizedText));
    final tokens = _tokenize(normalizedText, lang);

    if (tokens.isEmpty) {
      return 'Other';
    }

    final model = _buildModel(lang);
    String bestCategory = 'Other';
    double bestScore = double.negativeInfinity;

    for (final category in categories) {
      if (category == 'Other') continue;
      final score = _scoreTokens(tokens, model, category);
      if (score > bestScore) {
        bestScore = score;
        bestCategory = category;
      }
    }

    if (bestScore <= model.fallbackThreshold) {
      return 'Other';
    }
    return bestCategory;
  }

  /// Lightweight language detection using token overlap with English and Indonesian hints.
  static String detectLanguage(String text) {
    final normalized = text.toLowerCase();
    final tokens = _tokenize(normalized, 'en');

    var idScore = 0;
    var enScore = 0;
    for (final token in tokens) {
      if (_indonesianLanguageHints.contains(token)) idScore += 2;
      if (_englishLanguageHints.contains(token)) enScore += 2;
      if (_indonesianStopWords.contains(token)) idScore += 1;
      if (_englishStopWords.contains(token)) enScore += 1;
    }

    if (idScore > enScore) return 'id';
    return 'en';
  }

  static String suggestTitle(String text, {String? category}) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !RegExp(r'^[0-9\s\-_/.:]+$').hasMatch(line))
        .where((line) => !_looksLikeNoise(line))
        .toList();

    if (lines.isEmpty) {
      return category == null ? 'Untitled document' : '$category document';
    }

    final first = lines.first;
    return first.length > 40 ? first.substring(0, 40).trimRight() : first;
  }

  static List<String> suggestTags(String text) {
    final lower = text.toLowerCase();
    final lang = detectLanguage(lower);
    final tags = <String>{};
    final tokens = _tokenize(lower, lang);

    void addIfContains(List<String> needles, String tag) {
      if (needles.any(lower.contains) || needles.any(tokens.contains)) {
        tags.add(tag);
      }
    }

    if (lang == 'id') {
      addIfContains(['faktur', 'invoice'], 'invoice');
      addIfContains(['struk', 'kwitansi', 'receipt'], 'receipt');
      addIfContains(['total', 'jumlah'], 'total');
      addIfContains(['tanggal', 'jatuh tempo'], 'date');
      addIfContains(['tanda tangan', 'ttd', 'signature'], 'signature');
      addIfContains(['alamat'], 'address');
      addIfContains(['telepon', 'hp', 'phone'], 'phone');
      addIfContains(['email'], 'email');
    } else {
      addIfContains(['invoice'], 'invoice');
      addIfContains(['receipt'], 'receipt');
      addIfContains(['total'], 'total');
      addIfContains(['due date'], 'due-date');
      addIfContains(['signature'], 'signature');
      addIfContains(['address'], 'address');
      addIfContains(['date'], 'date');
      addIfContains(['phone'], 'phone');
      addIfContains(['email'], 'email');
    }

    return tags.toList();
  }

  static String shortSnippet(String text, {int maxChars = 120}) {
    final flattened = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flattened.length <= maxChars) return flattened;
    return '${flattened.substring(0, maxChars).trimRight()}...';
  }

  static bool _looksLikeNoise(String line) {
    return RegExp(r'^[\d\W]+$').hasMatch(line) || line.length <= 2;
  }

  static String _normalizeLanguage(String language) {
    if (language.startsWith('id')) return 'id';
    return 'en';
  }

  static List<String> _tokenize(String text, String language) {
    final tokens = RegExp(
      r'[a-z0-9]+',
    ).allMatches(text).map((match) => match.group(0)!).toList();
    final stopWords = language == 'id'
        ? _indonesianStopWords
        : _englishStopWords;
    return tokens
        .where((token) => token.length > 1 && !stopWords.contains(token))
        .toList();
  }

  static _TextClassificationModel _buildModel(String language) {
    final samplesByCategory =
        _trainingSamples[language] ?? _trainingSamples['en']!;
    final categoryTokenCounts = <String, Map<String, int>>{};
    final categoryTotals = <String, int>{};
    final vocabulary = <String>{};

    for (final entry in samplesByCategory.entries) {
      final counts = <String, int>{};
      var total = 0;
      for (final sample in entry.value) {
        final sampleTokens = _tokenize(sample.toLowerCase(), language);
        for (final token in sampleTokens) {
          counts[token] = (counts[token] ?? 0) + 1;
          total++;
          vocabulary.add(token);
        }
      }
      categoryTokenCounts[entry.key] = counts;
      categoryTotals[entry.key] = total;
    }

    return _TextClassificationModel(
      categoryTokenCounts: categoryTokenCounts,
      categoryTotals: categoryTotals,
      vocabularySize: vocabulary.length,
      fallbackThreshold: -80,
    );
  }

  static double _scoreTokens(
    List<String> tokens,
    _TextClassificationModel model,
    String category,
  ) {
    final counts = model.categoryTokenCounts[category] ?? const <String, int>{};
    final total = model.categoryTotals[category] ?? 0;
    final denominator = total + model.vocabularySize;

    var score = 0.0;
    for (final token in tokens) {
      final count = counts[token] ?? 0;
      score += _log((count + 1) / denominator);
    }

    final prior = 1 / (categories.length - 1);
    score += _log(prior);
    score += _anchorBonus(
      tokens,
      _normalizeLanguage(_detectLanguageHint(tokens)),
      category,
    );
    return score;
  }

  static String _detectLanguageHint(List<String> tokens) {
    var idScore = 0;
    var enScore = 0;
    for (final token in tokens) {
      if (_indonesianLanguageHints.contains(token)) idScore += 2;
      if (_englishLanguageHints.contains(token)) enScore += 2;
    }
    return idScore > enScore ? 'id' : 'en';
  }

  static double _anchorBonus(
    List<String> tokens,
    String language,
    String category,
  ) {
    final anchors = _anchorTokens[language]?[category] ?? const <String>[];
    if (anchors.isEmpty) return 0.0;

    var bonus = 0.0;
    for (final anchor in anchors) {
      if (anchor.contains(' ')) {
        if (tokens.join(' ').contains(anchor)) {
          bonus += 1.5;
        }
      } else if (tokens.contains(anchor)) {
        bonus += 1.5;
      }
    }
    return bonus;
  }

  static double _log(double value) => math.log(value);
}

class _TextClassificationModel {
  final Map<String, Map<String, int>> categoryTokenCounts;
  final Map<String, int> categoryTotals;
  final int vocabularySize;
  final double fallbackThreshold;

  const _TextClassificationModel({
    required this.categoryTokenCounts,
    required this.categoryTotals,
    required this.vocabularySize,
    required this.fallbackThreshold,
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'models/document_draft.dart';
import 'models/document_record.dart';
import 'services/document_classifier.dart';
import 'services/document_ocr_service.dart';
import 'services/document_storage_service.dart';

void main() {
  runApp(const SmartDocumentApp());
}

class SmartDocumentApp extends StatelessWidget {
  const SmartDocumentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Document Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF245B63)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DocumentOcrService _ocr = DocumentOcrService();
  final DocumentStorageService _storage = DocumentStorageService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormat = DateFormat('d MMM yyyy, HH:mm');

  List<DocumentRecord> _documents = [];
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _loading = true;

  List<String> get _categories => ['All', ...DocumentClassifier.categories];

  List<DocumentRecord> get _visibleDocuments {
    final query = _searchQuery.trim().toLowerCase();
    return _documents.where((doc) {
      final matchesCategory =
          _selectedCategory == 'All' || doc.category == _selectedCategory;
      if (!matchesCategory) return false;
      if (query.isEmpty) return true;

      final haystack = [
        doc.title,
        doc.category,
        doc.tags.join(' '),
        doc.extractedText,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() => _loading = true);
    final documents = await _storage.loadDocuments();
    if (!mounted) return;
    setState(() {
      _documents = documents;
      _loading = false;
    });
  }

  Future<void> _scanDocument(ImageSource source) async {
    final capturedFile = await _captureDocumentImage(source);
    if (capturedFile == null) return;

    final draft = await _ocr.scan(capturedFile);
    if (!mounted) return;

    final reviewedDraft = await _showDocumentEditor(draft);

    if (reviewedDraft == null) return;
    await _storage.saveDraft(reviewedDraft);
    if (!mounted) return;
    await _loadDocuments();
  }

  Future<File?> _captureDocumentImage(ImageSource source) async {
    // Use the ML Kit DocumentScanner only for camera captures.
    // For gallery uploads, skip the scanner and open the image picker directly.
    if (Platform.isAndroid || Platform.isIOS) {
      if (source == ImageSource.camera) {
        try {
          final scanner = DocumentScanner(
            options: DocumentScannerOptions(
              documentFormats: const {DocumentFormat.jpeg},
              pageLimit: 1,
              mode: ScannerMode.full,
              isGalleryImport: false,
            ),
          );
          try {
            final result = await scanner.scanDocument();
            final images = result.images;
            if (images != null && images.isNotEmpty) {
              return File(images.first);
            }
            // If the scanner returned no images (user cancelled or no capture),
            // do not fall back to reopening the camera or picker — signal
            // cancellation by returning null.
            return null;
          } finally {
            await scanner.close();
          }
        } catch (e) {
          // If scanner throws (for example user pressed back), treat as
          // cancelled and do not re-open camera/picker.
          return null;
        }
      }
    }

    // For non-camera sources (gallery) or non-mobile platforms, use the
    // image picker directly.
    final picked = await _picker.pickImage(source: source, imageQuality: 90);
    if (picked == null) return null;
    return File(picked.path);
  }

  Future<void> _editDocument(DocumentRecord document) async {
    final draft = DocumentDraft(
      sourceFile: File(document.imagePath),
      extractedText: document.extractedText,
      title: document.title,
      category: document.category,
      tagsText: document.tags.join(', '),
      capturedAt: document.capturedAt,
    );

    final reviewedDraft = await _showDocumentEditor(draft);
    if (reviewedDraft == null) return;

    final updated = document.copyWith(
      title: reviewedDraft.title.trim().isEmpty
          ? 'Untitled document'
          : reviewedDraft.title.trim(),
      category: reviewedDraft.category,
      extractedText: reviewedDraft.extractedText,
      tags: reviewedDraft.tags,
    );
    await _storage.updateDocument(updated);
    if (!mounted) return;
    await _loadDocuments();
  }

  Future<DocumentDraft?> _showDocumentEditor(DocumentDraft draft) {
    return showDialog<DocumentDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DocumentReviewDialog(draft: draft),
    );
  }

  Future<void> _deleteDocument(DocumentRecord document) async {
    await _storage.deleteDocument(document.id);
    if (!mounted) return;
    await _loadDocuments();
  }

  @override
  void dispose() {
    _ocr.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.camera_alt_outlined),
                    title: const Text('Take photo'),
                    subtitle: const Text('Scan a document with the camera'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _scanDocument(ImageSource.camera);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.photo_library_outlined),
                    title: const Text('Upload photo'),
                    subtitle: const Text('Choose an image from your gallery'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _scanDocument(ImageSource.gallery);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        label: const Text('Scan document'),
        icon: const Icon(Icons.document_scanner_outlined),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1D4A52), Color(0xFFF4F1EA)],
            stops: [0.0, 0.42],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Document Scanner',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan, organize, and search documents offline with on-device OCR.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _StatCard(
                          label: 'Saved docs',
                          value: _documents.length.toString(),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: 'Visible',
                          value: _visibleDocuments.length.toString(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F1EA),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _loadDocuments,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                            children: [
                              TextField(
                                controller: _searchController,
                                onChanged: (value) =>
                                    setState(() => _searchQuery = value),
                                decoration: InputDecoration(
                                  hintText:
                                      'Search title, tag, category, or text',
                                  prefixIcon: const Icon(Icons.search),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _categories.map((category) {
                                    final selected =
                                        _selectedCategory == category;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: FilterChip(
                                        selected: selected,
                                        label: Text(category),
                                        onSelected: (_) => setState(
                                          () => _selectedCategory = category,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const SizedBox(height: 18),
                              if (_visibleDocuments.isEmpty)
                                _EmptyState(
                                  hasFilters:
                                      _searchQuery.isNotEmpty ||
                                      _selectedCategory != 'All',
                                )
                              else
                                ..._visibleDocuments.map(
                                  (document) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _DocumentCard(
                                      document: document,
                                      dateFormat: _dateFormat,
                                      onDelete: () => _deleteDocument(document),
                                      onEdit: () => _editDocument(document),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasFilters;

  const _EmptyState({required this.hasFilters});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFE7EFEF),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.folder_open_outlined,
                size: 46,
                color: Color(0xFF245B63),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilters
                  ? 'No documents match your filters'
                  : 'No documents scanned yet',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              hasFilters
                  ? 'Clear the search or category filter to see more results.'
                  : 'Tap the scan button to capture a document and let the app organize it for you.',
              style: TextStyle(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentRecord document;
  final DateFormat dateFormat;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _DocumentCard({
    required this.document,
    required this.dateFormat,
    required this.onDelete,
    required this.onEdit,
  });

  Color _categoryColor(String category) {
    switch (category) {
      case 'Receipt':
        return const Color(0xFF0F766E);
      case 'Invoice':
        return const Color(0xFF2563EB);
      case 'ID Card':
        return const Color(0xFF7C3AED);
      case 'Form':
        return const Color(0xFFB45309);
      case 'Letter':
        return const Color(0xFFDB2777);
      case 'Note':
        return const Color(0xFF15803D);
      default:
        return const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(document.imagePath);
    final hasImage = imageFile.existsSync();
    final accent = _categoryColor(document.category);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _DocumentDetailSheet(
            document: document,
            accent: accent,
            dateFormat: dateFormat,
            onEdit: onEdit,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 72,
                  height: 96,
                  color: const Color(0xFFE8EEF0),
                  child: hasImage
                      ? Image.file(imageFile, fit: BoxFit.cover)
                      : const Icon(
                          Icons.description_outlined,
                          color: Color(0xFF245B63),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit document',
                        ),
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete document',
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(document.category),
                          backgroundColor: accent.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.18),
                          ),
                          labelStyle: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Chip(
                          label: Text(dateFormat.format(document.capturedAt)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DocumentClassifier.shortSnippet(document.extractedText),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.35,
                      ),
                    ),
                    if (document.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: document.tags
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F4F5),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tag,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentDetailSheet extends StatelessWidget {
  final DocumentRecord document;
  final Color accent;
  final DateFormat dateFormat;
  final VoidCallback onEdit;

  const _DocumentDetailSheet({
    required this.document,
    required this.accent,
    required this.dateFormat,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final imageFile = File(document.imagePath);
    final hasImage = imageFile.existsSync();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      document.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onEdit();
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      document.category,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                dateFormat.format(document.capturedAt),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              if (hasImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.file(
                    imageFile,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              if (hasImage) const SizedBox(height: 16),
              const Text(
                'Tags',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: document.tags.isEmpty
                    ? [const Chip(label: Text('No tags'))]
                    : document.tags
                          .map((tag) => Chip(label: Text(tag)))
                          .toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Extracted text',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE1E6E8)),
                ),
                child: Text(
                  document.extractedText,
                  style: const TextStyle(height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DocumentReviewDialog extends StatefulWidget {
  final DocumentDraft draft;

  const DocumentReviewDialog({super.key, required this.draft});

  @override
  State<DocumentReviewDialog> createState() => _DocumentReviewDialogState();
}

class _DocumentReviewDialogState extends State<DocumentReviewDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _tagsController;
  late final TextEditingController _textController;
  late String _category;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.draft.title);
    _tagsController = TextEditingController(text: widget.draft.tagsText);
    _textController = TextEditingController(text: widget.draft.extractedText);
    _category = widget.draft.category;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _reclassifyFromText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final category = DocumentClassifier.suggestCategory(text);
    final suggestedTitle = DocumentClassifier.suggestTitle(
      text,
      category: category,
    );
    final suggestedTags = DocumentClassifier.suggestTags(text).join(', ');

    setState(() {
      _category = category;
      _tagsController.text = suggestedTags;
      if (_titleController.text.trim().isEmpty ||
          _titleController.text.trim() == widget.draft.title.trim()) {
        _titleController.text = suggestedTitle;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Review scan'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  widget.draft.sourceFile,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Document title'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: DocumentClassifier.categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'invoice, school, tax, travel',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Scanned text',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _reclassifyFromText,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Reclassify from text'),
              ),
              const SizedBox(height: 12),
              const Text(
                'OCR preview',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 180),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE1E6E8)),
                ),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, value, _) => SingleChildScrollView(
                    child: Text(
                      value.text,
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.draft.title = _titleController.text.trim();
            widget.draft.extractedText = _textController.text.trim();
            widget.draft.category = _category;
            widget.draft.tagsText = _tagsController.text.trim();
            Navigator.of(context).pop(widget.draft);
          },
          child: const Text('Save document'),
        ),
      ],
    );
  }
}

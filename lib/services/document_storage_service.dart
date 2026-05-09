import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/document_draft.dart';
import '../models/document_record.dart';

class DocumentStorageService {
  static const String _storageKey = 'document_records_v1';

  Future<List<DocumentRecord>> loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    final records = decoded
        .map((item) => DocumentRecord.fromJson(item as Map<String, dynamic>))
        .toList();
    records.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    return records;
  }

  Future<DocumentRecord> saveDraft(DocumentDraft draft) async {
    final documents = await loadDocuments();
    final savedImagePath = await _copyImageToLibrary(draft.sourceFile);
    final now = DateTime.now();
    final record = DocumentRecord(
      id: now.microsecondsSinceEpoch.toString(),
      title: draft.title.trim().isEmpty
          ? 'Untitled document'
          : draft.title.trim(),
      category: draft.category,
      imagePath: savedImagePath,
      extractedText: draft.extractedText,
      tags: draft.tags,
      capturedAt: draft.capturedAt,
    );

    documents.insert(0, record);
    await _persistDocuments(documents);
    return record;
  }

  Future<void> updateDocument(DocumentRecord updatedRecord) async {
    final documents = await loadDocuments();
    final index = documents.indexWhere((doc) => doc.id == updatedRecord.id);
    if (index == -1) return;
    documents[index] = updatedRecord;
    await _persistDocuments(documents);
  }

  Future<void> deleteDocument(String id) async {
    final documents = await loadDocuments();
    documents.removeWhere((doc) => doc.id == id);
    await _persistDocuments(documents);
  }

  Future<String> _copyImageToLibrary(File sourceFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final scansDir = Directory(p.join(directory.path, 'document_scans'));
    if (!await scansDir.exists()) {
      await scansDir.create(recursive: true);
    }

    final extension = p.extension(sourceFile.path).isEmpty
        ? '.jpg'
        : p.extension(sourceFile.path);
    final fileName = '${DateTime.now().microsecondsSinceEpoch}$extension';
    final destination = File(p.join(scansDir.path, fileName));
    return sourceFile.copy(destination.path).then((file) => file.path);
  }

  Future<void> _persistDocuments(List<DocumentRecord> documents) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(documents.map((doc) => doc.toJson()).toList()),
    );
  }
}

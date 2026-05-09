# Smart Document Scanner

A simple offline-first Flutter app that lets the user scan or upload documents,
run on-device OCR, auto-suggest a document category, and organize saved scans by
searchable tags and metadata.

## Features

- Take a photo or upload an image of a document.
- Extract text locally with `google_mlkit_text_recognition`.
- Auto-suggest document type, title, and tags.
- Review and edit metadata before saving.
- Search and filter saved documents by category and text.
- View scan details, extracted text, and the saved document image.

## Run

```bash
flutter pub get
flutter run -d <android-device-id>
```

## Tests

```bash
flutter test --coverage
```
## Screenshots


## Limitations
The app OCR performance relies on Google's ML Kit Text Recognition and 
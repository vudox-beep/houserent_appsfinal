import 'package:flutter/material.dart';

import '../screens/legal_document_screen.dart';

/// Opens Privacy / Terms without relying on GoRouter hot-reload.
void openLegalDocument(
  BuildContext context, {
  required LegalDocumentType type,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => LegalDocumentScreen(type: type),
    ),
  );
}

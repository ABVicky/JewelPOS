import 'package:flutter_test/flutter_test.dart';
import 'package:jewel_pos/db.dart';
import 'package:jewel_pos/printer.dart';

void main() {
  test('generateLabelPdfBytes renders QR code label without error', () async {
    final item = InventoryItem(
      barcode: 'JW10042',
      itemName: 'Gold Ring',
      category: 'Rings',
      purity: '22K',
      weight: 5.25,
    );

    final bytes = await TSPLPrinter.generateLabelPdfBytes(item);
    expect(bytes.isNotEmpty, true);
  });
}

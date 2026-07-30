import 'package:flutter_test/flutter_test.dart';
import 'package:jewel_pos/db.dart';
import 'package:jewel_pos/printer.dart';

void main() {
  group('TSPL Label Printer Unit Tests for HPRT HT800', () {
    test('Standard Item Label Generation', () {
      final item = InventoryItem(
        barcode: 'JMT000000001',
        itemName: 'Gold Antique Bangle',
        category: 'Bangle',
        purity: '22K',
        weight: 14.250,
      );

      final tspl = TSPLPrinter.buildTSPLCommand(item);

      expect(tspl, contains('SIZE 38 mm,25 mm'));
      expect(tspl, contains('GAP 2 mm,0 mm'));
      expect(tspl, contains('SPEED 3'));
      expect(tspl, contains('DENSITY 10'));
      expect(tspl, contains('DIRECTION 1'));
      expect(tspl, contains('CLS'));
      expect(tspl, contains('TEXT 20,15,"3",0,1,1,"Gold Antique Bangle"'));
      expect(tspl, contains('TEXT 20,50,"2",0,1,1,"Wt:14.250g"'));
      expect(tspl, contains('TEXT 170,50,"3",0,1,1,"22K"'));
      expect(tspl, contains('BARCODE 20,85,"128",65,0,0,2,4,"JMT000000001"'));
      expect(tspl, contains('TEXT 40,165,"2",0,1,1,"JMT000000001"'));
      expect(tspl, contains('PRINT 1,1'));
    });

    test('Maximum Length Item Name Truncation Handling', () {
      final item = InventoryItem(
        barcode: 'JMT000000002',
        itemName: '22K Heavy Designer Bridal Gold Necklace Extra Long Title',
        category: 'Necklace',
        purity: '22K (916)',
        weight: 125.750,
      );

      final tspl = TSPLPrinter.buildTSPLCommand(item);

      // Verify item name is safely bounded to prevent label overflow
      expect(tspl, contains('TEXT 20,15,"3",0,1,1,"22K Heavy Designer Bri"'));
      expect(tspl, contains('TEXT 20,50,"2",0,1,1,"Wt:125.750g"'));
      expect(tspl, contains('TEXT 170,50,"3",0,1,1,"22K (916)"'));
      expect(tspl, contains('BARCODE 20,85,"128",65,0,0,2,4,"JMT000000002"'));
      expect(tspl, contains('TEXT 40,165,"2",0,1,1,"JMT000000002"'));
    });

    test('Small Weight and Custom Purity Formatting', () {
      final item = InventoryItem(
        barcode: 'JMT000000003',
        itemName: 'Diamond Nose Ring',
        category: 'Ring',
        purity: '18K (750)',
        weight: 0.850,
      );

      final tspl = TSPLPrinter.buildTSPLCommand(item);

      expect(tspl, contains('TEXT 20,50,"2",0,1,1,"Wt:0.850g"'));
      expect(tspl, contains('TEXT 170,50,"3",0,1,1,"18K (750)"'));
      expect(tspl, contains('BARCODE 20,85,"128",65,0,0,2,4,"JMT000000003"'));
    });
  });
}

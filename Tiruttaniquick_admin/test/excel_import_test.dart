import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:tiruttaniquick_admin/services/excel_product_parser.dart';

void main() {
  group('ExcelProductParser 12 Edge-Case Tests', () {
    // Helper to create an Excel file in memory
    Uint8List createWorkbook(List<List<CellValue?>> rowData) {
      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[defaultSheet];
      for (final row in rowData) {
        sheet.appendRow(row);
      }
      return Uint8List.fromList(excel.save()!);
    }

    final standardHeaders = [
      TextCellValue('Product Name'),
      TextCellValue('Product Name (Tamil)'),
      TextCellValue('Category'),
      TextCellValue('Brand'),
      TextCellValue('Description'),
      TextCellValue('Unit'),
      TextCellValue('MRP'),
      TextCellValue('Selling Price'),
      TextCellValue('Stock Quantity'),
      TextCellValue('Image URL'),
    ];

    // Test 1: All fields populated. Expected: PASS.
    test('Test 1: All fields populated -> PASS', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Tata Salt'),
          TextCellValue('டாடா உப்பு'),
          TextCellValue('Groceries'),
          TextCellValue('Tata'),
          TextCellValue('Iodized salt'),
          TextCellValue('1 kg'),
          IntCellValue(28),
          IntCellValue(25),
          IntCellValue(100),
          TextCellValue('https://example.com/salt.jpg'),
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      expect(result.validCount, equals(1));
      expect(result.invalidCount, equals(0));

      final product = result.rows.first;
      expect(product.isValid, isTrue);
      expect(product.productName, equals('Tata Salt'));
      expect(product.productNameTamil, equals('டாடா உப்பு'));
      expect(product.category, equals('Groceries'));
      expect(product.brand, equals('Tata'));
      expect(product.description, equals('Iodized salt'));
      expect(product.unit, equals('1 kg'));
      expect(product.mrp, equals(28.0));
      expect(product.sellingPrice, equals(25.0));
      expect(product.stock, equals(100));
      expect(product.imageUrl, equals('https://example.com/salt.jpg'));
    });

    // Test 2: Description empty. Expected: PASS.
    test('Test 2: Description empty -> PASS', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Aashirvaad Atta'),
          TextCellValue('ஆட்டா'),
          TextCellValue('Flour'),
          TextCellValue('ITC'),
          null, // Empty description
          TextCellValue('5 kg'),
          DoubleCellValue(250.0),
          DoubleCellValue(230.0),
          IntCellValue(50),
          null,
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.description, equals(''));
    });

    // Test 3: Brand empty. Expected: PASS.
    test('Test 3: Brand empty -> PASS', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Fresh Eggs'),
          TextCellValue('முட்டை'),
          TextCellValue('Dairy & Eggs'),
          null, // Empty Brand
          TextCellValue('Farm fresh'),
          TextCellValue('6 pcs'),
          IntCellValue(42),
          IntCellValue(40),
          IntCellValue(200),
          null,
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.brand, equals(''));
    });

    // Test 4: Category empty. Expected: PASS if category is optional.
    test('Test 4: Category empty -> PASS', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Ginger'),
          TextCellValue('இஞ்சி'),
          null, // Empty Category
          null,
          TextCellValue('Fresh root'),
          TextCellValue('250 g'),
          IntCellValue(30),
          IntCellValue(25),
          IntCellValue(40),
          null,
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.category, equals(''));
    });

    // Test 5: Tamil Product Name empty. Expected: PASS if optional.
    test('Test 5: Tamil Product Name empty -> PASS', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Basmati Rice'),
          null, // Empty Tamil name
          TextCellValue('Rice'),
          TextCellValue('India Gate'),
          TextCellValue('Premium grain'),
          TextCellValue('1 kg'),
          IntCellValue(120),
          IntCellValue(110),
          IntCellValue(80),
          null,
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.productNameTamil, equals(''));
    });

    // Test 6: Several optional fields empty. Expected: PASS.
    test('Test 6: Several optional fields empty -> PASS', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Coriander Leaves'),
          null, // No Tamil name
          null, // No Category
          null, // No Brand
          null, // No Description
          TextCellValue('1 bunch'),
          IntCellValue(15),
          IntCellValue(10),
          IntCellValue(100),
          null, // No image
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.productNameTamil, equals(''));
      expect(p.category, equals(''));
      expect(p.brand, equals(''));
      expect(p.description, equals(''));
      expect(p.imageUrl, equals(''));
    });

    // Test 7: Completely empty row. Expected: Ignored.
    test('Test 7: Completely empty row -> Ignored', () {
      final bytes = createWorkbook([
        standardHeaders,
        [null, null, null, null, null, null, null, null, null, null],
        [TextCellValue('   '), TextCellValue(''), null], // blank whitespace row
        [
          TextCellValue('Product A'),
          null,
          null,
          null,
          null,
          TextCellValue('1 pc'),
          IntCellValue(10),
          IntCellValue(10),
          IntCellValue(5),
          null,
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      expect(result.emptyRowsSkipped, equals(2));
      expect(result.rows.first.productName, equals('Product A'));
    });

    // Test 8: Row has fewer cells than header. Expected: No crash.
    test('Test 8: Row has fewer cells than header -> No crash', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Short Product'),
          TextCellValue('குறுகிய பெயர்'),
          // Only 2 cells in this row!
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.productName, equals('Short Product'));
      expect(p.isValid, isFalse);
      expect(p.errors.any((e) => e.contains('[Unit] is required')), isTrue);
    });

    // Test 9: Extra unknown column. Expected: No crash.
    test('Test 9: Extra unknown column -> No crash', () {
      final bytes = createWorkbook([
        [
          TextCellValue('Notes'), // Extra col 1
          TextCellValue('Product Name'),
          TextCellValue('Vendor Code'), // Extra col 2
          TextCellValue('Unit'),
          TextCellValue('Selling Price'),
          TextCellValue('MRP'),
          TextCellValue('Stock Quantity'),
        ],
        [
          TextCellValue('Urgent'),
          TextCellValue('Extra Col Item'),
          TextCellValue('VEND-99'),
          TextCellValue('500 ml'),
          IntCellValue(45),
          IntCellValue(50),
          IntCellValue(10),
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.productName, equals('Extra Col Item'));
      expect(p.unit, equals('500 ml'));
      expect(p.sellingPrice, equals(45.0));
      expect(p.mrp, equals(50.0));
    });

    // Test 10: Required Product Name missing. Expected: Clear row-specific validation error.
    test('Test 10: Required Product Name missing -> Clear row-specific validation error', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          null, // Missing product name
          TextCellValue('பெயர் இல்லை'),
          TextCellValue('Category'),
          TextCellValue('Brand'),
          TextCellValue('Desc'),
          TextCellValue('1 pc'),
          IntCellValue(20),
          IntCellValue(15),
          IntCellValue(10),
          null,
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isFalse);
      expect(p.errors.any((e) => e.contains('[Product Name] is required')), isTrue);
    });

    // Test 11: Null cell. Expected: No "Null check operator used on a null value".
    test('Test 11: Null cell -> No Null check operator used on a null value', () {
      final bytes = createWorkbook([
        standardHeaders,
        [
          TextCellValue('Null Cell Product'),
          null, // null
          null, // null
          null, // null
          null, // null
          TextCellValue('1 pack'),
          TextCellValue('₹99.00'), // Currency symbol formatted text
          TextCellValue('85.50'),
          TextCellValue(' 42 '), // Whitespace padded
          null, // null
        ],
      ]);

      final result = ExcelProductParser.parseBytes(bytes);
      expect(result.rows.length, equals(1));
      final p = result.rows.first;
      expect(p.isValid, isTrue);
      expect(p.productName, equals('Null Cell Product'));
      expect(p.mrp, equals(99.0));
      expect(p.sellingPrice, equals(85.5));
      expect(p.stock, equals(42));
    });

    // Test 12: Actual file: Ranukastore_scanned_products_final.xlsx. Expected: Successful parsing with accurate count.
    test('Test 12: Actual file: Ranukastore_scanned_products_final.xlsx -> Successful parsing', () async {
      final file = File(r'C:\Users\gopim\Downloads\Ranukastore_scanned_products_final.xlsx');
      expect(file.existsSync(), isTrue, reason: 'Actual test file must exist');

      final bytes = await file.readAsBytes();
      final result = ExcelProductParser.parseBytes(bytes);

      expect(result.sheetName, equals('Sheet1'));
      expect(result.rows.length, equals(349)); // 350 rows minus 1 header
      expect(result.validCount, equals(345));
      expect(result.invalidCount, equals(4));

      // Verify that all 29 invalid rows have clear row-specific errors
      final invalidRows = result.rows.where((r) => !r.isValid).toList();
      for (final inv in invalidRows) {
        expect(inv.errors.isNotEmpty, isTrue);
        expect(
          inv.errors.every((e) => e.startsWith('Row ') && e.contains('is required')),
          isTrue,
        );
      }

      // Verify sample valid products
      final firstValid = result.rows.first;
      expect(firstValid.productName, equals('Colgate Salt'));
      expect(firstValid.isValid, isTrue);
      expect(firstValid.sellingPrice, greaterThan(0.0));
      expect(firstValid.mrp, greaterThan(0.0));
    });
  });
}

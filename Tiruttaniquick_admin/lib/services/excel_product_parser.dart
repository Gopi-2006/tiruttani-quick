import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// Represents a single parsed row from an Excel import.
class ExcelRowData {
  final int rowIndex;
  final String sheetName;
  final String productName;
  final String productNameTamil;
  final String category;
  final String brand;
  final String description;
  final String unit;
  final double mrp;
  final double sellingPrice;
  final int stock;
  final String imageUrl;
  final List<String> errors;
  String? existingDocId;

  ExcelRowData({
    required this.rowIndex,
    this.sheetName = 'Sheet1',
    required this.productName,
    required this.productNameTamil,
    required this.category,
    required this.brand,
    required this.description,
    required this.unit,
    required this.mrp,
    required this.sellingPrice,
    required this.stock,
    required this.imageUrl,
    required this.errors,
    this.existingDocId,
  });

  bool get isValid => errors.isEmpty;
  bool get isDuplicate => existingDocId != null;
}

/// Represents the overall result of parsing an Excel workbook.
class ParsedExcelResult {
  final String sheetName;
  final int headerRowIndex;
  final Map<String, int> columnMap;
  final List<ExcelRowData> rows;
  final List<String> errorLog;
  final int totalRowsRead;
  final int emptyRowsSkipped;

  ParsedExcelResult({
    required this.sheetName,
    required this.headerRowIndex,
    required this.columnMap,
    required this.rows,
    required this.errorLog,
    required this.totalRowsRead,
    required this.emptyRowsSkipped,
  });

  int get validCount => rows.where((r) => r.isValid).length;
  int get invalidCount => rows.where((r) => !r.isValid).length;
}

/// Robust, null-safe Excel parser for product imports.
class ExcelProductParser {
  // Aliases for header mapping
  static const Map<String, List<String>> _headerAliases = {
    'productName': [
      'product name',
      'productname',
      'product',
      'item name',
      'item',
      'name',
      'title',
      'product title',
    ],
    'productNameTamil': [
      'product name (tamil)',
      'product name tamil',
      'tamil name',
      'tamil product name',
      'name tamil',
      'tamil',
      'product nametamil',
    ],
    'category': [
      'category',
      'category name',
      'cat',
      'department',
    ],
    'brand': [
      'brand',
      'brand name',
      'manufacturer',
      'make',
    ],
    'description': [
      'description',
      'desc',
      'product description',
      'details',
    ],
    'unit': [
      'unit',
      'unit size',
      'size',
      'pack size',
      'weight',
      'volume',
      'quantity unit',
      'uom',
    ],
    'mrp': [
      'mrp',
      'm.r.p',
      'm.r.p.',
      'maximum retail price',
      'market price',
      'original price',
      'list price',
    ],
    'sellingPrice': [
      'selling price',
      'sellingprice',
      'price',
      'sale price',
      'our price',
      'rate',
      'offer price',
      'final price',
    ],
    'stock': [
      'stock quantity',
      'stock',
      'stock qty',
      'quantity',
      'qty',
      'available stock',
      'inventory',
      'units in stock',
    ],
    'imageUrl': [
      'image url',
      'image',
      'imageurl',
      'photo',
      'img',
      'image link',
      'picture',
      'photo url',
    ],
  };

  /// Safely converts any Excel [Data] cell to a trimmed [String].
  /// Never throws null-check or type errors.
  static String getCellValueAsString(Data? cell) {
    if (cell == null) return '';
    final val = cell.value;
    if (val == null) return '';
    try {
      if (val is TextCellValue) {
        return val.value.toString().trim();
      }
      if (val is FormulaCellValue) {
        return val.formula.trim();
      }
      if (val is IntCellValue) {
        return val.value.toString().trim();
      }
      if (val is DoubleCellValue) {
        return val.value.toString().trim();
      }
      if (val is DateCellValue) {
        return val.asDateTimeLocal().toIso8601String().trim();
      }
      if (val is TimeCellValue) {
        return val.toString().trim();
      }
      if (val is BoolCellValue) {
        return val.value.toString().trim();
      }
      return val.toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Extracts the raw underlying cell value.
  /// Returns null for empty, blank, or null cells.
  static dynamic getRawCellValue(Data? cell) {
    if (cell == null) return null;
    final val = cell.value;
    if (val == null) return null;
    try {
      if (val is TextCellValue) {
        final s = val.value.toString().trim();
        return s.isEmpty ? null : s;
      }
      if (val is IntCellValue) {
        return val.value;
      }
      if (val is DoubleCellValue) {
        return val.value;
      }
      if (val is FormulaCellValue) {
        final f = val.formula.trim();
        return f.isEmpty ? null : f;
      }
      if (val is BoolCellValue) {
        return val.value;
      }
      final s = val.toString().trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// Safely retrieves a cell by index from a row.
  /// Returns null if the index is out of range, negative, or row is null.
  static Data? getCell(List<Data?>? row, int? colIdx) {
    if (row == null || colIdx == null || colIdx < 0 || colIdx >= row.length) {
      return null;
    }
    return row[colIdx];
  }

  /// Checks whether a row is null or has zero data cells (completely empty).
  static bool isRowEmpty(List<Data?>? row) {
    if (row == null || row.isEmpty) return true;
    for (final cell in row) {
      if (cell != null && cell.value != null) {
        final text = getCellValueAsString(cell);
        if (text.isNotEmpty) return false;
      }
    }
    return true;
  }

  /// Safely parses a double from any dynamic value.
  /// Handles numbers, strings with currency symbols (₹, $), commas, etc.
  static double? parseDouble(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    // Strip common currency symbols, commas, and formatting spaces
    s = s
        .replaceAll('₹', '')
        .replaceAll(r'$', '')
        .replaceAll('Rs.', '')
        .replaceAll('Rs', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .trim();
    return double.tryParse(s);
  }

  /// Safely parses an integer from any dynamic value.
  /// Handles numbers, strings with commas, decimal strings (e.g. "50.0"), etc.
  static int? parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    var s = raw.toString().trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(',', '').replaceAll(' ', '').trim();
    final d = double.tryParse(s);
    return d?.toInt() ?? int.tryParse(s);
  }

  /// Maps row cells to standard column keys based on header names.
  static Map<String, int> mapHeaders(List<Data?>? row) {
    final map = <String, int>{};
    if (row == null || row.isEmpty) return map;
    for (int i = 0; i < row.length; i++) {
      final cell = row[i];
      if (cell == null) continue;
      final rawVal = getCellValueAsString(cell).toLowerCase();
      if (rawVal.isEmpty) continue;

      for (final entry in _headerAliases.entries) {
        if (!map.containsKey(entry.key)) {
          if (entry.value.contains(rawVal)) {
            map[entry.key] = i;
            break;
          }
        }
      }
    }

    // Positional fallback for 10-column standard templates if 'productName' was not matched
    if (!map.containsKey('productName') && row.length >= 10) {
      map.putIfAbsent('productName', () => 0);
      map.putIfAbsent('productNameTamil', () => 1);
      map.putIfAbsent('category', () => 2);
      map.putIfAbsent('brand', () => 3);
      map.putIfAbsent('description', () => 4);
      map.putIfAbsent('unit', () => 5);
      map.putIfAbsent('mrp', () => 6);
      map.putIfAbsent('sellingPrice', () => 7);
      map.putIfAbsent('stock', () => 8);
      map.putIfAbsent('imageUrl', () => 9);
    }

    return map;
  }

  /// Parses an Excel file from raw bytes into validated [ParsedExcelResult].
  ///
  /// Features:
  /// - Completely null-safe (zero force unwrapping).
  /// - Automatically identifies the sheet containing product data.
  /// - Automatically detects header row position.
  /// - Matches columns by header name or aliases.
  /// - Gracefully handles missing cells, short rows, empty rows, extra columns.
  /// - Formats exact error messages with Sheet, Row, Column, and error details.
  /// - Safely converts optional fields to empty strings/defaults without discarding rows.
  static ParsedExcelResult parseBytes(
    Uint8List bytes, {
    Map<String, String>? existingProducts,
  }) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception(
        'The selected Excel file contains no sheets. '
        'This may mean the file is empty, password-protected, or uses a format not supported by the parser.',
      );
    }

    // 1. Locate the best target sheet and its header row
    String? targetSheetName;
    Sheet? targetSheet;
    Map<String, int>? columnMap;
    int headerRowIndex = 0;

    for (final sheetName in excel.tables.keys) {
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.maxRows <= 0) continue;

      final rows = sheet.rows;
      for (int r = 0; r < rows.length && r < 15; r++) {
        final row = rows[r];
        if (row.isEmpty) continue;
        final candidateMap = mapHeaders(row);
        if (candidateMap.containsKey('productName') &&
            (candidateMap.containsKey('sellingPrice') || candidateMap.containsKey('mrp'))) {
          targetSheetName = sheetName;
          targetSheet = sheet;
          columnMap = candidateMap;
          headerRowIndex = r;
          break;
        }
      }
      if (targetSheet != null) break;
    }

    // Fallback: Use the first non-empty sheet
    if (targetSheet == null) {
      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName];
        if (sheet != null && sheet.maxRows > 0) {
          targetSheetName = sheetName;
          targetSheet = sheet;
          if (sheet.rows.isNotEmpty) {
            columnMap = mapHeaders(sheet.rows.first);
            headerRowIndex = 0;
          }
          break;
        }
      }
    }

    if (targetSheet == null || targetSheetName == null) {
      // Build a diagnostic message showing what sheets were found
      final sheetInfo = excel.tables.entries.map((e) {
        final rows = e.value.maxRows;
        return '"${e.key}" ($rows rows)';
      }).join(', ');
      throw Exception(
        'The Excel file has no readable sheets or rows.\n'
        'Sheets found: ${sheetInfo.isEmpty ? "none" : sheetInfo}',
      );
    }


    columnMap ??= {};

    // Validate presence of required headers
    final missingHeaders = <String>[];
    if (!columnMap.containsKey('productName')) missingHeaders.add('Product Name');
    if (!columnMap.containsKey('unit')) missingHeaders.add('Unit');
    if (!columnMap.containsKey('mrp')) missingHeaders.add('MRP');
    if (!columnMap.containsKey('sellingPrice')) missingHeaders.add('Selling Price');
    if (!columnMap.containsKey('stock')) missingHeaders.add('Stock Quantity');

    if (missingHeaders.isNotEmpty) {
      throw Exception(
        'Required column(s) not found in sheet "$targetSheetName":\n'
        '${missingHeaders.join(', ')}\n\n'
        'Please ensure the Excel headers include: Product Name, Unit, MRP, Selling Price, Stock Quantity.',
      );
    }

    final rows = targetSheet.rows;
    final List<ExcelRowData> parsedRows = [];
    final List<String> errorLog = [];
    int emptyRowsSkipped = 0;

    final colName = columnMap['productName'];
    final colTamil = columnMap['productNameTamil'];
    final colCat = columnMap['category'];
    final colBrand = columnMap['brand'];
    final colDesc = columnMap['description'];
    final colUnit = columnMap['unit'];
    final colMrp = columnMap['mrp'];
    final colPrice = columnMap['sellingPrice'];
    final colStock = columnMap['stock'];
    final colImg = columnMap['imageUrl'];

    final existing = existingProducts ?? const <String, String>{};

    // 2. Iterate through data rows after the header row
    for (int r = headerRowIndex + 1; r < rows.length; r++) {
      final row = rows[r];
      final displayRow = r + 1; // 1-based row number for user display

      // Safely ignore completely empty rows
      if (isRowEmpty(row)) {
        emptyRowsSkipped++;
        continue;
      }

      // Safe cell value extraction (zero force unwrapping)
      final productName = getCellValueAsString(getCell(row, colName)).trim();
      final productNameTamil = getCellValueAsString(getCell(row, colTamil)).trim();
      final category = getCellValueAsString(getCell(row, colCat)).trim();
      final brand = getCellValueAsString(getCell(row, colBrand)).trim();
      final description = getCellValueAsString(getCell(row, colDesc)).trim();
      final unit = getCellValueAsString(getCell(row, colUnit)).trim();
      final imageUrl = getCellValueAsString(getCell(row, colImg)).trim();

      final rawMrp = getRawCellValue(getCell(row, colMrp));
      final rawPrice = getRawCellValue(getCell(row, colPrice));
      final rawStock = getRawCellValue(getCell(row, colStock));

      final List<String> rowErrors = [];

      // Required Field 1: Product Name
      if (productName.isEmpty) {
        rowErrors.add('Row $displayRow: [Product Name] is required (Sheet: $targetSheetName, Column: Product Name)');
      }

      // Required Field 2: Unit
      if (unit.isEmpty) {
        rowErrors.add('Row $displayRow: [Unit] is required (Sheet: $targetSheetName, Column: Unit)');
      }

      // Required Field 3: MRP
      double mrp = 0.0;
      if (rawMrp == null) {
        rowErrors.add('Row $displayRow: [MRP] is required (Sheet: $targetSheetName, Column: MRP)');
      } else {
        final parsedMrp = parseDouble(rawMrp);
        if (parsedMrp == null) {
          rowErrors.add('Row $displayRow: [MRP] must be a valid number, found "$rawMrp" (Sheet: $targetSheetName, Column: MRP)');
        } else if (parsedMrp < 0) {
          rowErrors.add('Row $displayRow: [MRP] cannot be negative, found "$rawMrp" (Sheet: $targetSheetName, Column: MRP)');
        } else {
          mrp = parsedMrp;
        }
      }

      // Required Field 4: Selling Price
      double price = 0.0;
      if (rawPrice == null) {
        rowErrors.add('Row $displayRow: [Selling Price] is required (Sheet: $targetSheetName, Column: Selling Price)');
      } else {
        final parsedPrice = parseDouble(rawPrice);
        if (parsedPrice == null) {
          rowErrors.add('Row $displayRow: [Selling Price] must be a valid number, found "$rawPrice" (Sheet: $targetSheetName, Column: Selling Price)');
        } else if (parsedPrice < 0) {
          rowErrors.add('Row $displayRow: [Selling Price] cannot be negative, found "$rawPrice" (Sheet: $targetSheetName, Column: Selling Price)');
        } else {
          price = parsedPrice;
        }
      }

      // Required Field 5: Stock Quantity
      int stock = 0;
      if (rawStock == null) {
        rowErrors.add('Row $displayRow: [Stock Quantity] is required (Sheet: $targetSheetName, Column: Stock Quantity)');
      } else {
        final parsedStock = parseInt(rawStock);
        if (parsedStock == null) {
          rowErrors.add('Row $displayRow: [Stock Quantity] must be a valid integer, found "$rawStock" (Sheet: $targetSheetName, Column: Stock Quantity)');
        } else if (parsedStock < 0) {
          rowErrors.add('Row $displayRow: [Stock Quantity] cannot be negative, found "$rawStock" (Sheet: $targetSheetName, Column: Stock Quantity)');
        } else {
          stock = parsedStock;
        }
      }

      // Duplicate match lookup
      String? existingDocId;
      if (productName.isNotEmpty) {
        existingDocId = existing[productName.toLowerCase()];
      }

      final rowData = ExcelRowData(
        rowIndex: displayRow,
        sheetName: targetSheetName,
        productName: productName,
        productNameTamil: productNameTamil,
        category: category,
        brand: brand,
        description: description,
        unit: unit,
        mrp: mrp,
        sellingPrice: price,
        stock: stock,
        imageUrl: imageUrl,
        errors: rowErrors,
        existingDocId: existingDocId,
      );

      parsedRows.add(rowData);

      if (rowErrors.isNotEmpty) {
        errorLog.add('Row $displayRow (Sheet: $targetSheetName):\n${rowErrors.join('\n')}\n--------------------------------');
      }
    }

    return ParsedExcelResult(
      sheetName: targetSheetName,
      headerRowIndex: headerRowIndex + 1,
      columnMap: columnMap,
      rows: parsedRows,
      errorLog: errorLog,
      totalRowsRead: rows.length,
      emptyRowsSkipped: emptyRowsSkipped,
    );
  }
}

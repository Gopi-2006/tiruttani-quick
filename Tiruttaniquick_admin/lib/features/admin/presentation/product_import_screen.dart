import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

import '../../../services/file_saver.dart';

class ExcelRowData {
  final int rowIndex;
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

class ProductImportScreen extends StatefulWidget {
  const ProductImportScreen({super.key});

  @override
  State<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends State<ProductImportScreen> {
  PlatformFile? _selectedFile;
  bool _isProcessingFile = false;
  bool _isImporting = false;
  String _processingStatus = '';
  
  List<ExcelRowData> _allRows = [];
  List<ExcelRowData> _filteredRows = [];
  List<String> _errorLog = [];

  // Search & Filtering States
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'name'; // 'name', 'price', 'stock'
  String _filterStatus = 'all'; // 'all', 'valid', 'invalid', 'new', 'duplicate'
  
  // Progress states
  double _importProgress = 0.0;
  int _processedCount = 0;
  int _totalToProcess = 0;
  String _estimatedTimeRemaining = '';

  // Summary counts
  int _summaryTotalRead = 0;
  int _summaryImported = 0;
  int _summaryUpdated = 0;
  int _summaryFailed = 0;
  int _summarySkipped = 0;
  Duration _summaryTimeTaken = Duration.zero;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFile = result.files.first;
          _allRows.clear();
          _filteredRows.clear();
          _errorLog.clear();
        });
      }
    } catch (e) {
      _showErrorDialog('File Picking Error', 'Failed to pick file: $e');
    }
  }

  void _removeFile() {
    setState(() {
      _selectedFile = null;
      _allRows.clear();
      _filteredRows.clear();
      _errorLog.clear();
    });
  }

  Future<void> _processExcelFile() async {
    if (_selectedFile == null) return;

    setState(() {
      _isProcessingFile = true;
      _processingStatus = 'Reading Excel file...';
    });

    try {
      Uint8List? fileBytes = _selectedFile!.bytes;
      if (fileBytes == null && _selectedFile!.path != null) {
        final file = File(_selectedFile!.path!);
        fileBytes = await file.readAsBytes();
      }

      if (fileBytes == null) {
        throw Exception('Could not read Excel file content.');
      }

      final excel = Excel.decodeBytes(fileBytes);
      if (excel.tables.isEmpty) {
        throw Exception('The selected Excel file contains no sheets.');
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];
      if (sheet == null || sheet.maxRows <= 1) {
        throw Exception('The Excel sheet is empty or contains no data rows.');
      }

      final rows = sheet.rows;
      final headers = rows.first;
      
      // Validate columns
      if (headers.length < 10) {
        throw Exception('Excel file must have at least 10 columns in order.');
      }

      final expectedHeaders = [
        'Product Name',
        'Product Name (Tamil)',
        'Category',
        'Brand',
        'Description',
        'Unit',
        'MRP',
        'Selling Price',
        'Stock Quantity',
        'Image URL'
      ];

      for (int i = 0; i < 10; i++) {
        final headerVal = headers[i]?.value?.toString().trim().toLowerCase();
        if (headerVal != expectedHeaders[i].toLowerCase()) {
          throw Exception(
            "Column structure mismatch at index ${i + 1}. Expected '${expectedHeaders[i]}' but found '${headers[i]?.value ?? 'Empty'}'.\nPlease ensure the Excel template format matches exactly."
          );
        }
      }

      setState(() {
        _processingStatus = 'Validating rows & searching database duplicates...';
      });

      // Fetch duplicate detection dictionary (match by parent product name)
      final existingProducts = <String, String>{};
      final db = FirebaseFirestore.instance;
      final snapshot = await db.collection('products').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = (data['productName'] as String? ?? data['name'] as String? ?? '').trim().toLowerCase();
        if (name.isNotEmpty) {
          existingProducts[name] = doc.id;
        }
      }

      final List<ExcelRowData> parsedRows = [];
      final List<String> tempErrorLog = [];

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty || row.every((cell) => cell?.value == null)) {
          continue; // Skip completely empty rows
        }

        // Pad row cells to 10 columns if short
        while (row.length < 10) {
          row.add(null);
        }

        final productName = row[0]?.value?.toString().trim() ?? '';
        final productNameTamil = row[1]?.value?.toString().trim() ?? '';
        final category = row[2]?.value?.toString().trim() ?? '';
        final brand = row[3]?.value?.toString().trim() ?? '';
        final description = row[4]?.value?.toString().trim() ?? '';
        final unit = row[5]?.value?.toString().trim() ?? '';
        
        final rawMrp = row[6]?.value;
        final rawPrice = row[7]?.value;
        final rawStock = row[8]?.value;
        final imageUrl = row[9]?.value?.toString().trim() ?? '';

        final List<String> rowErrors = [];

        // Validation Rules
        if (productName.isEmpty) rowErrors.add('Product Name is empty');
        if (unit.isEmpty) rowErrors.add('Unit is empty');

        // Numeric parsing
        double mrp = 0.0;
        if (rawMrp == null) {
          rowErrors.add('MRP is missing');
        } else {
          final parsed = double.tryParse(rawMrp.toString());
          if (parsed == null) {
            rowErrors.add('MRP is not numeric ("$rawMrp")');
          } else {
            mrp = parsed;
          }
        }

        double price = 0.0;
        if (rawPrice == null) {
          rowErrors.add('Selling Price is missing');
        } else {
          final parsed = double.tryParse(rawPrice.toString());
          if (parsed == null) {
            rowErrors.add('Selling Price is not numeric ("$rawPrice")');
          } else {
            price = parsed;
          }
        }

        int stock = 0;
        if (rawStock == null) {
          rowErrors.add('Stock Quantity is missing');
        } else {
          final parsed = int.tryParse(rawStock.toString());
          if (parsed == null) {
            rowErrors.add('Stock Quantity is not numeric ("$rawStock")');
          } else {
            stock = parsed;
          }
        }

        // Duplicate Check (Matches existing parent product by name)
        String? existingId;
        if (productName.isNotEmpty) {
          existingId = existingProducts[productName.toLowerCase()];
        }

        final rowData = ExcelRowData(
          rowIndex: r + 1,
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
          existingDocId: existingId,
        );

        parsedRows.add(rowData);

        if (rowErrors.isNotEmpty) {
          tempErrorLog.add('Row ${r + 1}\n${rowErrors.join('\n')}\n--------------------------------');
        }
      }

      setState(() {
        _allRows = parsedRows;
        _errorLog = tempErrorLog;
        _isProcessingFile = false;
        _applyFilters();
      });
    } catch (e) {
      setState(() {
        _isProcessingFile = false;
      });
      _showErrorDialog('Parsing Failed', e.toString());
    }
  }

  void _applyFilters() {
    List<ExcelRowData> filtered = List.from(_allRows);

    // Apply Search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((row) {
        return row.productName.toLowerCase().contains(_searchQuery) ||
               row.productNameTamil.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // Apply Status Filter
    if (_filterStatus != 'all') {
      filtered = filtered.where((row) {
        return switch (_filterStatus) {
          'valid' => row.isValid,
          'invalid' => !row.isValid,
          'new' => row.isValid && !row.isDuplicate,
          'duplicate' => row.isValid && row.isDuplicate,
          _ => true
        };
      }).toList();
    }

    // Apply Sorting
    filtered.sort((a, b) {
      return switch (_sortBy) {
        'name' => a.productName.toLowerCase().compareTo(b.productName.toLowerCase()),
        'price' => a.sellingPrice.compareTo(b.sellingPrice),
        'stock' => a.stock.compareTo(b.stock),
        _ => 0
      };
    });

    setState(() {
      _filteredRows = filtered;
    });
  }

  Future<void> _importProducts() async {
    final validRows = _allRows.where((r) => r.isValid).toList();
    if (validRows.isEmpty) {
      _showErrorDialog('No Valid Products', 'There are no valid products to import from this Excel file.');
      return;
    }

    setState(() {
      _isImporting = true;
      _processedCount = 0;
      _totalToProcess = validRows.length;
      _importProgress = 0.0;
      _estimatedTimeRemaining = 'Calculating...';
    });

    final stopwatch = Stopwatch()..start();
    final db = FirebaseFirestore.instance;
    int imported = 0;
    int updated = 0;
    int failed = 0;

    // 1. Group rows by Product Name
    final Map<String, List<ExcelRowData>> groups = {};
    for (final row in validRows) {
      final nameKey = row.productName.trim();
      if (!groups.containsKey(nameKey)) {
        groups[nameKey] = [];
      }
      groups[nameKey]!.add(row);
    }

    // 2. Fetch all existing categories first to avoid querying inside transaction
    final categoryMap = <String, String>{}; // name.toLowerCase() -> id
    try {
      final catSnap = await db.collection('categories').get();
      for (final doc in catSnap.docs) {
        final name = (doc.data()['name'] as String? ?? '').trim().toLowerCase();
        if (name.isNotEmpty) {
          categoryMap[name] = doc.id;
        }
      }
    } catch (e) {
      debugPrint('Error pre-fetching categories: $e');
    }

    // Pre-create any category that doesn't exist yet
    final categoriesToCreate = <String>{};
    for (final row in validRows) {
      final catName = row.category.trim();
      if (catName.isNotEmpty && !categoryMap.containsKey(catName.toLowerCase())) {
        categoriesToCreate.add(catName);
      }
    }

    for (final catName in categoriesToCreate) {
      try {
        final docRef = db.collection('categories').doc();
        await docRef.set({
          'name': catName,
          'imageUrl': '',
          'categoryImage': '',
          'color': '#00A86B',
          'sortOrder': 999,
        });
        categoryMap[catName.toLowerCase()] = docRef.id;
        debugPrint('Automatically created category: $catName');
      } catch (e) {
        debugPrint('Error creating category "$catName": $e');
      }
    }

    // Ensure we have a default "General" category
    if (!categoryMap.containsKey('general')) {
      try {
        final docRef = db.collection('categories').doc();
        await docRef.set({
          'name': 'General',
          'imageUrl': '',
          'categoryImage': '',
          'color': '#00A86B',
          'sortOrder': 999,
        });
        categoryMap['general'] = docRef.id;
      } catch (e) {
        debugPrint('Error creating default General category: $e');
      }
    }

    // 3. Process each group transactionally
    final parentNames = groups.keys.toList();
    int rowCount = 0;

    for (final parentName in parentNames) {
      final groupRows = groups[parentName]!;
      final firstRow = groupRows.first;

      // Resolve Category ID
      final String productCategoryName = firstRow.category.trim();
      final String resolvedCategoryId = productCategoryName.isNotEmpty
          ? (categoryMap[productCategoryName.toLowerCase()] ?? categoryMap['general'] ?? 'general')
          : (categoryMap['general'] ?? 'general');

      try {
        await db.runTransaction((transaction) async {
          if (firstRow.isDuplicate && firstRow.existingDocId != null) {
            // Merge variants into existing parent product
            final parentRef = db.collection('products').doc(firstRow.existingDocId);
            final parentSnap = await transaction.get(parentRef);

            if (parentSnap.exists) {
              final product = ProductModel.fromFirestore(parentSnap.id, parentSnap.data() as Map<String, dynamic>);
              final List<ProductVariantModel> existingVariants = List.from(product.variants);

              for (final row in groupRows) {
                final mrp = row.mrp;
                final price = row.sellingPrice;
                double discount = mrp > price && mrp > 0 ? (((mrp - price) / mrp) * 100).roundToDouble() : 0.0;

                // Parse Unit into size and unitType
                final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(row.unit);
                String size = '1';
                String unitType = 'Pieces';
                if (match != null) {
                  size = match.group(1) ?? '1';
                  unitType = match.group(2)?.trim() ?? 'Pieces';
                  if (unitType.isEmpty) unitType = 'Pieces';
                } else {
                  size = '1';
                  unitType = row.unit.trim();
                  if (unitType.isEmpty) unitType = 'Pieces';
                }

                final matchIndex = existingVariants.indexWhere((v) =>
                  v.name.toLowerCase() == row.unit.toLowerCase()
                );

                final newV = ProductVariantModel(
                  id: matchIndex != -1 
                      ? existingVariants[matchIndex].id 
                      : '${DateTime.now().millisecondsSinceEpoch}_${row.rowIndex}',
                  name: row.unit,
                  size: size,
                  unitType: unitType,
                  mrp: mrp,
                  price: price,
                  purchasePrice: 0.0,
                  discount: discount,
                  stockQuantity: row.stock,
                  lowStockThreshold: 5,
                  status: row.stock > 0 ? 'Available' : 'Out of Stock',
                  barcode: '',
                  sku: matchIndex != -1 ? existingVariants[matchIndex].sku : '${parentName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}_${unitType.toLowerCase()}_$size',
                  imageUrl: row.imageUrl.isNotEmpty ? row.imageUrl : (matchIndex != -1 ? existingVariants[matchIndex].imageUrl : ''),
                );

                if (matchIndex != -1) {
                  existingVariants[matchIndex] = newV;
                } else {
                  existingVariants.add(newV);
                }
              }

              final double lowestPrice = existingVariants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
              final double lowestMrp = existingVariants.map((v) => v.mrp).reduce((a, b) => a < b ? a : b);
              final int totalStock = existingVariants.map((v) => v.stockQuantity).reduce((a, b) => a + b);

              transaction.update(parentRef, {
                'variantsEnabled': true,
                'variants': existingVariants.map((v) => v.toMap()).toList(),
                'price': lowestPrice,
                'mrp': lowestMrp,
                'stockQuantity': totalStock,
                'updatedAt': FieldValue.serverTimestamp(),
                if (firstRow.description.isNotEmpty) 'description': firstRow.description,
                if (firstRow.productNameTamil.isNotEmpty) 'nameTamil': firstRow.productNameTamil,
                if (firstRow.brand.isNotEmpty) 'brand': firstRow.brand,
                'category': resolvedCategoryId,
                'categoryId': resolvedCategoryId,
              });
              updated += groupRows.length;
            } else {
              failed += groupRows.length;
            }
          } else {
            // Create a brand new parent product with variants
            final newParentRef = db.collection('products').doc();
            final List<ProductVariantModel> newVariants = [];

            for (final row in groupRows) {
              final mrp = row.mrp;
              final price = row.sellingPrice;
              double discount = mrp > price && mrp > 0 ? (((mrp - price) / mrp) * 100).roundToDouble() : 0.0;

              // Parse Unit into size and unitType
              final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$').firstMatch(row.unit);
              String size = '1';
              String unitType = 'Pieces';
              if (match != null) {
                size = match.group(1) ?? '1';
                unitType = match.group(2)?.trim() ?? 'Pieces';
                if (unitType.isEmpty) unitType = 'Pieces';
              } else {
                size = '1';
                unitType = row.unit.trim();
                if (unitType.isEmpty) unitType = 'Pieces';
              }

              newVariants.add(ProductVariantModel(
                id: '${DateTime.now().millisecondsSinceEpoch}_${row.rowIndex}',
                name: row.unit,
                size: size,
                unitType: unitType,
                mrp: mrp,
                price: price,
                purchasePrice: 0.0,
                discount: discount,
                stockQuantity: row.stock,
                lowStockThreshold: 5,
                status: row.stock > 0 ? 'Available' : 'Out of Stock',
                barcode: '',
                sku: '${parentName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')}_${unitType.toLowerCase()}_$size',
                imageUrl: row.imageUrl,
              ));
            }

            final double lowestPrice = newVariants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
            final double lowestMrp = newVariants.map((v) => v.mrp).reduce((a, b) => a < b ? a : b);
            final int totalStock = newVariants.map((v) => v.stockQuantity).reduce((a, b) => a + b);

            transaction.set(newParentRef, {
              'productName': parentName,
              'name': parentName,
              'nameTamil': groupRows.first.productNameTamil,
              'brand': groupRows.first.brand.isNotEmpty ? groupRows.first.brand : 'Imported',
              'description': groupRows.first.description.isNotEmpty ? groupRows.first.description : 'Imported product with variants.',
              'category': resolvedCategoryId,
              'categoryId': resolvedCategoryId,
              'unit': newVariants.first.name,
              'mrp': lowestMrp,
              'sellingPrice': lowestPrice,
              'price': lowestPrice,
              'stockQuantity': totalStock,
              'imageUrl': newVariants.first.imageUrl,
              'isActive': true,
              'sortOrder': 0,
              'variantsEnabled': true,
              'variants': newVariants.map((v) => v.toMap()).toList(),
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            imported += groupRows.length;
          }
        });
      } catch (e) {
        debugPrint('Error importing product "$parentName": $e');
        failed += groupRows.length;
      }

      rowCount += groupRows.length;
      if (!mounted) return;

      setState(() {
        _processedCount = rowCount;
        _importProgress = _processedCount / _totalToProcess;

        final elapsed = stopwatch.elapsedMilliseconds;
        final averageTime = elapsed / _processedCount;
        final remaining = _totalToProcess - _processedCount;
        final etaSeconds = ((remaining * averageTime) / 1000).ceil();

        if (etaSeconds > 60) {
          _estimatedTimeRemaining = '${(etaSeconds / 60).floor()}m ${etaSeconds % 60}s';
        } else {
          _estimatedTimeRemaining = '${etaSeconds}s remaining';
        }
      });
    }

    stopwatch.stop();

    setState(() {
      _isImporting = false;
      _summaryTotalRead = _allRows.length;
      _summaryImported = imported;
      _summaryUpdated = updated;
      _summaryFailed = failed + (_allRows.length - validRows.length);
      _summarySkipped = _allRows.length - validRows.length;
      _summaryTimeTaken = stopwatch.elapsed;
    });

    _showSummaryDialog();
  }

  Future<void> _downloadTemplate() async {
    try {
      final excel = Excel.createExcel();
      final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(defaultSheet, 'Products Template');
      final sheet = excel['Products Template'];

      sheet.appendRow([
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
      ]);

      sheet.appendRow([
        TextCellValue('Apple Red'),
        TextCellValue('ஆப்பிள் சிவப்பு'),
        TextCellValue('Fruits'),
        TextCellValue('Fresh'),
        TextCellValue('Crisp and sweet red apples'),
        TextCellValue('500 g'),
        TextCellValue('120'),
        TextCellValue('100'),
        TextCellValue('50'),
        TextCellValue('https://example.com/apple.jpg'),
      ]);

      final bytes = excel.save();
      if (bytes != null) {
        final path = await FileSaver().saveFile(bytes, 'product_import_template.xlsx');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Template downloaded successfully! Saved to: $path'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _showErrorDialog('Download Failed', 'Failed to generate Excel template: $e');
    }
  }

  Future<void> _downloadErrorReport() async {
    if (_errorLog.isEmpty) return;

    try {
      final reportText = 'Product Import Error Report\n\n'
          'Total failed rows: ${_allRows.where((r) => !r.isValid).length}\n\n'
          '${_errorLog.join('\n')}';

      final bytes = utf8.encode(reportText);
      final path = await FileSaver().saveFile(bytes, 'product_import_errors.txt');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error report downloaded! Saved to: $path'),
            backgroundColor: Colors.blueAccent,
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('Download Failed', 'Failed to save error report: $e');
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 40),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSummaryDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final hasErrors = _summarySkipped > 0;
        return AlertDialog(
          icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 48),
          title: const Text('Import Completed Successfully'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSummaryRow('Total Products Read:', '$_summaryTotalRead'),
              _buildSummaryRow('Products Imported (New):', '$_summaryImported', color: Colors.green.shade700),
              _buildSummaryRow('Products Updated:', '$_summaryUpdated', color: Colors.blue.shade700),
              _buildSummaryRow('Products Skipped (Invalid):', '$_summarySkipped', color: hasErrors ? Colors.orange.shade700 : null),
              _buildSummaryRow('Products Failed to Upload:', '$_summaryFailed', color: _summaryFailed > 0 ? Colors.red : null),
              _buildSummaryRow('Total Time Taken:', '${_summaryTimeTaken.inSeconds} seconds'),
            ],
          ),
          actions: [
            if (hasErrors)
              TextButton.icon(
                icon: const Icon(Icons.download),
                label: const Text('Download Error Report'),
                onPressed: () {
                  Navigator.pop(context);
                  _downloadErrorReport();
                },
              ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.pop(); // Returns back to Product Catalog dashboard
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 800;
    
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Product Import', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text('Import products directly from an Excel file.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildUploadCard(),
                const SizedBox(height: 16),
                
                if (_allRows.isNotEmpty) ...[
                  _buildControlsAndFilters(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: isDesktop ? _buildDesktopPreviewTable() : _buildMobilePreviewList(),
                  ),
                ] else
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.description_outlined, size: 64, color: AppColors.border),
                          SizedBox(height: 12),
                          Text(
                            'No file loaded. Please upload a valid Excel file.',
                            style: TextStyle(color: AppColors.muted, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 16),
                _buildActionButtons(),
              ],
            ),
          ),
          
          if (_isProcessingFile)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_processingStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
          if (_isImporting)
            Container(
              color: Colors.black45,
              child: Center(
                child: Container(
                  width: 340,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Uploading Products...',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: _importProgress),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('$_processedCount / $_totalToProcess Uploaded'),
                          Text('${(_importProgress * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Estimated Time:', style: TextStyle(color: AppColors.muted)),
                          Text(_estimatedTimeRemaining, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Excel Upload',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedFile == null
                            ? 'Select product import sheet (.xlsx only)'
                            : '${_selectedFile!.name} (${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB)',
                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (_selectedFile != null) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _removeFile,
                    tooltip: 'Remove File',
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Choose File'),
                    onPressed: _pickFile,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsAndFilters() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search & Sort row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim().toLowerCase();
                        _applyFilters();
                      });
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by Product Name, Brand, Category...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.sort),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Sort by Name')),
                    DropdownMenuItem(value: 'price', child: Text('Sort by Price')),
                    DropdownMenuItem(value: 'stock', child: Text('Sort by Stock')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _sortBy = val;
                        _applyFilters();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Filter:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 8),
                  _buildFilterChip('All (${_allRows.length})', 'all'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Valid (${_allRows.where((r) => r.isValid).length})', 'valid'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Invalid (${_allRows.where((r) => !r.isValid).length})', 'invalid'),
                  const SizedBox(width: 6),
                  _buildFilterChip('New (${_allRows.where((r) => r.isValid && !r.isDuplicate).length})', 'new'),
                  const SizedBox(width: 6),
                  _buildFilterChip('To Update (${_allRows.where((r) => r.isValid && r.isDuplicate).length})', 'duplicate'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final selected = _filterStatus == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (bool select) {
        if (select) {
          setState(() {
            _filterStatus = value;
            _applyFilters();
          });
        }
      },
    );
  }

  Widget _buildDesktopPreviewTable() {
    if (_filteredRows.isEmpty) {
      return const Center(child: Text('No matching items found.', style: TextStyle(color: AppColors.muted)));
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
            columns: const [
              DataColumn(label: Text('Product Name')),
              DataColumn(label: Text('Product Name (Tamil)')),
              DataColumn(label: Text('Category')),
              DataColumn(label: Text('Brand')),
              DataColumn(label: Text('Description')),
              DataColumn(label: Text('Unit')),
              DataColumn(label: Text('MRP')),
              DataColumn(label: Text('Selling Price')),
              DataColumn(label: Text('Stock Quantity')),
              DataColumn(label: Text('Image URL')),
              DataColumn(label: Text('Validation Status')),
            ],
            rows: _filteredRows.map((row) {
              return DataRow(
                color: row.isValid ? null : WidgetStateProperty.all(Colors.red.shade50.withValues(alpha: 0.3)),
                cells: [
                  DataCell(Text(row.productName, style: const TextStyle(fontWeight: FontWeight.w500))),
                  DataCell(Text(row.productNameTamil)),
                  DataCell(Text(row.category)),
                  DataCell(Text(row.brand)),
                  DataCell(Text(row.description)),
                  DataCell(Text(row.unit)),
                  DataCell(Text('₹${row.mrp.toStringAsFixed(2)}')),
                  DataCell(Text('₹${row.sellingPrice.toStringAsFixed(2)}')),
                  DataCell(Text('${row.stock}')),
                  DataCell(Text(row.imageUrl.isNotEmpty ? 'Has URL' : 'None', style: TextStyle(color: row.imageUrl.isNotEmpty ? Colors.green : Colors.grey))),
                  DataCell(_buildStatusChip(row)),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildMobilePreviewList() {
    if (_filteredRows.isEmpty) {
      return const Center(child: Text('No matching items found.', style: TextStyle(color: AppColors.muted)));
    }

    return ListView.separated(
      itemCount: _filteredRows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = _filteredRows[index];
        return Card(
          elevation: 0,
          color: row.isValid ? null : Colors.red.shade50.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: row.isValid ? AppColors.border : Colors.red.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.inventory_2_outlined, size: 40, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.productName.isEmpty ? '(Empty Name)' : row.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tamil Name: ${row.productNameTamil} (${row.unit})',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.blueGrey, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text('Category: ${row.category} | Brand: ${row.brand}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      Text('Description: ${row.description}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('Sell: ₹${row.sellingPrice} ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('(MRP: ₹${row.mrp}) ', style: const TextStyle(color: AppColors.muted, fontSize: 11, decoration: TextDecoration.lineThrough)),
                          Text('| Stock: ${row.stock}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _buildStatusChip(row),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusChip(ExcelRowData row) {
    if (!row.isValid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Tooltip(
          message: row.errors.join('\n'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade900),
              const SizedBox(width: 4),
              Text('Invalid (${row.errors.length})', style: TextStyle(color: Colors.red.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (row.isDuplicate) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_alt, size: 14, color: Colors.blue.shade900),
            const SizedBox(width: 4),
            Text('Update', style: TextStyle(color: Colors.blue.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 14, color: Colors.green.shade900),
          const SizedBox(width: 4),
          Text('New', style: TextStyle(color: Colors.green.shade900, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final validCount = _allRows.where((r) => r.isValid).length;
    final fileSelected = _selectedFile != null;
    final previewAvailable = _allRows.isNotEmpty;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _downloadTemplate,
          child: const Text('Download Excel Template'),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        if (fileSelected && !previewAvailable)
          ElevatedButton(
            onPressed: _processExcelFile,
            child: const Text('Preview Products'),
          ),
        if (previewAvailable)
          ElevatedButton(
            onPressed: validCount > 0 ? _importProducts : null,
            child: Text('Import $validCount Products'),
          ),
      ],
    );
  }
}

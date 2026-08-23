import 'package:flutter/material.dart';
import 'package:tiruttaniquick_shared/tiruttaniquick_shared.dart';

/// Modal bottom sheet for Amazon-style filtering and sorting.
class SearchFilterBottomSheet extends StatefulWidget {
  final ProductFilterOptions currentFilters;
  final ProductSortOption currentSort;
  final List<CategoryModel> categories;
  final List<String> availableBrands;
  final Function(ProductFilterOptions filters, ProductSortOption sort) onApply;

  const SearchFilterBottomSheet({
    super.key,
    required this.currentFilters,
    required this.currentSort,
    required this.categories,
    required this.availableBrands,
    required this.onApply,
  });

  @override
  State<SearchFilterBottomSheet> createState() => _SearchFilterBottomSheetState();
}

class _SearchFilterBottomSheetState extends State<SearchFilterBottomSheet> {
  late ProductSortOption _selectedSort;
  late Set<String> _selectedCategoryIds;
  late Set<String> _selectedBrands;
  double? _minPrice;
  double? _maxPrice;
  late bool _inStockOnly;
  int? _minDiscount;

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.currentSort;
    _selectedCategoryIds = Set.from(widget.currentFilters.categoryIds);
    _selectedBrands = Set.from(widget.currentFilters.brands);
    _minPrice = widget.currentFilters.minPrice;
    _maxPrice = widget.currentFilters.maxPrice;
    _inStockOnly = widget.currentFilters.inStockOnly;
    _minDiscount = widget.currentFilters.minDiscount;
  }

  int get _activeCount {
    int count = 0;
    if (_selectedSort != ProductSortOption.relevance) count += 1;
    if (_selectedCategoryIds.isNotEmpty) count += _selectedCategoryIds.length;
    if (_selectedBrands.isNotEmpty) count += _selectedBrands.length;
    if (_minPrice != null || _maxPrice != null) count += 1;
    if (_inStockOnly) count += 1;
    if (_minDiscount != null) count += 1;
    return count;
  }

  void _clearAll() {
    setState(() {
      _selectedSort = ProductSortOption.relevance;
      _selectedCategoryIds.clear();
      _selectedBrands.clear();
      _minPrice = null;
      _maxPrice = null;
      _inStockOnly = false;
      _minDiscount = null;
    });
  }

  void _apply() {
    final updatedFilters = ProductFilterOptions(
      categoryIds: _selectedCategoryIds,
      brands: _selectedBrands,
      minPrice: _minPrice,
      maxPrice: _maxPrice,
      inStockOnly: _inStockOnly,
      minDiscount: _minDiscount,
    );
    widget.onApply(updatedFilters, _selectedSort);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.darkSurface : AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Filters & Sort',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_activeCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$_activeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    if (_activeCount > 0)
                      TextButton(
                        onPressed: _clearAll,
                        child: const Text(
                          'Clear All',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Filter Body ───────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 1. Sort By Section
                _buildSectionHeader('Sort By'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ProductSortOption.values.map((sort) {
                    final isSelected = _selectedSort == sort;
                    return ChoiceChip(
                      label: Text(sort.label),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedSort = sort);
                      },
                      selectedColor: AppColors.amberLight,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primary : (isDarkMode ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : AppColors.border,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // 2. Categories Section
                if (widget.categories.isNotEmpty) ...[
                  _buildSectionHeader('Categories'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.categories.map((cat) {
                      final isSelected = _selectedCategoryIds.contains(cat.id);
                      return FilterChip(
                        label: Text(cat.name),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedCategoryIds.add(cat.id);
                            } else {
                              _selectedCategoryIds.remove(cat.id);
                            }
                          });
                        },
                        selectedColor: AppColors.amberLight,
                        checkmarkColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : (isDarkMode ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : AppColors.border,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                // 3. Brands Section
                if (widget.availableBrands.isNotEmpty) ...[
                  _buildSectionHeader('Brands'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.availableBrands.map((brand) {
                      final isSelected = _selectedBrands.contains(brand);
                      return FilterChip(
                        label: Text(brand),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedBrands.add(brand);
                            } else {
                              _selectedBrands.remove(brand);
                            }
                          });
                        },
                        selectedColor: AppColors.amberLight,
                        checkmarkColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? AppColors.primary : (isDarkMode ? Colors.white70 : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                          side: BorderSide(
                            color: isSelected ? AppColors.primary : AppColors.border,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                // 4. Price Brackets Section
                _buildSectionHeader('Price Range'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPriceChip('Under ₹50', null, 50),
                    _buildPriceChip('₹50 - ₹150', 50, 150),
                    _buildPriceChip('₹150 - ₹300', 150, 300),
                    _buildPriceChip('₹300 - ₹500', 300, 500),
                    _buildPriceChip('Above ₹500', 500, null),
                  ],
                ),

                const SizedBox(height: 20),

                // 5. Discount Section
                _buildSectionHeader('Discount'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [10, 20, 30, 50].map((disc) {
                    final isSelected = _minDiscount == disc;
                    return ChoiceChip(
                      label: Text('$disc% and above'),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          _minDiscount = val ? disc : null;
                        });
                      },
                      selectedColor: AppColors.amberLight,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primary : (isDarkMode ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : AppColors.border,
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),

                // 6. Availability Switch
                _buildSectionHeader('Availability'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'In Stock Only',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Hide products that are currently out of stock',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  value: _inStockOnly,
                  activeThumbColor: AppColors.primary,
                  onChanged: (val) => setState(() => _inStockOnly = val),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // ── Footer Apply Button ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode ? AppColors.darkSurface : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearAll,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                      ),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.borderRadiusMedium),
                      ),
                    ),
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildPriceChip(String label, double? min, double? max) {
    final isSelected = _minPrice == min && _maxPrice == max;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            _minPrice = min;
            _maxPrice = max;
          } else {
            _minPrice = null;
            _maxPrice = null;
          }
        });
      },
      selectedColor: AppColors.amberLight,
      labelStyle: TextStyle(
        color: isSelected ? AppColors.primary : (isDarkMode ? Colors.white70 : Colors.black87),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.buttonRadiusPill),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.border,
        ),
      ),
    );
  }
}

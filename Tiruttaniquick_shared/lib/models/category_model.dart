class CategoryModel {
  final String id;
  final String name;
  final String imageUrl;
  final String? icon;
  final String color;
  final int sortOrder;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.icon,
    required this.color,
    required this.sortOrder,
  });

  /// Backward-compatible getter for widgets referencing categoryImage
  String get categoryImage => imageUrl;

  factory CategoryModel.fromFirestore(String id, Map<String, dynamic> data) {
    final rawImageUrl = data['imageUrl'] as String? ??
        data['categoryImage'] as String? ??
        '';
    final rawIcon = data['icon'] as String?;
    final emojiIcon = (rawIcon != null &&
            !rawIcon.startsWith('http://') &&
            !rawIcon.startsWith('https://'))
        ? rawIcon
        : null;

    return CategoryModel(
      id: id,
      name: data['name'] as String? ?? id,
      imageUrl: rawImageUrl,
      icon: emojiIcon,
      color: data['color'] as String? ?? '#00A86B',
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 999,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'imageUrl': imageUrl,
      'categoryImage': imageUrl,
      'color': color,
      'sortOrder': sortOrder,
      if (icon != null) 'icon': icon,
    };
  }
}



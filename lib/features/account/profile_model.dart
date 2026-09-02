class ProfileModel {
  final String? id;
  final String name;
  final int? age;
  final double? height; // 公分
  final double? weight; // 公斤
  final String? gender;

  ProfileModel({
    this.id,
    required this.name,
    this.age,
    this.height,
    this.weight,
    this.gender,
  });

  // 從後端 JSON 轉成物件
  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      age: json['age'],
      height: (json['height'] as num?)?.toDouble(),
      weight: (json['weight'] as num?)?.toDouble(),
      gender: json['gender'],
    );
  }

  // 從物件轉成要送給後端的 JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      if (age != null) 'age': age,
      if (height != null) 'height': height,
      if (weight != null) 'weight': weight,
      if (gender != null) 'gender': gender,
    };
  }
}
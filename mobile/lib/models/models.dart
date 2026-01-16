class Category {
  final String key;
  final String label;
  final int sortOrder;

  Category({
    required this.key,
    required this.label,
    required this.sortOrder,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      key: json['key'],
      label: json['label'],
      sortOrder: json['sortOrder'] ?? 0,
    );
  }
}

class PaymentMethod {
  final String id;
  final String name;
  final bool isCreditCard;
  final int? closingDay;

  PaymentMethod({
    required this.id,
    required this.name,
    required this.isCreditCard,
    this.closingDay,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'],
      name: json['name'],
      isCreditCard: json['is_credit_card'] ?? false,
      closingDay: json['closing_day'],
    );
  }
}

class UserProfile {
  final String id;
  final String name;
  final String email;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      name: json['name'],
      email: json['email'],
    );
  }
}

class Expense {
  final String? id;
  final String userId;
  final double amount;
  final String categoryKey;
  final String paymentMethodId;
  final String? comment;
  final DateTime spentAt;

  Expense({
    this.id,
    required this.userId,
    required this.amount,
    required this.categoryKey,
    required this.paymentMethodId,
    this.comment,
    required this.spentAt,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'amount': amount,
      'category_key': categoryKey,
      'payment_method_id': paymentMethodId,
      'comment': comment,
      'spent_at': spentAt.toIso8601String(),
    };
  }
}

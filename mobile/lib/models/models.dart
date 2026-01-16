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

class Earning {
  final String? id;
  final String userId;
  final double amount;
  final String? description;
  final DateTime earnedAt;

  Earning({
    this.id,
    required this.userId,
    required this.amount,
    this.description,
    required this.earnedAt,
  });

  factory Earning.fromJson(Map<String, dynamic> json) {
    return Earning(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      description: json['description'],
      earnedAt: DateTime.parse(json['earned_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'amount': amount,
      'description': description,
      'earned_at': earnedAt.toIso8601String(),
    };
  }
}

class Investment {
  final String? id;
  final String userId;
  final String type; // stock, crypto, bond, cash
  final String? symbol;
  final String name;
  final double quantity;
  final double costBasis;
  final String currency; // 'USD' or 'BRL'

  // Enriched fields from backend
  final double? currentPrice;
  final double? currentValueNative;
  final double? currentValueUsd;
  final double? currentValueBrl;
  final double? pnl;
  final double? pnlPct;

  Investment({
    this.id,
    required this.userId,
    required this.type,
    this.symbol,
    required this.name,
    required this.quantity,
    this.costBasis = 0.0,
    this.currency = 'BRL',
    this.currentPrice,
    this.currentValueNative,
    this.currentValueUsd,
    this.currentValueBrl,
    this.pnl,
    this.pnlPct,
  });

  factory Investment.fromJson(Map<String, dynamic> json) {
    return Investment(
      id: json['id'],
      userId: json['user_id'],
      type: json['type'],
      symbol: json['symbol'],
      name: json['name'],
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
      costBasis: (json['cost_basis'] as num? ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'BRL',
      currentPrice: (json['current_price'] as num?)?.toDouble(),
      currentValueNative: (json['current_value_native'] as num?)?.toDouble(),
      currentValueUsd: (json['current_value_usd'] as num?)?.toDouble(),
      currentValueBrl: (json['current_value_brl'] as num?)?.toDouble(),
      pnl: (json['pnl'] as num?)?.toDouble(),
      pnlPct: (json['pnl_pct'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'type': type,
      'symbol': symbol,
      'name': name,
      'quantity': quantity,
      'cost_basis': costBasis,
      'currency': currency,
    };
  }
}

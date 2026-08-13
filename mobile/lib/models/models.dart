class Category {
  final String key;
  final String label;
  final int sortOrder;
  final bool isGlobal;
  final bool isHidden;

  Category({
    required this.key,
    required this.label,
    required this.sortOrder,
    this.isGlobal = true,
    this.isHidden = false,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      key: json['key'],
      label: json['label'],
      sortOrder: json['sort_order'] ?? json['sortOrder'] ?? 0,
      isGlobal: json['is_global'] ?? true,
      isHidden: json['is_hidden'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category && runtimeType == other.runtimeType && key == other.key;

  @override
  int get hashCode => key.hashCode;
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentMethod &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class UserProfile {
  final String id;
  final String name;
  final String? email;
  final bool isVirtual;
  final String? defaultPaymentMethodId;

  UserProfile({
    required this.id,
    required this.name,
    this.email,
    this.isVirtual = false,
    this.defaultPaymentMethodId,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      name: json['name'],
      email: json['email'] as String?,
      isVirtual: (json['is_virtual'] as bool?) ?? false,
      defaultPaymentMethodId: json['default_payment_method_id'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Expense {
  final String? id;
  final String userId;
  final double amount;
  final String categoryKey;
  final String paymentMethodId;
  final String? comment;
  final DateTime spentAt;
  final int installments;
  final String? recurringId;
  final String? installmentGroupId;

  Expense({
    this.id,
    required this.userId,
    required this.amount,
    required this.categoryKey,
    required this.paymentMethodId,
    this.comment,
    required this.spentAt,
    this.installments = 0,
    this.recurringId,
    this.installmentGroupId,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      categoryKey: json['category_key'],
      paymentMethodId: json['payment_method_id'],
      comment: json['comment'],
      spentAt: DateTime.parse(json['spent_at']),
      installments: json['installments'] ?? 0,
      recurringId: json['recurring_id'],
      installmentGroupId: json['installment_group_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'amount': amount,
      'category_key': categoryKey,
      'payment_method_id': paymentMethodId,
      'comment': comment,
      'spent_at': spentAt.toIso8601String(),
      'installments': installments,
      'recurring_id': recurringId,
      if (installmentGroupId != null) 'installment_group_id': installmentGroupId,
    };
  }
}

class RecurringExpense {
  final String? id;
  final String userId;
  final double amount;
  final String categoryKey;
  final String paymentMethodId;
  final String? description;
  final int dayOfMonth;
  final bool active;
  final DateTime? createdAt;

  RecurringExpense({
    this.id,
    required this.userId,
    required this.amount,
    required this.categoryKey,
    required this.paymentMethodId,
    this.description,
    required this.dayOfMonth,
    this.active = true,
    this.createdAt,
  });

  factory RecurringExpense.fromJson(Map<String, dynamic> json) {
    return RecurringExpense(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      categoryKey: json['category_key'],
      paymentMethodId: json['payment_method_id'],
      description: json['description'],
      dayOfMonth: json['day_of_month'] ?? 1,
      active: json['active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'amount': amount,
      'category_key': categoryKey,
      'payment_method_id': paymentMethodId,
      'description': description,
      'day_of_month': dayOfMonth,
      'active': active,
      // created_at is handled by server
    };
  }
}

class Earning {
  final String? id;
  final String userId;
  final double amount;
  final String? description;
  final DateTime earnedAt;
  final String? userName;

  Earning({
    this.id,
    required this.userId,
    required this.amount,
    this.description,
    required this.earnedAt,
    this.userName,
  });

  factory Earning.fromJson(Map<String, dynamic> json) {
    return Earning(
      id: json['id'],
      userId: json['user_id'],
      amount: (json['amount'] as num? ?? 0.0).toDouble(),
      description: json['description'],
      earnedAt: DateTime.parse(json['earned_at']),
      userName: json['user_name'],
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

// ── Investment Asset (position master) ───────────────────────────────────────

class InvestmentAsset {
  final String? id;
  final String familyId;
  final String category; // stock | bond | crypto | cash_broker | cash_home | cash_bank
  final String? symbol;
  final String name;
  final String currency;
  final String? account;
  final String? notes;

  // Computed by backend from transaction history
  final double quantity;
  final double avgCostBrl;
  final double totalInvestedBrl;
  final double realizedGainsBrl;
  final double dividendsBrl;
  final double? currentPrice;
  final double? dailyChangePct;
  final double currentValueBrl;
  final double unrealizedPnlBrl;
  final double unrealizedPnlPct;

  static const Set<String> pricedCategories = {'stock', 'crypto'};
  bool get hasMktPrice => pricedCategories.contains(category) && symbol != null;

  InvestmentAsset({
    this.id,
    required this.familyId,
    required this.category,
    this.symbol,
    required this.name,
    this.currency = 'BRL',
    this.account,
    this.notes,
    this.quantity = 0.0,
    this.avgCostBrl = 0.0,
    this.totalInvestedBrl = 0.0,
    this.realizedGainsBrl = 0.0,
    this.dividendsBrl = 0.0,
    this.currentPrice,
    this.dailyChangePct,
    this.currentValueBrl = 0.0,
    this.unrealizedPnlBrl = 0.0,
    this.unrealizedPnlPct = 0.0,
  });

  factory InvestmentAsset.fromJson(Map<String, dynamic> json) {
    return InvestmentAsset(
      id: json['id'],
      familyId: json['family_id'] ?? '',
      category: json['category'] ?? 'stock',
      symbol: json['symbol'],
      name: json['name'] ?? '',
      currency: json['currency'] ?? 'BRL',
      account: json['account'],
      notes: json['notes'],
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
      avgCostBrl: (json['avg_cost_brl'] as num? ?? 0.0).toDouble(),
      totalInvestedBrl: (json['total_invested_brl'] as num? ?? 0.0).toDouble(),
      realizedGainsBrl: (json['realized_gains_brl'] as num? ?? 0.0).toDouble(),
      dividendsBrl: (json['dividends_brl'] as num? ?? 0.0).toDouble(),
      currentPrice: (json['current_price'] as num?)?.toDouble(),
      dailyChangePct: (json['daily_change_pct'] as num?)?.toDouble(),
      currentValueBrl: (json['current_value_brl'] as num? ?? 0.0).toDouble(),
      unrealizedPnlBrl: (json['unrealized_pnl_brl'] as num? ?? 0.0).toDouble(),
      unrealizedPnlPct: (json['unrealized_pnl_pct'] as num? ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toAssetJson() => {
        'category': category,
        'name': name,
        if (symbol != null) 'symbol': symbol,
        'currency': currency,
        if (account != null) 'account': account,
        if (notes != null) 'notes': notes,
      };
}

// ── Investment Transaction ────────────────────────────────────────────────────

class InvestmentTransaction {
  final String? id;
  final String assetId;
  final String familyId;
  final String transactionType; // buy | sell | dividend | deposit | withdrawal
  final DateTime transactionDate;
  final double quantity;
  final double? pricePerUnitOriginal;
  final String originalCurrency;
  final double originalAmount;
  final double? exchangeRate;
  final double brlAmount;
  final double feesBrl;
  final String? notes;

  // Embedded from JOIN (present in list responses)
  final String? assetName;
  final String? assetSymbol;
  final String? assetCategory;
  final String? assetAccount;

  InvestmentTransaction({
    this.id,
    required this.assetId,
    required this.familyId,
    required this.transactionType,
    required this.transactionDate,
    this.quantity = 0.0,
    this.pricePerUnitOriginal,
    this.originalCurrency = 'BRL',
    required this.originalAmount,
    this.exchangeRate,
    required this.brlAmount,
    this.feesBrl = 0.0,
    this.notes,
    this.assetName,
    this.assetSymbol,
    this.assetCategory,
    this.assetAccount,
  });

  factory InvestmentTransaction.fromJson(Map<String, dynamic> json) {
    final assetInfo = json['investment_assets'] as Map<String, dynamic>?;
    return InvestmentTransaction(
      id: json['id'],
      assetId: json['asset_id'] ?? '',
      familyId: json['family_id'] ?? '',
      transactionType: json['transaction_type'] ?? 'buy',
      transactionDate: DateTime.parse(json['transaction_date']),
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
      pricePerUnitOriginal: (json['price_per_unit_original'] as num?)?.toDouble(),
      originalCurrency: json['original_currency'] ?? 'BRL',
      originalAmount: (json['original_amount'] as num? ?? 0.0).toDouble(),
      exchangeRate: (json['exchange_rate'] as num?)?.toDouble(),
      brlAmount: (json['brl_amount'] as num? ?? 0.0).toDouble(),
      feesBrl: (json['fees_brl'] as num? ?? 0.0).toDouble(),
      notes: json['notes'],
      assetName: assetInfo?['name'],
      assetSymbol: assetInfo?['symbol'],
      assetCategory: assetInfo?['category'],
      assetAccount: assetInfo?['account'],
    );
  }

  Map<String, dynamic> toJson() => {
        'asset_id': assetId,
        'transaction_type': transactionType,
        'transaction_date':
            '${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}-${transactionDate.day.toString().padLeft(2, '0')}',
        'quantity': quantity,
        if (pricePerUnitOriginal != null) 'price_per_unit_original': pricePerUnitOriginal,
        'original_currency': originalCurrency,
        'original_amount': originalAmount,
        if (exchangeRate != null) 'exchange_rate': exchangeRate,
        'brl_amount': brlAmount,
        'fees_brl': feesBrl,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

// ── Category Summary ──────────────────────────────────────────────────────────

class CategorySummary {
  final String category;
  final double valueBrl;
  final double investedBrl;

  double get pnlBrl => valueBrl - investedBrl;
  double get pnlPct => investedBrl > 0 ? (pnlBrl / investedBrl * 100) : 0.0;

  CategorySummary({
    required this.category,
    required this.valueBrl,
    required this.investedBrl,
  });

  factory CategorySummary.fromJson(String category, Map<String, dynamic> json) {
    return CategorySummary(
      category: category,
      valueBrl: (json['value_brl'] as num? ?? 0.0).toDouble(),
      investedBrl: (json['invested_brl'] as num? ?? 0.0).toDouble(),
    );
  }
}

// ── Portfolio Summary ─────────────────────────────────────────────────────────

class PortfolioSummary {
  final double totalValueBrl;
  final double totalInvestedBrl;
  final double totalPnlBrl;
  final double totalPnlPct;
  final double exchangeRateUsdBrl;
  final Map<String, CategorySummary> byCategory;
  final List<InvestmentAsset> assets;

  PortfolioSummary({
    required this.totalValueBrl,
    required this.totalInvestedBrl,
    required this.totalPnlBrl,
    required this.totalPnlPct,
    required this.exchangeRateUsdBrl,
    required this.byCategory,
    required this.assets,
  });

  factory PortfolioSummary.fromJson(Map<String, dynamic> json) {
    final rawByCategory = json['by_category'] as Map<String, dynamic>? ?? {};
    final byCategory = rawByCategory.map(
      (k, v) => MapEntry(k, CategorySummary.fromJson(k, v as Map<String, dynamic>)),
    );
    return PortfolioSummary(
      totalValueBrl: (json['total_value_brl'] as num? ?? 0.0).toDouble(),
      totalInvestedBrl: (json['total_invested_brl'] as num? ?? 0.0).toDouble(),
      totalPnlBrl: (json['total_pnl_brl'] as num? ?? 0.0).toDouble(),
      totalPnlPct: (json['total_pnl_pct'] as num? ?? 0.0).toDouble(),
      exchangeRateUsdBrl: (json['exchange_rate_usd_brl'] as num? ?? 5.0).toDouble(),
      byCategory: byCategory,
      assets: (json['assets'] as List<dynamic>? ?? [])
          .map((e) => InvestmentAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

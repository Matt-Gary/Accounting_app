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
  final String? sector;
  final String? country;

  // Computed by backend from transaction history
  final double quantity;
  final double avgCostBrl;
  final double totalInvestedBrl;
  final double realizedGainsBrl;
  final double dividendsBrl;

  /// Net income booked in the trailing 12 months, and that income as a share
  /// of invested capital. Null yield means it does not apply (nothing
  /// invested), never 0%.
  final double dividends12mBrl;
  final double? yieldOnCostPct;

  final double? currentPrice;
  final double? dailyChangePct;
  final double currentValueBrl;
  final double unrealizedPnlBrl;
  final double unrealizedPnlPct;

  // Same figures in the asset's own currency, so average cost can be compared
  // against the Yahoo quote in matching units.
  final String nativeCurrency;
  final double avgCostOriginal;
  final double currentValueOriginal;
  final double totalInvestedOriginal;
  final double realizedGainsOriginal;
  final double dividendsOriginal;

  /// Share of the active broker portfolio (stocks + ETFs + broker cash).
  /// Null means no share applies — a reserve, or a position that could not be
  /// valued. It never means zero.
  final double? portfolioPct;
  final bool inAllocationBase;

  /// Sold down to zero but with transactions behind it. Still owns its realized
  /// gain and its history, so it stays reachable instead of disappearing.
  final bool isClosed;
  final int transactionCount;
  final DateTime? firstTransactionDate;
  final DateTime? lastTransactionDate;

  /// An asset created but never transacted against — distinct from a closed
  /// position, which has history worth keeping.
  bool get isEmpty => transactionCount == 0;

  /// Unrealized P&L in the asset's own currency — the FX component is excluded
  /// by construction, so this is the pure asset move.
  double get unrealizedPnlOriginal =>
      currentValueOriginal - totalInvestedOriginal;

  double get unrealizedPnlPctOriginal => totalInvestedOriginal == 0
      ? 0.0
      : unrealizedPnlOriginal / totalInvestedOriginal * 100;

  /// Categories that carry a ticker and are valued from a live quote.
  /// Mirrors PRICED_CATEGORIES in service/portfolio/categories.py.
  static const Set<String> pricedCategories = {
    'stock', 'etf', 'crypto', 'cash_equivalent'
  };
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
    this.sector,
    this.country,
    this.quantity = 0.0,
    this.avgCostBrl = 0.0,
    this.totalInvestedBrl = 0.0,
    this.realizedGainsBrl = 0.0,
    this.dividendsBrl = 0.0,
    this.dividends12mBrl = 0.0,
    this.yieldOnCostPct,
    this.currentPrice,
    this.dailyChangePct,
    this.currentValueBrl = 0.0,
    this.unrealizedPnlBrl = 0.0,
    this.unrealizedPnlPct = 0.0,
    this.nativeCurrency = 'BRL',
    this.avgCostOriginal = 0.0,
    this.currentValueOriginal = 0.0,
    this.totalInvestedOriginal = 0.0,
    this.realizedGainsOriginal = 0.0,
    this.dividendsOriginal = 0.0,
    this.portfolioPct,
    this.inAllocationBase = false,
    this.isClosed = false,
    this.transactionCount = 0,
    this.firstTransactionDate,
    this.lastTransactionDate,
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
      sector: json['sector'],
      country: json['country'],
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
      avgCostBrl: (json['avg_cost_brl'] as num? ?? 0.0).toDouble(),
      totalInvestedBrl: (json['total_invested_brl'] as num? ?? 0.0).toDouble(),
      realizedGainsBrl: (json['realized_gains_brl'] as num? ?? 0.0).toDouble(),
      dividendsBrl: (json['dividends_brl'] as num? ?? 0.0).toDouble(),
      dividends12mBrl:
          (json['dividends_12m_brl'] as num? ?? 0.0).toDouble(),
      yieldOnCostPct: (json['yield_on_cost_pct'] as num?)?.toDouble(),
      currentPrice: (json['current_price'] as num?)?.toDouble(),
      dailyChangePct: (json['daily_change_pct'] as num?)?.toDouble(),
      currentValueBrl: (json['current_value_brl'] as num? ?? 0.0).toDouble(),
      unrealizedPnlBrl: (json['unrealized_pnl_brl'] as num? ?? 0.0).toDouble(),
      unrealizedPnlPct: (json['unrealized_pnl_pct'] as num? ?? 0.0).toDouble(),
      nativeCurrency: json['native_currency'] ?? json['currency'] ?? 'BRL',
      avgCostOriginal: (json['avg_cost_original'] as num? ?? 0.0).toDouble(),
      totalInvestedOriginal:
          (json['total_invested_original'] as num? ?? 0.0).toDouble(),
      realizedGainsOriginal:
          (json['realized_gains_original'] as num? ?? 0.0).toDouble(),
      dividendsOriginal:
          (json['dividends_original'] as num? ?? 0.0).toDouble(),
      portfolioPct: (json['portfolio_pct'] as num?)?.toDouble(),
      inAllocationBase: json['in_allocation_base'] == true,
      isClosed: json['is_closed'] == true,
      transactionCount: (json['transaction_count'] as num? ?? 0).toInt(),
      firstTransactionDate: json['first_transaction_date'] == null
          ? null
          : DateTime.parse(json['first_transaction_date']),
      lastTransactionDate: json['last_transaction_date'] == null
          ? null
          : DateTime.parse(json['last_transaction_date']),
      currentValueOriginal:
          (json['current_value_original'] as num? ?? 0.0).toDouble(),
    );
  }

  /// Applies edited metadata onto this asset, keeping every backend-computed
  /// figure. The form only knows the editable fields, so replacing the object
  /// outright would blank the position until the next refresh.
  ///
  /// Note that changing category or currency also changes how the position is
  /// valued, so the carried-over figures are stale until the portfolio reloads.
  InvestmentAsset withMetadataFrom(InvestmentAsset edited) => InvestmentAsset(
        id: id,
        familyId: familyId,
        category: edited.category,
        name: edited.name,
        symbol: edited.symbol,
        currency: edited.currency,
        account: edited.account,
        sector: edited.sector,
        country: edited.country,
        notes: edited.notes,
        quantity: quantity,
        avgCostBrl: avgCostBrl,
        totalInvestedBrl: totalInvestedBrl,
        realizedGainsBrl: realizedGainsBrl,
        dividendsBrl: dividendsBrl,
        dividends12mBrl: dividends12mBrl,
        yieldOnCostPct: yieldOnCostPct,
        currentPrice: currentPrice,
        dailyChangePct: dailyChangePct,
        currentValueBrl: currentValueBrl,
        unrealizedPnlBrl: unrealizedPnlBrl,
        unrealizedPnlPct: unrealizedPnlPct,
        nativeCurrency: edited.currency,
        avgCostOriginal: avgCostOriginal,
        currentValueOriginal: currentValueOriginal,
        totalInvestedOriginal: totalInvestedOriginal,
        realizedGainsOriginal: realizedGainsOriginal,
        dividendsOriginal: dividendsOriginal,
        portfolioPct: portfolioPct,
        inAllocationBase: inAllocationBase,
        isClosed: isClosed,
        transactionCount: transactionCount,
        firstTransactionDate: firstTransactionDate,
        lastTransactionDate: lastTransactionDate,
      );

  /// Payload for create and update. Optional fields are always present so that
  /// clearing one on an edit actually clears it, rather than the key being
  /// omitted and the old value surviving.
  Map<String, dynamic> toAssetJson() => {
        'category': category,
        'name': name,
        'symbol': symbol,
        'currency': currency,
        'account': account,
        'notes': notes,
        'sector': sector,
        'country': country,
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
  // Fee as it was typed, in the transaction's currency. Needed to prefill the
  // edit form — feesBrl is the converted figure and would round-trip wrong.
  final double feesOriginal;
  final double withholdingTaxOriginal;
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
    this.feesOriginal = 0.0,
    this.withholdingTaxOriginal = 0.0,
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
      feesOriginal: (json['fees_original'] as num? ?? 0.0).toDouble(),
      withholdingTaxOriginal:
          (json['withholding_tax_original'] as num? ?? 0.0).toDouble(),
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
        // brl_amount is deliberately omitted — the backend derives the
        // authoritative figure from amount, fee and rate.
        'fees_original': feesOriginal,
        if (withholdingTaxOriginal != 0)
          'withholding_tax_original': withholdingTaxOriginal,
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

/// One of the two top-level sections on the investments screen:
/// 'exchange' (stocks, ETFs) or 'off_exchange' (crypto, bonds, cash).
class GroupSummary {
  final double valueBrl;
  final double investedBrl;
  final double pnlBrl;

  /// Null when nothing is invested in the group.
  final double? pnlPct;

  /// Share of the combined portfolio value. Null when any group holds an
  /// unpriced position — a share of a partial total would mislead.
  final double? shareOfTotalPct;

  /// False when a position in this group could not be valued, so the value
  /// above understates the truth.
  final bool complete;

  GroupSummary({
    this.valueBrl = 0.0,
    this.investedBrl = 0.0,
    this.pnlBrl = 0.0,
    this.pnlPct,
    this.shareOfTotalPct,
    this.complete = true,
  });

  factory GroupSummary.fromJson(Map<String, dynamic> json) => GroupSummary(
        valueBrl: (json['value_brl'] as num? ?? 0.0).toDouble(),
        investedBrl: (json['invested_brl'] as num? ?? 0.0).toDouble(),
        pnlBrl: (json['pnl_brl'] as num? ?? 0.0).toDouble(),
        pnlPct: (json['pnl_pct'] as num?)?.toDouble(),
        shareOfTotalPct: (json['share_of_total_pct'] as num?)?.toDouble(),
        complete: json['complete'] != false,
      );
}

class PortfolioSummary {
  final double totalValueBrl;
  final double totalInvestedBrl;
  final double totalPnlBrl;
  final double totalPnlPct;
  final double exchangeRateUsdBrl;
  final Map<String, CategorySummary> byCategory;
  final List<InvestmentAsset> assets;

  /// Denominator behind every [InvestmentAsset.portfolioPct]: the value of the
  /// active broker portfolio (stocks + ETFs + broker cash).
  final double allocationBaseBrl;

  /// False when a position that belongs in the base could not be valued, so
  /// the shares are computed over an incomplete total.
  final bool allocationComplete;

  /// Concentration section from the backend: the family's thresholds plus
  /// `position_breaches`, `sector_breaches`, `currency_breaches` and
  /// `country_breaches`. Kept as raw JSON — the banner is the only consumer.
  final Map<String, dynamic> concentration;

  /// True when any concentration threshold is exceeded.
  bool get hasConcentrationBreaches => const [
        'position_breaches',
        'sector_breaches',
        'currency_breaches',
        'country_breaches',
      ].any((k) => (concentration[k] as List?)?.isNotEmpty ?? false);

  /// The two top-level sections, keyed 'exchange' / 'off_exchange'.
  final Map<String, GroupSummary> byGroup;

  /// Portfolio-level dividend figures, all net of withholding.
  final double dividendsTotalNetBrl;
  final double dividends12mNetBrl;

  /// Trailing-12m income over invested capital; null when nothing invested.
  final double? portfolioYieldOnCostPct;

  /// Positions sold down to zero, most recently closed first. Their realized
  /// gain is what the tax report is built from, so they stay reachable.
  List<InvestmentAsset> get closedPositions {
    final closed = assets.where((a) => a.isClosed).toList();
    closed.sort((a, b) {
      final ad = a.lastTransactionDate;
      final bd = b.lastTransactionDate;
      if (ad == null || bd == null) return 0;
      return bd.compareTo(ad);
    });
    return closed;
  }

  /// Total realized across every closed position, for the section header.
  double get closedRealizedBrl => closedPositions.fold(
      0.0, (sum, a) => sum + a.realizedGainsBrl);

  /// Assets created but never transacted against. Listed so they can be used
  /// or deleted instead of lingering invisibly.
  List<InvestmentAsset> get emptyAssets =>
      assets.where((a) => a.isEmpty).toList();

  /// Positions that carry a share, largest first.
  List<InvestmentAsset> get allocationPositions {
    final held = assets
        .where((a) => a.portfolioPct != null && a.portfolioPct! > 0)
        .toList();
    held.sort((a, b) => b.portfolioPct!.compareTo(a.portfolioPct!));
    return held;
  }

  PortfolioSummary({
    required this.totalValueBrl,
    required this.totalInvestedBrl,
    required this.totalPnlBrl,
    required this.totalPnlPct,
    required this.exchangeRateUsdBrl,
    required this.byCategory,
    required this.assets,
    this.allocationBaseBrl = 0.0,
    this.allocationComplete = true,
    this.concentration = const {},
    this.byGroup = const {},
    this.dividendsTotalNetBrl = 0.0,
    this.dividends12mNetBrl = 0.0,
    this.portfolioYieldOnCostPct,
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
      allocationBaseBrl:
          (json['allocation_base_brl'] as num? ?? 0.0).toDouble(),
      allocationComplete: json['allocation_complete'] != false,
      concentration:
          json['concentration'] as Map<String, dynamic>? ?? const {},
      byGroup: (json['by_group'] as Map<String, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(
              k, GroupSummary.fromJson(v as Map<String, dynamic>))),
      dividendsTotalNetBrl:
          ((json['dividends'] as Map<String, dynamic>?)?['total_net_brl']
                  as num? ??
              0.0)
          .toDouble(),
      dividends12mNetBrl:
          ((json['dividends'] as Map<String, dynamic>?)?['last_12m_net_brl']
                  as num? ??
              0.0)
          .toDouble(),
      portfolioYieldOnCostPct: ((json['dividends']
              as Map<String, dynamic>?)?['portfolio_yield_on_cost_pct']
          as num?)
          ?.toDouble(),
      byCategory: byCategory,
      assets: (json['assets'] as List<dynamic>? ?? [])
          .map((e) => InvestmentAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

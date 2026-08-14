import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../utils/asset_display.dart';
import '../utils/money_format.dart';
import '../widgets/charts/allocation_bars.dart';
import '../widgets/charts/equity_curve.dart';
import '../widgets/charts/performance_chart.dart';
import 'add_transaction_screen.dart';
import 'asset_transactions_screen.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => InvestmentsScreenState();
}

class InvestmentsScreenState extends State<InvestmentsScreen> {
  final _backendService = BackendService();
  PortfolioSummary? _portfolio;
  bool _isLoading = false;
  String _errorMessage = '';

  /// Display currency for all aggregate values. The Avg → Now row on each
  /// asset card stays in the asset's native currency regardless, so the
  /// current price always matches the Yahoo quote for that ticker.
  String _displayCurrency = 'BRL';

  /// Closed positions are history, not the working view — collapsed by default.
  bool _showArchive = false;

  // Mirrors GROUPS in the backend's service/portfolio/categories.py: the
  // exchange section is stocks + ETFs, everything else sits off-exchange.
  // Categories inside each group keep the old display order.
  static const _groupOrder = ['exchange', 'off_exchange'];
  static const _groupCategories = {
    'exchange': ['stock', 'etf'],
    'off_exchange': [
      'crypto', 'bond', 'cash_equivalent',
      'cash_broker', 'cash_home', 'cash_bank',
    ],
  };
  static const _categoryIcons = {
    'stock': Icons.show_chart,
    'etf': Icons.donut_small,
    'crypto': Icons.currency_bitcoin,
    'bond': Icons.account_balance,
    'cash_equivalent': Icons.savings,
    'cash_broker': Icons.business_center,
    'cash_home': Icons.home,
    'cash_bank': Icons.account_balance_wallet,
  };

  String _categoryLabel(String cat) => 'investments.categories.$cat'.tr();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({bool refresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final portfolio = await _backendService.getPortfolio(refresh: refresh);
      setState(() => _portfolio = portfolio);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Formatting ─────────────────────────────────────────────────────────────

  double get _usdRate => _portfolio?.exchangeRateUsdBrl ?? 5.0;

  String get _locale => context.locale.toString();

  /// Formats a BRL value in the currently selected display currency.
  String _money(double brlValue) {
    final showUsd = _displayCurrency == 'USD';
    final v = showUsd && _usdRate > 0 ? brlValue / _usdRate : brlValue;
    return formatMoney(v, showUsd ? 'USD' : 'BRL', _locale);
  }

  /// Formats a value already expressed in [currency] — no conversion.
  String _native(double v, String currency) =>
      formatMoney(v, currency, _locale);

  /// Picks the exact figure for an asset instead of converting a historical
  /// BRL amount at today's rate. See `utils/asset_display.dart` — dividing a
  /// past cost by the current rate re-prices history and invents a gain.
  String _assetMoney(InvestmentAsset a, double brl, double native) {
    final picked = pickAmount(
      displayCurrency: _displayCurrency,
      nativeCurrency: a.nativeCurrency,
      brl: brl,
      native: native,
      usdBrlRate: _usdRate,
    );
    final text = formatMoney(picked.value, picked.currency, _locale);
    // '≈' marks a converted approximation (e.g. an EUR asset viewed in USD,
    // or a fallback when a rate is missing) so it cannot pass for exact.
    return picked.exact ? text : '≈ $text';
  }

  /// True when this asset's figures are exact in the selected currency.
  bool _nativeView(InvestmentAsset a) =>
      isNativeView(_displayCurrency, a.nativeCurrency);

  String _price(double v, String currency) =>
      formatPrice(v, currency, _locale);

  String _pct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  String _qty(double q) => formatQuantity(q, _locale);

  Color _pnlColor(double v) =>
      v >= 0 ? const Color(0xFF1F7A1F) : const Color(0xFFC00000);

  // ── Navigation ─────────────────────────────────────────────────────────────

  void openAddTransaction() => _openAddTransaction();

  void _openAddTransaction() async {
    final assets = await _backendService.getAssets();
    if (!mounted) return;
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(availableAssets: assets),
      ),
    );
    if (refreshed == true) _loadData();
  }

  void _openAsset(InvestmentAsset asset) async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AssetTransactionsScreen(asset: asset),
      ),
    );
    if (refreshed == true) _loadData();
  }

  Future<void> _showReportDialog() async {
    final currentYear = DateTime.now().year;
    final years = [currentYear, currentYear - 1, currentYear - 2, currentYear - 3];
    int? selectedYear = currentYear;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('investments.annual_report'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: years.map((y) => RadioListTile<int>(
              title: Text(y.toString()),
              value: y,
              groupValue: selectedYear,
              onChanged: (v) => setDialogState(() => selectedYear = v),
            )).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _backendService.downloadInvestmentReport(selectedYear!);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('common.error_with_message'
                              .tr(namedArgs: {'message': '$e'}))),
                    );
                  }
                }
              },
              child: Text('investments.download'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate

    return Scaffold(
      appBar: AppBar(
        title: Text('investments.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'investments.annual_report_tooltip'.tr(),
            onPressed: _showReportDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTransaction,
        tooltip: 'investments.add_transaction_tooltip'.tr(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _loadData,
                          child: Text('common.retry'.tr())),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _loadData(refresh: true),
                  child: _portfolio == null
                      ? Center(child: Text('investments.no_data'.tr()))
                      : _buildBody(),
                ),
    );
  }

  Widget _buildBody() {
    final groupSections =
        _groupOrder.expand((g) => _buildGroupSection(g)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCurrencyToggle(),
        const SizedBox(height: 12),
        _buildSummaryCard(),
        const SizedBox(height: 12),
        if (_portfolio!.hasConcentrationBreaches) ...[
          _buildConcentrationBanner(),
          const SizedBox(height: 12),
        ],
        EquityCurve(showUsd: _displayCurrency == 'USD'),
        const SizedBox(height: 12),
        const PerformanceChart(),
        const SizedBox(height: 12),
        AllocationBars(
          positions: _portfolio!.allocationPositions,
          complete: _portfolio!.allocationComplete,
          formatValue: _money,
        ),
        if (_portfolio!.dividendsTotalNetBrl > 0) ...[
          const SizedBox(height: 12),
          _buildDividendsCard(),
        ],
        const SizedBox(height: 16),
        if (groupSections.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Text(
              'investments.empty'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          )
        else
          ...groupSections,
        ..._buildArchiveSection(),
      ],
    );
  }

  /// One top-level section: a summary card ("Exchange" / "Off-exchange") with
  /// the group's value, P&L and share of the whole, followed by its category
  /// subsections. Groups with no open positions disappear entirely.
  List<Widget> _buildGroupSection(String group) {
    final sections = _groupCategories[group]!
        .expand((cat) => _buildCategorySection(cat))
        .toList();
    if (sections.isEmpty) return [];
    return [
      _buildGroupHeader(group),
      ...sections,
      const SizedBox(height: 8),
    ];
  }

  Widget _buildGroupHeader(String group) {
    final summary = _portfolio!.byGroup[group];
    final title = 'investments.groups.$group'.tr();
    if (summary == null) {
      // Backend older than the app: header only, no figures to show.
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
    }
    final pnl = summary.pnlBrl;
    return Card(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (summary.shareOfTotalPct != null)
                  Text(
                    'investments.groups.share'.tr(namedArgs: {
                      'pct': summary.shareOfTotalPct!.toStringAsFixed(0)
                    }),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_money(summary.valueBrl),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      '${'investments.summary.invested'.tr()} '
                      '${_money(summary.investedBrl)}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pnl >= 0 ? '+' : ''}${_money(pnl)}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _pnlColor(pnl)),
                    ),
                    if (summary.pnlPct != null)
                      Text(_pct(summary.pnlPct!),
                          style: TextStyle(
                              fontSize: 11, color: _pnlColor(pnl))),
                  ],
                ),
              ],
            ),
            if (!summary.complete)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'investments.groups.incomplete'.tr(),
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange.shade800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Portfolio-level dividend income, always net of withholding tax.
  Widget _buildDividendsCard() {
    final p = _portfolio!;
    Widget stat(String labelKey, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(labelKey.tr(),
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text('investments.dividends.title'.tr(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                stat('investments.dividends.last_12m',
                    _money(p.dividends12mNetBrl)),
                stat('investments.dividends.total',
                    _money(p.dividendsTotalNetBrl)),
                stat(
                    'investments.dividends.yield_on_cost',
                    p.portfolioYieldOnCostPct == null
                        ? '—'
                        : '${p.portfolioYieldOnCostPct!.toStringAsFixed(2)}%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Positions sold down to zero, plus assets never transacted against.
  /// Collapsed by default — this is history, not the working view — but always
  /// present, because a closed position still owns the realized gain that the
  /// tax report is built from.
  List<Widget> _buildArchiveSection() {
    final closed = _portfolio!.closedPositions;
    final empties = _portfolio!.emptyAssets;
    if (closed.isEmpty && empties.isEmpty) return [];

    final realized = _portfolio!.closedRealizedBrl;

    return [
      const SizedBox(height: 8),
      InkWell(
        onTap: () => setState(() => _showArchive = !_showArchive),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(_showArchive ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'investments.archive.title'.tr(
                    namedArgs: {'count': '${closed.length + empties.length}'}),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey),
              ),
              const Spacer(),
              if (closed.isNotEmpty)
                Text(
                  '${realized >= 0 ? '+' : ''}${_money(realized)}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _pnlColor(realized)),
                ),
            ],
          ),
        ),
      ),
      if (_showArchive) ...[
        ...closed.map(_buildClosedCard),
        ...empties.map(_buildEmptyCard),
      ],
      const SizedBox(height: 8),
    ];
  }

  Widget _buildClosedCard(InvestmentAsset asset) {
    // Realized gain is historical; it has an exact native figure and must not
    // be reconstructed from BRL at today's rate.
    final realized = _nativeView(asset)
        ? asset.realizedGainsOriginal
        : asset.realizedGainsBrl;
    final icon = _categoryIcons[asset.category] ?? Icons.folder;
    final from = asset.firstTransactionDate;
    final to = asset.lastTransactionDate;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.grey.shade200,
          child: Icon(icon, size: 17, color: Colors.grey.shade600),
        ),
        title: Text(
          asset.symbol ?? asset.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          [
            if (from != null && to != null)
              '${_shortDate(from)} → ${_shortDate(to)}',
            'investments.archive.transactions'
                .tr(namedArgs: {'count': '${asset.transactionCount}'}),
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${realized >= 0 ? '+' : ''}'
              '${_assetMoney(asset, asset.realizedGainsBrl, asset.realizedGainsOriginal)}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _pnlColor(realized)),
            ),
            Text('investments.position.realized_gains'.tr(),
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        onTap: () => _openAsset(asset),
      ),
    );
  }

  Widget _buildEmptyCard(InvestmentAsset asset) {
    final icon = _categoryIcons[asset.category] ?? Icons.folder;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.grey.shade200,
          child: Icon(icon, size: 17, color: Colors.grey.shade600),
        ),
        title: Text(asset.symbol ?? asset.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('investments.archive.no_transactions'.tr(),
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        onTap: () => _openAsset(asset),
      ),
    );
  }

  String _shortDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Widget _buildCurrencyToggle() {
    return Row(
      children: [
        _toggleBtn('BRL', 'R\$ BRL'),
        const SizedBox(width: 8),
        _toggleBtn('USD', '\$ USD'),
        const Spacer(),
        Text(
          'investments.rate'.tr(
              namedArgs: {'rate': _usdRate.toStringAsFixed(2)}),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _toggleBtn(String value, String label) {
    final selected = _displayCurrency == value;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _displayCurrency = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          border: Border.all(
              color: selected ? scheme.primary : Colors.grey.shade400),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? scheme.onPrimary : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final p = _portfolio!;
    final isProfit = p.totalPnlBrl >= 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('investments.total_portfolio'.tr(),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              _money(p.totalValueBrl),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                    '${'investments.invested_label'.tr()}: ${_money(p.totalInvestedBrl)}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isProfit
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${isProfit ? '+' : ''}${_money(p.totalPnlBrl)}  ${_pct(p.totalPnlPct)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _pnlColor(p.totalPnlBrl)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCategorySection(String category) {
    // Show anything still holding value or cost, not just anything with a share
    // count — a cash balance or an asset whose price is temporarily unavailable
    // must not silently disappear from the list.
    // Open positions only. Closed ones and never-used assets are listed in
    // their own section below — previously they matched none of the value
    // conditions here and became unreachable altogether.
    final assets = _portfolio!.assets
        .where((a) =>
            a.category == category && !a.isClosed && !a.isEmpty)
        .toList();
    if (assets.isEmpty) return [];

    final catSummary = _portfolio!.byCategory[category];
    final icon = _categoryIcons[category] ?? Icons.folder;

    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(_categoryLabel(category),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey)),
            const Spacer(),
            if (catSummary != null)
              Text(
                _money(catSummary.valueBrl),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey),
              ),
          ],
        ),
      ),
      ...assets.map((asset) => asset.hasMktPrice
          ? _buildPricedCard(asset)
          : _buildFixedCard(asset)),
      const SizedBox(height: 4),
    ];
  }

  /// Stock / crypto: shows the live Yahoo quote against the average purchase
  /// price, both in the asset's own currency so they are directly comparable.
  Widget _buildPricedCard(InvestmentAsset asset) {
    final cur = asset.nativeCurrency;
    // In the asset's own currency the P&L is the pure asset move; in BRL it
    // also carries the FX move. Both are exact — neither is the other divided
    // by today's rate.
    final native = _nativeView(asset);
    final pnl =
        native ? asset.unrealizedPnlOriginal : asset.unrealizedPnlBrl;
    final pnlPct =
        native ? asset.unrealizedPnlPctOriginal : asset.unrealizedPnlPct;
    final isProfit = pnl >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _openAsset(asset),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(_categoryIcons[asset.category] ?? Icons.folder,
                        size: 17,
                        color:
                            Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(asset.symbol ?? asset.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          'investments.qty_meta'.tr(namedArgs: {
                            'qty': _qty(asset.quantity),
                            'type': _categoryLabel(asset.category),
                          }),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  if (asset.dailyChangePct != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: asset.dailyChangePct! >= 0
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _pct(asset.dailyChangePct!),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _pnlColor(asset.dailyChangePct!)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Avg → Now → Value, all in the ticker's native currency.
              Row(
                children: [
                  Expanded(
                    child: _metric('investments.avg_label'.tr(),
                        _price(asset.avgCostOriginal, cur)),
                  ),
                  const Icon(Icons.arrow_right_alt,
                      size: 18, color: Colors.grey),
                  Expanded(
                    child: _metric('investments.now_label'.tr(),
                        _price(asset.currentPrice ?? 0, cur)),
                  ),
                  Expanded(
                    child: _metric('investments.value_label'.tr(),
                        _native(asset.currentValueOriginal, cur),
                        alignEnd: true),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('investments.pnl_label'.tr(),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Text(
                    '${isProfit ? '+' : ''}'
                    '${native ? _native(pnl, cur) : _money(pnl)}'
                    ' (${_pct(pnlPct)})',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _pnlColor(pnl)),
                  ),
                  const Spacer(),
                  _shareLabel(asset),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bonds and cash: no market quote, so no price comparison.
  /// Bonds and cash. A bank balance is not an investment, so it shows a
  /// balance rather than "invested" and a P&L — asking whether a deposit grew
  /// is the direct result of framing it that way.
  ///
  /// The FX line appears only when viewing foreign-currency cash in BRL, which
  /// is the one case where cost and value genuinely differ. In the asset's own
  /// currency they are the same number: dollars you deposited and still hold
  /// have not gained anything.
  Widget _buildFixedCard(InvestmentAsset asset) {
    final icon = _categoryIcons[asset.category] ?? Icons.folder;
    final showFxLine = !_nativeView(asset) &&
        asset.nativeCurrency != 'BRL' &&
        _displayCurrency == 'BRL';
    final fxMove = asset.currentValueBrl - asset.totalInvestedBrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon,
              size: 18,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(
          asset.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          [
            _categoryLabel(asset.category),
            if (asset.account != null) asset.account!,
            // Cost only means something when it differs from the value, i.e.
            // when viewing foreign-currency cash in BRL. In its own currency
            // cost and balance are the same number by definition.
            if (showFxLine)
              '${'investments.cash.cost'.tr()} ${_money(asset.totalInvestedBrl)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _assetMoney(
                  asset, asset.currentValueBrl, asset.currentValueOriginal),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (showFxLine)
              Text(
                '${fxMove >= 0 ? '+' : ''}${_money(fxMove)} '
                '${'investments.cash.fx_move'.tr()}',
                style: TextStyle(fontSize: 11, color: _pnlColor(fxMove)),
              )
            else if (asset.portfolioPct != null)
              // Broker cash counts toward the active portfolio, so it carries a
              // share; bank and physical cash are reserves and show nothing.
              Text(
                'investments.allocation.share'.tr(
                    namedArgs: {'pct': asset.portfolioPct!.toStringAsFixed(1)}),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              )
            else
              Text('investments.cash.balance'.tr(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
        onTap: () => _openAsset(asset),
      ),
    );
  }

  /// Informational (deliberately not alarming) notice that a position or a
  /// group exceeds the family's concentration thresholds. Collapsed by
  /// default; expands to list every breach against its limit.
  Widget _buildConcentrationBanner() {
    final c = _portfolio!.concentration;
    final settings = c['settings'] as Map<String, dynamic>? ?? const {};

    String pctOf(dynamic v) => (v as num).toStringAsFixed(1);

    final lines = <String>[];
    for (final b in (c['position_breaches'] as List? ?? const [])) {
      lines.add('investments.concentration.position_line'.tr(namedArgs: {
        'name': (b['symbol'] ?? b['name'] ?? '?').toString(),
        'pct': pctOf(b['portfolio_pct']),
        'limit': '${settings['max_position_pct'] ?? ''}',
      }));
    }
    void addGroupLines(String key, String labelKey, String limitKey) {
      for (final b in (c[key] as List? ?? const [])) {
        lines.add(labelKey.tr(namedArgs: {
          'name': (b['group'] ?? '?').toString(),
          'pct': pctOf(b['pct']),
          'limit': '${settings[limitKey] ?? ''}',
        }));
      }
    }

    addGroupLines('sector_breaches',
        'investments.concentration.sector_line', 'max_sector_pct');
    addGroupLines('currency_breaches',
        'investments.concentration.currency_line', 'max_currency_pct');
    addGroupLines('country_breaches',
        'investments.concentration.country_line', 'max_country_pct');

    return Card(
      color: Colors.amber.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.balance, color: Colors.amber.shade800),
          title: Text(
            'investments.concentration.title'
                .tr(namedArgs: {'count': '${lines.length}'}),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $line',
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.amber.shade900)),
                    ),
                  const SizedBox(height: 4),
                  Text('investments.concentration.hint'.tr(),
                      style: TextStyle(
                          fontSize: 11, color: Colors.amber.shade800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Share of the active broker portfolio. Reserves and unpriced positions
  /// carry no share, so they show the BRL equivalent instead of a misleading
  /// percentage.
  Widget _shareLabel(InvestmentAsset asset) {
    final pct = asset.portfolioPct;
    if (pct == null) {
      // _assetMoney already prefixes '≈' when the figure is approximate.
      return Text(
          _assetMoney(asset, asset.currentValueBrl, asset.currentValueOriginal),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.pie_chart_outline,
            size: 12, color: Colors.grey.shade500),
        const SizedBox(width: 3),
        Text(
          'investments.allocation.share'
              .tr(namedArgs: {'pct': pct.toStringAsFixed(1)}),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _metric(String label, String value, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value,
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void refresh() => _loadData();
}

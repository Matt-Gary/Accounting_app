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

  /// Display currency for every figure on the screen, whatever currency an
  /// asset is quoted in or a trade was paid in. Shared with the asset screen.
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

  /// Today's USD/BRL rate, or 0 when unavailable — `pickAmount` then shows
  /// BRL rather than converting at an invented rate (this used to be 5.0).
  double get _usdRate => _portfolio?.exchangeRateUsdBrl ?? 0;

  String get _locale => context.locale.toString();

  /// The representation of a figure to show — and to sign and colour by.
  /// Picks the backend's exact USD figure instead of converting a historical
  /// BRL amount at today's rate. See `utils/asset_display.dart` — dividing a
  /// past cost by the current rate re-prices history and invents a gain.
  DisplayAmount _pick(double brl, double? usd) => pickAmount(
        displayCurrency: _displayCurrency,
        brl: brl,
        usd: usd,
        usdBrlRate: _usdRate,
      );

  /// Formats a figure from its BRL and USD representations in the selected
  /// currency. [signed] prefixes '+' on non-negative values (P&L).
  String _money(double brl, double? usd, {bool signed = false}) =>
      _format(_pick(brl, usd), formatMoney, signed);

  String _format(DisplayAmount a,
      String Function(double, String, String) format, bool signed) {
    final text = format(a.value, a.currency, _locale);
    final withSign = signed && a.value >= 0 ? '+$text' : text;
    // '≈' marks a converted approximation (the backend lacked a trade-date
    // close for the USD figure) so it cannot pass for exact.
    return a.exact ? withSign : '≈ $withSign';
  }

  /// A percentage for the selected currency. The USD one differs from the BRL
  /// one by the FX move; without it, the BRL one matches the "≈" fallback.
  double? _pctFor(double? brlPct, double? usdPct) =>
      _displayCurrency == 'USD' && usdPct != null ? usdPct : brlPct;

  // ── Per-asset figures ──────────────────────────────────────────────────────
  // Totals follow the toggle (BRL/USD); one asset's own figures follow
  // `assetDisplayCurrency`, so an EUR position stays in euros in the foreign
  // view instead of being re-expressed in dollars.

  /// The currency [a]'s own figures are shown in right now.
  String _assetView(InvestmentAsset a) =>
      assetDisplayCurrency(_displayCurrency, a.nativeCurrency);

  /// True when [a] is shown in its own third currency (EUR, PLN).
  bool _inOwnCurrency(InvestmentAsset a) =>
      a.nativeAvailable &&
      _assetView(a) == a.nativeCurrency &&
      _assetView(a) != 'BRL' &&
      _assetView(a) != 'USD';

  DisplayAmount _pickAsset(
          InvestmentAsset a, double brl, double? usd, double native) =>
      pickAssetAmount(
        displayCurrency: _displayCurrency,
        nativeCurrency: a.nativeCurrency,
        brl: brl,
        usd: usd,
        native: native,
        nativeAvailable: a.nativeAvailable,
        usdBrlRate: _usdRate,
      );

  String _assetMoney(InvestmentAsset a, double brl, double? usd, double native,
          {bool signed = false}) =>
      _format(_pickAsset(a, brl, usd, native), formatMoney, signed);

  String _assetPrice(
          InvestmentAsset a, double brl, double? usd, double native) =>
      _format(_pickAsset(a, brl, usd, native), formatPrice, false);

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
        builder: (_) => AssetTransactionsScreen(
          asset: asset,
          // One toggle for the whole module: the asset screen opens in the
          // currency chosen here, and a flip there carries back.
          displayCurrency: _displayCurrency,
          usdBrlRate: _portfolio?.exchangeRateUsdBrl ?? 0,
          onDisplayCurrencyChanged: (c) {
            if (mounted) setState(() => _displayCurrency = c);
          },
        ),
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
        // Above everything else: a total that silently excludes a position
        // reads as the portfolio being worth less.
        if (_portfolio!.unavailableAssets.isNotEmpty) ...[
          _buildIncompleteBanner(),
          const SizedBox(height: 12),
        ],
        if (_portfolio!.hasConcentrationBreaches) ...[
          _buildConcentrationBanner(),
          const SizedBox(height: 12),
        ],
        EquityCurve(showUsd: _displayCurrency == 'USD'),
        const SizedBox(height: 12),
        PerformanceChart(showUsd: _displayCurrency == 'USD'),
        const SizedBox(height: 12),
        AllocationBars(
          positions: _portfolio!.allocationPositions,
          complete: _portfolio!.allocationComplete,
          // Market values are present-day figures, so today's rate is the
          // exact one for them (unlike a cost).
          formatValue: (brl) =>
              _money(brl, _usdRate > 0 ? brl / _usdRate : null),
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
    final pnl = _pick(summary.pnlBrl, summary.pnlUsd).value;
    final pnlPct = _pctFor(summary.pnlPct, summary.pnlPctUsd);
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
                    Text(_money(summary.valueBrl, summary.valueUsd),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(
                      '${'investments.summary.invested'.tr()} '
                      '${_money(summary.investedBrl, summary.investedUsd)}',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(summary.pnlBrl, summary.pnlUsd, signed: true),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _pnlColor(pnl)),
                    ),
                    if (pnlPct != null)
                      Text(_pct(pnlPct),
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

  /// Positions the totals leave out, each with the backend's reason. Without
  /// this, an unpriced position simply made the portfolio look smaller.
  Widget _buildIncompleteBanner() {
    final missing = _portfolio!.unavailableAssets;
    final color = Colors.orange.shade800;
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('investments.incomplete.title'.tr(),
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final m in missing)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '• ${m.name}'
                  '${m.reason != null ? ' — ${m.reason}' : ''}',
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// "—" for a figure of a position that could not be valued; its zero is a
  /// placeholder, not a value.
  String _orDash(InvestmentAsset a, String Function() figure) =>
      a.valueAvailable ? figure() : '—';

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
                    _money(p.dividends12mNetBrl, p.dividends12mNetUsd)),
                stat('investments.dividends.total',
                    _money(p.dividendsTotalNetBrl, p.dividendsTotalNetUsd)),
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

    final realizedBrl = _portfolio!.closedRealizedBrl;
    final realizedUsd = _portfolio!.closedRealizedUsd;
    final realized = _pick(realizedBrl, realizedUsd).value;

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
                  _money(realizedBrl, realizedUsd, signed: true),
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
    // Realized gain is historical; it has an exact USD figure and must not be
    // reconstructed from BRL at today's rate.
    final realized = _pickAsset(asset, asset.realizedGainsBrl,
            asset.realizedGainsUsd, asset.realizedGainsOriginal)
        .value;
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
              _assetMoney(asset, asset.realizedGainsBrl,
                  asset.realizedGainsUsd, asset.realizedGainsOriginal,
                  signed: true),
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
          'investments.rate'.tr(namedArgs: {
            'rate': _usdRate > 0 ? _usdRate.toStringAsFixed(2) : '—'
          }),
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
    final pnl = _pick(p.totalPnlBrl, p.totalPnlUsd).value;
    final isProfit = pnl >= 0;
    final pnlPct = _pctFor(p.totalPnlPct, p.totalPnlPctUsd) ?? 0.0;
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
              _money(p.totalValueBrl, p.totalValueUsd),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                    '${'investments.invested_label'.tr()}: '
                    '${_money(p.totalInvestedBrl, p.totalInvestedUsd)}',
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
                    '${_money(p.totalPnlBrl, p.totalPnlUsd, signed: true)}'
                    '  ${_pct(pnlPct)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _pnlColor(pnl)),
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
                _money(catSummary.valueBrl, catSummary.valueUsd),
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
  /// price, both in the selected display currency so they are directly
  /// comparable.
  Widget _buildPricedCard(InvestmentAsset asset) {
    // Each currency's P&L is its own exact figure: in USD it measures the
    // gain in dollars, in BRL in reais — neither is the other divided by
    // today's rate.
    final pnl = _pickAsset(asset, asset.unrealizedPnlBrl,
            asset.unrealizedPnlUsd, asset.unrealizedPnlOriginal)
        .value;
    final pnlPct = _inOwnCurrency(asset)
        ? asset.unrealizedPnlPctOriginal
        : _pctFor(asset.unrealizedPnlPct, asset.unrealizedPnlPctUsd) ?? 0.0;

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
                        // A fresh fetch failed and the last known quote is
                        // shown: it must say how old it is.
                        if (asset.priceStale && asset.priceAsOf != null)
                          Text(
                            'investments.price_stale'.tr(namedArgs: {
                              'time': DateFormat('dd.MM HH:mm', _locale)
                                  .format(asset.priceAsOf!),
                            }),
                            style: TextStyle(
                                fontSize: 11, color: Colors.orange.shade800),
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
              // Avg → Now → Value in the selected currency. The average is the
              // one accumulated at each purchase's own rate (exact in both
              // currencies), never today's average re-priced; the quote and the
              // value are present-day figures, so today's rate is right for them.
              Row(
                children: [
                  Expanded(
                    child: _metric('investments.avg_label'.tr(),
                        _assetPrice(asset, asset.avgCostBrl, asset.avgCostUsd,
                            asset.avgCostOriginal)),
                  ),
                  const Icon(Icons.arrow_right_alt,
                      size: 18, color: Colors.grey),
                  Expanded(
                    child: _metric(
                        'investments.now_label'.tr(),
                        // No converted quote means today's rate is missing — a
                        // dash, never a zero or a price under the wrong label.
                        // In its own currency the raw quote needs no rate.
                        asset.currentPrice == null ||
                                (asset.currentPriceBrl == null &&
                                    !_inOwnCurrency(asset))
                            ? '—'
                            : _assetPrice(asset, asset.currentPriceBrl ?? 0,
                                asset.currentPriceUsd, asset.currentPrice!)),
                  ),
                  Expanded(
                    child: _metric(
                        'investments.value_label'.tr(),
                        _orDash(
                            asset,
                            () => _assetMoney(asset, asset.currentValueBrl,
                                asset.currentValueUsd,
                                asset.currentValueOriginal)),
                        alignEnd: true),
                  ),
                ],
              ),
              if (!asset.valueAvailable && asset.unavailableReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(asset.unavailableReason!,
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange.shade800)),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('investments.pnl_label'.tr(),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Text(
                    _orDash(
                        asset,
                        () => '${_assetMoney(asset, asset.unrealizedPnlBrl, asset.unrealizedPnlUsd, asset.unrealizedPnlOriginal, signed: true)}'
                            ' (${_pct(pnlPct)})'),
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
  /// The FX line appears only when viewing a balance in a currency other than
  /// its own (USD cash in BRL, BRL cash in USD), which is the one case where
  /// cost and value genuinely differ. In the asset's own currency they are the
  /// same number: dollars you deposited and still hold have not gained
  /// anything.
  Widget _buildFixedCard(InvestmentAsset asset) {
    final icon = _categoryIcons[asset.category] ?? Icons.folder;
    final showFxLine = asset.nativeCurrency != _assetView(asset);
    final fxMoveBrl = asset.currentValueBrl - asset.totalInvestedBrl;
    final fxMoveUsd =
        asset.currentValueUsd == null || asset.totalInvestedUsd == null
            ? null
            : asset.currentValueUsd! - asset.totalInvestedUsd!;
    final fxMoveNative =
        asset.currentValueOriginal - asset.totalInvestedOriginal;
    final fxMove =
        _pickAsset(asset, fxMoveBrl, fxMoveUsd, fxMoveNative).value;

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
            // when viewing a balance in another currency. In its own currency
            // cost and balance are the same number by definition.
            if (showFxLine)
              '${'investments.cash.cost'.tr()} '
                  '${_assetMoney(asset, asset.totalInvestedBrl, asset.totalInvestedUsd, asset.totalInvestedOriginal)}',
          ].join(' · '),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _orDash(
                  asset,
                  () => _assetMoney(asset, asset.currentValueBrl,
                      asset.currentValueUsd, asset.currentValueOriginal)),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            if (showFxLine)
              Text(
                '${_assetMoney(asset, fxMoveBrl, fxMoveUsd, fxMoveNative, signed: true)} '
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
          _assetMoney(asset, asset.currentValueBrl, asset.currentValueUsd,
              asset.currentValueOriginal),
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

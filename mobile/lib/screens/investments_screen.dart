import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import 'add_investment_screen.dart';
import '../widgets/language_toggle.dart';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  final _backendService = BackendService();
  bool _isLoading = false;
  bool _isLoadingUser = true;
  PortfolioData? _portfolio;
  String _errorMessage = '';
  UserProfile? _currentUser;

  // Filters
  String _filterType = 'All';
  String _filterCurrency = 'All';
  String _filterAccount = 'All';
  String _chartCurrency = 'BRL'; // 'BRL' or 'USD'

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final familyData = await _backendService.getFamilyData();
      // Investments are per-person; skip the family-level virtual profile.
      final realProfiles =
          familyData.profiles.where((u) => !u.isVirtual).toList();
      if (realProfiles.isNotEmpty) {
        _currentUser = realProfiles.first;
      }
    } catch (e) {
      setState(() => _errorMessage = 'common.error_with_message'
          .tr(namedArgs: {'error': e.toString()}));
    } finally {
      setState(() => _isLoadingUser = false);
      if (_currentUser != null) _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final portfolio = await _backendService.getInvestments();
      setState(() => _portfolio = portfolio);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _backendService.deleteInvestmentById(id);
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text('common.error_with_message'
                  .tr(namedArgs: {'error': e.toString()}))));
    }
  }

  // --- Formatting helpers ---

  // Money with thousands separators, e.g. 4287.25 -> "4,287.25".
  String _money(double v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(2);
    final parts = s.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${neg ? '-' : ''}$buf.${parts[1]}';
  }

  String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  void _openEditor({Investment? inv}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddInvestmentScreen(
          currentUser: _currentUser,
          investmentToEdit: inv,
          existingInvestments: _portfolio?.investments ?? const [],
        ),
      ),
    );
    _loadData();
  }

  void _confirmDelete(Investment inv) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('investments.delete_title'.tr()),
              content: Text('investments.are_you_sure'.tr()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('common.cancel'.tr())),
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      if (inv.id != null) _delete(inv.id!);
                    },
                    child: Text('common.delete'.tr(),
                        style: const TextStyle(color: Colors.red))),
              ],
            ));
  }

  // --- Cards ---

  Widget _buildInvestmentCard(Investment inv) {
    final currency = inv.currency;
    final bool isPriced =
        inv.type.toLowerCase() == 'stock' || inv.type.toLowerCase() == 'crypto';
    final nativeValue = inv.currentValueNative ?? 0;
    final brlValue = inv.currentValueBrl ?? 0;
    final usdValue = inv.currentValueUsd ?? 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openEditor(inv: inv),
        onLongPress: () => _confirmDelete(inv),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: isPriced
              ? _pricedBody(inv, currency, nativeValue, brlValue)
              : _fixedBody(inv, currency, nativeValue, brlValue, usdValue),
        ),
      ),
    );
  }

  // Leading avatar shared by all holding cards, icon chosen by type.
  Widget _typeAvatar(String type) {
    final t = type.toLowerCase();
    IconData icon;
    switch (t) {
      case 'crypto':
        icon = Icons.currency_bitcoin;
        break;
      case 'cash':
        icon = Icons.account_balance_wallet_outlined;
        break;
      case 'bond':
        icon = Icons.savings_outlined;
        break;
      case 'stock':
        icon = Icons.show_chart;
        break;
      default:
        icon = Icons.pie_chart_outline;
    }
    return CircleAvatar(
      backgroundColor: Colors.grey.shade100,
      child: Icon(icon, color: Colors.grey.shade700, size: 20),
    );
  }

  // Stock / crypto: symbol, daily change, avg -> current price, value, P&L.
  Widget _pricedBody(
      Investment inv, String currency, double nativeValue, double brlValue) {
    final isProfit = (inv.pnl ?? 0) >= 0;
    // Prefer the backend-derived avg; fall back to cost basis / quantity so the
    // card still shows a purchase price even before the backend is updated.
    final avg = inv.avgPrice ??
        (inv.quantity > 0 ? inv.costBasis / inv.quantity : 0);
    final now = inv.currentPrice ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _typeAvatar(inv.type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(inv.symbol ?? inv.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    'investments.qty_meta'.tr(namedArgs: {
                      'qty': _qty(inv.quantity),
                      'type': inv.type.toUpperCase(),
                    }),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            _dailyBadge(inv.dailyChangePct),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _metric(
                    'investments.avg_label'.tr(), '$currency ${_money(avg)}')),
            _arrow(),
            Expanded(
                child: _metric(
                    'investments.now_label'.tr(), '$currency ${_money(now)}')),
            Expanded(
              child: _metric('investments.value_label'.tr(),
                  '$currency ${_money(nativeValue)}',
                  alignEnd: true),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('investments.pnl_label'.tr(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            Text(
              '${isProfit ? '+' : ''}${_money(inv.pnl ?? 0)} (${(inv.pnlPct ?? 0).toStringAsFixed(1)}%)',
              style: TextStyle(
                  color: isProfit ? Colors.green.shade700 : Colors.red.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
            const Spacer(),
            if (currency != 'BRL')
              Text('≈ R\$ ${_money(brlValue)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ],
    );
  }

  // Bond / cash / other: name + value + equivalents. No price/P&L.
  Widget _fixedBody(Investment inv, String currency, double nativeValue,
      double brlValue, double usdValue) {
    return Row(
      children: [
        _typeAvatar(inv.type),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(inv.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(inv.type.toUpperCase(),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$currency ${_money(nativeValue)}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 2),
            if (currency != 'USD')
              Text('USD ${_money(usdValue)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            if (currency != 'BRL')
              Text('R\$ ${_money(brlValue)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
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
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  Widget _arrow() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey.shade400),
      );

  Widget _dailyBadge(double? pct) {
    if (pct == null) return const SizedBox.shrink();
    final up = pct >= 0;
    final color = up ? Colors.green.shade700 : Colors.red.shade700;
    final bg = up ? Colors.green.shade50 : Colors.red.shade50;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: color, size: 16),
          Text('${up ? '+' : ''}${pct.toStringAsFixed(2)}%',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    if (_isLoadingUser || _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty && _currentUser == null) {
      return Center(
          child: Text('common.error_with_message'
              .tr(namedArgs: {'error': _errorMessage})));
    }

    // Filter Logic
    List<Investment>? filteredList = _portfolio?.investments;
    if (filteredList != null) {
      if (_filterType != 'All') {
        filteredList = filteredList
            .where((i) => i.type.toLowerCase() == _filterType.toLowerCase())
            .toList();
      }
      if (_filterCurrency != 'All') {
        filteredList =
            filteredList.where((i) => i.currency == _filterCurrency).toList();
      }
      if (_filterAccount != 'All') {
        filteredList = filteredList
            .where((i) => (i.account ?? '').trim() == _filterAccount)
            .toList();
      }
    }

    // Investing vs reserves totals, computed from the holdings themselves
    // (single source of truth) rather than backend aggregate fields.
    double investingBrl = 0, investingUsd = 0, reservesBrl = 0, reservesUsd = 0;
    for (final inv in (_portfolio?.investments ?? const <Investment>[])) {
      final b = inv.currentValueBrl ?? 0;
      final u = inv.currentValueUsd ?? 0;
      if (inv.investable) {
        investingBrl += b;
        investingUsd += u;
      } else {
        reservesBrl += b;
        reservesUsd += u;
      }
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('nav.investments'.tr(),
            style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          const LanguageToggle(),
          IconButton(
              icon: const Icon(Icons.refresh, color: Colors.black),
              onPressed: _loadData),
          IconButton(
              icon: const Icon(Icons.add, color: Colors.black),
              onPressed: () => _openEditor()),
        ],
      ),
      body: _errorMessage.isNotEmpty
          ? Center(
              child: Text('common.error_with_message'
                  .tr(namedArgs: {'error': _errorMessage})))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Investing Portfolio vs Reserves
                  Row(
                    children: [
                      Expanded(
                        child: _summaryCard(
                          'investments.investing_portfolio'.tr(),
                          investingBrl,
                          investingUsd,
                          Colors.black,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _summaryCard(
                          'investments.reserves'.tr(),
                          reservesBrl,
                          reservesUsd,
                          Colors.teal.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_portfolio != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            'investments.net_worth'.tr(namedArgs: {
                              'value': _money(investingBrl + reservesBrl)
                            }),
                            style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                                fontSize: 12)),
                        Text(
                            'investments.rate'.tr(namedArgs: {
                              'rate':
                                  _portfolio!.exchangeRate.toStringAsFixed(2)
                            }),
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),

                  const SizedBox(height: 20),

                  // Allocation Bars (investable positions only)
                  _buildAllocationBars(),

                  const SizedBox(height: 20),

                  // Filters
                  _buildFilters(),

                  const SizedBox(height: 10),

                  if (filteredList != null && filteredList.isNotEmpty)
                    ..._buildAccountGroups(filteredList)
                  else
                    Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text('investments.no_match'.tr()),
                    ),

                  const SizedBox(height: 20),
                  Text('investments.long_press_hint'.tr(),
                      style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(String title, double brl, double usd, Color bg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 5),
          Text('R\$ ${_money(brl)}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text('\$ ${_money(usd)}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  // Group holdings by account; each group has a header (name + badge + subtotal).
  List<Widget> _buildAccountGroups(List<Investment> items) {
    final Map<String, List<Investment>> groups = {};
    for (final inv in items) {
      final acc = (inv.account ?? '').trim();
      final key = acc.isEmpty ? '' : acc;
      groups.putIfAbsent(key, () => []).add(inv);
    }

    // Sort groups by BRL subtotal descending.
    final entries = groups.entries.toList()
      ..sort((a, b) {
        double sum(List<Investment> l) =>
            l.fold(0.0, (s, i) => s + (i.currentValueBrl ?? 0));
        return sum(b.value).compareTo(sum(a.value));
      });

    final widgets = <Widget>[];
    for (final e in entries) {
      final label = e.key.isEmpty
          ? 'investments.unassigned_account'.tr()
          : e.key;
      final subtotal =
          e.value.fold(0.0, (s, i) => s + (i.currentValueBrl ?? 0));
      final allInvestable = e.value.every((i) => i.investable);
      final allReserve = e.value.every((i) => !i.investable);

      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8, left: 2, right: 2),
        child: Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(width: 8),
            if (allInvestable)
              _groupBadge('investments.investable_badge'.tr(),
                  Colors.green.shade700, Colors.green.shade50)
            else if (allReserve)
              _groupBadge('investments.reserve_badge'.tr(),
                  Colors.orange.shade800, Colors.orange.shade50),
            const Spacer(),
            Text('R\$ ${_money(subtotal)}',
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ],
        ),
      ));
      widgets.addAll(e.value.map(_buildInvestmentCard));
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  Widget _groupBadge(String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }

  Widget _buildFilters() {
    // Distinct account labels currently in the portfolio.
    final accounts = <String>{};
    for (final inv in (_portfolio?.investments ?? const <Investment>[])) {
      final a = (inv.account ?? '').trim();
      if (a.isNotEmpty) accounts.add(a);
    }
    final accountOptions = ['All', ...accounts];
    // Guard against a stale selection (e.g. after deleting the last item of an account).
    final accountValue =
        accountOptions.contains(_filterAccount) ? _filterAccount : 'All';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text('investments.type_label'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: _filterType,
            items: ['All', 'Stock', 'Crypto', 'Bond', 'Cash', 'Other']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _filterType = v!),
            underline: Container(),
          ),
          const SizedBox(width: 16),
          Text('investments.currency_label'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: _filterCurrency,
            items: ['All', 'BRL', 'USD', 'EUR', 'PLN']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _filterCurrency = v!),
            underline: Container(),
          ),
          const SizedBox(width: 16),
          Text('investments.account_filter'.tr(),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: accountValue,
            items: accountOptions
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _filterAccount = v!),
            underline: Container(),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationBars() {
    final investable =
        (_portfolio?.investments ?? const <Investment>[])
            .where((i) => i.investable)
            .toList();

    if (_portfolio == null || investable.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Icon(Icons.bar_chart, color: Colors.grey.shade400, size: 32),
            const SizedBox(width: 12),
            Text('investments.no_investments'.tr(),
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    final bool useUsd = _chartCurrency == 'USD';
    final double total =
        useUsd ? _portfolio!.investingTotalUsd : _portfolio!.investingTotalBrl;

    final Map<String, Color> typeColors = {
      'crypto': Colors.orange.shade700,
      'bond': Colors.green.shade600,
      'cash': Colors.teal.shade600,
      'other': Colors.purple.shade600,
    };

    final List<Color> stockColors = [
      Colors.blue.shade700,
      Colors.indigo.shade600,
      Colors.pink.shade600,
      Colors.cyan.shade700,
      Colors.deepOrange.shade600,
      Colors.lightBlue.shade600,
      Colors.amber.shade700,
      Colors.deepPurple.shade600,
      Colors.lightGreen.shade700,
      Colors.brown.shade600,
      Colors.red.shade600,
      Colors.lime.shade700,
    ];

    final Map<String, double> typeAggregates = {};
    final Map<String, _StockBucket> stockBySymbol = {};

    for (final inv in investable) {
      final double val =
          useUsd ? (inv.currentValueUsd ?? 0) : (inv.currentValueBrl ?? 0);
      if (val <= 0) continue;

      if (inv.type.toLowerCase() == 'stock') {
        final key = (inv.symbol != null && inv.symbol!.isNotEmpty)
            ? inv.symbol!
            : inv.name;
        final existing = stockBySymbol[key];
        if (existing == null) {
          stockBySymbol[key] =
              _StockBucket(label: key, name: inv.name, value: val);
        } else {
          existing.value += val;
        }
      } else {
        final raw = inv.type.toLowerCase();
        typeAggregates[raw] = (typeAggregates[raw] ?? 0) + val;
      }
    }

    final List<_AllocRow> rows = [];
    typeAggregates.forEach((type, value) {
      rows.add(_AllocRow(
        label: type[0].toUpperCase() + type.substring(1),
        sublabel: '',
        value: value,
        color: typeColors[type] ?? Colors.grey,
      ));
    });

    final sortedStocks = stockBySymbol.values.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (int i = 0; i < sortedStocks.length; i++) {
      final s = sortedStocks[i];
      rows.add(_AllocRow(
        label: s.label,
        sublabel: s.name == s.label ? '' : s.name,
        value: s.value,
        color: stockColors[i % stockColors.length],
      ));
    }

    rows.sort((a, b) => b.value.compareTo(a.value));

    final String currencyPrefix = useUsd ? '\$' : 'R\$';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('investments.portfolio_allocation'.tr(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              Row(children: [
                _chartToggleBtn('BRL'),
                const SizedBox(width: 4),
                _chartToggleBtn('USD'),
              ]),
            ],
          ),
          const SizedBox(height: 4),
          Text('investments.portfolio_subtitle'.tr(),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 16),
          if (rows.isEmpty || total <= 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('investments.no_positions'.tr(),
                  style: TextStyle(color: Colors.grey.shade500)),
            )
          else
            ...rows.map((r) {
              final double pct = (r.value / total) * 100;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: r.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(r.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        if (r.sublabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              r.sublabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text('${pct.toStringAsFixed(1)}%',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Text(
                        '$currencyPrefix ${_money(r.value)}',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (ctx, c) {
                        final double clampedPct = (pct / 100).clamp(0.0, 1.0);
                        return Stack(
                          children: [
                            Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Container(
                              height: 4,
                              width: c.maxWidth * clampedPct,
                              decoration: BoxDecoration(
                                color: r.color,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _chartToggleBtn(String cur) {
    bool isSelected = _chartCurrency == cur;
    return GestureDetector(
      onTap: () => setState(() => _chartCurrency = cur),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.black : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(cur,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _AllocRow {
  final String label;
  final String sublabel;
  final double value;
  final Color color;
  _AllocRow({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.color,
  });
}

class _StockBucket {
  final String label;
  final String name;
  double value;
  _StockBucket({
    required this.label,
    required this.name,
    required this.value,
  });
}

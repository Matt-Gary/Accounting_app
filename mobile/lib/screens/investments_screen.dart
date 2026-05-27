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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(
              content: Text('common.error_with_message'
                  .tr(namedArgs: {'error': e.toString()}))));
    }
  }

  Widget _buildInvestmentCard(Investment inv) {
    final currency = inv.currency;
    final isProfit = (inv.pnl ?? 0) >= 0;

    final nativeValue = inv.currentValueNative ?? 0;
    final usdValue = inv.currentValueUsd ?? 0;
    final brlValue = inv.currentValueBrl ?? 0;

    // Determine colors
    Color iconColor;
    Color iconBgColor;
    if (currency == 'USD') {
      iconColor = Colors.blue;
      iconBgColor = Colors.blue[50]!;
    } else if (currency == 'EUR') {
      iconColor = Colors.indigo;
      iconBgColor = Colors.indigo[50]!;
    } else if (currency == 'PLN') {
      iconColor = Colors.red;
      iconBgColor = Colors.red[50]!;
    } else {
      iconColor = Colors.green;
      iconBgColor = Colors.green[50]!;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddInvestmentScreen(
                    currentUser: _currentUser, investmentToEdit: inv),
              ));
          _loadData();
        },
        onLongPress: () {
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
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Icon
              CircleAvatar(
                backgroundColor: iconBgColor,
                child: Text(currency.substring(0, 1),
                    style: TextStyle(
                        color: iconColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              // Name and Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                        "${inv.quantity} ${inv.symbol ?? ''} • ${inv.type.toUpperCase()}",
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              // Values
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "$currency ${nativeValue.toStringAsFixed(2)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  // Always show USD and BRL equivalents (unless it IS that currency, maybe redundant but explicit is strictly requested)
                  if (currency != 'USD')
                    Text("USD ${usdValue.toStringAsFixed(2)}",
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (currency != 'BRL')
                    Text("BRL ${brlValue.toStringAsFixed(2)}",
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),

                  if (inv.pnl != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        "${isProfit ? '+' : ''}${inv.pnl!.toStringAsFixed(2)} (${inv.pnlPct!.toStringAsFixed(1)}%)",
                        style: TextStyle(
                          color: isProfit ? Colors.green : Colors.red,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
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
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          AddInvestmentScreen(currentUser: _currentUser)),
                );
                _loadData();
              }),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text('common.error_with_message'
                      .tr(namedArgs: {'error': _errorMessage})))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Total Value Cards
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('investments.total_brl'.tr(),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 5),
                                  Text(
                                    'R\$ ${(_portfolio?.totalValueBrl ?? 0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue[900],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('investments.total_usd'.tr(),
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12)),
                                  const SizedBox(height: 5),
                                  Text(
                                    '\$ ${(_portfolio?.totalValueUsd ?? 0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_portfolio != null)
                        Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                'investments.rate'.tr(namedArgs: {
                                  'rate': _portfolio!.exchangeRate
                                      .toStringAsFixed(2)
                                }),
                                style: const TextStyle(color: Colors.grey))),

                      const SizedBox(height: 20),

                      // Allocation Bars Section
                      _buildAllocationBars(),

                      const SizedBox(height: 20),

                      // Filters
                      _buildFilters(),

                      const SizedBox(height: 10),

                      if (filteredList != null && filteredList.isNotEmpty)
                        ...filteredList.map(_buildInvestmentCard)
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

  // State variables for filters and chart
  String _filterType = 'All';
  String _filterCurrency = 'All';
  String _chartCurrency = 'BRL'; // 'BRL' or 'USD'

  Widget _buildFilters() {
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
        ],
      ),
    );
  }

  Widget _buildAllocationBars() {
    if (_portfolio == null || _portfolio!.investments.isEmpty) {
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
        useUsd ? _portfolio!.totalValueUsd : _portfolio!.totalValueBrl;

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

    for (final inv in _portfolio!.investments) {
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
        // Merge cash + bond into a single bucket per the design.
        final raw = inv.type.toLowerCase();
        final key = (raw == 'cash' || raw == 'bond') ? 'bond+cash' : raw;
        typeAggregates[key] = (typeAggregates[key] ?? 0) + val;
      }
    }

    const Map<String, String> typeLabels = {
      'bond+cash': 'Bond+Cash',
      'crypto': 'Crypto',
      'other': 'Other',
    };
    final Color bondCashColor = Colors.teal.shade600;

    final List<_AllocRow> rows = [];
    typeAggregates.forEach((type, value) {
      rows.add(_AllocRow(
        label: typeLabels[type] ?? (type[0].toUpperCase() + type.substring(1)),
        sublabel: '',
        value: value,
        color: type == 'bond+cash'
            ? bondCashColor
            : (typeColors[type] ?? Colors.grey),
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
                        '$currencyPrefix ${r.value.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (ctx, c) {
                        final double clampedPct =
                            (pct / 100).clamp(0.0, 1.0);
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

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../repositories/accounting_repository.dart';
import 'add_investment_screen.dart';

class InvestmentsScreen extends StatefulWidget {
  final UserProfile? currentUser;
  const InvestmentsScreen({Key? key, required this.currentUser})
      : super(key: key);

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  final _backendService = BackendService();
  final _repository = AccountingRepository();
  bool _isLoading = false;
  PortfolioData? _portfolio;
  PortfolioDistribution? _distribution;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.currentUser != null) {
      _loadData();
    }
  }

  @override
  void didUpdateWidget(covariant InvestmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUser != widget.currentUser) {
      _loadData(); // Reload if user changes (though usually handled by parent rebuild)
    }
  }

  Future<void> _loadData() async {
    if (widget.currentUser == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await _backendService.getInvestments(widget.currentUser!.id);
      setState(() => _portfolio = data);
      _loadDistribution();
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDistribution() async {
    if (widget.currentUser == null) return;

    try {
      // Only apply chart type filter if not 'All'
      List<String>? typesFilter;
      if (_chartTypeFilter != 'All') {
        typesFilter = [_chartTypeFilter.toLowerCase()];
      }

      final dist = await _backendService.getPortfolioDistribution(
        widget.currentUser!.id,
        investmentTypes: typesFilter,
      );
      setState(() => _distribution = dist);
    } catch (e) {
      print('Error loading distribution: $e');
    }
  }

  Future<void> _delete(String id) async {
    try {
      await _repository.deleteInvestment(id);
      _loadData();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
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
                    currentUser: widget.currentUser, investmentToEdit: inv),
              ));
          _loadData();
        },
        onLongPress: () {
          showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                    title: const Text("Delete Investment"),
                    content: const Text("Are you sure?"),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("Cancel")),
                      TextButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            if (inv.id != null) _delete(inv.id!);
                          },
                          child: const Text("Delete",
                              style: TextStyle(color: Colors.red))),
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
    if (widget.currentUser == null) {
      return const Center(
          child: Text("Please select a user in the Dashboard first."));
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
        title: const Text('Investments', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
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
                          AddInvestmentScreen(currentUser: widget.currentUser)),
                );
                _loadData();
              }),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text('Error: $_errorMessage'))
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
                                  const Text('Total BRL',
                                      style: TextStyle(
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
                                  const Text('Total USD',
                                      style: TextStyle(
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
                                "Rate: 1 USD = ${(_portfolio!.exchangeRate).toStringAsFixed(2)} BRL",
                                style: const TextStyle(color: Colors.grey))),

                      const SizedBox(height: 20),

                      // Pie Chart Section
                      if (_distribution != null &&
                          _distribution!.distribution.isNotEmpty)
                        _buildPieChart(),

                      const SizedBox(height: 20),

                      // Filters
                      _buildFilters(),

                      const SizedBox(height: 10),

                      if (filteredList != null && filteredList.isNotEmpty)
                        ...filteredList.map(_buildInvestmentCard).toList()
                      else
                        const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text("No investments found matching filters."),
                        ),

                      const SizedBox(height: 20),
                      const Text("Long press to delete, tap to edit.",
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
    );
  }

  // State variables for filters and chart
  String _filterType = 'All';
  String _filterCurrency = 'All';
  String _chartCurrency = 'BRL'; // 'BRL' or 'USD'
  String _chartTypeFilter = 'All'; // Filter for pie chart by type

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text("Type: ", style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButton<String>(
            value: _filterType,
            items: ['All', 'Stock', 'Crypto', 'Bond', 'Cash', 'Other']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() => _filterType = v!),
            underline: Container(),
          ),
          const SizedBox(width: 16),
          const Text("Currency: ",
              style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _buildPieChart() {
    if (_distribution == null) return const SizedBox.shrink();

    double totalVal = _chartCurrency == 'BRL'
        ? _distribution!.totalValueBrl
        : _distribution!.totalValueUsd;

    List<PieChartSectionData> sections = [];
    bool showingIndividual =
        _distribution!.items != null && _distribution!.items!.isNotEmpty;
    bool isEmpty = totalVal == 0 ||
        (_distribution!.distribution.isEmpty && !showingIndividual);

    final Map<String, Color> typeColors = {
      'stock': Colors.blue,
      'crypto': Colors.orange,
      'bond': Colors.green,
      'cash': Colors.teal,
      'other': Colors.purple,
    };

    // More diverse color scheme for individual investments
    final List<Color> individualColors = [
      Colors.blue.shade700,
      Colors.green.shade600,
      Colors.orange.shade700,
      Colors.purple.shade600,
      Colors.teal.shade700,
      Colors.indigo.shade700,
      Colors.pink.shade600,
      Colors.lime.shade700,
      Colors.cyan.shade700,
      Colors.deepOrange.shade600,
      Colors.lightBlue.shade600,
      Colors.amber.shade700,
      Colors.deepPurple.shade600,
      Colors.lightGreen.shade700,
      Colors.brown.shade600,
    ];

    if (showingIndividual && !isEmpty) {
      // Show individual investments
      int colorIndex = 0;
      for (var item in _distribution!.items!) {
        double val = _chartCurrency == 'BRL' ? item.valueBrl : item.valueUsd;

        if (val <= 0) continue;

        final color = individualColors[colorIndex % individualColors.length];
        final pct = item.percentage;

        sections.add(PieChartSectionData(
          color: color,
          value: val,
          title: '${pct.toStringAsFixed(1)}%',
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ));
        colorIndex++;
      }
    } else if (!isEmpty) {
      // Show aggregated by type
      for (var typeData in _distribution!.distribution) {
        double val =
            _chartCurrency == 'BRL' ? typeData.valueBrl : typeData.valueUsd;

        if (val <= 0) continue;

        final color = typeColors[typeData.type.toLowerCase()] ?? Colors.grey;
        final pct = typeData.percentage;

        sections.add(PieChartSectionData(
          color: color,
          value: val,
          title: '${pct.toStringAsFixed(1)}%',
          radius: 60,
          titleStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ));
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                showingIndividual
                    ? "Individual ${_chartTypeFilter} Holdings"
                    : "Portfolio Distribution by Type",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              // Currency Toggle
              Row(children: [
                _chartToggleBtn('BRL'),
                const SizedBox(width: 4),
                _chartToggleBtn('USD'),
              ])
            ],
          ),
          const SizedBox(height: 12),
          // Type filter for pie chart
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text("Filter: ",
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                ...['All', 'Stock', 'Crypto', 'Bond', 'Cash', 'Other']
                    .map((type) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _chartTypeFilterBtn(type),
                        ))
                    .toList(),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pie_chart_outline,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          _chartTypeFilter == 'All'
                              ? 'No investments'
                              : 'No ${_chartTypeFilter.toLowerCase()} investments',
                          style: TextStyle(
                              color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                    ),
                  ),
          ),
          if (!isEmpty) const SizedBox(height: 12),
          // Legend (only show if not empty)
          if (!isEmpty)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: showingIndividual
                  ? _distribution!.items!.asMap().entries.map((entry) {
                      int idx = entry.key;
                      var item = entry.value;
                      final color =
                          individualColors[idx % individualColors.length];
                      final val = _chartCurrency == 'BRL'
                          ? item.valueBrl
                          : item.valueUsd;
                      final symbol = _chartCurrency == 'BRL' ? 'R\$' : '\$';
                      final displayName = item.symbol ?? item.name;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$displayName: $symbol ${val.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      );
                    }).toList()
                  : _distribution!.distribution.map((typeData) {
                      final color = typeColors[typeData.type.toLowerCase()] ??
                          Colors.grey;
                      final val = _chartCurrency == 'BRL'
                          ? typeData.valueBrl
                          : typeData.valueUsd;
                      final symbol = _chartCurrency == 'BRL' ? 'R\$' : '\$';
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${typeData.type.toUpperCase()}: $symbol ${val.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      );
                    }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _chartTypeFilterBtn(String type) {
    bool isSelected = _chartTypeFilter == type;
    return GestureDetector(
      onTap: () {
        setState(() => _chartTypeFilter = type);
        _loadDistribution();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          type,
          style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w600),
        ),
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

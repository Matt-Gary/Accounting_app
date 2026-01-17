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
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
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
                      if (_portfolio != null &&
                          _portfolio!.investments.isNotEmpty)
                        _buildPieChart(_portfolio!.investments),

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

  Widget _buildPieChart(List<Investment> investments) {
    // Group by Name or Symbol for the chart to avoid clutter if many lots of same
    // For simplicity, let's just map each investment. If too many, might need grouping.

    double totalVal = 0.0;
    // Calculate total based on selected chart currency
    if (_chartCurrency == 'BRL') {
      totalVal = _portfolio?.totalValueBrl ?? 0;
    } else {
      totalVal = _portfolio?.totalValueUsd ?? 0;
    }

    if (totalVal == 0) return const SizedBox.shrink();

    List<PieChartSectionData> sections = [];
    final List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.amber
    ];

    int i = 0;
    // We want to show distribution of the WHOLE portfolio, not just filtered.
    // Or normally, charts show what's filtered. Let's show ALL for overview,
    // or arguably filtered. Let's stick to ALL investments for the portfolio chart.

    // Sort by value desc to make chart pretty
    List<Investment> sortedCalls = List.from(investments);
    sortedCalls.sort((a, b) {
      double valA = _chartCurrency == 'BRL'
          ? (a.currentValueBrl ?? 0)
          : (a.currentValueUsd ?? 0);
      double valB = _chartCurrency == 'BRL'
          ? (b.currentValueBrl ?? 0)
          : (b.currentValueUsd ?? 0);
      return valB.compareTo(valA);
    });

    for (var inv in sortedCalls) {
      double val = _chartCurrency == 'BRL'
          ? (inv.currentValueBrl ?? 0)
          : (inv.currentValueUsd ?? 0);
      if (val <= 0) continue;

      final color = colors[i % colors.length];
      final pct = (val / totalVal) * 100;

      if (pct < 1) continue; // Skip very small slices

      sections.add(PieChartSectionData(
        color: color,
        value: val,
        title: '${pct.toStringAsFixed(1)}%',
        radius: 50,
        titleStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
        badgeWidget:
            Text(inv.symbol ?? inv.name, style: const TextStyle(fontSize: 10)),
        badgePositionPercentageOffset: 1.4,
      ));
      i++;
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
              const Text("Portfolio Distribution",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              // Toggle
              Row(children: [
                _chartToggleBtn('BRL'),
                const SizedBox(width: 4),
                _chartToggleBtn('USD'),
              ])
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: sections.isEmpty
                ? const Center(child: Text("No data"))
                : PieChart(
                    PieChartData(
                      sections: sections,
                      centerSpaceRadius: 40,
                      sectionsSpace: 2,
                    ),
                  ),
          ),
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

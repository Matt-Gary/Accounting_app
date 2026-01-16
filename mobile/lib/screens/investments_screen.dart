import 'package:flutter/material.dart';
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

    // Display value in Native currency AND the OTHER currency.
    // If Native is BRL, show BRL (large) and USD (small)
    // If Native is USD, show USD (large) and BRL (small)

    final nativeValue = inv.currentValueNative ?? 0;
    final usdValue = inv.currentValueUsd ?? 0;
    final brlValue = inv.currentValueBrl ?? 0;

    String mainText = "$currency ${nativeValue.toStringAsFixed(2)}";
    String subText = currency == 'BRL'
        ? "USD ${usdValue.toStringAsFixed(2)}"
        : "BRL ${brlValue.toStringAsFixed(2)}";

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              currency == 'USD' ? Colors.blue[50] : Colors.green[50],
          child: Text(currency.substring(0, 1),
              style: TextStyle(
                  color: currency == 'USD' ? Colors.blue : Colors.green,
                  fontWeight: FontWeight.bold)),
        ),
        title:
            Text(inv.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            "${inv.quantity} ${inv.symbol ?? ''} • ${inv.type.toUpperCase()}"),
        trailing: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(mainText,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(subText,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            if (inv.pnl != null)
              Text(
                "${isProfit ? '+' : ''}${inv.pnl!.toStringAsFixed(2)} (${inv.pnlPct!.toStringAsFixed(1)}%)",
                style: TextStyle(
                  color: isProfit ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
          ],
        ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentUser == null) {
      return const Center(
          child: Text("Please select a user in the Dashboard first."));
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
                      // Total Value Cards (Two separate charts/cards)
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
                                color:
                                    Colors.blue[900], // Distinct color for USD
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
                      if (_portfolio != null)
                        ..._portfolio!.investments
                            .map(_buildInvestmentCard)
                            .toList()
                      else
                        const Text("No investments found."),

                      const SizedBox(height: 20),
                      const Text("Long press to delete, tap to edit.",
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
    );
  }
}

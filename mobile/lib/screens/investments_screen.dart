import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
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

  static const _categoryOrder = [
    'stock', 'crypto', 'bond', 'cash_broker', 'cash_home', 'cash_bank'
  ];
  static const _categoryLabels = {
    'stock': 'Ações',
    'crypto': 'Cripto',
    'bond': 'Renda Fixa',
    'cash_broker': 'Caixa Corretora',
    'cash_home': 'Dinheiro Físico',
    'cash_bank': 'Conta Bancária',
  };
  static const _categoryIcons = {
    'stock': Icons.show_chart,
    'crypto': Icons.currency_bitcoin,
    'bond': Icons.account_balance,
    'cash_broker': Icons.business_center,
    'cash_home': Icons.home,
    'cash_bank': Icons.account_balance_wallet,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final portfolio = await _backendService.getPortfolio();
      setState(() => _portfolio = portfolio);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _money(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1000000) return '${sign}R\$ ${(abs / 1000000).toStringAsFixed(2)}M';
    if (abs >= 1000) return '${sign}R\$ ${(abs / 1000).toStringAsFixed(1)}K';
    return '${sign}R\$ ${abs.toStringAsFixed(2)}';
  }

  String _pct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  Color _pnlColor(double v) =>
      v >= 0 ? const Color(0xFF1F7A1F) : const Color(0xFFC00000);

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
          title: const Text('Relatório Anual'),
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
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await _backendService.downloadInvestmentReport(selectedYear!);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erro: $e')),
                    );
                  }
                }
              },
              child: const Text('Baixar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfólio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Relatório anual',
            onPressed: _showReportDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTransaction,
        tooltip: 'Adicionar transação',
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
                          onPressed: _loadData, child: const Text('Tentar novamente')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: _portfolio == null
                      ? const Center(child: Text('Nenhum dado'))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            _buildSummaryCard(),
                            const SizedBox(height: 16),
                            ..._categoryOrder.expand((cat) => _buildCategorySection(cat)),
                          ],
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
            const Text('Portfólio Total',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text(
              _money(p.totalValueBrl),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Investido: ${_money(p.totalInvestedBrl)}',
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
    final assets = _portfolio!.assets
        .where((a) => a.category == category && a.quantity > 0)
        .toList();
    if (assets.isEmpty) return [];

    final catSummary = _portfolio!.byCategory[category];
    final label = _categoryLabels[category] ?? category;
    final icon = _categoryIcons[category] ?? Icons.folder;

    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Text(label,
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
      ...assets.map((asset) => _buildAssetCard(asset)),
      const SizedBox(height: 4),
    ];
  }

  Widget _buildAssetCard(InvestmentAsset asset) {
    final isProfit = asset.unrealizedPnlBrl >= 0;
    final icon = _categoryIcons[asset.category] ?? Icons.folder;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, size: 18,
              color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        title: Text(
          asset.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asset.symbol != null)
              Text(asset.symbol!,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text(
              'Investido: ${_money(asset.totalInvestedBrl)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (asset.hasMktPrice && asset.dailyChangePct != null)
              Text(
                'Hoje: ${_pct(asset.dailyChangePct!)}',
                style: TextStyle(
                    fontSize: 11, color: _pnlColor(asset.dailyChangePct!)),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money(asset.currentValueBrl),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              '${isProfit ? '+' : ''}${_money(asset.unrealizedPnlBrl)} (${_pct(asset.unrealizedPnlPct)})',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _pnlColor(asset.unrealizedPnlBrl)),
            ),
          ],
        ),
        onTap: () => _openAsset(asset),
        isThreeLine: true,
      ),
    );
  }

  void refresh() => _loadData();
}

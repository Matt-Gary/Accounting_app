import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import 'add_transaction_screen.dart';

class AssetTransactionsScreen extends StatefulWidget {
  final InvestmentAsset asset;

  const AssetTransactionsScreen({super.key, required this.asset});

  @override
  State<AssetTransactionsScreen> createState() =>
      _AssetTransactionsScreenState();
}

class _AssetTransactionsScreenState extends State<AssetTransactionsScreen> {
  final _backendService = BackendService();
  List<InvestmentTransaction> _transactions = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _didModify = false;

  static const _txTypeLabels = {
    'buy': 'Compra',
    'sell': 'Venda',
    'dividend': 'Dividendo',
    'deposit': 'Depósito',
    'withdrawal': 'Retirada',
  };
  static const _txTypeColors = {
    'buy': Color(0xFF1F7A1F),
    'sell': Color(0xFFC00000),
    'dividend': Color(0xFF1565C0),
    'deposit': Color(0xFF1F7A1F),
    'withdrawal': Color(0xFFC00000),
  };
  static const _categoryLabels = {
    'stock': 'Ações',
    'crypto': 'Cripto',
    'bond': 'Renda Fixa',
    'cash_broker': 'Caixa Corretora',
    'cash_home': 'Dinheiro Físico',
    'cash_bank': 'Conta Bancária',
  };

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final txns = await _backendService.getTransactions(
          assetId: widget.asset.id);
      setState(() => _transactions = txns);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _money(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    return '${sign}R\$ ${abs.toStringAsFixed(2)}';
  }

  Color _pnlColor(double v) =>
      v >= 0 ? const Color(0xFF1F7A1F) : const Color(0xFFC00000);

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _openAddTransaction() async {
    final assets = await _backendService.getAssets();
    if (!mounted) return;
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          availableAssets: assets,
          preselectedAsset: assets.firstWhere(
            (a) => a.id == widget.asset.id,
            orElse: () => widget.asset,
          ),
        ),
      ),
    );
    if (refreshed == true) {
      _didModify = true;
      _loadTransactions();
    }
  }

  Future<void> _deleteTransaction(InvestmentTransaction tx) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir transação?'),
        content: Text(
          '${_txTypeLabels[tx.transactionType] ?? tx.transactionType} de '
          '${_money(tx.brlAmount)} em ${_formatDate(tx.transactionDate)}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _backendService.deleteTransaction(tx.id!);
        _didModify = true;
        _loadTransactions();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir: $e')),
          );
        }
      }
    }
  }

  void _showTransactionDetail(InvestmentTransaction tx) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _TransactionDetailSheet(tx: tx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _didModify) {
          // Signal parent to refresh
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(asset.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '${_categoryLabels[asset.category] ?? asset.category}'
                '${asset.account != null ? ' · ${asset.account}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _didModify),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openAddTransaction,
          tooltip: 'Adicionar transação',
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            _buildPositionCard(asset),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage.isNotEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMessage,
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              FilledButton(
                                  onPressed: _loadTransactions,
                                  child: const Text('Tentar novamente')),
                            ],
                          ),
                        )
                      : _transactions.isEmpty
                          ? const Center(
                              child: Text(
                                'Nenhuma transação.\nToque + para adicionar.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadTransactions,
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.only(bottom: 80),
                                itemCount: _transactions.length,
                                itemBuilder: (_, i) =>
                                    _buildTxTile(_transactions[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(InvestmentAsset asset) {
    final isProfit = asset.unrealizedPnlBrl >= 0;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quantidade',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(asset.quantity.toStringAsFixed(asset.quantity < 10 ? 6 : 2),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Preço Médio',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(_money(asset.avgCostBrl),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Valor Atual',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(_money(asset.currentValueBrl),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Investido',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(_money(asset.totalInvestedBrl),
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ganho Não Realizado',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(
                        '${isProfit ? '+' : ''}${_money(asset.unrealizedPnlBrl)} (${asset.unrealizedPnlPct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _pnlColor(asset.unrealizedPnlBrl)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (asset.realizedGainsBrl != 0 || asset.dividendsBrl > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (asset.realizedGainsBrl != 0)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ganhos Realizados',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            _money(asset.realizedGainsBrl),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color:
                                    _pnlColor(asset.realizedGainsBrl)),
                          ),
                        ],
                      ),
                    ),
                  if (asset.dividendsBrl > 0)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Dividendos',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(
                            _money(asset.dividendsBrl),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTxTile(InvestmentTransaction tx) {
    final typeLabel = _txTypeLabels[tx.transactionType] ?? tx.transactionType;
    final typeColor =
        _txTypeColors[tx.transactionType] ?? Colors.grey;

    return Dismissible(
      key: Key(tx.id ?? tx.transactionDate.toIso8601String()),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteTransaction(tx);
        return false; // We handle removal via reload
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: ListTile(
        onTap: () => _showTransactionDetail(tx),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: typeColor.withAlpha(30),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            typeLabel,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: typeColor),
          ),
        ),
        title: Text(
          _money(tx.brlAmount),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_formatDate(tx.transactionDate)}'
          '${tx.quantity > 0 ? ' · ${tx.quantity.toStringAsFixed(4)} un.' : ''}'
          '${tx.originalCurrency != 'BRL' ? ' · ${tx.originalCurrency} ${tx.originalAmount.toStringAsFixed(2)}' : ''}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: tx.notes != null
            ? const Icon(Icons.notes, size: 16, color: Colors.grey)
            : null,
      ),
    );
  }
}

// ── Transaction detail bottom sheet ──────────────────────────────────────────

class _TransactionDetailSheet extends StatelessWidget {
  final InvestmentTransaction tx;
  const _TransactionDetailSheet({required this.tx});

  static const _txTypeLabels = {
    'buy': 'Compra',
    'sell': 'Venda',
    'dividend': 'Dividendo',
    'deposit': 'Depósito',
    'withdrawal': 'Retirada',
  };

  String _money(double v) => 'R\$ ${v.toStringAsFixed(2)}';
  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_txTypeLabels[tx.transactionType] ?? tx.transactionType,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _row('Data', _fmt(tx.transactionDate)),
          _row('Valor BRL', _money(tx.brlAmount)),
          if (tx.quantity > 0) _row('Quantidade', tx.quantity.toStringAsFixed(6)),
          if (tx.originalCurrency != 'BRL') ...[
            _row('Moeda', tx.originalCurrency),
            _row('Valor Original', tx.originalAmount.toStringAsFixed(2)),
            if (tx.exchangeRate != null)
              _row('Taxa de Câmbio', tx.exchangeRate!.toStringAsFixed(4)),
          ],
          if (tx.feesBrl > 0) _row('Taxas', _money(tx.feesBrl)),
          if (tx.notes != null) _row('Notas', tx.notes!),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

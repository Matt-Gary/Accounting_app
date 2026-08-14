import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../utils/money_format.dart';
import '../widgets/asset_form_sheet.dart';
import '../widgets/charts/price_history_chart.dart';
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

  static const _txTypeColors = {
    'buy': Color(0xFF1F7A1F),
    'sell': Color(0xFFC00000),
    'dividend': Color(0xFF1565C0),
    'coupon': Color(0xFF1565C0),
    'deposit': Color(0xFF1F7A1F),
    'withdrawal': Color(0xFFC00000),
  };

  String _txTypeLabel(String t) => 'investments.tx_types.$t'.tr();
  String _categoryLabel(String c) => 'investments.categories.$c'.tr();

  /// Which currency the figures on this screen are shown in: BRL, or the
  /// currency the asset was actually bought in.
  late String _displayCurrency;

  /// Local copy so an edit shows immediately instead of waiting for the
  /// portfolio screen to reload.
  late InvestmentAsset _asset;

  /// The asset's own currency. Falls back to `currency` for assets that
  /// predate `native_currency` being returned.
  String get _assetCurrency => _asset.nativeCurrency.isNotEmpty
      ? _asset.nativeCurrency
      : _asset.currency;

  /// A BRL-denominated asset has nothing to switch between.
  bool get _canSwitchCurrency => _assetCurrency != 'BRL';

  bool get _showingNative => _displayCurrency != 'BRL';

  @override
  void initState() {
    super.initState();
    _asset = widget.asset;  // seed once
    _displayCurrency = 'BRL';
    _loadTransactions();
  }

  Future<void> _editAsset() async {
    final edited = await showModalBottomSheet<InvestmentAsset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AssetFormSheet(
        existing: _asset,
        transactionCount: _transactions.length,
      ),
    );
    if (edited == null || !mounted) return;
    try {
      await _backendService.updateAsset(_asset.id!, edited.toAssetJson());
      setState(() {
        _asset = _asset.withMetadataFrom(edited);
        // Category or currency changes alter how the position is valued, so
        // the portfolio screen must recompute when we go back.
        _didModify = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('common.error_with_message'
                  .tr(namedArgs: {'message': '$e'}))),
        );
      }
    }
  }

  /// Deleting cascades every transaction, so it is offered only while there is
  /// nothing to lose. An asset with history is archived, never removed — that
  /// history is what the tax report is built from.
  Future<void> _deleteAsset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('investments.asset_form.delete_title'.tr()),
        content: Text('investments.asset_form.delete_body'
            .tr(namedArgs: {'name': _asset.name})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr())),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _backendService.deleteAsset(_asset.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('common.error_with_message'
                  .tr(namedArgs: {'message': '$e'}))),
        );
      }
    }
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final txns = await _backendService.getTransactions(
          assetId: _asset.id);
      setState(() => _transactions = txns);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Formats a value that is already expressed in [currency]. Nothing here
  /// converts — each figure is picked from the pair the backend computed, so a
  /// native amount is never re-derived from a BRL one using today's rate.
  String _money(double v, {String? currency}) =>
      formatMoney(v, currency ?? _displayCurrency, context.locale.toString());

  /// Picks the right member of a BRL/native pair for the current toggle.
  String _pick(double brl, double native) =>
      _money(_showingNative ? native : brl);

  Widget _currencyBtn(String currency) {
    final selected = _displayCurrency == currency;
    final onSurface = Theme.of(context).appBarTheme.foregroundColor ??
        Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: () => setState(() => _displayCurrency = currency),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? onSurface.withValues(alpha: 0.15) : null,
          border: Border.all(color: onSurface.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          currency,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: onSurface.withValues(alpha: selected ? 1.0 : 0.6),
          ),
        ),
      ),
    );
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
            (a) => a.id == _asset.id,
            orElse: () => _asset,
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
        title: Text('investments.tx.delete_title'.tr()),
        content: Text(
          '${_txTypeLabel(tx.transactionType)} · '
          '${_money(tx.brlAmount)} · ${_formatDate(tx.transactionDate)}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr())),
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
            SnackBar(
                content: Text('investments.tx.delete_error'
                    .tr(namedArgs: {'error': '$e'}))),
          );
        }
      }
    }
  }

  void _showTransactionDetail(InvestmentTransaction tx) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _TransactionDetailSheet(tx: tx),
    );
    if (action == 'edit') _openEditTransaction(tx);
  }

  Future<void> _openEditTransaction(InvestmentTransaction tx) async {
    final assets = await _backendService.getAssets();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          availableAssets: assets,
          preselectedAsset: assets.firstWhere(
            (a) => a.id == tx.assetId,
            orElse: () => _asset,
          ),
          existing: tx,
        ),
      ),
    );
    if (saved == true) {
      _didModify = true;
      _loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    final asset = _asset;
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
                '${_categoryLabel(asset.category)}'
                '${asset.account != null ? ' · ${asset.account}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _didModify),
          ),
          actions: [
            if (_canSwitchCurrency)
              Row(children: [
                _currencyBtn('BRL'),
                const SizedBox(width: 6),
                _currencyBtn(_assetCurrency),
              ]),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _editAsset();
                if (v == 'delete') _deleteAsset();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    const Icon(Icons.edit_outlined, size: 18),
                    const SizedBox(width: 10),
                    Text('investments.asset_form.edit_asset'.tr()),
                  ]),
                ),
                // Only while there is no history to destroy.
                if (_transactions.isEmpty)
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      const Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      const SizedBox(width: 10),
                      Text('investments.asset_form.delete_asset'.tr(),
                          style: const TextStyle(color: Colors.red)),
                    ]),
                  ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openAddTransaction,
          tooltip: 'investments.add_transaction_tooltip'.tr(),
          child: const Icon(Icons.add),
        ),
        body: Column(
          children: [
            _buildPositionCard(asset),
            // Price context for decisions: only assets with a live quote have
            // a history to draw. Wrapped so a missing id can never crash.
            if (asset.hasMktPrice && asset.id != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: PriceHistoryChart(asset: asset),
              ),
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
                                  child: Text('common.retry'.tr())),
                            ],
                          ),
                        )
                      : _transactions.isEmpty
                          ? Center(
                              child: Text(
                                'investments.tx.none'.tr(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey),
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

  /// A closed position has zero quantity, zero average and zero current value —
  /// showing that grid would be four meaningless zeros. What matters once a
  /// position is sold out is what it actually made.
  Widget _buildClosedCard(InvestmentAsset asset) {
    final realized = _showingNative
        ? asset.realizedGainsOriginal
        : asset.realizedGainsBrl;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text('investments.archive.closed_badge'.tr(),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (asset.lastTransactionDate != null)
                  Text(_formatDate(asset.lastTransactionDate!),
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('investments.position.realized_gains'.tr(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(
                        '${realized >= 0 ? '+' : ''}${_money(realized)}',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _pnlColor(realized)),
                      ),
                    ],
                  ),
                ),
                if (asset.dividendsBrl > 0)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('investments.position.dividends'.tr(),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                        Text(
                          _pick(asset.dividendsBrl, asset.dividendsOriginal),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(InvestmentAsset asset) {
    if (asset.isClosed) return _buildClosedCard(asset);
    // Each figure is read from whichever of the two the backend computed —
    // the native P&L excludes the FX component by construction, so switching
    // the toggle shows the pure asset move rather than a reconverted total.
    final pnl = _showingNative
        ? asset.unrealizedPnlOriginal
        : asset.unrealizedPnlBrl;
    final pnlPct = _showingNative
        ? asset.unrealizedPnlPctOriginal
        : asset.unrealizedPnlPct;
    final isProfit = pnl >= 0;
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
                      Text('investments.position.quantity'.tr(),
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
                      Text('investments.position.avg_price'.tr(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(_pick(asset.avgCostBrl, asset.avgCostOriginal),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('investments.position.current_value'.tr(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(
                          _pick(asset.currentValueBrl,
                              asset.currentValueOriginal),
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
                      Text('investments.position.invested'.tr(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(
                          _pick(asset.totalInvestedBrl,
                              asset.totalInvestedOriginal),
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('investments.position.unrealized_pnl'.tr(),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(
                        '${isProfit ? '+' : ''}${_money(pnl)} (${pnlPct.toStringAsFixed(1)}%)',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _pnlColor(pnl)),
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
                          Text('investments.position.realized_gains'.tr(),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          Text(
                            _pick(asset.realizedGainsBrl,
                                asset.realizedGainsOriginal),
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
                          Text('investments.position.dividends'.tr(),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          Text(
                            _pick(asset.dividendsBrl, asset.dividendsOriginal),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0)),
                          ),
                          if (asset.yieldOnCostPct != null)
                            Text(
                              'investments.position.yield_on_cost'.tr(
                                  namedArgs: {
                                    'pct': asset.yieldOnCostPct!
                                        .toStringAsFixed(2)
                                  }),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey),
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

  /// The amount in whichever currency the headline is NOT showing, so a
  /// foreign trade always displays both figures at once.
  String _secondaryAmount(InvestmentTransaction tx) {
    if (tx.originalCurrency == 'BRL') return '';
    return _showingNative
        ? ' · ${_money(tx.brlAmount, currency: 'BRL')}'
        : ' · ${_money(tx.originalAmount, currency: tx.originalCurrency)}';
  }

  Widget _buildTxTile(InvestmentTransaction tx) {
    final typeLabel = _txTypeLabel(tx.transactionType);
    final typeColor = _txTypeColors[tx.transactionType] ?? Colors.grey;

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
        // Headline follows the toggle; the other currency stays on the
        // subtitle so both are always visible for a foreign-currency trade.
        title: Text(
          _showingNative
              ? _money(tx.originalAmount, currency: tx.originalCurrency)
              : _money(tx.brlAmount, currency: 'BRL'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_formatDate(tx.transactionDate)}'
          '${tx.quantity > 0 ? ' · ${tx.quantity.toStringAsFixed(4)} ${'investments.tx.units_short'.tr()}' : ''}'
          '${_secondaryAmount(tx)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tx.notes != null)
              const Icon(Icons.notes, size: 16, color: Colors.grey),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'common.edit'.tr(),
              onPressed: () => _openEditTransaction(tx),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Transaction detail bottom sheet ──────────────────────────────────────────

class _TransactionDetailSheet extends StatelessWidget {
  final InvestmentTransaction tx;
  const _TransactionDetailSheet({required this.tx});

  String _money(double v, [String currency = 'BRL']) =>
      formatMoney(v, currency, Intl.getCurrentLocale());
  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('investments.tx_types.${tx.transactionType}'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _row('investments.tx.date'.tr(), _fmt(tx.transactionDate)),
          _row('investments.tx.amount_brl'.tr(), _money(tx.brlAmount)),
          if (tx.quantity > 0)
            _row('investments.tx.quantity'.tr(),
                tx.quantity.toStringAsFixed(6)),
          if (tx.originalCurrency != 'BRL') ...[
            _row('investments.tx.currency'.tr(), tx.originalCurrency),
            _row('investments.tx.original_amount'.tr(),
                _money(tx.originalAmount, tx.originalCurrency)),
            if (tx.exchangeRate != null)
              _row('investments.tx.exchange_rate'.tr(),
                  tx.exchangeRate!.toStringAsFixed(4)),
          ],
          // Shown in both units when the trade was foreign, so the figure that
          // raised the cost basis is traceable to the one that was typed.
          if (tx.feesOriginal > 0 || tx.feesBrl > 0)
            _row(
              'investments.tx.fees'.tr(),
              tx.originalCurrency == 'BRL'
                  ? _money(tx.feesBrl)
                  : '${_money(tx.feesOriginal, tx.originalCurrency)}'
                      '  ·  ${_money(tx.feesBrl)}',
            ),
          if (tx.notes != null) _row('investments.tx.notes'.tr(), tx.notes!),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'edit'),
              icon: const Icon(Icons.edit, size: 18),
              label: Text('common.edit'.tr()),
            ),
          ),
          const SizedBox(height: 8),
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

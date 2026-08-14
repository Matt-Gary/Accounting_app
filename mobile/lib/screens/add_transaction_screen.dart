import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../widgets/asset_form_sheet.dart';

class AddTransactionScreen extends StatefulWidget {
  final List<InvestmentAsset> availableAssets;
  final InvestmentAsset? preselectedAsset;

  /// When set, the screen edits this transaction instead of creating one.
  final InvestmentTransaction? existing;

  const AddTransactionScreen({
    super.key,
    required this.availableAssets,
    this.preselectedAsset,
    this.existing,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _backendService = BackendService();

  List<InvestmentAsset> _assets = [];
  InvestmentAsset? _selectedAsset;
  String _transactionType = 'buy';
  DateTime _date = DateTime.now();
  String _originalCurrency = 'BRL';
  bool _isSubmitting = false;

  final _quantityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _originalAmtCtrl = TextEditingController();
  final _exchangeRateCtrl = TextEditingController(text: '1.0');
  final _brlAmtCtrl = TextEditingController();
  final _feesCtrl = TextEditingController(text: '0.00');
  final _withholdingCtrl = TextEditingController(text: '0.00');
  final _notesCtrl = TextEditingController();

  static const _currencies = ['BRL', 'USD', 'EUR', 'PLN'];
  static const _txTypeKeys = [
    'buy', 'sell', 'dividend', 'coupon', 'deposit', 'withdrawal'
  ];

  String _txTypeLabel(String t) => 'investments.tx_types.$t'.tr();
  String _categoryLabel(String c) => 'investments.categories.$c'.tr();

  bool get _showQuantityPrice =>
      _transactionType == 'buy' || _transactionType == 'sell';
  bool get _showExchangeRate => _originalCurrency != 'BRL';
  bool get _isCashType =>
      _transactionType == 'deposit' || _transactionType == 'withdrawal';
  bool get _isIncomeType =>
      _transactionType == 'dividend' || _transactionType == 'coupon';

  bool get _isEditing => widget.existing != null;

  /// Trade-date rate fetched from the backend, shown so the user knows the
  /// prefilled figure is a market close, not something they typed.
  String? _fxRateDate;

  /// Domain rejection from the backend (oversell, missing rate), rendered
  /// inline under the form instead of a vanishing snackbar.
  String? _submitError;

  /// Date of the transaction the sticky fields were copied from, so the form
  /// can say where the exchange rate came from instead of presenting a stale
  /// figure as if it were current.
  DateTime? _prefilledFrom;

  /// Copies the repetitive fields from the most recent transaction on this
  /// asset: type, currency, exchange rate and fee. Amount, quantity, price and
  /// date are always left blank — those are what actually changes, and a stale
  /// one silently entered is worse than an empty field.
  Future<void> _applyPreviousDefaults(InvestmentAsset asset) async {
    if (_isEditing || asset.id == null) return;
    try {
      final previous =
          await _backendService.getTransactions(assetId: asset.id);
      if (previous.isEmpty || !mounted) return;
      final last = previous.first; // API returns newest first
      setState(() {
        _transactionType = last.transactionType;
        _originalCurrency = last.originalCurrency;
        _exchangeRateCtrl.text = (last.exchangeRate ?? 1.0).toString();
        _feesCtrl.text = last.feesOriginal.toStringAsFixed(2);
        _prefilledFrom = last.transactionDate;
      });
      _recalcBrl();
      // A fresh market close for the trade date beats a rate carried over
      // from an older transaction; replaces the stale-rate warning when found.
      _maybePrefillFxRate();
    } catch (_) {
      // Prefilling is a convenience — never let it block entry.
    }
  }

  @override
  void initState() {
    super.initState();
    _assets = widget.availableAssets;
    _selectedAsset = widget.preselectedAsset;

    final tx = widget.existing;
    if (tx != null) {
      _prefillFrom(tx);
    }

    // Attached after prefilling so restoring the saved values does not trigger
    // a recalculation that overwrites them.
    _originalAmtCtrl.addListener(_recalcBrl);
    _exchangeRateCtrl.addListener(_recalcBrl);
    _feesCtrl.addListener(_recalcBrl);
    _priceCtrl.addListener(_recalcOriginalAmt);
    _quantityCtrl.addListener(_recalcOriginalAmt);

    // Arriving from an asset's own screen: carry its last transaction forward.
    if (!_isEditing && _selectedAsset != null) {
      _applyPreviousDefaults(_selectedAsset!);
    }
  }

  void _prefillFrom(InvestmentTransaction tx) {
    _transactionType = tx.transactionType;
    _date = tx.transactionDate;
    _originalCurrency = tx.originalCurrency;
    _selectedAsset = _assets.where((a) => a.id == tx.assetId).isNotEmpty
        ? _assets.firstWhere((a) => a.id == tx.assetId)
        : widget.preselectedAsset;

    // Quantity is only meaningful for buys and sells. For cash movements the
    // stored quantity mirrors the amount, so showing it would invite the two to
    // drift apart; the backend re-derives it on save.
    if (_showQuantityPrice) {
      _quantityCtrl.text = _trim(tx.quantity);
      if (tx.pricePerUnitOriginal != null) {
        _priceCtrl.text = _trim(tx.pricePerUnitOriginal!);
      }
    }
    _originalAmtCtrl.text = tx.originalAmount.toStringAsFixed(2);
    _exchangeRateCtrl.text = (tx.exchangeRate ?? 1.0).toString();
    _feesCtrl.text = tx.feesOriginal.toStringAsFixed(2);
    _withholdingCtrl.text = tx.withholdingTaxOriginal.toStringAsFixed(2);
    _brlAmtCtrl.text = tx.brlAmount.toStringAsFixed(2);
    _notesCtrl.text = tx.notes ?? '';
  }

  /// Drops trailing zeros so 10.000000 reads as 10 in the form.
  String _trim(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v.toString();

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    _originalAmtCtrl.dispose();
    _exchangeRateCtrl.dispose();
    _brlAmtCtrl.dispose();
    _feesCtrl.dispose();
    _withholdingCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Fetch the closing rate for the selected trade date and currency and
  /// prefill the rate field. Best-effort: no rate, no change. Never runs while
  /// editing — the stored rate is an authoritative tax figure and must not be
  /// silently rewritten.
  Future<void> _maybePrefillFxRate() async {
    if (_isEditing || _originalCurrency == 'BRL') return;
    final dateStr =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    final result =
        await _backendService.getFxRate(_originalCurrency, dateStr);
    if (result == null || !mounted) return;
    setState(() {
      _exchangeRateCtrl.text = (result['rate_brl'] as num).toString();
      _fxRateDate = result['rate_date'] as String?;
      _prefilledFrom = null; // a fresh market close replaces the stale warning
    });
    _recalcBrl();
  }

  void _recalcOriginalAmt() {
    final qty = double.tryParse(_quantityCtrl.text);
    final price = double.tryParse(_priceCtrl.text);
    if (qty != null && price != null) {
      _originalAmtCtrl.removeListener(_recalcBrl);
      _originalAmtCtrl.text = (qty * price).toStringAsFixed(2);
      _originalAmtCtrl.addListener(_recalcBrl);
      _recalcBrl();
    }
  }

  /// Net amount in the transaction's own currency, applying the Receita
  /// Federal fee rule: a purchase fee is part of the acquisition cost, a sale
  /// fee comes out of the proceeds. Applied before conversion.
  ///
  /// This mirrors `net_amount_original` on the backend, which is authoritative
  /// — what the form shows is a live preview of what the server will store.
  double? get _netOriginal {
    final orig = double.tryParse(_originalAmtCtrl.text);
    if (orig == null) return null;
    final fee = double.tryParse(_feesCtrl.text) ?? 0.0;
    final isAcquisition =
        _transactionType == 'buy' || _transactionType == 'deposit';
    if (_transactionType == 'dividend' || _transactionType == 'coupon') {
      return orig;
    }
    return isAcquisition ? orig + fee : orig - fee;
  }

  void _recalcBrl() {
    final net = _netOriginal;
    if (net == null) return;
    if (_originalCurrency == 'BRL') {
      _brlAmtCtrl.text = net.toStringAsFixed(2);
    } else {
      final rate = double.tryParse(_exchangeRateCtrl.text);
      if (rate != null && rate > 0) {
        _brlAmtCtrl.text = (net * rate).toStringAsFixed(2);
      }
    }
  }

  void _onCurrencyChanged(String? val) {
    if (val == null) return;
    setState(() {
      _originalCurrency = val;
      _fxRateDate = null;
      if (val == 'BRL') {
        _exchangeRateCtrl.text = '1.0';
      }
    });
    _recalcBrl();
    _maybePrefillFxRate();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _date = picked;
        _fxRateDate = null; // the old close no longer matches the new date
      });
      _maybePrefillFxRate();
    }
  }

  Future<void> _createAssetInline() async {
    final result = await showModalBottomSheet<InvestmentAsset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AssetFormSheet(),
    );
    if (result != null) {
      try {
        final created = await _backendService.createAsset(result.toAssetJson());
        setState(() {
          _assets = [..._assets, created];
          _selectedAsset = created;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('investments.asset_form.create_error'
                    .tr(namedArgs: {'error': '$e'}))),
          );
        }
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('investments.form.select_asset'.tr())),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final dateStr =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    // brl_amount is deliberately NOT sent. It is the authoritative tax figure
    // and the backend derives it from these inputs using the same rule the
    // cost-basis engine applies; the field on screen is only a preview.
    final data = <String, dynamic>{
      'asset_id': _selectedAsset!.id,
      'transaction_type': _transactionType,
      'transaction_date': dateStr,
      // Cash movements send 0 so the backend derives the quantity from the
      // amount. Sending the old stored quantity would leave it stale whenever
      // the amount is edited.
      'quantity': _showQuantityPrice
          ? (double.tryParse(_quantityCtrl.text) ?? 0.0)
          : 0.0,
      'original_currency': _originalCurrency,
      'original_amount': double.tryParse(_originalAmtCtrl.text) ?? 0.0,
      'fees_original': double.tryParse(_feesCtrl.text) ?? 0.0,
      // Tax withheld at source on foreign income. Sent for every type (zero
      // outside dividends/coupons) so clearing it on an edit sticks.
      'withholding_tax_original': _isIncomeType
          ? (double.tryParse(_withholdingCtrl.text) ?? 0.0)
          : 0.0,
    };

    if (_showQuantityPrice) {
      // Sent even when blank so that clearing the field on an edit actually
      // clears the stored value instead of leaving the old one behind.
      data['price_per_unit_original'] = double.tryParse(_priceCtrl.text);
    }
    if (_showExchangeRate) {
      data['exchange_rate'] = double.tryParse(_exchangeRateCtrl.text);
    }
    if (_notesCtrl.text.isNotEmpty) {
      data['notes'] = _notesCtrl.text.trim();
    } else if (_isEditing) {
      // Explicit null so deleting the note on an edit actually removes it.
      data['notes'] = null;
    }

    try {
      if (_isEditing) {
        await _backendService.updateTransaction(widget.existing!.id!, data);
      } else {
        await _backendService.createTransaction(data);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        // Inline, not a snackbar: a domain rejection (oversell, missing FX
        // rate) needs to stay on screen while the user fixes the field.
        setState(() => _submitError =
            '$e'.replaceFirst(RegExp(r'^Exception:\s*'), ''));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      appBar: AppBar(
        title: Text((_isEditing
                ? 'investments.form.title_edit'
                : 'investments.form.title')
            .tr()),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Asset ─────────────────────────────────────────────────────
            DropdownButtonFormField<InvestmentAsset>(
              value: _selectedAsset,
              decoration: InputDecoration(
                labelText: 'investments.form.asset'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: [
                ..._assets.map((a) => DropdownMenuItem(
                      value: a,
                      child: Text(
                        '${a.name}${a.symbol != null ? ' (${a.symbol})' : ''} — ${_categoryLabel(a.category)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                DropdownMenuItem(
                  value: null,
                  child: Text('investments.form.new_asset'.tr(),
                      style: const TextStyle(color: Colors.blue)),
                ),
              ],
              // Moving a transaction to a different asset would silently
              // rewrite the cost basis of two positions at once, so the asset
              // is locked while editing. Change it by deleting and re-entering.
              onChanged: _isEditing
                  ? null
                  : (val) {
                      if (val == null) {
                        _createAssetInline();
                      } else {
                        setState(() => _selectedAsset = val);
                        _applyPreviousDefaults(val);
                      }
                    },
            ),
            const SizedBox(height: 12),

            // ── Transaction Type ───────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _transactionType,
              decoration: InputDecoration(
                labelText: 'investments.form.tx_type'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: _txTypeKeys
                  .map((k) => DropdownMenuItem(
                      value: k, child: Text(_txTypeLabel(k))))
                  .toList(),
              onChanged: (v) {
                // The fee direction depends on the type, so the BRL preview
                // has to be recomputed when it changes.
                setState(() => _transactionType = v!);
                _recalcBrl();
              },
            ),
            const SizedBox(height: 12),

            // ── Date ──────────────────────────────────────────────────────
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'investments.form.date'.tr(),
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                child: Text(
                  '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Quantity (buy/sell only) ───────────────────────────────────
            if (_showQuantityPrice) ...[
              TextFormField(
                controller: _quantityCtrl,
                decoration: InputDecoration(
                  labelText: 'investments.form.quantity'.tr(),
                  border: const OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (_showQuantityPrice && (v == null || v.isEmpty)) {
                    return 'investments.form.quantity_required'.tr();
                  }
                  // Early catch only — the backend replays the ledger on
                  // every write and is the authority (covers edits too).
                  if (!_isEditing && _transactionType == 'sell') {
                    final qty = double.tryParse(v ?? '');
                    final held = _selectedAsset?.quantity;
                    if (qty != null && held != null && qty > held + 1e-9) {
                      return 'investments.form.oversell'
                          .tr(namedArgs: {'held': _trim(held)});
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // ── Original Currency ──────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _originalCurrency,
              decoration: InputDecoration(
                labelText: 'investments.form.currency'.tr(),
                border: const OutlineInputBorder(),
              ),
              items: _currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _onCurrencyChanged,
            ),
            const SizedBox(height: 12),

            // ── Price per unit (buy/sell only, optional) ───────────────────
            if (_showQuantityPrice) ...[
              TextFormField(
                controller: _priceCtrl,
                decoration: InputDecoration(
                  labelText: 'investments.form.price_per_unit'
                      .tr(namedArgs: {'currency': _originalCurrency}),
                  border: const OutlineInputBorder(),
                  helperText: 'investments.form.price_helper'.tr(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
            ],

            // ── Total original amount ──────────────────────────────────────
            TextFormField(
              controller: _originalAmtCtrl,
              decoration: InputDecoration(
                labelText: (_isCashType
                        ? 'investments.form.amount'
                        : 'investments.form.total')
                    .tr(namedArgs: {'currency': _originalCurrency}),
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'investments.form.amount_required'.tr();
                }
                if (double.tryParse(v) == null) {
                  return 'investments.form.amount_invalid'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Fees, in the transaction's own currency ────────────────────
            TextFormField(
              controller: _feesCtrl,
              decoration: InputDecoration(
                labelText: 'investments.form.fees'
                    .tr(namedArgs: {'currency': _originalCurrency}),
                border: const OutlineInputBorder(),
                helperText: 'investments.form.fees_helper'.tr(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),

            // ── Withholding tax (dividends / coupons only) ─────────────────
            // Tax retained at source on foreign income. The gross amount goes
            // into the row (the tax report needs it); the app shows income
            // net of this figure.
            if (_isIncomeType) ...[
              TextFormField(
                controller: _withholdingCtrl,
                decoration: InputDecoration(
                  labelText: 'investments.form.withholding'
                      .tr(namedArgs: {'currency': _originalCurrency}),
                  border: const OutlineInputBorder(),
                  helperText: 'investments.form.withholding_helper'.tr(),
                  helperMaxLines: 2,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final d = double.tryParse(v);
                  if (d == null || d < 0) {
                    return 'investments.form.amount_invalid'.tr();
                  }
                  final gross = double.tryParse(_originalAmtCtrl.text);
                  if (gross != null && d > gross) {
                    return 'investments.form.withholding_exceeds_gross'.tr();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // ── Exchange rate (non-BRL only) ───────────────────────────────
            if (_showExchangeRate) ...[
              TextFormField(
                controller: _exchangeRateCtrl,
                decoration: InputDecoration(
                  labelText: 'investments.form.exchange_rate'
                      .tr(namedArgs: {'currency': _originalCurrency}),
                  border: const OutlineInputBorder(),
                  // Provenance of a prefilled rate. A market close fetched
                  // for the trade date is trustworthy (green); a rate carried
                  // over from an older trade is not today's rate, and it
                  // lands straight in the BRL cost basis, so it must not
                  // look current (red).
                  helperText: _fxRateDate != null
                      ? 'investments.form.exchange_rate_fetched'
                          .tr(namedArgs: {'date': _fxRateDate!})
                      : _prefilledFrom == null
                          ? 'investments.form.exchange_rate_helper'.tr()
                          : 'investments.form.exchange_rate_prefilled'.tr(
                              namedArgs: {'date': _formatDate(_prefilledFrom!)}),
                  helperMaxLines: 2,
                  helperStyle: _fxRateDate != null
                      ? const TextStyle(color: Colors.green)
                      : _prefilledFrom == null
                          ? null
                          : TextStyle(
                              color: Theme.of(context).colorScheme.error),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (_showExchangeRate) {
                    final d = double.tryParse(v ?? '');
                    if (d == null || d <= 0) {
                      return 'investments.form.exchange_rate_invalid'.tr();
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // ── BRL Amount (auto-computed, editable override) ──────────────
            TextFormField(
              controller: _brlAmtCtrl,
              // Read-only: the backend derives the stored figure from amount,
              // fee and rate. Letting it be edited here would allow the tax
              // number to drift from the inputs that justify it.
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'investments.form.total_brl'.tr(),
                border: const OutlineInputBorder(),
                helperText: 'investments.form.total_brl_helper'.tr(),
                filled: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d <= 0) {
                  return 'investments.form.total_brl_required'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Notes ─────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: 'investments.form.notes'.tr(),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            // ── Inline domain error (oversell, missing FX rate…) ───────────
            if (_submitError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _submitError!,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text((_isEditing
                          ? 'investments.form.save'
                          : 'investments.form.submit')
                      .tr()),
            ),
          ],
        ),
      ),
    );
  }
}

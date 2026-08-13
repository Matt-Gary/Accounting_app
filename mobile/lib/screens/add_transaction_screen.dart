import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';

class AddTransactionScreen extends StatefulWidget {
  final List<InvestmentAsset> availableAssets;
  final InvestmentAsset? preselectedAsset;

  const AddTransactionScreen({
    super.key,
    required this.availableAssets,
    this.preselectedAsset,
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
  final _notesCtrl = TextEditingController();

  static const _currencies = ['BRL', 'USD', 'EUR', 'PLN'];
  static const _txTypes = {
    'buy': 'Compra',
    'sell': 'Venda',
    'dividend': 'Dividendo',
    'deposit': 'Depósito',
    'withdrawal': 'Retirada',
  };
  static const _categoryLabels = {
    'stock': 'Ações',
    'crypto': 'Cripto',
    'bond': 'Renda Fixa',
    'cash_broker': 'Caixa Corretora',
    'cash_home': 'Dinheiro Físico',
    'cash_bank': 'Conta Bancária',
  };

  bool get _showQuantityPrice =>
      _transactionType == 'buy' || _transactionType == 'sell';
  bool get _showExchangeRate => _originalCurrency != 'BRL';
  bool get _isCashType =>
      _transactionType == 'deposit' || _transactionType == 'withdrawal';

  @override
  void initState() {
    super.initState();
    _assets = widget.availableAssets;
    _selectedAsset = widget.preselectedAsset;
    _originalAmtCtrl.addListener(_recalcBrl);
    _exchangeRateCtrl.addListener(_recalcBrl);
    _priceCtrl.addListener(_recalcOriginalAmt);
    _quantityCtrl.addListener(_recalcOriginalAmt);
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    _originalAmtCtrl.dispose();
    _exchangeRateCtrl.dispose();
    _brlAmtCtrl.dispose();
    _feesCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
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

  void _recalcBrl() {
    final orig = double.tryParse(_originalAmtCtrl.text);
    if (orig == null) return;
    if (_originalCurrency == 'BRL') {
      _brlAmtCtrl.text = orig.toStringAsFixed(2);
    } else {
      final rate = double.tryParse(_exchangeRateCtrl.text);
      if (rate != null && rate > 0) {
        _brlAmtCtrl.text = (orig * rate).toStringAsFixed(2);
      }
    }
  }

  void _onCurrencyChanged(String? val) {
    if (val == null) return;
    setState(() {
      _originalCurrency = val;
      if (val == 'BRL') {
        _exchangeRateCtrl.text = '1.0';
      }
    });
    _recalcBrl();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _createAssetInline() async {
    final result = await showModalBottomSheet<InvestmentAsset>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateAssetSheet(),
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
            SnackBar(content: Text('Erro ao criar ativo: $e')),
          );
        }
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAsset == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione um ativo')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final dateStr =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    final data = <String, dynamic>{
      'asset_id': _selectedAsset!.id,
      'transaction_type': _transactionType,
      'transaction_date': dateStr,
      'quantity': double.tryParse(_quantityCtrl.text) ?? 0.0,
      'original_currency': _originalCurrency,
      'original_amount': double.tryParse(_originalAmtCtrl.text) ?? 0.0,
      'brl_amount': double.tryParse(_brlAmtCtrl.text) ?? 0.0,
      'fees_brl': double.tryParse(_feesCtrl.text) ?? 0.0,
    };

    if (_showQuantityPrice && _priceCtrl.text.isNotEmpty) {
      data['price_per_unit_original'] = double.tryParse(_priceCtrl.text);
    }
    if (_showExchangeRate) {
      data['exchange_rate'] = double.tryParse(_exchangeRateCtrl.text);
    }
    if (_notesCtrl.text.isNotEmpty) {
      data['notes'] = _notesCtrl.text.trim();
    }

    try {
      await _backendService.createTransaction(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Transação'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Asset ─────────────────────────────────────────────────────
            DropdownButtonFormField<InvestmentAsset>(
              value: _selectedAsset,
              decoration: const InputDecoration(
                labelText: 'Ativo',
                border: OutlineInputBorder(),
              ),
              items: [
                ..._assets.map((a) => DropdownMenuItem(
                      value: a,
                      child: Text(
                        '${a.name}${a.symbol != null ? ' (${a.symbol})' : ''} — ${_categoryLabels[a.category] ?? a.category}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
                const DropdownMenuItem(
                  value: null,
                  child: Text('+ Novo ativo...', style: TextStyle(color: Colors.blue)),
                ),
              ],
              onChanged: (val) {
                if (val == null) {
                  _createAssetInline();
                } else {
                  setState(() => _selectedAsset = val);
                }
              },
            ),
            const SizedBox(height: 12),

            // ── Transaction Type ───────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _transactionType,
              decoration: const InputDecoration(
                labelText: 'Tipo de Transação',
                border: OutlineInputBorder(),
              ),
              items: _txTypes.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _transactionType = v!),
            ),
            const SizedBox(height: 12),

            // ── Date ──────────────────────────────────────────────────────
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data da Transação',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
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
                decoration: const InputDecoration(
                  labelText: 'Quantidade',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (_showQuantityPrice && (v == null || v.isEmpty)) {
                    return 'Informe a quantidade';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // ── Original Currency ──────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _originalCurrency,
              decoration: const InputDecoration(
                labelText: 'Moeda Original',
                border: OutlineInputBorder(),
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
                  labelText: 'Preço por Unidade ($_originalCurrency) — opcional',
                  border: const OutlineInputBorder(),
                  helperText: 'Preencher calcula o total automaticamente',
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
                labelText: _isCashType
                    ? 'Valor ($_originalCurrency)'
                    : 'Total ($_originalCurrency)',
                border: const OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Informe o valor';
                if (double.tryParse(v) == null) return 'Valor inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Exchange rate (non-BRL only) ───────────────────────────────
            if (_showExchangeRate) ...[
              TextFormField(
                controller: _exchangeRateCtrl,
                decoration: InputDecoration(
                  labelText: 'Taxa de Câmbio (1 $_originalCurrency = ? BRL)',
                  border: const OutlineInputBorder(),
                  helperText: 'Informe a cotação na data da transação',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (_showExchangeRate) {
                    final d = double.tryParse(v ?? '');
                    if (d == null || d <= 0) return 'Taxa inválida';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
            ],

            // ── BRL Amount (auto-computed, editable override) ──────────────
            TextFormField(
              controller: _brlAmtCtrl,
              decoration: const InputDecoration(
                labelText: 'Total em BRL (R\$)',
                border: OutlineInputBorder(),
                helperText: 'Calculado automaticamente. Edite se necessário.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final d = double.tryParse(v ?? '');
                if (d == null || d <= 0) return 'Informe o valor em R\$';
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Fees ──────────────────────────────────────────────────────
            TextFormField(
              controller: _feesCtrl,
              decoration: const InputDecoration(
                labelText: 'Taxas/Corretagem (BRL) — opcional',
                border: OutlineInputBorder(),
                helperText: 'Já incluído no total BRL acima',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),

            // ── Notes ─────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Observações — opcional',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Registrar Transação'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Inline asset creation sheet ───────────────────────────────────────────────

class _CreateAssetSheet extends StatefulWidget {
  const _CreateAssetSheet();

  @override
  State<_CreateAssetSheet> createState() => _CreateAssetSheetState();
}

class _CreateAssetSheetState extends State<_CreateAssetSheet> {
  final _formKey = GlobalKey<FormState>();
  String _category = 'stock';
  String _currency = 'BRL';
  final _nameCtrl = TextEditingController();
  final _symbolCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();

  static const _categories = {
    'stock': 'Ações',
    'crypto': 'Cripto',
    'bond': 'Renda Fixa',
    'cash_broker': 'Caixa Corretora',
    'cash_home': 'Dinheiro Físico',
    'cash_bank': 'Conta Bancária',
  };
  static const _currencies = ['BRL', 'USD', 'EUR', 'PLN'];

  bool get _showSymbol =>
      _category == 'stock' || _category == 'crypto';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _symbolCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final asset = InvestmentAsset(
      familyId: '',
      category: _category,
      name: _nameCtrl.text.trim(),
      symbol: _showSymbol && _symbolCtrl.text.isNotEmpty
          ? _symbolCtrl.text.trim().toUpperCase()
          : null,
      currency: _currency,
      account: _accountCtrl.text.isNotEmpty ? _accountCtrl.text.trim() : null,
    );
    Navigator.pop(context, asset);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Novo Ativo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                  labelText: 'Categoria', border: OutlineInputBorder()),
              items: _categories.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nome', border: OutlineInputBorder()),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Informe o nome' : null,
            ),
            if (_showSymbol) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _symbolCtrl,
                decoration: const InputDecoration(
                    labelText: 'Ticker (ex: AAPL, BTC-USD)',
                    border: OutlineInputBorder()),
                textCapitalization: TextCapitalization.characters,
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _currency,
              decoration: const InputDecoration(
                  labelText: 'Moeda', border: OutlineInputBorder()),
              items: _currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accountCtrl,
              decoration: const InputDecoration(
                  labelText: 'Corretora / Conta — opcional',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Criar Ativo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

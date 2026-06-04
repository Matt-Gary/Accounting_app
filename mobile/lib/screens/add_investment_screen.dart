import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../widgets/language_toggle.dart';

class AddInvestmentScreen extends StatefulWidget {
  final UserProfile? currentUser;
  final Investment? investmentToEdit;
  final List<Investment> existingInvestments;

  const AddInvestmentScreen({
    super.key,
    this.currentUser,
    this.investmentToEdit,
    this.existingInvestments = const [],
  });

  @override
  State<AddInvestmentScreen> createState() => _AddInvestmentScreenState();
}

class _AddInvestmentScreenState extends State<AddInvestmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _backendService = BackendService();
  bool _isLoading = false;

  final _nameController = TextEditingController();
  final _symbolController = TextEditingController();
  final _quantityController = TextEditingController();
  final _avgPriceController = TextEditingController();
  final _accountController = TextEditingController();

  String _selectedType = 'stock';
  final List<String> _types = ['stock', 'crypto', 'bond', 'cash', 'other'];

  String _selectedCurrency = 'BRL';
  final List<String> _currencies = ['BRL', 'USD', 'EUR', 'PLN'];

  bool _investable = true;

  // Distinct account labels already in use + their last-seen investable flag,
  // used for suggestion chips and to prefill the toggle when an account repeats.
  late final List<String> _accountSuggestions;
  late final Map<String, bool> _accountInvestable;

  @override
  void initState() {
    super.initState();

    _accountInvestable = {};
    final seen = <String>[];
    for (final inv in widget.existingInvestments) {
      final acc = inv.account?.trim() ?? '';
      if (acc.isEmpty) continue;
      if (!seen.contains(acc)) seen.add(acc);
      _accountInvestable[acc] = inv.investable;
    }
    _accountSuggestions = seen;

    if (widget.investmentToEdit != null) {
      final inv = widget.investmentToEdit!;
      _nameController.text = inv.name;
      _symbolController.text = inv.symbol ?? '';
      _quantityController.text = inv.quantity.toString();
      _selectedType = inv.type;
      _selectedCurrency = inv.currency;
      _accountController.text = inv.account ?? '';
      _investable = inv.investable;
      // Derive avg price per share from the stored total cost basis.
      if (inv.quantity > 0) {
        _avgPriceController.text =
            (inv.costBasis / inv.quantity).toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _symbolController.dispose();
    _quantityController.dispose();
    _avgPriceController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  double _parse(String s) => double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Resolve user: use provided currentUser, or load from profiles
    var user = widget.currentUser;
    if (user == null) {
      final familyData = await _backendService.getFamilyData();
      if (familyData.profiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('add_investment.no_profile'.tr())));
        }
        return;
      }
      user = familyData.profiles.first;
    }

    setState(() => _isLoading = true);

    try {
      final quantity = _parse(_quantityController.text);

      // Cost basis is always stored as the TOTAL invested.
      // - stock/crypto: avg price per share x quantity
      // - fixed-value (bond/cash/other): value itself, so P&L is 0
      final double costBasis = _isFixedValueType
          ? quantity
          : _parse(_avgPriceController.text) * quantity;

      final account = _accountController.text.trim();

      final inv = Investment(
        id: widget.investmentToEdit?.id,
        userId: user.id,
        type: _selectedType,
        name: _nameController.text,
        symbol: _symbolController.text.isEmpty
            ? null
            : _symbolController.text.toUpperCase(),
        quantity: quantity,
        costBasis: costBasis,
        currency: _selectedCurrency,
        account: account.isEmpty ? null : account,
        // Stock/crypto are always part of the investing portfolio.
        investable: _isFixedValueType ? _investable : true,
      );

      if (widget.investmentToEdit == null) {
        await _backendService.addInvestment(inv.toJson());
      } else {
        await _backendService.updateInvestmentById(inv.id!, inv.toJson());
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('add_investment.saved'.tr())));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'add_investment.error'.tr(namedArgs: {'error': e.toString()}))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isFixedValueType =>
      _selectedType == 'bond' ||
      _selectedType == 'cash' ||
      _selectedType == 'other';

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate

    // Live "total invested" preview for stock/crypto.
    final double qty = _parse(_quantityController.text);
    final double avg = _parse(_avgPriceController.text);
    final double totalInvested = qty * avg;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.investmentToEdit == null
            ? 'add_investment.title_add'.tr()
            : 'add_investment.title_edit'.tr()),
        actions: const [LanguageToggle()],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedType,
                      decoration: InputDecoration(
                          labelText: 'add_investment.type'.tr(),
                          border: const OutlineInputBorder()),
                      items: _types
                          .map((t) => DropdownMenuItem(
                              value: t, child: Text(t.toUpperCase())))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedType = val!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCurrency,
                      decoration: InputDecoration(
                          labelText: 'add_investment.currency'.tr(),
                          border: const OutlineInputBorder()),
                      items: _currencies
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedCurrency = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                    labelText: 'add_investment.name'.tr(),
                    border: const OutlineInputBorder()),
                validator: (v) =>
                    v == null || v.isEmpty ? 'common.required'.tr() : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _symbolController,
                decoration: InputDecoration(
                  labelText: 'add_investment.symbol'.tr(),
                  border: const OutlineInputBorder(),
                  helperText: _isFixedValueType
                      ? 'add_investment.symbol_optional'.tr()
                      : 'add_investment.symbol_required_hint'.tr(),
                ),
                validator: (v) {
                  if (_selectedType == 'stock' || _selectedType == 'crypto') {
                    if (v == null || v.isEmpty) {
                      return 'add_investment.symbol_required_error'.tr();
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _isFixedValueType
                      ? 'add_investment.current_value'.tr()
                      : 'add_investment.quantity'.tr(),
                  border: const OutlineInputBorder(),
                  helperText: _isFixedValueType
                      ? 'add_investment.value_hint'.tr()
                      : 'add_investment.quantity_hint'.tr(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'common.required'.tr() : null,
              ),
              // Avg purchase price (stock/crypto only)
              if (!_isFixedValueType) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _avgPriceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'add_investment.avg_price'.tr(),
                    border: const OutlineInputBorder(),
                    prefixText: '$_selectedCurrency ',
                    helperText: 'add_investment.avg_price_hint'.tr(),
                  ),
                ),
                if (totalInvested > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '${'add_investment.total_invested'.tr()}: $_selectedCurrency ${totalInvested.toStringAsFixed(2)}',
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              // Account label + suggestion chips
              TextFormField(
                controller: _accountController,
                onChanged: (v) {
                  final match = v.trim();
                  if (_accountInvestable.containsKey(match)) {
                    setState(() => _investable = _accountInvestable[match]!);
                  }
                },
                decoration: InputDecoration(
                  labelText: 'add_investment.account'.tr(),
                  border: const OutlineInputBorder(),
                  helperText: 'add_investment.account_hint'.tr(),
                ),
              ),
              if (_accountSuggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _accountSuggestions
                        .map((a) => ActionChip(
                              label: Text(a),
                              onPressed: () => setState(() {
                                _accountController.text = a;
                                if (_accountInvestable.containsKey(a)) {
                                  _investable = _accountInvestable[a]!;
                                }
                              }),
                            ))
                        .toList(),
                  ),
                ),
              // Investable toggle (reserves vs investing) — fixed-value types only
              if (_isFixedValueType) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('add_investment.investable_toggle'.tr()),
                  subtitle: Text('add_investment.investable_sub'.tr()),
                  value: _investable,
                  onChanged: (v) => setState(() => _investable = v),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('common.save'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

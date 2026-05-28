import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../widgets/language_toggle.dart';

class AddInvestmentScreen extends StatefulWidget {
  final UserProfile? currentUser;
  final Investment? investmentToEdit;

  const AddInvestmentScreen({
    super.key,
    this.currentUser,
    this.investmentToEdit,
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
  final _costBasisController = TextEditingController();

  String _selectedType = 'stock';
  final List<String> _types = ['stock', 'crypto', 'bond', 'cash', 'other'];

  String _selectedCurrency = 'BRL';
  final List<String> _currencies = ['BRL', 'USD', 'EUR', 'PLN'];

  @override
  void initState() {
    super.initState();
    if (widget.investmentToEdit != null) {
      final inv = widget.investmentToEdit!;
      _nameController.text = inv.name;
      _symbolController.text = inv.symbol ?? '';
      _quantityController.text = inv.quantity.toString();
      _costBasisController.text = inv.costBasis.toString();
      _selectedType = inv.type;
      _selectedCurrency = inv.currency;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _symbolController.dispose();
    _quantityController.dispose();
    _costBasisController.dispose();
    super.dispose();
  }

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
      final quantity =
          double.parse(_quantityController.text.replaceAll(',', '.'));
      final costBasis =
          double.tryParse(_costBasisController.text.replaceAll(',', '.')) ??
              0.0;

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
              const SizedBox(height: 16),
              TextFormField(
                controller: _costBasisController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'add_investment.cost_basis'.tr(),
                    border: const OutlineInputBorder(),
                    helperText: 'add_investment.cost_basis_hint'.tr()),
              ),
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

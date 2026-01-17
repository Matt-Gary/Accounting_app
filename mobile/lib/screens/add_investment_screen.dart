import 'package:flutter/material.dart';
import '../models/models.dart';
import '../repositories/accounting_repository.dart';

class AddInvestmentScreen extends StatefulWidget {
  final UserProfile? currentUser;
  final Investment? investmentToEdit;

  const AddInvestmentScreen({
    Key? key,
    required this.currentUser,
    this.investmentToEdit,
  }) : super(key: key);

  @override
  State<AddInvestmentScreen> createState() => _AddInvestmentScreenState();
}

class _AddInvestmentScreenState extends State<AddInvestmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = AccountingRepository();
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
    if (widget.currentUser == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No user selected')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final quantity =
          double.parse(_quantityController.text.replaceAll(',', '.'));
      final costBasis =
          double.tryParse(_costBasisController.text.replaceAll(',', '.')) ??
              0.0;

      // Construct Investment object
      // Note: Model expects JSON-friendly mostly, but we can use constructor
      // We need to create a new object or use existing ID
      final inv = Investment(
        id: widget.investmentToEdit?.id,
        userId: widget.currentUser!.id,
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
        await _repository.addInvestment(inv);
      } else {
        await _repository.updateInvestment(inv);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.investmentToEdit == null
            ? 'Add Investment'
            : 'Edit Investment'),
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
                      value: _selectedType,
                      decoration: const InputDecoration(
                          labelText: 'Type', border: OutlineInputBorder()),
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
                      value: _selectedCurrency,
                      decoration: const InputDecoration(
                          labelText: 'Currency', border: OutlineInputBorder()),
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
                decoration: const InputDecoration(
                    labelText: 'Name (e.g. Apple, Bitcoin, Treasury)',
                    border: OutlineInputBorder()),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _symbolController,
                decoration: InputDecoration(
                  labelText: 'Symbol (e.g. AAPL, BTC-USD)',
                  border: const OutlineInputBorder(),
                  helperText: (_selectedType == 'bond' ||
                          _selectedType == 'cash' ||
                          _selectedType == 'other')
                      ? 'Optional'
                      : 'Required for automatic pricing',
                ),
                validator: (v) {
                  if (_selectedType == 'stock' || _selectedType == 'crypto') {
                    if (v == null || v.isEmpty)
                      return 'Required for Stocks/Crypto';
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
                  labelText: (_selectedType == 'bond' ||
                          _selectedType == 'cash' ||
                          _selectedType == 'other')
                      ? 'Current Value'
                      : 'Quantity',
                  border: const OutlineInputBorder(),
                  helperText: (_selectedType == 'bond' ||
                          _selectedType == 'cash' ||
                          _selectedType == 'other')
                      ? 'Enter the total monetary value'
                      : 'Number of shares/units',
                ),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _costBasisController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Total Cost Basis (Optional)',
                    border: OutlineInputBorder(),
                    helperText: 'Used to calculate Profit/Loss'),
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
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

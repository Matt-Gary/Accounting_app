import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/backend_service.dart';

class EditExpenseScreen extends StatefulWidget {
  final Map<String, dynamic> expense;

  const EditExpenseScreen({super.key, required this.expense});

  @override
  State<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _backendService = BackendService();

  UserProfile? _selectedUser;
  Category? _selectedCategory;
  PaymentMethod? _selectedPaymentMethod;
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  late DateTime _spentAt;
  bool _isLoading = false;

  List<UserProfile> _users = [];
  List<Category> _categories = [];
  List<PaymentMethod> _paymentMethods = [];

  @override
  void initState() {
    super.initState();
    _spentAt = DateTime.parse(widget.expense['spent_at']);
    _amountController.text =
        (widget.expense['amount'] as num).toDouble().toStringAsFixed(2);
    _commentController.text = widget.expense['comment'] ?? '';
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.expense['recurring_id'] != null) return;
    try {
      final familyData = await _backendService.getFamilyData();
      if (mounted) {
        setState(() {
          _users = familyData.profiles;
          _categories = familyData.categories;
          _paymentMethods = familyData.paymentMethods;

          _selectedUser = _users.firstWhere(
            (u) => u.id == widget.expense['user_id'],
            orElse: () => _users.isNotEmpty ? _users.first : _users.first,
          );
          _selectedCategory = _categories.firstWhere(
            (c) => c.key == widget.expense['category_key'],
            orElse: () =>
                _categories.isNotEmpty ? _categories.first : _categories.first,
          );
          _selectedPaymentMethod = _paymentMethods.firstWhere(
            (p) => p.id == widget.expense['payment_method_id'],
            orElse: () => _paymentMethods.isNotEmpty
                ? _paymentMethods.first
                : _paymentMethods.first,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUser == null ||
        _selectedCategory == null ||
        _selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select all required fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', '.'));
      final comment = _commentController.text.trim();

      final updated = await _backendService.updateExpense(
        widget.expense['id'],
        {
          'amount': amount,
          'category_key': _selectedCategory!.key,
          'payment_method_id': _selectedPaymentMethod!.id,
          'spent_at': _spentAt.toIso8601String(),
          'comment': comment.isEmpty ? null : comment,
          'user_id': _selectedUser!.id,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense updated successfully')),
        );
        // Merge raw DB response with display-friendly labels from the selected
        // dropdown objects so the details screen refreshes without a round-trip.
        final enriched = {
          ...widget.expense,
          ...updated,
          'category_label': _selectedCategory!.label,
          'payment_method_name': _selectedPaymentMethod!.name,
          'user_name': _selectedUser!.name,
        };
        Navigator.pop(context, enriched);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating expense: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expense['recurring_id'] != null) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title:
              const Text('Edit Expense', style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.repeat, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text(
                  'Cannot Edit Recurring Expense',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This expense is auto-generated from a recurring definition. '
                  'To change its values, edit the recurring expense in Recurring Expenses settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_users.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title:
              const Text('Edit Expense', style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title:
            const Text('Edit Expense', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Amount
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Amount',
                          style: TextStyle(color: Colors.grey)),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          prefixText: 'R\$ ',
                          border: InputBorder.none,
                          hintText: '0.00',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Required';
                          if (double.tryParse(value.replaceAll(',', '.')) ==
                              null) {
                            return 'Invalid amount';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              const Text('Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              _buildDropdown<UserProfile>(
                label: 'User',
                value: _selectedUser,
                items: _users,
                itemLabel: (u) => u.name,
                onChanged: (val) => setState(() => _selectedUser = val),
              ),

              _buildDropdown<Category>(
                label: 'Category',
                value: _selectedCategory,
                items: _categories,
                itemLabel: (c) => c.label,
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),

              _buildDropdown<PaymentMethod>(
                label: 'Payment Method',
                value: _selectedPaymentMethod,
                items: _paymentMethods,
                itemLabel: (p) => p.name,
                onChanged: (val) =>
                    setState(() => _selectedPaymentMethod = val),
              ),

              // Date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(DateFormat('EEE, MMM d, yyyy').format(_spentAt)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _spentAt,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _spentAt = picked);
                },
              ),
              const Divider(),

              // Comment
              TextFormField(
                controller: _commentController,
                decoration: const InputDecoration(
                  labelText: 'Comment (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Changes',
                          style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) itemLabel,
    required Function(T?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.white,
        ),
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(itemLabel(item)),
          );
        }).toList(),
        onChanged: onChanged,
        validator: (value) => value == null ? 'Required' : null,
      ),
    );
  }
}

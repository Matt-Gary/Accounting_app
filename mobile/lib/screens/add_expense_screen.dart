import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../repositories/accounting_repository.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = AccountingRepository();

  // Form State
  UserProfile? _selectedUser;
  Category? _selectedCategory;
  PaymentMethod? _selectedPaymentMethod;
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  final _installmentsController = TextEditingController();
  DateTime _spentAt = DateTime.now();
  bool _isLoading = false;

  // Data
  List<UserProfile> _users = [];
  List<Category> _categories = [];
  List<PaymentMethod> _paymentMethods = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final users = await _repository.getProfiles();
      final categories = await _repository.getCategories();
      final methods = await _repository.getPaymentMethods();

      if (mounted) {
        setState(() {
          _users = users;
          _categories = categories;
          _paymentMethods = methods;

          // Defaults if available
          if (_users.isNotEmpty) _selectedUser = _users.first;
          if (_paymentMethods.isNotEmpty)
            _selectedPaymentMethod = _paymentMethods.first;
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

  DateTime _addMonths(DateTime date, int months) {
    int year = date.year + (date.month + months - 1) ~/ 12;
    int month = (date.month + months - 1) % 12 + 1;
    int day = date.day;
    int lastDayOfNewMonth = DateTime(year, month + 1, 0).day;
    if (day > lastDayOfNewMonth) {
      day = lastDayOfNewMonth;
    }
    return DateTime(year, month, day, date.hour, date.minute, date.second);
  }

  Future<void> _submit() async {
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
      final installmentsStr = _installmentsController.text.trim();
      final installments =
          (installmentsStr.isEmpty) ? 0 : int.tryParse(installmentsStr) ?? 0;

      final baseComment = _commentController.text.trim();

      if (installments > 1) {
        final List<Expense> expenses = [];
        final double installmentAmount =
            (amount / installments).floorToDouble();
        final double lastInstallmentAmount =
            amount - (installmentAmount * (installments - 1));

        for (int i = 0; i < installments; i++) {
          final isLast = i == installments - 1;
          final currentAmount =
              isLast ? lastInstallmentAmount : installmentAmount;
          final installmentDate = _addMonths(_spentAt, i);

          final commentSuffix = "(${i + 1}/$installments)";
          final finalComment = baseComment.isEmpty
              ? commentSuffix
              : "$baseComment $commentSuffix";

          expenses.add(Expense(
            userId: _selectedUser!.id,
            amount: currentAmount,
            categoryKey: _selectedCategory!.key,
            paymentMethodId: _selectedPaymentMethod!.id,
            spentAt: installmentDate,
            comment: finalComment,
            installments: installments,
          ));
        }

        await _repository.addExpenses(expenses);
      } else {
        final expense = Expense(
          userId: _selectedUser!.id,
          amount: amount,
          categoryKey: _selectedCategory!.key,
          paymentMethodId: _selectedPaymentMethod!.id,
          spentAt: _spentAt,
          comment: baseComment.isEmpty ? null : baseComment,
          installments: installments,
        );

        await _repository.addExpense(expense);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense added successfully!')),
        );
        Navigator.pop(context); // Go back home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding expense: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('New Expense', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _users.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Amount Input
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: const TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.bold),
                              decoration: const InputDecoration(
                                prefixText: 'R\$ ',
                                border: InputBorder.none,
                                hintText: '0.00',
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty)
                                  return 'Required';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Details Form
                    const Text('Details',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // User Dropdown
                    _buildDropdown<UserProfile>(
                      label: 'User',
                      value: _selectedUser,
                      items: _users,
                      itemLabel: (u) => u.name,
                      onChanged: (val) => setState(() => _selectedUser = val),
                    ),

                    // Category Dropdown
                    _buildDropdown<Category>(
                      label: 'Category',
                      value: _selectedCategory,
                      items: _categories,
                      itemLabel: (c) => c.label,
                      onChanged: (val) =>
                          setState(() => _selectedCategory = val),
                    ),

                    // Payment Method Dropdown
                    _buildDropdown<PaymentMethod>(
                      label: 'Payment Method',
                      value: _selectedPaymentMethod,
                      items: _paymentMethods,
                      itemLabel: (p) => p.name,
                      onChanged: (val) =>
                          setState(() => _selectedPaymentMethod = val),
                    ),

                    // Date Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date'),
                      subtitle:
                          Text(DateFormat('EEE, MMM d, yyyy').format(_spentAt)),
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

                    // Comment Input
                    TextFormField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        labelText: 'Comment (Optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Installments Input
                    TextFormField(
                      controller: _installmentsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Installments (Optional)',
                        hintText: 'e.g. 5',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.repeat),
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('Save Expense',
                                style: TextStyle(
                                    fontSize: 18, color: Colors.white)),
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
        value: value,
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
      ),
    );
  }
}

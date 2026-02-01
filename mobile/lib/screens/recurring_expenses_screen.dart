import 'package:flutter/material.dart';
import '../models/models.dart';
import '../repositories/accounting_repository.dart';

class RecurringExpensesScreen extends StatefulWidget {
  const RecurringExpensesScreen({super.key});

  @override
  State<RecurringExpensesScreen> createState() =>
      _RecurringExpensesScreenState();
}

class _RecurringExpensesScreenState extends State<RecurringExpensesScreen> {
  final _repository = AccountingRepository();
  bool _isLoading = false;
  List<RecurringExpense> _recurringExpenses = [];
  List<UserProfile> _users = [];
  List<Category> _categories = [];
  List<PaymentMethod> _paymentMethods = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final recurring = await _repository.getRecurringExpenses();
      final users = await _repository.getProfiles();
      final cats = await _repository.getCategories();
      final methods = await _repository.getPaymentMethods();

      setState(() {
        _recurringExpenses = recurring;
        _users = users;
        _categories = cats;
        _paymentMethods = methods;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecurring(RecurringExpense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Recurring Expense?'),
        content: const Text(
            'This will stop future expenses from being generated. Past expenses will remain.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true && expense.id != null) {
      try {
        await _repository.deleteRecurringExpense(expense.id!);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e')),
          );
        }
      }
    }
  }

  void _showForm([RecurringExpense? expense]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecurringForm(
        expense: expense,
        users: _users,
        categories: _categories,
        paymentMethods: _paymentMethods,
        onSave: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recurring Expenses'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recurringExpenses.isEmpty
              ? const Center(child: Text('No recurring expenses set up.'))
              : ListView.builder(
                  itemCount: _recurringExpenses.length,
                  itemBuilder: (ctx, i) {
                    final item = _recurringExpenses[i];
                    final cat = _categories
                        .firstWhere((c) => c.key == item.categoryKey,
                            orElse: () => Category(
                                key: 'unknown',
                                label: 'Unknown',
                                sortOrder: 999))
                        .label;
                    final user = _users
                        .firstWhere((u) => u.id == item.userId,
                            orElse: () =>
                                UserProfile(id: '?', name: '?', email: ''))
                        .name;
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(item.dayOfMonth.toString()),
                        backgroundColor:
                            item.active ? Colors.blue : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                      title: Text(item.description ?? cat),
                      subtitle:
                          Text('$user • R\$ ${item.amount.toStringAsFixed(2)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: item.active,
                            onChanged: (val) async {
                              final updated = RecurringExpense(
                                id: item.id,
                                userId: item.userId,
                                amount: item.amount,
                                categoryKey: item.categoryKey,
                                paymentMethodId: item.paymentMethodId,
                                description: item.description,
                                dayOfMonth: item.dayOfMonth,
                                active: val,
                                createdAt: item.createdAt,
                              );
                              await _repository.updateRecurringExpense(updated);
                              _loadData();
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showForm(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteRecurring(item),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class RecurringForm extends StatefulWidget {
  final RecurringExpense? expense;
  final List<UserProfile> users;
  final List<Category> categories;
  final List<PaymentMethod> paymentMethods;
  final VoidCallback onSave;

  const RecurringForm({
    super.key,
    this.expense,
    required this.users,
    required this.categories,
    required this.paymentMethods,
    required this.onSave,
  });

  @override
  State<RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<RecurringForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _dayController = TextEditingController();
  final _repository = AccountingRepository();

  late UserProfile _selectedUser;
  late Category _selectedCategory;
  late PaymentMethod _selectedPaymentMethod;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.users.isNotEmpty) _selectedUser = widget.users.first;
    if (widget.categories.isNotEmpty)
      _selectedCategory = widget.categories.first;
    if (widget.paymentMethods.isNotEmpty)
      _selectedPaymentMethod = widget.paymentMethods.first;

    if (widget.expense != null) {
      _amountController.text = widget.expense!.amount.toString();
      _descController.text = widget.expense!.description ?? '';
      _dayController.text = widget.expense!.dayOfMonth.toString();
      if (widget.users.any((u) => u.id == widget.expense!.userId)) {
        _selectedUser =
            widget.users.firstWhere((u) => u.id == widget.expense!.userId);
      }
      if (widget.categories.any((c) => c.key == widget.expense!.categoryKey)) {
        _selectedCategory = widget.categories
            .firstWhere((c) => c.key == widget.expense!.categoryKey);
      }
      if (widget.paymentMethods
          .any((p) => p.id == widget.expense!.paymentMethodId)) {
        _selectedPaymentMethod = widget.paymentMethods
            .firstWhere((p) => p.id == widget.expense!.paymentMethodId);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', '.'));
      final day = int.parse(_dayController.text);

      final expense = RecurringExpense(
        id: widget.expense?.id,
        userId: _selectedUser.id,
        amount: amount,
        categoryKey: _selectedCategory.key,
        paymentMethodId: _selectedPaymentMethod.id,
        description: _descController.text.isEmpty ? null : _descController.text,
        dayOfMonth: day,
        active: widget.expense?.active ?? true,
        createdAt: widget.expense?.createdAt,
      );

      if (widget.expense == null) {
        await _repository.addRecurringExpense(expense);
      } else {
        await _repository.updateRecurringExpense(expense);
      }

      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recurring Expense Details',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount', prefixText: r'R$ '),
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                  labelText: 'Description (e.g. Condominio)'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _dayController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Day of Month (1-31)'),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Required';
                final n = int.tryParse(v);
                if (n == null || n < 1 || n > 31) return 'Invalid day';
                return null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<UserProfile>(
              value: _selectedUser,
              decoration: const InputDecoration(labelText: 'User'),
              items: widget.users
                  .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                  .toList(),
              onChanged: (u) => setState(() => _selectedUser = u!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Category>(
              value: _selectedCategory,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                  .toList(),
              onChanged: (c) => setState(() => _selectedCategory = c!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<PaymentMethod>(
              value: _selectedPaymentMethod,
              decoration: const InputDecoration(labelText: 'Payment Method'),
              items: widget.paymentMethods
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (p) => setState(() => _selectedPaymentMethod = p!),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Save'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

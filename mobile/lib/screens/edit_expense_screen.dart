import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../utils/error_text.dart';
import '../utils/money_format.dart';

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
  String? _loadError;

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
      if (!mounted) return;

      // The expense may point at a category that has since been hidden, a
      // payment method that was removed, or a member who left. Substituting
      // "the first one in the list" (what this screen used to do) silently
      // re-categorised the expense on the next save — even when the user only
      // meant to fix the amount. Keep the original value as an extra option
      // instead, labelled from the expense row itself.
      final expense = widget.expense;
      final users = [...familyData.profiles];
      final categories = [...familyData.categories];
      final methods = [...familyData.paymentMethods];

      UserProfile? user;
      for (final u in users) {
        if (u.id == expense['user_id']) user = u;
      }
      if (user == null && expense['user_id'] != null) {
        user = UserProfile(
          id: expense['user_id'] as String,
          name: (expense['user_name'] as String?) ?? 'common.unknown'.tr(),
        );
        users.add(user);
      }

      Category? category;
      for (final c in categories) {
        if (c.key == expense['category_key']) category = c;
      }
      if (category == null && expense['category_key'] != null) {
        category = Category(
          key: expense['category_key'] as String,
          label: (expense['category_label'] as String?) ??
              expense['category_key'] as String,
          sortOrder: 999,
        );
        categories.add(category);
      }

      PaymentMethod? method;
      for (final p in methods) {
        if (p.id == expense['payment_method_id']) method = p;
      }
      if (method == null && expense['payment_method_id'] != null) {
        method = PaymentMethod(
          id: expense['payment_method_id'] as String,
          name: (expense['payment_method_name'] as String?) ??
              'common.unknown'.tr(),
          isCreditCard: false,
        );
        methods.add(method);
      }

      setState(() {
        _users = users;
        _categories = categories;
        _paymentMethods = methods;
        _selectedUser = user;
        _selectedCategory = category;
        _selectedPaymentMethod = method;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'edit_expense.load_failed'
          .tr(namedArgs: {'error': errorText(e)}));
    }
  }

  String _categoryLabel(Category c) {
    if (!c.isGlobal) return c.label;
    final k = 'categories.${c.key}';
    final t = k.tr();
    return t == k ? c.label : t;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUser == null ||
        _selectedCategory == null ||
        _selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.select_all_fields'.tr())),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final amount = parseAmount(_amountController.text)!; // validated above
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
          SnackBar(content: Text('edit_expense.updated'.tr())),
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
          SnackBar(
              content: Text('edit_expense.update_failed'
                  .tr(namedArgs: {'error': errorText(e)}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        title: Text('edit_expense.title'.tr(),
            style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      );

  Widget _buildMessage({
    required IconData icon,
    required Color iconColor,
    String? title,
    required String body,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor),
            const SizedBox(height: 16),
            if (title != null) ...[
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate

    if (widget.expense['recurring_id'] != null) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: _buildMessage(
          icon: Icons.repeat,
          iconColor: Colors.orange,
          title: 'edit_expense.recurring_title'.tr(),
          body: 'edit_expense.recurring_body'.tr(),
          actionLabel: 'common.back'.tr(),
          onAction: () => Navigator.pop(context),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: _buildMessage(
          icon: Icons.error_outline,
          iconColor: Colors.red,
          body: _loadError!,
          actionLabel: 'common.retry'.tr(),
          onAction: () {
            setState(() => _loadError = null);
            _loadData();
          },
        ),
      );
    }

    if (_users.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // A future-dated row (a later installment) must stay selectable: the
    // picker rejects an initial date after its last date.
    final now = DateTime.now();
    final lastDate = _spentAt.isAfter(now) ? _spentAt : now;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
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
                      Text('add_expense.amount'.tr(),
                          style: const TextStyle(color: Colors.grey)),
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          prefixText: '${currencySymbol(expenseCurrency)} ',
                          border: InputBorder.none,
                          hintText: '0,00',
                        ),
                        validator: validateAmount,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text('add_expense.details'.tr(),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              _buildDropdown<UserProfile>(
                label: 'add_expense.user'.tr(),
                value: _selectedUser,
                items: _users,
                itemLabel: (u) => u.name,
                onChanged: (val) => setState(() => _selectedUser = val),
              ),

              _buildDropdown<Category>(
                label: 'add_expense.category'.tr(),
                value: _selectedCategory,
                items: _categories,
                itemLabel: _categoryLabel,
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),

              _buildDropdown<PaymentMethod>(
                label: 'add_expense.payment_method'.tr(),
                value: _selectedPaymentMethod,
                items: _paymentMethods,
                itemLabel: (p) => p.name,
                onChanged: (val) =>
                    setState(() => _selectedPaymentMethod = val),
              ),

              // Date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('add_expense.date'.tr()),
                subtitle: Text(DateFormat('EEE, MMM d, yyyy').format(_spentAt)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _spentAt,
                    firstDate: DateTime(2020),
                    lastDate: lastDate,
                  );
                  if (picked != null) setState(() => _spentAt = picked);
                },
              ),
              const Divider(),

              // Comment
              TextFormField(
                controller: _commentController,
                decoration: InputDecoration(
                  labelText: 'add_expense.comment_optional'.tr(),
                  border: const OutlineInputBorder(),
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
                      : Text('edit_expense.save'.tr(),
                          style: const TextStyle(
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
        validator: (value) => value == null ? 'common.required'.tr() : null,
      ),
    );
  }
}

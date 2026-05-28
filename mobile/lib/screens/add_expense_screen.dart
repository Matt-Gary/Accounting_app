import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../widgets/language_toggle.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _backendService = BackendService();

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
  String? _favoritePaymentMethodId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String? _loadError;

  Future<void> _loadData() async {
    try {
      final familyData =
          await _backendService.getFamilyData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _users = familyData.profiles;
        _categories = familyData.categories;
        _paymentMethods = familyData.paymentMethods;
        if (_users.isNotEmpty) _selectedUser = _users.first;
        if (_paymentMethods.isNotEmpty) {
          final currentProfile = familyData.profiles.firstWhere(
            (p) => p.id == familyData.currentProfileId,
            orElse: () => familyData.profiles.first,
          );
          _favoritePaymentMethodId = currentProfile.defaultPaymentMethodId;
          final favId = _favoritePaymentMethodId;
          _selectedPaymentMethod = favId != null
              ? _paymentMethods.firstWhere(
                  (pm) => pm.id == favId,
                  orElse: () => _paymentMethods.first,
                )
              : _paymentMethods.first;
        }
        _loadError = _users.isEmpty ? 'add_expense.no_users'.tr() : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError =
          'add_expense.load_failed'.tr(namedArgs: {'error': e.toString()}));
    }
  }

  Future<bool?> _askInstallmentStartMonth(int installments) {
    final thisMonthLabel = DateFormat('MMMM yyyy').format(_spentAt);
    final nextMonthLabel = DateFormat('MMMM yyyy')
        .format(DateTime(_spentAt.year, _spentAt.month + 1, 1));
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('add_expense.first_installment_title'.tr()),
        content: Text(
          'add_expense.first_installment_body'
              .tr(namedArgs: {'count': installments.toString()}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('add_expense.next_month'
                .tr(namedArgs: {'month': nextMonthLabel})),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('add_expense.this_month'
                .tr(namedArgs: {'month': thisMonthLabel})),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUser == null ||
        _selectedCategory == null ||
        _selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.select_all_fields'.tr())),
      );
      return;
    }

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', '.'));
      final installmentsStr = _installmentsController.text.trim();
      final installments =
          (installmentsStr.isEmpty) ? 0 : int.tryParse(installmentsStr) ?? 0;

      final baseComment = _commentController.text.trim();

      if (installments > 1) {
        // Credit cards: ask the user which bill installment 1 belongs to.
        // Cash/Pix have no closing-day concept, so keep #1 on spent_at.
        bool startThisMonth = true;
        if (_selectedPaymentMethod!.isCreditCard) {
          final answer = await _askInstallmentStartMonth(installments);
          if (answer == null) return;
          startThisMonth = answer;
        }

        setState(() => _isLoading = true);

        final List<Expense> expenses = [];
        // Round to 2 decimal places (e.g. 15 / 4 = 3.75)
        final double installmentAmount =
            (amount / installments * 100).round() / 100;
        // Last installment absorbs any rounding remainder to keep total exact
        final double lastInstallmentAmount = double.parse(
            (amount - (installmentAmount * (installments - 1)))
                .toStringAsFixed(2));

        // Installments 2..N always land on the 1st of subsequent months so
        // the billing period is unambiguous regardless of closing-day drift.
        final DateTime firstInstallmentDate = startThisMonth
            ? _spentAt
            : DateTime(_spentAt.year, _spentAt.month + 1, 1);
        final DateTime firstBillingMonth = startThisMonth
            ? DateTime(_spentAt.year, _spentAt.month, 1)
            : firstInstallmentDate;

        for (int i = 0; i < installments; i++) {
          final isLast = i == installments - 1;
          final currentAmount =
              isLast ? lastInstallmentAmount : installmentAmount;
          final installmentDate = i == 0
              ? firstInstallmentDate
              : DateTime(
                  firstBillingMonth.year, firstBillingMonth.month + i, 1);

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

        await _backendService
            .addExpenses(expenses.map((e) => e.toJson()).toList());
      } else {
        setState(() => _isLoading = true);

        final expense = Expense(
          userId: _selectedUser!.id,
          amount: amount,
          categoryKey: _selectedCategory!.key,
          paymentMethodId: _selectedPaymentMethod!.id,
          spentAt: _spentAt,
          comment: baseComment.isEmpty ? null : baseComment,
          installments: installments,
        );

        await _backendService.addExpense(expense.toJson());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('add_expense.added_success'.tr())),
        );
        Navigator.pop(context); // Go back home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('add_expense.add_failed'
                  .tr(namedArgs: {'error': e.toString()}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('add_expense.title'.tr(),
            style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: const [LanguageToggle()],
      ),
      body: _users.isEmpty
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 16),
                          ElevatedButton(
                              onPressed: () {
                                setState(() => _loadError = null);
                                _loadData();
                              },
                              child: Text('common.retry'.tr())),
                        ],
                      ),
                    ),
            )
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
                            Text('add_expense.amount'.tr(),
                                style: const TextStyle(color: Colors.grey)),
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
                                if (value == null || value.isEmpty) {
                                  return 'common.required'.tr();
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Details Form
                    Text('add_expense.details'.tr(),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),

                    // User Dropdown
                    _buildDropdown<UserProfile>(
                      label: 'add_expense.user'.tr(),
                      value: _selectedUser,
                      items: _users,
                      itemLabel: (u) => u.name,
                      onChanged: (val) => setState(() => _selectedUser = val),
                    ),

                    // Category Dropdown
                    _buildDropdown<Category>(
                      label: 'add_expense.category'.tr(),
                      value: _selectedCategory,
                      items: _categories,
                      itemLabel: (c) {
                        if (!c.isGlobal) return c.label;
                        final k = 'categories.${c.key}';
                        final t = k.tr();
                        return t == k ? c.label : t;
                      },
                      onChanged: (val) =>
                          setState(() => _selectedCategory = val),
                    ),

                    // Payment Method Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('add_expense.payment_method'.tr()),
                      subtitle: Text(_selectedPaymentMethod?.name ?? '—'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedPaymentMethod?.id ==
                              _favoritePaymentMethodId)
                            const Icon(Icons.star,
                                color: Colors.amber, size: 18),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                      onTap: _showPaymentMethodPicker,
                    ),

                    // Date Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('add_expense.date'.tr()),
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
                      decoration: InputDecoration(
                        labelText: 'add_expense.comment_optional'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Installments Input
                    TextFormField(
                      controller: _installmentsController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'add_expense.installments_optional'.tr(),
                        hintText: 'add_expense.installments_hint'.tr(),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.repeat),
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
                            : Text('add_expense.save'.tr(),
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

  void _showPaymentMethodPicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => ListView(
          children: _paymentMethods.map((pm) {
            final isFav = pm.id == _favoritePaymentMethodId;
            final isSelected = pm.id == _selectedPaymentMethod?.id;
            return ListTile(
              leading: Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
              ),
              title: Text(pm.name),
              onTap: () {
                setState(() => _selectedPaymentMethod = pm);
                Navigator.pop(ctx);
              },
              trailing: IconButton(
                icon: Icon(
                  isFav ? Icons.star : Icons.star_border,
                  color: isFav ? Colors.amber : null,
                ),
                onPressed: () async {
                  final newFav = isFav ? null : pm.id;
                  final previous = _favoritePaymentMethodId;
                  setState(() => _favoritePaymentMethodId = newFav);
                  setLocal(() {});
                  try {
                    await _backendService.setFavoritePaymentMethod(newFav);
                  } catch (e) {
                    setState(() => _favoritePaymentMethodId = previous);
                    setLocal(() {});
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
              ),
            );
          }).toList(),
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

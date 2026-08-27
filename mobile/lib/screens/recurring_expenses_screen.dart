import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../widgets/language_toggle.dart';

/// Translates a category label — global categories use the categories.* JSON
/// namespace; user-created categories keep their raw DB label.
String _translateCategoryLabel(Category c) {
  if (!c.isGlobal) return c.label;
  final k = 'categories.${c.key}';
  final t = k.tr();
  return t == k ? c.label : t;
}

class RecurringExpensesScreen extends StatefulWidget {
  const RecurringExpensesScreen({super.key});

  @override
  State<RecurringExpensesScreen> createState() =>
      _RecurringExpensesScreenState();
}

class _RecurringExpensesScreenState extends State<RecurringExpensesScreen> {
  final _backendService = BackendService();
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
      final results = await Future.wait([
        _backendService.getRecurringExpenses(),
        _backendService.getFamilyData(),
      ]);
      final rawRecurring = results[0] as List<Map<String, dynamic>>;
      final familyData = results[1] as FamilyData;

      setState(() {
        _recurringExpenses =
            rawRecurring.map((e) => RecurringExpense.fromJson(e)).toList();
        // Includes the family-level virtual profile ("General") so a shared bill
        // (rent, internet) can be recurring without being charged to one person.
        // Backend orders real profiles first, so `_users.first` stays a human.
        _users = familyData.profiles;
        _categories = familyData.categories;
        _paymentMethods = familyData.paymentMethods;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('recurring.load_error'
                  .tr(namedArgs: {'error': e.toString()}))),
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
        title: Text('recurring.delete_title'.tr()),
        content: Text('recurring.delete_body'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('common.cancel'.tr())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('common.delete'.tr(),
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true && expense.id != null) {
      try {
        await _backendService.deleteRecurringExpense(expense.id!);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('recurring.delete_error'
                    .tr(namedArgs: {'error': e.toString()}))),
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
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    return Scaffold(
      appBar: AppBar(
        title: Text('recurring.title'.tr()),
        actions: const [LanguageToggle()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recurringExpenses.isEmpty
              ? Center(child: Text('recurring.empty'.tr()))
              : ListView.builder(
                  itemCount: _recurringExpenses.length,
                  itemBuilder: (ctx, i) {
                    final item = _recurringExpenses[i];
                    final categoryObj = _categories.firstWhere(
                        (c) => c.key == item.categoryKey,
                        orElse: () => Category(
                            key: 'unknown',
                            label: 'Unknown',
                            sortOrder: 999));
                    final catLabel = _translateCategoryLabel(categoryObj);
                    final user = _users
                        .firstWhere((u) => u.id == item.userId,
                            orElse: () =>
                                UserProfile(id: '?', name: '?', email: ''))
                        .name;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            item.active ? Colors.blue : Colors.grey,
                        foregroundColor: Colors.white,
                        child: Text(item.dayOfMonth.toString()),
                      ),
                      title: Text(item.description ?? catLabel),
                      subtitle: Text('recurring.item_subtitle'.tr(
                          namedArgs: {
                            'user': user,
                            'amount': item.amount.toStringAsFixed(2)
                          })),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: item.active,
                            onChanged: (val) async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await _backendService.updateRecurringExpense(
                                  item.id!,
                                  {'active': val},
                                );
                                _loadData();
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                      content: Text('recurring.error'.tr(
                                          namedArgs: {
                                            'error': e.toString()
                                          }))),
                                );
                              }
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
  final _backendService = BackendService();

  late UserProfile _selectedUser;
  late Category _selectedCategory;
  late PaymentMethod _selectedPaymentMethod;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.users.isNotEmpty) _selectedUser = widget.users.first;
    if (widget.categories.isNotEmpty) {
      _selectedCategory = widget.categories.first;
    }
    if (widget.paymentMethods.isNotEmpty) {
      _selectedPaymentMethod = widget.paymentMethods.first;
    }

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
        description:
            _descController.text.isEmpty ? null : _descController.text,
        dayOfMonth: day,
        active: widget.expense?.active ?? true,
        createdAt: widget.expense?.createdAt,
      );

      if (widget.expense == null) {
        await _backendService.addRecurringExpense(expense.toJson());
      } else {
        await _backendService.updateRecurringExpense(
          widget.expense!.id!,
          expense.toJson(),
        );
      }

      widget.onSave();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'recurring.error'.tr(namedArgs: {'error': e.toString()}))));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
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
            Text('recurring.form_title'.tr(),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'recurring.amount'.tr(), prefixText: r'R$ '),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'common.required'.tr() : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descController,
              decoration: InputDecoration(
                  labelText: 'recurring.description'.tr()),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _dayController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: 'recurring.day_of_month'.tr()),
              validator: (v) {
                if (v == null || v.isEmpty) return 'common.required'.tr();
                final n = int.tryParse(v);
                if (n == null || n < 1 || n > 31) {
                  return 'recurring.invalid_day'.tr();
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<UserProfile>(
              initialValue: _selectedUser,
              decoration: InputDecoration(labelText: 'recurring.user'.tr()),
              items: widget.users
                  .map((u) => DropdownMenuItem(value: u, child: Text(u.name)))
                  .toList(),
              onChanged: (u) => setState(() => _selectedUser = u!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<Category>(
              initialValue: _selectedCategory,
              decoration:
                  InputDecoration(labelText: 'recurring.category'.tr()),
              items: widget.categories
                  .map((c) => DropdownMenuItem(
                      value: c, child: Text(_translateCategoryLabel(c))))
                  .toList(),
              onChanged: (c) => setState(() => _selectedCategory = c!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _selectedPaymentMethod,
              decoration: InputDecoration(
                  labelText: 'recurring.payment_method'.tr()),
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
                    : Text('common.save'.tr()),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/backend_service.dart';
import '../utils/category_icons.dart';
import '../utils/error_text.dart';
import '../utils/installments.dart';
import '../utils/money_format.dart';
import '../widgets/language_toggle.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  static const _maxInstallments = 48;

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

  /// Push the whole installment series one bill later (credit cards only).
  bool _deferFirst = false;

  /// Closing-day override stored for the month of [_spentAt], if any. It beats
  /// the card's own closing day — the same priority the backend applies.
  int? _monthOverride;
  int _overrideSeq = 0;

  // Data
  List<UserProfile> _users = [];
  List<Category> _categories = [];
  List<PaymentMethod> _paymentMethods = [];
  String? _favoritePaymentMethodId;

  String? _loadError;

  @override
  void initState() {
    super.initState();
    // The installment preview depends on both fields, so it follows typing.
    _amountController.addListener(_onInputChanged);
    _installmentsController.addListener(_onInputChanged);
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    _installmentsController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    try {
      final familyData =
          await _backendService.getFamilyData(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _users = familyData.profiles;
        _categories = familyData.categories;
        _paymentMethods = familyData.paymentMethods;
        if (_users.isNotEmpty) {
          // Default to whoever is logged in. `_users.first` is merely the
          // first name alphabetically, so in a two-person family half the
          // expenses were attributed to the wrong person by default.
          final currentProfile = _users.firstWhere(
            (p) => p.id == familyData.currentProfileId,
            orElse: () => _users.first,
          );
          _selectedUser = currentProfile;
          if (_paymentMethods.isNotEmpty) {
            _favoritePaymentMethodId = currentProfile.defaultPaymentMethodId;
            final favId = _favoritePaymentMethodId;
            _selectedPaymentMethod = favId != null
                ? _paymentMethods.firstWhere(
                    (pm) => pm.id == favId,
                    orElse: () => _paymentMethods.first,
                  )
                : _paymentMethods.first;
          }
        }
        _loadError = _users.isEmpty ? 'add_expense.no_users'.tr() : null;
      });
      _refreshClosingOverride();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'add_expense.load_failed'
          .tr(namedArgs: {'error': errorText(e)}));
    }
  }

  // ── Closing day ────────────────────────────────────────────────────────────

  /// Keeps [_monthOverride] in step with the chosen date and payment method,
  /// so the installment preview names the right bill.
  Future<void> _refreshClosingOverride() async {
    final seq = ++_overrideSeq;
    final pm = _selectedPaymentMethod;
    if (pm == null || !pm.isCreditCard) {
      if (_monthOverride != null) setState(() => _monthOverride = null);
      return;
    }
    final override = await _fetchOverride();
    // A newer date/method change is already in flight — its answer wins.
    if (!mounted || seq != _overrideSeq) return;
    setState(() => _monthOverride = override);
  }

  Future<int?> _fetchOverride() async {
    try {
      return await _backendService.getClosingDayOverride(
          _spentAt.month, _spentAt.year);
    } catch (_) {
      // Best effort: without it the card's own closing day applies.
      return null;
    }
  }

  int _closingDayFor(PaymentMethod pm, int? monthOverride) =>
      monthOverride ?? pm.closingDay ?? defaultClosingDay;

  // ── Installments ───────────────────────────────────────────────────────────

  /// Installment count typed by the user; 0 when empty or not a number.
  int get _installmentCount =>
      int.tryParse(_installmentsController.text.trim()) ?? 0;

  InstallmentPlan? _previewPlan() {
    final pm = _selectedPaymentMethod;
    final amount = parseAmount(_amountController.text);
    final count = _installmentCount;
    if (pm == null || amount == null || amount <= 0) return null;
    if (count < 2 || count > _maxInstallments) return null;
    return planInstallments(
      total: amount,
      count: count,
      spentAt: _spentAt,
      isCreditCard: pm.isCreditCard,
      closingDay: _closingDayFor(pm, _monthOverride),
      deferFirst: _deferFirst && pm.isCreditCard,
    );
  }

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit({bool addAnother = false}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUser == null ||
        _selectedCategory == null ||
        _selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.select_all_fields'.tr())),
      );
      return;
    }

    // Both validated by the form above.
    final amount = parseAmount(_amountController.text)!;
    final installments = _installmentCount;
    final pm = _selectedPaymentMethod!;
    final baseComment = _commentController.text.trim();

    // Each installment must be at least one cent.
    if (installments > 1 && (amount * 100).round() < installments) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.installments_too_many'.tr())),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (installments > 1) {
        // Read the override again rather than trusting the preview's copy: a
        // save tapped before that request returned would otherwise plan the
        // series against the wrong closing day.
        final closingDay = pm.isCreditCard
            ? _closingDayFor(pm, await _fetchOverride())
            : defaultClosingDay;
        final plan = planInstallments(
          total: amount,
          count: installments,
          spentAt: _spentAt,
          isCreditCard: pm.isCreditCard,
          closingDay: closingDay,
          deferFirst: _deferFirst && pm.isCreditCard,
        );

        final expenses = [
          for (final entry in plan.entries)
            Expense(
              userId: _selectedUser!.id,
              amount: entry.amount,
              categoryKey: _selectedCategory!.key,
              paymentMethodId: pm.id,
              spentAt: entry.date,
              comment: baseComment.isEmpty
                  ? '(${entry.number}/$installments)'
                  : '$baseComment (${entry.number}/$installments)',
              installments: installments,
            ),
        ];

        await _backendService
            .addExpenses(expenses.map((e) => e.toJson()).toList());
      } else {
        final expense = Expense(
          userId: _selectedUser!.id,
          amount: amount,
          categoryKey: _selectedCategory!.key,
          paymentMethodId: pm.id,
          spentAt: _spentAt,
          comment: baseComment.isEmpty ? null : baseComment,
          installments: installments,
        );

        await _backendService.addExpense(expense.toJson());
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.added_success'.tr())),
      );
      if (addAnother) {
        // Person, category, payment method and date stay: entering a stack of
        // receipts usually repeats them.
        _amountController.clear();
        _commentController.clear();
        _installmentsController.clear();
        setState(() => _deferFirst = false);
      } else {
        Navigator.pop(context); // Go back home
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('add_expense.add_failed'
                  .tr(namedArgs: {'error': errorText(e)}))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  String _categoryLabel(Category c) {
    if (!c.isGlobal) return c.label;
    final k = 'categories.${c.key}';
    final t = k.tr();
    return t == k ? c.label : t;
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
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: const TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                prefixText:
                                    '${currencySymbol(expenseCurrency)} ',
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

                    // Category Picker
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue[50],
                        child: Icon(categoryIcon(_selectedCategory?.key),
                            color: Colors.blue, size: 20),
                      ),
                      title: Text('add_expense.category'.tr()),
                      subtitle: Text(_selectedCategory == null
                          ? 'add_expense.pick_category'.tr()
                          : _categoryLabel(_selectedCategory!)),
                      trailing: const Icon(Icons.arrow_drop_down),
                      onTap: _showCategoryPicker,
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
                        if (picked != null) {
                          setState(() => _spentAt = picked);
                          _refreshClosingOverride();
                        }
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
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final n = int.tryParse(text);
                        if (n == null || n < 1 || n > _maxInstallments) {
                          return 'add_expense.installments_invalid'.tr();
                        }
                        return null;
                      },
                    ),
                    _buildInstallmentPreview(),

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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => _submit(addAnother: true),
                        child: Text('add_expense.save_and_new'.tr(),
                            style: const TextStyle(color: Colors.black)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  /// What the installment fields will actually produce, before saving: the
  /// per-installment amount and the bill the first one lands on. This replaces
  /// the old "this month / next month" dialog, whose "this month" answer was
  /// wrong for any purchase made on or after the closing day.
  Widget _buildInstallmentPreview() {
    final plan = _previewPlan();
    if (plan == null) return const SizedBox.shrink();
    final isCreditCard = _selectedPaymentMethod!.isCreditCard;
    final locale = context.locale.toString();

    final summary = (isCreditCard
            ? 'add_expense.installments_preview'
            : 'add_expense.installments_preview_cash')
        .tr(namedArgs: {
      'count': plan.entries.length.toString(),
      'amount':
          formatMoney(plan.entries.first.amount, expenseCurrency, locale),
      'month': DateFormat('MMMM yyyy').format(plan.firstBillMonth),
    });

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(summary,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (isCreditCard)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('add_expense.defer_first_installment'.tr()),
              value: _deferFirst,
              onChanged: (v) => setState(() => _deferFirst = v),
            ),
        ],
      ),
    );
  }

  void _showCategoryPicker() {
    // Sorted by the label actually shown: the backend orders by the English
    // label, which looks random once the names are translated.
    final sorted = [..._categories]..sort((a, b) => _categoryLabel(a)
        .toLowerCase()
        .compareTo(_categoryLabel(b).toLowerCase()));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => GridView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1.1,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: sorted.length,
          itemBuilder: (_, i) {
            final category = sorted[i];
            final selected = category == _selectedCategory;
            final foreground = selected ? Colors.white : Colors.black87;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _selectedCategory = category);
                Navigator.pop(ctx);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected ? Colors.black : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(categoryIcon(category.key), color: foreground),
                    const SizedBox(height: 6),
                    Text(
                      _categoryLabel(category),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: foreground),
                    ),
                  ],
                ),
              ),
            );
          },
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
                _refreshClosingOverride();
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
                    if (!mounted) return;
                    setState(() => _favoritePaymentMethodId = previous);
                    setLocal(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('common.error_with_message'
                              .tr(namedArgs: {'error': errorText(e)}))),
                    );
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

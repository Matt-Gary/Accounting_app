import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/backend_service.dart';
import 'edit_expense_screen.dart';
import '../widgets/language_toggle.dart';

class ExpenseDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> expense;

  const ExpenseDetailsScreen({super.key, required this.expense});

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  final _backendService = BackendService();
  late Map<String, dynamic> _expense;

  @override
  void initState() {
    super.initState();
    _expense = Map<String, dynamic>.from(widget.expense);
  }

  Future<void> _editExpense() async {
    final updated = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditExpenseScreen(expense: _expense),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _expense = {
          ..._expense,
          ...updated,
        };
      });
    }
  }

  Future<void> _deleteExpense() async {
    if (_expense['recurring_id'] != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('delete_expense.cannot_delete_title'.tr()),
          content: Text('delete_expense.recurring_warning'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.ok'.tr()),
            ),
          ],
        ),
      );
      return;
    }

    final bool isInstallment = _expense['installment_group_id'] != null;
    final String? scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('delete_expense.title'.tr()),
        content: Text(isInstallment
            ? 'delete_expense.installment_body'.tr()
            : 'delete_expense.confirm_body'.tr()),
        actions: isInstallment
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('common.cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'this'),
                  child: Text('delete_expense.only_this'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'future'),
                  child: Text('delete_expense.this_and_future'.tr(),
                      style: const TextStyle(color: Colors.red)),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('common.cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'this'),
                  child: Text('common.delete'.tr(),
                      style: const TextStyle(color: Colors.red)),
                ),
              ],
      ),
    );

    if (scope != null && mounted) {
      try {
        await _backendService.deleteExpense(_expense['id'], scope: scope);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('delete_expense.success'.tr())),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('common.error_with_message'
                    .tr(namedArgs: {'error': e.toString()}))),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // subscribe to locale changes so .tr() strings re-evaluate
    final double amount = (_expense['amount'] as num).toDouble();
    final String category =
        _expense['category_label'] ?? 'common.unknown'.tr();
    final String method =
        _expense['payment_method_name'] ?? 'common.unknown'.tr();
    final String userName = _expense['user_name'] ?? 'common.unknown'.tr();
    final DateTime date = DateTime.parse(_expense['spent_at']);
    final String? comment = _expense['comment'];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text('expense_details.title'.tr(),
            style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          const LanguageToggle(),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.black),
            onPressed: _editExpense,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _deleteExpense,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Amount Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(category,
                      style: const TextStyle(fontSize: 18, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Text(
                    'R\$ ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 40, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(DateFormat('EEE, MMM d, yyyy').format(date)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Details List
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  _buildTile(
                      Icons.person, 'expense_details.user'.tr(), userName),
                  const Divider(height: 1),
                  _buildTile(Icons.payment,
                      'expense_details.payment_method'.tr(), method),
                  const Divider(height: 1),
                  _buildTile(
                      Icons.comment,
                      'expense_details.comment'.tr(),
                      comment != null && comment.isNotEmpty
                          ? comment
                          : 'expense_details.no_comment'.tr()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(IconData icon, String title, String value) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.black),
      ),
      title:
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      subtitle: Text(value,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
    );
  }
}

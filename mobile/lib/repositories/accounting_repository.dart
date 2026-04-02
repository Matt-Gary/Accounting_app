import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class AccountingRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Category>> getCategories() async {
    final response = await _client
        .from('categories')
        .select()
        .order('sort_order', ascending: true);

    return (response as List).map((e) => Category.fromJson(e)).toList();
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    final response = await _client.from('payment_methods').select();

    return (response as List).map((e) => PaymentMethod.fromJson(e)).toList();
  }

  Future<List<UserProfile>> getProfiles() async {
    final response = await _client.from('profiles').select();

    return (response as List).map((e) => UserProfile.fromJson(e)).toList();
  }

  Future<void> addExpense(Expense expense) async {
    await _client.from('expenses').insert(expense.toJson());
  }

  Future<void> addExpenses(List<Expense> expenses) async {
    await _client
        .from('expenses')
        .insert(expenses.map((e) => e.toJson()).toList());
  }

  Future<void> addEarning(Earning earning) async {
    await _client.from('earnings').insert(earning.toJson());
  }

  Future<void> addInvestment(Investment investment) async {
    await _client.from('investments').insert(investment.toJson());
  }

  // RECURRING EXPENSES
  Future<List<RecurringExpense>> getRecurringExpenses() async {
    final response = await _client.from('recurring_expenses').select();
    return (response as List).map((e) => RecurringExpense.fromJson(e)).toList();
  }

  Future<void> addRecurringExpense(RecurringExpense recurring) async {
    await _client.from('recurring_expenses').insert(recurring.toJson());
  }

  Future<void> updateRecurringExpense(RecurringExpense recurring) async {
    if (recurring.id == null) return;
    await _client
        .from('recurring_expenses')
        .update(recurring.toJson())
        .eq('id', recurring.id!);
  }

  Future<void> deleteRecurringExpense(String id) async {
    await _client.from('recurring_expenses').delete().eq('id', id);
  }

  Future<void> updateInvestment(Investment investment) async {
    if (investment.id == null) return;
    await _client
        .from('investments')
        .update(investment.toJson())
        .eq('id', investment.id!);
  }

  Future<void> deleteInvestment(String id) async {
    await _client.from('investments').delete().eq('id', id);
  }

  Future<void> deleteExpense(String id) async {
    await _client.from('expenses').delete().eq('id', id);
  }
}

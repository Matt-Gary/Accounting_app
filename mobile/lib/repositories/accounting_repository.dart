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
    final response = await _client
        .from('payment_methods')
        .select();
    
    return (response as List).map((e) => PaymentMethod.fromJson(e)).toList();
  }

  Future<List<UserProfile>> getProfiles() async {
    final response = await _client
        .from('profiles')
        .select();
    
    return (response as List).map((e) => UserProfile.fromJson(e)).toList();
  }

  Future<void> addExpense(Expense expense) async {
    await _client.from('expenses').insert(expense.toJson());
  }
}

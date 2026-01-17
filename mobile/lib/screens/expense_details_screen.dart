import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpenseDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> expense;

  const ExpenseDetailsScreen({super.key, required this.expense});

  @override
  Widget build(BuildContext context) {
    // Parsing data safely
    final double amount = (expense['amount'] as num).toDouble();
    final String currency = expense['currency'] ?? 'BRL';
    final String category = expense['category_label'] ?? 'Unknown';
    final String method = expense['payment_method_name'] ?? 'Unknown';
    final String userName = expense['user_name'] ?? 'Unknown';
    final DateTime date = DateTime.parse(expense['spent_at']);
    final String? comment = expense['comment'];

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Expense Details',
            style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
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
                    color: Colors.grey.withOpacity(0.1),
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
                  _buildTile(Icons.person, 'User', userName),
                  const Divider(height: 1),
                  _buildTile(Icons.payment, 'Payment Method', method),
                  const Divider(height: 1),
                  _buildTile(
                      Icons.comment,
                      'Comment',
                      comment != null && comment.isNotEmpty
                          ? comment
                          : 'No comment'),
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

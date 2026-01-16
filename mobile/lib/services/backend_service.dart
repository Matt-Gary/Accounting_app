import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class BackendService {
  // Use 10.0.2.2 for Android Simulator localhost, or your machine IP for real device/iOS simulator
  static const String baseUrl = 'http://127.0.0.1:5000';

  Future<DashboardData> getDashboard(
      {required int month, required int year, String? userId}) async {
    final queryParams = {
      'month': month.toString(),
      'year': year.toString(),
      if (userId != null) 'user_id': userId,
    };

    final uri =
        Uri.parse('$baseUrl/dashboard').replace(queryParameters: queryParams);

    final response = await http.get(uri);

    if (response.statusCode == 200) {
      print("Raw JSON: ${response.body}"); // Debugging
      return DashboardData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load dashboard: ${response.body}');
    }
  }

  Future<void> downloadReport(int month, int year) async {
    // Logic to open URL in browser or download file
    // For MVP, we can just print the URL or use url_launcher
    final url = '$baseUrl/report/monthly?month=$month&year=$year';
    print("Download Report URL: $url");
  }
}

class DashboardData {
  final double totalSpent;
  final Map<String, double> categoryBreakdown;
  final Map<String, double> userBreakdown;
  final String billingPeriod;
  final int expenseCount;
  final List<dynamic> expenses; // Keep raw list for details view

  DashboardData({
    required this.totalSpent,
    required this.categoryBreakdown,
    required this.userBreakdown,
    required this.billingPeriod,
    required this.expenseCount,
    required this.expenses,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    Map<String, double> breakdown = {};
    if (json['category_breakdown'] != null) {
      json['category_breakdown'].forEach((key, value) {
        breakdown[key] = (value as num).toDouble();
      });
    }

    Map<String, double> uBreakdown = {};
    if (json['user_breakdown'] != null) {
      json['user_breakdown'].forEach((key, value) {
        uBreakdown[key] = (value as num).toDouble();
      });
    }

    return DashboardData(
      totalSpent: (json['total_spent'] as num).toDouble(),
      categoryBreakdown: breakdown,
      userBreakdown: uBreakdown,
      billingPeriod: json['billing_period'],
      expenseCount: json['expense_count'],
      expenses: json['expenses'] ?? [],
    );
  }
}

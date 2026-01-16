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

  Future<Earning> addEarning(Earning earning) async {
    final uri = Uri.parse('$baseUrl/earnings');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(earning.toJson()),
    );

    if (response.statusCode == 201) {
      return Earning.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to add earning: ${response.body}');
    }
  }

  Future<PortfolioData> getInvestments(String userId) async {
    final uri = Uri.parse('$baseUrl/investments?user_id=$userId');
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return PortfolioData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load investments: ${response.body}');
    }
  }
}

class PortfolioData {
  final double totalValueUsd;
  final double totalValueBrl;
  final double exchangeRate;
  final List<Investment> investments;

  PortfolioData(
      {required this.totalValueUsd,
      required this.totalValueBrl,
      required this.exchangeRate,
      required this.investments});

  factory PortfolioData.fromJson(Map<String, dynamic> json) {
    return PortfolioData(
      totalValueUsd: (json['total_value_usd'] as num? ?? 0.0).toDouble(),
      totalValueBrl: (json['total_value_brl'] as num? ?? 0.0).toDouble(),
      exchangeRate: (json['exchange_rate_usd_brl'] as num? ?? 0.0).toDouble(),
      investments: (json['investments'] as List<dynamic>?)
              ?.map((e) => Investment.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class DashboardData {
  final double totalSpent;
  final double totalEarned;
  final Map<String, double> categoryBreakdown;
  final Map<String, double> userSpendBreakdown;
  final Map<String, double> userEarnedBreakdown;
  final String billingPeriod;
  final int expenseCount;
  final List<dynamic> expenses;
  final int earningCount;
  final List<Earning> earnings;

  DashboardData({
    required this.totalSpent,
    required this.totalEarned,
    required this.categoryBreakdown,
    required this.userSpendBreakdown,
    required this.userEarnedBreakdown,
    required this.billingPeriod,
    required this.expenseCount,
    required this.expenses,
    required this.earningCount,
    required this.earnings,
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    Map<String, double> extractBreakdown(Map<String, dynamic>? data) {
      Map<String, double> result = {};
      if (data != null) {
        data.forEach((key, value) {
          result[key] = (value as num? ?? 0.0).toDouble();
        });
      }
      return result;
    }

    return DashboardData(
      totalSpent: (json['total_spent'] as num? ?? 0.0).toDouble(),
      totalEarned: (json['total_earned'] as num? ?? 0.0).toDouble(),
      categoryBreakdown: extractBreakdown(json['category_breakdown']),
      userSpendBreakdown: extractBreakdown(json['user_spend_breakdown']),
      userEarnedBreakdown: extractBreakdown(json['user_earned_breakdown']),
      billingPeriod: json['billing_period'] ?? '',
      expenseCount: json['expense_count'] ?? 0,
      expenses: json['expenses'] ?? [],
      earningCount: json['earning_count'] ?? 0,
      earnings: (json['earnings'] as List<dynamic>?)
              ?.map((e) => Earning.fromJson(e))
              .toList() ??
          [],
    );
  }
}

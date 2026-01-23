import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';

class BackendService {
  // Use 10.0.2.2 for Android Simulator localhost, or your machine IP for real device/iOS simulator
  static const String baseUrl = 'http://127.0.0.1:5000';
  //static const String baseUrl = 'http://69.62.101.177:5005';

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
    final url = '$baseUrl/report/monthly?month=$month&year=$year';
    final uri = Uri.parse(url);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      print("Error launching download URL: $e");
      rethrow;
    }
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

  Future<PortfolioDistribution> getPortfolioDistribution(String userId,
      {List<String>? investmentTypes}) async {
    final queryParams = {
      'user_id': userId,
      if (investmentTypes != null && investmentTypes.isNotEmpty)
        'investment_types': investmentTypes.join(','),
    };

    final uri = Uri.parse('$baseUrl/investments/distribution')
        .replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      return PortfolioDistribution.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load distribution: ${response.body}');
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

class PortfolioDistribution {
  final List<InvestmentTypeDistribution> distribution;
  final List<InvestmentItem>?
      items; // Individual investments when filtering by type
  final double totalValueUsd;
  final double totalValueBrl;
  final double exchangeRate;

  PortfolioDistribution({
    required this.distribution,
    this.items,
    required this.totalValueUsd,
    required this.totalValueBrl,
    required this.exchangeRate,
  });

  factory PortfolioDistribution.fromJson(Map<String, dynamic> json) {
    return PortfolioDistribution(
      distribution: (json['distribution'] as List<dynamic>?)
              ?.map((e) => InvestmentTypeDistribution.fromJson(e))
              .toList() ??
          [],
      items: json['items'] != null
          ? (json['items'] as List<dynamic>)
              .map((e) => InvestmentItem.fromJson(e))
              .toList()
          : null,
      totalValueUsd: (json['total_value_usd'] as num? ?? 0.0).toDouble(),
      totalValueBrl: (json['total_value_brl'] as num? ?? 0.0).toDouble(),
      exchangeRate: (json['exchange_rate_usd_brl'] as num? ?? 0.0).toDouble(),
    );
  }
}

// Placeholder for InvestmentItem, assuming it's similar to Investment
// You might need to adjust this based on your actual InvestmentItem structure
class InvestmentItem {
  final String? id;
  final String name;
  final String? symbol;
  final String type;
  final double valueUsd;
  final double valueBrl;
  final double percentage;
  final double quantity;

  InvestmentItem({
    this.id,
    required this.name,
    this.symbol,
    required this.type,
    required this.valueUsd,
    required this.valueBrl,
    required this.percentage,
    required this.quantity,
  });

  factory InvestmentItem.fromJson(Map<String, dynamic> json) {
    return InvestmentItem(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      symbol: json['symbol'],
      type: json['type'] ?? '',
      valueUsd: (json['value_usd'] as num? ?? 0.0).toDouble(),
      valueBrl: (json['value_brl'] as num? ?? 0.0).toDouble(),
      percentage: (json['percentage'] as num? ?? 0.0).toDouble(),
      quantity: (json['quantity'] as num? ?? 0.0).toDouble(),
    );
  }
}

class InvestmentTypeDistribution {
  final String type;
  final double valueUsd;
  final double valueBrl;
  final double percentage;

  InvestmentTypeDistribution({
    required this.type,
    required this.valueUsd,
    required this.valueBrl,
    required this.percentage,
  });

  factory InvestmentTypeDistribution.fromJson(Map<String, dynamic> json) {
    return InvestmentTypeDistribution(
      type: json['type'] ?? '',
      valueUsd: (json['value_usd'] as num? ?? 0.0).toDouble(),
      valueBrl: (json['value_brl'] as num? ?? 0.0).toDouble(),
      percentage: (json['percentage'] as num? ?? 0.0).toDouble(),
    );
  }
}

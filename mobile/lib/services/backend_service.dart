import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';

class BackendService {
  // Use 10.0.2.2 for Android Simulator localhost, or your machine IP for real device/iOS simulator
  static const String baseUrl = 'http://127.0.0.1:5000';
  //static const String baseUrl = 'http://72.60.137.97:5005';

  Map<String, String> _authHeaders({bool json = false}) {
    final session = Supabase.instance.client.auth.currentSession;
    return {
      if (json) 'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };
  }

  // Executes [fn] with auth headers. On 401, refreshes the session once and retries.
  Future<http.Response> _withAuth(
    Future<http.Response> Function(Map<String, String>) fn, {
    bool json = false,
  }) async {
    final response = await fn(_authHeaders(json: json));
    if (response.statusCode != 401) return response;

    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (_) {
      return response;
    }

    return fn(_authHeaders(json: json));
  }

  static final Map<String, DashboardData> _dashboardCache = {};
  static final Map<String, DateTime> _dashboardCacheTime = {};
  static const _dashboardHardTtl = Duration(minutes: 2);

  static bool hasDashboardCache(int month, int year) =>
      _dashboardCache.containsKey('${month}_$year');

  static void clearDashboardCache() {
    _dashboardCache.clear();
    _dashboardCacheTime.clear();
  }

  Future<DashboardData> getDashboard({
    required int month,
    required int year,
    String? userId,
    int? closingDay,
    void Function(DashboardData)? onRefresh,
  }) async {
    final cacheKey = '${month}_${year}_${closingDay ?? 0}';
    final cached = _dashboardCache[cacheKey];
    final cacheTime = _dashboardCacheTime[cacheKey];
    final now = DateTime.now();

    Future<DashboardData> fetchFresh() async {
      final queryParams = {
        'month': month.toString(),
        'year': year.toString(),
        if (userId != null) 'user_id': userId,
        if (closingDay != null) 'closing_day': closingDay.toString(),
      };
      final uri =
          Uri.parse('$baseUrl/dashboard').replace(queryParameters: queryParams);
      final response = await _withAuth((h) => http.get(uri, headers: h));
      if (response.statusCode == 200) {
        final data = DashboardData.fromJson(jsonDecode(response.body));
        _dashboardCache[cacheKey] = data;
        _dashboardCacheTime[cacheKey] = DateTime.now();
        return data;
      } else {
        throw Exception('Failed to load dashboard: ${response.body}');
      }
    }

    if (cached != null && cacheTime != null) {
      final age = now.difference(cacheTime);
      if (age < _dashboardHardTtl) {
        return cached;
      }
      if (onRefresh != null) {
        fetchFresh().then(onRefresh).catchError((_) {});
      }
      return cached;
    }

    return fetchFresh();
  }

  Future<void> downloadReport(int month, int year) async {
    final uri = Uri.parse('$baseUrl/report/monthly').replace(queryParameters: {
      'month': month.toString(),
      'year': year.toString(),
    });

    try {
      final response = await _withAuth((h) => http.get(uri, headers: h));
      if (response.statusCode == 200) {
        final tempDir = Directory.systemTemp;
        final filePath = '${tempDir.path}/report_${month}_$year.xlsx';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        final fileUri = Uri.file(file.path);
        if (await canLaunchUrl(fileUri)) {
          await launchUrl(fileUri, mode: LaunchMode.externalApplication);
        }
      } else {
        throw Exception('Failed to download report: ${response.statusCode}');
      }
    } catch (e) {
      print("Error downloading report: $e");
      rethrow;
    }
  }

  Future<Earning> addEarning(Earning earning) async {
    final uri = Uri.parse('$baseUrl/earnings');
    final body = jsonEncode(earning.toJson());
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );

    if (response.statusCode == 201) {
      return Earning.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to add earning: ${response.body}');
    }
  }

  Future<PortfolioData> getInvestments() async {
    final uri = Uri.parse('$baseUrl/investments');
    final response = await _withAuth((h) => http.get(uri, headers: h));

    if (response.statusCode == 200) {
      return PortfolioData.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load investments: ${response.body}');
    }
  }

  Future<void> addInvestment(Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/investments');
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to add investment: ${response.body}');
    }
  }

  Future<void> updateInvestmentById(
      String id, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/investments/$id');
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.put(uri, headers: h, body: body),
      json: true,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update investment: ${response.body}');
    }
  }

  Future<void> deleteInvestmentById(String id) async {
    final uri = Uri.parse('$baseUrl/investments/$id');
    final response = await _withAuth((h) => http.delete(uri, headers: h));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete investment: ${response.body}');
    }
  }

  Future<void> deleteExpense(String id, {String scope = 'this'}) async {
    final uri = Uri.parse('$baseUrl/expenses/$id').replace(
      queryParameters: {'scope': scope},
    );
    final response = await _withAuth((h) => http.delete(uri, headers: h));
    if (response.statusCode != 200) {
      throw Exception('Failed to delete expense: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateExpense(
      String id, Map<String, dynamic> data) async {
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.put(Uri.parse('$baseUrl/expenses/$id'), headers: h, body: body),
      json: true,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to update expense: ${response.body}');
  }

  Future<PortfolioDistribution> getPortfolioDistribution(
      {List<String>? investmentTypes}) async {
    final queryParams = {
      if (investmentTypes != null && investmentTypes.isNotEmpty)
        'investment_types': investmentTypes.join(','),
    };

    final uri = Uri.parse('$baseUrl/investments/distribution')
        .replace(queryParameters: queryParams);
    final response = await _withAuth((h) => http.get(uri, headers: h));

    if (response.statusCode == 200) {
      return PortfolioDistribution.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load distribution: ${response.body}');
    }
  }

  // ============= CLOSING DAY OVERRIDE METHODS =============

  Future<int?> getClosingDayOverride(int month, int year) async {
    final uri =
        Uri.parse('$baseUrl/closing-day-overrides').replace(queryParameters: {
      'month': month.toString(),
      'year': year.toString(),
    });

    final response = await _withAuth((h) => http.get(uri, headers: h));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['closing_day'] as int?;
    } else {
      throw Exception('Failed to get closing day override: ${response.body}');
    }
  }

  Future<void> setClosingDayOverride(
      int month, int year, int closingDay) async {
    final uri = Uri.parse('$baseUrl/closing-day-overrides');
    final body = jsonEncode({
      'month': month,
      'year': year,
      'closing_day': closingDay,
    });
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to set closing day override: ${response.body}');
    }
  }

  Future<void> deleteRecurringExpense(String id) async {
    final uri = Uri.parse('$baseUrl/recurring-expenses/$id');
    final response = await _withAuth((h) => http.delete(uri, headers: h));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete recurring expense: ${response.body}');
    }
  }

  Future<void> updateRecurringExpense(
      String id, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/recurring-expenses/$id');
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.put(uri, headers: h, body: body),
      json: true,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update recurring expense: ${response.body}');
    }
  }

  Future<void> deleteClosingDayOverride(int month, int year) async {
    final uri =
        Uri.parse('$baseUrl/closing-day-overrides').replace(queryParameters: {
      'month': month.toString(),
      'year': year.toString(),
    });

    final response = await _withAuth((h) => http.delete(uri, headers: h));

    if (response.statusCode != 200 && response.statusCode != 404) {
      throw Exception(
          'Failed to delete closing day override: ${response.body}');
    }
  }

  // ============= RECURRING EXPENSES =============

  Future<List<Map<String, dynamic>>> getRecurringExpenses() async {
    final uri = Uri.parse('$baseUrl/recurring-expenses');
    final response = await _withAuth((h) => http.get(uri, headers: h));

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load recurring expenses: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> addRecurringExpense(
      Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/recurring-expenses');
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to add recurring expense: ${response.body}');
    }
  }

  // ============= AUTH / ONBOARDING =============

  Future<List<Category>> getCategoriesForManagement() async {
    final uri = Uri.parse('$baseUrl/categories');
    final response = await _withAuth((h) => http.get(uri, headers: h));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((e) => Category.fromJson(e)).toList();
    }
    throw Exception('Failed to load categories: ${response.body}');
  }

  Future<Category> createCustomCategory(String label) async {
    final uri = Uri.parse('$baseUrl/categories');
    final body = jsonEncode({'label': label});
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );
    if (response.statusCode == 201) {
      return Category.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to create category: ${response.body}');
  }

  Future<void> deleteCustomCategory(String key) async {
    final uri = Uri.parse('$baseUrl/categories/$key');
    final response = await _withAuth((h) => http.delete(uri, headers: h));
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw Exception(body['error'] ?? 'Failed to delete category');
    }
  }

  Future<void> setCategoryVisibility(String key, {required bool hidden}) async {
    final uri = Uri.parse('$baseUrl/categories/$key/visibility');
    final body = jsonEncode({'hidden': hidden});
    final response = await _withAuth(
      (h) => http.put(uri, headers: h, body: body),
      json: true,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update category visibility: ${response.body}');
    }
  }

  static FamilyData? _familyDataCache;
  static DateTime? _familyDataCacheTime;
  static const _familyCacheTtl = Duration(minutes: 5);

  static void clearFamilyDataCache() {
    _familyDataCache = null;
    _familyDataCacheTime = null;
  }

  Future<FamilyData> getFamilyData({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _familyDataCache != null &&
        _familyDataCacheTime != null &&
        DateTime.now().difference(_familyDataCacheTime!) < _familyCacheTtl) {
      return _familyDataCache!;
    }
    final uri = Uri.parse('$baseUrl/family/data');
    final response = await _withAuth((h) => http.get(uri, headers: h));
    if (response.statusCode == 200) {
      _familyDataCache = FamilyData.fromJson(jsonDecode(response.body));
      _familyDataCacheTime = DateTime.now();
      return _familyDataCache!;
    } else {
      throw Exception('Failed to load family data: ${response.body}');
    }
  }

  Future<void> addExpense(Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/expenses');
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to add expense: ${response.body}');
    }
  }

  Future<void> addExpenses(List<Map<String, dynamic>> data) async {
    final uri = Uri.parse('$baseUrl/expenses/bulk');
    final body = jsonEncode(data);
    final response = await _withAuth(
      (h) => http.post(uri, headers: h, body: body),
      json: true,
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to add expenses: ${response.body}');
    }
  }

  Future<void> onboardUser({
    required String displayName,
    required String familyName,
    String? accessToken,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/onboard');
    // Use provided token (from signUp response) or fall back to current session
    final token = accessToken ??
        Supabase.instance.client.auth.currentSession?.accessToken;
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'display_name': displayName,
        'family_name': familyName,
      }),
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to onboard user: ${response.body}');
    }
  }

  // ============= APP UPDATE =============

  Future<Map<String, dynamic>?> checkForUpdate() async {
    final uri = Uri.parse('$baseUrl/app/version');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('[WARN] Version check failed: $e');
    }
    return null;
  }

  Future<String> downloadApk({
    required String downloadUrl,
    required void Function(double progress) onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await client.send(request);
      final contentLength = streamedResponse.contentLength ?? 0;
      final directory = await _getDownloadDirectory();
      final filePath = '${directory.path}/app-update.apk';
      final sink = File(filePath).openWrite();
      int bytesReceived = 0;
      await streamedResponse.stream.listen((chunk) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        if (contentLength > 0) onProgress(bytesReceived / contentLength);
      }).asFuture();
      await sink.close();
      return filePath;
    } finally {
      client.close();
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    } catch (_) {}
    return getTemporaryDirectory();
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

class FamilyData {
  final List<UserProfile> profiles;
  final List<Category> categories;
  final List<PaymentMethod> paymentMethods;

  FamilyData({
    required this.profiles,
    required this.categories,
    required this.paymentMethods,
  });

  factory FamilyData.fromJson(Map<String, dynamic> json) {
    return FamilyData(
      profiles: (json['profiles'] as List<dynamic>?)
              ?.map((e) => UserProfile.fromJson(e))
              .toList() ??
          [],
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => Category.fromJson(e))
              .toList() ??
          [],
      paymentMethods: (json['payment_methods'] as List<dynamic>?)
              ?.map((e) => PaymentMethod.fromJson(e))
              .toList() ??
          [],
    );
  }
}

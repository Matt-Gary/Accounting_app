import 'package:flutter/material.dart';

/// Maps a stable category key (see the `categories` block in the translation
/// files) to a distinct Material icon. Unknown / custom family categories fall
/// back to a neutral default.
IconData categoryIcon(String? key) {
  switch (key) {
    case 'clothing':
      return Icons.checkroom;
    case 'condominium':
      return Icons.apartment;
    case 'credit_loans':
      return Icons.credit_card;
    case 'education_work':
      return Icons.school;
    case 'electricity_gas':
      return Icons.bolt;
    case 'fuel':
      return Icons.local_gas_station;
    case 'government':
      return Icons.account_balance;
    case 'groceries':
      return Icons.shopping_cart;
    case 'gym':
      return Icons.fitness_center;
    case 'health':
      return Icons.local_hospital;
    case 'health_insurance':
      return Icons.health_and_safety;
    case 'home_items':
      return Icons.chair;
    case 'internet':
      return Icons.wifi;
    case 'misc':
      return Icons.category;
    case 'mobile':
      return Icons.smartphone;
    case 'parking':
      return Icons.local_parking;
    case 'psychologist':
      return Icons.psychology;
    case 'restaurants':
      return Icons.restaurant;
    case 'services_maintenance':
      return Icons.handyman;
    case 'travel':
      return Icons.flight;
    case 'uber':
      return Icons.local_taxi;
    default:
      return Icons.label_outline;
  }
}

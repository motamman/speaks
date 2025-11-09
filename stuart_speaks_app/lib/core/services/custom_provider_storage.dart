import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_template.dart';

/// Storage for custom provider templates imported by users
class CustomProviderStorage {
  static const String _storageKey = 'custom_provider_templates';
  final SharedPreferences _prefs;

  CustomProviderStorage(this._prefs);

  /// Get all custom provider templates
  Future<List<ProviderTemplate>> getAll() async {
    final jsonString = _prefs.getString(_storageKey);
    if (jsonString == null) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => ProviderTemplate.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // If parsing fails, return empty list
      return [];
    }
  }

  /// Save a custom provider template
  Future<void> save(ProviderTemplate template) async {
    final templates = await getAll();

    // Check if provider with this ID already exists
    final existingIndex = templates.indexWhere((t) => t.id == template.id);

    if (existingIndex >= 0) {
      // Update existing
      templates[existingIndex] = template;
    } else {
      // Add new
      templates.add(template);
    }

    await _saveAll(templates);
  }

  /// Delete a custom provider template
  Future<void> delete(String providerId) async {
    final templates = await getAll();
    templates.removeWhere((t) => t.id == providerId);
    await _saveAll(templates);
  }

  /// Get a specific provider template by ID
  Future<ProviderTemplate?> getById(String providerId) async {
    final templates = await getAll();
    try {
      return templates.firstWhere((t) => t.id == providerId);
    } catch (e) {
      return null;
    }
  }

  /// Check if a provider ID already exists
  Future<bool> exists(String providerId) async {
    final template = await getById(providerId);
    return template != null;
  }

  /// Save all templates to storage
  Future<void> _saveAll(List<ProviderTemplate> templates) async {
    final jsonList = templates.map((t) => t.toJson()).toList();
    final jsonString = jsonEncode(jsonList);
    await _prefs.setString(_storageKey, jsonString);
  }

  /// Clear all custom providers
  Future<void> clearAll() async {
    await _prefs.remove(_storageKey);
  }
}

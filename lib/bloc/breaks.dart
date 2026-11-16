import 'dart:convert';

import 'package:flutter/material.dart';

/// A kind of break the pause button offers when held, with how long it should last. The list is
/// set in Settings and kept on this device.
class BreakCategory {
  final String name;
  final int minutes;

  /// One of [breakIcons]' keys.
  final String icon;

  const BreakCategory({required this.name, required this.minutes, this.icon = 'pause'});

  BreakCategory copyWith({String? name, int? minutes, String? icon}) => BreakCategory(
      name: name ?? this.name, minutes: minutes ?? this.minutes, icon: icon ?? this.icon);

  Map<String, Object> toJson() => {'name': name, 'minutes': minutes, 'icon': icon};

  /// Reads one category, or null when [json] isn't one.
  static BreakCategory? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final minutes = json['minutes'];
    final icon = json['icon'];
    if (name is! String || name.trim().isEmpty || minutes is! int) return null;
    return BreakCategory(
        name: name.trim(),
        minutes: minutes.clamp(minBreakMinutes, maxBreakMinutes),
        icon: icon is String && breakIcons.containsKey(icon) ? icon : 'pause');
  }

  @override
  bool operator ==(Object other) =>
      other is BreakCategory &&
      other.name == name &&
      other.minutes == minutes &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(name, minutes, icon);
}

/// The range a break's planned length may take, in minutes.
const minBreakMinutes = 1;
const maxBreakMinutes = 180;

/// Breaks shorter than this rarely rest you, so the app suggests a longer one.
const recommendedBreakMinutes = 5;

/// The break types offered until Settings changes them: short ones to rest the eyes and stretch,
/// longer ones for meals and errands. None is shorter than [recommendedBreakMinutes].
const defaultBreakCategories = [
  BreakCategory(name: 'Coffee', minutes: 5, icon: 'coffee'),
  BreakCategory(name: 'Stretch', minutes: 10, icon: 'stretch'),
  BreakCategory(name: 'Walk', minutes: 15, icon: 'walk'),
  BreakCategory(name: 'Errand', minutes: 30, icon: 'errand'),
  BreakCategory(name: 'Lunch', minutes: 45, icon: 'meal'),
];

/// The icons a break type can have.
const breakIcons = <String, IconData>{
  'pause': Icons.pause_circle_outline,
  'coffee': Icons.coffee_outlined,
  'stretch': Icons.self_improvement,
  'walk': Icons.directions_walk,
  'meal': Icons.restaurant_outlined,
  'errand': Icons.shopping_bag_outlined,
  'rest': Icons.bedtime_outlined,
  'call': Icons.call_outlined,
};

IconData breakIcon(String? icon) => breakIcons[icon] ?? Icons.coffee_outlined;

/// The icon for a break with [reason], from the category of that name in [categories].
IconData breakIconFor(String? reason, List<BreakCategory> categories) {
  for (final c in categories) {
    if (c.name == reason) return breakIcon(c.icon);
  }
  return Icons.coffee_outlined;
}

String encodeBreakCategories(List<BreakCategory> categories) =>
    jsonEncode([for (final c in categories) c.toJson()]);

/// Reads the saved list; anything that doesn't read gives the defaults back. An empty list is
/// kept: the person removed every type, and holding pause then only offers a plain pause.
List<BreakCategory> decodeBreakCategories(String? encoded) {
  if (encoded == null) return defaultBreakCategories;
  try {
    final list = jsonDecode(encoded);
    if (list is! List) return defaultBreakCategories;
    return [
      for (final c in list)
        if (BreakCategory.fromJson(c) case final category?) category
    ];
  } on FormatException {
    return defaultBreakCategories;
  }
}

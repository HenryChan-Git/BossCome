import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class StatsService {
  // Updated according to the new API documentation
  static const String _serverUrl = "https://www.henrychanserver.top:16800/api/bosscome/report";
  
  static const String _keyInstallFlag = "stats_install_flag";
  static const String _keyPendingCount = "stats_pending_count";
  static const String _keyPendingHourly = "stats_pending_hourly";
  static const String _keyLocalTotal = "stats_local_total";

  /// Increment stats when entering Boss/Black screen mode
  static Future<void> recordBossEnter() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Persistent Local Total (For User) - Never cleared by upload
    int localTotal = prefs.getInt(_keyLocalTotal) ?? 0;
    await prefs.setInt(_keyLocalTotal, localTotal + 1);

    // 2. Pending Total (For Server) - Cleared after upload
    int pendingTotal = prefs.getInt(_keyPendingCount) ?? 0;
    await prefs.setInt(_keyPendingCount, pendingTotal + 1);

    // 3. Hourly Stats (For Server) - Cleared after upload
    // Key format: "HH" (00-23)
    String currentHour = DateFormat('HH').format(DateTime.now());
    String jsonString = prefs.getString(_keyPendingHourly) ?? "{}";
    Map<String, dynamic> hourlyMap = {};
    try {
      hourlyMap = jsonDecode(jsonString);
    } catch (e) {
      hourlyMap = {};
    }

    int currentHourCount = (hourlyMap[currentHour] as int?) ?? 0;
    hourlyMap[currentHour] = currentHourCount + 1;
    
    await prefs.setString(_keyPendingHourly, jsonEncode(hourlyMap));
  }

  /// Get local total count for display
  static Future<int> getLocalTotal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyLocalTotal) ?? 0;
  }

  /// Check and upload pending stats to server
  /// Call this on app startup
  static Future<void> checkAndUpload() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Check Install Flag (Default is 1 if not set, or you can check if key exists)
      // Requirement: "install=1" initially. Upload -> set to 0.
      int installFlag = prefs.getInt(_keyInstallFlag) ?? 1;

      // 2. Load pending stats
      int pendingCount = prefs.getInt(_keyPendingCount) ?? 0;
      String hourlyJson = prefs.getString(_keyPendingHourly) ?? "{}";
      Map<String, dynamic> hourlyMap = {};
      try {
        hourlyMap = jsonDecode(hourlyJson);
      } catch (e) {
        // ignore
      }

      // Normalize hourly_stats keys to "HH" (00-23) in case older cached data uses "yyyy-MM-dd HH"
      if (hourlyMap.isNotEmpty) {
        final Map<String, dynamic> normalized = {};
        hourlyMap.forEach((key, value) {
          String hourKey = key;
          final match = RegExp(r'(?:^|\s)(\d{2})$').firstMatch(key);
          if (match != null) {
            hourKey = match.group(1) ?? key;
          }
          final int count = (value is int) ? value : int.tryParse(value.toString()) ?? 0;
          normalized[hourKey] = (normalized[hourKey] as int? ?? 0) + count;
        });
        hourlyMap = normalized;
      }

      // If nothing to upload, return
      if (installFlag == 0 && pendingCount == 0 && hourlyMap.isEmpty) {
        return;
      }

      // Construct payload
      Map<String, dynamic> payload = {
        "install": installFlag,
        "boss_switch_count": pendingCount,
        "hourly_stats": hourlyMap,
        "timestamp": DateTime.now().toIso8601String(),
      };

      try {
        print("DEBUG: [Stats] Start upload to: $_serverUrl");
        print("DEBUG: [Stats] Payload: ${jsonEncode(payload)}");
        // Send to server
        // Note: You might want to handle timeout/errors gracefully
        final response = await http
            .post(
              Uri.parse(_serverUrl),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 30)); // Increase timeout for mobile networks

        if (response.statusCode >= 200 && response.statusCode < 300) {
          // Success: Clear pending stats
          if (installFlag == 1) {
            await prefs.setInt(_keyInstallFlag, 0);
          }
          await prefs.setInt(_keyPendingCount, 0);
          await prefs.setString(_keyPendingHourly, "{}");
          print("DEBUG: [Stats] Upload successful. Stats cleared.");
        } else {
          print("DEBUG: [Stats] Upload failed with status: ${response.statusCode}");
        }
      } catch (e) {
        print("DEBUG: [Stats] Upload error (network/server): $e");
      }
    } catch (e) {
      print("DEBUG: [Stats] Fatal error in checkAndUpload: $e");
    }
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Collects device metadata and computes the server-compatible SHA256 hash.
class DeviceIdentifierService {
  DeviceIdentifierService({DeviceInfoPlugin? plugin})
      : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  Map<String, dynamic>? _cachedData;
  String? _cachedHash;

  Future<Map<String, dynamic>> collectDeviceData() async {
    if (_cachedData != null) {
      return _cachedData!;
    }

    final data = <String, dynamic>{
      'platform': _platformName(),
    };

    try {
      if (kIsWeb) {
        final info = await _plugin.webBrowserInfo;
        data['device_id'] = info.userAgent ?? 'web';
        data['vendor'] = info.vendor;
      } else if (Platform.isAndroid) {
        final info = await _plugin.androidInfo;
        data['device_id'] = info.id;
        data['model'] = info.model;
        data['brand'] = info.brand;
        data['manufacturer'] = info.manufacturer;
      } else if (Platform.isIOS) {
        final info = await _plugin.iosInfo;
        data['device_id'] = info.identifierForVendor ?? 'ios-unknown';
        data['model'] = info.model;
        data['system_name'] = info.systemName;
      } else if (Platform.isWindows) {
        final info = await _plugin.windowsInfo;
        data['device_id'] = info.deviceId;
        data['computer_name'] = info.computerName;
      } else if (Platform.isMacOS) {
        final info = await _plugin.macOsInfo;
        data['device_id'] = info.systemGUID ?? 'macos-unknown';
        data['model'] = info.model;
      } else if (Platform.isLinux) {
        final info = await _plugin.linuxInfo;
        data['device_id'] = info.machineId ?? 'linux-unknown';
        data['name'] = info.name;
      }
    } catch (_) {
      data['device_id'] ??= 'unknown';
    }

    _cachedData = data;
    return data;
  }

  Future<String> computeHash() async {
    if (_cachedHash != null) {
      return _cachedHash!;
    }
    final data = await collectDeviceData();
    _cachedHash = computeDeviceHash(data);
    return _cachedHash!;
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }
    return Platform.operatingSystem;
  }
}

String computeDeviceHash(Map<String, dynamic> data) {
  final canonical = jsonEncode(_sortJson(data));
  return sha256.convert(utf8.encode(canonical)).toString();
}

dynamic _sortJson(dynamic value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return {
      for (final entry in entries) entry.key.toString(): _sortJson(entry.value),
    };
  }
  if (value is List) {
    return value.map(_sortJson).toList();
  }
  return value;
}

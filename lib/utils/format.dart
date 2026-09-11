import 'package:flutter/material.dart';

/// 字节数格式化
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// 速度格式化
String formatSpeed(double bps) {
  if (bps <= 0) return '--';
  if (bps < 1024) return '${bps.toStringAsFixed(0)} B/s';
  if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
  return '${(bps / 1024 / 1024).toStringAsFixed(1)} MB/s';
}

/// 设备类型图标
IconData deviceTypeIcon(String type) {
  switch (type) {
    case 'windows':
      return Icons.desktop_windows;
    case 'macos':
      return Icons.laptop_mac;
    case 'android':
      return Icons.phone_android;
    case 'ios':
      return Icons.phone_iphone;
    default:
      return Icons.devices_other;
  }
}

/// 设备类型中文名
String deviceTypeLabel(String type) {
  switch (type) {
    case 'windows':
      return 'Windows';
    case 'macos':
      return 'Mac';
    case 'android':
      return 'Android';
    case 'ios':
      return 'iPhone';
    default:
      return '设备';
  }
}

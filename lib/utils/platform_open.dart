import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

// Re-export ResultType so callers can compare with r.type
export 'package:open_filex/open_filex.dart' show ResultType;

/// 文件预览类型
enum PreviewKind { image, video, document, unknown }

PreviewKind classifyFile(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return PreviewKind.unknown;
  final ext = path.substring(dot + 1).toLowerCase();
  const images = {
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif', 'svg', 'tiff', 'tif',
  };
  const videos = {
    'mp4', 'mov', 'mkv', 'avi', 'webm', 'flv', 'wmv', 'm4v', '3gp',
  };
  const docs = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'rtf',
    'xmind', 'epub', 'csv', 'json', 'xml', 'html', 'htm', 'odt', 'ods', 'odp',
  };
  if (images.contains(ext)) return PreviewKind.image;
  if (videos.contains(ext)) return PreviewKind.video;
  if (docs.contains(ext)) return PreviewKind.document;
  return PreviewKind.unknown;
}

/// 用系统默认应用打开文件
Future<OpenResult> openWithDefault(String path) {
  return OpenFilex.open(path);
}

/// 在系统文件管理器中打开目录
Future<void> openDirectory(String dirPath) async {
  if (Platform.isWindows) {
    await Process.start('explorer.exe', [dirPath], mode: ProcessStartMode.detached)
        .catchError((_) => Process.start('explorer', [dirPath], mode: ProcessStartMode.detached));
  } else if (Platform.isMacOS) {
    await Process.start('open', [dirPath], mode: ProcessStartMode.detached);
  } else if (Platform.isLinux) {
    await Process.start('xdg-open', [dirPath], mode: ProcessStartMode.detached);
  } else if (Platform.isAndroid) {
    // 安卓：调起系统文件管理器打开目录
    final uri = 'file://$dirPath';
    try {
      await MethodChannel('com.android.documentsui')
          .invokeMethod('view', {'uri': uri});
    } catch (_) {
      try {
        await Process.start(
          'am',
          [
            'start',
            '-a',
            'android.intent.action.VIEW',
            '-d',
            uri,
            '-t',
            'vnd.android.document/directory',
          ],
          mode: ProcessStartMode.detached,
        );
      } catch (_) {}
    }
  } else if (Platform.isIOS) {
    // iOS 沙盒外目录无法直接打开，跳过
  }
}

/// 打开文件所在目录并选中该文件（仅桌面端支持）
Future<void> revealInFolder(String filePath) async {
  if (Platform.isWindows) {
    await Process.start('explorer.exe', ['/select,', filePath], mode: ProcessStartMode.detached);
  } else if (Platform.isMacOS) {
    await Process.start('open', ['-R', filePath], mode: ProcessStartMode.detached);
  } else {
    await openDirectory(File(filePath).parent.path);
  }
}

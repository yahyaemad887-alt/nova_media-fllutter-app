import 'package:photo_manager/photo_manager.dart';

class VideoModel {
  final String id;
  final String title;
  final AssetEntity entity; // بدلاً من String path
  final Duration duration;

  VideoModel({
    required this.id,
    required this.title,
    required this.entity,
    required this.duration,
  });

  // دالة مجانية للحصول على ملف الفيديو الحقيقي في أي وقت
  Future<String?> get filePath async {
    final file = await entity.file;
    return file?.path;
  }
}
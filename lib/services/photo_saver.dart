import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';

class PhotoSaver {
  /// 사진을 갤러리에 저장
  static Future<String?> savePhotoToGallery(XFile imageFile) async {
    try {
      // silent

      // 갤러리 접근 권한 확인
      final hasAccess = await Gal.hasAccess();

      if (!hasAccess) {
        return await _saveToInternalStorage(imageFile);
      }

      // 원본 파일 확인
      final originalFile = File(imageFile.path);
      if (!await originalFile.exists()) {
        return null;
      }

      // silent

      // 갤러리에 사진 저장
      await Gal.putImage(originalFile.path);
      return originalFile.path;
    } catch (e) {
      // 오류 발생 시 앱 내부에 저장
      return await _saveToInternalStorage(imageFile);
    }
  }

  /// 앱 내부 저장소에 사진 저장
  static Future<String?> _saveToInternalStorage(XFile imageFile) async {
    try {
      // silent

      // 앱 문서 디렉토리에 저장
      final documentsDir = await getApplicationDocumentsDirectory();
      final aiPcbDir = Directory('${documentsDir.path}/AI_PCB_Inspector');

      // silent

      // 폴더 생성
      if (!await aiPcbDir.exists()) {
        await aiPcbDir.create(recursive: true);
        // silent
      }

      // 파일명 생성
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'PCB_${timestamp}.jpg';
      final savedPath = '${aiPcbDir.path}/$fileName';

      // silent

      // 원본 파일 복사
      final originalFile = File(imageFile.path);
      await originalFile.copy(savedPath);

      // 복사된 파일 확인
      final savedFile = File(savedPath);
      if (await savedFile.exists()) {
        return savedPath;
      } else {
        // silent
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 갤러리에 사진이 저장되었는지 확인
  static Future<bool> isPhotoSaved(String imagePath) async {
    try {
      final file = File(imagePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// 저장된 사진 목록 가져오기
  static Future<List<File>> getSavedPhotos() async {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) return [];

      final aiPcbDir = Directory('${externalDir.path}/AI_PCB_Inspector');
      if (!await aiPcbDir.exists()) return [];

      final files = await aiPcbDir.list().toList();
      return files
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.jpg'))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

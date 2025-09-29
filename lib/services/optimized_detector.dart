import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Float16 최적화 탐지기
class Float16OptimizedDetector {
  Interpreter? _interpreter;
  
  /// Float16 모델 초기화
  Future<void> initializeFloat16Model() async {
    try {
      print('🔥 Float16 GPU 최적화 모델 초기화 중...');
      
      final options = InterpreterOptions()
        ..threads = 4 // GPU 병렬 처리 최적화
        ..useNnApiForAndroid = false; // GPU 우선, NNAPI는 백업용

      // 🚀 Float16 전용 GPU Delegate 설정 비활성화 (문제 해결을 위해 임시로 비활성화)
      print('ℹ️ Float16 GPU Delegate 비활성화 - CPU 모드로 실행');

      _interpreter = await Interpreter.fromAsset(
        'assets/best_float16.tflite',
        options: options
      );
      
      print('✅ Float16 GPU 최적화 완료');
      
      // 모델 정보 출력
      final inputTensors = _interpreter!.getInputTensors();
      final outputTensors = _interpreter!.getOutputTensors();
      
      print('📊 Float16 모델 정보:');
      print('  - 입력 텐서: ${inputTensors.map((t) => '${t.shape} (${t.type})').join(', ')}');
      print('  - 출력 텐서: ${outputTensors.map((t) => '${t.shape} (${t.type})').join(', ')}');
      
    } catch (e) {
      print('❌ Float16 모델 초기화 실패: $e');
      rethrow;
    }
  }
  
  /// GPU Delegate 활성화 (필요시 사용)
  Future<void> enableGpuDelegate() async {
    if (_interpreter == null) return;
    
    try {
      // 기존 인터프리터 해제
      _interpreter!.close();
      
      final options = InterpreterOptions()
        ..threads = 4
        ..useNnApiForAndroid = false;
      
      // GPU Delegate 설정
      if (Platform.isAndroid) {
        print('🔥 Android GPU Delegate 설정...');
        final gpuDelegate = GpuDelegateV2();
        options.addDelegate(gpuDelegate);
        print('✅ Android GPU Delegate 설정 완료');
      } else if (Platform.isIOS) {
        print('🔥 iOS GPU Delegate 설정...');
        print('ℹ️ iOS GPU Delegate는 기본 설정으로 진행');
      }
      
      _interpreter = await Interpreter.fromAsset(
        'assets/best_float16.tflite',
        options: options
      );
      
      print('✅ GPU Delegate 활성화 완료');
    } catch (e) {
      print('❌ GPU Delegate 활성화 실패: $e');
      // 실패 시 기본 모드로 다시 초기화
      await initializeFloat16Model();
    }
  }
  
  /// 리소스 해제
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    print('🧹 Float16OptimizedDetector 정리 완료');
  }
}

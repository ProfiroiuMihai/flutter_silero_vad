import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:flutter_silero_vad/flutter_silero_vad.dart';

class RecorderService {
  final _audioRecorder = AudioRecorder();
  final vad = FlutterSileroVad();
  bool isRecording = false;
  bool isVadInited = false;
  String? currentRecordingPath;

  final recordings = <String>[];
  final recordingsStreamController = StreamController<List<String>>.broadcast();

  Stream<List<String>> get recordingsStream => recordingsStreamController.stream;

  final int sampleRate = 16000;
  final int frameSize = 512; // 32ms at 16kHz

  StreamSubscription<Uint8List>? _audioStreamSubscription;
  final pauseDetectedStreamController = StreamController<bool>.broadcast();

  Stream<bool> get pauseDetectedStream => pauseDetectedStreamController.stream;

  Future<String> get modelPath async =>
      '${(await getApplicationSupportDirectory()).path}/silero_vad.v5.onnx';

  Future<void> init() async {
    try {
      print('Initializing RecorderService...');
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw Exception('Microphone permission not granted');
      }
      print('Microphone permission granted');

      await initVad();
    } catch (e) {
      print('Error initializing RecorderService: $e');
      rethrow;
    }
  }

  Future<void> initVad() async {
    if (!isVadInited) {
      try {
        print('Initializing VAD...');
        await vad.initialize(
          modelPath: await modelPath,
          sampleRate: sampleRate,
          frameSize: frameSize,
          threshold: 0.5,
          minSilenceDurationMs: 500,
          speechPadMs: 300,
        );
        isVadInited = true;
        print('VAD initialized successfully');
      } catch (e) {
        print('Error initializing VAD: $e');
        rethrow;
      }
    }
  }

  Future<void> startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final directory = await getApplicationDocumentsDirectory();
      currentRecordingPath = '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _audioRecorder.start(
        RecordConfig(  encoder: AudioEncoder.aacLc,
          bitRate: 128000,),
        path: currentRecordingPath!,

      );

      isRecording = true;
      print('Recording started: $currentRecordingPath');

      _startPauseDetection();
    }
  }

  void _startPauseDetection() async {
       final a =  await _audioRecorder.startStream( RecordConfig(  encoder: AudioEncoder.aacLc, bitRate: 128000,));
         a.listen ( (data) async {
      if (data.isNotEmpty) {
        await _processPauseDetection(data);
      }
    });
  }

  Future<void> _processPauseDetection(Uint8List data) async {
    final floatData = Float32List.fromList(
        data.buffer.asInt16List().map((e) => e / 32768.0).toList()
    );

    final isPause = await vad.predict(floatData);
    pauseDetectedStreamController.add(!isPause!);
  }

  Future<void> stopRecording() async {
    if (!isRecording) return;

    final path = await _audioRecorder.stop();
    isRecording = false;
    _audioStreamSubscription?.cancel();

    if (path != null) {
      recordings.add(path);
      recordingsStreamController.add(recordings);
      print('Recording stopped and saved: $path');
    }
  }

  Future<void> toggleRecording() async {
    if (isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  void dispose() {
    _audioStreamSubscription?.cancel();
    recordingsStreamController.close();
    pauseDetectedStreamController.close();
  }
}
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:audio_streamer/audio_streamer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_silero_vad/flutter_silero_vad.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RecorderService {
  final recorder = AudioStreamer.instance;
  final vad = FlutterSileroVad();
  Future<String> get modelPath async =>
      '${(await getApplicationSupportDirectory()).path}/silero_vad.v5.onnx';
  final sampleRate = 16000;
  final frameSize = 40; // 80ms

  bool isInited = false;
  bool isVadInited = false;
  bool isListening = false;
  bool isRecording = false;
  Timer? silenceTimer;

  final int bitsPerSample = 16;
  final int numChannels = 1;

  List<int> currentRecording = [];
  final recordings = <String>[];
  final recordingsStreamController = StreamController<List<String>>.broadcast();

  StreamSubscription<List<int>>? audioStreamSubscription;

  Stream<List<String>> get recordingsStream => recordingsStreamController.stream;

  bool isVadActive = false;
  final silenceDuration = Duration(milliseconds: 1000);  // Adjust this value as needed
  DateTime? lastSpeechDetectedTime;

  Future<void> init() async {
    try {
      print('Initializing RecorderService...');
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        throw Exception('Microphone permission not granted');
      }
      print('Microphone permission granted');

      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));
      print('AudioSession configured');

      await onnxModelToLocal();
      print('ONNX model copied to local storage');

      isInited = true;
      print('RecorderService initialized successfully');
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
          minSilenceDurationMs: 300,
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

  Future<void> startListening() async {
    if (!isInited || !isVadInited) {
      throw Exception('RecorderService or VAD not initialized');
    }

    if (isListening) return;

    isListening = true;
    await recorder.startRecording();

    audioStreamSubscription = recorder.audioStream.listen(
          (buffer) async {
        final data = _transformBuffer(buffer);
        if (data.isEmpty) return;
        await _processAudio(data);
      },
      onError: (error) {
        print('Error in audio stream: $error');
      },
    );
  }

  Future<void> stopListening() async {
    if (!isListening) return;

    isListening = false;
    await recorder.stopRecording();
    audioStreamSubscription?.cancel();
    if (isRecording) {
      await _stopRecording();
    }
  }

  Future<void> _processAudio(List<int> buffer) async {
    final transformedBufferFloat = buffer.map((e) => e / 32768).toList();

    try {
      final isActivated = await vad.predict(Float32List.fromList(transformedBufferFloat));
      print('VAD active: $isActivated');

      if (isActivated == true) {
        _handleSpeechDetected(buffer);
      } else {
        _handleSilenceDetected();
      }
    } catch (e) {
      print('Error in VAD prediction: $e');
    }
  }

  void _handleSpeechDetected(List<int> buffer) {
    isVadActive = true;
    lastSpeechDetectedTime = DateTime.now();
    silenceTimer?.cancel();  // Cancel any existing silence timer
    silenceTimer = null;  // Reset the silence timer
    _startOrContinueRecording(buffer);
  }

  void _handleSilenceDetected() {
    isVadActive = false;
    if (isRecording && silenceTimer == null) {
      // Only start a new silence timer if we're recording and don't already have one
      silenceTimer = Timer(silenceDuration, _checkAndStopRecording);
    }
  }

  void _startOrContinueRecording(List<int> buffer) {
    if (!isRecording) {
      isRecording = true;
      currentRecording.clear();
      print('Started new recording');
    }
    currentRecording.addAll(buffer);
    print('Added ${buffer.length} bytes to recording');
  }

  void _checkAndStopRecording() {
    if (!isVadActive && isRecording) {
      if (lastSpeechDetectedTime != null &&
          DateTime.now().difference(lastSpeechDetectedTime!) >= silenceDuration) {
        _stopRecording();
      }
    }
    silenceTimer = null;  // Reset the silence timer after it's fired
  }




  Future<void> _stopRecording() async {
    if (!isRecording) return;

    isRecording = false;
    silenceTimer?.cancel();

    if (currentRecording.isNotEmpty) {
      await _saveRecording();
    }
    currentRecording.clear();
  }

  Future<void> _saveRecording() async {
    final outputPath = '${(await getApplicationDocumentsDirectory()).path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
    saveAsWav(currentRecording, outputPath);
    recordings.add(outputPath);
    recordingsStreamController.add(recordings);
    print('Audio saved to: $outputPath');
  }

  Int16List _transformBuffer(List<int> buffer) {
    final bytes = Uint8List.fromList(buffer);
    return Int16List.view(bytes.buffer);
  }


  Future<void> onnxModelToLocal() async {
    try {
      print('Copying ONNX model to local storage...');
      final data = await rootBundle.load('assets/silero_vad.v5.onnx');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final file = File(await modelPath);
      await file.writeAsBytes(bytes);
      print('ONNX model copied successfully. File size: ${file.lengthSync()} bytes');
    } catch (e) {
      print('Error copying ONNX model: $e');
      rethrow;
    }
  }

  void dispose() {
    stopListening();
    recordingsStreamController.close();
  }

  void saveAsWav(List<int> buffer, String filePath) {
    // PCMデータの変換
    final bytes = Uint8List.fromList(buffer);
    final pcmData = Int16List.view(bytes.buffer);
    final byteBuffer = ByteData(pcmData.length * 2);

    for (var i = 0; i < pcmData.length; i++) {
      byteBuffer.setInt16(i * 2, pcmData[i], Endian.little);
    }

    final wavHeader = ByteData(44);
    final pcmBytes = byteBuffer.buffer.asUint8List();

    // RIFFチャンク
    wavHeader
      ..setUint8(0x00, 0x52) // 'R'
      ..setUint8(0x01, 0x49) // 'I'
      ..setUint8(0x02, 0x46) // 'F'
      ..setUint8(0x03, 0x46) // 'F'
      ..setUint32(4, 36 + pcmBytes.length, Endian.little) // ChunkSize
      ..setUint8(0x08, 0x57) // 'W'
      ..setUint8(0x09, 0x41) // 'A'
      ..setUint8(0x0A, 0x56) // 'V'
      ..setUint8(0x0B, 0x45) // 'E'
      ..setUint8(0x0C, 0x66) // 'f'
      ..setUint8(0x0D, 0x6D) // 'm'
      ..setUint8(0x0E, 0x74) // 't'
      ..setUint8(0x0F, 0x20) // ' '
      ..setUint32(16, 16, Endian.little) // Subchunk1Size
      ..setUint16(20, 1, Endian.little) // AudioFormat
      ..setUint16(22, numChannels, Endian.little) // NumChannels
      ..setUint32(24, sampleRate, Endian.little) // SampleRate
      ..setUint32(
        28,
        sampleRate * numChannels * bitsPerSample ~/ 8,
        Endian.little,
      ) // ByteRate
      ..setUint16(
        32,
        numChannels * bitsPerSample ~/ 8,
        Endian.little,
      ) // BlockAlign
      ..setUint16(34, bitsPerSample, Endian.little) // BitsPerSample

    // dataチャンク
      ..setUint8(0x24, 0x64) // 'd'
      ..setUint8(0x25, 0x61) // 'a'
      ..setUint8(0x26, 0x74) // 't'
      ..setUint8(0x27, 0x61) // 'a'
      ..setUint32(40, pcmBytes.length, Endian.little); // Subchunk2Size

    File(filePath).writeAsBytesSync(wavHeader.buffer.asUint8List() + pcmBytes);
  }
  }

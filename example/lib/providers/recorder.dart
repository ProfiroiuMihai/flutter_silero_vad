import 'package:flutter_silero_vad_example/services/recorder.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final recorderProvider = Provider((ref) => RecorderService());

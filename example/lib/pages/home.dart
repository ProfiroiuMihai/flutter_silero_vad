import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_silero_vad_example/providers/recorder.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'components.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useStreamController<List<int>>();
    final spots = useState<List<int>>([]);
    final isInitialized = useState(false);
    final isRecording = useState(false);
    final errorMessage = useState<String?>(null);

    useEffect(
          () {
        Future.microtask(() async {
          try {
            final recorderService = ref.read(recoderProvider);
            await recorderService.init();
            isInitialized.value = true;
          } catch (e) {
            errorMessage.value = 'Error initializing: $e';
          }
        });

        return null;
      },
      [],
    );

    if (!isInitialized.value) {
      return Scaffold(
        body: Center(
          child: errorMessage.value != null
              ? Text(errorMessage.value!)
              : const CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Waveform(audioData: spots.value),
          const SizedBox(height: 20),
          if (errorMessage.value != null)
            Text(errorMessage.value!, style: TextStyle(color: Colors.red)),
          ElevatedButton(
            onPressed: () async {
              try {
                if (isRecording.value) {
                  await ref.read(recoderProvider).stopRecorder();
                  isRecording.value = false;
                } else {
                  // Initialize VAD before starting recording
                  await ref.read(recoderProvider).initVad();
                  await ref.read(recoderProvider).record(controller);
                  isRecording.value = true;

                  controller.stream.listen(
                        (event) {
                      spots.value = event;
                    },
                    onError: (error) {
                      errorMessage.value = 'Error during recording: $error';
                      isRecording.value = false;
                    },
                  );
                }
                errorMessage.value = null;
              } catch (e) {
                errorMessage.value = 'Error: $e';
                isRecording.value = false;
              }
            },
            child: Text(isRecording.value ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }
}
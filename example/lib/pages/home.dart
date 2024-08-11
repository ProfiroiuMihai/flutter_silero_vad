import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_silero_vad_example/services/recorder.dart';
import 'package:flutter_silero_vad_example/providers/recorder.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;

class HomePage extends HookConsumerWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recorderService = ref.watch(recorderProvider);
    final isInitialized = useState(false);
    final isListening = useState(false);
    final errorMessage = useState<String?>(null);
    final player = useMemoized(() => AudioPlayer(), []);
    final isPlaying = useState(false);
    final currentPlayingIndex = useState<int?>(-1);

    useEffect(() {
      Future<void> initializeRecorder() async {
        try {
          await recorderService.init();
          await recorderService.initVad();
          isInitialized.value = true;
        } catch (e) {
          errorMessage.value = 'Error initializing: $e';
        }
      }

      initializeRecorder();

      return () {
        recorderService.dispose();
        player.dispose();
      };
    }, []);

    final recordings = useStream(recorderService.recordingsStream).data ?? [];

    Future<void> playRecording(String filePath, int index) async {
      // ... (keep existing playRecording function)
    }

    Future<void> shareRecording(String filePath) async {
      try {
        print('Attempting to share file: $filePath');
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('File does not exist');
        }
        print('File size: ${await file.length()} bytes');

        final result = await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Check out this audio recording!',
        );

        print('Share result: ${result.status}');
        if (result.status == ShareResultStatus.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Shared successfully')),
          );
        } else {
          throw Exception('Sharing failed: ${result.status}');
        }
      } catch (e) {
        print('Error sharing file: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing file: $e')),
        );
      }
    }

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
      appBar: AppBar(title: Text('Audio Recorder')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: recordings.length,
              itemBuilder: (context, index) {
                final filePath = recordings[index];
                final fileName = path.basename(filePath);
                return ListTile(
                  title: Text('Recording ${index + 1}'),
                  subtitle: Text(fileName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          currentPlayingIndex.value == index && isPlaying.value
                              ? Icons.stop
                              : Icons.play_arrow,
                        ),
                        onPressed: () => playRecording(filePath, index),
                      ),
                      IconButton(
                        icon: Icon(Icons.share),
                        onPressed: () => shareRecording(filePath),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (errorMessage.value != null)
            Text(errorMessage.value!, style: TextStyle(color: Colors.red)),
          ElevatedButton(
            onPressed: () async {
              try {
                if (isListening.value) {
                  await recorderService.stopListening();
                } else {
                  await recorderService.startListening();
                }
                isListening.value = !isListening.value;
                errorMessage.value = null;
              } catch (e) {
                errorMessage.value = 'Error: $e';
                isListening.value = false;
              }
            },
            child: Text(isListening.value ? 'Stop Listening' : 'Start Listening'),
          ),
        ],
      ),
    );
  }
}
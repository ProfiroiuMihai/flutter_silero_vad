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
    final isRecording = useState(false);
    final isPaused = useState(false);
    final currentPlayingIndex = useState<int?>(null);

    // Initialize the recorder service
    useEffect(() {
      recorderService.init().then((_) {
        isInitialized.value = true;
      }).catchError((error) {
        print('Error initializing recorder: $error');
      });
      return null;
    }, []);

    // Listen for pause detection
    useEffect(() {
      final subscription = recorderService.pauseDetectedStream.listen((paused) {
        isPaused.value = paused;
      });
      return subscription.cancel;
    }, [recorderService]);

    // Get the list of recordings
    final recordings = useStream(recorderService.recordingsStream).data ?? [];

    // Audio player for playback
    final player = useMemoized(() => AudioPlayer(), []);

    // Function to toggle recording
    Future<void> toggleRecording() async {
      try {
        await recorderService.toggleRecording();
        isRecording.value = recorderService.isRecording;
      } catch (e) {
        print('Error toggling recording: $e');
      }
    }

    // Function to play/stop a recording
    Future<void> playRecording(String filePath, int index) async {
      if (currentPlayingIndex.value == index) {
        await player.stop();
        currentPlayingIndex.value = null;
      } else {
        await player.stop();
        await player.play(DeviceFileSource(filePath));
        currentPlayingIndex.value = index;
        player.onPlayerComplete.listen((_) {
          currentPlayingIndex.value = null;
        });
      }
    }

    // Function to share a recording
    Future<void> shareRecording(String filePath) async {
      try {
        await Share.shareXFiles([XFile(filePath)], text: 'Check out this audio recording!');
      } catch (e) {
        print('Error sharing file: $e');
      }
    }

    if (!isInitialized.value) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
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
                final isPlaying = currentPlayingIndex.value == index;
                return ListTile(
                  title: Text('Recording ${index + 1}'),
                  subtitle: Text(fileName),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
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
          if (isRecording.value)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                isPaused.value ? 'Speech Paused' : 'Speech Detected',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: toggleRecording,
              child: Text(isRecording.value ? 'Stop Recording' : 'Start Recording'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
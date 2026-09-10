import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

import '../data/file_storage.dart';

class MediaService {
  MediaService(this.storage);

  final FileStorage storage;
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder recorder = AudioRecorder();
  final AudioPlayer player = AudioPlayer();

  Future<File?> pickPhoto({
    required ImageSource source,
    required String id,
  }) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 2200,
    );
    if (picked == null) return null;
    final extension = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path).toLowerCase();
    return storage.copyAttachment(
      sourcePath: picked.path,
      id: id,
      kind: 'photo',
      extension: extension,
    );
  }

  Future<List<XFile>> retrieveLostPhotos() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty || response.exception != null) return [];
    return response.files ?? const [];
  }

  Future<String> startRecording(String attachmentId) async {
    if (!await recorder.hasPermission()) {
      throw StateError(
        'Permissão de microfone negada. Autorize-a nas configurações do aplicativo.',
      );
    }
    final target = await storage.audioTarget(attachmentId);
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: target.path,
    );
    return target.path;
  }

  Future<String?> stopRecording() => recorder.stop();
  Future<void> cancelRecording() => recorder.cancel();

  Future<void> play(String relativePath) async {
    final path = await storage.absolutePath(relativePath);
    await player.play(DeviceFileSource(path));
  }

  Future<void> stopPlayback() => player.stop();

  Future<void> dispose() async {
    await recorder.dispose();
    await player.dispose();
  }
}

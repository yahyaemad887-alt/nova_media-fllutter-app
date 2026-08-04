import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => NovaAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.nova.media.audio',
      androidNotificationChannelName: 'Nova Media playback',
      androidNotificationChannelDescription: 'مشغل الصوتيات الخلفي لتطبيق نوفا ميديا',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}

class NovaAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  NovaAudioHandler() {
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForSequenceStateChanges(); // لمراقبة تغيير الأغاني في القائمة
    _listenForCurrentSongCompletion();
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }

  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      if (queue.value.isNotEmpty && index != null && index < queue.value.length) {
        final oldMediaItem = queue.value[index];
        final newMediaItem = oldMediaItem.copyWith(duration: duration);
        queue.value[index] = newMediaItem;
        mediaItem.add(newMediaItem);
      }
    });
  }

  // تحديث بيانات الأغنية الحالية في الإشعار عند الانتقال التلقائي
  void _listenForSequenceStateChanges() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;

      final items = sequence.map((source) => source.tag as MediaItem).toList();
      queue.add(items);

      final currentIndex = sequenceState?.currentIndex;
      if (currentIndex != null && currentIndex < items.length) {
        mediaItem.add(items[currentIndex]);
      }
    });
  }

  void _listenForCurrentSongCompletion() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        // لو مفيش أغنية بعدها، وإحنا مش مفعلين التكرار، نوقف الصوت
        if (!_player.hasNext) {
          pause();
          seek(Duration.zero);
        }
      }
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  // تفعيل التكرار (Repeat)
  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await _player.setLoopMode(LoopMode.all);
        break;
    }
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  // تفعيل التشغيل العشوائي (Shuffle)
  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      await _player.setShuffleModeEnabled(false);
    } else {
      await _player.setShuffleModeEnabled(true);
      await _player.shuffle();
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  // دالة جديدة لتشغيل قائمة كاملة عشان التشغيل التلقائي يشتغل
  Future<void> loadPlaylist(List<MediaItem> songs, int initialIndex) async {
    final audioSource = ConcatenatingAudioSource(
      children: songs.map((item) {
        return AudioSource.uri(
          Uri.parse(item.id),
          tag: item,
        );
      }).toList(),
    );

    await _player.setAudioSource(audioSource, initialIndex: initialIndex);
    play();
  }

  // احتفظنا بالدالة القديمة في حال احتجتها
  Future<void> playSong(String uri, String title, String artist) async {
    try {
      final item = MediaItem(
        id: uri,
        album: "Nova Media",
        title: title,
        artist: artist,
      );

      mediaItem.add(item);
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri), tag: item));
      play();
    } catch (e) {
      print("Error playing audio: $e");
    }
  }
}
// ====================================================================
// ADVANCED AUDIO HANDLER - LARK PLAYER BACKGROUND PLAYBACK ENGINE
// ====================================================================

import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// تهيئة خدمة الصوت الخلفية مع دعم التدويل وتخصيص الإشعارات
Future<AudioHandler> initAudioService({
  String channelId = 'com.nova.media.audio',
  String channelName = 'Nova Media Playback',
  String channelDescription = 'Background media playback service for Nova Media',
}) async {
  return await AudioService.init(
    builder: () => NovaAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: channelId,
      androidNotificationChannelName: channelName,
      androidNotificationChannelDescription: channelDescription,
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/ic_launcher',
    ),
  );
}

class NovaAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(children: []);
  AndroidLoudnessEnhancer? _loudnessEnhancer;

  NovaAudioHandler() {
    _initAudioSession();
    _initAudioEffects();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenForDurationChanges();
    _listenForSequenceStateChanges();
    _listenForCurrentSongCompletion();
  }

  /// إعداد جلسة الصوت للتعامل مع المكالمات وفصل السماعات
  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(0.5);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.pause:
            play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    session.becomingNoisyEventStream.listen((_) {
      pause(); // إيقاف التشغيل عند نزع السماعة
    });
  }

  /// تهيئة محرك تحسين الصوت
  void _initAudioEffects() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      _loudnessEnhancer!.setEnabled(true);
    }
  }

  /// ربط حالة التشغيل مع أزرار التحكم في الإشعارات وشريط القفل
  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen(
          (PlaybackEvent event) {
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
            MediaAction.setRepeatMode,
            MediaAction.setShuffleMode,
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
      },
      onError: (Object e, StackTrace stackTrace) {
        if (kDebugMode) print('Playback Event Error: $e');
      },
    );
  }

  /// تحديث مدة المقطع داخل القائمة بدون كسر الـ Stream
  void _listenForDurationChanges() {
    _player.durationStream.listen((duration) {
      final index = _player.currentIndex;
      final currentQueue = queue.value;
      if (currentQueue.isNotEmpty && index != null && index < currentQueue.length) {
        final updatedList = List<MediaItem>.from(currentQueue);
        final oldMediaItem = updatedList[index];
        final newMediaItem = oldMediaItem.copyWith(duration: duration);

        updatedList[index] = newMediaItem;
        queue.add(updatedList);
        mediaItem.add(newMediaItem);
      }
    });
  }

  /// مراقبة تغيير المقاطع في القائمة وتحديث الإشعارات تلقائياً
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

  /// التعامل مع انتهاء تشغيل المقطع الحالي
  void _listenForCurrentSongCompletion() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (!_player.hasNext && _player.loopMode == LoopMode.off) {
          pause();
          seek(Duration.zero);
        }
      }
    });
  }

  // ====================================================================
  // BASIC AUDIO CONTROLS
  // ====================================================================

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
    await _player.dispose();
    return super.stop();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    playbackState.add(playbackState.value.copyWith(speed: speed));
  }

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

  // ====================================================================
  // QUEUE MANAGEMENT & ADVANCED PLAYBACK
  // ====================================================================

  /// تحميل قائمة تشغيل كاملة
  /// تحميل قائمة تشغيل كاملة
  Future<void> loadPlaylist(List<MediaItem> songs, int initialIndex) async {
    try {
      if (songs.isEmpty) return;

      _playlist = ConcatenatingAudioSource(
        useLazyPreparation: true,
        children: songs.map((item) {
          return AudioSource.uri(
            Uri.parse(item.id),
            tag: item,
          );
        }).toList(),
      );

      queue.add(songs);

      // ⚠️ خطوة أساسية: تعيين الأغنية الحالية في الـ mediaItem فوراً عشان الإشعار يظهر
      mediaItem.add(songs[initialIndex]);

      await _player.setAudioSource(_playlist, initialIndex: initialIndex);
      play();
    } catch (e) {
      if (kDebugMode) print("Error loading playlist: $e");
    }
  }

  /// إدراج عنصر جديد في القائمة أثناء التشغيل
  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    try {
      final audioSource = AudioSource.uri(Uri.parse(mediaItem.id), tag: mediaItem);
      await _playlist.add(audioSource);
      final newQueue = List<MediaItem>.from(queue.value)..add(mediaItem);
      queue.add(newQueue);
    } catch (e) {
      if (kDebugMode) print("Error adding item to queue: $e");
    }
  }

  /// إزالة عنصر محدد من قائمة التشغيل
  @override
  Future<void> removeQueueItemAt(int index) async {
    try {
      if (index >= 0 && index < _playlist.length) {
        await _playlist.removeAt(index);
        final newQueue = List<MediaItem>.from(queue.value)..removeAt(index);
        queue.add(newQueue);
      }
    } catch (e) {
      if (kDebugMode) print("Error removing item from queue: $e");
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    try {
      if (index >= 0 && index < _playlist.length) {
        await _player.seek(Duration.zero, index: index);
        play();
      }
    } catch (e) {
      if (kDebugMode) print("Error skipping to queue index: $e");
    }
  }

  /// تشغيل أغنية منفردة مباشرة
  Future<void> playSong(String uri, String title, String artist, {String? artUri}) async {
    try {
      final item = MediaItem(
        id: uri,
        album: "Nova Media",
        title: title,
        artist: artist,
        artUri: artUri != null ? Uri.parse(artUri) : null,
      );

      mediaItem.add(item);
      queue.add([item]);
      await _player.setAudioSource(AudioSource.uri(Uri.parse(uri), tag: item));
      play();
    } catch (e) {
      if (kDebugMode) print("Error playing song: $e");
    }
  }

  // ====================================================================
  // CUSTOM ACTIONS (Equalizer & DSP)
  // ====================================================================

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == 'setBassBoost') {
      final double gain = extras?['gain'] ?? 0.0;
      if (_loudnessEnhancer != null) {
        await _loudnessEnhancer!.setTargetGain(gain);
      }
    } else if (name == 'setVolume') {
      final double volume = extras?['volume'] ?? 1.0;
      await _player.setVolume(volume);
    }
    return super.customAction(name, extras);
  }
}
// ====================================================================
// FULL PRODUCTION MEDIA SERVICES LAYER - LARK PLAYER ARCHITECTURE
// WITH FULL BACKGROUND AUDIO SERVICE & NOTIFICATIONS SUPPORT
// ====================================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Video_model.dart';

// --------------------------------------------------------------------
// MODEL: Synced Lyric Line Structure
// --------------------------------------------------------------------
class LyricLine {
  final Duration timeStamp;
  final String text;

  LyricLine({required this.timeStamp, required this.text});
}

// ====================================================================
// 0. AUDIO HANDLER FOR BACKGROUND & NOTIFICATIONS (Lark Player Core)
// ====================================================================
class LarkAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  AndroidLoudnessEnhancer? _loudnessEnhancer;

  LarkAudioHandler() {
    _initEngine();
    _listenToPlayerEvents();
  }

  void _initEngine() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      _loudnessEnhancer!.setEnabled(true);
    }
  }

  void _listenToPlayerEvents() {
    // تحديث حالة التشغيل والإشعارات عند أي تغيير في الصوت أو حالة المشغل
    _player.playbackEventStream.listen((_) => _updatePlaybackState());
    _player.playerStateStream.listen((_) => _updatePlaybackState());

    // تحديث الـ MediaItem فور تغير الأغنية في القائمة
    _player.currentIndexStream.listen((index) {
      if (index != null && _player.audioSource is ConcatenatingAudioSource) {
        final concatenatingSource = _player.audioSource as ConcatenatingAudioSource;
        if (index < concatenatingSource.children.length) {
          final source = concatenatingSource.children[index] as UriAudioSource;
          final currentMediaItem = source.tag as MediaItem?;
          if (currentMediaItem != null) {
            mediaItem.add(currentMediaItem);
          }
        }
      }
    });
  }

  void _updatePlaybackState() {
    final playing = _player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
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
        queueIndex: _player.currentIndex,
      ),
    );
  }

  AudioPlayer get player => _player;
  AndroidLoudnessEnhancer? get loudnessEnhancer => _loudnessEnhancer;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }
}

// Global Audio Handler Instance initialization function for main()
late final LarkAudioHandler audioHandler;

Future<void> initAudioServiceHandler() async {
  audioHandler = await AudioService.init(
    builder: () => LarkAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.nova.media.audio.channel',
      androidNotificationChannelName: 'Nova Media Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'mipmap/launcher_icon', // تم التصحيح لتطابق الـ Manifest
    ),
  );
}

// ====================================================================
// 1. MAIN SERVICE (Permissions, File System Auditing & Stats)
// ====================================================================
class MainService {
  static final MainService _instance = MainService._internal();
  factory MainService() => _instance;
  MainService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<bool> requestStoragePermission() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // طلب إذن الإشعارات لأندرويد 13+
        if (await Permission.notification.isDenied) {
          await Permission.notification.request();
        }

        final audioStatus = await Permission.audio.status;
        final videoStatus = await Permission.videos.status;
        final storageStatus = await Permission.storage.status;

        if (audioStatus.isGranted || storageStatus.isGranted) {
          return true;
        }

        Map<Permission, PermissionStatus> statuses = await [
          Permission.audio,
          Permission.videos,
          Permission.storage,
          Permission.notification,
        ].request();

        return statuses.values.any((status) => status.isGranted);
      }
      return (await Permission.storage.request()).isGranted;
    } catch (e) {
      if (kDebugMode) print('MainService Permission Error: $e');
      return false;
    }
  }

  Future<Map<String, int>> fetchRealMediaStats() async {
    try {
      bool hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        return {'totalVideos': 0, 'totalAudio': 0, 'totalPlaylists': 0, 'totalArtists': 0};
      }

      final prefs = await SharedPreferences.getInstance();
      final bool hideShortAudio = prefs.getBool('hide_short_audio') ?? true;
      final int minDuration = prefs.getInt('min_audio_duration_ms') ?? 30000;

      List<SongModel> songs = await _audioQuery.querySongs(
        ignoreCase: true,
        uriType: UriType.EXTERNAL,
      );

      if (hideShortAudio) {
        songs = songs.where((s) => (s.duration ?? 0) >= minDuration).toList();
      }

      List<ArtistModel> artists = await _audioQuery.queryArtists(uriType: UriType.EXTERNAL);
      List<PlaylistModel> playlists = await _audioQuery.queryPlaylists(uriType: UriType.EXTERNAL);
      List<File> videos = await VideoService().fetchDeviceVideos();

      return {
        'totalVideos': videos.length,
        'totalAudio': songs.length,
        'totalPlaylists': playlists.length,
        'totalArtists': artists.length,
      };
    } catch (e) {
      if (kDebugMode) print('MainService Fetch Stats Error: $e');
      return {'totalVideos': 0, 'totalAudio': 0, 'totalPlaylists': 0, 'totalArtists': 0};
    }
  }
}

// ====================================================================
// 2. MUSIC SERVICE (Advanced Queries, Sorting & Favorites)
// ====================================================================
class MusicService {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();
  static const String _keyFavorites = 'favorite_songs_list';
  static const String _keyRecentlyPlayed = 'recently_played_list';

  Future<List<SongModel>> fetchAllSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool hideShortAudio = prefs.getBool('hide_short_audio') ?? true;
      final int minDuration = prefs.getInt('min_audio_duration_ms') ?? 30000;

      List<SongModel> songs = await _audioQuery.querySongs(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        sortType: SongSortType.TITLE,
      );

      if (hideShortAudio) {
        songs = songs.where((song) => (song.duration ?? 0) >= minDuration).toList();
      }

      return songs;
    } catch (e) {
      if (kDebugMode) print('MusicService Fetch Songs Error: $e');
      return [];
    }
  }

  Future<List<SongModel>> searchSongs(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      List<SongModel> allSongs = await fetchAllSongs();
      final q = query.toLowerCase();
      return allSongs.where((song) {
        final title = song.title.toLowerCase();
        final artist = song.artist?.toLowerCase() ?? '';
        final album = song.album?.toLowerCase() ?? '';
        return title.contains(q) || artist.contains(q) || album.contains(q);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  List<SongModel> sortSongs(List<SongModel> songs, SongSortType sortType, {bool ascending = true}) {
    List<SongModel> list = List.from(songs);
    list.sort((a, b) {
      int res = 0;
      switch (sortType) {
        case SongSortType.TITLE:
          res = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case SongSortType.DURATION:
          res = (a.duration ?? 0).compareTo(b.duration ?? 0);
          break;
        case SongSortType.DATE_ADDED:
          res = (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0);
          break;
        case SongSortType.SIZE:
          res = (a.size ?? 0).compareTo(b.size ?? 0);
          break;
        default:
          res = a.title.compareTo(b.title);
      }
      return ascending ? res : -res;
    });
    return list;
  }

  Future<bool> toggleFavorite(int songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> favs = prefs.getStringList(_keyFavorites) ?? [];
      final idStr = songId.toString();

      if (favs.contains(idStr)) {
        favs.remove(idStr);
      } else {
        favs.add(idStr);
      }
      await prefs.setStringList(_keyFavorites, favs);
      return favs.contains(idStr);
    } catch (e) {
      return false;
    }
  }

  Future<bool> isFavorite(int songId) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> favs = prefs.getStringList(_keyFavorites) ?? [];
    return favs.contains(songId.toString());
  }

  Future<List<SongModel>> fetchFavoriteSongs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> favs = prefs.getStringList(_keyFavorites) ?? [];
      List<SongModel> allSongs = await fetchAllSongs();
      return allSongs.where((s) => favs.contains(s.id.toString())).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addToRecentlyPlayed(int songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> recent = prefs.getStringList(_keyRecentlyPlayed) ?? [];
      final idStr = songId.toString();

      recent.remove(idStr);
      recent.insert(0, idStr);
      if (recent.length > 100) recent = recent.sublist(0, 100);

      await prefs.setStringList(_keyRecentlyPlayed, recent);
    } catch (e) {
      if (kDebugMode) print('Recently Played Error: $e');
    }
  }
}

// ====================================================================
// 3. AUDIO PLAYER & EQUALIZER SERVICE (Lark Player Core Engine Wrapper)
// ====================================================================
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  AudioPlayer get player => audioHandler.player;

  Future<void> setPlaylist(List<SongModel> songs, int initialIndex) async {
    try {
      if (songs.isEmpty || initialIndex < 0 || initialIndex >= songs.length) return;

      final currentSong = songs[initialIndex];

      final initialMediaItem = MediaItem(
        id: currentSong.id.toString(),
        album: currentSong.album ?? 'Unknown Album',
        title: currentSong.title,
        artist: currentSong.artist ?? 'Unknown Artist',
        duration: Duration(milliseconds: currentSong.duration ?? 0),
        artUri: null, // إزالة مسار الـ assets غير المدعوم في الإشعارات
      );

      audioHandler.mediaItem.add(initialMediaItem);

      final playlist = ConcatenatingAudioSource(
        useLazyPreparation: true,
        children: songs.map((song) {
          return AudioSource.uri(
            Uri.parse(song.uri!),
            tag: MediaItem(
              id: song.id.toString(),
              album: song.album ?? 'Unknown Album',
              title: song.title,
              artist: song.artist ?? 'Unknown Artist',
              duration: Duration(milliseconds: song.duration ?? 0),
              artUri: null,
            ),
          );
        }).toList(),
      );

      await audioHandler.player.setAudioSource(playlist, initialIndex: initialIndex);
      await audioHandler.play();

      MusicService().addToRecentlyPlayed(currentSong.id);
    } catch (e) {
      if (kDebugMode) print('AudioPlayer SetPlaylist Error: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (audioHandler.player.playing) {
      await audioHandler.pause();
    } else {
      await audioHandler.play();
    }
  }

  Future<void> playNext() async => await audioHandler.skipToNext();

  Future<void> playPrevious() async => await audioHandler.skipToPrevious();

  Future<void> seekTo(Duration position) async => await audioHandler.seek(position);

  Future<void> setPlaybackSpeed(double speed) async => await audioHandler.player.setSpeed(speed);

  Future<void> setBassBoostGain(double targetGain) async {
    if (audioHandler.loudnessEnhancer != null) {
      await audioHandler.loudnessEnhancer!.setTargetGain(targetGain);
    }
  }

  Future<void> setVolume(double volume) async => await audioHandler.player.setVolume(volume.clamp(0.0, 1.0));

  Future<void> toggleRepeat() async {
    final current = audioHandler.player.loopMode;
    if (current == LoopMode.off) {
      await audioHandler.player.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      await audioHandler.player.setLoopMode(LoopMode.one);
    } else {
      await audioHandler.player.setLoopMode(LoopMode.off);
    }
  }

  Future<void> toggleShuffle() async {
    final enabled = audioHandler.player.shuffleModeEnabled;
    await audioHandler.player.setShuffleModeEnabled(!enabled);
  }
}

// ====================================================================
// 4. LYRICS ENGINE SERVICE (Synced LRC Parsing & Processing)
// ====================================================================
class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  List<LyricLine> parseLrc(String lrcContent) {
    final List<LyricLine> lines = [];
    final RegExp timeRegExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');

    for (var line in lrcContent.split('\n')) {
      final matches = timeRegExp.allMatches(line);
      if (matches.isNotEmpty) {
        final text = line.replaceAll(timeRegExp, '').trim();
        for (var match in matches) {
          final min = int.parse(match.group(1)!);
          final sec = int.parse(match.group(2)!);
          final msStr = match.group(3)!.padRight(3, '0');
          final ms = int.parse(msStr.substring(0, 3));

          final timestamp = Duration(minutes: min, seconds: sec, milliseconds: ms);
          lines.add(LyricLine(timeStamp: timestamp, text: text));
        }
      }
    }
    lines.sort((a, b) => a.timeStamp.compareTo(b.timeStamp));
    return lines;
  }

  Future<List<LyricLine>> fetchLocalLyrics(String songFilePath) async {
    try {
      final lrcPath = songFilePath.replaceAll(RegExp(r'\.[^.]+$'), '.lrc');
      final file = File(lrcPath);

      if (await file.exists()) {
        final content = await file.readAsString();
        return parseLrc(content);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  int getCurrentLyricIndex(List<LyricLine> lyrics, Duration currentPosition) {
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (currentPosition >= lyrics[i].timeStamp) {
        return i;
      }
    }
    return 0;
  }
}

// ====================================================================
// 5. SLEEP TIMER SERVICE (Smart Fade-Out Countdown Engine)
// ====================================================================
class SleepTimerService {
  static final SleepTimerService _instance = SleepTimerService._internal();
  factory SleepTimerService() => _instance;
  SleepTimerService._internal();

  Timer? _timer;
  final StreamController<int> _controller = StreamController<int>.broadcast();

  Stream<int> get remainingTimeStream => _controller.stream;
  bool get isActive => _timer != null && _timer!.isActive;

  void startTimer(int minutes) {
    cancelTimer();
    int totalSeconds = minutes * 60;
    _controller.add(totalSeconds);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      totalSeconds--;
      _controller.add(totalSeconds);

      if (totalSeconds <= 10 && totalSeconds > 0) {
        final currentVol = totalSeconds / 10.0;
        await AudioPlayerService().setVolume(currentVol);
      }

      if (totalSeconds <= 0) {
        await AudioPlayerService().player.pause();
        await AudioPlayerService().setVolume(1.0);
        cancelTimer();
      }
    });
  }

  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _controller.add(0);
  }

  void dispose() {
    _controller.close();
  }
}

// ====================================================================
// 6. VIDEO SERVICE (Directory Scanner & PhotoManager Integration)
// ====================================================================
class VideoService {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  Future<List<File>> fetchDeviceVideos() async {
    try {
      List<File> videoFiles = [];
      List<Directory>? dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);

      if (dirs == null || dirs.isEmpty) {
        dirs = [await getApplicationDocumentsDirectory()];
      }

      final validExtensions = {'.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp', '.flv', '.ts'};

      for (var dir in dirs) {
        final rootPath = dir.path.split('Android')[0];
        final rootDir = Directory(rootPath);

        if (await rootDir.exists()) {
          await for (var entity in rootDir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final ext = path.extension(entity.path).toLowerCase();
              if (validExtensions.contains(ext)) {
                if (!entity.path.contains('.private_vault')) {
                  videoFiles.add(entity);
                }
              }
            }
          }
        }
      }
      return videoFiles;
    } catch (e) {
      if (kDebugMode) print('VideoService Error: $e');
      return [];
    }
  }

  static Future<List<VideoModel>> fetchLocalVideos() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) return [];

      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );

      if (albums.isEmpty) return [];

      List<AssetEntity> media = await albums[0].getAssetListPaged(page: 0, size: 500);

      return media.map((asset) => VideoModel(
        id: asset.id,
        title: asset.title ?? 'Un-named Video',
        entity: asset,
        duration: asset.videoDuration,
      )).toList();
    } catch (e) {
      return [];
    }
  }
}

// ====================================================================
// 7. PRIVATE VAULT SERVICE (Secure Isolation with .nomedia)
// ====================================================================
class VaultService {
  static final VaultService _instance = VaultService._internal();
  factory VaultService() => _instance;
  VaultService._internal();

  Future<Directory> _getVaultDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${appDir.path}/.private_vault');
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
      final noMediaFile = File('${vaultDir.path}/.nomedia');
      if (!await noMediaFile.exists()) {
        await noMediaFile.create();
      }
    }
    return vaultDir;
  }

  Future<bool> hideFile(File sourceFile) async {
    try {
      if (!await sourceFile.exists()) return false;
      final vaultDir = await _getVaultDirectory();
      final fileName = path.basename(sourceFile.path);
      final destination = File('${vaultDir.path}/$fileName');

      await sourceFile.copy(destination.path);
      await sourceFile.delete();
      return true;
    } catch (e) {
      if (kDebugMode) print('Vault Hide Error: $e');
      return false;
    }
  }

  Future<bool> restoreFile(File vaultFile, String targetPath) async {
    try {
      if (!await vaultFile.exists()) return false;
      final destination = File(targetPath);
      await vaultFile.copy(destination.path);
      await vaultFile.delete();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<File>> fetchVaultFiles() async {
    try {
      final vaultDir = await _getVaultDirectory();
      final entities = vaultDir.listSync();
      return entities.whereType<File>().where((f) => !f.path.endsWith('.nomedia')).toList();
    } catch (e) {
      return [];
    }
  }
}

// ====================================================================
// 8. SETTINGS & APP CONFIGURATION SERVICE
// ====================================================================
class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyDarkMode = 'is_dark_mode';
  static const String _keyHideShortAudio = 'hide_short_audio';
  static const String _keyMinDuration = 'min_audio_duration_ms';

  Future<bool> saveDarkModeSetting(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setBool(_keyDarkMode, isDark);
  }

  Future<bool> getDarkModeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? true;
  }

  Future<bool> setHideShortAudio(bool hide, {int minDurationMs = 30000}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyMinDuration, minDurationMs);
    return await prefs.setBool(_keyHideShortAudio, hide);
  }

  Future<bool> getHideShortAudio() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHideShortAudio) ?? true;
  }

  Future<double> getCacheSizeMB() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int totalBytes = 0;
      if (await tempDir.exists()) {
        await for (var entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            totalBytes += await entity.length();
          }
        }
      }
      return totalBytes / (1024 * 1024);
    } catch (e) {
      return 0.0;
    }
  }

  Future<bool> clearAppCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}

// ====================================================================
// 9. PLAYLIST, ALBUM & ARTIST SERVICES
// ====================================================================
class PlaylistService {
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<PlaylistModel>> fetchPlaylists() async {
    try {
      return await _audioQuery.queryPlaylists(uriType: UriType.EXTERNAL);
    } catch (e) {
      return [];
    }
  }

  Future<bool> createPlaylist(String name) async {
    try {
      if (name.trim().isEmpty) return false;
      await _audioQuery.createPlaylist(name.trim());
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deletePlaylist(int playlistId) async {
    try {
      await _audioQuery.removePlaylist(playlistId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> addSongToPlaylist(int playlistId, int songId) async {
    try {
      await _audioQuery.addToPlaylist(playlistId, songId);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeSongFromPlaylist(int playlistId, int songId) async {
    try {
      await _audioQuery.removeFromPlaylist(playlistId, songId);
      return true;
    } catch (e) {
      return false;
    }
  }
}

class AlbumService {
  static final AlbumService _instance = AlbumService._internal();
  factory AlbumService() => _instance;
  AlbumService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<AlbumModel>> fetchAlbums() async {
    try {
      return await _audioQuery.queryAlbums(uriType: UriType.EXTERNAL);
    } catch (e) {
      return [];
    }
  }
}

class ArtistService {
  static final ArtistService _instance = ArtistService._internal();
  factory ArtistService() => _instance;
  ArtistService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  Future<List<ArtistModel>> fetchArtists() async {
    try {
      return await _audioQuery.queryArtists(uriType: UriType.EXTERNAL);
    } catch (e) {
      return [];
    }
  }
}

class WelcomeService {
  static final WelcomeService _instance = WelcomeService._internal();
  factory WelcomeService() => _instance;
  WelcomeService._internal();

  static const String _keyIsFirstRun = 'is_first_run';

  Future<bool> isFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsFirstRun) ?? true;
  }

  Future<bool> setFirstRunCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setBool(_keyIsFirstRun, false);
  }
}
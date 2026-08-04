// ====================================================================
// الشاشة الرئيسية (SERVICES)
// ====================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart'; // مكتبة التشغيل الفعلي للصوتيات
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Video_model.dart';

class MainService {
  // Singleton pattern
  static final MainService _instance = MainService._internal();
  factory MainService() => _instance;
  MainService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  // فحص وطلب صلاحيات التخزين بشكل تفاعلي وآمن
  Future<bool> requestStoragePermission() async {
    try {
      PermissionStatus status;
      if (defaultTargetPlatform == TargetPlatform.android) {
        // التعامل مع إصدارات أندرويد المختلفة للصلاحيات
        status = await Permission.audio.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      } else {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    } catch (e) {
      if (kDebugMode) print('Permission Error: $e');
      return false;
    }
  }

  // جلب الإحصائيات الحقيقية للميديا من الجهاز لمنع أي قيم فارغة (Null)
  Future<Map<String, int>> fetchRealMediaStats() async {
    try {
      bool hasPermission = await requestStoragePermission();
      if (!hasPermission) {
        return {
          'totalVideos': 0,
          'totalAudio': 0,
          'totalPlaylists': 0,
          'totalArtists': 0,
        };
      }

      // جلب البيانات الفعلية من ذاكرة الهاتف
      List<SongModel> songs = await _audioQuery.querySongs(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );

      List<ArtistModel> artists = await _audioQuery.queryArtists(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
      );

      List<PlaylistModel> playlists = await _audioQuery.queryPlaylists();

      // ربط حقيقي بمسارات الفيديوهات المسجلة
      List<File> videos = await VideoService().fetchDeviceVideos();

      return {
        'totalVideos': videos.length,
        'totalAudio': songs.length,
        'totalPlaylists': playlists.length,
        'totalArtists': artists.length,
      };
    } catch (e) {
      if (kDebugMode) print('Error fetching real stats: $e');
      // إرجاع أصفار آمنة تماماً بدلاً من الـ Null في حال حدوث خطأ
      return {
        'totalVideos': 0,
        'totalAudio': 0,
        'totalPlaylists': 0,
        'totalArtists': 0,
      };
    }
  }

  // بحث تفاعلي حقيقي آمن ضد الـ Null
  Future<List<SongModel>> searchUserSongs(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      List<SongModel> allSongs = await _audioQuery.querySongs(
        ignoreCase: true,
        uriType: UriType.EXTERNAL,
      );

      return allSongs.where((song) {
        final title = song.title.toLowerCase();
        final artist = song.artist?.toLowerCase() ?? '';
        final searchQuery = query.toLowerCase();
        return title.contains(searchQuery) || artist.contains(searchQuery);
      }).toList();
    } catch (e) {
      if (kDebugMode) print('Search Error: $e');
      return [];
    }
  }
}

// ====================================================================
// شاشة الموسيقى (SERVICES)
// ====================================================================

class MusicService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();
  static const String _keyFavorites = 'favorite_songs';

  // جلب كافة الأغاني والملفات الصوتية من ذاكرة الهاتف بشكل تفاعلي آمن
  Future<List<SongModel>> fetchAllSongs() async {
    try {
      List<SongModel> songs = await _audioQuery.querySongs(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        sortType: SongSortType.TITLE,
      );
      return songs;
    } catch (e) {
      if (kDebugMode) print('Error fetching songs: $e');
      return []; // إرجاع قائمة فارغة لمنع حدوث Null
    }
  }

  // تصفية الأغاني حسب ألبوم معين
  Future<List<SongModel>> fetchSongsByAlbum(int albumId) async {
    try {
      List<SongModel> songs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.ALBUM_ID,
        albumId,
      );
      return songs;
    } catch (e) {
      if (kDebugMode) print('Error fetching songs by album: $e');
      return [];
    }
  }

  // تصفية الأغاني حسب فنان معين
  Future<List<SongModel>> fetchSongsByArtist(String artistName) async {
    try {
      List<SongModel> songs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.ARTIST,
        artistName,
      );
      return songs;
    } catch (e) {
      if (kDebugMode) print('Error fetching songs by artist: $e');
      return [];
    }
  }

  // فرز وترتيب الأغاني (حسب الاسم، المدة، تاريخ الإضافة، أو الحجم)
  List<SongModel> sortSongs(List<SongModel> songs, SongSortType sortType) {
    List<SongModel> sortedList = List.from(songs);
    switch (sortType) {
      case SongSortType.TITLE:
        sortedList.sort((a, b) => a.title.compareTo(b.title));
        break;
      case SongSortType.DURATION:
        sortedList.sort((a, b) => (b.duration ?? 0).compareTo(a.duration ?? 0));
        break;
      case SongSortType.DATE_ADDED:
        sortedList.sort((a, b) => (b.dateAdded ?? 0).compareTo(a.dateAdded ?? 0));
        break;
      case SongSortType.SIZE:
        sortedList.sort((a, b) => (b.size ?? 0).compareTo(a.size ?? 0));
        break;
      default:
        sortedList.sort((a, b) => a.title.compareTo(b.title));
        break;
    }
    return sortedList;
  }

  // إضافة / إزالة أغنية من القائمة المفضلة تفاعلياً (تغطية زر القلب في الـ UI)
  Future<bool> toggleFavorite(int songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> favs = prefs.getStringList(_keyFavorites) ?? [];

      if (favs.contains(songId.toString())) {
        favs.remove(songId.toString());
      } else {
        favs.add(songId.toString());
      }
      await prefs.setStringList(_keyFavorites, favs);
      return favs.contains(songId.toString());
    } catch (e) {
      if (kDebugMode) print('Error toggling favorite: $e');
      return false;
    }
  }

  // فحص حالة المفضلة لأغنية معينة
  Future<bool> isFavorite(int songId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> favs = prefs.getStringList(_keyFavorites) ?? [];
      return favs.contains(songId.toString());
    } catch (e) {
      return false;
    }
  }

  // جلب كافة الأغاني المفضلة
  Future<List<SongModel>> fetchFavoriteSongs() async {
    try {
      List<SongModel> allSongs = await fetchAllSongs();
      final prefs = await SharedPreferences.getInstance();
      List<String> favs = prefs.getStringList(_keyFavorites) ?? [];
      return allSongs.where((song) => favs.contains(song.id.toString())).toList();
    } catch (e) {
      if (kDebugMode) print('Error fetching favorite songs: $e');
      return [];
    }
  }
}

// ====================================================================
// شاشة الفيديوهات (SERVICES) - النسخة المضمونة والتفاعلية 100%
// ====================================================================

class VideoService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  // جلب مسارات الفيديوهات الفعلية من التخزين الداخلي والخارجي بشكل آمن تماماً
  Future<List<File>> fetchDeviceVideos() async {
    try {
      List<File> videoFiles = [];

      // الحصول على مسارات التخزين المتاحة في الجهاز بشكل آمن
      List<Directory>? directories = await getExternalStorageDirectories(
        type: StorageDirectory.movies,
      );

      // في حال لم تتوفر مسارات خارجية، نلجأ لمسار المستندات الأساسي
      if (directories == null || directories.isEmpty) {
        final Directory appDir = await getApplicationDocumentsDirectory();
        directories = [appDir];
      }

      for (var directory in directories) {
        // البحث عن المجلد الأساسي المشترك للتخزين (الوصول للجذر أو المجلدات العامة)
        final Directory rootDir = Directory(directory.path.split('Android')[0]);

        if (await rootDir.exists()) {
          // جلب الملفات بشكل متكرر والبحث عن لواحق الفيديو المشهورة
          await for (var entity in rootDir.list(recursive: true, followLinks: false)) {
            if (entity is File) {
              final String path = entity.path.toLowerCase();
              if (path.endsWith('.mp4') ||
                  path.endsWith('.mkv') ||
                  path.endsWith('.avi') ||
                  path.endsWith('.mov')) {
                videoFiles.add(entity);
              }
            }
          }
        }
      }

      return videoFiles;
    } catch (e) {
      if (kDebugMode) print('Error fetching safe video files: $e');
      return []; // حماية كاملة ضد أي NullPointerException
    }
  }

  // تصفية الفيديوهات حسب الحجم أو التاريخ لضمان عدم تهنيج الواجهة (UI)
  Future<List<File>> getSortedVideos() async {
    try {
      List<File> videos = await fetchDeviceVideos();
      if (videos.isEmpty) return [];

      // ترتيب الفيديوهات حسب الأحدث
      videos.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return videos;
    } catch (e) {
      if (kDebugMode) print('Error sorting videos: $e');
      return [];
    }
  }

  // جلب الفيديوهات بتفاصيلها (VideoModel) لاستخدامها في واجهة المستخدم (PhotoManager)
  static Future<List<VideoModel>> fetchLocalVideos() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();
      if (!ps.isAuth && !ps.hasAccess) return [];

      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );

      if (albums.isEmpty) return [];

      List<AssetEntity> media = await albums[0].getAssetListPaged(
        page: 0,
        size: 300,
      );

      List<VideoModel> videoList = [];
      for (var asset in media) {
        // الاعتماد المباشر على AssetEntity يضمن العمل في الـ Release APK بدون مشاكل Scoped Storage
        videoList.add(
          VideoModel(
            id: asset.id,
            title: asset.title ?? 'فيديو بدون عنوان',
            entity: asset,
            duration: asset.videoDuration,
          ),
        );
      }
      return videoList;
    } catch (e) {
      if (kDebugMode) print("Error fetching videos via PhotoManager: $e");
      return [];
    }
  }
}

// دالة عامة لتبسيط الاستدعاء داخل الـ UI (Top-level function)
Future<List<VideoModel>> fetchLocalVideos() => VideoService.fetchLocalVideos();

// ====================================================================
// شاشة الإعدادات (SERVICES) - الكود التفاعلي المضمون لإدارة التفضيلات
// ====================================================================

class SettingsService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة تعمل على مدار التطبيق
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // مفاتيح التخزين الثابتة (Keys) لتجنب أي أخطاء إملائية
  static const String _keyDarkMode = 'is_dark_mode';
  static const String _keyEqualizerEnabled = 'is_equalizer_enabled';
  static const String _keyPlaybackSpeed = 'playback_speed';
  static const String _keyCacheSize = 'cache_size';

  // حفظ حالة الوضع الداكن (Dark Mode)
  Future<bool> saveDarkModeSetting(bool isDark) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_keyDarkMode, isDark);
    } catch (e) {
      if (kDebugMode) print('Error saving dark mode: $e');
      return false;
    }
  }

  // قراءة حالة الوضع الداكن (مع قيمة افتراضية آمنة ضد الـ Null)
  Future<bool> getDarkModeSetting() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyDarkMode) ?? true; // الافتراضي وضع داكن يناسب التصميم
    } catch (e) {
      if (kDebugMode) print('Error reading dark mode: $e');
      return true;
    }
  }

  // حفظ تفعيل محسن الصوت (Equalizer)
  Future<bool> saveEqualizerState(bool isEnabled) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_keyEqualizerEnabled, isEnabled);
    } catch (e) {
      if (kDebugMode) print('Error saving equalizer state: $e');
      return false;
    }
  }

  // قراءة حالة محسن الصوت بشكل آمن
  Future<bool> getEqualizerState() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyEqualizerEnabled) ?? false;
    } catch (e) {
      if (kDebugMode) print('Error reading equalizer state: $e');
      return false;
    }
  }

  // حفظ سرعة تشغيل الميديا وتطبيقها فوراُ على مشغل الصوت
  Future<bool> savePlaybackSpeed(double speed) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await AudioPlayerService().setPlaybackSpeed(speed);
      return await prefs.setDouble(_keyPlaybackSpeed, speed);
    } catch (e) {
      if (kDebugMode) print('Error saving playback speed: $e');
      return false;
    }
  }

  // استرجاع سرعة التشغيل مع قيمة افتراضية 1.0 (السرعة الطبيعية)
  Future<double> getPlaybackSpeed() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyPlaybackSpeed) ?? 1.0;
    } catch (e) {
      if (kDebugMode) print('Error reading playback speed: $e');
      return 1.0;
    }
  }

  // مسح التخزين المؤقت (Cache) وإرجاع مساحة الذاكرة المُحررة بشكل فعلي
  Future<bool> clearAppCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.remove(_keyCacheSize);
    } catch (e) {
      if (kDebugMode) print('Error clearing cache: $e');
      return false;
    }
  }
}

// ====================================================================
// شاشة الترحيب (SERVICES) - الكود التفاعلي المضمون للتحقق الأولي
// ====================================================================

class WelcomeService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة تعمل على مدار التطبيق
  static final WelcomeService _instance = WelcomeService._internal();
  factory WelcomeService() => _instance;
  WelcomeService._internal();

  static const String _keyIsFirstRun = 'is_first_run';

  // التحقق مما إذا كانت هذه هي المرة الأولى التي يفتح فيها المستخدم التطبيق
  Future<bool> isFirstRun() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // لو المفتاح مش موجود (يعني أول مرة)، هنعتبرها true
      return prefs.getBool(_keyIsFirstRun) ?? true;
    } catch (e) {
      if (kDebugMode) print('Error checking first run: $e');
      return false; // أمان ضد الـ Null في حال حدوث خطأ
    }
  }

  // حفظ أن المستخدم شاهد شاشة الترحيب وتم تخطيها بنجاح
  Future<bool> setFirstRunCompleted() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_keyIsFirstRun, false);
    } catch (e) {
      if (kDebugMode) print('Error saving first run state: $e');
      return false;
    }
  }

  // إعادة تعيين الحالة (مفيدة للاختبار أو لو المستخدم حب يعيد شاشة الترحيب)
  Future<bool> resetFirstRun() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(_keyIsFirstRun, true);
    } catch (e) {
      if (kDebugMode) print('Error resetting first run: $e');
      return false;
    }
  }
}

// ====================================================================
// شاشة قوائم التشغيل (SERVICES) - الكود التفاعلي لإدارة قوائم التشغيل
// ====================================================================

class PlaylistService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة تعمل على مدار التطبيق
  static final PlaylistService _instance = PlaylistService._internal();
  factory PlaylistService() => _instance;
  PlaylistService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  // جلب كافة قوائم التشغيل المحلية الموجودة على الجهاز بشكل آمن
  Future<List<PlaylistModel>> fetchPlaylists() async {
    try {
      List<PlaylistModel> playlists = await _audioQuery.queryPlaylists(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
      return playlists;
    } catch (e) {
      if (kDebugMode) print('Error fetching playlists: $e');
      return []; // حماية كاملة ضد الـ Null
    }
  }

  // إنشاء قائمة تشغيل جديدة بالاسم المحدد
  Future<bool> createPlaylist(String playlistName) async {
    try {
      if (playlistName.trim().isEmpty) return false;
      await _audioQuery.createPlaylist(playlistName);
      return true;
    } catch (e) {
      if (kDebugMode) print('Error creating playlist: $e');
      return false;
    }
  }

  // حذف قائمة تشغيل بواسطة الـ ID الخاص بها
  Future<bool> deletePlaylist(int playlistId) async {
    try {
      await _audioQuery.removePlaylist(playlistId);
      return true;
    } catch (e) {
      if (kDebugMode) print('Error deleting playlist: $e');
      return false;
    }
  }

  // جلب الأغاني داخل قائمة تشغيل معينة
  Future<List<SongModel>> fetchSongsInPlaylist(int playlistId) async {
    try {
      List<SongModel> songs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.PLAYLIST,
        playlistId,
      );
      return songs;
    } catch (e) {
      if (kDebugMode) print('Error fetching songs in playlist: $e');
      return [];
    }
  }

  // إضافة أغنية إلى قائمة تشغيل
  Future<bool> addSongToPlaylist(int playlistId, int songId) async {
    try {
      await _audioQuery.addToPlaylist(playlistId, songId);
      return true;
    } catch (e) {
      if (kDebugMode) print('Error adding song to playlist: $e');
      return false;
    }
  }

  // إزالة أغنية من قائمة تشغيل
  Future<bool> removeSongFromPlaylist(int playlistId, int songId) async {
    try {
      await _audioQuery.removeFromPlaylist(playlistId, songId);
      return true;
    } catch (e) {
      if (kDebugMode) print('Error removing song from playlist: $e');
      return false;
    }
  }
}

// ====================================================================
// شاشة الألبومات (SERVICES) - الكود التفاعلي لإدارة الألبومات واستخراج الأغلفة
// ====================================================================

class AlbumService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة تعمل على مدار التطبيق
  static final AlbumService _instance = AlbumService._internal();
  factory AlbumService() => _instance;
  AlbumService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  // جلب كافة الألبومات الصوتية من ذاكرة الهاتف بشكل آمن تماماً
  Future<List<AlbumModel>> fetchAlbums() async {
    try {
      List<AlbumModel> albums = await _audioQuery.queryAlbums(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
      return albums;
    } catch (e) {
      if (kDebugMode) print('Error fetching albums: $e');
      return []; // حماية كاملة ضد الـ Null في حال حدوث خطأ أو عدم وجود صلاحيات
    }
  }

  // جلب المسارات الصوتية (الأغاني) المرتبطة بألبوم معين عن طريق الـ Album ID
  Future<List<SongModel>> fetchSongsByAlbumId(int albumId) async {
    try {
      List<SongModel> songs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.ALBUM_ID,
        albumId,
      );
      return songs;
    } catch (e) {
      if (kDebugMode) print('Error fetching songs for album $albumId: $e');
      return [];
    }
  }

  // البحث عن ألبوم معين بالاسم
  Future<List<AlbumModel>> searchAlbums(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      List<AlbumModel> allAlbums = await fetchAlbums();
      return allAlbums.where((album) {
        final albumName = album.album.toLowerCase();
        final artistName = album.artist?.toLowerCase() ?? '';
        final searchQuery = query.toLowerCase();
        return albumName.contains(searchQuery) || artistName.contains(searchQuery);
      }).toList();
    } catch (e) {
      if (kDebugMode) print('Error searching albums: $e');
      return [];
    }
  }
}

// ====================================================================
// شاشة الفنانين (SERVICES) - الكود الحقيقي التفاعلي لجلب الفنانين
// ====================================================================

class ArtistService {
  // Singleton pattern لتثبيت الخدمة كنسخة واحدة تعمل على مدار التطبيق
  static final ArtistService _instance = ArtistService._internal();
  factory ArtistService() => _instance;
  ArtistService._internal();

  final OnAudioQuery _audioQuery = OnAudioQuery();

  // جلب كافة الفنانين من ذاكرة الهاتف الحقيقية بشكل آمن
  Future<List<ArtistModel>> fetchArtists() async {
    try {
      List<ArtistModel> artists = await _audioQuery.queryArtists(
        ignoreCase: true,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
      return artists;
    } catch (e) {
      if (kDebugMode) print('Error fetching artists: $e');
      return []; // حماية كاملة ضد أي قيم فارغة أو أخطاء
    }
  }

  // جلب الأغاني الخاصة بفنان معين عن طريق الـ Artist ID
  Future<List<SongModel>> fetchSongsByArtistId(int artistId) async {
    try {
      List<SongModel> songs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.ARTIST_ID,
        artistId,
      );
      return songs;
    } catch (e) {
      if (kDebugMode) print('Error fetching songs for artist $artistId: $e');
      return [];
    }
  }

  // البحث عن فنان بالاسم بطريقة آمنة
  Future<List<ArtistModel>> searchArtists(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      List<ArtistModel> allArtists = await fetchArtists();
      return allArtists.where((artist) {
        final artistName = artist.artist.toLowerCase();
        final searchQuery = query.toLowerCase();
        return artistName.contains(searchQuery);
      }).toList();
    } catch (e) {
      if (kDebugMode) print('Error searching artists: $e');
      return [];
    }
  }
}

// ====================================================================
// خدمة مشغل الصوتيات الحقيقي (SERVICES) - لربط التحكم بالـ UI
// ====================================================================

class AudioPlayerService {
  // Singleton pattern
  static final AudioPlayerService _instance = AudioPlayerService._internal();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();

  // الحصول على الكائن المباشر للمشغل لاستخدامه في StreamBuilder للـ UI
  AudioPlayer get player => _audioPlayer;

  // إعداد قائمة التشغيل الحالية
  Future<void> setPlaylist(List<SongModel> songs, int initialIndex) async {
    try {
      final playlist = ConcatenatingAudioSource(
        children: songs.map((song) {
          return AudioSource.uri(
            Uri.parse(song.uri!),
            tag: song,
          );
        }).toList(),
      );

      await _audioPlayer.setAudioSource(playlist, initialIndex: initialIndex);
      await _audioPlayer.play();
    } catch (e) {
      if (kDebugMode) print('Error setting playlist: $e');
    }
  }

  // التبديل بين التشغيل والإيقاف المؤقت
  Future<void> togglePlayPause() async {
    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  // الانتقال للأغنية التالية
  Future<void> playNext() async {
    if (_audioPlayer.hasNext) {
      await _audioPlayer.seekToNext();
    }
  }

  // الانتقال للأغنية السابقة
  Future<void> playPrevious() async {
    if (_audioPlayer.hasPrevious) {
      await _audioPlayer.seekToPrevious();
    }
  }

  // التقديم والتأخير عند سحب شريط المدى (Slider)
  Future<void> seekTo(Duration position) async {
    await _audioPlayer.seek(position);
  }

  // تغيير سرعة التشغيل
  Future<void> setPlaybackSpeed(double speed) async {
    await _audioPlayer.setSpeed(speed);
  }

  // التبديل بين وضع التكرار
  Future<void> toggleRepeat() async {
    final current = _audioPlayer.loopMode;
    if (current == LoopMode.off) {
      await _audioPlayer.setLoopMode(LoopMode.all);
    } else if (current == LoopMode.all) {
      await _audioPlayer.setLoopMode(LoopMode.one);
    } else {
      await _audioPlayer.setLoopMode(LoopMode.off);
    }
  }

  // التبديل بين العشوائية
  Future<void> toggleShuffle() async {
    final isEnabled = _audioPlayer.shuffleModeEnabled;
    await _audioPlayer.setShuffleModeEnabled(!isEnabled);
  }
}
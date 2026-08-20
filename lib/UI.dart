
// ====================================================================
// NOVA MEDIA - COMPLETE INTEGRATED UI (Master Dream Build - Optimized)
// ====================================================================
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'SERVICES.dart'; // استيراد خدمات الصوت والـ AudioHandler الموحد
import 'videos_screen.dart';
import 'Video_model.dart';
import 'video_player_screen.dart';

// -------------------------------------------------------------------
// إدارة الحالات العامة والتخزين المحلي الموحد
// -------------------------------------------------------------------

abstract class PrefKeys {
  static const String favorites = 'favorites';
  static const String recentlyPlayed = 'recently_played';
  static const String isDarkMode = 'is_dark_mode';
}

final ValueNotifier<List<SongModel>> allSongsNotifier = ValueNotifier<List<SongModel>>([]);
final ValueNotifier<Set<int>> favoriteSongsNotifier = ValueNotifier<Set<int>>({});
final ValueNotifier<List<String>> recentIdsNotifier = ValueNotifier<List<String>>([]);

// ربط المشغل العام بالـ AudioHandler لضمان ظهور الإشعارات
AudioPlayer get globalAudioPlayer => audioHandler.player;
final OnAudioQuery globalAudioQuery = OnAudioQuery();

final ValueNotifier<SongModel?> currentSongNotifier = ValueNotifier<SongModel?>(null);
final ValueNotifier<List<SongModel>> currentPlaylistNotifier = ValueNotifier<List<SongModel>>([]);
final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(0);
final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(true);

bool _isAudioSessionInitialized = false;

Future<void> loadSavedData() async {
  final prefs = await SharedPreferences.getInstance();

  final favList = prefs.getStringList(PrefKeys.favorites) ?? [];
  favoriteSongsNotifier.value = favList.map((e) => int.tryParse(e)).whereType<int>().toSet();
  recentIdsNotifier.value = prefs.getStringList(PrefKeys.recentlyPlayed) ?? [];

  isDarkModeNotifier.value = prefs.getBool(PrefKeys.isDarkMode) ?? true;

  // أضف السطرين دول هنا عشان السجل يشتغل تلقائياً مع كل أغنية جديدة
  currentSongNotifier.addListener(() {
    final song = currentSongNotifier.value;
    if (song != null) {
      addToRecentlyPlayed(song.id.toString());
    }
  });
}

Future<void> toggleDarkMode() async {
  final prefs = await SharedPreferences.getInstance();
  final newValue = !isDarkModeNotifier.value;
  isDarkModeNotifier.value = newValue;
  await prefs.setBool(PrefKeys.isDarkMode, newValue);
}

Future<void> toggleFavorite(int songId) async {
  final prefs = await SharedPreferences.getInstance();
  final updated = Set<int>.from(favoriteSongsNotifier.value);
  if (updated.contains(songId)) {
    updated.remove(songId);
  } else {
    updated.add(songId);
  }
  favoriteSongsNotifier.value = updated;
  await prefs.setStringList(PrefKeys.favorites, updated.map((e) => e.toString()).toList());
}

Future<void> addToRecentlyPlayed(String songId) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> updated = List.from(recentIdsNotifier.value);
  updated.remove(songId);
  updated.insert(0, songId);
  if (updated.length > 50) updated.removeLast();
  recentIdsNotifier.value = updated;
  await prefs.setStringList(PrefKeys.recentlyPlayed, updated);
}

int _getRandomIndexExceptCurrent(int totalLength, int currentIndex) {
  if (totalLength <= 1) return 0;
  int nextIndex;
  do {
    nextIndex = math.Random().nextInt(totalLength);
  } while (nextIndex == currentIndex);
  return nextIndex;
}

void playNextSongGlobal() async {
  final list = currentPlaylistNotifier.value;
  if (list.isEmpty) return;

  if (globalAudioPlayer.shuffleModeEnabled) {
    currentIndexNotifier.value = _getRandomIndexExceptCurrent(list.length, currentIndexNotifier.value);
  } else {
    currentIndexNotifier.value = (currentIndexNotifier.value + 1) % list.length;
  }

  final nextSong = list[currentIndexNotifier.value];
  currentSongNotifier.value = nextSong;

  await AudioPlayerService().setPlaylist(list, currentIndexNotifier.value);
}

void playPreviousSongGlobal() async {
  final list = currentPlaylistNotifier.value;
  if (list.isEmpty) return;

  if (globalAudioPlayer.shuffleModeEnabled) {
    currentIndexNotifier.value = _getRandomIndexExceptCurrent(list.length, currentIndexNotifier.value);
  } else {
    currentIndexNotifier.value = (currentIndexNotifier.value - 1 + list.length) % list.length;
  }

  final prevSong = list[currentIndexNotifier.value];
  currentSongNotifier.value = prevSong;

  await AudioPlayerService().setPlaylist(list, currentIndexNotifier.value);
}

Future<void> initAudioSession() async {
  if (_isAudioSessionInitialized) return;
  _isAudioSessionInitialized = true;

  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  session.becomingNoisyEventStream.listen((_) {
    if (globalAudioPlayer.playing) {
      globalAudioPlayer.pause();
    }
  });

  globalAudioPlayer.playerStateStream.listen((state) {
    if (state.processingState == ProcessingState.completed) {
      if (globalAudioPlayer.loopMode == LoopMode.one) {
        globalAudioPlayer.seek(Duration.zero);
        globalAudioPlayer.play();
      } else {
        playNextSongGlobal();
      }
    }
  });
}

Future<List<VideoModel>> fetchLocalVideos() async {
  List<VideoModel> localVideos = [];

  try {
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) return [];

    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      hasAll: true,
    );

    if (albums.isEmpty) return [];

    List<AssetEntity> videoAssets = await albums[0].getAssetListPaged(
      page: 0,
      size: 200,
    );

    for (var asset in videoAssets) {
      localVideos.add(
        VideoModel(
          id: asset.id,
          title: asset.title ?? 'untitled_video'.tr(),
          entity: asset,
          duration: asset.videoDuration,
        ),
      );
    }
  } catch (e) {
    debugPrint('❌ حدث خطأ أثناء جلب الفيديوهات: $e');
  }

  return localVideos;
}

// -------------------------------------------------------------------
// 1. الشاشة الرئيسية (Main Screen UI)
// -------------------------------------------------------------------
class MainScreenUI extends StatefulWidget {
  const MainScreenUI({super.key});

  @override
  State<MainScreenUI> createState() => _MainScreenUIState();
}

class _MainScreenUIState extends State<MainScreenUI> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  String _searchQuery = '';
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    loadSavedData();
    initAudioSession();
    _tabController = TabController(length: 3, vsync: this);
    _checkAndRequestPermission();
  }

  Future<void> _checkAndRequestPermission() async {
    var notificationStatus = await Permission.notification.status;
    if (!notificationStatus.isGranted) {
      await Permission.notification.request();
    }

    bool permissionStatus = await globalAudioQuery.permissionsStatus();
    if (!permissionStatus) {
      permissionStatus = await globalAudioQuery.permissionsRequest();
    }
    setState(() {
      _hasPermission = permissionStatus;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final backgroundColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);

        return Theme(
          data: isDark ? ThemeData.dark() : ThemeData.light(),
          child: Scaffold(
            backgroundColor: backgroundColor,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context, isDark),
                  Expanded(
                    child: !_hasPermission
                        ? _buildPermissionRequestWidget(isDark)
                        : TabBarView(
                      controller: _tabController,
                      children: [
                        VideosTabWidget(searchQuery: _searchQuery),
                        SongsTabWidget(searchQuery: _searchQuery),
                        const PlaylistsTabWidget(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: ValueListenableBuilder<SongModel?>(
              valueListenable: currentSongNotifier,
              builder: (context, currentSong, child) {
                if (currentSong == null) return const SizedBox.shrink();
                return MiniPlayerWidget(
                  song: currentSong,
                  onTap: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, anim1, anim2) => FullPlayerScreenUI(song: currentSong),
                        transitionsBuilder: (context, anim1, anim2, child) {
                          return SlideTransition(
                            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim1),
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPermissionRequestWidget(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.grey : Colors.black54;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_special_rounded, size: 80, color: Color(0xFF00BCD4)),
            ),
            const SizedBox(height: 24),
            Text(
              'media_permission_title'.tr(),
              style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'media_permission_desc'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: subTextColor, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BCD4),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _checkAndRequestPermission,
              icon: const Icon(Icons.lock_open_rounded, color: Colors.black),
              label: Text(
                'grant_permission_now'.tr(),
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[300]!, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _isSearching
                  ? Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'search_hint'.tr(),
                    hintStyle: const TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: Icon(Icons.clear, color: isDark ? Colors.white70 : Colors.black),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              });
                            },
                          ),
                        IconButton(
                          icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black),
                          onPressed: () {
                            setState(() {
                              _isSearching = false;
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              )
                  : Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/rr.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'app_title'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF00BCD4),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              if (!_isSearching)
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.search, color: isDark ? Colors.white70 : Colors.black),
                      onPressed: () {
                        setState(() {
                          _isSearching = true;
                        });
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : Colors.black),
                      onPressed: () => _showOptionsMenu(context, isDark),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF00BCD4),
            unselectedLabelColor: isDark ? Colors.grey : Colors.black54,
            indicatorColor: const Color(0xFF00BCD4),
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            unselectedLabelStyle: const TextStyle(fontSize: 14),
            tabs: [
              Tab(text: 'videos_tab'.tr()),
              Tab(text: 'songs_tab'.tr()),
              Tab(text: 'playlists_tab'.tr()),
            ],
          ),
        ],
      ),
    );
  }

  void _showOptionsMenu(BuildContext context, bool isDark) {
    final sheetBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4)),
                title: Text('complete_music_library'.tr(), style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const MusicLibraryScreenUI()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_rounded, color: Color(0xFF00BCD4)),
                title: Text('complete_video_library'.tr(), style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const VideosLibraryScreenUI()));
                },
              ),
              ListTile(
                leading: Icon(
                  isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: const Color(0xFF00BCD4),
                ),
                title: Text('dark_mode_title'.tr(), style: TextStyle(color: textColor)),
                trailing: Switch(
                  value: isDark,
                  activeColor: const Color(0xFF00BCD4),
                  onChanged: (val) {
                    toggleDarkMode();
                  },
                ),
              ),
              Divider(color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[300]),
              ListTile(
                leading: const Icon(Icons.language_rounded, color: Color(0xFF00BCD4)),
                title: Text('select_language'.tr(), style: TextStyle(color: textColor)),
                onTap: () {
                  Navigator.pop(context);
                  _showLanguageSelectionBottomSheet(context, isDark);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLanguageSelectionBottomSheet(BuildContext context, bool isDark) {
    final sheetBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final currentLocaleCode = context.locale.languageCode;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(2)),
              ),
              Text(
                'choose_app_language'.tr(),
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.language, color: Color(0xFF00BCD4)),
                title: Text('arabic_language'.tr(), style: TextStyle(color: textColor)),
                trailing: currentLocaleCode == 'ar' ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00BCD4)) : null,
                onTap: () {
                  Navigator.pop(context);
                  context.setLocale(const Locale('ar', ''));
                },
              ),
              ListTile(
                leading: const Icon(Icons.language, color: Color(0xFF00BCD4)),
                title: Text('english_language'.tr(), style: TextStyle(color: textColor)),
                trailing: currentLocaleCode == 'en' ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00BCD4)) : null,
                onTap: () {
                  Navigator.pop(context);
                  context.setLocale(const Locale('en', ''));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 2. تبويب الأغاني (Songs Tab)
// -------------------------------------------------------------------
class SongsTabWidget extends StatefulWidget {
  final String searchQuery;
  const SongsTabWidget({super.key, this.searchQuery = ''});

  @override
  State<SongsTabWidget> createState() => _SongsTabWidgetState();
}

class _SongsTabWidgetState extends State<SongsTabWidget> {
  late Future<List<SongModel>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = _fetchSongs();
  }

  Future<List<SongModel>> _fetchSongs() async {
    final songs = await globalAudioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    allSongsNotifier.value = songs;
    return songs;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return FutureBuilder<List<SongModel>>(
          future: _songsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "${'music_error_loading'.tr()}: ${snapshot.error}",
                  style: TextStyle(color: textColor),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFF00BCD4)));
            }
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text('no_audio_files_found'.tr(), style: const TextStyle(color: Colors.grey)),
              );
            }

            List<SongModel> songs = snapshot.data!.where((song) {
              final q = widget.searchQuery.toLowerCase();
              return song.title.toLowerCase().contains(q) ||
                  (song.artist ?? '').toLowerCase().contains(q);
            }).toList();

            if (songs.isEmpty) {
              return Center(
                child: Text('no_search_results'.tr(), style: const TextStyle(color: Colors.grey)),
              );
            }

            return ListView.builder(
              itemCount: songs.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                SongModel song = songs[index];
                return ValueListenableBuilder<SongModel?>(
                  valueListenable: currentSongNotifier,
                  builder: (context, activeSong, child) {
                    final bool isSelected = activeSong?.id == song.id;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF00BCD4).withValues(alpha: isDark ? 0.2 : 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                        leading: QueryArtworkWidget(
                          id: song.id,
                          type: ArtworkType.AUDIO,
                          artworkBorder: BorderRadius.circular(10),
                          nullArtworkWidget: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[300],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4), size: 26),
                          ),
                        ),
                        title: Text(
                          song.title,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF00BCD4) : textColor,
                            fontSize: 15,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            '${song.artist ?? "unknown_artist".tr()} • ${_formatDuration(song.duration ?? 0)}',
                            style: TextStyle(color: subtitleColor, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: ValueListenableBuilder<Set<int>>(
                          valueListenable: favoriteSongsNotifier,
                          builder: (context, favorites, child) {
                            final isFav = favorites.contains(song.id);
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isFav)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4.0, right: 4.0),
                                    child: Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 20),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.more_vert_rounded, color: Colors.grey),
                                  onPressed: () => _showSongOptions(context, song, isDark),
                                ),
                              ],
                            );
                          },
                        ),
                        onTap: () async {
                          currentSongNotifier.value = song;
                          currentPlaylistNotifier.value = songs;
                          currentIndexNotifier.value = index;

                          // البدء عن طريق الخدمة الموحدة لإنشاء الإشعار وضمان التشغيل بالخلفية
                          await AudioPlayerService().setPlaylist(songs, index);
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSongOptions(BuildContext context, SongModel song, bool isDark) {
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return ValueListenableBuilder<Set<int>>(
          valueListenable: favoriteSongsNotifier,
          builder: (context, favorites, child) {
            final isFav = favorites.contains(song.id);
            return Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 12.0),
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: Colors.grey[500], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? Colors.pinkAccent : const Color(0xFF00BCD4),
                  ),
                  title: Text(
                    isFav ? 'remove_from_favorites'.tr() : 'add_to_favorites'.tr(),
                    style: TextStyle(color: textColor),
                  ),
                  onTap: () {
                    toggleFavorite(song.id);
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Color(0xFF00BCD4)),
                  title: Text('share_song'.tr(), style: TextStyle(color: textColor)),
                  onTap: () {
                    Navigator.pop(context);
                    Share.shareXFiles([XFile(song.data)], text: song.title);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

String _formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
// -------------------------------------------------------------------
// 4. تبويب قوائم التشغيل (Playlists Tab)
// -------------------------------------------------------------------
class PlaylistsTabWidget extends StatefulWidget {
  const PlaylistsTabWidget({super.key});

  @override
  State<PlaylistsTabWidget> createState() => _PlaylistsTabWidgetState();
}

class _PlaylistsTabWidgetState extends State<PlaylistsTabWidget> {
  late Future<List<SongModel>> _songsFuture;

  @override
  void initState() {
    super.initState();
    _songsFuture = _getSongs();
  }

  Future<List<SongModel>> _getSongs() async {
    if (allSongsNotifier.value.isNotEmpty) {
      return allSongsNotifier.value;
    }
    final songs = await globalAudioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );
    allSongsNotifier.value = songs;
    return songs;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
        final folderIconBg = isDark ? const Color(0xFF2C2C2C) : Colors.grey[200]!;

        return FutureBuilder<List<SongModel>>(
          future: _songsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
              );
            }

            final allSongs = snapshot.data ?? [];

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // قائمة الأغاني المفضلة مع التحديث الفوري
                ValueListenableBuilder<Set<int>>(
                  valueListenable: favoriteSongsNotifier,
                  builder: (context, favorites, child) {
                    final favSongs = allSongs.where((s) => favorites.contains(s.id)).toList();
                    return _buildCustomPlaylistItem(
                      context,
                      isDark: isDark,
                      title: 'favorite_songs_title'.tr(),
                      subtitle: '${favSongs.length} ${'songs_count_suffix'.tr()}',
                      icon: Icons.favorite_rounded,
                      color: Colors.pink,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => PlaylistDetailsScreenUI(
                              title: 'favorite_songs_title'.tr(),
                              songs: favSongs,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                // قائمة المشغلة مؤخراً مع التحديث الفوري
                ValueListenableBuilder<List<String>>(
                  valueListenable: recentIdsNotifier,
                  builder: (context, recentIds, child) {
                    final List<SongModel> recentSongs = [];
                    for (var id in recentIds) {
                      final match = allSongs.where((s) => s.id.toString() == id);
                      if (match.isNotEmpty) {
                        recentSongs.add(match.first);
                      }
                    }
                    return _buildCustomPlaylistItem(
                      context,
                      isDark: isDark,
                      title: 'recently_played_title'.tr(),
                      subtitle: '${recentSongs.length} ${'songs_count_suffix'.tr()}',
                      icon: Icons.history_rounded,
                      color: Colors.cyan,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => PlaylistDetailsScreenUI(
                              title: 'recently_played_title'.tr(),
                              songs: recentSongs,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text(
                    'device_folders_playlists'.tr(),
                    style: const TextStyle(
                      color: Color(0xFF00BCD4),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),

                // المجلدات التلقائية كمجموعات تشغيل
                Builder(
                  builder: (context) {
                    final Map<String, List<SongModel>> folderPlaylists = {};
                    for (var song in allSongs) {
                      final pathSegments = song.data.split('/');
                      if (pathSegments.length > 1) {
                        String folderName = pathSegments[pathSegments.length - 2];
                        folderPlaylists.putIfAbsent(folderName, () => []).add(song);
                      }
                    }

                    if (folderPlaylists.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: Text(
                            'no_folders_with_songs'.tr(),
                            style: TextStyle(color: subtitleColor),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: folderPlaylists.entries.map((entry) {
                        return Card(
                          color: cardColor,
                          elevation: isDark ? 0 : 1,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: folderIconBg,
                              child: const Icon(Icons.folder_open_rounded, color: Color(0xFF00BCD4)),
                            ),
                            title: Text(
                              entry.key,
                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${entry.value.length} ${'songs_count_suffix'.tr()}',
                              style: TextStyle(color: subtitleColor),
                            ),
                            trailing: Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => PlaylistDetailsScreenUI(
                                    title: entry.key,
                                    songs: entry.value,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCustomPlaylistItem(
      BuildContext context, {
        required bool isDark,
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Card(
      color: cardColor,
      elevation: isDark ? 0 : 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: TextStyle(color: subtitleColor)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 16),
        onTap: onTap,
      ),
    );
  }
}

// -------------------------------------------------------------------
// 5. شاشة عرض الأغاني داخل القائمة (Playlist Details Screen)
// -------------------------------------------------------------------
class PlaylistDetailsScreenUI extends StatelessWidget {
  final String title;
  final List<SongModel> songs;

  const PlaylistDetailsScreenUI({
    super.key,
    required this.title,
    required this.songs,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final appBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
        final placeholderBg = isDark ? const Color(0xFF2C2C2C) : Colors.grey[300]!;

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: isDark ? 0 : 1,
            title: Text(
              title,
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: songs.isEmpty
              ? Center(
            child: Text(
              'playlist_empty'.tr(),
              style: TextStyle(color: subtitleColor, fontSize: 16),
            ),
          )
              : Column(
            children: [
              // بار تشغيل الكل
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${songs.length} ${'songs_count_suffix'.tr()}',
                      style: TextStyle(color: subtitleColor, fontWeight: FontWeight.w600),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BCD4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      onPressed: () => _playSongAtIndex(context, 0),
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                      label: Text(
                        'play_all'.tr(),
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: songs.length,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return ValueListenableBuilder<SongModel?>(
                      valueListenable: currentSongNotifier,
                      builder: (context, activeSong, child) {
                        final bool isSelected = activeSong?.id == song.id;

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF00BCD4).withValues(alpha: isDark ? 0.2 : 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: QueryArtworkWidget(
                              id: song.id,
                              type: ArtworkType.AUDIO,
                              artworkBorder: BorderRadius.circular(10),
                              nullArtworkWidget: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: placeholderBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4), size: 24),
                              ),
                            ),
                            title: Text(
                              song.title,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF00BCD4) : textColor,
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${song.artist ?? "unknown_artist".tr()} • ${_formatDuration(song.duration ?? 0)}',
                              style: TextStyle(color: subtitleColor, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _playSongAtIndex(context, index),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _playSongAtIndex(BuildContext context, int index) async {
    final song = songs[index];
    currentSongNotifier.value = song;
    currentPlaylistNotifier.value = songs;
    currentIndexNotifier.value = index;

    addToRecentlyPlayed(song.id.toString());

    try {
      // التشغيل عبر الخدمة الموحدة المسؤولة عن الإشعار والربط بـ AudioHandler
      await AudioPlayerService().setPlaylist(songs, index);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'playback_error'.tr()}: $e')),
        );
      }
    }
  }

  static String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    return duration.inHours > 0
        ? '${twoDigits(duration.inHours)}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

// -------------------------------------------------------------------
// 6. المشغل المصغر السفلي (Mini Player)
// -------------------------------------------------------------------
class MiniPlayerWidget extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const MiniPlayerWidget({
    super.key,
    required this.song,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
        final iconColor = isDark ? Colors.white : Colors.black87;
        final shadowColor = isDark
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.black.withValues(alpha: 0.08);

        return GestureDetector(
          onTap: onTap,
          child: Container(
            height: 72,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
              border: Border.all(
                color: const Color(0xFF00BCD4).withValues(alpha: isDark ? 0.3 : 0.5),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Row(
                        children: [
                          QueryArtworkWidget(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            artworkBorder: BorderRadius.circular(10),
                            nullArtworkWidget: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2C2C2C) : Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  song.artist ?? "unknown_artist".tr(),
                                  style: TextStyle(color: subtitleColor, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<Set<int>>(
                            valueListenable: favoriteSongsNotifier,
                            builder: (context, favorites, _) {
                              final isFav = favorites.contains(song.id);
                              return IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(5),
                                icon: Icon(
                                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: isFav ? Colors.pinkAccent : subtitleColor,
                                  size: 22,
                                ),
                                onPressed: () => toggleFavorite(song.id),
                              );
                            },
                          ),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(5),
                            icon: Icon(Icons.skip_previous_rounded, color: iconColor, size: 24),
                            onPressed: playPreviousSongGlobal,
                          ),
                          StreamBuilder<bool>(
                            stream: globalAudioPlayer.playingStream,
                            builder: (context, snapshot) {
                              final isPlaying = snapshot.data ?? false;
                              return IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(5),
                                icon: Icon(
                                  isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  color: const Color(0xFF00BCD4),
                                  size: 34,
                                ),
                                onPressed: () {
                                  if (isPlaying) {
                                    globalAudioPlayer.pause();
                                  } else {
                                    addToRecentlyPlayed(song.id.toString());
                                    globalAudioPlayer.play();
                                  }
                                },
                              );
                            },
                          ),
                          IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(5),
                            icon: Icon(Icons.skip_next_rounded, color: iconColor, size: 24),
                            onPressed: playNextSongGlobal,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // شريط التقدم النحيف في الأسفل
                  StreamBuilder<Duration>(
                    stream: globalAudioPlayer.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final total = globalAudioPlayer.duration ?? Duration.zero;
                      final double progress = (total.inMilliseconds > 0)
                          ? (position.inMilliseconds / total.inMilliseconds)
                          : 0.0;

                      return LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 2.5,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00BCD4)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
// -------------------------------------------------------------------
// 7. شاشة تشغيل الموسيقى الكاملة (Full Player Screen UI)
// -------------------------------------------------------------------
class FullPlayerScreenUI extends StatefulWidget {
  final SongModel song;
  const FullPlayerScreenUI({super.key, required this.song});

  @override
  State<FullPlayerScreenUI> createState() => _FullPlayerScreenUIState();
}

class _FullPlayerScreenUIState extends State<FullPlayerScreenUI> {
  double? _dragValue;
  Timer? _sleepTimer;

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
        final iconColor = isDark ? Colors.white70 : Colors.black54;
        final artworkBg = isDark ? const Color(0xFF1E1E1E) : Colors.grey[300]!;

        return Scaffold(
          backgroundColor: bgColor,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // الشريط العلوي
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 34),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'main_player_title'.tr(),
                        style: TextStyle(color: subtitleColor, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_vert_rounded, color: textColor),
                        onPressed: () => _showPlayerMenu(context, isDark),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // صورة الألبوم
                  ValueListenableBuilder<SongModel?>(
                    valueListenable: currentSongNotifier,
                    builder: (context, song, child) {
                      final activeSong = song ?? widget.song;
                      return Hero(
                        tag: 'artwork_${activeSong.id}',
                        child: QueryArtworkWidget(
                          id: activeSong.id,
                          type: ArtworkType.AUDIO,
                          artworkWidth: screenSize.width * 0.78,
                          artworkHeight: screenSize.width * 0.78,
                          artworkBorder: BorderRadius.circular(24),
                          size: 2000,
                          quality: 100,
                          artworkQuality: FilterQuality.high,
                          nullArtworkWidget: Container(
                            width: screenSize.width * 0.78,
                            height: screenSize.width * 0.78,
                            decoration: BoxDecoration(
                              color: artworkBg,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00BCD4).withValues(alpha: isDark ? 0.25 : 0.15),
                                  blurRadius: 30,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(Icons.album_rounded, size: 110, color: Color(0xFF00BCD4)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),

                  // عنوان الأغنية والفنان بزر المفضلة
                  ValueListenableBuilder<SongModel?>(
                    valueListenable: currentSongNotifier,
                    builder: (context, song, child) {
                      final activeSong = song ?? widget.song;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeSong.title,
                                  style: TextStyle(color: textColor, fontSize: 20, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  activeSong.artist ?? "unknown_artist".tr(),
                                  style: TextStyle(color: subtitleColor, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          ValueListenableBuilder<Set<int>>(
                            valueListenable: favoriteSongsNotifier,
                            builder: (context, favorites, child) {
                              final isFav = favorites.contains(activeSong.id);
                              return IconButton(
                                icon: Icon(
                                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: isFav ? Colors.pinkAccent : textColor,
                                  size: 30,
                                ),
                                onPressed: () => toggleFavorite(activeSong.id),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // شريط التقدم والوقت
                  StreamBuilder<Duration>(
                    stream: globalAudioPlayer.positionStream,
                    builder: (context, snapshot) {
                      final position = snapshot.data ?? Duration.zero;
                      final duration = globalAudioPlayer.duration ?? Duration.zero;

                      final double currentValue = _dragValue ??
                          position.inSeconds.toDouble().clamp(
                            0.0,
                            duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                          );

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFF00BCD4),
                              inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
                              thumbColor: const Color(0xFF00BCD4),
                              trackHeight: 4.0,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                            ),
                            child: Slider(
                              value: currentValue,
                              min: 0.0,
                              max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                              onChanged: (val) {
                                setState(() {
                                  _dragValue = val;
                                });
                              },
                              onChangeEnd: (val) {
                                globalAudioPlayer.seek(Duration(seconds: val.toInt()));
                                setState(() {
                                  _dragValue = null;
                                });
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(position), style: TextStyle(color: subtitleColor, fontSize: 12)),
                                Text(_formatDuration(duration), style: TextStyle(color: subtitleColor, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // أزرار التحكم في التشغيل
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      StreamBuilder<bool>(
                        stream: globalAudioPlayer.shuffleModeEnabledStream,
                        builder: (context, snapshot) {
                          final isShuffle = snapshot.data ?? false;
                          return IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: isShuffle ? const Color(0xFF00BCD4) : subtitleColor,
                              size: 26,
                            ),
                            onPressed: () async {
                              await globalAudioPlayer.setShuffleModeEnabled(!isShuffle);
                            },
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_previous_rounded, color: textColor, size: 40),
                        onPressed: playPreviousSongGlobal,
                      ),
                      StreamBuilder<bool>(
                        stream: globalAudioPlayer.playingStream,
                        builder: (context, snapshot) {
                          final isPlaying = snapshot.data ?? false;
                          return Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF00BCD4),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: Icon(
                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 40,
                              ),
                              onPressed: () {
                                if (isPlaying) {
                                  globalAudioPlayer.pause();
                                } else {
                                  globalAudioPlayer.play();
                                }
                              },
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next_rounded, color: textColor, size: 40),
                        onPressed: playNextSongGlobal,
                      ),
                      StreamBuilder<LoopMode>(
                        stream: globalAudioPlayer.loopModeStream,
                        builder: (context, snapshot) {
                          final loopMode = snapshot.data ?? LoopMode.off;
                          final isRepeatOne = loopMode == LoopMode.one;
                          final isRepeatAll = loopMode == LoopMode.all;

                          IconData iconData = Icons.repeat_rounded;
                          if (isRepeatOne) iconData = Icons.repeat_one_rounded;

                          Color color = (isRepeatOne || isRepeatAll) ? const Color(0xFF00BCD4) : subtitleColor!;

                          return IconButton(
                            icon: Icon(iconData, color: color, size: 26),
                            onPressed: () {
                              if (loopMode == LoopMode.off) {
                                globalAudioPlayer.setLoopMode(LoopMode.all);
                              } else if (loopMode == LoopMode.all) {
                                globalAudioPlayer.setLoopMode(LoopMode.one);
                              } else {
                                globalAudioPlayer.setLoopMode(LoopMode.off);
                              }
                            },
                          );
                        },
                      ),
                    ],
                  ),
                  const Spacer(),

                  // الأدوات السفلية (قائمة الانتظار ومؤقت النوم)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(Icons.queue_music_rounded, color: iconColor),
                        onPressed: () => _showQueueBottomSheet(context, isDark),
                      ),
                      const SizedBox(width: 40),
                      IconButton(
                        icon: Icon(Icons.timer_rounded, color: iconColor),
                        onPressed: () => _showSleepTimerDialog(context, isDark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showQueueBottomSheet(BuildContext context, bool isDark) {
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final playlist = currentPlaylistNotifier.value;
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'current_playlist_title'.tr(),
                style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: playlist.length,
                  itemBuilder: (context, index) {
                    final song = playlist[index];
                    return ValueListenableBuilder<SongModel?>(
                      valueListenable: currentSongNotifier,
                      builder: (context, activeSong, _) {
                        final isSelected = activeSong?.id == song.id;
                        return ListTile(
                          title: Text(
                            song.title,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF00BCD4) : textColor,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            song.artist ?? 'unknown_artist'.tr(),
                            style: TextStyle(color: subtitleColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () async {
                            currentSongNotifier.value = song;
                            currentIndexNotifier.value = index;

                            try {
                              // استخدام الخدمة الموحدة لضمان تحديث الإشعارات والتشغيل الصحيح
                              await AudioPlayerService().setPlaylist(playlist, index);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('${'playback_error'.tr()}: $e')),
                                );
                              }
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                        );
                      },
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }

  void _showSleepTimerDialog(BuildContext context, bool isDark) {
    final dialogBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: dialogBg,
          title: Text('sleep_timer_title'.tr(), style: TextStyle(color: textColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [15, 30, 45, 60].map((minutes) {
              return ListTile(
                title: Text('$minutes ${'minutes_suffix'.tr()}', style: TextStyle(color: textColor)),
                onTap: () {
                  _sleepTimer?.cancel();
                  _sleepTimer = Timer(Duration(minutes: minutes), () {
                    globalAudioPlayer.pause();
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${'sleep_timer_set_msg'.tr()} $minutes ${'minutes_suffix'.tr()}')),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showPlayerMenu(BuildContext context, bool isDark) {
    final activeSong = currentSongNotifier.value ?? widget.song;
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.info_outline, color: textColor),
              title: Text('audio_file_details'.tr(), style: TextStyle(color: textColor)),
              onTap: () {
                Navigator.pop(context);
                _showAudioInfoBottomSheet(context, activeSong, isDark);
              },
            ),
          ],
        );
      },
    );
  }

  void _showAudioInfoBottomSheet(BuildContext context, SongModel song, bool isDark) {
    final sheetBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF00BCD4), size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'audio_details_title'.tr(),
                      style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Divider(color: subtitleColor?.withValues(alpha: 0.3), height: 24),
                _buildDetailRow(Icons.title, 'title_label'.tr(), song.title, textColor, subtitleColor),
                _buildDetailRow(Icons.person, 'artist_label'.tr(), song.artist ?? 'unknown_artist'.tr(), textColor, subtitleColor),
                _buildDetailRow(Icons.album_rounded, 'album_label'.tr(), song.album ?? 'unknown'.tr(), textColor, subtitleColor),
                _buildDetailRow(
                  Icons.timer,
                  'duration_label'.tr(),
                  song.duration != null ? _formatDuration(Duration(milliseconds: song.duration!)) : 'unknown'.tr(),
                  textColor,
                  subtitleColor,
                ),
                _buildDetailRow(Icons.folder, 'path_label'.tr(), song.data, textColor, subtitleColor),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value, Color textColor, Color? subtitleColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: subtitleColor, size: 20),
          const SizedBox(width: 12),
          Text('$title: ', style: TextStyle(color: subtitleColor, fontSize: 14)),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? '${twoDigits(duration.inHours)}:$minutes:$seconds'
        : '$minutes:$seconds';
  }
}

// -------------------------------------------------------------------
// 8. شاشة مكتبة الموسيقى الشاملة (Music Library Screen UI)
// -------------------------------------------------------------------
class MusicLibraryScreenUI extends StatefulWidget {
  const MusicLibraryScreenUI({super.key});

  @override
  State<MusicLibraryScreenUI> createState() => _MusicLibraryScreenUIState();
}

class _MusicLibraryScreenUIState extends State<MusicLibraryScreenUI>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final appBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: isDark ? 0 : 1,
            title: _isSearching
                ? TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: textColor, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'search_hint'.tr(),
                hintStyle: TextStyle(color: subtitleColor),
                border: InputBorder.none,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
            )
                : Text(
              'complete_music_library'.tr(),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close_rounded : Icons.search_rounded,
                  color: textColor,
                ),
                onPressed: () {
                  setState(() {
                    if (_isSearching) {
                      _isSearching = false;
                      _searchController.clear();
                      _searchQuery = '';
                    } else {
                      _isSearching = true;
                    }
                  });
                },
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF00BCD4),
              indicatorWeight: 3,
              labelColor: const Color(0xFF00BCD4),
              unselectedLabelColor: subtitleColor,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(icon: const Icon(Icons.videocam_rounded), text: "videos_tab".tr()),
                Tab(icon: const Icon(Icons.music_note_rounded), text: "songs_tab".tr()),
                Tab(icon: const Icon(Icons.playlist_play_rounded), text: "playlists_tab".tr()),
              ],
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    VideosTabWidget(searchQuery: _searchQuery),
                    SongsTabWidget(searchQuery: _searchQuery),
                    const PlaylistsTabWidget(),
                  ],
                ),
              ),
              ValueListenableBuilder<SongModel?>(
                valueListenable: currentSongNotifier,
                builder: (context, song, child) {
                  if (song == null) return const SizedBox.shrink();
                  return MiniPlayerWidget(
                    song: song,
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, anim1, anim2) => FullPlayerScreenUI(song: song),
                          transitionsBuilder: (context, anim1, anim2, child) {
                            return SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim1),
                              child: child,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 9. شاشة مكتبة الفيديوهات (Videos Library Screen UI)
// -------------------------------------------------------------------
class VideosLibraryScreenUI extends StatefulWidget {
  const VideosLibraryScreenUI({super.key});

  @override
  State<VideosLibraryScreenUI> createState() => _VideosLibraryScreenUIState();
}

class _VideosLibraryScreenUIState extends State<VideosLibraryScreenUI> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final appBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: isDark ? 0 : 1,
            title: _isSearching
                ? TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: textColor, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'search_videos_hint'.tr(),
                hintStyle: TextStyle(color: subtitleColor),
                border: InputBorder.none,
              ),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
            )
                : Text(
              'complete_video_library'.tr(),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isSearching ? Icons.close_rounded : Icons.search_rounded,
                  color: textColor,
                ),
                onPressed: () {
                  setState(() {
                    if (_isSearching) {
                      _isSearching = false;
                      _searchController.clear();
                      _searchQuery = '';
                    } else {
                      _isSearching = true;
                    }
                  });
                },
              ),
            ],
          ),
          body: VideosTabWidget(searchQuery: _searchQuery),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 10. شاشة الإعدادات المتطورة (Settings Screen UI)
// -------------------------------------------------------------------
class SettingsScreenUI extends StatefulWidget {
  const SettingsScreenUI({super.key});

  @override
  State<SettingsScreenUI> createState() => _SettingsScreenUIState();
}

class _SettingsScreenUIState extends State<SettingsScreenUI> {
  bool _audioEnhancement = true;
  bool _autoScanFolders = true;
  double _playbackSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final iconBg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0F7FA);
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: cardBg,
            elevation: isDark ? 0 : 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'app_settings_title'.tr(),
              style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // قسم المظهر
              _buildSectionHeader('appearance_section'.tr()),
              _buildGroupContainer(
                cardBg: cardBg,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: isDarkModeNotifier,
                    builder: (context, isDark, child) {
                      return _buildSwitchTile(
                        icon: Icons.dark_mode_rounded,
                        title: 'dark_mode_title'.tr(),
                        subtitle: 'dark_mode_subtitle'.tr(),
                        value: isDark,
                        textColor: textColor,
                        subtitleColor: subtitleColor,
                        iconBg: iconBg,
                        onChanged: (val) {
                          isDarkModeNotifier.value = val;
                        },
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // قسم الصوت والتشغيل
              _buildSectionHeader('audio_playback_section'.tr()),
              _buildGroupContainer(
                cardBg: cardBg,
                children: [
                  _buildSwitchTile(
                    icon: Icons.equalizer_rounded,
                    title: 'audio_enhancement_title'.tr(),
                    subtitle: 'audio_enhancement_subtitle'.tr(),
                    value: _audioEnhancement,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                    iconBg: iconBg,
                    onChanged: (val) {
                      setState(() {
                        _audioEnhancement = val;
                      });
                    },
                  ),
                  Divider(color: subtitleColor?.withValues(alpha: 0.15), height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.speed_rounded, color: Color(0xFF00BCD4)),
                    ),
                    title: Text('default_playback_speed'.tr(), style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('${'current_speed'.tr()}: $_playbackSpeed x', style: TextStyle(color: subtitleColor, fontSize: 13)),
                    trailing: DropdownButton<double>(
                      value: _playbackSpeed,
                      dropdownColor: cardBg,
                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                      underline: const SizedBox(),
                      items: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((double speed) {
                        return DropdownMenuItem<double>(
                          value: speed,
                          child: Text('$speed x'),
                        );
                      }).toList(),
                      onChanged: (double? newSpeed) {
                        if (newSpeed != null) {
                          setState(() {
                            _playbackSpeed = newSpeed;
                            globalAudioPlayer.setSpeed(_playbackSpeed);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // قسم الملفات والتخزين
              _buildSectionHeader('storage_files_section'.tr()),
              _buildGroupContainer(
                cardBg: cardBg,
                children: [
                  _buildSwitchTile(
                    icon: Icons.folder_open_rounded,
                    title: 'auto_scan_folders_title'.tr(),
                    subtitle: 'auto_scan_folders_subtitle'.tr(),
                    value: _autoScanFolders,
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                    iconBg: iconBg,
                    onChanged: (val) {
                      setState(() {
                        _autoScanFolders = val;
                      });
                    },
                  ),
                  Divider(color: subtitleColor?.withValues(alpha: 0.15), height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF00BCD4)),
                    ),
                    title: Text('clear_cache_title'.tr(), style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('clear_cache_subtitle'.tr(), style: TextStyle(color: subtitleColor, fontSize: 13)),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 16),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('cache_cleared_msg'.tr())),
                      );
                    },
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // قسم عن التطبيق
              _buildSectionHeader('about_app_section'.tr()),
              _buildGroupContainer(
                cardBg: cardBg,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.info_outline_rounded, color: Color(0xFF00BCD4)),
                    ),
                    title: Text('app_version_title'.tr(), style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
                    subtitle: Text('Nova Media v2.0 (Master Dream Build)', style: TextStyle(color: subtitleColor, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, right: 4.0, bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF00BCD4),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGroupContainer({required Color cardBg, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Color textColor,
    required Color? subtitleColor,
    required Color iconBg,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: const Color(0xFF00BCD4)),
      ),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: subtitleColor, fontSize: 13)),
      value: value,
      activeColor: const Color(0xFF00BCD4),
      onChanged: onChanged,
    );
  }
}

// -------------------------------------------------------------------
// 11. شاشة الترحيب (Welcome Screen UI)
// -------------------------------------------------------------------
class WelcomeScreenUI extends StatelessWidget {
  const WelcomeScreenUI({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FA);
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // شريط علوي خفيف لضبط اللغة والثيم سريعا
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                          color: textColor,
                        ),
                        onPressed: () {
                          isDarkModeNotifier.value = !isDarkModeNotifier.value;
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.language_rounded, color: Color(0xFF00BCD4), size: 20),
                        label: Text(
                          context.locale.languageCode == 'ar' ? 'English' : 'عربي',
                          style: const TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          if (context.locale.languageCode == 'ar') {
                            context.setLocale(const Locale('en'));
                          } else {
                            context.setLocale(const Locale('ar'));
                          }
                        },
                      ),
                    ],
                  ),
                  const Spacer(),

                  // شعار التطبيق المتألق
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      color: cardBg,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00BCD4).withValues(alpha: isDark ? 0.35 : 0.2),
                          blurRadius: 45,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_filled_rounded,
                        size: 85,
                        color: Color(0xFF00BCD4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // العنوان والوصف
                  Text(
                    'welcome_title'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      'welcome_desc'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const Spacer(),

                  // زر بدء التجربة
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BCD4),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                        shadowColor: const Color(0xFF00BCD4).withValues(alpha: 0.4),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const MainScreenUI()),
                        );
                      },
                      child: Text(
                        'start_experience_btn'.tr(),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 12. شاشة المفضلة المتطورة (Favorites Screen UI)
// -------------------------------------------------------------------
class FavoritesScreenUI extends StatelessWidget {
  const FavoritesScreenUI({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final appBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: isDark ? 0 : 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'favorite_songs_title'.tr(),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: FutureBuilder<List<SongModel>>(
                  future: globalAudioQuery.querySongs(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
                      );
                    }

                    final allSongs = snapshot.data ?? [];

                    return ValueListenableBuilder<Set<int>>(
                      valueListenable: favoriteSongsNotifier,
                      builder: (context, favorites, child) {
                        final favSongs = allSongs.where((s) => favorites.contains(s.id)).toList();

                        if (favSongs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.favorite_border_rounded, size: 70, color: subtitleColor),
                                const SizedBox(height: 16),
                                Text(
                                  'no_favorite_songs_yet'.tr(),
                                  style: TextStyle(color: subtitleColor, fontSize: 16),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                          itemCount: favSongs.length,
                          itemBuilder: (context, index) {
                            final song = favSongs[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8.0),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: QueryArtworkWidget(
                                  id: song.id,
                                  type: ArtworkType.AUDIO,
                                  nullArtworkWidget: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00BCD4).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4)),
                                  ),
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  song.artist ?? 'unknown_artist'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: subtitleColor, fontSize: 13),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.favorite_rounded, color: Color(0xFF00BCD4)),
                                  onPressed: () {
                                    final currentFavs = Set<int>.from(favoriteSongsNotifier.value);
                                    currentFavs.remove(song.id);
                                    favoriteSongsNotifier.value = currentFavs;
                                  },
                                ),
                                onTap: () async {
                                  currentSongNotifier.value = song;
                                  await globalAudioPlayer.setAudioSource(AudioSource.uri(Uri.parse(song.data)));
                                  globalAudioPlayer.play();
                                },
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              // MiniPlayer
              ValueListenableBuilder<SongModel?>(
                valueListenable: currentSongNotifier,
                builder: (context, song, child) {
                  if (song == null) return const SizedBox.shrink();
                  return MiniPlayerWidget(
                    song: song,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullPlayerScreenUI(song: song),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 13. شاشة الألبومات (Albums Screen UI)
// -------------------------------------------------------------------
class AlbumsScreenUI extends StatelessWidget {
  const AlbumsScreenUI({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final appBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final artworkBg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0F7FA);
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: isDark ? 0 : 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'music_albums_title'.tr(),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: FutureBuilder<List<AlbumModel>>(
                  future: globalAudioQuery.queryAlbums(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
                      );
                    }

                    final albums = snapshot.data ?? [];
                    if (albums.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.album_outlined, size: 70, color: subtitleColor),
                            const SizedBox(height: 16),
                            Text(
                              'no_albums_found'.tr(),
                              style: TextStyle(color: subtitleColor, fontSize: 16),
                            ),
                          ],
                        ),
                      );
                    }

                    return GridView.builder(
                      padding: const EdgeInsets.all(16.0),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.82,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: albums.length,
                      itemBuilder: (context, index) {
                        final album = albums[index];
                        return GestureDetector(
                          onTap: () {
                            // يمكنك التوجيه لشاشة تفاصيل الألبوم هنا
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    child: QueryArtworkWidget(
                                      id: album.id,
                                      type: ArtworkType.ALBUM,
                                      artworkWidth: double.infinity,
                                      artworkHeight: double.infinity,
                                      artworkFit: BoxFit.cover,
                                      nullArtworkWidget: Container(
                                        color: artworkBg,
                                        child: const Center(
                                          child: Icon(
                                            Icons.album_rounded,
                                            size: 55,
                                            color: Color(0xFF00BCD4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        album.album,
                                        style: TextStyle(
                                          color: textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${album.numOfSongs} ${'songs_count_suffix'.tr()}',
                                        style: TextStyle(
                                          color: subtitleColor,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // MiniPlayer
              ValueListenableBuilder<SongModel?>(
                valueListenable: currentSongNotifier,
                builder: (context, song, child) {
                  if (song == null) return const SizedBox.shrink();
                  return MiniPlayerWidget(
                    song: song,
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, anim1, anim2) => FullPlayerScreenUI(song: song),
                          transitionsBuilder: (context, anim1, anim2, child) {
                            return SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim1),
                              child: child,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 14. شاشة الفنانين المتطورة (Artists Screen UI)
// -------------------------------------------------------------------
class ArtistsScreenUI extends StatelessWidget {
  const ArtistsScreenUI({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDark, child) {
        final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7);
        final appBarBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final avatarBg = isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0F7FA);
        final textColor = isDark ? Colors.white : Colors.black87;
        final subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: AppBar(
            backgroundColor: appBarBg,
            elevation: isDark ? 0 : 1,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, color: textColor),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'artists_list_title'.tr(),
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
          body: Column(
            children: [
              Expanded(
                child: FutureBuilder<List<ArtistModel>>(
                  future: globalAudioQuery.queryArtists(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF00BCD4)));
                    }
                    final artists = snapshot.data ?? [];
                    if (artists.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_outline_rounded, size: 70, color: subtitleColor),
                            const SizedBox(height: 16),
                            Text('no_artists_found'.tr(), style: TextStyle(color: subtitleColor, fontSize: 16)),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: artists.length,
                      padding: const EdgeInsets.all(12),
                      itemBuilder: (context, index) {
                        final artist = artists[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: avatarBg,
                              child: const Icon(Icons.person_rounded, color: Color(0xFF00BCD4)),
                            ),
                            title: Text(
                              artist.artist,
                              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${artist.numberOfTracks ?? 0} ${'songs_count_suffix'.tr()}',
                              style: TextStyle(color: subtitleColor, fontSize: 13),
                            ),
                            trailing: Icon(Icons.arrow_forward_ios_rounded, color: subtitleColor, size: 16),
                            onTap: () {
                              // تفاعل التنقل لأغاني الفنان إذا رغبت
                            },
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // MiniPlayer
              ValueListenableBuilder<SongModel?>(
                valueListenable: currentSongNotifier,
                builder: (context, song, child) {
                  if (song == null) return const SizedBox.shrink();
                  return MiniPlayerWidget(
                    song: song,
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, anim1, anim2) => FullPlayerScreenUI(song: song),
                          transitionsBuilder: (context, anim1, anim2, child) {
                            return SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(anim1),
                              child: child,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------------
// 15. ويدجت الضغط التفاعلي المحسنة
// -------------------------------------------------------------------
class GestureDetectWithAnimation extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const GestureDetectWithAnimation({super.key, required this.child, required this.onTap});

  @override
  State<GestureDetectWithAnimation> createState() => _GestureDetectWithAnimationState();
}

class _GestureDetectWithAnimationState extends State<GestureDetectWithAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}
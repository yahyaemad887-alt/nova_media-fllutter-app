// ====================================================================
// NOVA MEDIA - COMPLETE INTEGRATED UI (Master Dream Build)
// ====================================================================
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:photo_manager/photo_manager.dart'; // 👈 تمت إضافة مكتبة إدارة الفيديوهات
import 'videos_screen.dart';
import 'Video_model.dart';
import 'video_player_screen.dart';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
ValueNotifier<List<SongModel>> allSongsNotifier = ValueNotifier<List<SongModel>>([]);
ValueNotifier<List<String>> favoriteIdsNotifier = ValueNotifier<List<String>>([]);
ValueNotifier<List<String>> recentIdsNotifier = ValueNotifier<List<String>>([]);

// تحميل البيانات المخزنة عند فتح التطبيق
Future<void> loadSavedData() async {
  final prefs = await SharedPreferences.getInstance();
  favoriteIdsNotifier.value = prefs.getStringList('favorites') ?? [];
  recentIdsNotifier.value = prefs.getStringList('recently_played') ?? [];
}

// إضافة/حذف أغنية من المفضلة
Future<void> toggleFavorite(String songId) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> updated = List.from(favoriteIdsNotifier.value);
  if (updated.contains(songId)) {
    updated.remove(songId);
  } else {
    updated.add(songId);
  }
  favoriteIdsNotifier.value = updated;
  await prefs.setStringList('favorites', updated);
}

// إضافة أغنية لسجل المشغلة مؤخراً
Future<void> addToRecentlyPlayed(String songId) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> updated = List.from(recentIdsNotifier.value);
  updated.remove(songId);
  updated.insert(0, songId);
  if (updated.length > 50) updated.removeLast();
  recentIdsNotifier.value = updated;
  await prefs.setStringList('recently_played', updated);
}
// -------------------------------------------------------------------
// المحرك العالمي والدولية لإدارة الحالات والتكامل (Global Engine & State)
// -------------------------------------------------------------------
final AudioPlayer globalAudioPlayer = AudioPlayer();
final OnAudioQuery globalAudioQuery = OnAudioQuery();

ValueNotifier<SongModel?> currentSongNotifier = ValueNotifier<SongModel?>(null);
ValueNotifier<List<SongModel>> currentPlaylistNotifier = ValueNotifier<List<SongModel>>([]);
ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(0);
ValueNotifier<Set<int>> favoriteSongsNotifier = ValueNotifier<Set<int>>({});
ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(true);

// دوال التحكم العالمية (للانتقال والرجوع مع دعم التشغيل العشوائي)
void playNextSongGlobal() async {
  final list = currentPlaylistNotifier.value;
  if (list.isEmpty) return;

  if (globalAudioPlayer.shuffleModeEnabled) {
    currentIndexNotifier.value = math.Random().nextInt(list.length);
  } else {
    currentIndexNotifier.value = (currentIndexNotifier.value + 1) % list.length;
  }

  final nextSong = list[currentIndexNotifier.value];
  currentSongNotifier.value = nextSong;

  // 🔥 حفظ الأغنية في سجل "المشغلة مؤخراً" تلقائياً
  addToRecentlyPlayed(nextSong.id.toString());

  // 🔥 إضافة MediaItem لدعم الإشعارات في الخلفية
  await globalAudioPlayer.setAudioSource(
    AudioSource.uri(
      Uri.parse(nextSong.data),
      tag: MediaItem(
        id: nextSong.id.toString(),
        album: nextSong.album ?? "موسيقى".tr(),
        title: nextSong.title,
        artist: nextSong.artist ?? "unknown_artist".tr(),
        artUri: Uri.parse('file://${nextSong.data}'),
      ),
    ),
  );
  globalAudioPlayer.play();
}

void playPreviousSongGlobal() async {
  final list = currentPlaylistNotifier.value;
  if (list.isEmpty) return;

  if (globalAudioPlayer.shuffleModeEnabled) {
    currentIndexNotifier.value = math.Random().nextInt(list.length);
  } else {
    currentIndexNotifier.value = (currentIndexNotifier.value - 1 + list.length) % list.length;
  }

  final prevSong = list[currentIndexNotifier.value];
  currentSongNotifier.value = prevSong;

  // 🔥 إضافة الأغنية لسجل المشغلة مؤخراً
  addToRecentlyPlayed(prevSong.id.toString());

  // 🔥 إضافة MediaItem لدعم الإشعارات في الخلفية
  await globalAudioPlayer.setAudioSource(
    AudioSource.uri(
      Uri.parse(prevSong.data),
      tag: MediaItem(
        id: prevSong.id.toString(),
        album: prevSong.album ?? "موسيقى".tr(),
        title: prevSong.title,
        artist: prevSong.artist ?? "unknown_artist".tr(),
        artUri: Uri.parse('file://${prevSong.data}'),
      ),
    ),
  );
  globalAudioPlayer.play();
}

// تهيئة جلسة الصوت وتفعيل الانتقال التلقائي
Future<void> initAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

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
// -------------------------------------------------------------------
// دالة جلب الفيديوهات الحقيقية من الجهاز (Real Local Video Fetcher)
// -------------------------------------------------------------------
Future<List<VideoModel>> fetchLocalVideos() async {
  List<VideoModel> localVideos = [];

  try {
    // 1. طلب الصلاحية من المستخدم
    final PermissionState ps = await PhotoManager.requestPermissionExtend();
    if (!ps.isAuth) {
      debugPrint('❌ لم يتم إعطاء صلاحية الوصول للملفات');
      return [];
    }

    // 2. جلب المجلدات التي تحتوي على فيديوهات
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: RequestType.video,
    );

    if (albums.isEmpty) return [];

    // 3. جلب الفيديوهات من المجلد الرئيسي - أول 100 فيديو كمثال
    List<AssetEntity> videoAssets = await albums[0].getAssetListPaged(
      page: 0,
      size: 100,
    );

    // 4. تحويل الفيديوهات إلى الموديل الخاص بالتطبيق
    for (var asset in videoAssets) {
      localVideos.add(
        VideoModel(
          id: asset.id,
          title: asset.title ?? 'فيديو بدون عنوان'.tr(),
          entity: asset, // 👈 تمرير الـ AssetEntity مباشرة هنا مطابقة للموديل
          duration: asset.videoDuration,
        ),
      );
    }
    debugPrint('✅ تم جلب ${localVideos.length} فيديو بنجاح');
  } catch (e) {
    debugPrint('❌ حدث خطأ أثناء جلب الفيديوهات: $e');
  }

  return localVideos;
}

// -------------------------------------------------------------------
// 1. الشاشة الرئيسية (Main Screen UI)
// -------------------------------------------------------------------
class MainScreenUI extends StatefulWidget {
  const MainScreenUI({Key? key}) : super(key: key);

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
    initAudioSession();
    _tabController = TabController(length: 3, vsync: this);
    _checkAndRequestPermission();
  }

  Future<void> _checkAndRequestPermission() async {
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
        return Theme(
          data: isDark ? ThemeData.dark() : ThemeData.light(),
          child: Scaffold(
            backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F7),
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context, isDark),
                  Expanded(
                    child: !_hasPermission
                        ? _buildPermissionRequestWidget()
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

  Widget _buildPermissionRequestWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF00BCD4).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.folder_special_rounded, size: 80, color: Color(0xFF00BCD4)),
            ),
            const SizedBox(height: 24),
            Text(
              'media_permission_title'.tr(),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'media_permission_desc'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.4),
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
                    suffixIcon: IconButton(
                      icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black),
                      onPressed: () {
                        setState(() {
                          _isSearching = false;
                          _searchQuery = '';
                          _searchController.clear();
                        });
                      },
                    ),
                  ),
                ),
              )
                  : Row(
                children: [
                  // 👈 تم استبدال الأيقونة القديمة بصورتك الشخصية ico.png
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
                      onPressed: () => _showOptionsMenu(context),
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
  void _showOptionsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
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
                decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4)),
                title: Text('complete_music_library'.tr(), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const MusicLibraryScreenUI()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library_rounded, color: Color(0xFF00BCD4)),
                title: Text('complete_video_library'.tr(), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (c) => const VideosLibraryScreenUI()));
                },
              ),
              const Divider(color: Color(0xFF2C2C2C)),
              ListTile(
                leading: const Icon(Icons.language_rounded, color: Color(0xFF00BCD4)),
                title: Text('select_language'.tr(), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: const Color(0xFF1E1E1E),
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
                              decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
                            ),
                            Text(
                              'choose_app_language'.tr(),
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.language, color: Color(0xFF00BCD4)),
                              title: Text('arabic_language'.tr(), style: const TextStyle(color: Colors.white)),
                              trailing: const Icon(Icons.check, color: Color(0xFF00BCD4)),
                              onTap: () {
                                Navigator.pop(context);
                                context.setLocale(const Locale('ar', ''));
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.language, color: Color(0xFF00BCD4)),
                              title: const Text('English', style: TextStyle(color: Colors.white)),
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
// 2. تبويب الأغاني (Songs Tab) - محرك تشغيل حقيقي وتكاملي
// -------------------------------------------------------------------
class SongsTabWidget extends StatelessWidget {
  final String searchQuery;
  const SongsTabWidget({Key? key, this.searchQuery = ''}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: globalAudioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text("${'music_error_loading'.tr()}: ${snapshot.error}", style: const TextStyle(color: Colors.white)));
        }
        if (snapshot.data == null) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00BCD4)));
        }
        if (snapshot.data!.isEmpty) {
          return Center(
            child: Text('no_audio_files_found'.tr(), style: const TextStyle(color: Colors.grey)),
          );
        }

        List<SongModel> songs = snapshot.data!.where((song) {
          return song.title.toLowerCase().contains(searchQuery) ||
              (song.artist ?? '').toLowerCase().contains(searchQuery);
        }).toList();

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
                    color: isSelected ? const Color(0xFF00BCD4).withOpacity(0.15) : Colors.transparent,
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
                          color: const Color(0xFF2C2C2C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4), size: 26),
                      ),
                    ),
                    title: Text(
                      song.title,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF00BCD4) : Colors.white,
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
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    trailing: ValueListenableBuilder<Set<int>>(
                      valueListenable: favoriteSongsNotifier,
                      builder: (context, favorites, child) {
                        final isFav = favorites.contains(song.id);
                        return IconButton(
                          icon: Icon(
                            isFav ? Icons.favorite_rounded : Icons.more_vert_rounded,
                            color: isFav ? Colors.pinkAccent : Colors.grey,
                          ),
                          onPressed: () {
                            if (isFav) {
                              favoriteSongsNotifier.value = Set.from(favoriteSongsNotifier.value)..remove(song.id);
                            } else {
                              _showSongOptions(context, song);
                            }
                          },
                        );
                      },
                    ),
                    onTap: () async {
                      currentSongNotifier.value = song;
                      currentPlaylistNotifier.value = songs;
                      currentIndexNotifier.value = index;

                      try {
                        await globalAudioPlayer.setAudioSource(
                          AudioSource.uri(
                            Uri.parse(song.data),
                            tag: MediaItem(
                              id: song.id.toString(),
                              album: song.album ?? "موسيقى".tr(),
                              title: song.title,
                              artist: song.artist ?? "unknown_artist".tr(),
                              artUri: Uri.parse('file://${song.data}'),
                            ),
                          ),
                        );
                        globalAudioPlayer.play();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${'playback_error'.tr()}: $e')),
                        );
                      }
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSongOptions(BuildContext context, SongModel song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.favorite_border, color: Colors.pinkAccent),
              title: Text('add_to_favorites'.tr(), style: const TextStyle(color: Colors.white)),
              onTap: () {
                favoriteSongsNotifier.value = Set.from(favoriteSongsNotifier.value)..add(song.id);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: Color(0xFF00BCD4)),
              title: Text('add_to_playlist'.tr(), style: const TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: Text('share_file'.tr(), style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  static String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).truncate();
    final minutes = (seconds / 60).truncate();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

// -------------------------------------------------------------------
// 3. تبويب الفيديوهات (Videos Tab) - ديناميكي ومدمج مع الصور المصغرة
// -------------------------------------------------------------------
class VideosTabWidget extends StatelessWidget {
  final String searchQuery;
  const VideosTabWidget({Key? key, this.searchQuery = ''}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<VideoModel>>(
      future: fetchLocalVideos(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF00BCD4)));
        }

        final videos = snapshot.data ?? [];

        if (videos.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.video_library_outlined, size: 60, color: Colors.grey),
                const SizedBox(height: 12),
                Text('no_videos_in_gallery'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }

        final filteredVideos = videos
            .where((v) => (v.title).toLowerCase().contains(searchQuery.toLowerCase()))
            .toList();

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 16 / 11,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: filteredVideos.length,
          itemBuilder: (context, index) {
            final video = filteredVideos[index];
            return GestureDetectWithAnimation(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(videoEntity: video.entity),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FutureBuilder<Uint8List?>(
                            future: video.entity.thumbnailDataWithSize(const ThumbnailSize(200, 200)),
                            builder: (context, thumbSnapshot) {
                              if (thumbSnapshot.connectionState == ConnectionState.done && thumbSnapshot.data != null) {
                                return ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                  child: Image.memory(
                                    thumbSnapshot.data!,
                                    fit: BoxFit.cover,
                                  ),
                                );
                              }
                              return Container(
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2C2C2C),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00BCD4)),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Center(
                            child: Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 36),
                          ),
                          Positioned(
                            bottom: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(video.duration),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        video.title,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final minutes = (seconds / 60).truncate();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

// -------------------------------------------------------------------
// 4. تبويب قوائم التشغيل (Playlists Tab) - النسخة المستقلة
// -------------------------------------------------------------------
class PlaylistsTabWidget extends StatelessWidget {
  const PlaylistsTabWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SongModel>>(
      future: globalAudioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
          );
        }

        final allSongs = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _buildCustomPlaylistItem(
              context,
              title: 'favorite_songs_title'.tr(),
              subtitle: 'favorite_songs_subtitle'.tr(),
              icon: Icons.favorite_rounded,
              color: Colors.pink,
              onTap: () {
                final favorites = favoriteSongsNotifier.value;
                final favSongs = allSongs
                    .where((s) => favorites.contains(s.id))
                    .toList();

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
            ),
            _buildCustomPlaylistItem(
              context,
              title: 'recently_played_title'.tr(),
              subtitle: 'recently_played_subtitle'.tr(),
              icon: Icons.history_rounded,
              color: Colors.cyan,
              onTap: () {
                final List<SongModel> recentSongs = [];
                for (var id in recentIdsNotifier.value) {
                  final match = allSongs.where((s) => s.id.toString() == id);
                  if (match.isNotEmpty) {
                    recentSongs.add(match.first);
                  }
                }

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
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(
                'device_folders_playlists'.tr(),
                style: const TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold),
              ),
            ),
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
                      child: Text('no_folders_with_songs'.tr(), style: const TextStyle(color: Colors.grey)),
                    ),
                  );
                }

                return Column(
                  children: folderPlaylists.entries.map((entry) {
                    return Card(
                      color: const Color(0xFF1E1E1E),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF2C2C2C),
                          child: Icon(Icons.folder_open_rounded, color: Color(0xFF00BCD4)),
                        ),
                        title: Text(
                          entry.key,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${entry.value.length} ${'songs_count_suffix'.tr()}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
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
  }

  Widget _buildCustomPlaylistItem(
      BuildContext context, {
        required String title,
        required String subtitle,
        required IconData icon,
        required Color color,
        required VoidCallback onTap,
      }) {
    return Card(
      color: const Color(0xFF1E1E1E),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(51),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
        onTap: onTap,
      ),
    );
  }
}

// -------------------------------------------------------------------
// 5. شاشة عرض الأغاني داخل القائمة والمفضلة والمشغلة مؤخراً
// -------------------------------------------------------------------
class PlaylistDetailsScreenUI extends StatelessWidget {
  final String title;
  final List<SongModel> songs;

  const PlaylistDetailsScreenUI({
    Key? key,
    required this.title,
    required this.songs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: songs.isEmpty
          ? Center(
        child: Text(
          'playlist_empty'.tr(),
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      )
          : ListView.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return ListTile(
            leading: QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              nullArtworkWidget: const CircleAvatar(
                backgroundColor: Color(0xFF2C2C2C),
                child: Icon(Icons.music_note, color: Color(0xFF00BCD4)),
              ),
            ),
            title: Text(
              song.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              song.artist ?? "unknown_artist".tr(),
              style: const TextStyle(color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () async {
              currentSongNotifier.value = song;
              currentPlaylistNotifier.value = songs;
              currentIndexNotifier.value = index;

              addToRecentlyPlayed(song.id.toString());

              await globalAudioPlayer.setAudioSource(
                AudioSource.uri(
                  Uri.parse(song.data),
                  tag: MediaItem(
                    id: song.id.toString(),
                    album: song.album ?? "موسيقى".tr(),
                    title: song.title,
                    artist: song.artist ?? "unknown_artist".tr(),
                    artUri: Uri.parse('file://${song.data}'),
                  ),
                ),
              );
              globalAudioPlayer.play();
            },
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------
// 6. المشغل المصغر السفلي (Mini Player Widget)
// -------------------------------------------------------------------
class MiniPlayerWidget extends StatelessWidget {
  final SongModel song;
  final VoidCallback onTap;

  const MiniPlayerWidget({
    Key? key,
    required this.song,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 68,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
          border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            QueryArtworkWidget(
              id: song.id,
              type: ArtworkType.AUDIO,
              artworkBorder: BorderRadius.circular(10),
              nullArtworkWidget: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C2C2C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    song.artist ?? "unknown_artist".tr(),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<List<String>>(
              valueListenable: favoriteIdsNotifier,
              builder: (context, favorites, _) {
                final isFav = favorites.contains(song.id.toString());
                return IconButton(
                  icon: Icon(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFav ? Colors.redAccent : Colors.grey,
                    size: 24,
                  ),
                  onPressed: () => toggleFavorite(song.id.toString()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
              onPressed: () => playPreviousSongGlobal(),
            ),
            StreamBuilder<bool>(
              stream: globalAudioPlayer.playingStream,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                    color: const Color(0xFF00BCD4),
                    size: 36,
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
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
              onPressed: () => playNextSongGlobal(),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------
// 7. شاشة تشغيل الموسيقى الكاملة احترافية (Full Player Screen UI)
// -------------------------------------------------------------------
class FullPlayerScreenUI extends StatefulWidget {
  final SongModel song;
  const FullPlayerScreenUI({Key? key, required this.song}) : super(key: key);

  @override
  State<FullPlayerScreenUI> createState() => _FullPlayerScreenUIState();
}

class _FullPlayerScreenUIState extends State<FullPlayerScreenUI> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 34),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text('main_player_title'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                    onPressed: () => _showPlayerMenu(context),
                  ),
                ],
              ),
              const Spacer(),
              ValueListenableBuilder<SongModel?>(
                valueListenable: currentSongNotifier,
                builder: (context, song, child) {
                  final activeSong = song ?? widget.song;
                  return Hero(
                    tag: 'artwork_${activeSong.id}',
                    child: QueryArtworkWidget(
                      id: activeSong.id,
                      type: ArtworkType.AUDIO,
                      artworkWidth: MediaQuery.of(context).size.width * 0.78,
                      artworkHeight: MediaQuery.of(context).size.width * 0.78,
                      artworkBorder: BorderRadius.circular(24),
                      size: 2000,
                      quality: 100,
                      artworkQuality: FilterQuality.high,
                      nullArtworkWidget: Container(
                        width: MediaQuery.of(context).size.width * 0.78,
                        height: MediaQuery.of(context).size.width * 0.78,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00BCD4).withOpacity(0.25),
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
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              activeSong.artist ?? "unknown_artist".tr(),
                              style: const TextStyle(color: Colors.grey, fontSize: 15),
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
                              color: isFav ? Colors.pinkAccent : Colors.white,
                              size: 30,
                            ),
                            onPressed: () {
                              if (isFav) {
                                favoriteSongsNotifier.value = Set.from(favoriteSongsNotifier.value)..remove(activeSong.id);
                              } else {
                                favoriteSongsNotifier.value = Set.from(favoriteSongsNotifier.value)..add(activeSong.id);
                              }
                            },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              StreamBuilder<Duration>(
                stream: globalAudioPlayer.positionStream,
                builder: (context, snapshot) {
                  final position = snapshot.data ?? Duration.zero;
                  final duration = globalAudioPlayer.duration ?? Duration.zero;

                  return Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF00BCD4),
                          inactiveTrackColor: Colors.grey[800],
                          thumbColor: const Color(0xFF00BCD4),
                          trackHeight: 4.0,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                        ),
                        child: Slider(
                          value: position.inSeconds.toDouble().clamp(0.0, duration.inSeconds.toDouble()),
                          min: 0.0,
                          max: duration.inSeconds > 0 ? duration.inSeconds.toDouble() : 1.0,
                          onChanged: (val) {
                            globalAudioPlayer.seek(Duration(seconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(position), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(_formatDuration(duration), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  StreamBuilder<bool>(
                    stream: globalAudioPlayer.shuffleModeEnabledStream,
                    builder: (context, snapshot) {
                      final isShuffle = snapshot.data ?? false;
                      return IconButton(
                        icon: Icon(Icons.shuffle_rounded, color: isShuffle ? const Color(0xFF00BCD4) : Colors.grey, size: 26),
                        onPressed: () async {
                          await globalAudioPlayer.setShuffleModeEnabled(!isShuffle);
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 40),
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
                          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 40),
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
                  ValueListenableBuilder<List<String>>(
                    valueListenable: favoriteIdsNotifier,
                    builder: (context, favorites, _) {
                      final isFav = currentSongNotifier.value != null &&
                          favorites.contains(currentSongNotifier.value!.id.toString());
                      return IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? Colors.redAccent : Colors.white,
                          size: 30,
                        ),
                        onPressed: () {
                          if (currentSongNotifier.value != null) {
                            toggleFavorite(currentSongNotifier.value!.id.toString());
                          }
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 40),
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

                      Color color = (isRepeatOne || isRepeatAll) ? const Color(0xFF00BCD4) : Colors.grey;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
                    onPressed: () => _showQueueBottomSheet(context),
                  ),
                  const SizedBox(width: 40),
                  IconButton(
                    icon: const Icon(Icons.timer_rounded, color: Colors.white70),
                    onPressed: () => _showSleepTimerDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueueBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final playlist = currentPlaylistNotifier.value;
        return Container(
          padding: const EdgeInsets.all(16),
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('current_playlist_title'.tr(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: playlist.length,
                  itemBuilder: (context, index) {
                    final song = playlist[index];
                    return ListTile(
                      title: Text(song.title, style: const TextStyle(color: Colors.white), maxLines: 1),
                      subtitle: Text(song.artist ?? 'unknown_artist'.tr(), style: const TextStyle(color: Colors.grey)),
                      onTap: () async {
                        currentSongNotifier.value = song;
                        currentIndexNotifier.value = index;

                        await globalAudioPlayer.setAudioSource(
                          AudioSource.uri(
                            Uri.parse(song.data),
                            tag: MediaItem(
                              id: song.id.toString(),
                              album: song.album ?? "موسيقى".tr(),
                              title: song.title,
                              artist: song.artist ?? "unknown_artist".tr(),
                              artUri: Uri.parse('file://${song.data}'),
                            ),
                          ),
                        );

                        globalAudioPlayer.play();
                        if (context.mounted) Navigator.pop(context);
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

  void _showSleepTimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text('sleep_timer_title'.tr(), style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [15, 30, 45, 60].map((minutes) {
              return ListTile(
                title: Text('$minutes ${'minutes_suffix'.tr()}', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Timer(Duration(minutes: minutes), () {
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

  void _showPlayerMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: Text('audio_file_details'.tr(), style: const TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }
}

// -------------------------------------------------------------------
// 8. شاشة مكتبة الموسيقى الشاملة (Music Library Screen UI)
// -------------------------------------------------------------------
class MusicLibraryScreenUI extends StatefulWidget {
  const MusicLibraryScreenUI({Key? key}) : super(key: key);

  @override
  State<MusicLibraryScreenUI> createState() => _MusicLibraryScreenUIState();
}

class _MusicLibraryScreenUIState extends State<MusicLibraryScreenUI> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: Text(
          'complete_music_library'.tr(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00BCD4),
          labelColor: const Color(0xFF00BCD4),
          unselectedLabelColor: Colors.grey,
          tabs: [
            Tab(icon: const Icon(Icons.videocam_rounded), text: "videos_tab".tr()),
            Tab(icon: const Icon(Icons.music_note_rounded), text: "songs_tab".tr()),
            Tab(icon: const Icon(Icons.playlist_play_rounded), text: "playlists_tab".tr()),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          VideosTabWidget(searchQuery: _searchQuery),
          SongsTabWidget(searchQuery: _searchQuery),
          const PlaylistsTabWidget(),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------
// 9. شاشة مكتبة الفيديوهات (Videos Library Screen UI)
// -------------------------------------------------------------------
class VideosLibraryScreenUI extends StatefulWidget {
  const VideosLibraryScreenUI({Key? key}) : super(key: key);

  @override
  State<VideosLibraryScreenUI> createState() => _VideosLibraryScreenUIState();
}

class _VideosLibraryScreenUIState extends State<VideosLibraryScreenUI> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: Text('complete_video_library'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: const VideosTabWidget(),
    );
  }
}

// -------------------------------------------------------------------
// 10. شاشة الإعدادات المتطورة (Settings Screen UI)
// -------------------------------------------------------------------
class SettingsScreenUI extends StatefulWidget {
  const SettingsScreenUI({Key? key}) : super(key: key);

  @override
  State<SettingsScreenUI> createState() => _SettingsScreenUIState();
}

class _SettingsScreenUIState extends State<SettingsScreenUI> {
  bool _audioEnhancement = true;
  bool _autoScanFolders = true;
  double _playbackSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('app_settings_title'.tr(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader('appearance_section'.tr()),
          ValueListenableBuilder<bool>(
            valueListenable: isDarkModeNotifier,
            builder: (context, isDark, child) {
              return _buildSwitchTile(
                icon: Icons.dark_mode_rounded,
                title: 'dark_mode_title'.tr(),
                subtitle: 'dark_mode_subtitle'.tr(),
                value: isDark,
                onChanged: (val) {
                  isDarkModeNotifier.value = val;
                },
              );
            },
          ),
          const Divider(color: Color(0xFF2C2C2C), height: 30),
          _buildSectionHeader('audio_playback_section'.tr()),
          _buildSwitchTile(
            icon: Icons.equalizer_rounded,
            title: 'audio_enhancement_title'.tr(),
            subtitle: 'audio_enhancement_subtitle'.tr(),
            value: _audioEnhancement,
            onChanged: (val) {
              setState(() {
                _audioEnhancement = val;
              });
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.speed_rounded, color: Color(0xFF00BCD4)),
            ),
            title: Text('default_playback_speed'.tr(), style: const TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: Text('${'current_speed'.tr()}: $_playbackSpeed x', style: const TextStyle(color: Colors.grey, fontSize: 13)),
            trailing: DropdownButton<double>(
              value: _playbackSpeed,
              dropdownColor: const Color(0xFF1E1E1E),
              style: const TextStyle(color: Colors.white),
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
          const Divider(color: Color(0xFF2C2C2C), height: 30),
          _buildSectionHeader('storage_files_section'.tr()),
          _buildSwitchTile(
            icon: Icons.folder_open_rounded,
            title: 'auto_scan_folders_title'.tr(),
            subtitle: 'auto_scan_folders_subtitle'.tr(),
            value: _autoScanFolders,
            onChanged: (val) {
              setState(() {
                _autoScanFolders = val;
              });
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.cleaning_services_rounded, color: Color(0xFF00BCD4)),
            ),
            title: Text('clear_cache_title'.tr(), style: const TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: Text('clear_cache_subtitle'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 13)),
            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey, size: 16),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('cache_cleared_msg'.tr())),
              );
            },
          ),
          const Divider(color: Color(0xFF2C2C2C), height: 30),
          _buildSectionHeader('about_app_section'.tr()),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.info_outline_rounded, color: Color(0xFF00BCD4)),
            ),
            title: Text('app_version_title'.tr(), style: const TextStyle(color: Colors.white, fontSize: 15)),
            subtitle: const Text('Nova Media v2.0 (Master Dream Build)', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF00BCD4),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: const Color(0xFF00BCD4)),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
  const WelcomeScreenUI({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00BCD4).withOpacity(0.3),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_filled_rounded,
                    size: 80,
                    color: Color(0xFF00BCD4),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'welcome_title'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'welcome_desc'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const Spacer(),
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
                    elevation: 0,
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
  }
}

// -------------------------------------------------------------------
// 12. شاشة المفضلة (Favorites Screen UI)
// -------------------------------------------------------------------
class FavoritesScreenUI extends StatelessWidget {
  const FavoritesScreenUI({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('favorite_songs_title'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: ValueListenableBuilder<Set<int>>(
        valueListenable: favoriteSongsNotifier,
        builder: (context, favorites, child) {
          if (favorites.isEmpty) {
            return Center(
              child: Text('no_favorite_songs_yet'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 16)),
            );
          }
          return FutureBuilder<List<SongModel>>(
            future: globalAudioQuery.querySongs(),
            builder: (context, snapshot) {
              final allSongs = snapshot.data ?? [];
              final favSongs = allSongs.where((s) => favorites.contains(s.id)).toList();

              return ListView.builder(
                itemCount: favSongs.length,
                itemBuilder: (context, index) {
                  final song = favSongs[index];
                  return ListTile(
                    leading: const Icon(Icons.music_note_rounded, color: Color(0xFF00BCD4)),
                    title: Text(song.title, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(song.artist ?? 'unknown_artist'.tr(), style: const TextStyle(color: Colors.grey)),
                    onTap: () async {
                      currentSongNotifier.value = song;
                      await globalAudioPlayer.setAudioSource(AudioSource.uri(Uri.parse(song.data)));
                      globalAudioPlayer.play();
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------
// 13. شاشة الألبومات الحقيقية (Albums Screen UI)
// -------------------------------------------------------------------
class AlbumsScreenUI extends StatelessWidget {
  const AlbumsScreenUI({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('music_albums_title'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<List<AlbumModel>>(
        future: globalAudioQuery.queryAlbums(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00BCD4)));
          }
          final albums = snapshot.data ?? [];
          if (albums.isEmpty) {
            return Center(child: Text('no_albums_found'.tr(), style: const TextStyle(color: Colors.grey)));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: QueryArtworkWidget(
                        id: album.id,
                        type: ArtworkType.ALBUM,
                        artworkBorder: const BorderRadius.vertical(top: Radius.circular(14)),
                        nullArtworkWidget: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF2C2C2C),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                          ),
                          child: const Center(child: Icon(Icons.album_rounded, size: 50, color: Color(0xFF00BCD4))),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(album.album, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1),
                          Text('${album.numOfSongs} ${'songs_count_suffix'.tr()}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------
// 14. شاشة الفنانين الحقيقية (Artists Screen UI)
// -------------------------------------------------------------------
class ArtistsScreenUI extends StatelessWidget {
  const ArtistsScreenUI({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('artists_list_title'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<List<ArtistModel>>(
        future: globalAudioQuery.queryArtists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00BCD4)));
          }
          final artists = snapshot.data ?? [];
          if (artists.isEmpty) {
            return Center(child: Text('no_artists_found'.tr(), style: const TextStyle(color: Colors.grey)));
          }

          return ListView.builder(
            itemCount: artists.length,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, index) {
              final artist = artists[index];
              return Card(
                color: const Color(0xFF1E1E1E),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF2C2C2C),
                    child: Icon(Icons.person_rounded, color: Color(0xFF00BCD4)),
                  ),
                  title: Text(artist.artist, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('${artist.numberOfTracks ?? 0} ${'songs_count_suffix'.tr()}', style: const TextStyle(color: Colors.grey)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------
// 15. ويدجت الضغط التفاعلي بالأبعاد (Animation Helper)
// -------------------------------------------------------------------
class GestureDetectWithAnimation extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const GestureDetectWithAnimation({Key? key, required this.child, required this.onTap}) : super(key: key);

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
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(_controller);
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
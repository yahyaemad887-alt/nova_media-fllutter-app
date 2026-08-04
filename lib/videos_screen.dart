import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'video_player_screen.dart';

// ====================================================================
// 1. تبويب الفيديوهات (Videos Tab)
// ====================================================================
class VideosTabWidget extends StatefulWidget {
  const VideosTabWidget({super.key});

  @override
  State<VideosTabWidget> createState() => _VideosTabWidgetState();
}

class _VideosTabWidgetState extends State<VideosTabWidget> {
  List<AssetEntity> _videoList = [];
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    PhotoManager.addChangeCallback(_onPhotoManagerChange);
    PhotoManager.startChangeNotify();
    _fetchVideos();
  }

  @override
  void dispose() {
    PhotoManager.removeChangeCallback(_onPhotoManagerChange);
    PhotoManager.stopChangeNotify();
    super.dispose();
  }

  void _onPhotoManagerChange(MethodCall call) {
    if (mounted) {
      _fetchVideos();
    }
  }

  Future<void> _fetchVideos() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();

      if (ps.isAuth || ps.hasAccess || ps == PermissionState.limited) {
        // جلب قائمة الفيديوهات مباشرة بدون الاعتماد على الألبومات
        final List<AssetEntity> media = await PhotoManager.getAssetListRange(
          start: 0,
          end: 5000,
          type: RequestType.video,
          filterOption: FilterOptionGroup(
            orders: [
              const OrderOption(
                type: OrderOptionType.createDate,
                asc: false,
              ),
            ],
          ),
        );

        if (mounted) {
          setState(() {
            _videoList = media;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching videos: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)));
    }

    if (_permissionDenied) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 50, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'التطبيق يحتاج صلاحية الوصول للملفات لعرض الفيديوهات',
              style: TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
              onPressed: () async {
                await PhotoManager.openSetting();
                _fetchVideos();
              },
              child: const Text('منح الصلاحية من الإعدادات', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_videoList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'لا توجد مقاطع فيديو متاحة في المعرض',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF6C5CE7), size: 30),
              onPressed: _fetchVideos,
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF6C5CE7),
      onRefresh: _fetchVideos,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _videoList.length,
        itemBuilder: (context, index) {
          return _VideoGridItem(
            video: _videoList[index],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(videoEntity: _videoList[index]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ====================================================================
// 2. شاشة مكتبة الفيديوهات الكاملة (Videos Library Screen UI)
// ====================================================================
class VideosLibraryScreenUI extends StatefulWidget {
  const VideosLibraryScreenUI({super.key});

  @override
  State<VideosLibraryScreenUI> createState() => _VideosLibraryScreenUIState();
}

class _VideosLibraryScreenUIState extends State<VideosLibraryScreenUI> {
  bool _isGridView = true;
  List<AssetEntity> _videoList = [];
  bool _isLoading = true;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    PhotoManager.addChangeCallback(_onPhotoManagerChange);
    PhotoManager.startChangeNotify();
    _fetchVideos();
  }

  @override
  void dispose() {
    PhotoManager.removeChangeCallback(_onPhotoManagerChange);
    PhotoManager.stopChangeNotify();
    super.dispose();
  }

  void _onPhotoManagerChange(MethodCall call) {
    if (mounted) {
      _fetchVideos();
    }
  }

  Future<void> _fetchVideos() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _permissionDenied = false;
    });

    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend();

      if (ps.isAuth || ps.hasAccess || ps == PermissionState.limited) {
        final List<AssetEntity> media = await PhotoManager.getAssetListRange(
          start: 0,
          end: 5000,
          type: RequestType.video,
          filterOption: FilterOptionGroup(
            orders: [
              const OrderOption(
                type: OrderOptionType.createDate,
                asc: false,
              ),
            ],
          ),
        );

        if (mounted) {
          setState(() {
            _videoList = media;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching videos: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: RefreshIndicator(
        color: const Color(0xFF6C5CE7),
        onRefresh: _fetchVideos,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverAppBar(
              backgroundColor: const Color(0xFF1E1E2C),
              expandedHeight: 120.0,
              floating: true,
              pinned: true,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Colors.white),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: const Text('مكتبة الفيديو', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFF1E1E2C), const Color(0xFF6C5CE7).withValues(alpha: 0.2)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7))),
              )
            else if (_permissionDenied)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock_outline, size: 50, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'يلزم السماح بالوصول للفيديوهات من الإعدادات',
                        style: TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
                        onPressed: () async {
                          await PhotoManager.openSetting();
                          _fetchVideos();
                        },
                        child: const Text('فتح الإعدادات', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              )
            else if (_videoList.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('لا توجد فيديوهات متاحة', style: TextStyle(color: Colors.grey))),
                )
              else
                _isGridView ? _buildGrid() : _buildList(),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return SliverPadding(
      padding: const EdgeInsets.all(12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
              (context, index) => _VideoGridItem(
            video: _videoList[index],
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(videoEntity: _videoList[index]),
                ),
              );
            },
          ),
          childCount: _videoList.length,
        ),
      ),
    );
  }

  Widget _buildList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          AssetEntity video = _videoList[index];
          return Card(
            color: const Color(0xFF1E1E2C),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.all(8),
              leading: SizedBox(
                width: 80,
                height: 60,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ImageItemWidget(entity: video),
                ),
              ),
              title: Text(
                video.title ?? 'فيديو بدون عنوان',
                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _formatDuration(video.duration),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => VideoPlayerScreen(videoEntity: video),
                  ),
                );
              },
            ),
          );
        },
        childCount: _videoList.length,
      ),
    );
  }
}

// ====================================================================
// عناصر الواجهة والصور المصغرة
// ====================================================================
class _VideoGridItem extends StatelessWidget {
  final AssetEntity video;
  final VoidCallback onTap;

  const _VideoGridItem({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2C),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    child: ImageItemWidget(entity: video),
                  ),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(video.duration),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                video.title ?? 'فيديو بدون عنوان',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// الويجت المحسن لعرض الصور المصغرة
class ImageItemWidget extends StatelessWidget {
  final AssetEntity entity;

  const ImageItemWidget({super.key, required this.entity});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: entity.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }

        if (snapshot.hasError) {
          return Container(
            color: const Color(0xFF2A2A3D),
            child: const Center(child: Icon(Icons.videocam_off, color: Colors.grey)),
          );
        }

        return Container(
          color: const Color(0xFF2A2A3D),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6C5CE7)),
            ),
          ),
        );
      },
    );
  }
}

String _formatDuration(int seconds) {
  final minutes = (seconds / 60).truncate();
  final remainingSeconds = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 👈 تم التصحيح إلى .dart بدلاً من .h
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';

class VideoPlayerScreen extends StatefulWidget {
  final AssetEntity videoEntity;

  const VideoPlayerScreen({super.key, required this.videoEntity}); // 👈 تم التحديث للطريقة الحديثة

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _showControls = true;
  bool _isLocked = false;
  double _currentSpeed = 1.0;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // السماح بتدوير الشاشة بكل الاتجاهات عند فتح الفيديو
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final String? mediaUrl = await widget.videoEntity.getMediaUrl();

    if (mediaUrl != null) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(mediaUrl))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isInitialized = true;
            });
            _controller!.play();
            setState(() {
              _isPlaying = true;
            });
            _startHideTimer();
          }
        });

      _controller!.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _controller!.value.isPlaying;
          });
        }
      });
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (!_isLocked) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isPlaying) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  void _toggleControls() {
    if (_isLocked) return;
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  // تغيير سرعة الفيديو
  void _changeSpeed() {
    List<double> speeds = [0.5, 1.0, 1.25, 1.5, 2.0];
    int nextIndex = (speeds.indexOf(_currentSpeed) + 1) % speeds.length;
    setState(() {
      _currentSpeed = speeds[nextIndex];
      _controller?.setPlaybackSpeed(_currentSpeed);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('السرعة: ${_currentSpeed}x'), duration: const Duration(milliseconds: 800)),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.dispose();
    // إعادة الشاشة للوضع العمودي الطبيعي عند الخروج من شاشة الفيديو
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isInitialized && _controller != null
            ? GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // الفيديو الأساسي في المنتصف
              Center(
                child: AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                ),
              ),

              // طبقة التحكم والواجهة
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // الشريط العلوي
                        Padding(
                          padding: const EdgeInsets.only(top: 30, left: 16, right: 16),
                          child: Row(
                            children: [
                              if (!_isLocked)
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.videoEntity.title ?? 'فيديو',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // زر تغيير السرعة
                              TextButton.icon(
                                onPressed: _changeSpeed,
                                icon: const Icon(Icons.speed, color: Color(0xFF00BCD4), size: 20),
                                label: Text(
                                  '${_currentSpeed}x',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // أزرار التحكم في المنتصف
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.replay_10, color: Colors.white, size: 36),
                              onPressed: () {
                                final currentPosition = _controller!.value.position;
                                final targetPosition = currentPosition - const Duration(seconds: 10);
                                _controller!.seekTo(targetPosition > Duration.zero ? targetPosition : Duration.zero);
                                _startHideTimer();
                              },
                            ),
                            const SizedBox(width: 30),
                            Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFF00BCD4),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                icon: Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: Colors.black,
                                  size: 40,
                                ),
                                onPressed: () {
                                  setState(() {
                                    if (_isPlaying) {
                                      _controller!.pause();
                                    } else {
                                      _controller!.play();
                                      _startHideTimer();
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 30),
                            IconButton(
                              icon: const Icon(Icons.forward_10, color: Colors.white, size: 36),
                              onPressed: () {
                                final currentPosition = _controller!.value.position;
                                final duration = _controller!.value.duration;
                                final targetPosition = currentPosition + const Duration(seconds: 10);
                                _controller!.seekTo(targetPosition < duration ? targetPosition : duration);
                                _startHideTimer();
                              },
                            ),
                          ],
                        ),

                        // الشريط السفلي
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          child: Row(
                            children: [
                              ValueListenableBuilder(
                                valueListenable: _controller!,
                                builder: (context, VideoPlayerValue value, child) {
                                  return Text(
                                    _formatDuration(value.position),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  );
                                },
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: VideoProgressIndicator(
                                  _controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Color(0xFF00BCD4),
                                    bufferedColor: Colors.white24,
                                    backgroundColor: Colors.grey,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ValueListenableBuilder(
                                valueListenable: _controller!,
                                builder: (context, VideoPlayerValue value, child) {
                                  return Text(
                                    _formatDuration(value.duration),
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  );
                                },
                              ),
                              const SizedBox(width: 10),
                              // زر قفل الشاشة
                              IconButton(
                                icon: Icon(
                                  _isLocked ? Icons.lock : Icons.lock_open,
                                  color: _isLocked ? const Color(0xFF00BCD4) : Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isLocked = !_isLocked;
                                    if (_isLocked) _showControls = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(_isLocked ? 'تم قفل الشاشة' : 'تم إلغاء القفل'),
                                      duration: const Duration(milliseconds: 800),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
            : const CircularProgressIndicator(color: Color(0xFF00BCD4)),
      ),
    );
  }
}
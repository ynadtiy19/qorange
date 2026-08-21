// lib/views/shop/confetti_celebration_overlay.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 自绘制烟花与庆祝彩带粒子模型
class _ConfettiParticle {
  late double x;
  late double y;
  late double vx;
  late double vy;
  late double size;
  late Color color;
  late double rotation;
  late double rotationSpeed;
  late double flip;
  late double flipSpeed;
  late int shapeType; // 0: 矩形丝带, 1: 圆形碎屑, 2: 五角星, 3: 烟花发散火花

  _ConfettiParticle.firework(double startX, double startY, math.Random random) {
    x = startX;
    y = startY;
    final angle = random.nextDouble() * 2 * math.pi;
    final speed = random.nextDouble() * 240 + 80;
    vx = math.cos(angle) * speed;
    vy = math.sin(angle) * speed - 60; // 初始略微向上冲
    size = random.nextDouble() * 4 + 3;
    rotation = random.nextDouble() * 2 * math.pi;
    rotationSpeed = (random.nextDouble() - 0.5) * 6;
    flip = random.nextDouble() * 2 * math.pi;
    flipSpeed = random.nextDouble() * 8;
    shapeType = random.nextInt(10) > 7 ? 2 : (random.nextBool() ? 0 : 1);

    const colors = [
      Color(0xFF2C7B6D),
      Color(0xFFFFB703),
      Color(0xFFFB8500),
      Color(0xFFE63946),
      Color(0xFF48CAE4),
      Color(0xFF9D4EDD),
      Color(0xFFFFD166),
      Color(0xFF06D6A0),
    ];
    color = colors[random.nextInt(colors.length)];
  }

  void update(double dt, double gravity) {
    x += vx * dt;
    y += vy * dt;
    vy += gravity * dt;
    vx *= 0.98; // 空气阻力
    rotation += rotationSpeed * dt;
    flip += flipSpeed * dt;
  }
}

/// 烟花与丝带自绘制画布
class _CelebrationPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _CelebrationPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // 绘制中心微光冲击波光晕
    if (progress < 0.45) {
      final waveProgress = progress / 0.45;
      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1.0 - waveProgress) * 4
        ..color = const Color(0xFF2C7B6D).withOpacity((1.0 - waveProgress) * 0.4);
      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2 - 40),
        waveProgress * (size.width * 0.45),
        wavePaint,
      );
    }

    final double alpha = (1.0 - (progress - 0.7).clamp(0.0, 0.3) / 0.3).clamp(0.0, 1.0);

    for (final p in particles) {
      paint.color = p.color.withOpacity((p.color.opacity * alpha).clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rotation);
      final scaleX = math.cos(p.flip);
      canvas.scale(scaleX.abs(), 1.0);

      if (p.shapeType == 0) {
        // 丝带纸屑矩形
        final rect = Rect.fromCenter(center: Offset.zero, width: p.size * 1.8, height: p.size);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
      } else if (p.shapeType == 1) {
        // 圆形粒子
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        // 五角星粒子
        final path = Path();
        const numPoints = 5;
        final outerRadius = p.size;
        final innerRadius = p.size / 2.2;
        for (int i = 0; i < numPoints * 2; i++) {
          final r = i.isEven ? outerRadius : innerRadius;
          final angle = (i * math.pi) / numPoints - math.pi / 2;
          final point = Offset(math.cos(angle) * r, math.sin(angle) * r);
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) => true;
}

/// 屏幕居中祝贺徽章与全屏烟花 Overlay 控制器
class ConfettiCelebrationOverlay {
  static void show(
      BuildContext context, {
        String title = '恭喜！解锁成功',
        String subtitle = '商品权益已成功下发至您的账号',
        VoidCallback? onFinished,
      }) {
    final overlayState = Overlay.of(context, rootOverlay: true);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _CelebrationWidget(
        title: title,
        subtitle: subtitle,
        onDismiss: () {
          overlayEntry.remove();
          if (onFinished != null) onFinished();
        },
      ),
    );

    overlayState.insert(overlayEntry);
  }
}

class _CelebrationWidget extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback onDismiss;

  const _CelebrationWidget({
    required this.title,
    required this.subtitle,
    required this.onDismiss,
  });

  @override
  State<_CelebrationWidget> createState() => _CelebrationWidgetState();
}

class _CelebrationWidgetState extends State<_CelebrationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _badgeScale;
  late Animation<double> _badgeOpacity;
  final List<_ConfettiParticle> _particles = [];
  final math.Random _random = math.Random();
  double _lastUpdateTime = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _badgeScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.15).chain(CurveTween(curve: Curves.easeOutBack)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8).chain(CurveTween(curve: Curves.easeInBack)), weight: 15),
    ]).animate(_controller);

    _badgeOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 20),
    ]).animate(_controller);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initParticles();
      _controller.forward().then((_) => widget.onDismiss());
    });

    _controller.addListener(_updatePhysics);
  }

  void _initParticles() {
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final centerY = size.height / 2 - 40;

    // 产生左右双点与中心三连发烟花爆裂
    final sources = [
      Offset(centerX, centerY),
      Offset(centerX - 80, centerY + 40),
      Offset(centerX + 80, centerY + 40),
    ];

    for (final src in sources) {
      for (int i = 0; i < 45; i++) {
        _particles.add(_ConfettiParticle.firework(src.dx, src.dy, _random));
      }
    }
  }

  void _updatePhysics() {
    final currentTime = _controller.value;
    final dt = (currentTime - _lastUpdateTime) * 2.6; // 时间缩放
    _lastUpdateTime = currentTime;

    if (dt > 0 && dt < 0.1) {
      for (final p in _particles) {
        p.update(dt, 280); // 重力
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 粒子画布
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return CustomPaint(
                  size: MediaQuery.of(context).size,
                  painter: _CelebrationPainter(
                    particles: _particles,
                    progress: _controller.value,
                  ),
                );
              },
            ),

            // 居中弹出微光荣誉勋章与文字
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.scale(
                  scale: _badgeScale.value,
                  child: Opacity(
                    opacity: _badgeOpacity.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.96),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2C7B6D).withOpacity(0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFF2C7B6D).withOpacity(0.15), width: 1.5),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2C7B6D), Color(0xFF48CAE4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2C7B6D).withOpacity(0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.check_rounded, color: Colors.white, size: 40),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
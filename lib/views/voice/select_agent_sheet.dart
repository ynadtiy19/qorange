import 'package:flutter/material.dart';

class SelectAgentBottomSheet extends StatefulWidget {
  // 🌟 支持传入当前选中的 Key；若未传，则自动使用内存中上一次选择的 Key
  final String? currentKey;
  final Function(String character, String key) onAgentSelected;

  const SelectAgentBottomSheet({
    super.key,
    required this.onAgentSelected,
    this.currentKey,
  });

  // 🌟 静态成员：在内存中持久化存储上一次选中的 Key，100% 实现跨弹窗周期的角色记忆功能
  static String lastSelectedKey = 'Maya-EN';

  @override
  State<SelectAgentBottomSheet> createState() => _SelectAgentBottomSheetState();
}

class _SelectAgentBottomSheetState extends State<SelectAgentBottomSheet> {
  late final PageController _pageController;
  int _currentPage = 0;

  // 🌟 核心改进：人物描述中文本地化，名字与后台传递的 Key 保持英文原样
  final List<Map<String, String>> _agents = [
    {
      'key': 'Maya-EN',
      'character': 'Maya',
      'displayName': 'Maya',
      'desc': '温暖且富有创造力；她是您的故事倾听者与灵感共鸣伙伴。',
    },
    {
      'key': 'Miles-EN',
      'character': 'Miles',
      'displayName': 'Miles',
      'desc': '随性而敏锐；像老朋友一样直言不讳地为您提供最真诚的建议。',
    },
    {
      'key': 'Simone-EN',
      'character': 'Simone',
      'displayName': 'Simone',
      'desc': '充满好奇心与求知欲；能将任何深度探讨转化为一场奇妙的思维冒险。',
    },
    {
      'key': 'Charlie-EN',
      'character': 'Charlie',
      'displayName': 'Charlie',
      'desc': '机智风趣又充满温情；随时准备与您一起深度探索感兴趣的冷门领域。',
    },
  ];

  @override
  void initState() {
    super.initState();
    // 🌟 核心改进：初始化时根据 widget.currentKey 或 lastSelectedKey 寻找到之前选中的索引
    final activeKey = widget.currentKey ?? SelectAgentBottomSheet.lastSelectedKey;
    final initialIndex = _agents.indexWhere((agent) => agent['key'] == activeKey);

    _currentPage = initialIndex != -1 ? initialIndex : 0;
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 曜石暗红轻奢拟物配色
    final Color buttonColor = const Color(0xFF4A1E24);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text(
            '选择您的 AI 助手',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 30),

          // 角色卡片滑块
          SizedBox(
            height: 140,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _agents.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                final agent = _agents[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        agent['displayName']!,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.black),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          agent['desc']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF8B7E74), height: 1.4),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          ),

          // 🌟 状态原点指示器 (Dot Indicator)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_agents.length, (index) {
              final isSelected = _currentPage == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isSelected ? 12 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isSelected ? buttonColor : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
          const SizedBox(height: 36),

          // 曜石暗红大圆角按钮
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                final selected = _agents[_currentPage];
                // 🌟 核心改进：确认选中时，在内存中持久化更新当前角色的 key
                SelectAgentBottomSheet.lastSelectedKey = selected['key']!;

                Navigator.pop(context);
                widget.onAgentSelected(selected['character']!, selected['key']!);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                '选择 ${_agents[_currentPage]['displayName']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
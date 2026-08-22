import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qorange/theme.dart';

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

  // 🌟 核心改进：人物描述改存多语言词条 key，展示时调用 .tr，切换语言即时生效；名字与后台传递的 Key 保持英文原样
  final List<Map<String, String>> _agents = [
    {
      'key': 'Maya-EN',
      'character': 'Maya',
      'displayName': 'Maya',
      'descKey': 'agent_desc_1',
    },
    {
      'key': 'Miles-EN',
      'character': 'Miles',
      'displayName': 'Miles',
      'descKey': 'agent_desc_2',
    },
    {
      'key': 'Simone-EN',
      'character': 'Simone',
      'displayName': 'Simone',
      'descKey': 'agent_desc_3',
    },
    {
      'key': 'Charlie-EN',
      'character': 'Charlie',
      'displayName': 'Charlie',
      'descKey': 'agent_desc_4',
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
      decoration: BoxDecoration(color: AppColors.surface,
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
            decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(
            'select_ai_assistant'.tr,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                          agent['descKey']!.tr,
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
                  color: isSelected ? buttonColor : AppColors.border,
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
                'select_agent_named'.trParams({'name': _agents[_currentPage]['displayName']!}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
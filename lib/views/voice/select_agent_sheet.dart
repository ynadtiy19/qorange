import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

class SelectAgentBottomSheet extends StatefulWidget {
  final Function(String character, String key) onAgentSelected;
  const SelectAgentBottomSheet({super.key, required this.onAgentSelected});

  @override
  State<SelectAgentBottomSheet> createState() => _SelectAgentBottomSheetState();
}

class _SelectAgentBottomSheetState extends State<SelectAgentBottomSheet> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _agents = [
    {
      'key': 'Maya-EN',
      'character': 'Maya',
      'displayName': 'Maya',
      'desc': 'Warm and creative; your storyteller and thought partner.',
    },
    {
      'key': 'Miles-EN',
      'character': 'Miles',
      'displayName': 'Miles',
      'desc': 'Laid-back and sharp; the wingman who tells you what you need to hear.',
    },
    {
      'key': 'Simone-EN',
      'character': 'Simone',
      'displayName': 'Simone',
      'desc': 'Curious and intellectual; turns any deep-dive into an adventure.',
    },
    {
      'key': 'Charlie-EN',
      'character': 'Charlie',
      'displayName': 'Charlie',
      'desc': 'Witty and warm; the friend who nerds out with you.',
    },
  ];

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
            'Select your agent',
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
                Navigator.pop(context);
                widget.onAgentSelected(selected['character']!, selected['key']!);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(
                'Select ${_agents[_currentPage]['displayName']}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
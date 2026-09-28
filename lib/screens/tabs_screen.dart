import 'package:flutter/material.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/screens/learn/home_tab.dart';
import 'package:loksewa_solution/screens/learn/exam_tab.dart';
import 'package:loksewa_solution/screens/learn/discussion_tab.dart';
import 'package:loksewa_solution/screens/learn/profile_tab.dart';

/// Main tab shell — mirrors app/(tabs): Home, Exam, Discussion, Profile.
class TabsScreen extends StatefulWidget {
  const TabsScreen({super.key});

  @override
  State<TabsScreen> createState() => _TabsScreenState();
}

class _TabsScreenState extends State<TabsScreen> {
  int _index = 0;

  static const _tabs = <Widget>[
    HomeTab(),
    ExamTab(),
    DiscussionTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.navy,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            activeIcon: Icon(Icons.assignment),
            label: 'Exam',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            activeIcon: Icon(Icons.forum),
            label: 'Discussion',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

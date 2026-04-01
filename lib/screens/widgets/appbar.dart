import 'package:flutter/material.dart';

import '../profile_screen.dart';

class AppBarPage extends StatelessWidget {
  final String  title;
  final String? avatarImagePath; // ixtiyoriy: "assets/images/profile.jpg"
  final String? userInitials;    // rasm bo'lmasa ko'rsatiladigan harf (masalan "AV")
  final VoidCallback? onLanguageTap;

  const AppBarPage({
    required this.title,
    this.avatarImagePath,
    this.userInitials,
    this.onLanguageTap,
    super.key,
  });

  // ── Navigate to AkkountPage ──────────────────────────────────────────────
  void _openProfile(BuildContext context) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => const AkkountPage(),
        transitionsBuilder: (_, animation, __, child) {
          // Smooth fade + slight upward slide
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end:   Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Colors.blue, Colors.purple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft:  Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color:      Colors.deepPurple.withOpacity(0.4),
            blurRadius: 10,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [

          // ── 🌐 Til ikonasi — o'ng tomon ──────────────────────────────────
          Positioned(
            right: 8,
            child: IconButton(
              tooltip: 'Tilni o\'zgartirish',
              icon: const Icon(Icons.language, color: Colors.white, size: 28),
              onPressed: onLanguageTap ?? () {},
            ),
          ),

          // ── 📝 Sarlavha — markazda ────────────────────────────────────────
          Center(
            child: Text(
              title,
              style: const TextStyle(
                color:       Colors.white,
                fontSize:    22,
                fontWeight:  FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),

          // ── 👤 Profil avatar — chap tomon ─────────────────────────────────
          Positioned(
            left: 8,
            child: Tooltip(
              message: 'Profilni ko\'rish',
              child: GestureDetector(
                onTap: () => _openProfile(context),
                child: // Hero widget: AkkountPage ichida ham xuddi shu heroTag
                // ishlatilsa avatar ochilganda smooth zoom animatsiyasi
                // bo'ladi (ixtiyoriy, lekin juda chiroyli ko'rinadi).
                Hero(
                  tag: 'profile_avatar',
                  child: Container(
                    margin:  const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      // Hover/press effekti uchun subtle glow
                      boxShadow: [
                        BoxShadow(
                          color:      Colors.white.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Colors.white,
                      backgroundImage: avatarImagePath != null
                          ? AssetImage(avatarImagePath!)
                          : null,
                      // Rasm bo'lmasa initials yoki default icon
                      child: avatarImagePath == null
                          ? (userInitials != null
                          ? Text(
                        userInitials!,
                        style: TextStyle(
                          color:      Colors.purple.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize:   16,
                        ),
                      )
                          : Icon(
                        Icons.person,
                        color: Colors.purple.shade300,
                        size: 26,
                      ))
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}
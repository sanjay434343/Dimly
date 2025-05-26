import 'dart:ui';
// Add this import for the pattern painter

import 'package:dimly/screens/home_page.dart' show FuturisticPatternPainter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart'; // Import for SVG support
import 'package:url_launcher/url_launcher.dart';  // Add this import at the top

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with TickerProviderStateMixin {  // Add TickerProviderStateMixin
  bool _isQuickTileAdded = false;
  bool _startWithFlashlightOn = false;
  bool _showBrightnessAsPercentage = true;
  bool _rememberLastBrightness = false;
  double _startupBrightness = 1.0;
  bool _backgroundServiceEnabled = true;
  bool _enableHapticFeedback = true;
  bool _autoOffAfterTime = false;
  int _autoOffMinutes = 5;
  
  static const platform = MethodChannel('com.example.dimly/quicksettings');
  static const backgroundServiceChannel = MethodChannel('com.example.dimly/background_service');

  late AnimationController _animationController;  // Add this controller

  @override
  void initState() {
    super.initState();
    _checkQuickTileStatus();
    _loadSettings();

    // Add animation controller initialization
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();  // Add this
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _startWithFlashlightOn = prefs.getBool('start_with_flashlight_on') ?? false;
      _showBrightnessAsPercentage = prefs.getBool('show_brightness_percentage') ?? true;
      _rememberLastBrightness = prefs.getBool('remember_last_brightness') ?? false;
      _startupBrightness = prefs.getDouble('startup_brightness') ?? 1.0;
      _enableHapticFeedback = prefs.getBool('enable_haptic_feedback') ?? true;
      _autoOffAfterTime = prefs.getBool('auto_off_after_time') ?? false;
      _autoOffMinutes = prefs.getInt('auto_off_minutes') ?? 5;
      _backgroundServiceEnabled = prefs.getBool('background_service_enabled') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool('start_with_flashlight_on', _startWithFlashlightOn),
      prefs.setBool('show_brightness_percentage', _showBrightnessAsPercentage),
      prefs.setBool('remember_last_brightness', _rememberLastBrightness),
      prefs.setDouble('startup_brightness', _startupBrightness),
      prefs.setBool('enable_haptic_feedback', _enableHapticFeedback),
      prefs.setBool('auto_off_after_time', _autoOffAfterTime),
      prefs.setInt('auto_off_minutes', _autoOffMinutes),
      prefs.setBool('background_service_enabled', _backgroundServiceEnabled),
    ]);

    // Apply background service state immediately
    if (_backgroundServiceEnabled) {
      await backgroundServiceChannel.invokeMethod('startBackgroundService');
    } else {
      await backgroundServiceChannel.invokeMethod('stopBackgroundService');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _checkQuickTileStatus() async {
    try {
      final bool? result = await platform.invokeMethod<bool>('isQuickTileAdded');
      setState(() {
        _isQuickTileAdded = result ?? true;
      });
    } catch (e) {
      setState(() {
        _isQuickTileAdded = true;
      });
    }
  }

  Future<void> _addQuickSettingsTile() async {
    try {
      HapticFeedback.mediumImpact();
      
      setState(() => _isQuickTileAdded = true);
      
      await platform.invokeMethod('addQuickSettingsTile');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quick Settings tiles are now available! Swipe down twice from the top and look for Dimly, SOS, and Ambient tiles.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quick settings tiles are now available: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _toggleBackgroundService(bool enable) async {
    try {
      if (enable) {
        await backgroundServiceChannel.invokeMethod('startBackgroundService');
      } else {
        await backgroundServiceChannel.invokeMethod('stopBackgroundService');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Background service control: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withOpacity(0.08),
              colorScheme.surface,
              colorScheme.secondary.withOpacity(0.08),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Add the animated background pattern
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: FuturisticPatternPainter(
                      color1: colorScheme.primary.withOpacity(0.08),
                      color2: colorScheme.secondary.withOpacity(0.06),
                      accentColor: colorScheme.tertiary.withOpacity(0.04),
                      progress: _animationController.value,
                      isLightMode: Theme.of(context).brightness == Brightness.light,
                    ),
                  );
                },
              ),
            ),

            // Existing content
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: colorScheme.primary),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(
                  'Settings',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  children: [
                    // Replace the developer info card with this:
                    _buildSettingsCard(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Profile image
                          Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.shadow.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assest/logo/mine.png',
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.person_outline_rounded,
                                      size: 70,
                                      color: colorScheme.primary,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Name and title with better spacing
                          Column(
                            children: [
                              Text(
                                'Sanjay',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Flutter Developer',
                                style: TextStyle(
                                  color: colorScheme.primary.withOpacity(0.8),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Crafting elegant solutions with\nFlutter and Kotlin',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Contact buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () async {
                                  final Uri emailLaunchUri = Uri(
                                    scheme: 'mailto',
                                    path: 'sanjay13649@gmail.com',
                                    queryParameters: {
                                      'subject': 'Hello from Dimly App User'
                                    }
                                  );
                                  if (!await launchUrl(emailLaunchUri)) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Could not launch email client')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.email_rounded),
                                label: const Text('Contact'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  minimumSize: const Size(130, 44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              FilledButton.icon(
                                onPressed: () async {
                                  final Uri url = Uri.parse('https://github.com/sanjay434343');
                                  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Could not launch GitHub')),
                                      );
                                    }
                                  }
                                },
                                icon: const Icon(Icons.code_rounded),
                                label: const Text('GitHub'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: colorScheme.primary,
                                  foregroundColor: colorScheme.onPrimary,
                                  minimumSize: const Size(130, 44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32), // Add this gap

                    _buildSectionHeader('Quick Settings Tiles', Icons.grid_view_rounded),
                    _buildQuickSettingsTileCard(),
                    
                    const SizedBox(height: 24),
                    
                    _buildSectionHeader('Startup Options', Icons.power_settings_new_rounded),
                    _buildSettingsCard(
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            title: 'Start with Flashlight On',
                            subtitle: 'Turn on flashlight when app launches',
                            value: _startWithFlashlightOn,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _startWithFlashlightOn = value);
                              _saveSettings();
                            },
                          ),
                          if (_startWithFlashlightOn) ...[
                            _buildDivider(),
                            _buildSwitchTile(
                              title: 'Remember Last Brightness',
                              subtitle: 'Use the last brightness level when starting',
                              value: _rememberLastBrightness,
                              onChanged: (value) {
                                HapticFeedback.lightImpact();
                                setState(() => _rememberLastBrightness = value);
                                _saveSettings();
                              },
                            ),
                            if (!_rememberLastBrightness) ...[
                              _buildDivider(),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Startup Brightness',
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Default brightness level when app starts',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.brightness_low,
                                          color: colorScheme.primary.withOpacity(0.7),
                                        ),
                                        Expanded(
                                          child: SliderTheme(
                                            data: SliderThemeData(
                                              activeTrackColor: colorScheme.primary,
                                              inactiveTrackColor: colorScheme.surfaceContainerHighest,
                                              thumbColor: colorScheme.primary,
                                              trackHeight: 4.0,
                                            ),
                                            child: Slider(
                                              value: _startupBrightness,
                                              min: 0.1,
                                              max: 1.0,
                                              divisions: 9,
                                              onChanged: (value) {
                                                HapticFeedback.selectionClick();
                                                setState(() => _startupBrightness = value);
                                                _saveSettings();
                                              },
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.brightness_high,
                                          color: colorScheme.primary,
                                        ),
                                      ],
                                    ),
                                    Center(
                                      child: Text(
                                        '${(_startupBrightness * 100).round()}%',
                                        style: TextStyle(
                                          color: colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSectionHeader('Display & Feedback', Icons.display_settings_rounded),
                    _buildSettingsCard(
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            title: 'Show Brightness as Percentage',
                            subtitle: 'Display brightness level as a percentage',
                            value: _showBrightnessAsPercentage,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _showBrightnessAsPercentage = value);
                              _saveSettings();
                            },
                          ),
                          _buildDivider(),
                          _buildSwitchTile(
                            title: 'Haptic Feedback',
                            subtitle: 'Feel vibrations when interacting with controls',
                            value: _enableHapticFeedback,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _enableHapticFeedback = value);
                              _saveSettings();
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSectionHeader('Auto Features', Icons.schedule_rounded),
                    _buildSettingsCard(
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            title: 'Auto Turn Off',
                            subtitle: 'Automatically turn off flashlight after specified time',
                            value: _autoOffAfterTime,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _autoOffAfterTime = value);
                              _saveSettings();
                            },
                          ),
                          if (_autoOffAfterTime) ...[
                            _buildDivider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Auto Turn Off Timer',
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Minutes before automatically turning off',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.timer,
                                        color: colorScheme.primary.withOpacity(0.7),
                                      ),
                                      Expanded(
                                        child: SliderTheme(
                                          data: SliderThemeData(
                                            activeTrackColor: colorScheme.primary,
                                            inactiveTrackColor: colorScheme.surfaceContainerHighest,
                                            thumbColor: colorScheme.primary,
                                            trackHeight: 4.0,
                                          ),
                                          child: Slider(
                                            value: _autoOffMinutes.toDouble(),
                                            min: 1,
                                            max: 30,
                                            divisions: 29,
                                            onChanged: (value) {
                                              HapticFeedback.selectionClick();
                                              setState(() => _autoOffMinutes = value.round());
                                              _saveSettings();
                                            },
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.timer_off,
                                        color: colorScheme.primary,
                                      ),
                                    ],
                                  ),
                                  Center(
                                    child: Text(
                                      '$_autoOffMinutes minutes',
                                      style: TextStyle(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSectionHeader('Background Service', Icons.settings_backup_restore_rounded),
                    _buildSettingsCard(
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            title: 'Background Quick Settings',
                            subtitle: 'Keep service running for faster Quick Settings response',
                            value: _backgroundServiceEnabled,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _backgroundServiceEnabled = value);
                              _toggleBackgroundService(value);
                            },
                          ),
                          _buildDivider(),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Background service provides faster Quick Settings tile response. A persistent notification will be shown when active.',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    _buildSectionHeader('About', Icons.info_outline_rounded),
                    _buildSettingsCard(
                      child: Column(
                        children: [
                          _buildListTile(
                            leading: Icon(Icons.code, color: colorScheme.primary),
                            title: 'Version',
                            trailing: const Text('1.0.0'),
                          ),
                          _buildDivider(),
                          _buildListTile(
                            leading: Icon(Icons.info_outline, color: colorScheme.primary),
                            title: 'About Dimly',
                            onTap: () => _showAboutDialog(context),
                          ),
                          _buildDivider(),
                          _buildListTile(
                            leading: Icon(Icons.rate_review_outlined, color: colorScheme.primary),
                            title: 'Rate App',
                            onTap: () {
                              // Open app store rating
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildQuickSettingsTileCard() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.03),
            blurRadius: 20,
            spreadRadius: -5,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withOpacity(0.05),
                  colorScheme.surface.withOpacity(0.9),
                  colorScheme.secondary.withOpacity(0.05),
                ],
              ),
            ),
            child: Column(
              children: [
                // Handle indicator with gradient
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary.withOpacity(0.3),
                        colorScheme.secondary.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Quick Settings content
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.1),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.dashboard_customize,
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Settings Tiles',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add Dimly tiles to your device\'s quick settings panel: Main flashlight, SOS emergency signal, and Ambient light control.',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _addQuickSettingsTile,
                  icon: const Icon(Icons.add_to_home_screen),
                  label: const Text('Add Quick Tiles'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.secondary.withOpacity(0.05),
                        blurRadius: 10,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: colorScheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Tip: After tapping the button above, swipe down twice from the top of your screen and look for Dimly, SOS, and Ambient tiles to add them!',
                          style: TextStyle(
                            color: colorScheme.onSecondaryContainer,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),)
      );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 10,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.03),
            blurRadius: 20,
            spreadRadius: -5,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary.withOpacity(0.05),
                  colorScheme.surface.withOpacity(0.9),
                  colorScheme.secondary.withOpacity(0.05),
                ],
              ),
            ),
            child: Column(
              children: [
                // Handle indicator with gradient
                Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary.withOpacity(0.3),
                        colorScheme.secondary.withOpacity(0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      )
      );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return SwitchListTile.adaptive(
      title: Text(
        title,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: colorScheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildListTile({
    required Widget leading,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return ListTile(
      leading: leading,
      title: Text(
        title,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ?? Icon(
        Icons.chevron_right,
        color: colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider() {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Divider(
      color: colorScheme.outlineVariant.withOpacity(0.3),
      height: 1,
      indent: 16,
      endIndent: 16,
    );
  }

  // Add this new method to show the About dialog
  void _showAboutDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Dimly'), // Simplified title row
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SvgPicture.asset(
                  'assest/logo/logo.svg',
                  width: 80,
                  height: 80,
                  colorFilter: ColorFilter.mode(
                    colorScheme.primary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Advanced Flashlight Control',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Dimly is a modern flashlight app that brings precise control and advanced features to your device\'s flashlight.',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Key Features:',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...{
                'Brightness Control': 'Precise control over flashlight intensity',
                'Morse Code': 'Convert and transmit text using light signals',
                'SOS Signal': 'Emergency SOS light pattern',
                'Interval Mode': 'Customizable flashing intervals',
                'Ambient Mode': 'Automatic brightness based on surroundings',
              }.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            entry.value,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
              const SizedBox(height: 16),
              Text(
                '© 2024 Dimly',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Add this helper method in the class
  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ColorScheme colorScheme,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        minimumSize: const Size(130, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 0,
      ),
      icon: Icon(icon, size: 20),
      label: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// No need to add FuturisticPatternPainter class as it's already defined in home_page.dart

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:dimly/services/morse_service.dart';
import 'package:dimly/screens/settings_page.dart'; // Import the settings page
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/torch_service.dart';
import 'package:dimly/services/light_sensor_service.dart'; // Import the new service using package path
// Import permission_handler
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final _torchService = TorchService();
  final _audioPlayer = AudioPlayer();
  late LightSensorService _lightSensorService; // Add LightSensorService instance
  bool _isFlashlightOn = false;
  double _brightness = 0.0; // Change from 1.0 to 0.0
  final bool _isAdjusting = false;
  Duration _defaultInterval = const Duration(seconds: 1);
  final Duration _minInterval = const Duration(seconds: 1);
  final Duration _maxInterval = const Duration(seconds: 10);
  bool _isSosActive = false;
  bool _isIntervalActive = false;
  bool _isMorseActive = false;
  String _currentMorsePattern = '';
  String _currentLetter = '';
  String _morseText = ''; // Store the text being transmitted
  bool _isCenterFlashOn = false;
  late AnimationController _animationController;
  late AnimationController _spinController;
  late AnimationController _pulseController; // New controller for pulsing animation
  late Animation<double> _pulseAnimation;    // New animation for pulsing
  bool _isAmbientMode = false;
  final bool _isVibroModeActive = false; // Restore the state variable but don't use it functionally

  // Add a property to control the size of the center light
  final double _centerLightSizeMultiplier = 0.8; // Increased from 0.75

  // Ambient mode animation - remove 'late' keyword to initialize immediately
  AnimationController? _ambientBrightnessController;
  Animation<double>? _ambientBrightnessAnimation;
  double _targetAmbientBrightness = 1.0;

  // Constants for ambient mode brightness adjustment - updated for more precise control
  static const double _MIN_LUX_FOR_MAX_FLASHLIGHT = 10.0; // Very dark - maximum brightness
  static const double _MID_LOW_LUX_THRESHOLD = 50.0; // Low light threshold for 25% brightness
  static const double _MID_HIGH_LUX_THRESHOLD = 75.0; // Medium light threshold for 50% brightness
  static const double _MAX_LUX_FOR_OFF_FLASHLIGHT = 200.0; // Bright light - turn off
  static const double _MIN_AMBIENT_BRIGHTNESS_VALUE = 0.0; // Min brightness in ambient mode (can be 0 to turn off)
  static const double _MAX_AMBIENT_BRIGHTNESS_VALUE = 1.0; // Max brightness in ambient mode
  static const double _BRIGHTNESS_CHANGE_THRESHOLD = 0.02; // Reduced from 0.05 for more precision

  // New settings variables
  bool _enableHapticFeedback = true;
  bool _autoOffAfterTime = false;
  int _autoOffMinutes = 5;
  Timer? _autoOffTimer;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200), // Duration for one pulse cycle
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initialize the ambient brightness controller immediately
    _ambientBrightnessController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _ambientBrightnessAnimation = Tween<double>(begin: _brightness, end: _targetAmbientBrightness).animate(
      CurvedAnimation(parent: _ambientBrightnessController!, curve: Curves.easeInOut),
    )..addListener(() {
      if (_isAmbientMode) { // Only adjust if ambient mode is still active
        _isAdjustingFromAmbient = true;
        _adjustBrightness(_ambientBrightnessAnimation!.value);
        _isAdjustingFromAmbient = false;
      }
    });

    _lightSensorService = LightSensorService();
    _lightSensorService.onLightData = _handleAmbientLightUpdate;
    _lightSensorService.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Light sensor error: ${error.toString()}')),
        );
        if (_isAmbientMode) {
          setState(() {
            _isAmbientMode = false; // Turn off ambient mode if sensor fails
          });
        }
      }
    };

    // Set status bar style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    // Only listen for current letter and its morse pattern
    _torchService.onCurrentLetterUpdate = (letter) {
      setState(() => _currentLetter = letter);
    };
    _torchService.onMorsePatternUpdate = (pattern) {
      // Only set the pattern for the current letter, not the full text
      setState(() => _currentMorsePattern = pattern);
    };
    _torchService.onTorchStateChange = (isOn) {
      setState(() => _isCenterFlashOn = isOn);
    };

    // Add method channel to handle ambient mode activation from Quick Settings
    const ambientChannel = MethodChannel('com.example.dimly/ambient');
    ambientChannel.setMethodCallHandler((call) async {
      if (call.method == 'activateAmbientMode') {
        // Activate ambient mode when called from Quick Settings
        if (!_isAmbientMode) {
          _toggleAmbientMode();
        }
      }
    });
    
    // Add method channel to handle SOS activation from Quick Settings
    const sosChannel = MethodChannel('com.example.dimly/sos');
    sosChannel.setMethodCallHandler((call) async {
      if (call.method == 'activateSOSMode') {
        // Activate SOS mode when called from Quick Settings
        if (!_isSosActive) {
          _toggleSOS();
        }
      }
    });
    
    // Apply startup settings
    _applyStartupSettings();
    _loadAppSettings();
  }

  Future<void> _loadAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _enableHapticFeedback = prefs.getBool('enable_haptic_feedback') ?? true;
      _autoOffAfterTime = prefs.getBool('auto_off_after_time') ?? false;
      _autoOffMinutes = prefs.getInt('auto_off_minutes') ?? 5;
    });
  }

  void _startAutoOffTimer() {
    _autoOffTimer?.cancel();
    if (_autoOffAfterTime && _isFlashlightOn) {
      _autoOffTimer = Timer(Duration(minutes: _autoOffMinutes), () {
        if (_isFlashlightOn) {
          _adjustBrightness(0.0);
          if (_enableHapticFeedback) {
            HapticFeedback.mediumImpact();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Flashlight auto-turned off'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _autoOffTimer?.cancel();
    _animationController.dispose();
    _spinController.dispose();
    _pulseController.dispose();
    _ambientBrightnessController?.dispose(); // Use safe call operator
    _lightSensorService.dispose();
    _audioPlayer.dispose(); // Add this line
    super.dispose();
  }

  Future<void> _toggleFlashlight() async {
    try {
      await _torchService.toggleTorch();
      // Update path to match the directory structure (include assest/ prefix)
      await _audioPlayer.play(AssetSource(_torchService.isOn ? '../assest/audio/on.mp3' : '../assest/audio/off.mp3'));
      
      setState(() {
        _isFlashlightOn = _torchService.isOn;
        if (_isFlashlightOn) {
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
          _startAutoOffTimer(); // Start auto-off timer when flashlight turns on
        } else {
          _autoOffTimer?.cancel(); // Cancel timer when flashlight turns off
          _pulseController.stop();
          _pulseController.value = 0.0;
        }
      });
      
      if (_enableHapticFeedback) {
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<void> _applyStartupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check if we should start with flashlight on
    final startWithFlashlightOn = prefs.getBool('start_with_flashlight_on') ?? false;
    final rememberLastBrightness = prefs.getBool('remember_last_brightness') ?? false;
    
    if (startWithFlashlightOn) {
      double targetBrightness;
      
      if (rememberLastBrightness) {
        // Use last saved brightness
        targetBrightness = prefs.getDouble('last_brightness') ?? 1.0;
      } else {
        // Use startup brightness setting
        targetBrightness = prefs.getDouble('startup_brightness') ?? 1.0;
      }
      
      // Apply the brightness setting
      await Future.delayed(const Duration(milliseconds: 500)); // Wait for UI to initialize
      if (mounted) {
        await _adjustBrightness(targetBrightness);
      }
    }
  }

  Future<void> _adjustBrightness(double value) async {
    // If user manually adjusts brightness, turn off ambient mode
    if (_isAmbientMode && !_isAdjustingFromAmbient) { // Add a flag to differentiate calls
      setState(() {
        _isAmbientMode = false;
        _lightSensorService.stopListening();
        _ambientBrightnessController?.stop(); // Use safe call operator
      });
    }
    try {
      final newBrightness = value.clamp(0.0, 1.0);
      await _torchService.toggleTorch(intensity: newBrightness);
      setState(() {
        _brightness = newBrightness;
        _isFlashlightOn = newBrightness > 0;
        if (_isFlashlightOn) {
          if (!_pulseController.isAnimating) {
            _pulseController.repeat(reverse: true);
          }
          _startAutoOffTimer(); // Start auto-off timer when brightness is adjusted
        } else {
          _autoOffTimer?.cancel(); // Cancel timer when flashlight turns off
          _pulseController.stop();
          _pulseController.value = 0.0;
        }
      });
      
      // Save current brightness for "remember last brightness" feature
      _saveCurrentBrightness(newBrightness);
      
      if (_enableHapticFeedback) {
        HapticFeedback.lightImpact();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adjusting brightness: ${e.toString()}')),
      );
    }
  }

  // Flag to indicate if _adjustBrightness is called from ambient mode logic
  bool _isAdjustingFromAmbient = false;

  void _handleAmbientLightUpdate(int luxValue) {
    if (!_isAmbientMode) return;
    if (_ambientBrightnessController == null) return; // Safety check

    double newBrightnessTarget;

    // More precise brightness mapping based on lux ranges
    if (luxValue <= _MIN_LUX_FOR_MAX_FLASHLIGHT) {
      // Very dark (0-10 lux): 100% brightness
      newBrightnessTarget = _MAX_AMBIENT_BRIGHTNESS_VALUE;
    } else if (luxValue <= _MID_LOW_LUX_THRESHOLD) {
      // Dark to low light (10-50 lux): Gradually decrease from 100% to 25%
      double factor = (luxValue - _MIN_LUX_FOR_MAX_FLASHLIGHT) /
          (_MID_LOW_LUX_THRESHOLD - _MIN_LUX_FOR_MAX_FLASHLIGHT);
      newBrightnessTarget = _MAX_AMBIENT_BRIGHTNESS_VALUE - (factor * 0.75); // 100% to 25%
    } else if (luxValue <= _MID_HIGH_LUX_THRESHOLD) {
      // Low to medium light (50-75 lux): Stay around 25% brightness
      newBrightnessTarget = 0.25; // 25% brightness
    } else if (luxValue <= _MAX_LUX_FOR_OFF_FLASHLIGHT) {
      // Medium to bright light (75-200 lux): Gradually decrease from 25% to 0%
      double factor = (luxValue - _MID_HIGH_LUX_THRESHOLD) /
          (_MAX_LUX_FOR_OFF_FLASHLIGHT - _MID_HIGH_LUX_THRESHOLD);
      newBrightnessTarget = 0.25 - (factor * 0.25); // 25% to 0%
    } else {
      // Very bright light (200+ lux): Turn off completely
      newBrightnessTarget = _MIN_AMBIENT_BRIGHTNESS_VALUE;
    }

    newBrightnessTarget = newBrightnessTarget.clamp(_MIN_AMBIENT_BRIGHTNESS_VALUE, _MAX_AMBIENT_BRIGHTNESS_VALUE);

    // Debug logging to see the brightness adjustments
    print('Ambient mode: $luxValue lux → ${(newBrightnessTarget * 100).round()}% brightness');

    // More sensitive brightness change detection
    final brightnessDifference = (newBrightnessTarget - _brightness).abs();
    final isCurrentlyOff = !_isFlashlightOn && _brightness < 0.01;
    final isTargetOff = newBrightnessTarget < 0.01;

    if ((isTargetOff && _isFlashlightOn) || // Turning off
        (!isTargetOff && isCurrentlyOff) || // Turning on
        (!isTargetOff && !isCurrentlyOff && brightnessDifference > _BRIGHTNESS_CHANGE_THRESHOLD)) { // More sensitive change detection
      
      if (_targetAmbientBrightness != newBrightnessTarget || !_ambientBrightnessController!.isAnimating) {
        _targetAmbientBrightness = newBrightnessTarget;
        
        // Add haptic feedback for ambient brightness changes
        if (_enableHapticFeedback) {
          if (brightnessDifference > 0.15) {
            HapticFeedback.mediumImpact(); // Stronger haptic for significant changes
          } else if (brightnessDifference > _BRIGHTNESS_CHANGE_THRESHOLD) {
            HapticFeedback.lightImpact(); // Light haptic for smaller changes
          }
        }
        
        _ambientBrightnessAnimation = Tween<double>(begin: _brightness, end: _targetAmbientBrightness).animate(
          CurvedAnimation(parent: _ambientBrightnessController!, curve: Curves.easeInOut),
        );
        
        // Faster animation for more responsive feel
        _ambientBrightnessController!.duration = Duration(milliseconds: brightnessDifference > 0.3 ? 800 : 500);
        _ambientBrightnessController!.forward(from: 0.0);
      }
    }
  }

  Future<void> _showIntervalDialog() async {
    Duration selectedInterval = _defaultInterval;

    // If user opens interval dialog, turn off ambient mode
    if (_isAmbientMode) {
      setState(() {
        _isAmbientMode = false;
        _lightSensorService.stopListening();
        _ambientBrightnessController?.stop(); // Safe call
      });
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isIntervalActive ? 'Stop Interval' : 'Interval Flash'),
        content: _isIntervalActive
            ? const Text('Stop the interval flashing?')
            : StatefulBuilder(
                builder: (context, setBuilderState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Interval: ${selectedInterval.inSeconds}s',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Slider(
                      value: selectedInterval.inMilliseconds.toDouble(),
                      min: _minInterval.inMilliseconds.toDouble(),
                      max: _maxInterval.inMilliseconds.toDouble(),
                      divisions: 9,
                      label: '${selectedInterval.inSeconds}s',
                      onChanged: (value) {
                        if (_enableHapticFeedback) {
                          HapticFeedback.selectionClick();
                        }
                        setBuilderState(() {
                          selectedInterval = Duration(milliseconds: value.round());
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${_minInterval.inSeconds}s'),
                        Text('${_maxInterval.inSeconds}s'),
                      ],
                    ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () {
              if (_enableHapticFeedback) {
                HapticFeedback.lightImpact();
              }
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (_enableHapticFeedback) {
                HapticFeedback.mediumImpact();
              }
              if (_isIntervalActive) {
                _torchService.stopInterval();
                setState(() => _isIntervalActive = false);
              } else {
                // Ensure ambient mode is off if starting interval
                if (_isAmbientMode) {
                  _isAmbientMode = false;
                  _lightSensorService.stopListening();
                  _ambientBrightnessController?.stop();
                }
                _defaultInterval = selectedInterval;
                _torchService.toggleInterval(_defaultInterval);
                setState(() => _isIntervalActive = true);
              }
              Navigator.pop(context);
            },
            icon: Icon(_isIntervalActive ? Icons.stop : Icons.play_arrow),
            label: Text(_isIntervalActive ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSOS() async {
    if (_isAmbientMode) {
      setState(() {
        _isAmbientMode = false;
        _lightSensorService.stopListening();
        _ambientBrightnessController?.stop(); // Safe call
      });
    }
    if (!_isSosActive) {
      setState(() => _isSosActive = true);
      await _torchService.flashSOS();
    } else {
      _torchService.stopMorse();
      setState(() => _isSosActive = false);
    }
    
    if (_enableHapticFeedback) {
      HapticFeedback.mediumImpact();
    }
  }

  void _toggleAmbientMode() {
    if (_enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
    
    setState(() {
      _isAmbientMode = !_isAmbientMode;
      if (_isAmbientMode) {
        _deactivateOtherModes();
        
        // Ensure controller is initialized 
        if (_ambientBrightnessController == null) {
          _ambientBrightnessController = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 800), // Faster default duration
          );
          
          _ambientBrightnessAnimation = Tween<double>(begin: _brightness, end: _targetAmbientBrightness).animate(
            CurvedAnimation(parent: _ambientBrightnessController!, curve: Curves.easeInOut),
          )..addListener(() {
            if (_isAmbientMode) {
              _isAdjustingFromAmbient = true;
              _adjustBrightness(_ambientBrightnessAnimation!.value);
              _isAdjustingFromAmbient = false;
            }
          });
        }
        
        // Start the light sensor - let it provide real readings
        _lightSensorService.startListening();
        
        // Immediately set flashlight to 100% when ambient mode starts
        _isAdjustingFromAmbient = true;
        _adjustBrightness(1.0); // Turn on at full brightness immediately
        _isAdjustingFromAmbient = false;
        
        // Set initial target to maximum brightness
        _targetAmbientBrightness = 1.0;
        
        // Provide initial haptic feedback when ambient mode starts
        if (_enableHapticFeedback) {
          HapticFeedback.mediumImpact();
        }
      } else {
        _lightSensorService.stopListening();
        _ambientBrightnessController?.stop();
        
        // Provide haptic feedback when ambient mode stops
        if (_enableHapticFeedback) {
          HapticFeedback.lightImpact();
        }
      }
    });
  }

  Future<void> _saveCurrentBrightness(double brightness) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('last_brightness', brightness);
  }

  void _deactivateOtherModes() {
    if (_isSosActive) {
      _torchService.stopMorse(); // SOS uses morse
      setState(() => _isSosActive = false);
    }
    if (_isIntervalActive) {
      _torchService.stopInterval();
      setState(() => _isIntervalActive = false);
    }
    if (_isMorseActive) {
      _torchService.stopMorse();
      setState(() {
        _isMorseActive = false;
        _currentLetter = '';
        _currentMorsePattern = '';
        _morseText = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.of(context).size;
    
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
            // Modern animated background pattern
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
            
            // Add floating app bar
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 20,
              right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: colorScheme.primary.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_isFlashlightOn || _isSosActive || _isIntervalActive || _isMorseActive || _isAmbientMode)
                          _buildStatusChip()
                        else
                          Text(
                            'DIMLY',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        const Spacer(),
                        // Brightness percentage
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.brightness_7,
                                size: 18,
                                color: colorScheme.primary.withOpacity(0.8),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(_brightness * 100).round()}%',
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Settings button
                        GestureDetector(
                          onTap: () async {
                            if (_enableHapticFeedback) {
                              HapticFeedback.lightImpact();
                            }
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SettingsPage()),
                            );
                            _loadAppSettings();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.settings_rounded,
                              size: 20,
                              color: colorScheme.primary.withOpacity(0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 80), // Add padding for floating bar
                child: Column(
                  children: [
                    // Removed existing header row
                    const SizedBox(height: 24),

                    // Main flashlight control
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(
                          child: Hero(
                            tag: 'flashlight_control',
                            child: Material(
                              color: Colors.transparent,
                              child: _buildFlashlightControl(screenSize),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Feature controls panel - Enhanced floating design
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(28, 16, 28, 16), // Changed from 8 to 38
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
                            offset: const Offset(0, -8),
                            spreadRadius: 0,
                          ),
                          BoxShadow(
                            color: colorScheme.primary.withOpacity(0.05),
                            blurRadius: 20,
                            spreadRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                          // Inner glow effect
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
                                // Control buttons with enhanced spacing and animations
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: List.generate(4, (index) => _buildControlButton(index, context)),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                _buildBrightnessSlider(colorScheme),
                                const SizedBox(height: 8),
                              ],
                            ),
                          ),
                        ),
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

  Widget _buildStatusChip() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('on_status'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.9),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPulsingDot(),
          const SizedBox(width: 8),
          Text(
            'ACTIVE',
            style: TextStyle(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ],
      )
    );
  }

  Widget _buildPulsingDot() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.2),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          height: 10,
          width: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.8),
                blurRadius: 6 * value,
                spreadRadius: value,
              ),
            ],
          ),
        );
      },
      child: Container(),
    );
  }

  Widget _buildFlashlightControl(Size screenSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = screenSize.width * 0.78; // Increased from 0.7
    
    return GestureDetector(
      onTap: _toggleFlashlight,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Light beam effect
            if (_isFlashlightOn)
              ...List.generate(3, (i) {
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.5, end: 1.0),
                  duration: Duration(seconds: 1 + i),
                  curve: Curves.easeInOut,
                  builder: (context, value, _) {
                    return Opacity(
                      opacity: (1.0 - value) * 0.5 * _brightness, // Scale opacity with brightness
                      child: Container(
                        width: size * value * 1.5,
                        height: size * value * 1.5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              colorScheme.primary.withOpacity(0.7 * _brightness), // Scale opacity with brightness
                              colorScheme.primary.withOpacity(0.0),
                            ],
                          ),
                        ),
                      )
                    );
                    },
                  
                );
              }),
            
            // Add a subtle glow behind the main control - intensity based on brightness
            if (_isFlashlightOn)
              Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.5 * _brightness), // Glow intensity based on brightness
                      blurRadius: 30 * _brightness, // Blur radius based on brightness
                      spreadRadius: 10 * _brightness, // Spread radius based on brightness
                    ),
                  ],
                ),
              ),
              
            // SVG Logo with rotation and pulsing
            ScaleTransition(
              scale: _pulseAnimation,
              child: RotationTransition(
                turns: Tween(begin: 0.0, end: 0.25).animate(
                  CurvedAnimation(
                    parent: _spinController,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: size * _centerLightSizeMultiplier,
                  height: size * _centerLightSizeMultiplier,
                  // Add glow effect to the SVG container based on brightness
                  decoration: _isFlashlightOn ? BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.6 * _brightness),
                        blurRadius: 20 * _brightness,
                        spreadRadius: 5 * _brightness,
                      ),
                    ],
                  ) : null,
                  child: SvgPicture.asset(
                    'assest/logo/logo.svg',
                    colorFilter: ColorFilter.mode(
                      _isFlashlightOn 
                        ? (Theme.of(context).brightness == Brightness.dark ? colorScheme.primary : colorScheme.onPrimary) 
                        : colorScheme.outline, 
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(int index, BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 160;
    final buttonWidth = (availableWidth / 4.5).floor().toDouble();
    final buttonGap = 12.0;

    final configs = [
      (_isMorseActive, Icons.message_rounded, 'Morse', () =>
        _isMorseActive ? _torchService.stopMorse() : _showMorseDialog()),
      (_isSosActive, Icons.sos_rounded, 'SOS', _toggleSOS),
      (_isIntervalActive, Icons.timer_rounded, 'Interval', _showIntervalDialog),
      (_isAmbientMode, Icons.insights_rounded, 'Ambient', _toggleAmbientMode),
    ];

    final (isActive, icon, label, onPressed) = configs[index];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: buttonGap / 2),
      child: Container(
        width: buttonWidth,
        height: 65,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: colorScheme.surfaceContainerLowest.withOpacity(0.3),
          border: Border.all(
            color: isActive 
              ? colorScheme.primary.withOpacity(0.5)  // Brighter border when active
              : colorScheme.outlineVariant.withOpacity(0.2),
            width: isActive ? 2.0 : 1.5,  // Thicker border when active
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.2),
                blurRadius: 8,
                spreadRadius: 2,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (_enableHapticFeedback) {
                HapticFeedback.lightImpact();
              }
              onPressed();
            },
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: isActive ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withOpacity(0.95),
                    colorScheme.primary.withOpacity(0.85),
                  ],
                ) : null,
                boxShadow: [
                  if (isActive)
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      color: isActive 
                        ? colorScheme.onPrimary 
                        : colorScheme.onSurface.withOpacity(0.8),
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        color: isActive 
                          ? colorScheme.onPrimary 
                          : colorScheme.onSurface.withOpacity(0.8),
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            
          ),
        ),
      ),
      )
    );
  }

  Future<void> _showMorseDialog() async {
    final controller = TextEditingController();
    String previewPattern = '';

    // If user opens Morse dialog, turn off ambient and vibro mode
    if (_isAmbientMode) {
      setState(() {
        _isAmbientMode = false;
        _lightSensorService.stopListening();
        _ambientBrightnessController?.stop(); // Safe call
      });
    }
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Morse Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Enter text to transmit',
                  hintText: 'e.g., HELLO',
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (text) {
                  if (text.isEmpty) {
                    setDialogState(() => previewPattern = '');
                  } else {
                    final morse = MorseService.toMorse(text);
                    setDialogState(() => previewPattern = morse);
                  }
                },
              ),
              if (previewPattern.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Preview:',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        previewPattern,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (_enableHapticFeedback) {
                  HapticFeedback.lightImpact();
                }
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.text.isNotEmpty ? () {
                if (_enableHapticFeedback) {
                  HapticFeedback.mediumImpact();
                }
                Navigator.pop(context);
                // Ensure ambient and vibro mode are off if starting Morse
                if (_isAmbientMode) {
                  setState(() {
                     _isAmbientMode = false;
                     _lightSensorService.stopListening();
                     _ambientBrightnessController?.stop(); // Safe call
                  });
                }
                _playMorseCode(controller.text);
              } : null,
              child: const Text('Start'),
            ),
          ],
        ),
      )
      );
  }

  Future<void> _playMorseCode(String text) async {
    // Ensure ambient and vibro mode are off
    if (_isAmbientMode) {
      setState(() {
        _isAmbientMode = false;
        _lightSensorService.stopListening();
        _ambientBrightnessController?.stop(); // Safe call
      });
    }
    setState(() {
      _isMorseActive = true;
      _morseText = text.toUpperCase();
      _currentMorsePattern = '';
      _currentLetter = '';
    });
    await _torchService.playMorseCode(text);
    setState(() {
      _isMorseActive = false;
      _currentMorsePattern = '';
      _currentLetter = '';
      _morseText = '';
    });
  }

  Widget _buildBrightnessSlider(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.primary.withOpacity(0.15),
          width: 2,
        ),
        borderRadius: BorderRadius.circular(24),
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.05),
            blurRadius: 15,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(4),
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 4), // Add horizontal padding
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: colorScheme.surfaceContainerLowest.withOpacity(0.7),
        ),
        clipBehavior: Clip.none,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth - 8; // Reduce from 30 to 8
            final handlePosition = (trackWidth * _brightness).clamp(0.0, trackWidth);
            
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Background track - full width with subtle appearance
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                
                // Add brightness fill effect
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: handlePosition + 15,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          colorScheme.primary.withOpacity(0.3),
                          colorScheme.primary.withOpacity(0.15),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Percentage markers
                ...List.generate(5, (index) {
                  final position = (trackWidth * (index / 4));
                  return Positioned(
                    left: position + 4, // Reduce from 15 to 4
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        height: 16,
                        width: 2,
                        decoration: BoxDecoration(
                          color: index * 25 <= (_brightness * 100) 
                              ? colorScheme.primary.withOpacity(0.8)
                              : colorScheme.onSurfaceVariant.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  );
                }),
                
                // Dragable area - full container for easy swipe anywhere
                Positioned.fill(
                  child: GestureDetector(
                    onHorizontalDragStart: (_) {
                      if (_enableHapticFeedback) {
                        HapticFeedback.selectionClick();
                      }
                      if (_isAmbientMode) {
                        setState(() {
                          _isAmbientMode = false;
                          _lightSensorService.stopListening();
                          _ambientBrightnessController?.stop();
                        });
                      }
                    },
                    onHorizontalDragUpdate: (details) {
                      final RenderBox box = context.findRenderObject() as RenderBox;
                      final localPos = box.globalToLocal(details.globalPosition);
                      final effectiveX = localPos.dx.clamp(0.0, trackWidth);
                      final newValue = effectiveX / trackWidth;
                      if (_enableHapticFeedback) {
                        HapticFeedback.selectionClick();
                      }
                      _adjustBrightness(newValue);
                    },
                    onTapDown: (details) {
                      final RenderBox box = context.findRenderObject() as RenderBox;
                      final localPos = box.globalToLocal(details.globalPosition);
                      final effectiveX = localPos.dx.clamp(0.0, trackWidth);
                      final newValue = effectiveX / trackWidth;
                      if (_enableHapticFeedback) {
                        HapticFeedback.mediumImpact();
                      }
                      _adjustBrightness(newValue);
                    },
                    behavior: HitTestBehavior.opaque,
                  ),
                ),
                
                // Handle with drag indicator - extended beyond the container
                Positioned(
                  left: handlePosition + 4 - 3, // Adjust handle position
                  top: 8,
                  bottom: 8,
                  child: Container(
                    width: 6,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary,
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
           ] );
            
  
            },
          ),
        ),
    );
  }
  
  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
  }
}

// Custom thumb shape for the slider with brightness icon
class _CustomThumbShape extends SliderComponentShape {
  final double enabledThumbRadius;
  final Color color;
  final Color iconColor;

  const _CustomThumbShape({
    required this.enabledThumbRadius,
    required this.color,
    required this.iconColor,
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size.fromRadius(enabledThumbRadius);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Draw shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      center.translate(0, 2),
      enabledThumbRadius,
      shadowPaint,
    );

    // Draw thumb
    final fillPaint = Paint()..color = color;
    canvas.drawCircle(center, enabledThumbRadius, fillPaint);

    // Draw inner circle
    final innerCirclePaint = Paint()..color = iconColor;
    canvas.drawCircle(center, enabledThumbRadius * 0.6, innerCirclePaint);

    // Draw brightness indicator lines
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    
    final lineLength = enabledThumbRadius * 0.7;
    for (int i = 0; i < 8; i++) {
      final angle = i * (pi / 4);
      final start = Offset(
        center.dx + cos(angle) * (enabledThumbRadius * 0.3),
        center.dy + sin(angle) * (enabledThumbRadius * 0.3),
      );
      final end = Offset(
        center.dx + cos(angle) * lineLength,
        center.dy + sin(angle) * lineLength,
      );
      canvas.drawLine(start, end, linePaint);
    }
  }
}

// New circular ring painter for flashlight button
class FlashlightRingPainter extends CustomPainter {
  final Color color;
  final double progress;
  final int segments;
  final double gapSize;

  FlashlightRingPainter({
    required this.color,
    required this.progress,
    required this.segments,
    required this.gapSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final segmentAngle = (2 * pi - (gapSize * segments)) / segments;
    
    for (int i = 0; i < segments; i++) {
      final startAngle = i * (segmentAngle + gapSize);
      final sweepAngle = segmentAngle * progress;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FlashlightRingPainter oldDelegate) =>
      oldDelegate.progress != progress || 
      oldDelegate.color != color;
}

// New modern pattern painter with subtle visibility
class FuturisticPatternPainter extends CustomPainter {
  final Color color1;
  final Color color2;
  final Color accentColor;
  final double progress;
  final bool isLightMode;

  FuturisticPatternPainter({
    required this.color1,
    required this.color2,
    required this.accentColor,
    required this.progress,
    required this.isLightMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Hexagonal grid pattern
    _drawHexagonalGrid(canvas, size);
    
    // Moving particles
    _drawParticles(canvas, size);
    
    // Circuit-like lines
    _drawCircuitLines(canvas, size);
    
    // Pulsing nodes
    _drawPulsingNodes(canvas, size);
    
    // Animated waves
    _drawAnimatedWaves(canvas, size);
  }

  void _drawHexagonalGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color1.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final hexSize = 30.0;
    final rows = (size.height / (hexSize * 0.75)).ceil() + 2;
    final cols = (size.width / (hexSize * 1.5)).ceil() + 2;

    for (int row = -1; row < rows; row++) {
      for (int col = -1; col < cols; col++) {
        final offsetX = col * hexSize * 1.5;
        final offsetY = row * hexSize * 0.75 + (col % 2) * hexSize * 0.375;
        
        // Add subtle animation to hex positions
        final animatedX = offsetX + sin(progress * 2 * pi + row * 0.1) * 2;
        final animatedY = offsetY + cos(progress * 2 * pi + col * 0.1) * 2;
        
        _drawHexagon(canvas, Offset(animatedX, animatedY), hexSize * 0.8, paint);
      }
    }
  }

  void _drawHexagon(Canvas canvas, Offset center, double size, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3;
      final x = center.dx + size * cos(angle);
      final y = center.dy + size * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawParticles(Canvas canvas, Size size) {
    final particlePaint = Paint()
      ..style = PaintingStyle.fill;

    // Generate animated particles
    for (int i = 0; i < 20; i++) {
      final baseX = (size.width / 20) * i;
      final baseY = (size.height / 10) * (i % 10);
      
      // Particle movement
      final animatedX = baseX + sin(progress * 2 * pi + i * 0.5) * 50;
      final animatedY = baseY + cos(progress * 1.5 * pi + i * 0.3) * 30;
      
      // Particle opacity based on position and time
      final opacity = (sin(progress * 3 * pi + i * 0.8) + 1) * 0.5 * 0.15;
      
      particlePaint.color = (i % 3 == 0 ? color1 : i % 3 == 1 ? color2 : accentColor)
          .withOpacity(opacity);
      
      final particleSize = 1.5 + sin(progress * 4 * pi + i) * 0.5;
      canvas.drawCircle(Offset(animatedX, animatedY), particleSize, particlePaint);
    }
  }

  void _drawCircuitLines(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    // Horizontal circuit lines
    for (int i = 0; i < 8; i++) {
      final y = (size.height / 8) * i;
      final animatedProgress = (progress + i * 0.2) % 1.0;
      
      linePaint.color = color2.withOpacity(0.06);
      
      final path = Path();
      path.moveTo(0, y);
      
      for (double x = 0; x <= size.width; x += 40) {
        final offsetY = y + sin((x / 40 + animatedProgress * 5) * pi) * 5;
        path.lineTo(x, offsetY);
      }
      
      canvas.drawPath(path, linePaint);
      
      // Add glowing effect at certain positions
      if (animatedProgress > 0.7) {
        final glowX = (animatedProgress - 0.7) * size.width / 0.3;
        final glowPaint = Paint()
          ..color = accentColor.withOpacity(0.8)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
        
        canvas.drawCircle(Offset(glowX, y), 3, glowPaint);
      }
    }

    // Vertical circuit lines
    for (int i = 0; i < 6; i++) {
      final x = (size.width / 6) * i;
      final animatedProgress = (progress + i * 0.15) % 1.0;
      
      linePaint.color = color1.withOpacity(0.04);
      
      final path = Path();
      path.moveTo(x, 0);
      
      for (double y = 0; y <= size.height; y += 50) {
        final offsetX = x + cos((y / 50 + animatedProgress * 4) * pi) * 8;
        path.lineTo(offsetX, y);
      }
      
      canvas.drawPath(path, linePaint);
    }
  }

  void _drawPulsingNodes(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..style = PaintingStyle.fill;

    // Strategic node positions
    final nodePositions = [
      Offset(size.width * 0.2, size.height * 0.3),
      Offset(size.width * 0.8, size.height * 0.2),
      Offset(size.width * 0.1, size.height * 0.7),
      Offset(size.width * 0.9, size.height * 0.8),
      Offset(size.width * 0.5, size.height * 0.15),
      Offset(size.width * 0.7, size.height * 0.6),
    ];

    for (int i = 0; i < nodePositions.length; i++) {
      final position = nodePositions[i];
      final pulsePhase = (progress * 2 + i * 0.3) % 1.0;
      final pulseSize = 2 + sin(pulsePhase * 2 * pi) * 1.5;
      final pulseOpacity = (cos(pulsePhase * 2 * pi) + 1) * 0.5 * 0.1;
      
      // Outer glow
      nodePaint.color = accentColor.withOpacity(pulseOpacity);
      canvas.drawCircle(position, pulseSize * 3, nodePaint);
      
      // Inner core
      nodePaint.color = color1.withOpacity(pulseOpacity * 2);
      canvas.drawCircle(position, pulseSize, nodePaint);
    }
  }

  void _drawAnimatedWaves(Canvas canvas, Size size) {
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Multiple wave layers
    for (int layer = 0; layer < 3; layer++) {
      final waveHeight = 15.0 - layer * 5;
      final waveFrequency = 0.02 + layer * 0.01;
      final waveSpeed = 1.0 + layer * 0.5;
      
      wavePaint.color = (layer == 0 ? color1 : layer == 1 ? color2 : accentColor)
          .withOpacity(0.05 - layer * 0.01);
      
      final path = Path();
      path.moveTo(0, size.height * 0.5);
      
      for (double x = 0; x <= size.width; x += 2) {
        final y = size.height * 0.5 + 
                 sin((x * waveFrequency) + (progress * waveSpeed * 2 * pi)) * waveHeight +
                 sin((x * waveFrequency * 2) + (progress * waveSpeed * 3 * pi)) * (waveHeight * 0.5);
        
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      
      canvas.drawPath(path, wavePaint);
    }
  }

  @override
  bool shouldRepaint(FuturisticPatternPainter oldDelegate) => 
      oldDelegate.progress != progress;
}

// Keep the existing ModernPatternPainter as backup or remove it
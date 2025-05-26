import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'morse_service.dart';

class TorchService {
  static final TorchService _instance = TorchService._internal();
  static const platform = MethodChannel('com.example.dimly/torch');
  bool _isOn = false;
  bool _isMorseActive = false;
  bool _isIntervalActive = false;
  Completer<void>? _sosCompleter;

  factory TorchService() {
    return _instance;
  }

  TorchService._internal();

  bool get isOn => _isOn;
  bool get isMorseActive => _isMorseActive;
  bool get isIntervalActive => _isIntervalActive;

  Future<void> initialize() async {
    try {
      await platform.invokeMethod('setTorch', {'intensity': 0.0});
      _isOn = false;
    } catch (e) {
      debugPrint('Torch initialization error: $e');
      rethrow;
    }
  }

  Function(bool)? onTorchStateChange;

  Future<void> toggleTorch({double? intensity}) async {
    try {
      final double targetIntensity = intensity?.clamp(0.0, 1.0) ?? (_isOn ? 0.0 : 1.0);
      final int brightnessLevel = (targetIntensity * 100).round().clamp(0, 100);
      
      await platform.invokeMethod('setTorch', {"intensity": targetIntensity});
      _isOn = targetIntensity > 0;
      onTorchStateChange?.call(_isOn);
    } catch (e) {
      debugPrint('Torch toggle error: $e');
      rethrow;
    }
  }

  Future<void> toggleInterval(Duration duration) async {
    _isIntervalActive = !_isIntervalActive;
    while (_isIntervalActive) {
      await toggleTorch(intensity: 1.0);
      HapticFeedback.mediumImpact();
      await Future.delayed(duration);
      await toggleTorch(intensity: 0.0);
      HapticFeedback.lightImpact();
      await Future.delayed(duration);
    }
  }

  Future<void> flashSOS() async {
    _isMorseActive = true;
    _sosCompleter?.complete();
    _sosCompleter = Completer<void>();

    while (_isMorseActive) {
      try {
        // S (...)
        for (int i = 0; i < 3 && _isMorseActive; i++) {
          await toggleTorch(intensity: 1.0);
          await _delayWithHaptics(const Duration(milliseconds: 200), true);
          await toggleTorch(intensity: 0.0);
          await _delayWithHaptics(const Duration(milliseconds: 200), false);
        }
        await _delayWithCancel(const Duration(milliseconds: 400));

        // O (---)
        for (int i = 0; i < 3 && _isMorseActive; i++) {
          await toggleTorch(intensity: 1.0);
          await _delayWithCancel(const Duration(milliseconds: 600));
          await toggleTorch(intensity: 0.0);
          await _delayWithCancel(const Duration(milliseconds: 200));
        }
        await _delayWithCancel(const Duration(milliseconds: 400));

        // S (...)
        for (int i = 0; i < 3 && _isMorseActive; i++) {
          await toggleTorch(intensity: 1.0);
          await _delayWithHaptics(const Duration(milliseconds: 200), true);
          await toggleTorch(intensity: 0.0);
          await _delayWithHaptics(const Duration(milliseconds: 200), false);
        }
        await _delayWithCancel(const Duration(seconds: 1));
      } catch (e) {
        if (e is CancellationException) break;
        rethrow;
      }
    }
    await toggleTorch(intensity: 0.0); // Ensure torch is off when stopped
  }

  static const int defaultRepeatCount = 3;
  Function(String)? onMorsePatternUpdate;
  Function(String)? onCurrentLetterUpdate;

  Future<void> playMorseCode(String text, {double wpm = 15.0}) async {
    if (text.isEmpty) return;
    
    final letters = text.toUpperCase().split('');
    _isMorseActive = true;

    while (_isMorseActive) {
      try {
        for (int letterIndex = 0; letterIndex < letters.length && _isMorseActive; letterIndex++) {
          // Gap before letter
          await Future.delayed(const Duration(seconds: 2));

          final letter = letters[letterIndex];
          final morseChar = MorseService.getLetterCode(letter);
          onCurrentLetterUpdate?.call(letter);
          onMorsePatternUpdate?.call(morseChar);

          // Flash the letter
          for (int i = 0; i < morseChar.length && _isMorseActive; i++) {
            final char = morseChar[i];
            switch (char) {
              case '.':
                await toggleTorch(intensity: 1.0);
                onTorchStateChange?.call(true);
                await _delayWithHaptics(MorseService.getDotDuration(wpm), true);
                await toggleTorch(intensity: 0.0);
                onTorchStateChange?.call(false);
                await _delayWithHaptics(MorseService.getDotDuration(wpm), false);
                break;
              case '-':
                await toggleTorch(intensity: 1.0);
                onTorchStateChange?.call(true);
                await _delayWithHaptics(MorseService.getDashDuration(wpm), true);
                await toggleTorch(intensity: 0.0);
                onTorchStateChange?.call(false);
                await _delayWithHaptics(MorseService.getDotDuration(wpm), false);
                break;
            }
          }

          // Gap after letter
          if (_isMorseActive) {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      } catch (e) {
        if (e is CancellationException) break;
        rethrow;
      }
    }

    onCurrentLetterUpdate?.call('');
    _isMorseActive = false;
    await toggleTorch(intensity: 0.0);
  }

  Future<void> _delayWithCancel(Duration duration) async {
    if (!_isMorseActive) throw CancellationException();
    try {
      await Future.delayed(duration);
    } catch (e) {
      if (!_isMorseActive) throw CancellationException();
      rethrow;
    }
  }

  Future<void> _delayWithHaptics(Duration duration, bool isOn) async {
    if (!_isMorseActive) throw CancellationException();
    if (isOn) HapticFeedback.mediumImpact();
    try {
      await Future.delayed(duration);
    } catch (e) {
      if (!_isMorseActive) throw CancellationException();
      rethrow;
    }
  }

  void stopMorse() {
    _isMorseActive = false;
    _sosCompleter?.complete();
    _sosCompleter = null;
    toggleTorch(intensity: 0.0); // Immediately turn off torch
  }

  void stopInterval() {
    _isIntervalActive = false;
  }
}

class CancellationException implements Exception {}

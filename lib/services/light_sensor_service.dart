import 'dart:async';
import 'package:light_sensor/light_sensor.dart'; // Changed import

class LightSensorService {
  StreamSubscription<int>? _subscription;
  void Function(int luxValue)? onLightData;
  void Function(Object error)? onError;

  LightSensorService() {
    // Initialization is not typically needed here for light_sensor,
    // as errors are handled when starting the stream.
  }

  Future<void> startListening() async {
    // Ensure any previous subscription is cancelled before starting a new one.
    await _subscription?.cancel();
    _subscription = null;

    try {
      // Subscribe to the light sensor stream
      _subscription = LightSensor().lightSensorStream.listen(
        (luxValue) {
          print('Light sensor reading: $luxValue lux'); // Debug log
          onLightData?.call(luxValue);
        },
        onError: (error, stackTrace) {
          print("Light sensor stream error: $error\n$stackTrace");
          onError?.call(error);
        },
        cancelOnError: true, // Automatically cancels the subscription on error.
      );

      // Start with a brief delay then provide initial reading for faster adjustment
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_subscription != null) {
          // Trigger initial adjustment - assume indoor lighting that would result in 25% brightness
          // This will be quickly replaced by real sensor data
          onLightData?.call(60); // Medium indoor light level (around 50-75 lux range)
        }
      });

    } catch (e, stackTrace) { // Catch synchronous errors from starting the stream
      print("Error starting light sensor listener: $e\n$stackTrace");
      onError?.call("Error starting light sensor: $e");
    }
  }

  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopListening();
  }
}

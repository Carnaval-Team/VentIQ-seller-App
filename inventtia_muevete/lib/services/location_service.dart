import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  /// Checks the current location permission status.
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Requests location permission from the user.
  Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Returns the current device position as a LatLng.
  Future<LatLng> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    return LatLng(position.latitude, position.longitude);
  }

  /// Returns a stream of position updates as LatLng for real-time tracking.
  Stream<LatLng> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // minimum distance (meters) before update
      ),
    ).map((position) => LatLng(position.latitude, position.longitude));
  }

  /// Calculates the distance between two LatLng points in kilometers
  /// using the latlong2 Distance class (Haversine formula).
  double calculateDistance(LatLng from, LatLng to) {
    const distance = Distance();
    // distance.as returns meters by default with LengthUnit.Meter
    final meters = distance.as(LengthUnit.Meter, from, to);
    return meters / 1000.0;
  }

  /// Checks whether the device location service is enabled.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }
}

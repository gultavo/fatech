import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationFailure implements Exception {
  const LocationFailure(this.message, {this.permanentlyDenied = false});

  final String message;
  final bool permanentlyDenied;

  @override
  String toString() => message;
}

class LocationService {
  Future<Position> capture() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'A localização do aparelho está desligada. Ative-a e tente novamente.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure('Permissão de localização negada.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Permissão de localização bloqueada. Abra as configurações do aplicativo.',
        permanentlyDenied: true,
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } on TimeoutException {
      throw const LocationFailure(
        'Não foi possível obter uma posição atual em 20 segundos.',
      );
    }
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

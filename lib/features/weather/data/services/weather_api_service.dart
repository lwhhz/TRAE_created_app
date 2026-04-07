import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:callduck_weather/features/weather/domain/models/weather.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherApiService {
  static const String defaultApiKey = '';
  static const String defaultBaseUrl = 'https://restapi.amap.com/v3/weather/weatherInfo';
  static const String defaultCityCode = '110000';

  Future<String> _getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('weatherApiKey') ?? defaultApiKey;
  }

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('weatherApiUrl') ?? defaultBaseUrl;
  }

  Future<Weather> getCurrentWeather(String cityCode) async {
    final apiKey = await _getApiKey();
    final baseUrl = await _getBaseUrl();
    final url = '$baseUrl?key=$apiKey&city=$cityCode&extensions=base';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('请求失败，状态码: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    
    if (data['status'] != '1' || data['lives'] == null || data['lives'].isEmpty) {
      throw Exception('高德API返回错误: ${data['info']}');
    }

    final live = data['lives'][0];
    return Weather(
      temperature: double.tryParse(live['temperature'] ?? '20') ?? 20.0,
      condition: live['weather'] ?? '晴',
      humidity: int.tryParse(live['humidity'] ?? '50') ?? 50,
      windSpeed: _parseWindPower(live['windpower']),
      windDirection: _parseWindDirection(live['winddirection']),
      pressure: 1013,
      precipitation: 0.0,
      icon: _getIconFromCondition(live['weather']),
      cityName: live['city'] ?? '北京',
      provinceName: live['province'] ?? '北京市',
      reportTime: _parseReportTime(live['reporttime']),
      timestamp: DateTime.now(),
    );
  }

  Future<List<HourlyForecast>> getHourlyForecast(String cityCode) async {
    final apiKey = await _getApiKey();
    final baseUrl = await _getBaseUrl();
    final url = '$baseUrl?key=$apiKey&city=$cityCode&extensions=all';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      return _getMockHourlyForecast();
    }

    final data = json.decode(response.body);
    final List<HourlyForecast> forecasts = [];

    if (data['status'] == '1' && data['forecasts'] != null && data['forecasts'].isNotEmpty) {
      final forecast = data['forecasts'][0];
      if (forecast['casts'] != null) {
        final now = DateTime.now();
        int hourIndex = 0;
        
        for (final cast in forecast['casts']) {
          forecasts.add(HourlyForecast(
            time: now.add(Duration(hours: hourIndex * 3)),
            temperature: double.tryParse(cast['daytemp'] ?? '20') ?? 20.0,
            condition: cast['dayweather'] ?? '晴',
            icon: _getIconFromCondition(cast['dayweather']),
            precipitation: 0.0,
          ));
          hourIndex++;
          
          if (forecasts.length >= 8) break;
          
          forecasts.add(HourlyForecast(
            time: now.add(Duration(hours: hourIndex * 3)),
            temperature: double.tryParse(cast['nighttemp'] ?? '15') ?? 15.0,
            condition: cast['nightweather'] ?? '晴',
            icon: _getIconFromCondition(cast['nightweather']),
            precipitation: 0.0,
          ));
          hourIndex++;
          
          if (forecasts.length >= 8) break;
        }
      }
    }

    return forecasts.isEmpty ? _getMockHourlyForecast() : forecasts;
  }

  Future<List<DailyForecast>> getDailyForecast(String cityCode) async {
    final apiKey = await _getApiKey();
    final baseUrl = await _getBaseUrl();
    final url = '$baseUrl?key=$apiKey&city=$cityCode&extensions=all';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      return _getMockDailyForecast();
    }

    final data = json.decode(response.body);
    final List<DailyForecast> forecasts = [];

    if (data['status'] == '1' && data['forecasts'] != null && data['forecasts'].isNotEmpty) {
      final forecast = data['forecasts'][0];
      if (forecast['casts'] != null) {
        for (final cast in forecast['casts']) {
          forecasts.add(DailyForecast(
            date: DateTime.parse(cast['date']),
            maxTemperature: double.tryParse(cast['daytemp'] ?? '25') ?? 25.0,
            minTemperature: double.tryParse(cast['nighttemp'] ?? '15') ?? 15.0,
            condition: cast['dayweather'] ?? '晴',
            icon: _getIconFromCondition(cast['dayweather']),
            precipitation: 0.0,
          ));
        }
      }
    }

    return forecasts.isEmpty ? _getMockDailyForecast() : forecasts;
  }

  double _parseWindPower(String? windPower) {
    if (windPower == null) return 0.0;
    
    // 解析类似 "≤3" 或 "4-5" 的风力等级
    if (windPower.startsWith('≤')) {
      return double.tryParse(windPower.substring(1)) ?? 0.0;
    }
    
    if (windPower.contains('-')) {
      final parts = windPower.split('-');
      final min = double.tryParse(parts[0]) ?? 0.0;
      final max = double.tryParse(parts[1]) ?? 0.0;
      return (min + max) / 2;
    }
    
    return double.tryParse(windPower) ?? 0.0;
  }

  String _parseWindDirection(String? windDirection) {
    if (windDirection == null || windDirection.isEmpty) return '无持续风向';
    
    final directionMap = {
      '0': '无持续风向',
      '1': '东北风',
      '2': '东风',
      '3': '东南风',
      '4': '南风',
      '5': '西南风',
      '6': '西风',
      '7': '西北风',
      '8': '北风',
    };
    
    return directionMap[windDirection] ?? windDirection;
  }

  DateTime _parseReportTime(String? reportTime) {
    if (reportTime == null) return DateTime.now();
    
    try {
      return DateTime.parse(reportTime);
    } catch (e) {
      return DateTime.now();
    }
  }

  String _getIconFromCondition(String? condition) {
    if (condition == null) return 'sunny';
    
    if (condition.contains('晴')) return 'sunny';
    if (condition.contains('多云')) return 'cloudy';
    if (condition.contains('阴')) return 'overcast';
    if (condition.contains('雨')) return 'rain';
    if (condition.contains('雪')) return 'snow';
    if (condition.contains('雾') || condition.contains('霾')) return 'fog';
    if (condition.contains('雷')) return 'thunder';
    
    return 'sunny';
  }

  List<HourlyForecast> _getMockHourlyForecast() {
    final now = DateTime.now();
    return List.generate(8, (index) {
      return HourlyForecast(
        time: now.add(Duration(hours: index * 3)),
        temperature: 20.0 + (index % 3) * 2,
        condition: '晴',
        icon: 'sunny',
        precipitation: 0.0,
      );
    });
  }

  List<DailyForecast> _getMockDailyForecast() {
    final now = DateTime.now();
    return List.generate(7, (index) {
      return DailyForecast(
        date: now.add(Duration(days: index)),
        maxTemperature: 25.0 - (index % 3),
        minTemperature: 15.0 + (index % 2),
        condition: '晴',
        icon: 'sunny',
        precipitation: 0.0,
      );
    });
  }
}

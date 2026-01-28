import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const String _key = 'favorite_bench_ids';

  Future<Set<int>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    return list.map((e) => int.tryParse(e)).whereType<int>().toSet();
  }

  Future<void> setFavorites(Set<int> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, favorites.map((e) => e.toString()).toList());
  }

  Future<bool> isFavorite(int id) async {
    final favs = await getFavorites();
    return favs.contains(id);
  }

  Future<bool> toggleFavorite(int id) async {
    final favs = await getFavorites();
    final nowFav = !favs.contains(id);
    if (nowFav) {
      favs.add(id);
    } else {
      favs.remove(id);
    }
    await setFavorites(favs);
    return nowFav;
  }

  Future<void> clearFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

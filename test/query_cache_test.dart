import 'package:flutter_test/flutter_test.dart' hide Tags;
import 'package:garde/state/query_cache.dart';

void main() {
  group('QueryCache', () {
    test('charge une fois et dédoublonne les appels simultanés', () async {
      final cache = QueryCache();
      var calls = 0;
      final e = cache.entry<int>('k', () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 42;
      });
      e.addListener(() {});
      await Future.wait([e.fetch(), e.fetch(), e.fetch()]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // 1 chargement + au plus 1 rechargement demandé pendant le premier : jamais 3.
      expect(calls, lessThanOrEqualTo(2));
      expect(e.state.data, 42);
      expect(e.state.isLoading, isFalse);
    });

    test('garde les données pendant un rechargement et après une erreur', () async {
      final cache = QueryCache();
      var fail = false;
      final e = cache.entry<String>('k', () async {
        if (fail) throw StateError('boom');
        return 'ok';
      });
      await e.fetch();
      expect(e.state.data, 'ok');

      fail = true;
      await e.fetch();
      expect(e.state.data, 'ok'); // l'écran ne se vide pas
      expect(e.state.hasError, isTrue);
      expect(e.state.isFailure, isFalse); // il y a des données : pas d'écran d'erreur

      fail = false;
      await e.fetch();
      expect(e.state.hasError, isFalse);
    });

    test('erreur sans données = échec affichable', () async {
      final cache = QueryCache();
      final e = cache.entry<int>('k', () async => throw StateError('x'));
      await e.fetch();
      expect(e.state.isFailure, isTrue);
    });

    test('invalidate recharge seulement les entrées étiquetées et affichées', () async {
      final cache = QueryCache();
      var a = 0;
      var b = 0;
      final ea = cache.entry<int>('a', () async => ++a, tags: {Tags.vehicles('c1')});
      final eb = cache.entry<int>('b', () async => ++b, tags: {Tags.vehicles('c2')});
      ea.addListener(() {}); // « affichée »
      eb.addListener(() {});
      await ea.fetch();
      await eb.fetch();
      expect([a, b], [1, 1]);

      cache.invalidate([Tags.vehicles('c1')]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(a, 2);
      expect(b, 1);
      expect(ea.state.data, 2);
    });

    test('une entrée non affichée est rechargée à la prochaine ouverture', () async {
      final cache = QueryCache();
      var n = 0;
      final e = cache.entry<int>('k', () async => ++n, tags: {'t'});
      await e.fetch();
      cache.invalidate(['t']); // personne n'écoute : pas de chargement inutile
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(n, 1);
      e.ensureFresh();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(n, 2);
    });

    test('une donnée trop vieille est rechargée', () async {
      var now = DateTime(2026, 1, 1, 12);
      final cache = QueryCache(staleAfter: const Duration(seconds: 30), clock: () => now);
      var n = 0;
      final e = cache.entry<int>('k', () async => ++n);
      await e.fetch();
      e.ensureFresh();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(n, 1); // encore fraîche

      now = now.add(const Duration(seconds: 31));
      e.ensureFresh();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(n, 2);
    });

    test('invalidation pendant un chargement : une seconde lecture suit', () async {
      final cache = QueryCache();
      var n = 0;
      final e = cache.entry<int>('k', () async {
        final v = ++n;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return v;
      }, tags: {'t'});
      e.addListener(() {});
      final first = e.fetch();
      cache.invalidate(['t']);
      await first;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(n, 2);
      expect(e.state.data, 2); // la donnée la plus récente l'emporte
    });

    test('éviction : jamais une entrée affichée', () {
      final cache = QueryCache(maxEntries: 2);
      final shown = cache.entry<int>('shown', () async => 1)..addListener(() {});
      cache.entry<int>('b', () async => 2);
      cache.entry<int>('c', () async => 3);
      cache.entry<int>('d', () async => 4);
      expect(cache.length, lessThanOrEqualTo(3));
      expect(identical(cache.entry<int>('shown', () async => 1), shown), isTrue);
    });

    test('listenTag prévient puis cesse après désinscription', () {
      final cache = QueryCache();
      var hits = 0;
      final stop = cache.listenTag('x', () => hits++);
      cache.invalidate(['x']);
      cache.invalidate(['y']);
      expect(hits, 1);
      stop();
      cache.invalidate(['x']);
      expect(hits, 1);
    });

    test('clear vide tout', () {
      final cache = QueryCache();
      cache.entry<int>('a', () async => 1);
      cache.clear();
      expect(cache.length, 0);
    });
  });
}

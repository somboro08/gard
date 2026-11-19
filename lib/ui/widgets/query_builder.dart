import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/icons.dart';
import '../../state/app_controller.dart';
import '../../state/query_cache.dart';
import 'empty_state.dart';

/// Affiche le résultat d'une requête en cache et se met à jour tout seul
/// quand une étiquette de [tags] est invalidée (modification locale ou synchro).
class QueryBuilder<T> extends StatefulWidget {
  const QueryBuilder({
    super.key,
    required this.queryKey,
    required this.fetch,
    required this.builder,
    this.tags = const {},
  });

  final String queryKey;
  final Future<T> Function() fetch;
  final Set<String> tags;
  final Widget Function(BuildContext context, Loadable<T> state) builder;

  @override
  State<QueryBuilder<T>> createState() => _QueryBuilderState<T>();
}

class _QueryBuilderState<T> extends State<QueryBuilder<T>> {
  QueryEntry<T>? _entry;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind();
  }

  @override
  void didUpdateWidget(QueryBuilder<T> old) {
    super.didUpdateWidget(old);
    _bind();
  }

  void _bind() {
    final cache = AppScope.read(context).cache;
    final next = cache.entry<T>(widget.queryKey, widget.fetch, tags: widget.tags);
    if (!identical(next, _entry)) {
      _entry?.removeListener(_onChange);
      _entry = next..addListener(_onChange);
    }
    // Jamais de chargement pendant la construction : après la frame.
    if (!_scheduled) {
      _scheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (mounted) _entry?.ensureFresh();
      });
    }
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _entry?.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    return widget.builder(context, e == null ? Loadable<T>(isLoading: true) : e.state);
  }
}

/// Écran d'erreur standard quand rien ne peut être affiché.
class QueryError extends StatelessWidget {
  const QueryError({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: AppIcons.warning,
      title: 'Chargement impossible',
      message: message ?? 'Une erreur est survenue en lisant les données de cet appareil.',
      actionLabel: 'Réessayer',
      onAction: onRetry,
    );
  }
}


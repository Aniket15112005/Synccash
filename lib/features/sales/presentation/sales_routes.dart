import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// GPU-friendly horizontal slide used by every push inside the sales feature.
Route<T> salesRoute<T>(Widget page) =>
    CupertinoPageRoute<T>(builder: (_) => page);

/// Runs [action] after the current route's push animation completes so
/// Firestore snapshots don't fight the transition on the UI thread.
void deferUntilRouteSettled(BuildContext context, VoidCallback action) {
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.status == AnimationStatus.completed) {
      action();
      return;
    }
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        anim.removeStatusListener(onStatus);
        if (context.mounted) action();
      }
    }
    anim.addStatusListener(onStatus);
  });
}

/// Delays [setState] while a child route is sliding over this screen.
void setStateAfterTransition(State state, VoidCallback fn) {
  if (!state.mounted) return;
  final sec = ModalRoute.of(state.context)?.secondaryAnimation;
  if (sec != null && sec.isAnimating) {
    void listener(AnimationStatus status) {
      if (!sec.isAnimating) {
        sec.removeStatusListener(listener);
        if (state.mounted) state.setState(fn);
      }
    }
    sec.addStatusListener(listener);
    return;
  }
  state.setState(fn);
}

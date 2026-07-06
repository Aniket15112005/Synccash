// lib/features/purchases/presentation/purchase_routes.dart
//
// Mirrors lib/features/sales/presentation/sales_routes.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';

/// GPU-friendly horizontal slide used by every push inside the purchases
/// feature — identical transition to salesRoute() so navigation feels
/// consistent across both features.
Route<T> purchaseRoute<T>(Widget page) =>
    CupertinoPageRoute<T>(builder: (_) => page);

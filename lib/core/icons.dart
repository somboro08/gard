import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Toutes les icônes de l'app passent par ici.
/// Si une icône Iconsax est renommée dans une future version du paquet,
/// il suffit de corriger la ligne correspondante.
abstract final class AppIcons {
  // Navigation
  static const IconData navFind = Iconsax.search_normal_1;
  static const IconData navRegister = Iconsax.add_square;

  // Actions
  static const IconData scan = Iconsax.scan_barcode;
  static const IconData keyboard = Iconsax.keyboard;
  static const IconData camera = Iconsax.camera;
  static const IconData search = Iconsax.search_normal_1;
  static const IconData more = Iconsax.more;
  static const IconData add = Iconsax.add;
  static const IconData edit = Iconsax.edit;
  static const IconData trash = Iconsax.trash;
  static const IconData copy = Iconsax.copy;
  static const IconData send = Iconsax.send_2;
  static const IconData settings = Iconsax.setting_2;

  // Flèches
  static const IconData back = Iconsax.arrow_left;
  static const IconData close = Iconsax.close_circle;
  static const IconData chevronDown = Iconsax.arrow_down_1;
  static const IconData chevronLeft = Iconsax.arrow_left_2;
  static const IconData chevronRight = Iconsax.arrow_right_3;

  // Contenu
  static const IconData building = Iconsax.building_4;
  static const IconData location = Iconsax.location;
  static const IconData user = Iconsax.user;
  static const IconData phone = Iconsax.call;
  static const IconData note = Iconsax.document_text;
  static const IconData clock = Iconsax.clock;
  static const IconData calendar = Iconsax.calendar;
  static const IconData ticket = Iconsax.ticket;
  static const IconData wallet = Iconsax.wallet_2;
  static const IconData car = Iconsax.car;
  static const IconData emptyBox = Iconsax.box_search;
  static const IconData shield = Iconsax.shield_tick;

  // États
  static const IconData check = Iconsax.tick_circle;
  static const IconData warning = Iconsax.warning_2;
  static const IconData info = Iconsax.info_circle;

  // Lampe / thème
  static const IconData flashOn = Iconsax.flash_1;
  static const IconData flashOff = Iconsax.flash_slash;
  static const IconData sun = Iconsax.sun_1;
  static const IconData moon = Iconsax.moon;
}

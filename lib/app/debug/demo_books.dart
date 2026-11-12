// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Affluent Labs LLC

import 'package:material_ui/material_ui.dart';

/// Made-up books for the developer screens and tests. The covers are the
/// generated images in assets/demo/covers (see tool/gen_demo_covers.sh).
class DemoBook {
  const DemoBook({
    required this.id,
    required this.title,
    required this.author,
    required this.narrator,
    required this.coverAsset,
    this.series,
  });

  final String id;
  final String title;
  final String author;
  final String narrator;
  final String coverAsset;
  final String? series;

  ImageProvider get cover => AssetImage(coverAsset);
}

const demoBooks = <DemoBook>[
  DemoBook(
    id: 'demo-clockmakers-tide',
    title: 'The Clockmaker\'s Tide',
    author: 'Mara Ellison',
    narrator: 'Jonah Pryce',
    coverAsset: 'assets/demo/covers/clockmakers_tide.jpg',
  ),
  DemoBook(
    id: 'demo-salt-and-starlight',
    title: 'Salt and Starlight',
    author: 'Mara Ellison',
    narrator: 'Priya Castellan',
    coverAsset: 'assets/demo/covers/salt_and_starlight.jpg',
  ),
  DemoBook(
    id: 'demo-ember-road',
    title: 'Ember Road',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    series: 'Book 1 of The Example Saga',
    coverAsset: 'assets/demo/covers/ember_road.jpg',
  ),
  DemoBook(
    id: 'demo-ash-harbor',
    title: 'Ash Harbor',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    series: 'Book 2 of The Example Saga',
    coverAsset: 'assets/demo/covers/ash_harbor.jpg',
  ),
  DemoBook(
    id: 'demo-quiet-places',
    title: 'A Field Guide to Quiet Places',
    author: 'Ines Okafor',
    narrator: 'Ines Okafor',
    coverAsset: 'assets/demo/covers/quiet_places.jpg',
  ),
  DemoBook(
    id: 'demo-lanterns',
    title: 'Lanterns Under the Ice',
    author: 'Rafael Dorn',
    narrator: 'Priya Castellan',
    coverAsset: 'assets/demo/covers/lanterns_under_the_ice.jpg',
  ),
  DemoBook(
    id: 'demo-long-way',
    title: 'The Long Way to Morning',
    author: 'Rafael Dorn',
    narrator: 'Jonah Pryce',
    coverAsset: 'assets/demo/covers/long_way_to_morning.jpg',
  ),
  DemoBook(
    id: 'demo-kindling-sky',
    title: 'Kindling Sky',
    author: 'Theo Vance',
    narrator: 'Jonah Pryce',
    series: 'Book 10 of The Example Saga',
    coverAsset: 'assets/demo/covers/kindling_sky.jpg',
  ),
];

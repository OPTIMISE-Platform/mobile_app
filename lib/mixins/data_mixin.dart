/*
 * Copyright 2026 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import 'package:flutter/foundation.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/characteristics.dart';
import 'package:mobile_app/services/concepts.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/joined_load.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

mixin DataMixin on ChangeNotifier {

  final Map<String, Aspect> aspects = {};
  final _aspectsLoad = JoinedLoad();

  final Map<String, Concept> concepts = {};
  final _conceptsLoad = JoinedLoad();

  final Map<String, Characteristic> characteristics = {};
  final _characteristicsLoad = JoinedLoad();

  final Map<String, PlatformFunction> platformFunctions = {};
  final _platformFunctionsLoad = JoinedLoad();

  Future<bool> loadAspects(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale,
          bool quiet = false}) =>
      _aspectsLoad.run(() => _loadAspects(maxAge, serveStale, quiet));

  Future<bool> _loadAspects(Duration maxAge,
      void Function(DateTime storedAt)? serveStale, bool quiet) async {
    final epoch = AccountEpoch.current;
    try {
      // Swap after the fetch: clearing first would leave the map visibly
      // empty for the whole request, clearing at all is what drops entries
      // deleted on the backend.
      final fetched = await AspectsService.getAspects(
          maxAge: maxAge, serveStale: serveStale);
      // A fetch that outlived its account leaves the next one's map alone.
      if (epoch != AccountEpoch.current) return false;
      aspects.clear();
      for (final e in fetched) {
        aspects[e.id] = e;
      }
    } catch (e, s) {
      _reportLoadFailure('Could not load aspects', e, s, quiet, epoch);
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadConcepts(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale,
          bool quiet = false}) =>
      _conceptsLoad.run(() => _loadConcepts(maxAge, serveStale, quiet));

  Future<bool> _loadConcepts(Duration maxAge,
      void Function(DateTime storedAt)? serveStale, bool quiet) async {
    final epoch = AccountEpoch.current;
    try {
      final fetched = await ConceptsService.getConcepts(
          maxAge: maxAge, serveStale: serveStale);
      if (epoch != AccountEpoch.current) return false;
      concepts.clear();
      for (final e in fetched) {
        concepts[e.id] = e;
      }
    } catch (e, s) {
      _reportLoadFailure('Could not get concepts', e, s, quiet, epoch);
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadCharacteristics(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale,
          bool quiet = false}) =>
      _characteristicsLoad.run(() => _loadCharacteristics(maxAge, serveStale, quiet));

  Future<bool> _loadCharacteristics(Duration maxAge,
      void Function(DateTime storedAt)? serveStale, bool quiet) async {
    final epoch = AccountEpoch.current;
    try {
      final fetched = await CharacteristicsService.getCharacteristics(
          maxAge: maxAge, serveStale: serveStale);
      if (epoch != AccountEpoch.current) return false;
      characteristics.clear();
      for (final e in fetched) {
        characteristics[e.id] = e;
      }
    } catch (e, s) {
      _reportLoadFailure('Could not get characteristics', e, s, quiet, epoch);
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadNestedFunctions(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale,
          bool quiet = false}) =>
      _platformFunctionsLoad.run(() => _loadNestedFunctions(maxAge, serveStale, quiet));

  Future<bool> _loadNestedFunctions(Duration maxAge,
      void Function(DateTime storedAt)? serveStale, bool quiet) async {
    final epoch = AccountEpoch.current;
    try {
      final fetched = await FunctionsService.getFunctions(
          maxAge: maxAge, serveStale: serveStale);
      if (epoch != AccountEpoch.current) return false;
      platformFunctions.clear();
      for (final e in fetched) {
        platformFunctions[e.id] = e;
      }
    } catch (e, s) {
      _reportLoadFailure('Could not get nested functions', e, s, quiet, epoch);
      return false;
    }
    notifyListeners();
    return true;
  }

  /// [quiet] loads run in the background over data already on screen, so
  /// their failure is logged only, as is that of a load that outlived the
  /// account of [epoch].
  void _reportLoadFailure(
      String message, Object e, StackTrace s, bool quiet, int epoch) {
    if (quiet || epoch != AccountEpoch.current) {
      ErrorReporter.log(message, e, s);
    } else {
      ErrorReporter.report(message, e, s);
    }
  }

  void clearData() {
    aspects.clear();
    concepts.clear();
    characteristics.clear();
    platformFunctions.clear();
  }
}
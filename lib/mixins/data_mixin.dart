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
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/joined_load.dart';

mixin DataMixin on ChangeNotifier {

  final Map<String, Aspect> aspects = {};
  final _aspectsLoad = JoinedLoad();

  final Map<String, Concept> concepts = {};
  final _conceptsLoad = JoinedLoad();

  final Map<String, Characteristic> characteristics = {};
  final _characteristicsLoad = JoinedLoad();

  final Map<String, PlatformFunction> platformFunctions = {};
  final _platformFunctionsLoad = JoinedLoad();

  Future<bool> loadAspects() => _aspectsLoad.run(_loadAspects);

  Future<bool> _loadAspects() async {
    try {
      // Swap after the fetch: clearing first would leave the map visibly
      // empty for the whole request, clearing at all is what drops entries
      // deleted on the backend.
      final fetched = await AspectsService.getAspects();
      aspects.clear();
      for (final e in fetched) {
        aspects[e.id] = e;
      }
    } catch (e, s) {
      ErrorReporter.report('Could not load aspects', e, s);
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadConcepts() => _conceptsLoad.run(_loadConcepts);

  Future<bool> _loadConcepts() async {
    try {
      final fetched = await ConceptsService.getConcepts();
      concepts.clear();
      for (final e in fetched) {
        concepts[e.id] = e;
      }
    } catch (e, s) {
      ErrorReporter.report('Could not get concepts', e, s);
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadCharacteristics() => _characteristicsLoad.run(_loadCharacteristics);

  Future<bool> _loadCharacteristics() async {
    try {
      final fetched = await CharacteristicsService.getCharacteristics();
      characteristics.clear();
      for (final e in fetched) {
        characteristics[e.id] = e;
      }
    } catch (e, s) {
      ErrorReporter.report('Could not get characteristics', e, s);
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadNestedFunctions() => _platformFunctionsLoad.run(_loadNestedFunctions);

  Future<bool> _loadNestedFunctions() async {
    try {
      final fetched = await FunctionsService.getFunctions();
      platformFunctions.clear();
      for (final e in fetched) {
        platformFunctions[e.id] = e;
      }
    } catch (e, s) {
      ErrorReporter.report('Could not get nested functions', e, s);
      return false;
    }
    notifyListeners();
    return true;
  }

  void clearData() {
    aspects.clear();
    concepts.clear();
    characteristics.clear();
    platformFunctions.clear();
  }
}
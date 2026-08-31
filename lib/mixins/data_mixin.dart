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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/characteristics.dart';
import 'package:mobile_app/services/concepts.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mutex/mutex.dart';

mixin DataMixin on ChangeNotifier {
  static final _logger = Logger(printer: SimplePrinter());

  final Map<String, Aspect> aspects = {};
  final _aspectsMutex = Mutex();

  final Map<String, Concept> concepts = {};
  final _conceptsMutex = Mutex();

  final Map<String, Characteristic> characteristics = {};
  final _characteristicsMutex = Mutex();

  final Map<String, PlatformFunction> platformFunctions = {};
  final _platformFunctionsMutex = Mutex();

  Future<bool> loadAspects() async {
    final locked = _aspectsMutex.isLocked;
    await _aspectsMutex.acquire();
    if (locked) {
      // Deduplicated onto the load that was already running; releasing here is
      // what lets that dedup happen more than once per process.
      _aspectsMutex.release();
      return true;
    }
    try {
      // Swap after the fetch: clearing first would leave the map visibly
      // empty for the whole request, clearing at all is what drops entries
      // deleted on the backend.
      final fetched = await AspectsService.getAspects();
      aspects.clear();
      for (final e in fetched) {
        aspects[e.id] = e;
      }
    } catch (e) {
      final err = 'Could not load aspects: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      return false;
    } finally {
      _aspectsMutex.release();
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadConcepts() async {
    final locked = _conceptsMutex.isLocked;
    await _conceptsMutex.acquire();
    if (locked) {
      _conceptsMutex.release();
      return true;
    }
    try {
      final fetched = await ConceptsService.getConcepts();
      concepts.clear();
      for (final e in fetched) {
        concepts[e.id] = e;
      }
    } catch (e) {
      final err = 'Could not get concepts: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      return false;
    } finally {
      _conceptsMutex.release();
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadCharacteristics() async {
    final locked = _characteristicsMutex.isLocked;
    await _characteristicsMutex.acquire();
    if (locked) {
      _characteristicsMutex.release();
      return true;
    }
    try {
      final fetched = await CharacteristicsService.getCharacteristics();
      characteristics.clear();
      for (final e in fetched) {
        characteristics[e.id] = e;
      }
    } catch (e) {
      final err = 'Could not get characteristics: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      return false;
    } finally {
      _characteristicsMutex.release();
    }
    notifyListeners();
    return true;
  }

  Future<bool> loadNestedFunctions() async {
    final locked = _platformFunctionsMutex.isLocked;
    await _platformFunctionsMutex.acquire();
    if (locked) {
      _platformFunctionsMutex.release();
      return true;
    }
    try {
      final fetched = await FunctionsService.getFunctions();
      platformFunctions.clear();
      for (final e in fetched) {
        platformFunctions[e.id] = e;
      }
    } catch (e) {
      final err = 'Could not get nested functions: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      return false;
    } finally {
      _platformFunctionsMutex.release();
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
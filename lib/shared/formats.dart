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

import 'package:intl/intl.dart';

/// Date/time formats shared across widgets, kept out of [MyTheme] because
/// they have nothing to do with colour or brightness.
class Formats {
  static final ss = DateFormat.s();
  static final mm = DateFormat.m();
  static final mmss = DateFormat.ms();
  static final hh = DateFormat.H();
  static final hhmm = DateFormat.Hm();
  static final e = DateFormat.E();
  static final ehh = DateFormat.E().add_H();
  static final ehhmm = DateFormat.E().add_Hm();
  static final mmm = DateFormat.MMM();
  static final ddmm = DateFormat('dd.MM');
  static final y = DateFormat.y();
  static final eddmmy = DateFormat('E, dd.MM.y');
}

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

/// How a reading shows that its value just changed; a setting of the app.
enum ValueChangeStyle {
  /// A tinted background behind the value that fades out.
  flash,

  /// An arrow next to the value shows the direction and fades out.
  arrow,

  /// The new value slides in from below when it rose, from above when it fell.
  slide;

  /// The style stored under [name], [flash] for none or an unknown one.
  static ValueChangeStyle parse(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => flash);
}

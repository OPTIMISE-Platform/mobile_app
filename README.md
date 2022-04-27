# OPTIMISE mobile app

## Android
The android app can be downloaded from the [releases](https://github.com/OPTIMISE-Platform/mobile_app/releases) page.

## Other platforms
In development

## Project Init
- add key.properties to /android
- add sepl.keystore to /android
- add .env to /
- add the following script to /.git/hooks as 'pre-commit'

```
#!/bin/bash

perl -i -pe 's/^(version:\s+\d+\.\d+\.)(\d+)(\+)(\d+)$/$1.($2+1).$3.($4+1)/e' pubspec.yaml
git add pubspec.yaml
```
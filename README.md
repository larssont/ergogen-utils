# Ergogen Utils

A collection of utilities to enhance your experience with [Ergogen](https://github.com/ergogen/ergogen), the ergonomic keyboard layout generator.

## Features

- [PowerShell build script](build.ps1) (view usage via Get-Help .\build.ps1)
  - Invokes either a global Ergogen installation or a node-based developmet cli.
  - Supports --clean to purge previous outputs and --debug for debug mode.
  - Runs parallel JSCAD→STL conversions using @jscad/cli.

## Installation

This repo can be cloned directly, but for best results, place it under `utils/larssont` in your Ergogen project since some scripts assume this structure. It's not mandatory and can be overridden with command-line arguments.

To add this repo as a submodule under `utils/larssont` in your Ergogen project:

```bash
git submodule add https://github.com/larssont/ergogen-utils.git utils/larssont
```

## License

Distributed under the MIT License. See [LICENSE.md](LICENSE.md) for more information.

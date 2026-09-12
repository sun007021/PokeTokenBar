# Third-Party Notices

This project is a fork of [PokeTokenBar](https://github.com/chattymin/PokeTokenBar) that
integrates the account-switching engine from [Mobius](https://github.com/chussum/mobius).
Both upstream projects and this fork's own modifications are released under the MIT
License (see [`LICENSE`](LICENSE)). This file reproduces the original copyright notices
that MIT requires to be preserved.

## PokeTokenBar

- **Project**: PokeTokenBar
- **Source**: https://github.com/chattymin/PokeTokenBar
- **Copyright**: Copyright (c) 2026 chattymin
- **License**: MIT

```
MIT License

Copyright (c) 2026 chattymin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Mobius

- **Project**: Mobius
- **Source**: https://github.com/chussum/mobius
- **Copyright**: Copyright (c) 2026 Mobius Contributors
- **License**: MIT

`Sources/MobiusCore/` and `Tests/MobiusCoreTests/` in this repository are vendored,
near-verbatim copies of Mobius's account-switching engine (see
[`docs/reference/mobius-integration.md`](docs/reference/mobius-integration.md) for the
one intentional modification point).

```
MIT License

Copyright (c) 2026 Mobius Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Mobius itself bundles one further third-party dependency, `swift-argument-parser`
(Apache License 2.0), used by its standalone `mobius` CLI target. **This fork does not
carry that dependency** — only `Sources/MobiusCore/` (the engine) was ported, not the CLI
target, and `Package.swift` in this repository declares no external SwiftPM dependencies.

## This fork's modifications

- **Copyright**: Copyright (c) 2026 Sunwook Lee
- **License**: MIT (see [`LICENSE`](LICENSE))

Everything outside `Sources/MobiusCore/` and `Tests/MobiusCoreTests/` that isn't part of
the original PokeTokenBar source (the Mobius integration glue in
`Sources/PokeTokenBarExtended/Mobius/`, UI additions, build/packaging changes, and this notices
file) is this fork's own original work.

---

No other third-party source code is vendored into this repository. Pokémon species data
and sprites are fetched at runtime from [PokéAPI](https://pokeapi.co) and cached locally;
they are not bundled and are not covered by this project's MIT license — see the
[License & disclaimer](README.md#license--disclaimer) section of the README.

# Credits

The `tidy:changes` skill is written fresh. It takes ideas, and in places close phrasing, from these sources:

- **[ce-simplify-code](https://github.com/EveryInc/compound-engineering-plugin/tree/main/skills/ce-simplify-code)** in EveryInc/compound-engineering-plugin (MIT): resolving scope from a named target or the branch against its base; the list of behaviour to keep and safety checks never to remove; report-first with numbered findings that the user picks and that are re-checked before applying; separate defects from simplifications; verification by blast radius.
- **[code-simplification](https://github.com/addyosmani/agent-skills/tree/main/skills/code-simplification)** in addyosmani/agent-skills (MIT): understand why code exists before removing it (Chesterton's fence); one change at a time with tests after each; existing tests must pass unmodified.
- **Claude Code's built-in `/simplify`** (Anthropic): the idea of looking at a diff from separate angles such as reuse, simplification, efficiency and depth of the fix. Its text is not used.

The MIT licences of the first two sources follow.

## EveryInc/compound-engineering-plugin

```
MIT License

Copyright (c) 2025 Every

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

## addyosmani/agent-skills

```
MIT License

Copyright (c) 2025 Addy Osmani

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

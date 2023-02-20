# execute

This TeX package enables you to *execute* any token also within *expansion-only* contexts, e.g in `\edef{...}` or `\write{...}`.

**You do not need a special version of TeX.**
But you must compile your document with **LuaTeX**.

*Execution* means *consuming* some tokens, evaluate them and *change the state* of TeX (most important parts of TeX's state). For example
- `\def\todef{replacement text}` directs TeX to insert or redefine a macro in TeX's table of macros.
- `\advance\mycount42` directs TeX to add 42 to the integer register behind `\mycount`.
- Normal plain text (*characters*) is read, and the corresponding *glyphs* are appended to the PDF file to output.

After executing a token more tokens are read.

Whenever *execution* takes place (most often) also *expansion* takes place.

*Expansion* is (normally) restricted to processes which *replace some tokens by others tokens*.
- replacing a defined macro with its replacement text while may consuming arguments.
  E.g. `\todef` is replaced by `replacement text`.
- expand the then-branch or else-branch of a conditional (e.g. `\ifx`)
- execute expandable built-in control sequences (e.g. `\number\mycount`)
- some tokens expand to nothing (e.g. the macro `\empty`)

**Issues are welcome!**

## Usage

This package provides the command sequence `\execute`, which scans a braced tokens (maybe with a `<filler>` in before).
*The outer braces are mandatory!*
Also if you have only one token to execute, you must surround it with braces.

### Caution!

**Because this control sequence complicates TeX even more, you must know what you do!**
You should only use this control sequence if you are sure, that you have really no better solution for your problem.

This package was created with the following in mind:
Sometimes you have a macro from other people, that calls your code in an expansion-only context.
But your code requires doing something very special and the only solution to your problem you can imagine off,
requires executing something (especially defining a macro or setting a catcode.)
But the package with the troubling macro does not provide another callback interface to execute this special solution in before.
Or the special solution requires an argument which is only given in the called back code you provide to the troubling macro.
This all while patching (meaning altering the code) of the troubling macro or patching the API of the package of the troubling macro raises concerns.
(e.g. What if the troubling macro is rewritten and the patch fails.)

Please study the following in depth before considering using this package in the following order
1. your problem
2. all solutions for your problem you can imagine off
3. the public API of the package of the troubling macro
4. the private interfaces of the package of the troubling macro
5. other private macros of the package of the troubling macro
6. *the code of the troubling macro*

### Loading
```
\input execute.tex
```

### `\edef` example
```
// \mycount is 21.
\edef\mytext{%
    There are %
    \execute{%
        \multiply\mycount2\relax%
    }%
    \number\mycount%
    \space numbers.%
}
// \mycount is 42.
// The replacement text of \mytext is "There are 42 numbers." .
```

### `\write` example
```
\def\takeWithCare#1{%
    \execute{%
        \def\@tempa{#1}%
        % do something with \@tempa and change its replacement text
    }%
    // The replacment text of \@tempa is "<care>#1</care>" .
    \@tempa% expand to something special.
}%
...
\write\@auxout{%
    Some \takeWithCare{things} must be taken with \takeWithCare{care}.%
}
// writes the following to the .aux file:
// "Some <care>things</care> must be taken with <care>care</care>."
```

## How Does it Work

The heart of this package are the Lua functions `execute(...)` and `execute_token(cur_tok)`.

The arguments to `execute(...)` should be *token filters*.
These are functions, which are provided with a TeX token (the Lua representation of it).
They then decide to call `execute_token(cur_tok)` with this token or not.
If no token filter does so, then the unexecuted token will be saved to be prepended to the input stack again,
before `execute(...)` exits.

`execute_token(cur_tok)` runs `tex.runtoks()` resp. its C implementation `runtoks(lua_State*)`.
This prepends two *internal* tokens to the input stack:
- A token with the command code `lua_local_call_cmd` and a "character code" which refers to a nested, anonymous Lua function.
  Because `lua_local_call_cmd` is greater than `max_command_cmd`, this token is considered **expandable** in TeX's implementation conventions.
  *Expanding* this token means calling `local_control()`.
  Because this token is expandable the `jump_table` has no entry for it.
- A token with the command code `extension_cmd` and the "character code" `end_local_code`.
  Because `extension_cmd` is less than `max_command_cmd`, this token is unexpandable.
  But thus the jump_table can be consulted to execute this token.
  For this token `end_local_control()` is executed.
The `lua_local_call_cmd` token is read before the `end_local_code` token.

Then `runtoks(lua_State*)` calls `local_control()`.
This C function is LuaTeX specific and mimics TeX's `main_control()`.

Both functions can be described by the following pseudo code:
```
function main_control/local_control() {
    <set up>
    repeat {
        current_token = get_x_token()
        // get_x_token() guarantees, that current_token is unexpandable.
        func_to_execute = jump_table[current_token]
        func_to_execute()
    } until <exit condtion>
    <tear down>
}
```
For `local_control()` the exit condition is true, after `end_local_control()` was called (anywhere).
`end_local_control()` signals `local_control()` to exit via incrementing the global variable `local_level`.

`get_x_token()` can be described by the following pseudocode:
```
function get_x_token() {
    repeat forever {
        current_token = read_next_token()
        if current_token is expandable then {
            expand() // expands the current token
        } else {
            break loop
        }
    }
}
```

In both pseudocodes `current_token` is a shared, global variable.<br>
(By sides: `current_token` does not equal `cur_tok`.
In this README `cur_tok` is the argument to the Lua function `execute_token(cur_tok)`.)

Thus the `lua_local_call_cmd` token is read/consumed as the current_token and expanded by `get_x_token()`.
It is *expanded* by `expand()`, which means executing the nested, anonymous Lua function.

Because TeX uses numerous global variables and also LuaTeX only has one global Lua state,
the nested, anonymous Lua function can alter LuaTeX's state in an arbitrary manner. (Know what you do!)

First the nested, anonymous Lua function completely removes the `end_local_code` token.<br>
(No fear: `end_local_control()` will be called via an other way.)

Second it prepends `cur_tok` to the input stack.
This does not yet expand or execute `cur_tok`. 
It also does not yet set it as the current token.
 
Third it runs `tex.quittoks()` resp. its C implementation `quittoks(lua_State*)`.
The latter in turn calls `end_local_control()`.
Thus `local_control()` *will be* triggered to exit.

**Now comes the hack** any why it was necessary to completely remove the `end_local_code` token.

The nested, anonymous Lua function returns, `expand()` returns, and we are back at `get_x_token()`.
Its loop continues *a second time* and the previously prepended `cur_tok` is read as the current token.
If `cur_tok` is expandable, then the loop continues more times.
If `cur_tok` is unexpandable, then the loop terminates and `get_x_token()` returns to `local_control()`.

Now in `local_control()` the current token is `cur_tok` and in the `jump_table` the C function to execute for `cur_tok` is looked up.
This is the only time the `jump_table` is consulted in `local_control()`.
This C function will be *executed*.
Because `end_local_control()` was indirectly called by `tex.quittoks()`,
`local_control()` executes its loop body only once.

`local_control()` returns to `runtoks(lua_State*)` resp. `tex.runtoks()`,
which in turn returns to `execute_token(cur_tok)`, which in turn returns to `execute(...)`.
Before `execute(...)` exits, it reinserts/prepends the remaining tokens.

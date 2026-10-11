# `char`, `varchar`, and `text`: Trailing Spaces & Join Behavior

`char(n)` is **blank-padded** to a fixed length, which changes equality and join
semantics when compared against `varchar`/`text`. This note shows how trailing
spaces and cross-type comparisons affect results and the chosen plan.

## Setup

```sql
CREATE TABLE t1 (id int, c_char char(10), c_varchar varchar(10), c_text text);
INSERT INTO t1 VALUES (1, 'a',   'a',   'a');
INSERT INTO t1 VALUES (2, 'a  ', 'a  ', 'a  ');   -- trailing spaces
```

```text
 Column   |         Type          |
-----------+-----------------------+
 c_char    | character(10)         |
 c_varchar | character varying(10) |
 c_text    | text                  |
```

## `char = char`: trailing spaces are ignored → all 4 pairs match

Because `char(10)` blank-pads both `'a'` and `'a  '` to the same 10-char value,
rows 1 and 2 are considered equal — the self-join matches **all four**
combinations:

```text
mytest=> SELECT a.id aid, b.id bid FROM t1 a, t1 b WHERE a.c_char=b.c_char;
 aid | bid
-----+-----
   1 |   2
   1 |   1
   2 |   2
   2 |   1
(4 rows)
```

## `char = varchar`: still bpchar semantics → all 4 match

The planner casts the `varchar` side to `bpchar` (`b.c_varchar)::bpchar`), so
blank-padding rules still apply and all four pairs match:

```text
mytest=> EXPLAIN SELECT a.id aid, b.id bid FROM t1 a, t1 b WHERE a.c_char=b.c_varchar;
 Hash Join  ...
   Hash Cond: (a.c_char = (b.c_varchar)::bpchar)
```

## `char = text`: text semantics → trailing spaces matter → only 2 match

Comparing against `text` casts the `char` side to `text` (`(a.c_char)::text`),
which keeps the padding, so `'a         '` (padded) only equals the padded form —
only the matching-length rows pair up (2 rows), via a Merge Join:

```text
mytest=> SELECT a.id aid, b.id bid FROM t1 a, t1 b WHERE a.c_char=b.c_text;
 aid | bid
-----+-----
   1 |   1
   2 |   1
(2 rows)

mytest=> EXPLAIN SELECT ... WHERE a.c_char=b.c_text;
 Merge Join  ...
   Merge Cond: (((a.c_char)::text) = b.c_text)
```

## `varchar`/`text` comparisons: exact, trailing spaces are significant → 2 match

`varchar = varchar`, `varchar = text`, and `text = text` all use text equality,
so `'a'` ≠ `'a  '` and only the identical rows match:

```text
mytest=> SELECT ... WHERE a.c_varchar=b.c_varchar;   -- (1,1),(2,2)
   Hash Cond: ((a.c_varchar)::text = (b.c_varchar)::text)

mytest=> SELECT ... WHERE a.c_varchar=b.c_text;      -- (1,1),(2,2)
   Hash Cond: ((a.c_varchar)::text = b.c_text)

mytest=> SELECT ... WHERE a.c_text=b.c_text;         -- (1,1),(2,2)
   Hash Cond: (a.c_text = b.c_text)
```

## Takeaways

- `char(n)` is blank-padded; equality **ignores trailing spaces** when both sides are `char`/`bpchar`. This silently matches values you may consider different.
- Comparing `char` against `text` promotes to **text** semantics, so trailing spaces become significant and results change — plus you can lose index usability and get extra casts/sorts in the plan.
- Prefer `text` (or `varchar(n)` only when you truly need a length cap). Mixing `char` with `text`/`varchar` in joins introduces implicit casts (`::bpchar` / `::text`) that change both correctness and the chosen plan.

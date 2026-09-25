import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'supabase/migrations/prod_full_dump.sql'
s = open(path, encoding='utf-8').read()

# Re-run of the shell version corrupted the ALTER-TABLE ADD CONSTRAINT wrapper
# because $do$ was shell-interpolated. Fix that first if it happened.
s = s.replace('DO $ BEGIN', 'DO $ddo$ BEGIN')
s = s.replace('END $;', 'END $ddo$;')

# CREATE TABLE public.X (  -> CREATE TABLE IF NOT EXISTS public.X (
s = re.sub(r'^CREATE TABLE (public\.[A-Za-z_0-9]+) \(', r'CREATE TABLE IF NOT EXISTS \1 (', s, flags=re.M)

# CREATE INDEX / CREATE UNIQUE INDEX
s = re.sub(r'^CREATE INDEX ', 'CREATE INDEX IF NOT EXISTS ', s, flags=re.M)
s = re.sub(r'^CREATE UNIQUE INDEX ', 'CREATE UNIQUE INDEX IF NOT EXISTS ', s, flags=re.M)

# CREATE FUNCTION -> CREATE OR REPLACE FUNCTION
s = re.sub(r'^CREATE FUNCTION ', 'CREATE OR REPLACE FUNCTION ', s, flags=re.M)

# CREATE VIEW / MATERIALIZED VIEW
s = re.sub(r'^CREATE VIEW ', 'CREATE OR REPLACE VIEW ', s, flags=re.M)
s = re.sub(r'^CREATE MATERIALIZED VIEW ', 'CREATE MATERIALIZED VIEW IF NOT EXISTS ', s, flags=re.M)

# Match either `foo` or "quoted with spaces" for the object name.
NAME = r'(?:"[^"]+"|\S+)'

# Statement-aware scanner: find the terminating ';' that is outside quotes and
# outside parentheses. pg_dump policies contain quoted names with ';' and
# nested USING(...)/WITH CHECK(...) parens.
def find_stmt_end(text, i):
    depth = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == "'":
            j = text.find("'", i + 1)
            i = (j + 1) if j >= 0 else n
            continue
        if c == '"':
            j = text.find('"', i + 1)
            i = (j + 1) if j >= 0 else n
            continue
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        elif c == ';' and depth == 0:
            return i
        i += 1
    return n - 1

def prefix_drops(pattern, drop_fn):
    out = []
    last = 0
    text = s
    for m in re.finditer(pattern, text, flags=re.M):
        end = find_stmt_end(text, m.start()) + 1
        body = text[m.start():end]
        drop = drop_fn(body)
        out.append(text[last:m.start()])
        if drop:
            out.append(drop + '\n')
        out.append(body)
        last = end
    out.append(text[last:])
    return ''.join(out)

def trig_drop(body):
    name_m = re.match(rf'CREATE TRIGGER ({NAME})', body)
    if not name_m:
        return None
    on_match = re.search(rf' ON ({NAME})', body)
    if not on_match:
        return None
    return f'DROP TRIGGER IF EXISTS {name_m.group(1)} ON {on_match.group(1)};'

def pol_drop(body):
    hdr = re.match(rf'CREATE POLICY ({NAME}) ON ({NAME})', body)
    if not hdr:
        return None
    return f'DROP POLICY IF EXISTS {hdr.group(1)} ON {hdr.group(2)};'

s = prefix_drops(r'^CREATE TRIGGER ', trig_drop)
s = prefix_drops(r'^CREATE POLICY ', pol_drop)

# ALTER TABLE ... ADD CONSTRAINT ...; -> wrap in DO $ddo$ ... $ddo$
def add_constraint(m):
    return (
        'DO $ddo$ BEGIN\n'
        + m.group(0)
        + '\nEXCEPTION WHEN others THEN null; END $ddo$;'
    )
s = re.sub(
    r'^ALTER TABLE (?:ONLY )?[^\n]+\n\s+ADD CONSTRAINT [^;]+;',
    add_constraint,
    s,
    flags=re.M,
)

open(path, 'w', encoding='utf-8').write(s)
print(f'wrote {path}')

/^CREATE TYPE public\.[a-z_]+ AS ENUM \(/ {
  print "DO $$ BEGIN"
  in_type = 1
  print
  next
}
in_type {
  print
  if ($0 ~ /^\);/) {
    print "EXCEPTION WHEN duplicate_object THEN null; END $$;"
    in_type = 0
  }
  next
}
{ print }

# the GSettings schemas changed (GTK 3, its programs): rebuild gschemas.compiled, which GTK 3 reads
# (the file chooser aborts without it)
path=usr/share/glib-2.0/schemas/*
run=/usr/bin/glib-compile-schemas $ROOT/usr/share/glib-2.0/schemas

# fonts or their configuration changed: rebuild the system font cache
path=usr/share/fonts/*
path=usr/share/fonts/*/*
path=usr/share/fonts/*/*/*
path=etc/fonts/conf.d/*
run=/usr/bin/fc-cache -s -y $ROOT

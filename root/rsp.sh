/data/local/tmp/resetprop ro.debuggable 1
/data/local/tmp/resetprop ro.secure 0
/data/local/tmp/resetprop service.adb.root 1
stop adbd
start adbd

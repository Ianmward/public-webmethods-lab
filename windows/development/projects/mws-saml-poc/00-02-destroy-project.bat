@echo off

echo THIS WILL REMOVE ALL VOLUMES FOR THE CURRENT PROJECT! ARE YOU SURE? CTRL-C if not.
pause

echo Shutdown BPMS Node
call .\02-bpmsNodeType1-02-down.bat

echo Shutdown Adminer Node
call .\S01-adminer-02-down.bat

echo Shutdown Database
call .\01-mysql-02-down.bat

echo Remove BPMS Node
call .\02-02-mws-03-destroy.bat

echo Remove Database
call .\01-mysql-03-destroy.bat

del *.yml

pause


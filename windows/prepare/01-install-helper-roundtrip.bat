@echo off

cd ..\build\os\centos-wm-install-helper

SET SAG_W_ENTRY_POINT=echo DONE

call .\01-up.bat

call .\03-destroy.bat
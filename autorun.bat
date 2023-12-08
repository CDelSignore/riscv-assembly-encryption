@echo on
IF EXIST data/encrypted.txt DEL /F data/encrypted.txt
IF EXIST data/decrypted.txt DEL /F data/decrypted.txt
java -jar bin/rars1_6.jar src/project-one.s